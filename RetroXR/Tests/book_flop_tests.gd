## book_flop_tests — a soft-cover book hangs from the hand, and only from the hand.
##
## Two halves. `sim/` steps BookFlop on its own with a fixed dt: it is pure, so
## the same inputs give the same numbers every run and the cases can assert
## SIGNS and orderings rather than tuned magnitudes. `book/` checks the wiring on
## a real PDFBook — above all that every surface on one side of the gutter is
## handed the very same bend, because a block bent differently from the sheet on
## top of it comes straight through the page (see paper_rest.gdshaderinc for the
## two times that class of bug already shipped).
##
## What this CANNOT show is how it looks or feels: that is
## Tools/vr/book_flop_probe (windowed, renders the poses) and the headset.
##
## Needs no PDF and no godot-pdfium: the book is a CBZ built here.
extends Node3D

const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const CBZ_PATH := "user://__book_flop_tests.cbz"
const PAGES := 24
const THICK_CBZ_PATH := "user://__book_flop_tests_thick.cbz"
const THICK_PAGES := 400
const DT := 1.0 / 90.0
const G := 9.8

const FACE_UP := Vector3(0.0, 0.0, -G)     # pages to the ceiling: gravity is local -Z
const FACE_DOWN := Vector3(0.0, 0.0, G)
const SPINE_DOWN := Vector3(0.0, -G, 0.0)  # reading posture: gravity along the spine

var _failed := 0
var _ran := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[test] FAIL suite/timed out")
		get_tree().quit(1))

	_test_sim_direction()
	_test_sim_stiffness()
	_test_sim_support()
	_test_sim_two_hands()
	_test_sim_sag()
	_test_sim_hardback()
	_test_sim_fan()
	_test_sim_robustness()
	_test_sim_pose_drive()
	_test_bend_geometry()
	_test_bent_outline_shaders()
	await _test_book()
	await _test_turning_leaf_textures()
	await _test_end_leaves()
	await _test_thick_book()

	print("[test] %d cases, %s" % [_ran,
		"PASS" if _failed == 0 else "%d FAILURE(S)" % _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ── sim ───────────────────────────────────────────────────────────────────────

func _open_sim(left: int = 12, right: int = 12, fan: int = 0) -> BookFlop:
	var sim := BookFlop.new()
	sim.configure(0.18, left, right, 1, 1, true, fan, fan)
	return sim


func _run(sim: BookFlop, accel: Vector3, ticks: int = 500) -> void:
	for i in ticks:
		sim.step(DT, accel, accel)


func _test_sim_direction() -> void:
	var up := _open_sim()
	_run(up, FACE_UP)
	_ok(up.tip_angle(1) < -0.05 and up.tip_angle(-1) < -0.05,
		"sim/held face-up, both halves droop AWAY from the reader (%.3f, %.3f)"
			% [up.tip_angle(-1), up.tip_angle(1)])
	_ok(is_equal_approx(up.tip_angle(1), up.tip_angle(-1)),
		"sim/equal halves droop equally")

	var down := _open_sim()
	_run(down, FACE_DOWN)
	_ok(down.tip_angle(1) > 0.05 and down.tip_angle(-1) > 0.05,
		"sim/held face-down, both halves hang TOWARD each other (%.3f, %.3f)"
			% [down.tip_angle(-1), down.tip_angle(1)])

	var reading := _open_sim()
	_run(reading, SPINE_DOWN)
	_ok(absf(reading.tip_angle(1)) < 1e-9 and absf(reading.tip_angle(-1)) < 1e-9,
		"sim/gravity along the spine bends nothing — a book held to read stays flat")

	var rigid := _open_sim()
	rigid.floppiness = 0.0
	_run(rigid, FACE_UP)
	_ok(rigid.params(1) == Vector4.ZERO and rigid.params(-1) == Vector4.ZERO,
		"sim/floppiness 0 is exactly the rigid book")

	# Hanging by the top half: that half points up (an inverted pendulum), the
	# other down. Neither may run away.
	var hung := _open_sim()
	_run(hung, Vector3(G, 0.0, 0.0))
	_ok(absf(hung.tip_angle(1)) < 1e-9 and absf(hung.tip_angle(-1)) < 1e-9,
		"sim/gravity straight along a flat page has no lever on it")


func _test_sim_stiffness() -> void:
	var manual := _open_sim(2, 2)
	var tome := _open_sim(150, 150)
	_run(manual, FACE_UP)
	_run(tome, FACE_UP)
	_ok(absf(manual.tip_angle(1)) > absf(tome.tip_angle(1)) * 2.0,
		"sim/a 4-leaf manual droops much further than a 300-leaf book (%.3f vs %.3f)"
			% [manual.tip_angle(1), tome.tip_angle(1)])

	# Lopsided: near the front of a book the left half is thin and the right thick.
	var lopsided := _open_sim(2, 60)
	_run(lopsided, FACE_UP)
	_ok(absf(lopsided.tip_angle(-1)) > absf(lopsided.tip_angle(1)),
		"sim/the thin half of a lopsided spread is the floppy one")

	var shut := BookFlop.new()
	shut.configure(0.18, 0, 12, 0, 2, false)
	_run(shut, FACE_UP)
	_ok(absf(shut.hinge(1)) < 1e-6 and shut.bend_angle(1) < -0.01,
		"sim/a shut book bends but has no free hinge (hinge %.4f, bend %.3f)"
			% [shut.hinge(1), shut.bend_angle(1)])
	_ok(shut.params(-1) == Vector4.ZERO, "sim/the half a shut book does not have stays flat")


func _test_sim_support() -> void:
	var sim := _open_sim()
	sim.set_support(true, Vector3(0.10, 0.0, 0.0))   # hand 10 cm out on the right page
	_run(sim, FACE_UP)
	_ok(sim.support(1) > 0.09 and sim.support(-1) == 0.0,
		"sim/the hand supports the half it is on, and only that half")
	_ok(absf(sim.hinge(1)) < 0.01 and sim.hinge(-1) < -0.1,
		"sim/the supported half does not hinge; the free half still does (%.3f, %.3f)"
			% [sim.hinge(1), sim.hinge(-1)])
	_ok(absf(sim.tip_angle(1)) < absf(sim.tip_angle(-1)),
		"sim/the supported half droops less than the free one")

	var spine := _open_sim()
	spine.set_support(true, Vector3(0.005, 0.0, 0.0))
	_run(spine, FACE_UP)
	_ok(spine.support(1) == 0.0 and spine.hinge(1) < -0.1,
		"sim/a hand on the spine supports neither half")

	sim.set_support(false, Vector3.ZERO)
	_run(sim, FACE_UP)
	_ok(sim.support(1) == 0.0, "sim/letting go releases the support")


## One hand on each end is how you steady a limp magazine to read it.
func _test_sim_two_hands() -> void:
	var one := _open_sim()
	one.set_support(true, Vector3(0.12, 0.0, 0.0))
	_run(one, FACE_UP)

	var two := _open_sim()
	two.set_support(true, Vector3(0.12, 0.0, 0.0), Vector3(-0.12, 0.0, 0.0))
	_run(two, FACE_UP)
	_ok(two.support(1) > 0.11 and two.support(-1) > 0.11,
		"sim/two hands, one on each half: both halves are supported")
	_ok(absf(two.hinge(1)) < 0.01 and absf(two.hinge(-1)) < 0.01,
		"sim/...so neither hinges")
	_ok(absf(two.tip_angle(-1)) < absf(one.tip_angle(-1)) * 0.5,
		"sim/...and the half the second hand took stops hanging (%.3f -> %.3f)"
			% [one.tip_angle(-1), two.tip_angle(-1)])
	_ok(two.tip_angle(1) < -0.001,
		"sim/...though the strip beyond each hand still droops a little (%.4f)" % two.tip_angle(1))

	# Both hands on the SAME half: the further one is what holds it up.
	var same := _open_sim()
	same.set_support(true, Vector3(0.05, 0.0, 0.0), Vector3(0.13, 0.0, 0.0))
	_run(same, FACE_UP)
	_ok(same.support(1) > 0.12 and same.support(-1) == 0.0,
		"sim/two hands on one half: supported out to the further hand, the other half free")

	two.set_support(true, Vector3(0.12, 0.0, 0.0))
	_run(two, FACE_UP)
	_ok(two.support(-1) == 0.0 and two.hinge(-1) < -0.1,
		"sim/the second hand lets go: that half hangs again")


## The middle of a spread hangs between two hands. The hands do not move, so the
## GUTTER drops and each half slopes up from it to its hand.
func _test_sim_sag() -> void:
	var sim := _open_sim(7, 7)
	sim.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.14, 0.0, 0.0))
	_run(sim, FACE_UP)
	_ok(sim.sag() < -0.005, "sag/held at both ends face-up, the gutter DROPS (%.1f mm)" % (sim.sag() * 1000.0))
	_ok(sim.sag_slope(1) > 0.02 and is_equal_approx(sim.sag_slope(1), sim.sag_slope(-1)),
		"sag/...and both halves slope up from it to the hands (%.1f deg)" % rad_to_deg(sim.sag_slope(1)))
	var grip_r := sim.bend(Vector3(0.14, 0.0, 0.0))
	var grip_l := sim.bend(Vector3(-0.14, 0.0, 0.0))
	_ok(absf(grip_r.z) < 0.002 and absf(grip_l.z) < 0.002,
		"sag/the paper in each hand stays in the hand (z %.2f, %.2f mm)" % [grip_r.z * 1000.0, grip_l.z * 1000.0])
	var gut_r := sim.bend(Vector3(1e-7, 0.0, 0.0))
	var gut_l := sim.bend(Vector3(-1e-7, 0.0, 0.0))
	_ok(absf(gut_r.z - gut_l.z) < 1e-6 and absf(gut_r.z - sim.sag()) < 1e-6,
		"sag/the two halves still meet at the binding")
	_ok(sim.unbend(sim.bend(Vector3(0.10, 0.03, 0.02))).distance_to(Vector3(0.10, 0.03, 0.02)) < 1e-5,
		"sag/a hand on a sagging page is still found on the flat one")

	# Hands at different distances: ONE drop, two slopes — the nearer hand's half
	# is the steeper. Anything else tears the spread at the gutter.
	var skew := _open_sim(7, 7)
	skew.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.07, 0.0, 0.0))
	_run(skew, FACE_UP)
	_ok(skew.sag_slope(-1) > skew.sag_slope(1) * 1.5 and skew.sag_slope(1) > 0.0,
		"sag/unequal hands: the half with the nearer hand is steeper (%.1f vs %.1f deg)"
			% [rad_to_deg(skew.sag_slope(-1)), rad_to_deg(skew.sag_slope(1))])
	_ok(absf(skew.bend(Vector3(0.14, 0, 0)).z) < 0.002 and absf(skew.bend(Vector3(-0.07, 0, 0)).z) < 0.002
			and absf(skew.bend(Vector3(1e-7, 0, 0)).z - skew.bend(Vector3(-1e-7, 0, 0)).z) < 1e-6,
		"sag/...both grips still hold and the gutter is still one line")

	var down := _open_sim(7, 7)
	down.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.14, 0.0, 0.0))
	_run(down, FACE_DOWN)
	_ok(down.sag() > 0.005 and down.sag_slope(1) < -0.02, "sag/turned over, it hangs the other way")

	var thick := _open_sim(150, 150)
	thick.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.14, 0.0, 0.0))
	_run(thick, FACE_UP)
	_ok(absf(thick.sag()) < absf(sim.sag()) * 0.5,
		"sag/a thick book sags far less than a manual (%.1f vs %.1f mm)" % [thick.sag() * 1000.0, sim.sag() * 1000.0])

	var narrow := _open_sim(7, 7)
	narrow.set_support(true, Vector3(0.05, 0.0, 0.0), Vector3(-0.05, 0.0, 0.0))
	_run(narrow, FACE_UP)
	_ok(absf(narrow.sag()) < absf(sim.sag()) * 0.5,
		"sag/hands close together leave little to sag between (%.1f mm)" % (narrow.sag() * 1000.0))

	var one := _open_sim(7, 7)
	one.set_support(true, Vector3(0.14, 0.0, 0.0))
	_run(one, FACE_UP)
	_ok(one.sag() == 0.0 and one.params(1).w == 0.0, "sag/one hand has nothing to sag between: EXACTLY zero")

	var boards := _open_sim(7, 7)
	boards.hardback = true
	boards.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.14, 0.0, 0.0))
	_run(boards, FACE_UP)
	_ok(boards.sag() == 0.0, "sag/boards held at both ends hold the joint up")

	# The second hand lets go: the sag eases out. The slope must never whip UP on
	# the way, which is what dividing by a support point sliding home would do.
	var before := sim.sag_slope(-1)
	var worst := before
	sim.set_support(true, Vector3(0.14, 0.0, 0.0))
	for i in 400:
		sim.step(DT, FACE_UP, FACE_UP)
		worst = maxf(worst, sim.sag_slope(-1))
	_ok(absf(sim.sag()) < 1e-4, "sag/a hand lets go and the sag eases out")
	_ok(worst <= before + 1e-9, "sag/...without the slope ever whipping up on the way (%.2f deg peak, %.2f before)"
		% [rad_to_deg(worst), rad_to_deg(before)])

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A6
	var wild := _open_sim(3, 3, 3)
	wild.set_support(true, Vector3(0.14, 0.0, 0.0), Vector3(-0.06, 0.0, 0.0))
	var sane := true
	for i in 2000:
		var a := Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		wild.step(DT * rng.randf_range(0.5, 3.0), a, a)
		for dir: int in [-1, 1]:
			var slope := wild.sag_slope(dir)
			sane = sane and not is_nan(slope) and absf(slope) <= asin(BookFlop.SAG_MAX_SLOPE) + 1e-9
	_ok(sane, "sag/shaken violently, no half ever slopes past 30 degrees or goes NaN")


