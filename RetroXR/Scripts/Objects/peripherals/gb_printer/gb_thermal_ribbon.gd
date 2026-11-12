## GbThermalRibbon — the Game Boy Printer's thermal paper, wherever it is.
##
## One sheet and one solver (paper-godot's PaperSheetSolver, which says how it
## bends, meets things and rubs on them) for all three places the paper is found:
##
##   on the printer   fed out of the slot (set_slot, set_out): the rows still in
##                    the slot are pinned along it and slide out as lines print,
##                    so what is out is the same paper it was a line ago;
##   in a hand        a torn print, the row in the hand pinned (pin_nearest);
##   loose            nothing pinned; its rigid body owns the fall and this only
##                    relaxes its bend (GbPrintoutFlop).
##
## Two particles a row, one on each edge, in the frame of the body the paper
## belongs to (the printer, the print). This class keeps the sheet, lays fresh
## paper, feeds it and hands a torn length over; it steps nothing itself. Where
## paper-godot is not loaded the paper holds its shape and says so once.
##
## It was two models: a 2D chain of hinges on the printer (GbPrinterStrip) and
## this sheet for a torn print, each also kept as a GDScript solver and a native
## port matched to the bit. The chain is gone (docs/dev/gb-printer.md says why).
class_name GbThermalRibbon
extends RefCounted

## The curl the roll leaves in the paper, as a radius, meters: judged from
## photographs of prints, not measured.
const CURL_RADIUS := 0.065
## Half the paper's thickness and a little: how far off a surface it lies (the
## solver's SKIN), and how far behind a patch of surface paper still counts as
## in it rather than on its far side (under the table it hangs over).
const SKIN := 0.0004
const PATCH_DEPTH := 0.03
## A row every ROW of paper, meters, and no more than MAX_ROWS of them: past
## 1.2 m out the rows are made twice as far apart instead (_coarsen). The paper
## bends over its own weight in about 8 cm, so a row has to be well under that
## for the sheet to draw a curve; at the old 48 rows a metre of it was a
## polyline of 2 cm facets.
const ROW := 0.006
const MAX_ROWS := 200
## Paper this near the slot is the slot's, never pushed by the printer's boxes:
## the slot is in the printer's top, inside its body's box.
const CONTACT_FROM := 0.008
## A knock or a flick turns the paper about the slot; no farther out than this
## is it carried by the turn, meters.
const JOLT_REACH := 0.04
## The fastest paper comes out of the slot, m/s (the printer's own feed is a
## twentieth of it; at 0.5 a strip arriving whole was shot out hard enough to
## kink 82 degrees over the printer's back edge), and the longest a fresh end of
## roll is laid at once.
const FEED_MAX := 0.2
const FRESH_MAX := 0.03
## The paper is stepped in steps of STEP seconds, always: a frame takes as many
## whole ones as have come due (what is left over waits for the next), and no
## more than MAX_STEPS however long it was, so a hitch is not caught up. Cut to
## fit each frame instead, the paper never came to rest in a window: where it
## rests depends a little on the step, and no two frames' were alike.
const STEP := 1.0 / 240.0
const MAX_STEPS := 8
const MAX_FRAME := STEP * MAX_STEPS
## The solver's own limit, for what is said about it here: the fastest any point
## of the paper moves against its frame, m/s.
const MAX_SPEED := 0.8

var length := 0.0
var width := 0.038
## How far apart the rows are, and how many gaps between them.
var ds := 0.0
var segments := 0
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
## Rows held where they are told (two positions a row).
var pin_rows := PackedInt32Array()
var pin_positions := PackedVector3Array()
## Surface patches: [normal, offset, center, reach, depth] in the body's frame.
var patches: Array = []
## The body's own boxes, which rows before `box_free_rows` do not meet.
var boxes: Array[AABB] = []
var box_free_rows := 0
## Fingertips: [center, radius].
var fingers: Array = []
## The fastest any particle moved over the last step, m/s.
var move_speed := 0.0
## Loose-sheet contact recovery belongs to the rigid body, not to a crease.
## The caller applies this local translation after step(). Patches are shifted
## into the recovered body's frame as the solve advances.
var body_shift := Vector3.ZERO
var support_normal := Vector3.ZERO
## Paper past the slot, meters; 0 for a sheet that is not being fed. `wanted`
## is what set_out asked for, which `out` reaches at FEED_MAX at most.
var out := 0.0
var wanted := 0.0
## A knock or flick since the last step (jolt): something to wake for.
var jolted := false

