## ArcadeDrumstick — a bachi: one of a Taiko no Tatsujin drummer's pair, wired to the cabinet (ArcadeHeldGear), lying in a cradle each side of the drum and taken out in a hand.
##
## A drum has four zones, MAME's BUTTON1 to BUTTON4 (namco/namcos10.cpp `taiko`: "P1R Rim", "P1R Surface", "P1L Surface", "P1L Rim"): the left and right half of the FACE (a don, red) and the left
## and right half of the RIM (a ka, blue). The cabinet builds them as sectors of a ring (ArcadeInstruments._taiko, the `sector` meta of each `Btn<n>`), and a hit is a tap of that button's pad bit
## (ArcadeInput.tap_pad_bit), so the game, the panel's cap that sinks and netplay all see it as they see a finger on it.
##
## HOW A HIT IS MADE, by whatever the player has in their hand:
##   VR, swung   the TIP crosses the face of a sector going down, fast enough (HIT_SPEED), where the sector is: the zone it lands in is the hit, as on a real drum. A tip resting on the drum, or lifted
##               and coming down gently, hits nothing; it has to come back above the drum (REARM_HEIGHT) to hit again.
##   VR, pressed the hand's TRIGGER (or B / Y) hits the FACE (a don) and A / X the RIM (a ka), on the drum's half that is the hand's own side: a left controller hits the left half.
##   desktop     the mouse: LEFT click a don (red), RIGHT click a ka (blue), the two sticks taking turns so a roll alternates hands. Taking one stick brings the other (DesktopPickup's companion).
##               A first pad plays it through the same events: its right trigger is the left button, its left trigger the middle one, which is a ka too.
## Every number here is an estimate: nothing has been swung in a headset.
class_name ArcadeDrumstick
extends ArcadeHeldGear

## The cord leaves the stick's butt, and a hit is measured at its head's end, both in the stick's own frame (-Z along it toward the head). The scene is baked to these numbers (Tools/gen/gen_arcade_drumstick.gd).
const CORD_BOSS := Vector3(0.0, 0.0, 0.092)
const TIP := Vector3(0.0, 0.0, -0.232)
## A head coming down on the face at no less than this (m/s, along the face's normal) is a hit; a lighter touch is not.
const HIT_SPEED := 0.45
## After a hit the head must rise this far (m) over the face it struck before it can hit again.
const REARM_HEIGHT := 0.012
## How long a hit holds its button (seconds): a few frames, so every core sees it, short enough for a roll of sixteen to a second (a Taiko roll is about that fast).
const TAP_SECONDS := 0.07
## The analog trigger, latched with a gap.
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.4
## The swing a click animates on the desktop (radians) and its duration (seconds).
const SWING_ANGLE := 0.55
const SWING_SECONDS := 0.12

const DON := &"don"
const KA := &"ka"

## A hit was made: the zone's name ("FaceLeft"...), the kind (DON or KA), and the drum's half (0 left, 1 right).
signal struck(zone: String, kind: StringName, hit_side: int)

## The ring on the stick and the swing pivot (the whole stick but the body), found by name.
var _swing: Node3D = null
var _swing_t := 1.0

## The last place the head was, to see it cross a face between two frames.
var _tip_prev := Vector3.ZERO
var _has_prev := false
## The cap just struck by the head and not yet left (it must rise REARM_HEIGHT over it).
var _struck_cap: MeshInstance3D = null
var _trigger_down := false
var _a_down := false
var _b_down := false

## The desktop's hand: which stick is the leader (the first the desktop took, it reads the mouse for both) and whose turn it is.
static var _leader: ArcadeDrumstick = null
var _turn := 0


func _ready() -> void:
	super._ready()
	_swing = get_node_or_null("Swing") as Node3D
	set_rows(_rows())


func _exit_tree() -> void:
	if _leader == self:
		_leader = null
	super._exit_tree()


