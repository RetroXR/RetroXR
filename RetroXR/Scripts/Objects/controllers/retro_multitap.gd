## RetroMultitap — a multitap adapter. It plugs into a console controller port
## with the same cable + plug as a controller, and re-exposes four controller
## ports on its own body. A controller snapped into sub-port k feeds the console
## at the multitap's base port + k, so one physical port fans out to up to four
## players. The base port is whichever console port the multitap's plug occupies
## (plug it into port 0 for the netplay-safe 0..3 mapping).
##
## It has the Super Multitap's SELECT switch (mode):
##   • 5P — a multitap. The tap's own plug announces "multitap" on its port, which
##     a core that knows one resolves to its device (bsnes: "Multitap" on the
##     Super NES's second port, polling libretro ports 1-4 as players 2-5); a
##     core that knows none gets a plain pad there. All four sockets are live, and
##     the first does not announce over the tap.
##   • 2P — an extension cord. The tap is transparent (RETRO_DEVICE_NONE) and only
##     the first socket is live: its pad is the pad on the port the tap is in,
##     announced as itself.
## Flipping the switch while plugged in re-announces the port and re-routes the
## sockets on the spot.
##
## A mod that dresses a tap in a real model places the sockets and the switch on
## it: override _socket_transform, _draws_ports and _build_switch.
class_name RetroMultitap
extends XRToolsPickable


const CONTROLLER_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")
const RETRO_DEVICE_NONE := 0
const RETRO_DEVICE_JOYPAD := 1
const SUB_PORTS := 4
const MODE_2P := 2
const MODE_5P := 5
## The name a core lists its multitap under (bsnes: "Multitap").
const MULTITAP_NAME := "multitap"

## The SELECT switch. 5P by default: a tap is spawned to add players.
@export var mode: int = MODE_5P

## Reported to the console when the multitap's own plug seats: the multitap at
## 5P, nothing at 2P (set from `mode`; see _apply_device).
var device_type: int = RETRO_DEVICE_JOYPAD
## The names the console matches against the core's devices for this port.
var device_names := PackedStringArray([MULTITAP_NAME])

# Port connection state (the console port this multitap's plug occupies).
var _connected_system: RetroSystem = null
var _base_port: int = -1

# Cable (same pattern as RetroController / RetroKeyboard).
var _cable_instance: Node3D = null


## The captive cable spawned for this adapter, or null. Parented to the scene
## root, so the storage box asks for it to unplug and free it with the adapter.
func cable_instance() -> Node3D:
	return _cable_instance
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length: float = 0.0
var _pending_port_restore: Dictionary = {}

# Sub-port snap zones and the plug currently seated in each (or null).
var _sub_zones: Array = []
var _sub_plugs: Array = [null, null, null, null]
# Which sub-ports are bound to the console now (so a flip unbinds exactly those).
var _bound: Array = [false, false, false, false]
var _labels: Array = []
var _switch: VRSlider = null

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _ports_root: Node3D = $Ports


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	_apply_device()
	_build_ports()
	_build_switch()
	_update_labels()
	_spawn_cable()
	grabbed.connect(func(_p: Node3D, _by: Node3D) -> void: pass)


## Four sub-port snap zones across the FRONT face of the adapter, each with a
## recessed port box and a number label below it — matching the console's own
## controller ports (system.tscn ControllerPort#).
const PORT_XS := [-0.09, -0.03, 0.03, 0.09]  # front-face X positions (meters)
const PORT_FACE_Z := 0.03                     # front face of the 0.06-deep body

func _build_ports() -> void:
	var recess_mat := StandardMaterial3D.new()
	recess_mat.albedo_color = Color(0.08, 0.08, 0.08)
	for i in range(SUB_PORTS):
		var zone: XRToolsSnapZone = SNAP_ZONE_SCENE.instantiate()
		zone.snap_require = "controller_plug"
		zone.grab_distance = 0.03
		_ports_root.add_child(zone)
		zone.transform = _socket_transform(i)

		var lbl: Label3D = null
		if _draws_ports():
			# Recessed port box on the front face (dark inset, like the console).
			var recess := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.018, 0.012, 0.005)
			recess.mesh = box
			recess.set_surface_override_material(0, recess_mat)
			zone.add_child(recess)

			# Number label just below the port, billboarded to face the player.
			lbl = Label3D.new()
			lbl.text = str(i + 1)
			lbl.pixel_size = 0.001
			lbl.font_size = 14
			lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			lbl.position = Vector3(0, -0.018, 0.006)
			zone.add_child(lbl)
		_labels.append(lbl)

		var idx := i
		zone.has_picked_up.connect(func(obj: Node3D) -> void: _on_sub_snapped(idx, obj))
		# has_dropped takes NO argument (see the same note in system.gd). Taking
		# one aborted every unplug, so a pad pulled from a sub-port kept driving
		# its console port. _sub_plugs already remembers what was seated.
		zone.has_dropped.connect(func() -> void: _on_sub_released(idx))
		_sub_zones.append(zone)


