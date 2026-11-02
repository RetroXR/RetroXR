## SystemPorts — what is plugged into a machine's controller ports and USB
## sockets, and what its core is told about each of them.
##
## A child of the RetroSystem it serves, made in _init like the other components:
## a bare RetroSystem.new() in a suite never enters the tree, and its ports still
## have to bind. Lifted out of system.gd whole: the port tables are this node's
## own, and what it needs of the machine -- the model, the Libretro node, the core
## options, the Wii pairing -- it asks for through the machine's public surface.
##
## The machine keeps one-line forwarders for the calls peripherals and the mods
## make on it BY NAME (attach_expanded_controller, port_holder, core_device_id,
## reapply_pak, ...). Its own code and the suites hold this node instead:
## RetroSystem.controller_ports().
class_name SystemPorts
extends Node

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null

## The cabinet's controller-port snap zones, in socket order (system.tscn's
## ControllerPort1-4), handed over by wire_zones(). Empty on a machine that never
## entered the tree.
var zones: Array = []

## The core's declared devices, per port, as Libretro.GetControllerInfo() gives
## them: [{port, controllers: [{name, id}], current_id}]. Filled at options_ready;
## empty while the machine is off, when nothing is known about the core. Written
## in place by set_device, so the options panel shows the live selection.
var controller_info: Array = []

## The peripheral currently on each port (same index as the libretro port the
## core sees), null where empty. Populated by the snap/release handlers so rumble
## can be routed back to the physical holder without a node tree scan on every
## core callback.
##
## Eight, not four: a multitap fans one port out to four, and the Super NES's
## second port then reaches libretro port 4 (player 5), which a four-slot table
## never stored.
var controllers: Array = [null, null, null, null, null, null, null, null]

## The ControllerPlug seated in each cabinet socket. Kept alongside the controller
## because the two are not interchangeable on the way out: has_dropped names
## nothing, and the release path needs the PLUG (its device_type, its collision
## exception, its on_unplugged) rather than the controller behind it.
var plugs: Array = [null, null, null, null]

## The console's USB-A sockets (Connectors.USB_PORTS), what is seated in each and
## the peripheral at its far end. Built in code by build_usb(): system.tscn has
## none.
var usb_zones: Array = []
var usb_plugs: Array = []
var usb_controllers: Array = []

## Whether the ports have been announced again after the core's first frame
## (ensure_devices_bound). Cleared at every core start.
var devices_settled := false

## Ports whose DEVICE an adapter decides, whatever pad feeds them: libretro port ->
## the adapter (own_port_device). A Four Score at 4P is "Gamepad" on ports 2 and
## 3 whether or not its sockets 3 and 4 hold a pad: fceumm reads players 3 and 4
## only off a port announced as its Gamepad (the plain joypad id is its "Auto",
## which reads them for the games in its own list and no others), and the game
## finds the adapter there with the sockets empty, as on the hardware. At 2P it is
## nothing. The owner answers port_device(machine, lib_port) -> {type, names}, and
## the pads in its sockets bind with announce false: they feed the port, the
## owner says what it is.
var port_owners: Dictionary = {}

## What changes a port's input on its way to the core: libretro port -> the node
## whose filter_port_input(port, pad) -> pad it is (set_input_filter). A Four
## Score's TURBO switches, which mask A and B on every pad it carries.
var input_filters: Dictionary = {}

## The sockets a plug seated beside another one is filling as well (socket_span):
## cabinet index -> whether that zone was enabled before, so letting go puts back
## what build_zones said. The Four Score's lead ends in ONE moulded block carrying
## two NES plugs at the console's pitch, so seating it fills both ports.
var _spanned: Dictionary = {}

## The console's accessory connector (Connectors.ACCESSORY_PORTS: the Famicom's
## 15-pin expansion port on its front), what is seated in it, and the libretro
## port its device is announced on. Built in code by build_accessory_port().
var accessory_zone: XRToolsSnapZone = null
var accessory_plug: Node3D = null
var accessory_lib_port := -1

## Ports a core would otherwise fill on a GUESS, told they are empty at every core
## start unless something in the room is on them. A port the room never announces
## stays at the core's own default, which for the NES cores is "Auto": fceumm then
## plugs in a Four Score by itself for every game in its fourscore list, and a
## Famicom 4-player adapter on port 4 for its famicom_4p list (Mesen does the same
## from its database). Measured with Bomberman II (USA): with no Four Score in the
## room its BATTLE MODE showed three players, where the real console without one --
## and the Four Score switched to 2 -- will not open BATTLE MODE at all.
const UNWIRED_PORTS := {
	"nes": [2, 3],
	"famicom": [2, 3, 4],
}

## Words a core uses for a light gun in its own device list, for the cores that
## give one a base type other than RETRO_DEVICE_LIGHTGUN.
const _LIGHTGUN_WORDS: Array = [
	"zapper", "lightgun", "light gun", "gun", "scope", "justifier", "phaser", "menacer",
]


func setup(host: RetroSystem) -> void:
	_host = host


## Take the cabinet's socket zones and wire them: what seats and leaves each,
## and which plugs it takes. Called once from RetroSystem._ready.
func wire_zones(port_zones: Array) -> void:
	zones = port_zones
	for i in zones.size():
		var idx := i
		var zone := zones[i] as XRToolsSnapZone
		zone.has_picked_up.connect(func(obj: Node3D) -> void: on_port_snapped(idx, obj))
		# has_dropped carries NO argument — it says the zone is empty, not what
		# left, and it fires after the zone has already forgotten. Taking one here
		# made every unplug abort with "expected 1 argument, called with 0", so a
		# controller pulled out of a port never released it: the libretro device
		# stayed set and the slot stayed occupied. `plugs` is what remembers.
		zone.has_dropped.connect(func() -> void: on_port_released(idx))
		# A SNES pad does not fit a PlayStation. Same gate the cartridge slot
		# uses for media, applied to the connector -- and to the sockets beside
		# this one for a plug that fills more than one (accepts_plug_at).
		zone.snap_filter = accepts_plug_at.bind(idx)


## Show the controller ports this console really had.
##
## The SystemInfo descriptor wins over the model's default when it has an
## opinion, clamped to the snap zones the cabinet actually carries. A
## multitap extends players past this on its own, and a handheld exposes
## none at all -- it IS its own controller, driven by HandheldInput.
func build_zones() -> void:
	var model := _host.get_model()
	var port_count := 0
	if not model.is_handheld():
		port_count = model.get_controller_port_count()
		var info := SystemInfo.for_system(_host.systemid)
		if info and info.native_ports > 0 and not model.port_count_is_fixed():
			port_count = info.native_ports
		port_count = clampi(port_count, 1, zones.size())
	print("[RetroSystem] %s: %d controller port(s) shown" % [_host.systemid, port_count])
	for i in range(zones.size()):
		var active := i < port_count
		zones[i].visible = active
		# A socket a two-plug block is filling stays shut until the block leaves,
		# and then takes what this says now.
		if _spanned.has(i):
			_spanned[i] = active
			continue
		zones[i].enabled = active