## Boards do not bend, and barely open past flat — but they still swing shut.
func _test_sim_hardback() -> void:
	var soft := _open_sim()
	var hard := _open_sim()
	hard.hardback = true
	_run(soft, FACE_UP)
	_run(hard, FACE_UP)
	_ok(hard.bend_angle(1) == 0.0 and hard.params(1).y == 0.0,
		"sim/hardback: the boards do not bend at all")
	_ok(hard.tip_angle(1) < -0.001 and hard.tip_angle(1) > BookFlop.HARDBACK_ANGLE_MIN - BookFlop.HARD_STOP_MARGIN - 1e-6,
		"sim/hardback: held face-up it opens barely past flat (%.3f, a softcover %.3f)"
			% [hard.tip_angle(1), soft.tip_angle(1)])
	_ok(absf(hard.tip_angle(1)) < absf(soft.tip_angle(1)) * 0.5,
		"sim/hardback: ...far less than the same book in soft covers")

	var down := _open_sim(12, 12, 3)
	down.hardback = true
	_run(down, FACE_DOWN)
	_ok(down.tip_angle(1) > 0.3, "sim/hardback: turned over, the boards still swing toward shut (%.3f)" % down.tip_angle(1))
	_ok(down.fan_delta(1, 0) > down.fan_delta(1, 2) and down.fan_delta(1, 2) > 0.02,
		"sim/hardback: ...and the pages inside still fan — they are paper")

	var shut := BookFlop.new()
	shut.hardback = true
	shut.configure(0.18, 0, 12, 0, 2, false)
	_run(shut, FACE_UP)
	_ok(shut.params(1) == Vector4.ZERO, "sim/hardback: shut, it is a rigid block")

	# Switched on mid-hang, the bend it already had must not be left frozen in.
	soft.hardback = true
	soft.step(DT, FACE_UP, FACE_UP)
	_ok(soft.bend_angle(1) == 0.0, "sim/hardback: switched on while hanging, the bend goes at once")


func _test_sim_fan() -> void:
	var up := _open_sim(12, 12, 3)
	_run(up, FACE_UP)
	var shut := true
	for k in 3:
		shut = shut and up.fan_delta(1, k) == 0.0 and up.fan_delta(-1, k) == 0.0
	_ok(shut, "sim/face-up, gravity pins the fan shut at EXACTLY zero (nothing to draw)")

	var down := _open_sim(12, 12, 3)
	_run(down, FACE_DOWN)
	_ok(down.fan_delta(1, 0) > down.fan_delta(1, 1) and down.fan_delta(1, 1) > down.fan_delta(1, 2)
			and down.fan_delta(1, 2) > 0.02,
		"sim/face-down the leaves peel and FAN: top furthest (%.3f > %.3f > %.3f)"
			% [down.fan_delta(1, 0), down.fan_delta(1, 1), down.fan_delta(1, 2)])

	down.suppress_fan(1, true)
	_ok(down.fan_delta(1, 0) == 0.0, "sim/turning a page shuts that side's fan at once")
	_run(down, FACE_DOWN, 60)
	_ok(down.fan_delta(1, 0) == 0.0 and down.fan_delta(-1, 0) > 0.02,
		"sim/...keeps it shut, and leaves the other side's alone")
	down.suppress_fan(1, false)
	_run(down, FACE_DOWN)
	_ok(down.fan_delta(1, 0) > 0.02, "sim/...and lets it fall open again afterwards")


func _test_sim_robustness() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB00C
	var sim := _open_sim(6, 20, 3)
	var sane := true
	var ordered := true
	var worst := 0.0
	var hard := maxf(BookFlop.ANGLE_MAX, -BookFlop.ANGLE_MIN) + BookFlop.HARD_STOP_MARGIN + 1e-6
	for i in 3000:
		var a := Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var b := Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		if i % 300 == 0:
			sim.set_support(rng.randf() > 0.5, Vector3(rng.randf_range(-0.2, 0.2), 0.0, 0.0))
		sim.step(DT * rng.randf_range(0.5, 3.0), a, b)
		for dir: int in [-1, 1]:
			var t := sim.tip_angle(dir)
			sane = sane and not is_nan(t) and not is_inf(t)
			worst = maxf(worst, absf(t))
			var last := INF
			for k in 3:
				var d := sim.fan_delta(dir, k)
				ordered = ordered and d >= 0.0 and d <= last and not is_nan(d)
				last = d
	_ok(sane, "sim/3000 ticks of violent shaking: never NaN or infinite")
	_ok(worst <= hard and hard < PI * 0.5,
		"sim/...and no half ever reaches 90 degrees, where two could cross (worst %.3f rad)" % worst)
	_ok(ordered, "sim/...and no loose leaf ever passes the block or the leaf under it")

	# Same inputs, same bits.
	var one := _open_sim(6, 20, 3)
	var two := _open_sim(6, 20, 3)
	for sim2: BookFlop in [one, two]:
		var r := RandomNumberGenerator.new()
		r.seed = 7
		for i in 400:
			sim2.step(DT, Vector3(r.randf_range(-20, 20), 0, r.randf_range(-20, 20)), FACE_DOWN)
	_ok(one.params(1) == two.params(1) and one.params(-1) == two.params(-1)
			and one.fan_delta(-1, 0) == two.fan_delta(-1, 0),
		"sim/deterministic: the same inputs give bit-identical state")


