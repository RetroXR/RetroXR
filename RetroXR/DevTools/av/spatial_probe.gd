## spatial_probe.gd — Phase 0 of plans/wish-list/spatial-data-quest3.md.
##
## Answers on real hardware: does the runtime back the vendor-neutral core path
## (XR_EXT_spatial_entity), and do real Room Setup planes arrive as trackers?
## Everything is discovered reflectively, so it reports even when a class or
## method is absent.
##
## Run it as the main scene on device (QuestSpatialProbe preset) and read the
## [spatial] lines from logcat. The Meta Fb path is exercised LAST: without the
## USE_SCENE runtime permission it can take the process down, which would
## otherwise swallow the core results.
extends Node3D


const CLASSES: PackedStringArray = [
	"OpenXRSpatialEntityExtension",
	"OpenXRSpatialPlaneTrackingCapability",
	"OpenXRSpatialAnchorCapability",
	"OpenXRFbSpatialEntityExtension",
	"OpenXRFbSceneCaptureExtension",
	"OpenXRMetaSpatialEntityMeshExtension",
	"OpenXRFbSceneManager",
	"OpenXRPlaneTracker",
	"OpenXRAnchorTracker",
]
const SCENE_PERMS: PackedStringArray = [
	"com.oculus.permission.USE_SCENE",
	"horizonos.permission.USE_SCENE",
]

var _frames: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(0))
	_register_depth_globals()

	var xri: XRInterface = XRServer.find_interface("OpenXR")
	var initialized: bool = xri != null and xri.is_initialized()
	print("[spatial] OpenXR interface=%s initialized=%s" % [xri != null, initialized])
	if initialized:
		xri.set_play_area_mode(XRInterface.XR_PLAY_AREA_ROOMSCALE)
		get_viewport().use_xr = true
		print("[spatial] blend modes=%s" % str(xri.get_supported_environment_blend_modes()))

	_report_permissions()
	_report_classes()
	_report_core_capabilities()
	_report_trackers("t=0")

	# Discovery is asynchronous — planes show up some frames after the session
	# starts, so sample repeatedly rather than once.
	for t: int in [3, 8, 15, 25]:
		await get_tree().create_timer(float(t) - _elapsed).timeout
		_report_trackers("t=%ds" % t)

	# Meta path last, on purpose (see the class docs above).
	print("[spatial] ===== core probe complete; trying Meta Fb path =====")
	_report_fb()
	await get_tree().create_timer(6.0).timeout
	await _report_fb_anchors()

	print("[spatial] ===== trying environment depth =====")
	await _report_depth()

	await get_tree().create_timer(3.0).timeout
	print("[spatial] ===== probe complete =====")
	get_tree().quit(0)


## The vendors plugin sets these every frame once environment_depth is on, and
## expects them declared: the editor writes them as shader_globals/ when the
## setting is switched on there. Switched on for a feature tag alone they never
## are, and the plugin logs a failure every frame (the first probe run, 2026-10-24).
## Declared here, before anything renders, with the types its shaders use.
func _register_depth_globals() -> void:
	const MAT4 := RenderingServer.GLOBAL_VAR_TYPE_MAT4
	var wanted := {
		"META_ENVIRONMENT_DEPTH_TEXTURE": RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2DARRAY,
		"META_ENVIRONMENT_DEPTH_TEXEL_SIZE": RenderingServer.GLOBAL_VAR_TYPE_VEC2,
		"META_ENVIRONMENT_DEPTH_AVAILABLE": RenderingServer.GLOBAL_VAR_TYPE_BOOL,
		"META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_LEFT": MAT4,
		"META_ENVIRONMENT_DEPTH_FROM_CAMERA_PROJECTION_RIGHT": MAT4,
		"META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_LEFT": MAT4,
		"META_ENVIRONMENT_DEPTH_TO_CAMERA_PROJECTION_RIGHT": MAT4,
		"META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_LEFT": MAT4,
		"META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_RIGHT": MAT4,
		"META_ENVIRONMENT_DEPTH_INV_PROJECTION_VIEW_LEFT": MAT4,
		"META_ENVIRONMENT_DEPTH_INV_PROJECTION_VIEW_RIGHT": MAT4,
	}
	var have := RenderingServer.global_shader_parameter_get_list()
	var added: PackedStringArray = []
	for g: String in wanted:
		if g in have:
			continue
		var t: int = wanted[g]
		var value: Variant = Projection.IDENTITY if t == MAT4 else (Vector2.ZERO if t == RenderingServer.GLOBAL_VAR_TYPE_VEC2
			else (false if t == RenderingServer.GLOBAL_VAR_TYPE_BOOL else null))
		RenderingServer.global_shader_parameter_add(g, t, value)
		added.append(g)
	print("[spatial] depth globals: %d already declared, added %s" % [wanted.size() - added.size(), str(added)])


