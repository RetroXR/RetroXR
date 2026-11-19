extends Control
## The spawn menu's OPTIONS > Systems page in a NARROW window, saved as a PNG:
## long descriptions must wrap inside the panel, not run off its right edge.
## Windowed only. `-- --out=<png> --view=<spawn|cores|...> --tab=<n>` (tab: OPTIONS only).

const SPAWN_MENU := preload("res://Scenes/UI/spawn_menu.tscn")


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void: get_tree().quit(2))
	var out := "user://menu_wrap_probe.png"
	var tab := 1
	var view := "options"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--tab="):
			tab = int(a.substr(6))
		elif a.begins_with("--view="):
			view = a.substr(7)
	SceneManager.current_scene_id = "test"
	var vp := SubViewport.new()
	vp.size = Vector2i(1900, 1500)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var host := Control.new()
	host.size = Vector2(vp.size)
	vp.add_child(host)
	var menu := SPAWN_MENU.instantiate()
	host.add_child(menu)
	for i in 6: await get_tree().process_frame
	menu.call("_show_%s_view" % view)
	var tabs := menu.find_children("*", "TabContainer", true, false)
	for t: TabContainer in tabs:
		if view == "options" and t.get_tab_count() > tab and t.is_visible_in_tree():
			t.current_tab = tab
	for i in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out)
	# What the page's labels force the panel to: the fault widens it past the view.
	var panel := menu.find_children("*", "PanelContainer", false, false)[0] as Control
	var need := panel.get_combined_minimum_size().x * float(menu.get("ui_scale"))
	print("[menu-wrap-probe] view %d, panel needs %.0f -> %s" % [vp.size.x, need,
		"FITS" if need <= vp.size.x + 1 else "OVERFLOWS"])
	get_tree().quit(0)
