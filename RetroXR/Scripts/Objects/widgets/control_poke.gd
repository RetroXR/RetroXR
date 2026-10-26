## ControlPoke — a pad's or handheld's own controls, pressed with a fingertip.
##
## A pad or handheld animates its caps FROM its input state (ControlAnimator and
## the detailed handhelds' own passes), so the caps were only ever read, never
## touched. This turns that round: each cap is a target, a PokeTip inside it
## presses it, and the owner ORs the result into the state it sends. The core,
## netplay and the cap's own animation all see a poke exactly as they see a
## mapped controller button, because by then it IS one.
##
## Not a VRButton per cap. A VRButton fires a signal; a pad button is a HELD bit
## the core polls every frame, and a pad has a dozen of them on caps a few
## millimetres apart that already have an animator moving them. One hit test per
## owner, against the caps the animator binds, keeps the two from disagreeing
## about where a cap is.
##
## Targets (dictionaries; the builders below fill them):
##   button : node, rest, dir, bit? | mask? | stick_dir? (+ stick), depth?, src?
##            With "src" (an animator's own entry) the input keys are read from
##            that instead, live.
##            A target with no bit, mask or stick is a cap with no input behind
##            it (a Home key): ControlPoke presses it itself, by depth along dir.
##   rocker : node, rest, dir, pivot, up, right, bits [up, down, left, right]
## Every vector is in the node's PARENT frame, as the animators keep them.
class_name ControlPoke
extends RefCounted

## Reach past a cap's faces that starts a press, and the larger reach that keeps
## one going (hysteresis, so a millimetre of tremor at the edge does not chatter).
## Tight: caps on a pad sit 3-5 mm apart, and a press must land on the one under
## the fingertip, not its neighbour.
const ENGAGE_MARGIN := 0.002
const RELEASE_MARGIN := 0.006
## How far INTO the shell a press, once started, still holds. A tracked fingertip
## has no shell to stop it, and a press that let go as the tip sank past the cap
## would release on exactly the push meant to hold it down.
const DEPTH_REACH := 0.02
## Where the contact disc starts snapping to a cap's face. Visual only.
const CONTACT_MARGIN := 0.01
## Seconds a press survives the tip outside the release box, to ride out a
## dropped tracking frame. See PokeTip.CONTACT_GRACE.
const GRACE := 0.05
## Nothing is tested unless a fingertip is this close to the owner's origin.
## Larger than any handheld's half-diagonal.
const NEAR := 0.35
## A rocker's centre presses nothing, as a real cross's pivot does not: inside
## this fraction of its radius the tip is on the pivot, not an arm.
const ROCKER_DEAD := 0.2
## sin(22.5°): the eight 45° sectors of a rocker, so a tip between two arms
## presses both (a diagonal), as a thumb on the corner of a real cross does.
const ROCKER_SECTOR := 0.383
const VISUAL_LERP := 20.0
const HAPTIC_KEY := &"control_poke"

const _DEFAULT_ROCKER_BITS := [ControllerBindings.JOYPAD_UP, ControllerBindings.JOYPAD_DOWN,
	ControllerBindings.JOYPAD_LEFT, ControllerBindings.JOYPAD_RIGHT]

var targets: Array[Dictionary] = []

var _owner: Node3D = null
var _controllers: Array[Node3D] = []
var _rig_retry := 0
var _frame := -1
var _state := {"btn": 0, "lstick": Vector2.ZERO, "rstick": Vector2.ZERO}


func _init(owner: Node3D) -> void:
	_owner = owner


# ── Builders ────────────────────────────────────────────────────────────────

## A cap pressed along `dir` (its parent frame) that sets `bit`. Pass bit = -1
## with `extra` {"depth": ..} for a cap with no input behind it, which ControlPoke
## then moves itself.
static func button(node: Node3D, bit: int, dir: Vector3, extra: Dictionary = {}) -> Dictionary:
	var entry := {"node": node, "rest": node.transform, "dir": dir}
	if bit >= 0:
		entry["bit"] = bit
	entry.merge(extra)
	return entry


