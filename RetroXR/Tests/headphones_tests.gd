## The RETRO XR headphones (Headphones): a headset on a captive cord to a 3.5 mm plug, for any headphone jack.
##
##   godot --headless --path RetroXR res://Tests/headphones_tests.tscn
##   godot --headless --path RetroXR res://Tests/headphones_tests.tscn -- --only=jack
##
## Groups:
##   scene/  the captive end is in the headset's own jack for good and nothing can take it; the plug is the model's,
##           its box what it draws
##   jack/   the plug fits a headphone jack and no other socket; seated in a handheld's, the jack's lead reaches the
##           headphones as a sink, the handheld's own speaker is cut, left plays at the left cup and right at the
##           right; pulled, the handheld plays from its own body again and the headphones carry nothing
##   tv/     in a set's jack: the set's sound plays at the cups, at the headphones' level and distance law
##   sound/  the host's two voices (a stand-in for Meta XR Audio, which reports unavailable headless) go to the cups,
##           L and R, at LEVEL near the head and LEVEL x 0.12 a metre off; dry: the game sets no room on the SDK
##   wear/   put on, the headset rides the camera with its ears on the head's; a hand taking it takes it off; the
##           menu does both, and sizes the band
##   save/   worn and the band's size come back from a save
##   ray/    the desktop ray takes the headset and the plug where they are drawn
##
## How it SOUNDS in a headset is a windowed check with Meta XR Audio enabled (Tools/av/headphones_probe).
extends "res://Tests/test_suite.gd"

