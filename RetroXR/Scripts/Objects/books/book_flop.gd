## BookFlop — how a soft-cover book hangs, swings and fans in the hand.
##
## Not a cloth solver. Each half of the book is two damped pendulums about the
## gutter — a loose HINGE at the binding and a stiffer BEND over the page — and
## each loose leaf of the fan is one more. That is a handful of scalars, stepped
## at the physics tick, whose only output is the four numbers per side that
## paper_flop.gdshaderinc wraps the geometry around. No mesh is ever rebuilt:
## GDScript verlet cables are what saturated the main thread in the 20 fps Quest
## diagnosis, and a vertex-stage bend costs the CPU nothing (blind_slat.gdshader).
##
## Held, the pages meet what is around them as the printer's thermal paper does:
## PDFBook hands over the room as surface patches and the free fingertips
## (`patches`, `fingers`), and each sheet's own angles are pushed out of them
## (_collide). See "What the pages meet" in docs/dev/books.md.
##
## Pure and deterministic on purpose: no nodes, no engine time, no randomness, so
## book_flop_tests can step it with a fixed dt and get the same numbers every run.
##
## Frame (book-local): the gutter is the line x = 0 along Y, pages face +Z.
## A side is dir = +1 (right) or -1 (left). Angles are about the gutter, measured
## from the flat spread, POSITIVE TOWARD +Z — so positive is the half closing
## over the other one and negative is it folding back / drooping under a book
## held face-up. s is metres out from the gutter along the (unbent) sheet.
class_name BookFlop
extends RefCounted

## Arc length the hinge angle is spread over at the binding. Must match
## FLOP_HINGE_LEN in paper_flop.gdshaderinc — book_flop_tests pins the two.
const HINGE_LEN := 0.012
## A sheet LIFTED off the book spreads the same turn over this many times its
## height instead (see hinge_len_at). FLOP_LIFT_SPREAD in the include; pinned too.
const LIFT_SPREAD := 2.5

## A half may close to here over the other half, and fold back to here. With the
## hard stop's margin on top, both stay short of 90 degrees, so two halves
## hanging off a raised spine (or folded back behind it) cannot cross.
const ANGLE_MAX := deg_to_rad(82.0)
const ANGLE_MIN := deg_to_rad(-80.0)
const HARD_STOP_MARGIN := 0.12
## A hardback's boards open flat and a touch beyond, then the joint stops them.
const HARDBACK_ANGLE_MIN := deg_to_rad(-6.0)
## A loose leaf may go further: it lies over onto the far half.
const FAN_ANGLE_MAX := 2.3
const FAN_FAR_CLEARANCE := 0.2

## Spring constants are angular frequencies squared (rad^2/s^2): stiffness over
## moment of inertia. Leaves slide on each other, so a block's stiffness grows
## LINEARLY with its leaf count rather than with the cube a solid board would.
const HINGE_W2_BASE := 45.0
const HINGE_W2_PER_LEAF := 2.5
const BEND_W2_BASE := 110.0
const BEND_W2_PER_LEAF := 9.0
## The second cover of a closed book, bound to the same block.
const BEND_W2_EXTRA_COVER := 110.0
const HINGE_ZETA := 0.5
const BEND_ZETA := 0.4
## A hinge that is not free (closed book, or the hand is on that half) is pulled
## flat by this instead.
const HINGE_LOCKED_W2 := 1600.0
const LIMIT_W2 := 2500.0
## Ceiling on any one spring, so a short free length cannot outrun the step.
const W2_CEILING := 6000.0

const FAN_W2 := 45.0
## Each deeper leaf is held a little tighter by the binding, which is the whole
## reason a fan fans instead of moving as one sheet.
const FAN_W2_SPREAD := 0.45
const FAN_ZETA := 0.55
const FAN_MAX_LEAVES := 3

## The hand has to be this far out on a half before it counts as supporting it;
## nearer than that it is holding the spine.
const CLAMP_MIN := 0.02
## ...and never supports the whole page: the outer strip always stays free.
const CLAMP_MAX_FRACTION := 0.8
const CLAMP_RATE := 0.6   # metres / second the support point may slide

## Tracking jitter differentiated twice is loud. Low-passed, then capped.
const ACCEL_RESPONSE := 22.0
const ACCEL_MAX := 60.0
const GRAVITY := 9.8

## Sag: the middle of a spread hanging between two hands, one on each half. The
## hands do not move, so the grips stay put and the GUTTER drops between them;
## each half then slopes up from the gutter to its hand by asin(drop / distance
## to that hand). One scalar — the gutter's displacement along book Z, in metres —
## is the whole degree of freedom, which is also what keeps the two halves
## meeting at the binding when the hands are at different distances from it.
##
## What resists it is the paper between the hands bending, so it stiffens with
## the leaf count and with a SHORTER span. The reference span is hands 0.8 of a
## page out on each side.
const SAG_W2_BASE := 200.0
const SAG_W2_PER_LEAF := 10.0
const SAG_ZETA := 0.45
## With fewer than two supporting hands there is nothing to sag between, and
## this eases whatever sag there was back out instead of snapping it.
const SAG_LOCKED_W2 := 900.0
## The gutter may drop this fraction of the distance to the nearer hand: a slope
## of 30 degrees, past which a spread is being folded, not sagging.
const SAG_MAX_SLOPE := 0.5
const SAG_REF_SPAN := 1.6

const SETTLE_ANGLE := 0.002
const SETTLE_SPEED := 0.02
const SETTLE_SAG := 0.0003
const SETTLE_TICKS := 30

## Contact: what the pages meet (the room, a fingertip). See _collide.
##
## Where a sheet is tested: fractions of the page out from the gutter line (the
## binding never moves), and of its half-height along the spine. Two rows, the
## page's top and bottom edges: the bend is the same all along the spine, so a
## flat surface meets one of the edges first.
const CONTACT_S: Array[float] = [0.25, 0.5, 0.75, 1.0]
const CONTACT_ROWS: Array[float] = [-0.9, 0.9]
## Clearance kept from a surface, metres.
const CONTACT_SKIN := 0.001
## No point is pushed out faster than this, m/s: a surface found with the page
## already in it (the room is looked at a row at a time) eases it out instead of
## snapping it there, as the printer's TERMINAL_SPEED does for its paper.
const CONTACT_SPEED := 1.0
const CONTACT_PASSES := 2
## Only points this close to being pushed are looked at in a step: a point
## further clear of a surface cannot reach it before the next.
const CONTACT_NEAR := 0.03
## Below this lever (metres per radian) no angle of the sheet can move the point:
## it is at the binding, or in the hand.
const CONTACT_MIN_LEVER := 0.002
## A point this close to a surface is lying on it (see _gather).
const REST_GAP := 0.003
## A fingertip pushing paper (GbPrinter.FINGER_RADIUS).
const FINGER_RADIUS := 0.009
## A finger this far through a sheet from the side it was pushing from has got
## past it (the paper could not keep up), and lets go.
const FINGER_SLIP := 0.03

## 0 = the rigid board the book used to be, 1 = a limp magazine.
var floppiness := 0.7

## Hardback: the covers are boards. They do not bend, so neither does the block
## bound between them, and the joint lets them open only just past flat — a
## hardback held level by the spine lies open instead of drooping. They still
## swing toward shut when the book is turned over, and the pages inside, being
## paper, still fan. Shut, a hardback is simply rigid.
var hardback := false

