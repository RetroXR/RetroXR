## Four-player adapter self-tests -- the NES Four Score and the Famicom's Hori 4
## Players Adaptor on real consoles, with real pads in their sockets. Headless, no
## core, no ROM: what a core is told is read off the port table (`current_id`),
## against the device lists fceumm and Mesen declare.
##
##     "$godot" --headless --path RetroXR res://Tests/four_player_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/four_player_tests.tscn -- --only=fourscore
##
## Groups:
##   fourscore/ the block fills both of an NES's ports and nowhere else; at 4 the
##              sockets are players 1-4 and ports 2 and 3 are the core's Gamepad
##              with or without a pad (fceumm reads them only so); at 2 the back
##              row is dead and ports 2 and 3 are nothing; a core start keeps all
##              of it; TURBO masks A and B on alternate pairs of frames; pulling
##              the block lets everything go
##   famicom/   the Famicom's accessory connector is on its front and takes the
##              15-pin plug and nothing else; the adaptor puts its own device on
##              the core's fifth port and players 3 and 4 on ports 2 and 3, the
##              hardwired pads untouched; sockets 3 and 4 reach nothing
##   names/     Mesen's names for the same devices
##   save/      both adapters come back with their lead seated, their switches
##              and their pads
##   satellite/ the NES Satellite: its receiver fills both ports, the transmitter
##              pairs with it, 3 or 4 occupied makes it four-player; off, out of
##              range, out of the beam or behind a wall the console hears released
##              pads (routing kept); TURBO, GUN, the seven-minute auto-off, six C
##              cells, and both halves saved
##   psmultitap/ the PlayStation Multitap: its connector fills port and card slot
##              (refused over a card), A-D players 1-4 with the console's port 2
##              moved to libretro port 4, pcsx_rearmed's option pinned, slot A the
##              console's card, a second tap players 5-8, saves, all of it undone
##   ps2multitap/ the PlayStation 2 Multitap (SCPH-10090): the PlayStation's layout
##              in its own ribbed box, pcee2's and LRPS2's pcsx2_multitap pinned
##              (port1 / both / port2 / disabled), PS2 cards only, A and B on one
##              face and C and D on the other, the cord out of an end; either tap
##              in the OTHER console is socket A only, no port moved, no option
##   unwired/   with no adapter, a core start tells fceumm an NES's ports 3 and 4
##              and a Famicom's 3-5 are EMPTY: left at its "Auto" it plugs in a Four
##              Score or a Famicom adapter by itself for games in its own lists
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const FOUR_SCORE_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_four_score.tscn")
const HORI_SCENE := preload("res://Scenes/Objects/controllers/famicom/famicom_four_players_adaptor.tscn")
const NES_PAD_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_controller.tscn")
const GENERIC_PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const SATELLITE_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_satellite.tscn")
const SATELLITE_RX_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_satellite_receiver.tscn")
const PS_MULTITAP_SCENE := preload("res://Scenes/Objects/controllers/playstation/ps_multitap.tscn")
const PS2_MULTITAP_SCENE := preload("res://Scenes/Objects/controllers/playstation/ps2_multitap.tscn")
const PS2_CARD_SCENE := preload("res://Scenes/Objects/media/ps2_memory_card.tscn")
const PS1_PAD_SCENE := preload("res://Scenes/Objects/controllers/playstation/ps1_controller.tscn")
const MEMORY_CARD_SCENE := preload("res://Scenes/Objects/media/memory_card.tscn")

## pcsx_rearmed's eight ports (frontend/libretro.c `pads`), each the same list.
const PCSX_PAD_LIST: Array = [{"name": "standard", "id": 1}, {"name": "dualshock", "id": 517},
	{"name": "analog", "id": 261}, {"name": "negcon", "id": 773}, {"name": "guncon", "id": 260},
	{"name": "konami gun", "id": 516}, {"name": "mouse", "id": 258}]
var PCSX_PORTS: Array = range(8).map(func(p: int) -> Dictionary: return {"port": p, "controllers": PCSX_PAD_LIST})

## LRPS2's eight (pcsx2/PAD/PAD.cpp Input::Init, fork v7): ports 0-1 the USB devices
## too, 2-7 a DualShock 2 alone.
var LRPS2_PORTS: Array = range(8).map(func(p: int) -> Dictionary: return {"port": p,
	"controllers": [{"name": "DualShock 2", "id": 1}, {"name": "GunCon 2", "id": 4},
		{"name": "USB Keyboard", "id": 3}, {"name": "USB Mouse", "id": 2}] if p < 2
		else [{"name": "DualShock 2", "id": 1}]})

const NONE := 0
const JOYPAD := 1
const FCEUMM_GAMEPAD := 513
const FCEUMM_FC_4P := 769
const MESEN_STANDARD := 257
const MESEN_FC_4P := 768

## fceumm's ports as it declares them (libretro.c retro_set_environment): its
## "Auto" IS the plain joypad id, and its Gamepad a subclass of it.
const FCEUMM_PORTS: Array = [
	{"port": 0, "controllers": [{"name": "Auto", "id": 1}, {"name": "Gamepad", "id": 513},
		{"name": "Zapper", "id": 258}]},
	{"port": 1, "controllers": [{"name": "Auto", "id": 1}, {"name": "Gamepad", "id": 513},
		{"name": "Arkanoid", "id": 514}, {"name": "Zapper", "id": 258},
		{"name": "Power Pad A", "id": 1025}, {"name": "Power Pad B", "id": 1281}]},
	{"port": 2, "controllers": [{"name": "Auto", "id": 1}, {"name": "Gamepad", "id": 513},
		{"name": "Power Pad A", "id": 1025}, {"name": "Power Pad B", "id": 1281}]},
	{"port": 3, "controllers": [{"name": "Auto", "id": 1}, {"name": "Gamepad", "id": 513}]},
	{"port": 4, "controllers": [{"name": "Auto", "id": 1}, {"name": "Arkanoid", "id": 258},
		{"name": "(Bandai) Hyper Shot", "id": 514}, {"name": "(Konami) Hyper Shot", "id": 1793},
		{"name": "Oeka Kids Tablet", "id": 770}, {"name": "4-Player Adapter", "id": 769},
		{"name": "Family Trainer A", "id": 1025}, {"name": "Family Trainer B", "id": 1281}]},
]

