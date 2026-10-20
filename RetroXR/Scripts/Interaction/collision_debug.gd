## CollisionDebug — draw every collision shape in the running scene, coloured by
## the layer it sits on. Toggled from OPTIONS > General.
##
## Godot's own "Visible Collision Shapes" only works when the tree is launched
## with debug_collisions_hint already set, draws everything in one colour, and is
## not reachable from an exported build or a headset. The interesting question
## here is almost always *which* layer a volume is on — a console's grab box, its
## enclosing pointer box and a snap zone's reach are three different things in
## the same few centimetres, and they behave completely differently.
##
## Each shape's overlay is parented to the CollisionObject3D that owns it and
## carries that shape owner's local transform, so it tracks anything that moves
## with no per-frame work of our own. Drawn with depth testing off, because a
## volume you cannot see through the shell around it is the one you need to look
## at.
class_name CollisionDebug
extends Node

## Re-scan interval. Objects get spawned, shells land and models resize their
## boxes long after a scene starts, so the view has to keep looking.
const RESCAN_SECONDS := 0.5

## Draw the PLAYER's own volumes too — both hands' grab and pose areas, the pointer
## and the body capsule.
##
## Off, because they ride the camera: they sit in the middle of the view wherever you
## stand and travel with you, so they obscure the thing you turned the overlay on to
## look at and never hold still long enough to read. The room's volumes are the ones
## worth seeing. Flip it when the question is about the hands themselves.
const SHOW_PLAYER := false

## Colour per layer NUMBER (1-based, as project.godot names them).
const LAYER_COLORS := {
	1: Color(0.45, 0.45, 0.50),   # World
	3: Color(0.30, 0.90, 0.40),   # Pickable
	17: Color(0.20, 0.90, 0.90),  # XRHand_SnapZone
	18: Color(0.30, 0.50, 1.00),  # XRHand_Physics
	19: Color(0.10, 0.75, 0.65),  # XRPickable
	20: Color(1.00, 0.65, 0.15),  # XRButton
	21: Color(1.00, 0.25, 0.85),  # XRPointer
	22: Color(0.95, 0.95, 0.25),  # XRPoseDetector
	23: Color(1.00, 0.30, 0.25),  # XRPointerSuppress
}
## Anything on no layer at all — a monitoring-only area, or a body a script has
## switched off. Worth seeing: "it is there but on layer 0" explains a lot.
const UNLAYERED_COLOR := Color(0.55, 0.35, 0.75)

static var _instance: CollisionDebug = null

## Edge-only copies of the engine's debug meshes, keyed by that mesh's RID. Static
## so every cabinet of the same kind shares one set.
static var _wire_cache: Dictionary = {}

var _overlays: Array[MeshInstance3D] = []
var _seen: Dictionary = {}
var _materials: Dictionary = {}
var _since_scan := 0.0
var _last_reported := -1


## True when the overlay is currently up.
static func is_enabled() -> bool:
	return is_instance_valid(_instance)


## Show or hide the overlay. `from` only has to be any node inside the tree.
static func set_enabled(from: Node, on: bool) -> void:
	if on == is_enabled():
		return
	if not on:
		_instance.queue_free()
		_instance = null
		return
	if from == null or not from.is_inside_tree():
		return
	var debug := CollisionDebug.new()
	debug.name = "CollisionDebug"
	_instance = debug
	from.get_tree().root.add_child(debug)


static func toggle(from: Node) -> bool:
	set_enabled(from, not is_enabled())
	return is_enabled()


func _ready() -> void:
	_scan()


func _exit_tree() -> void:
	for overlay in _overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_overlays.clear()
	_seen.clear()
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	_follow()
	_since_scan += delta
	if _since_scan < RESCAN_SECONDS:
		return
	_since_scan = 0.0
	_scan()


## Re-read each overlay's shape-owner transform.
##
## Being parented to the body covers a shape that moves because the BODY moved.
## A shape that moves within its body does not: the NES's bay flap is a box on
## the console's own two bodies, re-posed as the flap swings, and read once it
## would draw shut over an open bay. Assigned only on a change, so the room's
## static volumes cost a comparison and no transform propagation.
func _follow() -> void:
	for overlay in _overlays:
		if not is_instance_valid(overlay):
			continue
		var body := overlay.get_parent() as CollisionObject3D
		if body == null:
			continue
		var t: Transform3D = body.shape_owner_get_transform(overlay.get_meta(&"owner_id", 0))
		if overlay.transform != t:
			overlay.transform = t


