## A video of the RETRO XR DVD player's tray, windowed, one PNG per frame at a fixed 30 fps step:
##   godot --path RetroXR res://Tools/av/dvd_tray_video_probe.tscn --resolution 320x240 --position 20,20 --fixed-fps 30 -- --out=<dir>
## Open empty, a disc lowered into the well, shut with it, open again, shut. Encode frames/ with imageio.
extends Node

const DVD_SCENE := "res://Scenes/Objects/appliances/dvd_player.tscn"
const DISC_SCENE := "res://Scenes/Objects/media/dvd_disc.tscn"

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _world: Node3D
var _n := 0
var _t := 0.0
var _seat_shut: Transform3D
var _seat_in_tray: Transform3D


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	_stage()
	await _run()
	print("[probe] %d frames" % _n)
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.041, 0)
	_world.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 38
	_world.add_child(_cam)
	_cam.current = true


## One frame: the camera drifts slowly round the front, then the frame is saved.
func _frame() -> void:
	await get_tree().process_frame
	_t += 1.0 / 30.0
	var a := deg_to_rad(-28.0 + 9.0 * sin(_t * 0.35))
	var at := Vector3(-0.07, 0.0, 0.14)
	_cam.look_at_from_position(at + Vector3(sin(a) * 0.52, 0.30, cos(a) * 0.52), at)
	_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
	_n += 1


func _frames(count: int) -> void:
	for i in count:
		await _frame()


func _until(dvd: DVDPlayer) -> void:
	await _frames(3)
	var guard := 0
	while dvd._tray_anim != "" and guard < 300:
		await _frame()
		guard += 1


func _run() -> void:
	var dvd := (load(DVD_SCENE) as PackedScene).instantiate() as DVDPlayer
	dvd.freeze = true
	_world.add_child(dvd)
	for i in 6:
		await get_tree().process_frame
	await _frames(30)
	var m := dvd.find_child("Model", true, false) as ApplianceModel
	_seat_shut = m.part("DiscSeat").global_transform
	_seat_in_tray = m.part("Tray").global_transform.affine_inverse() * _seat_shut
	dvd._on_eject_pressed()
	await _until(dvd)
	print("[probe] tray out at frame %d" % _n)
	await _frames(30)
	# A disc lowered by hand onto the tray, then taken by the slot.
	var disc := (load(DISC_SCENE) as PackedScene).instantiate() as RigidBody3D
	disc.freeze = true
	_world.add_child(disc)
	var model := dvd.find_child("Model", true, false) as ApplianceModel
	var tray := model.part("Tray")
	var seat := tray.global_transform * _seat_in_tray
	print("[probe] lowering onto the seat, %.3f m out from the shut tray's" % (seat.origin - _seat_shut.origin).length())
	for i in 36:
		var k := float(i) / 35.0
		disc.global_transform = Transform3D(seat.basis, seat.origin + Vector3(0, 0.002 + 0.12 * (1.0 - k * k * (3.0 - 2.0 * k)), 0.0))
		await _frame()
	dvd._slot._accept(disc, false)
	await _until(dvd)
	print("[probe] shut with the disc at frame %d" % _n)
	await _frames(24)
	dvd._on_eject_pressed()
	await _until(dvd)
	await _frames(36)
	dvd._on_eject_pressed()
	await _until(dvd)
	await _frames(30)