## A cross rocked about `pivot`. `turn_up` / `turn_right` are the axes the owner's
## animator turns it about (sign included) for UP and RIGHT; the arm a turn sinks
## is the one it drives along `dir`, which is dir x turn. Deriving the arms that
## way, rather than restating them, keeps every model's own rotation convention
## the single source of which arm is which.
static func rocker(node: Node3D, rest: Transform3D, pivot: Vector3, dir: Vector3,
		turn_up: Vector3, turn_right: Vector3, bits: Array = _DEFAULT_ROCKER_BITS) -> Dictionary:
	return {"node": node, "rest": rest, "dir": dir, "pivot": pivot, "rocker": true,
		"up": dir.cross(turn_up).normalized(), "right": dir.cross(turn_right).normalized(),
		"bits": bits}


## Every control a ControlAnimator binds. Its rockers turn by Basis.from_euler
## (pitch about X, roll about Z) where pitch is UP-minus-DOWN times
## dpad_pitch_sign and roll is LEFT-minus-RIGHT, so RIGHT turns about -Z. Sticks
## are left out: a thumbstick is pushed, not pressed.
func add_animator(anim: ControlAnimator) -> void:
	for e: Dictionary in anim.buttons:
		var node: Node3D = e["node"]
		if node == null:
			continue
		# The animator's own entry rides along as "src" and is read every frame,
		# not copied: a pad may rebind a cap while it runs (the Saturn pads give C
		# and Z whichever bits the plugged-in core reads them from).
		targets.append({"node": node, "rest": e["rest"], "dir": e.get("dir", anim.press_dir),
			"src": e})
	for pad: Dictionary in [anim.dpad, anim.dpad2]:
		if pad.is_empty() or pad.get("node") == null:
			continue
		targets.append(rocker(pad["node"], pad["rest"], pad["pivot"], anim.press_dir,
			Vector3.RIGHT * anim.dpad_pitch_sign, Vector3.FORWARD,
			pad.get("bits", _DEFAULT_ROCKER_BITS)))


# ── Polling ─────────────────────────────────────────────────────────────────

