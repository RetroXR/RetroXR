## The Game Boy Color stand-in: that the gbc row wears its own shell and not the
## Game Boy's, and that everything on that shell faces the way it should.
##
## Spawns a `gbc` system (and a `gb` one beside it, as the control: the Game Boy
## must still be the Game Boy), seats a cartridge through restore_cartridge() --
## the path a save takes -- and settles each facing by a number: the infrared
## window on the top edge in FRONT of the cartridge, the EXT socket looking out of
## the left flank, the lead leaving down the bottom edge, START and SELECT
## slanting the way A and B do.
##
##   godot --headless --path RetroXR res://Tools/models/game_boy_color_probe.tscn
##
## Windowed (no --headless, `--resolution 320x240 --position 20,20`) it also
## photographs the shell into probe_out/gbc/.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const OUT_DIR := "res://probe_out/gbc"
const SHOT := Vector2i(1200, 900)

var _fail := false
var _shot := 0
var _sv: SubViewport = null
var _cam: Camera3D = null


func _check(ok: bool, what: String) -> void:
	print("[gbc] %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fail = true


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[gbc] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _spawn(systemid: String, at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = at
	sys.ignore_gravity = true
	add_child(sys)
	sys.add_to_group("spawned")
	return sys


func _run() -> void:
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_check(made == OK, "probe_out/gbc is there to write to (%s)" % error_string(made))
	_build_world()
	var sys := _spawn("gbc", Vector3(0, 1, 0))
	var dmg := _spawn("gb", Vector3(-0.13, 1, 0))
	await _wait(40)

	# --- which shell -------------------------------------------------------------
	var model := sys.get("_model") as RetroSystemModelGameBoyColor
	var got: String = (sys.get("_model") as Node).scene_file_path.get_file()
	_check(model != null and got == "game_boy_color_primitive.tscn", "the gbc row wears its own shell: %s" % got)
	var dmg_model := dmg.get("_model") as Node
	_check(dmg_model is RetroSystemModelGameBoy and dmg_model.scene_file_path.get_file() == "game_boy_primitive.tscn",
		"and the gb row still wears the Game Boy's: %s" % dmg_model.scene_file_path.get_file())
	if model == null:
		get_tree().quit(1)
		return
	var to_sys := sys.global_transform.affine_inverse()
	var half := model.body_size * 0.5
	print("[gbc] body_size %s mm" % (model.body_size * 1000.0))
	_check(_near(model.body_size, Vector3(0.078, 0.0274, 0.1335), 0.00001), "body 78 x 27.4 x 133.5 mm")

	# --- the panel ---------------------------------------------------------------
	var quad := model.get_node("HandheldScreen") as MeshInstance3D
	var quad_b := to_sys.basis * quad.global_basis
	_check(_near(quad_b * Vector3.BACK, Vector3.UP), "the screen faces up (+Y): %s" % (quad_b * Vector3.BACK))
	_check(_near(quad_b * Vector3.UP, Vector3.FORWARD), "its picture's top is toward the top edge (-Z): %s" % (quad_b * Vector3.UP))
	_check(absf(model.screen_size.x / model.screen_size.y - 160.0 / 144.0) < 0.001,
		"160:144, %.1f x %.1f mm" % [model.screen_size.x * 1000.0, model.screen_size.y * 1000.0])
	_check(model.get("_lcd_shader") == RetroSystemModelHandheld.PIXEL_AA_SHADER,
		"the panel is a colour one (pixel-AA, not the DMG's greens)")
	_check(dmg_model.get("_lcd_shader") == RetroSystemModelGameBoy.LCD_SHADER, "and the Game Boy keeps its greens")

	# --- the infrared window -----------------------------------------------------
	var ir := _box(to_sys, model.get_node("IrWindow") as MeshInstance3D)
	var mouth := _box(to_sys, model.get_node("CardSlotMouth") as MeshInstance3D)
	print("[gbc] IR window %s .. %s mm" % [ir.position * 1000.0, ir.end * 1000.0])
	_check(ir.position.z < -half.z and ir.end.z > -half.z,
		"the IR window is on the top edge, %.2f mm proud of it" % ((-half.z - ir.position.z) * 1000.0))
	_check(absf(ir.size.x - ir.size.y) < 0.00001, "and square: %.1f x %.1f mm" % [ir.size.x * 1000.0, ir.size.y * 1000.0])
	_check(absf(ir.get_center().x) < 0.00001, "centred across the shell")
	_check(ir.position.y > mouth.end.y and ir.end.y < half.y,
		"in FRONT of the cartridge slot (slot ends y %.1f, window %.1f .. %.1f, face %.1f mm)"
		% [mouth.end.y * 1000.0, ir.position.y * 1000.0, ir.end.y * 1000.0, half.y * 1000.0])

	# --- the face ----------------------------------------------------------------
	var a_btn := model.get_node("FaceButton1") as MeshInstance3D
	var b_btn := model.get_node("FaceButton2") as MeshInstance3D
	_check(a_btn.position.x > b_btn.position.x and a_btn.position.z < b_btn.position.z, "A is right of B and above it")
	for nm: String in ["SelectButton", "StartButton"]:
		var pill := model.get_node(nm) as MeshInstance3D
		# The long axis is local +X. Its right end is the higher one when that
		# axis has a NEGATIVE z; the transpose slants it the other way.
		_check(pill.basis.x.x > 0.9 and pill.basis.x.z < -0.4, "%s rises to the right: long axis %s" % [nm, pill.basis.x])
	_check((model.get_node("SelectButton") as Node3D).position.x < (model.get_node("StartButton") as Node3D).position.x,
		"SELECT is left of START")

	# --- EXT socket and video out ------------------------------------------------
	var port := model.get_node("LinkPort") as LinkPort
	var port_at := to_sys * port.global_position
	var port_out := (to_sys.basis * port.global_basis) * Vector3.BACK
	_check(port_at.x < -half.x and port_out.x < -0.99,
		"EXT socket on the left flank, facing out of it: at %s mm, +Z %s" % [port_at * 1000.0, port_out])
	_check(port.plug_group() == "link_plug", "and it is the Game Boy's socket: %s" % port.plug_group())
	var channels: Array = sys.get("_channels")
	_check(not channels.is_empty(), "the machine has a video-out channel")
	if not channels.is_empty():
		var attach := channels[0].attach as Node3D
		var at := to_sys * attach.global_position
		var lead := (to_sys.basis * attach.global_basis) * Vector3.FORWARD
		_check(at.z > half.z and at.x < 0.0, "video out at the headphone jack, bottom edge left of centre: %s mm" % (at * 1000.0))
		_check(lead.z > 0.9, "and the lead leaves down the bottom edge: %s" % lead)

	# --- the switches ------------------------------------------------------------
	var sw := model.get_node("PowerSwitch") as VRSlider
	var knob := sw.get_node("KnobMesh") as Node3D
	var knob_off := to_sys * knob.global_position
	_check(knob_off.x > half.x - 0.003, "the power switch is on the right flank: %s mm" % (knob_off * 1000.0))
	sw.set_value_no_signal(1.0)
	await _wait(2)
	var slid := to_sys * knob.global_position - knob_off
	_check(_near(slid, Vector3(0, 0, -0.006), 0.00001), "and slides 6 mm UP the edge to ON: %s mm" % (slid * 1000.0))
	sw.set_value_no_signal(0.0)
	var vol := model.get_node("VolumeSlider") as VRSlider
	var wheel := vol.get_node("KnobMesh") as Node3D
	var loud := to_sys * wheel.global_position
	vol.set_value_no_signal(0.0)
	await _wait(2)
	var quiet := to_sys * wheel.global_position
	_check(loud.x < -half.x + 0.003 and loud.z < quiet.z, "volume on the left flank, louder up the edge")
	_check(loud.z - 0.0035 > port_at.z + 0.0065,
		"clear of a seated link plug (%.1f mm between them)" % ((loud.z - 0.0035 - (port_at.z + 0.0065)) * 1000.0))
	vol.set_value_no_signal(1.0)

	var led := model.get_node("PowerLED") as MeshInstance3D
	var dark := led.get_surface_override_material(0)
	model.on_power_on()
	var lit := led.get_surface_override_material(0) as StandardMaterial3D
	_check(lit != null and lit != dark and lit.emission_enabled, "the power lamp lights with the machine")
	model.on_power_off()
	_check(led.get_surface_override_material(0) == dark, "and goes back to its dark lens with it")

	# --- the shared stand-in pass finds every control ----------------------------
	var start := model.get_node("StartButton") as MeshInstance3D
	var bar := model.get_node("DpadBar2") as MeshInstance3D
	var a_rest := a_btn.position
	var start_rest := start.position
	var up_arm := Vector3(0, 0, -0.01)
	var arm_rest := bar.transform * up_arm
	var held := (1 << ControllerBindings.JOYPAD_A) | (1 << ControllerBindings.JOYPAD_START) | (1 << ControllerBindings.JOYPAD_UP)
	for i in 40:
		model.animate_controls(held, Vector2.ZERO, Vector2.ZERO)
	_check(a_btn.position.y < a_rest.y - 0.0005 and absf(b_btn.position.y - a_rest.y) < 0.00001,
		"A sinks %.2f mm and B stays" % ((a_rest.y - a_btn.position.y) * 1000.0))
	_check(start.position.y < start_rest.y - 0.0003, "START sinks %.2f mm" % ((start_rest.y - start.position.y) * 1000.0))
	_check((bar.transform * up_arm).y < arm_rest.y - 0.0002,
		"UP sinks the D-pad's top arm %.2f mm" % ((arm_rest.y - (bar.transform * up_arm).y) * 1000.0))
	for i in 60:
		model.animate_controls(0, Vector2.ZERO, Vector2.ZERO)
	_check(a_btn.position.distance_to(a_rest) < 0.00002 and start.position.distance_to(start_rest) < 0.00002,
		"and everything comes back")

	# The Game Boy stands in front of the left flank; it is in the last picture only.
	dmg.visible = false
	if DisplayServer.get_name() != "headless":
		await _shots(sys, "")

	# --- the cartridge -----------------------------------------------------------
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "gbc"
	cart.game_label = "PROBE"
	cart.position = Vector3(0, 1.3, 0)
	add_child(cart)
	cart.add_to_group("spawned")
	await _wait(20)
	sys.restore_cartridge(cart)
	await _wait(40)
	var size := MediaDimensions.cart_size("gbc")
	var rel := to_sys * cart.global_transform
	var grip := rel * Vector3(0, size.y * 0.5, 0)
	print("[gbc] cart x %s y %s z %s o %s mm" % [rel.basis.x, rel.basis.y, rel.basis.z, rel.origin * 1000.0])
	_check((rel.basis * Vector3.UP).z < -0.99, "the cartridge's grip is out of the top edge")
	_check((rel.basis * Vector3.BACK).y < -0.99, "its label toward the back of the console")
	_check(absf((-half.z - grip.z) - model._cart_protrude()) < 0.0001,
		"standing %.1f mm out of the top edge" % ((-half.z - grip.z) * 1000.0))
	_check(absf(rel.origin.x) < 0.0001 and rel.origin.y + size.z * 0.5 < ir.position.y
			and rel.origin.y - size.z * 0.5 > -half.y,
		"inside the shell and BEHIND the IR window (cart y %.1f .. %.1f, window from %.1f mm)"
		% [(rel.origin.y - size.z * 0.5) * 1000.0, (rel.origin.y + size.z * 0.5) * 1000.0, ir.position.y * 1000.0])

	if DisplayServer.get_name() != "headless":
		model.on_power_on()
		await _shots(sys, "cart_")
		model.on_power_off()
		dmg.visible = true
		await _pair_shot(sys, dmg)

	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	await _wait(5)
	cart.queue_free()
	sys.queue_free()
	dmg.queue_free()
	await _wait(3)
	print("[gbc] %s" % ("ALL CHECKS PASSED" if not _fail else "FAILED"))
	get_tree().quit(1 if _fail else 0)


## A mesh's bounds in the system's frame.
func _box(to_sys: Transform3D, mesh: MeshInstance3D) -> AABB:
	return (to_sys * mesh.global_transform) * mesh.get_aabb()


func _near(a: Vector3, b: Vector3, tol: float = 0.001) -> bool:
	return a.distance_to(b) < tol


# --- windowed: pictures --------------------------------------------------------

func _camera() -> void:
	if _cam != null:
		return
	_sv = SubViewport.new()
	_sv.size = SHOT
	_sv.own_world_3d = false
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.005
	_cam.far = 5.0
	_cam.fov = 28.0
	_sv.add_child(_cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)


func _shots(sys: Node3D, tag: String) -> void:
	_camera()
	var c := sys.global_position
	var top := c + Vector3(0, 0, -0.06675)
	# Straight down at the face, the top edge end on (the infrared window, and the
	# cartridge behind it), over that edge from the front, each flank, and the
	# whole machine as it sits in the hand.
	for spec: Array in [[c + Vector3(0, 0.42, 0.0001), c, Vector3.FORWARD, "face"],
			[top + Vector3(0, 0.03, -0.20), top, Vector3.UP, "top_edge"],
			[top + Vector3(0.05, 0.13, -0.13), top, Vector3.UP, "top_edge_above"],
			[c + Vector3(-0.30, 0.05, -0.03), c, Vector3.UP, "left_flank"],
			[c + Vector3(0.30, 0.05, -0.03), c, Vector3.UP, "right_flank"],
			[c + Vector3(-0.09, 0.30, 0.24), c, Vector3.UP, "front"]]:
		await _snap(spec[0], spec[1], spec[2], "%s%s" % [tag, spec[3]])


## The Color beside the Game Boy it used to borrow.
func _pair_shot(sys: Node3D, dmg: Node3D) -> void:
	_camera()
	var mid := (sys.global_position + dmg.global_position) * 0.5
	await _snap(mid + Vector3(0, 0.50, 0.0001), mid, Vector3.FORWARD, "beside_game_boy")


func _snap(eye: Vector3, target: Vector3, up: Vector3, file: String) -> void:
	_cam.look_at_from_position(eye, target, up)
	_cam.current = true
	await _wait(8)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	# FORMAT_RGB8 first: the frame carries an alpha channel nothing fills, and a
	# straight save writes a picture every viewer paints as a blank rectangle.
	var img := _sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := OUT_DIR.path_join("%02d_%s.png" % [_shot, file])
	var err := img.save_png(path)
	_shot += 1
	_check(err == OK, "wrote %s%s" % [path, "" if err == OK else " (%s)" % error_string(err)])


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.31, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.74, 0.80)
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)
	for spec in [[Vector3(-46, -30, 0), 1.9], [Vector3(-12, 150, 0), 0.7]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		add_child(light)
