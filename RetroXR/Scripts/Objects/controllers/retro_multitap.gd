## RetroMultitap — a multitap adapter. It plugs into a console controller port
## with the same cable + plug as a controller, and re-exposes four controller
## ports on its own body. A controller snapped into sub-port k feeds the console
## at the multitap's base port + k, so one physical port fans out to up to four
## players. The base port is whichever console port the multitap's plug occupies
## (plug it into port 0 for the netplay-safe 0..3 mapping).
##
## The multitap itself reports RETRO_DEVICE_NONE, so the base port stays
## transparent until a controller occupies sub-port 0.
class_name RetroMultitap
extends XRToolsPickable


const CONTROLLER_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")
const RETRO_DEVICE_NONE := 0
const SUB_PORTS := 4

## Reported to the console when the multitap's own plug seats (NONE).
var device_type: int = RETRO_DEVICE_NONE

# Port connection state (the console port this multitap's plug occupies).
var _connected_system: RetroSystem = null
var _base_port: int = -1

# Cable (same pattern as RetroController / RetroKeyboard).
var _cable_instance: Node3D = null
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length: float = 0.0
var _pending_port_restore: Dictionary = {}

# Sub-port snap zones and the plug currently seated in each (or null).
var _sub_zones: Array = []
var _sub_plugs: Array = [null, null, null, null]

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _ports_root: Node3D = $Ports


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	_build_ports()
	_spawn_cable()
	grabbed.connect(func(_p: Node3D, _by: Node3D) -> void: pass)


## Four sub-port snap zones across the FRONT face of the adapter, each with a
## recessed port box and a number label below it — matching the console's own
## controller ports (system.tscn ControllerPort#).
const PORT_XS := [-0.09, -0.03, 0.03, 0.09]  # front-face X positions (metres)
const PORT_FACE_Z := 0.03                     # front face of the 0.06-deep body

func _build_ports() -> void:
	var recess_mat := StandardMaterial3D.new()
	recess_mat.albedo_color = Color(0.08, 0.08, 0.08)
	for i in range(SUB_PORTS):
		var zone: XRToolsSnapZone = SNAP_ZONE_SCENE.instantiate()
		zone.snap_require = "controller_plug"
		zone.grab_distance = 0.03
		_ports_root.add_child(zone)
		zone.position = Vector3(PORT_XS[i], 0.006, PORT_FACE_Z)

		# Recessed port box on the front face (dark inset, like the console).
		var recess := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.018, 0.012, 0.005)
		recess.mesh = box
		recess.set_surface_override_material(0, recess_mat)
		zone.add_child(recess)

		# Number label just below the port, billboarded to face the player.
		var lbl := Label3D.new()
		lbl.text = str(i + 1)
		lbl.pixel_size = 0.001
		lbl.font_size = 14
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.position = Vector3(0, -0.018, 0.006)
		zone.add_child(lbl)

		var idx := i
		zone.has_picked_up.connect(func(obj: Node3D) -> void: _on_sub_snapped(idx, obj))
		# has_dropped takes NO argument (see the same note in system.gd). Taking
		# one aborted every unplug, so a pad pulled from a sub-port kept driving
		# its console port. _sub_plugs already remembers what was seated.
		zone.has_dropped.connect(func() -> void: _on_sub_released(idx))
		_sub_zones.append(zone)


func _on_sub_snapped(i: int, plug: Node3D) -> void:
	_sub_plugs[i] = plug
	if _connected_system != null and _base_port >= 0:
		print("[RetroMultitap] sub-port %d -> console port %d" % [i + 1, _base_port + i])
		_connected_system.attach_expanded_controller(_base_port + i, plug)


func _on_sub_released(i: int) -> void:
	var plug: Node3D = _sub_plugs[i]
	_sub_plugs[i] = null
	if not is_instance_valid(plug):
		return
	if _connected_system != null and _base_port >= 0:
		_connected_system.detach_expanded_controller(_base_port + i, plug)


# ── Port events (the multitap's own plug ↔ a console port) ────────────────────

func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	_connected_system = system
	_base_port = port_index
	print("[RetroMultitap] plugged into console port %d; fanning out ports %d..%d" % [
		port_index, port_index, port_index + SUB_PORTS - 1])
	# Attach any controllers already seated in the sub-ports.
	for i in range(SUB_PORTS):
		if is_instance_valid(_sub_plugs[i]):
			system.attach_expanded_controller(port_index + i, _sub_plugs[i])


func on_unplugged() -> void:
	print("[RetroMultitap] unplugged from console port %d" % _base_port)
	if _connected_system != null and _base_port >= 0:
		for i in range(SUB_PORTS):
			if is_instance_valid(_sub_plugs[i]):
				_connected_system.detach_expanded_controller(_base_port + i, _sub_plugs[i])
	_connected_system = null
	_base_port = -1


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


func _physics_process(_delta: float) -> void:
	# Cable rope clamp (same as RetroController / RetroKeyboard).
	if _cable_plug != null and _cable_attach_point != null and _max_rope_length > 0.0 \
			and not _cable_plug.is_picked_up() and _connected_system == null:
		PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
				_cable_attach_point.global_position, _max_rope_length)
