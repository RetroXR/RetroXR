## A cord that loops over ITSELF on a floor — does the crossing lie still?
##
##   "$godot" --headless --path RetroXR res://Tools/rope/rope_crossing_probe.tscn
##   ... -- --awake   wake() every tick: measure the jitter itself, not the sleep
##   ... -- --video=<dir> --resolution 640x480   (windowed) frames, 3 ticks each
##   ... -- --scale=0.3  the laid loop at 30% size: a TIGHT loop, whose own bend
##                    stiffness pushes it open against friction
##   ... -- --heap    instead of the laid loop, 2 m of cord dropped from 30 cm
##                    between two mounts 20 cm apart, so it piles into loops that
##                    cross wherever they fall; reports every stacked particle
##
## One bare rope with cable.tscn's solver settings, both ends on mounts at the
## floor, laid as an alpha loop so one run crosses over another (the crossing is
## at t = 0.2 / 0.8 of the lay; the t = 0.8 run is laid on top). Hand-stepped:
## there are no plug bodies here, this is purely the cord against itself and the
## floor.
##
## What to read: the rope's first sleep and how many of the last 300 ticks it
## slept; at the crossing, the upper and lower strands' resting heights (a
## 4.5 mm-radius cord: lower ~4.5 mm, upper ~13.5 mm) and the largest single-
## tick vertical move in the last 200 ticks. Under --awake, that last number IS
## the jitter a player sees whenever the cord is awake — asleep, it reads 0
## however badly the crossing chatters.

extends Node

const RADIUS := 0.0045
const SEG := 0.03
const TICKS := 900