func _test_sim_pose_drive() -> void:
	# Pages to the ceiling: local +Z is world up, local Y lies along world -Z.
	var face_up := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0, 1.2, 0))
	var sim := _open_sim()
	for i in 500:
		sim.drive_from_pose(DT, face_up, true)
	_ok(sim.tip_angle(1) < -0.05 and sim.tip_angle(-1) < -0.05,
		"sim/pose: a still book held face-up droops under real gravity")

	var face_down := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, 1.2, 0))
	var sim_down := _open_sim()
	for i in 500:
		sim_down.drive_from_pose(DT, face_down, true)
	_ok(sim_down.tip_angle(1) > 0.05, "sim/pose: the same book turned over hangs the other way")

	# Yanked upward at 2 g, the halves lag behind: more droop than gravity alone.
	var still := sim.tip_angle(1)
	var y := 1.2
	var v := 0.0
	var deepest := 0.0
	for i in 40:
		v += 2.0 * G * DT
		y += v * DT
		sim.drive_from_pose(DT, Transform3D(face_up.basis, Vector3(0, y, 0)), true)
		deepest = minf(deepest, sim.tip_angle(1))
	_ok(deepest < still - 0.05,
		"sim/pose: jerked upward, the halves lag behind the hand (%.3f -> %.3f)" % [still, deepest])

	# Put down: no drive at all, however it is lying, and it comes to rest.
	var ticks := 0
	while not sim.is_settled() and ticks < 900:
		sim.drive_from_pose(DT, face_up, false)
		ticks += 1
	_ok(sim.is_settled() and absf(sim.tip_angle(1)) < 0.01,
		"sim/put down, it relaxes flat and settles (%d ticks)" % ticks)


func _test_bend_geometry() -> void:
	var src := FileAccess.get_file_as_string("res://Shaders/paper_flop.gdshaderinc")
	var rx := RegEx.create_from_string("FLOP_HINGE_LEN\\s*=\\s*([0-9.]+)")
	var hit := rx.search(src)
	_ok(hit != null and is_equal_approx(float(hit.get_string(1)), BookFlop.HINGE_LEN),
		"bend/the shader's hinge length is the script's (the two halves of one bend)")

	var sim := _open_sim(3, 3)
	sim.set_support(true, Vector3(0.06, 0.0, 0.0))
	_run(sim, FACE_DOWN)
	var worst := 0.0
	for point: Vector3 in [Vector3(0.17, 0.05, 0.0), Vector3(-0.15, -0.1, 0.004),
			Vector3(0.09, 0.0, 0.03), Vector3(-0.004, 0.0, 0.0), Vector3(0.18, 0.12, -0.002)]:
		worst = maxf(worst, sim.unbend(sim.bend(point)).distance_to(point))
	_ok(worst < 1e-5, "bend/unbend(bend(p)) returns p (worst %.2f micrometres)" % (worst * 1e6))
	_ok(sim.bend(Vector3(0.17, 0, 0)).distance_to(Vector3(0.17, 0, 0)) > 0.01,
		"bend/...on a book that really is bent")

	# Paper does not stretch: walk the bent neutral line and measure it.
	var length := 0.0
	var prev := sim.bend(Vector3.ZERO)
	for i in range(1, 361):
		var here := sim.bend(Vector3(0.18 * i / 360.0, 0.0, 0.0))
		length += here.distance_to(prev)
		prev = here
	_ok(absf(length - 0.18) < 1e-4, "bend/the bent page is as long as the flat one (%.5f m)" % length)

	_ok(sim.bend(Vector3(0.05, 0, 0)).is_equal_approx(Vector3(0.05, 0, 0)),
		"bend/nothing moves between the gutter and the supporting hand")
	_test_leaf_crosses_the_gutter()
	# Right half hanging toward +Z turns NEGATIVELY about Y; the left, positively.
	_ok(sim.bend_rotation_y(Vector3(0.17, 0, 0)) < 0.0 and sim.bend_rotation_y(Vector3(-0.17, 0, 0)) > 0.0,
		"bend/a grab zone turns with its page, each half its own way")


## A page being turned is lifted over the spine, and a sheet LIFTED off a bend is
## on the outside of the curve: z above a radius R it would have to cover
## (R + z) / R times the paper it has. On a drooping book the flap was stretched
## into a flat tongue longer than the page, and the hand carrying it slid off the
## paper as it passed over. The leaf's map spreads the turn over an arc that
## widens with height. The first case is the control — it shows the defect is real.
func _test_leaf_crosses_the_gutter() -> void:
	var sim := _open_sim(7, 7)
	_run(sim, FACE_UP)
	var high := 0.05
	_ok(_worst_stretch(sim, high, false) > 2.5,
		"leaf/control: 5 cm over a drooping spine the halves' own bend stretches a sheet %.1fx"
			% _worst_stretch(sim, high, false))
	_ok(_worst_stretch(sim, high, true) < 1.4,
		"leaf/the turning leaf's map carries it over nearly unstretched (%.2fx)" % _worst_stretch(sim, high, true))
	_ok(_worst_stretch(sim, 0.10, true) < 1.4 and _worst_stretch(sim, 0.01, true) < 1.4,
		"leaf/...at any height a hand lifts it to")
	var seam := sim.bend_over(Vector3(1e-7, 0, high), 1).distance_to(sim.bend_over(Vector3(-1e-7, 0, high), 1))
	_ok(seam < 1e-6, "leaf/...with no seam where it passes from one half's bend to the other's")

	var worst := 0.0
	for point: Vector3 in [Vector3(0.10, 0.02, 0.06), Vector3(0.03, 0, 0.05), Vector3(0.0, 0, 0.08),
			Vector3(-0.04, -0.05, 0.05), Vector3(-0.13, 0, 0.02), Vector3(0.15, 0.1, 0.0)]:
		worst = maxf(worst, sim.unbend_over(sim.bend_over(point, 1), 1).distance_to(point))
		worst = maxf(worst, sim.unbend_over(sim.bend_over(point, -1), -1).distance_to(point))
	_ok(worst < 1e-5, "leaf/the turning hand is found on the flat page anywhere over the book (worst %.2f micrometres)" % (worst * 1e6))

	# On a LOPSIDED book, so the two halves really do bend differently: with
	# equal halves a flap given the wrong half's bend looks exactly right.
	var lopsided := _open_sim(2, 60)
	_run(lopsided, FACE_UP)
	var same := absf(lopsided.tip_angle(-1)) > absf(lopsided.tip_angle(1)) * 1.5
	for x: float in [0.17, 0.05, 0.004, -0.004, -0.09, -0.17]:
		for own: int in [1, -1]:
			same = same and lopsided.bend_over(Vector3(x, 0, 0), own).is_equal_approx(lopsided.bend(Vector3(x, 0, 0)))
	_ok(same, "leaf/ON the page the leaf lies on whichever half it is over — a landed page lies on ITS block")

	var src := FileAccess.get_file_as_string("res://Shaders/paper_flop.gdshaderinc")
	var hit := RegEx.create_from_string("FLOP_LIFT_SPREAD\\s*=\\s*([0-9.]+)").search(src)
	_ok(hit != null and is_equal_approx(float(hit.get_string(1)), BookFlop.LIFT_SPREAD),
		"leaf/the shader widens the arc by the script's factor")


## Walk a sheet across the spine at height z, a millimetre at a time, and report
## the most any one millimetre of it is stretched.
func _worst_stretch(sim: BookFlop, z: float, as_leaf: bool) -> float:
	var longest := 0.0
	var prev := Vector3.ZERO
	for i in 241:
		var flat := Vector3(0.12 - 0.001 * i, 0.0, z)
		var here := sim.bend_over(flat, 1) if as_leaf else sim.bend(flat)
		if i > 0:
			longest = maxf(longest, here.distance_to(prev))
		prev = here
	return longest / 0.001


# ── the turning leaf's pages ─────────────────────────────────────────────────

## Flipping quickly, the page just turned would flash up as the page beyond it,
## for a moment or until the turn finished (a Quest, 2026-09-20). _spawn_leaf()
## puts the page BEYOND on the block's top sheet under the leaf — but
## _refresh_visible_textures() re-applies the plain spread to that same sheet,
## and the spread's right page IS the page on the leaf. Anything that refreshed
## mid-turn put it back. _drain_uploads() refreshes every frame it lands a page,
## so a fast reader, outrunning the prefetch, hit it constantly.
func _test_turning_leaf_textures() -> void:
	_write_cbz(CBZ_PATH)
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = ProjectSettings.globalize_path(CBZ_PATH)
	add_child(book)
	await _settle()
	await _drain_renders(book)
	book.set_page(PDFBook.BookState.OPEN, 4)
	await _settle()
	await _drain_renders(book)

	for dir: int in [1, -1]:
		var plan := book._leaf_plan(dir)
		var under_page := int(plan["under_page"])
		var turning := int(plan["front"])
		var under := plan["under"] as MeshInstance3D
		_ok(book._spawn_leaf(dir), "leaf/a %s turn starts" % ("forward" if dir > 0 else "backward"))
		_ok(_mat(under).get_shader_parameter("front_texture") == book._texture_cache.get(under_page),
			"leaf/%+d: the block under a turning page shows the page beyond it" % dir)
		book._refresh_visible_textures()
		var shown: Variant = _mat(under).get_shader_parameter("front_texture")
		_ok(shown == book._texture_cache.get(under_page) and shown != book._texture_cache.get(turning),
			"leaf/%+d: ...and STILL does once a refresh lands mid-turn — not the page being turned (showing %d, want %d, turning %d)"
				% [dir, _page_of(book, shown), under_page, turning])
		book._despawn_active_leaf()
		book.set_page(PDFBook.BookState.OPEN, 4)
		await _settle()

	book.queue_free()
	await _settle()
	_remove_tree("user://pdf_cache/" + ProjectSettings.globalize_path(CBZ_PATH).md5_text())


