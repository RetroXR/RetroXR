## ArcadePanelGrip — a player's whole panel as ONE controller you attach to.
##
## The stick and the six buttons are not separate things to poke: aiming at the panel lights
## the WHOLE of it (player 1's or player 2's, whichever you aim at), the way aiming at a
## controller lights the controller, and the same press that would pick a controller up
## attaches you to it. You do not take it in your hand; you hold on to it. Press again, or
## switch the machine off, and you let go. While attached, your own controller (VR, a pad,
## the keyboard) plays that player.
##
## A pointable Area3D over the panel: a desktop click or the laser's trigger arrives as a
## pointer_event, and in VR a squeeze of the grip with a hand over the panel does the same.
## A hand that is working a control of the panel (ArcadePanelHands: it has taken hold of the stick, or
## is reaching for it) is pulling its trigger for THAT, so its laser's press is not taken as an attach.
class_name ArcadePanelGrip
extends Area3D

signal toggled(attached: bool)
## A momentary panel (`momentary`) is held while it is pressed.
signal held_changed(held: bool)

const POINTABLE_LAYER := 1 << 20
## A hand this close to the panel's centre, squeezing the grip, takes hold of it.
const REACH := 0.22
const GRIP_ON := 0.6
const GRIP_OFF := 0.4

## The lit area, width x height in the panel's own frame.
@export var panel_size := Vector2(0.285, 0.185)

## A ring in place of the rectangle (a steering wheel): the lit area is an annulus of this radius (the middle of the rim) and `ring_width`, in the panel's XY plane, so
## the hole stays open to the eye and to a laser. 0 is the rectangle.
@export var ring_radius := 0.0
@export var ring_width := 0.06

## In DESKTOP mode the pointable and lit area is this rectangle (the panel's frame, relative to the grip's own origin) instead of the whole panel: a mouse has no business taking hold of a drum, which sticks and
## fingers work. Empty is the whole panel; a headset always keeps the whole (its hands touch the drum, and a squeeze on the panel still attaches).
@export var desktop_rect := Rect2()

## A panel with nothing to take hold of (a gun cabinet's START buttons: the gun is the
## controller): a press does not attach anyone, it HOLDS the panel for as long as it lasts, and
## the cabinet reads that as START.
@export var momentary := false

var attached := false
## Whether a momentary panel is being pressed now.
var held := false

var _hovered := false
## The glow on the deck and the bouncing "1P" (ArcadePanelGlow), in place of the yellow frame there was.
var _glow: ArcadePanelGlow = null
var _controllers: Array[XRController3D] = []
var _squeezing: Dictionary = {}


func _ready() -> void:
	collision_layer |= POINTABLE_LAYER
	collision_mask = 0
	monitoring = false
	if desktop_rect.has_area() and not get_viewport().use_xr:
		_narrow_to_desktop_rect()
	_glow = ArcadePanelGlow.new()
	_glow.name = "PanelHighlight"
	_glow.panel_size = panel_size
	_glow.ring_radius = ring_radius
	_glow.ring_width = ring_width
	if has_meta(&"glow_rect"):
		_glow.rect = get_meta(&"glow_rect") as Rect2
	var who: Variant = get_parent().get("player") if get_parent() != null else null
	_glow.player = maxi(int(who), 0) if who != null else 0
	# The panel's own colour when it has one (a cabinet from a model: its caps'), else the stick ball's for the player.
	var parent := get_parent()
	_glow.color = parent.get_meta(&"player_color") as Color if parent != null and parent.has_meta(&"player_color") \
		else ArcadeCabinetBuilder._player_color(_glow.player)
	# Just above the deck, under the caps: the glow lies on the panel itself.
	_glow.position = Vector3(0.0, 0.0, 0.0045)
	add_child(_glow)
	_refresh()
	await get_tree().process_frame
	for node in XrControllers.all(get_tree()):
		_controllers.append(node as XRController3D)


## Shrink the pointable box and the lit frame to `desktop_rect`, and move this node onto it (its origin is what a laser or a test aims at, and the plate is drawn about it). Logged: a panel whose crosshair area
## changed with the platform is the first thing asked about.
func _narrow_to_desktop_rect() -> void:
	for child in get_children():
		var col := child as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		var box := col.shape as BoxShape3D
		print("[Arcade] %s: desktop mode, the crosshair's grip is %.2f x %.2f m round START, not the whole %.2f x %.2f m panel" % [
			get_parent().name if get_parent() != null else name, desktop_rect.size.x, desktop_rect.size.y, box.size.x, box.size.y])
		box.size = Vector3(desktop_rect.size.x, desktop_rect.size.y, box.size.z)
	var centre := desktop_rect.get_center()
	position += basis * Vector3(centre.x, centre.y, 0.0)
	panel_size = desktop_rect.size


## A pointer (the desktop reticle, the laser) on the panel: entering lights it, a press
## attaches or lets go.
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hovered = true
		XRToolsPointerEvent.Type.EXITED:
			_hovered = false
			if momentary:
				set_held(false)
		XRToolsPointerEvent.Type.PRESSED:
			_hovered = true
			if _hand_reaches(event.pointer):
				print("[Arcade] %s: press ignored, the hand is on one of its controls" % (get_parent().name if get_parent() != null else name))
				_refresh()
				return
			if momentary:
				set_held(true)
			else:
				set_attached(not attached)
		XRToolsPointerEvent.Type.RELEASED:
			if momentary:
				set_held(false)
	_refresh()


## Is the hand behind `pointer` holding, or about to take hold of, one of this panel's controls? Null for the
## desktop's reticle, which has no hand.
func _hand_reaches(pointer: Node) -> bool:
	var panel := get_parent() as ArcadeControlModule
	return panel != null and panel.hand_reaching(Haptics.controller_of(pointer))


func set_held(on: bool) -> void:
	if on == held:
		return
	held = on
	_refresh()
	held_changed.emit(on)


func set_attached(on: bool) -> void:
	if on == attached:
		return
	attached = on
	_refresh()
	toggled.emit(on)


func is_hovered() -> bool:
	return _hovered


func _process(_delta: float) -> void:
	# VR: a squeeze with a hand over the panel is the same press.
	for ctrl in _controllers:
		if not is_instance_valid(ctrl) or not ctrl.get_is_active():
			continue
		var id := ctrl.get_instance_id()
		var grip := ctrl.get_float("grip")
		var was: bool = _squeezing.get(id, false)
		if not was and grip > GRIP_ON:
			_squeezing[id] = true
			# A fist round a control (ArcadePanelHands) is for the control: it neither attaches nor holds START.
			if PokeTip.tip_of(ctrl).distance_to(global_position) <= REACH and not _hand_reaches(ctrl):
				if momentary:
					set_held(true)
				else:
					set_attached(not attached)
				_hovered = false
				_refresh()
		elif was and grip < GRIP_OFF:
			_squeezing[id] = false
			if momentary:
				set_held(false)
	# A hand near the panel lights it, as a pointer does.
	if not _controllers.is_empty():
		var near := false
		for ctrl in _controllers:
			if is_instance_valid(ctrl) and ctrl.get_is_active() \
					and PokeTip.tip_of(ctrl).distance_to(global_position) <= REACH:
				near = true
		if near != _vr_near:
			_vr_near = near
			_refresh()


var _vr_near := false


func _refresh() -> void:
	if _glow == null:
		return
	_glow.set_state(_hovered or _vr_near, attached or held)
