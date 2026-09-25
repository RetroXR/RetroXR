## Dreamcast model probe — the shell's moving parts and connectors, spawned for real.
##
##   godot --headless --path RetroXR res://Tools/models/dreamcast_probe.tscn
##   godot --path RetroXR --rendering-driver opengl3 res://Tools/models/dreamcast_probe.tscn
##
## Headless it checks: the model and its baked shell; RESET hidden (the machine has
## none); POWER / OPEN adopted by the cabinet's buttons; POWER's latch and the orange
## lens; OPEN releasing the spring lid to its 70 degrees and a second press leaving it
## up; the disc seat on the platter; four controller zones on the shell's
## ControllerPort markers, level and evenly spaced; and AV OUT on its marker.
##
## With a renderer it also seats four pads' plugs and the Dreamcast AV lead, opens the
## lid, powers the lens and writes user://dreamcast_probe_{front,rear,iso}.png — the
## pictures that show a seated plug lines up, which no number here can.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const DC_AV_CABLE := preload("res://Scenes/Objects/system_models/dreamcast/dc_av_cable.tscn")

var _failures: Array[String] = []


func _ok(cond: bool, msg: String) -> void:
	print("[dc] %s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		_failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	var sys := SYSTEM_SCENE.instantiate() as RigidBody3D
	sys.set("systemid", "dreamcast")
	sys.set("model_id", "dreamcast")
	sys.freeze = true
	add_child(sys)
	await _frames(30)

	var model := sys.get("_model") as RetroSystemModel
	_ok(model is RetroSystemModelDreamcast, "the dreamcast row builds RetroSystemModelDreamcast")
	if not (model is RetroSystemModelDreamcast):
		_finish()
		return
	_ok(model.has_baked_shell(), "and wears the GLB shell")

	# Buttons.
	var reset := sys.get_node("ResetButton") as VRButton
	_ok(not reset.visible, "RESET is hidden: a Dreamcast has none")
	for pair in [["PowerButton", "PowerButton"], ["EjectButton", "OpenButton"]]:
		var btn := sys.get_node(pair[0]) as VRButton
		var cap := model.find_child(pair[1], true, false) as MeshInstance3D
		_ok(cap != null, "%s cap is in the shell" % pair[1])
		if btn != null and cap != null:
			var c: Vector3 = cap.global_transform * cap.get_aabb().get_center()
			_ok(btn.global_position.distance_to(c) < 1e-4, "%s widget sits on the %s cap" % [pair[0], pair[1]])

	# The desktop pointer reaches both caps, lid shut.
	await _pointer_reaches_caps(sys, "lid shut")

	# Power latch and lens.
	var led := model.find_child("PowerLED", true, false) as MeshInstance3D
	model.on_power_on()
	var lit := led != null and (led.get_surface_override_material(0) as StandardMaterial3D).emission_energy_multiplier > 0.0
	_ok(lit, "power on lights the orange lens")
	model.on_power_off()
	var dark := led != null and (led.get_surface_override_material(0) as StandardMaterial3D).emission_energy_multiplier == 0.0
	_ok(dark, "power off puts it out")

	# Lid: OPEN is a latch release; a second press does not shut it.
	_ok(model.has_spring_latched_lid(), "the lid is spring latched")
	_ok(not model.is_lid_open(), "the lid spawns shut")
	sys.call("_on_eject_pressed")
	# Time, not frames: headless frames are uncapped and the open tween is 0.38 s.
	await get_tree().create_timer(0.6).timeout
	_ok(model.is_lid_open() and absf(model.get_lid_angle_deg() - 70.0) < 0.5,
		"OPEN pops the lid to 70 degrees (%.1f)" % model.get_lid_angle_deg())
	sys.call("_on_eject_pressed")
	await get_tree().create_timer(0.6).timeout
	_ok(model.is_lid_open(), "a second OPEN leaves it up: it is closed by hand")
	await _pointer_reaches_caps(sys, "lid open")

	# Disc seat on the platter, gated on the lid.
	var slot := sys.get_node("CartridgeSlot") as XRToolsSnapZone
	var plate := model.find_child("SpindlePlate", true, false) as MeshInstance3D
	if plate != null:
		var top: float = (plate.global_transform * plate.get_aabb()).end.y
		_ok(absf(slot.global_position.y - top) < 1e-4 and
			Vector2(slot.global_position.x - plate.global_position.x,
				slot.global_position.z - plate.global_position.z).length() < 1e-4,
			"the disc seat is the platter's top, on its axis")
	_ok(slot.enabled, "and takes a disc with the lid up")

	# Controller ports.
	var xs: Array[float] = []
	var ys: Array[float] = []
	for i in range(1, 5):
		var zone := sys.get_node("ControllerPort%d" % i) as Node3D
		var mouth := model.find_child("ControllerPort%d" % i, true, false) as Node3D
		_ok(zone.visible, "port %d is live" % i)
		if mouth != null:
			_ok(zone.global_position.distance_to(mouth.global_position) < 1e-4,
				"port %d zone sits on its socket mouth" % i)
		xs.append(sys.to_local(zone.global_position).x)
		ys.append(sys.to_local(zone.global_position).y)
	var pitch := [xs[1] - xs[0], xs[2] - xs[1], xs[3] - xs[2]]
	_ok(absf(pitch.max() - pitch.min()) < 1e-5, "ports are evenly spaced (%.3f mm)" % (pitch[0] * 1000.0))
	_ok(absf(ys.max() - ys.min()) < 1e-6, "ports are level")
	_ok(absf(xs[0] + xs[3]) < 1e-4, "ports are centred on the console")

	# AV OUT.
	var av := sys.find_child("AvMultiOut", true, false) as Node3D
	var av_mouth := model.find_child("AvOut", true, false) as Node3D
	_ok(av is DcAvPort and av_mouth != null and av.global_position.distance_to(av_mouth.global_position) < 1e-4,
		"AV OUT is a DcAvPort on the tunnel mouth")

	if DisplayServer.get_name() != "headless":
		await _render(sys, model, av as XRToolsSnapZone)
	_finish()


func _render(sys: Node3D, model: RetroSystemModel, av: XRToolsSnapZone) -> void:
	model.on_power_on()
	for i in range(1, 5):
		var pad := PAD_SCENE.instantiate() as Node3D
		pad.set("systemid", "dreamcast")
		# Behind every camera below, so a pad never stands in the shot.
		pad.position = Vector3(-0.375 + i * 0.15, 0.0, 1.2)
		add_child(pad)
	await _frames(20)
	var plugs: Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n is ControllerPlug:
			plugs.append(n)
	for i in mini(4, plugs.size()):
		var zone := sys.get_node("ControllerPort%d" % (i + 1)) as XRToolsSnapZone
		zone.enabled = true
		zone.pick_up_object(plugs[i])
	var lead := DC_AV_CABLE.instantiate() as Node3D
	lead.position = Vector3(0, 0.2, -0.6)
	add_child(lead)
	await _frames(20)
	av.pick_up_object(lead.get_node("PlugA0"))
	await _frames(60)

	# The boot curtain is head-locked to whatever camera is current, so it would
	# fill every shot; famicom_render_probe clears it the same way.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(30)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.005
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	add_child(env)
	var c := sys.global_position + Vector3(0, 0.04, 0)
	for shot in [["front", Vector3(0.0, 0.08, 0.32), c + Vector3(0, -0.01, 0.08)],
			["rear", Vector3(-0.08, 0.05, -0.22), c + Vector3(-0.03, -0.02, -0.09)],
			["iso", Vector3(0.28, 0.3, 0.4), c]]:
		cam.global_position = c + shot[1]
		cam.look_at(shot[2])
		await _frames(4)
		await RenderingServer.frame_post_draw
		var path := "user://dreamcast_probe_%s.png" % shot[0]
		get_viewport().get_texture().get_image().save_png(path)
		print("[dc] wrote ", ProjectSettings.globalize_path(path))


## Aim the desktop pointer's own resolver at each cap — its centre and both edges,
## from the front-above angle a seated player looks from and from straight above —
## and ask what a click there would operate. The console's collision box and the
## lid's grab box both surround the caps, and either one winning is a dead button.
func _pointer_reaches_caps(sys: Node3D, when: String) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var hand := Node3D.new()
	add_child(hand)
	var up := sys.global_transform.basis.y.normalized()
	var front := sys.global_transform.basis.z.normalized()
	var right := sys.global_transform.basis.x.normalized()
	for name in ["PowerButton", "EjectButton"]:
		var btn := sys.get_node(name) as VRButton
		var cap := btn.get("_mesh") as MeshInstance3D
		if cap == null:
			_ok(false, "%s has adopted its cap" % name)
			continue
		var ab: AABB = cap.global_transform * cap.get_aabb()
		var top := Vector3(ab.get_center().x, ab.end.y, ab.get_center().z)
		var bad: Array[String] = []
		for dx: float in [-0.35, 0.0, 0.35]:
			var aim := top + right * ab.size.x * dx
			for dir: Vector3 in [(up + front).normalized(), up]:
				var t := InteractionResolver.resolve_desktop(space, aim + dir * 0.4, aim - dir * 0.1, hand)
				if not (t.kind == InteractionTarget.KIND_BUTTON and t.action_node == btn):
					bad.append("%+.2f %s -> %s" % [dx, "above" if dir == up else "front", t.action_node.name if t.action_node else t.kind])
		_ok(bad.is_empty(), "the pointer clicks %s (%s)%s" % [name, when, "" if bad.is_empty() else ": " + ", ".join(bad)])
	# And the lid stays reachable among the stepped shell boxes. Latched shut its grab
	# box is off (OPEN releases it, as on the PlayStation), so only once it is up does
	# an aim at its free front half take the lid — which is how it gets closed.
	var hinge := sys.find_child("LidHinge", true, false) as Node3D
	if hinge != null and (sys.get("_model") as RetroSystemModel).is_lid_open():
		var at := hinge.global_position
		var t := InteractionResolver.resolve_desktop(space, at + up * 0.4, at - up * 0.1, hand)
		_ok(t.action_node == hinge, "the pointer takes the open lid to close it (%s)" % t.action_node)
	hand.queue_free()


func _finish() -> void:
	print("[dc] %s (%d failed)" % ["ALL CHECKS PASSED" if _failures.is_empty() else "FAILURES", _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)
