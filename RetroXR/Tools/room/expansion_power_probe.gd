## Expansion power probe -- the 32X's own adapter going into its ADAPTOR jack.
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 res://Tools/room/expansion_power_probe.tscn
##       [-- --out=<folder>] [--no-mods]
##
## A Genesis on its MK-2103, a 32X in its slot, and a second MK-2103 slid into the
## 32X's jack (ExpansionPower) along the jack's axis. Checks: the jack is on the
## shell's rear panel, the plug fits it, the pair will not start until the 32X has
## its supply, and starts once it has. Windowed: frames to <out>/frames_NNNNN.png for
## an mp4 (the plug sliding in), and a close-up still, <out>/jack.png.
extends Node3D

const SYSTEM := "res://Scenes/Objects/system.tscn"
const EXPANSION := "res://Scenes/Objects/expansion.tscn"
const BRICK := "res://Scenes/Objects/power/power_brick.tscn"
const OUTLET := "res://Scenes/Objects/room/wall_outlet.tscn"
const SLIDE_FRAMES := 40

var _failures: Array[String] = []
var _out := ""
var _frame := 0
var _cam: Camera3D = null


func _ok(cond: bool, msg: String) -> void:
	print("[xpower] %s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		_failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[xpower] TIMED OUT"); get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	await _frames(5)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	AppPrefs.power_simulation = true
	AppPrefs.mains_region = "na"
	_stage()
	var md := (load(SYSTEM) as PackedScene).instantiate() as RetroSystem
	md.systemid = "genesis"
	md.freeze = true
	add_child(md)
	md.add_to_group("spawned")
	await get_tree().create_timer(2.0).timeout
	md.position.y = -md.body_aabb().position.y
	md.core_start_stand_in = func() -> void: pass
	var unit := (load(EXPANSION) as PackedScene).instantiate() as RetroExpansion
	unit.expansion_id = "sega_32x"
	unit.freeze = true
	unit.position = Vector3(0.6, 0.2, 0)
	add_child(unit)
	unit.add_to_group("spawned")
	await _frames(10)
	md.restore_expansion(unit)
	await _frames(10)
	_ok(md.expansion_ids() == ["sega_32x"], "the 32X is in the Genesis's slot")
	var plate := (load(OUTLET) as PackedScene).instantiate() as WallOutlet
	plate.position = Vector3(0, 0.3, -1.5)
	add_child(plate)
	var md_brick := _brick(Vector3(0.4, 0.05, -0.5))
	var x_brick := _brick(Vector3(-0.4, 0.05, -0.5))
	await _frames(6)
	var md_jack := PowerInput.of(md).inlets()[0] as DcPort
	md_jack.pick_up_object(md_brick.dc_plug)
	(plate.get_node("TopPort") as PowerPort).pick_up_object(md_brick.wall_plug)
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(x_brick.wall_plug)
	await _frames(4)
	var jack := unit.get_node_or_null(ExpansionPower.INLET_NAME) as DcPort
	_ok(jack != null, "the 32X has its own DC IN (%s)" % (jack.connector if jack != null else "none"))
	if jack == null:
		_finish()
		return
	md.toggle_power()
	await _frames(3)
	_ok(not md.is_powered_on, "with nothing in the 32X's jack the Genesis will not start")
	var plug := x_brick.dc_plug
	_ok(plug.is_in_group(jack.snap_require), "the MK-2103's plug fits the 32X's jack (%s)" % jack.connector)
	var seat := jack.global_transform
	var out := seat.basis.z.normalized()
	var start := Transform3D(seat.basis, seat.origin + out * 0.12)
	plug.freeze = true
	plug.global_transform = start
	_cam.look_at_from_position(seat.origin + out * 0.30 + Vector3(-0.12, 0.12, 0.0), seat.origin + out * 0.03)
	for i in 8:
		await _shot()
	for i in SLIDE_FRAMES:
		var t := float(i + 1) / SLIDE_FRAMES
		plug.global_transform = start.interpolate_with(seat, t * t * (3.0 - 2.0 * t))
		await _shot()
	jack.pick_up_object(plug)
	await _frames(4)
	for i in 20:
		await _shot()
	_ok(jack.picked_up_object == plug, "seated in the 32X's jack")
	_ok(PowerInput.of(unit).is_live(), "the 32X has power: %s" % PowerInput.of(unit).describe())
	md.toggle_power()
	await _frames(3)
	_ok(md.is_powered_on, "and the Genesis starts with it")
	if not _out.is_empty():
		_cam.look_at_from_position(seat.origin + out * 0.16 + Vector3(-0.05, 0.05, 0.0), seat.origin)
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(_out.path_join("jack.png"))
		_cam.look_at_from_position(Vector3(0.0, 0.35, -0.6), Vector3(0.0, 0.08, -0.05))
		await _frames(8)
		get_viewport().get_texture().get_image().save_png(_out.path_join("pair.png"))
	md.power_off()
	_finish()


func _brick(at: Vector3) -> PowerBrick:
	var brick := (load(BRICK) as PackedScene).instantiate() as PowerBrick
	brick.brick_id = "sega_mk2103_adapter"
	brick.variant = "usa"
	brick.position = at
	add_child(brick)
	brick.add_to_group("spawned")
	return brick


func _shot() -> void:
	await get_tree().process_frame
	if _out.is_empty():
		return
	get_viewport().get_texture().get_image().save_png(_out.path_join("frames_%05d.png" % _frame))
	_frame += 1


func _finish() -> void:
	print("[xpower] %s (%d failed)" % ["ALL CHECKS PASSED" if _failures.is_empty() else "FAILURES", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 200, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 20, 0)
	fill.light_energy = 0.6
	add_child(fill)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(10, 0.1, 10)
	fs.shape = fb
	fs.position.y = -0.05
	floor_body.add_child(fs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	pm.material = mat
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.near = 0.005
	add_child(_cam)
	_cam.make_current()
