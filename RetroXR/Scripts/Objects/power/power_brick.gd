## PowerBrick — an AC adapter: its body, its DC lead and the plug the console takes,
## and its mains side -- prongs on the body, a fixed mains cord, or a C8 inlet a
## figure-eight cord goes into (docs/dev/power.md).
##
## A primitive, built in code from its PowerBrickCatalog row as WallOutlet builds a
## plate from MainsRegions: one scene for every adapter, its body a box of the
## RetroXR-models item's own size, its anchors that item's. When a row names a model,
## the box gives way to it (the anchors are the model's, so nothing else changes).
##
## A brick is the variant it was spawned as (the region it was bought in), and stays
## it: a change of the room's region does not re-form it, MainsSplice puts a travel
## adapter between its prongs and a wall that no longer takes them.
##
## Speaks PowerCord's mains and persistence APIs: mains_live_at (its DC plug has
## power while its mains side does), plug_at / seating / restore_*, two ends --
## PowerCord.End.WALL its wall plug and APPLIANCE its DC plug -- and the body's pose
## as the strip's (carried_body_pose).
class_name PowerBrick
extends Node3D

const END_WALL := PowerCord.End.WALL
const END_DC := PowerCord.End.APPLIANCE
const GROUP := "power_brick"
const C8_PORT := preload("res://Scenes/Objects/cables/iec_c8_port.tscn")
const PLUG_MESH := "res://Scenes/Objects/cables/%s.res"

const BODY_COLOR := Color(0.12, 0.12, 0.13)
const PLUG_COLOR := Color(0.08, 0.08, 0.09)
const PIN_COLOR := Color(0.78, 0.76, 0.7)

## Its PowerBrickCatalog id. Set before it enters the tree (the spawn menu, a save).
@export var brick_id := ""
## Which of the row's variants (RetroXR-models' model name: usa, eur, ...); "" is the
## one sold in the player's region, settled in _ready and saved from then on.
@export var variant := ""

## The variant's form (PowerBrickCatalog): wall_wart, inline, inlet, dock, battery_pack.
var form := ""
## The prongs of a wall wart or the plug at the end of the mains cord, or null for a
## form with no mains side of its own (inlet, battery_pack).
var wall_plug: PowerPlug = null
## The plug at the end of the DC lead, or the whole module for a dock.
var dc_plug: PowerPlug = null
## The C8 inlet of an inlet brick, or null.
var inlet: PowerPort = null

@onready var _body: RigidBody3D = $Body
@onready var _dc_rope: VerletRope = $DcRope
@onready var _ac_rope: VerletRope = $AcRope

var _spec := {}
## The model the body wears (a mod's), or null for the primitive box.
var _model_scene: PackedScene = null
## [rope, anchor (Node3D on the thing that carries it), plug, reach] for each cord.
var _cords: Array = []


func _ready() -> void:
	add_to_group(GROUP)
	wall_plug = $WallPlug as PowerPlug
	dc_plug = $DcPlug as PowerPlug
	if not PowerBrickCatalog.has(brick_id):
		push_warning("[Power] a power brick with no known row '%s': kept as a bare box" % brick_id)
	if variant.is_empty() or not PowerBrickCatalog.variants_of(brick_id).has(variant):
		variant = PowerBrickCatalog.variant_for_region(brick_id, AppPrefs.mains_region)
	_spec = PowerBrickCatalog.variant(brick_id, variant)
	form = str(_spec.get("form", "wall_wart"))
	_build()
	for plug: PowerPlug in [wall_plug, dc_plug]:
		if plug != null:
			plug.cable = self
	print("[Power] brick %s (%s, %s): DC plug %s%s" % [brick_id, variant, form,
		dc_plug.connector if dc_plug != null else "-",
		", prongs %s" % wall_plug.connector if wall_plug != null else ""])
	_build_ropes.call_deferred()


# ── building it ──────────────────────────────────────────────────────────────

static func _mm(v: Variant) -> Vector3:
	var a: Array = v if v is Array else [0.0, 0.0, 0.0]
	return Vector3(float(a[0]), float(a[1]), float(a[2])) * 0.001