## Where sub-port `i`'s socket is, in the Ports node's frame (its +Z out of the
## socket). The plain box's front face; a mod's model puts them on its own.
func _socket_transform(i: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(PORT_XS[i], 0.006, PORT_FACE_Z))


## Whether the sockets are drawn (a dark inset and a number): the plain box's
## are, a modeled tap's are its own.
func _draws_ports() -> bool:
	return true


## The SELECT switch: a two-position slide on top of the box, 2P at its left end
## and 5P at its right. A mod's model builds its own (set_mode is what it calls).
const SWITCH_POS := Vector3(-0.115, 0.047, 0.012)
const SWITCH_THROW := 0.008

func _build_switch() -> void:
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.55, 0.55, 0.6)
	var knob := MeshInstance3D.new()
	knob.name = "SelectKnob"
	var knob_mesh := BoxMesh.new()
	knob_mesh.size = Vector3(0.006, 0.004, 0.008)
	knob.mesh = knob_mesh
	knob.material_override = cap
	add_child(knob)
	knob.position = SWITCH_POS + Vector3(SWITCH_THROW * (0.5 if mode == MODE_5P else -0.5), 0.0, 0.0)
	var slider := VRSlider.new()
	slider.name = "SelectSwitch"
	slider.axis_local = Vector3(1.0, 0.0, 0.0)
	slider.travel = SWITCH_THROW
	slider.steps = 2
	slider.value = 1.0 if mode == MODE_5P else 0.0
	slider.collision_layer = 1 | (1 << 20)
	slider.engage_radius = 0.016
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SWITCH_THROW + 0.008, 0.008, 0.012)
	col.shape = box
	slider.add_child(col)
	add_child(slider)
	slider.position = SWITCH_POS
	slider.set_knob_mesh(knob)
	for end: Array in [["2P", -1.0], ["5P", 1.0]]:
		var word := Label3D.new()
		word.text = str(end[0])
		word.pixel_size = 0.0008
		word.font_size = 12
		word.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		word.position = SWITCH_POS + Vector3(float(end[1]) * (SWITCH_THROW * 0.5 + 0.009), 0.0005, 0.0)
		add_child(word)
	slider.value_changed.connect(func(v: float) -> void: set_mode(MODE_5P if v >= 0.5 else MODE_2P))
	_switch = slider


## Throw the SELECT switch. Plugged in, the port is told again what is on it and
## the sockets are re-routed, as the hardware does the moment it is thrown.
func set_mode(next: int) -> void:
	if next != MODE_2P and next != MODE_5P:
		return
	if next == mode:
		return
	var sys := _connected_system
	var base := _base_port
	if sys != null and base >= 0:
		_detach_sockets(sys, base)
	mode = next
	_apply_device()
	if _switch != null and _switch.value != (1.0 if mode == MODE_5P else 0.0):
		_switch.set_value_no_signal(1.0 if mode == MODE_5P else 0.0)
	if sys != null and base >= 0:
		if sys.has_method("reannounce_port"):
			sys.reannounce_port(base)
		_attach_sockets(sys, base)
	_update_labels()
	print("[RetroMultitap] SELECT -> %dP" % mode)


## The tap as the console sees it, here and on its plug (which copied it once,
## when the cable was made).
func _apply_device() -> void:
	device_type = RETRO_DEVICE_JOYPAD if mode == MODE_5P else RETRO_DEVICE_NONE
	device_names = PackedStringArray([MULTITAP_NAME]) if mode == MODE_5P else PackedStringArray()
	if _cable_plug != null:
		_cable_plug.device_type = device_type
		_cable_plug.device_names = device_names


## Whether sub-port `i` reaches the console in this mode.
func socket_live(i: int) -> bool:
	return mode == MODE_5P or i == 0


