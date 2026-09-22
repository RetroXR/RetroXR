## Wii System Menu install probe — runs the dolphin core's online system update
## (Libretro.RunWiiSystemUpdate, the path FirmwareInstaller's WII_MENU job
## takes) into a SCRATCH NAND, never the player's.
##
##   "$godot" --headless --path RetroXR res://Tools/cores/wii_menu_update_probe.tscn \
##       -- --user-dir=<empty dir> [--region=USA] [--cancel-after=N]
##
## Needs the network, the installed dolphin core with the
## `retroxr_wii_system_update` export, and minutes. Prints each title as it
## lands, the result code, and whether the menu's title.tmd exists after.
## --cancel-after=N returns false from the progress callback at title N, which
## is the control leg: the result must then be 8 (Cancelled) and a rerun must
## pick up where it stopped.
extends Node

var _thread := Thread.new()


func _ready() -> void:
	var user_dir := ""
	var region := "USA"
	var cancel_after := -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--user-dir="):
			user_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--region="):
			region = arg.get_slice("=", 1)
		elif arg.begins_with("--cancel-after="):
			cancel_after = int(arg.get_slice("=", 1))
	if user_dir.is_empty():
		print("[probe] FAIL --user-dir=<scratch dir> is required (never the real NAND)")
		get_tree().quit(2)
		return
	if user_dir.simplify_path() == WiiSystemMenu.user_dir().simplify_path():
		print("[probe] FAIL refusing to write the player's real NAND")
		get_tree().quit(2)
		return
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[probe] FAIL timed out")
		get_tree().quit(3))
	DirAccess.make_dir_recursive_absolute(user_dir)
	_thread.start(_run.bind(user_dir, region, cancel_after))


func _run(user_dir: String, region: String, cancel_after: int) -> void:
	var started := Time.get_ticks_msec()
	var progress := func(processed: int, total: int, title: String) -> bool:
		print("[probe] title %d/%d %s  (%.1f s)" % [processed, total, title,
			(Time.get_ticks_msec() - started) / 1000.0])
		return cancel_after < 0 or processed < cancel_after
	var result := int(ClassDB.class_call_static("Libretro", "RunWiiSystemUpdate",
		CoreDownloadManager.default_core_root(), WiiSystemMenu.CORE, user_dir,
		WiiSystemMenu.sys_dir(), region, progress))
	_finish.call_deferred(user_dir, result, (Time.get_ticks_msec() - started) / 1000.0)


func _finish(user_dir: String, result: int, seconds: float) -> void:
	_thread.wait_to_finish()
	var tmd := user_dir.path_join("Wii/title/00000001/00000002/content/title.tmd")
	print("[probe] result=%d (%s) in %.1f s" % [result,
		"ok" if WiiSystemMenu.succeeded(result) else WiiSystemMenu.result_text(result), seconds])
	print("[probe] menu title.tmd %s" % ("PRESENT" if FileAccess.file_exists(tmd) else "absent"))
	var bytes := FileAccess.get_file_as_bytes(tmd)
	if bytes.size() >= 0x18C:
		var ios := "%02x%02x%02x%02x/%02x%02x%02x%02x" % Array(bytes.slice(0x184, 0x18C))
		print("[probe] menu runs on IOS %s: %s" % [ios, "PRESENT" if FileAccess.file_exists(
			user_dir.path_join("Wii/title/%s/content/title.tmd" % ios)) else "ABSENT"])
	get_tree().quit(0 if WiiSystemMenu.succeeded(result) else 1)
