## Shared by arcade_scale_probe and arcade_soak_probe: the stage, N cabinets, and the
## readings (per-thread CPU and RSS from /proc, a core's pacing, the renderer's counters).
## Preloaded by path, deliberately no class_name (nothing to regenerate in the class cache).
extends RefCounted

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

## Distance between two cabinets' centres, in metres: a row of arcade cabinets in a room.
const SPACING := 1.1


static func parse_args() -> Dictionary:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			if arg.contains("="):
				args[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
			else:
				args[arg.trim_prefix("--")] = "true"
	return args


# ── the stage ───────────────────────────────────────────────────────────────────

## A floor, an environment, a camera, and (lights = "room") the ceiling lights the real room
## has: shadow-casting omnis and a directional, which is what every arcade mesh is drawn into.
static func build_stage(host: Node, lights: String, looking_away: bool, count: int) -> Camera3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.62)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	host.add_child(we)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 1.6, 2.2)
	fill.omni_range = 6.0
	fill.light_energy = 0.6
	host.add_child(fill)
	if lights == "room":
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 35, 0)
		sun.light_energy = 0.6
		sun.shadow_enabled = true
		host.add_child(sun)
		for i in 4:
			var o := OmniLight3D.new()
			o.position = Vector3((i - 1.5) * 2.0, 2.6, 0.5 + (i % 2) * 1.5)
			o.omni_range = 8.0
			o.light_energy = 0.9
			o.shadow_enabled = true
			host.add_child(o)
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(14, 0.02, 10)
	floor_mesh.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.30, 0.34)
	floor_mesh.material_override = fmat
	floor_mesh.position.y = -0.01
	host.add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 70.0
	host.add_child(cam)
	cam.current = true
	var back := 2.2 + 0.5 * float(count)
	cam.position = Vector3(0.0, 1.35, back)
	var target := Vector3(0.0, 0.9, 0.0)
	if looking_away:
		target = Vector3(0.0, 1.35, back + 5.0)
	cam.look_at(target, Vector3.UP)
	return cam


# ── cabinets ────────────────────────────────────────────────────────────────────

## One cabinet, in a row, frozen, with its board seated when `rom` is given. Not powered.
static func spawn_cabinet(host: Node, index: int, count: int, model_id: String, core: String, rom: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = "arcade"
	sys.freeze = true
	if not core.is_empty():
		sys.core_name = core
	sys.position = Vector3((float(index) - float(count - 1) * 0.5) * SPACING, 0.0, 0.0)
	host.add_child(sys)
	return sys


## Opens the lid and seats a board. Awaits frames, so it is a coroutine.
static func seat_board(host: Node, sys: RetroSystem, rom: String) -> void:
	var tree := host.get_tree()
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = rom
	cart.freeze = true
	cart.position = sys.position + Vector3(0, 3, 0)
	host.add_child(cart)
	for i in 8:
		await tree.process_frame
	var bay: ArcadeBayUnit = sys.get_bay()
	var slot: XRToolsSnapZone = bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone
	slot.pick_up_object(cart)
	for i in 6:
		await tree.process_frame


## A coin, then START held a moment, from the cabinet's own player-0 parts (arcade_load_probe's route).
static func coin_and_start(sys: RetroSystem) -> void:
	var cab := sys.get_model() as RetroSystemModelArcadeCabinet
	for m in cab.modules_of_kind(ArcadeProfiles.KIND_COIN):
		if (m as ArcadeCoinModule).player == 0:
			(m as ArcadeCoinModule).insert_coin()
	for m in cab.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		if (m as ArcadeControlModule).player == 0:
			var grip := (m as ArcadeControlModule).grip()
			grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))


## Just the coin, from the cabinet's player-0 coin door. Safe to repeat.
static func insert_coin(sys: RetroSystem) -> void:
	var cab := sys.get_model() as RetroSystemModelArcadeCabinet
	for m in cab.modules_of_kind(ArcadeProfiles.KIND_COIN):
		if (m as ArcadeCoinModule).player == 0:
			(m as ArcadeCoinModule).insert_coin()


## Attach player 0's panel (a press on it TOGGLES, so this is for once: pressing again lets go, and a
## player who is not attached sends nothing; the first soak run alternated every coin).
static func attach_panel(sys: RetroSystem) -> void:
	var cab := sys.get_model() as RetroSystemModelArcadeCabinet
	for m in cab.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		if (m as ArcadeControlModule).player == 0 and not (m as ArcadeControlModule).is_attached():
			var grip := (m as ArcadeControlModule).grip()
			grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))