## What the hint over a held stick says (HeldHint rows: [id, platform, glyphs, caption]).
func _rows() -> Array:
	return [
		[&"don_vr", HeldHint.PLATFORM_VR, ["quest_trigger_{side}_outline"], "Don (red): the face"],
		[&"ka_vr", HeldHint.PLATFORM_VR, ["quest_button_{ax}_outline"], "Ka (blue): the rim"],
		[&"swing_vr", HeldHint.PLATFORM_VR, ["quest_grip_{side}_outline"], "Hold, and swing it onto the drum"],
		[&"don_pc", HeldHint.PLATFORM_DESKTOP, ["mouse_left_outline"], "Don (red): the face"],
		[&"ka_pc", HeldHint.PLATFORM_DESKTOP, ["mouse_right_outline"], "Ka (blue): the rim"],
	]


# ── what the hands do ────────────────────────────────────────────────────────

func _on_let_go() -> void:
	_has_prev = false
	_struck_cap = null
	_trigger_down = false
	_a_down = false
	_b_down = false
	if _leader == self:
		# The other of the pair, if the desktop still has it, takes the mouse over.
		_leader = mate if is_instance_valid(mate) and mate.held_by_desktop() else null


func _on_taken_by_controller(_ctrl: XRController3D) -> void:
	_has_prev = false
	_struck_cap = null


func _tick(delta: float) -> void:
	_animate(delta)
	if not is_picked_up():
		return
	if held_by_desktop():
		if _leader == null or not is_instance_valid(_leader) or not _leader.held_by_desktop():
			_leader = self
		return
	var ctrl := holding_controller()
	if ctrl == null:
		return
	_read_buttons(ctrl)
	_read_swing(delta)


## The hand's trigger and thumb buttons: a don on the trigger or B / Y, a ka on A / X, on the hand's own side of the drum.
func _read_buttons(ctrl: XRController3D) -> void:
	var half := 0 if ctrl.tracker == &"left_hand" else 1
	var trigger := ctrl.get_float("trigger")
	if not _trigger_down and trigger >= TRIGGER_ON:
		_trigger_down = true
		strike(DON, half)
	elif _trigger_down and trigger < TRIGGER_OFF:
		_trigger_down = false
	var a_now := ctrl.is_button_pressed("ax_button")
	if a_now and not _a_down:
		strike(KA, half)
	_a_down = a_now
	var b_now := ctrl.is_button_pressed("by_button")
	if b_now and not _b_down:
		strike(DON, half)
	_b_down = b_now


## The head's path since the last frame against the drum's faces.
func _read_swing(delta: float) -> void:
	var tip := tip_position()
	if not _has_prev:
		_tip_prev = tip
		_has_prev = true
		return
	var zones := _zones()
	if _struck_cap != null:
		if not is_instance_valid(_struck_cap) or _height_over(_struck_cap, tip) > REARM_HEIGHT:
			_struck_cap = null
	if _struck_cap == null and delta > 0.0:
		var found := crossing(_tip_prev, tip, delta, zones)
		if not found.is_empty():
			_struck_cap = found["cap"] as MeshInstance3D
			_make_hit(found["zone"] as Dictionary)
	_tip_prev = tip


## The head's end, in the world.
func tip_position() -> Vector3:
	return global_transform * TIP


## How high `point` is over the face of `cap` (a drum's sector), along its normal.
static func _height_over(cap: MeshInstance3D, point: Vector3) -> float:
	var local := cap.global_transform.affine_inverse() * point
	return local.y - cap.mesh.get_aabb().end.y


## The hit, if the head went from `prev` to `tip` DOWN through the face of one of `zones` (what `zones_of` lists), at `delta` seconds, fast enough and where the sector is: `{zone, cap, speed}`, or {}.
## Pure, for the tests: the zone whose reading at the crossing is smallest wins (the face and the rim zones overlap by the margin a finger gets).
static func crossing(prev: Vector3, tip: Vector3, delta: float, zones: Array) -> Dictionary:
	var best := {}
	var best_reading := 1.0
	for zone: Dictionary in zones:
		var cap := zone["cap"] as MeshInstance3D
		if not is_instance_valid(cap) or not cap.is_visible_in_tree():
			continue
		var inverse := cap.global_transform.affine_inverse()
		var a := inverse * prev
		var b := inverse * tip
		var box := cap.mesh.get_aabb()
		var top := box.end.y
		if not (a.y > top and b.y <= top):
			continue
		var t := (a.y - top) / (a.y - b.y)
		var at := a.lerp(b, t)
		var speed := (prev - tip).dot(cap.global_basis.y.normalized()) / delta
		if speed < HIT_SPEED:
			continue
		var reading := ArcadePanelHands.sector_reading(at, box, cap.get_meta(&"sector", {}) as Dictionary, 1.0)
		if reading <= best_reading:
			best_reading = reading
			best = {"zone": zone, "cap": cap, "speed": speed}
	return best


