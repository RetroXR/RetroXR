## Real room self-tests — the player's real room inside the passthrough room: the
## consent asked once, Meta's scene manager under the origin, every scanned thing
## a surface to rest on (the mesh over the furniture boxes), the player's body let
## through it all, the room-scan notice, the depth that occlusion and a Game Boy
## Camera share, and the occlusion switch.
##
## No headset, no Meta: the scene manager, its entities, the depth extension and
## the player's body are stood in for. What the real ones do on a Quest 3 is
## Tools/av/spatial_probe.
##
##     "$godot" --headless --path RetroXR res://Tests/real_room_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/real_room_tests.tscn -- --only=surfaces
##
## Exits 0 when everything passes, 1 otherwise.
extends "res://Tests/test_suite.gd"

var _only := ""


## An OpenXRFbSpatialEntity, as far as RealRoomSurface asks.
class FakeEntity:
	extends RefCounted
	var labels := PackedStringArray()
	var mesh := false

	func _init(of: PackedStringArray, is_mesh := false) -> void:
		labels = of
		mesh = is_mesh

	func get_semantic_labels() -> PackedStringArray:
		return labels

	func create_collision_shape() -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		if mesh:
			var c := ConcavePolygonShape3D.new()
			c.set_faces(PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK]))
			cs.shape = c
		else:
			cs.shape = BoxShape3D.new()
		return cs


## OpenXRFbSceneManager: what RealRoom sets and listens to, and an anchor made
## the way the real one makes one (the default scene under an anchor node,
## setup_scene, then the signal).
class FakeManager:
	extends Node3D
	signal openxr_fb_scene_anchor_created(node: Object, entity: Object)
	signal openxr_fb_scene_data_missing
	signal openxr_fb_scene_capture_completed(success: bool)
	var default_scene: PackedScene = null
	var auto_create := false
	var captures := 0
	var capture_supported := true
	var removes := 0
	var creates := 0

	func is_scene_capture_supported() -> bool:
		return capture_supported

	func request_scene_capture() -> bool:
		captures += 1
		return true

	func remove_scene_anchors() -> void:
		removes += 1
		for c in get_children():
			c.queue_free()

	func create_scene_anchors() -> void:
		creates += 1

	func make_anchor(entity: FakeEntity) -> RealRoomSurface:
		var anchor := Node3D.new()
		add_child(anchor)
		var surface := default_scene.instantiate() as RealRoomSurface
		anchor.add_child(surface)
		surface.setup_scene(entity)
		openxr_fb_scene_anchor_created.emit(anchor, entity)
		return surface


## OpenXRMetaEnvironmentDepthExtension.
class FakeDepth:
	extends RefCounted
	var supported := true
	var started := false
	var starts := 0
	var stops := 0

	func is_environment_depth_supported() -> bool:
		return supported

	func is_environment_depth_started() -> bool:
		return started

	func start_environment_depth() -> void:
		starts += 1
		started = true

	func stop_environment_depth() -> void:
		stops += 1
		started = false


func _ready() -> void:
	suite_tag = "room"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[room] TIMEOUT")
		get_tree().quit(1))

	if _wants("kinds"):
		_test_kinds()
	if _wants("consent"):
		await _test_consent()
	if _wants("surfaces"):
		await _test_surfaces()
	if _wants("depth"):
		_test_depth()
	if _wants("occlusion"):
		await _test_occlusion()
	if _wants("spatial"):
		await _test_spatial()
	if _wants("prefs"):
		_test_prefs()
	if _wants("setup"):
		await _test_setup()
	if _wants("rig"):
		await _test_rig()
	if _wants("overlay"):
		await _test_overlay()
	if _wants("support"):
		_test_support()
	if _wants("project"):
		_test_project()

	_reset_statics()
	_finish()


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _reset_statics() -> void:
	PassthroughSupport.mesh_seen = false
	SpatialPermission.reset()
	EnvironmentDepth.reset()
	RealRoom.reset_notice()