var _slot := Vector3.ZERO
var _slot_dir := Vector3.UP
var _slot_across := Vector3.RIGHT
var _solver: Object = null
## Time not yet stepped, seconds (under one STEP).
var _due := 0.0
static var _said := false


# --- A sheet on its own (a torn print) -------------------------------------------

func configure(sheet_length: float, sheet_width: float, curvature := 1.0 / CURL_RADIUS) -> void:
	length = sheet_length
	width = sheet_width
	out = 0.0
	segments = clampi(ceili(length / ROW), 2, MAX_ROWS - 1)
	ds = length / segments
	positions.resize((segments + 1) * 2)
	velocities.resize(positions.size())
	velocities.fill(Vector3.ZERO)
	var center := Vector3.ZERO
	# Start with an open arc even for a very long print. Contact, rather than an
	# initially intersecting circle, decides how subsequent turns lie together.
	var turn := clampf(curvature * ds, -(TAU - 0.2) / segments, (TAU - 0.2) / segments)
	for row in segments + 1:
		positions[2 * row] = center + Vector3.RIGHT * width * 0.5
		positions[2 * row + 1] = center - Vector3.RIGHT * width * 0.5
		var angle := (row + 0.5 - segments * 0.5) * turn
		center += Vector3(0.0, cos(angle), -sin(angle)) * ds
	var mean := _mean(positions)
	for i in positions.size():
		positions[i] -= mean
	unpin()


## Exact snapshot of a sheet at tear time. Each row contains its two edges.
func restore(state: Dictionary) -> void:
	positions = (state["positions"] as PackedVector3Array).duplicate()
	velocities = (state["velocities"] as PackedVector3Array).duplicate()
	length = float(state["length"])
	width = float(state["width"])
	out = 0.0
	@warning_ignore("integer_division")
	segments = positions.size() / 2 - 1
	ds = length / maxi(segments, 1)
	unpin()


func snapshot() -> Dictionary:
	return {"positions": positions.duplicate(), "velocities": velocities.duplicate(), "length": length, "width": width}


func pin_nearest(at: Vector3) -> void:
	var nearest := INF
	var row := 0
	var mid := centers()
	for i in mid.size():
		var distance := mid[i].distance_squared_to(at)
		if distance < nearest:
			nearest = distance
			row = i
	pin_rows = PackedInt32Array([row])
	pin_positions = PackedVector3Array([positions[2 * row], positions[2 * row + 1]])


func unpin() -> void:
	pin_rows = PackedInt32Array()
	pin_positions = PackedVector3Array()


# --- Paper out of a slot (on the printer) ----------------------------------------
#
# Rows are counted from the slot: row 0 and 1 are still inside it, pinned on its
# line, and the last row is the paper's free end. A row is a place ON THE PAPER,
# a whole number of `ds` from the free end, so feeding moves the pinned rows out
# along the slot and never re-lays what is already out. When the row nearest the
# mouth comes out it is let go and another is put in behind it.

## Where the slot is, which way it sends the paper and which way the paper lies
## across it, in the body's frame.
func set_slot(at: Vector3, dir: Vector3, across_axis: Vector3) -> void:
	_slot = at
	_slot_dir = dir.normalized()
	_slot_across = across_axis.normalized()
	if out > 0.0 and positions.size() >= 4:
		_pin_slot()


## Ask for `paper` meters past the slot. More is paper fed: what was out keeps
## its shape and is pushed on, as fast as it arrives up to FEED_MAX, so a strip
## that arrives whole still comes out of the slot rather than appearing inside
## the table. Less is a tear (or the power going off): a fresh end of roll, laid
## at the roll's curl and at rest.
func set_out(paper: float) -> void:
	if paper <= 0.0:
		return
	if out <= 0.0 or paper < out:
		_lay_fresh(minf(paper, FRESH_MAX))
	wanted = paper
	_feed(minf(wanted, out + ds))


## Whether paper asked for is still on its way out.
func feeding() -> bool:
	return wanted > out + 1e-7


func _feed(paper: float) -> void:
	if paper <= out:
		return
	out = paper
	length = out
	_fit_rows()
	if segments + 1 > MAX_ROWS:
		_coarsen()
	_pin_slot()


## How far along the paper from the slot row `row` is; negative inside it.
func row_out(row: int) -> float:
	return out - (segments - row) * ds


