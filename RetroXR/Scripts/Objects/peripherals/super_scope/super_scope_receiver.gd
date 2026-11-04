## SuperScopeReceiver — the Super Scope's infrared receiver (SNS-014), a
## primitive stand-in. From the photographs and Wikipedia (docs/dev/super-scope.md):
## a light grey box about 6.4 x 6.4 x 2.5 cm, a dark oval window across its front,
## and a Super NES controller cord out of its back. It goes in the console's
## SECOND controller port and stands on top of the television, its window toward
## the player.
##
## It is what the console sees. Its cord's plug is a light gun to the socket
## (device type 4) and is announced by NAME (`device_names`): snes9x lists the
## SuperScope on its second port alone, so a receiver in the first port is
## announced as nothing (`strict_device_names`, SystemPorts.core_device_id) and
## says so, as the console reads no Super Scope there either.
##
## It decides nothing. The scope (SuperScope) pairs with the nearest seated
## receiver and sends the gun's state down this receiver's port while the
## infrared reaches it; this end only says where it is and which way its window
## looks. Its frame: the origin under the middle of the box, +Y up, the window on
## the -Z face, the cord out of +Z.
class_name SuperScopeReceiver
extends XRToolsPickable


const GROUP := "super_scope_receiver"
const CONTROLLER_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
## The SNES connector's own moulding, as the SNES Mouse's cord wears.
const PLUG_MESH := "res://imported-assets/controllers/snes-mouse/snes_mouse_plug.res"
## The save type (ScenePersistence).
const SAVE_TYPE := "super_scope_receiver"

## Wikipedia's 2.5 x 2.5 x 1 in.
const SIZE := Vector3(0.064, 0.025, 0.064)
## The oval window on the front: its straight middle and its height.
const WINDOW := Vector2(0.044, 0.016)

const SHELL := Color(0.74, 0.74, 0.72)
const BLACK := Color(0.05, 0.05, 0.055)

## What its plug is to a socket (ControllerPlug.set_controller copies these).
var device_type: int = RetroSystem.RETRO_DEVICE_LIGHTGUN
var device_names := PackedStringArray(["superscope", "super scope"])
var strict_device_names := true
var systemid: String = "snes"

## The scope it serves, or null (SuperScope._repair sets it).
var scope: Node = null

var _system: RetroSystem = null
var _lib_port := -1
var _cable_instance: Node3D = null
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length := 0.0
var _pending_restore: Dictionary = {}
var _cord_exit: Node3D = null


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	add_to_group(GROUP)
	_build()
	_spawn_cable()


func save_type() -> String:
	return SAVE_TYPE


func _exit_tree() -> void:
	# The cord is parented to the scene, as a pad's is: whatever takes the
	# receiver away takes its cord with it.
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	super._exit_tree()


## The cord, for the storage box (as RetroController.cable_instance).
func cable_instance() -> Node3D:
	return _cable_instance


func get_plug() -> ControllerPlug:
	return _cable_plug


## The middle of the window, in world space.
func lens_point() -> Vector3:
	return global_transform * Vector3(0.0, SIZE.y * 0.5, -SIZE.z * 0.5)


## Which way the window looks, in world space.
func lens_normal() -> Vector3:
	return (global_basis * Vector3.FORWARD).normalized()


func is_plugged_in() -> bool:
	return is_instance_valid(_system) and _lib_port >= 0


## The console it is in, or null.
func get_connected_system() -> RetroSystem:
	return _system if is_instance_valid(_system) else null


## The libretro port its plug is on, or -1.
func get_port_index() -> int:
	return _lib_port if is_plugged_in() else -1


## The console SOCKET its plug is in, or -1: what a save names.
func get_cabinet_port() -> int:
	if not is_plugged_in():
		return -1
	return _system.cabinet_port_of(self)


## Whether the console reads a Super Scope where this one is: the port's device,
## as the running core lists it. True before the core has said what it lists.
func port_reads_scope() -> bool:
	if not is_plugged_in():
		return false
	return _system.core_device_id(device_type, _lib_port, device_names, true) != RetroSystem.RETRO_DEVICE_NONE


# ── Port events (from the plug) ───────────────────────────────────────────────

func on_plugged_in(system: Node3D, port_index: int) -> void:
	_system = system as RetroSystem
	_lib_port = port_index
	print("[SuperScopeRx] seated in %s (libretro port %d)" % [system.name, port_index])
	if _system != null and not port_reads_scope():
		print("[SuperScopeRx] %s's core lists no Super Scope on libretro port %d: plugged in, read by nothing"
			% [system.name, port_index])
		_notice("Controller port 2", "The Super Scope's receiver works in controller port 2.")
	_tell_scopes()


