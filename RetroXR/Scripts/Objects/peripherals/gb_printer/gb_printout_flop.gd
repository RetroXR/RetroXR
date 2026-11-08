## GbPrintoutFlop — a torn-off Game Boy Printer print bends as paper, not a board.
##
## A print is a Poster: a flat sticker. Stuck to something it stays one. Loose,
## it is the paper it was on the printer, curled by the roll and given to its
## weight: held, it hangs from the hand both ways along its length, swings as the
## hand moves and stops. Loose, its body carries the fall and surface recovery;
## its ribbon keeps relaxing toward the roll's curl without impact creases.
##
## A single 3D thermal ribbon carries both edges. Only a held row is pinned;
## release preserves every particle and velocity and removes that pin. The
## body's segment colliders follow the ribbon instead of retaining a flat board.
class_name GbPrintoutFlop
extends Node

const NODE_NAME := "PrintoutFlop"
## A print torn off the printer carries the bend it had there (rad/m) as this
## meta, and starts bent so, then relaxes as it hangs.
const BEND_META := &"gb_printout_bend"
const STATE_META := &"gb_printout_state"
## Actual vertex displacement must stay quiet for this long before sleeping.
const SETTLED := 0.0005
const SETTLE_TIME := 0.5
## A loose print whose body STAYS within this of one pose (meters, radians) for
## SETTLE_TIME, its sheet quiet, is settled: put to sleep and left alone. A
## curled print on a table rocks up to ~0.05 rad for ever (measured, the drop
## test): the turn allowed must cover that. A print tipping over speeds up and
## leaves it at once. No support is asked for: falling, it drifts 3 mm in 25 ms.
const SETTLE_DRIFT := 0.003
const SETTLE_TURN := 0.08
## How often the surface under a loose print is looked for, seconds, how far
## down, and how far each way the patch found reaches.
const FLOOR_EVERY := 0.25
const FLOOR_REACH := 0.3
const PATCH_REACH := 0.025
## How wide the highlight round the print is, meters (GbPaperRim).
const RIM := 0.0015
## A point of the mesh moving less than this (meters) is not worth redrawing.
const REDRAW := 0.00005

var _poster: Poster
var _flat: MeshInstance3D
var _mesh: MeshInstance3D
var _arrays := ArrayMesh.new()
var _ribbon := GbThermalRibbon.new()
var _quiet := 0.0
var _body_segments: Array[CollisionShape3D] = []
var _flat_body: CollisionShape3D
var _body_was_disabled := false
var _body_owned := false
var _motion := GbPaperMotion.new()
var _was_held := false
var _was_stuck := false
## The desktop hand held it flat last frame (see _desktop_holds).
var _was_rigid := false
var _support_quiet := 0.0
## Settled on its support: put to sleep, and nothing here runs until it is
## taken, stuck, or its body is moved past SETTLE_DRIFT / SETTLE_TURN.
var _settled := false
## Where the body was when its current quiet spell began, and where it settled.
var _rest_pose := Transform3D()
var _settled_pose := Transform3D()
var _floor_hit: Array = []
var _paper_sweep := GbPaperSweep.new()
var _floor_wait := 0.0
var _size := Vector2.ZERO
var _last_pose := Transform3D()
var _drawn := PackedVector3Array()
## The highlight round the print while it bends (the Poster's flat rim, behind
## a flat sheet, covered a bent one held in the hand), and whether it is ours.
var _rim: MeshInstance3D
var _rim_owned := false


