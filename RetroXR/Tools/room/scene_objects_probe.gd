## scene_objects_probe -- how SCENE > Objects and Locate's arrow look.
##
## Windowed only (the dummy renderer saves a blank image of the right size):
##   "$godot" --path RetroXR --resolution 1100x700 --position 20,20 ##       res://Tools/room/scene_objects_probe.tscn -- --out=C:/some/dir/
## Writes objects_page.png (the real SCENE view on its Objects page, one Delete
## asking again), locate_behind.png (menu shut, the located cartridge behind the
## player: the arrow on the left edge) and locate_side.png (turned part way).
extends Node

var _out := "user://scene_objects_probe/"


class Thing extends XRToolsPickable:
	var label := ""
	func display_name() -> String:
		return label


var _cam: XRCamera3D
var _page: SceneObjectsPage
var _canvas: CanvasLayer


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	var root := self
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	world.add_child(floor_mi)

	_cam = XRCamera3D.new()
	_cam.current = true
	world.add_child(_cam)
	_cam.position = Vector3(0, 1.6, 0)

	var items := [
		["Super Nintendo", Vector3(0.6, 0.8, -1.2), Color(0.6, 0.6, 0.65)],
		["Super Mario World", Vector3(-1.4, 0.05, 2.6), Color(0.85, 0.2, 0.2)],
		["Sony PlayStation", Vector3(2.5, 0.9, -3.0), Color(0.4, 0.4, 0.45)],
		["DualShock Controller", Vector3(-0.3, 0.7, -0.9), Color(0.15, 0.15, 0.18)],
		["Composite Cable", Vector3(4.0, 0.0, 1.0), Color(0.9, 0.8, 0.1)],
	]
	var things := []
	for it: Array in items:
		var t := Thing.new()
		t.label = it[0]
		t.freeze = true
		t.add_to_group("spawned")
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.12, 0.25)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = it[2]
		bm.material = mat
		mi.mesh = bm
		t.add_child(mi)
		world.add_child(t)
		t.global_position = it[1]
		things.append(t)

	_canvas = CanvasLayer.new()
	root.add_child(_canvas)
	var bg := ColorRect.new()
	bg.color = MenuStyle.COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(bg)
	# The real SCENE view, so the ribbon is in the picture too.
	var view := SpawnMenuSceneView.create()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_left = 24
	view.offset_right = -24
	view.offset_top = 16
	view.offset_bottom = -16
	_canvas.add_child(view)
	view.show_objects()
	_page = view.objects_page()
	_run(things)


func _run(things: Array) -> void:
	for i in 10:
		await get_tree().process_frame
	_page.refresh()
	# One tap on the PlayStation's Delete, so the confirm state is in the shot.
	for id: int in _page._ids:
		if _page._rows[id]["name"] == "Sony PlayStation":
			(_page._rows[id]["delete"] as Button).pressed.emit()
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_out + "objects_page.png")
	print("[probe] page rows=%d" % _page._ids.size())

	# Leg 2: Locate the cartridge behind the player, menu shut.
	for id: int in _page._ids:
		if _page._rows[id]["name"] == "Super Mario World":
			_page._on_locate(_page._rows[id])
	_canvas.visible = false
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_out + "locate_behind.png")
	var arrow := LocateArrow.on(_cam)
	print("[probe] arrow visible=%s pos=%s" % [arrow.visible, arrow.position])
	# Turned 60 degrees toward it and looking down: still off to the left.
	_cam.rotation_degrees = Vector3(-25, 60, 0)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_out + "locate_side.png")
	print("[probe] arrow visible=%s pos=%s" % [arrow.visible, arrow.position])
	get_tree().quit(0)
