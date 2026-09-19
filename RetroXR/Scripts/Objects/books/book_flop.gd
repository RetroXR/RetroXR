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
var _fan_count := [0, 0]
var _fan := [PackedFloat64Array(), PackedFloat64Array()]
var _fan_v := [PackedFloat64Array(), PackedFloat64Array()]
var _fan_suppressed := [false, false]
var _leaves := [0, 0]
var _sag := 0.0
var _sag_v := 0.0
var _sag_hand := [0.0, 0.0]

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
			_fan_count[i] = n
			var d := PackedFloat64Array()
			d.resize(n)
			var v := PackedFloat64Array()
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
		_accel[i] = Vector3.ZERO
		for k in _fan_count[i]:
			_fan[i][k] = 0.0
			_fan_v[i][k] = 0.0
	_sag = 0.0
	_sag_v = 0.0
	_sag_hand = [0.0, 0.0]
	_have_pose = 0
	_still_ticks = 0


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
	_clamp[i] = move_toward(_clamp[i], _clamp_target[i], CLAMP_RATE * h)
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

	# A hard stop behind the soft one, so no input can fold a half through itself.
	var hard_max := ANGLE_MAX + HARD_STOP_MARGIN
	var hard_min := angle_min - HARD_STOP_MARGIN
	total = _hinge[i] + _bend[i]
	if total > hard_max or total < hard_min:
		var excess: float = total - clampf(total, hard_min, hard_max)
		# A board has no bend to give, so its joint takes the whole stop.
		var from_hinge := 1.0 if hardback else 0.5
		_hinge[i] -= excess * from_hinge
		_bend[i] -= excess * (1.0 - from_hinge)
		_hinge_v[i] = 0.0
		_bend_v[i] = 0.0
	if floppiness <= 0.0:
		_hinge[i] = 0.0
		_hinge_v[i] = 0.0
		_bend[i] = 0.0
		_bend_v[i] = 0.0

	_step_fan(i, h, a_s, a_z, gain)


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
	var far: float = sag_slope(-1 if i == 1 else 1) + _hinge[1 - i] + _bend[1 - i]
	var ceiling := minf(FAN_ANGLE_MAX, PI - far - FAN_FAR_CLEARANCE) - base
	for k in n:
		var w2 := FAN_W2 * (1.0 + FAN_W2_SPREAD * float(k))
		var ang: float = base + d[k]
		var acc := -w2 * d[k] - 2.0 * FAN_ZETA * sqrt(w2) * v[k] \
			+ gain * (a_z * cos(ang) - a_s * sin(ang))
		v[k] += acc * h
		d[k] += v[k] * h
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
	var i := _i(dir)
	var d := fan_delta(dir, k)
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
		return bend_sz(s, z, params(own_dir), hl)
	var far := bend_sz(-s, z, params(-own_dir), hl)
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
func bend_over(point: Vector3, own_dir: int, lift: float = 0.0, pivot_z: float = 0.0) -> Vector3:
	var d := 1.0 if own_dir > 0 else -1.0
	var lifted := Vector2(d * point.x, point.z - pivot_z).rotated(lift)
	var r := _bend_over_sz(lifted.x, lifted.y + pivot_z, own_dir)
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
		var step := Vector2((e * err.x - b * err.y) / det, (a * err.y - c * err.x) / det)
		# A full step can overshoot where the arc length switches on (z = 0).
		guess += step.limit_length(0.05)
	# The droop is undone; now the leaf's own hinge, which was applied first.
	var flat := Vector2(guess.x, guess.y - pivot_z).rotated(-lift)
	return Vector3(d * flat.x, point.y, flat.y + pivot_z)


## Rotation of the sheet about the book's Y axis at that point, as a Node3D
## rotation.y: the right half tilting toward +Z turns -angle about Y.
func bend_rotation_y(point: Vector3) -> float:
	var dir := 1 if point.x >= 0.0 else -1
	return -float(dir) * bend_sz(absf(point.x), point.z, params(dir)).z


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
