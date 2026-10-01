## Times what the spawn menu's main thread pays when a download, a RomM sync or
## the scraper reports back — the hitches felt while something is downloading.
##
## menu_perf_probe times opening and searching a platform; this times what lands
## on the menu WHILE it is open (and while it is not): toast ticks, cover art
## arriving, a finished download, a finished core install, the core unzip and
## the gamelist dedupe that runs after every download and scrape.
##
## WINDOWED ONLY. The menu is hosted exactly as player_rig.tscn hosts it — a
## Viewport2Din3D at 2200x1800 with its CurvedPanel — because the toast pop-out
## only exists on that host, and a SubViewport that renders every frame hangs a
## headless run. On a headset, run it as its own package (the probe-only export
## in docs/dev/quest-device.md), where it is the launched scene.
##
## Writes NOTHING into a real data root. On desktop it reads the player's synced
## index for PLATFORM; where there is none (a probe package starts empty) it
## writes a synthetic one of SYNTH_ROWS rows into its own sandbox. The core it
## pretends finished is one whose ROM folders all exist already, so no folder is
## created either. Scratch files go to user://probe_download_ui/ and are removed.
##
## Prints [perf] lines, leaves them in user://perf_result.txt, and quits.
extends Node3D

const PLATFORM := "gba"
## The size of the desktop's real gba index, so the two devices compare.
const SYNTH_ROWS := 3147
const SYNTH_ID_BASE := 900000
## A mid-sized core: genesis_plus_gx is ~5 MB, mupen64plus_next ~12, dolphin 25.
const ZIP_BYTES := 12 * 1024 * 1024
const SCRATCH := "user://probe_download_ui"
const TIMEOUT_SEC := 300.0
## Tried in order; the first whose every ROM folder already exists is used.
const MULTI_SYSTEM_CORES := ["genesis_plus_gx", "picodrive", "mednafen_pce_fast",
	"fceumm", "mgba", "gambatte"]
const TOAST_EMOJI := ["✅", "❌", "⏳", "⬇", "⚠", "🗑", "⏹"]
## The cores installed on the dev Quest 3 on 2026-09-30, stood in for by empty
## files in a probe package's own cores folder (it starts with none), so the
## Manager and Download grids are the size a player's are. Never loaded.
const QUEST_CORES := ["arduous", "atari800", "azahar", "bluemsx", "cap32", "dolphin",
	"dosbox_pure", "fbneo", "fceumm", "flycast", "freechaf", "freeintv", "fuse", "gambatte",
	"gearcoleco", "genesis_plus_gx", "hatari", "mame2003_plus", "mednafen_lynx", "mednafen_ngp",
	"mednafen_pce_fast", "mednafen_pcfx", "mednafen_supergrafx", "mednafen_vb", "mednafen_wswan",
	"melondsds", "mgba", "mupen64plus_next_gles3", "neocd", "np2kai", "o2em", "opera", "pcsx2",
	"pcsx_rearmed", "picodrive", "pokemini", "potator", "ppsspp", "prosystem", "puae", "px68k",
	"quasi88", "scummvm", "snes9x", "stella", "supermodel", "vecx", "vemulator", "vice_x64sc",
	"virtualjaguar", "xemu", "yabasanshiro"]

var _lines: PackedStringArray = PackedStringArray()
var _host: Node3D = null


func _t() -> int:
	return Time.get_ticks_usec()


func _ms(a: int) -> float:
	return float(Time.get_ticks_usec() - a) / 1000.0


