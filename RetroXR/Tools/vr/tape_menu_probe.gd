## Tape menu probe -- does the generic object menu over a VHS tape and a cassette
## show the tape's place and its path, grow to hold them, and keep up as the
## place moves? A plain pickable beside them is the control: its menu must keep
## the size it always had. Windowed, because the pages are SubViewports:
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/vr/tape_menu_probe.tscn -- --out=<dir>
extends Node

const VCR_TAPE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const AUDIO_CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")

var _fail := 0
var _out := ""


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	await _run()
	print("[probe] ---- %s ----" % ("all checks passed" if _fail == 0 else "%d FAILED" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, what: String, detail := "") -> void:
	if not cond:
		_fail += 1
	print("[probe] %s  %s%s" % ["PASS" if cond else "FAIL", what,
		"" if detail.is_empty() else "  - " + detail])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shoot(tex: Texture2D, name: String) -> void:
	if _out.is_empty():
		return
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := _out.path_join(name)
	img.save_png(path)
	print("[probe] wrote %s" % path)


func _page(obj: Node3D) -> XRToolsViewport2DIn3D:
	var panel := obj.get_node_or_null(ObjectOptionsPanel.NODE_NAME)
	return panel.get_node("ObjectOptionsViewport") as XRToolsViewport2DIn3D if panel else null


func _ui(obj: Node3D) -> ObjectOptions2D:
	return _page(obj).get_node("Viewport").get_child(0) as ObjectOptions2D


func _run() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1200, 700)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	sv.add_child(env)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.25, 0.9), Vector3(0.0, 0.2, 0.0), Vector3.UP)

	var vhs := VCR_TAPE.instantiate() as VCRTape
	vhs.video_path = "C:/Users/rymcc/retroxr/videos/Back to the Future Part II (1989).mp4"
	vhs.video_label = "Back to the Future Part II (1989)"
	vhs.tape_time = 3754.0
	vhs.tape_progress = 0.48
	sv.add_child(vhs)
	vhs.freeze = true
	vhs.position = Vector3(-0.4, 0.0, 0.0)

	var cass := AUDIO_CASSETTE.instantiate() as AudioCassette
	cass.album_path = "C:/Users/rymcc/retroxr/music/Pink Floyd - The Dark Side of the Moon"
	cass.album_label = "The Dark Side of the Moon"
	cass.tape_track = 3
	cass.tape_time = 141.0
	cass.tape_progress = 0.41
	sv.add_child(cass)
	cass.freeze = true

	# The control: a pickable with nothing to tell.
	var plain := XRToolsPickable.new()
	plain.name = "PlainBox"
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	box.mesh = bm
	plain.add_child(box)
	sv.add_child(plain)
	plain.freeze = true
	plain.position = Vector3(0.4, 0.0, 0.0)

	await _frames(2)
	for obj: Node3D in [vhs, cass, plain]:
		ObjectOptionsPanel.toggle_for(obj, cam)
	await _frames(20)

	for obj: Node3D in [vhs, cass]:
		var v := _page(obj)
		var ui := _ui(obj)
		var need := ui.content_height()
		_ok(v.viewport_size.y > 100.0 + FloatingObjectPanel3D.LOCK_ROW_PX,
			"%s: the page grew past title + lock row" % obj.name, "page %s" % v.viewport_size)
		_ok(absf(v.viewport_size.y - ceilf(need)) <= 1.0,
			"%s: and is as tall as what is on it" % obj.name, "page %.0f, content %.1f" % [v.viewport_size.y, need])
		_ok(ui._panel.get_combined_minimum_size().x <= v.viewport_size.x,
			"%s: and no wider than the page (nothing clipped off the right)" % obj.name,
			"content %.0f px wide" % ui._panel.get_combined_minimum_size().x)
		_ok(is_equal_approx(v.screen_size.y / v.viewport_size.y, 0.1 / 100.0),
			"%s: at the density it was authored at" % obj.name, "screen %s" % v.screen_size)
		var box_v := ui._info.get_parent()
		_ok(box_v.get_child(box_v.get_child_count() - 1).name == "LockRow" and ui._info.get_index() == 1,
			"%s: title, then info, then the lock row" % obj.name)
		print("[probe] %s rows: %s" % [obj.name, ui._info.get_children().map(
			func(r: Node) -> String: return (r.get_child(1) as Label).text)])

	var pv := _page(plain)
	_ok(is_equal_approx(pv.viewport_size.y, 100.0 + FloatingObjectPanel3D.LOCK_ROW_PX),
		"control: a menu with nothing to tell keeps its size", "page %s, content %.1f" % [
			pv.viewport_size, _ui(plain).content_height()])
	_ok(not _ui(plain)._info.visible, "control: and shows no info")
	_ok((_ui(vhs)._title.text == "Back to the Future Part II (1989)"),
		"vhs: titled with its video", _ui(vhs)._title.text)

	await RenderingServer.frame_post_draw
	await _frames(2)
	_shoot(sv.get_texture(), "tape_menu_room.png")
	_shoot(_page(vhs).get_node("Viewport").get_texture(), "tape_menu_vhs.png")
	_shoot(_page(cass).get_node("Viewport").get_texture(), "tape_menu_cassette.png")
	_shoot(pv.get_node("Viewport").get_texture(), "tape_menu_control.png")

	# The place moves while the menu is up (a deck playing it): the row follows,
	# and the page does not change size for a time that is one line either way.
	var before := _page(vhs).viewport_size
	vhs.tape_time = 3755.0
	await _frames(3)
	var pos_text := (_ui(vhs)._info.get_child(0).get_child(1) as Label).text
	_ok(pos_text.begins_with("01:02:35"), "vhs: a moved place shows in the open menu", pos_text)
	_ok(_page(vhs).viewport_size == before, "vhs: and the page keeps its size")
