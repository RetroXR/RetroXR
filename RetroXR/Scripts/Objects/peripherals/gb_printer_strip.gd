## GbPrinterStrip — how the paper standing out of a Game Boy Printer bends.
##
## Thermal paper off a small roll remembers the roll: out of the slot it curls
## back toward the roll cover, and once there is enough of it, its own weight wins
## and it flops over, swinging when the printer is moved and coming to rest on the
## cover, the deck or the table. This is that, as a 2D elastica in the plane the
## paper bends in (the printer's YZ: across its 38 mm the strip is far too stiff
## to bend, so it never does).
##
## A chain of SEGMENTS segments, each a hinge with a spring toward the roll's
## curl. A hinge carries what hangs past it: gravity (less the slot's own
## acceleration, so a shaken printer shakes its paper) as a torque, and the
## moment of inertia of the paper beyond it. Each hinge steps on its own with its
## spring and damping implicit, which is what keeps it stable however short the
## segments: the tip's hinges, with almost nothing beyond them, simply sit where
## their spring and load balance. Contact is a projection after each step: a
## point found inside an obstacle is moved out along the chain, within the same
## speed limit as free motion. Corrected hinges do not carry that repair as a
## velocity, so contact cannot kick the paper away on the following step.
##
## Pure: the printer hands in where the slot is, which way gravity pulls and what
## is in the way, all in its own frame. Nothing here touches the tree, so a suite
## can check it without one.
class_name GbPrinterStrip
extends RefCounted

## Bending stiffness, N m^2: E about 3 GPa over a 38 x 0.15 mm section (sticker
## paper on its backing). With MASS_PER_M it puts the length at which the paper
## starts to give way to its weight at about 8 cm, which is where it does.
const BEND_STIFFNESS := 3.2e-5
## kg per meter of strip: 38 mm of about 150 g/m^2.
const MASS_PER_M := 0.0057
## The curl the roll leaves in it, as a radius, meters. Judged, not measured: a
## long print in photographs makes a loose, open curve. At 6 cm a 22 cm print
## closed most of a circle, and wherever the printer was its end came back to the
## printer's base, pressed there as if stuck -- measured again at 6.5 cm, 8 and 9
## (2026-10-24), its end curled in under the base. A torn print is free of the
## case and takes the tighter GbThermalRibbon.CURL_RADIUS.
const CURL_RADIUS := 0.13
## The paper's swing, as BookFlop swings a book's pages: one springy, lightly
## damped pendulum for the whole strip, kicked by the printer's moves and turns,
## its angle spread along the strip as extra bend for the hinges to follow. The
## bend alone settles without ever swinging back; this is the flop. SWAY_W2 is its
## spring (rad^2/s^2, about a swing a second) for a SWAY_REF_LENGTH strip, softer
## for a longer one; SWAY_GAIN turns a shove (m/s^2) into a push on it for a
## meter of paper, more for a shorter one; SWAY_SPIN the same for a turn.
const SWAY_W2 := 40.0
const SWAY_REF_LENGTH := 0.1
const SWAY_ZETA := 0.3
const SWAY_GAIN := 0.3
const SWAY_SPIN := 0.15
const SWAY_MAX := 0.8
## The slot holds the paper's direction this many times as firmly as the paper
## holds its own shape.
const ROOT_HOLD := 6.0
## Each hinge's damping as a fraction of critical: critical, as paper in air
## settles without swinging back. At 0.45 the hinges, each settling on its own,
## overshot together: on a printer held in a hand (a probe with tracking noise)
## a short strip's tip turned back 73 times in 6 s, against 28.
const DAMPING := 1.0
## The longest a segment is let be, and the most segments.
const SEGMENT := 0.004
const MAX_SEGMENTS := 48
## The step the chain takes at most, seconds: a frame is cut into as many.
const MAX_STEP := 1.0 / 240.0
## Paper this near the slot is the slot's, never pushed by contact: the slot is
## in the printer's top, and its first millimeters are inside its body's box.
const CONTACT_FROM := 0.008
## How many times a point is pushed out and set back on its segment, at most:
## set back, it can land in something again.
const CONTACT_PASSES := 3
## How far behind a patch of surface paper still counts as in it, meters: past
## that it is on the far side (under the table it hangs over), not in it.
const PATCH_DEPTH := 0.03
## How far under each box counts as the box, meters: all the way to the table.
const UNDER_BOX := 1.0
## The fastest any point of the paper moves against the printer of its own
## accord, m/s: about a sheet of paper's speed falling through air.
const TERMINAL_SPEED := 0.5
## Contact repair slower than this (m/s, the fastest point over a step) is the
## paper settling against what it lies on, not motion: a long strip on the case
## buzzes about 6 mm/s for ever, a tenth of a millimeter a frame.
const REST_SPEED := 0.012
## Half the paper's thickness and a little: how far off a surface it lies.
const SKIN := 0.0008