## A RealRoom with every outside thing stood in for, and what it was handed.
func _room(granted: Dictionary, rig: Dictionary) -> RealRoom:
	# "Use Room Data in Passthrough" on, unless a case says otherwise.
	if not SpatialPermission.wanted_source.is_valid():
		SpatialPermission.wanted_source = func() -> bool: return true
	SpatialPermission.granted_source = func() -> PackedStringArray:
		return PackedStringArray(["com.oculus.permission.USE_SCENE"]) if granted["on"] else PackedStringArray()
	var room := RealRoom.new()
	room.manager_factory = func() -> Object:
		rig["managers"] = int(rig["managers"]) + 1
		return FakeManager.new()
	room.origin_source = func() -> Node: return rig["origin"]
	room.camera_source = func() -> Node3D: return rig["camera"]
	room.player_body_source = func() -> PhysicsBody3D: return rig["body"]
	room.mesh_pref_source = func() -> bool: return bool(rig.get("mesh", false))
	room.notice_sink = func(title: String, text: String) -> void:
		(rig["notices"] as Array).append([title, text])
	add_child(room)
	return room


func _rig() -> Dictionary:
	var origin := Node3D.new()
	add_child(origin)
	var camera := Node3D.new()
	origin.add_child(camera)
	var body := CharacterBody3D.new()
	add_child(body)
	return {"origin": origin, "camera": camera, "body": body, "managers": 0, "notices": []}


func _free_rig(rig: Dictionary) -> void:
	for k in ["origin", "body"]:
		if is_instance_valid(rig[k]):
			(rig[k] as Node).queue_free()


func _test_kinds() -> void:
	_ok(RealRoomSurface.kind_for(PackedStringArray(["GLOBAL_MESH"])) == RealRoomSurface.Kind.MESH,
		"kinds/the room's scan is the mesh")
	_ok(RealRoomSurface.kind_for(PackedStringArray(["table"])) == RealRoomSurface.Kind.FURNITURE
		and RealRoomSurface.kind_for(PackedStringArray(["COUCH"])) == RealRoomSurface.Kind.FURNITURE,
		"kinds/a table or a couch is furniture, whatever case the label comes in")
	_ok(RealRoomSurface.kind_for(PackedStringArray(["FLOOR"])) == RealRoomSurface.Kind.FACE
		and RealRoomSurface.kind_for(PackedStringArray(["WALL_FACE"])) == RealRoomSurface.Kind.FACE,
		"kinds/the floor and a wall are faces of the room")
	_ok(RealRoomSurface.kind_for(PackedStringArray(["DOOR_FRAME"])) == RealRoomSurface.Kind.NONE
		and RealRoomSurface.kind_for(PackedStringArray()) == RealRoomSurface.Kind.NONE,
		"kinds/a door frame, or nothing said, is nothing to rest on")


func _test_consent() -> void:
	var granted := {"on": false}
	var asked: Array = []
	SpatialPermission.request_sink = func(p: String) -> void: asked.append(p)
	var rig := _rig()
	var room := _room(granted, rig)
	room.start()
	_ok(asked.size() == SpatialPermission.PERMISSIONS.size() and int(rig["managers"]) == 0,
		"consent/without the player's consent it is asked for, and the room is not read",
		"%d asked, %d managers" % [asked.size(), int(rig["managers"])])
	room.start()
	_ok(asked.size() == SpatialPermission.PERMISSIONS.size(), "consent/asked once a run, not every time")
	granted["on"] = true
	room.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_ok(room.has_manager() and int(rig["managers"]) == 1,
		"consent/given while the app was away, the room is read when it comes back")
	var manager := (rig["origin"] as Node).get_node_or_null("RealRoomScene") as FakeManager
	_ok(manager != null and manager.default_scene == RealRoom.SURFACE_SCENE and manager.auto_create,
		"consent/the scene manager goes under the origin, making a surface of everything")
	room.start()
	_ok(int(rig["managers"]) == 1, "consent/and is made once")
	room.queue_free()
	await get_tree().process_frame
	_ok(not is_instance_valid(manager) or manager.is_queued_for_deletion(),
		"consent/the room gone, its manager on the rig goes with it")
	_free_rig(rig)
	_reset_statics()


