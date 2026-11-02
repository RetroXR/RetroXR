## The 32X's A/V hookup: Sega's Video Link Cable from the Genesis's A/V OUT into the
## 32X's A/V IN, and the console's own A/V Cable from the 32X's A/V OUT to a set.
##
## Prints where the two sockets are, which way a seated plug stands, what the routing
## makes of it (which input of the set the Genesis is filed on), and how far each A/V
## plug's head clears the MK-2103 plug in the DC jack beside it (both adapters are
## plugged in, as on a real hookup), and writes stills of the back of the stack and of
## the 32X's panel close up.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/models/sega32x_av_probe.tscn -- --out=C:/path/to/stills [--nolink] [--primitive]
##
## --nolink leaves the Video Link Cable out: the control, in which the set must have
## no Genesis on it. --primitive puts the 32X on the box that stands in for a Genesis
## without its shell, which wears the same mini-DIN, drawn. Windowed, never --headless:
## the dummy renderer draws nothing.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const BRICK_SCENE := preload("res://Scenes/Objects/power/power_brick.tscn")
## The MK-2103's plug body (PowerBrickCatalog plug_mm) and the A/V plug's head
## (gen_genesis_av.gd HEAD_R), for the clearance between two seated side by side.
const DC_PLUG_R := 0.0049
const AV_HEAD_R := 0.00575

const STAGE := Vector3(0, 1.0, 0)

var out_dir := ""
var no_link := false
var primitive := false
var _cam: Camera3D
## What stays drawn: the hardware and the leads, not the panels they float.
var keep: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
		elif String(a) == "--nolink":
			no_link = true
		elif String(a) == "--primitive":
			primitive = true
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
	key.rotation_degrees = Vector3(-42, 150, 0)
	key.light_energy = 1.6
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -40, 0)
	fill.light_energy = 0.6
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.01
	add_child(_cam)
	# Something for the leads to hang onto.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.02, 4)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = STAGE - Vector3(0, 0.01, 0)
	add_child(floor_body)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String, from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _wait(3)
	await RenderingServer.frame_post_draw
	if out_dir.is_empty():
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, shot_name])
	print("[probe] wrote %s" % shot_name)


func _hide_panels() -> void:
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var wanted := false
		for k in keep:
			if is_instance_valid(k) and (k == n or k.is_ancestor_of(n)):
				wanted = true
				break
		if not wanted and not n is Light3D:
			(n as VisualInstance3D).visible = false


