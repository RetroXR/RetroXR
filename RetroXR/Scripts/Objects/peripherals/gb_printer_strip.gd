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
## point found inside an obstacle is turned out of it by the hinges behind it,
## and the hinges' speeds are what their angles did over the step, so paper laid
## on something stays laid on it.
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
## The curl the roll leaves in it, as a radius, meters.
const CURL_RADIUS := 0.06
## The slot holds the paper's direction this many times as firmly as the paper
## holds its own shape.
const ROOT_HOLD := 6.0
## Each hinge's damping as a fraction of critical: paper in air settles in a
## swing or two.
const DAMPING := 0.45
## The longest a segment is let be, and the most segments.
const SEGMENT := 0.004
const MAX_SEGMENTS := 48
## The step the chain takes at most, seconds: a frame is cut into as many.
const MAX_STEP := 1.0 / 120.0
## Paper this near the slot is the slot's, never pushed by contact: the slot is
## in the printer's top, and its first millimeters are inside its body's box.
const CONTACT_FROM := 0.008
## How many hinges behind a point share turning it out of an obstacle, and the
## most any one turns for it in a step.
const CONTACT_HINGES := 8
const CONTACT_MAX_TURN := 0.3
## Half the paper's thickness and a little: how far off a surface it lies.
const SKIN := 0.0008

## The paper's length, and how many segments it is.
var length := 0.0
var segments := 0
## Each hinge's angle from the one before it (hinge 0 from the slot's direction),
## and its speed. Angles grow toward the back, -Z: the way the curl goes.
var angles := PackedFloat64Array()
var speeds := PackedFloat64Array()
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
	new_angles.fill(curl)
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


## The printer has turned `by` rad about the hinges' line under the paper (its
## +X). The paper keeps its heading in the room for that instant, so against the
## printer it turns the other way, at the slot, and the slot's hold brings it
## round after.
func turn_root(by: float) -> void:
	if segments == 0:
		return
	angles[0] += by
	_lay_points()


## Step `dt` seconds under `gravity` (m/s^2 in the printer's (Y, Z), the slot's
## acceleration already taken off it).
func step(dt: float, gravity: Vector2) -> void:
	if segments == 0 or dt <= 0.0:
		return
	var n_steps := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / n_steps
	for _s in n_steps:
		_substep(h, gravity)


## The highest any hinge is turning, rad/s: zero is at rest.
func motion() -> float:
	var top := 0.0
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


## What a turn of +1 rad about `pivot` does to a point `r` from it.
static func _swing(r: Vector2) -> Vector2:
	return Vector2(r.y, -r.x)


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


func _substep(h: float, gravity: Vector2) -> void:
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
		var rest := 0.0 if i == 0 else curl
		var inert := inertia[i]
		var c := 2.0 * DAMPING * sqrt(ki * inert)
		var w := (inert * speeds[i] + h * (torque[i] - ki * (angles[i] - rest))) \
			/ (inert + h * c + h * h * ki)
		speeds[i] = w
		angles[i] += h * w
	_lay_points()
	_contact()
	for i in n:
		speeds[i] = (angles[i] - before[i]) / h


## Turn every point found inside an obstacle back out of it, root first, by the
## hinges behind it, each as far as it moves the point out.
func _contact() -> void:
	if boxes.is_empty() and planes.is_empty():
		return
	var ds := length / segments
	var first := maxi(1, ceili(CONTACT_FROM / ds))
	for j in range(first, segments + 1):
		var push := _push_out(points[j])
		if push == Vector2.ZERO:
			continue
		var depth := push.length()
		var normal := push / depth
		var lo := maxi(1, j - CONTACT_HINGES)
		var gains := PackedFloat64Array()
		gains.resize(j - lo)
		var total := 0.0
		for i in range(lo, j):
			var g := normal.dot(_swing(points[j] - points[i]))
			gains[i - lo] = g
			total += g * g
		if total < 1e-12:
			continue
		for i in range(lo, j):
			angles[i] += clampf(depth * gains[i - lo] / total, -CONTACT_MAX_TURN, CONTACT_MAX_TURN)
		_lay_points()


## How far, and which way, `p` has to go to be clear of everything: the deepest
## obstacle's way out, or zero when it is clear. Never out of a box into a
## surface: the printer stands a hair off the table, and paper pushed out of its
## bottom went under the table, back up, and so on until it was under the printer.
func _push_out(p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	for box: Rect2 in boxes:
		var r := box.grow(SKIN)
		if not r.has_point(p):
			continue
		var outs := [
			Vector2(r.position.x - p.x, 0.0), Vector2(r.end.x - p.x, 0.0),
			Vector2(0.0, r.position.y - p.y), Vector2(0.0, r.end.y - p.y)]
		var way := Vector2.ZERO
		for o: Vector2 in outs:
			# Half a skin's grace: paper lying on the table beside the box is where
			# it should be, not under it.
			if _under(p + o) > SKIN * 0.5:
				continue
			if way == Vector2.ZERO or o.length_squared() < way.length_squared():
				way = o
		if way.length_squared() > best.length_squared():
			best = way
	var under := _under(p)
	if under > 0.0 and under * under > best.length_squared():
		for plane: Array in planes:
			var normal: Vector2 = plane[0]
			if float(plane[1]) + SKIN - normal.dot(p) >= under:
				best = normal * under
				break
	return best


## How far `p` is into the surface it is deepest in, or 0 or less when it is in none.
func _under(p: Vector2) -> float:
	var deepest := -INF
	for plane: Array in planes:
		var normal: Vector2 = plane[0]
		deepest = maxf(deepest, float(plane[1]) + SKIN - normal.dot(p))
	return deepest if not planes.is_empty() else 0.0