var _video := ""


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	var awake := OS.get_cmdline_user_args().has("--awake")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--video="):
			_video = arg.trim_prefix("--video=")

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	col.shape = box
	col.position = Vector3(0, -0.1, 0)
	floor_body.add_child(col)
	add_child(floor_body)
	if not _video.is_empty():
		_stage_camera()

	# The lay: x = 0.8(t - 0.5) + 0.3 sin(2 pi t), z = 0.25(1 - cos 2 pi t) crosses
	# itself at t = 0.2 and 0.8.
	var heap := OS.get_cmdline_user_args().has("--heap")
	var scale := 1.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scale="):
			scale = float(arg.trim_prefix("--scale="))
	var path: Array[Vector3] = []
	var n := 400
	for k in n + 1:
		var t := float(k) / n
		var up := exp(-pow((t - 0.8) / 0.03, 2.0)) * RADIUS * 2.2
		path.append(Vector3((0.8 * (t - 0.5) + 0.3 * sin(TAU * t)) * scale, RADIUS + up,
			0.25 * (1.0 - cos(TAU * t)) * scale))
	var length := 0.0
	for k in n:
		length += path[k].distance_to(path[k + 1])
	var segments := int(round(length / SEG))
	if heap:
		# A U hanging from two mounts 30 cm up, 2 m of cord in it: it drops and piles.
		path.clear()
		for q in n + 1:
			var t := float(q) / n
			path.append(Vector3(-0.1 + 0.2 * t, 0.3 - 0.9 * sin(PI * t) * 0.3, 0.02 * sin(TAU * 3.0 * t)))
		length = 2.0
		segments = int(round(length / SEG))

	var a := Node3D.new()
	a.position = path[0]
	add_child(a)
	var b := Node3D.new()
	b.position = path[n]
	add_child(b)
	var rope := VerletRope.new()
	add_child(rope)
	rope.constraint_iterations = 8
	rope.bend_stiffness = 0.2
	rope.collision_radius = RADIUS
	rope.tube_radius = 0.004
	rope.surface_collision_mask = 7
	rope.self_collision = true
	rope.segment_count = segments
	rope.segment_length = length / segments
	rope.start_node = a
	rope.end_node = b
	rope.set_process(false)
	rope.set_physics_process(false)
	rope._init_points()
	# Resample the lay at equal arc length onto the particles.
	var lay := PackedVector3Array()
	var want := 0.0
	var run := 0.0
	var k := 0
	for p in segments + 1:
		want = length * float(p) / segments
		while k < n - 1 and run + path[k].distance_to(path[k + 1]) < want:
			run += path[k].distance_to(path[k + 1])
			k += 1
		var seg_len := path[k].distance_to(path[k + 1])
		lay.append(path[k].lerp(path[k + 1], clampf((want - run) / maxf(seg_len, 1e-9), 0.0, 1.0)))
	if heap:
		lay = rope.get_points()
	else:
		print("[probe] segments=%d restored=%s" % [segments, str(rope.restore_points(lay))])
	await get_tree().physics_frame

	# The two strands at the crossing: the closest pair in plan view that is not
	# near-neighbours along the cord.
	var lower := -1
	var upper := -1
	var best := 1e9
	for i in lay.size():
		for j in range(i + 6, lay.size()):
			var d := Vector2(lay[i].x - lay[j].x, lay[i].z - lay[j].z).length()
			if d < best:
				best = d
				lower = i
				upper = j
	if lay[lower].y > lay[upper].y:
		var tmp := lower
		lower = upper
		upper = tmp
	print("[probe] crossing particles %d (under) / %d (over), %.1f mm apart in plan" % [lower, upper, best * 1000.0])
	if not _video.is_empty():
		var at := (lay[lower] + lay[upper]) * 0.5
		var cam := get_viewport().get_camera_3d()
		cam.look_at_from_position(at + Vector3(0.10, 0.035, 0.10), at + Vector3(0, 0.004, 0))
	var slept := -1
	var asleep_tail := 0
	var jitter := 0.0
	var jitter_at := -1
	var prev_y := {}
	var frame := 0
	var flips := 0
	var creep := 0.0
	var stacked_peak := 0.0
	var stacked_peak_tick := -1
	var last_pts := PackedVector3Array()
	var was_sleeping := false
	for tick in TICKS:
		await get_tree().physics_frame
		if awake:
			rope.wake()
		rope.step(1.0 / 90.0)
		var pts := rope.get_points()
		if tick >= TICKS - 600 and last_pts.size() == pts.size():
			var sum := 0.0
			for q in pts.size():
				sum += pts[q].distance_to(last_pts[q])
			creep += sum / pts.size()
		# Peak vertical jump of any particle riding on another strand, over the
		# whole run after the lay has dropped onto the floor.
		if tick >= 30 and last_pts.size() == pts.size():
			for q in pts.size():
				if maxf(pts[q].y, last_pts[q].y) > RADIUS * 1.5:
					var dy := absf(pts[q].y - last_pts[q].y)
					if dy > stacked_peak:
						stacked_peak = dy
						stacked_peak_tick = tick
		last_pts = pts
		if slept < 0 and rope.is_sleeping():
			slept = tick
		if tick >= TICKS - 300 and rope.is_sleeping():
			asleep_tail += 1
		var watch: Array = [lower - 1, lower, lower + 1, upper - 1, upper, upper + 1]
		if heap:
			watch = range(pts.size())
		if rope.is_sleeping() != was_sleeping:
			if tick >= TICKS - 600:
				flips += 1
			was_sleeping = rope.is_sleeping()
		for idx: int in watch:
			if tick >= TICKS - 200 and prev_y.has(idx):
				var dyy := absf(pts[idx].y - prev_y[idx])
				if dyy > jitter:
					jitter = dyy
					jitter_at = idx
			prev_y[idx] = pts[idx].y
		if not _video.is_empty() and tick % 3 == 0:
			rope.remesh()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/f%04d.png" % [
				ProjectSettings.globalize_path(_video), frame])
			frame += 1
	var pts := rope.get_points()
	print("[probe] %s first_slept=%s asleep %d/300 of the tail" % [
		"held awake" if awake else "free", str(slept) if slept >= 0 else "NEVER", asleep_tail])
	print("[probe] crossing: lower strand y=%.1f mm, upper strand y=%.1f mm, horizontal gap %.1f mm" % [
		pts[lower].y * 1000.0, pts[upper].y * 1000.0,
		Vector2(pts[lower].x - pts[upper].x, pts[lower].z - pts[upper].z).length() * 1000.0])
	print("[probe] vertical jitter at the crossing, last 200 ticks: %.3f mm/tick (particle %d of %d, at y %.1f mm)" % [
		jitter * 1000.0, jitter_at, pts.size(), pts[maxi(jitter_at, 0)].y * 1000.0])
	var stacked := 0
	var sunk := 0
	for q in pts.size():
		if pts[q].y > RADIUS * 2.0:
			stacked += 1
		if pts[q].y < RADIUS * 0.8:
			sunk += 1
	print("[probe] peak vertical jump of a stacked particle after tick 30: %.3f mm (tick %d)" % [
		stacked_peak * 1000.0, stacked_peak_tick])
	print("[probe] creep: mean particle travel over the last 600 ticks %.2f mm" % (creep * 1000.0))
	print("[probe] sleep/wake flips in the last 600 ticks: %d; particles stacked (y > 2r): %d; sunk into the floor (y < 0.8r): %d of %d" % [
		flips, stacked, sunk, pts.size()])
	get_tree().quit(0)


func _stage_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35.0
	cam.look_at_from_position(Vector3(0.05, 0.05, 0.42), Vector3(-0.05, 0.004, 0.12))
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
	add_child(sun)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 0.2, 4)
	mi.mesh = bm
	mi.position = Vector3(0, -0.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	mi.material_override = mat
	add_child(mi)
	var overlay := get_node_or_null("/root/LoadingOverlay")
	if overlay != null and overlay.has_method("suspend"):
		overlay.suspend()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_video))
