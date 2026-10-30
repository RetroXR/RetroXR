## Windowed: saves a slot in the bedroom with the spawn menu OPEN in front of the
## eye, then draws the SCENE tab's room grid and slot grid, to see the pictures.
## Scratch data home:  APPDATA=/tmp/scratch "$godot" --path RetroXR --resolution 1100x800 \
##     res://Tools/room/scene_cards_probe.tscn
extends Node


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[cards] TIMEOUT")
		get_tree().quit(1))
	var room := (load(RoomCatalog.path_of("bedroom")) as PackedScene).instantiate()
	add_child(room)
	await get_tree().create_timer(10.0).timeout
	var eye := get_viewport().get_camera_3d()
	eye.global_position = Vector3(-1.2, 1.5, 1.4)
	eye.look_at(Vector3(1.2, 1.1, -1.5), Vector3.UP)
	# The menu's screen, square in front of the eye, as it is when Save is pressed.
	var menu: Node3D = null
	for n in get_tree().get_nodes_in_group(SceneThumbnail.HIDDEN_GROUP):
		if n.get_parent().name == "SpawnMenuViewport":
			menu = n.get_parent() as Node3D
	print("[cards] menu screen found: %s" % (menu != null))
	if menu != null:
		menu.visible = true
		menu.global_transform = Transform3D(eye.global_basis, eye.global_position - eye.global_basis.z * 1.2)
	await get_tree().process_frame
	var sp := ScenePersistence.new("bedroom")
	var id := sp.create_new_slot(room, "State 1")
	var refused: bool = await SceneThumbnail.capture(sp.thumbnail_path(id), false)
	print("[cards] capture without hiding refused: %s" % (not refused))
	var ok: bool = await SceneThumbnail.capture(sp.thumbnail_path(id), true)
	print("[cards] capture with the menu up: %s, menu visible after: %s" % [ok, menu.visible if menu else false])
	SceneManager.set_active_slot(id, "bedroom")
	if menu != null:
		menu.visible = false
	get_viewport().get_texture().get_image().save_png("user://cards_room_view.png")

	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var view := SpawnMenuSceneView.create()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(view)
	view.show_rooms()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://cards_rooms.png")
	view.show_states("bedroom")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://cards_slots.png")
	print("[cards] done")
	get_tree().quit(0)