## The USB-A sockets, for a console that has them: on the box's front face below
## the free controller ports, until the model puts them on its own shell.
func build_usb() -> void:
	var model := _host.get_model()
	if not usb_zones.is_empty() or model.is_handheld():
		return
	var count := model.get_usb_port_count()
	if count < 0:
		count = int(Connectors.USB_PORTS.get(_host.systemid, 0))
	if count <= 0:
		return
	var recess_mesh := BoxMesh.new()
	recess_mesh.size = Vector3(0.0135, 0.0055, 0.006)
	var recess_mat := StandardMaterial3D.new()
	recess_mat.albedo_color = Color(0.05, 0.05, 0.05)
	for k in count:
		var zone := RetroSystem.SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
		zone.name = "UsbPort%d" % (k + 1)
		zone.snap_require = "controller_plug"
		zone.snap_filter = accepts_usb_plug
		zone.grab_distance = 0.03
		_host.add_child(zone)
		zone.position = Vector3(0.05 + 0.03 * k, -0.025, 0.125)
		var recess := MeshInstance3D.new()
		recess.name = "UsbRecess"
		recess.mesh = recess_mesh
		recess.set_surface_override_material(0, recess_mat)
		zone.add_child(recess)
		zone.has_picked_up.connect(on_usb_snapped.bind(k))
		zone.has_dropped.connect(on_usb_released.bind(k))
		usb_zones.append(zone)
		usb_plugs.append(null)
		usb_controllers.append(null)
	print("[RetroSystem] %s: %d USB socket(s) built" % [_host.systemid, count])
	model.configure_usb_ports(usb_zones)


## The accessory connector, for a console that has one (Connectors.ACCESSORY_PORTS):
## the Famicom's 15-pin expansion port, where the 4 Players Adaptor (and in time a
## Zapper, an Arkanoid paddle, a keyboard) plugs in. On the box's front face until
## the model puts it on its own shell (configure_accessory_port). What is seated
## is announced on the connector's libretro port (fceumm and Mesen read the
## Famicom expansion port as their fifth) by its own device type and names, as a
## USB device is.
func build_accessory_port() -> void:
	var model := _host.get_model()
	if accessory_zone != null or model == null or model.is_handheld():
		return
	var spec: Dictionary = Connectors.ACCESSORY_PORTS.get(_host.systemid, {})
	if spec.is_empty():
		return
	accessory_lib_port = int(spec.get("port", -1))
	var zone := RetroSystem.SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	zone.name = "AccessoryPort"
	zone.snap_require = "controller_plug"
	zone.snap_filter = accepts_accessory_plug
	zone.grab_distance = 0.03
	_host.add_child(zone)
	zone.position = Vector3(0.0, -0.025, 0.125)
	zone.has_picked_up.connect(on_accessory_snapped)
	zone.has_dropped.connect(on_accessory_released)
	accessory_zone = zone
	print("[RetroSystem] %s: accessory connector '%s' built, its device on libretro port %d"
		% [_host.systemid, spec.get("connector", ""), accessory_lib_port])
	model.configure_accessory_port(zone)


# --- Gates ---

## Port gate: is this plug what the ports take? One that says nothing (the game's
## generic props) fits every port; see Connectors.of.
func accepts_plug(obj: Node3D) -> bool:
	var plug := Connectors.of(obj)
	return plug.is_empty() or plug == _host.controller_connector()


## Port gate for socket `i`: the plug fits (accepts_plug), and a plug that fills
## more than one socket finds every socket beside this one there, open and empty.
## The Four Score's block has its plugs at the console's own pitch, port 1's on
## the left, so it goes in at port 1 and nowhere else on an NES.
func accepts_plug_at(obj: Node3D, i: int) -> bool:
	if not accepts_plug(obj):
		return false
	for k in range(1, socket_span_of(obj)):
		if not _open_for_span(i + k):
			return false
	return true


## Whether socket `j` is there, open and empty for a block's second plug.
func _open_for_span(j: int) -> bool:
	if j >= zones.size():
		return false
	var zone := zones[j] as XRToolsSnapZone
	return zone.enabled and not is_instance_valid(zone.picked_up_object) \
		and not (j < plugs.size() and is_instance_valid(plugs[j]))


## How many side-by-side sockets `plug` fills: its socket_span, else one.
static func socket_span_of(plug: Object) -> int:
	if plug != null and "socket_span" in plug:
		return maxi(1, int(plug.get("socket_span")))
	return 1


## Accessory gate: the plug is this console's accessory connector.
func accepts_accessory_plug(obj: Node3D) -> bool:
	var spec: Dictionary = Connectors.ACCESSORY_PORTS.get(_host.systemid, {})
	return not spec.is_empty() and Connectors.of(obj) == str(spec.get("connector", ""))


## USB gate: a USB-A plug, and nothing else.
func accepts_usb_plug(obj: Node3D) -> bool:
	return Connectors.of(obj) == Connectors.USB_A


# --- What the core is told ---

## Switch the input device type on a given controller port.
## device_id corresponds to RETRO_DEVICE_* constants (1 = joypad, 5 = analog, etc.).
func set_device(port: int, device_id: int) -> void:
	print("[RetroSystem] set_controller_port_device port=%d device=%d" % [port, device_id])
	# Update the cached current_id so reopening the panel shows the right selection
	for entry in controller_info:
		if entry["port"] == port:
			entry["current_id"] = device_id
			break
	# Guard: a controller can be plugged in before the machine is built (a bare
	# RetroSystem.new() in a suite has no Libretro child). The device selection
	# is re-applied at core start, so skipping here is safe.
	var lib := _host.get_libretro_node()
	if is_instance_valid(lib):
		lib.SetControllerPortDevice(port, device_id)


## Tell the core which device is on each occupied port, now that there is a core
## to tell. set_device is a no-op while the machine is off, and everything that
## claims a port — a plug seating, a remote pairing, a save being restored — can
## happen long before that.
##
## A plain joypad survived the gap by luck: libretro already defaults its ports to
## JOYPAD, so a pad plugged in beforehand worked anyway. A Wii Remote does not.
## The core zeroes every port during its own startup, so the remote was paired as
## far as this room was concerned, showing its player light, and simply absent in
## the game — no buttons, no pointer.
func reannounce_all() -> void:
	for i in range(controllers.size()):
		announce_cabinet_port(i)
	# Last, so a USB device wins its port over the pad there.
	for k in usb_plugs.size():
		if usb_plug_at(k) != null:
			announce_port(k)
	if accessory_plug_at(accessory_lib_port) != null:
		announce_port(accessory_lib_port)
	_announce_unwired()