## Each socket's number is the player it is: the port the tap is in, counted
## from 1, and on from there (2 to 5 on the Super NES's second port). A socket
## that is dead at 2P is dimmed.
func _update_labels() -> void:
	var first := _base_port + 1 if _base_port >= 0 else 2
	for i in _labels.size():
		var lbl := _labels[i] as Label3D
		if lbl == null:
			continue
		lbl.text = str(first + i)
		lbl.modulate = Color(1, 1, 1, 1) if socket_live(i) else Color(1, 1, 1, 0.3)


func _on_sub_snapped(i: int, plug: Node3D) -> void:
	_sub_plugs[i] = plug
	if _connected_system != null and _base_port >= 0:
		_attach_socket(_connected_system, _base_port, i)


func _on_sub_released(i: int) -> void:
	var plug: Node3D = _sub_plugs[i]
	_sub_plugs[i] = null
	if not is_instance_valid(plug):
		return
	if _connected_system != null and _base_port >= 0 and _bound[i]:
		_connected_system.detach_expanded_controller(_base_port + i, plug, _announces(i))
	_bound[i] = false


## Bind sub-port `i`'s pad, when it has one and the switch lets it through. At
## 5P the first socket's port is the tap's to announce.
func _attach_socket(sys: RetroSystem, base: int, i: int) -> void:
	if _bound[i] or not socket_live(i) or not is_instance_valid(_sub_plugs[i]):
		return
	print("[RetroMultitap] sub-port %d -> console port %d" % [i + 1, base + i])
	sys.attach_expanded_controller(base + i, _sub_plugs[i], _announces(i))
	_bound[i] = true


## Whether sub-port `i`'s pad is what its port is to the core: not at 5P's first
## socket, whose port is the tap's.
func _announces(i: int) -> bool:
	return not (mode == MODE_5P and i == 0)


func _attach_sockets(sys: RetroSystem, base: int) -> void:
	for i in range(SUB_PORTS):
		_attach_socket(sys, base, i)


func _detach_sockets(sys: RetroSystem, base: int) -> void:
	for i in range(SUB_PORTS):
		if _bound[i] and is_instance_valid(_sub_plugs[i]):
			sys.detach_expanded_controller(base + i, _sub_plugs[i], _announces(i))
		_bound[i] = false


# ── Port events (the multitap's own plug ↔ a console port) ────────────────────

func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	_connected_system = system
	_base_port = port_index
	print("[RetroMultitap] plugged into console port %d at %dP; ports %d..%d" % [
		port_index, mode, port_index, port_index + (SUB_PORTS - 1 if mode == MODE_5P else 0)])
	# Attach any controllers already seated in the sub-ports.
	_attach_sockets(system, port_index)
	_update_labels()


func on_unplugged() -> void:
	print("[RetroMultitap] unplugged from console port %d" % _base_port)
	if _connected_system != null and _base_port >= 0:
		_detach_sockets(_connected_system, _base_port)
	_connected_system = null
	_base_port = -1
	_update_labels()


func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	if _cable_plug != null:
		system.restore_controller_plug(port_index, _cable_plug)
	else:
		_pending_port_restore = {"system": system, "port_index": port_index}


# ── Cable (mirrors RetroController / RetroKeyboard) ───────────────────────────

func _spawn_cable() -> void:
	_cable_instance = CONTROLLER_CABLE_SCENE.instantiate()
	call_deferred("_add_cable_to_scene")


func _add_cable_to_scene() -> void:
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_cable_plug = _cable_instance.get_node("ControllerPlug") as ControllerPlug
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_plug.set_controller(self)
	_cable_plug.add_collision_exception_with(self)
	# Cable exits the back of the adapter (ports are on the front).
	_cable_plug.global_position = _cable_attach_point.global_position + Vector3(0, 0, -0.12)
	_cable_rope.start_node = _cable_attach_point
	_cable_rope.end_node = _cable_plug
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length

	if not _pending_port_restore.is_empty():
		var sys: RetroSystem = _pending_port_restore.get("system")
		var idx: int = _pending_port_restore.get("port_index", -1)
		_pending_port_restore = {}
		if is_instance_valid(sys) and idx >= 0:
			sys.restore_controller_plug(idx, _cable_plug)


## The cable is not a child, so a despawn would otherwise leave its plug and
## rope standing in the room (RetroController._exit_tree).
func _exit_tree() -> void:
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	super._exit_tree()


func _physics_process(_delta: float) -> void:
	# Cable rope clamp (same as RetroController / RetroKeyboard).
	if _cable_plug != null and _cable_attach_point != null and _max_rope_length > 0.0 \
			and not _cable_plug.is_picked_up() and _connected_system == null:
		PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
				_cable_attach_point.global_position, _max_rope_length)