func _test_surfaces() -> void:
	var granted := {"on": true}
	var rig := _rig()
	var room := _room(granted, rig)
	room.start()
	var manager := (rig["origin"] as Node).get_node("RealRoomScene") as FakeManager
	var body := rig["body"] as CharacterBody3D

	var table := manager.make_anchor(FakeEntity.new(PackedStringArray(["TABLE"])))
	_ok(table.kind == RealRoomSurface.Kind.FURNITURE and table.collision_layer == RealRoomSurface.WORLD_LAYER
		and table.collision_mask == 0, "surfaces/a table is solid on the world layer, where every room's tables are")
	_ok(table.get_child_count() == 1 and table.get_child(0) is CollisionShape3D,
		"surfaces/its shape is the one Meta builds for it")
	_ok(table in body.get_collision_exceptions() and table in room.surfaces(),
		"surfaces/and the player's body passes through it: leaning over it moves nothing")
	var wall := manager.make_anchor(FakeEntity.new(PackedStringArray(["WALL_FACE"])))
	_ok(wall.is_in_group(RealRoomSurface.POSTER_GROUP) and wall.collision_layer == RealRoomSurface.WORLD_LAYER,
		"surfaces/a wall is solid, and a poster presses flat against it")
	var door := manager.make_anchor(FakeEntity.new(PackedStringArray(["DOOR_FRAME"])))
	_ok(door.collision_layer == 0 and door.get_child_count() == 0, "surfaces/a door frame is nothing")

	var mesh := manager.make_anchor(FakeEntity.new(PackedStringArray(["GLOBAL_MESH"]), true))
	_ok(mesh.collision_layer == 0 and table.collision_layer == RealRoomSurface.WORLD_LAYER
		and (mesh.get_child(0) as CollisionShape3D).shape is ConcavePolygonShape3D,
		"surfaces/flat by default: the table's box is solid and the scanned mesh is not")
	rig["mesh"] = true
	room.refresh_room_shape()
	_ok(mesh.collision_layer == RealRoomSurface.WORLD_LAYER,
		"surfaces/with Detailed Room Mesh, the room's mesh is solid, its real shape")
	_ok(table.collision_layer == 0 and wall.collision_layer == RealRoomSurface.WORLD_LAYER,
		"surfaces/and the table's box is not: things rest where the desk's things are; walls stay")
	var couch := manager.make_anchor(FakeEntity.new(PackedStringArray(["COUCH"])))
	_ok(couch.collision_layer == 0, "surfaces/furniture scanned after the mesh is not solid either")
	rig["mesh"] = false
	room.refresh_room_shape()
	_ok(mesh.collision_layer == 0 and table.collision_layer == RealRoomSurface.WORLD_LAYER
		and couch.collision_layer == RealRoomSurface.WORLD_LAYER,
		"surfaces/switched back to flat, the boxes are solid again and the mesh is not")

	manager.openxr_fb_scene_data_missing.emit()
	manager.openxr_fb_scene_data_missing.emit()
	var notices: Array = rig["notices"]
	_ok(notices.size() == 1 and "Set Up Room" in str(notices[0][1]),
		"surfaces/no room scanned: the player is told where to scan it, once", str(notices))

	room.queue_free()
	await get_tree().process_frame
	_ok(body.get_collision_exceptions().is_empty(), "surfaces/the room gone, the player's body excepts nothing")
	_free_rig(rig)
	_reset_statics()