## The paper's length, and how many segments it is.
var length := 0.0
var segments := 0
## Each hinge's angle from the one before it (hinge 0 from the slot's direction),
## and its speed. Angles grow toward the back, -Z: the way the curl goes.
var angles := PackedFloat64Array()
var speeds := PackedFloat64Array()
## The swing (SWAY_W2), rad over the whole strip, and its speed.
var sway := 0.0
var sway_speed := 0.0
var _contact_motion := 0.0
## The slot, in the printer's (Y, Z), and the angle it points the paper at
## (0 straight up the printer's +Y, growing toward -Z).
var root := Vector2.ZERO
var root_angle := 0.0
## The points along the strip, root first, after the last step.
var points := PackedVector2Array()

## What the paper cannot go into, in the printer's (Y, Z): boxes as Rect2s, and
## surfaces as [normal (unit), offset] where normal . p >= offset is outside.
var boxes: Array[Rect2] = []
var planes: Array = []
## Pieces of surface found in the room: [normal (unit), offset, center, reach],
## a plane as above but only for paper within `reach` of `center` along it and
## no deeper behind it than PATCH_DEPTH (or an optional fifth recovery depth).
## A whole plane under the slot kept a
## long print from hanging over a table's edge, and nothing else in the room
## was there at all.
var patches: Array = []
## Fingertips in the paper's way: [center, radius], round. A finger pushes the
## paper aside and the paper lies against it: nudged, flicked, held up.
var fingers: Array = []
## The other half of a torn print, mirrored into this strip's frame. It starts
## at the shared grip, so only the two segments at that grip are adjacent.
var other_paper := PackedVector2Array()
var _other_bounds := Rect2()


## Set the paper's length. New paper comes out of the slot with the roll's curl
## and pushes what was there out ahead of it, so the shape the strip had is kept,
## counted from its free end.
func set_length(new_length: float) -> void:
	if is_equal_approx(new_length, length) and segments > 0:
		return
	var n := clampi(ceili(new_length / SEGMENT), 2, MAX_SEGMENTS)
	var ds := new_length / n
	var curl := ds / CURL_RADIUS
	# Shorter is a tear (or the power going off): a fresh end of roll, at rest.
	var fresh := segments == 0 or new_length < length
	var old_ds := length / segments if segments > 0 else 0.0
	var new_angles := PackedFloat64Array()
	var new_speeds := PackedFloat64Array()
	new_angles.resize(n)
	new_speeds.resize(n)
	# A print restored at its full length must start without a loop through
	# itself. Its normal curl remains the spring target and settles by contact.
	new_angles.fill(minf(curl, (TAU - 0.1) / n) if fresh else curl)
	new_speeds.fill(0.0)
	new_angles[0] = 0.0
	if not fresh:
		new_angles[0] = angles[0]
		new_speeds[0] = speeds[0]
		for i in range(1, n):
			# The old strip's bend per meter at the same distance from the free
			# end; none yet where this is paper that was still on the roll.
			var s := length - (new_length - i * ds)
			if s <= 0.0:
				continue
			var at := s / old_ds
			var lo := clampi(floori(at), 1, segments - 1)
			var hi := mini(lo + 1, segments - 1)
			var t := clampf(at - lo, 0.0, 1.0)
			new_angles[i] = lerpf(angles[lo], angles[hi], t) * ds / old_ds
			new_speeds[i] = lerpf(speeds[lo], speeds[hi], t) * ds / old_ds
	if fresh:
		sway = 0.0
		sway_speed = 0.0
	length = new_length
	segments = n
	angles = new_angles
	speeds = new_speeds
	_lay_points()


## Put the slot at `at`, pointing the paper at `angle`.
func place(at: Vector2, angle: float) -> void:
	if at == root and angle == root_angle:
		return
	root = at
	root_angle = angle
	_lay_points()


