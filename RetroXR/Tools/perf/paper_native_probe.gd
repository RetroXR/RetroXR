## The paper solvers, GDScript against paper-godot's native port, side by side.
## godot --headless --path RetroXR res://Tools/perf/paper_native_probe.tscn
## On a Quest: the "Quest paper probe" preset (com.xenu.retroxr.ppprobe), whose
## main scene this is (run/main_scene.paperprobe; quest-device.md has the recipe).
## Each case runs three ways. The script; native with the ENGINE's sin/cos/
## atan2/exp (`engine_math`), which must agree with the script to the bit, or the
## port is wrong (FAIL); and native as the room runs it, on its own libm, which
## can part from the engine's in the last bit of a double (Windows: MSVC against
## MinGW): its largest gap is reported, with each one's time a frame, never
## failed. On a Quest the probe-only export runs it (quest-device.md), where the
## engine and the library are built by different compilers: a gap there is
## reported for what it is. [paper-native] lines only.
extends Node

const FRAMES := 60
## A headset has no console to close a wedged probe from.
const GIVE_UP_S := 300.0


func _ready() -> void:
	get_tree().create_timer(GIVE_UP_S).timeout.connect(func() -> void:
		print("[paper-native] TIMEOUT after %d s" % GIVE_UP_S)
		get_tree().quit(2))
	print("[paper-native] %s, %s" % [OS.get_name(), Engine.get_version_info().string])
	if not ClassDB.class_exists(&"PaperStripSolver"):
		print("[paper-native] FAIL paper-godot is not loaded")
		get_tree().quit(1)
		return
	var parted := 0
	for length: float in [0.04, 0.12, 0.24, 0.6, 1.2]:
		for kind in ["free", "patches", "case", "finger", "torn"]:
			# One case a frame: a long run must not hold the main thread (or a
			# headset's compositor) for a minute at a time.
			await get_tree().process_frame
			parted += _strip_case(length, kind)
		for kind in ["held", "patches", "loose", "landing"]:
			await get_tree().process_frame
			parted += _ribbon_case(length, kind)
	print("[paper-native] %s: %d cases parted" % ["PASS" if parted == 0 else "FAIL", parted])
	get_tree().quit(0 if parted == 0 else 1)


func _strip(length: float, kind: String) -> GbPrinterStrip:
	var s := GbPrinterStrip.new()
	s.set_length(length)
	s.place(Vector2(0.03, 0.0), 0.14)
	match kind:
		"patches":
			for i in 49:
				s.patches.append([Vector2.RIGHT, -0.025, Vector2(-0.025, (i - 24) * 0.015), 0.012, 0.03])
		"case":
			# The printer's boxes, a table and a wall: what the room hands it.
			s.boxes = [Rect2(Vector2(-0.0285, -0.07), Vector2(0.057, 0.14)), Rect2(Vector2(0.02, -0.03), Vector2(0.012, 0.025))]
			s.planes = [[Vector2(1.0, 0.0), -0.0285]]
			s.patches = [[Vector2(0.0, 1.0), -0.12, Vector2(0.0, -0.12), 0.08]]
		"finger":
			s.fingers = [[Vector2(0.05, -0.004), 0.009]]
		"torn":
			var other := GbPrinterStrip.new()
			other.set_length(length * 0.5)
			other.place(Vector2.ZERO, -0.3)
			s.meet_other_half(other)
	return s


func _strip_case(length: float, kind: String) -> int:
	var a := _strip(length, kind)
	var b := _strip(length, kind)
	var c := _strip(length, kind)
	b._native_solver().engine_math = true
	var libm := 0.0
	var first := -1
	var worst := 0.0

	var t_script := 0
	var t_native := 0
	for frame in FRAMES:
		var g := Vector2(-9.8, 0.0)
		var shove := Vector2(0.0, sin(frame * 0.1))
		GbPrinterStrip.native = false
		var start := Time.get_ticks_usec()
		a.step(1.0 / 90.0, g, 0.3 * cos(frame * 0.2), shove)
		t_script += Time.get_ticks_usec() - start
		GbPrinterStrip.native = true
		b.step(1.0 / 90.0, g, 0.3 * cos(frame * 0.2), shove)
		start = Time.get_ticks_usec()
		c.step(1.0 / 90.0, g, 0.3 * cos(frame * 0.2), shove)
		t_native += Time.get_ticks_usec() - start
		libm = maxf(libm, maxf(_diff2(a.points, c.points), _diff1(a.angles, c.angles)))
		var d := _diff2(a.points, b.points)
		d = maxf(d, _diff1(a.angles, b.angles))
		d = maxf(d, absf(a.sway_speed - b.sway_speed))
		if d > 0.0 and first < 0:
			first = frame
		worst = maxf(worst, d)
	print("[paper-native] strip  %-8s length=%.2f n=%2d  %s  libm %-9s  script %.3f ms  native %.3f ms  x%.0f" % [
		kind, length, a.segments, _verdict(first, worst), String.num_scientific(libm), t_script / 1000.0 / FRAMES,
		t_native / 1000.0 / FRAMES, float(t_script) / maxf(t_native, 1.0)])
	return int(first >= 0)


