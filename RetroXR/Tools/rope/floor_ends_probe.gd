## Loose plugs on a floor — do a lead's ends lie still once it lands?
##
##   "$godot" --headless --path RetroXR res://Tools/rope/floor_ends_probe.tscn
##   "$godot" --path RetroXR --resolution 640x480 --position 20,20 \
##       res://Tools/rope/floor_ends_probe.tscn -- --video=res://probe_out/floor_ends
##   ... -- --legacy     plug colliders put back to the spheres they used to be
##   ... -- --no-couple  end_align_stiffness 0: the cord never pushes a plug
##   ... -- --no-friction  static/kinetic_friction 0: the old viscous slide
##
## Two real leads with real RigidBody plugs, ticked by the engine so the physics
## server owns the bodies (rope_video_probe drives step() by hand and has no plug
## bodies, so it cannot show this). A plain lead runs from a mount on a console-
## height block down to a loose plug on the floor; a composite lead is dropped
## flat with all six plugs loose.
##
## What to read, per plug: `travel` is how far its cable anchor moved AFTER the
## lead landed (tick 240 on) — a plug lying still is a few millimetres at most;
## `peak` the largest single-tick move in the last 150 ticks; `height` how far
## the plug's origin rests above the floor (an RCA barrel is 14 mm across, so
## ~7 mm lying down); `tilt` the exit axis's angle to the floor. And each rope's
## tick of first sleep, and `creep`: the mean distance each of its particles
## travelled after landing — the cord itself sliding about, not its plugs.
##
## Frames (windowed only — the headless dummy renderer returns a blank image)
## land in --video as f%04d.png, one per 3 physics ticks: 30 fps real time.

extends Node

const COMPOSITE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const PLAIN := preload("res://Scenes/Objects/cables/cable.tscn")

var TICKS := 900
const LANDED := 240
const WINDOW := 150

var _video := ""
var _legacy := false
var _no_couple := false
var _no_friction := false
var _mu_s := -1.0
var _mu_k := -1.0



func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--video="):
			_video = arg.trim_prefix("--video=")
		elif arg == "--legacy":
			_legacy = true
		elif arg == "--no-couple":
			_no_couple = true
		elif arg == "--no-friction":
			_no_friction = true
		elif arg.begins_with("--mu-s="):
			_mu_s = float(arg.trim_prefix("--mu-s="))
		elif arg.begins_with("--mu-k="):
			_mu_k = float(arg.trim_prefix("--mu-k="))
		elif arg.begins_with("--ticks="):
			TICKS = int(arg.trim_prefix("--ticks="))
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	await _run()
	get_tree().quit(0)


func _build_world() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for spec: Array in [
		[Vector3(8.0, 0.2, 8.0), Vector3(0.0, -0.1, 0.0)],  # floor, top at y = 0
		[Vector3(0.3, 0.3, 0.3), Vector3(-0.6, 0.15, 0.0)],  # a console on the floor
	]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[0]
		col.shape = box
		col.position = spec[1]
		body.add_child(col)
		if not _video.is_empty():
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = spec[0]
			mi.mesh = bm
			mi.position = spec[1]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.5, 0.45) if spec[1].y < 0.0 else Color(0.25, 0.25, 0.28)
			mi.material_override = mat
			add_child(mi)


func _build_camera() -> void:
	# Low and close over the plain lead's plug, with the composite's plugs behind.
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45.0
	cam.look_at_from_position(Vector3(0.62, 0.26, 0.62), Vector3(0.45, 0.0, 0.14))
	# --low: eye level with the floor, to see whether a plug is ON it — lying,
	# propped, or sunk — which the view from above cannot tell apart.
	if OS.get_cmdline_user_args().has("--low"):
		cam.fov = 30.0
		cam.look_at_from_position(Vector3(0.72, 0.012, 0.52), Vector3(0.67, 0.007, 0.28))
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	add_child(sun)
	# The boot loading curtain is a 44 m panel standing in the world, in front of
	# this camera; nothing here ever ends it.
	var overlay := get_node_or_null("/root/LoadingOverlay")
	if overlay != null and overlay.has_method("suspend"):
		overlay.suspend()


## Put a plug's collider back to the sphere it was before the fitted boxes, so
## the old build can be filmed as it shipped.
func _restore_sphere(plug: RigidBody3D, radius: float, z: float) -> void:
	for c: Node in plug.get_children():
		if c is CollisionShape3D:
			var s := SphereShape3D.new()
			s.radius = radius
			(c as CollisionShape3D).shape = s
			(c as CollisionShape3D).position = Vector3(0, 0, z)
			return


