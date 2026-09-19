## PageGrab — pinch a page of an open book and drag it over.
##
## Interaction (VR + desktop), following the VRButton/VRHinge house pattern:
##   • HOVER — a controller's poke tip inside the zone, or the desktop reticle
##     over it, arms the grab and shows the book's page hint.
##   • HELD  — pull the TRIGGER to latch. The point of the page you were
##     touching is the point that follows your hand from then on, so a corner
##     gives a corner curl and a mid-edge grip gives a mid-edge fold. Once
##     latched the hand may roam anywhere; only releasing the trigger lets go.
##
## The trigger is deliberate: GRIP already means "pick up the whole book"
## (XRToolsPickable), so the two never fight over the same squeeze.
##
## The zone covers the outer part of a page rather than all of it. The Area3D is
## on the pointer layer, and InteractionResolver ranks a pointer-interactive
## area (250) above a pickable (100) — covering the whole page would leave the
## laser no way to pick the book up.
class_name PageGrab
extends Area3D

## Emitted when a hand latches onto the page. world_pos is the grip point.
signal grab_begin(dir: int, world_pos: Vector3)
## Emitted every frame while latched.
signal grab_move(world_pos: Vector3)
## Emitted when the hand lets go.
signal grab_end(dir: int)

const POINTABLE_LAYER := 1 << 20
## Analog trigger, read as a float like the rest of the project.
const TRIGGER_ACTION := "trigger"
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.4

## Which page this zone turns: +1 the forward (right) page, -1 the backward one.
@export var direction: int = 1

## Half-extents of the grab volume in this node's local space.
var reach: Vector3 = Vector3(0.05, 0.12, 0.03)

var _controllers: Array[XRController3D] = []
## Per-controller re-arm latch. Without it, sweeping a HELD trigger from one
## page zone to the other grabs the second page the instant the first is
## dropped.
var _rearmed: Dictionary = {}
var _ctrl: XRController3D = null
var _pointer_held := false
var _pointer_hover := false
## Off until the book has pages and a spread on this side to turn.
var _enabled := false


func _ready() -> void:
	collision_layer |= POINTABLE_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	_sync_shapes()
	await get_tree().process_frame
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)


## Turn the zone on/off — a book that is closed has no page to grab on one side,
## and a book still downloading has no pages at all.
func set_enabled(on: bool) -> void:
	if _enabled == on:
		return
	_enabled = on
	_sync_shapes()
	if not on:
		_release()


## A zone that is off must not be in the way either. Ignoring pointer_event is
## not enough: the shape still stops the ray, and this layer outranks everything,
## so a dead zone swallowed every click meant for whatever was behind it. A book
## whose file failed to open never reaches _layout_page_grabs(), which left both
## zones as BoxShape3D's default 1 m cube around the book, the things beside it
## and its own options panel.
func _sync_shapes() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", not _enabled)


func is_enabled() -> bool:
	return _enabled


func is_held() -> bool:
	return _ctrl != null or _pointer_held


## The controller latched onto this page, or null (desktop pointer, or nobody).
func held_by() -> XRController3D:
	return _ctrl


## True while a hand or the reticle is over the zone but not yet latched.
func is_hovering() -> bool:
	return _enabled and not is_held() and (_pointer_hover or _hovering_ctrl() != null)


func _process(_delta: float) -> void:
	if not _enabled:
		return

	for ctrl in _controllers:
		if ctrl != null and ctrl.get_float(TRIGGER_ACTION) < TRIGGER_OFF:
			_rearmed[ctrl.get_instance_id()] = true

	if _ctrl != null:
		# Latched. The hand is free to leave the page — only the trigger lets go.
		if not is_instance_valid(_ctrl) or not _ctrl.get_is_active() \
				or _ctrl.get_float(TRIGGER_ACTION) < TRIGGER_OFF:
			_release()
		else:
			grab_move.emit(PokeTip.tip_of(_ctrl))
		return

	if _pointer_held:
		return

	var ctrl := _hovering_ctrl()
	if ctrl == null or ctrl.get_float(TRIGGER_ACTION) <= TRIGGER_ON:
		return
	if not _rearmed.get(ctrl.get_instance_id(), false):
		return
	_rearmed[ctrl.get_instance_id()] = false
	_ctrl = ctrl
	grab_begin.emit(direction, PokeTip.tip_of(ctrl))


## Desktop reticle / VR laser. Same contract as VRButton and VRHinge: PRESSED
## latches, the latch survives the ray leaving the zone, and only RELEASED lets
## go — EXITED just clears the hover.
func pointer_event(event: XRToolsPointerEvent) -> void:
	if not _enabled:
		return
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_pointer_hover = true
		XRToolsPointerEvent.Type.PRESSED:
			if _ctrl == null:
				_pointer_held = true
				grab_begin.emit(direction, event.position)
		XRToolsPointerEvent.Type.MOVED:
			if _pointer_held:
				grab_move.emit(event.position)
		XRToolsPointerEvent.Type.RELEASED:
			if _pointer_held:
				_release()
		XRToolsPointerEvent.Type.EXITED:
			_pointer_hover = false


## First active, non-holding controller whose poke tip is inside the zone.
func _hovering_ctrl() -> XRController3D:
	for ctrl in _controllers:
		if ctrl == null or not ctrl.get_is_active() or not PokeTip.is_poking(ctrl):
			continue
		var local: Vector3 = to_local(PokeTip.tip_of(ctrl))
		if absf(local.x) <= reach.x and absf(local.y) <= reach.y and absf(local.z) <= reach.z:
			return ctrl
	return null


func _release() -> void:
	if _ctrl == null and not _pointer_held:
		return
	_ctrl = null
	_pointer_held = false
	grab_end.emit(direction)
