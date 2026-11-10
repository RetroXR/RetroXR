## The RETRO XR nightstand in the Mobile renderer, its drawer pulled out and pushed back in with a TV remote lying in
## it: the remote must ride out and back with the drawer (Jolt, the VRDrawer's physics follow), not slide or fall
## through. Prints where the remote went against where the drawer went, writes stills, and with --frames= a frame
## sequence for an mp4.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/room/nightstand_probe.tscn -- --out=C:/path/to/stills [--frames]
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

const NIGHTSTAND := preload("res://Scenes/Objects/furniture/nightstand.tscn")
const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")

var out_dir := ""
var frames := false
var _n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
		elif String(a) == "--frames":
			frames = true
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
	_light()
	await _run()
	get_tree().quit(0)


func _light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.33, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_energy = 1.7
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(cs)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.44, 0.42)
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)


func _run() -> void:
	var ns := NIGHTSTAND.instantiate() as Nightstand
	add_child(ns)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0.95, 1.25, 1.35), Vector3(0.0, 0.42, 0.08))
	cam.current = true
	for i in 20:
		await get_tree().physics_frame
	_hide_overlays()
	var remote := REMOTE.instantiate() as RigidBody3D
	add_child(remote)
	# Authored lying flat, 175 mm long along Z: it lies along the drawer's depth (270 mm inside).
	remote.global_transform = ns.global_transform * Transform3D(Basis(), Nightstand.DRAWER_SEAT + Vector3(0.06, 0.02, 0.0))
	for i in 60:
		await get_tree().physics_frame
	var d := ns.drawer()
	var rest := remote.global_position
	print("[probe] remote at rest %.1f mm over the drawer floor" % ((rest.y - (ns.global_transform
		* Nightstand.DRAWER_SEAT).y) * 1000.0))
	await _shot("nightstand_shut")
	print("[probe] before the pull the remote is %s" % ("ASLEEP" if remote.sleeping else "awake"))
	# Out over 1.2 s, hold, back in over 1.2 s, as a hand would (VRDrawer.set_value: the body follows on physics).
	var t := 0.0
	var plan := [[0.0, 0.0], [0.4, 0.0], [1.6, 1.0], [2.4, 1.0], [3.6, 0.0], [4.2, 0.0]]
	var peak_rode := 0.0
	var peak_open := 0.0
	while t < 4.2:
		var v := _along(plan, t)
		d.set_value(v)
		await get_tree().process_frame
		t += get_process_delta_time()
		var rode := (remote.global_position - rest).dot(ns.global_basis.z)
		if d.open_distance() > peak_open:
			peak_open = d.open_distance()
			peak_rode = rode
		if frames:
			await _frame()
		if absf(t - 2.0) < 0.02:
			await _shot("nightstand_open")
	var back := (remote.global_position - rest)
	print("[probe] drawer out %.0f mm: the remote rode %.0f mm; shut again it is %.1f mm from where it lay, %.1f mm up" % [
		peak_open * 1000.0, peak_rode * 1000.0, Vector2(back.x, back.z).length() * 1000.0, back.y * 1000.0])
	print("[probe] %s" % ("PASS the remote rode out and back with the drawer"
		if absf(peak_rode - peak_open) < 0.03 and Vector2(back.x, back.z).length() < 0.03 and absf(back.y) < 0.01
		else "FAIL the remote did not ride with the drawer"))
	await _shot("nightstand_back_in")


## Off a headset the loading screen is a flat CanvasLayer over everything (console_stand_probe does the same).
func _hide_overlays() -> void:
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false


func _along(plan: Array, t: float) -> float:
	for i in range(1, plan.size()):
		var a: Array = plan[i - 1]
		var b: Array = plan[i]
		if t <= b[0]:
			var u := clampf((t - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
			return lerpf(a[1], b[1], u * u * (3.0 - 2.0 * u))
	return plan[-1][1]


func _shot(stem: String) -> void:
	if out_dir.is_empty():
		return
	_hide_overlays()
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)


func _frame() -> void:
	if out_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	_n += 1
	if _n % 2 == 0:
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("f_%04d.png" % (_n / 2)))