func on_unplugged() -> void:
	if not is_plugged_in():
		return
	print("[SuperScopeRx] unplugged from libretro port %d" % _lib_port)
	_system = null
	_lib_port = -1
	_tell_scopes()


## Seat it back where a save says: console socket `port_index`.
func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	if _cable_plug != null and _cable_plug.is_inside_tree():
		print("[SuperScopeRx] restoring into %s socket %d" % [system.name, port_index])
		system.restore_controller_plug(port_index, _cable_plug)
	else:
		_pending_restore = {"system": system, "port_index": port_index}


## Every scope looks again at which receiver it has.
func _tell_scopes() -> void:
	if is_inside_tree():
		get_tree().call_group(SuperScope.GROUP, "_repair")


func _notice(title: String, text: String) -> void:
	if not is_instance_valid(_system):
		return
	var toast := AchievementToast.attach_to_machine(_system)
	if toast != null:
		toast.show_notice("Super Scope", title, text)


# ── Cord ──────────────────────────────────────────────────────────────────────

func _spawn_cable() -> void:
	_cable_instance = CONTROLLER_CABLE_SCENE.instantiate()
	_add_cable_to_scene.call_deferred()


func _add_cable_to_scene() -> void:
	if not is_inside_tree():
		return
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_cable_plug = _cable_instance.get_node("ControllerPlug") as ControllerPlug
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_plug.set_controller(self)
	if ResourceLoader.exists(PLUG_MESH):
		_cable_plug.set_plug_mesh(PLUG_MESH)
	_cable_plug.add_collision_exception_with(self)
	_cable_plug.global_position = _cord_exit.global_position + global_basis * Vector3(0, 0, 0.12)
	_cable_rope.start_node = _cord_exit
	_cable_rope.end_node = _cable_plug
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length
	if not _pending_restore.is_empty():
		var sys: RetroSystem = _pending_restore.get("system")
		var idx: int = _pending_restore.get("port_index", -1)
		_pending_restore = {}
		if is_instance_valid(sys) and idx >= 0:
			print("[SuperScopeRx] restoring into %s socket %d" % [sys.name, idx])
			sys.restore_controller_plug(idx, _cable_plug)


func _physics_process(_delta: float) -> void:
	if _cable_plug == null or _cord_exit == null or _max_rope_length <= 0.0:
		return
	if _cable_plug.is_picked_up() or is_plugged_in():
		return
	PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
		_cord_exit.global_position, _max_rope_length)


# ── Body ──────────────────────────────────────────────────────────────────────

func _build() -> void:
	var shell := _mat(SHELL, 0.55)
	var black := _mat(BLACK, 0.3)
	_box("Body", SIZE, Vector3(0.0, SIZE.y * 0.5, 0.0), shell)
	# The oval window, a hair proud of the front: a straight middle and a round
	# end either side (cylinders stood on end, their axis +Y).
	var front := -SIZE.z * 0.5 - 0.0006
	var mid_y := SIZE.y * 0.5
	_box("Window", Vector3(WINDOW.x, WINDOW.y, 0.0016), Vector3(0.0, mid_y, front), black)
	for side: float in [-1.0, 1.0]:
		var end := MeshInstance3D.new()
		end.name = "WindowEnd"
		var cyl := CylinderMesh.new()
		cyl.top_radius = WINDOW.y * 0.5
		cyl.bottom_radius = WINDOW.y * 0.5
		cyl.height = 0.0016
		cyl.radial_segments = 16
		cyl.rings = 1
		end.mesh = cyl
		end.material_override = black
		add_child(end)
		end.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(side * WINDOW.x * 0.5, mid_y, front))
	# The seam round the lid, a darker line a quarter down, as the photograph has it.
	_box("Seam", Vector3(SIZE.x + 0.0008, 0.0008, SIZE.z + 0.0008),
		Vector3(0.0, SIZE.y * 0.78, 0.0), _mat(SHELL.darkened(0.25), 0.6))
	_cord_exit = Node3D.new()
	_cord_exit.name = "CordExit"
	add_child(_cord_exit)
	# The rope leaves along its node's -Z: turned half round, it leaves out of the back.
	_cord_exit.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, SIZE.y * 0.4, SIZE.z * 0.5))
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = SIZE
		col.shape = box
		col.position = Vector3(0.0, SIZE.y * 0.5, 0.0)


func _box(node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	mi.position = at
	return mi


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