## Step `dt` seconds under `gravity` (m/s^2 in the printer's (Y, Z), the slot's
## acceleration already taken off it) while the printer's turn about its +X (the
## hinges' line) speeds up by `spin_accel` rad/s^2. The paper is slow to follow
## that, so against the printer it lags: each hinge takes the turn's change times
## the inertia past it, the other way. `shove` is the slot's acceleration alone,
## taken off (m/s^2, the printer's (Y, Z)): what swings the paper (sway).
func step(dt: float, gravity: Vector2, spin_accel := 0.0, shove := Vector2.ZERO) -> void:
	if segments == 0 or dt <= 0.0:
		return
	var n_steps := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / n_steps
	_contact_motion = 0.0
	var was := points.duplicate()
	for _s in n_steps:
		_swing(h, shove, spin_accel)
		_substep(h, gravity, spin_accel)
	var farthest := 0.0
	for i in points.size():
		farthest = maxf(farthest, points[i].distance_squared_to(was[i]))
	if sqrt(farthest) < REST_SPEED * dt:
		_contact_motion = 0.0


## Step the swing: the shove across the strip (the way its middle points) and the
## printer's turn push it; its spring and damping bring it back, past, and home.
func _swing(h: float, shove: Vector2, spin_accel: float) -> void:
	var mid := points[points.size() / 2] - root
	var across := Vector2.ZERO
	if mid.length_squared() > 1e-10:
		var phi := atan2(-mid.y, mid.x)
		across = Vector2(-sin(phi), -cos(phi))
	var w2 := SWAY_W2 * clampf(SWAY_REF_LENGTH / length, 0.4, 3.0)
	var push := SWAY_GAIN / maxf(length, 0.02) * shove.dot(across) + SWAY_SPIN * spin_accel
	sway_speed += (push - w2 * sway - 2.0 * SWAY_ZETA * sqrt(w2) * sway_speed) * h
	sway += sway_speed * h
	if absf(sway) > SWAY_MAX:
		sway = clampf(sway, -SWAY_MAX, SWAY_MAX)
		sway_speed = 0.0


## Give the swing a kick, rad/s: the gear's knock coming through the printer,
## or the stub flicking back as the print tears off it.
func jolt(by: float) -> void:
	sway_speed += by


## Bend every hinge to `curvature` (rad/m) and hold it still: a strip taken
## from paper that was already bent (a print torn off the printer). A uniform
## arc is capped short of a full loop so its initial pose cannot cross itself.
func bend_to(curvature: float) -> void:
	if segments == 0:
		return
	var ds := length / segments
	for i in range(1, segments):
		angles[i] = clampf(curvature * ds, -(TAU - 0.1) / segments, (TAU - 0.1) / segments)
		speeds[i] = 0.0
	_lay_points()


## How much it bends, on average, rad/m (its hinges past the slot's).
func mean_curvature() -> float:
	if segments < 2 or length <= 0.0:
		return 0.0
	var total := 0.0
	for i in range(1, segments):
		total += angles[i]
	return total / (length * float(segments - 1) / float(segments))


## The highest any hinge is turning, or the swing, rad/s: zero is at rest.
func motion() -> float:
	var top := maxf(absf(sway_speed), _contact_motion)
	for v in speeds:
		top = maxf(top, absf(v))
	return top


## The strip's direction at each point (the segment's after it; the last, the
## last segment's), as a unit vector in the printer's (Y, Z).
func directions() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(segments + 1)
	var phi := root_angle
	for i in segments:
		phi += angles[i]
		out[i] = _dir(phi)
	out[segments] = out[segments - 1]
	return out


static func _dir(phi: float) -> Vector2:
	return Vector2(cos(phi), -sin(phi))


func _lay_points() -> void:
	points.resize(segments + 1)
	var ds := length / segments
	var p := root
	var phi := root_angle
	points[0] = p
	for i in segments:
		phi += angles[i]
		p += _dir(phi) * ds
		points[i + 1] = p


