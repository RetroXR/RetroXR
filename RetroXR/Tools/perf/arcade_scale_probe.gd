## What N arcade cabinets cost: frame time, renderer counters, CPU per thread, and for
## each running core its own pacing. WINDOWED, never --headless (the dummy renderer has no GPU
## time and draws nothing), and ONE core per process (CLAUDE.md: never loop cores in a process).
##
##   "$godot" --path RetroXR --resolution 1280x720 --position 20,20 \
##       res://Tools/perf/arcade_scale_probe.tscn -- --n=4 --state=on --core=fbneo \
##       --rom=$HOME/retroxr/roms/mame/dino.zip
##
## --n=0..8        cabinets in a row (0 = the stage alone, the baseline)
## --state=off|on  off: scenes only, nothing powered. on: a board seated and a core running
## --core=         pins the core (fbneo | mame); --rom= the romset zip; --model= another cabinet
## --lights=room|min   room: a directional and four omnis, all casting shadows (as the room has)
## --view=all|away     away: the camera looks the other way, so nothing is drawn but everything runs
## --shadows=on|off    off: cast_shadow OFF on every mesh of the cabinets (diagnostic A/B)
## --interior=shown|hidden   hidden: the bay unit (and the board in it) is not drawn
## --glass=on|off      off: the Glass quad over the tube is not drawn
## --seconds=8 --windows=3 --warmup=6   measured windows; the result is the median of the windows
## --lid=closed|open  with --state=on the door is shut again after the board is seated (as in play)
## --mute=video       tell every core nothing shows its picture (Libretro.SetVideoMuted): what a cabinet
##                     out of view could save. Needs a libretro-godot built with it.
## --nogame        with --state=on, do not press coin/START (the core stays on its attract screen)
##
## XENU_UNTHROTTLED=1 in the environment removes the cores' frame ceiling and audio brake, so the
## fps each prints is what the core COSTS (a paced run reads 60 either way).
## The result line is `[arcade_perf] RESULT {json}`; exit 0, 1 on a failed load or a core that
## never ran, 2 on the safety timer.
extends Node3D

const Common := preload("res://Tools/perf/arcade_perf_common.gd")

var _a: Dictionary = {}
var _failed: Array[String] = []
var _systems: Array[RetroSystem] = []
var _vp: SubViewport