var _page_w := 0.18
# Index 0 = left (dir -1), 1 = right (dir +1).
var _active := [false, false]
var _hinge_free := [false, false]
var _hinge_w2 := [HINGE_W2_BASE, HINGE_W2_BASE]
var _bend_w2 := [BEND_W2_BASE, BEND_W2_BASE]
var _hinge := [0.0, 0.0]
var _hinge_v := [0.0, 0.0]
var _bend := [0.0, 0.0]
var _bend_v := [0.0, 0.0]
var _clamp := [0.0, 0.0]
var _clamp_target := [0.0, 0.0]
## How far out each half lies on a surface its binding rests on (_gather),
## which holds it up as a hand would.
var _rest_clamp := [0.0, 0.0]
var _fan_count := [0, 0]
var _fan := [PackedFloat64Array(), PackedFloat64Array()]
var _fan_v := [PackedFloat64Array(), PackedFloat64Array()]
var _fan_suppressed := [false, false]
## The highest each side's fan may peel to: a page being turned over that half
## lies on it (set_fan_lid). INF = nothing over it.
var _fan_lid := [INF, INF]
## A page coming down onto a half RESTS on its top loose leaf (ride_params) and
## becomes that half's new top leaf where it lay (push_fan_leaf). Off is the
## control for book_flop_tests and book_flop_probe --nolid: the page lies on the
## block, through any leaves up off it.
var rest_on_fan := true
## How much higher than the top loose leaf the page being turned rides over each
## half (PDFBook._ride_clearance): set from the page, so the hand's solve and its
## shader see the same sheet.
var _ride_extra := [0.0, 0.0]
## How far up off its own block the page being turned off each half was when it
## was taken: it was that half's top loose leaf, and it goes on turning from
## there (turn_params) rather than being laid flat first.
var _turn_peel := [0.0, 0.0]
## ...and how much higher at the binding than that it rides, to stay over the
## leaves left under it (PDFBook._ride_clearance, as _ride_extra is for the far half).
var _turn_extra := [0.0, 0.0]
var _leaves := [0, 0]
var _sag := 0.0
var _sag_v := 0.0
var _sag_hand := [0.0, 0.0]

## Surfaces in book space, as PDFBook found them in the room this tick:
## [normal, offset, centres, reach, depth, dir, row, first column, last column].
## A point of that half's sheets in that row and those columns (CONTACT_ROWS,
## CONTACT_S) is inside when normal·p < offset, within `reach` across the surface
## of its column's centre (one per column, or one for them all) and no more than
## `depth` behind it.
var patches: Array = []
## Fingertips in book space: [position, radius, id]. The id keeps which side of
## each sheet a finger is pushing from, from one tick to the next.
var fingers: Array = []
## Points pushed out on the last step, per side (0 = left), and how many of them
## by a finger. For the caller's log.
var contacts := [0, 0]
var finger_contacts := 0
var _page_h := 0.25
## Per side: (Z of the cover underneath, Z of the page on top) on the flat book.
var _faces := [Vector2.ZERO, Vector2.ZERO]
## Per side: Z of the top loose leaf on the flat book; each deeper one lies
## _fan_step lower.
var _fan_top := [0.0, 0.0]
var _fan_step := 0.0
## Which side of a sheet each finger is pushing from: key -> +1 over its page,
## -1 under its cover. Kept while the finger stays over the sheet, so one that
## moves faster than the paper pushes it along instead of passing through.
var _finger_side: Dictionary = {}
## Each side's contact points as drawn (_point): per index (_at), the point and
## the version of its sheet it was bent at; per sheet, its version now. A push
## moves one sheet's version on (the block's moves every leaf's too: they hang
## from it), so only the points read again afterwards are bent again.
var _shape := [PackedVector3Array(), PackedVector3Array()]
var _shape_ver := [PackedInt32Array(), PackedInt32Array()]
var _sheet_ver := [PackedInt32Array(), PackedInt32Array()]
var _ver := 0
## ...and each sheet's numbers (params, fan_params) at its version.
var _sheet_prm := [PackedVector4Array(), PackedVector4Array()]
var _prm_ver := [PackedInt32Array(), PackedInt32Array()]

# Pose history for the acceleration estimate.
var _have_pose := 0
var _p1 := [Vector3.ZERO, Vector3.ZERO]
var _p2 := [Vector3.ZERO, Vector3.ZERO]
var _accel := [Vector3.ZERO, Vector3.ZERO]
var _still_ticks := 0


static func _i(dir: int) -> int:
	return 1 if dir > 0 else 0


# ── Configuration ─────────────────────────────────────────────────────────────

## Describe the book as it stands. leaves_* is the block on that side (0 = that
## half does not exist, as on a closed book), covers_* the covers bound to it,
## hinge_free whether the half can swing at the binding at all, fan_* how many
## loose leaves may peel off it.
func configure(page_w: float, leaves_left: int, leaves_right: int,
		covers_left: int, covers_right: int, hinge_free: bool,
		fan_left: int = 0, fan_right: int = 0) -> void:
	_page_w = maxf(page_w, 0.01)
	var leaves := [leaves_left, leaves_right]
	var covers := [covers_left, covers_right]
	var fans := [fan_left, fan_right]
	for i in 2:
		_leaves[i] = maxi(leaves[i], 0)
		_active[i] = leaves[i] > 0
		_hinge_free[i] = hinge_free and _active[i]
		_hinge_w2[i] = HINGE_W2_BASE + HINGE_W2_PER_LEAF * leaves[i]
		_bend_w2[i] = BEND_W2_BASE + BEND_W2_PER_LEAF * leaves[i] \
			+ BEND_W2_EXTRA_COVER * maxi(covers[i] - 1, 0)
		var n := clampi(fans[i], 0, FAN_MAX_LEAVES) if _active[i] else 0
		if n != _fan_count[i]:
			# Every turned page changes how many leaves a side may fan; the ones
			# still up stay where they are (a new one comes in flat, at the bottom).
			_fan_count[i] = n
			var d: PackedFloat64Array = _fan[i]
			d.resize(n)
			var v: PackedFloat64Array = _fan_v[i]
			v.resize(n)
			_fan[i] = d
			_fan_v[i] = v
		if not _active[i]:
			_hinge[i] = 0.0
			_hinge_v[i] = 0.0
			_bend[i] = 0.0
			_bend_v[i] = 0.0


## Lay everything flat and forget the motion history.
func reset() -> void:
	for i in 2:
		_hinge[i] = 0.0
		_hinge_v[i] = 0.0
		_bend[i] = 0.0
		_bend_v[i] = 0.0
		_clamp[i] = 0.0
		_clamp_target[i] = 0.0
		_rest_clamp[i] = 0.0
		_accel[i] = Vector3.ZERO
		_fan_lid[i] = INF
		_ride_extra[i] = 0.0
		_turn_peel[i] = 0.0
		_turn_extra[i] = 0.0
		for k in _fan_count[i]:
			_fan[i][k] = 0.0
			_fan_v[i][k] = 0.0
	_sag = 0.0
	_sag_v = 0.0
	_sag_hand = [0.0, 0.0]
	_have_pose = 0
	_still_ticks = 0
	_finger_side.clear()
	contacts = [0, 0]
	finger_contacts = 0


## Where each half's surfaces lie on the flat book, for contact: the page's
## height along the spine, each side's (cover underneath, page on top) Z, the Z
## of each side's top loose leaf, and how much lower each deeper leaf lies.
func set_contact_frame(page_h: float, faces_left: Vector2, faces_right: Vector2,
		fan_top_left: float, fan_top_right: float, fan_step: float) -> void:
	_page_h = maxf(page_h, 0.01)
	_faces = [faces_left, faces_right]
	_fan_top = [fan_top_left, fan_top_right]
	_fan_step = fan_step