func _run() -> void:
	var host := SYSTEM_SCENE.instantiate() as RetroSystem
	host.systemid = "genesis"
	if primitive:
		host.model_id = SystemModelRegistry.PLACEHOLDER_ID
	host.freeze = true
	add_child(host)
	host.global_position = STAGE
	await _wait(30)
	var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
	unit.expansion_id = "sega_32x"
	unit.freeze = true
	add_child(unit)
	unit.global_position = STAGE + Vector3(0.0, 0.2, 0.5)
	await _wait(12)
	var spacer := ScenePersistence.instantiate("sega32x_spacer") as Sega32xSpacer
	spacer.freeze = true
	add_child(spacer)
	await _wait(6)
	unit.restore_accessory(spacer)
	host.restore_cartridge(unit)
	await _wait(12)
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.freeze = true
	add_child(tv)
	tv.global_position = STAGE + Vector3(0.9, 0.0, -0.6)
	await _wait(12)

	var multi := host.find_child("AvMultiOut", true, false) as RcaPort
	var a_in := unit.av_through_in()
	var a_out := unit.av_through_out()
	if multi == null or a_in == null or a_out == null:
		print("[probe] FAIL sockets missing: console %s, A/V IN %s, A/V OUT %s" % [multi, a_in, a_out])
		return
	for port: RcaPort in [a_in, a_out]:
		var local := unit.global_transform.affine_inverse() * port.global_transform
		print("[probe] %s at %s mm (unit), +Z %s, +Y %s" % [port.name, local.origin * 1000.0,
			local.basis.z, local.basis.y])
	var jack := multi.get_node_or_null("PanelJack") as Node3D
	print("[probe] the console's A/V OUT draws its own jack: %s (the box moulds none; a shell does)" % [
		jack != null and jack.visible])

	# Off a headset the loading screen is a flat CanvasLayer over everything; a console
	# spawning raises it.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	keep.append(host.get("_model"))
	if primitive:
		# The box draws through the console's own body mesh and its socket's jack.
		keep.append(host.get_node_or_null("SystemBody"))
		keep.append(multi)
	keep.append(unit.get_node_or_null("Shell"))
	keep.append(spacer)
	_hide_panels()
	# The empty sockets first, before a lead is in front of them.
	var out_at := multi.global_position
	await _shot("console_av_out_empty", out_at + Vector3(-0.03, 0.02, -0.09), out_at)
	var panel := a_in.global_position.lerp(a_out.global_position, 0.5)
	await _shot("panel_empty", panel + Vector3(-0.03, 0.03, -0.11), panel)

	# Both adapters in: the console's DC jack and the 32X's ADAPTOR, beside their A/V
	# sockets, so the stills show whether the plugs clear each other.
	var dc_plugs: Array[Node3D] = []
	for owner_node: Node in [host, unit]:
		var supply := PowerInput.of(owner_node)
		var dc_jack: DcPort = null
		if supply != null:
			for inlet: Node in supply.inlets():
				if inlet is DcPort:
					dc_jack = inlet as DcPort
		if dc_jack == null:
			print("[probe] %s has no DC jack" % owner_node.name)
			continue
		var brick := BRICK_SCENE.instantiate() as PowerBrick
		brick.brick_id = "sega_mk2103_adapter"
		brick.variant = "usa"
		add_child(brick)
		brick.global_position = STAGE + Vector3(-0.3, 0.05, -0.3)
		await _wait(6)
		dc_jack.pick_up_object(brick.dc_plug)
		dc_plugs.append(brick.dc_plug)
		keep.append(brick)

	var lead := ScenePersistence.instantiate("genesis_av_cable") as Node3D
	add_child(lead)
	lead.global_position = STAGE + Vector3(0.4, 0.05, -0.4)
	var link: Node3D = null
	if not no_link:
		link = ScenePersistence.instantiate("sega32x_video_link_cable") as Node3D
		add_child(link)
		link.global_position = STAGE + Vector3(0.0, 0.1, -0.25)
	await _wait(10)
	a_out.pick_up_object(lead.get_node("PlugA0") as RcaPlug)
	var ins := ["CompositePort4", "AudioLIn4", "AudioRIn4"]
	for c in 3:
		(tv.get_node(ins[c]) as RcaPort).pick_up_object(lead.get_node("PlugB%d" % c) as RcaPlug)
	if link != null:
		multi.pick_up_object(link.get_node("PlugA0") as RcaPlug)
		a_in.pick_up_object(link.get_node("PlugB0") as RcaPlug)
	# Let the leads settle into a hang.
	await _wait(150)

	var input := tv.input_for_device(host)
	print("[probe] console: %s" % ("the primitive box" if primitive else "the Genesis model"))
	print("[probe] leg=%s  the set files the Genesis on input %d (%s), console feeds %s" % [
		"nolink" if no_link else "link", input,
		tv.source_name(input) if input >= 0 else "none",
		host.connected_tv.name if host.connected_tv != null else "<none>"])
	if link != null:
		var plug := link.get_node("PlugB0") as Node3D
		var up := plug.global_transform.basis.y
		print("[probe] the Video Link Cable's plug in the 32X stands with +Y %s (upright = (0, 1, 0))" % up)
	# Each A/V plug's head against the DC plug nearest it, across the panel (the two
	# stand side by side, so the distance between their axes is what decides).
	var av_plugs: Array[Node3D] = [lead.get_node("PlugA0") as Node3D]
	if link != null:
		av_plugs.append(link.get_node("PlugA0") as Node3D)
		av_plugs.append(link.get_node("PlugB0") as Node3D)
	for av: Node3D in av_plugs:
		var best := INF
		for dc: Node3D in dc_plugs:
			var d := av.global_position - dc.global_position
			d -= av.global_basis.z * d.dot(av.global_basis.z)
			best = minf(best, d.length())
		if best < INF:
			print("[probe] %s/%s: %.1f mm from the nearest DC plug's axis, clearance %.2f mm" % [
				av.get_parent().name, av.name, best * 1000.0, (best - AV_HEAD_R - DC_PLUG_R) * 1000.0])

	keep.append(lead)
	if link != null:
		keep.append(link)
	_hide_panels()
	var back := STAGE + Vector3(0.0, 0.10, -0.06)
	await _shot("rear_three_quarter", STAGE + Vector3(-0.32, 0.30, -0.50), back)
	await _shot("rear_straight", STAGE + Vector3(0.0, 0.16, -0.55), back)
	# The console's A/V OUT with the Video Link Cable in it, beside the adapter's plug.
	await _shot("console_av_out", out_at + Vector3(-0.06, -0.015, -0.08), out_at)
	await _shot("console_av_out_behind", out_at + Vector3(-0.005, 0.03, -0.09), out_at + Vector3(-0.005, 0, 0))
	# The 32X's panel, close: both plugs in their sockets beside the ADAPTOR jack.
	await _shot("panel_close", panel + Vector3(-0.04, 0.05, -0.13), panel)
	await _shot("panel_side", panel + Vector3(0.12, 0.02, -0.08), panel)
