## The PocketStation's own menu (the card panel a VMU has), on a card carrying a real
## app, captured tab by tab; then the unit switched on from it and the room looked at.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/pocketstation_menu_probe.tscn -- \
##         --image=<a PS1 card .mcr> --out=<dir> [--root=<scratch libretro root>]
##
## --root: a libretro root holding cores/pokket_libretro.dll and system/pokket/pocketstation.bin
## (the unit's core_directory); without it the panel shows what a room with no Pokket shows.
##
## Windowed, never headless: the panel is a SubViewport, and the dummy renderer hands back
## a blank image at the right size. The card image goes into the player's real memory card
## folder under a name no player would use, and is removed at the end.
extends Node

const UNIT := "res://Scenes/Objects/peripherals/pocketstation.tscn"
const CARD_ID := "__PS_MENU_PROBE"

var image_path := ""
var root_dir := ""
var out_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--image="):
			image_path = a.trim_prefix("--image=").replace("\\", "/")
		elif a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[psmenu] TIMEOUT")
		_cleanup()
		get_tree().quit(1))
	get_tree().current_scene = self
	if out_dir.is_empty() or not FileAccess.file_exists(image_path):
		print("[psmenu] need --image= and --out=")
		get_tree().quit(1)
		return
	await _run()
	_cleanup()
	get_tree().quit(0)


func _cleanup() -> void:
	for p: String in [SramPaths.card_save_path("playstation", CARD_ID),
			PocketStation.PLAY_DIR.path_join("%s.mcr" % CARD_ID)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.2
	add_child(sun)

	if not AtomicFile.write_bytes(SramPaths.card_save_path("playstation", CARD_ID),
			FileAccess.get_file_as_bytes(image_path), "pocketstation_menu_probe"):
		print("[psmenu] could not write the fixture card")
		return
	var ps := (load(UNIT) as PackedScene).instantiate() as PocketStation
	ps.card_id = CARD_ID
	ps.card_label = "POCKETSTATION 1"
	if not root_dir.is_empty():
		ps.core_directory = root_dir
	add_child(ps)
	ps.freeze = true
	ps.global_position = Vector3(0, 1.0, 0)
	# Screen up, tipped toward the eye, as a hand holds one.
	ps.rotation_degrees = Vector3(50, 0, 0)

	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 960)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 50.0
	sv.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.10, 0.42), Vector3(0, 1.06, 0), Vector3.UP)
	cam.current = true
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	await get_tree().process_frame
	print("[psmenu] blocker '%s'" % ps.standalone_blocker())

	ps.toggle_options_ui(cam)
	var panel: MemoryCardPanel = null
	for c in ps.get_children():
		if c is MemoryCardPanel:
			panel = c
	if panel == null:
		print("[psmenu] FAIL no panel")
		return
	for i in 20:
		await get_tree().process_frame
	var vp := panel.get_node_or_null("MemoryCardViewport/Viewport") as SubViewport
	var tabs := _find_tabs(vp)
	if vp == null or tabs == null:
		print("[psmenu] FAIL no viewport (%s) or tabs (%s)" % [vp, tabs])
		return
	for t in tabs.get_tab_count():
		if tabs.is_tab_hidden(t):
			print("[psmenu] tab %d %s hidden" % [t, tabs.get_tab_title(t)])
			continue
		tabs.current_tab = t
		await _settle()
		_save(vp.get_texture().get_image(), "panel_%d_%s.png" % [t, tabs.get_tab_title(t).to_lower()])
	tabs.current_tab = 0
	await _settle()
	_save(sv.get_texture().get_image(), "room_menu.png")

	# Switched on from its own card, as the Games tab's Play does.
	if ps.standalone_blocker().is_empty() and ps.power_on(ps.image_path(), "POCKETSTATION 1"):
		var lib: Object = ps.get("_lib")
		var deadline := Time.get_ticks_msec() + 30000
		while int(lib.GetFrameCount()) < 200 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		# Opened afresh, as a player would open it on a running unit.
		panel.hide_panel()
		await _settle()
		ps.toggle_options_ui(cam)
		await _settle()
		tabs.current_tab = 0
		await _settle()
		_save(vp.get_texture().get_image(), "panel_running.png")
		panel.hide_panel()
		await _settle()
		cam.look_at_from_position(Vector3(0.0, 1.075, 0.16), Vector3(0, 1.0, 0), Vector3.UP)
		await _settle()
		_save(sv.get_texture().get_image(), "room_running.png")
		ps.power_off()
		for i in 120:
			await get_tree().process_frame
	else:
		print("[psmenu] not switched on: '%s'" % ps.standalone_blocker())


func _find_tabs(n: Node) -> TabContainer:
	if n == null:
		return null
	if n is TabContainer:
		return n
	for c in n.get_children():
		var t := _find_tabs(c)
		if t != null:
			return t
	return null


func _settle() -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame


func _save(img: Image, file: String) -> void:
	if img == null or img.is_empty():
		print("[psmenu] %s: no image" % file)
		return
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGB8)
	var p := out_dir.path_join(file)
	copy.save_png(p)
	print("[psmenu] wrote %s (%dx%d)" % [p, copy.get_width(), copy.get_height()])