func _build() -> void:
	var size := _mm(_spec.get("size_mm", [60.0, 40.0, 100.0]))
	_model_scene = _scene_of(str(_spec.get("model", "")), "model")
	match form:
		"wall_wart":
			_drop(_body)
			_body = null
			_drop(_ac_rope)
			_ac_rope = null
			_make_wall_plug(true, size)
			if _model_scene != null:
				var box := _wear(wall_plug)
				(wall_plug.get_node("PlugTip") as MeshInstance3D).visible = false
				# The hand and the wall meet the body, not the blades in front of its face.
				if box.end.z > 0.0 and box.position.z < 0.0:
					box.size.z = -box.position.z
				_fit_shapes(wall_plug, box.get_center(), box.size)
				_add_cord(_dc_rope, _model_anchor(wall_plug, "DcAnchor", "DCCordAnchor", box,
					_mm(_spec.get("dc"))), dc_plug)
			else:
				_add_cord(_dc_rope, _anchor(wall_plug, "DcAnchor", _mm(_spec.get("dc")),
					Vector3(0, 0, -size.z * 0.5), size), dc_plug)
			_make_dc_plug()
		"inline":
			var box := _make_body(size)
			_make_wall_plug(false, size)
			_add_cord(_ac_rope, _model_anchor(_body, "AcAnchor", "ACCordAnchor", box,
				_mm(_spec.get("ac"))), wall_plug)
			_add_cord(_dc_rope, _model_anchor(_body, "DcAnchor", "DCCordAnchor", box,
				_mm(_spec.get("dc"))), dc_plug)
			_make_dc_plug()
		"inlet":
			var box := _make_body(size)
			_drop(wall_plug)
			wall_plug = null
			_drop(_ac_rope)
			_ac_rope = null
			_make_inlet(_model_point("ACInAnchor", _mm(_spec.get("ac_in"))), box)
			_add_cord(_dc_rope, _model_anchor(_body, "DcAnchor", "DCCordAnchor", box,
				_mm(_spec.get("dc"))), dc_plug)
			_make_dc_plug()
		"dock":
			_drop(_body)
			_body = null
			_drop(_dc_rope)
			_dc_rope = null
			_make_dock(size)
			_make_wall_plug(false, size)
			if _model_scene != null:
				var box := _wear(dc_plug)
				(dc_plug.get_node("PlugTip") as MeshInstance3D).visible = false
				_add_cord(_ac_rope, _model_anchor(dc_plug, "AcAnchor", "ACCordAnchor", box,
					_mm(_spec.get("ac"))), wall_plug)
			else:
				_add_cord(_ac_rope, _anchor(dc_plug, "AcAnchor", _mm(_spec.get("ac")),
					Vector3(0, 0, size.z * 0.5), size), wall_plug)
		"battery_pack":
			var box := _make_body(size)
			_drop(wall_plug)
			wall_plug = null
			_drop(_ac_rope)
			_ac_rope = null
			_add_cord(_dc_rope, _model_anchor(_body, "DcAnchor", "DCCordAnchor", box,
				_mm(_spec.get("dc"))), dc_plug)
			_make_dc_plug()


## A part this form has no use for, gone now: queued, it would run its deferred
## set-up (a highlight's) out of the tree.
func _drop(node: Node) -> void:
	if node != null and is_instance_valid(node):
		remove_child(node)
		node.free()