func _run() -> void:
	_build_world()
	if not _video.is_empty():
		_build_camera()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_video))

	var plain: Node3D = PLAIN.instantiate()
	add_child(plain)
	var comp: Node3D = COMPOSITE.instantiate()
	add_child(comp)
	# Turned so the lead lies along +X and its B plugs land beside the plain one.
	# --straight drops it unturned instead, the way rope_tests' loose case does.
	if OS.get_cmdline_user_args().has("--straight"):
		comp.global_transform = Transform3D(Basis(), Vector3(0.45, 0.06, -0.6))
	else:
		comp.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.1, 0.06, 0.28))
	await get_tree().process_frame

	var mount := Node3D.new()
	mount.position = Vector3(-0.45, 0.2, 0.0)
	mount.rotation_degrees = Vector3(0, -90, 0)  # the cord leaves the console along +X
	add_child(mount)
	var plug: RigidBody3D = plain.get_node("CablePlug")
	# The pair beside it belong to a channel this probe does not wire.
	for n: String in ["CablePlugL", "CablePlugR"]:
		var extra := plain.get_node_or_null(n)
		if extra != null:
			extra.queue_free()
	plug.global_transform = Transform3D(Basis.from_euler(Vector3(0.3, 0.8, 0.0)),
		Vector3(0.3, 0.12, 0.05))
	var pl: VerletRope = plain.get_node("VerletRope")
	pl.ribbon_count = 1
	pl.fray_segments_end = 0
	pl.start_node = mount
	pl.end_node = plug
	pl.end_anchor_offset = plug.get("cable_anchor")
	pl.set_rope_length(1.0)
	pl._init_points()

	var names := ["plain"]
	var plugs := {"plain": plug}
	for n: String in ["PlugA0", "PlugA1", "PlugA2", "PlugB0", "PlugB1", "PlugB2"]:
		names.append(n)
		plugs[n] = comp.get_node(n)
	if _legacy:
		_restore_sphere(plug, 0.035, 0.0)
		for n: String in names.slice(1):
			_restore_sphere(plugs[n], 0.028, -0.013)

	var ropes := {"plain": pl, "composite": comp.get_node("VerletRope") as VerletRope}
	for k: String in ropes:
		var r: VerletRope = ropes[k]
		if _no_couple:
			r.end_align_stiffness = 0.0
		if _no_friction:
			r.set("static_friction", 0.0)
			r.set("kinetic_friction", 0.0)
		if _mu_s >= 0.0:
			r.set("static_friction", _mu_s)
		if _mu_k >= 0.0:
			r.set("kinetic_friction", _mu_k)
	var slept := {"plain": -1, "composite": -1}
	var prev := {}
	var travel := {}
	var peak := {}
	for n: String in names:
		travel[n] = 0.0
		peak[n] = 0.0

	var creep := {"plain": 0.0, "composite": 0.0}
	var last_pts := {}
	var frame := 0
	for t in range(TICKS):
		await get_tree().physics_frame
		for k: String in ropes:
			var r: VerletRope = ropes[k]
			if slept[k] < 0 and r.is_sleeping():
				slept[k] = t
			var pts: PackedVector3Array = r.get_points()
			if t >= LANDED and last_pts.has(k) and (last_pts[k] as PackedVector3Array).size() == pts.size():
				var lp: PackedVector3Array = last_pts[k]
				var sum := 0.0
				for i in pts.size():
					sum += pts[i].distance_to(lp[i])
				creep[k] += sum / maxf(1.0, float(pts.size()))
			last_pts[k] = pts
		for n: String in names:
			var p: RigidBody3D = plugs[n]
			var a: Vector3 = p.global_transform * (p.get("cable_anchor") as Vector3)
			if prev.has(n):
				var d: float = a.distance_to(prev[n])
				if t >= LANDED:
					travel[n] += d
				if t >= TICKS - WINDOW:
					peak[n] = maxf(peak[n], d)
			prev[n] = a
		if not _video.is_empty() and t % 3 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [
				ProjectSettings.globalize_path(_video), frame])
			frame += 1

	print("[probe] mode=%s%s%s" % ["legacy spheres" if _legacy else "as shipped",
		" no-couple" if _no_couple else "", " no-friction" if _no_friction else ""])
	for k: String in ropes:
		print("[probe] rope %-9s first_slept=%s asleep_now=%s creep=%.2f mm" % [k,
			str(slept[k]) if slept[k] >= 0 else "NEVER", str((ropes[k] as VerletRope).is_sleeping()),
			creep[k] * 1000.0])
	var total := 0.0
	for n: String in names:
		var p: RigidBody3D = plugs[n]
		var axis: Vector3 = p.global_transform.basis.z.normalized()
		var tilt := rad_to_deg(asin(clampf(absf(axis.y), 0.0, 1.0)))
		total += travel[n]
		print("[probe] %-7s travel=%7.2f mm  peak=%6.3f mm  height=%5.1f mm  tilt=%4.1f deg  sleeping=%s  at %s" % [
			n, travel[n] * 1000.0, peak[n] * 1000.0, p.global_position.y * 1000.0, tilt,
			str(p.sleeping), p.global_position])
	print("[probe] total plug travel after landing = %.2f mm" % (total * 1000.0))
