## Does a cabinet get slower the longer a game runs? Plays a romset (Cadillacs by default) for
## minutes with a scripted player, samples every few seconds, and says which series GROW.
## WINDOWED, never --headless; ONE core per process.
##
##   "$godot" --path RetroXR --resolution 640x360 --position 20,20 \
##       res://Tools/perf/arcade_soak_probe.tscn -- --core=fbneo --rom=$HOME/retroxr/roms/mame/dino.zip \
##       --minutes=10 [--n=4] [--interval=5]
##
## The player: a coin and START at the start, then RIGHT held and the attack button mashed at 6 Hz, a
## jump now and then, another coin every 40 s and a START tap every 23 s (so a continue is taken). It
## cannot see the game, so it does not know when it reaches the boss: the CSV is by time, and the
## screen is a picture the user can check (`--shots=<dir>` saves a PNG of the viewport each minute).
##
## One CSV row per interval in user://logs/arcade_soak.csv (flushed per row, so it can be read while
## it runs): the room's frame time, each core's fps and ms inside retro_run (and the worst call), CPU
## of the main thread and of all threads, RSS, the engine's node / object / resource counts, and how
## fast godot.log grows (a core logging every frame shows there).
##
## At the end `[soak] RESULT {json}` says, per series, the mean of the first and the last third of the
## run and the slope per minute, and `grows` when the last third is more than 10% above the first
## (and by more than a floor): a number that grows with retro_run flat is OURS (a leak, churn, a
## log), one that grows with it is the core's own cost on that part of the game.
##
## XENU_UNTHROTTLED=1 removes the cores' frame ceiling: retro_run then shows its true cost and the
## fps shows the margin left on the boss. XENU_PACE_TRACE=1 adds the room's own once-a-second trace.
extends Node3D

const Common := preload("res://Tools/perf/arcade_perf_common.gd")
const CSV_PATH := "user://logs/arcade_soak.csv"
const LOG_PATH := "user://logs/godot.log"

var _a: Dictionary = {}
var _vp: SubViewport
var _systems: Array[RetroSystem] = []
var _failed: Array[String] = []
var _series: Dictionary = {}     # name -> PackedFloat64Array, one value per sample
var _times := PackedFloat64Array()
var _csv: FileAccess = null


