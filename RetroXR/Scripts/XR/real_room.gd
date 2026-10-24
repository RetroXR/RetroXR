## RealRoom — the player's real room, inside the passthrough room.
##
## Two things, both from what the Quest knows of the room once the player lets the
## game read it (SpatialPermission):
##
## - Things rest on it. Meta's scene manager (OpenXRFbSceneManager) makes an anchor
##   for everything scanned in Space Setup, and each becomes a RealRoomSurface: a
##   static body on the world layer, so a cartridge dropped on the real desk stays
##   on the desk. The room mesh (a Quest 3's scan) is the shape used; the boxes
##   drawn round the furniture are used only when there is no mesh. The player's
##   own body is excepted from all of it -- leaning over a real table must not push
##   the room out of register with the one it stands for.
## - It hides what is behind it (AppPrefs.passthrough_occlusion). Meta's occlusion
##   node over the player's eyes, from its depth (EnvironmentDepth), on the layer
##   the Game Boy Camera's lens leaves out.
##
## Made by PassthroughInit once passthrough is up, and gone with the room. The
## manager and the occlusion node live on the player's rig, which outlives the
## room, so both are freed here, not left to the room's teardown.
class_name RealRoom
extends Node

const MANAGER_CLASS := "OpenXRFbSceneManager"
const OCCLUSION_CLASS := "OpenXRMetaEnvironmentDepth"
const SURFACE_SCENE := preload("res://Scenes/XR/real_room_surface.tscn")
## Toast distance in front of the player, in meters.
const NOTICE_REACH := 1.2

## Makes the scene manager, or a stand-in. A suite supplies one.
var manager_factory := Callable()
## Makes the occlusion node, or a stand-in. A suite supplies one.
var occlusion_factory := Callable()
## The player's body, or null. A suite supplies one.
var player_body_source := Callable()
## The node the manager goes under (the XROrigin3D), and the occlusion node's
## parent (the XRCamera3D). A suite supplies them.
var origin_source := Callable()
var camera_source := Callable()
## Whether occlusion is wanted, or null to read AppPrefs. A suite supplies one.
var occlusion_pref_source := Callable()
## Called with the notice's title and text instead of a toast. A suite supplies one.
var notice_sink := Callable()

## The room-scan notice is shown once a run, whichever room asked.
static var _told_missing := false

var _started := false
var _manager: Node = null
var _occlusion: Node = null
var _surfaces: Array[RealRoomSurface] = []
var _excepted_body: PhysicsBody3D = null


## Begin: ask for the permission if it is not given yet (once a run), and use the
## room as far as it is.
func start() -> void:
	_started = true
	if not SpatialPermission.is_wanted():
		return
	if not SpatialPermission.has():
		SpatialPermission.request_once()
		return
	_ensure_manager()
	refresh_occlusion()


## Follow "Use Room Data in Passthrough": on, the room is read (asking for the
## permission first if need be); off, everything read from it is put away and the
## room is plain passthrough again.
func refresh_spatial() -> void:
	if SpatialPermission.is_wanted():
		start()
	else:
		_put_away()
		EnvironmentDepth.drop_all()


func _notification(what: int) -> void:
	# The consent dialog is answered outside the app: coming back is when an
	# answer may have arrived.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _started and is_inside_tree():
		start()


func _exit_tree() -> void:
	_started = false
	_put_away()


## Free what was made from the room: the manager (and with it every surface),
## the player's exceptions, the occlusion.
func _put_away() -> void:
	if is_instance_valid(_excepted_body):
		for s in _surfaces:
			if is_instance_valid(s):
				_excepted_body.remove_collision_exception_with(s)
	_surfaces.clear()
	if is_instance_valid(_manager):
		_manager.queue_free()
	_manager = null
	_drop_occlusion()


## Open Meta's Space Setup so the player can scan (or rescan) this room; the room
## is read again when it closes. "" when it opened, else why it could not, in
## words for the menu.
func request_room_setup() -> String:
	if not SpatialPermission.is_wanted():
		return "Turn on Use Room Data in Passthrough first."
	if not SpatialPermission.has():
		SpatialPermission.request_now()
		return "Allow spatial data, then press Set Up Room again."
	_started = true
	_ensure_manager()
	if _manager == null:
		return "Room setup isn't available on this headset."
	if _manager.has_method("is_scene_capture_supported") and not _manager.call("is_scene_capture_supported"):
		return "This headset can't open Space Setup from a game."
	# Only a false is a refusal: the call may answer nothing.
	var opened: Variant = _manager.call("request_scene_capture")
	if opened is bool and not opened:
		return "Space Setup didn't open. Try again from the Quest's settings."
	return ""


## Space Setup has closed: what was read of the room is put away and read anew.
func _on_capture_completed(_success: Variant = null) -> void:
	if _manager == null:
		return
	if is_instance_valid(_excepted_body):
		for s in _surfaces:
			if is_instance_valid(s):
				_excepted_body.remove_collision_exception_with(s)
	_surfaces.clear()
	if _manager.has_method("remove_scene_anchors"):
		_manager.call("remove_scene_anchors")
	if _manager.has_method("create_scene_anchors"):
		_manager.call("create_scene_anchors")


func has_manager() -> bool:
	return _manager != null


func surfaces() -> Array[RealRoomSurface]:
	return _surfaces