## Mesen's (Libretro/libretro.cpp): "Standard Controller", and the Famicom's
## adapter a NONE subclass.
const MESEN_PORTS: Array = [
	{"port": 0, "controllers": [{"name": "Auto", "id": 1}, {"name": "Standard Controller", "id": 257}]},
	{"port": 1, "controllers": [{"name": "Auto", "id": 1}, {"name": "Standard Controller", "id": 257}]},
	{"port": 2, "controllers": [{"name": "Auto", "id": 1}, {"name": "Standard Controller", "id": 257}]},
	{"port": 3, "controllers": [{"name": "Auto", "id": 1}, {"name": "Standard Controller", "id": 257}]},
	{"port": 4, "controllers": [{"name": "Auto", "id": 1}, {"name": "Arkanoid", "id": 2},
		{"name": "Four Player Adapter", "id": 768}, {"name": "Hori Track", "id": 258}]},
]

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "fourp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[fourp] TIMED OUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if _want("fourscore"):
		await _group_fourscore()
	if _want("famicom"):
		await _group_famicom()
	if _want("names"):
		await _group_names()
	if _want("unwired"):
		await _group_unwired()
	if _want("satellite"):
		await _group_satellite()
	if _want("psmultitap"):
		await _group_psmultitap()
	if _want("ps2multitap"):
		await _group_ps2multitap()
	if _want("save"):
		await _group_save()
	await _clear()
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)


func _console(systemid: String, at: Vector3, ports: Array) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = at
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(20)
	sys.controller_ports().controller_info = ports.duplicate(true)
	return sys


func _make(scene: PackedScene, at: Vector3) -> Node3D:
	var obj := scene.instantiate() as Node3D
	obj.position = at
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	add_child(obj)
	_spawned.append(obj)
	return obj


## Each port's announced device, ports 0-4.
func _ids(sys: RetroSystem) -> Array:
	var out: Array = [-1, -1, -1, -1, -1]
	for e: Dictionary in sys.controller_ports().controller_info:
		var p := int(e.get("port", -1))
		if p >= 0 and p < out.size():
			out[p] = int(e.get("current_id", -1))
	return out


func _port_of(pad: Node) -> int:
	return int(pad.call("get_port_index")) if is_instance_valid(pad) else -2


# ── fourscore ─────────────────────────────────────────────────────────────────

func _group_fourscore() -> void:
	var sys := await _console("nes", Vector3(0, 1, 0), FCEUMM_PORTS)
	var fs := _make(FOUR_SCORE_SCENE, Vector3(0, 1, 0.5)) as NesFourScore
	var pads: Array = []
	for i in 4:
		pads.append(_make(NES_PAD_SCENE, Vector3(-0.3 + 0.2 * i, 1, 1)))
	await _wait(4)
	var plug := fs.get_plug()
	_ok(plug != null and plug.socket_span == 2, "fourscore/its lead ends in one block of two plugs")
	if plug == null:
		return
	var zones: Array = sys.controller_ports().zones
	_ok((zones[0] as XRToolsSnapZone).snap_filter.call(plug), "fourscore/the block goes in at port 1")
	_ok(not (zones[1] as XRToolsSnapZone).snap_filter.call(plug),
		"fourscore/and not at port 2, where its second plug would have no socket")
	# The block's pitch is the console's: its second plug lands in port 2.
	var pitch := (zones[0] as Node3D).global_position.distance_to((zones[1] as Node3D).global_position)
	_ok(absf(pitch - NesFourScore.PLUG_PITCH) < 0.001, "fourscore/its plugs are the NES's port pitch apart",
		"ports %.4f m apart, plugs %.4f" % [pitch, NesFourScore.PLUG_PITCH])

	# Pads in sockets 1-4 before the lead is in: nothing is bound yet.
	for i in 4:
		fs.restore_socket(i, pads[i])
	await _wait(6)
	_ok(fs.socket_peripherals() == pads, "fourscore/four pads seat in its sockets",
		str(fs.socket_peripherals()))
	_eq(_port_of(pads[2]), -1, "fourscore/with the lead out, a pad in it reaches nothing")

	sys.restore_controller_plug(0, plug)
	await _wait(4)
	_eq(sys.cabinet_ports_of_plug(plug), [0, 1] as Array[int], "fourscore/seated, the block fills ports 1 and 2")
	_ok(not (zones[1] as XRToolsSnapZone).enabled, "fourscore/and port 2 is shut to anything else")
	var pm1 := plug.get_node_or_null("PlugModel") as Node3D
	var pm2 := plug.get_node_or_null("PlugModel2") as Node3D
	if pm1 != null and pm2 != null:
		var off1 := pm1.global_position - (zones[0] as Node3D).global_position
		var off2 := pm2.global_position - (zones[1] as Node3D).global_position
		_ok(off1.distance_to(off2) < 0.001, "fourscore/its second plug sits in port 2 as its first sits in port 1",
			"first %s, second %s" % [off1, off2])
	else:
		_ok(false, "fourscore/the block draws both plugs")
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [0, 1, 2, 3],
		"fourscore/at 4 its sockets are players 1 to 4")
	# What a shared room replays: the block's second bind, and a socketed pad's bind
	# on its expanded port. Neither may move anything.
	fs.restore_port_connection(sys, 1)
	sys.restore_controller_plug(2, pads[2].call("get_plug"))
	await _wait(2)
	_eq(sys.cabinet_ports_of_plug(plug), [0, 1] as Array[int], "fourscore/a replayed second bind leaves the block where it is")
	_ok(not is_instance_valid((zones[2] as XRToolsSnapZone).picked_up_object) and fs.socket_of(pads[2]) == 2,
		"fourscore/and a replayed socket-3 bind leaves that pad in the Four Score, not in the NES's shut third socket")
	_ok(sys.port_holder(2) == pads[2] and sys.port_holder(3) == pads[3],
		"fourscore/and the console holds the back row's pads on ports 3 and 4")
	_eq(_ids(sys).slice(0, 4), [JOYPAD, JOYPAD, FCEUMM_GAMEPAD, FCEUMM_GAMEPAD],
		"fourscore/players 3 and 4 are fceumm's Gamepad, 1 and 2 the pads as themselves")
	sys.controller_ports().reannounce_all()
	_eq(_ids(sys).slice(0, 4), [JOYPAD, JOYPAD, FCEUMM_GAMEPAD, FCEUMM_GAMEPAD],
		"fourscore/a core start tells the core the same")

	# Socket 3 emptied: port 3 is still the adapter's Gamepad (the game finds the
	# Four Score with the socket empty, as on the hardware).
	(fs.get("_sub_zones")[2] as XRToolsSnapZone).drop_object()
	await _wait(2)
	_eq(_port_of(pads[2]), -1, "fourscore/a pad pulled from socket 3 leaves port 3")
	_eq(_ids(sys)[2], FCEUMM_GAMEPAD, "fourscore/which is still the Four Score's Gamepad")
	fs.restore_socket(2, pads[2])
	await _wait(6)
	_eq(_port_of(pads[2]), 2, "fourscore/and it goes back in")

	fs.set_mode(FourPlayerAdapter.MODE_2P)
	await _wait(1)
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [0, 1, -1, -1],
		"fourscore/at 2 only sockets 1 and 2 reach the console")
	_eq(_ids(sys).slice(0, 4), [JOYPAD, JOYPAD, NONE, NONE], "fourscore/and ports 3 and 4 are nothing")
	sys.controller_ports().reannounce_all()
	_eq(_ids(sys).slice(0, 4), [JOYPAD, JOYPAD, NONE, NONE], "fourscore/still, after a core start")
	var mode_switch := fs.get_node_or_null("Top/ModeSwitch") as VRSlider
	_ok(mode_switch != null and mode_switch.value == 0.0, "fourscore/its switch stands at the rear, 2")
	fs.set_mode(FourPlayerAdapter.MODE_4P)
	await _wait(1)
	_eq([_port_of(pads[2]), _port_of(pads[3])], [2, 3], "fourscore/back at 4, players 3 and 4 again")
	_ok(mode_switch != null and mode_switch.value == 1.0, "fourscore/its switch at the front, 4")

	# TURBO: the A bit through a button that is on comes and goes in pairs of frames.
	var a_held := {"btn": 1 << ControllerBindings.JOYPAD_A | 1 << ControllerBindings.JOYPAD_START,
		"alx": 0, "aly": 0, "arx": 0, "ary": 0}
	var seen: Array = []
	for frame in 8:
		seen.append(int(fs.turbo_frame(a_held, frame)["btn"]) & (1 << ControllerBindings.JOYPAD_A) != 0)
	_eq(seen, [true, true, true, true, true, true, true, true], "fourscore/with TURBO off, A stays held")
	fs.set_turbo("a", true)
	seen.clear()
	var start_kept := true
	for frame in 8:
		var out: Dictionary = fs.turbo_frame(a_held, frame)
		seen.append(int(out["btn"]) & (1 << ControllerBindings.JOYPAD_A) != 0)
		start_kept = start_kept and (int(out["btn"]) & (1 << ControllerBindings.JOYPAD_START) != 0)
	_eq(seen, [true, true, false, false, true, true, false, false],
		"fourscore/TURBO A lets A through two frames in four")
	_ok(start_kept, "fourscore/and leaves every other button alone")
	_ok(int(fs.turbo_frame({"btn": 1 << ControllerBindings.JOYPAD_B}, 2)["btn"]) & (1 << ControllerBindings.JOYPAD_B) != 0,
		"fourscore/B untouched while only A's slide is on")
	# Through the console: the filter is on every port the unit carries.
	var masked := false
	var passed := false
	for i in 8:
		var got: Dictionary = sys.filter_port_input(3, a_held)
		if int(got["btn"]) & (1 << ControllerBindings.JOYPAD_A) == 0:
			masked = true
		else:
			passed = true
		await get_tree().physics_frame
	_ok(masked and passed, "fourscore/a pad on port 4 goes through it")
	_ok(sys.filter_port_input(5, a_held) == a_held, "fourscore/a port it does not carry does not")
	# TURBO A is a latching push button: down while on, a press toggles it.
	var turbo_a := fs.get_node_or_null("Top/TurboA") as VRButton
	var cap := turbo_a.get_node_or_null("ButtonMesh") as Node3D if turbo_a != null else null
	_ok(turbo_a != null and cap != null, "fourscore/TURBO A is a push button with a cap")
	if turbo_a != null and cap != null:
		var down_y := cap.position.y
		_ok(bool(turbo_a.get("_latched_pressed")), "fourscore/held down while its turbo is on")
		turbo_a.button_pressed.emit()
		_ok(not fs.turbo_a and not bool(turbo_a.get("_latched_pressed")), "fourscore/a press lets it back up, turbo off")
		_ok(cap.position.y > down_y + 0.002, "fourscore/its cap rising out of the panel",
			"down %.4f, up %.4f" % [down_y, cap.position.y])
		turbo_a.button_pressed.emit()
		_ok(fs.turbo_a and bool(turbo_a.get("_latched_pressed")), "fourscore/the next press latches it again")
		var turbo_b := fs.get_node_or_null("Top/TurboB") as VRButton
		_ok(turbo_b != null and not fs.turbo_b and not bool(turbo_b.get("_latched_pressed")),
			"fourscore/TURBO B stays up and off meanwhile")
	fs.set_turbo("a", false)

	# The block out: everything lets go.
	(zones[0] as XRToolsSnapZone).drop_object()
	await _wait(2)
	_eq(sys.cabinet_ports_of_plug(plug), [] as Array[int], "fourscore/pulled, the block is in no port")
	_ok((zones[1] as XRToolsSnapZone).enabled, "fourscore/and port 2 is open again")
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [-1, -1, -1, -1],
		"fourscore/its pads reach nothing")
	_eq(_ids(sys).slice(0, 4), [NONE, NONE, NONE, NONE], "fourscore/and the core is told so")
	_ok(fs.get_connected_system() == null, "fourscore/the unit is in no console")
	_ok(sys.filter_port_input(3, a_held) == a_held, "fourscore/its TURBO is off the ports")

	# An NES pad's plug still goes straight into port 2.
	var lone := _make(NES_PAD_SCENE, Vector3(0.5, 1, 1))
	await _wait(4)
	var lone_plug: Node3D = lone.call("get_plug")
	_ok((zones[1] as XRToolsSnapZone).snap_filter.call(lone_plug), "fourscore/a pad fits port 2 again")
	await _clear()