## Turning the LAST page forward, or the FIRST page back, left a blank white
## sheet in the book for the length of the turn (a Quest, 2026-09-20). At either
## end the leaf being turned IS a cover, and nothing lies under a cover — but only
## the two turns that start from a shut book (open the cover, close the back) knew
## to lift the cover mesh and its one-leaf block with the leaf. The two that start
## from an open spread left both behind, and the block showed as a bare page.
##
## The oracle is the MIRROR: each end turn must leave exactly the surfaces its
## reverse turn does. That cannot pass by accident, and it names the stray.
func _test_end_leaves() -> void:
	_write_cbz(CBZ_PATH)
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = ProjectSettings.globalize_path(CBZ_PATH)
	add_child(book)
	await _settle()
	await _drain_renders(book)
	var last := book._leaf_count - 2
	var pairs := [
		["the last page, turned forward", PDFBook.BookState.OPEN, last, 1,
			"its reverse, closing from the back", PDFBook.BookState.LAST_PAGE, last + 1, -1],
		["the first page, turned back", PDFBook.BookState.OPEN, 0, -1,
			"its reverse, opening the cover", PDFBook.BookState.CLOSED, 0, 1],
	]
	for pair: Array in pairs:
		var got := await _visible_during(book, pair[1], pair[2], pair[3])
		var want := await _visible_during(book, pair[5], pair[6], pair[7])
		_ok(got == want, "ends/%s leaves the book as %s does (%s vs %s)"
				% [pair[0], pair[4], ", ".join(got), ", ".join(want)])
	book.set_page(PDFBook.BookState.OPEN, last)
	await _settle()
	book._spawn_leaf(1)
	_ok(not book._right_stack.visible and not book._back_cover_mesh.visible,
		"ends/the last leaf takes the back cover and its block with it, no bare sheet under it")
	book._despawn_active_leaf()
	book.set_page(PDFBook.BookState.OPEN, 0)
	await _settle()
	book._spawn_leaf(-1)
	_ok(not book._left_stack.visible and not book._cover_mesh.visible,
		"ends/...and the first, the front cover and its block")
	book._despawn_active_leaf()
	# An abandoned turn puts everything back.
	book.set_page(PDFBook.BookState.OPEN, 0)
	await _settle()
	_ok(book._left_stack.visible and book._cover_mesh.visible,
		"ends/a turn that is let go of puts the cover and block back")
	book.queue_free()
	await _settle()
	_remove_tree("user://pdf_cache/" + ProjectSettings.globalize_path(CBZ_PATH).md5_text())


## The names of the page surfaces showing while a turn is in progress.
func _visible_during(book: PDFBook, state: int, leaf: int, dir: int) -> PackedStringArray:
	book.set_page(state, leaf)
	await _settle()
	book._spawn_leaf(dir)
	var names: PackedStringArray = []
	for node: MeshInstance3D in [book._cover_mesh, book._back_cover_mesh, book._left_stack,
			book._right_stack, book._left_stack_top, book._right_stack_top]:
		if node.visible:
			names.append(node.name)
	book._despawn_active_leaf()
	return names


# ── book ──────────────────────────────────────────────────────────────────────