## Whether the book has this half at all (a shut book has one).
func is_active(dir: int) -> bool:
	return _active[_i(dir)]


## Where the holding hand is, in book-local space. The root is rigidly tied to
## the hand, so the spine is the frame: the half the hand is on is supported
## from the gutter out to the hand and only bends beyond it, while the other
## half hinges freely. held = false releases both.
##
## A second hand (Vector3.INF = none) supports whichever half IT is on. One on
## each end is how a limp magazine is steadied to be read: both hinges lock and
## only the strip beyond each hand is left to droop. Two hands on the same half
## support it out to the further one.
func set_support(held: bool, hand_local: Vector3, second_local: Vector3 = Vector3.INF) -> void:
	for i in 2:
		var dir := 1.0 if i == 1 else -1.0
		_clamp_target[i] = 0.0
		if not held:
			continue
		for hand: Vector3 in [hand_local, second_local]:
			if not hand.is_finite():
				continue
			var s := dir * hand.x
			if s >= CLAMP_MIN:
				_clamp_target[i] = maxf(_clamp_target[i], minf(s, _page_w * CLAMP_MAX_FRACTION))


## Flatten a side's fan at once and keep it down (a page is being turned off it).
func suppress_fan(dir: int, on: bool) -> void:
	var i := _i(dir)
	_fan_suppressed[i] = on
	if on:
		for k in _fan_count[i]:
			_fan[i][k] = 0.0
			_fan_v[i][k] = 0.0


## A page being turned is over this half, and the loose leaves under it cannot
## peel past `angle` (fan_delta units, off the block): it presses them down as
## it comes over instead of passing through them. INF lifts it. Applied at once
## as well as every step, so a page coming down between ticks never shows a
## frame with a leaf through it.
func set_fan_lid(dir: int, angle: float) -> void:
	var i := _i(dir)
	_fan_lid[i] = maxf(angle, 0.0)
	if is_inf(angle):
		return
	var d: PackedFloat64Array = _fan[i]
	var v: PackedFloat64Array = _fan_v[i]
	for k in _fan_count[i]:
		if d[k] > _fan_lid[i]:
			d[k] = _fan_lid[i]
			v[k] = minf(v[k], 0.0)
	_fan[i] = d
	_fan_v[i] = v


## A page has landed on this half's fan and is now its top leaf, lying where it
## came to rest (`peel`, its top leaf's when it landed). The leaves under it each
## go one place deeper, starting from where they hung, and the deeper place's
## stiffer spring brings each down to where the leaf below it was. Returns how far
## up the deepest leaf was: it leaves the fan for the block (PDFBook settles it
## down onto it), 0 if every leaf still has a place.
func push_fan_leaf(dir: int, peel: float) -> float:
	var i := _i(dir)
	var n: int = _fan_count[i]
	if n == 0:
		return 0.0
	var d: PackedFloat64Array = _fan[i]
	var v: PackedFloat64Array = _fan_v[i]
	var dropped: float = d[n - 1]
	for k in range(n - 1, 0, -1):
		d[k] = d[k - 1]
		v[k] = v[k - 1]
	d[0] = maxf(peel, d[1] if n > 1 else 0.0)
	v[0] = v[1] if n > 1 else 0.0
	_fan[i] = d
	_fan_v[i] = v
	return dropped


## A page is being turned off this half, and it was the top loose leaf: take it
## out of the fan. The leaves under it each come up a place as they hang (the
## deepest place starts flat on the block). Returns how far up it was, which is
## where it goes on turning from (set_turn_peel); 0 when nothing was up.
func pop_fan_leaf(dir: int) -> float:
	var i := _i(dir)
	var n: int = _fan_count[i]
	if n == 0 or not rest_on_fan:
		return 0.0
	var d: PackedFloat64Array = _fan[i]
	var v: PackedFloat64Array = _fan_v[i]
	var taken: float = d[0]
	for k in n - 1:
		d[k] = d[k + 1]
		v[k] = v[k + 1]
	d[n - 1] = 0.0
	v[n - 1] = 0.0
	_fan[i] = d
	_fan_v[i] = v
	return taken


## The page being turned off this half goes on from `peel` up off its block.
func set_turn_peel(dir: int, peel: float) -> void:
	_turn_peel[_i(dir)] = peel


## ...riding `extra` radians higher at the binding than that.
func set_turn_extra(dir: int, extra: float) -> void:
	_turn_extra[_i(dir)] = extra


## How the page being turned off this half hangs on its own side: from where it
## floated when it was taken, the block's own numbers when it lay flat.
func turn_params(dir: int) -> Vector4:
	if not rest_on_fan:
		return params(dir)
	return fan_params_at(dir, _turn_peel[_i(dir)]) + Vector4(_turn_extra[_i(dir)], 0.0, 0.0, 0.0)


## What a sheet coming down onto this half lies on: its top loose leaf, or the
## block when none is up (the same numbers then).
func ride_params(dir: int) -> Vector4:
	if not rest_on_fan:
		return params(dir)
	return fan_params(dir, 0) + Vector4(_ride_extra[_i(dir)], 0.0, 0.0, 0.0)


## The page being turned rides `extra` radians higher at the binding than the top
## loose leaf on this half (0 = lying right on it).
func set_ride_extra(dir: int, extra: float) -> void:
	_ride_extra[_i(dir)] = extra


## The lid on a side's fan, INF if nothing is over it.
func fan_lid(dir: int) -> float:
	return _fan_lid[_i(dir)]


# ── Stepping ──────────────────────────────────────────────────────────────────

## Step from the book's pose. Effective gravity on a half is real gravity minus
## the acceleration of that half's own centre, which is one second difference
## and already contains swing, shake and rotation. held = false removes the
## drive altogether: a book lying on furniture is supported, so it relaxes flat.
func drive_from_pose(dt: float, xform: Transform3D, held: bool) -> void:
	if dt <= 0.0:
		return
	var inv := xform.basis.inverse()
	var accel := [Vector3.ZERO, Vector3.ZERO]
	for i in 2:
		var dir := 1.0 if i == 1 else -1.0
		var p := xform * Vector3(dir * _page_w * 0.5, 0.0, 0.0)
		var raw := Vector3.ZERO
		if _have_pose >= 2:
			raw = (p - _p1[i] * 2.0 + _p2[i]) / (dt * dt)
			if raw.length() > ACCEL_MAX:
				raw = raw.normalized() * ACCEL_MAX
		_p2[i] = _p1[i] if _have_pose >= 1 else p
		_p1[i] = p
		_accel[i] = _accel[i].lerp(raw, 1.0 - exp(-ACCEL_RESPONSE * dt))
		if held:
			accel[i] = inv * (Vector3.DOWN * GRAVITY - _accel[i])
	_have_pose = mini(_have_pose + 1, 2)
	step(dt, accel[0], accel[1])


## Advance by dt under an effective gravity per side, in book-local space.
func step(dt: float, accel_left: Vector3, accel_right: Vector3) -> void:
	if dt <= 0.0:
		return
	dt = minf(dt, 1.0 / 30.0)
	var sub := clampi(ceili(dt * 120.0), 1, 4)
	var h := dt / float(sub)
	var accel := [accel_left, accel_right]
	for _n in sub:
		for i in 2:
			if _active[i]:
				_step_side(i, h, accel[i])
		_step_sag(h, (accel_left.z + accel_right.z) * 0.5)
	_collide(dt)
	_update_settled()