# ── famicom ───────────────────────────────────────────────────────────────────

func _group_famicom() -> void:
	var sys := await _console("famicom", Vector3(0, 1, 0), FCEUMM_PORTS)
	var ports := sys.controller_ports()
	var zone := ports.accessory_zone
	_ok(zone != null, "famicom/the Famicom has its expansion connector")
	if zone == null:
		return
	var seat := sys.get_model().get_node_or_null("Front/AccessorySeat") as Node3D
	_ok(seat != null and zone.global_position.distance_to(seat.global_position) < 0.001,
		"famicom/on its front, at the 15-pin recess")
	_ok(zone.global_basis.z.dot(sys.global_basis.z) > 0.99, "famicom/facing out of the front")
	var hori := _make(HORI_SCENE, Vector3(0, 1, 0.5)) as FamicomFourPlayersAdaptor
	var nes_pad := _make(NES_PAD_SCENE, Vector3(0.6, 1, 1))
	var pads: Array = []
	for i in 4:
		pads.append(_make(GENERIC_PAD_SCENE, Vector3(-0.3 + 0.2 * i, 1, 1)))
	await _wait(4)
	var plug := hori.get_plug()
	var nes_plug: Node3D = nes_pad.call("get_plug")
	_ok(plug != null and zone.snap_filter.call(plug), "famicom/its connector takes the adaptor's 15-pin plug")
	_ok(not zone.snap_filter.call(nes_plug), "famicom/and not an NES pad's")
	var cab0 := ports.zones[0] as XRToolsSnapZone
	_ok(not cab0.snap_filter.call(plug), "famicom/a controller port does not take the 15-pin plug")
	var sock := hori.get("_sub_zones")[0] as XRToolsSnapZone
	_ok(not sock.snap_filter.call(nes_plug), "famicom/an NES pad does not fit the adaptor's sockets")
	_ok(sock.snap_filter.call(pads[0].call("get_plug")), "famicom/the generic pad does")
	var captive0 := sys.port_holder(0)
	_ok(captive0 != null, "famicom/its own pads are on ports 1 and 2")

	for i in 4:
		hori.restore_socket(i, pads[i])
	sys.restore_controller_plug(RetroSystem.ACCESSORY_SLOT, plug)
	await _wait(8)
	_ok(ports.accessory_plug == plug, "famicom/the adaptor's lead is in the expansion port")
	_eq(sys.cabinet_port_of_plug(plug), RetroSystem.ACCESSORY_SLOT, "famicom/saved as the accessory slot")
	_eq(_ids(sys)[4], FCEUMM_FC_4P, "famicom/the core's fifth port is its 4-Player Adapter")
	_eq(_ids(sys).slice(2, 4), [FCEUMM_GAMEPAD, FCEUMM_GAMEPAD], "famicom/players 3 and 4 its Gamepad")
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [2, 3, -1, -1],
		"famicom/sockets 1 and 2 are players 3 and 4; 3 and 4 reach no player")
	_ok(sys.port_holder(0) == captive0, "famicom/and the hardwired pads stay players 1 and 2")
	ports.reannounce_all()
	_eq(_ids(sys).slice(2, 5), [FCEUMM_GAMEPAD, FCEUMM_GAMEPAD, FCEUMM_FC_4P], "famicom/a core start says the same")
	hori.set_mode(FourPlayerAdapter.MODE_2P)
	await _wait(1)
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [2, 3, -1, -1],
		"famicom/at 2 the same: the simple players are sockets 1 and 2 either way")
	_eq(_ids(sys).slice(2, 5), [FCEUMM_GAMEPAD, FCEUMM_GAMEPAD, FCEUMM_FC_4P], "famicom/and the same devices")

	zone.drop_object()
	await _wait(2)
	_ok(ports.accessory_plug == null, "famicom/pulled, the connector is empty")
	_eq(_ids(sys).slice(2, 5), [NONE, NONE, NONE], "famicom/and the core has no adapter or players 3 and 4")
	_eq([_port_of(pads[0]), _port_of(pads[1])], [-1, -1], "famicom/its pads reach nothing")
	_ok(sys.port_holder(0) == captive0, "famicom/the hardwired pads are still there")
	await _clear()


