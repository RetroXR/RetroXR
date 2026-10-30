extends Node3D
## The RETRO XR television in the game (tv.tscn wearing tv_model "retroxr_crt"): checks that every socket sits on
## the model's mouth, the tube on ScreenSeat, the twelve keys on the model's, the door gating its five keys, the
## lamp following the power and a resized set carrying the model and sockets with it; then renders the set on
## (front, door open), its back with a lead in AV1 and two speaker leads, and the set resized larger.
## Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/av/tv_model_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera: the desktop loading screen is a CanvasLayer over the main view.

const TV := preload("res://Scenes/Objects/tv.tscn")
const COMPOSITE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const LEAD := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")

const SOCKETS := [
	"CompositePort", "AudioLIn", "AudioRIn", "CompositePort2", "AudioLIn2", "AudioRIn2",
	"CompositePort3", "AudioLIn3", "AudioRIn3", "CompositePort4", "AudioLIn4", "AudioRIn4",
	"RfPort", "VgaPort", "SpeakerOutL", "SpeakerOutR", "SpeakerOutC", "SpeakerOutLfe", "SpeakerOutSl",
	"SpeakerOutSr",
]

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://tv_model_probe"
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): print("[tvprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.57)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-35, 160, 0)
	back.light_energy = 1.2
	add_child(back)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	floor.position.y = -0.165
	add_child(floor)

	var tv := TV.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	add_child(tv)
	tv.freeze = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 40
	_vp.add_child(_cam)
	await _frames(8)

	var shell := tv.get_node_or_null("RetroXRCrt") as RetroXRCrtShell
	_check(shell != null, "the set wears the RETRO XR cabinet")
	if shell == null:
		get_tree().quit(1)
		return
	var model := shell.model()
	_check(model.levels.size() == 3, "three levels")
	for s in SOCKETS:
		var port := tv.get_node_or_null(s) as Node3D
		var mouth := model.part(s + "Mouth")
		var ok := port != null and mouth != null \
			and port.global_position.distance_to(mouth.global_position) < 0.001 \
			and port.global_basis.z.normalized().dot(mouth.global_basis.z.normalized()) > 0.99
		_check(ok, "%s on the model's mouth, +Z out of the back" % s,
			"%s vs %s" % [port.global_position if port else null, mouth.global_position if mouth else null])
	var seat := model.part("ScreenSeat")
	_check(tv.screen_mesh().global_position.distance_to(seat.global_position) < 0.001, "the tube on ScreenSeat")
	_check(not (model.part("Screen") as Node3D).visible, "the model's own Screen hidden")
	for b: String in RetroXRCrtShell.KEYS:
		var btn := tv.get_node(b) as Node3D
		var key := model.part(RetroXRCrtShell.KEYS[b])
		_check(btn.global_position.distance_to(key.global_position) < 0.0005 and not key.visible,
			"%s on the model's %s" % [b, RetroXRCrtShell.KEYS[b]])
	_check((tv.get_node("CRTButton") as Area3D).collision_layer == 0, "door shut: CRT key dead")
	shell.set_door_open(true)
	await _frames(2)
	_check((tv.get_node("CRTButton") as Area3D).collision_layer != 0, "door open: CRT key live")
	tv.set_power(true)
	await _frames(4)
	var led := model.part("PowerLed") as MeshInstance3D
	_check((led.material_override as StandardMaterial3D).emission_enabled, "power on: the lamp lit")

	_cam.look_at_from_position(Vector3(0.42, 0.20, 0.82), Vector3(0.0, -0.01, 0.0))
	await _shot("tv_on_door_open")
	shell.set_door_open(false)
	_cam.look_at_from_position(Vector3(0.0, 0.0, 0.95), Vector3(0.0, 0.0, 0.0))
	await _shot("tv_front_on")

	var av := COMPOSITE.instantiate() as Node3D
	add_child(av)
	await _frames(4)
	for k in 3:
		(tv.get_node(["CompositePort", "AudioLIn", "AudioRIn"][k]) as RcaPort).pick_up_object(av.get_node("PlugB%d" % k))
	for spec: Array in [["SpeakerOutL", Vector3(0.45, -0.1, -0.35)], ["SpeakerOutR", Vector3(-0.45, -0.1, -0.35)]]:
		var cab := SATELLITE.instantiate() as Node3D
		cab.position = spec[1]
		cab.rotation_degrees.y = 180
		add_child(cab)
		if cab is RigidBody3D:
			(cab as RigidBody3D).freeze = true
		await _frames(4)
		var lead := LEAD.instantiate() as Node3D
		add_child(lead)
		await _frames(4)
		(tv.get_node(spec[0]) as RcaPort).pick_up_object(lead.get_node("PlugA0"))
		(cab.get_node("SpeakerIn") as RcaPort).pick_up_object(lead.get_node("PlugB0"))
	await _frames(20)
	_check((tv.get_node("CompositePort") as RcaPort).picked_up_object != null, "a lead seated in AV1")
	_cam.look_at_from_position(Vector3(-0.55, 0.30, -0.95), Vector3(0.0, -0.05, -0.15))
	await _shot("tv_rear_leads")

	var before := (tv.get_node("CompositePort") as Node3D).global_position.distance_to(tv.global_position)
	tv.set_tv_scale(1.5)
	await _frames(8)
	var after := (tv.get_node("CompositePort") as Node3D).global_position.distance_to(tv.global_position)
	var mouth := model.part("CompositePortMouth")
	_check(absf(after / before - 1.5) < 0.02 and (tv.get_node("CompositePort") as Node3D).global_position.distance_to(
		mouth.global_position) < 0.0015, "resized 1.5x: model and sockets scale together", "%f -> %f" % [before, after])
	_cam.look_at_from_position(Vector3(0.65, 0.30, 1.25), Vector3(0.0, 0.05, 0.0))
	await _shot("tv_resized_1_5x")
	print("[tvprobe] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String, detail := "") -> void:
	if not ok:
		_fails += 1
	print("[tvprobe] %s %s %s" % ["PASS" if ok else "FAIL", what, detail if not ok else ""])


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(10)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[tvprobe] wrote ", path)
