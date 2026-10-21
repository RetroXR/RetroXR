## SpawnMenuUpdateBanner -- the bar across the top of the spawn menu that asks
## whether to update, on every tab.
##
## It is a face over the AppUpdate autoload and keeps nothing: the service owns the
## state, this redraws on `state_changed` and moves the bar on `progress_changed`.
## Hidden unless there is something to ask or show (AppUpdateService.wants_attention)
## -- a launch with no newer release, or no network, leaves the menu exactly as it
## was.
##
## The same install press is reachable from the ABOUT tab, where an update the
## player said "Later" to can still be taken; request_install() is the one place
## that decides whether it may start.
class_name SpawnMenuUpdateBanner
extends VBoxContainer

var _menu: Node = null
var _svc: AppUpdateService = null
var _bar: ProgressBar = null


static func create(menu: Node) -> SpawnMenuUpdateBanner:
	var b := SpawnMenuUpdateBanner.new()
	b._menu = menu
	return b


## The autoload is only reachable from inside the tree, so this is found here and
## not in create().
func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_svc = get_node_or_null("/root/AppUpdate") as AppUpdateService
	if _svc != null:
		_svc.state_changed.connect(_refresh)
		_svc.progress_changed.connect(_on_progress)
	_refresh()


## Press handler shared with the ABOUT tab: refuse with the reason (a toast) when
## the room is busy, else start it. A `menu` without a toast API just skips the toast.
static func request_install(menu: Node, svc: AppUpdateService) -> void:
	var why := ""
	if menu != null and menu.has_method("busy_reason"):
		why = str(menu.busy_reason())
	if why.is_empty():
		why = svc.install()
	if not why.is_empty() and menu != null and menu.has_method("notify"):
		menu.notify("update", "❌" if svc.state == AppUpdateService.State.FAILED else "ℹ️",
			why, -1.0, MenuToasts.DWELL_FAIL)


func _refresh() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_bar = null
	visible = _svc != null and _svc.wants_attention()
	if not visible:
		return
	var ver := _svc.available_version()
	match _svc.state:
		AppUpdateService.State.AVAILABLE:
			_build_offer(ver)
		AppUpdateService.State.DOWNLOADING:
			add_child(_line("Downloading RetroXR %s…" % ver))
			_bar = ProgressBar.new()
			_bar.custom_minimum_size = Vector2(0, 22)
			_bar.max_value = 1.0
			_bar.step = 0.001
			_bar.show_percentage = true
			add_child(_bar)
		AppUpdateService.State.VERIFYING:
			add_child(_line("Checking the download…"))
		AppUpdateService.State.READY:
			add_child(_line("RetroXR %s is downloaded and ready." % ver))
			if not _svc.error.is_empty():
				add_child(MenuStyle.hint(_svc.error))
			add_child(_button("Restart now", func() -> void:
				request_install(_menu, _svc)))
		AppUpdateService.State.INSTALLING:
			add_child(_line("Installing RetroXR %s — it restarts by itself." % ver))
		AppUpdateService.State.FAILED:
			add_child(_line("The update failed.", true))
			add_child(MenuStyle.hint(_svc.error))
			var row := MenuStyle.hbox(10)
			row.add_child(_button("Try again", func() -> void:
				request_install(_menu, _svc)))
			row.add_child(_button("Open download page", func() -> void:
				_svc.open_release_page()))
			add_child(row)
	add_child(HSeparator.new())


func _build_offer(ver: String) -> void:
	add_child(_line("RetroXR %s is available  (this is %s)." % [ver, _svc.current_version]))
	var notes := str(_svc.release.get("notes", ""))
	if not notes.is_empty():
		add_child(MenuStyle.hint(notes))
	var row := MenuStyle.hbox(10)
	if _svc.can_auto_install():
		row.add_child(_button("Update now", func() -> void: request_install(_menu, _svc)))
	else:
		row.add_child(_button("Open download page", func() -> void: _svc.open_release_page()))
	row.add_child(_button("Later", func() -> void: _svc.postpone(), false))
	row.add_child(_button("Skip this version", func() -> void: _svc.skip_this_version(), false))
	add_child(row)
	if _svc.can_auto_install():
		var size := int((_svc.release.get("asset", {}) as Dictionary).get("size", 0))
		add_child(MenuStyle.hint(("Downloads %s, checks it, then restarts. Your room "
			+ "comes back as it was.") % MenuStyle.human_bytes(size)))
	else:
		add_child(MenuStyle.hint(_svc.manual_reason()))


func _on_progress(fraction: float) -> void:
	if _bar != null:
		_bar.value = fraction


static func _line(text: String, bad := false) -> Label:
	var l := MenuStyle.label(text, 20, MenuStyle.COLOR_BTN_CLEAR.lightened(0.5) if bad \
		else MenuStyle.COLOR_RECOMMENDED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _button(text: String, on_press: Callable, primary := true) -> Button:
	var b := MenuStyle.row_button(text, 20, 240, 52, false)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_stylebox_override("normal", MenuStyle.rounded(
		MenuStyle.COLOR_BTN_DL if primary else MenuStyle.COLOR_BTN_REUP, 6))
	b.pressed.connect(on_press)
	return b