## Tell the core the ports UNWIRED_PORTS lists are empty, those that are: no pad,
## no adapter deciding them, nothing in a USB socket or the accessory connector.
func _announce_unwired() -> void:
	var said: Array = []
	for p: int in UNWIRED_PORTS.get(_host.systemid, []):
		if port_owner(p) != null or usb_plug_at(p) != null or accessory_plug_at(p) != null:
			continue
		if p < controllers.size() and is_instance_valid(controllers[p]):
			continue
		set_device(p, RetroSystem.RETRO_DEVICE_NONE)
		said.append(p)
	if not said.is_empty():
		print("[RetroSystem] %s: ports %s have nothing on them, said so (no core guess)" % [_host.systemid, str(said)])


## Tell the core what is on cabinet port `i` again, now: a multitap's SELECT
## switch thrown with it plugged in changes what the port is.
func reannounce_port(i: int) -> void:
	if i >= 0 and i < controllers.size():
		announce_cabinet_port(i)


## Let `owner` decide what libretro port `lib_port` is to the core (see
## port_owners), and tell the core now.
func own_port_device(lib_port: int, owner: Node) -> void:
	if lib_port < 0 or lib_port >= controllers.size() or not is_instance_valid(owner):
		print("[RetroSystem] port %d device claim refused: %s" % [lib_port,
			"no owner" if not is_instance_valid(owner) else "no such port"])
		return
	var held := port_owner(lib_port)
	if held != null and held != owner:
		print("[RetroSystem] port %d: %s takes its device over from %s" % [lib_port, owner.name, held.name])
	port_owners[lib_port] = owner
	announce_port(lib_port)


## Give port `lib_port`'s device back, if `owner` is the one deciding it, and tell
## the core what the port is without it: the pad there as itself, else nothing.
func disown_port_device(lib_port: int, owner: Node) -> void:
	if not port_owners.has(lib_port) or port_owners[lib_port] != owner:
		return
	port_owners.erase(lib_port)
	print("[RetroSystem] port %d's device released by %s" % [lib_port,
		owner.name if is_instance_valid(owner) else "a freed adapter"])
	announce_port(lib_port)


## The adapter deciding port `lib_port`'s device, or null. One freed without
## letting go is forgotten here.
func port_owner(lib_port: int) -> Node:
	if not port_owners.has(lib_port):
		return null
	var held: Variant = port_owners[lib_port]
	if not is_instance_valid(held):
		port_owners.erase(lib_port)
		print("[RetroSystem] port %d: its adapter is gone, the port is its own again" % lib_port)
		return null
	return held as Node


## Tell the core what the peripheral in cabinet slot `i` is, if one is there.
func announce_cabinet_port(i: int) -> void:
	var owner := port_owner(i)
	if owner != null and owner.has_method("port_device"):
		var dev: Dictionary = owner.call("port_device", _host, i)
		var names: PackedStringArray = dev.get("names", PackedStringArray())
		set_device(i, core_device_id(int(dev.get("type", RetroSystem.RETRO_DEVICE_NONE)), i, names))
		return
	var ctrl: Node = controllers[i]
	# A multitap at 5P is the port's device, whatever pad is in its first socket
	# (that pad is what `controllers` holds, for rumble and netplay): it is what
	# the cabinet socket's plug belongs to.
	var cab_plug: Node = plugs[i] if i < plugs.size() else null
	if is_instance_valid(cab_plug) and cab_plug.has_method("get_controller"):
		var tap: Node = controller_of(cab_plug)
		# At 2P the pad in its first socket is the port's device, and with none
		# there the tap's own (nothing) is.
		if tap is RetroMultitap and ((tap as RetroMultitap).mode == RetroMultitap.MODE_5P
				or not is_instance_valid(ctrl)):
			ctrl = tap
	if not is_instance_valid(ctrl):
		return
	var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
	if not claims_port_device(dev):
		return
	# `plugs` is what says WIRED: a cabinet socket records its plug, and a
	# wireless remote or a multitap sub-port has none. Only the wired ones take
	# the GameCube-on-Wii translation.
	var announce := dev
	var wii := _host.get_wii_link()
	if wii != null and i < plugs.size() and plugs[i] != null:
		announce = wii.cabinet_device_id(dev)
	var lib_port := libretro_port_for(dev, i)
	set_device(lib_port, core_device_id(announce, lib_port, device_names_of(ctrl)))


## Say what is on each port a SECOND time, once the core has actually run a frame.
## True on the call that did it, so the machine can run what else waits for that
## frame (its storages).
##
## reannounce_all at options_ready is enough for anything announced while a core
## was already running: Wrapper queues that as an emulation-thread command and it
## lands between frames. A device announced while the machine was OFF does not
## take that path. It goes into Wrapper's pending map and is applied right after
## retro_load_game — which is canonical, and is also before the first retro_run.
##
## That is too early for a core which decides anything on its first pass. Dolphin
## turns its sensors on in InitSensors(), at the top of frame 0, and binds a Wii
## Remote's accelerometer and gyroscope INSIDE retro_set_controller_port_device
## only if that has already happened. So a remote paired before the console was
## switched on — which is the ordinary way round, you press SYNC and then you
## press POWER — got no motion at all for the whole session, and nothing rebound
## it short of pulling the Nunchuk out and putting it back.
##
## Measured with Tools/prestart_probe: "Applying pre-start port device: port=0
## device=769" prints before every "Sensor: accelerometer enabled" line, and both
## come from the emulation thread, so that order is real rather than two threads
## interleaving in the log.
##
## One completed frame is the whole condition — retro_run has returned, so
## whatever the core sets up on its first pass is up. Deliberately not a frame
## COUNT: see SystemAudio.ensure_bound, where elapsed frames stood in for a readiness
## question and the two only agreed for cores that come up fast.
func ensure_devices_bound() -> bool:
	if devices_settled or not _host.is_powered_on:
		return false
	var lib := _host.get_libretro_node()
	if not is_instance_valid(lib) or lib.GetFrameCount() <= 0:
		return false
	devices_settled = true
	print("[RetroSystem] %s: first frame run, ports announced again" % _host.systemid)
	reannounce_all()
	return true


