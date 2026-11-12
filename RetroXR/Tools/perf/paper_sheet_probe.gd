## paper_sheet_probe — the thermal paper's numbers, headless: how it stands,
## falls over, feeds onto a table, and what a frame's steps cost (GbThermalRibbon
## on paper-godot's PaperSheetSolver; gb-printer.md).
##   "$godot" --headless --path RetroXR res://Tools/perf/paper_sheet_probe.tscn
## After `--`: `--feed` the feeds only, `--trace` how it settles second by second,
## `--uneven` a window's uneven frame times (the paper must still rest),
## `--dump` its shape, `--carry` the printer carried toward paper lying on a table,
## `--tune=<constant>:<value>` one of the solver's constants changed for the run.
## It is also what the "Quest paper probe" export preset starts (project.godot).
extends Node

const SLOT := Vector3(0.0, 0.0305, 0.026)
const TABLE_Y := -0.0305
const DT := 1.0 / 90.0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void: get_tree().quit(2))
	if not GbThermalRibbon.has_solver():
		print("[paper] FAIL: paper-godot has no PaperSheetSolver")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tune="):
			var kv := arg.trim_prefix("--tune=").split(":")
			ClassDB.class_call_static(&"PaperSheetSolver", &"tune", kv[0], float(kv[1]))
			print("[paper] tuned %s = %s" % [kv[0], kv[1]])
	if OS.get_cmdline_user_args().has("--carry"):
		_carry()
		get_tree().quit(0)
		return
	if not OS.get_cmdline_user_args().has("--feed"):
		for length: float in [0.04, 0.08, 0.15, 0.22, 0.6, 1.2]:
			_stand(length)
	_feed(1.0, 0.02)
	_feed(1.0, 0.04)
	get_tree().quit(0)


func _sheet() -> GbThermalRibbon:
	var r := GbThermalRibbon.new()
	var lean := deg_to_rad(8.0)
	r.set_slot(SLOT, Vector3(0.0, cos(lean), -sin(lean)), Vector3.RIGHT)
	r.boxes = [AABB(Vector3(-0.035, -0.03, -0.0675), Vector3(0.07, 0.06, 0.135))]
	r.patches = [[Vector3.UP, TABLE_Y, Vector3(0.0, TABLE_Y, 0.0), 10.0, 0.05]]
	return r


func _report(what: String, r: GbThermalRibbon, usec: float) -> void:
	var mid := r.centers()
	var stretch := 0.0
	var lowest := INF
	for i in range(3, mid.size()):
		stretch = maxf(stretch, absf(r.positions[2 * i].distance_to(r.positions[2 * i - 2]) - r.ds))
	for p in r.positions:
		lowest = minf(lowest, p.y - TABLE_Y)
	var tip := mid[mid.size() - 1]
	var fast := 0
	var sharp := 1
	for i in mid.size():
		if r.velocities[2 * i].length() > r.velocities[2 * fast].length():
			fast = i
		if i >= 1 and i < mid.size() - 1 and (mid[i] - mid[i - 1]).angle_to(mid[i + 1] - mid[i]) 				> (mid[sharp] - mid[sharp - 1]).angle_to(mid[sharp + 1] - mid[sharp]):
			sharp = i
	print("[paper]   fastest row %d at %s v=%s; sharpest row %d at %s" % [fast, mid[fast], r.velocities[2 * fast], sharp, mid[sharp]])
	if OS.get_cmdline_user_args().has("--dump"):
		var line := ""
		for i in mid.size():
			line += "(%.0f,%.0f) " % [mid[i].z * 1000.0, mid[i].y * 1000.0]
		print("[paper]   z,y mm: " + line)
	var side := 0.0
	for q in mid:
		side = maxf(side, absf(q.x))
	print("[paper] %s rows=%d sideways=%.0f mm tip=(y %.3f z %.3f) sharpest=%.1f deg stretch=%.3f mm lowest=%.2f mm speed=%.2f mm/s step=%.0f us" % [
		what, mid.size(), side * 1000.0, tip.y, tip.z, rad_to_deg(r.sharpest_turn()), stretch * 1000.0,
		lowest * 1000.0, r.move_speed * 1000.0, usec])