func _test_book() -> void:
	_write_cbz(CBZ_PATH)
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = ProjectSettings.globalize_path(CBZ_PATH)
	add_child(book)
	await _settle()
	await _drain_renders(book)

	_ok(book._page_count == PAGES, "book/loaded and laid out")
	_ok(not book.is_physics_processing(), "book/a book nobody is holding does not tick")
	_ok((book._right_stack.mesh as BoxMesh).subdivide_width > 0,
		"book/the block has columns to bend with (a box's corners cannot curve)")
	_ok(book._right_stack_top.custom_aabb.size.z >= book._book_width * 2.0,
		"book/culling bounds cover a half hanging straight down")

	# Where a hand takes hold. A shut book only exists right of the gutter.
	var shut_grip: Vector3 = book._grip_point(Vector3(-0.30, 0.0, 0.2))
	_ok(shut_grip.x >= 0.0 and shut_grip.z == 0.0,
		"book/shut: a hand reaching from the left takes it by the spine, not by thin air (x %.3f)" % shut_grip.x)

	# Shut, the block lies flat between its covers, so they are flat too.
	_ok(float(_mat(book._cover_mesh).get_shader_parameter("fore_droop")) == 0.0
			and float(_mat(book._right_stack).get_shader_parameter("fore_droop")) == 0.0,
		"book/shut: neither the block nor its covers droop at the fore edge")

	# Shut: one block, both covers, all on the right.
	_drive(book, FACE_UP)
	_ok(book._flop.params(1) != Vector4.ZERO, "book/shut, the block bends")
	_ok(_side_agrees(book, 1), "book/shut: cover, back cover and block carry ONE bend")

	book.turn_page_forward()
	book.turn_page_forward()
	await _settle()
	await _drain_renders(book)
	_ok(book._state == PDFBook.BookState.OPEN, "book/opened")
	# Seen from BEHIND, this was a white band down the fore edge of both covers:
	# the block takes the page's fore-edge droop, the covers were left flat a
	# millimetre under it, and the block's cream underside hung through them.
	var droops := true
	for pair: Array in [[book._cover_mesh, book._left_stack], [book._back_cover_mesh, book._right_stack]]:
		var cover_droop := float(_mat(pair[0]).get_shader_parameter("fore_droop"))
		var block_droop := float(_mat(pair[1]).get_shader_parameter("fore_droop"))
		droops = droops and block_droop > 0.0 and is_equal_approx(cover_droop, block_droop)
	_ok(droops, "book/open: each cover sags at the fore edge exactly as far as the block lying on it")
	# ...and a cover turned 180 about Y has to sag along the BOOK's Z, not its own,
	# or it sags up into its block instead: that sign is the one the bend uses.
	_ok(float(_mat(book._cover_mesh).get_shader_parameter("flop_z_sign")) == -1.0,
		"book/...downward, though the cover's own +Z points down out of the book")
	# The inside of a cover is printed. The sheet shader's back face otherwise
	# defaults to blank WHITE, which a rigid book always hid behind its block.
	# Against the CACHE, not _get_page_texture(): asking for a page a worker may
	# still be rendering races it (see the fan case below).
	var inside_front: Variant = _mat(book._cover_mesh).get_shader_parameter("back_texture")
	var inside_back: Variant = _mat(book._back_cover_mesh).get_shader_parameter("back_texture")
	_ok(inside_front != null and inside_front == book._texture_cache.get(1)
			and inside_back != null and inside_back == book._texture_cache.get(PAGES - 2),
		"book/a cover's inner face carries the page printed on it, never blank white")
	_drive(book, FACE_UP)
	_ok(book._flop.hinge(1) < -0.05 and book._flop.hinge(-1) < -0.05, "book/open, both halves hinge")
	_ok(_side_agrees(book, 1) and _side_agrees(book, -1),
		"book/open: every sheet and block on a side carries that side's bend")
	_ok(book._flop_sheets.size() == 4 and book._flop_blocks.size() == 2,
		"book/all six hanging surfaces are registered")
	_ok(_mat(book._cover_mesh).get_shader_parameter("flop_z_sign") == -1.0
			and _mat(book._right_stack_top).get_shader_parameter("flop_z_sign") == 1.0,
		"book/a cover turned 180 about Y bends toward the BOOK's +Z, not its own")
	_ok(is_equal_approx(float(_mat(book._right_stack_top).get_shader_parameter("flop_origin_z")),
			book._page_plane_z(1)),
		"book/a page on a Z-scaled block still knows its true height off the neutral plane")

	var zone := book.get_node("PageGrabRight") as PageGrab
	var flat := Vector3(PDFBook.SPINE_WIDTH * 0.5 + book._book_width * (1.0 - PDFBook.GRAB_BAND * 0.5),
		0.0, book._page_plane_z(1))
	_ok(zone.position.is_equal_approx(book._flop.bend(flat)) and zone.position.z < flat.z - 0.005,
		"book/the grab zone went down with the drooping page (z %.3f -> %.3f)" % [flat.z, zone.position.z])

	# Fan.
	_ok(book._fan_shown[1] == 0 and not _fan_leaf(book, 1, 0).visible,
		"book/face-up the fan is hidden")
	var plain_right: Texture2D = _mat(book._right_stack_top).get_shader_parameter("front_texture")
	_drive(book, FACE_DOWN)
	# Let any page the fan uncovered finish rendering and be adopted. Asking for
	# it sooner races the worker: its PNG can be on disk before the main thread
	# has taken the texture, and a second one is then loaded from the file.
	await _drain_renders(book)
	await _settle()
	var shown: int = book._fan_shown[1]
	_ok(shown > 0 and _fan_leaf(book, 1, 0).visible, "book/tipped over, leaves peel off (%d shown)" % shown)
	var right_page: int = (book._current_leaf + 1) * 2
	_ok(_mat(_fan_leaf(book, 1, 0)).get_shader_parameter("front_texture") == plain_right,
		"book/the top loose leaf carries the page that was on top")
	var under: Texture2D = _mat(book._right_stack_top).get_shader_parameter("front_texture")
	_ok(under == book._get_page_texture(right_page + 2 * shown),
		"book/...and the block shows the page under the last of them (page %d, showing %d)"
			% [right_page + 2 * shown, _page_of(book, under)])
	_ok(_mat(_fan_leaf(book, 1, 0)).get_shader_parameter("flop_own") == book._flop.fan_params(1, 0)
			and book._flop.fan_params(1, 0) != book._flop.params(1),
		"book/a loose leaf hangs by its own bend, not the block's")

	_ok(book._spawn_leaf(1), "book/a page can still be turned off a fanned side")
	_ok(book._fan_shown[1] == 0 and not _fan_leaf(book, 1, 0).visible,
		"book/...and taking it shuts that side's fan")
	_ok(_mat(book._active_leaf).get_shader_parameter("flop_own") == book._flop.params(1)
			and _mat(book._active_leaf).get_shader_parameter("flop_far") == book._flop.params(-1),
		"book/the turning leaf rides its own half, and the far half once it crosses")
	_ok(_mat(book._active_leaf).get_shader_parameter("flop_cross") == 1.0
			and not _mat(book._right_stack_top).get_shader_parameter("flop_cross"),
		"book/only the turning leaf blends across the gutter; a resting sheet must agree with its block")
	book._despawn_active_leaf()
	book._set_state(book._state)

	book.floppiness = 0.0
	_drive(book, FACE_DOWN)
	_ok(book._flop.params(1) == Vector4.ZERO and _mat(book._right_stack).get_shader_parameter("flop_own") == Vector4.ZERO,
		"book/floppiness 0 gives the shaders nothing to bend")
	book.floppiness = 0.7

	# Two hands, one on each end.
	_ok(book.second_hand_grab == XRToolsPickable.SecondHandGrab.SECOND,
		"book/a second hand may take hold of a held book")
	var edge := book._book_width + PDFBook.SPINE_WIDTH * 0.5
	var far_right: Vector3 = book._grip_point(Vector3(0.6, 0.0, 0.15))
	var far_left: Vector3 = book._grip_point(Vector3(-0.6, 0.9, -0.15))
	_ok(far_right.x > edge * 0.8 and far_right.x < edge and far_right.z == 0.0,
		"book/a hand out past the fore edge holds the END of the page (x %.3f of %.3f)" % [far_right.x, edge])
	_ok(far_left.x < -edge * 0.8 and far_left.x > -edge and far_left.y < book.book_height * 0.5,
		"book/...and the other hand the other end, on the paper")
	var on_page := Vector3(0.07, -0.04, 0.0)
	_ok(book._grip_point(on_page).is_equal_approx(on_page),
		"book/a hand already on the page holds it exactly where it closed")
	book._flop.set_support(true, far_right, far_left)
	_drive(book, FACE_UP)
	_ok(absf(book._flop.hinge(1)) < 0.01 and absf(book._flop.hinge(-1)) < 0.01,
		"book/held at both ends, the spread lies open and steady")
	_ok(book._flop.sag() < -0.001 and is_equal_approx(book._spine_node.position.z, book._spine_rest_z + book._flop.sag()),
		"book/...and sags in the middle, the rigid binding going down with the gutter (%.1f mm)"
			% (book._flop.sag() * 1000.0))
	_ok(_side_agrees(book, 1) and _side_agrees(book, -1)
			and (_mat(book._left_stack).get_shader_parameter("flop_own") as Vector4).w
				== (_mat(book._right_stack_top).get_shader_parameter("flop_own") as Vector4).w,
		"book/...with both halves handed the SAME gutter drop, or the spread tears at the binding")
	book._flop.set_support(false, Vector3.ZERO)

	# Hardback.
	_ok(not book.hardback, "book/hardback physics is OFF unless asked for")
	book.hardback = true
	_drive(book, FACE_UP)
	_ok(book._flop.hardback and (_mat(book._right_stack).get_shader_parameter("flop_own") as Vector4).y == 0.0
			and book._flop.hinge(1) > BookFlop.HARDBACK_ANGLE_MIN - BookFlop.HARD_STOP_MARGIN - 1e-6,
		"book/hardback: the boards reach the shaders unbent and barely past flat")
	var sp := ScenePersistence.new()
	var saved: Dictionary = sp._serialize_node(book, 1, {})
	_ok(saved.get("hardback") == true, "book/hardback is saved with the book")
	var back := sp._deserialize_object({"type": "book", "pdf_path": "", "hardback": true}) as PDFBook
	var plain := sp._deserialize_object({"type": "book", "pdf_path": ""}) as PDFBook
	_ok(back != null and back.hardback and plain != null and not plain.hardback,
		"book/...and restored; a room saved before the option existed gets soft covers")
	if back:
		back.free()
	if plain:
		plain.free()
	book.hardback = false

	_test_outline_bends(book)
	_test_page_bends(book)
	_test_pointer_drags_across_the_middle(book)
	await _test_page_follows_hand(book)
	_test_follow_across_spine(book)

	# Shut again AFTER having been open: the covers must give the droop back. (Checked
	# only on a freshly loaded book, this passed with the reset deleted — nothing had
	# ever set the droop it was supposed to clear.)
	book.set_page(PDFBook.BookState.CLOSED, 0)
	_ok(float(_mat(book._cover_mesh).get_shader_parameter("fore_droop")) == 0.0
			and float(_mat(book._back_cover_mesh).get_shader_parameter("fore_droop")) == 0.0,
		"book/shut again, the covers lie flat on a block that no longer droops")
	book.set_page(PDFBook.BookState.OPEN, 1)

	# Armed by a pickup; with nobody actually holding it, it relaxes and disarms.
	_drive(book, FACE_UP)
	book.picked_up.emit(book)
	_ok(book.is_physics_processing(), "book/picking it up arms the tick")
	for i in 240:
		if not book.is_physics_processing():
			break
		await get_tree().physics_frame
	_ok(not book.is_physics_processing(), "book/put down, it settles and stops ticking")
	_ok(_mat(book._right_stack_top).get_shader_parameter("flop_own") == Vector4.ZERO
			and _mat(book._left_stack).get_shader_parameter("flop_own") == Vector4.ZERO,
		"book/...lying EXACTLY flat, on the shaders' no-bend path")
	_ok(zone.position.is_equal_approx(flat), "book/...with its grab zone back on the flat page")
	# Approximately: a node's position is 32-bit and the rest height is not.
	_ok(is_equal_approx(book._spine_node.position.z, book._spine_rest_z) and book._flop.sag() == 0.0,
		"book/...and its binding back where the layout put it")

	var cache_dir: String = book._cache_dir
	book.queue_free()
	await _settle()
	_remove_tree(cache_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CBZ_PATH))


## Held up and carried past the spine, a page stopped following the hand (a
## Quest, 2026-09-20). The lift was handed over to the roll by the hand's
## BEARING alone, so a page merely leaning past upright went limp: the roll laid
## it flat on the far half and the grip trailed the hand by up to 22 cm, well
## inside the paper's reach. Landing is about the hand coming DOWN.
##
## The oracle is SYMMETRY. Paper has a real reach, and a hand out past the fore
## edge is left a real gap — but the same gap on both halves. So the far half may
## be no worse than the near one, at every height a page is held at.
func _test_follow_across_spine(book: PDFBook) -> void:
	_drive(book, FACE_UP)
	var w := book._book_width
	var plane := book._page_plane_z(1)
	for height: float in [0.05, 0.10]:
		book._despawn_active_leaf()
		book._on_page_grab_begin(1, _hand_at(book, Vector3(w * 0.85, -0.02, plane + 0.004)))
		var near := 0.0
		var far := 0.0
		var far_at := 0.0
		for i in 35:
			var along := lerpf(0.85, -0.85, float(i) / 34.0)
			var hand := _hand_at(book, Vector3(w * along, -0.02, plane + height))
			book._update_fold_from_hand(hand)
			var err := _grip_world(book).distance_to(hand)
			if along > 0.0:
				near = maxf(near, err)
			elif err > far:
				far = err
				far_at = along
		_ok(far <= near + 0.002,
			"spine/held %d cm up, the far half follows the hand as well as the near one (worst %.0f mm at %.2f, near half %.0f mm)"
				% [int(height * 100.0), far * 1000.0, far_at, near * 1000.0])
	# The hand-over is a band of HEIGHT, so crossing it is where a page could leap:
	# bring a hand straight down onto the far page and watch a point on the paper,
	# as the spine sweep does. This is the side of the trade the old design won
	# (1.4 mm; this is ~5 mm, a quick settle as it lands, measured in
	# _solve_leaf_lift) — the bound is there so it cannot quietly get worse.
	book._despawn_active_leaf()
	book._on_page_grab_begin(1, _hand_at(book, Vector3(w * 0.85, -0.02, plane + 0.004)))
	book._update_fold_from_hand(_hand_at(book, Vector3(w * -0.5, -0.02, plane + 0.10)))
	var mid := Vector2(book._grab_anchor.x * 0.5 - w * 0.25, -0.02)
	var worst_step := 0.0
	var worst_up := 0.0
	var last_mid := Vector3.INF
	for i in 201:
		var up := lerpf(0.10, 0.001, float(i) / 200.0)
		book._update_fold_from_hand(_hand_at(book, Vector3(w * -0.5, -0.02, plane + up)))
		var here := _leaf_point_world(book, mid)
		if last_mid.is_finite() and here.distance_to(last_mid) > worst_step:
			worst_step = here.distance_to(last_mid)
			worst_up = up
		last_mid = here
	_ok(worst_step < 0.006,
		"spine/brought straight down onto the far page it lands without a leap (mid-page moved at most %.1f mm per 0.5 mm of hand, %.0f mm up)"
			% [worst_step * 1000.0, worst_up * 1000.0])
	_ok(book._leaf_lift < 0.02, "spine/...and once down, the roll has it (%.1f deg of lift left)" % rad_to_deg(book._leaf_lift))
	book._despawn_active_leaf()


