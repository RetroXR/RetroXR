## data_paths_tests — the player's chosen data folder, and moving a library to it.
##
## The root holds the player's ROMs, so the rules are about never losing or
## clobbering a file and never stranding them on a path that has gone away.
## Everything runs in a scratch folder in the OS cache dir (the app's own folder
## is refused as a root) with the config file redirected; the player's real
## data_root.json is never read or written.
##
##   "$godot" --headless --path RetroXR res://Tests/data_paths_tests.tscn
extends "res://Tests/test_suite.gd"

const EXPECTED_CASES := 86

var _scratch := ""


func _ready() -> void:
	suite_tag = "datapaths"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[datapaths] TIMEOUT")
		get_tree().quit(1))
	_scratch = (OS.get_cache_dir() + "/__data_paths_selftest").replace("\\", "/")
	_wipe(_scratch)
	DirAccess.make_dir_recursive_absolute(_scratch)
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")

	_group_config()
	_group_validate()
	_group_migration()
	_group_schedule()
	await _group_dialog()
	await _group_dialog_mouse()
	await _group_boot_move()
	await _group_move_recovery()

	_wipe(_scratch)
	DataPaths.set_config_path_for_tests("")
	_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")
	_finish()


func _group_schedule() -> void:
	var a := _scratch + "/current"
	var b := _scratch + "/next"
	DataPaths.set_root(a)
	_eq(DataPaths.schedule_root_change(b, false), "", "schedule/accepts a folder without moving")
	_eq(DataPaths.media_root(), a, "schedule/running room keeps its root for shutdown saves")
	_eq(DataPaths.pending_move_from(), "", "schedule/no move starts in the running process")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.media_root(), b, "schedule/next process uses the new root")
	_eq(DataPaths.pending_move_from(), "", "schedule/without moving leaves no work for boot")
	DataPaths.set_root(a)
	_eq(DataPaths.schedule_root_change(b, true), "", "schedule/accepts a move")
	_eq(DataPaths.media_root(), a, "schedule/a move also leaves the running root alone")
	_eq(DataPaths.pending_move_from(), "", "schedule/a move waits for the next process")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.pending_move_from(), a, "schedule/boot can resume the move")
	_eq(DataPaths.saved_root(), b, "schedule/boot knows the exact destination")
	_ok(DataPaths.clear_pending_move(), "schedule/completion is persisted")
	_ok(not DataPaths.schedule_root_change(b, false).is_empty(), "schedule/same folder refused")
	_ok(not DataPaths.schedule_root_change("relative/path", false).is_empty(), "schedule/invalid folder refused")
	_eq(DataPaths.media_root(), b, "schedule/a rejected choice leaves the active root alone")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.media_root(), b, "schedule/a rejected choice leaves the saved root alone")
	_wipe(b)
	_eq(DataPaths.saved_root(), b, "schedule/missing drive cannot redirect a move to the default")
	DataPaths.clear_root()
	DataPaths.set_config_path_for_tests(_scratch) # A directory cannot be a config file.
	var before := DataPaths.media_root()
	_ok(not DataPaths.schedule_root_change(b, false).is_empty(), "schedule/config write failure is reported")
	_eq(DataPaths.media_root(), before, "schedule/config write failure keeps the running root")
	_eq(DataPaths.pending_move_from(), "", "schedule/config write failure leaves no pending move")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")


func _group_dialog() -> void:
	var old := _scratch + "/dialog_old"
	DataPaths.set_root(old)
	_write(old + "/roms/game.rom", "GAME")
	var ui := DataRootDialog.new()
	add_child(ui)
	_eq(ui._picker.file_mode, FileDialog.FILE_MODE_OPEN_DIR, "dialog/chooses folders")
	_ok(ui._picker.use_native_dialog, "dialog/requests the native picker")
	ui._selected(_scratch + "/dialog_new")
	_ok(ui._confirm != null and ui._confirm.get_ok_button().text == "Move files and restart",
		"dialog/existing files offer a move before restart")
	var transitioning: bool = SceneManager._transitioning
	SceneManager._transitioning = true
	ui._apply(true)
	SceneManager._transitioning = transitioning
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.media_root(), old, "dialog/a blocked restart does not persist the choice")
	ui._confirm.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.media_root(), old, "dialog/cancel leaves the choice unchanged")
	DataPaths.clear_root()