## Diagnostic A/B switches, applied by the probe on the nodes (the scenes are untouched).
static func set_shadows(root: Node, on: bool) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n += 1
	return n


static func count_meshes(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()


# ── readings ────────────────────────────────────────────────────────────────────

static func _read_lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		out.append(f.get_line())
	return out


## tid -> {"comm": String, "ticks": utime+stime in clock ticks}. Linux only; empty elsewhere.
static func thread_cpu() -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open("/proc/self/task")
	if d == null:
		return out
	for tid in d.get_directories():
		var stat := _read_lines("/proc/self/task/%s/stat" % tid)
		if stat.is_empty():
			continue
		var line := stat[0]
		var rp := line.rfind(")")
		if rp < 0:
			continue
		var f := line.substr(rp + 2).split(" ")
		if f.size() < 13:
			continue
		var comm := _read_lines("/proc/self/task/%s/comm" % tid)
		out[int(tid)] = {"comm": comm[0] if not comm.is_empty() else "?", "ticks": int(f[11]) + int(f[12])}
	return out


## The busiest threads over a window, as [{tid, comm, cpu}] with cpu in percent of ONE core.
static func thread_cpu_delta(a: Dictionary, b: Dictionary, seconds: float, top: int = 10) -> Array:
	var hz := 100.0
	var rows: Array = []
	for tid: int in b:
		var before: int = int((a.get(tid, {}) as Dictionary).get("ticks", 0)) if a.has(tid) else 0
		var cpu := float(int((b[tid] as Dictionary)["ticks"]) - before) / hz / maxf(seconds, 0.001) * 100.0
		rows.append({"tid": tid, "comm": (b[tid] as Dictionary)["comm"], "cpu": snappedf(cpu, 0.1)})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["cpu"] > y["cpu"])
	return rows.slice(0, top)


## All CPU the machine spent in a window, as busy cores: [busy ticks, total ticks, core count] from /proc/stat.
static func system_ticks() -> Array:
	var lines := _read_lines("/proc/stat")
	if lines.is_empty():
		return [0, 0, 1]
	var f := lines[0].split(" ", false)
	var busy := 0
	var total := 0
	for i in range(1, mini(f.size(), 9)):
		var v := int(f[i])
		total += v
		if i != 4 and i != 5:      # idle and iowait
			busy += v
	var cores := 0
	for l in lines:
		if l.begins_with("cpu") and l.length() > 3 and l[3] >= "0" and l[3] <= "9":
			cores += 1
	return [busy, total, maxi(cores, 1)]


## Cores busy across the whole machine between two system_ticks() readings.
static func system_cores_busy(a: Array, b: Array) -> float:
	var total := int(b[1]) - int(a[1])
	if total <= 0:
		return 0.0
	return snappedf(float(int(b[0]) - int(a[0])) / float(total) * float(b[2]), 0.1)


## Cores THIS process kept busy, summed over every thread (thread_cpu_delta lists only the top few).
static func own_cores_busy(a: Dictionary, b: Dictionary, seconds: float) -> float:
	var ticks := 0
	for tid: int in b:
		ticks += int((b[tid] as Dictionary)["ticks"]) - (int((a[tid] as Dictionary)["ticks"]) if a.has(tid) else 0)
	return snappedf(float(ticks) / 100.0 / maxf(seconds, 0.001), 0.01)


## What the hardware is doing: the integrated GPU's clock (MHz), the package temperature (C) and the
## mean CPU clock (MHz), from /sys. A laptop that is hot or short of package power runs the GPU slower,
## which is what "it lags after a few minutes" can be. Missing counters read -1.
static func hw_state() -> Dictionary:
	var out := {"gpu_mhz": -1.0, "pkg_temp_c": -1.0, "cpu_mhz": -1.0}
	var drm := DirAccess.open("/sys/class/drm")
	if drm != null:
		for card in drm.get_directories():
			var f := _read_lines("/sys/class/drm/%s/gt_act_freq_mhz" % card)
			if not f.is_empty() and f[0].is_valid_int():
				out["gpu_mhz"] = float(f[0])
				break
	var th := DirAccess.open("/sys/class/thermal")
	if th != null:
		for z in th.get_directories():
			var ty := _read_lines("/sys/class/thermal/%s/type" % z)
			if not ty.is_empty() and ty[0] == "x86_pkg_temp":
				var tv := _read_lines("/sys/class/thermal/%s/temp" % z)
				if not tv.is_empty() and tv[0].is_valid_int():
					out["pkg_temp_c"] = float(tv[0]) / 1000.0
				break
	var cpus := DirAccess.open("/sys/devices/system/cpu")
	if cpus != null:
		var sum := 0.0
		var n := 0
		for c in cpus.get_directories():
			if c.begins_with("cpu") and c.substr(3).is_valid_int():
				var fl := _read_lines("/sys/devices/system/cpu/%s/cpufreq/scaling_cur_freq" % c)
				if not fl.is_empty() and fl[0].is_valid_int():
					sum += float(fl[0]) / 1000.0
					n += 1
		if n > 0:
			out["cpu_mhz"] = snappedf(sum / n, 1.0)
	return out


