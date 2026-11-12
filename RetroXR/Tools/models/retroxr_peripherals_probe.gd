## RETRO XR peripherals probe -- the pad, light gun, keyboard and mouse as the game spawns them, filmed.
##
##   godot --path RetroXR --resolution 320x240 --position 20,20 res://Tools/models/retroxr_peripherals_probe.tscn
##
## Instantiates the real scenes (retro_controller, light_gun, retro_keyboard, retro_mouse), the pad and the gun in
## each colourway (model_variant, as the spawn menu sets it), and checks what can fail: every pad and gun control
## wears the model's mesh, a colourway really repaints the shell, every keyboard key wears a modelled cap, a key
## pressed through the pointer path sinks in the TILTED deck, and the gun's caps travel and its trigger swings.
## Stills and frames go to res://probe_out/peripherals/. Windowed, never --headless.
extends Node

const PAD := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const GUN := preload("res://Scenes/Objects/peripherals/light_gun.tscn")
const KEYBOARD := preload("res://Scenes/Objects/peripherals/retro_keyboard.tscn")
const MOUSE := preload("res://Scenes/Objects/peripherals/retro_mouse.tscn")
const OUT := "res://probe_out/peripherals"
const VARIANTS := ["charcoal", "cream", "red"]

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[periph] TIMEOUT"); get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 800)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.62)
	e.ambient_light_energy = 0.8
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var desk := CSGBox3D.new()
	desk.size = Vector3(3, 0.02, 3)
	desk.position = Vector3(0, -0.01, 0)
	desk.material = StandardMaterial3D.new()
	(desk.material as StandardMaterial3D).albedo_color = Color(0.36, 0.3, 0.24)
	_world.add_child(desk)
	_cam = Camera3D.new()
	_cam.fov = 35
	_world.add_child(_cam)
	_cam.current = true
	await _run()
	print("[periph] RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _ok(cond: bool, what: String, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("[periph] %s  %s%s" % ["ok  " if cond else "FAIL", what, ("  -- " + detail) if detail != "" else ""])


func _place(scene: PackedScene, at: Vector3, rot_deg: Vector3, variant: String = "") -> Node3D:
	var n := scene.instantiate() as Node3D
	if not variant.is_empty():
		n.set("model_variant", variant)
	(n as RigidBody3D).freeze = true
	n.position = at
	n.rotation_degrees = rot_deg
	_world.add_child(n)
	return n


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _still(file: String, from: Vector3, to: Vector3) -> void:
	_cam.look_at_from_position(from, to)
	for i in 3:
		await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("%s/%s.png" % [OUT, file])


func _shell_colour(n: Node, path: String, surface: int) -> Color:
	var mi := n.get_node_or_null(path) as MeshInstance3D
	if mi == null:
		return Color.BLACK
	var m := mi.get_surface_override_material(surface)
	if m == null:
		m = mi.mesh.surface_get_material(surface)
	return (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.BLACK


func _run() -> void:
	var pads: Array[Node3D] = []
	var guns: Array[Node3D] = []
	for i in 3:
		pads.append(_place(PAD, Vector3(-0.42 + i * 0.17, 0.02, 0.18), Vector3.ZERO, VARIANTS[i]))
		# Each gun on its left side, muzzle to the left, as one lies on a desk.
		guns.append(_place(GUN, Vector3(-0.40 + i * 0.25, 0.017, -0.12), Vector3(0, 90, -90), VARIANTS[i]))
	var kb := _place(KEYBOARD, Vector3(0.36, 0.0, 0.10), Vector3.ZERO)
	var mouse := _place(MOUSE, Vector3(0.68, 0.0, 0.12), Vector3.ZERO)
	await _settle(30)

	# --- what can fail ----------------------------------------------------------------------------------------
	for path in ["Model/Shell", "Model/DPad", "Model/FaceA", "Model/TriggerL", "Model/StickL/Cap"]:
		var mi := pads[0].get_node(path) as MeshInstance3D
		_ok(mi.mesh is ArrayMesh, "pad: %s wears the model's mesh" % path)
	var tops := [_shell_colour(pads[0], "Model/Shell", 0), _shell_colour(pads[1], "Model/Shell", 0),
		_shell_colour(pads[2], "Model/Shell", 0)]
	_ok(tops[0] != tops[1] and tops[1] != tops[2], "pad: the three colourways paint three tops", str(tops))
	_ok(tops[1].is_equal_approx(Color8(226, 218, 200)), "pad: cream is cream", str(tops[1]))
	for path in ["Shell/Body", "AuxAButton", "SelectButton", "AuxCButton", "ReloadButton", "DPad", "TriggerPivot/Trigger"]:
		var mi := guns[0].get_node_or_null(path) as MeshInstance3D
		_ok(mi != null and mi.mesh is ArrayMesh, "gun: %s wears the model's mesh" % path)
	var slide := [_shell_colour(guns[0], "Shell/Body", 0), _shell_colour(guns[2], "Shell/Body", 0)]
	_ok(not slide[0].is_equal_approx(slide[1]), "gun: charcoal and red slides differ", str(slide))
	var tip := guns[0].get_node("Shell/Bushing") as MeshInstance3D
	var tip_col := (tip.mesh.surface_get_material(0) as BaseMaterial3D).albedo_color
	_ok(tip_col.r > 0.8 and tip_col.g < 0.6 and tip_col.b < 0.3, "gun: the muzzle is orange", str(tip_col))
	var keys: Array = kb.get("_keys")
	var modelled := 0
	for k: Dictionary in keys:
		if (k["mesh"] as MeshInstance3D).mesh is ArrayMesh:
			modelled += 1
	_ok(keys.size() == 104 and modelled == 104, "keyboard: all 104 keys wear modelled caps", "%d/%d" % [modelled, keys.size()])
	# A cap material named "..._Alpha" imports transparent (Godot's name hint), does not write depth, and paints
	# over its own legend from some angles: every cap must be opaque.
	var see_through := 0
	for k: Dictionary in keys:
		var m := ((k["mesh"] as MeshInstance3D).mesh as Mesh).surface_get_material(0) as BaseMaterial3D
		if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			see_through += 1
	_ok(see_through == 0, "keyboard: every cap is opaque under its legend", "%d transparent" % see_through)
	var keys_root := kb.get_node("Keys") as Node3D
	_ok(absf(keys_root.rotation_degrees.x - 4.0) < 0.1, "keyboard: the deck is tilted 4 degrees",
		"%.2f" % keys_root.rotation_degrees.x)
	_ok((mouse.get_node("MouseVisual/BodyMesh") as MeshInstance3D).mesh is ArrayMesh, "mouse: the body is the model's")

	# --- stills -------------------------------------------------------------------------------------------------
	await _still("overview", Vector3(0.12, 0.62, 0.95), Vector3(0.12, 0.0, 0.03))
	await _still("pads", Vector3(-0.25, 0.30, 0.52), Vector3(-0.25, 0.0, 0.17))
	await _still("guns", Vector3(-0.15, 0.36, 0.30), Vector3(-0.15, 0.03, -0.12))
	await _still("keyboard", Vector3(0.36, 0.30, 0.48), Vector3(0.36, 0.0, 0.08))
	await _still("keyboard_close", Vector3(0.24, 0.13, 0.25), Vector3(0.26, 0.01, 0.07))
	await _still("keyboard_top", Vector3(0.26, 0.20, 0.035), Vector3(0.26, 0.0, 0.034))
	await _still("mouse", Vector3(0.74, 0.14, 0.30), Vector3(0.68, 0.01, 0.12))
	await _still("pad_back", Vector3(-0.42, 0.10, -0.12), Vector3(-0.42, 0.0, 0.18))

	# --- the keyboard: a key pressed by the pointer sinks, in the tilted deck ---------------------------------
	var a_key := -1
	for i in keys.size():
		if int(keys[i]["keycode"]) == "a".unicode_at(0):
			a_key = i
	var a_mesh := keys[a_key]["mesh"] as MeshInstance3D
	var rest_y := a_mesh.position.y
	var at := keys_root.to_global(a_mesh.position)
	_ok(kb.call("has_key_at", at), "keyboard: the pointer finds the A cap where it is drawn")
	kb.call("pointer_press_at", at)
	await _settle(2)
	_ok(a_mesh.position.y < rest_y - 0.001, "keyboard: pressed, the A cap sinks", "%.1f mm" % ((rest_y - a_mesh.position.y) * 1000))
	await _still("keyboard_press", Vector3(0.24, 0.13, 0.25), Vector3(0.26, 0.01, 0.07))
	kb.call("pointer_release")
	await _still("keyboard_leds_off", Vector3(0.50, 0.12, 0.10), Vector3(0.55, 0.015, 0.05))
	var scroll := kb.find_child("LedScroll", true, false) as MeshInstance3D
	var off_mat := scroll.get_surface_override_material(0) as BaseMaterial3D
	_ok(off_mat != null and not off_mat.emission_enabled, "keyboard: the lock lights start dark")
	kb.call("_light_scroll_lock", true)
	var on_mat := scroll.get_surface_override_material(0) as BaseMaterial3D
	_ok(on_mat != null and on_mat.emission_enabled, "keyboard: capture lights Scroll Lock")
	await _still("keyboard_scroll_lock", Vector3(0.50, 0.12, 0.10), Vector3(0.55, 0.015, 0.05))

	# --- the gun: every cap travels, the trigger swings ---------------------------------------------------------
	var g := guns[0]
	# The gun animates from its own input every frame (all released here): hold that off while the probe drives it.
	g.set_process(false)
	g.set_physics_process(false)
	var reload := g.get_node("ReloadButton") as MeshInstance3D
	var reload_rest := reload.position
	var trig := g.get_node("TriggerPivot") as Node3D
	var down := {ControllerBindings.LIGHTGUN_TRIGGER: true, ControllerBindings.LIGHTGUN_RELOAD: true,
		ControllerBindings.LIGHTGUN_AUX_A: true, ControllerBindings.LIGHTGUN_SELECT: true}
	for i in 20:
		g.call("_animate_controls", down)
		await get_tree().process_frame
	_ok(reload.position.y > reload_rest.y + 0.0007, "gun: RELOAD goes up into the grip",
		"%.2f mm" % ((reload.position.y - reload_rest.y) * 1000))
	_ok(absf(rad_to_deg(trig.rotation.x) + 6.0) < 0.5, "gun: the trigger swings 6 degrees back",
		"%.1f deg" % rad_to_deg(trig.rotation.x))
	await _still("gun_pulled", Vector3(-0.40, 0.20, 0.06), Vector3(-0.40, 0.03, -0.12))
	for i in 20:
		g.call("_animate_controls", {})
		await get_tree().process_frame
	await _still("gun_rest", Vector3(-0.40, 0.20, 0.06), Vector3(-0.40, 0.03, -0.12))