func _group_move_recovery() -> void:
	var a := _scratch + "/recovery_old"
	var b := _scratch + "/recovery_new"
	_write(a + "/roms/game.rom", "ORIGINAL")
	_write(b + "/roms", "BLOCKER")
	DataPaths.set_root(b, a)
	var move := DataRootMove.new()
	add_child(move)
	_retry_after_fix(move, a, b)
	await move.finish_pending()
	_eq(_read(b + "/roms/game.rom"), "ORIGINAL", "recovery/retry completes the move")
	_eq(DataPaths.pending_move_from(), "", "recovery/retry clears the pending move")
	move.queue_free()
	await get_tree().process_frame
	_write(a + "/roms/game.rom", "ANOTHER ORIGINAL")
	DataPaths.set_root(b, a)
	move = DataRootMove.new()
	add_child(move)
	_continue_after_conflict(move)
	await move.finish_pending()
	_eq(_read(b + "/roms/game.rom"), "ORIGINAL", "recovery/conflict keeps the destination")
	_eq(_read(a + "/roms/game.rom"), "ANOTHER ORIGINAL", "recovery/conflict keeps the source")
	_eq(DataPaths.pending_move_from(), "", "recovery/conflicts are acknowledged without an endless retry")
	move.queue_free()
	await get_tree().process_frame
	DataPaths.clear_root()


func _group_dialog_mouse() -> void:
	var original_mode := Input.mouse_mode
	var capture := XRToolsDesktopMouseCapture.new()
	add_child(capture)
	capture.add_to_group("movement_providers")
	var turn := XRToolsDesktopMovementTurn.new()
	add_child(turn)
	turn.add_to_group("movement_providers")
	turn.mouse_move_vector = Vector2(8, 4)
	DataPaths.set_root(_scratch + "/mouse_old")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var captured_mode := Input.mouse_mode # The headless display cannot capture.
	print("[datapaths] mouse/display=%s starting_mode=%d" % [DisplayServer.get_name(), captured_mode])
	var ui := DataRootDialog.new()
	add_child(ui)
	_ok(not capture.enabled, "mouse/the every-tick capture provider is suspended")
	_ok(not turn.enabled, "mouse/mouse-look is suspended")
	_eq(turn.mouse_move_vector, Vector2.ZERO, "mouse/pending mouse-look is cleared")
	_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "mouse/the dialog exposes the pointer")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(not capture.enabled, "mouse/physics ticks cannot reclaim the pointer")
	ui._selected(_scratch + "/mouse_new")
	_ok(not capture.enabled, "mouse/confirmation retains the capture suspension")
	ui._confirm.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_ok(capture.enabled, "mouse/cancel restores the capture provider")
	_ok(turn.enabled, "mouse/cancel restores enabled mouse-look")
	_eq(Input.mouse_mode, captured_mode, "mouse/cancel restores the previous pointer mode")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	capture.enabled = false
	turn.enabled = false
	ui = DataRootDialog.new()
	add_child(ui)
	ui._picker.canceled.emit()
	await get_tree().process_frame
	_ok(not capture.enabled, "mouse/picker cancel preserves disabled capture")
	_ok(not turn.enabled, "mouse/picker cancel preserves disabled mouse-look")
	_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "mouse/an already free pointer stays free")
	capture.enabled = true
	ui = DataRootDialog.new()
	add_child(ui)
	ui._show_error("test error")
	_ok(not capture.enabled, "mouse/error dialog retains the capture suspension")
	ui._error.get_ok_button().pressed.emit()
	await get_tree().process_frame
	_ok(capture.enabled, "mouse/dismissing an error restores capture")
	_eq(turn.mouse_move_vector, Vector2.ZERO, "mouse/dialog motion cannot become a camera jump")
	capture.queue_free()
	turn.queue_free()
	Input.mouse_mode = original_mode
	DataPaths.clear_root()
	await get_tree().process_frame


func _retry_after_fix(move: DataRootMove, a: String, b: String) -> void:
	while move._dialog == null or not move._dialog.get_ok_button().visible \
			or move._dialog.ok_button_text != "Retry":
		await get_tree().process_frame
	_eq(DataPaths.pending_move_from(), a, "recovery/failure retains the pending move")
	_eq(_read(a + "/roms/game.rom"), "ORIGINAL", "recovery/failure leaves the source intact")
	DirAccess.remove_absolute(b + "/roms")
	move._dialog.get_ok_button().pressed.emit()


func _continue_after_conflict(move: DataRootMove) -> void:
	while move._dialog == null or not move._dialog.get_ok_button().visible \
			or move._dialog.ok_button_text != "Continue":
		await get_tree().process_frame
	move._dialog.get_ok_button().pressed.emit()


