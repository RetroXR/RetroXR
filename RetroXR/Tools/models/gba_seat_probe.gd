## The detailed Game Boy Advance: where a GBA cartridge seats in it, and whether
## its real controls move.
##
## Spawns the `game_boy_advance` model and a gba cartridge, seats the cart through
## restore_cartridge() (the same path a save takes), and checks the cartridge
## model against the console model's own CartridgeSocket: the node the console
## GLB carries for exactly this, fitted in codex-photos/gba to the laser-scanned
## slot with the same cartridge GLB. It writes the seated pose to
## probe_out/gba_seat/cart_in_console.json, in the console GLB's frame, for a mesh
## intersection check outside Godot.
##
##   godot --headless --path RetroXR res://Tools/models/gba_seat_probe.tscn
##
## Windowed (no --headless) it also renders the seated cart from four sides into
## probe_out/gba_seat/.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const OUT_DIR := "res://probe_out/gba_seat"
const SHOT := Vector2i(1200, 900)

var _fail := false
var _shot := 0


func _check(ok: bool, what: String) -> void:
	print("[gba] %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fail = true


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[gba] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_world()
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gba"
	sys.model_id = "game_boy_advance"
	sys.position = Vector3(0, 1, 0)
	sys.ignore_gravity = true
	add_child(sys)
	sys.add_to_group("spawned")
	await _wait(40)
	var model := sys.get("_model") as RetroSystemModelGameBoyAdvance
	_check(model != null and model.has_baked_shell(), "the gba row spawns the detailed shell")
	if model == null or not model.has_baked_shell():
		get_tree().quit(1)
		return
	var console := model.find_child("GBA_Console", true, false) as Node3D
	var socket := console.find_child("CartridgeSocket", true, false) as Node3D
	var to_sys := sys.global_transform.affine_inverse()

	# --- lay-back and size -----------------------------------------------------
	var shell_b := (to_sys * console.global_transform).basis
	_check(_near(shell_b * Vector3.BACK, Vector3.UP), "the screen faces up (+Y): %s" % (shell_b * Vector3.BACK))
	_check(_near(shell_b * Vector3.UP, Vector3.FORWARD), "the top edge is toward -Z: %s" % (shell_b * Vector3.UP))
	print("[gba] body_size %s" % (model.body_size * 1000.0))
	_check(_near(model.body_size, Vector3(0.14454, 0.02688, 0.082), 0.0003), "body 144.5 x 26.9 x 82.0 mm")
	var bb: AABB = model._glb_local_aabb(model.get_node("Shell"))
	_check(bb.get_center().length() < 0.0002, "the shell is centred on the model: %s mm" % (bb.get_center() * 1000.0))

	# --- screen ------------------------------------------------------------------
	var quad := model.get_node("HandheldScreen") as MeshInstance3D
	var lcd := console.find_child("Screen", true, false) as MeshInstance3D
	_check(quad.global_position.distance_to(lcd.global_position) < 0.00005, "the picture quad sits on the GLB's LCD")
	_check(_near(quad.global_basis * Vector3.BACK, sys.global_basis * Vector3.UP), "and faces up")
	_check(not lcd.visible, "the GLB's own LCD quad is hidden")
	_check(quad.get_surface_override_material(0) == lcd.get_active_material(0), "the quad wears the GLB's unlit LCD")

	# --- the cartridge --------------------------------------------------------------
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "gba"
	cart.game_label = "PROBE"
	cart.position = Vector3(0, 1.3, 0)
	add_child(cart)
	cart.add_to_group("spawned")
	await _wait(20)
	sys.restore_cartridge(cart)
	await _wait(40)
	var body := cart.get_node_or_null("CartModel") as Node3D
	_check(body != null, "the cartridge wears gba_cart.glb")
	var rel: Transform3D = console.global_transform.affine_inverse() * body.global_transform
	var want: Transform3D = socket.transform
	print("[gba] cart GLB in the console GLB: x %s y %s z %s o %s mm" % [rel.basis.x, rel.basis.y, rel.basis.z, rel.origin * 1000.0])
	print("[gba] CartridgeSocket:             x %s y %s z %s o %s mm" % [want.basis.x, want.basis.y, want.basis.z, want.origin * 1000.0])
	_check(rel.origin.distance_to(want.origin) < 0.0002, "seated where the console's CartridgeSocket is (%.3f mm off)" % (rel.origin.distance_to(want.origin) * 1000.0))
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_check(_near((rel.basis * axis).normalized(), want.basis * axis), "and turned as it is (cart %s)" % axis)
	_check(_near(rel.basis.get_scale(), Vector3.ONE, 0.002), "unsquashed: scale %s" % rel.basis.get_scale())
	_check((rel.basis * Vector3.BACK).z < -0.99, "label toward the back of the console")
	_check((rel.basis * Vector3.UP).y > 0.99, "grip out of the top edge")
	var f := FileAccess.open(OUT_DIR.path_join("cart_in_console.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"basis_x": _v(rel.basis.x), "basis_y": _v(rel.basis.y), "basis_z": _v(rel.basis.z),
		"origin": _v(rel.origin)}))
	f.close()

	# --- EXT socket and video out ------------------------------------------------------
	var port := model.get_node("LinkPort") as Node3D
	var p := to_sys * port.global_position
	_check(_near(p, Vector3(0.0087, 0.006587, -0.041999), 0.0001), "EXT socket on the top edge at x = 8.7 mm")
	_check(_near((to_sys.basis * port.global_basis) * Vector3.BACK, Vector3.FORWARD), "and faces out of it")
	_check(not (port.get_node("LinkJack") as Node3D).visible, "the placeholder jack is hidden")
	var channels: Array = sys.get("_channels")
	if not channels.is_empty():
		var attach := channels[0].attach as Node3D
		var a := to_sys * attach.global_position
		_check(_near(a, Vector3(0.04184, -0.001563, 0.035901), 0.0002), "video out at the headphone jack: %s mm" % (a * 1000.0))
		_check((to_sys.basis * attach.global_basis * Vector3.FORWARD).z > 0.9, "and the lead leaves down the bottom edge")

	# --- controls ------------------------------------------------------------------
	var sw := model.get_node("PowerSwitch") as VRSlider
	var cap := console.find_child("PowerSwitch", true, false) as Node3D
	var cap_off := cap.position
	sw.set_value(1.0)
	await _wait(2)
	var moved := cap.position - cap_off
	_check(_near(moved, Vector3(0.952167, -0.305577, 0) * 0.004, 0.0001), "power switch slides 4 mm along its track: %s mm" % (moved * 1000.0))
	sw.set_value_no_signal(0.0)
	await _wait(2)
	var wheel := console.find_child("VolumeWheel", true, false) as Node3D
	var wheel_rest := wheel.transform
	var vol := model.get_node("VolumeSlider") as VRSlider
	vol.set_value_no_signal(0.0)
	await _wait(2)
	var turn := wheel_rest.basis.x.signed_angle_to(wheel.transform.basis.x, Vector3.BACK)
	_check(absf(turn + 0.012 / 0.0045) < 0.01, "volume to 0 rolls the wheel back 153 degrees: %.1f" % rad_to_deg(turn))
	_check(wheel.position.distance_to(wheel_rest.origin) < 1e-6, "about its own axle")
	vol.set_value_no_signal(1.0)
	await _wait(2)
	var led := console.find_child("PowerLED", true, false) as MeshInstance3D
	model.on_power_on()
	var lit := led.get_surface_override_material(0) as StandardMaterial3D
	_check(lit != null and lit.emission_enabled, "power LED lights with the machine")
	model.on_power_off()
	_check(led.get_surface_override_material(0) == null, "and goes dark with it")
	var a_btn := console.find_child("Button_A", true, false) as Node3D
	var shoulder := console.find_child("Shoulder_L", true, false) as Node3D
	var dpad := console.find_child("DPad", true, false) as Node3D
	var a_rest := a_btn.position
	var l_rest := shoulder.basis
	var d_rest := dpad.basis
	var held := (1 << ControllerBindings.JOYPAD_A) | (1 << ControllerBindings.JOYPAD_L) | (1 << ControllerBindings.JOYPAD_UP)
	for i in 40:
		model.animate_controls(held, Vector2.ZERO, Vector2.ZERO)
	_check(absf(a_btn.position.z - (a_rest.z - 0.0008)) < 0.00002, "A presses 0.8 mm into the shell")
	var tip := dpad.basis * Vector3(0, 0.009, 0) - d_rest * Vector3(0, 0.009, 0)
	_check(tip.z < -0.0005, "UP sinks the D-pad's top arm: %.2f mm" % (tip.z * 1000.0))
	var outer := shoulder.basis * Vector3(-0.025, 0, 0) - l_rest * Vector3(-0.025, 0, 0)
	_check(outer.y < -0.001, "L presses its outer end down: %.2f mm" % (outer.y * 1000.0))
	for i in 40:
		model.animate_controls(0, Vector2.ZERO, Vector2.ZERO)
	_check(a_btn.position.distance_to(a_rest) < 0.00002 and shoulder.basis.is_equal_approx(l_rest), "and everything comes back")

	# --- the desktop pointer finds the seated cart --------------------------------------
	# What shows of it: its top end, over the back wall, seen end on past the top
	# edge and from behind. Aiming at the screen or over the front top still takes
	# the console.
	await _physics(4)
	for spec: Array in [[Vector3(0, -0.02, -0.12), "from behind the top edge"],
			[Vector3(0, -0.12, -0.05), "from the back, over the back wall"],
			[Vector3(0.0, -0.005, -0.15), "end on"]]:
		var from: Vector3 = sys.global_transform * (Vector3(0, -0.00786, -0.037) + (spec[0] as Vector3))
		var aim: Vector3 = sys.global_transform * Vector3(0, -0.00786, -0.037)
		_check(_takes(from, aim, cart), "the desktop pointer takes the seated cart %s" % spec[1])
	_check(_takes(sys.global_transform * Vector3(0, 0.3, 0), sys.global_transform * Vector3(0, 0.01, -0.005), sys),
		"and the console when aimed at its screen")
	_check(_takes(sys.global_transform * Vector3(0, 0.3, -0.037), sys.global_transform * Vector3(0, 0.0, -0.037), sys),
		"and when aimed straight down at the top edge over the slot")

	if DisplayServer.get_name() != "headless":
		await _shots(sys, "")

	# --- a Game Boy cartridge, which a GBA takes too ------------------------------------
	# Out of the slot first: a snap zone dropping its object during teardown fills
	# the log with not-in-tree errors that are nothing to do with this.
	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	await _wait(5)
	cart.queue_free()
	await _wait(10)
	var gb := CART_SCENE.instantiate() as RetroCartridge
	gb.systemid = "gb"
	gb.game_label = "PROBE GB"
	gb.position = Vector3(0, 1.3, 0)
	add_child(gb)
	gb.add_to_group("spawned")
	await _wait(20)
	sys.restore_cartridge(gb)
	await _wait(40)
	var gb_size := MediaDimensions.cart_size("gb")
	var gb_top := to_sys * (gb.global_transform * Vector3(0, gb_size.y * 0.5, 0))
	var gb_mid := to_sys * gb.global_position
	# The GBA's top edge is z = -41.0 mm in this frame; the user measured 30 mm
	# of a Game Boy cart standing out above it.
	print("[gba] gb cart top %.2f mm past the top edge, middle at y %.2f mm" % [(-0.041 - gb_top.z) * 1000.0, gb_mid.y * 1000.0])
	_check(absf((-0.041 - gb_top.z) - 0.030) < 0.001, "a Game Boy cart stands 30 mm out of the top edge")
	_check(absf(gb_mid.y - (-0.006988)) < 0.0001, "centred in the 7.8 mm slot, 0.15 mm clear of each wall")
	_check(absf(gb_mid.x) < 0.0001, "and across it")
	var gb_body := gb.get_node_or_null("CartModel") as Node3D
	if gb_body != null:
		var gr: Transform3D = console.global_transform.affine_inverse() * gb_body.global_transform
		var gf := FileAccess.open(OUT_DIR.path_join("gb_cart_in_console.json"), FileAccess.WRITE)
		gf.store_string(JSON.stringify({"basis_x": _v(gr.basis.x), "basis_y": _v(gr.basis.y), "basis_z": _v(gr.basis.z),
			"origin": _v(gr.origin)}))
		gf.close()
	await _physics(4)
	_check(_takes(sys.global_transform * Vector3(0, 0.25, -0.058), sys.global_transform * Vector3(0, 0, -0.058), gb),
		"the desktop pointer takes it from above, over its middle")
	if DisplayServer.get_name() != "headless":
		await _shots(sys, "gb_")
	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	await _wait(5)
	gb.queue_free()
	await _wait(10)

	# --- the e-Reader, whose tongue takes the same slot -------------------------------
	var unit := preload("res://Scenes/Objects/expansion.tscn").instantiate() as RetroExpansion
	unit.expansion_id = "ereader"
	unit.position = Vector3(0, 1.3, 0)
	add_child(unit)
	unit.add_to_group("spawned")
	await _wait(30)
	sys.restore_expansion(unit)
	await _wait(40)
	var seat := model.get_node("CartSeat") as Node3D
	var connector: Vector3 = to_sys * (unit.global_transform * (ExpansionCatalog.connector_of("ereader") as Vector3))
	_check(_near(connector, to_sys * seat.global_position, 0.0005), "the e-Reader's connector point sits on the cart seat")
	var reader_shell: Node3D = null
	for n: Node in unit.find_children("*", "Node3D", true, false):
		if (n as Node3D).scene_file_path.ends_with("ereader.glb"):
			reader_shell = n
	if reader_shell != null:
		var r: Transform3D = console.global_transform.affine_inverse() * reader_shell.global_transform
		var g := FileAccess.open(OUT_DIR.path_join("ereader_in_console.json"), FileAccess.WRITE)
		g.store_string(JSON.stringify({"basis_x": _v(r.basis.x), "basis_y": _v(r.basis.y), "basis_z": _v(r.basis.z),
			"origin": _v(r.origin)}))
		g.close()
	if DisplayServer.get_name() != "headless":
		await _shots(sys, "ereader_")
	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	await _wait(5)
	unit.queue_free()
	sys.queue_free()
	await _wait(3)
	print("[gba] %s" % ("ALL CHECKS PASSED" if not _fail else "FAILED"))
	get_tree().quit(1 if _fail else 0)


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