## Does the page being turned follow the hand? The fold rolls a page over FLAT and
## on its own cannot lift one: a hand pulling a page up or out used to leave the
## paper lying on the book 10-35 cm away. The leaf now swings up about the gutter
## by just enough for the fold to reach — and paper cannot stretch, so a hand
## beyond its reach gets a taut page POINTING at it, not a page that reaches it.
## On a hanging book, where every one of these goes through the bend.
func _test_page_follows_hand(book: PDFBook) -> void:
	_drive(book, FACE_UP)
	var w := book._book_width
	var plane := book._page_plane_z(1)
	var start := Vector3(w * 0.85, -0.02, plane + 0.004)
	book._despawn_active_leaf()
	book._on_page_grab_begin(1, _hand_at(book, start))
	_ok(book._active_leaf != null and book._leaf_lift == 0.0, "follow/a page taken by its edge starts lying down")

	# Low over the page, toward the spine: everything the fold already did.
	var over := _hand_at(book, Vector3(w * 0.25, -0.02, plane + 0.07))
	book._update_fold_from_hand(over)
	_ok(book._leaf_lift == 0.0, "follow/pulled OVER, low: no lift — the roll-over is untouched")
	_ok(_grip_world(book).distance_to(over) < 0.004,
		"follow/...and the gripped spot is under the hand (%.1f mm)" % (_grip_world(book).distance_to(over) * 1000.0))

	# Straight up, higher than the fold alone can carry paper, still within reach.
	var up := _hand_at(book, Vector3(w * 0.45, -0.02, plane + 0.115))
	book._update_fold_from_hand(up)
	# Part hinge, part bow: the lift only has to be enough for the curl to start at
	# the binding instead of behind it, and the arc carries the rest. (As a stiff
	# board it needed 83 degrees, and looked like one.)
	_ok(book._leaf_lift > 0.2 and book._leaf_lift < 1.0,
		"follow/pulled UP, the page swings up on its hinge and bows the rest (%.0f deg)" % rad_to_deg(book._leaf_lift))
	# Null-safe on purpose: float(null) is a script ERROR, which aborts the rest of
	# this function and lets the suite finish green on fewer cases.
	var told: Variant = _mat(book._active_leaf).get_shader_parameter("flop_lift")
	_ok(told != null and is_equal_approx(float(told), book._leaf_lift),
		"follow/...and the shader drawing it is told so")
	_ok(_grip_world(book).distance_to(up) < 0.004,
		"follow/...to the hand (%.1f mm; it lay 10 cm below before)" % (_grip_world(book).distance_to(up) * 1000.0))

	# Out of reach: 29 cm from the gutter, on 15 cm of paper.
	var away := _hand_at(book, Vector3(w * 0.70, -0.02, plane + 0.26))
	book._update_fold_from_hand(away)
	var gutter := book.to_global(book._flop.bend_over(Vector3(0.0, 0.0, plane), 1))
	var to_paper := _grip_world(book) - gutter
	var to_hand := away - gutter
	var reach := book._grab_anchor.x + w * 0.5 + PDFBook.SPINE_WIDTH * 0.5
	_ok(rad_to_deg(to_paper.angle_to(to_hand)) < 6.0,
		"follow/pulled AWAY out of reach, the page goes taut and points at the hand (%.1f deg off)"
			% rad_to_deg(to_paper.angle_to(to_hand)))
	_ok(absf(to_paper.length() - reach) < 0.012 and to_hand.length() > reach + 0.1,
		"follow/...without stretching: the paper is still %.0f mm long, the hand %.0f mm off"
			% [to_paper.length() * 1000.0, to_hand.length() * 1000.0])
	_ok(book._turn_progress() < PDFBook.TURN_COMMIT,
		"follow/...and a page held up at %.0f degrees is not yet turned (%.2f)"
			% [rad_to_deg(book._leaf_lift), book._turn_progress()])
	# The same pull carried on over the spine: past upright, it is.
	book._update_fold_from_hand(_hand_at(book, Vector3(w * -0.30, -0.02, plane + 0.26)))
	_ok(book._leaf_lift > PI * 0.5 and book._turn_progress() >= PDFBook.TURN_COMMIT,
		"follow/swung past upright (%.0f deg), it counts as turned (%.2f)"
			% [rad_to_deg(book._leaf_lift), book._turn_progress()])

	# Out past the fore edge, low: nothing to fold, but the page still reaches for it.
	var out := _hand_at(book, Vector3(w * 1.25, -0.02, plane + 0.05))
	book._update_fold_from_hand(out)
	to_paper = _grip_world(book) - gutter
	_ok(book._leaf_lift > 0.1 and rad_to_deg(to_paper.angle_to(out - gutter)) < 6.0,
		"follow/pulled OUT past the fore edge, it lifts toward the hand instead of lying flat")

	# Coming down onto the far half, the leaf must NOT still be up on its hinge: a
	# lifted leaf turns about its own half and can never lie on the other. The
	# rolled-over sheet takes over, smoothly in the hand's bearing.
	# Brought DOWN onto the far page: that is landing, and the roll takes it. (A hand
	# 3 cm up used to count: that is still holding the page, which now follows it.)
	book._update_fold_from_hand(_hand_at(book, Vector3(w * -0.60, -0.02, plane + 0.002)))
	_ok(book._leaf_lift < 0.02, "follow/landing on the far half, the lift has handed over to the roll (%.1f deg)"
		% rad_to_deg(book._leaf_lift))
	# ...and it got there without a jump: sweep the hand over the spine and watch.
	# Judged by the PAPER, not by the lift angle: where the hand's distance from the
	# gutter equals the paper's length, a fraction of a millimetre of slack turns
	# the sheet's tangent at the binding by degrees while its shape barely changes
	# — that is an inextensible sheet, not a fault. What a player would see is a
	# point on the page leaping, so follow one: half way out from the gutter.
	var mid := Vector2(book._grab_anchor.x * 0.5 - w * 0.25, -0.02)
	var worst_step := 0.0
	var worst_at := 0.0
	var last_mid := Vector3.INF
	for i in 301:
		var along := lerpf(0.8, -0.7, float(i) / 300.0)
		book._update_fold_from_hand(_hand_at(book, Vector3(w * along, -0.02, plane + 0.10)))
		var here := _leaf_point_world(book, mid)
		if last_mid.is_finite() and here.distance_to(last_mid) > worst_step:
			worst_step = here.distance_to(last_mid)
			worst_at = along
		last_mid = here
	_ok(worst_step < 0.006,
		"follow/carried right over the spine 10 cm up, the paper never leaps (mid-page moved at most %.1f mm per 0.9 mm of hand, at %.2f of a page)"
			% [worst_step * 1000.0, worst_at])

	# Brought back down and let go: the lift must not be left standing.
	book._update_fold_from_hand(_hand_at(book, start))
	book._on_page_grab_end(1)
	await get_tree().create_timer(0.6).timeout
	_ok(book._active_leaf == null and book._leaf_lift == 0.0 and book._current_leaf == 1,
		"follow/let go where it started, the page lies back down and nothing turned")


## Dragging a page with the desktop reticle (or the VR laser): it stood still all
## the way across the middle of the book. A latched page moved on the pointer's
## MOVED events, and a pointer only reports a position while its ray is on
## something that takes pointer events — which the inner third of each page, left
## to the book's pick-up body so the laser can still lift the book, is not. So:
## a pointer that sends NOTHING after the press, swept across the book.
func _test_pointer_drags_across_the_middle(book: PDFBook) -> void:
	_drive(book, FACE_UP)
	var w := book._book_width
	var plane := book._page_plane_z(1)
	var zone := book.get_node("PageGrabRight") as PageGrab
	var pointer := Node3D.new()
	var ray := RayCast3D.new()
	ray.name = "RayCast"
	ray.enabled = false
	ray.target_position = Vector3(0.0, 0.0, -10.0)
	pointer.add_child(ray)
	add_child(pointer)
	# Half a metre over the book, looking straight down at it.
	var aim := func(x: float) -> void:
		pointer.global_transform = Transform3D(book.global_basis, book.to_global(Vector3(x, -0.02, 0.5)))
	aim.call(w * 0.85)
	var grip := _hand_at(book, Vector3(w * 0.85, -0.02, plane))
	book._despawn_active_leaf()
	zone.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, pointer, zone, grip, grip))
	_ok(book._grab_dir == 1 and zone.is_held(), "pointer/pressing on the page latches it")

	var travel: Array[float] = []
	for along: float in [0.6, 0.35, 0.1, 0.0, -0.1, -0.35, -0.6]:
		aim.call(w * along)
		zone._process(1.0 / 60.0)      # the pointer itself says nothing at all
		travel.append(book._grip_travel)
	var rising := true
	for i in range(1, travel.size()):
		rising = rising and travel[i] > travel[i - 1] + 0.01
	_ok(rising, "pointer/swept across the book with no events, the page follows the RAY all the way (%s)"
		% ", ".join(travel.map(func(t: float) -> String: return "%.2f" % t)))
	_ok(absf(travel[3] - 0.5) < 0.08,
		"pointer/...and it is half turned when the ray is over the gutter (%.2f)" % travel[3])
	_ok(book._active_leaf != null and float(_mat(book._active_leaf).get_shader_parameter("fold_strength")) > 0.0,
		"pointer/...curled, not lying flat")

	# Carried back to where it started and let go: nothing turns.
	aim.call(w * 0.85)
	zone._process(1.0 / 60.0)
	zone.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, pointer, zone, grip, grip))
	_ok(not zone.is_held(), "pointer/releasing lets go")
	book._despawn_active_leaf()
	book._set_state(book._state)
	pointer.queue_free()


