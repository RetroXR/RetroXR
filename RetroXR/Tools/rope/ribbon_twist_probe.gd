## A flat two-wire mains cord: does its lay follow the END plug as well as the
## start one?
##
##   "$godot" --path RetroXR --resolution 640x480 --position 20,20 \
##       res://Tools/rope/ribbon_twist_probe.tscn -- --video=<dir>
##
## Windowed only: this is about how the tube is DRAWN (the ribbon's lay is a
## render-time frame, not simulated), so there is nothing for a headless run to
## measure. Both plugs are frozen — held, as far as the rope is concerned — with
## the cord sagging onto a floor between them. After it settles, the appliance
## plug turns a full 360 degrees about its own cord axis over six seconds, with
## the camera close on that end. The two wires should leave the plug square and
## turn with it; before the fix they lay wherever the transport from the wall
## plug happened to arrive, and did not follow the plug at all.

extends Node

const CORD := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn")


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	var video := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--video="):
			video = arg.trim_prefix("--video=")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	col.shape = box
	col.position = Vector3(0, -0.1, 0)
	floor_body.add_child(col)
	add_child(floor_body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	mi.position = col.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	mi.material_override = mat
	add_child(mi)

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(0.40, 0.09, 0.07), Vector3(0.44, 0.045, 0.0))
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	add_child(sun)
	var overlay := get_node_or_null("/root/LoadingOverlay")
	if overlay != null and overlay.has_method("suspend"):
		overlay.suspend()

	var cord: Node3D = CORD.instantiate()
	add_child(cord)
	await get_tree().process_frame
	var wall: RigidBody3D = cord.get_node("WallPlug")
	var appliance: RigidBody3D = cord.get_node("AppliancePlug")
	# Each plug's cord leaves along its local -Z, so they face each other across
	# the span: the wall plug's -Z along +X, the appliance plug's along -X.
	wall.freeze = true
	appliance.freeze = true
	wall.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-0.5, 0.05, 0.0))
	var hold := Vector3(0.5, 0.05, 0.0)
	appliance.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), hold)
	var rope: VerletRope = cord.get_node("VerletRope")
	rope._init_points()

	if not video.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(video))
	var frame := 0
	var ticks := 180 + 540
	for t in ticks:
		await get_tree().physics_frame
		if t >= 180:
			var roll := TAU * float(t - 180) / 540.0
			var xf := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, roll), hold)
			appliance.global_transform = xf
			PhysicsServer3D.body_set_state(appliance.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		if not video.is_empty() and t % 3 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [
				ProjectSettings.globalize_path(video), frame])
			frame += 1
	print("[probe] done, %d frames" % frame)
	get_tree().quit(0)