## The id the RUNNING core understands for a peripheral, given the generic type
## the peripheral carries. The light gun always needs translating, and it needs it
## badly: a core names its own device ids, and a gun is rarely plain
## RETRO_DEVICE_LIGHTGUN — fceumm's Zapper is 258, a MOUSE subclass. An id a core
## does not recognise does not leave the port alone either; fceumm's switch falls
## through to a gamepad, which un-plugs the gun the game had auto-detected.
##
## The core's own declared list is the source, so this needs no per-core table:
## prefer an entry whose base type IS a light gun, else one whose name reads as a
## gun, else announce what we were given.
##
## `named` is what a gun that is one PARTICULAR gun calls itself (a peripheral's
## `device_names`: "zapper", "guncon"). A core that lists several guns on one
## port lists them in its own order, and the first is not always the one in the
## player's hand: a PlayStation core offers the GunCon and the Justifier. Where
## the core has a device of one of those names, that is the one announced; where
## it has none, the rules above stand, so a named gun is never worse off than
## the generic one.
##
## A name is looked up for ANY peripheral that gives one, not only a gun. A pad
## that is more than a plain joypad has the gun's problem exactly: a Saturn 3D
## Control Pad is 261 to Beetle Saturn and 5 to the Yabause family, where 261 is
## the steering wheel. Where the core lists nothing of its name the pad is
## announced as the type it carries, which for a pad is the plain joypad every
## core has.
func core_device_id(device_type: int, lib_port: int,
		named: PackedStringArray = PackedStringArray()) -> int:
	if device_type != RetroSystem.RETRO_DEVICE_LIGHTGUN and named.is_empty():
		return device_type
	var devices: Array = []
	for entry: Dictionary in controller_info:
		if int(entry.get("port", -1)) == lib_port:
			devices.append_array(entry.get("controllers", []))
	# The names are in the peripheral's own order of preference, so each is
	# looked for through the whole list before the next: a GunCon 2 that will
	# settle for a GunCon still gets the "GunCon 2" a core lists after it.
	for word: String in named:
		if word.is_empty():
			continue
		for dev: Dictionary in devices:
			if String(dev.get("name", "")).to_lower().contains(word.to_lower()):
				return int(dev.get("id", 0))
	if device_type != RetroSystem.RETRO_DEVICE_LIGHTGUN:
		return device_type
	var by_name := -1
	for dev: Dictionary in devices:
		var id := int(dev.get("id", 0))
		if (id & RetroSystem.RETRO_DEVICE_MASK) == RetroSystem.RETRO_DEVICE_LIGHTGUN:
			return id
		if by_name < 0 and reads_as_lightgun(String(dev.get("name", ""))):
			by_name = id
	return by_name if by_name >= 0 else device_type


## The names a plugged peripheral goes by in a core's device list, or none. Read
## off the plug or the controller, whichever the caller has: a plug copies its
## controller's as it copies its device type.
static func device_names_of(peripheral: Object) -> PackedStringArray:
	if peripheral != null and "device_names" in peripheral:
		var names: Variant = peripheral.get("device_names")
		if names is PackedStringArray:
			return names
	return PackedStringArray()


## Whether a core's device NAME reads as a light gun, for the cores that
## describe one without using the light-gun base type.
static func reads_as_lightgun(device_name: String) -> bool:
	var lower := device_name.to_lower()
	for word: String in _LIGHTGUN_WORDS:
		if lower.contains(word):
			return true
	return false


## True when this system is a home computer (ScummVM, DOS, Amiga…) whose core
## reads the mouse on port 0 and takes keyboard input globally.
func is_computer() -> bool:
	var info := SystemInfo.for_system(_host.systemid)
	return info != null and info.computer


## The libretro port a plugged peripheral should drive. On computer systems the
## mouse always drives port 0 — where ScummVM/DOS/Amiga cores poll it — no matter
## which cabinet slot it's in; every other device drives its own physical port.
##
## A joypad on a computer is pinned the same way, and for the same reason. Its
## socket is the tower's game port, which is cabinet slot 3 because slots 1 and 2
## are the keyboard and mouse — but a DOS or Amiga core reads its one joystick on
## port 0, and a pad announced on port 2 is a pad the game never sees.
func libretro_port_for(device_type: int, physical_port: int) -> int:
	if device_type == RetroSystem.RETRO_DEVICE_MOUSE and is_computer():
		return 0
	# The GAME PORT only, not every joypad socket on a computer: a machine with two
	# joystick ports still drives port 1 from its second one.
	if device_type == RetroSystem.RETRO_DEVICE_JOYPAD and is_computer():
		var model := _host.get_model()
		if model != null and model.game_port_index() == physical_port:
			return 0
	return physical_port


## Whether a plugged peripheral occupies a numbered libretro port device. A
## computer keyboard does not: its keys are global to port 0 regardless, so it
## leaves the port free for the mouse and avoids cores that mishandle a
## RETRO_DEVICE_KEYBOARD "controller" set on a numbered port.
func claims_port_device(device_type: int) -> bool:
	return not (device_type == RetroSystem.RETRO_DEVICE_KEYBOARD and is_computer())


# --- Per-port core options: pad type and pak ---

## Auto-select the running core's per-port "pad type" option to match the pad
## just plugged in: a DualShock (pad_type_pref "dualshock") switches the port to
## the analog/DualShock profile, the original digital pad selects "standard".
## Gated on the option actually existing (PCSX-ReARMed's pcsx_rearmed_padNtype),
## so it is a no-op on every core that has no such option.
func apply_pad_type_option(lib_port: int, ctrl: Node) -> void:
	if not is_instance_valid(ctrl) or not ("pad_type_pref" in ctrl):
		return
	var key := pad_type_option_key(lib_port)
	if key.is_empty():
		return
	var desired: String = ctrl.get("pad_type_pref")
	var allowed := option_values(key)
	var current := String(_host.core_option_values().get(key, ""))
	var target := decide_pad_type(allowed, desired, current)
	if target.is_empty():
		return
	print("[RetroSystem] auto pad-type: port %d -> %s = '%s'" % [lib_port, key, target])
	_host.set_core_option(key, target)


## Pure pad-type decision: given the option's allowed values, the pad's preferred
## value and the current value, return the value to set, or "" for no change.
## A DualShock on a core that offers only a plain analog pad falls back to it.
static func decide_pad_type(allowed: Array, desired: String, current: String) -> String:
	if allowed.is_empty():
		return ""
	var pick := desired
	if not (pick in allowed):
		if desired == "dualshock" and "analog" in allowed:
			pick = "analog"
		else:
			return ""
	return "" if pick == current else pick


## Auto-select the running core's per-port pak option to match what is fitted to
## that controller's expansion port. An N64 controller takes a Rumble Pak, a
## Controller Pak or a Transfer Pak, and each port answers for itself.
##
## Gated on the option existing, so it is a no-op on every core without one. It
## is deliberately gated on the VALUE existing too: parallel_n64 offers a Bio
## Sensor where mupen64plus-next offers a Transfer Pak, and a pak the running
## core cannot serve must leave the port alone rather than silently fit
## something else.
func apply_pak_option(lib_port: int, ctrl: Node) -> void:
	if not is_instance_valid(ctrl) or not ctrl.has_method("pak_option_value"):
		return
	# Bind the bytes FIRST, and before the option key is even required. Setting
	# the option first starts the core's delayed pak insert, and a Controller Pak
	# that arrives before its file does reads whatever the cartridge's own .srm
	# left at that offset.
	#
	# The key only exists once the core has published its options, so gating this
	# on the key meant a pak already seated at boot had its paths pushed at
	# options_ready -- AFTER the core had already read the pak while initialising
	# the controllers. With the option persisted at its target value from the last
	# session there was then no transition to make it read again, so the cartridge
	# stayed absent until the machine was power cycled. Nothing here needs the
	# core's options, so nothing here waits for them.
	bind_pak_storage(lib_port, ctrl)
	var key := pak_option_key(lib_port)
	if key.is_empty():
		return
	var seated: String = ctrl.call("pak_option_value")
	var allowed := option_values(key)
	var current := String(_host.core_option_values().get(key, ""))
	var target := decide_pak(allowed, seated, current)
	if target.is_empty():
		return
	print("[RetroSystem] pak: port %d -> %s = '%s'" % [lib_port, key, target])
	_host.set_core_option(key, target)