const HEADPHONES := preload("res://Scenes/Objects/appliances/headphones.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const RCA_CABLE := preload("res://Scenes/Objects/cables/composite_cable.tscn")

var _only := ""
var _spawned: Array[Node] = []
var _grabber: Node3D
var _cam: Camera3D


## Stands in for the MetaXRAudio singleton: records where each voice was put and at what gain.
class FakeMx:
	extends RefCounted
	var pos := {}
	var gain := {}

	func set_voice_position(id: int, p: Vector3) -> void:
		pos[id] = p

	func set_voice_pose(id: int, p: Vector3, _f: Vector3, _u: Vector3) -> void:
		pos[id] = p

	func set_voice_gain(id: int, g: float) -> void:
		gain[id] = g

	func set_voice_directivity(_id: int, _k: float) -> void:
		pass


func _ready() -> void:
	suite_tag = "headphones"
	get_tree().create_timer(200.0).timeout.connect(func() -> void:
		print("[headphones] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.split("=")[1]
	_grabber = Node3D.new()
	add_child(_grabber)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.6, 2.0)
	add_child(_cam)
	_cam.current = true
	for c: Array in [["scene", _t_scene], ["jack", _t_jack], ["tv", _t_tv], ["sound", _t_sound], ["wear", _t_wear],
			["save", _t_save], ["ray", _t_ray]]:
		if not _only.is_empty() and not String(c[0]).begins_with(_only):
			continue
		await (c[1] as Callable).call()
		await _clear()
	_finish()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			if n.has_method("drop_and_free"):
				n.call("drop_and_free")
			else:
				n.queue_free()
	_spawned.clear()
	await _wait(3)


func _headphones(at: Vector3 = Vector3(0, 1, 0)) -> Headphones:
	var hp := HEADPHONES.instantiate() as Headphones
	add_child(hp)
	_spawned.append(hp)
	hp.global_position = at
	(hp.get_node("Body") as RigidBody3D).freeze = true
	return hp


func _handheld(systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.freeze = true
	sys.position = Vector3(_spawned.size() * 3.0 + 2.0, 1, 0)
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	return sys


func _plug(hp: Headphones) -> RcaPlug:
	return hp.get_node("PlugB0") as RcaPlug


func _seat(hp: Headphones, host: Node3D) -> bool:
	var jack := host.find_child("PhonesOut", true, false) as XRToolsSnapZone
	if jack == null:
		return false
	jack.pick_up_object(_plug(hp))
	await _wait(30)
	return true


# ── scene/ ────────────────────────────────────────────────────────────────────

func _t_scene() -> void:
	var hp := _headphones()
	await _wait(10)
	var a := hp.get_node("PlugA0") as RcaPlug
	var line_in := hp.get_node("Body/LineIn") as TrsPort
	_ok(a.seated_port() == line_in, "scene/the captive end sits in the headset's own jack")
	_ok(not a.enabled and a.collision_layer == 0 and not a.visible, "scene/and nothing can grab or see it")
	_ok(not line_in.enabled and line_in.collision_layer == 0, "scene/its jack takes nothing else")
	_ok(line_in.direction == RcaPort.Direction.IN and line_in.get_device() == hp,
		"scene/the jack is an IN on the headphones, which are its device")
	var exit := (hp.get_node("Body/Model") as ApplianceModel).part("CordExit")
	_ok(exit != null and line_in.global_position.distance_to(exit.global_position) < 0.0005
		and line_in.global_basis.z.dot(-exit.global_basis.z) > 0.999,
		"scene/on the left cup's CordExit, its mouth along the cord")
	var b := _plug(hp)
	var tip := b.get_node("PlugTip") as MeshInstance3D
	_ok(tip.mesh != null and tip.mesh.get_aabb().size.z > 0.04, "scene/the far end wears the model's 3.5 mm plug")
	var box := (b.get_node("CollisionShape3D") as CollisionShape3D)
	_ok(box.shape is BoxShape3D and ((box.shape as BoxShape3D).size - tip.mesh.get_aabb().size).length() < 0.0001
		and box.position.distance_to(tip.mesh.get_aabb().get_center()) < 0.0001,
		"scene/its box is what it draws")


# ── jack/ ─────────────────────────────────────────────────────────────────────

func _t_jack() -> void:
	var hp := _headphones()
	var gbc := _handheld("gbc")
	await _wait(60)
	var jack := gbc.find_child("PhonesOut", true, false) as XRToolsSnapZone
	_ok(jack != null, "jack/the Game Boy Color has a headphone jack")
	if jack == null:
		return
	var plug := _plug(hp)
	_ok(plug.is_in_group(jack.snap_require), "jack/the plug fits it")
	var lead := RCA_CABLE.instantiate() as Node3D
	add_child(lead)
	_spawned.append(lead)
	await _wait(5)
	var rca := lead.get_node("PlugA0") as RcaPlug
	var phono_groups := Connectors.groups_of(rca.connector)
	var fits_phono := false
	for g: String in phono_groups:
		fits_phono = fits_phono or plug.is_in_group(g)
	_ok(not fits_phono and not rca.is_in_group(jack.snap_require),
		"jack/and no phono socket takes it, nor does the jack take a phono plug")
	var route := gbc.audio_route()
	_ok(route["tv"] == null and not route["socketed"], "jack/with nothing in it the handheld plays from itself")
	await _seat(hp, gbc)
	route = gbc.audio_route()
	_ok(route["tv"] == hp, "jack/seated, the jack's lead reaches the headphones", str(route["tv"]))
	_ok(route["socketed"] and (gbc.get("_av") as Object).call("phones_carry_sound"), "jack/and the handheld's own speaker is cut")
	_ok([route["left"], route["right"]] == [0, 1], "jack/left on the left cup, right on the right")
	_ok(hp.source() == gbc, "jack/the headphones know who plays through them")
	var sp := hp.get_speaker_positions()
	var body := hp.get_node("Body") as Node3D
	var l_local := body.global_transform.affine_inverse() * sp[0]
	var r_local := body.global_transform.affine_inverse() * sp[1]
	_ok(l_local.x < -0.06 and r_local.x > 0.06 and absf(l_local.y) < 0.02,
		"jack/speaker 0 is the left pad, speaker 1 the right (%s, %s)" % [l_local, r_local])
	hp.net_release_plug(1, 0)
	await _wait(30)
	route = gbc.audio_route()
	_ok(route["tv"] == null and not route["socketed"], "jack/pulled, the handheld plays from itself again")
	_ok(hp.source() == null, "jack/and the headphones carry nothing")


# ── tv/ ───────────────────────────────────────────────────────────────────────

func _t_tv() -> void:
	var hp := _headphones(Vector3(0, 1, 1))
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.freeze = true
	tv.position = Vector3(3, 1, 0)
	add_child(tv)
	tv.add_to_group("spawned")
	_spawned.append(tv)
	await _wait(60)
	_ok(tv.panel().phones() is TrsPort, "tv/the stock set has a headphone jack")
	_ok(tv.get_audio_unit_size() <= 0.0, "tv/with nothing in it the set keeps its sources' own distance law")
	await _seat(hp, tv)
	_ok(tv.phones_sink() == hp, "tv/the set's jack reaches the headphones")
	_ok(tv.get_speaker_positions() == hp.get_speaker_positions(), "tv/its sound plays at the cups")
	_ok(is_equal_approx(tv.get_audio_unit_size(), Headphones.UNIT_SIZE),
		"tv/at the headphones' near-ear distance law (%.2f m)" % tv.get_audio_unit_size())
	tv.set_power(true)
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	await _wait(6)
	_ok(is_equal_approx(tv.audio().volume_for(RetroTV.Source.COMPOSITE_1), tv.audio().volume() * Headphones.LEVEL),
		"tv/and at the set's level times the headphones' (%.2f)" % Headphones.LEVEL)


# ── sound/ ────────────────────────────────────────────────────────────────────

## The real SystemAudio.update_position, with a recording stand-in for the SDK and two voice ids, as a running core's
## would be.
func _t_sound() -> void:
	var hp := _headphones()
	var gbc := _handheld("gbc")
	await _wait(60)
	await _seat(hp, gbc)
	var audio: SystemAudio = gbc.get("_audio")
	var mx := FakeMx.new()
	audio.set("_voices", PackedInt32Array([11, 12]))
	audio.set("_mx", mx)
	audio.set("_last_volume", Headphones.LEVEL)
	var listener: Vector3 = get_node("/root/SpatialAudioListener").call("get_listener_position")
	# Worn: the ear axis on the listener (the head's middle).
	var body := hp.get_node("Body") as Node3D
	body.global_transform = Transform3D(Basis(), listener + Vector3(0, Headphones.EXTEND_M * 0.5, 0))
	audio.update_position()
	var held_l: Vector3 = mx.pos.get(11, Vector3.INF)
	var held_r: Vector3 = mx.pos.get(12, Vector3.INF)
	_ok((held_l - listener).normalized().dot(Vector3.LEFT) > 0.999
		and (held_r - listener).normalized().dot(Vector3.RIGHT) > 0.999,
		"sound/worn, voice L is hard left of the head and voice R hard right", "%s %s" % [held_l, held_r])
	_ok(absf((held_l - listener).length() - SpatialAudioEmitter.MIN_LISTENER_DISTANCE) < 0.001,
		"sound/held off the head to %.2f m, where the HRTF stays clear" % SpatialAudioEmitter.MIN_LISTENER_DISTANCE)
	_ok(is_equal_approx(float(mx.gain.get(11, -1.0)), Headphones.LEVEL)
		and is_equal_approx(float(mx.gain.get(12, -1.0)), Headphones.LEVEL),
		"sound/at the headphones' level, %.2f, on both" % Headphones.LEVEL, str(mx.gain))
	# On a desk a metre off: the same two voices, a small source there, quieter by the near-ear law.
	body.global_transform = Transform3D(Basis(), listener + Vector3(0, 0, -1.0))
	audio.update_position()
	var cups := hp.get_speaker_positions()
	_ok((mx.pos[11] as Vector3).distance_to(cups[0]) < 0.0001 and (mx.pos[12] as Vector3).distance_to(cups[1]) < 0.0001,
		"sound/a metre off, the voices are the cups themselves")
	var want := Headphones.LEVEL * Headphones.UNIT_SIZE / 1.0
	_ok(absf(float(mx.gain[11]) - want) < 0.002, "sound/at %.3f, the leak of open headphones a metre off" % want,
		str(mx.gain))
	audio.set("_voices", PackedInt32Array())
	audio.set("_mx", null)
	# Dry: nothing in the game gives the SDK a room, so no voice has reverb or early reflections to send.
	var rooms := _calls_in_scripts("set_room(")
	_ok(rooms.is_empty(), "sound/no script sets a room on Meta XR Audio, so the voices are dry", str(rooms))


func _calls_in_scripts(needle: String) -> Array:
	var hits: Array = []
	var stack: Array[String] = ["res://Scripts"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(dir_path.path_join(sub))
		for f in d.get_files():
			if f.ends_with(".gd") and FileAccess.get_file_as_string(dir_path.path_join(f)).contains(needle):
				hits.append(dir_path.path_join(f))
	return hits


# ── wear/ ─────────────────────────────────────────────────────────────────────

func _t_wear() -> void:
	var hp := _headphones()
	await _wait(10)
	var body := hp.get_node("Body") as RigidBody3D
	body.freeze = false
	hp.put_on(_cam)
	await _wait(3)
	var want := _cam.global_transform * Headphones.WORN_OFFSET * Transform3D(Basis(), Vector3(0, Headphones.EXTEND_M * 0.5, 0))
	_ok(hp.worn and body.freeze and body.global_transform.origin.distance_to(want.origin) < 0.0001,
		"wear/put on, the headset rides the camera, its ear axis on the head's")
	_cam.global_position += Vector3(0.3, 0.0, 0.0)
	await _wait(3)
	_ok(body.global_position.distance_to((_cam.global_transform * Headphones.WORN_OFFSET).origin
		+ _cam.global_basis.y * Headphones.EXTEND_M * 0.5) < 0.0001,
		"wear/and follows it")
	var sp := hp.get_speaker_positions()
	var ear_l := _cam.global_transform * (Headphones.WORN_OFFSET * Vector3(-Headphones.PAD_X, 0, 0))
	_ok(sp[0].distance_to(ear_l) < 0.0001, "wear/the left channel is at the left ear, whatever the band's size")
	body.grabbed.emit(body, _grabber)
	await _wait(2)
	_ok(not hp.worn, "wear/a hand taking it takes it off")
	hp.options_choose(0, 1)
	_ok(hp.worn, "wear/its menu puts it on")
	var plug_rows: Array = _plug(hp).call("options_choices")
	_ok(plug_rows.size() == 2 and int((plug_rows[0] as Dictionary)["selected"]) == 1,
		"wear/the plug carries the same menu (the desktop's way to take them off)")
	_plug(hp).call("options_choose", 0, 0)
	_ok(not hp.worn and not body.freeze, "wear/and takes it off from there")
	var cup := (hp.get_node("Body/Model") as ApplianceModel).part("CupR")
	var before := cup.position.y
	hp.options_choose(1, 2)
	_ok(absf(before - cup.position.y - Headphones.EXTEND_M * 0.5) < 0.00001,
		"wear/Band: Large brings each ear piece 8 mm further down than Medium")
	hp.options_choose(1, 0)
	_ok(absf(cup.position.y - (before + Headphones.EXTEND_M * 0.5)) < 0.00001, "wear/Band: Small pulls them in")


# ── save/ ─────────────────────────────────────────────────────────────────────

func _t_save() -> void:
	var hp := _headphones()
	await _wait(10)
	hp.set_band(2)
	hp.put_on(_cam)
	await _wait(3)
	var sp := ScenePersistence.new("headphones_tests")
	var entry := sp.serialize_node(hp, 1, {hp: 1})
	_ok(str(entry.get("kind", "")) == "headphones", "save/saved as headphones", str(entry.get("kind")))
	_ok(bool((entry.get("body", {}) as Dictionary).get("worn", false)), "save/worn is saved")
	var band_saved := false
	for rec: Dictionary in entry.get("articulated", []):
		band_saved = band_saved or (str(rec.get("path")) == "Body/BandSize" and is_equal_approx(float(rec.get("value")), 1.0))
	_ok(band_saved, "save/the band's size is saved", str(entry.get("articulated")))
	var back := sp.deserialize_object(entry) as Headphones
	_ok(back != null, "save/it loads back as headphones")
	if back == null:
		return
	add_child(back)
	_spawned.append(back)
	await _wait(5)
	sp.call("_restore_articulated_controls", back, entry.get("articulated", []))
	sp.call("_restore_lead", self, 1, back, {}, entry)
	await _wait(5)
	_ok(back.worn, "save/restored worn, on the camera's head")
	var cup := (back.get_node("Body/Model") as ApplianceModel).part("CupR")
	var saved_cup := (hp.get_node("Body/Model") as ApplianceModel).part("CupR")
	_ok(absf(cup.position.y - saved_cup.position.y) < 0.00001
		and is_equal_approx((back.get_node("Body/BandSize") as VRSlider).value, 1.0),
		"save/and on the Large band", "%f vs %f" % [cup.position.y, saved_cup.position.y])


# ── ray/ ──────────────────────────────────────────────────────────────────────

func _t_ray() -> void:
	var hp := _headphones(Vector3(0, 1, 0))
	await _wait(10)
	var space := get_viewport().world_3d.direct_space_state
	var body := hp.get_node("Body") as Node3D
	var cup := body.global_transform * Vector3(0.0835, 0.0, 0.0)
	var t := InteractionResolver.resolve_desktop(space, cup + Vector3(0.6, 0, 0), cup - Vector3(0.05, 0, 0), _grabber)
	_ok(t.action_node == body, "ray/aimed at a cup from the side, the ray takes the headset",
		str(t.action_node.name) if t.action_node else "-")
	var apex := body.global_transform * Vector3(0.0, 0.1358, 0.0)
	t = InteractionResolver.resolve_desktop(space, apex + Vector3(0, 0.6, 0), apex - Vector3(0, 0.05, 0), _grabber)
	_ok(t.action_node == body, "ray/aimed at the band's crown from above, the headset")
	var inside := body.global_transform * Vector3(0.0, 0.08, 0.0)
	t = InteractionResolver.resolve_desktop(space, inside + Vector3(0, 0, 0.6), inside - Vector3(0, 0, 0.05), _grabber)
	_ok(t.action_node != body, "ray/through the open middle of the band, nothing of it (no box round the arch)")
	var plug := _plug(hp)
	plug.freeze = true
	plug.global_position = Vector3(1.0, 1.0, 0.0)
	await _wait(3)
	var pp := plug.global_transform * Vector3(0, 0, -0.01)
	t = InteractionResolver.resolve_desktop(space, pp + Vector3(0, 0.6, 0), pp - Vector3(0, 0.05, 0), _grabber)
	_ok(t.action_node == plug, "ray/aimed at the plug, the plug")