## The gutter hanging between two hands. Live only with a hand supporting EACH
## half of an open, soft-cover spread: one hand has nothing to sag between, a
## shut book has one half, and boards gripped at both ends hold the joint up.
func _step_sag(h: float, a_z: float) -> void:
	# On the TARGETS as well as the support points themselves: a hand that has
	# let go leaves its support point sliding home for a fraction of a second,
	# still above zero, and that is not a hand.
	var live: bool = not hardback and floppiness > 0.0 \
		and _hinge_free[0] and _hinge_free[1] and _clamp[0] > 0.0 and _clamp[1] > 0.0 \
		and _clamp_target[0] > 0.0 and _clamp_target[1] > 0.0
	var w2 := SAG_LOCKED_W2
	var drive := 0.0
	if live:
		# Remembered, so that when a hand lets go the sag eases out over the
		# distances it was hanging between — not over a support point that is
		# sliding back to the gutter, which would whip the slope up as it went.
		_sag_hand[0] = _clamp[0]
		_sag_hand[1] = _clamp[1]
		var span: float = _clamp[0] + _clamp[1]
		var ratio := SAG_REF_SPAN * _page_w / maxf(span, 0.02)
		w2 = minf((SAG_W2_BASE + SAG_W2_PER_LEAF * 0.5 * float(_leaves[0] + _leaves[1])) * ratio * ratio,
			W2_CEILING)
		drive = a_z * floppiness
	_sag_v += (-w2 * _sag - 2.0 * SAG_ZETA * sqrt(w2) * _sag_v + drive) * h
	_sag += _sag_v * h
	var reach: float = SAG_MAX_SLOPE * minf(_sag_hand[0], _sag_hand[1])
	if absf(_sag) > reach:
		_sag = clampf(_sag, -reach, reach)
		_sag_v = 0.0
	if floppiness <= 0.0:
		_sag = 0.0
		_sag_v = 0.0


## How far a half slopes because of the sag: up from the dropped gutter to the
## hand that has not moved. Positive toward +Z, like every other angle here.
func sag_slope(dir: int) -> float:
	var i := _i(dir)
	if _sag == 0.0 or _sag_hand[i] <= 0.0:
		return 0.0
	return asin(clampf(-_sag / _sag_hand[i], -SAG_MAX_SLOPE, SAG_MAX_SLOPE))


## The gutter's displacement along book Z, in metres (negative: it has dropped
## under a spread held face-up).
func sag() -> float:
	return _sag


func _step_side(i: int, h: float, a: Vector3) -> void:
	var dir := 1.0 if i == 1 else -1.0
	_clamp[i] = move_toward(_clamp[i], maxf(_clamp_target[i], _rest_clamp[i]), CLAMP_RATE * h)
	var free_len := maxf(_page_w - _clamp[i], _page_w * (1.0 - CLAMP_MAX_FRACTION))
	var a_s := dir * a.x
	var a_z := a.z
	var gain := 1.5 / free_len * floppiness

	# Hinge. Locked flat while the hand supports this half or the book is shut.
	var hinge_live: bool = _hinge_free[i] and _clamp[i] <= 0.0
	var hw2: float = _hinge_w2[i] if hinge_live else HINGE_LOCKED_W2
	# A sagging spread slopes this half already; gravity's lever on the strip
	# beyond the hand is measured from where the sheet actually points.
	var slope := sag_slope(1 if i == 1 else -1)
	var ang_h: float = slope + _hinge[i] + 0.5 * _bend[i]
	var torque_h := gain * (a_z * cos(ang_h) - a_s * sin(ang_h)) if hinge_live else 0.0
	var acc_h: float = -hw2 * _hinge[i] - 2.0 * HINGE_ZETA * sqrt(hw2) * _hinge_v[i] + torque_h

	# Bend. A shorter free length is a stiffer cantilever.
	var ratio := _page_w / free_len
	var bw2 := minf(_bend_w2[i] * ratio * ratio, W2_CEILING)
	var ang_b: float = slope + _hinge[i] + _bend[i]
	var torque_b := gain * (a_z * cos(ang_b) - a_s * sin(ang_b))
	var acc_b: float = -bw2 * _bend[i] - 2.0 * BEND_ZETA * sqrt(bw2) * _bend_v[i] + torque_b

	# Soft limits act on the total angle, pushed back through both springs.
	var angle_min := HARDBACK_ANGLE_MIN if hardback else ANGLE_MIN
	var total: float = _hinge[i] + _bend[i]
	var over := 0.0
	if total > ANGLE_MAX:
		over = total - ANGLE_MAX
	elif total < angle_min:
		over = total - angle_min
	if over != 0.0:
		acc_h -= LIMIT_W2 * over
		acc_b -= LIMIT_W2 * over

	_hinge_v[i] += acc_h * h
	_hinge[i] += _hinge_v[i] * h
	_bend_v[i] += acc_b * h
	_bend[i] += _bend_v[i] * h
	# Boards. Zeroed rather than merely stiffened: a spring stiff enough to look
	# rigid would outrun the step, and switching the option on while the book is
	# hanging has to take the bend it already has away, not freeze it in.
	if hardback:
		_bend[i] = 0.0
		_bend_v[i] = 0.0

	_hard_stop(i)
	if floppiness <= 0.0:
		_hinge[i] = 0.0
		_hinge_v[i] = 0.0
		_bend[i] = 0.0
		_bend_v[i] = 0.0

	_step_fan(i, h, a_s, a_z, gain)


## A hard stop behind the soft one, so no input — and no contact — can fold a
## half through itself.
func _hard_stop(i: int) -> void:
	var angle_min := HARDBACK_ANGLE_MIN if hardback else ANGLE_MIN
	var hard_max := ANGLE_MAX + HARD_STOP_MARGIN
	var hard_min := angle_min - HARD_STOP_MARGIN
	var total: float = _hinge[i] + _bend[i]
	if total > hard_max or total < hard_min:
		var excess: float = total - clampf(total, hard_min, hard_max)
		# A board has no bend to give, so its joint takes the whole stop.
		var from_hinge := 1.0 if hardback else 0.5
		_hinge[i] -= excess * from_hinge
		_bend[i] -= excess * (1.0 - from_hinge)
		_hinge_v[i] = 0.0
		_bend_v[i] = 0.0


## Loose leaves lying on the block. Each is its own light pendulum, but they are
## stacked: a leaf cannot pass the block (delta >= 0) or the leaf under it, so
## gravity pressing down on a face-up book pins the whole fan shut at zero.
func _step_fan(i: int, h: float, a_s: float, a_z: float, gain: float) -> void:
	var n: int = _fan_count[i]
	if n == 0:
		return
	var d: PackedFloat64Array = _fan[i]
	var v: PackedFloat64Array = _fan_v[i]
	if _fan_suppressed[i] or floppiness <= 0.0:
		for k in n:
			d[k] = 0.0
			v[k] = 0.0
		_fan[i] = d
		_fan_v[i] = v
		return
	var base: float = sag_slope(1 if i == 1 else -1) + _hinge[i] + _bend[i]
	for k in n:
		var w2 := FAN_W2 * (1.0 + FAN_W2_SPREAD * float(k))
		var ang: float = base + d[k]
		var acc := -w2 * d[k] - 2.0 * FAN_ZETA * sqrt(w2) * v[k] \
			+ gain * (a_z * cos(ang) - a_s * sin(ang))
		v[k] += acc * h
		d[k] += v[k] * h
	_fan[i] = d
	_fan_v[i] = v
	_stack_fan(i)