func _ready() -> void:
	_a = Common.parse_args()
	var n := int(_a.get("n", 1))
	var rom := str(_a.get("rom", ""))
	var core := str(_a.get("core", "fbneo"))
	var minutes := float(_a.get("minutes", 10.0))
	var interval := maxf(float(_a.get("interval", 5.0)), 1.0)
	var shots := str(_a.get("shots", ""))
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[soak] pass --rom=<an existing romset zip>")
		get_tree().quit(1)
		return
	get_tree().create_timer(minutes * 60.0 + 120.0 + 25.0 * n).timeout.connect(func() -> void:
		print("[soak] TIMED OUT")
		get_tree().quit(2))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp = SubViewport.new()
	var size_arg := str(_a.get("size", "1280x720")).split("x")
	_vp.size = Vector2i(int(size_arg[0]), int(size_arg[1]))
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.audio_listener_enable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var vp_rid := _vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	Common.build_stage(_vp, str(_a.get("lights", "room")), false, n)
	var model_id := str(_a.get("model", "arcade_cabinet_generic"))
	for i in n:
		_systems.append(Common.spawn_cabinet(_vp, i, n, model_id, core, rom))
	for i in 8:
		await get_tree().process_frame
	for sys in _systems:
		await Common.seat_board(_vp, sys, rom)
	if str(_a.get("lid", "closed")) == "closed":
		for sys in _systems:
			(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(0.0)
		for i in 20:
			await get_tree().process_frame
	for sys in _systems:
		sys.get_libretro_node().connect("content_load_failed", func(reason: String) -> void:
			_failed.append(reason.replace("\n", " | "))
			print("[soak] content_load_failed: ", reason.replace("\n", " | ")))
		sys.power_on()
		for i in 45:
			await get_tree().process_frame
	if not _failed.is_empty():
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	_csv = FileAccess.open(CSV_PATH, FileAccess.WRITE)
	_csv.store_line("t_s,fps,frame_p95_ms,gpu_ms,main_cpu_ms_per_frame,cpu_total_pct,machines_fps,machines_run_ms,machines_worst_ms,sink_pct,rss_mb,threads,nodes,orphans,objects,resources,static_mb,log_kb_per_s,textures_vram_mb,other_cores_busy,gpu_mhz,pkg_temp_c,cpu_mhz")
	print("[soak] %d x %s on %s for %.1f min, sampling every %.0f s, csv=%s" % [n, rom.get_file(), core, minutes, interval, ProjectSettings.globalize_path(CSV_PATH)])

	for sys in _systems:
		Common.attach_panel(sys)
		Common.insert_coin(sys)
	await get_tree().create_timer(1.0).timeout

	var t_start := Time.get_ticks_usec()
	var window_start := t_start
	var frame_ms := PackedFloat64Array()
	var gpu_sum := 0.0
	var gpu_n := 0
	var last_frame := t_start
	var pace_prev: Array[Dictionary] = []
	for sys in _systems:
		pace_prev.append(Common.pacing(sys.get_libretro_node()))
	var threads_prev := Common.thread_cpu()
	var sys_prev := Common.system_ticks()
	var log_prev := _log_bytes()
	# A coin (the SELECT bit) and START close together is a chord some cores read as the service /
	# test switch: the first run of this probe sat in Cadillacs' I/O TEST screen for nine minutes. Keep
	# the two at least 2.5 s apart for the whole run.
	var next_coin := 15.0
	var next_start := 6.5
	var shot_every := float(_a.get("shot_every", 60.0))
	var next_shot := shot_every
	while true:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last_frame) / 1000.0)
		last_frame = now
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		gpu_n += 1
		var t := float(now - t_start) / 1.0e6
		_drive(t)
		if t >= next_start:
			Input.action_press("RETRO_JOYPAD_START")
			get_tree().create_timer(0.25).timeout.connect(func() -> void: Input.action_release("RETRO_JOYPAD_START"))
			next_start += 23.0
		if t >= next_coin:
			for sys in _systems:
				Common.insert_coin(sys)
			next_coin += 40.0
		if not shots.is_empty() and t >= next_shot:
			next_shot += shot_every
			await RenderingServer.frame_post_draw
			var img := _vp.get_texture().get_image()
			img.save_png("%s/soak_%03d.png" % [shots, int(t)])
		var window := float(now - window_start) / 1.0e6
		if window >= interval:
			var threads_now := Common.thread_cpu()
			var threads := Common.thread_cpu_delta(threads_prev, threads_now, window)
			var pid := OS.get_process_id()
			var main_ms := 0.0
			if threads_now.has(pid) and threads_prev.has(pid):
				main_ms = float(int((threads_now[pid] as Dictionary)["ticks"]) - int((threads_prev[pid] as Dictionary)["ticks"])) * 10.0 / maxf(frame_ms.size(), 1)
			var fs := Common.frame_stats(frame_ms)
			var fps_l := PackedStringArray()
			var run_l := PackedStringArray()
			var worst_l := PackedStringArray()
			var run_avg := 0.0
			var fps_avg := 0.0
			var worst_max := 0.0
			var sink := 0
			for i in _systems.size():
				var cur := Common.pacing(_systems[i].get_libretro_node())
				var d := Common.pacing_delta(pace_prev[i], cur, window)
				pace_prev[i] = cur
				fps_l.append("%.0f" % d["fps"])
				run_l.append("%.2f" % d["run_ms_per_frame"])
				worst_l.append("%.0f" % d["run_worst_ms"])
				run_avg += float(d["run_ms_per_frame"]) / _systems.size()
				fps_avg += float(d["fps"]) / _systems.size()
				worst_max = maxf(worst_max, float(d["run_worst_ms"]))
				sink = maxi(sink, int(d["sink"]))
			var mem := Common.process_memory()
			var eng := Common.engine_counters()
			var log_now := _log_bytes()
			var log_kb := float(log_now - log_prev) / 1024.0 / window
			log_prev = log_now
			var gpu := gpu_sum / maxf(gpu_n, 1)
			var other := maxf(Common.system_cores_busy(sys_prev, Common.system_ticks()) - Common.own_cores_busy(threads_prev, threads_now, window), 0.0)
			var hw := Common.hw_state()
			var row := [t, fs["fps"], fs["p95_ms"], gpu, main_ms, Common.total_cpu(threads), "/".join(fps_l), "/".join(run_l),
				"/".join(worst_l), sink, mem["rss_mb"], mem["threads"], eng["nodes"], eng["orphans"], eng["objects"],
				eng["resources"], eng["static_mb"], log_kb, eng["vram_mb"], other, hw["gpu_mhz"], hw["pkg_temp_c"], hw["cpu_mhz"]]
			_csv.store_line(",".join(row.map(func(v: Variant) -> String: return "%.2f" % v if v is float else str(v))))
			_csv.flush()
			print("[soak] t=%4.0fs fps %5.1f p95 %5.1fms core %s fps run %s ms (worst %s) cpu %.0f%% main %.1fms rss %.0fMB nodes %d obj %d log %.1fKB/s others %.1f cores | gpu %.0f MHz, %.0f C, cpu %.0f MHz" % [
				t, fs["fps"], fs["p95_ms"], "/".join(fps_l), "/".join(run_l), "/".join(worst_l), Common.total_cpu(threads),
				main_ms, mem["rss_mb"], eng["nodes"], eng["objects"], log_kb, other, hw["gpu_mhz"], hw["pkg_temp_c"], hw["cpu_mhz"]])
			_push("fps", fs["fps"])
			_push("frame_p95_ms", fs["p95_ms"])
			_push("retro_run_ms", run_avg)
			_push("core_fps", fps_avg)
			_push("worst_call_ms", worst_max)
			_push("main_cpu_ms", main_ms)
			_push("cpu_total_pct", Common.total_cpu(threads))
			_push("rss_mb", mem["rss_mb"])
			_push("nodes", eng["nodes"])
			_push("objects", eng["objects"])
			_push("resources", eng["resources"])
			_push("static_mb", eng["static_mb"])
			_push("log_kb_per_s", log_kb)
			_push("gpu_ms", gpu)
			_push("other_cores_busy", other)
			_push("gpu_mhz", hw["gpu_mhz"])
			_push("pkg_temp_c", hw["pkg_temp_c"])
			_times.append(t)
			frame_ms.clear()
			gpu_sum = 0.0
			gpu_n = 0
			window_start = now
			threads_prev = threads_now
			sys_prev = Common.system_ticks()
		if t >= minutes * 60.0:
			break
	_release_keys()
	var result := _verdict()
	result["args"] = _a
	result["unthrottled"] = OS.has_environment("XENU_UNTHROTTLED")
	print("[soak] RESULT ", JSON.stringify(result))
	for sys in _systems:
		if is_instance_valid(sys) and sys.is_powered_on:
			sys.power_off()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)