# ── names ─────────────────────────────────────────────────────────────────────

func _group_names() -> void:
	var nes := await _console("nes", Vector3(0, 1, 0), MESEN_PORTS)
	var fs := _make(FOUR_SCORE_SCENE, Vector3(0, 1, 0.5)) as NesFourScore
	var fc := await _console("famicom", Vector3(2, 1, 0), MESEN_PORTS)
	var hori := _make(HORI_SCENE, Vector3(2, 1, 0.5)) as FamicomFourPlayersAdaptor
	await _wait(4)
	nes.restore_controller_plug(0, fs.get_plug())
	fc.restore_controller_plug(RetroSystem.ACCESSORY_SLOT, hori.get_plug())
	await _wait(4)
	_eq(_ids(nes).slice(2, 4), [MESEN_STANDARD, MESEN_STANDARD],
		"names/Mesen's Four Score players 3 and 4 are its Standard Controller")
	_eq(_ids(fc)[4], MESEN_FC_4P, "names/its Famicom adapter is its Four Player Adapter")
	await _clear()


# ── satellite ─────────────────────────────────────────────────────────────────

func _group_satellite() -> void:
	var sim_before: bool = AppPrefs.power_simulation
	AppPrefs.power_simulation = false
	var sys := await _console("nes", Vector3(0, 1, 0), FCEUMM_PORTS)
	var rx := _make(SATELLITE_RX_SCENE, Vector3(0.3, 1, 0.4)) as NesSatelliteReceiver
	# The transmitter 1.5 m in front of the console, its lens (-Z) toward it.
	var tx := _make(SATELLITE_SCENE, Vector3(0, 0.99, 1.5)) as NesSatellite
	var pads: Array = []
	for i in 4:
		pads.append(_make(NES_PAD_SCENE, Vector3(-0.3 + 0.2 * i, 1, 2.2)))
	await _wait(6)
	_ok(tx.receiver() == null, "satellite/no receiver seated, nothing to pair with")
	var zones: Array = sys.controller_ports().zones
	_ok((zones[0] as XRToolsSnapZone).snap_filter.call(rx), "satellite/the receiver goes in at port 1")
	_ok(not (zones[1] as XRToolsSnapZone).snap_filter.call(rx), "satellite/and not at port 2")
	sys.restore_controller_plug(0, rx)
	await _wait(4)
	_eq(sys.cabinet_ports_of_plug(rx), [0, 1] as Array[int], "satellite/seated, the receiver fills both ports")
	_ok(tx.receiver() == rx and rx.transmitter == tx, "satellite/the transmitter pairs with it")
	for i in 2:
		tx.restore_socket(i, pads[i])
	await _wait(6)
	_eq([_port_of(pads[0]), _port_of(pads[1])], [0, 1], "satellite/sockets 1 and 2 are players 1 and 2")
	_eq(_ids(sys).slice(2, 4), [NONE, NONE], "satellite/with 3 and 4 empty it is a two-player adapter")
	tx.restore_socket(2, pads[2])
	await _wait(6)
	_eq(_port_of(pads[2]), 2, "satellite/a controller in socket 3 is player 3")
	_eq(_ids(sys).slice(2, 4), [FCEUMM_GAMEPAD, FCEUMM_GAMEPAD], "satellite/and makes it a four-player adapter")

	var a_held := {"btn": 1 << ControllerBindings.JOYPAD_A, "alx": 0, "aly": 0, "arx": 0, "ary": 0}
	_ok(not tx.is_powered() and int(sys.filter_port_input(2, a_held)["btn"]) == 0,
		"satellite/switched off, the console hears a released pad")
	var power := tx.get_node_or_null("Top/PowerSwitch") as VRButton
	_ok(power != null, "satellite/it has a power switch")
	if power != null:
		power.button_pressed.emit()
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(tx.is_powered(), "satellite/a press switches it on")
	var led := tx.get_node_or_null("Top/PowerLed") as MeshInstance3D
	_ok(led != null and (led.material_override as StandardMaterial3D).emission_enabled, "satellite/its red LED lights")
	_ok(tx.link_up(), "satellite/in range and in the beam, the link is up")
	_eq(int(sys.filter_port_input(2, a_held)["btn"]), 1 << ControllerBindings.JOYPAD_A, "satellite/and the press gets through")

	# Something in the way.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.05)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	_spawned.append(wall)
	wall.global_position = Vector3(0, 1.0, 0.8)
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(not tx.link_up() and int(sys.filter_port_input(2, a_held)["btn"]) == 0,
		"satellite/a wall between the lenses cuts it")
	_eq(_port_of(pads[2]), 2, "satellite/without re-plugging anything")
	wall.global_position = Vector3(3, 1.0, 0.8)
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(tx.link_up(), "satellite/taken away, the link is back")
	# Out of the beam: turned 90 degrees.
	tx.global_basis = Basis(Vector3.UP, PI * 0.5)
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(not tx.link_up(), "satellite/turned away, out of the beam")
	tx.global_basis = Basis.IDENTITY
	# Past 15 feet.
	tx.global_position = Vector3(0, 0.99, 5.2)
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(not tx.link_up(), "satellite/past 15 feet, nothing")
	tx.global_position = Vector3(0, 0.99, 1.5)
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(tx.link_up(), "satellite/back in range")

	# TURBO as the Four Score's, through the link.
	var turbo := tx.get_node_or_null("Top/TurboA") as VRButton
	if turbo != null:
		turbo.button_pressed.emit()
	_ok(tx.turbo_a and int(tx.turbo_frame(a_held, 2)["btn"]) == 0, "satellite/TURBO A latches and masks A")
	tx.set_turbo("a", false)

	# GUN: sockets 3 and 4 are not carried.
	tx.set_gun_mode(true)
	await _wait(2)
	_eq(_port_of(pads[2]), -1, "satellite/at GUN socket 3 reaches nothing")
	_eq(_ids(sys).slice(2, 4), [NONE, NONE], "satellite/and it is a two-player adapter")
	tx.set_gun_mode(false)
	await _wait(2)
	_eq(_port_of(pads[2]), 2, "satellite/back at CTLR, player 3 again")

	# Seven minutes unused.
	tx.set("_idle", NesSatellite.AUTO_OFF_SECONDS - 0.01)
	await _wait(3)
	_ok(not tx.is_powered(), "satellite/seven minutes unused, it turns itself off")
	await _wait(NesSatellite.LOOK_TICKS + 2)
	_ok(not tx.link_up(), "satellite/and the link goes with it")

	# The cells. Its own supply is the six C cells under it; with none in, that is
	# dead (a room with no outlet powers everything anyway, so this asks the supply
	# itself, the room's leniency left out).
	var bay := CellSlots.of(tx)
	_eq(bay.seats().size() if bay != null else 0, 6, "satellite/its bay takes six cells")
	_eq(CellSlots.size_of_seat(bay.seats()[0]) if bay != null and not bay.seats().is_empty() else "",
		"C", "satellite/C cells")
	var supply := PowerInput.of(tx)
	_ok(supply != null and not bool(supply.own_supply()["supplied"]),
		"satellite/with none in, its own supply is dead")

	# Saved: the transmitter (its switches, its pads) and the receiver (its seat).
	var sp := ScenePersistence.new()
	tx.set_gun_mode(true)
	var ids := {sys: 7, tx: 1, rx: 2, pads[0]: 8, pads[1]: 9, pads[2]: 10}
	var trec: Dictionary = sp.serialize_node(tx, 1, ids)
	var rrec: Dictionary = sp.serialize_node(rx, 2, ids)
	_eq(str(trec.get("type", "")), "nes_satellite", "satellite/the transmitter has an entry of its own")
	_ok(bool(trec.get("gun_mode", false)) and int(trec.get("port_index", 0)) == -1,
		"satellite/with its mode switch, and no seat of its own")
	_eq(trec.get("sockets"), [8, 9, 10, null], "satellite/and its pads")
	_eq(str(rrec.get("type", "")), "nes_satellite_receiver", "satellite/the receiver has one too")
	_ok(rrec.get("system") == 7 and int(rrec.get("port_index", -1)) == 0, "satellite/naming its console and port")
	var room: Array = [trec, rrec, sp.serialize_node(sys, 7, ids), sp.serialize_node(pads[0], 8, ids),
		sp.serialize_node(pads[1], 9, ids), sp.serialize_node(pads[2], 10, ids)]
	_eq(ScenePersistence._objects_validation_error(room), "", "satellite/and the room's entries validate")
	(zones[0] as XRToolsSnapZone).drop_object()
	await _wait(3)
	_ok(tx.receiver() == null and _port_of(pads[0]) == -1, "satellite/the receiver pulled, the transmitter lets go")
	var back := sp.deserialize_object(rrec) as NesSatelliteReceiver
	_ok(back != null, "satellite/the receiver is rebuilt")
	if back != null:
		add_child(back)
		_spawned.append(back)
		await _wait(2)
		sp._restore_satellite_receiver(self, 2, back, {7: sys}, rrec)
		await _wait(4)
		_ok(back.is_plugged_in() and tx.receiver() == back, "satellite/seated again, and the transmitter pairs with it")
	AppPrefs.power_simulation = sim_before
	await _clear()