func _ready() -> void:
	_a = Common.parse_args()
	var n := int(_a.get("n", 1))
	var on := str(_a.get("state", "off")) == "on"
	var rom := str(_a.get("rom", ""))
	var core := str(_a.get("core", ""))
	var seconds := maxf(float(_a.get("seconds", 8.0)), 1.0)
	var windows := maxi(int(_a.get("windows", 3)), 1)
	var warmup := maxf(float(_a.get("warmup", 6.0)), 0.0)
	if on and (rom.is_empty() or not FileAccess.file_exists(rom)):
		print("[arcade_perf] --state=on needs --rom=<an existing romset zip>")
		get_tree().quit(1)
		return
	get_tree().create_timer(warmup + seconds * windows + 90.0 + 25.0 * n).timeout.connect(func() -> void:
		print("[arcade_perf] TIMED OUT")
		get_tree().quit(2))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	# What the panel would do to every measurement: lock the frame rate to the display.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# The scene is drawn into a viewport of its own: the window's own GPU time is mostly the wait
	# for the compositor (it read about half the frame whatever the scene held), a viewport's is not.
	_vp = SubViewport.new()
	var size_arg := str(_a.get("size", "1280x720")).split("x")
	_vp.size = Vector2i(int(size_arg[0]), int(size_arg[1]))
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.audio_listener_enable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var root_rid := _vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(root_rid, true)

	Common.build_stage(_vp, str(_a.get("lights", "room")), str(_a.get("view", "all")) == "away", n)
	var model_id := str(_a.get("model", "arcade_cabinet_generic"))
	for i in n:
		_systems.append(Common.spawn_cabinet(_vp, i, n, model_id, core, rom))
	for i in 8:
		await get_tree().process_frame
	if on:
		for sys in _systems:
			await Common.seat_board(_vp, sys, rom)
	if on and str(_a.get("lid", "closed")) == "closed":
		for sys in _systems:
			(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(0.0)
		for i in 20:
			await get_tree().process_frame
	_apply_diagnostics()
	if on:
		for sys in _systems:
			var lib := sys.get_libretro_node()
			lib.connect("content_load_failed", func(reason: String) -> void:
				_failed.append(reason.replace("\n", " | "))
				print("[arcade_perf] content_load_failed: ", reason.replace("\n", " | ")))
			# Cores initialising together is what broke the PS2 six-console run: stagger them.
			sys.power_on()
			for i in 45:
				await get_tree().process_frame
		if not _failed.is_empty():
			print("[arcade_perf] RESULT ", JSON.stringify({"n": n, "failed": _failed}))
			get_tree().quit(1)
			return
	print("[arcade_perf] staged n=%d state=%s core=%s meshes=%d" % [n, "on" if on else "off", core, Common.count_meshes(_vp)])
	print("[arcade_perf] display window=%s viewport=%s msaa3d=%d scale3d=%.2f vsync=%d refresh=%.1fHz screen_scale=%.2f adapter=%s" % [
		str(DisplayServer.window_get_size()), str(get_viewport().get_visible_rect().size), get_viewport().msaa_3d,
		get_viewport().scaling_3d_scale, DisplayServer.window_get_vsync_mode(), DisplayServer.screen_get_refresh_rate(),
		DisplayServer.screen_get_scale(), RenderingServer.get_video_adapter_name()])
	if on and not _a.has("nogame"):
		for sys in _systems:
			Common.coin_and_start(sys)
		await get_tree().create_timer(1.0).timeout
		for sys in _systems:
			Input.action_press("RETRO_JOYPAD_START")
		await get_tree().create_timer(0.3).timeout
		Input.action_release("RETRO_JOYPAD_START")
	if on and str(_a.get("mute", "off")) == "video":
		for sys in _systems:
			if not sys.get_libretro_node().has_method("SetVideoMuted"):
				print("[arcade_perf] this libretro-godot has no SetVideoMuted; --mute=video does nothing")
				break
			sys.get_libretro_node().call("SetVideoMuted", true)
	await get_tree().create_timer(warmup).timeout

	if on:
		for sys in _systems:
			sys.get_libretro_node().call("SetVideoTransferProfiling", true)
	var results: Array[Dictionary] = []
	for w in windows:
		results.append(await _measure(seconds, root_rid))
		var r: Dictionary = results[w]
		print("[arcade_perf] window %d  %s" % [w, JSON.stringify(r)])
	var summary := _summarise(results)
	summary["n"] = n
	summary["state"] = "on" if on else "off"
	summary["core"] = core
	summary["args"] = _a
	summary["unthrottled"] = OS.has_environment("XENU_UNTHROTTLED")
	summary["failed"] = _failed
	print("[arcade_perf] RESULT ", JSON.stringify(summary))
	var ok := _failed.is_empty()
	if on:
		for r in results:
			for m: Dictionary in r.get("machines", []):
				if float(m["fps"]) <= 0.0:
					ok = false
	for sys in _systems:
		if is_instance_valid(sys) and sys.is_powered_on:
			sys.power_off()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if ok else 1)


func _apply_diagnostics() -> void:
	for sys in _systems:
		if str(_a.get("shadows", "on")) == "off":
			Common.set_shadows(sys, false)
			var bay: ArcadeBayUnit = sys.get_bay()
			if bay != null:
				Common.set_shadows(bay, false)
			for c in _vp.get_children():
				if c is RetroCartridge:
					Common.set_shadows(c, false)
		if str(_a.get("interior", "shown")) == "hidden":
			var bay2: ArcadeBayUnit = sys.get_bay()
			if bay2 != null:
				bay2.visible = false
		if str(_a.get("glass", "on")) == "off":
			var glass := sys.find_child("Glass", true, false) as Node3D
			if glass != null:
				glass.visible = false