## The four outline shaders have a history of taking a Quest's GPU down when their
## shape changes, so the book does not touch them: it gets COPIES with the bend
## spliced in between two marker lines (Tools/gen_bent_outline_shaders.py). A copy
## of a fragile file drifts. Strip the marked lines back out of each copy and it
## must be its original, to the character.
func _test_bent_outline_shaders() -> void:
	const BEGIN := "// --- bent (Tools/gen_bent_outline_shaders.py) ---"
	const END := "// --- end bent ---"
	for name: String in ["outline", "outline_mask", "outline_hull", "outline_hull_primer"]:
		var original := FileAccess.get_file_as_string("res://Shaders/%s.gdshader" % name).replace("\r\n", "\n")
		var copy := FileAccess.get_file_as_string("res://Shaders/%s_bent.gdshader" % name).replace("\r\n", "\n")
		var kept: PackedStringArray = []
		var inside := false
		var blocks := 0
		for line: String in copy.split("\n").slice(5):     # the 5-line GENERATED header
			if line.strip_edges() == BEGIN:
				inside = true
				blocks += 1
			elif line.strip_edges() == END:
				inside = false
			elif not inside:
				kept.append(line)
		_ok(blocks >= 1 and copy.contains("outline_flop(bent_vertex, bent_normal)"),
			"outline/%s_bent really does run the bend" % name)
		_ok("\n".join(kept) == original,
			"outline/%s_bent is its original with nothing but the bend added (regenerate: Tools/gen_bent_outline_shaders.py)" % name)


## The pick-up outline is drawn from flat COPIES of the covers and blocks, and the
## bend exists only in the page shaders: the outline stayed where the flat book
## would be, an empty rectangle floating in the air, while the book drooped away
## under it. Each overlay must carry the bend its own source hangs by.
func _test_outline_bends(book: PDFBook) -> void:
	var highlight := book.get_node("PickableHighlight") as PickableHighlight
	_ok(highlight.bends_with_parent and highlight._outline_material.shader != PickableHighlight.OUTLINE_SHADER
			and highlight._outline_material.shader != PickableHighlight.OUTLINE_HULL_SHADER,
		"outline/a book's highlight draws with the bend-aware shaders")
	_drive(book, FACE_UP)
	var agrees := true
	var seen := 0
	for pair: Array in [[book._left_stack, -1], [book._right_stack, 1], [book._cover_mesh, -1], [book._back_cover_mesh, 1]]:
		var overlay := highlight.overlay_of(pair[0])
		if overlay == null:
			continue
		seen += 1
		agrees = agrees and overlay.get_instance_shader_parameter("flop_own") == book._flop.params(int(pair[1]))
	_ok(seen == 4 and agrees and book._flop.params(1) != Vector4.ZERO,
		"outline/each cover's and block's outline hangs by its own side's bend")
	var cover_frame: Vector4 = highlight.overlay_of(book._cover_mesh).get_instance_shader_parameter("flop_frame")
	var block_frame: Vector4 = highlight.overlay_of(book._right_stack).get_instance_shader_parameter("flop_frame")
	_ok(cover_frame.y == -1.0 and is_equal_approx(cover_frame.x, book._cover_mesh.position.z)
			and block_frame.y == 1.0 and is_equal_approx(block_frame.w, book._right_stack.scale.z),
		"outline/...told where its mesh sits: a cover turned over, a block scaled on Z")
	# Never given one: null, or the shader's all-zero default, which is "no bend".
	var spine_bend: Variant = null
	if highlight.overlay_of(book._spine_mesh) != null:
		spine_bend = highlight.overlay_of(book._spine_mesh).get_instance_shader_parameter("flop_own")
	_ok(highlight.overlay_of(book._right_stack_top) == null and highlight.overlay_of(book._spine_mesh) != null
			and (spine_bend == null or spine_bend == Vector4.ZERO),
		"outline/the rigid binding's outline is given no bend (and the page sheets have no outline)")
	# Overlays are rebuilt from scratch when the meshes change. A rebuilt one must
	# not come back flat.
	highlight.rebuild_overlays()
	_ok(highlight.overlay_of(book._right_stack).get_instance_shader_parameter("flop_own") == book._flop.params(1),
		"outline/rebuilt overlays keep the bend they were given")


## The shape a turning page takes. It used to be an origami fold — a 3 mm crease
## that flipped a sliver of page over the moment it was gripped — and looked like
## it was snapping into a fold, because it was.
func _test_page_bends(book: PDFBook) -> void:
	# Gripped and barely moved, lifted 2 cm: a broad shallow curve, not a crease.
	var small: Vector2 = book._fold_shape(0.005, 0.02)
	_ok(small.x > 0.03, "bend/a small pull is a broad curve (radius %.0f mm; the crease was 3)" % (small.x * 1000.0))
	# On the curve, the grip is where the cycloid says: across = r(p - sin p), up = r(1 - cos p).
	var curl: Vector2 = book._fold_shape(0.05, 0.06)
	var phi := curl.y / curl.x
	_ok(phi < PI and absf(curl.x * (phi - sin(phi)) - 0.05) < 1e-4 and absf(curl.x * (1.0 - cos(phi)) - 0.06) < 1e-4,
		"bend/the curl carries the grip exactly across and up (wrapped %.0f deg of a %.0f mm radius)"
			% [rad_to_deg(phi), curl.x * 1000.0])
	# A hand low over the page still gets the rolled-over flap, 2r up.
	var low: Vector2 = book._fold_shape(0.12, 0.03)
	_ok(is_equal_approx(low.x, 0.015) and is_equal_approx(low.y, (0.12 + PI * 0.015) * 0.5),
		"bend/a hand low over the page still rolls it right over")
	# A hand skimming 2 mm over the page would ask for a 1 mm crease. Paper does not
	# crease by being pulled: the curl stops at CURL_MIN and the grip rides a little
	# above the hand instead.
	var skim: Vector2 = book._fold_shape(0.12, 0.002)
	_ok(is_equal_approx(skim.x, PDFBook.CURL_MIN) and PDFBook.CURL_MIN >= 0.008,
		"bend/a hand skimming the page cannot crease it (radius held at %.0f mm, not 1)" % (skim.x * 1000.0))
	# And the two meet with no seam, which is the whole point.
	var seam := 0.10 * 2.0 / PI
	var below: Vector2 = book._fold_shape(0.10, seam - 1e-6)
	var above: Vector2 = book._fold_shape(0.10, seam + 1e-6)
	_ok(below.distance_to(above) < 1e-4, "bend/the curl becomes the roll with no seam between them")
	# Sweep a hand up from the page: the radius must never jump.
	var worst := 0.0
	var last: Vector2 = book._fold_shape(0.06, 0.0005)
	for i in range(1, 300):
		var here: Vector2 = book._fold_shape(0.06, 0.0005 * (i + 1))
		worst = maxf(worst, absf(here.y - last.y))
		last = here
	_ok(worst < 0.004, "bend/lifting the hand half a millimetre never moves the curl line more than 4 (%.2f mm)" % (worst * 1000.0))


## Where a hand at `flat` (a point written on the flat book) is in the world,
## over a book that is hanging.
func _hand_at(book: PDFBook, flat: Vector3) -> Vector3:
	return book.to_global(book._flop.bend_over(flat, 1))


## Where the gripped spot of the turning leaf is in the world.
## How far any part of the turning leaf has gone THROUGH the far half's block, in
## metres (positive = through it, negative = floating clear). The leaf is sampled
## on a grid; the strip by the gutter is skipped, where the pages dive into the
## valley on purpose.
func _through_far(book: PDFBook) -> float:
	var w := book._book_width
	var h := book.book_height
	var far_plane := book._page_plane_z(-book._grab_dir)
	var worst := -INF
	for ix in 11:
		for iy in 5:
			var p := Vector2(lerpf(-0.5, 0.5, float(ix) / 10.0) * w, lerpf(-0.45, 0.45, float(iy) / 4.0) * h)
			var flat := book._flop.unbend_over(book.to_local(_leaf_point_world(book, p)), book._turn_direction)
			if float(book._grab_dir) * flat.x < -0.15 * w:
				worst = maxf(worst, far_plane - flat.z)
	return worst


func _grip_world(book: PDFBook) -> Vector3:
	return _leaf_point_world(book, book._grab_anchor)


## Where a point of the turning leaf (leaf-local metres on the flat sheet) is in
## the world: the fold wrap of paper.gdshader replayed on the CPU for that one
## point, then the leaf's own hinge, then the book's bend.
func _leaf_point_world(book: PDFBook, point: Vector2) -> Vector3:
	var leaf := book._active_leaf
	var mat := _mat(leaf)
	var xy := point
	var z := 0.0
	if float(mat.get_shader_parameter("fold_strength")) > 0.0:
		var fn: Vector2 = (mat.get_shader_parameter("fold_normal") as Vector2).normalized()
		var d := (point - (mat.get_shader_parameter("fold_origin") as Vector2)).dot(fn)
		if d > 0.0:
			var u := clampf(0.5 + float(book._grab_dir) * point.x / book._book_width, 0.0, 1.0)
			var r := maxf(float(mat.get_shader_parameter("curl_radius"))
				* (1.0 + float(mat.get_shader_parameter("curl_taper")) * (1.0 - u)), 1e-4)
			var fold_pt := point - fn * d
			if d / r < PI:
				xy = fold_pt + fn * (r * sin(d / r))
				z = r * (1.0 - cos(d / r))
			else:
				xy = fold_pt - fn * (d - PI * r)
				z = 2.0 * r
	return book.to_global(book._flop.bend_over(
		leaf.position + Vector3(xy.x, xy.y, z), book._turn_direction, book._leaf_lift, leaf.position.z))


