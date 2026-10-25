## Paper CPU microbenchmark, no printer core or headset required.
## godot --headless --path RetroXR --script res://Tools/perf/paper_cpu_probe.gd
## Add -- --baseline before an optimization, then -- --compare afterwards to
## compare every recorded pose exactly. Output lives in repo-root build_out/.
## Measures the solvers, not rendering, ray casts, or the rigid-body engine.
extends SceneTree

class TimedStrip extends GbPrinterStrip:
	var contact_us := 0
	func _contact() -> void:
		var start := Time.get_ticks_usec()
		super._contact()
		contact_us += Time.get_ticks_usec() - start

class TimedRibbon extends GbThermalRibbon:
	var contact_us := 0
	var self_us := 0
	func _surface_contacts() -> void:
		var start := Time.get_ticks_usec()
		super._surface_contacts()
		contact_us += Time.get_ticks_usec() - start
	func _self_contacts(before: PackedVector3Array) -> void:
		var start := Time.get_ticks_usec()
		super._self_contacts(before)
		self_us += Time.get_ticks_usec() - start

func _initialize() -> void:
	var states: Array = []
	for length: float in [0.04, 0.12, 0.24, 0.6, 1.2]:
		for contact in [false, true]:
			var strip := TimedStrip.new()
			strip.set_length(length)
			strip.place(Vector2.ZERO, 0.0)
			if contact:
				for i in 49:
					strip.patches.append([Vector2.RIGHT, -0.025, Vector2(-0.025, (i - 24) * 0.015), 0.012, 0.03])
			var start := Time.get_ticks_usec()
			for frame in 60:
				strip.step(1.0 / 90.0, Vector2(-9.8, 0), 0.0, Vector2(0, sin(frame * 0.1)))
				states.append(strip.points.duplicate())
			print("[paper-cpu] strip length=%.2f n=%d contact=%s total=%.3f contact=%.3f ms/frame" % [length, strip.segments, contact, (Time.get_ticks_usec() - start) / 60000.0, strip.contact_us / 60000.0])
			var ribbon := TimedRibbon.new()
			ribbon.configure(length, 0.038)
			ribbon.pin_nearest(Vector3.ZERO)
			if contact:
				for i in 49:
					ribbon.patches.append([Vector3.BACK, -0.025, Vector3(0, (i - 24) * 0.015, -0.025), 0.025, 0.03])
			start = Time.get_ticks_usec()
			for frame in 60:
				ribbon.step(1.0 / 90.0, Vector3(0, -9.8, 0), Vector3(0, sin(frame * 0.1), 0))
				states.append(ribbon.positions.duplicate())
			print("[paper-cpu] ribbon length=%.2f n=%d contact=%s total=%.3f contact=%.3f self=%.3f ms/frame" % [length, ribbon.segments, contact, (Time.get_ticks_usec() - start) / 60000.0, ribbon.contact_us / 60000.0, ribbon.self_us / 60000.0])
	var path := ProjectSettings.globalize_path("res://../build_out/paper-cpu-baseline.bin").simplify_path()
	if OS.get_cmdline_user_args().has("--baseline"):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("[paper-cpu] cannot write baseline: %s" % path)
			quit(1)
			return
		file.store_var(states)
	elif OS.get_cmdline_user_args().has("--compare"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			print("[paper-cpu] run with --baseline first: %s" % path)
			quit(1)
			return
		var baseline: Array = file.get_var()
		if states.size() != baseline.size():
			print("[paper-cpu] snapshot count changed: %d versus baseline %d" % [states.size(), baseline.size()])
			quit(1)
			return
		if states != baseline:
			var changed := 0
			for i in states.size():
				changed += int(states[i] != baseline[i])
			print("[paper-cpu] FAIL %d of %d snapshots changed" % [changed, states.size()])
			quit(1)
			return
		print("[paper-cpu] all %d snapshots match exactly" % states.size())
	quit()
