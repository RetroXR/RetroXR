class_name CapsenseHand
extends XRNode3D

## Runtime hand geometry and joints paired with one physical controller. Meta's
## simultaneous-hands-and-controllers extension supplies controller-inferred
## Capsense joints while the Touch controller is held, and unobstructed camera
## joints when it is put down. The display preference decides which geometry is
## shown; unavailable joints or mesh always fall back to controller art.

@export var controller_path: NodePath
@export_enum("Left", "Right") var hand: int = 0

const POSITION_VALID := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID
const INDEX_TIP := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
const PALM := XRHandTracker.HAND_JOINT_PALM

var _controller: XRController3D = null
var _mesh: Node = null
var _mesh_ready_override: Variant = null
var _last_motion_range := -1
## Drawn from the controller's touch sensors while no joints arrive.
var _touch: TouchHandScript = null
var _no_hand_time := 0.0
## What this hand last drew from, for the log: "" until it draws anything.
var _logged_kind := ""

## Joints missing this long before the touch hand stands in, so a dropped frame
## of tracking doesn't flash it.
const TOUCH_HAND_DELAY := 0.3
const TouchHandScript := preload("res://Scripts/XR/touch_hand.gd")


func _ready() -> void:
	# This script owns visibility: XRNode3D's built-in tracking visibility is
	# updated from pose_changed and can turn the hand back on after our _process
	# hides it while holding an object, producing a one-frame grip flash.
	show_when_tracked = false
	_controller = get_node_or_null(controller_path) as XRController3D
	_mesh = get_node_or_null("OpenXRFbHandTrackingMesh")
	if _controller != null and _controller.has_method("register_capsense_hand"):
		_controller.call("register_capsense_hand", self)
	if _controller != null:
		_touch = TouchHandScript.new()
		_touch.name = "TouchHand"
		_touch.hand = hand
		_touch.controller = _controller
		_controller.add_child.call_deferred(_touch)
	apply_display_mode()


func _process(delta: float) -> void:
	_no_hand_time = 0.0 if is_hand_available() else _no_hand_time + delta
	apply_display_mode()


func hand_tracker() -> XRHandTracker:
	return XRServer.get_tracker(tracker) as XRHandTracker


func hand_source() -> int:
	var ht := hand_tracker()
	return ht.hand_tracking_source if ht != null \
		else XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED


func joints_valid() -> bool:
	var ht := hand_tracker()
	if ht == null or not ht.has_tracking_data:
		return false
	return _joint_position_valid(ht, PALM) and _joint_position_valid(ht, INDEX_TIP)


func mesh_ready() -> bool:
	if _mesh_ready_override != null:
		return bool(_mesh_ready_override)
	if _mesh == null or not _mesh.has_method("get_mesh_instance"):
		return false
	var mi := _mesh.call("get_mesh_instance") as MeshInstance3D
	return mi != null and mi.mesh != null


func is_hand_available() -> bool:
	return joints_valid() and mesh_ready()


## Current index tip in world space, queried directly from XRHandTracker. The
## joint transforms share tracking space; making the tip relative to the palm
## and composing it through this XRNode3D also carries the origin's reference
## frame and world-scale handling.
func index_tip_position() -> Variant:
	if ControllerArt.display_mode() == AppPrefs.XRDisplayMode.CONTROLLERS:
		return null
	var ht := hand_tracker()
	if ht == null or not ht.has_tracking_data \
			or not _joint_position_valid(ht, PALM) \
			or not _joint_position_valid(ht, INDEX_TIP):
		return _touch.index_tip() if is_instance_valid(_touch) else null
	var palm: Transform3D = ht.get_hand_joint_transform(PALM)
	var tip: Transform3D = ht.get_hand_joint_transform(INDEX_TIP)
	return global_transform * (palm.affine_inverse() * tip).origin


## Surface target for the post-tracking finger modifier. Only the rendered
## skeleton consumes this; PokeTip.tip_of() continues to expose the raw joint.
func visual_contact_target() -> Variant:
	var contact := visual_contact()
	return contact.get("point") if not contact.is_empty() else null


func visual_contact() -> Dictionary:
	if not visible or _controller == null or not PokeTip.is_poking(_controller):
		return {}
	var poke := _controller.get_node_or_null("PokeTip") as PokeTip
	return poke.visual_contact() if poke != null else {}


## OpenXR reports a spherical radius for every hand joint. The index-tip radius
## is the distance from its joint centre to the skin that should meet a surface.
## Some runtimes leave it at zero; 6 mm is a conservative fingertip fallback.
func index_tip_radius() -> float:
	var ht := hand_tracker()
	if ht == null:
		return 0.006
	return maxf(ht.get_hand_joint_radius(INDEX_TIP), 0.006)


func apply_display_mode() -> void:
	var mode: int = ControllerArt.display_mode()
	var source := hand_source()
	var available := is_hand_available()
	var holding := _controller != null and not PokeTip.is_poking(_controller)
	var show_hand := available and mode != AppPrefs.XRDisplayMode.CONTROLLERS and not holding
	visible = show_hand
	var touch := not available and _touch_hand_ready()
	if _touch != null:
		_touch.visible = touch and mode != AppPrefs.XRDisplayMode.CONTROLLERS and not holding
	_log_kind(available, touch, source)

	# A controller-sourced hand wraps its visible controller in BOTH mode. An
	# unobstructed camera hand has no controller at that pose, so it takes over.
	var show_controller := mode == AppPrefs.XRDisplayMode.CONTROLLERS or not available
	if mode == AppPrefs.XRDisplayMode.BOTH and available:
		show_controller = source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	elif mode == AppPrefs.XRDisplayMode.HANDS and touch:
		show_controller = false
	if _controller != null and _controller.has_method("set_display_visible"):
		_controller.call("set_display_visible", show_controller)

	var wanted_range := OpenXRInterface.HAND_MOTION_RANGE_CONFORM_TO_CONTROLLER
	if mode == AppPrefs.XRDisplayMode.HANDS \
			or source == XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED:
		wanted_range = OpenXRInterface.HAND_MOTION_RANGE_UNOBSTRUCTED
	_set_motion_range(wanted_range)


## One line whenever the hand's source changes (holding something doesn't count).
func _log_kind(available: bool, touch: bool, source: int) -> void:
	var kind := "none"
	if available:
		kind = "runtime hand, %s" % ("from the controller"
			if source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER else "camera-tracked")
	elif touch:
		kind = "touch-sensor hand (no hand joints from the runtime)"
	if kind == _logged_kind or (_logged_kind == "" and kind == "none"):
		return
	_logged_kind = kind
	print("[Hands] %s: %s" % ["left" if hand == 0 else "right", kind])


func _touch_hand_ready() -> bool:
	return is_instance_valid(_touch) and _touch.is_inside_tree() \
		and _no_hand_time >= TOUCH_HAND_DELAY and _controller.get_has_tracking_data()


func touch_hand() -> TouchHandScript:
	return _touch


func active_motion_range() -> int:
	return _last_motion_range


func _set_motion_range(value: int) -> void:
	if value == _last_motion_range:
		return
	_last_motion_range = value
	var xri := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xri != null:
		xri.set_motion_range(hand, value as OpenXRInterface.HandMotionRange)


func _joint_position_valid(ht: XRHandTracker, joint: int) -> bool:
	return (ht.get_hand_joint_flags(joint) & POSITION_VALID) != 0


## Synthetic probes have no runtime mesh, but still need to exercise the exact
## visibility and joint paths. null restores the real readiness check.
func set_mesh_ready_override(value: Variant) -> void:
	_mesh_ready_override = value