static func total_cpu(rows: Array) -> float:
	var t := 0.0
	for r: Dictionary in rows:
		t += float(r["cpu"])
	return snappedf(t, 0.1)


## VmRSS / VmHWM in MB and the thread count, from /proc/self/status.
static func process_memory() -> Dictionary:
	var out := {"rss_mb": 0.0, "hwm_mb": 0.0, "threads": 0}
	for line in _read_lines("/proc/self/status"):
		if line.begins_with("VmRSS:"):
			out["rss_mb"] = snappedf(float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0, 0.1)
		elif line.begins_with("VmHWM:"):
			out["hwm_mb"] = snappedf(float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0, 0.1)
		elif line.begins_with("Threads:"):
			out["threads"] = int(line.get_slice(":", 1).strip_edges())
	return out


## The renderer's and the engine's counters now.
static func engine_counters() -> Dictionary:
	return {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.1),
		"vram_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"physics_active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"physics_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
	}


## A core's pacing counters now (run_ms and brake_sleep_ms are cumulative; run_worst_ms resets on read).
static func pacing(lib: Libretro) -> Dictionary:
	var p: Dictionary = lib.GetPacingStats()
	return {
		"frames": int(lib.GetFrameCount()),
		"run_ms": float(p.get("run_ms", 0.0)),
		"worst_ms": float(p.get("run_worst_ms", 0.0)),
		"sleep_ms": float(p.get("brake_sleep_ms", 0.0)),
		"sink": int(lib.GetAudioBufferOccupancy()),
	}


## Rates between two pacing readings over `seconds`: fps, ms inside retro_run per frame, ms asleep per second.
static func pacing_delta(a: Dictionary, b: Dictionary, seconds: float) -> Dictionary:
	var frames := int(b["frames"]) - int(a["frames"])
	return {
		"fps": snappedf(float(frames) / maxf(seconds, 0.001), 0.1),
		"run_ms_per_frame": snappedf((float(b["run_ms"]) - float(a["run_ms"])) / maxf(float(frames), 1.0), 0.01),
		"run_worst_ms": snappedf(float(b["worst_ms"]), 0.1),
		"sleep_ms_per_s": snappedf((float(b["sleep_ms"]) - float(a["sleep_ms"])) / maxf(seconds, 0.001), 0.1),
		"sink": int(b["sink"]),
	}


## Median, p95, p99 and worst of a frame-time series in ms.
static func frame_stats(ms: PackedFloat64Array) -> Dictionary:
	if ms.is_empty():
		return {"frames": 0}
	var s := ms.duplicate()
	s.sort()
	var n := s.size()
	var sum := 0.0
	for v in s:
		sum += v
	return {
		"frames": n,
		"avg_ms": snappedf(sum / n, 0.01),
		"median_ms": snappedf(s[n / 2], 0.01),
		"p95_ms": snappedf(s[mini(n - 1, int(n * 0.95))], 0.01),
		"p99_ms": snappedf(s[mini(n - 1, int(n * 0.99))], 0.01),
		"worst_ms": snappedf(s[n - 1], 0.01),
		"fps": snappedf(1000.0 / maxf(sum / n, 0.001), 0.1),
	}


## Least-squares slope of y over x (units of y per unit of x); 0 for fewer than three points.
static func slope(xs: PackedFloat64Array, ys: PackedFloat64Array) -> float:
	var n := mini(xs.size(), ys.size())
	if n < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += xs[i]
		my += ys[i]
	mx /= n
	my /= n
	var num := 0.0
	var den := 0.0
	for i in n:
		num += (xs[i] - mx) * (ys[i] - my)
		den += (xs[i] - mx) * (xs[i] - mx)
	return num / den if den > 0.0 else 0.0
