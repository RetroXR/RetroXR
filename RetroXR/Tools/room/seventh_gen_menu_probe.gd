## seventh_gen_menu_probe — how the PlayStation 3 and the Xbox 360 look in the
## spawn menu: their tiles on the Systems and Cartridges tabs, and each one's
## Systems page (what it spawns).
##
## A tile exists only for a system with a default core, and these cores need not
## be installed, so the probe gives both a default IN MEMORY on the menu's own
## CoreDefaults. Nothing is saved: core_defaults.json on disk is untouched.
## The filter box narrows each grid so the two are on screen among the player's
## other systems.
##
## Windowed, never --headless (the dummy renderer returns a blank image):
##
##   "$godot" --path RetroXR --resolution 1280x800 --position 20,20 \
##     res://Tools/room/seventh_gen_menu_probe.tscn -- --out=C:/tmp/menu
##
## Writes <out>_<shot>.png and prints [seventh-menu] lines.
extends Control

const SPAWN_MENU := preload("res://Scenes/UI/spawn_menu.tscn")

var _out := "user://seventh_menu"
var _menu: Node = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[seventh-menu] TIMEOUT")
		get_tree().quit(1))
	# "test" is an authored, slotless room id: the menu skips its slot restore.
	SceneManager.current_scene_id = "test"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_menu = SPAWN_MENU.instantiate()
	add_child(_menu)
	if _menu is Control:
		(_menu as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(20)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()

	var defaults: CoreDefaults = _menu.get("core_defaults")
	var view: SpawnMenuSpawnView = _menu.call("spawn_view")
	if defaults == null or view == null:
		print("[seventh-menu] FAIL: menu has no core_defaults/spawn view")
		get_tree().quit(1)
		return
	for pair: Array in [["ps3", "rpcs3"], ["xbox360", "xenia_edge"]]:
		print("[seventh-menu] %s default was '%s'" % [pair[0], defaults.get_default_core(pair[0])])
		defaults.set_default_core(pair[0], pair[1])   # in memory only, never saved
	view.on_menu_shown()
	view.refresh_after_core_change("")
	await _frames(10)

	var tabs: TabContainer = view.get("_spawn_tabs")
	var systems: SystemGridBrowser = view.get("_systems_browser")
	var carts: SystemGridBrowser = view.get("_cartridges_browser")
	for filter: String in ["PlayStation", "Xbox"]:
		tabs.current_tab = systems.get_index()
		_filter(systems, filter)
		await _frames(10)
		await _shot("systems_" + filter.to_lower())
		tabs.current_tab = carts.get_index()
		_filter(carts, filter)
		await _frames(10)
		await _shot("cartridges_" + filter.to_lower())
	tabs.current_tab = systems.get_index()
	for sid: String in ["ps3", "xbox360"]:
		systems.open_system(sid)
		await _frames(10)
		await _shot("page_" + sid)
	print("[seventh-menu] done")
	get_tree().quit(0)


func _filter(browser: SystemGridBrowser, text: String) -> void:
	var edit: LineEdit = browser.get("_filter_edit")
	if edit == null:
		print("[seventh-menu] no filter box on %s" % browser.name)
		return
	edit.text = text
	edit.text_changed.emit(text)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_out, tag]
	print("[seventh-menu] shot %s -> %s (err=%d)" % [tag, path, img.save_png(path)])