func _rows_for(paper: float, spacing: float) -> int:
	return ceili(paper / spacing - 1e-6) + 2


## As many rows as `out` needs at this `ds`, added or taken at the slot's end.
func _fit_rows() -> void:
	var need := _rows_for(out, ds)
	@warning_ignore("integer_division")
	var have := positions.size() / 2
	while have < need:
		# The row at the mouth is out now: let go where the slot has pushed it to.
		if have >= 2:
			var past := out - (have - 2) * ds
			var c := _slot + _slot_dir * past
			positions[2] = c + _slot_across * width * 0.5
			positions[3] = c - _slot_across * width * 0.5
			velocities[2] = Vector3.ZERO
			velocities[3] = Vector3.ZERO
		for k in 2:
			positions.insert(0, _slot)
			velocities.insert(0, Vector3.ZERO)
		have += 1
	while have > need and have > 2:
		for k in 2:
			positions.remove_at(0)
			velocities.remove_at(0)
		have -= 1
	segments = have - 1


## The rows inside the slot, on its line.
func _pin_slot() -> void:
	pin_rows = PackedInt32Array([0, 1])
	pin_positions.resize(4)
	for row in 2:
		var c := _slot + _slot_dir * row_out(row)
		pin_positions[2 * row] = c + _slot_across * width * 0.5
		pin_positions[2 * row + 1] = c - _slot_across * width * 0.5
		positions[2 * row] = pin_positions[2 * row]
		positions[2 * row + 1] = pin_positions[2 * row + 1]
		velocities[2 * row] = Vector3.ZERO
		velocities[2 * row + 1] = Vector3.ZERO
	# Paper within CONTACT_FROM of the mouth does not meet the body's boxes.
	box_free_rows = 2
	while box_free_rows <= segments and row_out(box_free_rows) < CONTACT_FROM:
		box_free_rows += 1


## A fresh end of roll, `new_out` long: out of the slot and round at the roll's
## curl, short of a closed loop however long it is, at rest.
func _lay_fresh(new_out: float) -> void:
	out = new_out
	length = out
	ds = ROW
	while _rows_for(out, ds) > MAX_ROWS:
		ds *= 2.0
	var rows := _rows_for(out, ds)
	segments = rows - 1
	positions.resize(rows * 2)
	velocities.resize(rows * 2)
	velocities.fill(Vector3.ZERO)
	var turn := minf(ds / CURL_RADIUS, (TAU - 0.2) / rows)
	var heading := _slot_dir
	var c := _slot
	for row in range(2, rows):
		var step := row_out(row) - maxf(row_out(row - 1), 0.0)
		# Toward the side the bend constraint curls to: heading x across.
		var normal := heading.cross(_slot_across).normalized()
		heading = (heading * cos(turn) + normal * sin(turn)).normalized()
		c += heading * step
		positions[2 * row] = c + _slot_across * width * 0.5
		positions[2 * row + 1] = c - _slot_across * width * 0.5
	_pin_slot()


## Rows twice as far apart: every other one kept, counted from the free end so
## the kept ones are still the same places on the paper.
func _coarsen() -> void:
	@warning_ignore("integer_division")
	var rows := positions.size() / 2
	var kept_p := PackedVector3Array()
	var kept_v := PackedVector3Array()
	for row in rows:
		if (rows - 1 - row) % 2 == 0:
			kept_p.append(positions[2 * row])
			kept_p.append(positions[2 * row + 1])
			kept_v.append(velocities[2 * row])
			kept_v.append(velocities[2 * row + 1])
	positions = kept_p
	velocities = kept_v
	ds *= 2.0
	print("[GbPrinter] paper %.2f m out: rows now %.0f mm apart" % [out, ds * 1000.0])
	_fit_rows()


## Turn the paper about the slot by `by` rad/s: the gear's knock coming through
## the printer, or the stub flicking back as a print tears off it. Positive is
## the way the paper curls.
func jolt(by: float) -> void:
	jolted = true
	if out <= 0.0:
		return
	var mid := centers()
	var axes := across()
	for row in range(2, segments + 1):
		var lever := clampf(row_out(row), 0.0, JOLT_REACH)
		var along := (mid[row] - mid[row - 1]).normalized()
		var kick := along.cross(axes[row]).normalized() * by * lever
		velocities[2 * row] += kick
		velocities[2 * row + 1] += kick


