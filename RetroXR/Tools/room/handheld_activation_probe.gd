## Can every handheld's controls be worked while the console is in the hand?
##
## For each handheld: spawn it, pick it up through DesktopPickup, pull it in and catch it into the
## hand (screen to you), list its controls (anything with a pointer_event), and for each one turn the
## console in the hand until a crosshair aimed at the control resolves to it, then PRESS it the way
## the mouse does and see what changed (a slider's value, a button's signal). Prints one block per
## machine and a summary line. WINDOWED, scratch XDG_DATA_HOME:
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 \
##         res://Tools/room/handheld_activation_probe.tscn -- [--only=gba,gb]
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")

## [label, systemid, model_id ("" = the platform's default)]
const MACHINES := [
	["Game Boy", "gb", ""], ["Game Boy Color", "gbc", ""], ["Game Boy Advance", "gba", ""],
	["Game Boy Advance SP", "gba", "game_boy_advance_sp_primitive"],
	["Game Boy Advance (primitive)", "gba", "game_boy_advance_primitive"],
	["DS", "nds", ""], ["3DS", "n3ds", ""], ["PSP", "psp", ""], ["Atari Lynx", "atarilynx", ""],
	["WonderSwan", "wonderswan", ""], ["WonderSwan Color", "wonderswancolor", ""],
	["Game Gear", "gamegear", ""], ["Neo Geo Pocket", "ngp", ""], ["Neo Geo Pocket Color", "ngpc", ""],
	["Pokemon Mini", "pokemini", ""], ["Supervision", "supervision", ""],
]

var _cam: Camera3D = null
var _pressed_count := 0
var _summary: PackedStringArray = []