func _test_depth() -> void:
	var ext := FakeDepth.new()
	EnvironmentDepth.extension_source = func() -> Object: return ext
	var available := {"on": false}
	EnvironmentDepth.available_source = func() -> bool: return available["on"]
	var wanted := {"on": true}
	SpatialPermission.wanted_source = func() -> bool: return wanted["on"]
	SpatialPermission.granted_source = func() -> PackedStringArray: return PackedStringArray()
	var a := RefCounted.new()
	var b := RefCounted.new()
	_ok(not EnvironmentDepth.acquire(a) and ext.starts == 0, "depth/without consent there is no depth")
	SpatialPermission.granted_source = func() -> PackedStringArray:
		return PackedStringArray(["horizonos.permission.USE_SCENE"])
	_ok(EnvironmentDepth.acquire(a) and EnvironmentDepth.acquire(b) and EnvironmentDepth.acquire(a)
		and ext.starts == 1, "depth/given it, two holders start it once")
	_ok(not EnvironmentDepth.is_running(), "depth/started is not running until a depth frame has come")
	available["on"] = true
	_ok(EnvironmentDepth.is_running(), "depth/then it is")
	EnvironmentDepth.release(a)
	_ok(ext.stops == 0 and EnvironmentDepth.is_running(), "depth/one letting go stops nothing")
	EnvironmentDepth.release(b)
	EnvironmentDepth.release(b)
	_ok(ext.stops == 1 and not EnvironmentDepth.is_running(), "depth/the last stops it, once")
	ext.supported = false
	_ok(not EnvironmentDepth.acquire(a), "depth/a headset without it is never started")
	ext.supported = true
	wanted["on"] = false
	_ok(not EnvironmentDepth.acquire(a), "depth/nor with room data switched off, consent or not")
	wanted["on"] = true
	_ok(EnvironmentDepth.acquire(a) and EnvironmentDepth.acquire(b) and EnvironmentDepth.holds(a), "depth/on again, it is")
	var stops_before := ext.stops
	EnvironmentDepth.drop_all()
	_ok(not EnvironmentDepth.is_held() and ext.stops == stops_before + 1 and not EnvironmentDepth.holds(a),
		"depth/switched off mid-session, every holder's depth stops at once")
	EnvironmentDepth.release(a)
	_ok(ext.stops == stops_before + 1, "depth/and a holder letting go after stops nothing more")
	_reset_statics()


## Plain passthrough, or the room read too: "Use Room Data in Passthrough".
func _test_spatial() -> void:
	var granted := {"on": false}
	var wanted := {"on": false}
	var asked: Array = []
	SpatialPermission.wanted_source = func() -> bool: return wanted["on"]
	SpatialPermission.request_sink = func(p: String) -> void: asked.append(p)
	var ext := FakeDepth.new()
	EnvironmentDepth.extension_source = func() -> Object: return ext
	var rig := _rig()
	var room := _room(granted, rig)
	room.occlusion_pref_source = func() -> bool: return true
	room.occlusion_factory = func() -> Object: return MeshInstance3D.new()
	room.start()
	_ok(asked.is_empty() and not room.has_manager() and not room.has_occlusion(),
		"spatial/switched off: plain passthrough asks for nothing and reads nothing")
	wanted["on"] = true
	room.refresh_spatial()
	_ok(asked.size() == SpatialPermission.PERMISSIONS.size() and not room.has_manager(),
		"spatial/switched on, the consent is asked for")
	granted["on"] = true
	room.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_ok(room.has_manager() and room.has_occlusion() and ext.starts == 1,
		"spatial/given, the room is read: furniture, depth, occlusion")
	var manager := (rig["origin"] as Node).get_node("RealRoomScene") as FakeManager
	var table := manager.make_anchor(FakeEntity.new(PackedStringArray(["TABLE"])))
	var body := rig["body"] as CharacterBody3D
	wanted["on"] = false
	room.refresh_spatial()
	await get_tree().process_frame
	_ok(not room.has_manager() and not is_instance_valid(manager) and not room.has_occlusion(),
		"spatial/switched off, all of it is put away")
	_ok(ext.stops == 1 and not EnvironmentDepth.is_held() and body.get_collision_exceptions().is_empty(),
		"spatial/its depth stopped, and the player's body excepts nothing")
	_ok(not is_instance_valid(table), "spatial/and the real table is gone with it")
	wanted["on"] = true
	room.refresh_spatial()
	_ok(room.has_manager() and room.has_occlusion() and ext.starts == 2,
		"spatial/switched on again with consent given, it is all back at once")
	room.queue_free()
	_free_rig(rig)
	await get_tree().process_frame
	_reset_statics()