func _scan() -> void:
	# Overlays die with the objects they ride, so drop the corpses first.
	var live: Array[MeshInstance3D] = []
	for overlay in _overlays:
		if is_instance_valid(overlay):
			live.append(overlay)
	_overlays = live

	var counts: Dictionary = {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		# Prune the whole player rig at its origin — see SHOW_PLAYER. One test covers
		# both hands, their grab, pose and pointer areas and the body capsule, because
		# every one of them hangs off XROrigin3D.
		#
		# Anything a hand is HOLDING still draws: a pickable stays where it is in the
		# tree and is driven by a grab driver rather than reparented under the
		# controller, so it is never inside this subtree to begin with.
		if not SHOW_PLAYER and node is XROrigin3D:
			continue
		for child in node.get_children():
			stack.append(child)
		var body := node as CollisionObject3D
		if body == null:
			continue
		var layer := _lowest_layer(body.collision_layer)
		for owner_id_raw in body.get_shape_owners():
			var owner_id := int(owner_id_raw)
			if body.is_shape_owner_disabled(owner_id):
				continue
			for i in body.shape_owner_get_shape_count(owner_id):
				counts[layer] = int(counts.get(layer, 0)) + 1
				_decorate(body, owner_id, i, layer)

	var total := _tally(counts)
	if total == _last_reported:
		return
	_last_reported = total
	_report(counts)


func _decorate(body: CollisionObject3D, owner_id: int, shape_id: int, layer: int) -> void:
	var key := "%d:%d:%d" % [body.get_instance_id(), owner_id, shape_id]
	if _seen.has(key):
		return
	var shape := body.shape_owner_get_shape(owner_id, shape_id)
	if shape == null:
		return
	var debug_mesh := _wire_of(shape.get_debug_mesh())
	if debug_mesh == null:
		return
	_seen[key] = true

	var overlay := MeshInstance3D.new()
	overlay.name = "CollisionDebugShape"
	overlay.mesh = debug_mesh
	overlay.material_override = _material_for(layer)
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.set_meta(&"owner_id", owner_id)
	# A picture of a box is not part of the thing: a plug's pointer target is fitted
	# to what it draws, and measuring this would grow it to the box it shows.
	overlay.add_to_group(PointerFit.EXCLUDE_GROUP)
	overlay.transform = body.shape_owner_get_transform(owner_id)
	# The overlay rides the body it describes, so a swinging flap or a carried
	# console takes its boxes with it for free.
	body.add_child(overlay)
	_overlays.append(overlay)


## Edges only, cached per source mesh RID.
##
## Shape3D.get_debug_mesh() hands back solid triangles, and a solid volume drawn
## with depth testing off paints out the model it is meant to describe — three
## nested boxes and you can see nothing at all. Every edge, drawn once.
static func _wire_of(solid: Mesh) -> ArrayMesh:
	if solid == null:
		return null
	var key: RID = solid.get_rid()
	var cached: ArrayMesh = _wire_cache.get(key)
	if cached != null:
		return cached

	var lines := PackedVector3Array()
	var seen: Dictionary = {}
	for s in solid.get_surface_count():
		var arrays := solid.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var primitive := Mesh.PRIMITIVE_TRIANGLES
		if solid is ArrayMesh:
			primitive = (solid as ArrayMesh).surface_get_primitive_type(s)
		if primitive == Mesh.PRIMITIVE_LINES:
			lines.append_array(verts)
			continue
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			continue

		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
			else PackedInt32Array()
		var count := index.size() if index.size() > 0 else verts.size()
		var tri := 0
		while tri + 2 < count:
			for e in 3:
				var a: Vector3 = verts[index[tri + e]] if index.size() > 0 else verts[tri + e]
				var b: Vector3 = verts[index[tri + (e + 1) % 3]] if index.size() > 0 \
					else verts[tri + (e + 1) % 3]
				if _add_edge(seen, a, b):
					lines.append(a)
					lines.append(b)
			tri += 3

	if lines.is_empty():
		return null
	var arrays_out := []
	arrays_out.resize(Mesh.ARRAY_MAX)
	arrays_out[Mesh.ARRAY_VERTEX] = lines
	var wire := ArrayMesh.new()
	wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays_out)
	_wire_cache[key] = wire
	return wire


## Record an undirected edge, ordered so a shared edge is only drawn once.
static func _add_edge(seen: Dictionary, a: Vector3, b: Vector3) -> bool:
	var snap := Vector3(1e-4, 1e-4, 1e-4)
	var p := a.snapped(snap)
	var q := b.snapped(snap)
	if p == q:
		return false
	var key := "%v|%v" % ([p, q] if _before(p, q) else [q, p])
	if seen.has(key):
		return false
	seen[key] = true
	return true


static func _before(p: Vector3, q: Vector3) -> bool:
	if p.x != q.x:
		return p.x < q.x
	if p.y != q.y:
		return p.y < q.y
	return p.z < q.z


## Lowest layer NUMBER this body is on, or 0 when it is on none.
func _lowest_layer(mask: int) -> int:
	for bit in 32:
		if mask & (1 << bit):
			return bit + 1
	return 0


func _material_for(layer: int) -> StandardMaterial3D:
	var cached: StandardMaterial3D = _materials.get(layer)
	if cached != null:
		return cached
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LAYER_COLORS.get(layer, UNLAYERED_COLOR)
	mat.no_depth_test = true
	mat.disable_fog = true
	mat.render_priority = 3
	_materials[layer] = mat
	return mat


func _tally(counts: Dictionary) -> int:
	var total := 0
	for n in counts.values():
		total += int(n)
	return total


## One line per layer, named as project.godot names them, so the colours in the
## room can be read back without counting bits.
func _report(counts: Dictionary) -> void:
	var layers := counts.keys()
	layers.sort()
	var parts: PackedStringArray = []
	for layer in layers:
		parts.append("%s x%d" % [_layer_name(int(layer)), int(counts[layer])])
	print("[collision] %d shapes — %s" % [_tally(counts), ", ".join(parts)])


func _layer_name(layer: int) -> String:
	if layer <= 0:
		return "(no layer)"
	var setting := "layer_names/3d_physics/layer_%d" % layer
	var named: String = str(ProjectSettings.get_setting(setting, ""))
	return "%d:%s" % [layer, named] if named != "" else str(layer)