# ── the drum ─────────────────────────────────────────────────────────────────

## The panel of this stick's player (the cabinet's `Player<n>`), or null.
func panel() -> ArcadeControlModule:
	if cabinet == null or not is_instance_valid(cabinet) or not cabinet.has_method("modules_of_kind"):
		return null
	for module: Variant in cabinet.call("modules_of_kind", ArcadeProfiles.KIND_STICK_BUTTONS):
		if is_instance_valid(module) and int((module as ArcadeControlModule).player) == player:
			return module as ArcadeControlModule
	return null


## The drum's zones on a panel: `{name: "FaceLeft", cap: the sector's mesh, index: its cap index, kind: DON or KA, half: 0 left / 1 right, bit: the pad id it presses}` for every sector the panel has.
static func zones_of(panel: ArcadeControlModule) -> Array:
	var out: Array = []
	if panel == null:
		return out
	for i in panel.cap_count():
		var cap := panel.cap_node(i) as MeshInstance3D
		if cap == null or not cap.has_meta(&"sector") or not cap.has_meta(&"part"):
			continue
		var zone_name := str(cap.get_meta(&"part"))
		var kind := DON if zone_name.begins_with("Face") else (KA if zone_name.begins_with("Rim") else &"")
		if kind == &"":
			continue
		out.append({"name": zone_name, "cap": cap, "index": i, "kind": kind, "half": 0 if zone_name.ends_with("Left") else 1, "bit": panel.cap_bit(i)})
	return out


func _zones() -> Array:
	return zones_of(panel())


## Hit the drum's `kind` (DON the face, KA the rim) on its `half` (0 left, 1 right): a tap of the zone's button. The one way every hit is made (a swing, a trigger, a click): false when the
## player has no such zone or the cabinet no input.
func strike(kind: StringName, half: int) -> bool:
	for zone: Dictionary in _zones():
		if zone["kind"] == kind and int(zone["half"]) == half:
			_make_hit(zone)
			return true
	return false


func _make_hit(zone: Dictionary) -> void:
	var input: ArcadeInput = cabinet.call("arcade_input") if cabinet != null and is_instance_valid(cabinet) and cabinet.has_method("arcade_input") else null
	if input != null:
		input.tap_pad_bit(player, int(zone["bit"]), TAP_SECONDS)
	_swing_t = 0.0
	var ctrl := holding_controller()
	if ctrl != null:
		Haptics.pulse(ctrl, 0.7, 30, &"arcade_drumstick")
	struck.emit(str(zone["name"]), zone["kind"] as StringName, int(zone["half"]))


# ── the desktop's mouse ──────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _leader != self or not held_by_desktop() or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.shift_pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		click(DON)
	elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
		# The middle button is a first pad's left trigger (DesktopPad makes the right one the left button): a pad has no right button, and plays the rim with it.
		click(KA)


## A mouse click with the sticks in the desktop's hands: the pair take turns, this one first, so a roll goes left, right, left. Which drum half is the stick's own.
func click(kind: StringName) -> bool:
	var stick: ArcadeDrumstick = self
	if _turn == 1 and is_instance_valid(mate) and mate is ArcadeDrumstick and mate.held_by_desktop():
		stick = mate as ArcadeDrumstick
	_turn = 1 - _turn
	return stick.strike(kind, stick.side)


# ── the stick swinging on the desktop ────────────────────────────────────────

func _animate(delta: float) -> void:
	if _swing == null or _swing_t >= 1.0:
		return
	_swing_t = minf(_swing_t + delta / SWING_SECONDS, 1.0)
	# Down and back: the head dips by SWING_ANGLE about the hand and returns.
	_swing.rotation.x = -SWING_ANGLE * sin(PI * _swing_t)
	if _swing_t >= 1.0:
		_swing.rotation.x = 0.0
