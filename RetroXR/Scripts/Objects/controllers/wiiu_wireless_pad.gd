## WiiUWirelessPad — a pad with no cord that pairs with a Wii U over SYNC: the
## GamePad (WiiUGamePad) and the Pro Controller (WiiUProController).
##
## A RetroPadController in everything but the cord: the same held input, bindings,
## desktop pad, rumble and poked caps, its controls at the RETRO XR pad's node
## paths (Model/FaceA, Model/StickL, ...) so its animation binds unchanged. The
## port comes from pairing instead of a socket: SYNC on the console opens its
## window (WiiLink), SYNC on the pad takes a port, SYNC again lets it go, as on a
## Wii Remote. Built in code: the subclass draws its body in _build_model, from
## its measured size.
class_name WiiUWirelessPad
extends RetroPadController

## The pad's SYNC button, a VRButton the subclass's scene carries.
@onready var _sync_btn: VRButton = get_node_or_null("SyncButton") as VRButton

## POWER, as on the Wii Remote (wiimote.gd): with the console off a press switches it
## on; with it on only a hold of POWER_HOLD_SEC switches it off, so putting the pad
## down on its face cannot end a game. Built on the pad's Model/Power key.
const POWER_HOLD_SEC := 1.0
const POWER_HAPTIC_KEY := &"wiiu_pad_power"
const POWER_HAPTIC_MAGNITUDE := 0.15
var _power_btn: VRButton = null
var _power_held_for := 0.0
var _power_fired := false
var _power_haptic_ctrl: XRController3D = null


func _init() -> void:
	_build_model()


## The body and the controls, under a node named Model. Overridden.
func _build_model() -> void:
	pass


func _ready() -> void:
	super._ready()
	if _sync_btn != null:
		_sync_btn.button_pressed.connect(_on_sync_pressed)
	if not _pending_port_restore.is_empty():
		call_deferred("_apply_pending_restore")
	_build_power_button()


func _process(delta: float) -> void:
	super._process(delta)
	if _power_btn != null:
		_update_power_hold(delta)


func _exit_tree() -> void:
	_stop_power_haptic()
	super._exit_tree()


# ── POWER ─────────────────────────────────────────────────────────────────────

## A VRButton on the Model/Power key (the stand-in's, or the model a mod put at that
## path), pressing it into the face along the pad's -Y.
func _build_power_button() -> void:
	var model := get_node_or_null("Model") as Node3D
	var cap := model.get_node_or_null("Power") as MeshInstance3D if model != null else null
	if cap == null:
		return
	_power_btn = VRButton.new()
	_power_btn.name = "PowerButton"
	_power_btn.collision_layer = 0
	_power_btn.collision_mask = 0
	_power_btn.trigger_radius = 0.008
	_power_btn.contact_margin = 0.006
	_power_btn.depress_depth = 0.0007
	_power_btn.depress_axis = Vector3(0, -1, 0)
	var shape := CylinderShape3D.new()
	shape.radius = 0.004
	shape.height = 0.004
	var col := CollisionShape3D.new()
	col.shape = shape
	_power_btn.add_child(col)
	_power_btn.position = model.transform * cap.position
	add_child(_power_btn)
	_power_btn.set_button_mesh(cap)


## The Wii Remote's rule (wiimote.gd _update_power_hold), through toggle_power: the
## same entry the console's own key uses, with its netplay rules.
func _update_power_hold(delta: float) -> void:
	if not _power_btn.is_held():
		_stop_power_haptic()
		_power_held_for = 0.0
		_power_fired = false
		return
	if _power_fired:
		return
	if not is_instance_valid(_connected_system):
		_power_fired = true
		print("[WiiU] %s: POWER with no console paired — press SYNC on both first" % name)
		return
	if not _connected_system.is_powered_on:
		_power_fired = true
		print("[WiiU] %s: POWER — switching the console on" % name)
		_connected_system.toggle_power()
		return
	_set_power_haptic(_power_btn.held_by())
	_power_held_for += delta
	if _power_held_for < POWER_HOLD_SEC:
		return
	_stop_power_haptic()
	_power_fired = true
	print("[WiiU] %s: POWER held %.1fs — switching the console off" % [name, POWER_HOLD_SEC])
	_connected_system.toggle_power()