# ── psmultitap ────────────────────────────────────────────────────────────────

func _group_psmultitap() -> void:
	var sys := await _console("psx", Vector3(0, 1, 0), PCSX_PORTS)
	var ports := sys.controller_ports()
	var zones: Array = ports.zones
	var card_slots: Array = sys.memcard_slots()
	var tap := _make(PS_MULTITAP_SCENE, Vector3(0, 1, 0.6)) as PsMultitap
	var tap2 := _make(PS_MULTITAP_SCENE, Vector3(0.5, 1, 0.6)) as PsMultitap
	var pads: Array = []
	for i in 4:
		pads.append(_make(PS1_PAD_SCENE, Vector3(-0.3 + 0.2 * i, 1, 1.2)))
	var lone := _make(PS1_PAD_SCENE, Vector3(0.6, 1, 1.2))
	var card := _make(MEMORY_CARD_SCENE, Vector3(-0.4, 1, 0.4))
	var card_b := _make(MEMORY_CARD_SCENE, Vector3(-0.5, 1, 0.4))
	await _wait(4)
	var plug := tap.get_plug()
	_ok(plug != null and plug.covers_card_slot, "psmultitap/its connector fills a card slot as well as a port")
	if plug == null:
		await _clear()
		return

	# A card in the console's slot 1 is in the connector's way.
	sys.memcards().restore_memory_card(card, 0)
	await _wait(2)
	_ok(not (zones[0] as XRToolsSnapZone).snap_filter.call(plug), "psmultitap/a card in slot 1 keeps it out of port 1")
	# Taken out and carried off, as a hand does: let go beside the console, the two
	# slots would hand it to each other, so they are shut while it leaves.
	for z: Variant in card_slots:
		(z as XRToolsSnapZone).enabled = false
	(card_slots[0] as XRToolsSnapZone).drop_object()
	card.freeze = true
	card.global_position = Vector3(-2.0, 1.0, 2.0)
	await _wait(2)
	for z: Variant in card_slots:
		(z as XRToolsSnapZone).enabled = true
	_ok((zones[0] as XRToolsSnapZone).snap_filter.call(plug), "psmultitap/taken out, it fits")

	# A pad in the console's own port 2 first.
	sys.restore_controller_plug(1, lone.call("get_plug"))
	await _wait(3)
	_eq(_port_of(lone), 1, "psmultitap/a pad in port 2 is player 2")

	sys.restore_controller_plug(0, plug)
	for i in 4:
		tap.restore_socket(i, pads[i])
	await _wait(8)
	_ok(not (card_slots[0] as XRToolsSnapZone).enabled and sys.is_card_slot_covered(0),
		"psmultitap/seated in port 1, it shuts card slot 1")
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [0, 1, 2, 3],
		"psmultitap/sockets A-D are players 1-4")
	_eq(_port_of(lone), 4, "psmultitap/and the console's port 2 moves to libretro port 4, as pcsx_rearmed reads it")
	_ok(sys.port_holder(4) == lone and sys.cabinet_port_of(lone) == 1,
		"psmultitap/held there, still saved as port 2's")
	_eq(sys.all_forced_options("pcsx_rearmed_libretro").get("pcsx_rearmed_multitap", ""), "port 1",
		"psmultitap/pcsx_rearmed is told its multitap is in port 1")
	_ok(not sys.all_forced_options("mednafen_psx_hw").has("pcsx_rearmed_multitap"),
		"psmultitap/no other core is told anything")
	_eq(_ids(sys).slice(0, 5), [1, 1, 1, 1, 1], "psmultitap/five pads, five standard pads")
	(tap.get("_sub_zones")[1] as XRToolsSnapZone).drop_object()
	await _wait(2)
	_eq(_ids(sys)[1], NONE, "psmultitap/an empty socket is no pad")
	tap.restore_socket(1, pads[1])
	await _wait(6)
	sys.controller_ports().reannounce_all()
	_eq(_ids(sys).slice(0, 5), [1, 1, 1, 1, 1], "psmultitap/a core start says the same")

	# Slot A is the console's card slot 1; slot B is no core's.
	var card_a := _make(MEMORY_CARD_SCENE, Vector3(-0.6, 1, 0.8))
	await _wait(2)
	tap.restore_card(0, card_a)
	tap.restore_card(1, card_b)
	await _wait(2)
	_ok(sys.memcards().get_snapped_memcard(0) == card_a, "psmultitap/a card in slot A is the console's card 1")
	_ok(sys.memcards().get_snapped_memcard(1) == null, "psmultitap/a card in slot B is not the console's card 2")

	# Saved: the tap holds its cards; the console does not claim slot A's.
	var sp := ScenePersistence.new()
	var ids := {sys: 7, tap: 1, card_a: 20, card_b: 21, pads[0]: 8, pads[1]: 9, pads[2]: 10, pads[3]: 11, lone: 12}
	var trec: Dictionary = sp.serialize_node(tap, 1, ids)
	var srec: Dictionary = sp.serialize_node(sys, 7, ids)
	_eq(str(trec.get("type", "")), "ps_multitap", "psmultitap/it has an entry of its own")
	_ok(trec.get("system") == 7 and int(trec.get("port_index", -1)) == 0, "psmultitap/naming its console and port 1")
	_eq(trec.get("tap_cards"), [20, 21, null, null], "psmultitap/and the card in each of its slots")
	_eq(trec.get("sockets"), [8, 9, 10, 11], "psmultitap/and its pads")
	_ok(srec.get("memcard") == null, "psmultitap/the console does not claim slot A's card as its own")
	var lone_rec: Dictionary = sp.serialize_node(lone, 12, ids)
	_eq(int(lone_rec.get("port_index", -1)), 1, "psmultitap/the moved pad is saved in port 2")
	var room: Array = [trec, srec, lone_rec, sp.serialize_node(card_a, 20, ids), sp.serialize_node(card_b, 21, ids)]
	for p: int in 4:
		room.append(sp.serialize_node(pads[p], 8 + p, ids))
	_eq(ScenePersistence._objects_validation_error(room), "", "psmultitap/and the room's entries validate")

	# A second tap in port 2: players 5-8.
	(zones[1] as XRToolsSnapZone).drop_object()
	await _wait(2)
	sys.restore_controller_plug(1, tap2.get_plug())
	await _wait(4)
	_eq(tap2.call("_routes"), [4, 5, 6, 7] as Array[int], "psmultitap/a second tap in port 2 is players 5-8")
	_eq(sys.all_forced_options("pcsx_rearmed_libretro").get("pcsx_rearmed_multitap", ""), "ports 1 and 2",
		"psmultitap/both ports, the option says")
	_ok(not (card_slots[1] as XRToolsSnapZone).enabled, "psmultitap/and card slot 2 is under it")

	# The first tap out: the second is players 2-5, port 2's own numbering again.
	(zones[0] as XRToolsSnapZone).drop_object()
	await _wait(4)
	_eq(tap2.call("_routes"), [1, 2, 3, 4] as Array[int], "psmultitap/the first one out, the second is players 2-5")
	_eq(sys.all_forced_options("pcsx_rearmed_libretro").get("pcsx_rearmed_multitap", ""), "port 2",
		"psmultitap/and the option says port 2")
	_ok((card_slots[0] as XRToolsSnapZone).enabled and not sys.is_card_slot_covered(0), "psmultitap/card slot 1 opens again")
	_ok(sys.memcards().get_snapped_memcard(0) == null, "psmultitap/and slot A's card is no longer the console's")
	_eq([_port_of(pads[0]), _port_of(pads[3])], [-1, -1], "psmultitap/its pads reach nothing")
	(zones[1] as XRToolsSnapZone).drop_object()
	await _wait(3)
	_eq(sys.all_forced_options("pcsx_rearmed_libretro").get("pcsx_rearmed_multitap", ""), "disabled",
		"psmultitap/no tap, no multitap")
	await _clear()


