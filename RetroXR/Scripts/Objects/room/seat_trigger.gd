## SeatTrigger — the part of a seat (Seat, CockpitSeat) you press to sit on it.
##
## A pointable Area3D laid over the seat's cushion: a desktop click or the laser's trigger
## arrives as a pointer_event and sits (or gets up). It is a thin slab on the SURFACE the
## player sits on, so the rest of the seat (its legs, its sides) is still the body that is
## picked up by holding on it. Aimed at, it tints yellow, the colour everything selectable wears
## (WidgetOutline.SELECT_COLOR).
##
## THE VR LASER CANNOT SEE AN AREA. Its RayCast leaves `collide_with_areas` off (only the desktop reticle
## turns it on), so the Area3D alone took a desktop click and was invisible to a headset's laser: the seat
## could not be sat on in VR. A StaticBody3D of the same shape (`LaserBody`) stands on the same layer and
## hands what the laser sends on to `pointer_event`. It is the trigger's SIBLING, not its child: a laser's pickup
## takes a collider's parent for the pickable, so under the seat a hold on the cushion still carries the seat.
##
## SEATED, THE CUSHION GROWS. The cushion is under you, and a laser leaves the hand pointing forward: from the
## lap it flew over the seat you sit on and found nothing to press ("the cushion does not light up"). While the
## host is occupied the laser's body reaches `STAND_REACH_FORWARD` toward the knees and `STAND_REACH_SIDE` to each
## side, on the same thin slab; the host's own parts (SeatPointerArea) stand you up as well.
class_name SeatTrigger
extends Area3D

const POINTABLE_LAYER := 1 << 20
const HOVER_COLOR := Color(WidgetOutline.SELECT_COLOR, 0.22)
## How far the laser's slab reaches past the cushion while somebody sits on it, metres: forward (the seat's -Z) and to each side.
const STAND_REACH_FORWARD := 0.6
const STAND_REACH_SIDE := 0.2

var _hover: MeshInstance3D = null
var _laser_body: LaserBody = null
var _laser_shape: CollisionShape3D = null
var _rest_size := Vector3.ZERO
var _rest_position := Vector3.ZERO


## The part of the trigger a laser can hit: a body, because a laser's ray hits no areas.
class LaserBody extends StaticBody3D:
	var trigger: SeatTrigger = null

	func pointer_event(event: XRToolsPointerEvent) -> void:
		if trigger != null and is_instance_valid(trigger):
			trigger.pointer_event(event)


func _ready() -> void:
	collision_layer = POINTABLE_LAYER
	collision_mask = 0
	monitoring = false
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is BoxShape3D:
		_hover = MeshInstance3D.new()
		_hover.name = "SeatHover"
		var box := BoxMesh.new()
		box.size = (shape.shape as BoxShape3D).size
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = HOVER_COLOR
		box.material = mat
		_hover.mesh = box
		_hover.transform = shape.transform
		_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hover.visible = false
		add_child(_hover)
		_laser_body = LaserBody.new()
		_laser_body.name = "%sLaser" % name
		_laser_body.trigger = self
		_laser_body.collision_layer = POINTABLE_LAYER
		_laser_body.collision_mask = 0
		_laser_body.transform = transform
		var body_shape := CollisionShape3D.new()
		# Its own box: it is resized while somebody sits, and the trigger's must not follow.
		var own := BoxShape3D.new()
		own.size = (shape.shape as BoxShape3D).size
		body_shape.shape = own
		body_shape.transform = shape.transform
		_laser_body.add_child(body_shape)
		_laser_shape = body_shape
		_rest_size = own.size
		_rest_position = body_shape.position
		var host := get_parent()
		if host != null and host.has_signal("seated_changed"):
			host.connect("seated_changed", _on_host_seated)
		# The parent is still setting up its children while this runs.
		if get_parent() != null:
			get_parent().add_child.call_deferred(_laser_body)
	else:
		push_warning("[Seat] %s has no box shape: a headset's laser cannot sit on %s" % [name, str(get_parent())])


## The slab the laser can hit while somebody sits: `rest` grown forward (-Z) and to the sides. Pure.
static func stand_zone(rest: Vector3, rest_position: Vector3) -> Array:
	return [Vector3(rest.x + STAND_REACH_SIDE * 2.0, rest.y, rest.z + STAND_REACH_FORWARD),
		rest_position + Vector3(0.0, 0.0, -STAND_REACH_FORWARD * 0.5)]


func _on_host_seated(on: bool) -> void:
	if _laser_shape == null:
		return
	var box := _laser_shape.shape as BoxShape3D
	if on:
		var zone := stand_zone(_rest_size, _rest_position)
		box.size = zone[0]
		_laser_shape.position = zone[1]
	else:
		box.size = _rest_size
		_laser_shape.position = _rest_position


func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			if _hover != null:
				_hover.visible = true
		XRToolsPointerEvent.Type.EXITED:
			if _hover != null:
				_hover.visible = false
		XRToolsPointerEvent.Type.PRESSED:
			# Whatever it is laid over: a Seat, or a driving cabinet's own CockpitSeat.
			var seat := get_parent()
			if seat != null and seat.has_method("toggle"):
				print("[Seat] %s pressed (occupied=%s)" % [seat.name, str(seat.call("is_occupied")) if seat.has_method("is_occupied") else "?"])
				seat.call("toggle")
			else:
				push_warning("[Seat] %s pressed but its parent %s cannot be sat on (no toggle)" % [name, str(seat)])


func is_hovered() -> bool:
	return _hover != null and _hover.visible


## The body a headset's laser hits (null for a trigger with no box to copy).
func laser_body() -> StaticBody3D:
	return _laser_body