static func _material(color: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35 if metal else 0.75
	m.metallic = 0.9 if metal else 0.0
	return m


static func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mi.mesh = box
	return mi


## A body's collision and pointer boxes, round `box` (centre, size) in its frame.
static func _fit_shapes(body: Node3D, center: Vector3, size: Vector3, pointer_pad := 0.01) -> void:
	for path: String in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var shape := body.get_node_or_null(path) as CollisionShape3D
		if shape == null:
			continue
		var b := BoxShape3D.new()
		b.size = size + (Vector3.ONE * pointer_pad if path.begins_with("Pointer") else Vector3.ZERO)
		shape.shape = b
		shape.position = center


## The body: the model it wears, else a box of the row's size, its floor at the
## origin. Returns the body's bounds in its frame (the anchors' faces).
func _make_body(size: Vector3) -> AABB:
	if _model_scene != null:
		return _wear(_body)
	var center := Vector3(0, size.y * 0.5, 0)
	var box := _box_mesh(size, BODY_COLOR)
	box.name = "Box"
	box.position = center
	_body.add_child(box)
	_fit_shapes(_body, center, size)
	_body.mass = clampf(size.x * size.y * size.z * 1600.0, 0.08, 1.2)
	return AABB(center - size * 0.5, size)


## A scene a mod named, or null (and why, in the log) for none or one that will not load.
func _scene_of(path: String, what: String) -> PackedScene:
	if path.is_empty():
		return null
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("[Power] brick %s (%s): its %s %s does not load; the primitive stays"
			% [brick_id, variant, what, path])
	return packed


## Put the model on `carrier` (at the variant's model_offset), its boxes fitted to what
## it draws. Returns its bounds in the carrier's frame.
func _wear(carrier: Node3D, packed: PackedScene = null) -> AABB:
	var scene := packed if packed != null else _model_scene
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	var offset: Variant = _spec.get("model_offset", null)
	if offset is Transform3D:
		model.transform = offset
	carrier.add_child(model)
	var box := ApplianceModel.node_bounds(model, carrier) if carrier.is_inside_tree() \
		else _bounds_off_tree(model)
	_fit_shapes(carrier, box.get_center(), box.size)
	if (carrier != dc_plug or form == "dock") and carrier is RigidBody3D:
		(carrier as RigidBody3D).mass = clampf(box.size.x * box.size.y * box.size.z * 1600.0, 0.08, 1.2)
	return box


## A model's bounds in its parent's frame, before anything is in the tree.
static func _bounds_off_tree(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[model, model.transform]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var node := top[0] as Node
		var xf: Transform3D = top[1]
		if node is GeometryInstance3D:
			var box: AABB = xf * (node as GeometryInstance3D).get_aabb()
			if box.size != Vector3.ZERO:
				out = box if first else out.merge(box)
				first = false
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return out


## Where an anchor of the worn model is, in the carrier's frame, else `fallback` (the
## row's millimetres, in the same frame).
func _model_point(node_name: String, fallback: Vector3) -> Vector3:
	for carrier: Node in [_body, wall_plug, dc_plug]:
		if carrier == null or not is_instance_valid(carrier):
			continue
		var model := carrier.get_node_or_null("Model") as Node3D
		if model == null:
			continue
		var found := model.find_child(node_name, true, false) as Node3D
		if found != null:
			return _local_to(carrier as Node3D, found)
	return fallback


## `node`'s position in `carrier`'s frame, in or out of the tree.
static func _local_to(carrier: Node3D, node: Node3D) -> Vector3:
	var xf := node.transform
	var at: Node = node.get_parent()
	while at != null and at != carrier:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf.origin


## A cord's anchor on `carrier`: the worn model's own `node_name` if it has one, else
## `fallback`; its -Z out of the face of `box` it is on.
func _model_anchor(carrier: Node3D, anchor_name: String, node_name: String, box: AABB,
		fallback: Vector3) -> Node3D:
	var at := _model_point(node_name, fallback) if _model_scene != null else fallback
	return _anchor(carrier, anchor_name, at, box.get_center(), box.size)


## The wall plug: for a wall wart, the whole body with the region's prongs drawn on
## its face from MainsSpecs; else the region's cord plug.
func _make_wall_plug(is_body: bool, size: Vector3) -> void:
	var connector := PowerBrickCatalog.wall_plug_of(variant)
	wall_plug.set_connector(connector)
	var tip := wall_plug.get_node("PlugTip") as MeshInstance3D
	if is_body and _model_scene != null:
		# The model has its own blades and body (_build wears it).
		return
	if is_body:
		tip.mesh = _prongs(connector)
		var center := Vector3(0, 0, -size.z * 0.5)
		var box := _box_mesh(size, BODY_COLOR)
		box.name = "Box"
		box.position = center
		wall_plug.add_child(box)
		_fit_shapes(wall_plug, center, size)
		wall_plug.mass = clampf(size.x * size.y * size.z * 1600.0, 0.08, 1.2)
		# The cord leaves the body, not the prongs' back.
		wall_plug.cable_anchor = Vector3(0, 0, -size.z)
	else:
		var path := PLUG_MESH % connector
		if ResourceLoader.exists(path):
			tip.mesh = load(path) as Mesh
		var ab := tip.mesh.get_aabb() if tip.mesh != null else AABB(Vector3(-0.015, -0.01, -0.06), Vector3(0.03, 0.02, 0.06))
		_fit_shapes(wall_plug, ab.get_center(), ab.size, 0.012)
		wall_plug._derive_cable_anchor()


## The prongs of `connector` (MainsSpecs' pins), standing out of the face along +Z.
## A seated plug is turned half round about Y, so its pins mirror X (MainsSpecs).
static func _prongs(connector: String) -> Mesh:
	var spec: Dictionary = MainsSpecs.PLUGS.get(connector, {})
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pin: Dictionary in spec.get("pins", []):
		var at: Vector2 = pin.get("at", Vector2.ZERO) * 0.001
		var length := float(pin.get("len", 16.0)) * 0.001
		var shape: Mesh
		var turn := Basis.IDENTITY
		if str(pin.get("shape", "rect")) == "round":
			var cyl := CylinderMesh.new()
			cyl.top_radius = float(pin.get("d", 4.0)) * 0.0005
			cyl.bottom_radius = cyl.top_radius
			cyl.height = length
			cyl.radial_segments = 10
			cyl.rings = 1
			shape = cyl
			turn = Basis(Vector3.RIGHT, PI * 0.5)
		else:
			var size: Vector2 = pin.get("size", Vector2(1.5, 6.35)) * 0.001
			var box := BoxMesh.new()
			box.size = Vector3(size.x, size.y, length)
			shape = box
			turn = Basis(Vector3.BACK, deg_to_rad(-float(pin.get("angle", 0.0))))
		st.append_from(shape, 0, Transform3D(turn, Vector3(-at.x, at.y, length * 0.5)))
	if spec.get("pins", []).is_empty():
		var stub := BoxMesh.new()
		stub.size = Vector3(0.012, 0.006, 0.016)
		st.append_from(stub, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.008)))
	st.commit(mesh)
	mesh.surface_set_material(0, _material(PIN_COLOR, true))
	return mesh


