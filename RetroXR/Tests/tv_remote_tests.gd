## TV remote self-tests — the RETRO XR handset's own keys, headless, with no core, ROM or headset.
##
##     "$godot" --headless --path RetroXR res://Tests/tv_remote_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/tv_remote_tests.tscn -- --only=ray/
##
## The remote is RetroXR-models' generic/tv-remote: 26 keys, each one of the grid's cells.
##
##   dress/   every model key is a VRButton wearing the key, the tip is on the model's IrTip;
##   shapes/  every shape is what is drawn, no margin: each key's is its own triangles, the
##            laser's the shell's, the body's the shell's hull;
##   ray/     the desktop ray at every key's face takes THAT key, from above and tilted; aimed
##            into the 2 mm gap between two keys, or at the shell, it takes no key (the control:
##            the 3 mm-padded box adopt_button used to give would have taken the gap);
##   touch/   a fingertip on a key is that key's and no other's (the ring's arcs overlap as boxes);
##   keys/    each key does its cell on a set, a VCR, a DVD player and a record player, nothing
##            where the grid would grey the cell or leave it out; PREV/NEXT are a DVD's chapters;
##   aim/     with no grid up, a key acts on what the window points at, and on nothing turned away;
##   press/   a clicked key sinks 1.2 mm into the remote and comes back, and does its cell.
extends "res://Tests/test_suite.gd"

const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const DVD_SCENE := preload("res://Scenes/Objects/appliances/dvd_player.tscn")
const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")

## Written out again here, not read from TVRemote.KEY_CELLS: a key wired to the wrong
## cell must fail against something it was not copied from.
const PRINTED := {
	"KeyPower": "power", "KeySource": "source", "KeyVolDown": "vol_down", "KeyMute": "mute",
	"KeyVolUp": "vol_up", "KeyChDown": "ch_down", "KeyChUp": "ch_up", "KeyAudioMode": "audio_mode",
	"KeyStereo3d": "stereo3d", "KeyAspect": "aspect", "KeyAudioOut": "audio_out", "KeyEject": "eject",
	"KeyPrev": "prev", "KeyPlayPause": "playpause", "KeyNext": "next", "KeyRew": "rew", "KeyStop": "stop",
	"KeyFf": "ff", "KeyUp": "up", "KeyDown": "down", "KeyLeft": "left", "KeyRight": "right", "KeyOk": "ok",
	"KeyMenu": "menu", "KeyAudio": "audio", "KeySubtitle": "subtitle",
}
## A tenth of a millimetre.
const TOLERANCE := 0.0001

var _spawned: Array[Node] = []
var _hand: Node3D = null


func _ready() -> void:
	suite_tag = "remote"
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[remote] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	for c: Array in [["dress/", _test_dress], ["shapes/", _test_shapes], ["ray/", _test_ray],
			["touch/", _test_touch], ["keys/", _test_keys], ["aim/", _test_aim], ["press/", _test_press]]:
		if _wanted(str(c[0])):
			await (c[1] as Callable).call()
			await _cleanup()
	_finish()