func _test_occlusion() -> void:
	var ext := FakeDepth.new()
	EnvironmentDepth.extension_source = func() -> Object: return ext
	var granted := {"on": true}
	var rig := _rig()
	var room := _room(granted, rig)
	var pref := {"on": true}
	room.occlusion_pref_source = func() -> bool: return pref["on"]
	room.occlusion_factory = func() -> Object: return MeshInstance3D.new()
	room.start()
	var node := (rig["camera"] as Node).get_node_or_null("RealRoomOcclusion") as MeshInstance3D
	_ok(room.has_occlusion() and node != null and ext.starts == 1,
		"occlusion/on: Meta's occlusion goes over the player's eyes, on its depth")
	_ok(node != null and node.layers == GbCameraEye.LENS_ONLY_LAYER,
		"occlusion/on the one layer a Game Boy Camera's lens leaves out")
	pref["on"] = false
	room.refresh_occlusion()
	await get_tree().process_frame
	_ok(not room.has_occlusion() and not is_instance_valid(node) and ext.stops == 1,
		"occlusion/switched off, it is taken away and its depth let go")
	pref["on"] = true
	room.refresh_occlusion()
	_ok(room.has_occlusion() and ext.starts == 2, "occlusion/and back on again")
	room.queue_free()
	await get_tree().process_frame
	_ok(ext.stops == 2, "occlusion/the room gone, its depth goes too")
	_free_rig(rig)

	granted["on"] = false
	var rig2 := _rig()
	var room2 := _room(granted, rig2)
	room2.occlusion_pref_source = func() -> bool: return true
	room2.occlusion_factory = func() -> Object: return MeshInstance3D.new()
	SpatialPermission.request_sink = func(_p: String) -> void: pass
	room2.start()
	_ok(not room2.has_occlusion(), "occlusion/without consent there is none")
	room2.queue_free()
	_free_rig(rig2)
	await get_tree().process_frame
	_reset_statics()


## Each passthrough switch in OPTIONS shown only where the headset can do it,
## asked again whenever the page is shown.
func _test_support() -> void:
	PassthroughSupport.override = {}
	PassthroughSupport.mesh_seen = false
	_ok(not PassthroughSupport.passthrough() and not PassthroughSupport.room_data()
		and not PassthroughSupport.room_mesh() and not PassthroughSupport.depth()
		and not PassthroughSupport.camera(),
		"support/no headset here: no passthrough switch would show")
	# A Quest 2: passthrough and Space Setup's room, nothing else.
	PassthroughSupport.override = {"passthrough": true, "room_data": true, "depth": false}
	_ok(PassthroughSupport.room_data() and not PassthroughSupport.room_mesh()
		and not PassthroughSupport.depth() and not PassthroughSupport.camera(),
		"support/a Quest 2: room data and room scan, no mesh, depth or camera")
	PassthroughSupport.override = {"passthrough": true, "room_data": true, "room_mesh": true,
		"depth": true, "camera": true}
	_ok(PassthroughSupport.room_mesh() and PassthroughSupport.depth() and PassthroughSupport.camera(),
		"support/a Quest 3: all of it")
	# The mesh asked of the room where OpenXR's own query cannot be reached.
	PassthroughSupport.override = {"passthrough": true, "room_data": true}
	PassthroughSupport.mesh_seen = false
	var reachable := PassthroughSupport.mesh_extension() != null
	_ok(reachable or not PassthroughSupport.room_mesh(),
		"support/no mesh read yet: Detailed Room Mesh is not offered")
	var rig := _rig()
	var room := _room({"on": true}, rig)
	room.start()
	var manager := (rig["origin"] as Node).get_node("RealRoomScene") as FakeManager
	manager.make_anchor(FakeEntity.new(PackedStringArray(["GLOBAL_MESH"]), true))
	_ok(PassthroughSupport.mesh_seen and (reachable or PassthroughSupport.room_mesh()),
		"support/once a room mesh has been read, it is")
	room.free()
	_free_rig(rig)
	PassthroughSupport.mesh_seen = false
	var view := SpawnMenuOptionsView.new()
	var has := {"v": false}
	var row := HBoxContainer.new()
	view.call("_support_row", row, func() -> bool: return has["v"])
	view.call("_refresh_support_rows")
	_ok(not row.visible, "support/a row its headset cannot do is hidden")
	has["v"] = true
	view.call("_refresh_support_rows")
	_ok(row.visible, "support/and shown once the headset says it can, the next time the page is shown")
	row.free()
	view.free()
	PassthroughSupport.override = {}


