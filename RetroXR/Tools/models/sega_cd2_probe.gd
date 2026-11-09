## The Sega CD Model 2 stand-in: alone, its lid open, a Genesis Model 2 seated against
## its drive, and a Genesis Model 1 (the xenu.genesis1 mod's shell, mounted from the
## checkout's packed copy, never the player's mods folder) on it with the extension
## spacer clipped on and Sega's sound mixing cable from its PHONES into MIXING.
##
## Prints where each console's right side lands against the drive's wall, what the
## line out carries, and writes stills.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/models/sega_cd2_probe.tscn -- --out=C:/path/to/stills
##
## Windowed, never --headless: the dummy renderer draws nothing. Without the
## mod's pack (RetroXR/mods/xenu.genesis1.zip) the Model 1 legs are skipped and say so.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")
const GENESIS1_PACK := "res://mods/xenu.genesis1.zip"
const GENESIS1_MODEL := "xenu.genesis1:mk1601"

var out_dir := ""
var _cam: Camera3D
var keep: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	# The boot's loading overlay is a CanvasLayer over everything: off, as the other
	# model probes do.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
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
	key.shadow_enabled = true
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


func _shot(shot_name: String, from: Vector3, at: Vector3) -> void:
	_hide_panels()
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _wait(3)
	await RenderingServer.frame_post_draw
	if out_dir.is_empty():
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
	print("[probe] wrote %s" % shot_name)


## Only the hardware: the panels and hints floating beside things are hidden.
func _hide_panels() -> void:
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var wanted := false
		for k in keep:
			if is_instance_valid(k) and (k == n or k.is_ancestor_of(n)):
				wanted = true
				break
		if not wanted and not n is Light3D:
			(n as VisualInstance3D).visible = false


func _drive(at: Vector3) -> RetroExpansion:
	var cd := EXPANSION_SCENE.instantiate() as RetroExpansion
	cd.expansion_id = "sega_cd"
	cd.freeze = true
	add_child(cd)
	cd.global_position = at
	await _wait(12)
	keep.append(cd.get_node("Shell"))
	for n in ["EjectButton", "LineOutL", "LineOutR", "MixingIn", "PowerInlet"]:
		if cd.get_node_or_null(n) != null:
			keep.append(cd.get_node(n))
	return cd


func _genesis(model_id := "") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "genesis"
	sys.model_id = model_id
	sys.freeze = true
	add_child(sys)
	sys.global_position = Vector3(0, 3, 0)
	await _wait(40)
	keep.append(sys.get_model())
	for n in ["AvMultiOut", "PhonesOut"]:
		if sys.get_node_or_null(n) != null:
			keep.append(sys.get_node(n))
	return sys


## Where the console's right side is, in the drive's shell frame (mm).
func _report(label: String, cd: RetroExpansion, sys: RetroSystem) -> void:
	var shell := cd.get_node("Shell") as Node3D
	var box := sys.body_aabb()
	var right := shell.global_transform.affine_inverse() * (sys.global_transform * Vector3(box.end.x, box.position.y, box.get_center().z)) * 1000.0
	var origin := shell.global_transform.affine_inverse() * sys.global_position * 1000.0
	print("[probe] %s: %.1f wide, right side at %s mm, origin x %.1f; on it: %s; LINE OUT carries %s" % [
		label, box.size.x * 1000.0, right, origin.x, sys.expansion_ids(), ExpansionAudio.carrier(cd)])


## The xenu.genesis1 mod, mounted and registered the way ModManager does.
func _mount_genesis1() -> bool:
	if not FileAccess.file_exists(GENESIS1_PACK):
		print("[probe] no %s: the Model 1 legs are skipped" % GENESIS1_PACK)
		return false
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(GENESIS1_PACK), false):
		print("[probe] could not mount %s" % GENESIS1_PACK)
		return false
	ModUids.register("xenu.genesis1")
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://mods/xenu.genesis1/mod.json"))
	var manifest := ModManifest.parse(json as Dictionary)
	var script := load(manifest.entry) as GDScript
	var api := ModApi.new(manifest, ModHooks.new(get_tree()))
	(script.new() as RetroMod).register(api)
	print("[probe] xenu.genesis1 mounted")
	return true