## Whether `poster` is a print off the Game Boy Printer: marked so when torn off,
## or (a print saved before the mark) its picture is in the prints folder.
static func is_printout(poster: Poster) -> bool:
	if poster.printout:
		return true
	if poster.image_path.is_empty():
		return false
	var prints_dir := DataPaths.media_root(GbPrinter.PRINTS_DIR).simplify_path()
	return poster.image_path.simplify_path().begins_with(prints_dir)


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
	_flat_body = _poster.get_node("CollisionShape3D") as CollisionShape3D
	if _poster == null or _flat == null:
		set_process(false)
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "FlopMesh"
	_mesh.mesh = _arrays
	_flat.get_parent().add_child(_mesh)
	_mesh.transform = _flat.transform
	_rim = MeshInstance3D.new()
	_rim.name = "FlopRim"
	_rim.add_to_group("outline_exclude")
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.visible = false
	_rim.material_override = GbPaperRim.material(Poster.OUTLINE_COLOR)
	_flat.get_parent().add_child(_rim)
	_rim.transform = _flat.transform


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if _poster.is_stuck():
		_mesh.visible = false
		_flat.visible = true
		_own_rim(false)
		_own_body(false)
		_motion.reset()
		_paper_sweep.reset()
		_quiet = 0.0
		_was_held = false
		_was_stuck = true
		_support_quiet = 0.0
		_settled = false
		return
	if _poster.is_previewing():
		# The Poster has slid its Surface to where the print would stick, and the
		# bent mesh rides on that Surface: show the flat sticker there instead,
		# and hold the paper as it was until the hand takes it away again.
		if _mesh.visible:
			print("[GbPrinter] print previews a stick: flat sheet shown, paper paused")
		_mesh.visible = false
		_flat.visible = true
		_own_rim(false)
		_motion.reset()
		_paper_sweep.reset()
		_drawn.clear()
		_quiet = 0.0
		_support_quiet = 0.0
		_settled = false
		return
	if _desktop_holds():
		# In the desktop hand the print is a sheet to LOOK at: flat and still, so
		# turning it (middle drag) and sizing it (Q/E) work as for any poster. The
		# hand trails the gaze, and a pinned ribbon swung and curled with every
		# step of it (2026-11-08, "it floats and keeps moving"). Same look as a
		# stuck sticker; on release the paper is laid again with its curl below.
		if not _was_rigid:
			print("[GbPrinter] %s held by the desktop hand: shown flat and still" % _poster.name)
		_mesh.visible = false
		_flat.visible = true
		_own_rim(false)
		_own_body(false)
		_motion.reset()
		_paper_sweep.reset()
		_drawn.clear()
		_quiet = 0.0
		_support_quiet = 0.0
		_settled = false
		_was_held = false
		_was_rigid = true
		return
	var size := _poster.get_sheet_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _poster.has_meta(STATE_META):
		adopt_state(_poster.get_meta(STATE_META), size)
		_poster.remove_meta(STATE_META)
	elif _size != size or _was_stuck or _was_rigid:
		_size = size
		var bend := 0.0 if _was_stuck else float(_poster.get_meta(BEND_META, 1.0 / GbThermalRibbon.CURL_RADIUS))
		if _was_rigid:
			print("[GbPrinter] %s let go of the desktop hand: paper laid again (size %.1f x %.1f mm)" % [
				_poster.name, size.x * 1000.0, size.y * 1000.0])
		if _poster.has_meta(BEND_META):
			_poster.remove_meta(BEND_META)
		_ribbon.configure(size.y, size.x, bend)
		_drawn.clear()
		_quiet = 0.0
	_was_stuck = false
	_was_rigid = false
	var held := _poster.is_picked_up()
	if held and not _was_held:
		var by := _poster.get_picked_up_by()
		_ribbon.pin_nearest(_poster.to_local(by.global_position) if by != null else Vector3.ZERO)
		_quiet = 0.0
	elif not held and _was_held:
		_ribbon.unpin()
		_quiet = 0.0
	_was_held = held
	if _settled:
		# Awake is not disturbed: Jolt wakes a sleeping body whenever an awake one
		# touches it (in the room, the printer it came out of). Woken, the body
		# drops ~1 mm, because the height it settled at is the contact recovery's
		# and Jolt rests the colliders a little lower, into the table (measured in
		# the room). Resuming on that put the print straight back into the loop it
		# had settled out of; it is put back and to sleep instead, one transform
		# write. Only a hand, or a real move (a knock, its table gone: a fall is
		# 3 mm in 25 ms), brings the sheet back to life.
		var now := _poster.global_transform
		var drift := now.origin.distance_to(_settled_pose.origin)
		var turn := now.basis.get_rotation_quaternion().angle_to(
			_settled_pose.basis.get_rotation_quaternion())
		if not held and drift < SETTLE_DRIFT and turn < SETTLE_TURN:
			if not _poster.sleeping:
				_poster.global_transform = _settled_pose
				_poster.linear_velocity = Vector3.ZERO
				_poster.angular_velocity = Vector3.ZERO
				_poster.force_update_transform()
				_poster.sleeping = true
			return
		_settled = false
		_quiet = 0.0
		_support_quiet = 0.0
		print("[GbPrinter] settled print stirs: %s (moved %.2f mm, turned %.3f rad)" % [
			"picked up" if held else "moved", drift * 1000.0, turn])
	var xf := _poster.get_global_transform_interpolated()
	var still := xf.is_equal_approx(_last_pose)
	_last_pose = xf
	_floor_wait -= delta
	# Periodically wake even a still print: the table beneath it can move.
	if still and not held and _quiet >= SETTLE_TIME and _floor_wait > 0.0:
		return
	_motion.update(xf, Vector3.ZERO, delta)
	if _floor_wait <= 0.0:
		_floor_wait = FLOOR_EVERY
		_find_floor(xf)
	_sweep_floor(xf)
	_place_floor(xf)
	# A held sheet bends under the hand's acceleration. Once loose, the rigid
	# body owns falling and impact impulses; feeding those back into the ribbon
	# makes its moving colliders and the body's collision solver drive each other.
	_ribbon.step(delta, _motion.gravity if held else Vector3.ZERO,
		_motion.angular_accel if held else Vector3.ZERO)
	if not held and not _ribbon.body_shift.is_zero_approx():
		_poster.global_position += xf.basis * _ribbon.body_shift
		var normal := (xf.basis * _ribbon.support_normal).normalized()
		_poster.linear_velocity -= normal * minf(0.0, normal.dot(_poster.linear_velocity))
	# Settled is judged by where the body STAYS, not by its speeds. On a table the
	# contact recovery above and Jolt trade a fraction of a millimetre every frame
	# (or rock a curled sheet slightly) for ever, so the speeds never went quiet,
	# the body never slept, and each print cost ~1 ms a frame (2026-11-04). The
	# turn allowed is small, so an edge-first landing still tips over.
	var near_rest := xf.origin.distance_to(_rest_pose.origin) < SETTLE_DRIFT \
		and xf.basis.get_rotation_quaternion().angle_to(
			_rest_pose.basis.get_rotation_quaternion()) < SETTLE_TURN
	if not held and _ribbon.move_speed < SETTLED and near_rest:
		_support_quiet += delta
	else:
		_support_quiet = 0.0
		_rest_pose = xf
	_quiet = _quiet + delta if still and not held and _ribbon.move_speed < SETTLED else 0.0
	# Sleep only on a frame that refits nothing and with the lift above already
	# handed to Jolt: a refit is committed at Jolt's next step and a moved node's
	# transform reaches the server when transforms are flushed, and BOTH wake
	# the body (JoltBody3D::_shapes_committed, _transform_changed). Set before
	# either, every sleep here was undone a step later.
	if _support_quiet >= SETTLE_TIME and not _needs_redraw():
		_poster.force_update_transform()
		_settled = true
		_settled_pose = _poster.global_transform
		_poster.sleeping = true
		print("[GbPrinter] print settled at %s, body put to sleep" % _poster.global_position)
		return
	_draw(size)