## Point a Controller Pak's own file at the slice of the core's save block that
## port reads through.
##
## Both N64 cores keep all four paks inside the single SAVE_RAM block rather than
## behind a memory id apiece, back them with a storage backend whose save is a
## no-op, and stub their own mempak path helper to "" -- so nothing the core does
## persists a pak, and the only way to address one is by offset. The layout is
## the same in both (eeprom, then four paks, then sram, flashram); parallel_n64
## appends a 64DD region after that, which changes the block's SIZE but not where
## the paks begin.
func bind_pak_storage(lib_port: int, ctrl: Node) -> void:
	var lib := _host.get_libretro_node()
	if lib == null or lib_port < 0 or lib_port >= RetroSystem.MEMPAK_PORTS:
		return
	var pak: Node = ctrl.call("get_pak") if ctrl.has_method("get_pak") else null

	var path := ""
	if is_instance_valid(pak) and pak is ControllerPak:
		path = str(pak.call("image_path"))
		# Only a pak this session invented may have its image created. One
		# that came back from a saved room with its file missing runs
		# unbacked, so a vanished set of notes does not return as a silent
		# blank that reads exactly like a wipe.
		if not path.is_empty() and bool(pak.get("minted")):
			SramPaths.ensure_card(ControllerPak.FAMILY, str(pak.get("card_id")))
	lib.SetSramRegionPath(lib_port, path,
		RetroSystem.MEMPAK_BASE_OFFSET + lib_port * RetroSystem.MEMPAK_SIZE,
		RetroSystem.MEMPAK_SIZE)

	var rom := ""
	var ram := ""
	var rtc := ""
	if is_instance_valid(pak) and pak is TransferPak:
		rom = str(pak.call("cart_rom_path"))
		ram = str(pak.call("cart_save_path", _host.resolve_core_name()))
		rtc = str(pak.call("cart_rtc_path", _host.resolve_core_name()))
	# Before SetTransferPak: its generation bump is what has the core read the
	# cartridge again, and it asks for the clock then.
	lib.SetTransferPakClock(lib_port, rtc)
	lib.SetTransferPak(lib_port, rom, ram)


## Pure pak decision: given the option's allowed values, the value the seated pak
## asks for and the current value, return the value to set, or "" for no change.
##
## An empty `seated` means the controller has no expansion port at all, and that
## is NOT the same as an empty port. mupen64plus-next fits a Controller Pak to
## port 1 by default, so answering "none" for a pad that simply cannot take a pak
## would quietly pull out a pak the player has been saving to. Only a controller
## that HAS a port gets to say "none".
static func decide_pak(allowed: Array, seated: String, current: String) -> String:
	if allowed.is_empty() or seated.is_empty():
		return ""
	if not (seated in allowed):
		return ""
	return "" if seated == current else seated


## Push every seated pak's storage at the core BEFORE content starts.
##
## The core reads a Transfer Pak's cartridge while it initialises the
## controllers, which happens inside StartContent -- so a table filled after
## that is filled too late and the pak comes up holding nothing. None of this
## needs the core's published options, so it can run first, and must.
func bind_all_pak_storage() -> void:
	for i in range(controllers.size()):
		var ctrl: Node = controllers[i]
		if not is_instance_valid(ctrl):
			continue
		var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
		bind_pak_storage(libretro_port_for(dev, i), ctrl)


## Re-apply every port's pad-type and pak option. Called when the option set
## first becomes known (options_ready), covering pads plugged before core start,
## and by a pad that changes its own mode while it stays plugged in: a DualShock
## toggled out of analogue mode is the same controller reporting a different
## pad_type_pref, and the core option has to follow it without the cable being
## pulled and pushed back.
func reapply_pad_types() -> void:
	for i in range(controllers.size()):
		var ctrl: Node = controllers[i]
		if not is_instance_valid(ctrl):
			continue
		var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
		apply_pad_type_option(libretro_port_for(dev, i), ctrl)
		apply_pak_option(libretro_port_for(dev, i), ctrl)


## Re-announce the pak on one controller's port. Called when a pak is pushed into
## or pulled out of an expansion port, which the system cannot see for itself —
## the port belongs to the controller, two objects away.
func reapply_pak(ctrl: Node) -> void:
	for i in range(controllers.size()):
		if controllers[i] != ctrl:
			continue
		var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
		apply_pak_option(libretro_port_for(dev, i), ctrl)
		return


## Write each seated pak's option into the saved options file before the core
## reads it, so a pak already in its port at boot is the one the core comes up
## with. Only keys the file already has: the options_ready path still applies
## the pak, and records the key for next time.
##
## apply_pak_option remains the authority once the core has published its
## values: this cannot check them, so a pak a core has no word for (a Transfer
## Pak on parallel_n64) is written here and corrected there.
func persist_pak_options(dir: String, core: String) -> void:
	var saved: Dictionary = CoreOptionsStore.load_values(dir, core)
	if saved.is_empty():
		return
	var out := {}
	for i in range(controllers.size()):
		var ctrl: Node = controllers[i]
		if not is_instance_valid(ctrl) or not ctrl.has_method("pak_option_value"):
			continue
		var seated: String = ctrl.call("pak_option_value")
		# Empty means the pad has no expansion port at all, which is NOT the same
		# as an empty port -- see decide_pak. Those ports are left alone.
		if seated.is_empty():
			continue
		var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
		var lib_port := libretro_port_for(dev, i)
		if lib_port < 0:
			continue
		var suffix := "-pak%d" % (lib_port + 1)
		for key: String in saved:
			if key.ends_with(suffix):
				out[key] = seated
				break
	if not out.is_empty() and CoreOptionsStore.merge_values(dir, core, out):
		print("[RetroSystem] pak options pinned before boot: %s" % str(out))


## The core option key that controls the pad type on a given libretro port, or
## "" if the running core has none. PCSX-ReARMed exposes pcsx_rearmed_pad1type …
## pad8type (1-based); extend here to cover another core if needed.
func pad_type_option_key(lib_port: int) -> String:
	var key := "pcsx_rearmed_pad%dtype" % (lib_port + 1)
	return key if _host.core_declares_option(key) else ""


## The core option key that fits a pak to a given libretro port, or "" if the
## running core has none.
##
## FOUND rather than composed: mupen64plus-next's key prefix is whatever
## CORE_NAME the buildbot compiled it with — the source only guarantees a
## `-pakN` suffix — and parallel_n64's is `parallel-n64-`. Composing either one
## would fit paks on one build and silently nothing on the next.
func pak_option_key(lib_port: int) -> String:
	var suffix := "-pak%d" % (lib_port + 1)
	for key: String in _host.core_option_definitions():
		if key.ends_with(suffix):
			return key
	return ""


