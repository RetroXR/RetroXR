## PC tower drives probe -- each of the RETRO XR tower's three drives ejecting, filmed.
##
##   godot --path RetroXR --resolution 320x240 --position 20,20 res://Tools/models/pc_tower_drives_probe.tscn
##   [-- --only=cd|525|35]
##
## Three legs, each its own tower and its own medium, the machine switched off (no core
## needed): the CD tray of a ScummVM tower opening with its disc and closing; a C64
## tower's 5.25 in disk seated, then the drive's latch turned and the disk springing
## out; a DOS tower's 3.5 in disk seated, then its eject button pressed. Every press is
## the button's own (VRButton._activate, as a fingertip or the laser gives it).
## Frames go to res://probe_out/pc_drives/<leg>_NNNN.png; Tools/art or a one-liner turns
## them into an mp4. Asserts, not just films: after an eject the slot must be empty and
## the disk out of the drive; after the CD's second press the tray must be home.
##
## Windowed, never --headless (the dummy renderer films nothing).
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const OUT := "res://probe_out/pc_drives"

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _fails := 0
var _frame := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[pcdrives] TIMEOUT"); get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 720)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.56, 0.58)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.62, 0.64)
	e.ambient_light_energy = 0.9
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 28, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor := CSGBox3D.new()
	floor.size = Vector3(4, 0.02, 4)
	floor.position = Vector3(0, -0.01, 0)
	floor.use_collision = true
	_world.add_child(floor)
	_cam = Camera3D.new()
	_cam.fov = 40
	_world.add_child(_cam)
	_cam.current = true
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	if only in ["", "cd"]:
		await _leg_cd()
	if only in ["", "525"]:
		await _leg_floppy("525", "c64", "Floppy525LatchButton", Vector3(0.0, 0.325, 0.23))
	if only in ["", "35"]:
		await _leg_floppy("35", "dos", "Floppy35EjectButton", Vector3(0.0, 0.245, 0.23))
	print("[pcdrives] RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _ok(cond: bool, what: String, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("[pcdrives] %s  %s%s" % ["ok  " if cond else "FAIL", what, ("  -- " + detail) if detail != "" else ""])


func _tower(systemid: String) -> Node3D:
	var sys := SYSTEM_SCENE.instantiate() as Node3D
	sys.model_id = "pc_tower"
	sys.systemid = systemid
	sys.freeze = true
	_world.add_child(sys)
	await _settle(90)            # the shell lands and the bay is placed
	return sys


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Film `frames` frames of the leg (every other one is kept).
func _film(leg: String, frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
		if i % 2 == 0:
			_vp.get_texture().get_image().save_png("%s/%s_%04d.png" % [OUT, leg, _frame])
			_frame += 1


func _aim(target: Vector3, from: Vector3) -> void:
	_cam.look_at_from_position(from, target)


func _press(sys: Node3D, button_name: String) -> void:
	var b := sys.get_model().find_child(button_name, true, false) as VRButton
	if b == null:
		b = sys.find_child(button_name, true, false) as VRButton
	_ok(b != null, "%s: the %s is there" % [sys.systemid, button_name])
	if b != null:
		b.call("_activate")


func _leg_cd() -> void:
	_frame = 0
	var sys := await _tower("scummvm")
	_aim(Vector3(0.0, 0.36, 0.30), Vector3(0.24, 0.55, 0.62))
	var disc := DISC_SCENE.instantiate() as Node3D
	disc.systemid = "scummvm"
	_world.add_child(disc)
	await _settle(5)
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	slot.pick_up_object(disc)
	await _settle(30)
	_ok(sys.get_snapped_cartridge() == disc, "cd: the tray holds the disc")
	await _film("cd", 30)
	var pivot := sys.get_model().get_node("TrayPivot") as Node3D
	var rest := pivot.position
	_press(sys, "EjectButton")   # the machine's own EJECT key
	await _film("cd", 90)
	_ok(pivot.position.z > rest.z + 0.13, "cd: EJECT slides the tray out", "%.0f mm" % ((pivot.position.z - rest.z) * 1000.0))
	_ok(disc.global_position.z > sys.global_position.z + 0.30, "cd: the disc rides out on it")
	_press(sys, "EjectButton")
	await _film("cd", 90)
	_ok(absf(pivot.position.z - rest.z) < 0.002, "cd: EJECT again takes it home")
	sys.queue_free()
	disc.queue_free()
	await _settle(10)


func _leg_floppy(leg: String, systemid: String, button: String, focus: Vector3) -> void:
	_frame = 0
	var sys := await _tower(systemid)
	_aim(focus, focus + Vector3(0.22, 0.10, 0.36))
	var disk := CART_SCENE.instantiate() as RigidBody3D
	disk.systemid = systemid
	disk.freeze = true
	disk.position = Vector3(0.0, 0.6, 0.5)
	_world.add_child(disk)
	await _settle(10)
	await _film(leg, 16)
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	slot.pick_up_object(disk)
	await _film(leg, 40)
	_ok(sys.get_snapped_cartridge() == disk, "%s: the drive takes the %s disk" % [leg, systemid])
	var seated_z := (sys.global_transform.affine_inverse() * disk.global_position).z
	await _settle(10)
	_press(sys, button)
	await _film(leg, 70)
	var out_z := (sys.global_transform.affine_inverse() * disk.global_position).z
	_ok(sys.get_snapped_cartridge() == null, "%s: ejected, the slot is empty" % leg)
	_ok(out_z > seated_z + 0.015, "%s: and the disk sprang out of the drive" % leg, "%.1f mm" % ((out_z - seated_z) * 1000.0))
	_ok(not slot.enabled, "%s: the slot waits for a hand before it takes a disk again" % leg)
	if leg == "525":
		var lever := sys.get_model().find_child(button, true, false).get_node("ButtonMesh") as Node3D
		_ok(absf(lever.rotation.z - PI * 0.5) < 0.05, "525: the latch turned open", "%.0f deg" % rad_to_deg(lever.rotation.z))
	sys.queue_free()
	disk.queue_free()
	await _settle(10)