## The DC plug: a box of the item's plug size, its face at the origin, the cord out
## of its back.
func _make_dc_plug() -> void:
	dc_plug.set_connector(str(_spec.get("dc_plug", "barrel_5_5x2_1")))
	var size := _mm(_spec.get("plug_mm", [9.0, 9.0, 35.0]))
	var tip := dc_plug.get_node("PlugTip") as MeshInstance3D
	var plug_scene := _scene_of(str(_spec.get("plug_model", "")), "plug_model")
	if plug_scene != null:
		# The plug's model: its origin the face that stops against the jack, the barrel
		# along +Z (the game's plug frame), the lead out of its CordExit.
		tip.visible = false
		_wear(dc_plug, plug_scene)
		var model := dc_plug.get_node("Model") as Node3D
		var exit := model.find_child("CordExit", true, false) as Node3D
		dc_plug.cable_anchor = _local_to(dc_plug, exit) if exit != null \
			else Vector3(0, 0, -size.z)
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(PLUG_COLOR)
	tip.mesh = box
	tip.position = Vector3(0, 0, -size.z * 0.5)
	_fit_shapes(dc_plug, tip.position, size, 0.012)
	dc_plug._derive_cable_anchor()


## The N64's module: the DC plug IS the body, docking into the console's back.
func _make_dock(size: Vector3) -> void:
	dc_plug.set_connector(str(_spec.get("dc_plug", "n64_psu_dock")))
	var tip := dc_plug.get_node("PlugTip") as MeshInstance3D
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(BODY_COLOR)
	tip.mesh = box
	# A seated plug's +Z points INTO its socket (the reverse of the socket's), so the
	# module reaches +Z from its mouth: into the bay, its back face at the plug's
	# origin. Built toward -Z it docked hanging 73 mm off the console's back.
	tip.position = Vector3(0, 0, size.z * 0.5)
	_fit_shapes(dc_plug, tip.position, size)
	dc_plug.mass = clampf(size.x * size.y * size.z * 1600.0, 0.08, 1.2)
	dc_plug._derive_cable_anchor()