## Debug > Overlays > Real Room Surfaces.
func _test_overlay() -> void:
	var rig := _rig()
	var room := _room({"on": true}, rig)
	room.start()
	var manager := (rig["origin"] as Node).get_node("RealRoomScene") as FakeManager
	var table := manager.make_anchor(FakeEntity.new(PackedStringArray(["TABLE"])))
	var mesh := manager.make_anchor(FakeEntity.new(PackedStringArray(["GLOBAL_MESH"]), true))
	var door := manager.make_anchor(FakeEntity.new(PackedStringArray(["DOOR_FRAME"])))
	_ok(not table.has_debug_mesh() and not mesh.has_debug_mesh(), "overlay/off by default: nothing drawn")
	RealRoomSurface.set_debug_visible(get_tree(), true)
	var table_draw := table.get_node_or_null("DebugOverlay") as MeshInstance3D
	var mesh_draw := mesh.get_node_or_null("DebugOverlay") as MeshInstance3D
	_ok(table.has_debug_mesh() and table_draw != null and table_draw.mesh != null
		and mesh.has_debug_mesh() and mesh_draw.mesh.get_faces().size() == 3,
		"overlay/on: each surface drawn as its shape, the scanned mesh as its own triangles")
	_ok(not door.has_debug_mesh(), "overlay/and nothing for what is nothing")
	_ok((table_draw.material_override as StandardMaterial3D).no_depth_test,
		"overlay/drawn over everything: the real surface's own depth never hides it in patches")
	var table_color := (table_draw.material_override as StandardMaterial3D).albedo_color
	var mesh_color := (mesh_draw.material_override as StandardMaterial3D).albedo_color
	_ok(table.is_solid() and is_equal_approx(table_color.a, RealRoomSurface.DEBUG_ALPHA_SOLID)
		and not mesh.is_solid() and is_equal_approx(mesh_color.a, RealRoomSurface.DEBUG_ALPHA_NOT_SOLID)
		and not table_color.is_equal_approx(mesh_color),
		"overlay/coloured by kind, bold where things rest on it and faint where they don't")
	var later := manager.make_anchor(FakeEntity.new(PackedStringArray(["WALL_FACE"])))
	_ok(later.has_debug_mesh(), "overlay/a surface made while it is on is drawn too")
	RealRoomSurface.set_debug_visible(get_tree(), false)
	_ok(not table.has_debug_mesh() and not mesh.has_debug_mesh() and not later.has_debug_mesh(),
		"overlay/off again: all of it hidden")
	room.queue_free()
	_free_rig(rig)
	await get_tree().process_frame
	_reset_statics()


