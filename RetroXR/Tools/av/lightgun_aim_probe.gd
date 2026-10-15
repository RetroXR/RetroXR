## Measures how far a light gun's aim lands from what the player is pointing
## at, on a set's REAL glass with a picture on it. For a grid of picture points
## it finds where each is drawn on the tube (the mesh UV the CRT stage maps it
## from, after the fit the set's material carries), casts a camera ray through
## that point, and asks ScreenAim where the ray lands. Beside it, the flat
## plane through the mesh origin that LightGun used to meet, as the control:
## it must still show the error ScreenAim removed, or the check proves nothing.
##
##   godot --headless --path RetroXR res://Tools/av/lightgun_aim_probe.tscn -- \
##     [--shell=xenu.panasonic:ct20d10b] [--curvature=0.1]
##
## A mod's shell has to be installed and enabled. Exits 1 when any new error
## is over --tolerance (px, default 0.5) or the control shows none.
extends Node3D

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
## Picture points, (0,0) top left, as the shader's fuv.
const TARGETS: Array[Vector2] = [
	Vector2(0.5, 0.5), Vector2(0.25, 0.25), Vector2(0.75, 0.25),
	Vector2(0.25, 0.75), Vector2(0.75, 0.75), Vector2(0.05, 0.5), Vector2(0.95, 0.5),
	Vector2(0.5, 0.05), Vector2(0.5, 0.95),
]
const FRAME := Vector2(640.0, 448.0)


class StubSource extends Node3D:
	var texture: Texture2D

	func sends_video_to(_tv: Node) -> bool:
		return true

	func get_video_texture() -> Texture2D:
		return texture

	func get_video_stage(_tv: Node) -> Dictionary:
		return {}

	func set_audio_volume(_v: float) -> void:
		pass

	func get_rf_channel() -> int:
		return -1