func _ribbon(length: float, kind: String) -> GbThermalRibbon:
	var r := GbThermalRibbon.new()
	r.configure(length, 0.038)
	match kind:
		"held":
			r.pin_nearest(Vector3.ZERO)
		"patches":
			r.pin_nearest(Vector3.ZERO)
			for i in 49:
				r.patches.append([Vector3.BACK, -0.025, Vector3(0, (i - 24) * 0.015, -0.025), 0.025, 0.03])
		"loose":
			# Loose on a table: the body recovery and the patches moving with it.
			r.patches = [[Vector3.UP, -0.004, Vector3(0, -0.004, 0), 0.6, 0.03]]
		"landing":
			r.patches = [[Vector3.UP, 0.002, Vector3(0, 0.002, 0), 0.6, 0.03],
				[Vector3.BACK, 0.05, Vector3(0, 0, 0.05), 0.3, 0.2]]
	return r


func _ribbon_case(length: float, kind: String) -> int:
	var a := _ribbon(length, kind)
	var b := _ribbon(length, kind)
	var c := _ribbon(length, kind)
	b._native_solver().engine_math = true
	var libm := 0.0
	var first := -1
	var worst := 0.0

	var t_script := 0
	var t_native := 0
	for frame in FRAMES:
		var g := Vector3(0, -9.8, 0) if kind != "loose" and kind != "landing" else Vector3.ZERO
		var spin := Vector3(0, sin(frame * 0.1), 0.2 * cos(frame * 0.3))
		GbThermalRibbon.native = false
		var start := Time.get_ticks_usec()
		a.step(1.0 / 90.0, g, spin)
		t_script += Time.get_ticks_usec() - start
		GbThermalRibbon.native = true
		b.step(1.0 / 90.0, g, spin)
		start = Time.get_ticks_usec()
		c.step(1.0 / 90.0, g, spin)
		t_native += Time.get_ticks_usec() - start
		libm = maxf(libm, maxf(_diff3(a.positions, c.positions), _diff3(a.velocities, c.velocities)))
		var d := maxf(_diff3(a.positions, b.positions), _diff3(a.velocities, b.velocities))
		d = maxf(d, a.body_shift.distance_to(b.body_shift))
		d = maxf(d, absf(a.move_speed - b.move_speed))
		for i in a.patches.size():
			d = maxf(d, absf(float(a.patches[i][1]) - float(b.patches[i][1])))
		if d > 0.0 and first < 0:
			first = frame
		worst = maxf(worst, d)
	print("[paper-native] ribbon %-8s length=%.2f n=%2d  %s  libm %-9s  script %.3f ms  native %.3f ms  x%.0f" % [
		kind, length, a.segments, _verdict(first, worst), String.num_scientific(libm), t_script / 1000.0 / FRAMES,
		t_native / 1000.0 / FRAMES, float(t_script) / maxf(t_native, 1.0)])
	return int(first >= 0)


func _verdict(first: int, worst: float) -> String:
	if first < 0:
		return "exact          "
	return "PARTS frame %2d max %s" % [first, String.num_scientific(worst)]


func _diff1(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d = maxf(d, absf(a[i] - b[i]))
	return d if a.size() == b.size() else INF


func _diff2(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d = maxf(d, a[i].distance_to(b[i]))
	return d if a.size() == b.size() else INF


func _diff3(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d = maxf(d, a[i].distance_to(b[i]))
	return d if a.size() == b.size() else INF