## The list of allowed values for an option key (empty if unknown).
func option_values(key: String) -> Array:
	var def: Object = _host.core_option_definitions().get(key)
	if def == null:
		return []
	var out: Array = []
	for v in def.GetValues():
		out.append(v.GetValue())
	return out


# --- Who is where ---

## The libretro port a pad plugged into this machine occupies, or -1.
func pad_libretro_port(ctrl: Node) -> int:
	for i in range(controllers.size()):
		if controllers[i] != ctrl:
			continue
		var dev: int = ctrl.get("device_type") if "device_type" in ctrl else 1
		return libretro_port_for(dev, i)
	return -1


## The node holding a given libretro port, or null.
func port_holder(port: int) -> Node:
	if port < 0 or port >= controllers.size():
		return null
	var held: Node = controllers[port]
	return held if is_instance_valid(held) else null


## Every port's holder, port order, null where nothing is plugged in. A copy, so
## a caller cannot reshape the table by holding onto it.
func port_holders() -> Array:
	return controllers.duplicate()


## The cabinet socket a plug went into, or null when it cannot be told yet.
##
## Two ways to find it, because `plugs` is not always filled in by the time a
## plug-in hook runs. The index is the FALLBACK rather than the primary: it is
## the libretro port, which equals the cabinet socket for a joypad but not for
## everything — a computer mouse is forced to port 0 whichever socket it is in —
## so the identity lookup is preferred whenever it is available.
func port_socket(plug: Node, port_index: int) -> Node3D:
	for i in plugs.size():
		if plugs[i] == plug and i < zones.size():
			return zones[i] as Node3D
	if port_index >= 0 and port_index < zones.size():
		return zones[port_index] as Node3D
	return null


## The cabinet socket `plug` is seated in, or -1. By the PLUG, not the device:
## the holder of a multitap's port is the pad in its first socket at 5P, so
## cabinet_port_of cannot find the tap itself.
func cabinet_port_of_plug(plug: Node) -> int:
	if plug == null:
		return -1
	for i in plugs.size():
		if plugs[i] == plug:
			return i
	if accessory_plug != null and accessory_plug == plug:
		return RetroSystem.ACCESSORY_SLOT
	return -1


## Every cabinet socket `plug` is in, in socket order: one for an ordinary plug,
## two for the Four Score's block (socket_span).
func cabinet_ports_of_plug(plug: Node) -> Array[int]:
	var out: Array[int] = []
	if plug == null:
		return out
	for i in plugs.size():
		if plugs[i] == plug:
			out.append(i)
	return out


## Which cabinet socket holds this peripheral, or -1 if the system is not holding
## it at all; a USB socket answers RetroSystem.USB_SLOT_BASE + k.
##
## The peripheral's own _port_index is the LIBRETRO port, which is the same number
## only by coincidence: libretro_port_for pins a mouse on a computer system to
## port 0 whichever socket it is in, because that is where those cores poll it. So
## a save that recorded _port_index put the mouse and the keyboard both in socket 1
## on restore, and one of them was left dangling. Ask the cabinet instead.
func cabinet_port_of(peripheral: Node) -> int:
	for i in controllers.size():
		if is_instance_valid(controllers[i]) and controllers[i] == peripheral:
			return i
	for k in usb_controllers.size():
		if is_instance_valid(usb_controllers[k]) and usb_controllers[k] == peripheral:
			return RetroSystem.USB_SLOT_BASE + k
	return -1


# --- Controller port snap handlers ---

func on_port_snapped(port_index: int, controller: Node3D) -> void:
	_host.get_model().play_port_plug_insert(controller, zones[port_index])
	var device_type: int = controller.get("device_type") if "device_type" in controller else 1
	# The libretro port a peripheral drives isn't always its cabinet slot: on
	# computer systems the mouse is forced to port 0 (where those cores poll it),
	# so a mouse + keyboard can share the cabinet. See libretro_port_for().
	bind(libretro_port_for(device_type, port_index), controller, port_index)
	_take_spanned(port_index, controller, device_type)


## A plug that fills more than one socket (socket_span) takes the ones beside the
## socket it seated in as well: each is shut to anything else and bound to the same
## plug, so the core hears a device on every port the block fills and the plug's
## owner is told of each (on_plugged_in, once per port). A socket that cannot take
## it -- a restore that put the block where the console has no neighbour -- is
## left out and said so.
func _take_spanned(port_index: int, plug: Node3D, device_type: int) -> void:
	for k in range(1, socket_span_of(plug)):
		var j := port_index + k
		if not _open_for_span(j):
			print("[RetroSystem] port %d: %s fills %d sockets, and socket %d cannot take its plug %d"
				% [port_index, plug.name, socket_span_of(plug), j, k + 1])
			continue
		_spanned[j] = (zones[j] as XRToolsSnapZone).enabled
		(zones[j] as XRToolsSnapZone).enabled = false
		print("[RetroSystem] port %d: %s's plug %d fills socket %d too" % [port_index, plug.name, k + 1, j])
		bind(libretro_port_for(device_type, j), plug, j)


## Whether cabinet socket `i` is filled by a block seated in the socket beside it.
func is_spanned(i: int) -> bool:
	return _spanned.has(i)


## Let go of every socket `plug` was filling beside `port_index`, and open them.
func _free_spanned(port_index: int, plug: Node3D, device_type: int) -> void:
	for j in range(port_index + 1, plugs.size()):
		if plugs[j] != plug:
			continue
		plugs[j] = null
		if _spanned.has(j):
			if j < zones.size():
				(zones[j] as XRToolsSnapZone).enabled = bool(_spanned[j])
			_spanned.erase(j)
		print("[RetroSystem] port %d: socket %d freed with it" % [port_index, j])
		unbind(libretro_port_for(device_type, j), plug, j)


func on_port_released(port_index: int) -> void:
	var plug: Node3D = plugs[port_index]
	plugs[port_index] = null
	if not is_instance_valid(plug):
		print("[RetroSystem] port %d emptied with no plug recorded" % port_index)
		return
	var device_type: int = plug.get("device_type") if "device_type" in plug else 1
	_free_spanned(port_index, plug, device_type)
	# Clear the SAME libretro port the snap set (a computer mouse claimed port 0,
	# not its cabinet slot; a computer keyboard claimed none).
	unbind(libretro_port_for(device_type, port_index), plug, port_index)


