## Does a cord JITTER where it bends over a corner, or wound up on itself, while
## it is awake and being handled?
##
##   "$godot" --headless --path RetroXR res://Tools/rope/rope_jitter_probe.tscn -- --case=edge
##   cases: edge      over a table's edge to a floor socket; the table end is pulled
##                    back and forth ACROSS the edge, the floor end slid ALONG it
##          corner    the same over a box's VERTEX (two edges meeting)
##          wrap      two turns round a square horizontal bar, one end slackened and hauled
##          wrappipe  the same round a round bar (the control for `wrap`: no edges)
##          heap      2 m dropped in a pile, then one mount moved
##          wound     a hand-wound coil of 3.5 turns lying on the floor, one end moved
##          loop      an alpha loop on the floor: the cord lying across itself ONCE
##   ... -- --seeds=N every case N times over, each from a slightly different
##                    start, and a SUMMARY line of medians. A pile's number from
##                    ONE layout is mostly about how it happened to land.
##   ... -- --disable=B  solver features off, for control legs (VerletRope's
##                    debug_disable: 1 edge contacts, 2 strand friction,
##                    4 the rays that confirm a cached plane)
##   ... -- --substeps=N the solver's substeps
##   ... -- --rest    nothing moved, nothing woken, 20 s: does it sleep and STAY
##                    asleep? Counts the wakes after its first sleep.
##   ... -- --still   no anchor motion: wake() every tick instead (held awake)
##   ... -- --sharp   the boxes' collision margin set to 0. Jolt ROUNDS a box's
##                    edges by its margin (up to 4 cm, 8% of its thinnest side)
##                    for shape queries, while a ray sees the sharp box: the
##                    control that says how much of a kick is that disagreement
##   ... -- --trace   the worst-kicked particle and its neighbours, tick by tick
##                    round the kick: position, velocity (mm/tick), and each cached
##                    contact plane with the particle's distance from it
##   ... -- --watch=N the same trace round particle N's own worst kick
##   ... -- --mu-s= --mu-k=   static / kinetic friction (the cord's own are 0.7 / 0.5)
##   ... -- --video=<dir> --resolution 640x480   (windowed) frames, 3 ticks each
##
## Every other rope check asks whether a cord SETTLES. Sleep hides jitter: a cord
## that chatters while a hand moves it reads a clean zero once it is asleep. Here
## the anchors move slowly and smoothly (a few cm over 3-4 s), so whatever a
## particle does from one tick to the next beyond a smooth path is the solver's.
##
## What to read: the SECOND DIFFERENCE of each particle's position,
## |x(t+1) - 2 x(t) + x(t-1)|, in mm. A particle carried smoothly reads ~0.02;
## one in free fall reads g dt^2 = 1.21. `max` is the worst kick in the run, `p95`
## and `mean` are of each tick's worst particle, `rough` is the mean over every
## particle and tick (the whole cord's shimmer), `kicks` counts ticks whose worst
## particle moved more than 0.5 mm off its path. A span SWAYING after its end
## was moved reads as kicks too, so the number that means jitter is `chatter`:
## ticks on which some particle's acceleration turned right round from the tick
## before, by more than 0.5 mm both times.
##
## One bare rope with cable.tscn's solver settings, hand-stepped; no plug bodies.

extends Node

const RADIUS := 0.0045
const SEG := 0.03
const DT := 1.0 / 90.0
const MEASURE := 720
const KICK := 0.0005

var _video := ""
var _frame := 0
var _rope: VerletRope
var _a: Node3D
var _b: Node3D
var _case := "edge"
var _still := false
var _sharp := false
var _trace := false
## Only particles above this height are measured (the edge cases leave slack
## heaped at the floor socket, which is the `heap` case's business, not theirs).
var _min_y := -1.0
var _mu_s := -1.0
var _watch := -1
var _rest := false
var _seeds := 1
var _disable := 0
var _substeps := 0
var _wave := -1.0
## Everything one layout builds, freed before the next.
var _stage: Node3D
var _rng := RandomNumberGenerator.new()
var _phase := 0.0
var _mu_k := -1.0
var _a0 := Vector3.ZERO
var _b0 := Vector3.ZERO
var _look_from := Vector3(0.6, 1.0, 0.9)
var _look_at := Vector3(0, 0.7, 0)