# ── ps2multitap ───────────────────────────────────────────────────────────────

func _group_ps2multitap() -> void:
	var sys := await _console("ps2", Vector3(0, 1, 0), LRPS2_PORTS)
	var ports := sys.controller_ports()
	var zones: Array = ports.zones
	var card_slots: Array = sys.memcard_slots()
	var tap := _make(PS2_MULTITAP_SCENE, Vector3(0, 1, 0.6)) as Ps2Multitap
	var tap2 := _make(PS2_MULTITAP_SCENE, Vector3(0.5, 1, 0.6)) as Ps2Multitap
	var pads: Array = []
	for i in 4:
		pads.append(_make(PS1_PAD_SCENE, Vector3(-0.3 + 0.2 * i, 1, 1.2)))
	var lone := _make(PS1_PAD_SCENE, Vector3(0.6, 1, 1.2))
	await _wait(4)
	var plug := tap.get_plug()
	_ok(plug != null and plug.covers_card_slot, "ps2multitap/its connector fills a card slot as well as a port")
	_ok(tap.is_in_group("ps2_multitap") and not tap.is_in_group("ps_multitap"),
		"ps2multitap/it counts as a PS2 tap, not a PlayStation one")
	_eq(card_slots.size(), 2, "ps2multitap/the PS2 has two card slots")
	if plug == null or card_slots.size() < 2:
		await _clear()
		return

	# The box: A and B out of one long face, C and D out of the other, the cord
	# out of the -X end. By sign, from the nodes the hands meet.
	var sz: Array = tap.get("_sub_zones")
	var a_out := (sz[0] as Node3D).global_basis.z
	var c_out := (sz[2] as Node3D).global_basis.z
	_ok(absf(a_out.dot(Vector3.BACK)) > 0.9, "ps2multitap/socket A faces along Z")
	_ok(a_out.dot(c_out) < -0.9, "ps2multitap/C faces the other way from A")
	_ok(absf((sz[0] as Node3D).global_position.z - (sz[1] as Node3D).global_position.z) < 0.001,
		"ps2multitap/A and B share a face")
	var attach := tap.get_node("CableAttachPoint") as Node3D
	_ok((-attach.global_basis.z).dot(Vector3.LEFT) > 0.99 and attach.position.x < -0.06,
		"ps2multitap/the cord leaves the -X end")

	sys.restore_controller_plug(1, lone.call("get_plug"))
	await _wait(3)
	sys.restore_controller_plug(0, plug)
	for i in 4:
		tap.restore_socket(i, pads[i])
	await _wait(8)
	_ok(sys.is_card_slot_covered(0), "ps2multitap/seated in port 1, it shuts card slot 1")
	_eq([_port_of(pads[0]), _port_of(pads[1]), _port_of(pads[2]), _port_of(pads[3])], [0, 1, 2, 3],
		"ps2multitap/sockets A-D are players 1-4")
	_eq(_port_of(lone), 4, "ps2multitap/and the console's port 2 moves to libretro port 4, as both cores lay it out")
	_ok(sys.cabinet_port_of(lone) == 1, "ps2multitap/still saved as port 2's")
	_eq(sys.all_forced_options("pcsx2_libretro").get("pcsx2_multitap", ""), "port1",
		"ps2multitap/LRPS2 is told its multitap is in port 1")
	_eq(sys.all_forced_options("pcee2_libretro").get("pcsx2_multitap", ""), "port1",
		"ps2multitap/and pcee2, the same key")
	_ok(not sys.all_forced_options("play_libretro").has("pcsx2_multitap"), "ps2multitap/Play! is told nothing")
	_eq(_ids(sys).slice(0, 5), [1, 1, 1, 1, 1], "ps2multitap/five pads, five DualShock 2s")
	(sz[1] as XRToolsSnapZone).drop_object()
	await _wait(2)
	_eq(_ids(sys)[1], NONE, "ps2multitap/an empty socket is no pad")
	tap.restore_socket(1, pads[1])
	await _wait(6)

	# Cards: a PS2 card in slot A is the console's card 1; a PlayStation card does not go in.
	var card_a := _make(PS2_CARD_SCENE, Vector3(-0.6, 1, 0.8))
	var ps1_card := _make(MEMORY_CARD_SCENE, Vector3(-0.7, 1, 0.8))
	await _wait(2)
	var card_zone := (tap.get("_card_zones") as Array)[0] as XRToolsSnapZone
	_ok(not card_zone.snap_filter.call(ps1_card), "ps2multitap/a PlayStation card does not fit its slots")
	_ok(card_zone.snap_filter.call(card_a), "ps2multitap/a PS2 card does")
	tap.restore_card(0, card_a)
	await _wait(2)
	_ok(sys.memcards().get_snapped_memcard(0) == card_a, "ps2multitap/a card in slot A is the console's card 1")

	var sp := ScenePersistence.new()
	var ids := {sys: 7, tap: 1, card_a: 20, pads[0]: 8, pads[1]: 9, pads[2]: 10, pads[3]: 11, lone: 12}
	var trec: Dictionary = sp.serialize_node(tap, 1, ids)
	_eq(str(trec.get("type", "")), "ps2_multitap", "ps2multitap/it has an entry of its own")
	_eq(trec.get("tap_cards"), [20, null, null, null], "ps2multitap/with its card")
	var room: Array = [trec, sp.serialize_node(sys, 7, ids), sp.serialize_node(lone, 12, ids),
		sp.serialize_node(card_a, 20, ids)]
	for p: int in 4:
		room.append(sp.serialize_node(pads[p], 8 + p, ids))
	_eq(ScenePersistence._objects_validation_error(room), "", "ps2multitap/and the room's entries validate")
	var back := sp._load_four_player(trec)
	_ok(back is Ps2Multitap, "ps2multitap/and its entry builds a PS2 tap again")
	back.free()

	# A second tap in port 2: players 5-8, both ports.
	(zones[1] as XRToolsSnapZone).drop_object()
	await _wait(2)
	sys.restore_controller_plug(1, tap2.get_plug())
	await _wait(4)
	_eq(tap2.call("_routes"), [4, 5, 6, 7] as Array[int], "ps2multitap/a second tap in port 2 is players 5-8")
	_eq(sys.all_forced_options("pcsx2_libretro").get("pcsx2_multitap", ""), "both", "ps2multitap/both, the option says")
	(zones[0] as XRToolsSnapZone).drop_object()
	await _wait(4)
	_eq(tap2.call("_routes"), [1, 2, 3, 4] as Array[int], "ps2multitap/the first one out, the second is players 2-5")
	_eq(sys.all_forced_options("pcsx2_libretro").get("pcsx2_multitap", ""), "port2", "ps2multitap/port 2")
	(zones[1] as XRToolsSnapZone).drop_object()
	await _wait(3)
	_eq(sys.all_forced_options("pcsx2_libretro").get("pcsx2_multitap", ""), "disabled", "ps2multitap/no tap, disabled")

	# The PlayStation's tap in a PS2: socket A only, nothing moved, the option off.
	var ps1_tap := _make(PS_MULTITAP_SCENE, Vector3(-0.5, 1, 0.6)) as PsMultitap
	var p1 := _make(PS1_PAD_SCENE, Vector3(-0.3, 1, 1.6))
	var p2 := _make(PS1_PAD_SCENE, Vector3(-0.1, 1, 1.6))
	await _wait(4)
	sys.restore_controller_plug(1, lone.call("get_plug"))
	sys.restore_controller_plug(0, ps1_tap.get_plug())
	ps1_tap.restore_socket(0, p1)
	ps1_tap.restore_socket(1, p2)
	await _wait(8)
	_eq([_port_of(p1), _port_of(p2), _port_of(lone)], [0, -1, 1],
		"ps2multitap/a SCPH-1070 in a PS2 is socket A alone, port 2 its own")
	_eq(sys.all_forced_options("pcsx2_libretro").get("pcsx2_multitap", ""), "disabled",
		"ps2multitap/and turns no PS2 multitap on")
	await _clear()

	# And the PS2's tap in a PlayStation: the same.
	var psx := await _console("psx", Vector3(0, 1, 0), PCSX_PORTS)
	var tap3 := _make(PS2_MULTITAP_SCENE, Vector3(0, 1, 0.6)) as Ps2Multitap
	var q1 := _make(PS1_PAD_SCENE, Vector3(-0.3, 1, 1.2))
	var q2 := _make(PS1_PAD_SCENE, Vector3(-0.1, 1, 1.2))
	await _wait(4)
	psx.restore_controller_plug(0, tap3.get_plug())
	tap3.restore_socket(0, q1)
	tap3.restore_socket(1, q2)
	await _wait(8)
	_eq([_port_of(q1), _port_of(q2)], [0, -1], "ps2multitap/a SCPH-10090 in a PlayStation is socket A alone")
	_eq(psx.all_forced_options("pcsx_rearmed_libretro").get("pcsx_rearmed_multitap", ""), "disabled",
		"ps2multitap/and pcsx_rearmed's multitap stays off")
	await _clear()