## A C8 inlet on the body at `at`, facing out of the face of `box` it is on. Under a
## model the model's own pocket is the inlet's look.
func _make_inlet(at: Vector3, box: AABB) -> void:
	inlet = C8_PORT.instantiate() as PowerPort
	inlet.name = "AcInlet"
	_body.add_child(inlet)
	var out := _face_normal(at, box.get_center(), box.size)
	inlet.transform = Transform3D(_facing(out), at)
	if _model_scene != null:
		var own := inlet.get_node_or_null("Inlet") as Node3D
		if own != null:
			own.visible = false


## A node on `carrier` at `at`, its local -Z out of the face it is on (a cord
## leaves a node along its local -Z). `center`/`size` are the carrier's box.
func _anchor(carrier: Node3D, anchor_name: String, at: Vector3, center: Vector3, size: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = anchor_name
	carrier.add_child(node)
	var out := _face_normal(at, center, size)
	node.transform = Transform3D(_facing(-out), at)
	return node


## The outward normal of the face of box (center, size) nearest `at`.
static func _face_normal(at: Vector3, center: Vector3, size: Vector3) -> Vector3:
	var d := at - center
	var half := size * 0.5
	var best := Vector3.BACK
	var score := -INF
	for axis in 3:
		var h := maxf(half[axis], 0.0001)
		var s := absf(d[axis]) / h
		if s > score:
			score = s
			best = Vector3.ZERO
			best[axis] = signf(d[axis]) if d[axis] != 0.0 else 1.0
	return best


## A basis whose +Z is `z`.
static func _facing(z: Vector3) -> Basis:
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


func _add_cord(rope: VerletRope, anchor: Node3D, plug: PowerPlug) -> void:
	if rope != null and plug != null:
		_cords.append([rope, anchor, plug, 0.0])


func _build_ropes() -> void:
	if not is_inside_tree():
		return
	for cord: Array in _cords:
		var rope := cord[0] as VerletRope
		var plug := cord[2] as PowerPlug
		rope.start_node = cord[1]
		rope.end_node = plug
		rope.end_anchor_offset = plug.cable_anchor
		rope._init_points()
		cord[3] = float(rope.segment_count) * rope.segment_length


## The thing the player carries: the body, or the plug that is the body.
func _carrier_of(anchor: Node3D) -> RigidBody3D:
	return anchor.get_parent() as RigidBody3D if anchor != null else null


## Each cord within its reach: a loose plug is reeled in toward the body, and a body
## let go of with a plug in somewhere is hauled back toward it (the strip's rule).
func _physics_process(_delta: float) -> void:
	for cord: Array in _cords:
		var reach := float(cord[3])
		var anchor := cord[1] as Node3D
		var plug := cord[2] as PowerPlug
		if reach <= 0.0 or not is_instance_valid(anchor) or not is_instance_valid(plug):
			continue
		var from := anchor.global_position
		var to := plug.global_transform * plug.cable_anchor
		if not plug.is_held():
			PlugTether.reel_in(plug, to, from, reach)
			continue
		var carrier := _carrier_of(anchor)
		if carrier == null or carrier.freeze:
			continue
		var back := CableHaul.haul(carrier, from, to, reach)
		if back != Vector3.ZERO:
			carrier.global_position += back


func on_plug_seating_changed() -> void:
	# Told to the other players, one event per end that moved (MainsSync).
	MainsSync.report(self)


## A peer's seat of one of this lead's ends (EV_RCA_PLUG), and its pull.
func net_seat_plug(end: int, _cord: int, device: Node3D, port_name: String) -> void:
	MainsSync.seat(plug_at(end), device, port_name)


func net_release_plug(end: int, _cord: int) -> void:
	MainsSync.release(plug_at(end))


# ── Mains (MainsPower) ─────────────────────────────────────────────────────────

## Power at the DC plug while the mains side has it: the prongs or the cord's plug
## in a live socket, a live cord in the inlet, or always for a charged pack.
func mains_live_at(at: Node, seen: Dictionary) -> bool:
	if at != dc_plug or dc_plug == null:
		return false
	match form:
		"battery_pack":
			return true
		"inlet":
			var fed: Node3D = inlet.picked_up_object as Node3D if inlet != null else null
			return fed != null and MainsPower.plug_live(fed, seen)
	return wall_plug != null and MainsPower.seated_live(wall_plug, seen)


func mains_noun() -> String:
	match form:
		"battery_pack":
			return "battery pack"
		"dock":
			return "power supply"
	return "AC adapter"


## Where its mains comes in, for the words: its own wall plug, or the plug at the far
## end of the cord in its inlet.
func mains_wall_plug() -> Node3D:
	if form == "inlet":
		var fed: Node3D = inlet.picked_up_object as Node3D if inlet != null else null
		return PowerInput.lead_wall_plug(fed) if fed != null else null
	return wall_plug


# ── Persistence: PowerCord's API, two ends ────────────────────────────────────

func cord_count() -> int:
	return 1


func plug_at(end: int) -> PowerPlug:
	match end:
		END_WALL:
			return wall_plug
		END_DC:
			return dc_plug
	return null


func seating() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: int in [END_WALL, END_DC]:
		var plug := plug_at(e)
		if plug == null:
			continue
		var socket := _holder(plug)
		out.append({
			"plug": plug,
			"end": int(e),
			"cord": 0,
			"device": socket.get_device() if socket != null else null,
			"port": String(socket.name) if socket != null else "",
		})
	return out


## The socket holding one of its plugs: a mains socket, a DC jack, the N64's dock.
func _holder(plug: Node3D) -> Port:
	if plug == null or not plug.is_inside_tree():
		return null
	for node in plug.get_tree().get_nodes_in_group(Port.ANY_GROUP):
		var port := node as Port
		if port != null and port.picked_up_object == plug:
			return port
	return null


func restore_plug_poses(seats: Array) -> void:
	for seat: Dictionary in seats:
		var plug := plug_at(int(seat.get("end", 0)))
		if plug == null:
			continue
		var pos: Array = seat.get("position", [])
		var rot: Array = seat.get("rotation", [])
		if pos.size() == 3:
			plug.global_position = Vector3(pos[0], pos[1], pos[2])
		if rot.size() == 3:
			plug.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])