func _wanted(what: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return what.begins_with(arg.substr(7)) or arg.substr(7).begins_with(what)
	return true


func _remote(at := Vector3(0, 1, 0)) -> TVRemote:
	var r := REMOTE.instantiate() as TVRemote
	r.freeze = true
	r.position = at
	add_child(r)
	_spawned.append(r)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return r


func _spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var n := scene.instantiate() as Node3D
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	n.position = at
	add_child(n)
	_spawned.append(n)
	await get_tree().process_frame
	return n


func _cap(b: VRButton) -> MeshInstance3D:
	return b.get_node("ButtonMesh") as MeshInstance3D


## The middle of a key's face in world space (a key's origin is its face's middle).
func _face(b: VRButton) -> Vector3:
	return _cap(b).global_transform.origin


func _faces_box(shape: Shape3D) -> AABB:
	var faces := (shape as ConcavePolygonShape3D).get_faces()
	var box := AABB(faces[0], Vector3.ZERO)
	for p in faces:
		box = box.expand(p)
	return box


func _same(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < TOLERANCE and a.end.distance_to(b.end) < TOLERANCE


# ── dress/ ────────────────────────────────────────────────────────────────────

func _test_dress() -> void:
	var r := await _remote()
	_eq(r.get_node("Keys").get_child_count(), 26, "dress/26 keys, one VRButton each")
	var missing: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		var model_key := r.get_node("Model").call("part", key) as MeshInstance3D
		if b == null or model_key == null or _cap(b).mesh != model_key.mesh or not _cap(b).visible \
				or model_key.visible:
			missing.append(key)
	_ok(missing.is_empty(), "dress/every key wears the model's key, the model's own one hidden", str(missing))
	var tip := r.get_node("Tip") as Marker3D
	var want: Transform3D = r.get_node("Model").call("part_transform", "IrTip", r)
	_ok(tip.transform.is_equal_approx(want) and tip.position.distance_to(Vector3(0, 0.003, -0.1)) < TOLERANCE
		and tip.transform.basis.z.is_equal_approx(Vector3.BACK),
		"dress/the tip is on the model's IrTip, aiming along -Z", str(tip.transform))


# ── shapes/ ───────────────────────────────────────────────────────────────────

func _test_shapes() -> void:
	var r := await _remote()
	var model := r.get_node("Model") as ApplianceModel
	var except: Array[String] = ["BodyPrint"]
	except.append_array(PRINTED.keys())
	var drawn := ApplianceModel.node_bounds(model.levels[0], r, except)
	var body := (r.get_node("CollisionShape3D") as CollisionShape3D)
	var hull := body.shape as ConvexPolygonShape3D
	_ok(hull != null, "shapes/the body is a convex hull")
	if hull != null:
		var hb := AABB(hull.points[0], Vector3.ZERO)
		for p in hull.points:
			hb = hb.expand(p)
		_ok(_same(body.transform * hb, drawn), "shapes/the body's hull is the shell's bounds, no margin",
			"%s vs %s" % [body.transform * hb, drawn])
	var laser := r.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	_ok(laser.shape is ConcavePolygonShape3D and _same(laser.transform * _faces_box(laser.shape), drawn),
		"shapes/the laser's shape is the shell's own triangles")
	var padded: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		var shape := b.get_node("CollisionShape3D") as CollisionShape3D
		if not shape.shape is ConcavePolygonShape3D \
				or not _same(shape.transform * _faces_box(shape.shape), _cap(b).transform * _cap(b).mesh.get_aabb()):
			padded.append(key)
	_ok(padded.is_empty(), "shapes/every key's shape is its own triangles, no margin", str(padded))


# ── ray/ ──────────────────────────────────────────────────────────────────────

func _resolve(from: Vector3, to: Vector3) -> InteractionTarget:
	return InteractionResolver.resolve_desktop(get_viewport().world_3d.direct_space_state, from, to, _hand)


## Desktop rays from 0.6 m at `at`: straight down onto the face, and tilted 30 degrees
## toward the window, the grip end and either side.
func _rays_at(r: TVRemote, at: Vector3) -> Array[InteractionTarget]:
	var out: Array[InteractionTarget] = []
	for d: Vector3 in [Vector3(0, 1, 0), Vector3(0, 0.866, -0.5), Vector3(0, 0.866, 0.5),
			Vector3(0.5, 0.866, 0), Vector3(-0.5, 0.866, 0)]:
		var dir := r.global_transform.basis * d
		out.append(_resolve(at + dir * 0.6, at - dir * 0.01))
	return out


func _test_ray() -> void:
	var r := await _remote()
	var blocked: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		for t in _rays_at(r, _face(b) - r.global_transform.basis.y * 0.0002):
			if t.kind != InteractionTarget.KIND_BUTTON or t.action_node != b:
				blocked.append("%s (%s %s)" % [key, t.kind, t.action_node.name if t.action_node else "-"])
	_ok(blocked.is_empty(), "ray/every key's face takes that key, from above and tilted", ", ".join(blocked))
	# The control: the middle of the 2 mm gap between VOL - and MUTE takes no key. Each key's
	# box used to be 3 mm larger than the key, and that box reached 0.25 mm past this point.
	var mute := _face(r.key_button("KeyMute"))
	var gap := mute - r.global_transform.basis.x * 0.00725
	var t := _resolve(gap + Vector3.UP * 0.6, gap - Vector3.UP * 0.02)
	_ok(t.kind != InteractionTarget.KIND_BUTTON, "ray/the gap between two keys takes no key",
		"%s %s" % [t.kind, t.action_node.name if t.action_node else "-"])
	# …and the shell itself (RETRO XR, over the battery end) is the remote's, to pick up.
	var shell := r.global_transform * Vector3(0, 0.0112, 0.07)
	var s := _resolve(shell + Vector3.UP * 0.6, shell - Vector3.UP * 0.02)
	_ok(s.kind != InteractionTarget.KIND_BUTTON and s.action_node == r,
		"ray/the shell between the keys is the remote's", "%s %s" % [s.kind, s.action_node])


# ── touch/ ────────────────────────────────────────────────────────────────────

## A fingertip resting on one key's face (1 mm over it) is that key's, and every
## other key's gate refuses it — the ring's arcs and OK most of all, whose boxes overlap.
func _test_touch() -> void:
	var r := await _remote()
	var wrong: Array[String] = []
	for key: String in PRINTED:
		var tip := _face(r.key_button(key)) + r.global_transform.basis.y * 0.001
		for other: String in PRINTED:
			var takes: bool = r.key_button(other).press_gate.call(tip)
			if takes != (other == key):
				wrong.append("%s's face %s %s" % [key, "taken by" if takes else "refused by", other])
	_ok(wrong.is_empty(), "touch/a fingertip on a key is that key's alone", ", ".join(wrong))
	# Over the key and not on it: 5 mm up is a hover, not a press.
	var high := _face(r.key_button("KeyOk")) + r.global_transform.basis.y * 0.005
	_ok(not r.key_button("KeyOk").press_gate.call(high), "touch/5 mm over a key does not press it")


# ── keys/ ─────────────────────────────────────────────────────────────────────

func _test_keys() -> void:
	var r := await _remote()
	var tv := await _spawn(TV_SCENE, Vector3(3, 1, 0)) as RetroTV
	r._target = tv
	# A set: each of its keys acts on it; the transport keys are no keys of a set's.
	var on := tv.is_on()
	_eq(r.press_key("KeyPower"), "power", "keys/tv POWER is the set's power cell")
	_ok(tv.is_on() != on, "keys/tv POWER switched the set")
	var muted := tv.is_muted()
	_eq(r.press_key("KeyMute"), "mute", "keys/tv MUTE is the set's mute cell")
	_ok(tv.is_muted() != muted, "keys/tv MUTE muted the set")
	var wide := tv.widescreen
	_eq(r.press_key("KeyAspect"), "aspect", "keys/tv ASPECT is the set's aspect cell")
	_ok(tv.widescreen != wide, "keys/tv ASPECT changed the picture's shape")
	for key: String in ["KeyVolUp", "KeyVolDown", "KeySource", "KeyAudioMode", "KeyAudioOut"]:
		_eq(r.press_key(key), PRINTED[key], "keys/tv %s is its cell" % key)
	for key: String in ["KeyStop", "KeyPlayPause", "KeyEject", "KeyOk", "KeyMenu", "KeyPrev"]:
		_eq(r.press_key(key), "", "keys/tv %s does nothing to a set" % key)
	var vcr := await _spawn(VCR_SCENE, Vector3(5, 1, 0))
	r._target = vcr
	_eq(r.press_key("KeyStop"), "stop", "keys/vcr STOP")
	_eq(r.press_key("KeyFf"), "ff", "keys/vcr FF")
	_eq(r.press_key("KeyPrev"), "", "keys/vcr PREV is greyed on a tape")
	_eq(r.press_key("KeyEject"), "", "keys/vcr EJECT is greyed with no tape")
	_eq(r.press_key("KeyPower"), "", "keys/vcr POWER is no deck key")
	var dvd := await _spawn(DVD_SCENE, Vector3(7, 1, 0))
	r._target = dvd
	_eq(r.cell_for_key("KeyPrev"), "prev_ch", "keys/dvd PREV is the chapter key")
	_eq(r.cell_for_key("KeyNext"), "next_ch", "keys/dvd NEXT is the chapter key")
	_eq(r.press_key("KeyNext"), "next_ch", "keys/dvd NEXT skips a chapter")
	_eq(r.press_key("KeyUp"), "", "keys/dvd the ring is greyed outside a disc menu")
	_eq(r.press_key("KeyMenu"), "menu", "keys/dvd MENU is always live")
	var rp := await _spawn(RECORD_PLAYER, Vector3(9, 1, 0))
	r._target = rp
	_eq(r.cell_for_key("KeyPrev"), "prev", "keys/record PREV is plain prev off a DVD")
	_eq(r.press_key("KeyStop"), "stop", "keys/record STOP")
	_eq(r.press_key("KeyFf"), "", "keys/record FF is greyed (a turntable has no scan)")
	var wrong: Array[String] = []
	for key: String in PRINTED:
		if r.cell_for_key(key) != PRINTED[key]:
			wrong.append(key)
	_ok(wrong.is_empty(), "keys/every key is the cell printed on it", str(wrong))
	r._target = null


# ── aim/ ──────────────────────────────────────────────────────────────────────

func _test_aim() -> void:
	# The remote at the origin points along -Z; the set stands 1.5 m off that way.
	var tv := await _spawn(TV_SCENE, Vector3(0, 1, -1.5)) as RetroTV
	var r := await _remote(Vector3(0, 1.1, 0))
	var on := tv.is_on()
	_eq(r.press_key("KeyPower"), "power", "aim/a key on a remote lying pointed at a set acts on it")
	_ok(tv.is_on() != on, "aim/…and the set switched")
	r.rotate_y(PI)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_eq(r.press_key("KeyPower"), "", "aim/turned away from it, the same key acts on nothing")


# ── press/ ────────────────────────────────────────────────────────────────────

func _test_press() -> void:
	var tv := await _spawn(TV_SCENE, Vector3(0, 1, -1.5)) as RetroTV
	var r := await _remote(Vector3(0, 1.1, 0))
	var b := r.key_button("KeyMute")
	var rest := _cap(b).global_position
	var muted := tv.is_muted()
	var at := _face(b)
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, b, at, at))
	var sunk := rest - _cap(b).global_position
	_ok(absf(sunk.length() - 0.0012) < 0.00005 and sunk.normalized().dot(r.global_transform.basis.y) > 0.999,
		"press/a clicked key sinks 1.2 mm into the remote", str(sunk))
	_ok(tv.is_muted() != muted, "press/…and does its cell on the set it points at")
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, null, b, at, at))
	_ok(_cap(b).global_position.distance_to(rest) < 0.00001, "press/let go, it comes back up")


## remove_child then free, as deck_tests does: a set's or deck's audio emitter still
## alive at quit segfaults the exit.
func _cleanup() -> void:
	for n in _spawned:
		if not is_instance_valid(n):
			continue
		var parent := n.get_parent()
		if parent:
			parent.remove_child(n)
		n.free()
	_spawned.clear()
	for i in 3:
		await get_tree().process_frame