# ── unwired ───────────────────────────────────────────────────────────────────

func _group_unwired() -> void:
	var nes := await _console("nes", Vector3(0, 1, 0), FCEUMM_PORTS)
	var fc := await _console("famicom", Vector3(2, 1, 0), FCEUMM_PORTS)
	nes.controller_ports().reannounce_all()
	fc.controller_ports().reannounce_all()
	_eq(_ids(nes).slice(2, 4), [NONE, NONE], "unwired/an NES with nothing on ports 3 and 4 says so")
	_eq(_ids(fc).slice(2, 5), [NONE, NONE, NONE], "unwired/a Famicom with nothing in its expansion port says so")
	_ok(fc.port_holder(0) != null, "unwired/its own pads untouched")
	var fs := _make(FOUR_SCORE_SCENE, Vector3(0, 1, 0.5)) as NesFourScore
	await _wait(4)
	nes.restore_controller_plug(0, fs.get_plug())
	await _wait(3)
	nes.controller_ports().reannounce_all()
	_eq(_ids(nes).slice(2, 4), [FCEUMM_GAMEPAD, FCEUMM_GAMEPAD], "unwired/a Four Score at 4 overrides it")
	await _clear()


# ── save ──────────────────────────────────────────────────────────────────────

func _group_save() -> void:
	var sys := await _console("nes", Vector3(0, 1, 0), FCEUMM_PORTS)
	var fs := _make(FOUR_SCORE_SCENE, Vector3(0, 1, 0.5)) as NesFourScore
	var pad1 := _make(NES_PAD_SCENE, Vector3(-0.2, 1, 1))
	var pad3 := _make(NES_PAD_SCENE, Vector3(0.2, 1, 1))
	await _wait(4)
	fs.restore_socket(0, pad1)
	fs.restore_socket(2, pad3)
	sys.restore_controller_plug(0, fs.get_plug())
	await _wait(8)
	fs.set_turbo("b", true)
	var sp := ScenePersistence.new()
	var ids := {sys: 7, pad1: 8, pad3: 9, fs: 1}
	var rec: Dictionary = sp.serialize_node(fs, 1, ids)
	_eq(str(rec.get("type", "")), "nes_four_score", "save/a Four Score has an entry of its own")
	_eq(rec.get("system"), 7, "save/naming its console")
	_eq(int(rec.get("port_index", -1)), 0, "save/and the first port its block fills")
	_eq(int(rec.get("tap_mode", 0)), 4, "save/at 4")
	_eq(rec.get("sockets"), [8, null, 9, null], "save/with each socket's pad, null where empty")
	_ok(bool(rec.get("turbo_b", false)) and not bool(rec.get("turbo_a", true)), "save/and its TURBO buttons")
	var pad_rec: Dictionary = sp.serialize_node(pad3, 9, ids)
	_eq(int(pad_rec.get("port_index", 0)), -1, "save/a pad in it names no console port of its own")
	var room: Array = [rec, pad_rec, sp.serialize_node(sys, 7, ids), sp.serialize_node(pad1, 8, ids)]
	_eq(ScenePersistence._objects_validation_error(room), "", "save/and the room's entries validate")

	(sys.controller_ports().zones[0] as XRToolsSnapZone).drop_object()
	for z: Variant in fs.get("_sub_zones"):
		(z as XRToolsSnapZone).drop_object()
	await _wait(2)
	fs.queue_free()
	await _wait(3)
	var back := sp.deserialize_object(rec) as NesFourScore
	_ok(back != null, "save/it is rebuilt as a Four Score")
	if back == null:
		await _clear()
		return
	_ok(back.turbo_b and not back.turbo_a and back.mode == 4, "save/its switches as they were")
	add_child(back)
	_spawned.append(back)
	await _wait(2)
	sp._restore_four_player(self, 1, back, {7: sys, 8: pad1, 9: pad3}, rec)
	await _wait(10)
	_eq(sys.cabinet_ports_of_plug(back.get_plug()), [0, 1] as Array[int], "save/its block back in both ports")
	_eq([_port_of(pad1), _port_of(pad3)], [0, 2], "save/players 1 and 3 back in their sockets")
	_eq(_ids(sys)[2], FCEUMM_GAMEPAD, "save/and the core told of players 3 and 4")

	# The Famicom's, through the accessory slot.
	var fc := await _console("famicom", Vector3(2, 1, 0), FCEUMM_PORTS)
	var hori := _make(HORI_SCENE, Vector3(2, 1, 0.5)) as FamicomFourPlayersAdaptor
	await _wait(4)
	fc.restore_controller_plug(RetroSystem.ACCESSORY_SLOT, hori.get_plug())
	hori.set_mode(FourPlayerAdapter.MODE_2P)
	await _wait(3)
	var hrec: Dictionary = sp.serialize_node(hori, 2, {fc: 11})
	_eq(str(hrec.get("type", "")), "famicom_four_players_adaptor", "save/the Famicom adaptor has its own entry")
	_eq(int(hrec.get("port_index", -1)), RetroSystem.ACCESSORY_SLOT, "save/its lead in the accessory slot")
	_eq(int(hrec.get("tap_mode", 0)), 2, "save/at 2")
	fc.get_node("AccessoryPort").call("drop_object")
	await _wait(2)
	hori.queue_free()
	await _wait(3)
	var hback := sp.deserialize_object(hrec) as FamicomFourPlayersAdaptor
	_ok(hback != null and hback.mode == 2, "save/it is rebuilt at 2")
	if hback != null:
		add_child(hback)
		_spawned.append(hback)
		await _wait(2)
		sp._restore_four_player(self, 2, hback, {11: fc}, hrec)
		await _wait(6)
		_ok(fc.controller_ports().accessory_plug == hback.get_plug(), "save/with its lead back in the expansion port")
		_eq(_ids(fc)[4], FCEUMM_FC_4P, "save/and the core told of the adapter")
	await _clear()