## One window: per-frame times, the renderer's own measure, threads, and each core's pacing.
func _measure(seconds: float, root_rid: RID) -> Dictionary:
	var frame_ms := PackedFloat64Array()
	var gpu_sum := 0.0
	var cpu_sum := 0.0
	var samples := 0
	var threads_before := Common.thread_cpu()
	var sys_before := Common.system_ticks()
	var pace_before: Array[Dictionary] = []
	var xfer_before: Array[Dictionary] = []
	for sys in _systems:
		if sys.is_powered_on:
			var lib := sys.get_libretro_node()
			pace_before.append(Common.pacing(lib))
			xfer_before.append(lib.call("GetVideoTransferStats"))
	var t0 := Time.get_ticks_usec()
	var last := t0
	var hw_last := t0
	var mhz_sum := 0.0
	var mhz_n := 0
	var temp_max := 0.0
	while float(Time.get_ticks_usec() - t0) < seconds * 1.0e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if now - hw_last > 400000:
			# The integrated GPU's clock moves with the package's power and heat: a window's gpu_ms
			# means nothing without the clock it ran at, so it is sampled through the window.
			hw_last = now
			var hw := Common.hw_state()
			if float(hw["gpu_mhz"]) > 0.0:
				mhz_sum += float(hw["gpu_mhz"])
				mhz_n += 1
			temp_max = maxf(temp_max, float(hw["pkg_temp_c"]))
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(root_rid)
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(root_rid)
		samples += 1
	var elapsed := float(Time.get_ticks_usec() - t0) / 1.0e6
	var out: Dictionary = Common.frame_stats(frame_ms)
	out["gpu_ms"] = snappedf(gpu_sum / maxf(samples, 1), 0.01)
	out["render_cpu_ms"] = snappedf(cpu_sum / maxf(samples, 1), 0.01)
	var threads_after := Common.thread_cpu()
	var threads := Common.thread_cpu_delta(threads_before, threads_after, elapsed)
	# The main thread is the one whose tid is the pid: its CPU per frame is what the frame costs it,
	# not what it waited for (the window's frame rate is paced by the compositor).
	var pid := OS.get_process_id()
	if threads_after.has(pid) and threads_before.has(pid):
		out["main_cpu_ms_per_frame"] = snappedf(float(int((threads_after[pid] as Dictionary)["ticks"]) - int((threads_before[pid] as Dictionary)["ticks"])) * 10.0 / maxf(samples, 1), 0.01)
	out["threads_top"] = threads
	out["hw"] = Common.hw_state()
	out["gpu_mhz_avg"] = snappedf(mhz_sum / maxf(mhz_n, 1), 1.0)
	out["pkg_temp_max_c"] = temp_max
	# GPU time at the clock it ran at: millions of cycles a frame, comparable across windows.
	out["gpu_mcycles"] = snappedf(float(out["gpu_ms"]) * float(out["gpu_mhz_avg"]) / 1000.0, 0.01)
	# What ELSE the machine was doing: a browser, a transcoder... any of it moves every number here.
	out["own_cores_busy"] = Common.own_cores_busy(threads_before, threads_after, elapsed)
	out["system_cores_busy"] = Common.system_cores_busy(sys_before, Common.system_ticks())
	out["other_cores_busy"] = snappedf(maxf(float(out["system_cores_busy"]) - float(out["own_cores_busy"]), 0.0), 0.1)
	out["cpu_total_pct"] = Common.total_cpu(threads)
	out["engine"] = Common.engine_counters()
	out["memory"] = Common.process_memory()
	var machines: Array[Dictionary] = []
	var tex_ms := 0.0
	var k := 0
	for sys in _systems:
		if not sys.is_powered_on:
			continue
		var lib := sys.get_libretro_node()
		var d: Dictionary = Common.pacing_delta(pace_before[k], Common.pacing(lib), elapsed)
		var xa: Dictionary = xfer_before[k]
		var xb: Dictionary = lib.call("GetVideoTransferStats")
		tex_ms += float((xb.get("texture_update", {}) as Dictionary).get("total_ms", 0.0)) \
			- float((xa.get("texture_update", {}) as Dictionary).get("total_ms", 0.0))
		machines.append(d)
		k += 1
	out["machines"] = machines
	out["texture_update_ms_per_s"] = snappedf(tex_ms / maxf(elapsed, 0.001), 0.01)
	out["seconds"] = snappedf(elapsed, 0.1)
	return out


## The median across windows of each headline number.
func _summarise(results: Array[Dictionary]) -> Dictionary:
	var keys := ["avg_ms", "median_ms", "p95_ms", "p99_ms", "worst_ms", "fps", "gpu_ms", "render_cpu_ms",
		"cpu_total_pct", "texture_update_ms_per_s", "main_cpu_ms_per_frame", "own_cores_busy", "other_cores_busy", "gpu_mhz_avg", "gpu_mcycles", "pkg_temp_max_c"]
	var out: Dictionary = {}
	for k in keys:
		var v := PackedFloat64Array()
		for r in results:
			v.append(float(r.get(k, 0.0)))
		v.sort()
		out[k] = v[v.size() / 2]
	var last: Dictionary = results.back()
	out["engine"] = last["engine"]
	out["hw"] = last["hw"]
	out["memory"] = last["memory"]
	out["threads_top"] = last["threads_top"]
	# Per machine: the median of its own fps and ms inside retro_run.
	var machines: Array = []
	var count := (last["machines"] as Array).size()
	for i in count:
		var fps := PackedFloat64Array()
		var run := PackedFloat64Array()
		var worst := 0.0
		var sink := 0
		for r in results:
			var m: Dictionary = (r["machines"] as Array)[i]
			fps.append(float(m["fps"]))
			run.append(float(m["run_ms_per_frame"]))
			worst = maxf(worst, float(m["run_worst_ms"]))
			sink = int(m["sink"])
		fps.sort()
		run.sort()
		machines.append({"fps": fps[fps.size() / 2], "run_ms_per_frame": run[run.size() / 2],
			"run_worst_ms": worst, "sink": sink})
	out["machines"] = machines
	return out
