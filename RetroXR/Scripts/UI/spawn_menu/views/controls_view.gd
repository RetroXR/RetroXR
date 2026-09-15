## SpawnMenuControlsView — the menu's CONTROLS tab: what every physical input
## does inside an emulated system.
##
## Two pages inside one scroll. The global page carries the bindings that every
## machine falls back to, and below them a grid of platform tiles. Opening a tile
## swaps to that platform's page: an "Override global controls" switch, and when
## it is on, that platform's own copy of the same rows.
##
## The rows themselves live in ControlsBindingEditor, built once per page and
## parameterised by a systemid. One class rather than two copies of the same ten
## dropdowns, so a fix to a row cannot land on the global page and miss the
## per-platform one.
##
## A platform's override IS its stored profile — there is no separate flag. The
## switch writes the profile on and deletes it off, and because every binding
## consumer re-reads for its own system through the CONSUMER_GROUP fan-out, a
## write reaches exactly the machines of that platform while they are standing.
class_name SpawnMenuControlsView
extends ScrollContainer

## A row wants the next key/mouse press captured for `action_name`;
## spawn_menu_controller does the capturing and calls on_rebind_complete().
signal rebind_started(action_name: String)
## Same for a physical gamepad button, answered by on_pad_rebind_complete().
signal pad_rebind_started(target: String)
## Bindings were written — anything holding a copy should re-read them.
signal controller_bindings_changed

## Tile geometry, matching SystemGridBrowser so the two grids read as one family.
const TILE_MIN_W := 250.0
const TILE_H     := 96.0
const TILE_SEP   := 10
const ICON_PX    := 60.0

## Injected by the menu, which owns both. Used only to name the platforms.
var core_defaults: CoreDefaults = null
var core_db: CoreInfoDatabase = null

var _global_page:   VBoxContainer = null
var _platform_page: VBoxContainer = null
var _tiles_grid:    GridContainer = null

var _global_editor:   ControlsBindingEditor = null
var _platform_editor: ControlsBindingEditor = null
## Whichever editor a rebind capture should be answered on.
var _active_editor:   ControlsBindingEditor = null

var _platform_title:  Label      = null
var _platform_art:    TextureRect = null
var _platform_switch: VRToggle   = null
var _platform_hint:   Label      = null
var _platform_body:   VBoxContainer = null
var _current_sid: String = ""

## True while the code is moving the override switch to match a platform being
## opened. VRToggle slides its knob off the `toggled` signal, so the switch has
## to be set loudly; this stops that echo being read as the player flicking it.
var _syncing_switch: bool = false


static func create(a_core_defaults: CoreDefaults = null,
		a_core_db: CoreInfoDatabase = null) -> SpawnMenuControlsView:
	var v := SpawnMenuControlsView.new()
	v.core_defaults = a_core_defaults
	v.core_db = a_core_db
	v._build()
	return v


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var root := MenuStyle.vbox(14)
	add_child(root)

	_global_page = MenuStyle.vbox(14)
	root.add_child(_global_page)

	_platform_page = MenuStyle.vbox(14)
	_platform_page.visible = false
	root.add_child(_platform_page)

	_build_global_page()
	_build_platform_page()

	# Column count is measured from THIS container, never from the grid. A grid
	# with a width minimum widens the scroll it is measured against, and the
	# count can then never come back down — see system_grid_browser.gd.
	resized.connect(_update_tile_columns)


# ── Global page ───────────────────────────────────────────────────────────────

func _build_global_page() -> void:
	_global_page.add_child(MenuStyle.spacer(10))
	_global_page.add_child(MenuStyle.label("CONTROLS", 22, MenuStyle.COLOR_TITLE))

	_global_editor = ControlsBindingEditor.create("")
	_wire_editor(_global_editor)
	_global_page.add_child(_global_editor)
	_active_editor = _global_editor

	_global_page.add_child(HSeparator.new())
	_global_page.add_child(MenuStyle.label("PER-PLATFORM CONTROLS", 22, MenuStyle.COLOR_TITLE))

	var hint := Label.new()
	hint.text = "Every machine uses the bindings above unless its platform overrides them. Pick a platform to give it its own."
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_global_page.add_child(hint)

	_tiles_grid = GridContainer.new()
	_tiles_grid.columns = 2
	_tiles_grid.add_theme_constant_override("h_separation", TILE_SEP)
	_tiles_grid.add_theme_constant_override("v_separation", TILE_SEP)
	_tiles_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_page.add_child(_tiles_grid)

	_global_page.add_child(MenuStyle.spacer(10))
	refresh_platforms()