var _shell := ""
var _curvature := -1.0
var _tolerance := 0.5


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void: get_tree().quit(2))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shell="):
			_shell = arg.trim_prefix("--shell=")
		elif arg.begins_with("--curvature="):
			_curvature = float(arg.trim_prefix("--curvature="))
		elif arg.begins_with("--tolerance="):
			_tolerance = float(arg.trim_prefix("--tolerance="))
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.tv_model = _shell
	tv.freeze = true
	add_child(tv)
	for i in 30:
		await get_tree().process_frame
	if _shell != "" and tv.shell() == null:
		print("[probe] shell '%s' did not load" % _shell)
		get_tree().quit(1)
		return
	var src := StubSource.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	src.texture = ImageTexture.create_from_image(img)
	add_child(src)
	tv._panel._connected_systems[RetroTV.Source.COMPOSITE_3] = src
	tv.set_source(RetroTV.Source.COMPOSITE_3)
	for i in 8:
		await get_tree().process_frame
	if _curvature >= 0.0:
		tv.set_crt_param("crt_curvature", _curvature)
		await get_tree().process_frame

	var mi := tv.get_screen_mesh()
	var mat := mi.get_surface_override_material(0) as ShaderMaterial
	if mat == null or not RetroTV.is_crt_shader(mat.shader):
		print("[probe] the glass is not wearing the CRT stage: %s" % mi.get_surface_override_material(0))
		get_tree().quit(1)
		return
	var fit: Vector2 = ScreenAim._param(mat, "fit_scale", Vector2.ONE)
	var curvature := float(ScreenAim._param(mat, "crt_curvature", 0.0))
	var aabb := mi.mesh.get_aabb()
	var xf := mi.global_transform
	print("[probe] shell=%s aabb %s size %s, fit_scale %s, crt_curvature %.2f" % [
		_shell if _shell != "" else "stock", aabb.position, aabb.size, fit, curvature])

	var aim := ScreenAim.new(mi)
	var faces := aim._faces
	var uvs := aim._uvs
	var eye := 1.65 - xf.origin.y
	var poses: Array = [
		["head-on, level, 1.5 m", Vector3(0, 0, 1.5)],
		["standing, 1.5 m", Vector3(0, eye, 1.5)],
		["standing, 2.5 m", Vector3(0, eye, 2.5)],
		["standing, 1.0 m", Vector3(0, eye, 1.0)],
		["standing, 1.5 m, 0.4 m right", Vector3(0.4, eye, 1.5)],
		["crouched, 1.0 m, 0.6 m left", Vector3(-0.6, -0.2, 1.0)],
	]
	var worst_new := 0.0
	var worst_old := 0.0
	for pose: Array in poses:
		var cam: Vector3 = xf * (pose[1] as Vector3)
		var pose_new := 0.0
		var pose_old := 0.0
		var line := ""
		for t: Vector2 in TARGETS:
			var glass_uv := _glass_uv_for(t, fit, curvature)
			var local: Variant = _point_at_uv(faces, uvs, glass_uv)
			if local == null:
				print("[probe]   target %s: no triangle carries uv %s" % [t, glass_uv])
				get_tree().quit(1)
				return
			var p_world: Vector3 = xf * (local as Vector3)
			var dir := (p_world - cam).normalized()
			var got := aim.hit(cam, dir)
			if got.is_empty():
				var inv := xf.affine_inverse()
				var raw := aim._triangles.intersect_segment(inv * cam, inv * (cam + dir * 10.0))
				print("[probe]   target %s from %s: ScreenAim missed; glass point %s, raw %s" % [
					t, pose[0], local, raw])
				get_tree().quit(1)
				return
			var err_new: Vector2 = ((got["picture"] as Vector2) - t) * FRAME
			var err_old: Vector2 = (_plane_uv(xf, aabb, cam, dir) - t) * FRAME
			pose_new = maxf(pose_new, err_new.length())
			pose_old = maxf(pose_old, err_old.length())
			if t == Vector2(0.5, 0.5):
				line = "centre old (%+.1f, %+.1f) new (%+.2f, %+.2f)" % [err_old.x, err_old.y,
					err_new.x, err_new.y]
		print("[probe] %-30s worst old %5.1f px, new %.3f px; %s" % [pose[0], pose_old, pose_new, line])
		worst_new = maxf(worst_new, pose_new)
		worst_old = maxf(worst_old, pose_old)
	var ok := worst_new <= _tolerance and worst_old > 2.0
	print("[probe] worst old %.1f px, new %.3f px (tolerance %.2f): %s" % [worst_old, worst_new,
		_tolerance, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


## The glass UV the CRT stage draws picture point `t` at: fuv = (warp(uv) - 0.5)
## / fit + 0.5, solved for uv. The warp has no closed inverse, so it is walked
## back by fixed point; it converges in a few steps for the slider's range.
func _glass_uv_for(t: Vector2, fit: Vector2, curvature: float) -> Vector2:
	var want_w := (t - Vector2(0.5, 0.5)) * fit + Vector2(0.5, 0.5)
	if curvature <= 0.0:
		return want_w
	var target := want_w * 2.0 - Vector2.ONE
	var cc := target
	for i in 60:
		cc = target / (1.0 + curvature * cc.dot(cc))
	return cc * 0.5 + Vector2(0.5, 0.5)


## The old LightGun sums: a plane through the mesh origin, x and y off the bounds.
func _plane_uv(xf: Transform3D, aabb: AABB, origin: Vector3, dir: Vector3) -> Vector2:
	var plane := Plane(xf.basis.z, xf.origin)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector2(-1, -1)
	var local: Vector3 = xf.affine_inverse() * (hit as Vector3)
	return Vector2(local.x / aabb.size.x + 0.5, -local.y / aabb.size.y + 0.5)


## The mesh-local point whose interpolated UV is `uv`, searched in UV space, so
## it shares nothing with ScreenAim's ray search but the mesh.
func _point_at_uv(faces: PackedVector3Array, uvs: PackedVector2Array, uv: Vector2) -> Variant:
	for i in range(0, faces.size(), 3):
		var a := uvs[i]
		var v0 := uvs[i + 1] - a
		var v1 := uvs[i + 2] - a
		var v2 := uv - a
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var s := (v2.x * v1.y - v1.x * v2.y) / den
		var r := (v0.x * v2.y - v2.x * v0.y) / den
		if s >= -1e-6 and r >= -1e-6 and s + r <= 1.0 + 1e-6:
			return faces[i] * (1.0 - s - r) + faces[i + 1] * s + faces[i + 2] * r
	return null
