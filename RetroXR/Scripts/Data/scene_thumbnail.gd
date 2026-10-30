## SceneThumbnail — the picture on a SCENE tab card.
##
## A save slot's picture is the room as the player saw it when it was saved: one
## frame drawn from their eyes into a viewport of its own, written beside the
## slot's file as <slot id>.png. A room card shows its active slot's picture, else
## the newest any of its slots has, else the room's stock image (RoomCatalog's
## `thumbnail`, which a mod's register_room may give), else its colour.
##
## The viewport is GbCameraEye's arrangement: it shares the room's world, its
## Camera3D goes UNDER it (anywhere else it would become the player's camera) and
## it draws ONCE, never UPDATE_ALWAYS. Nodes in HIDDEN_GROUP (the spawn menu's
## screen) are hidden for that frame, which the player sees as the menu blinking
## once as a shutter does; a capture that must not blink (the periodic autosave)
## is skipped instead while one of them is showing.
class_name SceneThumbnail
extends RefCounted

## 16:9. A room card is half the 2200 px menu wide, and 384 read soft across it.
const SIZE := Vector2i(640, 360)
## Narrower than a headset's: the edges of a VR view are mostly the player's hands.
const FOV_DEGREES := 65.0
const HIDDEN_GROUP := "snapshot_hidden"

## path -> [modified time, Texture2D]. A card is rebuilt every time the grid is,
## and decoding the same PNG again each time is waste.
static var _cache: Dictionary = {}
static var _busy := false


## Draw the room from the player's eyes and write it to `path`. A coroutine:
## await it for the answer, true once the PNG is on disk. `hide_ui` says whether
## the menu may blink for it; without it a capture with the menu up is skipped.
static func capture(path: String, hide_ui: bool) -> bool:
	if DisplayServer.get_name() == "headless":
		# The dummy renderer hands back a correctly sized BLANK image, which would
		# be written as a black picture and shown as one.
		print("[SceneThumbnail] headless, no picture for %s" % path)
		return false
	if _busy:
		print("[SceneThumbnail] a capture is already running, skipped %s" % path)
		return false
	var tree := Engine.get_main_loop() as SceneTree
	var room := tree.current_scene if tree != null else null
	var eye := tree.root.get_camera_3d() if tree != null else null
	if room == null or eye == null:
		print("[SceneThumbnail] no room or no camera (room=%s eye=%s), skipped %s"
			% [room != null, eye != null, path])
		return false

	var hidden: Array[Node3D] = []
	for node: Node in tree.get_nodes_in_group(HIDDEN_GROUP):
		var n3 := node as Node3D
		if n3 == null or not n3.is_visible_in_tree():
			continue
		if not hide_ui:
			print("[SceneThumbnail] %s is showing, skipped %s" % [n3.name, path])
			return false
		hidden.append(n3)

	_busy = true
	var vp := SubViewport.new()
	vp.name = "SceneThumbnail"
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	# The room's omni and spot lights shadow through this atlas; a quarter of the
	# default is plenty at this size and is all the memory the frame borrows.
	vp.positional_shadow_atlas_size = 1024
	vp.gui_disable_input = true
	var cam := Camera3D.new()
	cam.fov = FOV_DEGREES
	cam.near = 0.05
	cam.far = maxf(eye.far, 50.0)
	cam.cull_mask = eye.cull_mask
	cam.environment = eye.environment
	cam.attributes = eye.attributes
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.add_child(cam)
	room.add_child(vp)
	# The flag: make_current() does not work inside a SubViewport.
	cam.current = true
	cam.global_transform = _level(eye.global_transform)

	for n3 in hidden:
		n3.visible = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(vp):
		img = vp.get_texture().get_image()
		vp.queue_free()
	for n3 in hidden:
		if is_instance_valid(n3):
			n3.visible = true
	if img == null or img.is_empty():
		_busy = false
		print("[SceneThumbnail] nothing was drawn (the room left mid-capture?), skipped %s" % path)
		return false

	# Encoding is the slow part; off the main thread, as the slot's own JSON is.
	# Written aside and renamed, so a card never reads half a PNG.
	var tmp := path + ".tmp"
	var result := [ERR_BUG]
	var job := func() -> void:
		result[0] = img.save_png(tmp)
		if result[0] == OK:
			result[0] = DirAccess.rename_absolute(tmp, path)
	var task := WorkerThreadPool.add_task(job, false, "scene thumbnail")
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_busy = false
	_cache.erase(path)
	if result[0] != OK:
		print("[SceneThumbnail] write failed (%s): %s" % [error_string(result[0]), path])
		DirAccess.remove_absolute(tmp)
		return false
	print("[SceneThumbnail] wrote %s (%dx%d, hid %d)" % [path, img.get_width(), img.get_height(),
		hidden.size()])
	return true


## Whether a slot's picture is missing or older than the slot's own file beside
## it, i.e. the room was saved since the picture was taken.
static func is_stale(picture_path: String) -> bool:
	var slot_file := picture_path.get_basename() + ".json"
	if not FileAccess.file_exists(slot_file):
		return false
	if not FileAccess.file_exists(picture_path):
		return true
	return FileAccess.get_modified_time(picture_path) < FileAccess.get_modified_time(slot_file)


## The head's pose without its roll, so a tilted head does not give a tilted
## picture. Straight up or down there is no level to find, and it is kept as is.
static func _level(head: Transform3D) -> Transform3D:
	var forward := -head.basis.z.normalized()
	if absf(forward.dot(Vector3.UP)) > 0.98:
		return Transform3D(head.basis.orthonormalized(), head.origin)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), head.origin)


## A picture, from res:// (shipped, a mod's) or from a slot's PNG, or null.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	if not FileAccess.file_exists(path):
		_cache.erase(path)
		return null
	var mtime := FileAccess.get_modified_time(path)
	var hit: Array = _cache.get(path, [])
	if not hit.is_empty() and hit[0] == mtime:
		return hit[1]
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		print("[SceneThumbnail] could not read %s" % path)
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[path] = [mtime, tex]
	return tex


## A slot's picture: its own PNG, or for Clean Room (the room as it ships) the
## room's stock image.
static func for_slot(room_id: String, slot_id: String) -> Texture2D:
	if slot_id == "clean":
		return load_texture(RoomCatalog.thumbnail_of(room_id))
	return load_texture(ScenePersistence.new(room_id).thumbnail_path(slot_id))


## A room card's picture: the active slot's, else the newest any slot has, else
## the room's stock image, else null (the card keeps its colour).
static func for_room(room_id: String, active_slot: String) -> Texture2D:
	if RoomCatalog.has_slots(room_id):
		var persistence := ScenePersistence.new(room_id)
		if active_slot != "clean":
			var own := load_texture(persistence.thumbnail_path(active_slot))
			if own != null:
				return own
		var newest := ""
		var newest_time := -1
		for slot: Dictionary in persistence.get_slots():
			var p := persistence.thumbnail_path(str(slot.get("id", "")))
			if slot.get("readonly", false) or not FileAccess.file_exists(p):
				continue
			var t := FileAccess.get_modified_time(p)
			if t > newest_time:
				newest_time = t
				newest = p
		if not newest.is_empty():
			return load_texture(newest)
	return load_texture(RoomCatalog.thumbnail_of(room_id))
