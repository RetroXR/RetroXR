## DoorPushBar — a VRDoor's crash bar (panic bar): a long bar across the push face of
## the leaf that a hand or a fingertip pushes IN, which draws the latch, and which a
## spring brings back out when let go. VRSpringReturnSlider is exactly that switch
## (the PSP's power slide): a momentary push that springs home and reports an INTENT
## once per push past `active_threshold` (toggle_requested), with no hold needed here.
##
## What it adds is the push. A slider's touch mode answers within a few cm of its
## middle, and a bar is 76 cm long: here any free fingertip ON THE BAR'S FACE, along
## its whole length, presses it, and the bar sits as deep as the tip is (VRDrawer's
## face push, turned to push in). A hand drawing back past the face, or sliding off
## an end, lets go of it.
##
## The node sits at the bar's middle with the bar OUT (value 0), its +Z into the door
## (the way it is pushed), X along the bar. The child BoxShape3D is the bar's face
## and footprint; the bar mesh is the `KnobMesh` child, or one handed over with
## set_knob_mesh() (a model's own bar). A pointer press is `pointer_pressed`: at a
## desk or with a laser it opens or shuts the door, as a knob's does.
class_name DoorPushBar
extends VRSpringReturnSlider

## A pointer (desktop reticle / VR laser) pressed the bar.
signal pointer_pressed

## A fingertip off the face by this much still counts as on it (m): taking hold is not
## a millimetre game, and a hand pushing a bar rests on it rather than touching it.
const FACE_SLACK := 0.008
## Backing off the face by more than this lets go (m).
const RELEASE_SLACK := 0.012
## Grown round the bar's footprint, across and along (m).
const FOOTPRINT_MARGIN := 0.02


func _init() -> void:
	super._init()
	axis_local = Vector3(0, 0, 1)
	travel = 0.025
	steps = 0
	require_trigger = false
	on_hold_sec = 0.0
	off_hold_sec = 0.0
	active_threshold = 0.6
	return_speed = 6.0


func _ready() -> void:
	super._ready()
	# VRSlider anchors an authored KnobMesh at mid-travel; the bar is modelled OUT,
	# which is value 0.
	if _knob != null:
		_anchor_knob(Transform3D(_knob.basis, _knob.position), 0.0)
		_update_knob()


## The controller pushing it now, or null.
func pushing_ctrl() -> XRController3D:
	return _engaged_ctrl if is_instance_valid(_engaged_ctrl) else null


func is_pushed() -> bool:
	return pushing_ctrl() != null or _pointer_engaged


## A fingertip at the bar, close enough to be about to push it (the door's leaf
## leaves such a hand to the bar).
func in_reach(world_pos: Vector3) -> bool:
	var half := _half_extents()
	var p := to_local(world_pos)
	return absf(p.x) <= half.x + FOOTPRINT_MARGIN and absf(p.y) <= half.y + FOOTPRINT_MARGIN \
		and p.z >= -half.z - 0.04 and p.z <= half.z + travel


## Value 0 is the bar out, where it is modelled; 1 is pushed `travel` in.
func _raw_value_at(world_pos: Vector3) -> float:
	if travel <= 0.0:
		return value
	return to_local(world_pos).dot(axis_local.normalized()) / travel


## The face push. A free fingertip in the bar's footprint and at its face presses it
## as deep as the tip goes; the base class's spring takes over once nothing does.
func _process_touch_mode(_delta: float) -> void:
	var half := _half_extents()
	if _engaged_ctrl != null:
		if not _qualified(_engaged_ctrl):
			_let_go("hand gone")
			return
		var p := to_local(PokeTip.tip_of(_engaged_ctrl))
		if absf(p.x) > half.x + FOOTPRINT_MARGIN or absf(p.y) > half.y + FOOTPRINT_MARGIN:
			_let_go("slid off the bar")
			return
		if p.z < -half.z - RELEASE_SLACK:
			_let_go("drew back")
			return
		last_input = "hand"
		_set_from_raw((p.z + half.z) / travel if travel > 0.0 else 0.0)
		return
	for ctrl in _controllers:
		if not _qualified(ctrl):
			continue
		var p := to_local(PokeTip.tip_of(ctrl))
		if absf(p.x) > half.x + FOOTPRINT_MARGIN or absf(p.y) > half.y + FOOTPRINT_MARGIN:
			continue
		# At the face, or already in it (a hand arriving fast), but not behind the bar.
		if p.z >= -half.z - FACE_SLACK and p.z <= half.z + travel:
			_engaged_ctrl = ctrl
			_lost = 0.0
			Haptics.click(ctrl, true, &"door_push_bar")
			return


func _let_go(why: String) -> void:
	if _engaged_ctrl != null and value > 0.05:
		print("[Door] push bar %s let go at %.2f: %s" % [name, value, why])
	_engaged_ctrl = null


## The bar's half size in this node's frame, from its box (the face is -Z).
func _half_extents() -> Vector3:
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			return (cs.shape as BoxShape3D).size * 0.5
	return Vector3(0.38, 0.03, 0.0175)


func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.PRESSED:
			PokeWake.wake(self)
			pointer_pressed.emit()
		XRToolsPointerEvent.Type.MOVED, XRToolsPointerEvent.Type.RELEASED:
			pass
		_:
			super.pointer_event(event)
