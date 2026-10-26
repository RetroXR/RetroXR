## Control poke self-tests — every button on every pad, handheld and peripheral
## in the game can be pressed with a fingertip (ControlPoke).
##
##     "$godot" --headless --path RetroXR res://Tests/control_poke_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/control_poke_tests.tscn -- --only=nes
##
## Exits 0 when everything passes, 1 otherwise.
##
## Per object, with a fake hand (a Node3D carrying a "PokeTip" child):
##   cover/  every cap-like mesh in the scene is a poke target, a widget's mesh,
##           or named in SKIP with the reason it is not pressed;
##   press/  a fingertip on a cap's face gives exactly that cap's input — no
##           neighbour bleeds in — and pushed 6 mm on into the shell it holds;
##   clear/  15 mm off the face gives nothing;
##   arm/    each d-pad direction: the model's OWN animation is driven with that
##           one bit, the arm it sinks is found, and a fingertip on that arm must
##           give that bit back. A swapped or inverted arm convention fails here;
##   pivot/  the middle of a cross gives nothing;
##   visual/ a cap with no input behind it (a Home key) gives nothing and goes in.
##
## Writes nothing.
extends Node

const PADS := {
	"nes": "res://Scenes/Objects/controllers/nes/nes_controller.tscn",
	"n64": "res://Scenes/Objects/controllers/n64/n64_controller.tscn",
	"ps1": "res://Scenes/Objects/controllers/playstation/ps1_controller.tscn",
	"dualshock": "res://Scenes/Objects/controllers/playstation/ps1_dualshock.tscn",
	"famicom1": "res://Scenes/Objects/controllers/famicom/famicom_controller_i.tscn",
	"famicom2": "res://Scenes/Objects/controllers/famicom/famicom_controller_ii.tscn",
	"vbpad": "res://Scenes/Objects/controllers/vb/vb_controller.tscn",
	"retropad": "res://Scenes/Objects/controllers/retro_controller.tscn",
	"cx40": "res://Scenes/Objects/controllers/atari/atari_2600_cx40.tscn",
}
const HANDHELDS := {
	"gb": "res://Scenes/Objects/system_models/game_boy_primitive.tscn",
	"gbc": "res://Scenes/Objects/system_models/game_boy_color_primitive.tscn",
	"gba_standin": "res://Scenes/Objects/system_models/game_boy_advance_primitive.tscn",
	"gba": "res://Scenes/Objects/system_models/game_boy_advance.tscn",
	"gbasp": "res://Scenes/Objects/system_models/game_boy_advance_sp_primitive.tscn",
	"nds": "res://Scenes/Objects/system_models/nds_primitive.tscn",
	"n3ds": "res://Scenes/Objects/system_models/n3ds_primitive.tscn",
	"psp": "res://Scenes/Objects/system_models/psp_primitive.tscn",
	"lynx": "res://Scenes/Objects/system_models/atari_lynx.tscn",
	"gamegear": "res://Scenes/Objects/system_models/game_gear.tscn",
	"ngp": "res://Scenes/Objects/system_models/neo_geo_pocket.tscn",
	"pokemini": "res://Scenes/Objects/system_models/pokemon_mini.tscn",
	"supervision": "res://Scenes/Objects/system_models/supervision.tscn",
	"wonderswan": "res://Scenes/Objects/system_models/wonderswan.tscn",
}
const OTHERS := {
	"vmu": "res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn",
	"nunchuk": "res://Scenes/Objects/controllers/wii/nunchuk.tscn",
	"lightgun": "res://Scenes/Objects/peripherals/light_gun.tscn",
}

## A mesh whose name says "control" but that a fingertip does not press, by
## object, with why. Anything cap-like and not here must be a poke target.
const SKIP := {
	# The power key is the console's own VRButton, which RetroSystem hands it
	# (configure_buttons) — no host in a suite, so it is not one yet.
	# PSButton is the C-Stick nub (the modeller reused a PlayStation name): a
	# stick, pushed rather than pressed.
	"n3ds": ["PowerButton3ds", "PSButton"],
	# POWER is a VRSlider's knob and EJECT the UMD latch's slider, both set up
	# by RetroSystem's configure_* calls.
	"psp": ["PowerButton", "EjectButton"],
	# Pulled by the holding hand's own trigger, not poked. Keyed by kind, so a
	# gun pack's trigger is let off too.
	"lightgun": ["Trigger"],
	# Any object: an extension plug's release latch (the Classic Controller
	# pack's) frees the plug and is no control at all.
	"*": ["LatchButton"],
}