## The player's body found as the passthrough room has it: RealRoom beside the
## rig, the body an XRToolsPlayerBody under the XROrigin3D. Asked of RealRoom
## itself, XRToolsPlayerBody.find_instance found nothing, the room mesh pushed
## the body, and on a Quest 3 everything in view slid away (2026-10-24).
func _test_rig() -> void:
	var granted := {"on": true}
	SpatialPermission.wanted_source = func() -> bool: return true
	SpatialPermission.granted_source = func() -> PackedStringArray:
		return PackedStringArray(["com.oculus.permission.USE_SCENE"])
	var origin := XROrigin3D.new()
	var camera := XRCamera3D.new()
	origin.add_child(camera)
	var body := CharacterBody3D.new()
	body.set_script(load("res://addons/godot-xr-tools/player/player_body.gd"))
	body.name = "PlayerBody"
	origin.add_child(body)
	add_child(origin)
	# Its own step wants a whole player rig; the case only needs it to collide.
	body.set_physics_process(false)
	var room := RealRoom.new()
	room.manager_factory = func() -> Object: return FakeManager.new()
	room.camera_source = func() -> Node3D: return camera
	room.notice_sink = func(_t: String, _x: String) -> void: pass
	add_child(room)
	room.start()
	var manager := origin.get_node_or_null("RealRoomScene") as FakeManager
	_ok(manager != null, "rig/the manager goes under the rig's origin, found through its camera")
	if manager != null:
		var mesh := manager.make_anchor(FakeEntity.new(PackedStringArray(["GLOBAL_MESH"]), true))
		_ok(body is XRToolsPlayerBody and mesh in body.get_collision_exceptions(),
			"rig/the player's own body, under the origin, passes through the room's mesh")
		# A table right over the player's head, and the head probe cast up through it.
		var table := manager.make_anchor(FakeEntity.new(PackedStringArray(["TABLE"])))
		(table.get_parent() as Node3D).global_position = body.global_position + Vector3.UP * 1.5
		var control := StaticBody3D.new()
		var control_shape := CollisionShape3D.new()
		control_shape.shape = BoxShape3D.new()
		control.add_child(control_shape)
		add_child(control)
		control.global_position = body.global_position + Vector3.UP * 3.5
		await get_tree().physics_frame
		await get_tree().physics_frame
		var head := body.get("_head_shape_cast") as ShapeCast3D
		var hit_table := true
		var hit_control := false
		if head != null:
			head.position = Vector3(0, 0.5, 0)
			head.target_position = Vector3.UP * 4.0
			head.force_shapecast_update()
			hit_table = head.is_colliding() and head.get_collider(0) == table
			hit_control = head.is_colliding() and head.get_collider(0) == control
		_ok(head != null and not hit_table and hit_control,
			"rig/and so does its head probe, which the body's exceptions do not reach",
			"hit table=%s, hit the control above it=%s" % [hit_table, hit_control])
		control.queue_free()
	room.queue_free()
	origin.queue_free()
	await get_tree().process_frame
	_reset_statics()