## The leaves are stacked: none passes the block (delta >= 0) or the leaf under
## it, nor the far half, nor a page being turned over this one (the lid).
func _stack_fan(i: int) -> void:
	var n: int = _fan_count[i]
	if n == 0:
		return
	var d: PackedFloat64Array = _fan[i]
	var v: PackedFloat64Array = _fan_v[i]
	var base: float = sag_slope(1 if i == 1 else -1) + _hinge[i] + _bend[i]
	var far: float = sag_slope(-1 if i == 1 else 1) + _hinge[1 - i] + _bend[1 - i]
	# Not past the other half — nor past ITS loose leaves, which peel up off it
	# towards this one. Stopped only at its block, the two fans of a book tipped
	# over swung into each other by the spine, a leaf of one lying among the
	# other's.
	var far_fan: float = _fan[1 - i][0] if _fan_count[1 - i] > 0 else 0.0
	var ceiling := minf(minf(FAN_ANGLE_MAX, PI - far - far_fan - FAN_FAR_CLEARANCE) - base, _fan_lid[i])
	# Contact, from the deepest leaf up: k = 0 is the top sheet, first to peel.
	for k in range(n - 1, -1, -1):
		var floor_d: float = 0.0 if k == n - 1 else d[k + 1]
		if d[k] < floor_d:
			d[k] = floor_d
			v[k] = maxf(v[k], 0.0)
		if d[k] > ceiling:
			d[k] = maxf(ceiling, floor_d)
			v[k] = minf(v[k], 0.0)
	_fan[i] = d
	_fan_v[i] = v


# ── Contact: what the pages meet ──────────────────────────────────────────────
#
# Thermal paper's arrangement (GbPrinterStrip, GbThermalRibbon) on a sim whose
# only freedoms are angles about the gutter. PDFBook finds the room with short
# rays as patches of surface, kept where they are in the room and placed in the
# book's frame every tick (`patches`); a free fingertip is a round obstacle
# (`fingers`). Each sheet — a half's block, cover to page, and each loose leaf
# that is up — is tested at a few points, and a point inside something is pushed
# out by turning that sheet's OWN angles: the half's hinge and bend, a leaf's
# peel. A position-based step on those, then the angular speed carrying the
# point in is taken out. Nothing moves that the shaders do not already move, so
# the block and the sheet lying on it still hang from one set of numbers.

## Push every sheet out of what it is in. Once a step, after the springs.
func _collide(dt: float) -> void:
	contacts = [0, 0]
	finger_contacts = 0
	if patches.is_empty() and fingers.is_empty():
		_finger_side.clear()
		_rest_clamp = [0.0, 0.0]
		return
	if floppiness <= 0.0:
		return
	var items: Array = []
	for i in 2:
		_stale(i, -1)
		_rest_clamp[i] = _gather(i, items) if _active[i] else 0.0
	_finger_items(items)
	if items.is_empty():
		return
	var push := CONTACT_SPEED * dt
	# A later pass looks again only at the sides the last one pushed: nothing
	# else has moved.
	var look := [true, true]
	for pass_n in CONTACT_PASSES:
		var pushed := [false, false]
		for item: Array in items:
			if look[item[0]] and _resolve(item, push):
				pushed[item[0]] = true
				if pass_n == 0:
					contacts[item[0]] += 1
					if int(item[2]) < 0:
						finger_contacts += 1
		if not pushed[0] and not pushed[1]:
			break
		look = pushed
	# A push never folds a half through itself, nor lifts a leaf through the far
	# half or the leaf above it.
	for i in 2:
		if _active[i]:
			_hard_stop(i)
			_stack_fan(i)


## Where a half's rigid part ends: the binding, or as far out as it is held.
func _root_s(i: int) -> float:
	return maxf(_clamp[i], gutter_gap)


## Index into _point: sheet 0 is the block, 1 + k loose leaf k; column c of
## CONTACT_S, or CONTACT_S.size() for the root.
static func _at(sheet: int, col: int) -> int:
	return sheet * (CONTACT_S.size() + 1) + col


## A sheet as drawn now at a column (or the root), on its own middle plane:
## (book-local x, book-local z, the sheet's angle there). bend_sz is linear in
## the height off that plane, so a face is this plus its height along the sheet's
## way up (_on_face), and the bend is the same all along the spine, so a row only
## adds its own y. Bent when first read after its sheet last moved: bending every
## point afresh for every surface cost ten times the rest of the tick.
func _point(i: int, sheet: int, col: int) -> Vector3:
	var index := _at(sheet, col)
	var stamp: int = _sheet_ver[i][sheet]
	if _shape_ver[i][index] == stamp:
		return _shape[i][index]
	var dir := 1 if i == 1 else -1
	var prm: Vector4
	if _prm_ver[i][sheet] == stamp:
		prm = _sheet_prm[i][sheet]
	else:
		prm = params(dir) if sheet == 0 else fan_params(dir, sheet - 1)
		_sheet_prm[i][sheet] = prm
		_prm_ver[i][sheet] = stamp
	var s: float = _root_s(i) if col == CONTACT_S.size() else CONTACT_S[col] * _page_w
	var r := bend_sz(s, 0.0, prm)
	var bent := Vector3(float(dir) * r.x, r.y, r.z)
	_shape[i][index] = bent
	_shape_ver[i][index] = stamp
	return bent


## A point of a sheet `z` off its middle plane, from _point's (x, z, angle).
static func _on_face(mid: Vector3, dir: int, z: float, y: float) -> Vector3:
	return Vector3(mid.x - float(dir) * sin(mid.z) * z, y, mid.y + cos(mid.z) * z)


## Side i's sheet has moved (-1: the whole side, the block and so every leaf on it).
func _stale(i: int, sheet: int) -> void:
	var sheets: int = 1 + _fan_count[i]
	if (_sheet_ver[i] as PackedInt32Array).size() != sheets:
		# Built here and then stored: a method called on an element of an Array
		# changes a copy of a packed array, not the one in it.
		var versions := PackedInt32Array()
		versions.resize(sheets)
		var points := PackedVector3Array()
		points.resize(_at(sheets, 0))
		var stamps := PackedInt32Array()
		stamps.resize(_at(sheets, 0))
		stamps.fill(-1)
		var prms := PackedVector4Array()
		prms.resize(sheets)
		var prm_stamps := PackedInt32Array()
		prm_stamps.resize(sheets)
		prm_stamps.fill(-1)
		_sheet_ver[i] = versions
		_shape[i] = points
		_shape_ver[i] = stamps
		_sheet_prm[i] = prms
		_prm_ver[i] = prm_stamps
	_ver += 1
	if sheet > 0:
		_sheet_ver[i][sheet] = _ver
		return
	for k in sheets:
		_sheet_ver[i][k] = _ver


## Z of loose leaf k of side i on the flat book.
func _leaf_z(i: int, k: int) -> float:
	return _fan_top[i] - _fan_step * k