func _substep(h: float, gravity: Vector2, spin_accel: float) -> void:
	var n := segments
	var ds := length / n
	var m := MASS_PER_M * ds
	var k := BEND_STIFFNESS / ds
	var curl := ds / CURL_RADIUS
	var before := angles.duplicate()

	# What hangs past each hinge, summed from the free end in: its weight, the
	# weight's moment about the origin, and its second moment, so each hinge's
	# torque and inertia come out in one pass.
	var f := gravity * m
	var sum_f := Vector2.ZERO
	var sum_cxf := 0.0
	var sum_m := 0.0
	var sum_mc := Vector2.ZERO
	var sum_mcc := 0.0
	var torque := PackedFloat64Array()
	var inertia := PackedFloat64Array()
	torque.resize(n)
	inertia.resize(n)
	for i in range(n - 1, -1, -1):
		var c := (points[i] + points[i + 1]) * 0.5
		sum_f += f
		sum_cxf += f.x * c.y - f.y * c.x
		sum_m += m
		sum_mc += c * m
		sum_mcc += m * c.length_squared() + m * ds * ds / 12.0
		var p := points[i]
		# Sum of F . swing(c - p) over everything past hinge i.
		torque[i] = sum_cxf - (sum_f.x * p.y - sum_f.y * p.x)
		inertia[i] = sum_mcc - 2.0 * p.dot(sum_mc) + p.length_squared() * sum_m

	for i in n:
		var ki := k * ROOT_HOLD if i == 0 else k
		var rest := 0.0 if i == 0 else curl + sway / (n - 1)
		var inert := inertia[i]
		var c := 2.0 * DAMPING * sqrt(ki * inert)
		var load := torque[i] + spin_accel * inert
		var w := (inert * speeds[i] + h * (load - ki * (angles[i] - rest))) \
			/ (inert + h * c + h * h * ki)
		speeds[i] = w
		angles[i] += h * w
	var was := points.duplicate()
	_lay_points()
	_limit_move(before, was, TERMINAL_SPEED * h)
	var free_angles := angles.duplicate()
	_contact()
	# Projection is positional repair, not an impulse. Limit the COMPLETE move,
	# including contact, and don't turn the repair into a kick next substep.
	var contacted := PackedByteArray()
	contacted.resize(n)
	for i in n:
		contacted[i] = int(absf(wrapf(angles[i] - free_angles[i], -PI, PI)) > 1e-7)
	_limit_move(before, was, TERMINAL_SPEED * h)
	# What each hinge did over the step, the short way round: contact reads a
	# hinge back wrapped to half a turn either way, so one folded right back
	# jumps from +PI to -PI, and taken as a speed that was a turn every few
	# milliseconds, which the next step carried on: the fold spun without end,
	# through its own paper.
	for i in n:
		_contact_motion = maxf(_contact_motion, absf(wrapf(angles[i] - before[i], -PI, PI)) / h)
		speeds[i] = 0.0 if contacted[i] else wrapf(angles[i] - before[i], -PI, PI) / h


## Local particle velocities for an exact tear handoff. Each upstream hinge
## contributes its angular speed to every downstream segment.
func point_velocities() -> PackedVector2Array:
	var out := PackedVector2Array([Vector2.ZERO])
	var velocity := Vector2.ZERO
	var phi := root_angle
	var omega := 0.0
	for i in segments:
		phi += angles[i]
		omega += speeds[i]
		velocity += Vector2(-sin(phi), -cos(phi)) * omega * length / segments
		out.append(velocity)
	return out


## Angles interpolate along their short arc; a wrapped contact angle must not
## send the strip on a full turn. Repeat because endpoint motion is nonlinear.
func _limit_move(before: PackedFloat64Array, was: PackedVector2Array, limit: float) -> void:
	for _pass in 8:
		var farthest := 0.0
		for i in points.size():
			farthest = maxf(farthest, points[i].distance_to(was[i]))
		if farthest <= limit + 1e-7:
			return
		var fraction := minf(0.9, limit / farthest * 0.95)
		for i in segments:
			angles[i] = before[i] + wrapf(angles[i] - before[i], -PI, PI) * fraction
		_lay_points()


