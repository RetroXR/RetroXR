## GbPrintoutFlop — a torn-off Game Boy Printer print bends as paper, not a board.
##
## A print is a Poster: a flat sticker. Stuck to something it stays one. Loose,
## it is the paper it was on the printer, curled by the roll and given to its
## weight: held, it hangs from the hand both ways along its length, swings as the
## hand moves and stops; lying on a table face down its ends curl up off it, face
## up they are pressed flat.
##
## Two GbPrinterStrips from the grip, one up the sheet (its +Y) and one down it,
## each the printer's own: the same curl, weight, swing and air (the lower one in
## the sheet's frame turned over in Y, so the curl goes the same way, toward the
## sheet's back, -Z). Drawn on a mesh beside the Poster's flat one under its
## Surface, which it hides while it bends; the Poster's body, pointer target and
## sticking are untouched. Asleep, it costs nothing: a print that has settled and
## is not moving is not stepped.
class_name GbPrintoutFlop
extends Node

const NODE_NAME := "PrintoutFlop"
## A print torn off the printer carries the bend it had there (rad/m) as this
## meta, and starts bent so, then relaxes as it hangs.
const BEND_META := &"gb_printout_bend"
## Settled below this (rad/s, both strips) and still, it sleeps.
const SETTLED := 0.002
## How often the surface under a loose print is looked for, seconds, how far
## down, and how far each way the patch found reaches.
const FLOOR_EVERY := 0.25
const FLOOR_REACH := 0.3
const PATCH_REACH := 0.3
## A point of the mesh moving less than this (meters) is not worth redrawing.
const REDRAW := 0.00005

var _poster: Poster
var _flat: MeshInstance3D
var _mesh: MeshInstance3D
var _arrays := ArrayMesh.new()
var _up := GbPrinterStrip.new()
var _down := GbPrinterStrip.new()
var _motion := GbPaperMotion.new()
var _grip := 0.0
var _was_held := false
var _floor_hit: Array = []
var _floor_wait := 0.0
var _size := Vector2.ZERO
var _last_pose := Transform3D()
var _drawn := PackedVector2Array()


## Whether `poster` is a print off the Game Boy Printer: marked so when torn off,
## or (a print saved before the mark) its picture is in the prints folder.
static func is_printout(poster: Poster) -> bool:
	if poster.printout:
		return true
	if poster.image_path.is_empty():
		return false
	var prints := DataPaths.media_root(GbPrinter.PRINTS_DIR).simplify_path()
	return poster.image_path.simplify_path().begins_with(prints)


## Give `poster` its flop, once.
static func attach(poster: Poster) -> void:
	if poster.has_node(NODE_NAME):
		return
	var flop := GbPrintoutFlop.new()
	flop.name = NODE_NAME
	poster.add_child(flop)


func _ready() -> void:
	_poster = get_parent() as Poster
	_flat = _poster.get_node_or_null("Surface/FlatMesh") as MeshInstance3D
	if _poster == null or _flat == null:
		set_process(false)
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "FlopMesh"
	_mesh.mesh = _arrays
	_flat.get_parent().add_child(_mesh)
	_mesh.transform = _flat.transform


func _process(delta: float) -> void:
	if _poster.is_stuck():
		# A sticker: flat, as the Poster draws it.
		_mesh.visible = false
		_flat.visible = true
		_motion.reset()
		return
	var size := _poster.get_sheet_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var held := _poster.is_picked_up()
	if held and not _was_held:
		_grip = _grip_at()
	elif not held:
		_grip = 0.0
	_was_held = held
	var half := size.y * 0.5
	_grip = clampf(_grip, -half + 0.002, half - 0.002)
	if size != _size:
		_size = size
		_up = GbPrinterStrip.new()
		_down = GbPrinterStrip.new()
		_drawn = PackedVector2Array()
	_up.set_length(half - _grip)
	_down.set_length(half + _grip)
	if _poster.has_meta(BEND_META):
		var bend := float(_poster.get_meta(BEND_META))
		_poster.remove_meta(BEND_META)
		_up.bend_to(bend)
		_down.bend_to(bend)
	_up.place(Vector2(_grip, 0.0), 0.0)
	_down.place(Vector2(-_grip, 0.0), 0.0)

	var xf := _poster.get_global_transform_interpolated()
	var still := xf.is_equal_approx(_last_pose)
	_last_pose = xf
	if still and not held and _up.motion() < SETTLED and _down.motion() < SETTLED and not _drawn.is_empty():
		return
	_motion.update(xf, Vector3(0.0, _grip, 0.0), delta)
	_floor_wait -= delta
	if _floor_wait <= 0.0:
		_floor_wait = FLOOR_EVERY
		_find_floor(xf)
	_place_floor(xf)
	var g := _motion.gravity
	var shove := _motion.shove
	var spin := _motion.spin_accel
	_up.step(delta, Vector2(g.y, g.z), spin, Vector2(shove.y, shove.z))
	_down.step(delta, Vector2(-g.y, g.z), -spin, Vector2(-shove.y, shove.z))
	_draw(size)