## One pass over side i's surfaces: the points that may need pushing this step
## (into `items`), and how far out the half lies ON something, which it returns.
##
## Each surface is met by the face of the block that faces it — the cover one the
## sheet faces away from, the page one it faces — and by every loose leaf that is
## up. Only points within CONTACT_NEAR of being pushed are kept: the rest cannot
## reach the surface this step.
##
## Never pushed clearer than the binding is: a sheet lies along a surface its
## binding is on, it is not lifted off it. Held resting on a table, the book is
## exactly flat; without this its halves were pushed a skin's width up off a
## table its cover already touched. The same rule leaves a surface the hand has
## pushed the book INTO alone (no point is pushed past its binding, and every
## point deeper than that is past `depth`), as the printer never takes a way out
## deeper than the point; a binding further in than `depth` is skipped early.
##
## Lying ON something: the binding rests on a surface and every point from there
## out touches one. That much of the half is held up as a hand holds it (the
## hinge locks, only the strip beyond bends), so a book held resting on a table
## lies flat on it and only what overhangs the edge droops. Pushed out point by
## point instead, a half resting on its binding and its fore edge stood up off the
## table between the two: gravity and the springs balance one contact at the
## edge with a hump. Both rows must agree (the nearer edge of the table wins):
## the bend is one all along the spine.
func _gather(i: int, items: Array) -> float:
	var dir := 1 if i == 1 else -1
	var any := false
	for patch: Array in patches:
		if int(patch[5]) == dir:
			any = true
			break
	if not any:
		return 0.0
	var cols := CONTACT_S.size()
	var rows := CONTACT_ROWS.size()
	var faces: Vector2 = _faces[i]
	var root_s := _root_s(i)
	var mids := PackedVector3Array()
	var ups := PackedVector3Array()
	for col in cols + 1:
		var mid := _point(i, 0, col)
		mids.append(mid)
		ups.append(Vector3(float(dir) * -sin(mid.z), 0.0, cos(mid.z)))
	var leaves := PackedInt32Array()
	for k in _fan_count[i]:
		if _fan[i][k] > 0.0:
			leaves.append(1 + k)
	var rooted := PackedByteArray()
	rooted.resize(rows)
	rooted.fill(0)
	var touching := PackedByteArray()
	touching.resize(rows * cols)
	touching.fill(0)
	for patch: Array in patches:
		if int(patch[5]) != dir:
			continue
		var n: Vector3 = patch[0]
		var off: float = patch[1]
		var centres: PackedVector3Array = patch[2]
		var reach: float = patch[3]
		var depth: float = patch[4]
		var row: int = patch[6]
		var first: int = patch[7]
		var y: float = CONTACT_ROWS[row] * _page_h * 0.5
		var root := _on_face(mids[cols], dir, faces.x if n.dot(ups[cols]) > 0.0 else faces.y, y)
		var d_root := n.dot(root) - off
		if d_root < -depth:
			continue
		if d_root <= REST_GAP:
			rooted[row] = 1
		var keep := off + minf(CONTACT_SKIN, d_root)
		for col in range(first, int(patch[8]) + 1):
			var z := faces.x if n.dot(ups[col]) > 0.0 else faces.y
			var p := _on_face(mids[col], dir, z, y)
			var lateral := p - centres[mini(col - first, centres.size() - 1)]
			if (lateral - n * n.dot(lateral)).length() > reach:
				continue
			var d := n.dot(p) - off
			if d < -depth:
				continue
			if d <= REST_GAP:
				touching[row * cols + col] = 1
			var s: float = CONTACT_S[col] * _page_w
			if s <= root_s:
				continue
			if n.dot(p) - keep < CONTACT_NEAR:
				items.append([i, 0, col, z, y, n, keep, off - depth, s])
			for sheet in leaves:
				var lz := _leaf_z(i, sheet - 1)
				var leaf_keep := off + minf(CONTACT_SKIN, n.dot(_on_face(_point(i, sheet, cols), dir, lz, y)) - off)
				var leaf_p := _on_face(_point(i, sheet, col), dir, lz, y)
				if n.dot(leaf_p) - leaf_keep < CONTACT_NEAR and n.dot(leaf_p) - off >= -depth:
					items.append([i, sheet, col, lz, y, n, leaf_keep, off - depth, s])
	var rest := INF
	var cap := _page_w * CLAMP_MAX_FRACTION
	for row in rows:
		var held := 0.0
		if rooted[row] == 1 and touching[row * cols] == 1:
			var last := 0
			while last + 1 < cols and touching[row * cols + last + 1] == 1:
				last += 1
			# The surface ends somewhere between this point and the next.
			held = cap if last == cols - 1 else minf(lerpf(CONTACT_S[last], CONTACT_S[last + 1], 0.5) * _page_w, cap)
		rest = minf(rest, held)
	return rest if rest >= CLAMP_MIN else 0.0


## Each fingertip over a sheet, as a point to keep out of: the sheet's point
## under the finger, kept a finger's radius away on the side it is pushing from.
func _finger_items(items: Array) -> void:
	var seen := {}
	for finger: Array in fingers:
		for i in 2:
			if not _active[i]:
				continue
			var dir := 1 if i == 1 else -1
			_finger_on(items, seen, finger, i, 0, _faces[i], params(dir))
			for k in _fan_count[i]:
				if _fan[i][k] > 0.0:
					var z := _leaf_z(i, k)
					_finger_on(items, seen, finger, i, 1 + k, Vector2(z, z), fan_params(dir, k))
	for key: int in _finger_side.keys():
		if not seen.has(key):
			_finger_side.erase(key)


func _finger_on(items: Array, seen: Dictionary, finger: Array, i: int, sheet: int,
		faces: Vector2, prm: Vector4) -> void:
	var dir := 1 if i == 1 else -1
	var at: Vector3 = finger[0]
	var r: float = finger[1]
	var flat := flat_point(at, dir, prm)
	if flat.x < gutter_gap or flat.x > _page_w + r or absf(flat.y) > _page_h * 0.5 + r:
		return
	var key := (int(finger[2]) * 2 + i) * 8 + sheet
	seen[key] = true
	var over := flat.z - faces.y
	var under := faces.x - flat.z
	var side: int = _finger_side.get(key, 0)
	# A new finger pushes from the side it came in on; one that has got right
	# through the sheet has slipped past it.
	if side == 0 or (side > 0 and over < -FINGER_SLIP) or (side < 0 and under < -FINGER_SLIP):
		side = 1 if flat.z >= (faces.x + faces.y) * 0.5 else -1
	_finger_side[key] = side
	if (over if side > 0 else under) >= r:
		return
	var s := clampf(flat.x, gutter_gap, _page_w)
	var y := clampf(flat.y, -_page_h * 0.5, _page_h * 0.5)
	var z := faces.y if side > 0 else faces.x
	var ang := bend_sz(s, z, prm).z
	var n := Vector3(float(dir) * -sin(ang), 0.0, cos(ang)) * float(-side)
	# Column -1: not on the grid, so bent where it is.
	items.append([i, sheet, -1, z, y, n, n.dot(at) + r, -INF, s])


## One point of a half across its sheets, book-local, as drawn now: the cover
## underneath, the page on top, then the top loose leaf if it is up. PDFBook
## looks round the room from these.
func column_points(dir: int, s: float, y: float) -> PackedVector3Array:
	var i := _i(dir)
	var faces: Vector2 = _faces[i]
	var r := bend_sz(s, 0.0, params(dir))
	var mid := Vector3(float(dir) * r.x, r.y, r.z)
	var out := PackedVector3Array([_on_face(mid, dir, faces.x, y), _on_face(mid, dir, faces.y, y)])
	if _fan_count[i] > 0 and _fan[i][0] > 0.0:
		out.append(_sheet_point(i, 0, s, y, _fan_top[i]))
	return out


## The page's width out from the gutter line, as configured.
func page_width() -> float:
	return _page_w


## Book-local point of a sheet of side i: the block (sheet -1) or loose leaf k,
## at (s, y, z) on the flat book.
func _sheet_point(i: int, sheet: int, s: float, y: float, z: float) -> Vector3:
	var dir := 1 if i == 1 else -1
	return _bent_point(dir, s, y, z, params(dir) if sheet < 0 else fan_params(dir, sheet))


static func _bent_point(dir: int, s: float, y: float, z: float, prm: Vector4) -> Vector3:
	var r := bend_sz(s, z, prm)
	return Vector3(float(dir) * r.x, y, r.y)