## Put every point out of what it is in, follow-the-leader: from the slot out,
## each point is first carried by however far the one before it was moved (so
## the paper past a push keeps its heading and only shifts), then pushed out of
## what it is in, then set back one segment from the one before, toward where it
## was pushed. The hinges are read back off the points after.
##
## Local by construction, and it cannot stretch the paper. Turning hinges to
## push points out swung all the paper past them like a lever, which threw a long
## strip's free end a tenth of a meter in a frame over the table; and turning
## only the hinge behind could not lift a point whose segment ran along the push,
## which left the curled end of a long strip inside the printer.
func _contact() -> void:
	# Headings contained in a half turn make a monotone curve, which cannot
	# intersect itself. Most short prints need no pairwise contact work at all.
	var phi_min := 0.0
	var phi_max := 0.0
	var heading := 0.0
	for angle in angles:
		heading += angle
		phi_min = minf(phi_min, heading)
		phi_max = maxf(phi_max, heading)
	var self_contact := phi_max - phi_min >= PI - 0.05
	var external := not (boxes.is_empty() and planes.is_empty() and patches.is_empty() and fingers.is_empty())
	if not self_contact and not external and other_paper.is_empty():
		return
	var ds := length / segments
	var first := maxi(1, ceili(CONTACT_FROM / ds))
	var shift := Vector2.ZERO
	var any := false
	var out := points.duplicate()
	for j in range(1, segments + 1):
		var was := points[j]
		var p := was + shift
		for _try in CONTACT_PASSES:
			var push := _push_out(p) if j >= first else Vector2.ZERO
			if self_contact or any:
				push += _self_push(p + push, out, j)
			if not other_paper.is_empty() and _other_bounds.intersects(Rect2(out[j - 1], p + push - out[j - 1]).abs(), true):
				for k in range(other_paper.size() - 1):
					if j == 1 and k == 0:
						continue
					push += _segment_push(out[j - 1], p + push, other_paper[k], other_paper[k + 1])
			if push == Vector2.ZERO:
				break
			any = true
			var d := (p + push) - out[j - 1]
			p = out[j - 1] + d.normalized() * ds if d.length_squared() > 1e-14 else p + push
		out[j] = p
		shift = p - was
	if not any:
		return
	# The hinges back off the points: each the turn from the segment before.
	var phi := root_angle
	for i in segments:
		var d := out[i + 1] - out[i]
		var seg_phi := atan2(-d.y, d.x)
		angles[i] = wrapf(seg_phi - phi, -PI, PI)
		phi += angles[i]
	_lay_points()


## A later segment rests against the earlier paper. Test the whole segment for
## a crossing as well as the endpoint for thickness: endpoint-only tests miss
## an X-shaped fold whose four ends are all clear. Adjacent segments share a
## hinge and are deliberately excluded.
func _self_push(p: Vector2, out: PackedVector2Array, j: int) -> Vector2:
	var start := out[j - 1]
	var push := Vector2.ZERO
	for k in range(j - 2):
		push += _segment_push(start, p + push, out[k], out[k + 1])
	return push


