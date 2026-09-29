## The 32X's scanned shell and its Model 2 spacer, clipped together and seated on
## a Mega Drive with a cartridge in it.
##
## Prints the numbers the seat is judged by -- which way the unit faces on the
## console, how its underside sits against the console's roof, how deep its plug
## goes, and where a cartridge in its own slot lands against the slot's floor --
## and writes a few stills of the assembly and of the unit alone.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/models/sega32x_probe.tscn -- --out=C:/path/to/stills
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

const STAGE := Vector3(0, 1.0, 0)

var out_dir := ""
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_light()
	await _run()
	get_tree().quit(0)


func _light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.6
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_energy = 0.6
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _wait(3)
	await RenderingServer.frame_post_draw
	if out_dir.is_empty():
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("[probe] wrote %s" % name)


func _marker(unit: RetroExpansion, name: String) -> Node3D:
	return unit.find_child(name, true, false) as Node3D


## The status and options panels a console and a unit float beside themselves
## stand in front of these cameras; only the hardware is wanted. Everything drawn
## is hidden except what lies under `keep` (the 32X's shell, the console's model,
## the cartridge).
var keep: Array[Node] = []


func _hide_panels(_root: Node = null) -> void:
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var wanted := false
		for k in keep:
			if is_instance_valid(k) and (k == n or k.is_ancestor_of(n)):
				wanted = true
				break
		if not wanted and not n is Light3D:
			(n as VisualInstance3D).visible = false


func _run() -> void:
	var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
	unit.expansion_id = "sega_32x"
	unit.freeze = true
	add_child(unit)
	unit.global_position = STAGE + Vector3(0.0, 0.0, 0.5)
	await _wait(12)
	var shell := unit.get_node_or_null("Shell") as Node3D
	print("[probe] shell=%s scale=%s position=%s" % [shell != null,
		shell.scale if shell else Vector3.ZERO, shell.position if shell else Vector3.ZERO])
	var alone := unit.global_position
	keep.append(shell)

	# The Model 2 spacer, spawned on its own beside the unit, then clipped on.
	var spacer := ScenePersistence.instantiate("sega32x_spacer") as Sega32xSpacer
	spacer.freeze = true
	add_child(spacer)
	spacer.global_position = alone + Vector3(0.20, -0.02, 0.0)
	await _wait(12)
	keep.append(spacer)
	_hide_panels()
	await _shot("unit_and_spacer", alone + Vector3(0.28, 0.18, 0.40), alone + Vector3(0.10, -0.01, 0))
	unit.restore_accessory(spacer)
	await _wait(6)
	print("[probe] spacer clipped on: %s, %.2f mm from the shell's origin" % [
		unit.get_accessory() == spacer, spacer.global_position.distance_to(shell.global_position) * 1000.0])
	await _shot("unit_front", alone + Vector3(0.20, 0.14, 0.34), alone)
	await _shot("unit_below", alone + Vector3(0.22, -0.20, 0.30), alone + Vector3(0, -0.02, 0))

	var host := SYSTEM_SCENE.instantiate() as RetroSystem
	host.systemid = "genesis"
	host.freeze = true
	add_child(host)
	host.global_position = STAGE
	await _wait(30)
	host.restore_cartridge(unit)
	await _wait(12)

	keep.append(host.get("_model"))
	_hide_panels()
	var inv := host.global_transform.affine_inverse()
	var roof := host.body_aabb()
	var ub := inv.basis * unit.global_transform.basis
	print("[probe] unit +Z in the console's frame: %s (the console faces +Z)" % (ub * Vector3.BACK))
	var seat_plane := (inv * unit.global_transform * shell.transform).origin.y if shell else NAN
	print("[probe] console body top y=%.4f  32X resting plane y=%.4f  gap %.1f mm" % [
		roof.end.y, seat_plane, (seat_plane - roof.end.y) * 1000.0])
	var plug := _marker(unit, "PlugSeat")
	if plug != null:
		var p := inv * plug.global_position
		print("[probe] plug board edge at y=%.4f (console floor 0), x=%.4f z=%.4f" % [p.y, p.x, p.z])
	var sm := spacer.find_children("*", "MeshInstance3D", true, false)
	if not sm.is_empty():
		var m := sm[0] as MeshInstance3D
		var sb := (inv * m.global_transform) * m.get_aabb()
		print("[probe] spacer floor y=%.4f -> %.1f mm above the console's top" % [
			sb.position.y, (sb.position.y - roof.end.y) * 1000.0])
	await _shot("seated_front", STAGE + Vector3(0.36, 0.26, 0.52), STAGE + Vector3(0, 0.05, 0))
	await _shot("seated_side", STAGE + Vector3(0.62, 0.08, 0.0), STAGE + Vector3(0, 0.05, 0))
	await _shot("seated_rear", STAGE + Vector3(-0.30, 0.22, -0.52), STAGE + Vector3(0, 0.05, 0))

	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "sega32x"
	cart.rom_path = "Z:/roms/sega32x/demo.32x"
	cart.freeze = true
	add_child(cart)
	cart.global_position = STAGE + Vector3(0.3, 0.3, 0.3)
	await _wait(12)
	unit.restore_media(cart)
	await _wait(12)
	keep.append(cart)
	_hide_panels()
	var floor_marker := _marker(unit, "CartFloor")
	if floor_marker != null:
		var cu := unit.to_local(cart.global_position)
		var fu := unit.to_local(floor_marker.global_position)
		var h: float = MediaDimensions.cart_size("sega32x").y
		print("[probe] cart centre (unit) %s; its bottom sits %.1f mm above CartFloor, %.1f mm off in z" % [
			cu, (cu.y - h * 0.5 - fu.y) * 1000.0, (cu.z - fu.z) * 1000.0])
	for f: String in ["Flap_Front", "Flap_Back"]:
		var n := _marker(unit, f)
		if n != null:
			print("[probe] %s rotation.x %.1f deg" % [f, rad_to_deg(n.rotation.x)])
	await _shot("cart_front", STAGE + Vector3(0.34, 0.30, 0.50), STAGE + Vector3(0, 0.09, 0))
	await _shot("cart_slot", STAGE + Vector3(0.10, 0.34, 0.20), STAGE + Vector3(0, 0.08, -0.03))