## Push one point out, if it is in. True when it moved anything.
## item: [side, sheet (0 block, 1 + k leaf), column (-1 off the grid), z, y,
## normal, keep, floor, s]: in when normal·p < keep, and let be when normal·p is
## under the floor (too deep behind the surface to be on it).
func _resolve(item: Array, push: float) -> bool:
	var i: int = item[0]
	var sheet: int = item[1]
	var col: int = item[2]
	var z: float = item[3]
	var y: float = item[4]
	var n: Vector3 = item[5]
	var s: float = item[8]
	var dir := 1 if i == 1 else -1
	var p := _on_face(_point(i, sheet, col), dir, z, y) if col >= 0 else _sheet_point(i, sheet - 1, s, y, z)
	var at := n.dot(p)
	var c := at - float(item[6])
	if c >= 0.0 or at < float(item[7]):
		return false
	var move := minf(-c, push)
	var slope := sag_slope(dir)
	var hinge: float = _hinge[i]
	var bend: float = _bend[i]
	var clamp_s: float = _clamp[i]
	const EPS := 1e-4
	if sheet > 0:
		var k := sheet - 1
		var d: PackedFloat64Array = _fan[i]
		var was: float = d[k]
		var lifted := _params_for(slope + hinge + (was + EPS) * 0.5, bend + (was + EPS) * 0.5, clamp_s)
		var g := (n.dot(_bent_point(dir, s, y, z, lifted)) - at) / EPS
		if absf(g) < CONTACT_MIN_LEVER:
			return false
		d[k] = maxf(was + move / g, 0.0)
		_fan[i] = d
		var v: PackedFloat64Array = _fan_v[i]
		if g * v[k] < 0.0:
			v[k] = 0.0
			_fan_v[i] = v
		_stale(i, sheet)
		return true
	# The block: the hinge while it swings free (no hand on the half, the book
	# open), the bend unless the covers are boards.
	var gh := 0.0
	var gb := 0.0
	if _hinge_free[i] and clamp_s <= 0.0:
		gh = (n.dot(_bent_point(dir, s, y, z, _params_for(slope + hinge + EPS, bend, clamp_s))) - at) / EPS
	if not hardback:
		gb = (n.dot(_bent_point(dir, s, y, z, _params_for(slope + hinge, bend + EPS, clamp_s))) - at) / EPS
	var g2 := gh * gh + gb * gb
	if g2 < CONTACT_MIN_LEVER * CONTACT_MIN_LEVER:
		return false
	_hinge[i] += gh * move / g2
	_bend[i] += gb * move / g2
	var rate: float = gh * _hinge_v[i] + gb * _bend_v[i]
	if rate < 0.0:
		_hinge_v[i] -= gh * rate / g2
		_bend_v[i] -= gb * rate / g2
	_stale(i, -1)
	return true


func _update_settled() -> void:
	var still := true
	for i in 2:
		if absf(_hinge[i]) > SETTLE_ANGLE or absf(_bend[i]) > SETTLE_ANGLE \
				or absf(_hinge_v[i]) > SETTLE_SPEED or absf(_bend_v[i]) > SETTLE_SPEED:
			still = false
		for k in _fan_count[i]:
			if absf(_fan[i][k]) > SETTLE_ANGLE or absf(_fan_v[i][k]) > SETTLE_SPEED:
				still = false
	if absf(_sag) > SETTLE_SAG or absf(_sag_v) > SETTLE_SPEED * 0.1:
		still = false
	_still_ticks = _still_ticks + 1 if still else 0


## Flat and motionless for long enough that stepping further changes nothing.
func is_settled() -> bool:
	return _still_ticks >= SETTLE_TICKS


# ── Reading the state ─────────────────────────────────────────────────────────

func hinge(dir: int) -> float:
	return _hinge[_i(dir)]


func bend_angle(dir: int) -> float:
	return _bend[_i(dir)]


## How far the fore edge has turned relative to the binding it hangs from. The
## slope a sagging spread gives the whole half is separate: sag_slope().
func tip_angle(dir: int) -> float:
	var i := _i(dir)
	return _hinge[i] + _bend[i]


func support(dir: int) -> float:
	return _clamp[_i(dir)]


func fan_count(dir: int) -> int:
	return _fan_count[_i(dir)]


## How far loose leaf k (0 = top sheet) has peeled off its block.
func fan_delta(dir: int, k: int) -> float:
	var i := _i(dir)
	return _fan[i][k] if k < _fan_count[i] else 0.0


## What the shader wraps this half around: (angle at the gutter, page curvature,
## support distance, gutter displacement).
##
## The gutter angle is the free hinge PLUS the slope of a sagging spread — they
## are never both live (a supported half's hinge is locked), and both turn the
## half about the binding, so the geometry takes their sum. The bend angle is
## spread evenly over the free sheet beyond the support, so every piece is a
## circular arc and paper length is conserved. The gutter displacement is the
## one number both halves share, which is what keeps them joined at the binding.
func params(dir: int) -> Vector4:
	var i := _i(dir)
	return _params_for(sag_slope(dir) + _hinge[i], _bend[i], _clamp[i])


## The same, for loose leaf k: it shares the block's hinge and support and takes
## its extra peel half at the binding, half over the sheet.
func fan_params(dir: int, k: int) -> Vector4:
	return fan_params_at(dir, fan_delta(dir, k))


## Distance out from the gutter over which a sheet leaves its block's bend for its
## own (paper.gdshader's BIND_SPREAD): every sheet of a half comes into the
## binding on the block's bend, so there it is ordered by height alone.
const BIND_SPREAD := 0.02
## The gutter's half-width, which s is measured past (PDFBook sets it).
var gutter_gap := 0.00175


## `sheet`'s bend at `s` out from the book's middle, blended from `block`'s at
## the binding (paper.gdshader does the same per vertex).
func bound(sheet: Vector4, block: Vector4, s: float) -> Vector4:
	if block == Vector4.ZERO:
		return sheet
	return block.lerp(sheet, smoothstep(0.0, BIND_SPREAD, s - gutter_gap))


## A loose leaf `d` up off this half's block, wherever it is in the fan.
func fan_params_at(dir: int, d: float) -> Vector4:
	var i := _i(dir)
	return _params_for(sag_slope(dir) + _hinge[i] + d * 0.5, _bend[i] + d * 0.5, _clamp[i])


func _params_for(gutter_a: float, bend_a: float, clamp_s: float) -> Vector4:
	var run := maxf(_page_w - maxf(clamp_s, HINGE_LEN), 0.01)
	return Vector4(gutter_a, bend_a / run, clamp_s, _sag)


# ── The bend itself, on the CPU ───────────────────────────────────────────────
#
# Mirrors paper_flop() in paper_flop.gdshaderinc. Used for what the GPU cannot
# tell us: where a grab zone has gone, and where on the FLAT page a hand is.

static func _arc(length: float, k: float) -> Vector3:
	# (along, up, angle)
	var ang := k * length
	if absf(ang) < 1e-4:
		return Vector3(length, 0.5 * k * length * length, ang)
	return Vector3(sin(ang) / k, (1.0 - cos(ang)) / k, ang)