func _ready() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	get_tree().create_timer(900.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await get_tree().create_timer(10.0).timeout
	_cam = get_viewport().get_camera_3d()
	for m: Array in MACHINES:
		if not only.is_empty() and not only.has(str(m[1])):
			continue
		await _machine(str(m[0]), str(m[1]), str(m[2]))
	print("[act] ---- summary ----")
	for line in _summary:
		print("[act] " + line)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _mouse(button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)
	if button == MOUSE_BUTTON_LEFT:
		if pressed:
			Input.action_press("trigger_left")
		else:
			Input.action_release("trigger_left")


func _controls(sys: Node) -> Array[Node3D]:
	# Only what a player can see: a machine carries power/reset/eject buttons for every kind of
	# machine and hides the ones it has no use for.
	var out: Array[Node3D] = []
	for n: Node in sys.find_children("*", "Node3D", true, false):
		if n.has_method("pointer_event") and n.has_method("desktop_aim_volume") \
				and (n as Node3D).is_visible_in_tree() and not (n.get_parent() is HeldHint):
			out.append(n as Node3D)
	return out


func _centre(control: Node3D) -> Vector3:
	var volume: Dictionary = control.call("desktop_aim_volume")
	if volume.is_empty():
		return control.global_position
	var inverse: Transform3D = volume["to_local"]
	return inverse.affine_inverse() * (volume["box"] as AABB).get_center()


func _machine(label: String, systemid: String, model_id: String) -> void:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	if not model_id.is_empty():
		sys.model_id = model_id
	sys.ignore_gravity = true
	get_tree().current_scene.add_child(sys)
	sys.add_to_group("spawned")
	await get_tree().create_timer(2.5).timeout
	sys.global_position = _cam.global_position + (-_cam.global_basis.z) * 0.45
	_cam.call("grab_spawned", sys)
	await _frames(10)
	_cam.set("_grab_dist", 0.15)
	await _catch()
	var caught: bool = _cam.get("_hand_hold")
	var handheld: bool = not DesktopPickup.screens_of(sys).is_empty()
	var controls := _controls(sys)
	print("[act] == %s (%s%s): held %s, caught %s, handheld-hold %s, %d control(s)" % [label, systemid,
		" / " + model_id if not model_id.is_empty() else "", _cam.call("held_object") != null, caught, handheld, controls.size()])
	var base: Basis = _cam.get("_hand_cam_basis")
	var worked := 0
	for control in controls:
		var name := "%s (%s)" % [control.name, control.get_script().get_global_name() if control.get_script() != null else control.get_class()]
		var found := await _reach(control, base)
		if not found["ok"]:
			print("[act]    %-34s  NOT REACHABLE in any of %d orientations" % [name, found["tried"]])
			_summary.append("%s: %s unreachable" % [label, control.name])
			continue
		var before := _state(control)
		var seen := [0]
		if control.has_signal("button_pressed"):
			control.connect("button_pressed", func() -> void: seen[0] += 1, CONNECT_ONE_SHOT)
		_mouse(MOUSE_BUTTON_LEFT, true)
		await _frames(6)
		var held_after_press: bool = _cam.call("held_object") != null
		_mouse(MOUSE_BUTTON_LEFT, false)
		await _frames(8)
		var after := _state(control)
		var held_after: bool = _cam.call("held_object") != null
		var effect: bool = before != after or seen[0] > 0
		if effect:
			worked += 1
		print("[act]    %-34s  reached at orientation %d; press: %s -> %s%s; console %s" % [name, found["index"],
			before, after, " (button signal)" if seen[0] > 0 else "",
			"kept in hand" if held_after_press and held_after else "DROPPED"])
		if not effect:
			_summary.append("%s: %s reached but nothing changed" % [label, control.name])
		if not (held_after_press and held_after):
			_summary.append("%s: %s dropped the console" % [label, control.name])
			# Pick it up again to go on.
			_cam.call("grab_spawned", sys)
			await _frames(10)
			_cam.set("_grab_dist", 0.15)
			await _catch()
	_summary.append("%s: %d of %d control(s) worked" % [label, worked, controls.size()])
	if _cam.call("held_object") != null:
		_cam.call("_drop")
	sys.queue_free()
	await _frames(10)


## The notch past the pull-in limit that carries it into the hand.
func _catch() -> void:
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames(30)


func _state(control: Node) -> String:
	if control.get("value") != null:
		return "value %.2f" % float(control.get("value"))
	if control.get("rotation_degrees") != null and control.has_signal("rotation_changed"):
		return "angle %.1f" % float(control.get("rotation_degrees"))
	return "-"


## Turn the console in the hand through a set of orientations until the crosshair, aimed at the
## control's middle, resolves to it.
func _reach(control: Node3D, base: Basis) -> Dictionary:
	var orientations: Array[Basis] = [Basis.IDENTITY]
	for deg_x: float in [-70.0, -40.0, 40.0, 70.0, 110.0, -110.0, 180.0]:
		orientations.append(Basis(Vector3.RIGHT, deg_to_rad(deg_x)))
	for deg_y: float in [-80.0, -45.0, 45.0, 80.0, 180.0]:
		orientations.append(Basis(Vector3.UP, deg_to_rad(deg_y)))
		for deg_x: float in [-60.0, 60.0]:
			orientations.append(Basis(Vector3.UP, deg_to_rad(deg_y)) * Basis(Vector3.RIGHT, deg_to_rad(deg_x)))
	var index := 0
	for o in orientations:
		_cam.set("_hand_cam_basis", o * base)
		_cam.set("_hold_blend", 1.0)
		await _frames(4)
		_cam.rotation = Vector3.ZERO
		var centre := _centre(control)
		var dir := (centre - _cam.global_position).normalized()
		_cam.look_at(_cam.global_position + dir, Vector3.UP)
		await _frames(6)
		var t: InteractionTarget = _cam.call("aimed_target")
		if t != null and t.can_activate and is_instance_valid(t.pointer_event_target) \
				and (t.pointer_event_target == control or control.is_ancestor_of(t.pointer_event_target)
				or t.pointer_event_target.is_ancestor_of(control)):
			return {"ok": true, "index": index, "tried": index + 1}
		index += 1
	return {"ok": false, "tried": orientations.size()}