func _stand(length: float) -> void:
	var r := _sheet()
	r.set_out(length)
	var spent := 0
	var frames := int(8.0 / DT)
	var rest_at := -1.0
	for f in frames:
		var t0 := Time.get_ticks_usec()
		r.step(DT, Vector3(0.0, -9.8, 0.0))
		spent += Time.get_ticks_usec() - t0
		if rest_at < 0.0 and r.move_speed < 0.0005:
			rest_at = f * DT
		elif r.move_speed >= 0.0005:
			rest_at = -1.0
	_report("stand %.2f m (quiet since %.1f s)" % [length, rest_at], r, float(spent) / frames)


## Feed `length` of paper at `speed` m/s onto the table, then let it lie.
func _feed(length: float, speed: float) -> void:
	var r := _sheet()
	r.set_out(0.004)
	var paper := 0.004
	var spent := 0
	var frames := 0
	var worst := 0.0
	while paper < length:
		paper = minf(length, paper + speed * DT)
		r.set_out(paper)
		var t0 := Time.get_ticks_usec()
		r.step(DT, Vector3(0.0, -9.8, 0.0))
		spent += Time.get_ticks_usec() - t0
		frames += 1
		var turn := r.sharpest_turn()
		if turn > worst + 0.2 or (frames % 450 == 0 and OS.get_cmdline_user_args().has("--trace")):
			var mid := r.centers()
			var at := 1
			for i in range(1, mid.size() - 1):
				if (mid[i] - mid[i - 1]).angle_to(mid[i + 1] - mid[i]) > (mid[at] - mid[at - 1]).angle_to(mid[at + 1] - mid[at]):
					at = i
			print("[paper]   %.3f m out: turn %.0f deg at row %d of %d, (z %.0f, y %.0f) mm; tip (z %.0f, y %.0f)" % [paper, rad_to_deg(turn), at, mid.size(),
				mid[at].z * 1000.0, mid[at].y * 1000.0, mid[mid.size() - 1].z * 1000.0, mid[mid.size() - 1].y * 1000.0])
		worst = maxf(worst, turn)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var uneven := OS.get_cmdline_user_args().has("--uneven")
	for f in int(8.0 / DT):
		# A window's frames: 60 a second give or take, a long one now and then.
		var dt := DT
		if uneven:
			dt = (0.05 if rng.randf() < 0.1 else rng.randf_range(0.014, 0.02))
		r.step(dt, Vector3(0.0, -9.8, 0.0))
		if f % 90 == 89 and OS.get_cmdline_user_args().has("--trace"):
			print("[paper]   %d s after the feed: %.2f mm/s" % [(f + 1) / 90, r.move_speed * 1000.0])
	var mid := r.centers()
	var lo := mid[0]
	var hi := mid[0]
	for p in mid:
		lo = lo.min(p)
		hi = hi.max(p)
	_report("feed %.1f m at %.0f mm/s (sharpest while feeding %.1f deg, lies y %.3f..%.3f z %.3f..%.3f)" % [
		length, speed * 1000.0, rad_to_deg(worst), lo.y, hi.y, lo.z, hi.z], r, float(spent) / maxi(frames, 1))


## Paper fed flat along a table from a slot lying on it, then the printer carried
## 10 cm toward its paper: the paper lying on the table stays with the ROOM (it
## is pushed up into a loop), with friction; without, it rides along untouched.
func _carry() -> void:
	for mu: float in [0.45, 0.0]:
		ClassDB.class_call_static(&"PaperSheetSolver", &"tune", "mu_static", mu)
		ClassDB.class_call_static(&"PaperSheetSolver", &"tune", "mu_kinetic", mu * 0.78)
		var r := GbThermalRibbon.new()
		r.set_slot(Vector3(0.0, 0.0005, 0.0), Vector3(0.0, 0.0, -1.0), Vector3.RIGHT)
		r.patches = [[Vector3.UP, 0.0, Vector3.ZERO, 10.0, 0.05]]
		r.set_out(0.3)
		while r.feeding():
			r.step(DT, Vector3(0.0, -9.8, 0.0))
		for f in int(3.0 / DT):
			r.step(DT, Vector3(0.0, -9.8, 0.0))
		var from := r.positions.duplicate()
		for f in 90:
			r.step(DT, Vector3(0.0, -9.8, 0.0), Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -0.1))
		var tip := r.positions[r.positions.size() - 1].z - from[from.size() - 1].z
		var high := 0.0
		for p in r.positions:
			high = maxf(high, p.y)
		print("[paper] carried 10 cm toward its paper, mu %.2f: free end %.1f mm nearer the slot, loop %.1f mm high" % [
			mu, tip * 1000.0, high * 1000.0])