## (s, z) on the flat sheet -> (s, z, angle) on the bent one. Three pieces in
## series out from the gutter: a tight arc at the binding (p.x, over HINGE_LEN),
## a straight run out to the supporting hand (p.z), a long shallow arc over the
## rest (curvature p.y) — then the whole half moved with the gutter (p.w).
static func bend_sz(s: float, z: float, p: Vector4, hinge_len: float = HINGE_LEN) -> Vector3:
	if p.x == 0.0 and p.y == 0.0 and p.w == 0.0:
		return Vector3(s, z, 0.0)
	var l1 := clampf(s, 0.0, hinge_len)
	var a1 := _arc(l1, p.x / hinge_len)
	var along := a1.x
	var up := a1.y
	var ang := a1.z
	var rest := s - l1
	if rest > 0.0:
		var l2 := minf(rest, maxf(p.z, hinge_len) - hinge_len)
		along += cos(ang) * l2
		up += sin(ang) * l2
		var l3 := rest - l2
		if l3 > 0.0:
			var a3 := _arc(l3, p.y)
			var c := cos(ang)
			var sn := sin(ang)
			along += c * a3.x - sn * a3.y
			up += sn * a3.x + c * a3.y
			ang += a3.z
	return Vector3(along - sin(ang) * z, up + cos(ang) * z + p.w, ang)


## Book-local point on the flat book -> where the bend carries it.
func bend(point: Vector3) -> Vector3:
	var dir := 1 if point.x >= 0.0 else -1
	var r := bend_sz(absf(point.x), point.z, params(dir))
	return Vector3(float(dir) * r.x, point.y, r.y)


## Over how long an arc a sheet at height z turns at the binding.
##
## A sheet lying on the book bends over HINGE_LEN. A sheet LIFTED off it cannot:
## z above a bend of radius R it is on the outside of the curve and would have
## to cover (R + z) / R times the paper it has — 5 cm over a drooping spine,
## nearly four times. The flap of a page being turned was stretched into a flat
## tongue longer than the page, and the hand carrying it slid several
## centimetres off the paper as it passed over the spine. So the turning leaf,
## and only that, spreads the same turn over an arc that widens with its height,
## which keeps the radius large beside the lift. On the page plane this is
## HINGE_LEN again, so a landed page lies exactly on its block.
static func hinge_len_at(z: float) -> float:
	return maxf(HINGE_LEN, LIFT_SPREAD * z)


## The turning leaf's map, in the (s, z) plane with s SIGNED: positive on
## own_dir's half, negative once the flap is past the gutter, where it rides the
## far half's bend mirrored in and out. The two meet at the gutter — the turn
## starts from zero there — so nothing is blended. Mirrors the flop_cross path of
## paper.gdshader.
##
func _bend_over_sz(s: float, z: float, own_dir: int) -> Vector3:
	var hl := hinge_len_at(z)
	if s >= 0.0:
		return bend_sz(s, z, bound(turn_params(own_dir), params(own_dir), s), hl)
	var far := bend_sz(-s, z, bound(ride_params(-own_dir), params(-own_dir), -s), hl)
	return Vector3(-far.x, far.y, -far.z)


## bend(), for a point on (or a hand near) the leaf being turned off own_dir's half.
##
## `lift` is the leaf's own hinge: a page gripped at its edge and pulled UP does
## not roll over flat, it swings up about the gutter toward the hand. It is a
## RIGID rotation about the gutter line at the leaf's own plane (`pivot_z`),
## applied BEFORE the book's droop — a page's hinge at the binding is a true
## hinge. It was first folded into the droop as one more angle over that widened
## arc, which gave the high parts of the sheet only a fraction of the lift; the
## "leaf's frame" was then not a frame at all, and the fold solver wanted curls
## starting 6 cm behind the binding.
## `after_lift` is a height added once the hinge has turned the point (the gutter
## dive of a page on its hinge, which paper.gdshader applies there).
func bend_over(point: Vector3, own_dir: int, lift: float = 0.0, pivot_z: float = 0.0,
		after_lift: float = 0.0) -> Vector3:
	var d := 1.0 if own_dir > 0 else -1.0
	var lifted := Vector2(d * point.x, point.z - pivot_z).rotated(lift)
	var r := _bend_over_sz(lifted.x, lifted.y + pivot_z + after_lift, own_dir)
	return Vector3(d * r.x, point.y, r.y)


## Inverse of bend_over(): where on the FLAT book the turning hand is.
func unbend_over(point: Vector3, own_dir: int, lift: float = 0.0, pivot_z: float = 0.0) -> Vector3:
	# Newton, with a measured Jacobian. unbend() can get away with turning the
	# residual back through the sheet's angle because a half's map is a rotation
	# up to a thin offset; this one is not — the arc a point turns over depends
	# on its own height — and that shortcut stalled 16 mm off. Only ever run for
	# the hand on a page being dragged, so three evaluations a round is nothing.
	var d := 1.0 if own_dir > 0 else -1.0
	var target := Vector2(d * point.x, point.z)
	var guess := target
	const H := 1e-5
	for _n in 16:
		var r := _bend_over_sz(guess.x, guess.y, own_dir)
		var err := target - Vector2(r.x, r.y)
		if err.length_squared() < 1e-14:
			break
		var rs := _bend_over_sz(guess.x + H, guess.y, own_dir)
		var rz := _bend_over_sz(guess.x, guess.y + H, own_dir)
		var a := (rs.x - r.x) / H
		var c := (rs.y - r.y) / H
		var b := (rz.x - r.x) / H
		var e := (rz.y - r.y) / H
		var det := a * e - b * c
		if absf(det) < 1e-9:
			guess += err.rotated(-r.z)
			continue
		var newton_step := Vector2((e * err.x - b * err.y) / det, (a * err.y - c * err.x) / det)
		# A full step can overshoot where the arc length switches on (z = 0).
		guess += newton_step.limit_length(0.05)
	# The droop is undone; now the leaf's own hinge, which was applied first.
	var flat := Vector2(guess.x, guess.y - pivot_z).rotated(-lift)
	return Vector3(d * flat.x, point.y, flat.y + pivot_z)


## Rotation of the sheet about the book's Y axis at that point, as a Node3D
## rotation.y: the right half tilting toward +Z turns -angle about Y.
func bend_rotation_y(point: Vector3) -> float:
	var dir := 1 if point.x >= 0.0 else -1
	return -float(dir) * bend_sz(absf(point.x), point.z, params(dir)).z


## Inverse of bend_sz() for one set of numbers: (s, y, z) on the flat sheet that
## a book-local point came from, s measured out from the gutter on dir's side
## whichever side the point is on (a finger under a half hanging past the spine).
## The same iteration as unbend().
static func flat_point(point: Vector3, dir: int, p: Vector4) -> Vector3:
	var target := Vector2(float(dir) * point.x, point.z)
	if p.x == 0.0 and p.y == 0.0 and p.w == 0.0:
		return Vector3(target.x, point.y, target.y)
	var guess := target
	for _n in 8:
		var r := bend_sz(guess.x, guess.y, p)
		var err := target - Vector2(r.x, r.y)
		if err.length_squared() < 1e-12:
			break
		guess += err.rotated(-r.z)
	return Vector3(guess.x, point.y, guess.y)


## Inverse of bend(): the flat-book point a bent-book point came from. The map
## is an isometry up to the thin offset off the neutral plane, so stepping the
## guess by the residual, turned back into the flat frame, converges in a few
## rounds.
func unbend(point: Vector3) -> Vector3:
	var dir := 1 if point.x >= 0.0 else -1
	var p := params(dir)
	if p.x == 0.0 and p.y == 0.0 and p.w == 0.0:
		return point
	var target := Vector2(absf(point.x), point.z)
	var guess := target
	for _n in 8:
		var r := bend_sz(guess.x, guess.y, p)
		var err := target - Vector2(r.x, r.y)
		if err.length_squared() < 1e-12:
			break
		guess += err.rotated(-r.z)
	return Vector3(float(dir) * guess.x, point.y, guess.y)