## Bind a peripheral to a libretro port, from either direction: `cabinet_index`
## is the socket it seated into, or -1 for an EXPANDED port — one a multitap fans
## out to, which has no socket, no plug to remember and no Wii translation, but is
## a port to the core like any other. `announce_device` false leaves the port's
## device as it is: a multitap at 5P owns its own port's device, the pad in its
## first socket only feeds it.
##
## Written once because the expanded copy used to be an abridged one, and the
## abridgement is what dropped the device translation: a light gun on a multitap
## announced RETRO_DEVICE_LIGHTGUN, which fceumm turns into a gamepad.
func bind(lib_port: int, plug: Node3D, cabinet_index: int, announce_device := true) -> void:
	if lib_port < 0 or not is_instance_valid(plug):
		print("[RetroSystem] port bind refused: libretro port %d, plug %s"
			% [lib_port, "valid" if is_instance_valid(plug) else "missing"])
		return
	var device_type: int = plug.get("device_type") if "device_type" in plug else 1
	var announce := device_type
	if cabinet_index >= 0:
		_host.add_collision_exception_with(plug)
		# The plug itself is kept for the release path, which is handed nothing.
		plugs[cabinet_index] = plug
		# On a Wii the slot may already hold a paired remote, and a wired pad may
		# need announcing as a GameCube pad rather than a plain joypad. Both are
		# Wii policy and both live in WiiLink; every other console skips them.
		var wii := _host.get_wii_link()
		if wii != null:
			wii.evict_remote_from(lib_port)
			announce = wii.cabinet_device_id(device_type)
	announce = core_device_id(announce, lib_port, device_names_of(plug))
	print("[RetroSystem] port %d bound: device_type=%d -> libretro port %d (announced %d)" %
		[cabinet_index, device_type, lib_port, announce])
	# A device in the USB socket of this number is what the core is told about:
	# it keeps the pad on the port besides (see announce_port).
	# A port an adapter decides is the adapter's to announce (port_owners).
	if announce_device and claims_port_device(device_type) and usb_plug_at(lib_port) == null:
		if port_owner(lib_port) != null:
			announce_cabinet_port(lib_port)
		else:
			set_device(lib_port, announce)
	# The bound node is a ControllerPlug (cable end). Unwrap to the actual
	# RetroController so rumble can be routed to its set_rumble() method.
	var ctrl := controller_of(plug)
	var slot := cabinet_index if cabinet_index >= 0 else lib_port
	if slot < controllers.size():
		controllers[slot] = ctrl
	_tell_plugged_in(plug, lib_port)
	# Auto-select the core's per-port pad type (e.g. PCSX-ReARMed: DualShock vs
	# the original digital pad). No-ops unless the core exposes such an option.
	apply_pad_type_option(lib_port, ctrl)
	apply_pak_option(lib_port, ctrl)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_PLUG,
		{"sys": _host, "ctrl": ctrl, "port": slot})


## Release a peripheral from a libretro port. See bind for `cabinet_index`.
func unbind(lib_port: int, plug: Node3D, cabinet_index: int, announce_device := true) -> void:
	if lib_port < 0:
		print("[RetroSystem] port unbind refused: libretro port %d" % lib_port)
		return
	print("[RetroSystem] port %d released" % cabinet_index)
	# Stop any active rumble on the controller being unplugged.
	var ctrl := controller_of(plug)
	if is_instance_valid(ctrl) and ctrl.has_method("set_rumble"):
		ctrl.set_rumble(0.0, 0.0)
	var device_type: int = plug.get("device_type") \
		if is_instance_valid(plug) and "device_type" in plug else 1
	if cabinet_index >= 0 and is_instance_valid(plug):
		_host.remove_collision_exception_with(plug)
	var slot := cabinet_index if cabinet_index >= 0 else lib_port
	if slot < controllers.size():
		controllers[slot] = null
	if announce_device and claims_port_device(device_type):
		if usb_plug_at(lib_port) != null or port_owner(lib_port) != null:
			announce_port(lib_port)
		else:
			set_device(lib_port, RetroSystem.RETRO_DEVICE_NONE)
	_tell_unplugged(plug)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_UNPLUG, {"sys": _host, "port": slot})


## What a socket was handed, unwrapped to the peripheral behind it.
##
## A controller port takes either a cable END -- a ControllerPlug, a light gun's
## or a multitap's plug, whose get_controller() names the pad at the far end --
## or a thing that IS its own plug (a VMU, an N64 pak, the GameCube-to-GBA lead's
## console end), which answers for itself. Every port path unwraps through here,
## so rumble, netplay and the port table all see the same node. A freed or
## missing plug unwraps to null.
static func controller_of(plug: Variant) -> Node3D:
	if not is_instance_valid(plug):
		return null
	var node := plug as Node
	if node != null and node.has_method("get_controller"):
		# A pad deleted while its plug still sits in the port leaves the plug holding a FREED controller, and a
		# freed instance cannot be assigned to a typed variable: ask for it untyped, and keep it only if it is
		# still there.
		var held: Variant = node.get_controller()
		return held as Node3D if is_instance_valid(held) else null
	return node as Node3D


## Tell what was seated that it is on libretro port `lib_port` of this machine.
## Optional on the plug side: a VMU or a pak seated as a plug has nothing to do.
func _tell_plugged_in(plug: Variant, lib_port: int) -> void:
	if is_instance_valid(plug) and plug.has_method("on_plugged_in"):
		plug.on_plugged_in(_host, lib_port)


## The other half of _tell_plugged_in, for whatever just left a socket.
func _tell_unplugged(plug: Variant) -> void:
	if is_instance_valid(plug) and plug.has_method("on_unplugged"):
		plug.on_unplugged()


# --- USB socket snap handlers ---

## A plug seated in USB socket k is the device on the core's port k. The core
## plugs it into its own USB port k and keeps the pad on that port as it was --
## the PlayStation 2 core: "The GunCon is a USB peripheral, so it does not
## displace the emulated SIO DualShock 2" -- so a pad in controller port k and a
## gun in USB socket k both work, and which player a gun is is the GAME's to
## decide, by USB port, as it was on the hardware.
func on_usb_snapped(plug: Node3D, k: int) -> void:
	if not is_instance_valid(plug) or k >= usb_plugs.size():
		print("[RetroSystem] USB socket %d refused a seat: %s" % [k,
			"no plug" if not is_instance_valid(plug) else "no such socket"])
		return
	var model := _host.get_model()
	if model != null and k < usb_zones.size():
		model.play_port_plug_insert(plug, usb_zones[k])
	_host.add_collision_exception_with(plug)
	usb_plugs[k] = plug
	var ctrl := controller_of(plug)
	usb_controllers[k] = ctrl
	print("[RetroSystem] USB socket %d: %s seated" % [k, plug.name])
	announce_port(k)
	_tell_plugged_in(plug, k)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_PLUG,
		{"sys": _host, "ctrl": ctrl, "port": RetroSystem.USB_SLOT_BASE + k})


func on_usb_released(k: int) -> void:
	if k >= usb_plugs.size():
		print("[RetroSystem] USB socket %d released, but there is no such socket" % k)
		return
	var plug: Node3D = usb_plugs[k]
	usb_plugs[k] = null
	usb_controllers[k] = null
	print("[RetroSystem] USB socket %d emptied" % k)
	announce_port(k)
	if not is_instance_valid(plug):
		return
	_host.remove_collision_exception_with(plug)
	_tell_unplugged(plug)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_UNPLUG,
		{"sys": _host, "port": RetroSystem.USB_SLOT_BASE + k})