## Rebuild the platform grid. Called when a system gains a default core and when
## an override is added or dropped, because the view is built once at menu
## construction and never rebuilt on a tab switch.
func refresh_platforms() -> void:
	if not is_instance_valid(_tiles_grid):
		return
	for child in _tiles_grid.get_children():
		child.queue_free()

	var ids: Array[String] = []
	if core_defaults != null:
		for sid: String in core_defaults.all_defaults():
			# A platform that reads another's profile is set on that one's page.
			var scope := BindingStore.scope_of(sid)
			if not ids.has(scope):
				ids.append(scope)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _display_name(a).naturalnocasecmp_to(_display_name(b)) < 0)

	if ids.is_empty():
		var empty := Label.new()
		empty.text = "No default cores set.\nGo to Cores ▸ Manager to configure systems."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
		_tiles_grid.add_child(empty)
		return

	for sid: String in ids:
		_tiles_grid.add_child(_make_tile(sid))
	_update_tile_columns()


## Console name for a systemid: libretro's own label, this project's descriptor,
## then the bare id.
func _display_name(systemid: String) -> String:
	if core_db != null:
		var name_text := core_db.get_systemname_for_id(systemid)
		if not name_text.is_empty():
			return name_text
	var info := SystemInfo.for_system(systemid)
	if info != null and not info.display_name.is_empty():
		return info.display_name
	return systemid


## True when either store carries a profile for this platform. Both are written
## together by the switch, but in desktop mode only the gamepad half exists.
static func _has_override(systemid: String) -> bool:
	return ControllerBindings.has_system_override(systemid) \
		or GamepadBindings.has_system_override(systemid) \
		or DesktopBindings.has_system_override(systemid)


func _make_tile(systemid: String) -> Button:
	var btn := Button.new()
	# Height only — a width minimum here would become the grid's minimum, and
	# with horizontal scrolling disabled this ScrollContainer would inherit it.
	btn.custom_minimum_size = Vector2(0, TILE_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.set_meta("systemid", systemid)
	SystemGridBrowser.style_tile(btn)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var art := SystemIcons.for_system(systemid)
	if art:
		var ico := TextureRect.new()
		ico.texture = art
		ico.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ico)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = _display_name(systemid)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# "Nintendo Entertainment System" is three lines in the space left beside the
	# art, and a third line pushes the badge out through the bottom of a tile
	# whose height is fixed. Capped and ellipsized, exactly as the SPAWN and
	# CORES grids cap theirs.
	name_lbl.max_lines_visible = 2
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", SystemGridBrowser.COLOR_TITLE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	if _has_override(systemid):
		var badge := Label.new()
		badge.text = "Overridden"
		badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		badge.add_theme_font_size_override("font_size", 16)
		badge.add_theme_color_override("font_color", SystemGridBrowser.COLOR_BADGE_HERE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(badge)

	btn.pressed.connect(_open_platform.bind(systemid))
	return btn


func _update_tile_columns() -> void:
	if not is_instance_valid(_tiles_grid):
		return
	var avail := size.x - 24.0
	var cols := int(floor((avail + TILE_SEP) / (TILE_MIN_W + TILE_SEP)))
	_tiles_grid.columns = maxi(1, cols)


# ── Platform page ─────────────────────────────────────────────────────────────

func _build_platform_page() -> void:
	_platform_page.add_child(MenuStyle.spacer(10))

	var back := Button.new()
	back.text = "◀ Controls"
	back.custom_minimum_size = Vector2(200, 52)
	back.add_theme_font_size_override("font_size", 18)
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(show_global)
	_platform_page.add_child(back)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_platform_page.add_child(head)

	_platform_art = TextureRect.new()
	_platform_art.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_platform_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_platform_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_platform_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_platform_art)

	_platform_title = MenuStyle.label("", 22, MenuStyle.COLOR_TITLE)
	_platform_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_platform_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_platform_title)

	_platform_switch = MenuStyle.switch_row(_platform_page, "Override global controls")
	_platform_switch.toggled.connect(_on_override_toggled)

	_platform_hint = Label.new()
	_platform_hint.text = "This platform uses the global bindings. Turn the switch on to give it its own, starting from a copy of the global ones."
	_platform_hint.add_theme_font_size_override("font_size", 16)
	_platform_hint.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
	_platform_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_platform_page.add_child(_platform_hint)

	_platform_body = MenuStyle.vbox(14)
	_platform_page.add_child(_platform_body)

	_platform_page.add_child(MenuStyle.spacer(10))


