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