## Heartbeat: distinguishes "process died" from "process alive but not ticking".
func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _frames % 90 == 0:
		print("[spatial] alive t=%.1fs frames=%d" % [_elapsed, _frames])


func _report_permissions() -> void:
	var granted: PackedStringArray = OS.get_granted_permissions()
	for p in SCENE_PERMS:
		print("[spatial] permission %s granted=%s" % [p, p in granted])
	# Ask for it if the shell did not grant it at install time.
	for p in SCENE_PERMS:
		if not (p in granted):
			print("[spatial] requesting %s -> %s" % [p, OS.request_permission(p)])


func _report_classes() -> void:
	for c in CLASSES:
		if not ClassDB.class_exists(c):
			print("[spatial] class %s: ABSENT" % c)
			continue
		print("[spatial] class %s: present singleton=%s parent=%s" % [
			c, Engine.has_singleton(c), ClassDB.get_parent_class(c)])


## The core / cross-vendor answer.
func _report_core_capabilities() -> void:
	if not Engine.has_singleton("OpenXRSpatialEntityExtension"):
		print("[spatial] core: OpenXRSpatialEntityExtension singleton ABSENT")
		return
	var ext: Object = Engine.get_singleton("OpenXRSpatialEntityExtension")
	for e in ClassDB.class_get_enum_list("OpenXRSpatialEntityExtension", true):
		for k in ClassDB.class_get_enum_constants("OpenXRSpatialEntityExtension", e, true):
			if not k.contains("CAPABILITY"):
				continue
			var v: int = ClassDB.class_get_integer_constant("OpenXRSpatialEntityExtension", k)
			print("[spatial] core supports_capability(%s) = %s" % [
				k, str(ext.call("supports_capability", v))])
	for c in ["OpenXRSpatialPlaneTrackingCapability", "OpenXRSpatialAnchorCapability"]:
		if Engine.has_singleton(c):
			_call_support_queries(c, Engine.get_singleton(c))


## Reflectively call every zero-arg is_*/supports_* query on an object.
func _call_support_queries(label: String, obj: Object) -> void:
	if obj == null:
		return
	for m: Dictionary in ClassDB.class_get_method_list(obj.get_class(), true):
		var name: String = str(m["name"])
		if (m["args"] as Array).is_empty() \
				and (name.begins_with("is_") or name.begins_with("supports_")):
			print("[spatial] %s.%s() = %s" % [label, name, str(obj.call(name))])


## What built-in plane/anchor detection actually published, with geometry.
func _report_trackers(when: String) -> void:
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANY)
	var planes: int = 0
	var lines: PackedStringArray = []
	for key: Variant in trackers:
		var t: Variant = trackers[key]
		if not (t is Object):
			continue
		var o: Object = t as Object
		if o.has_method("get_plane_label"):
			planes += 1
			lines.append("%s label=%s alignment=%s bounds=%s" % [
				str(key), str(o.call("get_plane_label")),
				str(o.call("get_plane_alignment")), str(o.call("get_bounds_size"))])
		elif o.has_method("get_uuid"):
			lines.append("%s ANCHOR uuid=%s" % [str(key), str(o.call("get_uuid"))])
	print("[spatial] %s trackers=%d planes=%d" % [when, trackers.size(), planes])
	for l in lines:
		print("[spatial]   %s" % l)


