## Drives the REAL player rig in desktop mode at an arcade cabinet and holds the left mouse
## button on it, the way a player does, to see whether hold-to-grab (HoldToGrab) lands:
## prints the ring's progress while the button is down and what the desktop hand holds after.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const RIG_SCENE := preload("res://Scenes/player_rig.tscn")


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(10, 0.1, 10)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.05
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(10, 0.1, 10)
	fc.shape = fs
	fb.add_child(fc)
	fb.collision_layer = 1
	floor_mesh.add_child(fb)
	add_child(floor_mesh)
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = "arcade"
	sys.freeze = true       # a free body fell out of this bare stage; the room has a real floor
	add_child(sys)
	var rig := RIG_SCENE.instantiate() as Node3D
	rig.position = Vector3(0.0, 0.0, 2.4)
	add_child(rig)
	get_viewport().use_xr = false
	for i in 30:
		await get_tree().physics_frame
	var cam := get_viewport().get_camera_3d()
	print("[probe] camera ", cam, " at ", cam.global_position if cam else null)
	var pick: Node = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("desktop_pickup.gd"):
			pick = n
	print("[probe] desktop pickup: ", pick)
	if pick == null:
		get_tree().quit(1)
		return
	# Aim at the side/marquee: the camera is at eye height straight ahead of the cabinet.
	cam.look_at(Vector3(0.0, 1.55, 0.0), Vector3.UP)
	for i in 10:
		await get_tree().physics_frame
	var dp: Node = pick.get("_desktop_pointer")
	print("[probe] pointer=", dp, " enabled=", dp.get("enabled") if dp else null)
	if dp != null:
		var rc := dp.get_node_or_null("RayCast") as RayCast3D
		if rc != null:
			print("[probe] ray from ", rc.global_position, " to ", rc.to_global(rc.target_position),
				" cam forward ", -cam.global_transform.basis.z)
		var sup := dp.get_node_or_null("SuppressArea") as Area3D
		if sup != null:
			print("[probe] suppress overlaps bodies=", sup.has_overlapping_bodies(), " areas=", sup.has_overlapping_areas())
	print("[probe] cabinet pos=", sys.global_position, " enabled=", sys.enabled, " picked=", sys.is_picked_up(),
		" freeze=", sys.freeze, " locked=", ObjectLock.is_locked(sys), " layer=", sys.collision_layer)
	var grabber: Variant = dp.call("_get_desktop_grabber") if dp != null else null
	print("[probe] grabber=", grabber, " can_pick_up=", sys.can_pick_up(grabber) if grabber != null else "n/a")
	var space := get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + (-cam.global_transform.basis.z) * 6.0, (1 << 0) | (1 << 2) | (1 << 20) | (1 << 22))
	rq.collide_with_areas = true
	var rh := space.intersect_ray(rq)
	print("[probe] raw ray hit: ", rh.get("collider"), " at ", rh.get("position"))
	var t: InteractionTarget = pick.call("_resolve_interaction_target", true)
	print("[probe] aimed: kind=", t.kind, " can_grab=", t.can_grab, " node=", t.action_node)
	# Press and hold.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	var reticle := get_tree().get_first_node_in_group("desktop_reticle")
	var last := -1.0
	for i in 200:
		await get_tree().physics_frame
		var p := float(reticle.call("get_hold_progress")) if reticle != null else -1.0
		if i % 20 == 0:
			print("[probe] t=%.2fs ring=%.2f mouse_down=%s held=%s" % [i / 60.0, p,
				Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), pick.call("held_object")])
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	Input.parse_input_event(rel)
	await get_tree().physics_frame
	print("[probe] after release held=", pick.call("held_object"))
	get_tree().quit(0)