func _segment_push(start: Vector2, end: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var skin := minf(SKIN * 2.0, length / segments * 0.25)
	if minf(start.x, end.x) > maxf(a.x, b.x) + skin or maxf(start.x, end.x) < minf(a.x, b.x) - skin \
			or minf(start.y, end.y) > maxf(a.y, b.y) + skin or maxf(start.y, end.y) < minf(a.y, b.y) - skin:
		return Vector2.ZERO
	var near := Geometry2D.get_closest_point_to_segment(end, a, b)
	var d := end - near
	if Geometry2D.segment_intersects_segment(start, end, a, b) != null:
		var along := (b - a).normalized()
		var normal := Vector2(-along.y, along.x)
		if normal.dot(start - a) < 0.0:
			normal = -normal
		return normal * maxf(0.0, skin - normal.dot(end - a))
	if d.length_squared() < skin * skin:
		var normal := d.normalized() if d.length_squared() > 1e-14 else (start - near).normalized()
		return normal * (skin - d.length())
	return Vector2.ZERO


func meet_other_half(other: GbPrinterStrip) -> void:
	other_paper.resize(other.points.size())
	for i in other.points.size():
		other_paper[i] = Vector2(-other.points[i].x, other.points[i].y)
		_other_bounds = Rect2(other_paper[i], Vector2.ZERO) if i == 0 else _other_bounds.expand(other_paper[i])
	_other_bounds = _other_bounds.grow(SKIN * 2.0)


## How far, and which way, `p` has to go to be clear of everything: the deepest
## obstacle's way out, or zero when it is clear.
##
## The boxes are one solid, the printer: a way out of one is taken only if it is
## clear of all of them. Each box on its own sent a point under the cover's hump
## up out of the body's top, into the hump, and the hump sent it back down; the
## two pushes cancelled and the paper stayed inside the printer.
##
## A box reaches all the way down (the printer's -Y): under the printer is never
## where paper goes. The printer stands a hair off the table, and paper crept
## into that gap; lifted and set down again, the printer then pinched it there,
## and it thrashed.
##
## Nor is a way out taken that goes deeper into a surface than the point already
## is. Deeper, not into at all: paper lying ON the table touches it, and a rule
## against any touch shut it out of its way out sideways.
func _push_out(p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var inside := false
	var now_under := maxf(_under(p), 0.0)
	var fallback := Vector2.ZERO
	for box: Rect2 in boxes:
		var r := _solid(box)
		if not r.has_point(p):
			continue
		inside = true
		for o: Vector2 in [
				Vector2(r.position.x - p.x, 0.0), Vector2(r.end.x - p.x, 0.0),
				Vector2(0.0, r.position.y - p.y), Vector2(0.0, r.end.y - p.y)]:
			if fallback == Vector2.ZERO or o.length_squared() < fallback.length_squared():
				fallback = o
			if best != Vector2.ZERO and o.length_squared() >= best.length_squared():
				continue
			# Just past the face, so the box it leaves does not count it in.
			var to := p + o + o.normalized() * 1e-6
			if _under(to) > now_under + SKIN * 0.5 or _in_solid(to):
				continue
			best = o
	if inside and best == Vector2.ZERO:
		best = fallback
	# Out of the printer, then off the table from there: a point in the corner of
	# the two goes into the corner in one push, where pushing it out of one and
	# then out of the other, a pass at a time, ping-ponged it.
	best += _off_surface(p + best)
	# Round a finger, from where the point would be.
	for finger: Array in fingers:
		var d: Vector2 = p + best - (finger[0] as Vector2)
		var reach := float(finger[1]) + SKIN
		if d.length_squared() < reach * reach:
			var l := d.length()
			best += (d / l if l > 1e-6 else Vector2(0.0, -1.0)) * (reach - l)
	return best


## Up out of whichever surface `p` is deepest in, or zero when it is in none.
func _off_surface(p: Vector2) -> Vector2:
	var out := Vector2.ZERO
	var deepest := 0.0
	for plane: Array in planes:
		var normal: Vector2 = plane[0]
		var under: float = float(plane[1]) + SKIN - normal.dot(p)
		if under > deepest:
			deepest = under
			out = normal * under
	for piece: Array in patches:
		var under := _in_patch(piece, p)
		if under > deepest:
			deepest = under
			out = (piece[0] as Vector2) * under
	return out


## How far `p` is into a patch of surface, or 0 or less when it is not (beside
## it, or past PATCH_DEPTH behind it).
static func _in_patch(piece: Array, p: Vector2) -> float:
	var normal: Vector2 = piece[0]
	var under: float = float(piece[1]) + SKIN - normal.dot(p)
	# A swept hit can retain a deeper contact until the paper has recovered.
	# Ordinary patches keep their depth cutoff so paper can hang under an edge.
	var depth := float(piece[4]) if piece.size() > 4 else PATCH_DEPTH
	if under <= 0.0 or under > depth:
		return 0.0
	var along := Vector2(normal.y, -normal.x)
	if absf(along.dot(p - (piece[2] as Vector2))) > float(piece[3]):
		return 0.0
	return under


## A box as the paper meets it: a skin bigger, and reaching all the way down.
static func _solid(box: Rect2) -> Rect2:
	var r := box.grow(SKIN)
	return Rect2(r.position - Vector2(UNDER_BOX, 0.0), r.size + Vector2(UNDER_BOX, 0.0))


func _in_solid(p: Vector2) -> bool:
	for box: Rect2 in boxes:
		if _solid(box).has_point(p):
			return true
	return false


## How far `p` is into the surface it is deepest in, or 0 or less when it is in none.
func _under(p: Vector2) -> float:
	var deepest := -INF
	for plane: Array in planes:
		var normal: Vector2 = plane[0]
		deepest = maxf(deepest, float(plane[1]) + SKIN - normal.dot(p))
	for piece: Array in patches:
		deepest = maxf(deepest, _in_patch(piece, p))
	return deepest if deepest != -INF else 0.0
