## SeatTrigger — the part of a seat (Seat, CockpitSeat) you press to sit on it.
##
## A pointable Area3D laid over the seat's cushion: a desktop click or the laser's trigger
## arrives as a pointer_event and sits (or gets up). It is a thin slab on the SURFACE the
## player sits on, so the rest of the seat (its legs, its sides) is still the body that is
## picked up by holding on it. Aimed at, it tints.
class_name SeatTrigger
extends Area3D

const POINTABLE_LAYER := 1 << 20
const HOVER_COLOR := Color(0.35, 1.0, 0.45, 0.16)

var _hover: MeshInstance3D = null


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
				seat.call("toggle")


func is_hovered() -> bool:
	return _hover != null and _hover.visible