## Options' Set Up Room: Meta's Space Setup opened from the game, and the room
## read again when it closes.
func _test_setup() -> void:
	var granted := {"on": false}
	var wanted := {"on": false}
	var asked: Array = []
	SpatialPermission.wanted_source = func() -> bool: return wanted["on"]
	SpatialPermission.request_sink = func(p: String) -> void: asked.append(p)
	var rig := _rig()
	var room := _room(granted, rig)
	room.start()
	_ok("Use Room Data" in room.request_room_setup() and not room.has_manager(),
		"setup/with room data off, the player is told to turn it on")
	wanted["on"] = true
	SpatialPermission.request_once()
	asked.clear()
	var why := room.request_room_setup()
	_ok("Allow" in why and asked.size() == SpatialPermission.PERMISSIONS.size(),
		"setup/without consent it is asked for again, though it was asked before", why)
	granted["on"] = true
	why = room.request_room_setup()
	var manager := (rig["origin"] as Node).get_node_or_null("RealRoomScene") as FakeManager
	_ok(why.is_empty() and manager != null and manager.captures == 1,
		"setup/given, Space Setup is opened", why)
	var table := manager.make_anchor(FakeEntity.new(PackedStringArray(["TABLE"])))
	var body := rig["body"] as CharacterBody3D
	manager.openxr_fb_scene_capture_completed.emit(true)
	await get_tree().process_frame
	_ok(manager.removes == 1 and manager.creates == 1 and not is_instance_valid(table)
		and room.surfaces().is_empty() and body.get_collision_exceptions().is_empty(),
		"setup/closed, the old room is put away and the new one asked for")
	manager.make_anchor(FakeEntity.new(PackedStringArray(["COUCH"])))
	_ok(room.surfaces().size() == 1, "setup/and what it makes is taken in as before")
	manager.capture_supported = false
	_ok("can't" in room.request_room_setup() and manager.captures == 1,
		"setup/a headset that cannot open it from a game says so")
	room.queue_free()
	_free_rig(rig)
	await get_tree().process_frame
	_reset_statics()


## What the Quest build needs switched on, and declared: the plugin sets the depth
## globals every frame and hung the app without them (spatial probe, 2026-10-24).
func _test_project() -> void:
	_ok(bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/scene_api", false))
		and bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/environment_depth", false)),
		"project/the room and its depth are switched on for the game")
	var types := {
		"META_ENVIRONMENT_DEPTH_TEXTURE": "sampler2DArray",
		"META_ENVIRONMENT_DEPTH_TEXEL_SIZE": "vec2",
		"META_ENVIRONMENT_DEPTH_AVAILABLE": "bool",
	}
	for side in ["LEFT", "RIGHT"]:
		for m in ["FROM_CAMERA_PROJECTION", "TO_CAMERA_PROJECTION", "PROJECTION_VIEW", "INV_PROJECTION_VIEW"]:
			types["META_ENVIRONMENT_DEPTH_%s_%s" % [m, side]] = "mat4"
	var wrong: PackedStringArray = []
	for g: String in types:
		var v: Variant = ProjectSettings.get_setting("shader_globals/" + g, null)
		if not (v is Dictionary) or str((v as Dictionary).get("type", "")) != types[g]:
			wrong.append(g)
	_ok(wrong.is_empty() and ProjectSettings.has_setting(EnvironmentDepth.DECLARED_SETTING),
		"project/and every depth global the plugin sets is declared, with its shaders' type", str(wrong))


func _test_prefs() -> void:
	var prefs := get_node_or_null("/root/AppPrefs")
	_ok(prefs != null and prefs.get("passthrough_occlusion") is bool, "prefs/the occlusion switch is a pref")
	if prefs == null:
		return
	# Saved by the live AppPrefs and read back by a fresh one, each the opposite
	# of its default, so a pref the save or the load dropped reads back wrong.
	var back := _app_prefs_round_trip({
		"passthrough_occlusion": not _app_prefs_default("passthrough_occlusion"),
		"passthrough_spatial": false,
		"passthrough_room_mesh": true,
	})
	_ok(back["passthrough_occlusion"] == (not _app_prefs_default("passthrough_occlusion")),
		"prefs/and it is saved and read back with the rest", str(back))
	_ok(prefs.get("passthrough_spatial") is bool and _app_prefs_default("passthrough_spatial") == true
		and back["passthrough_spatial"] == false,
		"prefs/room data is a pref too, on unless the player turns it off, saved and read back",
		str(back))
	_ok(prefs.get("passthrough_room_mesh") is bool and _app_prefs_default("passthrough_room_mesh") == false
		and back["passthrough_room_mesh"] == true,
		"prefs/the detailed mesh is a pref, off (flat furniture) unless turned on, saved and read back",
		str(back))
