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
extends Node

var _pass := 0
var _fail := 0
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
	var default_scene: PackedScene = null
	var auto_create := false

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

	_reset_statics()
	print("[room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[room] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[room] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


func _reset_statics() -> void:
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
	_ok(mesh.collision_layer == RealRoomSurface.WORLD_LAYER
		and (mesh.get_child(0) as CollisionShape3D).shape is ConcavePolygonShape3D,
		"surfaces/the room's mesh is solid, its real shape")
	_ok(table.collision_layer == 0 and wall.collision_layer == RealRoomSurface.WORLD_LAYER,
		"surfaces/with the mesh, the table's box is not: things rest where the desk's things are")
	var couch := manager.make_anchor(FakeEntity.new(PackedStringArray(["COUCH"])))
	_ok(couch.collision_layer == 0, "surfaces/and furniture scanned after the mesh is not solid either")

	manager.openxr_fb_scene_data_missing.emit()
	manager.openxr_fb_scene_data_missing.emit()
	var notices: Array = rig["notices"]
	_ok(notices.size() == 1 and "Space Setup" in str(notices[0][1]),
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
		"spatial/off by default: plain passthrough asks for nothing and reads nothing")
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


func _test_prefs() -> void:
	var prefs := get_node_or_null("/root/AppPrefs")
	_ok(prefs != null and prefs.get("passthrough_occlusion") is bool, "prefs/the occlusion switch is a pref")
	if prefs == null:
		return
	var src := FileAccess.get_file_as_string("res://Scripts/Data/app_prefs.gd")
	_ok("\"passthrough_occlusion\": passthrough_occlusion" in src
		and "get_bool(data, \"passthrough_occlusion\"" in src,
		"prefs/and it is saved and read back with the rest")
	_ok(prefs.get("passthrough_spatial") is bool and "var passthrough_spatial: bool = false" in src
		and "\"passthrough_spatial\": passthrough_spatial" in src
		and "get_bool(data, \"passthrough_spatial\"" in src,
		"prefs/room data is a pref too, off unless the player turns it on, saved and read back")
