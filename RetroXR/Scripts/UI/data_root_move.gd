## Only the restart's boot runs a move: the old process, cores and mounted packs
## have gone. The worker keeps even a large cross-drive copy off the UI thread.
## BootScene resumes normal startup in this same process when the move completes.
class_name DataRootMove
extends Node

var _thread: Thread
var _dialog: AcceptDialog
var _status: Label
var _bar: ProgressBar
var _stop := false


func finish_pending() -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "Moving RetroXR files"
	_dialog.canceled.connect(func() -> void: get_tree().quit())
	add_child(_dialog)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(540, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_dialog.add_child(box)
	box.add_child(_status)
	_bar = ProgressBar.new()
	box.add_child(_bar)
	_dialog.add_cancel_button("Quit")
	_dialog.popup_centered()
	while true:
		_dialog.get_ok_button().hide()
		_status.text = "Preparing to move your files…"
		_bar.value = 0
		var from := DataPaths.pending_move_from()
		var to := DataPaths.saved_root()
		var why := DataPaths.validate(to)
		if why.is_empty():
			why = DataRootMigration.check(from, to)
		var counts := {"moved": 0, "skipped": 0, "failed": 0}
		if why.is_empty():
			_thread = Thread.new()
			var err := _thread.start(_move.bind(from, to))
			if err == OK:
				while _thread.is_alive():
					await get_tree().process_frame
				counts = _thread.wait_to_finish()
				# Drain the worker's deferred progress before showing its result.
				await get_tree().process_frame
			else:
				why = "The file move could not be started."
			_thread = null
		if why.is_empty() and int(counts["failed"]) > 0:
			why = "%d file(s) could not be moved. They remain in:\n%s\n\nCheck the folder and drive, then retry." % [counts["failed"], from]
		if why.is_empty() and not DataPaths.clear_pending_move():
			why = "Files were moved, but the completed move could not be saved. Check that RetroXR's settings folder is writable, then retry."
		if why.is_empty():
			if int(counts["skipped"]) > 0:
				_status.text = "%d file(s) already existed in the new folder. The originals remain in:\n%s" % [counts["skipped"], from]
				_dialog.ok_button_text = "Continue"
				_dialog.get_ok_button().show()
				await _dialog.confirmed
			_dialog.hide()
			return
		_status.text = why
		_dialog.ok_button_text = "Retry"
		_dialog.get_ok_button().show()
		await _dialog.confirmed
		_dialog.popup_centered()


func _move(from: String, to: String) -> Dictionary:
	var files := DataRootMigration.list_files(from)
	var counts := {"moved": 0, "skipped": 0, "failed": 0}
	for i in files.size():
		if _stop:
			break
		counts[DataRootMigration.move_one(from, to, files[i])] += 1
		if i % 8 == 0 or i + 1 == files.size():
			_progress.call_deferred(i + 1, files.size())
	DataRootMigration.prune_empty(from)
	return counts


func _progress(done: int, total: int) -> void:
	_status.text = "Moving files… %d / %d" % [done, total]
	_bar.max_value = maxi(total, 1)
	_bar.value = done


func _exit_tree() -> void:
	_stop = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
