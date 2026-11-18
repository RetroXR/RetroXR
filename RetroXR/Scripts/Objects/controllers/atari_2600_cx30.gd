## Atari2600CX30 — the 2600's paddles (CX30): a pair on one plug, a primitive stand-in.
##
## Two bodies, both this class. The one the spawn menu makes (the LEAD) owns the
## cord and the DE-9 plug; it builds its PARTNER beside it, whose cord ends in the
## lead's plug, as the real pair's two cords go into one hood. The partner is
## captive: it is the lead's, saved in the lead's entry (partner_pose) and freed
## with it.
##
## Stella reads a jack's pair from two libretro ports (libretro.cxx update_input):
## the left jack's paddles A and B are ports 0 and 1, the right jack's 2 and 3. Each
## paddle's knob is its port's left-stick X, its fire button that port's B. So the
## lead in console port p drives libretro port 2p and the partner 2p + 1. The knob
## is sent as an absolute position (ForcedCoreOptions.paddle_input pins Stella's
## absolute mode), so the core's paddle is where the knob on the table is.
##
## The knob turns about 300 degrees between its stops (the 1 megohm pot), at a
## rate from the held hand's stick or the D-pad's left and right; any face button
## fires. Sizes from atari/2600/paddles in RetroXR-models (71 x 64.5 x 136 mm with
## the sleeve), the same frame as that model's GLB: knob up +Y, the label end +Z,
## the cord out of -Z, the fire button in the left wall.
class_name Atari2600CX30
extends AnimatedController

const FIRE_BIT: int = ControllerBindings.JOYPAD_B
## Any of these fires: the paddle has one button, and a hand has several.
const FIRE_MASK: int = (1 << ControllerBindings.JOYPAD_B) | (1 << ControllerBindings.JOYPAD_A) \
	| (1 << ControllerBindings.JOYPAD_Y) | (1 << ControllerBindings.JOYPAD_X)
const DPAD_LEFT: int = 1 << ControllerBindings.JOYPAD_LEFT
const DPAD_RIGHT: int = 1 << ControllerBindings.JOYPAD_RIGHT
## Half the pot's travel, either side of the middle.
const KNOB_HALF_TURN := deg_to_rad(150.0)
## A full stick turns the knob end to end in a little over a second.
const KNOB_RATE := deg_to_rad(270.0)
## Below this a stick is resting, not turning.
const STICK_DEAD := 0.15
## The button travel (the model's notes: pressed 1.5 along +X).
const FIRE_PRESS := 0.0015
## The partner's place beside the lead when the pair spawns.
const PARTNER_OFFSET := Vector3(0.085, 0.0, 0.0)

## What the plug is to the core: Stella lists "Paddles" for each jack, and a
## plain joypad there could stand for the CX40 (SystemPorts.core_device_id).
var device_names := PackedStringArray(["paddles"])
## Set on the partner before it enters the tree.
var is_partner := false
## The partner's lead, or the lead's partner.
var _lead: Atari2600CX30 = null
var _partner: Atari2600CX30 = null
## Clockwise seen from above, radians, within +-KNOB_HALF_TURN.
var knob_angle := 0.0
var _knob: Node3D = null
var _knob_rest := Basis.IDENTITY
## The last frame sent and the libretro port it went to (the tests read it).
var last_sent: Dictionary = {}
## A pose for the partner from a save, applied when it is built.
var _partner_pose: Dictionary = {}


func _ready() -> void:
	if is_partner:
		captive = true
	super._ready()
	if not is_partner:
		call_deferred("_build_partner")


func _cache_meshes() -> void:
	_anim.buttons.clear()
	_knob = find_child("KnobPivot", true, false) as Node3D
	if _knob == null:
		push_warning("[Atari2600CX30] KnobPivot not found")
	else:
		_knob_rest = _knob.basis
	var m := _find_mesh("Button")
	if m == null:
		push_warning("[Atari2600CX30] Button mesh not found")
	else:
		_anim.buttons.append({"node": m, "rest": m.transform, "bit": FIRE_BIT,
			"mask": FIRE_MASK, "depth": FIRE_PRESS, "dir": Vector3.RIGHT})


# ── The pair ──────────────────────────────────────────────────────────────────

func _build_partner() -> void:
	if is_instance_valid(_partner) or not is_inside_tree() or scene_file_path.is_empty():
		return
	var scene := load(scene_file_path) as PackedScene
	if scene == null:
		return
	var p := scene.instantiate() as Atari2600CX30
	if p == null:
		return
	p.is_partner = true
	p._lead = self
	_partner = p
	get_parent().add_child(p)
	p.global_transform = global_transform.translated_local(PARTNER_OFFSET)
	if not _partner_pose.is_empty():
		p._apply_pose(_partner_pose)
		_partner_pose = {}


func get_partner() -> Atari2600CX30:
	return _partner if is_instance_valid(_partner) else null