func _run() -> void:
	# 1. The drive alone, then its lid open.
	var cd := await _drive(Vector3(0, 1, 0))
	var c := cd.global_position
	await _shot("drive", c + Vector3(0.30, 0.30, 0.55), c)
	# The OPEN plate in the gray nose, close, then held pressed.
	var knob := cd.get_node("Shell/EjectButton") as MeshInstance3D
	var kc := knob.global_transform * knob.get_aabb().get_center()
	await _shot("open_button", kc + Vector3(-0.06, 0.07, 0.14), kc)
	var open_btn := cd.get_node("EjectButton") as VRButton
	open_btn.set_latched_pressed(true)
	await _shot("open_button_pressed", kc + Vector3(-0.06, 0.07, 0.14), kc)
	open_btn.set_latched_pressed(false)
	# The ACCESS lamp, dark and lit through the same call the core's LED makes.
	var lamp := cd.get_node("Shell/AccessLed") as MeshInstance3D
	var lc := lamp.global_transform * lamp.get_aabb().get_center()
	await _shot("access_lamp_off", lc + Vector3(0.03, 0.05, 0.12), lc)
	cd.call("_set_led", true)
	await _shot("access_lamp_on", lc + Vector3(0.03, 0.05, 0.12), lc)
	await _shot("access_lamp_on_wide", c + Vector3(0.10, 0.18, 0.42), c + Vector3(0.05, 0.0, 0.05))
	cd.call("_set_led", false)
	var tray := cd.get("_tray") as MediaTray
	tray.set_open(true, false)
	await _shot("drive_lid_open", c + Vector3(0.25, 0.35, 0.40), c + Vector3(0.10, 0.03, 0))
	tray.set_open(false, false)
	await _shot("drive_back", c + Vector3(-0.20, 0.20, -0.50), c + Vector3(0, 0, -0.08))

	# 2. A Genesis Model 2 slid on against the drive's wall.
	var md := await _genesis()
	cd.get_socket().pick_up_object(md)
	await _wait(10)
	_report("Model 2", cd, md)
	await _shot("model2_seated", c + Vector3(0.20, 0.35, 0.60), c + Vector3(0, 0.03, 0))
	await _shot("model2_seated_front", c + Vector3(0.0, 0.10, 0.70), c + Vector3(0, 0.03, 0))
	cd.get_socket().forget_object(md)
	cd.get_socket().drop_object()
	md.queue_free()
	await _wait(5)

	# 3. A Genesis Model 1 on the spacer, the mixing cable from PHONES into MIXING.
	if not _mount_genesis1():
		return
	var spacer := ScenePersistence.instantiate("sega_cd2_spacer") as SegaCd2Spacer
	spacer.freeze = true
	add_child(spacer)
	spacer.global_position = c + Vector3(-0.35, 0, 0.3)
	await _wait(10)
	keep.append(spacer)
	cd.restore_accessory(spacer)
	await _wait(5)
	await _shot("spacer_on", c + Vector3(-0.35, 0.30, 0.45), c + Vector3(-0.12, 0.02, 0))
	var m1 := await _genesis(GENESIS1_MODEL)
	print("[probe] Model 1 has PHONES: %s" % (m1.get_node_or_null("PhonesOut") != null))
	cd.get_socket().pick_up_object(m1)
	await _wait(10)
	_report("Model 1, no mixing lead", cd, m1)
	var lead := ScenePersistence.instantiate("sega_cd_mixing_cable") as Node3D
	add_child(lead)
	lead.global_position = c + Vector3(-0.1, 0.2, 0.3)
	await _wait(20)
	keep.append(lead)
	var phones := m1.get_node_or_null("PhonesOut") as Port
	if phones != null:
		phones.pick_up_object(lead.get_node("PlugA0") as RcaPlug)
		(cd.get_node("MixingIn") as Port).pick_up_object(lead.get_node("PlugB0") as RcaPlug)
		await _wait(90)
	_report("Model 1, mixing lead in", cd, m1)
	await _shot("model1_on_spacer", c + Vector3(-0.15, 0.40, 0.65), c + Vector3(-0.06, 0.03, 0))
	await _shot("model1_left_end", c + Vector3(-0.55, 0.20, 0.30), c + Vector3(-0.18, 0.03, 0))
	await _shot("model1_back_mixing", c + Vector3(-0.25, 0.35, -0.55), c + Vector3(-0.05, 0.02, -0.05))
