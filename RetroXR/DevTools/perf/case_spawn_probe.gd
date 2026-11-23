## Times spawning a game case: the freeze reported on Quest (2026-11-23, "the game freezes for a while until it
## spawns in").
##
## Spawns each game's case the way the spawn menu does (SpawnMenuController._on_spawn_case_requested, copied in
## _spawn: keep the two alike) three times, recording every frame around it. Then the same with the four things a
## spawn did on the main thread until that day put back, each the old operation itself: its three model files
## loaded where it stands and uncached (as when no case of its kind was in the room), its flip tray's faces read
## off the mesh, its discs and manual built in the spawn frame, each disc's label scan decoded there. And each of
## those alone.
##
##   "$godot" --path RetroXR res://DevTools/perf/case_spawn_probe.tscn -- "--game=psx|<rom>" ...
##
## With no --game it takes the first multi-disc game under roms/psx and the first game under roms/ps2. On a
## headset it is its own package (preset "Quest case spawn probe", com.xenu.retroxr.csprobe; the probe-only export
## in docs/dev/quest-device.md): launch it once so it makes its folders (it says where), push a game's art into
## them (roms/<system>/media/label, box_back + box_side + box_front or box, manual) with an empty file named as
## each disc beside them, and launch it again.
##
## Prints [perf] lines, leaves them in user://perf_result.txt, and quits.
extends Node3D

const TIMEOUT_SEC := 240.0
## Frames recorded after each spawn: about a second.
const WINDOW_FRAMES := 80
const REPEATS := 3
const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const ROM_EXTS := ["chd", "cue", "iso", "bin", "zip", "pbp"]

var _lines: PackedStringArray = PackedStringArray()
var _rec := PackedFloat64Array()
var _rec_on := false
var _last := 0
var _pace := 14.0


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


func _on_frame() -> void:
	var now := _t()
	if _rec_on:
		_rec.append(float(now - _last) / 1000.0)
	_last = now


func _finish(code: int) -> void:
	var f := FileAccess.open("user://perf_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	get_tree().quit(code)


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		_say("TIMEOUT")
		_finish(1))
	get_tree().process_frame.connect(_on_frame)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.3, 0.7)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	add_child(DirectionalLight3D.new())
	_run()


func _run() -> void:
	_say("device=%s  renderer=%s  user=%s", [OS.get_name(), DisplayServer.get_name(), OS.get_user_data_dir()])
	var games := _games()
	for sys: String in ["psx", "ps2"]:
		var dir := RomLibrary.rom_dir_for_system(sys)
		for sub: String in ["", "media/label", "media/box", "media/box_back", "media/box_side", "media/box_front", "media/manual"]:
			DirAccess.make_dir_recursive_absolute(dir.path_join(sub))
		_say("roms/%s = %s", [sys, dir])
	if games.is_empty():
		_say("no game found: push one into the folders above and launch again")
		_finish(2)
		return
	await _frames(60)
	_rec.clear()
	_rec_on = true
	await _frames(120)
	_rec_on = false
	var idle := _rec.duplicate()
	idle.sort()
	_pace = idle[idle.size() / 2]
	_say("idle frame p50 %.2f  max %.2f ms", [_pace, idle[idle.size() - 1]])
	for g: Array in games:
		var systemid := str(g[0])
		var rom := str(g[1])
		_say("==== %s (%s)", [rom.get_file(), systemid])
		for i in REPEATS:
			await _measured(systemid, rom, false, "as it spawns now #%d%s" % [i + 1, " (the session's first)" if i == 0 and g == games[0] else ""])
		for i in REPEATS:
			await _measured(systemid, rom, true, "with the old main-thread work #%d" % (i + 1))
		await _alone(systemid, rom)
	_say("done")
	_finish(0)


## --game=<systemid>|<rom path> arguments, else the first multi-disc PlayStation game and the first PS2 game there.
func _games() -> Array:
	var out: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			var kv := arg.trim_prefix("--game=").split("|")
			if kv.size() == 2:
				out.append([kv[0], kv[1]])
	if not out.is_empty():
		return out
	for sys: String in ["psx", "ps2"]:
		var dir := RomLibrary.rom_dir_for_system(sys)
		var names := Array(DirAccess.get_files_at(dir))
		names.sort()
		for file: String in names:
			if not ROM_EXTS.has(file.get_extension().to_lower()):
				continue
			if sys == "psx" and not file.contains("(Disc 1)"):
				continue
			out.append([sys, dir.path_join(file)])
			break
	return out