## The paper past the slot as rows of two edges, from the mouth to the free end,
## with how far down the picture each row is (1 at the mouth, 0 at the free end).
## What is drawn, and what a tear takes.
func outside() -> Array:
	var verts := PackedVector3Array([
		_slot + _slot_across * width * 0.5, _slot - _slot_across * width * 0.5])
	var vs := PackedFloat32Array([1.0])
	for row in range(2, segments + 1):
		var past := row_out(row)
		if past <= 1e-6:
			continue
		verts.append(positions[2 * row])
		verts.append(positions[2 * row + 1])
		vs.append(1.0 - past / out)
	return [verts, vs]


## What is past the slot as a sheet of its own, for the print torn off it
## (restore): the same paper where it is, its rows evened out along it (the
## stretch at the mouth is shorter than a row). Positions and velocities in the
## body's frame.
func torn_state() -> Dictionary:
	var rows_p := PackedVector3Array([
		_slot + _slot_across * width * 0.5, _slot - _slot_across * width * 0.5])
	var rows_v := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var at := PackedFloat64Array([0.0])
	for row in range(2, segments + 1):
		var past := row_out(row)
		if past <= 1e-6:
			continue
		rows_p.append(positions[2 * row])
		rows_p.append(positions[2 * row + 1])
		rows_v.append(velocities[2 * row])
		rows_v.append(velocities[2 * row + 1])
		at.append(past)
	var n := clampi(ceili(out / ROW), 2, MAX_ROWS - 1)
	var new_p := PackedVector3Array()
	var new_v := PackedVector3Array()
	var k := 0
	for row in n + 1:
		var s := out * row / n
		while k < at.size() - 2 and at[k + 1] < s:
			k += 1
		var span := at[k + 1] - at[k]
		var t := clampf((s - at[k]) / span, 0.0, 1.0) if span > 1e-9 else 0.0
		for side in 2:
			new_p.append(rows_p[2 * k + side].lerp(rows_p[2 * k + 2 + side], t))
			new_v.append(rows_v[2 * k + side].lerp(rows_v[2 * k + 2 + side], t))
	return {"positions": new_p, "velocities": new_v, "length": out, "width": width}


# --- Reading it ---------------------------------------------------------------------

func centers() -> PackedVector3Array:
	var mid := PackedVector3Array()
	mid.resize(segments + 1)
	for row in segments + 1:
		mid[row] = (positions[2 * row] + positions[2 * row + 1]) * 0.5
	return mid


func across() -> PackedVector3Array:
	var axes := PackedVector3Array()
	axes.resize(segments + 1)
	for row in segments + 1:
		axes[row] = (positions[2 * row] - positions[2 * row + 1]).normalized()
	return axes


func mean_curvature() -> float:
	var mid := centers()
	var axes := across()
	var total := 0.0
	for i in range(1, segments):
		var a := (mid[i] - mid[i - 1]).normalized()
		var b := (mid[i + 1] - mid[i]).normalized()
		total += atan2(-a.cross(b).dot(axes[i]), a.dot(b))
	return total / maxf(ds * (segments - 1), 1e-8)


## The sharpest the sheet turns between one row and the next, radians.
func sharpest_turn() -> float:
	var mid := centers()
	var sharpest := 0.0
	for i in range(1, segments):
		sharpest = maxf(sharpest, (mid[i] - mid[i - 1]).angle_to(mid[i + 1] - mid[i]))
	return sharpest


