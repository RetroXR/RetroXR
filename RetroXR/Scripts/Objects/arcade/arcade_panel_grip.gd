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
const HOVER_COLOR := Color(0.35, 1.0, 0.45, 0.16)       # WidgetOutline.HOVER_COLOR
const ATTACHED_COLOR := Color(1.0, 0.82, 0.28, 0.20)    # WidgetOutline.ACTIVE_COLOR
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

## A panel with nothing to take hold of (a gun cabinet's START buttons: the gun is the
## controller): a press does not attach anyone, it HOLDS the panel for as long as it lasts, and
## the cabinet reads that as START.
@export var momentary := false

var attached := false
## Whether a momentary panel is being pressed now.
var held := false

var _hovered := false
var _plate: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _controllers: Array[XRController3D] = []
var _squeezing: Dictionary = {}


func _ready() -> void:
	collision_layer |= POINTABLE_LAYER
	collision_mask = 0
	monitoring = false
	_plate = MeshInstance3D.new()
	_plate.name = "PanelHighlight"
	if ring_radius > 0.0:
		_plate.mesh = _ring_mesh()
	else:
		var quad := QuadMesh.new()
		quad.size = panel_size
		_plate.mesh = quad
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plate.material_override = _material
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Just above the deck, under the caps: the glow reads as the panel's own surface.
	_plate.position = Vector3(0.0, 0.0, 0.0045)
	add_child(_plate)
	_refresh()
	await get_tree().process_frame
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)


## The annulus a ring grip lights: `ring_width` wide about `ring_radius`, in XY, facing +Z.
func _ring_mesh() -> ArrayMesh:
	var outer := ring_radius + ring_width * 0.5
	var inner := maxf(ring_radius - ring_width * 0.5, 0.0)
	var n := 48
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		verts.append(Vector3(cos(a) * outer, sin(a) * outer, 0.0))
		verts.append(Vector3(cos(a) * inner, sin(a) * inner, 0.0))
		normals.append(Vector3.BACK)
		normals.append(Vector3.BACK)
	for i in n:
		var o0 := i * 2
		var o1 := ((i + 1) % n) * 2
		indices.append_array(PackedInt32Array([o0, o0 + 1, o1, o1, o0 + 1, o1 + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	if _plate == null:
		return
	_plate.visible = attached or held or _hovered or _vr_near
	_material.albedo_color = ATTACHED_COLOR if (attached or held) else HOVER_COLOR