func _say(fmt: String, args: Array = []) -> void:
	var s: String = fmt % args if not args.is_empty() else fmt
	_lines.append(s)
	print("[perf] " + s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## p50 / p95 / max of a list of ms samples, as one string.
func _stats(samples: PackedFloat64Array) -> String:
	if samples.is_empty():
		return "no samples"
	var s := samples.duplicate()
	s.sort()
	var p50 := s[s.size() / 2]
	var p95 := s[mini(s.size() - 1, int(s.size() * 0.95))]
	return "p50 %6.2f  p95 %6.2f  max %6.2f ms  (n=%d)" % [p50, p95, s[s.size() - 1], s.size()]


## Wall time of the next `n` frames, each one on its own.
func _frame_times(n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var last := _t()
	for i in n:
		await get_tree().process_frame
		var now := _t()
		out.append(float(now - last) / 1000.0)
		last = now
	return out


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		_say("TIMEOUT")
		_finish(1))
	# Frame times below mean main-thread work, not waiting on the display.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run()


func _run() -> void:
	_say("device=%s  data root=%s", [OS.get_name(), RomLibrary.rom_dir_for_system(PLATFORM)])

	if not RommCatalog.has_index(PLATFORM):
		if OS.has_feature("android"):
			_write_synthetic_index()
		else:
			_say("no %s index on this desktop and none will be written here — sync it first", [PLATFORM])
			_finish(1)
			return

	var menu := await _host_menu()
	if menu == null:
		_say("menu did not instantiate")
		_finish(1)
		return
	var sv: Node = menu.get("_spawn_view")
	var cv: Node = menu.get("_cores_view")
	var toasts: Node = menu.get("_toasts")

	var idle := await _frame_times(120)
	_say("idle frame                       %s", [_stats(idle)])

	await _probe_toasts(menu, toasts)
	await _probe_art(sv)
	await _probe_download_finished(menu, sv)
	await _probe_core_finished(menu, cv)
	await _probe_core_finished_on_cores_tab(menu, cv)
	await _probe_extract(cv)
	_probe_dedupe()

	_say("---- done ----")
	_finish(0)


func _finish(code: int) -> void:
	var f := FileAccess.open("user://perf_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	_remove_tree(SCRATCH)
	get_tree().quit(code)


# ── Setup ─────────────────────────────────────────────────────────────────────

## player_rig.tscn's SpawnMenuViewport, rebuilt: same host, size and panel.
func _host_menu() -> Control:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 1.3)
	add_child(cam)
	cam.make_current()

	var host := (load("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn") \
		as PackedScene).instantiate() as XRToolsViewport2DIn3D
	host.name = "SpawnMenuViewport"
	host.screen_size = Vector2(1.1, 0.9)
	host.scene = load("res://Scenes/UI/spawn_menu.tscn") as PackedScene
	host.viewport_size = Vector2(2200, 1800)
	host.transparent = XRToolsViewport2DIn3D.TransparancyMode.TRANSPARENT
	host.unshaded = true
	var curve := CurvedPanel.new()
	curve.name = "CurvedPanel"
	host.add_child(curve)
	add_child(host)
	_host = host

	var t := _t()
	await _frames(30)
	_say("menu instantiate + first frames  %8.2f ms", [_ms(t)])
	var menu := host.get_scene_instance() as Control
	if menu == null:
		return null
	# Shown the way the controller shows it, minus on_menu_shown(): that asks the
	# RomM server what changed, and a sync landing mid-probe would be measured.
	var sv: Node = menu.get("_spawn_view")
	if sv != null:
		sv.set("_menu_shown", true)
	await _frames(60)
	return menu


## A platform index made the way a sync makes one, from rows shaped like RomM's.
## Only ever called on a device, inside the probe package's own sandbox.
func _write_synthetic_index() -> void:
	var t := _t()
	var dir := RommCatalog.index_dir(PLATFORM)
	DirAccess.make_dir_recursive_absolute(dir)
	var regions := [["USA"], ["Europe"], ["Japan"], ["USA", "Europe"], ["World"]]
	var lines: Dictionary = {}
	for i in SYNTH_ROWS:
		var id := SYNTH_ID_BASE + i
		var title := "Probe Game %04d %s" % [i, ["Adventure", "Racing", "Puzzle", "Quest"][i % 4]]
		var item := {
			"id": id,
			"name": title,
			"name_sort_key": title.to_lower(),
			"fs_name": "%s (%s).gba" % [title, "USA"],
			"fs_extension": "gba",
			"fs_size_bytes": 8388608,
			"regions": regions[i % regions.size()],
			"languages": ["English"],
			"path_cover_small": "",
			"path_cover_large": "",
			"updated_at": "2026-09-01T00:00:00",
		}
		lines[id] = JSON.stringify(RommCatalog._slim_row(item))
	var rows := RommCatalog._rows_from_lines(lines)
	var written := RommCatalog._write_index(dir, rows)
	RommCatalog._write_text(RommCatalog.meta_path(PLATFORM), JSON.stringify({
		"total": int(written["total"]), "shown": int(written["shown"]),
		"updated_after": "", "synced_at": "probe", "platform_id": 0}))
	_say("synthetic %s index: %d rows in %.0f ms  (%s)",
		[PLATFORM, int(written["total"]), _ms(t), str(written["error"])])


# ── 1. Toasts ─────────────────────────────────────────────────────────────────

func _probe_toasts(menu: Node, toasts: Node) -> void:
	menu.call("notify", "probe:warm", "", "warming the pop-out", 0.0)
	await _frames(5)
	var panel: Node = toasts.get("_panel") if toasts != null else null
	_say("toast pop-out: %s", ["present" if is_instance_valid(panel)
		else "MISSING (host is not a Viewport2Din3D) - no arc cost measured"])
	menu.call("notify_clear", "probe:warm")
	await _frames(5)

	# The first sight of each emoji: none of the shipped fonts has them, so the
	# text server falls back to a system font. Timed with the refresh that shapes
	# the icon, which is where the lookup happens.
	for i in TOAST_EMOJI.size():
		var e: String = TOAST_EMOJI[i]
		var t := _t()
		menu.call("notify", "probe:emoji:%d" % i, e, "first sight of an emoji", -1.0)
		if is_instance_valid(panel):
			panel.call("refresh")
		var first := _ms(t)
		menu.call("notify_clear", "probe:emoji:%d" % i)
		t = _t()
		menu.call("notify", "probe:emoji2:%d" % i, e, "second sight of an emoji", -1.0)
		if is_instance_valid(panel):
			panel.call("refresh")
		var again := _ms(t)
		menu.call("notify_clear", "probe:emoji2:%d" % i)
		_say("toast emoji %s  first %7.2f ms   again %6.2f ms", [e, first, again])
	await _frames(5)

	# A core download: the same text every frame, only the bar moves.
	var call_ms := PackedFloat64Array()
	var refresh_ms := PackedFloat64Array()
	for i in 150:
		var t := _t()
		menu.call("notify", "probe:core", "", "Downloading Probe Core  (12 MB)", -1.0 if i == 0 else i / 150.0)
		call_ms.append(_ms(t))
		if is_instance_valid(panel):
			t = _t()
			panel.call("refresh")
			refresh_ms.append(_ms(t))
		await get_tree().process_frame
	_say("toast tick, fixed text  notify   %s", [_stats(call_ms)])
	_say("toast tick, fixed text  refresh  %s   <-- once per tick today", [_stats(refresh_ms)])

	# A RomM download: the bytes move, so the text changes width now and then.
	call_ms = PackedFloat64Array()
	refresh_ms = PackedFloat64Array()
	var total := 734003200
	for i in 150:
		var got := int(float(total) * i / 150.0)
		var t := _t()
		menu.call("notify", "probe:romm", "⬇", "Probe Game · %d%% · %s / %s" % [
			int(100.0 * got / total), String.humanize_size(got), String.humanize_size(total)],
			float(got) / total)
		call_ms.append(_ms(t))
		if is_instance_valid(panel):
			t = _t()
			panel.call("refresh")
			refresh_ms.append(_ms(t))
		await get_tree().process_frame
	_say("toast tick, moving text notify   %s", [_stats(call_ms)])
	_say("toast tick, moving text refresh  %s", [_stats(refresh_ms)])

	# What a frame costs while both tick at once, deferred refreshes included.
	var frames := PackedFloat64Array()
	var last := _t()
	for i in 120:
		var got := int(float(total) * i / 120.0)
		menu.call("notify", "probe:core", "", "Downloading Probe Core  (12 MB)", i / 120.0)
		menu.call("notify", "probe:romm", "⬇", "Probe Game · %d%% · %s / %s" % [
			int(100.0 * got / total), String.humanize_size(got), String.humanize_size(total)],
			float(got) / total)
		await get_tree().process_frame
		var now := _t()
		frames.append(float(now - last) / 1000.0)
		last = now
	_say("frame, two toasts ticking        %s", [_stats(frames)])
	menu.call("notify_clear", "probe:core")
	menu.call("notify_clear", "probe:romm")
	await _frames(10)


# ── 2. Cover art arriving ─────────────────────────────────────────────────────

func _probe_art(sv: Node) -> void:
	var browser: Control = sv.get("_cartridges_browser")
	# On screen, as the player has it: the SPAWN view, on the tab holding the
	# Cartridges browser. A page on a hidden tab is never laid out, so its list
	# binds rows but cannot scroll.
	var menu: Node = sv.get("_menu")
	if menu != null and menu.has_method("_show_spawn_view"):
		menu.call("_show_spawn_view")
	var tabs: TabContainer = sv.get("_spawn_tabs")
	if tabs != null and browser != null:
		for i in tabs.get_tab_count():
			var tab := tabs.get_tab_control(i)
			if tab == browser or tab.is_ancestor_of(browser):
				tabs.current_tab = i
	await _frames(5)
	var t := _t()
	browser.call("open_system", PLATFORM)
	var open_ms := _ms(t)
	await _frames(30)
	var rows: Array = sv.get("_romm_rows")
	_say("open_system(%s)                 %8.2f ms   %d rows", [PLATFORM, open_ms, rows.size()])

	var list: Object = sv.get("_romm_list")
	var catalog: Object = sv.get("romm_catalog")
	var romm_art: Object = sv.get("romm_art")
	var scraped_art: Object = sv.get("scraped_art")
	if list == null or rows.is_empty():
		_say("art: no ROM list open - skipped")
		return

	# The rom ids and art paths of the rows on screen, so a handler that only
	# re-binds rows whose art arrived has something to find.
	var visible: PackedInt32Array = list.call("visible_indices")
	var ids := PackedInt32Array()
	var art_paths := PackedStringArray()
	for i: int in visible:
		if i < 0 or i >= rows.size():
			continue
		var row: Dictionary = rows[i]
		var idx := int(row.get("index", -1))
		if idx >= 0:
			ids.append(int(catalog.call("rom_id_at", idx)))
		var p := str(row.get("path", ""))
		if p.is_empty() and idx >= 0:
			p = str(catalog.call("fs_basename_at", idx))
		art_paths.append(RomLibrary.rom_dir_for_system(PLATFORM).path_join("media/wheel") \
			.path_join(p.get_file().get_basename() + ".png"))
	_say("art: %d rows on screen, %d with a rom id", [visible.size(), ids.size()])

	t = _t()
	list.call("rebind_visible")
	_say("rebind_visible (one full window)  %8.2f ms", [_ms(t)])

	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var per_frame := PackedFloat64Array()
	# The caches' own budgets: 4 covers and 2 scraped images promoted per frame.
	for burst in 12:
		t = _t()
		for k in 4:
			if ids.is_empty():
				break
			romm_art.emit_signal("art_ready", ids[(burst * 4 + k) % ids.size()], tex)
		for k in 2:
			scraped_art.emit_signal("art_ready", art_paths[(burst * 2 + k) % art_paths.size()], tex)
		per_frame.append(_ms(t))
		await get_tree().process_frame
	_say("art: 4 covers + 2 scraped a frame %s   <-- emits only", [_stats(per_frame)])

	per_frame = PackedFloat64Array()
	var last := _t()
	for burst in 12:
		for k in 4:
			if ids.is_empty():
				break
			romm_art.emit_signal("art_ready", ids[(burst * 4 + k) % ids.size()], tex)
		for k in 2:
			scraped_art.emit_signal("art_ready", art_paths[(burst * 2 + k) % art_paths.size()], tex)
		await get_tree().process_frame
		var now := _t()
		per_frame.append(float(now - last) / 1000.0)
		last = now
	_say("art: frame with 6 arrivals        %s   <-- deferred work included", [_stats(per_frame)])
	await _frames(10)

	# Scrolling, one row a step: what binding the rows that came into view costs.
	# It used to re-bind the whole window, the rebind_visible line above.
	var scroll := (list as Control).get_parent() as ScrollContainer
	var node: Node = list as Node
	while scroll == null and node != null:
		node = node.get_parent()
		scroll = node as ScrollContainer
	if scroll != null:
		var steps := PackedFloat64Array()
		for i in 20:
			t = _t()
			scroll.scroll_vertical += 100
			steps.append(_ms(t))
			await get_tree().process_frame
		var window: PackedInt32Array = list.call("visible_indices")
		_say("scroll one row (20 steps)         %s   window now from row %d, scroll %d of %d",
			[_stats(steps), window[0] if not window.is_empty() else -1, scroll.scroll_vertical,
			int(scroll.get_v_scroll_bar().max_value)])


# ── 3. A finished ROM download ────────────────────────────────────────────────

## The two handlers a finished download reaches in one frame: the cache
## manifest's `changed` and the downloader's `finished`. Failed rather than ok so
## nothing is scraped and no row is removed — the rebuilds are the same.
func _probe_download_finished(menu: Node, sv: Node) -> void:
	var cache: Object = sv.get("romm_cache")
	if cache == null:
		_say("download finished: no RomM cache - skipped")
		return
	var open := PackedFloat64Array()
	var hidden := PackedFloat64Array()
	for pass_i in 2:
		var shown := pass_i == 0
		_host.visible = shown
		if shown:
			sv.set("_menu_shown", true)
		else:
			menu.call("on_menu_hidden")
		await _frames(5)
		for i in 5:
			var t := _t()
			cache.emit_signal("changed")
			sv.call("_on_romm_dl_finished", -1, false, "", "probe")
			await get_tree().process_frame
			(open if shown else hidden).append(_ms(t))
			await _frames(3)
	_host.visible = true
	sv.set("_menu_shown", true)
	_say("download finished, menu OPEN     %s   <-- one frame, deferred work included", [_stats(open)])
	_say("download finished, menu HIDDEN   %s", [_stats(hidden)])
	menu.call("notify_clear", "romm:dl:-1")
	await _frames(10)


# ── 4. A finished core install ────────────────────────────────────────────────

func _probe_core_finished(menu: Node, cv: Node) -> void:
	var core := ""
	var sids: Array = []
	for c: String in MULTI_SYSTEM_CORES:
		var info: Variant = (cv.get("core_db") as Object).call("get_by_core_name", c)
		if info == null:
			continue
		var these: Array = CoreInfoDatabase.systemids_of(info)
		if these.is_empty():
			continue
		var all_exist := true
		for sid: String in these:
			if not DirAccess.dir_exists_absolute(RomLibrary.rom_dir_for_system(sid)):
				all_exist = false
		# A probe package may make folders in its own sandbox; a desktop may not.
		if all_exist or OS.has_feature("android"):
			core = c
			sids = these
			break
	if core.is_empty():
		_say("core finished: no candidate core with every ROM folder present - skipped")
		return

	var key := CoreDownloadManager.job_key(core)
	var samples := PackedFloat64Array()
	for i in 3:
		(cv.get("_job_labels") as Dictionary)[key] = "Probe core"
		var t := _t()
		cv.call("_on_core_job_finished", key, true, "")
		var sync_ms := _ms(t)
		await get_tree().process_frame
		samples.append(_ms(t))
		if i == 0:
			_say("core finished (%s, %d systems): synchronous part %8.2f ms", [core, sids.size(), sync_ms])
		await _frames(5)
		menu.call("notify_clear", key)
	_say("core finished, whole frame       %s", [_stats(samples)])
	await _frames(10)

	# What that frame is made of, one part at a time.
	var sv: Node = menu.get("_spawn_view")
	var controls: Node = menu.get("_controls_view")
	for part: Array in [
			[sv, "_populate_systems_tab"], [sv, "_populate_cartridges_tab"],
			[cv, "_populate_manager_tab"], [cv, "refresh_download_systems"],
			[controls, "refresh_platforms"]]:
		var target: Object = part[0]
		if target == null or not target.has_method(part[1]):
			continue
		var t := _t()
		target.call(part[1])
		_say("  core finished part %-26s %8.2f ms", [part[1], _ms(t)])
		await _frames(3)


# ── 5. Unzipping a core ───────────────────────────────────────────────────────

func _probe_extract(cv: Node) -> void:
	var dm: Object = cv.get("download_manager")
	if dm == null:
		_say("extract: no download manager - skipped")
		return
	DirAccess.make_dir_recursive_absolute(SCRATCH.path_join("out"))
	var zip_path := SCRATCH.path_join("core.zip")
	_write_core_like_zip(zip_path, ZIP_BYTES)
	var zipped := FileAccess.get_file_as_bytes(zip_path).size()

	# How a finished download runs it now: a pool task, the frames going on.
	# First, and after the frames have settled, so nothing done earlier in the
	# same frame is counted against it.
	if dm.has_method("_unzip_task"):
		for run in 3:
			await _frames(10)
			var status: Array = [ERR_BUSY]
			var t0 := _t()
			var task := WorkerThreadPool.add_task(
				Callable(dm, "_unzip_task").bind(zip_path, SCRATCH.path_join("out"), status))
			var submit := _ms(t0)
			var frames := PackedFloat64Array()
			var last := _t()
			while not WorkerThreadPool.is_task_completed(task):
				await get_tree().process_frame
				var now := _t()
				frames.append(float(now - last) / 1000.0)
				last = now
			WorkerThreadPool.wait_for_task_completion(task)
			_say("extract on the pool: submit %.2f ms, frames meanwhile %s", [submit, _stats(frames)])
	await _frames(10)

	var t := _t()
	var err: int = dm.call("_extract_zip", zip_path, SCRATCH.path_join("out"))
	_say("extract %d MB core (%.1f MB zipped)  %8.2f ms  err=%d  <-- the unzip itself, inline",
		[ZIP_BYTES / 1048576, zipped / 1048576.0, _ms(t), err])

	# A real one where a desktop has it lying about (a dolphin build, 25 MB).
	if FileAccess.file_exists("user://probe_core.zip"):
		t = _t()
		err = dm.call("_extract_zip", "user://probe_core.zip", SCRATCH.path_join("out"))
		_say("extract user://probe_core.zip     %8.2f ms  err=%d", [_ms(t), err])


## Compresses about 2:1, like a shared library: runs of random bytes between
## runs of repetitive ones.
func _write_core_like_zip(path: String, size: int) -> void:
	var noise := Crypto.new().generate_random_bytes(size / 2)
	var filler := PackedByteArray()
	while filler.size() < 8192:
		filler.append_array("mov r0, r1; ldr r2, [r3, #4]; bl 0x0040; ".to_utf8_buffer())
	var payload := PackedByteArray()
	var n := 0
	# Half noise, half repetition, per 8 KB: deflate gets roughly 2:1 out of it.
	while payload.size() < size:
		payload.append_array(noise.slice(n, n + 4096))
		payload.append_array(filler.slice(0, 4096))
		n = (n + 4096) % maxi(1, noise.size() - 4096)
	payload.resize(size)
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("probe_libretro_android.so")
	zip.write_file(payload)
	zip.close_file()
	zip.close()


# ── 6. The gamelist dedupe ────────────────────────────────────────────────────

## Runs inside every finished download (_merge_gamelist) and every finished
## scrape (_write_result), on the main thread. Fed from memory, never disk.
func _probe_dedupe() -> void:
	for n: int in [100, 1000, 3000]:
		var gm := GamelistManager.new()
		(gm.get("_gamelists") as Dictionary)["probe"] = {"games": _synthetic_games(n)}
		var t := _t()
		var removed := gm.dedupe("probe")
		_say("dedupe %4d games               %8.2f ms   (%d folded)", [n, _ms(t), removed])


## `n` games of one or two ROMs each; every 50th repeats an earlier game's ROM,
## as a list split by an older add_or_merge_rom does.
func _synthetic_games(n: int) -> Array:
	var games: Array = []
	for i in n:
		var roms: Array = [{"path": "./Probe Game %04d (USA).gba" % i, "preferred": true}]
		if i % 3 == 0:
			roms.append({"path": "./Probe Game %04d (Europe).gba" % i})
		if i > 0 and i % 50 == 0:
			roms.append({"path": "./Probe Game %04d (USA).gba" % (i / 2)})
		games.append({"game_id": "ss:%d" % i, "name": "Probe Game %04d" % i, "roms": roms})
	return games


# ── Helpers ───────────────────────────────────────────────────────────────────

func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f: String in d.get_files():
		d.remove(f)
	for sub: String in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ── 4b. A finished core install, as the player sees it ────────────────────────

## On the CORES tab, where a core is downloaded from, with the buildbot listing
## in and a real install's worth of cores on disk. The SPAWN tab's share is owed
## until it is shown; what is left is this view's own grids and buttons.
func _probe_core_finished_on_cores_tab(menu: Node, cv: Node) -> void:
	var cores_dir := CoreDownloadManager.default_cores_dir()
	if OS.has_feature("android"):
		DirAccess.make_dir_recursive_absolute(cores_dir)
		for cn: String in QUEST_CORES:
			var stand_in := cores_dir.path_join(cn + "_libretro_android.so")
			if not FileAccess.file_exists(stand_in):
				var f := FileAccess.open(stand_in, FileAccess.WRITE)
				if f != null:
					f.close()
	var installed := 0
	var d := DirAccess.open(cores_dir)
	if d != null:
		for fn: String in d.get_files():
			if not CoreDownloadManager.core_name_from_lib_filename(fn).is_empty():
				installed += 1

	menu.call("_show_cores_view")
	var dm: Object = cv.get("download_manager")
	var give_up := Time.get_ticks_msec() + 30000
	while (dm.get("available_cores") as Array).is_empty() and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
	cv.call("_populate_manager_tab")
	await _frames(20)
	_say("cores tab: %d cores installed, %d in the buildbot listing",
		[installed, (dm.get("available_cores") as Array).size()])
	if (dm.get("available_cores") as Array).is_empty():
		_say("cores tab: no listing (offline?) - the Download grid is empty, skipped")
		return

	var key := CoreDownloadManager.job_key("genesis_plus_gx")
	var samples := PackedFloat64Array()
	var syncs := PackedFloat64Array()
	for i in 5:
		(cv.get("_job_labels") as Dictionary)[key] = "Probe core"
		var t := _t()
		cv.call("_on_core_job_finished", key, true, "")
		syncs.append(_ms(t))
		await get_tree().process_frame
		samples.append(_ms(t))
		await _frames(5)
		menu.call("notify_clear", key)
		await _frames(5)
	_say("core finished on CORES tab: synchronous part %s", [_stats(syncs)])
	_say("core finished on CORES tab, frame %s", [_stats(samples)])

	# The synchronous part, step by step, in the handler's order.
	var core_db: Object = cv.get("core_db")
	var defaults: Object = cv.get("core_defaults")
	var sids: Array = CoreInfoDatabase.systemids_of(core_db.call("get_by_core_name", "genesis_plus_gx"))
	var ts := _t()
	menu.call("notify", key, "", "Probe core installed", -1.0, 2.5)
	_say("  finish step notify                  %8.2f ms", [_ms(ts)])
	ts = _t()
	cv.call("_refresh_download_button", "genesis_plus_gx")
	_say("  finish step _refresh_download_button %7.2f ms", [_ms(ts)])
	ts = _t()
	for sid: String in sids:
		RomLibrary.ensure_rom_dir(sid)
	_say("  finish step ensure_rom_dir x%d       %8.2f ms", [sids.size(), _ms(ts)])
	ts = _t()
	for sid: String in sids:
		cv.emit_signal("default_core_changed", sid, str(defaults.call("get_default_core", sid)))
	_say("  finish step default_core_changed x%d %8.2f ms", [sids.size(), _ms(ts)])
	await _frames(5)
	menu.call("notify_clear", key)

	for part: String in ["_refresh_recommend_all_button", "_populate_manager_tab",
			"refresh_download_systems"]:
		await _frames(3)
		var t := _t()
		cv.call(part)
		_say("  cores tab part %-30s %8.2f ms", [part, _ms(t)])
	menu.call("_show_spawn_view")
	await _frames(10)