func _open_platform(systemid: String) -> void:
	_current_sid = systemid
	_platform_title.text = _display_name(systemid)
	_platform_art.texture = SystemIcons.for_system(systemid)

	# A fresh editor per platform: its working copies, its dropdown registry and
	# its two diagrams all belong to one systemid.
	if is_instance_valid(_platform_editor):
		_platform_editor.queue_free()
	_platform_editor = ControlsBindingEditor.create(systemid)
	_wire_editor(_platform_editor)
	_platform_body.add_child(_platform_editor)
	_active_editor = _platform_editor

	var on := _has_override(systemid)
	_syncing_switch = true
	_platform_switch.button_pressed = on
	_syncing_switch = false
	_platform_editor.visible = on
	_platform_hint.visible = not on

	_global_page.visible = false
	_platform_page.visible = true
	scroll_vertical = 0


## Back to the global page. The platform editor is left built — coming back to
## the same tile rebuilds it anyway, and freeing it here would race the button
## press that is still being handled.
func show_global() -> void:
	# A platform page loads its own keys into the InputMap to show them; leaving
	# it is where the global map comes back.
	DesktopBindings.apply_for_system("")
	_platform_page.visible = false
	_global_page.visible = true
	_active_editor = _global_editor
	scroll_vertical = 0
	refresh_platforms()


## On: materialise this platform's profile from whatever the editor is showing,
## which for a platform with no profile yet is a copy of the global map.
## Off: delete the profile in both stores and fall back to global.
func _on_override_toggled(on: bool) -> void:
	if _syncing_switch or _current_sid.is_empty():
		return
	if not is_instance_valid(_platform_editor):
		return
	if on:
		_platform_editor.apply_all()
	else:
		ControllerBindings.clear_system_override(_current_sid)
		GamepadBindings.clear_system_override(_current_sid)
		DesktopBindings.clear_system_override(_current_sid)
		# The editor pushed this platform's keys into the InputMap when it built;
		# dropping the profile has to put the global ones back or the page keeps
		# showing, and the desk keeps using, a map that no longer exists.
		DesktopBindings.apply_for_system("")
		controller_bindings_changed.emit()
	# Hidden rather than freed, so flicking the switch back does not rebuild two
	# diagrams and lose the rows the player was part-way through.
	_platform_editor.visible = on
	_platform_hint.visible = not on


# ── Editor plumbing ───────────────────────────────────────────────────────────

func _wire_editor(editor: ControlsBindingEditor) -> void:
	editor.rebind_started.connect(func(action: String) -> void:
		_active_editor = editor
		rebind_started.emit(action))
	editor.pad_rebind_started.connect(func(target: String) -> void:
		_active_editor = editor
		pad_rebind_started.emit(target))
	editor.controller_bindings_changed.connect(func() -> void:
		controller_bindings_changed.emit())


## Called by spawn_menu_controller after a key/mouse press is captured. Routed to
## whichever editor asked for it — the global page and a platform page each own a
## set of rebind buttons, and relabelling the wrong one leaves a row reading
## "[ Press a key… ]" for ever.
func on_rebind_complete(action: String, event: InputEvent) -> void:
	if is_instance_valid(_active_editor):
		_active_editor.on_rebind_complete(action, event)


## Called by spawn_menu_controller after a joypad press is captured.
func on_pad_rebind_complete(target: String, binding: String) -> void:
	if is_instance_valid(_active_editor):
		_active_editor.on_pad_rebind_complete(target, binding)
