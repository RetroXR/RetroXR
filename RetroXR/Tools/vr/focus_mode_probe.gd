## Windowed probe: a real core on a real television in a furnished room, then VR
## focus mode over it: the room gone, the picture on the floating screen, carried and
## resized, then the room back. Wants a core and a ROM, so it is a probe.
##
##   godot --path RetroXR --resolution 960x600 --position 20,20 \
##     res://Tools/vr/focus_mode_probe.tscn -- "--rom=C:/Users/me/retroxr/roms/nes/game.nes"
##
## Never --headless: the dummy renderer draws nothing. Prints the frame's draw calls
## with the room drawn, hidden, and back.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const OUT := "res://probe_out/focus"

var _rom := ""
var _systemid := "nes"
var _camera: Camera3D
var _fm: FocusMode
var _pickup: Node
var _frame := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			_rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--systemid="):
			_systemid = arg.trim_prefix("--systemid=")
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[probe] SKIP: need --rom=<path to a real ROM>")
		get_tree().quit(1)
		return
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(1))
	LoadingOverlay.suspend()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build_room()
	await _run()


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material_override = mat
	box.position = at
	add_child(box)
	return box


func _build_room() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	_box(Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), Color(0.45, 0.33, 0.22))
	_box(Vector3(8, 3, 0.1), Vector3(0, 1.5, -1.6), Color(0.72, 0.68, 0.58))
	_box(Vector3(0.1, 3, 8), Vector3(-2.6, 1.5, 0), Color(0.6, 0.66, 0.62))
	_box(Vector3(0.9, 1.0, 0.55), Vector3(0, 0.5, -0.05), Color(0.25, 0.18, 0.12))
	_box(Vector3(0.8, 0.9, 0.6), Vector3(1.4, 0.45, 0), Color(0.3, 0.3, 0.34))
	_box(Vector3(0.7, 1.9, 0.5), Vector3(-1.7, 0.95, -1.2), Color(0.5, 0.2, 0.18))

	var rig := Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.2, 1.5, 1.9)
	rig.add_child(_camera)
	_camera.current = true
	_camera.look_at(Vector3(0.3, 1.1, 0), Vector3.UP)
	var loco := LocomotionManager.new()
	rig.add_child(loco)
	var script := GDScript.new()
	script.source_code = "extends Node\nvar picked_up_object: Node3D = null\n"
	script.reload()
	_pickup = Node.new()
	_pickup.set_script(script)
	rig.add_child(_pickup)
	_fm = FocusMode.new()
	rig.add_child(_fm)
	var hands: Array[Node3D] = []
	var pointers: Array[Node] = []
	var pickups: Array[Node] = [_pickup]
	_fm.configure(_camera, null, hands, pointers, pickups, loco, null)


func _run() -> void:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.position = Vector3(0, 1.3, 0)
	tv.freeze = true
	add_child(tv)
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = _systemid
	sys.position = Vector3(1.4, 1.0, 0)
	sys.freeze = true
	add_child(sys)
	await _wait(60)

	var cable := CABLE_SCENE.instantiate() as Node3D
	cable.position = Vector3(0.7, 1.0, 0.4)
	add_child(cable)
	await _wait(20)
	var from := sys.get_node_or_null("VideoOut") as RcaPort
	var to := tv.get_node_or_null("CompositePort") as RcaPort
	if from == null or to == null:
		print("[probe] FAIL: no VideoOut (%s) or CompositePort (%s)" % [from, to])
		get_tree().quit(1)
		return
	from.pick_up_object(cable.get_node("PlugA0") as RcaPlug)
	to.pick_up_object(cable.get_node("PlugB0") as RcaPlug)
	await _wait(30)

	# A pad-sized box low in view, standing in for what the player holds.
	var held := _box(Vector3(0.16, 0.05, 0.1), Vector3.ZERO, Color(0.12, 0.12, 0.14))
	held.global_position = _camera.to_global(Vector3(0.12, -0.2, -0.45))
	_pickup.set("picked_up_object", held)

	if not tv.is_on():
		tv.remote_power_toggle()
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	sys.rom_path = _rom
	sys.power_on()
	print("[probe] rom=%s" % _rom.get_file())
	await _wait(300)

	await _shoot(20, "room")
	var calls_room := _draw_calls()
	_ok(_fm.enter(tv), "focus mode takes the set")
	var hidden_from := _picture(tv)
	await _shoot(30, "focus")
	var calls_focus := _draw_calls()
	_ok(not tv.visible and not sys.visible and held.visible,
		"the set and machine are hidden, the held pad is not")

	# Carried and scaled the way a grip and a stick would.
	var screen := _fm.screen()
	var home := screen.global_position
	for i in 60:
		var s := sin(float(i) / 59.0 * PI)
		screen.global_position = home + Vector3(0.7 * s, 0.2 * s, -0.3 * s)
		screen.set_width(FocusScreen.START_WIDTH * (1.0 + 0.6 * s))
		screen._face(_camera)
		await _shoot(1, "carry")
	_ok(_picture(tv) != hidden_from, "the hidden set's picture keeps changing while focused")
	_fm.leave()
	await _shoot(20, "back")
	var calls_back := _draw_calls()
	print("[probe] draw calls: room=%d focus=%d back=%d" % [calls_room, calls_focus, calls_back])
	_ok(calls_focus < calls_room and calls_back == calls_room,
		"the room stops being drawn while focused and is drawn again after")
	var back_from := _picture(tv)
	await _shoot(150, "later")
	_ok(_picture(tv) != back_from, "the set is still playing after focus mode ends")
	print("[probe] frames=%d" % _frame)
	sys.power_off()
	await _wait(30)
	get_tree().quit(0)


func _ok(ok: bool, what: String) -> void:
	print("[probe] %s  %s" % ["PASS" if ok else "FAIL", what])


## The set's current picture, as bytes.
func _picture(tv: RetroTV) -> PackedByteArray:
	var tex := tv.display().screen_texture()
	return tex.get_image().get_data() if tex != null else PackedByteArray()


func _draw_calls() -> int:
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shoot(n: int, tag: String) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f_%04d.png" % [OUT, _frame])
		if i == n - 1:
			img.save_png("%s/still_%s.png" % [OUT, tag])
		_frame += 1
		await get_tree().process_frame