## This frame's poked state: {btn, lstick, rstick}, sticks in the core's sense
## (y positive DOWN). Cached per process frame, so the animation pass and the
## input pass can both ask.
func poll() -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame == _frame:
		return _state
	_frame = frame
	var delta := _owner.get_process_delta_time() if is_instance_valid(_owner) else 0.0
	# Switched off in Options: no hand qualifies, so every press in flight lets go
	# this frame exactly as if the hand had walked away.
	var live: Array[Node3D] = []
	if AppPrefs.poke_controls:
		live = _live_controllers()
	var btn := 0
	var lstick := Vector2.ZERO
	var rstick := Vector2.ZERO
	for cap: Dictionary in targets:
		var node: Node3D = cap["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var held := _track(cap, live, delta)
		if cap.has("rocker"):
			if not held.is_empty():
				btn |= _rocker_bits(cap, held.keys()[0])
			continue
		var down := not held.is_empty()
		var src: Dictionary = cap.get("src", cap)
		# A cap the core reads as a stick is pressed as that stick even when it
		# also carries a bit: the N64's C-Left/C-Right bits are the shoulders'.
		if src.has("stick_dir"):
			if down:
				if src.get("stick", "right") == "left":
					lstick += src["stick_dir"]
				else:
					rstick += src["stick_dir"]
		elif src.has("mask"):
			if down:
				btn |= int(src["mask"])
		elif int(src.get("bit", -1)) >= 0:
			if down:
				btn |= 1 << int(src["bit"])
		elif cap.has("depth"):
			_press_visual(cap, down, delta)
	_state = {"btn": btn, "lstick": lstick.limit_length(1.0), "rstick": rstick.limit_length(1.0)}
	return _state


## Merge this frame's poke into an input state as the owners send it: buttons OR,
## and a poked stick replaces the analog value it pushes (scaled to `scale`).
func merge_into(btn: int, alx: int, aly: int, arx: int, ary: int, scale: int) -> Dictionary:
	var s := poll()
	var out := {"btn": btn | int(s["btn"]), "alx": alx, "aly": aly, "arx": arx, "ary": ary}
	var l: Vector2 = s["lstick"]
	var r: Vector2 = s["rstick"]
	if l != Vector2.ZERO:
		out["alx"] = int(l.x * scale)
		out["aly"] = int(l.y * scale)
	if r != Vector2.ZERO:
		out["arx"] = int(r.x * scale)
		out["ary"] = int(r.y * scale)
	return out


## Update which hands are pressing `cap`; returns its {controller: seconds lost}.
func _track(cap: Dictionary, live: Array[Node3D], delta: float) -> Dictionary:
	var held: Dictionary = cap.get("_held", {})
	cap["_held"] = held
	if not cap.has("_box"):
		cap["_box"] = _local_box(cap["node"])
	var box: AABB = cap["_box"]
	if box.size == Vector3.ZERO:
		return held
	var node: Node3D = cap["node"]
	var rest: Transform3D = cap["rest"]
	var parent := node.get_parent() as Node3D
	var xf: Transform3D = (parent.global_transform if parent != null else Transform3D()) * rest
	var inv := xf.affine_inverse()
	var dir_local: Vector3 = rest.basis.inverse() * (cap["dir"] as Vector3)
	var dir_world := xf.basis * dir_local
	var reach := dir_local * (DEPTH_REACH / maxf(dir_world.length(), 1e-6))
	var scale := xf.basis.get_scale()
	var mesh := _contact_mesh(node)

	# A hand that stopped qualifying (picked something up, lost tracking, moved
	# away from the whole device) lets go at once: grace is for a tip that slipped
	# off a cap, not one that walked away.
	for hand: Variant in held.keys():
		if not is_instance_valid(hand) or not live.has(hand):
			held.erase(hand)
			_click(hand, false)

	for hand: Node3D in live:
		var tip := PokeTip.tip_of(hand)
		var p := inv * tip
		var was := held.has(hand)
		# The reach into the shell only KEEPS a press: a cap is pressed by touching
		# it, so a tip that arrives under it from the side (pushing a neighbouring
		# face cap in, past a shoulder's edge) starts nothing.
		if _inside(box, p, RELEASE_MARGIN if was else ENGAGE_MARGIN, scale,
				reach if was else Vector3.ZERO):
			held[hand] = 0.0
			if not was:
				_click(hand, true)
		elif was:
			held[hand] = float(held[hand]) + delta
			if float(held[hand]) >= GRACE:
				held.erase(hand)
				_click(hand, false)
		if mesh != null and _inside(box, p, CONTACT_MARGIN, scale, Vector3.ZERO):
			PokeTip.claim_box_face(hand, mesh, tip, -dir_world.normalized(),
				PokeTip.CONTACT_ENGAGED if held.has(hand) else PokeTip.CONTACT_HOVER)
	return held


## `p` inside `box` grown by `margin` METRES on every side (the node may carry
## scale, so the margin is divided through it per axis) and stretched by `reach`
## into the shell.
static func _inside(box: AABB, p: Vector3, margin: float, scale: Vector3, reach: Vector3) -> bool:
	var m := Vector3(margin / maxf(scale.x, 1e-6), margin / maxf(scale.y, 1e-6),
		margin / maxf(scale.z, 1e-6))
	var b := AABB(box.position - m, box.size + m * 2.0)
	if reach != Vector3.ZERO:
		b = b.merge(AABB(b.position + reach, b.size))
	return b.has_point(p)


## Which arms of a rocker the tip of `hand` is on.
func _rocker_bits(cap: Dictionary, hand: Node3D) -> int:
	var node: Node3D = cap["node"]
	var parent := node.get_parent() as Node3D
	var pxf := parent.global_transform if parent != null else Transform3D()
	var up := (pxf.basis * (cap["up"] as Vector3)).normalized()
	var right := (pxf.basis * (cap["right"] as Vector3)).normalized()
	var d := PokeTip.tip_of(hand) - pxf * (cap["pivot"] as Vector3)
	var v := Vector2(d.dot(right), d.dot(up))
	if not cap.has("_radius"):
		cap["_radius"] = _rocker_radius(cap, pxf, up, right)
	if v.length() < float(cap["_radius"]) * ROCKER_DEAD:
		return 0
	var n := v.normalized()
	var bits: Array = cap.get("bits", _DEFAULT_ROCKER_BITS)
	var out := 0
	if n.y > ROCKER_SECTOR: out |= 1 << int(bits[0])
	if n.y < -ROCKER_SECTOR: out |= 1 << int(bits[1])
	if n.x < -ROCKER_SECTOR: out |= 1 << int(bits[2])
	if n.x > ROCKER_SECTOR: out |= 1 << int(bits[3])
	return out


## How far the cross reaches from its pivot across its face, in metres.
func _rocker_radius(cap: Dictionary, pxf: Transform3D, up: Vector3, right: Vector3) -> float:
	var box: AABB = cap["_box"]
	var xf: Transform3D = pxf * (cap["rest"] as Transform3D)
	var centre := pxf * (cap["pivot"] as Vector3)
	var r := 0.0
	for i in 8:
		var d := xf * box.get_endpoint(i) - centre
		r = maxf(r, maxf(absf(d.dot(up)), absf(d.dot(right))))
	return maxf(r, 0.001)


## A cap with nothing behind it: move it here, the way the animators move theirs.
func _press_visual(cap: Dictionary, down: bool, delta: float) -> void:
	var node: Node3D = cap["node"]
	var rest: Transform3D = cap["rest"]
	var target := Transform3D(rest.basis,
		rest.origin + (cap["dir"] as Vector3).normalized() * (float(cap["depth"]) * (1.0 if down else 0.0)))
	node.transform = node.transform.interpolate_with(target, clampf(VISUAL_LERP * delta, 0.0, 1.0))


## The hands that may poke this frame: active, and not holding anything (the hand
## gripping a handheld must not press its caps by being wrapped round them).
## Empty when no fingertip is near enough to matter.
func _live_controllers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_instance_valid(_owner) or not _owner.is_inside_tree():
		return out
	if _controllers.is_empty():
		# The rig may not exist yet (or ever, in a suite): look again a second on.
		if _rig_retry > 0:
			_rig_retry -= 1
			return out
		_rig_retry = 60
		var rig := PadInputShared.find_rig(_owner.get_tree())
		for k: String in ["left", "right"]:
			var hand := rig.get(k) as XRController3D
			if hand != null:
				_controllers.append(hand)
	var pos := _owner.global_position
	for hand: Node3D in _controllers:
		if not is_instance_valid(hand) or not PokeTip.is_poking(hand):
			continue
		if hand is XRController3D and not (hand as XRController3D).get_is_active():
			continue
		if PokeTip.tip_of(hand).distance_to(pos) <= NEAR:
			out.append(hand)
	return out


## Point the hit test at these hands instead of the player's rig. A suite or a
## probe has no rig and no tracking, so a hand here may be any Node3D carrying a
## "PokeTip" child (PokeTip.tip_of reads it; with no FunctionPickup it pokes).
func set_controllers(controllers: Array[Node3D]) -> void:
	_controllers = controllers
	_frame = -1


## Forget this frame's answer, so a suite can move a hand and ask again without
## waiting a frame. PokeTip keeps its own per-frame cache: move hands by a frame.
func invalidate() -> void:
	_frame = -1


static func _click(hand: Variant, down: bool) -> void:
	if hand is XRController3D and is_instance_valid(hand):
		Haptics.click(hand, down, HAPTIC_KEY)


## The cap's extent in its own frame. A control may be an empty carrying several
## meshes (a VMU's d-pad), so the box is every mesh under it, in the node's frame.
static func _local_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = [node] if node is MeshInstance3D else []
	meshes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	var inv := node.global_transform.affine_inverse()
	for m: MeshInstance3D in meshes:
		if m.mesh == null:
			continue
		var b: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The mesh the contact disc lands on: the cap itself, or the first one under it.
static func _contact_mesh(node: Node3D) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if m.mesh != null:
			return m
	return null
