## Broad phase for the finite surface patches sampled around printer paper.
## Bounds only discard impossible contacts; the solvers keep their exact tests
## and original patch order. Large recovery patches stay in an unbinned list.
class_name GbPaperContacts
extends RefCounted

const CELL := 0.04
const MAX_CELLS := 64
const PAD := 0.000001

var _cells: Dictionary[Vector3i, PackedInt32Array] = {}
var _large := PackedInt32Array()
var _empty := PackedInt32Array()
var _shift := Vector3.ZERO


func build_2d(patches: Array, skin: float, default_depth: float) -> void:
	_clear()
	for i in patches.size():
		var patch: Array = patches[i]
		var n: Vector2 = patch[0]
		var center: Vector2 = patch[2]
		var depth := float(patch[4]) if patch.size() > 4 else default_depth
		center += n * (float(patch[1]) + skin - depth * 0.5 - n.dot(center))
		var half := Vector2(absf(n.y), absf(n.x)) * float(patch[3]) + n.abs() * depth * 0.5
		_insert(i, AABB(Vector3(center.x - half.x, center.y - half.y, 0), Vector3(half.x * 2, half.y * 2, 0)).grow(PAD))


func build_3d(patches: Array, skin: float) -> void:
	_clear()
	for i in patches.size():
		var patch: Array = patches[i]
		var n: Vector3 = patch[0]
		var center: Vector3 = patch[2]
		var depth := float(patch[4])
		center += n * (float(patch[1]) + skin - depth * 0.5 - n.dot(center))
		# Axis-aligned bounds of the patch's disk extruded along its normal.
		var half := Vector3(sqrt(maxf(0, 1 - n.x * n.x)), sqrt(maxf(0, 1 - n.y * n.y)),
			sqrt(maxf(0, 1 - n.z * n.z))) * float(patch[3]) + n.abs() * depth * 0.5
		_insert(i, AABB(center - half, half * 2).grow(PAD))


func _clear() -> void:
	_cells.clear()
	_large.clear()
	_shift = Vector3.ZERO


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))


func _insert(index: int, bounds: AABB) -> void:
	var lo := _cell(bounds.position)
	var hi := _cell(bounds.end)
	var size := hi - lo + Vector3i.ONE
	if size.x * size.y * size.z > MAX_CELLS:
		_large.append(index)
		return
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				# A fresh packed array for each new cell: sharing _empty here
				# aliases all buckets and grows even the missing-cell result.
				var entries: PackedInt32Array = _cells.get(key, PackedInt32Array())
				entries.append(index)
				_cells[key] = entries


## The caller moved all patches by -shift when recovering the body's position.
func shift_frame(shift: Vector3) -> void:
	_shift += shift


func query(p: Vector3) -> PackedInt32Array:
	var nearby: PackedInt32Array = _cells.get(_cell(p + _shift), _empty)
	if not _large.is_empty():
		# Packed arrays are shared by reference; never append to a stored bucket.
		nearby = nearby.duplicate()
		nearby.append_array(_large)
		nearby.sort()
	return nearby