func _group_boot_move() -> void:
	var a := _scratch + "/boot_old"
	var b := _scratch + "/boot_new"
	_write(a + "/libretro/save/final.srm", "FINAL SHUTDOWN SAVE")
	DataPaths.set_root(b, a)
	var move := DataRootMove.new()
	add_child(move)
	await move.finish_pending()
	_eq(_read(b + "/libretro/save/final.srm"), "FINAL SHUTDOWN SAVE",
		"boot/the shutdown save reaches the new folder")
	_ok(not FileAccess.file_exists(a + "/libretro/save/final.srm"), "boot/the source is moved")
	_eq(DataPaths.pending_move_from(), "", "boot/the completed move is cleared")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.pending_move_from(), "", "boot/completion survives a fresh process")
	move.queue_free()
	await get_tree().process_frame
	DataPaths.clear_root()


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for d: String in dir.get_directories():
		_wipe(path + "/" + d)
	for f: String in dir.get_files():
		DirAccess.remove_absolute(path + "/" + f)
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _group_config() -> void:
	var def := DataPaths.default_root()
	_eq(DataPaths.media_root(), def, "config/no choice is the default")
	_eq(DataPaths.media_root("roms"), def + "/roms", "config/sub folder joins")
	var target := _scratch + "/lib"
	_eq(DataPaths.set_root(target), "", "config/a usable folder is accepted")
	_eq(DataPaths.media_root(), target, "config/media_root follows the choice")
	_eq(DataPaths.media_root("books"), target + "/books", "config/sub folder follows the choice")
	_eq(DataPaths.libretro_root(), target + "/libretro", "config/libretro_root follows the choice")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.media_root(), target, "config/the choice survives a reload")
	DataPaths.set_root(target + "\\", "")
	_eq(DataPaths.media_root(), target, "config/backslash and trailing slash normalised")
	DataPaths.set_root(target, _scratch + "/old")
	DataPaths.set_config_path_for_tests(_scratch + "/cfg.json")
	_eq(DataPaths.pending_move_from(), _scratch + "/old", "config/an owed move survives a reload")
	DataPaths.clear_pending_move()
	_eq(DataPaths.pending_move_from(), "", "config/a finished move is forgotten")
	_eq(DataPaths.media_root(), target, "config/clearing the move keeps the root")
	_wipe(target)
	_eq(DataPaths.media_root(), def, "config/a vanished folder falls back to the default")
	_ok(DataPaths.has_configured_root(), "config/the choice is kept for when the drive returns")
	DataPaths.clear_root()
	_ok(not DataPaths.has_configured_root(), "config/clear_root forgets it")
	_eq(DataPaths.media_root(), def, "config/cleared is the default again")


func _group_validate() -> void:
	_ok(not DataPaths.validate("").is_empty(), "validate/empty refused")
	_ok(not DataPaths.validate("relative/dir").is_empty(), "validate/relative refused")
	_ok(not DataPaths.validate("res://x").is_empty(), "validate/res:// refused")
	_ok(not DataPaths.validate(ProjectSettings.globalize_path("user://")).is_empty(),
		"validate/the app's own folder refused")
	_eq(DataPaths.validate(_scratch + "/new/deep"), "", "validate/a creatable folder passes")
	_eq(DataPaths.normalize("C:\\a\\b\\"), "C:/a/b", "validate/normalize folds a Windows path")


func _group_migration() -> void:
	var a := _scratch + "/from"
	var b := _scratch + "/to"
	_write(a + "/roms/nes/mario.nes", "MARIO")
	_write(a + "/books/m.pdf", "BOOK")
	_write(a + "/libretro/save/x.srm", "SAVE")
	_write(a + "/.hidden", "H")
	_ok(not DataRootMigration.check(a, a).is_empty(), "move/same folder refused")
	_ok(not DataRootMigration.check(a, a + "/inside").is_empty(), "move/into itself refused")
	_ok(not DataRootMigration.check(a + "/x", a).is_empty(), "move/from inside the target refused")
	_eq(DataRootMigration.check(a, b), "", "move/two folders pass")
	_eq(DataRootMigration.list_files(a).size(), 4, "move/lists every file, hidden included")

	_write(b + "/books/m.pdf", "THEIRS")
	var counts := DataRootMigration.run(a, b)
	_eq(counts[DataRootMigration.MOVED], 3, "move/moves the rest")
	_eq(counts[DataRootMigration.SKIPPED], 1, "move/skips a file already there")
	_eq(_read(b + "/roms/nes/mario.nes"), "MARIO", "move/content arrives intact")
	_eq(_read(b + "/books/m.pdf"), "THEIRS", "move/an existing file is never overwritten")
	_eq(_read(a + "/books/m.pdf"), "BOOK", "move/a skipped source is kept")
	_ok(not FileAccess.file_exists(a + "/roms/nes/mario.nes"), "move/a moved source is gone")
	_ok(not DirAccess.dir_exists_absolute(a + "/roms"), "move/emptied folders are pruned")
	_ok(DirAccess.dir_exists_absolute(a), "move/a source still holding a file stays")
	_eq(DataRootMigration.run(a, b)[DataRootMigration.MOVED], 0, "move/running again is harmless")
	_eq(DataRootMigration.move_one(a, b, "nope.bin"), DataRootMigration.FAILED,
		"move/a missing source fails rather than reporting a move")