## Whether the desktop hand (mouse and keyboard) is holding the print. A headset's
## hands keep the hanging, swinging paper; the desktop one has no hand to feel it.
func _desktop_holds() -> bool:
	if not _poster.is_picked_up():
		return false
	var by := _poster.get_picked_up_by()
	return is_instance_valid(by) and by.is_in_group("desktop_hand")


func adopt_state(state: Dictionary, size: Vector2) -> void:
	_ribbon.restore(state)
	_size = size
	_drawn.clear()
	_quiet = 0.0
	_draw(size)


## Sample along both edges, so an overhanging end does not rest on an imagined
## 60 cm wide patch under the center of the sheet.
func _find_floor(xf: Transform3D) -> void:
	_floor_hit.clear()
	var own := _own_rids()
	for i in range(0, _ribbon.positions.size(), 4):
		var at := xf * _ribbon.positions[i]
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.015, at + Vector3.DOWN * FLOOR_REACH)
		query.exclude = own
		var hit := _poster.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_floor_hit.append([hit["position"], hit["normal"]])


func _own_rids() -> Array[RID]:
	var own: Array[RID] = [_poster.get_rid()]
	for body in _poster.find_children("*", "CollisionObject3D", true, false):
		own.append((body as CollisionObject3D).get_rid())
	return own


func _place_floor(xf: Transform3D) -> void:
	_ribbon.patches.clear()
	for hit: Array in _floor_hit + _paper_sweep.hits:
		var covector: Vector3 = xf.basis.transposed() * (hit[1] as Vector3)
		var normal := covector.normalized()
		var at: Vector3 = xf.affine_inverse() * (hit[0] as Vector3)
		var depth := (float(hit[2]) if hit.size() > 2 else 0.03) / covector.length()
		_ribbon.patches.append([normal, normal.dot(at), at, PATCH_REACH, depth])