## Every `every`th row's middle and the free end's two corners: enough of the
## sheet to look round it by (rays down from it, sweeps between frames) without
## a ray for each of its particles.
func samples(every: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for row in range(0, segments + 1, maxi(every, 1)):
		pts.append((positions[2 * row] + positions[2 * row + 1]) * 0.5)
	pts.append(positions[2 * segments])
	pts.append(positions[2 * segments + 1])
	return pts


## The arrays of a mesh of `verts` (rows of two edges, right then left) shaded as
## one smooth sheet: each row's normal from the rows either side of it, where one
## flat normal a row drew every row as a fold. `vs` is each row's v.
static func mesh_arrays(verts: PackedVector3Array, vs: PackedFloat32Array) -> Array:
	@warning_ignore("integer_division")
	var rows := verts.size() / 2
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	normals.resize(rows * 2)
	uvs.resize(rows * 2)
	for i in rows:
		var ahead := mini(i + 1, rows - 1)
		var behind := maxi(i - 1, 0)
		var along := verts[2 * ahead] + verts[2 * ahead + 1] - verts[2 * behind] - verts[2 * behind + 1]
		var normal := (verts[2 * i] - verts[2 * i + 1]).cross(along).normalized()
		normals[2 * i] = normal
		normals[2 * i + 1] = normal
		uvs[2 * i] = Vector2(1.0, vs[i])
		uvs[2 * i + 1] = Vector2(0.0, vs[i])
		if i < rows - 1:
			var r := i * 2
			index.append_array([r, r + 1, r + 2, r + 1, r + 3, r + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


# --- Stepping it --------------------------------------------------------------------

## Whether the solver is there: paper-godot loaded, at a build that has it.
static func has_solver() -> bool:
	return ClassDB.class_exists(&"PaperSheetSolver")


## Step `delta` seconds. `gravity` is the frame's apparent gravity (the body's
## own acceleration taken off it), `angular_accel` how its turn is speeding up
## about `origin`; so a hand moving or turning the body excites bending and
## torsion without changing the paper's remembered curl. `frame_velocity` and
## `frame_spin` are how the body itself is moving (in its own axes): what paper
## lying on the ROOM rubs against.
func step(delta: float, gravity: Vector3, angular_accel := Vector3.ZERO, origin := Vector3.ZERO,
		frame_velocity := Vector3.ZERO, frame_spin := Vector3.ZERO) -> void:
	body_shift = Vector3.ZERO
	support_normal = Vector3.ZERO
	jolted = false
	if delta <= 0.0 or segments == 0:
		return
	_due += minf(delta, MAX_FRAME)
	var steps := mini(int(_due / STEP + 1e-6), MAX_STEPS)
	_due = maxf(0.0, _due - steps * STEP)
	if feeding():
		_feed(minf(wanted, out + FEED_MAX * minf(delta, MAX_FRAME)))
	if _solver == null:
		if has_solver():
			_solver = ClassDB.instantiate(&"PaperSheetSolver")
		if not _said:
			_said = true
			if _solver != null:
				print("[GbPrinter] paper solver: PaperSheetSolver (paper-godot)")
			else:
				push_error("[GbPrinter] paper-godot has no PaperSheetSolver (not loaded, or built before it): the paper will not move. Rebuild with Tools/build.py for this platform.")
		if _solver == null:
			move_speed = 0.0
			return
	# A frame shorter than a step: nothing is due yet, and move_speed stays what
	# the last step found.
	if steps == 0:
		return
	var patch_values := PackedFloat64Array()
	patch_values.resize(patches.size() * 9)
	for i in patches.size():
		var patch: Array = patches[i]
		var normal: Vector3 = patch[0]
		var center: Vector3 = patch[2]
		var at := i * 9
		patch_values[at] = normal.x
		patch_values[at + 1] = normal.y
		patch_values[at + 2] = normal.z
		patch_values[at + 3] = float(patch[1])
		patch_values[at + 4] = center.x
		patch_values[at + 5] = center.y
		patch_values[at + 6] = center.z
		patch_values[at + 7] = float(patch[3])
		patch_values[at + 8] = float(patch[4]) if patch.size() > 4 else PATCH_DEPTH
	var box_values := PackedVector3Array()
	for box in boxes:
		box_values.append(box.position)
		box_values.append(box.size)
	var finger_values := PackedFloat64Array()
	for finger: Array in fingers:
		var center: Vector3 = finger[0]
		finger_values.append(center.x)
		finger_values.append(center.y)
		finger_values.append(center.z)
		finger_values.append(float(finger[1]))
	var result: Array = _solver.solve(steps, STEP, gravity, angular_accel, origin, frame_velocity, frame_spin,
		ds, width, 1.0 / CURL_RADIUS, positions, velocities, pin_rows, pin_positions,
		patch_values, box_values, box_free_rows, finger_values)
	positions = result[0]
	velocities = result[1]
	move_speed = result[2]
	body_shift = result[3]
	support_normal = result[4]
	# The patches come back moved into a loose sheet's recovered frame, and are
	# written back in place: the caller's arrays are the ones it reads next.
	var moved: PackedFloat64Array = result[5]
	if not body_shift.is_zero_approx():
		for i in patches.size():
			var patch: Array = patches[i]
			patch[1] = moved[i * 9 + 3]
			patch[2] = Vector3(moved[i * 9 + 4], moved[i * 9 + 5], moved[i * 9 + 6])


static func _mean(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / maxi(points.size(), 1)