func _report_fb() -> void:
	for c in ["OpenXRFbSpatialEntityExtension", "OpenXRFbSceneCaptureExtension"]:
		if Engine.has_singleton(c):
			_call_support_queries(c, Engine.get_singleton(c))
	if not ClassDB.class_exists("OpenXRFbSceneManager"):
		return
	var n: Object = ClassDB.instantiate("OpenXRFbSceneManager")
	if not (n is Node):
		return
	var mgr: Node = n as Node
	if mgr.has_signal("openxr_fb_scene_data_missing"):
		mgr.connect("openxr_fb_scene_data_missing",
			func() -> void: print("[spatial] fb SIGNAL scene_data_missing (no Room Setup)"))
	if mgr.has_signal("openxr_fb_scene_anchor_created"):
		mgr.connect("openxr_fb_scene_anchor_created",
			func(node: Variant, entity: Variant) -> void:
				var labels: Variant = (entity as Object).call("get_semantic_labels") if entity is Object else null
				print("[spatial] fb SIGNAL anchor_created %s %s labels=%s" % [str(node), str(entity), str(labels)]))
	# Under the origin, as the game will put it: anchors are in tracking space.
	mgr.name = "FbSceneManager"
	# The game's own surface, as RealRoom hands it over. Without a scene the
	# manager found the room's 20 anchors and made no node of any (2026-10-24).
	mgr.set("default_scene", load("res://Scenes/XR/real_room_surface.tscn"))
	var origin := get_node_or_null("XROrigin3D")
	(origin if origin != null else self).add_child(mgr)
	print("[spatial] fb: OpenXRFbSceneManager added to tree (survived) auto_create=%s" % str(mgr.get("auto_create")))
	if mgr.has_method("get_anchor_uuids"):
		print("[spatial] fb room-setup anchors = %s" % str(mgr.call("get_anchor_uuids")))


## Every anchor the manager made: its labels, components, bounds, and what a
## collision shape built from it is. GLOBAL_MESH is the Quest 3 room mesh.
func _report_fb_anchors() -> void:
	var mgr := find_child("FbSceneManager", true, false)
	if mgr == null:
		print("[spatial] fb: no manager to ask")
		return
	if mgr.has_method("are_scene_anchors_created") and not mgr.call("are_scene_anchors_created"):
		print("[spatial] fb: anchors not created yet; create_scene_anchors() -> %s" % str(mgr.call("create_scene_anchors")))
		await get_tree().create_timer(4.0).timeout
	var uuids: Array = mgr.call("get_anchor_uuids") if mgr.has_method("get_anchor_uuids") else []
	print("[spatial] fb anchors=%d" % uuids.size())
	for uuid: Variant in uuids:
		var node: Variant = mgr.call("get_anchor_node", uuid)
		var entity: Variant = node.get("spatial_entity") if node is Object else null
		if entity == null and node is Object:
			for prop: Dictionary in (node as Object).get_property_list():
				var v: Variant = (node as Object).get(prop["name"])
				if v is Object and (v as Object).get_class() == "OpenXRFbSpatialEntity":
					entity = v
		var line := "[spatial] fb anchor %s node=%s" % [str(uuid), str(node)]
		if node is Node3D:
			line += " at=%s" % str((node as Node3D).global_position)
		# What the game's RealRoomSurface made of it.
		if node is Node:
			for s in (node as Node).find_children("*", "RealRoomSurface", true, false):
				var rs := s as RealRoomSurface
				var shape_kind := "none"
				for c in rs.get_children():
					if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
						var sh := (c as CollisionShape3D).shape
						shape_kind = sh.get_class()
						if sh is ConcavePolygonShape3D:
							shape_kind += "(%d faces)" % ((sh as ConcavePolygonShape3D).get_faces().size() / 3)
						elif sh is BoxShape3D:
							shape_kind += str((sh as BoxShape3D).size)
				print("[spatial] surface labels=%s kind=%s solid=%s shape=%s at=%s" % [
					str(rs.labels), RealRoomSurface.Kind.keys()[rs.kind], rs.collision_layer != 0,
					shape_kind, str(rs.global_position)])
		if entity is Object:
			var e := entity as Object
			line += " labels=%s components=%s" % [str(e.call("get_semantic_labels")), str(e.call("get_supported_components"))]
			if e.has_method("get_bounding_box_3d"):
				line += " box3d=%s" % str(e.call("get_bounding_box_3d"))
			if e.has_method("get_bounding_box_2d"):
				line += " box2d=%s" % str(e.call("get_bounding_box_2d"))
			if e.has_method("create_collision_shape"):
				var shape: Variant = e.call("create_collision_shape")
				line += " shape=%s" % str(shape)
				if shape is Node:
					for c in (shape as Node).get_children():
						line += " /%s" % str(c)
					var cs := shape as CollisionShape3D
					if cs != null and cs.shape is ConcavePolygonShape3D:
						line += " faces=%d" % ((cs.shape as ConcavePolygonShape3D).get_faces().size() / 3)
		else:
			line += " (no entity found on the node)"
		print(line)