## The partner's place and knob, for the lead's save entry.
func partner_pose() -> Dictionary:
	var p := get_partner()
	if p == null:
		return {}
	var at := p.global_position
	var r := p.global_rotation_degrees
	return {"position": [at.x, at.y, at.z], "rotation": [r.x, r.y, r.z], "knob": p.knob_angle,
		"lead_knob": knob_angle}


func restore_partner(data: Dictionary) -> void:
	if data.is_empty():
		return
	knob_angle = clampf(float(data.get("lead_knob", 0.0)), -KNOB_HALF_TURN, KNOB_HALF_TURN)
	var p := get_partner()
	if p != null:
		p._apply_pose(data)
	else:
		_partner_pose = data


func _apply_pose(data: Dictionary) -> void:
	var pos: Array = data.get("position", [])
	var rot: Array = data.get("rotation", [])
	if pos.size() == 3:
		global_position = Vector3(pos[0], pos[1], pos[2])
	if rot.size() == 3:
		global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	knob_angle = clampf(float(data.get("knob", 0.0)), -KNOB_HALF_TURN, KNOB_HALF_TURN)


func _exit_tree() -> void:
	super._exit_tree()
	# The partner goes with the lead: it is part of it.
	if not is_partner and is_instance_valid(_partner) and not _partner.is_queued_for_deletion():
		_partner.queue_free()


## The partner's cord ends in the lead's plug, so the partner has no plug of its
## own to seat: its rope's far end is the lead's.
func _add_cable_to_scene() -> void:
	if not is_partner:
		super._add_cable_to_scene()
		return
	if not is_instance_valid(_lead):
		return
	var lead_plug := _lead.get_plug()
	if lead_plug == null:
		call_deferred("_add_cable_to_scene")
		return
	# Its plug is let go of before the cord enters the room, where it would
	# start hooking itself up to hands.
	var own := _cable_instance.get_node_or_null("ControllerPlug")
	if own != null:
		_cable_instance.remove_child(own)
		own.free()
	get_tree().current_scene.add_child(_cable_instance)
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_rope.start_node = _cable_attach_point
	_cable_rope.end_node = lead_plug
	_cable_rope.end_anchor_offset = lead_plug.cable_anchor
	_resize_cable()
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length


func _physics_process(delta: float) -> void:
	if not is_partner:
		super._physics_process(delta)


func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	if get_partner() != null:
		_partner.reload_bindings()


func on_unplugged() -> void:
	# The last frame each port had stays in the core: centre the knobs' ports
	# and let go of fire before the lead forgets where it was.
	if _has_input_target():
		_deliver_joypad({"btn": 0, "alx": _knob_axis(), "aly": 0, "arx": 0, "ary": 0})
	super.on_unplugged()
	if get_partner() != null:
		_partner.reload_bindings()


# ── Where the input goes ──────────────────────────────────────────────────────

## The libretro port this paddle drives: two per console jack.
func _lib_port() -> int:
	if is_partner:
		return _lead._port_index * 2 + 1 if is_instance_valid(_lead) and _lead._port_index >= 0 else -1
	return _port_index * 2 if _port_index >= 0 else -1


func _has_input_target() -> bool:
	if is_partner:
		return is_instance_valid(_lead) and _lead._has_input_target()
	return super._has_input_target()


func _input_system() -> RetroSystem:
	if is_partner:
		return _lead._input_system() if is_instance_valid(_lead) else null
	return super._input_system()


func _deliver_joypad(pad: Dictionary) -> void:
	var system := _input_system()
	var port := _lib_port()
	if system == null or port < 0:
		return
	pad = system.filter_port_input(port, pad)
	last_sent = {"port": port, "pad": pad}
	if NetworkManager.netplay_route(system, port, pad):
		return
	system.get_libretro_node().SetJoypadState(port,
		pad["btn"], pad["alx"], pad["aly"], pad["arx"], pad["ary"])


# ── The knob ──────────────────────────────────────────────────────────────────

## The hand's stick or the D-pad turns the knob; what the core is sent is where it
## is, and whether any face button is down.
func _send_joypad(btn: int, alx: int, aly: int, arx: int, ary: int) -> void:
	var turn := float(alx) / ANALOG_SCALE
	if absf(turn) < STICK_DEAD:
		turn = float(arx) / ANALOG_SCALE
	if absf(turn) < STICK_DEAD:
		turn = (1.0 if btn & DPAD_RIGHT else 0.0) - (1.0 if btn & DPAD_LEFT else 0.0)
	if absf(turn) >= STICK_DEAD:
		knob_angle = clampf(knob_angle + turn * KNOB_RATE * get_process_delta_time(),
			-KNOB_HALF_TURN, KNOB_HALF_TURN)
	var fire := (1 << FIRE_BIT) if btn & FIRE_MASK else 0
	super._send_joypad(fire, _knob_axis(), 0, 0, 0)


## Clockwise is to the right, as a paddle game reads it.
func _knob_axis() -> int:
	return int(round(knob_angle / KNOB_HALF_TURN * ANALOG_SCALE))


func _animate(delta: float) -> void:
	super._animate(delta)
	if _knob != null:
		_knob.basis = _knob_rest * Basis(Vector3.UP, -knob_angle)