## Put Meta's occlusion over the player's eyes, or take it away, by the pref.
func refresh_occlusion() -> void:
	var wanted: bool = bool(occlusion_pref_source.call()) if occlusion_pref_source.is_valid() \
		else _pref_occlusion()
	var want := _started and wanted and SpatialPermission.usable() \
		and (occlusion_factory.is_valid() or ClassDB.class_exists(OCCLUSION_CLASS))
	if want and _occlusion == null:
		if not EnvironmentDepth.acquire(self):
			return
		var node: Object = occlusion_factory.call() if occlusion_factory.is_valid() \
			else ClassDB.instantiate(OCCLUSION_CLASS)
		if not (node is Node):
			EnvironmentDepth.release(self)
			return
		_occlusion = node as Node
		_occlusion.name = "RealRoomOcclusion"
		# The lens of a Game Boy Camera leaves this layer out: the player's
		# depth written into its picture would cut holes in it.
		if _occlusion is VisualInstance3D:
			(_occlusion as VisualInstance3D).layers = GbCameraEye.LENS_ONLY_LAYER
		var camera := _camera()
		if camera == null:
			_drop_occlusion()
			return
		camera.add_child(_occlusion)
	elif not want and _occlusion != null:
		_drop_occlusion()


func has_occlusion() -> bool:
	return _occlusion != null


func _drop_occlusion() -> void:
	if is_instance_valid(_occlusion):
		_occlusion.queue_free()
	if _occlusion != null:
		EnvironmentDepth.release(self)
	_occlusion = null


func _ensure_manager() -> void:
	if _manager != null:
		return
	if not manager_factory.is_valid() and not ClassDB.class_exists(MANAGER_CLASS):
		return
	var made: Object = manager_factory.call() if manager_factory.is_valid() \
		else ClassDB.instantiate(MANAGER_CLASS)
	if not (made is Node):
		return
	var origin := _origin()
	if origin == null:
		(made as Node).free()
		return
	_manager = made as Node
	_manager.name = "RealRoomScene"
	_manager.set("default_scene", SURFACE_SCENE)
	_manager.set("auto_create", true)
	_manager.connect("openxr_fb_scene_anchor_created", _on_anchor_created)
	_manager.connect("openxr_fb_scene_data_missing", _on_data_missing)
	if _manager.has_signal("openxr_fb_scene_capture_completed"):
		_manager.connect("openxr_fb_scene_capture_completed", _on_capture_completed)
	origin.add_child(_manager)


## The manager has set the surface up (setup_scene) under its anchor.
func _on_anchor_created(node: Object, _entity: Object) -> void:
	if not (node is Node):
		return
	var found: Array[RealRoomSurface] = []
	if node is RealRoomSurface:
		found.append(node as RealRoomSurface)
	for c in (node as Node).find_children("*", "RealRoomSurface", true, false):
		found.append(c as RealRoomSurface)
	for s in found:
		add_surface(s)


## Take `surface` into the room: the player's body passes through it, and which
## kinds are solid is decided again.
func add_surface(surface: RealRoomSurface) -> void:
	if surface in _surfaces:
		return
	_surfaces.append(surface)
	var body := _player_body()
	if body != null:
		_excepted_body = body
		body.add_collision_exception_with(surface)
	_settle_kinds()


## The mesh has the furniture's real shape, so with a mesh the furniture's boxes
## are not solid: a desk with things on it is rested on where its things are, not
## on the lid of a box round all of them.
func _settle_kinds() -> void:
	var has_mesh := false
	for s in _surfaces:
		if is_instance_valid(s) and s.kind == RealRoomSurface.Kind.MESH:
			has_mesh = true
			break
	for s in _surfaces:
		if is_instance_valid(s) and s.kind == RealRoomSurface.Kind.FURNITURE:
			s.set_solid(not has_mesh)


func _on_data_missing() -> void:
	if _told_missing:
		return
	_told_missing = true
	var title := "No room scan"
	var text := "Press Set Up Room in the menu's Options to scan it, so things can rest on your furniture."
	if notice_sink.is_valid():
		notice_sink.call(title, text)
		return
	var camera := _camera()
	if camera == null:
		return
	var anchor := Node3D.new()
	anchor.name = "RealRoomNotice"
	add_child(anchor)
	var ahead := -camera.global_transform.basis.z
	ahead.y = 0.0
	anchor.global_position = camera.global_position + ahead.normalized() * NOTICE_REACH
	var toast := AchievementToast.attach_to_machine(anchor)
	if toast != null:
		toast.show_notice("Passthrough", title, text)


func _pref_occlusion() -> bool:
	var prefs := get_node_or_null("/root/AppPrefs")
	return prefs == null or bool(prefs.get("passthrough_occlusion"))


func _player_body() -> PhysicsBody3D:
	if player_body_source.is_valid():
		return player_body_source.call() as PhysicsBody3D
	return XRToolsPlayerBody.find_instance(self) if is_inside_tree() else null


func _origin() -> Node:
	if origin_source.is_valid():
		return origin_source.call() as Node
	var camera := _camera()
	return camera.get_parent() as XROrigin3D if camera != null else null


func _camera() -> Node3D:
	if camera_source.is_valid():
		return camera_source.call() as Node3D
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## For suites.
static func reset_notice() -> void:
	_told_missing = false