## Meta environment depth: does it start, what do its globals hold, which space
## are its matrices in (move the origin and see whether they change), and what
## the CPU readback hands its callback.
func _report_depth() -> void:
	const EXT := "OpenXRMetaEnvironmentDepthExtension"
	if not Engine.has_singleton(EXT):
		print("[spatial] depth: %s singleton ABSENT" % EXT)
		return
	var ext: Object = Engine.get_singleton(EXT)
	_call_support_queries("depth", ext)
	if not ext.call("is_environment_depth_supported"):
		print("[spatial] depth: not supported")
		return
	ext.call("start_environment_depth")
	await get_tree().create_timer(2.0).timeout
	print("[spatial] depth started=%s" % str(ext.call("is_environment_depth_started")))
	for g in RenderingServer.global_shader_parameter_get_list():
		if str(g).begins_with("META_ENVIRONMENT_DEPTH"):
			print("[spatial] depth global %s = %s" % [g, str(RenderingServer.global_shader_parameter_get(g))])
	var origin := get_node_or_null("XROrigin3D") as Node3D
	var before: Variant = RenderingServer.global_shader_parameter_get("META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_LEFT")
	if origin != null:
		origin.position += Vector3(5, 0, 0)
		await get_tree().create_timer(1.0).timeout
		var after: Variant = RenderingServer.global_shader_parameter_get("META_ENVIRONMENT_DEPTH_PROJECTION_VIEW_LEFT")
		print("[spatial] depth PV_LEFT origin moved 5 m: changed=%s\n  before=%s\n  after=%s" % [str(before != after), str(before), str(after)])
		origin.position -= Vector3(5, 0, 0)
	if ext.has_method("get_environment_depth_map_async"):
		var done := {"v": false}
		ext.call("get_environment_depth_map_async", func(result: Variant) -> void:
			var shape := type_string(typeof(result))
			if result is Array:
				shape += " size=%d" % (result as Array).size()
				for r: Variant in result:
					shape += " | %s" % _describe(r)
			else:
				shape += " | %s" % _describe(result)
			print("[spatial] depth map async: %s" % shape)
			done["v"] = true)
		for i in 60:
			if done["v"]:
				break
			await get_tree().process_frame
		if not done["v"]:
			print("[spatial] depth map async: no callback in 60 frames")


func _describe(v: Variant) -> String:
	if v is Dictionary:
		var parts: PackedStringArray = []
		for k: Variant in v:
			var x: Variant = (v as Dictionary)[k]
			parts.append("%s:%s" % [str(k), ("Image %s %s" % [(x as Image).get_size(), (x as Image).get_format()]) if x is Image else type_string(typeof(x))])
		return "{%s}" % ", ".join(parts)
	if v is Image:
		return "Image %s fmt=%d" % [(v as Image).get_size(), (v as Image).get_format()]
	return "%s %s" % [type_string(typeof(v)), str(v).left(200)]