## Where along the sheet (its Y) the hand that took it holds it.
func _grip_at() -> float:
	var by := _poster.get_picked_up_by()
	if by == null:
		return 0.0
	return _poster.to_local(by.global_position).y


## The surface under the print, found every FLOOR_EVERY and kept in the room.
func _find_floor(xf: Transform3D) -> void:
	_floor_hit = []
	if not is_inside_tree():
		return
	var at := xf.origin
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.02, at + Vector3.DOWN * FLOOR_REACH)
	# Not the print, nor its own bodies: its pointer target is a StaticBody3D a
	# centimeter round the sheet, and taken for a surface it stood half the print
	# up off the table.
	var own: Array[RID] = [_poster.get_rid()]
	for body in _poster.find_children("*", "CollisionObject3D", true, false):
		own.append((body as CollisionObject3D).get_rid())
	query.exclude = own
	var hit := _poster.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_floor_hit = [hit["position"], hit["normal"]]


## That surface against the sheet as it is drawn now, one patch to each strip
## (the lower one's turned over in Y, as its strip is).
func _place_floor(xf: Transform3D) -> void:
	_up.patches.clear()
	_down.patches.clear()
	if _floor_hit.is_empty():
		return
	var n: Vector3 = xf.basis.orthonormalized().inverse() * (_floor_hit[1] as Vector3)
	var at: Vector3 = xf.affine_inverse() * (_floor_hit[0] as Vector3)
	var n2 := Vector2(n.y, n.z)
	if n2.length() < 0.3:
		return
	var off := n.dot(at) / n2.length()
	n2 /= n2.length()
	_up.patches.append([n2, off, Vector2(at.y, at.z), PATCH_REACH])
	_down.patches.append([Vector2(-n2.x, n2.y), off, Vector2(-at.y, at.z), PATCH_REACH])


## The sheet from the bottom of the lower strip, through the grip, to the top of
## the upper one, the picture laid along it by distance down the paper.
func _draw(size: Vector2) -> void:
	var rows := PackedVector2Array()
	var dist := PackedFloat64Array()
	var dn := _down.points
	for i in range(dn.size() - 1, -1, -1):
		rows.append(Vector2(-dn[i].x, dn[i].y))
		dist.append(_grip - i * (_down.length / maxi(_down.segments, 1)))
	var up := _up.points
	for i in range(1, up.size()):
		rows.append(up[i])
		dist.append(_grip + i * (_up.length / maxi(_up.segments, 1)))
	if rows.size() == _drawn.size():
		var moved := false
		for i in rows.size():
			if rows[i].distance_squared_to(_drawn[i]) > REDRAW * REDRAW:
				moved = true
				break
		if not moved:
			return
	_drawn = rows.duplicate()
	var half_w := size.x * 0.5
	var n := rows.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	verts.resize(n * 2)
	normals.resize(n * 2)
	uvs.resize(n * 2)
	for i in n:
		var a := rows[maxi(i - 1, 0)]
		var b := rows[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		# The picture's face: the sheet's +Z when it lies flat.
		var face := Vector3(0.0, -t.y, t.x)
		var p := Vector3(0.0, rows[i].x, rows[i].y)
		var v := 0.5 - dist[i] / size.y
		verts[i * 2] = p + Vector3(half_w, 0, 0)
		verts[i * 2 + 1] = p - Vector3(half_w, 0, 0)
		normals[i * 2] = face
		normals[i * 2 + 1] = face
		uvs[i * 2] = Vector2(1.0, v)
		uvs[i * 2 + 1] = Vector2(0.0, v)
	for i in n - 1:
		var r := i * 2
		index.append_array([r, r + 1, r + 2, r + 1, r + 3, r + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	_arrays.clear_surfaces()
	_arrays.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.material_override = _flat.get_surface_override_material(0)
	_mesh.visible = true
	_flat.visible = false