func restore_seating(seats: Array) -> void:
	call_deferred("_apply_seating", seats)


func _apply_seating(seats: Array) -> void:
	restore_plug_poses(seats)
	for seat: Dictionary in seats:
		var plug := plug_at(int(seat.get("end", 0)))
		var device: Node3D = seat.get("device")
		var port_name := str(seat.get("port", ""))
		if plug == null or device == null or not is_instance_valid(device) or port_name.is_empty():
			continue
		var port := CompositeCable.port_named(device, port_name)
		if port != null and plug.is_in_group(port.snap_require):
			port.pick_up_object(plug)
	_build_ropes()


## The body's pose, for a form with a body apart from its plugs.
func carried_body_pose() -> Dictionary:
	if _body == null or not is_instance_valid(_body):
		return {}
	var p := _body.global_position
	var r := _body.global_rotation_degrees
	return {"position": [p.x, p.y, p.z], "rotation": [r.x, r.y, r.z]}


func restore_carried_body(data: Dictionary) -> void:
	if _body == null or not is_instance_valid(_body) or data.is_empty():
		return
	var pos: Array = data.get("position", [])
	var rot: Array = data.get("rotation", [])
	if pos.size() == 3:
		_body.global_position = Vector3(pos[0], pos[1], pos[2])
	if rot.size() == 3:
		_body.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	_build_ropes.call_deferred()


## Out of everything, and whatever is in its inlet out of it, then freed.
func drop_and_free() -> void:
	for plug: PowerPlug in [wall_plug, dc_plug]:
		var holder := _holder(plug)
		if holder != null:
			holder.drop_object()
	if inlet != null and inlet.picked_up_object != null:
		inlet.drop_object()
	queue_free()