## A plug seated in the accessory connector: its device is announced on the
## connector's libretro port, and it is told it is there.
func on_accessory_snapped(plug: Node3D) -> void:
	if not is_instance_valid(plug):
		print("[RetroSystem] accessory connector refused a seat: no plug")
		return
	var model := _host.get_model()
	if model != null and accessory_zone != null:
		model.play_port_plug_insert(plug, accessory_zone)
	_host.add_collision_exception_with(plug)
	accessory_plug = plug
	print("[RetroSystem] accessory connector: %s seated, its device on libretro port %d"
		% [plug.name, accessory_lib_port])
	announce_port(accessory_lib_port)
	_tell_plugged_in(plug, accessory_lib_port)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_PLUG,
		{"sys": _host, "ctrl": controller_of(plug), "port": RetroSystem.ACCESSORY_SLOT})


func on_accessory_released() -> void:
	var plug := accessory_plug
	accessory_plug = null
	print("[RetroSystem] accessory connector emptied")
	if accessory_lib_port >= 0:
		announce_port(accessory_lib_port)
	if not is_instance_valid(plug):
		return
	_host.remove_collision_exception_with(plug)
	_tell_unplugged(plug)
	NetworkManager.report_event(NetEvents.Event.EV_PORT_UNPLUG,
		{"sys": _host, "port": RetroSystem.ACCESSORY_SLOT})


## The plug in the accessory connector when its device is on `lib_port`, or null.
func accessory_plug_at(lib_port: int) -> Node3D:
	if lib_port < 0 or lib_port != accessory_lib_port or not is_instance_valid(accessory_plug):
		return null
	return accessory_plug


## Put `filter` between port `lib_port`'s pad and the core: filter_port_input(port,
## pad) -> pad is asked of it for every frame a pad sends there. One per port; a
## second takes over from the first, and says so.
func set_input_filter(lib_port: int, filter: Node) -> void:
	if lib_port < 0 or not is_instance_valid(filter):
		return
	var held: Variant = input_filters.get(lib_port)
	if is_instance_valid(held) and held != filter:
		print("[RetroSystem] port %d: %s takes over the input filter from %s"
			% [lib_port, filter.name, (held as Node).name])
	input_filters[lib_port] = filter


## Take `filter` off port `lib_port`, if it is the one there.
func clear_input_filter(lib_port: int, filter: Node) -> void:
	if input_filters.has(lib_port) and input_filters[lib_port] == filter:
		input_filters.erase(lib_port)


## A pad's frame on its way to port `lib_port`, after the filter there.
func filter_port_input(lib_port: int, pad: Dictionary) -> Dictionary:
	if not input_filters.has(lib_port):
		return pad
	var filter: Variant = input_filters[lib_port]
	if not is_instance_valid(filter):
		input_filters.erase(lib_port)
		return pad
	return (filter as Node).call("filter_port_input", lib_port, pad)


## The plug in the USB socket of this number, or null.
func usb_plug_at(lib_port: int) -> Node3D:
	if lib_port < 0 or lib_port >= usb_plugs.size() or not is_instance_valid(usb_plugs[lib_port]):
		return null
	return usb_plugs[lib_port]


## Tell the core what is on its port `lib_port`: the device in the USB socket of
## that number if there is one, else the pad in the controller port, else nothing.
func announce_port(lib_port: int) -> void:
	var usb := usb_plug_at(lib_port)
	if usb == null:
		usb = accessory_plug_at(lib_port)
	if usb != null:
		var dev: int = usb.get("device_type") if "device_type" in usb else 1
		set_device(lib_port, core_device_id(dev, lib_port, device_names_of(usb)))
		return
	if lib_port < controllers.size() and (port_owner(lib_port) != null
			or is_instance_valid(controllers[lib_port])):
		announce_cabinet_port(lib_port)
		return
	set_device(lib_port, RetroSystem.RETRO_DEVICE_NONE)


## Route a rumble request from the core to the RetroController currently
## plugged into the matching cabinet port.
func on_rumble(port: int, weak: float, strong: float) -> void:
	if port < 0 or port >= controllers.size():
		return
	var ctrl: Variant = controllers[port]
	if ctrl and is_instance_valid(ctrl) and (ctrl as Object).has_method("set_rumble"):
		ctrl.set_rumble(weak, strong)


## Zero any active rumble on every plugged-in controller, so vibration does not
## leak past a core unload if the core was rumbling at shutdown.
func stop_all_rumble() -> void:
	for ctrl: Variant in controllers:
		if ctrl and is_instance_valid(ctrl) and (ctrl as Object).has_method("set_rumble"):
			ctrl.set_rumble(0.0, 0.0)


## Release a controller port from replicated state. A plain SnapZone drop leaves
## the plug centred in its grab volume, so it is immediately picked back up on
## the next physics tick. The local player's hand naturally carries a pulled
## plug away; a remote peer has no synced plug body, so park it by its controller
## before re-enabling the socket.
func net_release(port_index: int) -> void:
	# A USB socket is USB_SLOT_BASE + k, and released the same way.
	var zone_list: Array = zones
	var plug_list: Array = plugs
	var index := port_index
	if port_index >= RetroSystem.USB_SLOT_BASE:
		zone_list = usb_zones
		plug_list = usb_plugs
		index = port_index - RetroSystem.USB_SLOT_BASE
	if index < 0 or index >= zone_list.size():
		print("[RetroSystem] net release of port %d refused: no such socket" % port_index)
		return
	var zone := zone_list[index] as XRToolsSnapZone
	var plug := plug_list[index] as ControllerPlug
	var plug_enabled := plug.enabled if is_instance_valid(plug) else false
	var was_enabled: Array[bool] = []
	for candidate: XRToolsSnapZone in zone_list:
		was_enabled.append(candidate.enabled)
		candidate.enabled = false
	if is_instance_valid(plug):
		plug.enabled = false
	zone.drop_object()
	if is_instance_valid(plug):
		for candidate: XRToolsSnapZone in zone_list:
			candidate.forget_object(plug)
		var controller := plug.get_controller()
		var attach := controller.get_node_or_null("CableAttachPoint") as Node3D \
			if is_instance_valid(controller) else null
		if attach != null:
			plug.global_position = attach.global_position \
				+ attach.global_basis * Vector3(0, 0, -0.12)
		if plug is RigidBody3D:
			(plug as RigidBody3D).linear_velocity = Vector3.ZERO
			(plug as RigidBody3D).angular_velocity = Vector3.ZERO
	# DROPPED-mode zones receive the plug's dropped signal deferred. Keep every
	# neighbouring socket shut until that callback and a physics overlap refresh
	# have both passed, or the plug simply hops from port 1 into port 2.
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		for i in zone_list.size():
			zone_list[i].enabled = was_enabled[i]
		if is_instance_valid(plug):
			plug.enabled = plug_enabled, CONNECT_ONE_SHOT)