## One spawn with its frames: the spawn frame's own main-thread work, then how the frames went.
func _measured(systemid: String, rom: String, old: bool, label: String) -> void:
	await _frames(20)
	_rec.clear()
	_rec_on = true
	var call_ms: float = await _spawn(systemid, rom, old)
	await _frames(WINDOW_FRAMES)
	_rec_on = false
	var worst := 0.0
	var over := 0.0
	var spikes := PackedStringArray()
	for ft in _rec:
		worst = maxf(worst, ft)
		over += maxf(0.0, ft - _pace * 1.5)
		if ft > _pace * 2.5:
			spikes.append("%.0f" % ft)
	_say("%-46s spawn frame %7.1f ms | worst frame %7.1f ms, over-pace total %7.1f ms, long frames: %s",
		[label, call_ms, worst, over, " ".join(spikes) if not spikes.is_empty() else "none"])
	for node in get_tree().get_nodes_in_group("spawned"):
		node.queue_free()
	await _frames(20)


## SpawnMenuController._on_spawn_case_requested, with the placing in a hand left out. `old` puts back what it did
## on the main thread before 2026-11-23. Returns the ms of main-thread work in the frame the case appeared.
func _spawn(systemid: String, rom_path: String, old: bool) -> float:
	var discs := GameCase.disc_slots(rom_path, GameCase.disc_total_of(systemid, rom_path))
	var panels := RetroGameCase.box_panel_paths(systemid, rom_path)
	var art := RetroGameCase.box_art_path(systemid, rom_path)
	var img: Image = null
	if panels.is_empty() and not art.is_empty():
		img = await RetroGameCase.decode_image(get_tree(), art)
	var size := Vector2i(img.get_width(), img.get_height()) if img != null else RetroGameCase.box_size(systemid, rom_path)
	var pick := GameCase.pick(systemid, GameCase.market_of(systemid, rom_path), discs.size(), size,
		GameCase.release_of(systemid, rom_path))
	var models := GameCaseModel.model_paths(str(pick["family"]), str(pick["variant"]))
	if not old:
		ModelWarmer.prefetch(Array(models))
	if not panels.is_empty():
		img = await RetroGameCase.decode_panels(get_tree(), panels, str(pick["variant"]), str(pick["family"]))
		if img == null and not art.is_empty():
			img = await RetroGameCase.decode_image(get_tree(), art)
	if not old:
		for path in models:
			await ModelWarmer.acquire(path)
	var t := _t()
	if old:
		for path in models:                              # a plain load with no case of its kind in the room
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.rom_path = rom_path
	c.game_label = rom_path.get_file().get_basename()
	c.systemid = systemid
	c.case_family = str(pick["family"])
	c.case_variant = str(pick["variant"])
	c.case_color = str(pick["color"])
	c.box_image = img
	c.freeze = true
	add_child(c)
	c.add_to_group("spawned")
	c.global_position = Vector3(0.0, 1.0, 0.0)
	if old:
		for panel: Array in c.inner_panels():            # the tray's faces off its mesh
			c._panel_mesh_slab(str(panel[0]), float(panel[1]))
		c.spawn_contents(discs)                          # everything in this frame
		for disc_path in discs:                          # and each label scan decoded here
			if not disc_path.is_empty():
				MediaDimensions.load_label_texture(systemid, disc_path)
	else:
		c.spawn_contents_over_frames(discs)
	return _ms(t)


## Each of the old operations by itself.
func _alone(systemid: String, rom_path: String) -> void:
	var discs := GameCase.disc_slots(rom_path, GameCase.disc_total_of(systemid, rom_path))
	var pick := GameCase.pick(systemid, GameCase.market_of(systemid, rom_path), discs.size(),
		RetroGameCase.box_size(systemid, rom_path), GameCase.release_of(systemid, rom_path))
	var models := GameCaseModel.model_paths(str(pick["family"]), str(pick["variant"]))
	await _frames(10)
	var t := _t()
	for path in models:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_say("  alone: %s/%s's 3 model files, a plain uncached load %7.1f ms", [pick["family"], pick["variant"], _ms(t)])
	await _frames(10)
	var scans := 0
	t = _t()
	for disc_path in discs:
		if not disc_path.is_empty() and MediaDimensions.load_label_texture(systemid, disc_path) != null:
			scans += 1
	_say("  alone: %d label scans decoded on the main thread %7.1f ms", [scans, _ms(t)])
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.systemid = systemid
	c.case_family = str(pick["family"])
	c.case_variant = str(pick["variant"])
	c.freeze = true
	add_child(c)
	c.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(10)
	var panels := c.inner_panels()
	t = _t()
	for panel: Array in panels:
		c._panel_mesh_slab(str(panel[0]), float(panel[1]))
	_say("  alone: %d inner panel(s)' faces read off the mesh %7.1f ms", [panels.size(), _ms(t)])
	c.queue_free()
	await _frames(10)