## A book with a LOT of pages: 400, a 2 cm block, opened in the middle. Everything
## else in this suite is a 24-page booklet 1.2 mm thick, where a surface's height
## off the neutral plane is nothing; here the top page and the cover sit a
## centimetre either side of it, and the bend is written ABOUT that plane.
func _test_thick_book() -> void:
	_write_cbz(THICK_CBZ_PATH, THICK_PAGES)
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = ProjectSettings.globalize_path(THICK_CBZ_PATH)
	add_child(book)
	await _settle()
	@warning_ignore("integer_division")
	var middle := THICK_PAGES / 4 - 1
	book.set_page(PDFBook.BookState.OPEN, middle)
	await _settle()
	await _drain_renders(book)
	_ok(book._page_count == THICK_PAGES and book._current_leaf == middle and book._state == PDFBook.BookState.OPEN,
		"thick/400 pages loaded and opened in the middle (leaf %d of %d)" % [book._current_leaf, book._leaf_count])
	var half_block := book._side_thickness(1) * 0.5
	_ok(half_block > 0.004, "thick/the block really is thick: %.1f mm either side of the neutral plane" % (half_block * 1000.0))

	_drive(book, FACE_UP)
	var thin := _open_sim(7, 7)
	_run(thin, FACE_UP)
	_ok(book._flop.tip_angle(1) < -0.005 and absf(book._flop.tip_angle(1)) < absf(thin.tip_angle(1)) * 0.5,
		"thick/it still droops, far less than a booklet (%.1f deg against %.1f)"
			% [rad_to_deg(book._flop.tip_angle(1)), rad_to_deg(thin.tip_angle(1))])
	_ok(_side_agrees(book, 1) and _side_agrees(book, -1), "thick/every surface on a side still carries one bend")

	# THE invariant for a thick book. The binding turns over an arc HINGE_LEN long;
	# a surface z off the neutral plane, on the inside of that turn, is on a radius
	# (R - z). If the block's half-thickness (plus its cover) reached R, the inside
	# of the block would fold through itself. Under the worst a hand can do.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7B1C
	var reach := half_block + PDFBook.COVER_GAP + PDFBook.ZFIGHT_MARGIN
	var tightest := INF
	for i in 2500:
		var a := Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		book._flop.step(DT * rng.randf_range(0.5, 2.0), a, a)
		for dir: int in [-1, 1]:
			var turn := absf(book._flop.params(dir).x)
			if turn > 1e-6:
				tightest = minf(tightest, BookFlop.HINGE_LEN / turn)
	_ok(tightest > reach * 1.5,
		"thick/shaken violently, the binding never turns tighter than the block is thick (radius %.1f mm, block + cover %.1f)"
			% [tightest * 1000.0, reach * 1000.0])

	# Tipped over: the fan takes pages from the MIDDLE of the book, all in range.
	book._flop.reset()
	_drive(book, FACE_DOWN)
	await _drain_renders(book)
	await _settle()
	var right_page: int = (book._current_leaf + 1) * 2
	var shown: int = book._fan_shown[1]
	_ok(shown > 0 and right_page + 2 * shown < THICK_PAGES,
		"thick/tipped over, %d leaves fan from the middle of the book" % shown)
	_ok(_page_of(book, _mat(_fan_leaf(book, 1, 0)).get_shader_parameter("front_texture")) == right_page
			and _page_of(book, _mat(book._right_stack_top).get_shader_parameter("front_texture")) == right_page + 2 * shown,
		"thick/...the top loose leaf is page %d and the block shows page %d" % [right_page, right_page + 2 * shown])
	_ok(_page_of(book, _mat(_fan_leaf(book, -1, 0)).get_shader_parameter("front_texture")) == book._current_leaf * 2 + 1,
		"thick/...and on the left the top loose leaf is page %d" % (book._current_leaf * 2 + 1))

	# A page turned on it: the leaf hinges about the gutter at ITS OWN height, a
	# centimetre up, and the grip still lands on the hand.
	book._flop.reset()
	_drive(book, FACE_UP)
	var w := book._book_width
	var plane := book._page_plane_z(1)
	_ok(plane > 0.004, "thick/the page being turned starts %.1f mm above the neutral plane" % (plane * 1000.0))
	book._despawn_active_leaf()
	book._on_page_grab_begin(1, _hand_at(book, Vector3(w * 0.85, -0.02, plane + 0.004)))
	var over := _hand_at(book, Vector3(w * 0.25, -0.02, plane + 0.07))
	book._update_fold_from_hand(over)
	# To a millimetre, not four: hinging the leaf about the neutral plane instead of
	# its own height, 5 mm up, only moves the grip ~3 mm.
	_ok(_grip_world(book).distance_to(over) < 0.001,
		"thick/pulled over, the gripped spot is under the hand (%.1f mm)" % (_grip_world(book).distance_to(over) * 1000.0))

	var up := _hand_at(book, Vector3(w * 0.45, -0.02, plane + 0.115))
	book._update_fold_from_hand(up)
	_ok(_grip_world(book).distance_to(up) < 0.001,
		"thick/pulled up, the page swings up to the hand (%.1f mm)" % (_grip_world(book).distance_to(up) * 1000.0))
	book._despawn_active_leaf()
	book._set_state(book._state)

	# Set DOWN on the far half, at both ends of a thick book, where the two blocks'
	# tops are furthest apart. This is what the lift's hand-over to the roll is for:
	# without one, a lifted and bowed page sank 30-34 mm THROUGH the far block.
	var pierce := -INF
	var pierce_at := ""
	for at: int in [2, book._leaf_count - 4]:
		for dir: int in [1, -1]:
			book._despawn_active_leaf()
			book.set_page(PDFBook.BookState.OPEN, at)
			await _settle()
			var pw := book._book_width
			book._on_page_grab_begin(dir, _hand_at(book, Vector3(dir * pw * 0.85, -0.02, book._page_plane_z(dir) + 0.004)))
			var far_plane := book._page_plane_z(-dir)
			for height: float in [0.10, 0.05, 0.035, 0.02, 0.005, 0.001]:
				book._update_fold_from_hand(_hand_at(book, Vector3(-dir * pw * 0.6, -0.02, far_plane + height)))
				var through := _through_far(book)
				if through > pierce:
					pierce = through
					pierce_at = "leaf %d, dir %+d, %d mm up" % [at, dir, int(height * 1000.0)]
	# Not zero. Half-way through the hand-over (~35 mm up), at the FRONT of a thick
	# book, the leaf dips 2.7 mm into the far block: it swings about the gutter at
	# its own THIN side's height and bows down short of a block 10 mm higher. The
	# old bearing-only hand-over, landing by the roll, stayed 7.6 mm clear — this
	# is part of what following a held page costs (see _solve_leaf_lift). The
	# bound is pinned just over it so it cannot quietly grow; the 30-34 mm of a
	# page with no hand-over at all is what it really guards.
	_ok(pierce < 0.003,
		"thick/a page set down on the far half never goes more than a paper-width into its block (deepest %+.1f mm, %s)"
			% [pierce * 1000.0, pierce_at])
	book._despawn_active_leaf()
	book._set_state(book._state)

	var cache_dir: String = book._cache_dir
	book.queue_free()
	await _settle()
	_remove_tree(cache_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(THICK_CBZ_PATH))


## Step the book's own sim as if it were held, then hand the result to the
## shaders. The suite's book is frozen and nobody holds it, so the tick is off —
## which is the point: this drives the same code the tick would.
func _drive(book: PDFBook, accel: Vector3, ticks: int = 500) -> void:
	for i in ticks:
		book._flop.step(DT, accel, accel)
	book._push_flop(false)


## Does every registered surface on this side carry exactly this side's bend?
func _side_agrees(book: PDFBook, dir: int) -> bool:
	var want := book._flop.params(dir)
	var seen := 0
	for entry: Array in book._flop_sheets + book._flop_blocks:
		if int(entry[1]) != dir:
			continue
		seen += 1
		if (entry[0] as ShaderMaterial).get_shader_parameter("flop_own") != want:
			return false
	return seen > 0 and want != Vector4.ZERO


## Which page a texture is, or -1 (the loading placeholder, or evicted).
func _page_of(book: PDFBook, tex: Texture2D) -> int:
	for page: int in book._texture_cache:
		if book._texture_cache[page] == tex:
			return page
	return -1


func _mat(node: MeshInstance3D) -> ShaderMaterial:
	return node.get_surface_override_material(0) as ShaderMaterial


func _fan_leaf(book: PDFBook, dir: int, k: int) -> MeshInstance3D:
	var side: Array = book._fan_leaves[1 if dir > 0 else 0]
	return side[k] as MeshInstance3D


# ── helpers ───────────────────────────────────────────────────────────────────

func _ok(cond: bool, label: String) -> void:
	_ran += 1
	if cond:
		print("[test] ok   %s" % label)
	else:
		_failed += 1
		print("[test] FAIL %s" % label)


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame


func _drain_renders(book: PDFBook) -> void:
	for i in 600:
		if book._pending_renders.is_empty():
			return
		await get_tree().process_frame


func _write_cbz(path: String, pages: int = PAGES) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in pages:
		var img := Image.create(20, 28, false, Image.FORMAT_RGB8)
		img.fill(Color.from_hsv(float(i) / pages, 0.6, 0.8))
		zip.start_file("page_%04d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