func _push(key: String, v: float) -> void:
	if not _series.has(key):
		_series[key] = PackedFloat64Array()
	(_series[key] as PackedFloat64Array).append(v)


func _log_bytes() -> int:
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	return int(f.get_length()) if f != null else 0


## The scripted player: RIGHT held, the attack button mashed at 6 Hz, a jump now and then.
func _drive(t: float) -> void:
	_hold("RETRO_JOYPAD_RIGHT", true)
	_hold("RETRO_JOYPAD_B", int(t * 12.0) % 2 == 0)
	_hold("RETRO_JOYPAD_A", int(t * 2.0) % 7 == 0 and fmod(t * 2.0, 1.0) < 0.3)


func _hold(action: StringName, down: bool) -> void:
	if not InputMap.has_action(action):
		return
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_keys() -> void:
	for a in ["RETRO_JOYPAD_RIGHT", "RETRO_JOYPAD_B", "RETRO_JOYPAD_A", "RETRO_JOYPAD_START"]:
		if InputMap.has_action(a):
			Input.action_release(a)


## Per series: mean of the first third, mean of the last third, slope per minute, and `grows`.
## The floors keep a series that moves by noise from being called a trend.
func _verdict() -> Dictionary:
	var floors := {"fps": 3.0, "frame_p95_ms": 2.0, "retro_run_ms": 0.3, "core_fps": 3.0, "worst_call_ms": 3.0,
		"main_cpu_ms": 0.5, "cpu_total_pct": 8.0, "rss_mb": 30.0, "nodes": 20.0, "objects": 200.0,
		"resources": 50.0, "static_mb": 5.0, "log_kb_per_s": 1.0, "gpu_ms": 1.0, "other_cores_busy": 1.0, "gpu_mhz": 100.0, "pkg_temp_c": 4.0}
	# fps and core_fps falling is the harm; every other series rising is.
	var falling := ["fps", "core_fps", "gpu_mhz"]
	var per_series: Dictionary = {}
	var out := {"samples": _times.size(), "series": per_series}
	for key: String in _series:
		var v: PackedFloat64Array = _series[key]
		var n := v.size()
		if n < 6:
			continue
		var third := n / 3
		var first := 0.0
		var last := 0.0
		for i in third:
			first += v[i] / third
			last += v[n - 1 - i] / third
		var per_min := Common.slope(_times, v) * 60.0
		var delta := last - first
		var grows := false
		if key in falling:
			grows = -delta > float(floors[key]) and -delta > 0.10 * absf(first)
		else:
			grows = delta > float(floors[key]) and delta > 0.10 * absf(first)
		per_series[key] = {"first_third": snappedf(first, 0.01), "last_third": snappedf(last, 0.01),
			"per_min": snappedf(per_min, 0.01), "worse": grows}
	return out