var _grabber: Node3D = null


## True when the desktop pointer, aimed from `from` through `to`, acts on `want`
## — the same resolver the reticle uses. Says what it got instead when not.
func _takes(from: Vector3, to: Vector3, want: Node) -> bool:
	if _grabber == null:
		_grabber = Node3D.new()
		_grabber.add_to_group("desktop_hand")
		add_child(_grabber)
	var t := InteractionResolver.resolve_desktop(get_world_3d().direct_space_state,
		from, to + (to - from).normalized() * 0.2, _grabber)
	if not t.is_valid():
		print("[gba]   the pointer found nothing")
		return false
	for node: Node in [t.action_node, t.hit_node]:
		var n := node
		while n != null:
			if n == want:
				return true
			n = n.get_parent()
	print("[gba]   the pointer found %s" % (t.action_node.name if is_instance_valid(t.action_node) else "?"))
	return false


func _near(a: Vector3, b: Vector3, tol: float = 0.001) -> bool:
	return a.distance_to(b) < tol


func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# --- windowed: pictures of the seated cart -----------------------------------------

var _cam: Camera3D = null


func _shots(sys: Node3D, tag: String) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		add_child(_cam)
	_cam.near = 0.005
	_cam.far = 5.0
	_cam.fov = 28.0
	_cam.make_current()
	get_viewport().size = SHOT
	var c := sys.global_position
	var slot := c + Vector3(0, 0, -0.04)
	# Over the slot from behind, straight at the top edge, side on through the
	# slot, and the whole machine from the front.
	for spec: Array in [[slot + Vector3(0.05, 0.09, -0.12), slot, "slot_behind"],
			[slot + Vector3(0.0, 0.0, -0.22), slot, "top_edge"],
			[slot + Vector3(-0.22, 0.01, 0.0), slot, "side"],
			[c + Vector3(-0.10, 0.26, 0.22), c, "front"]]:
		_cam.global_position = spec[0]
		_cam.look_at(spec[1], Vector3.UP)
		await _wait(8)
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT_DIR.path_join("%02d_%s%s.png" % [_shot, tag, spec[2]]))
		_shot += 1


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.12)
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