func _set_power_haptic(ctrl: XRController3D) -> void:
	if ctrl == _power_haptic_ctrl:
		return
	_stop_power_haptic()
	if is_instance_valid(ctrl):
		_power_haptic_ctrl = ctrl
		Haptics.hold(ctrl, POWER_HAPTIC_MAGNITUDE, POWER_HAPTIC_KEY)


func _stop_power_haptic() -> void:
	if is_instance_valid(_power_haptic_ctrl):
		Haptics.stop(_power_haptic_ctrl, POWER_HAPTIC_KEY)
	_power_haptic_ctrl = null


## Cordless: nothing to spawn, so nothing tethers it either.
func _spawn_cable() -> void:
	pass


## A Wii U pad asks for libretro port 0, the GamePad's (WiiLink.pair).
func wants_gamepad_port() -> bool:
	return false


## Marker method WiiLink reads to tell a wireless pad from a wired one.
func on_wireless_rehomed() -> void:
	pass


func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	print("[WiiU] %s paired on port %d (device %d)" % [name, port_index, device_type])


func on_unplugged() -> void:
	print("[WiiU] %s let go of port %d" % [name, _port_index])
	super.on_unplugged()


# ── Pairing ─────────────────────────────────────────────────────────────────

func _on_sync_pressed() -> void:
	if _connected_system != null:
		var link := _connected_system.get_wii_link()
		print("[WiiU] %s: SYNC while paired, letting go of port %d" % [name, _port_index])
		if link != null:
			link.unpair(self)
		return
	var link := _nearest_listening_wiiu()
	if link == null:
		print("[WiiU] %s: SYNC with no Wii U listening; press SYNC on the console first" % name)
		return
	if link.pair(self) < 0:
		print("[WiiU] %s: pairing refused (port taken)" % name)


## The nearest Wii U with its pairing window open. A Wii's is passed over: these
## pads are the Wii U's own.
func _nearest_listening_wiiu() -> WiiLink:
	var best: WiiLink = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(WiiLink.PAIRING_GROUP):
		var link := node as WiiLink
		if link == null or not is_instance_valid(link.host) or not link.is_wiiu():
			continue
		var d := global_position.distance_to(link.host.global_position)
		if d < best_d:
			best_d = d
			best = link
	return best


func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	if is_inside_tree() and is_node_ready():
		system.attach_expanded_controller(port_index, self)
	else:
		_pending_port_restore = {"system": system, "port_index": port_index}


func _apply_pending_restore() -> void:
	var sys: RetroSystem = _pending_port_restore.get("system")
	var idx: int = _pending_port_restore.get("port_index", -1)
	_pending_port_restore = {}
	if is_instance_valid(sys) and idx >= 0:
		sys.attach_expanded_controller(idx, self)


# ── Building ────────────────────────────────────────────────────────────────

func _mk_mat(c: Color, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _mk_box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


## An upright cylinder (a face button, a stick's shaft): its axis is the pad's Y.
func _mk_cyl(parent: Node3D, node_name: String, radius: float, height: float, at: Vector3, mat: Material,
		bottom_radius := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius if bottom_radius < 0.0 else bottom_radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	mi.mesh = mesh
	mi.position = at
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


## A stick: shaft and cap, the RETRO XR pad's StickL/Cap arrangement.
func _mk_stick(parent: Node3D, node_name: String, at: Vector3, mat: Material) -> void:
	var shaft := _mk_cyl(parent, node_name, 0.0055, 0.01, at, mat, 0.0085)
	_mk_cyl(shaft, "Cap", 0.0105, 0.0035, Vector3(0.0, 0.0068, 0.0), mat, 0.0095)


## A D-pad: a cross of two bars (its root is the vertical arm).
func _mk_dpad(parent: Node3D, at: Vector3, mat: Material) -> void:
	var v := _mk_box(parent, "DPad", Vector3(0.008, 0.004, 0.024), at, mat)
	_mk_box(v, "DPadCross", Vector3(0.024, 0.004, 0.008), Vector3.ZERO, mat)


## A face button with its letter printed on top.
func _mk_face(parent: Node3D, node_name: String, letter: String, at: Vector3, mat: Material) -> void:
	var b := _mk_cyl(parent, node_name, 0.0048, 0.004, at, mat)
	var l := Label3D.new()
	l.name = "Label"
	l.text = letter
	l.font_size = 40
	l.pixel_size = 0.00015
	l.outline_size = 0
	l.modulate = Color(0.85, 0.85, 0.85)
	l.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0021, 0.0))
	b.add_child(l)
