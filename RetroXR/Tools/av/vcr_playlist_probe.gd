## VCR playlist probe -- does a tape that is a playlist play through its
## recordings on the real libVLC, scan across the join both ways, and play a copy
## that lives under user:// (where a netplay peer's lands)? Windowed, because
## VlcPlayer is not loaded headless:
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/av/vcr_playlist_probe.tscn -- --clips=<dir>
##
## <dir> holds red.mp4 and blue.mp4: any two videos of a couple of seconds each.
## The probe writes its playlists beside them and under user://, and removes the
## user:// copy after. The control leg opens the user:// path straight, as the
## decks did before, and must NOT play. Exits non-zero on failure.
extends Node

const VCR := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const TV := preload("res://Scenes/Objects/tv.tscn")
const USER_DIR := "user://vcr_playlist_probe"

var _fail := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	var clips := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = a.trim_prefix("--clips=")
	await _run(clips)
	print("[probe] ---- %s ----" % ("all checks passed" if _fail == 0 else "%d FAILED" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, what: String, detail := "") -> void:
	if not cond:
		_fail += 1
	print("[probe] %s  %s%s" % ["PASS" if cond else "FAIL", what,
		"" if detail.is_empty() else "  - " + detail])


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run(clips: String) -> void:
	if not (FileAccess.file_exists(clips.path_join("red.mp4")) and FileAccess.file_exists(clips.path_join("blue.mp4"))):
		_ok(false, "--clips=<dir> holding red.mp4 and blue.mp4", clips)
		return
	var list := clips.path_join("probe_tape.m3u")
	_write(list, "#EXTM3U\nred.mp4\nblue.mp4\n")

	var tv := TV.instantiate()
	add_child(tv)
	tv.position = Vector3(3.0, 0.0, 0.0)
	var vcr := VCR.instantiate() as VCRPlayer
	add_child(vcr)
	await get_tree().process_frame
	if vcr._vlc == null:
		_ok(false, "VlcPlayer is loaded (run windowed)")
		return
	vcr.connected_tv = tv
	vcr.video_path = list

	# Plays through, and winds back at the end of the tape.
	vcr.play()
	_ok(vcr.is_playing and vcr._rec_idx == 0, "plays the first recording")
	_ok(await _until(func() -> bool: return vcr._rec_idx == 1, 8.0),
		"plays on into the second when the first ends")
	_ok(await _until(func() -> bool: return not vcr.is_playing, 8.0) and vcr._rec_idx == 0,
		"stops at the end of the last, wound back to the first")

	# Fast-forward across the join.
	vcr.play()
	await _until(func() -> bool: return vcr._vlc_length_sec() > 0.0, 4.0)
	vcr._on_ff_pressed()
	var seen: Array[int] = []
	var crossed := await _until(func() -> bool:
		if seen.is_empty() or seen.back() != vcr._rec_idx:
			seen.append(vcr._rec_idx)
		return vcr._rec_idx == 1, 4.0)
	_ok(crossed, "FF runs on into the second recording", "recordings seen %s" % [seen])
	await _until(func() -> bool: return vcr._scan_dir == 0, 4.0)
	print("[probe] after FF off the end of the tape: playing=%s rec=%d" % [vcr.is_playing, vcr._rec_idx])
	vcr.stop()

	# Rewind across the join, from part way into the second.
	vcr._rec_idx = 1
	vcr._resume_at = 1.0
	vcr.play()
	await _until(func() -> bool: return not vcr._resume_pending(), 4.0)
	vcr._on_rewind_pressed()
	_ok(await _until(func() -> bool: return vcr._rec_idx == 0, 4.0),
		"REW runs back into the first recording")
	_ok(await _until(func() -> bool: return vcr._scan_dir == 0, 6.0) and vcr._rec_idx == 0 and vcr.is_playing,
		"and holds at the start of the tape", "at %.2f s" % vcr._vlc_time_sec())
	vcr.stop()

	# A peer's copy, under user://.
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	DirAccess.copy_absolute(clips.path_join("red.mp4"), USER_DIR.path_join("red.mp4"))
	DirAccess.copy_absolute(clips.path_join("blue.mp4"), USER_DIR.path_join("blue.mp4"))
	_write(USER_DIR.path_join("tape.m3u8"), "#EXTM3U\nred.mp4\nblue.mp4\n")
	vcr.video_path = USER_DIR.path_join("tape.m3u8")
	vcr._rec_idx = 0
	vcr._resume_at = 0.0
	vcr.play()
	_ok(await _until(func() -> bool: return vcr._vlc_length_sec() > 0.0, 5.0),
		"a recording under user:// opens", vcr._recordings[0] if not vcr._recordings.is_empty() else "")
	vcr.stop()
	# Control: the raw user:// path, as the decks handed it over before.
	vcr._vlc.open(USER_DIR.path_join("red.mp4"), false)
	vcr._vlc.play()
	await get_tree().create_timer(3.0).timeout
	_ok(vcr._vlc_length_sec() <= 0.0, "control: the raw user:// path does not open",
		"length %.2f" % vcr._vlc_length_sec())
	vcr._vlc.stop()
	RomLibrary._remove_tree(ProjectSettings.globalize_path(USER_DIR))
	DirAccess.remove_absolute(list)