const CAP_NAME := "(?i)(button|btn|dpad|d_pad|shoulder|trigger|start|select|home|fire)"

var _pass := 0
var _fail := 0
var _only := ""
var _hand: Node3D = null
var _cap_re := RegEx.create_from_string(CAP_NAME)


func _ready() -> void:
	# --extra=key|kind|res://path;... runs the same cases on objects that are not
	# the game's own: a shell pack staged into this checkout's mods/ folder.
	var extra: Array[PackedStringArray] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
		elif arg.begins_with("--extra="):
			for spec in arg.substr(8).split(";", false):
				extra.append(spec.split("|"))
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[poke] TIMEOUT")
		get_tree().quit(1))
	# The player's own switch, put back as found at the end and never saved.
	var poke_pref := AppPrefs.poke_controls
	AppPrefs.poke_controls = true
	_hand = Node3D.new()
	_hand.name = "Hand"
	var tip := Node3D.new()
	tip.name = "PokeTip"
	_hand.add_child(tip)
	add_child(_hand)

	for key: String in PADS:
		if _wants(key):
			await _test_object(key, PADS[key], "pad")
	for key: String in HANDHELDS:
		if _wants(key):
			await _test_object(key, HANDHELDS[key], "handheld")
	for key: String in OTHERS:
		if _wants(key):
			await _test_object(key, OTHERS[key], key)
	for spec: PackedStringArray in extra:
		await _test_object(spec[0], spec[2], spec[1])

	AppPrefs.poke_controls = poke_pref
	print("[poke] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _wants(key: String) -> bool:
	return _only.is_empty() or _only == key


func _check(name: String, ok: bool, why: String = "") -> void:
	if ok:
		_pass += 1
		print("[poke] PASS %s" % name)
	else:
		_fail += 1
		print("[poke] FAIL %s — %s" % [name, why])


# ── One object ──────────────────────────────────────────────────────────────

func _test_object(key: String, path: String, kind: String) -> void:
	var scene := load(path) as PackedScene
	_check("%s/load" % key, scene != null, "cannot load " + path)
	if scene == null:
		return
	var obj := scene.instantiate() as Node3D
	# Well clear of the origin and of each other: nothing else is near the hand.
	obj.position = Vector3(0, 1, 0)
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	add_child(obj)
	await get_tree().process_frame
	await get_tree().process_frame
	# The suite drives every poll and every animation itself.
	obj.set_process(false)
	obj.set_physics_process(false)

	var poke := _poke_of(obj, kind)
	_check("%s/bound" % key, poke != null and not poke.targets.is_empty(),
		"no ControlPoke, or no targets")
	if poke == null or poke.targets.is_empty():
		obj.queue_free()
		await get_tree().process_frame
		return
	var hands: Array[Node3D] = [_hand]
	poke.set_controllers(hands)

	_test_cover(key, kind, obj, poke)
	var drive := _driver(obj, kind)
	for i in poke.targets.size():
		var t: Dictionary = poke.targets[i]
		var label := "%s/%s" % [key, (t["node"] as Node).name]
		if t.has("rocker"):
			await _test_rocker(label, poke, t, drive)
		elif _expect(t).is_empty():
			await _test_visual(label, poke, t)
		else:
			await _test_button(label, poke, t)
	if kind == "handheld":
		await _test_powered_off(key, obj, poke)
	obj.queue_free()
	await get_tree().process_frame


## The object's ControlPoke, built the way its owner builds it.
func _poke_of(obj: Node, kind: String) -> ControlPoke:
	match kind:
		"handheld":
			if obj.has_method("poke_merge"):
				obj.call("poke_merge", 0, 0, 0, 0, 0, 1)
		"lightgun":
			obj.call("_merge_poke", {})
	return obj.get("_poke") as ControlPoke


## Drive the object's own animation with `btn` until it settles, so an arm test
## measures what the model actually does.
func _driver(obj: Node, kind: String) -> Callable:
	match kind:
		"pad", "vmu":
			return func(btn: int) -> void:
				(obj.get("_anim") as ControlAnimator).animate(btn, Vector2.ZERO, Vector2.ZERO, 1.0)
		"handheld":
			return func(btn: int) -> void:
				for i in 80:
					obj.call("animate_controls", btn, Vector2.ZERO, Vector2.ZERO)
	return Callable()


# ── cover/ ──────────────────────────────────────────────────────────────────

func _test_cover(key: String, kind: String, obj: Node, poke: ControlPoke) -> void:
	var owned := {}
	for t: Dictionary in poke.targets:
		var n: Node = t["node"]
		owned[n] = true
		for m in n.find_children("*", "MeshInstance3D", true, false):
			owned[m] = true
	# A widget's own meshes (a VRButton's cap, a slider's knob) are pressed or
	# slid by that widget.
	for w in obj.find_children("*", "Area3D", true, false):
		for m in w.find_children("*", "MeshInstance3D", true, false):
			owned[m] = true
		for p: Dictionary in w.get_property_list():
			var v: Variant = w.get(p["name"])
			if v is MeshInstance3D:
				owned[v] = true
	var skip: Array = []
	for k: String in [key, kind, "*"]:
		skip.append_array(SKIP.get(k, []))
	var missed: PackedStringArray = []
	for m: Node in obj.find_children("*", "MeshInstance3D", true, false):
		if owned.has(m) or not (m as MeshInstance3D).visible:
			continue
		if _cap_re.search(String(m.name)) == null:
			continue
		var skipped := false
		for s: String in skip:
			if String(m.name).begins_with(s):
				skipped = true
		if not skipped:
			missed.append(String(m.name))
	_check("%s/cover" % key, missed.is_empty(), "not pokeable: %s" % ", ".join(missed))


# ── Geometry ────────────────────────────────────────────────────────────────

## World transform of the target at rest, its outward normal, and its box.
func _frame(t: Dictionary) -> Dictionary:
	var node: Node3D = t["node"]
	var parent := node.get_parent() as Node3D
	var pxf := parent.global_transform if parent != null else Transform3D()
	var xf: Transform3D = pxf * (t["rest"] as Transform3D)
	var box: AABB = ControlPoke._local_box(node)
	var out := -(pxf.basis * (t["dir"] as Vector3)).normalized()
	var centre := xf * box.get_center()
	# Where a line out of the middle of the box along `out` leaves it: the face a
	# finger lands on. Not the corners' extent along `out`, which on a cap whose
	# press axis is not one of its box's axes lies off the box altogether.
	var o_local := xf.basis.inverse() * out
	var half := box.size * 0.5
	var s := INF
	for i in 3:
		if absf(o_local[i]) > 1e-9:
			s = minf(s, half[i] / absf(o_local[i]))
	var h := (xf.basis * (o_local * s)).length() if s < INF else 0.0
	return {"pxf": pxf, "xf": xf, "box": box, "out": out, "centre": centre, "top": h}


## Put the fingertip at `at` and poll on a new frame.
func _poke_at(poke: ControlPoke, at: Vector3) -> Dictionary:
	_hand.global_position = at
	await get_tree().process_frame
	poke.invalidate()
	return poke.poll()


## Take the hand out of reach, which lets go of everything at once.
func _lift(poke: ControlPoke) -> void:
	await _poke_at(poke, Vector3(0, -10, 0))


## What poking `t` alone should give: {"btn": mask} or {"stick": [side, vec]};
## empty for a cap with no input behind it.
func _expect(t: Dictionary) -> Dictionary:
	var src: Dictionary = t.get("src", t)
	if src.has("stick_dir"):
		return {"stick": [src.get("stick", "right"), src["stick_dir"]]}
	if src.has("mask"):
		return {"btn": int(src["mask"])}
	if int(src.get("bit", -1)) >= 0:
		return {"btn": 1 << int(src["bit"])}
	return {}


func _matches(s: Dictionary, want: Dictionary) -> bool:
	if want.has("btn"):
		return int(s["btn"]) == int(want["btn"]) \
			and s["lstick"] == Vector2.ZERO and s["rstick"] == Vector2.ZERO
	var side: String = want["stick"][0]
	var v: Vector2 = want["stick"][1]
	var got: Vector2 = s["lstick"] if side == "left" else s["rstick"]
	var other: Vector2 = s["rstick"] if side == "left" else s["lstick"]
	return int(s["btn"]) == 0 and got.is_equal_approx(v.limit_length(1.0)) and other == Vector2.ZERO


func _show(s: Dictionary) -> String:
	return "btn=%d l=%s r=%s" % [int(s["btn"]), s["lstick"], s["rstick"]]


# ── press/ clear/ ───────────────────────────────────────────────────────────

func _test_button(label: String, poke: ControlPoke, t: Dictionary) -> void:
	var f := _frame(t)
	var out: Vector3 = f["out"]
	var face: Vector3 = f["centre"] + out * (float(f["top"]) + 0.001)
	var want := _expect(t)
	await _lift(poke)
	var s := await _poke_at(poke, face)
	_check(label + "/press", _matches(s, want), "%s, wanted %s" % [_show(s), want])
	s = await _poke_at(poke, face - out * 0.006)
	_check(label + "/push", _matches(s, want), "%s, wanted %s" % [_show(s), want])
	await _lift(poke)
	s = await _poke_at(poke, face + out * 0.015)
	_check(label + "/clear", _idle(s), _show(s))
	await _lift(poke)
	# Switched off in Options: a press in flight lets go at once, and a fresh
	# touch starts nothing.
	await _poke_at(poke, face)
	AppPrefs.poke_controls = false
	s = await _poke_at(poke, face)
	var held_off := _idle(s)
	await _lift(poke)
	s = await _poke_at(poke, face)
	AppPrefs.poke_controls = true
	_check(label + "/off", held_off and _idle(s), _show(s))
	await _lift(poke)


func _idle(s: Dictionary) -> bool:
	return int(s["btn"]) == 0 and s["lstick"] == Vector2.ZERO and s["rstick"] == Vector2.ZERO


# ── visual/ ─────────────────────────────────────────────────────────────────

func _test_visual(label: String, poke: ControlPoke, t: Dictionary) -> void:
	var f := _frame(t)
	var out: Vector3 = f["out"]
	var face: Vector3 = f["centre"] + out * (float(f["top"]) + 0.001)
	var node: Node3D = t["node"]
	var rest: Transform3D = t["rest"]
	await _lift(poke)
	var s := {}
	for i in 30:
		s = await _poke_at(poke, face)
	var moved := (node.transform.origin - rest.origin).dot((t["dir"] as Vector3).normalized())
	_check(label + "/visual", int(s["btn"]) == 0 and moved > float(t.get("depth", 0.0)) * 0.5,
		"%s, moved %.5f of %.5f" % [_show(s), moved, float(t.get("depth", 0.0))])
	await _lift(poke)


# ── powered_off/ ────────────────────────────────────────────────────────────

## A host for HandheldInput: switched off or on, its model the object under test,
## and a libretro node that counts what reaches the core.
const _FAKE_HOST := """
extends Node3D
var is_powered_on := false
var model: Node = null
var sent: Array = []
func get_model() -> Node:
	return model
func get_libretro_node() -> Object:
	return self
func SetJoypadState(_port: int, btn: int, _alx: int, _aly: int, _arx: int, _ary: int) -> void:
	sent.append(btn)
"""


## Switched off, a cap still goes in under a fingertip and comes back out when
## let go, and nothing reaches the core; switched on (the control), the same poke
## does reach it.
func _test_powered_off(key: String, obj: Node3D, poke: ControlPoke) -> void:
	var t: Dictionary = {}
	for c: Dictionary in poke.targets:
		if not c.has("rocker") and _expect(c).has("btn"):
			t = c
			break
	if t.is_empty():
		return
	var script := GDScript.new()
	script.source_code = _FAKE_HOST
	script.reload()
	var host := Node3D.new()
	host.set_script(script)
	host.set("model", obj)
	add_child(host)
	var input := HandheldInput.new()
	input.set("_host", host)
	var f := _frame(t)
	var out: Vector3 = f["out"]
	var face: Vector3 = f["centre"] + out * (float(f["top"]) + 0.001)
	var node: Node3D = t["node"]
	var rest: Transform3D = t["rest"]
	var label := "%s/powered_off" % key
	await _lift(poke)
	for i in 40:
		await _poke_at(poke, face - out * 0.002)
		input._process(1.0 / 60.0)
	var moved := node.transform.origin.distance_to(rest.origin) 		+ node.transform.basis.get_rotation_quaternion().angle_to(rest.basis.get_rotation_quaternion())
	var sent: Array = host.get("sent")
	_check(label + "/press", moved > 1e-4 and sent.is_empty(),
		"moved %.5f, sent %s" % [moved, sent])
	for i in 90:
		await _poke_at(poke, Vector3(0, -10, 0))
		input._process(1.0 / 60.0)
	var back := node.transform.origin.distance_to(rest.origin)
	_check(label + "/release", back < moved * 0.1 and sent.is_empty(),
		"%.5f from rest after letting go (pressed %.5f), sent %s" % [back, moved, sent])
	host.set("is_powered_on", true)
	await _poke_at(poke, face - out * 0.002)
	input._process(1.0 / 60.0)
	var want := int(_expect(t)["btn"])
	_check(label + "/on_control", sent.size() == 1 and (int(sent[0]) & want) == want,
		"sent %s, wanted bit mask %d" % [sent, want])
	await _lift(poke)
	input._process(1.0 / 60.0)
	input.free()
	host.queue_free()


# ── arm/ pivot/ ─────────────────────────────────────────────────────────────

func _test_rocker(label: String, poke: ControlPoke, t: Dictionary, drive: Callable) -> void:
	var f := _frame(t)
	var pxf: Transform3D = f["pxf"]
	var xf: Transform3D = f["xf"]
	var out: Vector3 = f["out"]
	var pivot := pxf * (t["pivot"] as Vector3)
	var up := (pxf.basis * (t["up"] as Vector3)).normalized()
	var right := (pxf.basis * (t["right"] as Vector3)).normalized()
	var box: AABB = f["box"]
	var r := 0.0
	var top := 0.0
	for i in 8:
		var d := xf * box.get_endpoint(i) - pivot
		r = maxf(r, maxf(absf(d.dot(up)), absf(d.dot(right))))
		top = maxf(top, d.dot(out))
	var arms: Array[Vector3] = []
	for a: Vector3 in [up, -up, right, -right]:
		arms.append(pivot + a * r * 0.7 + out * (top + 0.001))

	await _lift(poke)
	var s := await _poke_at(poke, pivot + out * (top + 0.001))
	_check(label + "/pivot", int(s["btn"]) == 0, _show(s))
	await _lift(poke)

	if not drive.is_valid():
		return
	var bits: Array = t.get("bits", [ControllerBindings.JOYPAD_UP, ControllerBindings.JOYPAD_DOWN,
		ControllerBindings.JOYPAD_LEFT, ControllerBindings.JOYPAD_RIGHT])
	var node: Node3D = t["node"]
	var names := ["up", "down", "left", "right"]
	for k in 4:
		var bit := int(bits[k])
		drive.call(1 << bit)
		# Which arm the model's own animation sank for this bit.
		var best := -1
		var best_sink := 0.0
		for j in arms.size():
			var q := xf.affine_inverse() * arms[j]
			var now := pxf * node.transform * q
			var sink := (arms[j] - now).dot(out)
			if sink > best_sink:
				best_sink = sink
				best = j
		drive.call(0)
		if best < 0:
			_check("%s/arm_%s" % [label, names[k]], false, "the animation sinks no arm for bit %d" % bit)
			continue
		s = await _poke_at(poke, arms[best])
		_check("%s/arm_%s" % [label, names[k]], int(s["btn"]) == (1 << bit),
			"%s at the arm the animation sinks, wanted bit %d" % [_show(s), bit])
		await _lift(poke)
