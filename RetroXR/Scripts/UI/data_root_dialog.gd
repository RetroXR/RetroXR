## Desktop folder selection lives on the primary viewport, even when Storage
## belongs to the VR menu's SubViewport. No restart until the choice is confirmed.
class_name DataRootDialog
extends Node

var _picker: FileDialog
var _confirm: ConfirmationDialog
var _error: AcceptDialog
var _chosen := ""
var _mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _mouse_released := false
var _mouse_providers: Array[XRToolsMovementProvider] = []
var _provider_enabled: Array[bool] = []


static func open(root: Window) -> void:
	if not DataPaths.can_configure() or root.has_node("DataRootDialog"):
		return
	var dialog := DataRootDialog.new()
	dialog.name = "DataRootDialog"
	root.add_child(dialog)
	dialog._picker.popup_centered(Vector2i(800, 560))


func _ready() -> void:
	_release_mouse()
	_picker = FileDialog.new()
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.use_native_dialog = true
	_picker.title = "Choose the RetroXR data folder"
	_picker.current_dir = DataPaths.media_root()
	_picker.dir_selected.connect(_selected)
	_picker.canceled.connect(queue_free)
	add_child(_picker)


## MouseCapture reclaims the pointer every physics tick, and mouse-look also
## reads motion while a Godot popup is open. Suspend both until this whole flow
## ends, including its confirmation and error dialogs.
func _release_mouse() -> void:
	_mouse_mode = Input.mouse_mode
	_mouse_released = true
	for node: Node in get_tree().get_nodes_in_group("movement_providers"):
		if node is XRToolsDesktopMouseCapture or node is XRToolsDesktopMovementTurn:
			var provider := node as XRToolsMovementProvider
			_mouse_providers.append(provider)
			_provider_enabled.append(provider.enabled)
			provider.enabled = false
			if provider is XRToolsDesktopMovementTurn:
				provider.mouse_move_vector = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if not _mouse_released:
		return
	for i in _mouse_providers.size():
		var provider := _mouse_providers[i]
		if not is_instance_valid(provider):
			continue
		if provider is XRToolsDesktopMovementTurn:
			provider.mouse_move_vector = Vector2.ZERO
		provider.enabled = _provider_enabled[i]
	Input.mouse_mode = _mouse_mode


func _selected(path: String) -> void:
	_chosen = DataPaths.normalize(path)
	_picker.hide()
	if _chosen == DataPaths.normalize(DataPaths.media_root()):
		queue_free()
		return
	var why := DataPaths.validate(_chosen)
	if not why.is_empty():
		_show_error(why)
		return
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Change RetroXR data folder"
	_confirm.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.get_label().custom_minimum_size.x = 580
	_confirm.dialog_text = "Use this folder for ROMs, books, videos, mods and cores?\n\n%s\n\nRetroXR will restart to apply the change." % _chosen
	_confirm.canceled.connect(queue_free)
	var has_files := DataRootMigration.has_files(DataPaths.media_root())
	if has_files:
		_confirm.dialog_text += "\n\nMove your existing files, or use the folder without moving them.\nFiles already in the new folder will be kept."
		_confirm.ok_button_text = "Move files and restart"
		_confirm.add_button("Use without moving", false, "use")
		_confirm.custom_action.connect(func(_action: StringName) -> void: _apply(false))
	else:
		_confirm.ok_button_text = "Use folder and restart"
	_confirm.confirmed.connect(func() -> void: _apply(has_files))
	add_child(_confirm)
	_confirm.popup_centered(Vector2i(640, 0))


func _apply(move_files: bool) -> void:
	_confirm.hide()
	var why: String = SceneManager.restart_app(PackedStringArray(),
		DataPaths.schedule_root_change.bind(_chosen, move_files))
	if not why.is_empty():
		_show_error(why)


func _show_error(message: String) -> void:
	if _error == null:
		_error = AcceptDialog.new()
		_error.title = "Data folder could not be changed"
		_error.confirmed.connect(queue_free)
		_error.canceled.connect(queue_free)
		add_child(_error)
	_error.dialog_text = message
	_error.popup_centered()