func _sweep_floor(xf: Transform3D) -> void:
	var pts := PackedVector3Array()
	for p in _ribbon.positions:
		pts.append(xf * p)
	_paper_sweep.update(_poster.get_world_3d().direct_space_state, pts, _own_rids(), PATCH_REACH)


func _own_body(on: bool) -> void:
	if _body_owned == on:
		return
	if on:
		_body_was_disabled = _flat_body.disabled
	_flat_body.disabled = true if on else _body_was_disabled
	for shape in _body_segments:
		shape.disabled = not on
	if not on:
		_poster._apply_dimensions()
		(_poster.get_node("PointerArea/CollisionShape3D") as CollisionShape3D).position = Vector3.ZERO
	_body_owned = on


## One thin oriented box per segment. The body's support and the pointer bounds
## follow the curved sheet, including twist. Sticking restores the flat body.
func _fit_body(centers: PackedVector3Array, across: PackedVector3Array) -> void:
	while _body_segments.size() > _ribbon.segments:
		var old := _body_segments.pop_back() as CollisionShape3D
		_poster.remove_child(old)
		old.queue_free()
	while _body_segments.size() < _ribbon.segments:
		var shape := CollisionShape3D.new()
		shape.name = "PaperSegment%d" % _body_segments.size()
		shape.shape = BoxShape3D.new()
		_poster.add_child(shape)
		_body_segments.append(shape)
	for i in _ribbon.segments:
		var y := (centers[i + 1] - centers[i]).normalized()
		var x := (across[i] + across[i + 1]).normalized()
		var z := x.cross(y).normalized()
		x = y.cross(z).normalized()
		var shape := _body_segments[i]
		(shape.shape as BoxShape3D).size = Vector3(_size.x, centers[i].distance_to(centers[i + 1]), 0.0008)
		shape.transform = Transform3D(Basis(x, y, z), (centers[i] + centers[i + 1]) * 0.5)
	_own_body(true)
	_poster.mass = maxf(0.0001, _ribbon.length * 0.0057 * _ribbon.width / 0.038)
	var bounds := AABB(_ribbon.positions[0], Vector3.ZERO)
	for p in _ribbon.positions:
		bounds = bounds.expand(p)
	var pointer := _poster.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	pointer.position = bounds.get_center()
	(pointer.shape as BoxShape3D).size = bounds.size + Vector3.ONE * 0.004


## Whether the sheet has moved enough since it was last drawn to be drawn (and
## its colliders refit) again.
func _needs_redraw() -> bool:
	var verts := _ribbon.positions
	if verts.size() != _drawn.size() or not _body_owned:
		return true
	for i in verts.size():
		if verts[i].distance_squared_to(_drawn[i]) > REDRAW * REDRAW:
			return true
	return false


func _draw(_sheet_size: Vector2) -> void:
	if not _needs_redraw():
		return
	var verts := _ribbon.positions
	_drawn = verts.duplicate()
	var centers := _ribbon.centers()
	var across := _ribbon.across()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var along := PackedVector3Array()
	var vs := PackedFloat32Array()
	var index := PackedInt32Array()
	for i in centers.size():
		var tangent := (centers[mini(i + 1, _ribbon.segments)] - centers[maxi(i - 1, 0)]).normalized()
		var normal := across[i].cross(tangent).normalized()
		var v := 1.0 - float(i) / _ribbon.segments
		along.append(tangent)
		vs.append(v)
		normals.append_array(PackedVector3Array([normal, normal]))
		uvs.append_array(PackedVector2Array([Vector2(1.0, v), Vector2(0.0, v)]))
		if i < _ribbon.segments:
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
	_rim.mesh = GbPaperRim.build(centers, along, Vector3.RIGHT, _size.x * 0.5, RIM, vs, across)
	_own_rim(true)
	_fit_body(centers, across)


## Whether this draws the print's rim (bent) or the Poster does (flat, stuck).
func _own_rim(on: bool) -> void:
	if on == _rim_owned:
		return
	_rim_owned = on
	_poster.outline_drawn_by = self if on else null
	if not on:
		_rim.visible = false
	_poster._refresh_outline()


## The Poster's answer to whether its rim shows now (outline_drawn_by).
func show_outline(on: bool) -> void:
	_rim.visible = on and _rim_owned