func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func() -> void:
		print("[jitter] TIMEOUT"); get_tree().quit(1))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--video="):
			_video = arg.trim_prefix("--video=")
		elif arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg == "--still":
			_still = true
		elif arg.begins_with("--mu-s="):
			_mu_s = float(arg.trim_prefix("--mu-s="))
		elif arg.begins_with("--mu-k="):
			_mu_k = float(arg.trim_prefix("--mu-k="))
		elif arg.begins_with("--watch="):
			_watch = int(arg.trim_prefix("--watch="))
			_trace = true
		elif arg.begins_with("--seeds="):
			_seeds = int(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--disable="):
			_disable = int(arg.trim_prefix("--disable="))
		elif arg.begins_with("--wave="):
			_wave = float(arg.trim_prefix("--wave="))
		elif arg.begins_with("--substeps="):
			_substeps = int(arg.trim_prefix("--substeps="))
		elif arg == "--rest":
			_rest = true
		elif arg == "--trace":
			_trace = true
		elif arg == "--sharp":
			_sharp = true
	var runs: Array = []
	for k in _seeds:
		# A pile lands differently for a millimetre's difference in where it
		# started, and one layout's number says more about the landing than
		# about the solver: each seed moves the ends a few millimetres and
		# starts the hand's motion somewhere else in its cycle.
		_rng.seed = 1000 + k
		_phase = 0.0 if k == 0 else _rng.randf()
		if is_instance_valid(_stage):
			_stage.free()
			await get_tree().physics_frame
		_stage = Node3D.new()
		add_child(_stage)
		_min_y = -1.0
		_box(Vector3(0, -0.05, 0), Vector3(6, 0.10, 6), Color(0.55, 0.5, 0.45))
		match _case:
			"edge":
				await _build_edge()
			"corner":
				await _build_corner()
			"wrap":
				await _build_wrap(false)
			"wrappipe":
				await _build_wrap(true)
			"heap":
				await _build_heap()
			"wound":
				await _build_wound()
			"loop":
				await _build_loop()
			_:
				print("[jitter] unknown case %s" % _case)
				get_tree().quit(1)
				return
		if not _video.is_empty() and k == 0:
			_stage_camera()
		_a0 = _a.position
		_b0 = _b.position
		if _rest:
			await _measure_rest()
			continue
		runs.append(await _measure())
	if _seeds > 1:
		var line := "[jitter] SUMMARY case=%s seeds=%d disable=%d substeps=%d:" % [
			_case, _seeds, _disable, _substeps]
		for key: String in ["chatter", "chatter_mm", "kicks", "max", "rough", "us"]:
			var vals: Array[float] = []
			for run: Dictionary in runs:
				vals.append(float(run[key]))
			vals.sort()
			line += " %s med %.3f [%.3f..%.3f]" % [key, vals[vals.size() / 2], vals[0], vals[vals.size() - 1]]
		print(line)
	get_tree().quit(0)


# ── cases ─────────────────────────────────────────────────────────────────────

func _build_edge() -> void:
	# The table's front edge is the line x = 0, y = 0.75.
	_box(Vector3(-0.5, 0.70, 0), Vector3(1.0, 0.10, 1.0), Color(0.42, 0.33, 0.25))
	_make_rope(Vector3(-0.9, 0.76, 0), Vector3(0.35, 0.76, 0), 68)
	await _run(120)
	await _carry(_b, Vector3(0.36, 0.03, 0), 90)
	await _run(300)
	_min_y = 0.3
	_look_from = Vector3(0.55, 0.95, 0.75)
	_look_at = Vector3(0.0, 0.70, 0.0)


func _build_corner() -> void:
	# A block to the floor whose top vertex is at (0, 0.75, 0): the cord runs
	# diagonally over it, so it bears on two top edges and the upright one.
	_box(Vector3(-0.5, 0.375, -0.5), Vector3(1.0, 0.75, 1.0), Color(0.42, 0.33, 0.25))
	_make_rope(Vector3(-0.6, 0.76, -0.6), Vector3(0.28, 0.76, 0.28), 68)
	await _run(120)
	await _carry(_b, Vector3(0.25, 0.03, 0.25), 90)
	await _run(300)
	_min_y = 0.3
	_look_from = Vector3(0.75, 1.05, 0.35)
	_look_at = Vector3(0.0, 0.70, 0.0)


func _build_wrap(round_post: bool) -> void:
	# A horizontal bar along Z at 0.6 m (on an upright post the turns just slide
	# down to the floor, and the case measures a fall).
	var r := 0.05
	if round_post:
		r = 0.03 + RADIUS + 0.004
		_cylinder(Vector3(0, 0.6, 0), 0.03, 1.0, Color(0.42, 0.33, 0.25))
	else:
		_box(Vector3(0, 0.6, 0), Vector3(0.06, 0.06, 1.0), Color(0.42, 0.33, 0.25))
	# In along +X over the top, two turns advancing 15 mm a turn, out along +X.
	var path: Array[Vector3] = []
	for k in 41:
		path.append(Vector3(-0.5 + 0.5 * float(k) / 40.0, 0.6 + r, 0.0))
	for k in range(1, 161):
		var th := PI * 0.5 - TAU * 2.0 * float(k) / 160.0
		path.append(Vector3(r * cos(th), 0.6 + r * sin(th), 0.03 * float(k) / 160.0))
	for k in range(1, 41):
		path.append(Vector3(0.5 * float(k) / 40.0, 0.6 + r, 0.03))
	_lay(path)
	await _run(240)
	_look_from = Vector3(0.30, 0.85, 0.50)
	_look_at = Vector3(0.0, 0.58, 0.0)


func _build_heap() -> void:
	_make_rope(Vector3(-0.1, 0.3, 0), Vector3(0.1, 0.3, 0), int(round(2.0 / SEG)))
	await _run(500)
	_look_from = Vector3(0.35, 0.35, 0.45)
	_look_at = Vector3(0.0, 0.05, 0.0)


func _build_loop() -> void:
	# An alpha loop on the floor: ONE place where the cord lies across itself
	# (rope_crossing_probe's lay). The isolated strand-on-strand case.
	var path: Array[Vector3] = []
	for k in 401:
		var t := float(k) / 400.0
		var up := exp(-pow((t - 0.8) / 0.03, 2.0)) * RADIUS * 2.2
		path.append(Vector3(0.8 * (t - 0.5) + 0.3 * sin(TAU * t), RADIUS + up,
			0.25 * (1.0 - cos(TAU * t))))
	_lay(path)
	await _run(200)
	_look_from = Vector3(0.05, 0.25, 0.75)
	_look_at = Vector3(0.0, 0.01, 0.2)


func _build_wound() -> void:
	# In along +X on the floor, 3.5 turns of an 8 cm coil each lying on the last,
	# and out along -X from the top turn; that end is then set down on the floor.
	var r := 0.08
	var path: Array[Vector3] = []
	for k in 31:
		path.append(Vector3(-0.3 + 0.3 * float(k) / 30.0, RADIUS, -r))
	var top := RADIUS
	for k in range(1, 281):
		var th := -PI * 0.5 + TAU * 3.5 * float(k) / 280.0
		top = RADIUS + RADIUS * 2.1 * 3.5 * float(k) / 280.0
		path.append(Vector3(r * cos(th), top, r * sin(th)))
	for k in range(1, 31):
		path.append(Vector3(-0.3 * float(k) / 30.0, top, r))
	_lay(path)
	await _run(60)
	await _carry(_b, Vector3(-0.3, RADIUS, r), 60)
	await _run(300)
	_look_from = Vector3(0.22, 0.20, 0.34)
	_look_at = Vector3(0.0, 0.02, 0.0)


## Where the anchors are at tick `t` of the measured run: slow and smooth.
func _drive(t: int) -> void:
	if _still:
		_rope.wake()
		return
	var s4 := sin(TAU * (float(t) / 360.0 + _phase)) - sin(TAU * _phase)
	var s3 := sin(TAU * (float(t) / 240.0 + _phase)) - sin(TAU * _phase)
	match _case:
		"edge":
			_a.position = _a0 + Vector3(0.04 * s3, 0, 0)
			_b.position = _b0 + Vector3(0, 0, 0.10 * s4)
		"corner":
			_a.position = _a0 + Vector3(0.06 * s4, 0, -0.06 * s4)
			_b.position = _b0 + Vector3(0.04 * s3, 0, 0.04 * s3)
		"wrap", "wrappipe":
			_b.position = _b0 + Vector3(-0.03 * (0.5 - 0.5 * cos(TAU * float(t) / 360.0)), 0, 0.03 * s3)
		"heap":
			_b.position = _b0 + Vector3(0.05 * s4, 0.03 * s3, 0.04 * s3)
		"wound":
			_a.position = _a0 + Vector3(0.03 * s4, 0, 0.02 * s3)
		"loop":
			_b.position = _b0 + Vector3(0.04 * s4, 0, 0.03 * s3)


# ── measuring ─────────────────────────────────────────────────────────────────

func _measure() -> Dictionary:
	var p1: PackedVector3Array = _rope.get_points()
	var p0: PackedVector3Array = p1
	var have := 0
	var per_tick: Array[float] = []
	var worst := 0.0
	var worst_i := -1
	var worst_tick := -1
	var rough := 0.0
	var rough_n := 0
	var kicks := 0
	var slept := 0
	var spent := 0
	var history: Array = []
	var per_particle := PackedFloat32Array()
	per_particle.resize(p1.size())
	# CHATTER: a particle whose acceleration turns right round from one tick to
	# the next, more than KICK both times. A span swaying after its end was moved
	# has large second differences too, but they keep their direction for many
	# ticks; a contact fighting the solve does not.
	var last_d2 := PackedVector3Array()
	last_d2.resize(p1.size())
	var chatter := 0
	var chatter_worst := 0.0
	var chatter_i := -1
	var chatter_tick := -1
	var keys: Array[String] = ["sweep_snaps", "mid_turns", "capsule_stops", "recoveries",
		"self_pairs", "self_segments", "edges_found", "edge_handovers", "edges_lost"]
	var before: Dictionary = _rope.get_sleep_metrics()
	# What collision did on each tick whose worst particle was kicked, and on
	# each that was not: the pass that kicks shows up in the first and not the second.
	var on_kick := {}
	var on_calm := {}
	var calm := 0
	for key: String in keys:
		on_kick[key] = 0
		on_calm[key] = 0
	for t in MEASURE:
		await get_tree().physics_frame
		_drive(t)
		var began := Time.get_ticks_usec()
		_rope.step(DT)
		spent += Time.get_ticks_usec() - began
		var after: Dictionary = _rope.get_sleep_metrics()
		if _trace:
			var row: Array = []
			var snap: PackedVector3Array = _rope.get_points()
			for i in snap.size():
				var c: Dictionary = _rope.get_contact_debug(i)
				c["at"] = snap[i]
				row.append(c)
			history.append(row)
		if _rope.is_sleeping():
			slept += 1
		var now: PackedVector3Array = _rope.get_points()
		if have >= 2 and now.size() == p0.size():
			var tick_max := 0.0
			var tick_chatter := 0.0
			# The pinned ends are the anchors' own motion.
			for i in range(1, now.size() - 1):
				if now[i].y < _min_y:
					continue
				var d2v := now[i] - p1[i] * 2.0 + p0[i]
				var d2 := d2v.length()
				if d2 > KICK and last_d2[i].length() > KICK and d2v.dot(last_d2[i]) < -0.5 * d2 * last_d2[i].length():
					tick_chatter = maxf(tick_chatter, minf(d2, last_d2[i].length()))
					if minf(d2, last_d2[i].length()) > chatter_worst:
						chatter_i = i
						chatter_tick = t
				last_d2[i] = d2v
				rough += d2
				rough_n += 1
				per_particle[i] += d2
				if d2 > tick_max:
					tick_max = d2
				if d2 > worst and (_watch < 0 or i == _watch):
					worst = d2
					worst_i = i
					worst_tick = t
			per_tick.append(tick_max)
			if tick_chatter > 0.0:
				chatter += 1
				chatter_worst = maxf(chatter_worst, tick_chatter)
			if tick_max > KICK:
				kicks += 1
			else:
				calm += 1
			for key: String in keys:
				var did := int(after.get(key, 0)) - int(before.get(key, 0))
				if tick_max > KICK:
					on_kick[key] += did
				else:
					on_calm[key] += did
		before = after
		p0 = p1
		p1 = now
		have += 1
		await _shoot(t)
	per_tick.sort()
	var n := per_tick.size()
	var mean := 0.0
	for v: float in per_tick:
		mean += v
	mean /= maxf(float(n), 1.0)
	var pts: PackedVector3Array = _rope.get_points()
	print("[jitter] case=%s %s particles=%d ticks=%d asleep_ticks=%d" % [
		_case, "still" if _still else "driven", pts.size(), n, slept])
	print("[jitter] second difference mm: max=%.3f p95=%.3f median=%.3f mean=%.3f rough=%.4f kicks=%d/%d" % [
		worst * 1000.0, per_tick[int(float(n) * 0.95)] * 1000.0, per_tick[n / 2] * 1000.0,
		mean * 1000.0, rough / maxf(float(rough_n), 1.0) * 1000.0, kicks, n])
	print("[jitter] chatter (acceleration reversing tick to tick, over %.1f mm both ways): %d/%d ticks, worst %.3f mm" % [
		KICK * 1000.0, chatter, n, chatter_worst * 1000.0])
	print("[jitter] worst kick: particle %d of %d at tick %d, now at %s" % [
		worst_i, pts.size(), worst_tick, str(pts[maxi(worst_i, 0)])])
	if _trace and chatter_i >= 0 and _watch < 0:
		# Chatter is what the trace is for, when there is any.
		worst_i = chatter_i
		worst_tick = chatter_tick
		print("[jitter] tracing the worst chatter: particle %d at tick %d" % [worst_i, worst_tick])
	if _trace:
		# The kicked particle and its two neighbours, from six ticks before the
		# worst kick to three after: where each was, and what it was resting on.
		for t in range(maxi(worst_tick - 6, 0), mini(worst_tick + 4, history.size())):
			for i in range(maxi(worst_i - 1, 0), mini(worst_i + 2, pts.size())):
				var c: Dictionary = history[t][i]
				var at: Vector3 = c["at"]
				var vel: Vector3 = c["velocity"]
				var text := "[trace] t%d p%d at (%.1f %.1f %.1f) v (%.2f %.2f %.2f) flags %d" % [
					t, i, at.x * 1000.0, at.y * 1000.0, at.z * 1000.0,
					vel.x * 1000.0, vel.y * 1000.0, vel.z * 1000.0, int(c["flags"])]
				if int(c["flags"]) & 1:
					text += " n1 %s d1 %.2f" % [_n(c["n1"]), (at - (c["p1"] as Vector3)).dot(c["n1"]) * 1000.0]
				if int(c["flags"]) & 2:
					text += " n2 %s d2 %.2f" % [_n(c["n2"]), (at - (c["p2"] as Vector3)).dot(c["n2"]) * 1000.0]
				if int(c["mid"]) & 1:
					text += " mid1 %s t %.2f" % [_n(c["mid_n1"]), float(c["mid_t1"])]
				if int(c["mid"]) & 2:
					text += " mid2 %s t %.2f" % [_n(c["mid_n2"]), float(c["mid_t2"])]
				print(text)
	# Where along the cord the shimmer is: each particle's mean, worst five first.
	var order: Array = range(pts.size())
	order.sort_custom(func(x: int, y: int) -> bool: return per_particle[x] > per_particle[y])
	var where := "[jitter] roughest particles (mean mm, at):"
	for k in mini(5, order.size()):
		var idx: int = order[k]
		where += " p%d %.3f (%.0f %.0f %.0f)" % [idx, per_particle[idx] / maxf(float(n), 1.0) * 1000.0,
			pts[idx].x * 1000.0, pts[idx].y * 1000.0, pts[idx].z * 1000.0]
	print(where)
	var line := "[jitter] events per tick, kicked / calm:"
	for key: String in keys:
		line += " %s %.2f/%.2f" % [key, float(on_kick[key]) / maxf(float(kicks), 1.0),
			float(on_calm[key]) / maxf(float(calm), 1.0)]
	print(line)
	var longest := 0.0
	for i in range(pts.size() - 1):
		longest = maxf(longest, pts[i].distance_to(pts[i + 1]))
	print("[jitter] longest segment %.2fx rest, step %.0f us" % [
		longest / _rope.segment_length, float(spent) / float(MEASURE)])
	return {"chatter": chatter, "chatter_mm": chatter_worst * 1000.0, "kicks": kicks, "max": worst * 1000.0, "p95": per_tick[int(float(n) * 0.95)] * 1000.0,
		"rough": rough / maxf(float(rough_n), 1.0) * 1000.0, "us": float(spent) / float(MEASURE)}


## Nothing is moved and nothing is woken: does the cord go to sleep and STAY
## asleep? A sleeping cord is polled for a change in what it rests on, and a
## poll that is wrong wakes it, it jolts, settles and sleeps again, about once a
## second for ever.
func _measure_rest() -> void:
	var prev: PackedVector3Array = _rope.get_points()
	var first := -1
	var wakes := 0
	var worst := 0.0
	var asleep := false
	var awake_ticks := 0
	for t in 1800:
		if t % 4 == 0:
			await get_tree().physics_frame
		_rope.step(DT)
		var now: PackedVector3Array = _rope.get_points()
		var sleeping: bool = _rope.is_sleeping()
		if sleeping and first < 0:
			first = t
		if first >= 0:
			if asleep and not sleeping:
				wakes += 1
				print("[jitter] woke at tick %d" % t)
			if not sleeping:
				awake_ticks += 1
			for i in now.size():
				worst = maxf(worst, now[i].distance_to(prev[i]))
		asleep = sleeping
		prev = now
	print("[jitter] REST case=%s: first asleep at tick %d, then %d wakes in %d ticks, awake for %d of them, worst single-tick move %.3f mm" % [
		_case, first, wakes, 1800 - maxi(first, 0), awake_ticks, worst * 1000.0])


func _n(v: Vector3) -> String:
	return "(%.2f %.2f %.2f)" % [v.x, v.y, v.z]


func _run(ticks: int) -> void:
	for t in ticks:
		await get_tree().physics_frame
		_rope.step(DT)


func _carry(node: Node3D, to: Vector3, ticks: int) -> void:
	var stride: Vector3 = (to - node.position) / float(ticks)
	for t in ticks:
		await get_tree().physics_frame
		node.position += stride
		_rope.step(DT)


# ── building ──────────────────────────────────────────────────────────────────

func _make_rope(a: Vector3, b: Vector3, segments: int, seg_len := SEG) -> void:
	_a = Node3D.new()
	_a.position = a + _nudge()
	_stage.add_child(_a)
	_b = Node3D.new()
	_b.position = b + _nudge()
	_stage.add_child(_b)
	_rope = VerletRope.new()
	_stage.add_child(_rope)
	if _disable != 0:
		_rope.set("debug_disable", _disable)
	if _wave >= 0.0:
		_rope.set("wave_damping", _wave)
	if _substeps > 0:
		_rope.set("substeps", _substeps)
	# cable.tscn's solver settings; a bare VerletRope is softer than anything shipped.
	_rope.constraint_iterations = 8
	_rope.bend_stiffness = 0.2
	_rope.collision_radius = RADIUS
	_rope.tube_radius = 0.004
	_rope.surface_collision_mask = 7
	_rope.self_collision = true
	if _mu_s >= 0.0:
		_rope.static_friction = _mu_s
	if _mu_k >= 0.0:
		_rope.kinetic_friction = _mu_k
	_rope.segment_count = segments
	_rope.segment_length = seg_len
	_rope.start_node = _a
	_rope.end_node = _b
	_rope.set_process(false)
	_rope.set_physics_process(false)
	_rope._init_points()


## A few millimetres along the floor, different for every seed after the first.
func _nudge() -> Vector3:
	if _rng.seed == 1000:
		return Vector3.ZERO
	return Vector3(_rng.randf_range(-0.004, 0.004), 0.0, _rng.randf_range(-0.004, 0.004))


## A rope laid along `path`, resampled at equal arc length onto its particles.
func _lay(path: Array[Vector3]) -> void:
	var length := 0.0
	for k in path.size() - 1:
		length += path[k].distance_to(path[k + 1])
	var segments := int(round(length / SEG))
	_make_rope(path[0], path[path.size() - 1], segments, length / float(segments))
	var lay := PackedVector3Array()
	var run := 0.0
	var k := 0
	for p in segments + 1:
		var want := length * float(p) / float(segments)
		while k < path.size() - 2 and run + path[k].distance_to(path[k + 1]) < want:
			run += path[k].distance_to(path[k + 1])
			k += 1
		var span := path[k].distance_to(path[k + 1])
		lay.append(path[k].lerp(path[k + 1], clampf((want - run) / maxf(span, 1e-9), 0.0, 1.0)))
	print("[jitter] laid %d segments of %.1f mm, restored=%s" % [
		segments, length / float(segments) * 1000.0, str(_rope.restore_points(lay))])


func _box(centre: Vector3, size: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_stage.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	if _sharp:
		shape.margin = 0.0
	col.shape = shape
	col.position = centre
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = centre
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mi.material_override = mat
	body.add_child(mi)


func _cylinder(centre: Vector3, radius: float, height: float, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_stage.add_child(body)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position = centre
	col.rotation_degrees = Vector3(90, 0, 0)   # long axis along Z
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = centre
	mi.rotation_degrees = Vector3(90, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mi.material_override = mat
	body.add_child(mi)


# ── video ─────────────────────────────────────────────────────────────────────

func _shoot(tick: int) -> void:
	if _video.is_empty() or tick % 3 != 0:
		return
	_rope.remesh()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [
		ProjectSettings.globalize_path(_video), _frame])
	_frame += 1


func _stage_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35.0
	cam.near = 0.02
	cam.look_at_from_position(_look_from, _look_at)
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	add_child(sun)
	_rope.rope_color = Color(0.85, 0.75, 0.2)
	# The boot curtain is a 44 m panel standing in the world.
	var overlay := get_node_or_null("/root/LoadingOverlay")
	if overlay != null and overlay.has_method("suspend"):
		overlay.suspend()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_video))
