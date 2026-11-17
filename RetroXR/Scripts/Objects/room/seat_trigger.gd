## SeatTrigger — the part of a seat (Seat, CockpitSeat) you press to sit on it.
##
## A pointable Area3D laid over the seat's cushion: a desktop click or the laser's trigger
## arrives as a pointer_event and sits (or gets up). It is a thin slab on the SURFACE the
## player sits on, so the rest of the seat (its legs, its sides) is still the body that is
## picked up by holding on it. Aimed at, it lights yellow, the colour everything selectable wears
## (WidgetOutline.SELECT_COLOR).
##
## THE LIGHT IS PAINTED ON THE CUSHION, not floated over it. It was a flat translucent square 2 cm over the
## trigger's box (itself 3 cm proud of the cushion): hard edges, a card in the air over a soft cushion, a rectangle
## on a round one, on and off in a frame. It is a `Decal` (`SeatHover`) pointing down through the box, so it lies on
## whatever the cushion's surface does, faded off the arms and sides (`normal_fade`); its picture is a rounded
## outline over a soft fill (an ellipse with `round_shape`), made once per size (`hover_texture`). It fades in,
## breathes slowly while aimed at and fades out, as the seat's facing arrow does.
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
const HOVER_COLOR := WidgetOutline.SELECT_COLOR
## The light's projector reaches from this far over the trigger box's top to HOVER_REACH under it, metres (a soft
## sofa cushion's top sags well under the box laid over it).
const HOVER_LIFT := 0.03
const HOVER_REACH := 0.18
## The outline: its width and the corners' radius, metres; the fill inside it (alpha at the middle and by the outline).
const HOVER_RIM := 0.014
const HOVER_CORNER := 0.07
## How far in from the box's edge the outline runs, metres (at most a sixth of the place's short side). The box is as
## wide as the cushion, whose edge is ROUNDED: an outline on it was a band down the side of a round cushion with nothing
## on top, and wrapped down a sofa cushion's front.
const HOVER_INSET := 0.04
const HOVER_FILL_MIDDLE := 0.06
const HOVER_FILL_EDGE := 0.2
## Texels a metre (capped at HOVER_MAX_TEXELS a side).
const HOVER_TEXELS_PER_M := 320.0
const HOVER_MAX_TEXELS := 512
const HOVER_FADE_IN := 0.12
const HOVER_FADE_OUT := 0.2
## The breathing while aimed at: the alpha dips this far under full, this many times a second.
const HOVER_PULSE_DEPTH := 0.22
const HOVER_PULSE_HZ := 0.8
## The OUTLINE glows (its own emission picture, the rim alone), so it reads on dark fabric and in a dim room; the fill
## only tints. Both at 1.6 and one picture for the two turned a cushion solid yellow under filmic tonemapping.
const HOVER_EMISSION := 0.9
const HOVER_ALBEDO_MIX := 0.85
## How far the laser's slab reaches past the cushion while somebody sits on it, metres: forward (the seat's -Z) and to each side.
const STAND_REACH_FORWARD := 0.6
const STAND_REACH_SIDE := 0.2

## The place this trigger sits at, on a seat of several (Seat.toggle_at): its eye and stand markers. Empty: the
## seat's one place.
@export var eye_point: NodePath
@export var stand_point: NodePath

## A round seat (a round cushion, a pouf, a stool): the light is the ellipse filling the box, not a rounded
## rectangle. Set before the trigger enters the tree (ContractSeat does, from its `round_seat`).
@export var round_shape := false
## How much higher than HOVER_LIFT over the box the light's projector starts, metres: a BOWL (the papasan) whose sides
## rise well over the place's box, where the outline lands. Set before the trigger enters the tree.
@export var hover_rise := 0.0
## The place the light is laid out on, in the trigger's frame: `position` its centre, `size` its size. Zero size: the
## trigger's own box. ContractSeat sets it to the contract's place, because it grows the box over the cushion's edges
## (ContractSeat.fit_trigger) and the outline belongs on the cushion. Set before the trigger enters the tree.
@export var hover_box := AABB()

var _hover: Decal = null
var _hovered := false
var _fade := 0.0
var _fade_tween: Tween = null
var _pulse_time := 0.0
static var _textures: Dictionary = {}
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
		# The light is the place's TOP only, projected down onto it. A Decal has no surface of its own, so it cannot
		# z-fight the comforter a bed's contract sets the box's top AT (the whole box did; then a flat square floated
		# 2 cm over it), and it lies on a sagging sofa cushion instead of hanging over it.
		# Laid out from `hover_box` when given (the place's cushion; the box is grown over its edges), else the box.
		var size := (shape.shape as BoxShape3D).size
		var mid := shape.position
		if hover_box.size != Vector3.ZERO:
			size = hover_box.size
			mid = hover_box.position
		_hover = Decal.new()
		_hover.name = "SeatHover"
		_hover.size = Vector3(size.x, HOVER_LIFT + hover_rise + size.y + HOVER_REACH, size.z)
		var top := mid.y + size.y * 0.5 + HOVER_LIFT + hover_rise
		_hover.transform = Transform3D(shape.basis, Vector3(mid.x, top - _hover.size.y * 0.5, mid.z))
		_hover.texture_albedo = hover_texture(Vector2(size.x, size.z), round_shape)
		_hover.texture_emission = hover_texture(Vector2(size.x, size.z), round_shape, true)
		_hover.emission_energy = HOVER_EMISSION
		_hover.albedo_mix = HOVER_ALBEDO_MIX
		_hover.modulate = Color(HOVER_COLOR, 0.0)
		# Off the arms, the back and the sides of the cushion; soft where the projector starts and ends.
		_hover.normal_fade = 0.3
		_hover.upper_fade = 0.15
		_hover.lower_fade = 0.4
		_hover.visible = false
		add_child(_hover)
		set_process(false)
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
			_set_hovered(true)
		XRToolsPointerEvent.Type.EXITED:
			_set_hovered(false)
		XRToolsPointerEvent.Type.PRESSED:
			# Whatever it is laid over: a Seat, or a driving cabinet's own CockpitSeat.
			var seat := get_parent()
			if seat != null and not eye_point.is_empty() and seat.has_method("toggle_at"):
				print("[Seat] %s %s pressed (occupied=%s)" % [seat.name, name, str(seat.call("is_occupied"))])
				seat.call("toggle_at", self)
			elif seat != null and seat.has_method("toggle"):
				print("[Seat] %s pressed (occupied=%s)" % [seat.name, str(seat.call("is_occupied")) if seat.has_method("is_occupied") else "?"])
				seat.call("toggle")
			else:
				push_warning("[Seat] %s pressed but its parent %s cannot be sat on (no toggle)" % [name, str(seat)])


## Aimed at. The aim, not the light: that may still be fading out after the aim has left.
func is_hovered() -> bool:
	return _hover != null and _hovered


## The light (for the tests and probes), or null for a trigger with no box.
func hover_light() -> Decal:
	return _hover


func _set_hovered(on: bool) -> void:
	if _hover == null or on == _hovered:
		return
	_hovered = on
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	if on:
		_pulse_time = 0.0
		_hover.visible = true
	if not is_inside_tree():
		_fade = 1.0 if on else 0.0
		_hover.visible = on
		_apply_fade()
		return
	set_process(true)
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade", 1.0 if on else 0.0, HOVER_FADE_IN if on else HOVER_FADE_OUT)
	if not on:
		_fade_tween.tween_callback(_on_faded_out)


func _on_faded_out() -> void:
	_hover.visible = false
	set_process(false)


func _process(delta: float) -> void:
	_pulse_time += delta
	_apply_fade()


func _apply_fade() -> void:
	if _hover == null:
		return
	# Breathing down from full, starting at full so the light comes up bright.
	var breath := 1.0 - HOVER_PULSE_DEPTH * 0.5 * (1.0 - cos(TAU * HOVER_PULSE_HZ * _pulse_time))
	_hover.modulate = Color(HOVER_COLOR, _fade * breath)


## The light's picture for a place `size` metres across (x, z): white, its alpha a rounded outline (the ellipse filling
## it when `oval`) over a fill that grows toward the outline, anti-aliased. `glow`: the emission picture, the outline
## alone, premultiplied. One per size, shape and kind.
static func hover_texture(size: Vector2, oval: bool, glow := false) -> ImageTexture:
	var key := "%d_%d_%s_%s" % [roundi(size.x * 1000.0), roundi(size.y * 1000.0), str(oval), str(glow)]
	if _textures.has(key):
		return _textures[key]
	var per_m := minf(HOVER_TEXELS_PER_M, float(HOVER_MAX_TEXELS) / maxf(size.x, size.y))
	var w := maxi(8, roundi(size.x * per_m))
	var h := maxi(8, roundi(size.y * per_m))
	var half := size * 0.5
	var inset := minf(HOVER_INSET, minf(half.x, half.y) / 3.0)
	var shape_half := half - Vector2(inset, inset)
	var short := maxf(minf(shape_half.x, shape_half.y), 0.001)
	var radius := minf(HOVER_CORNER, short)
	var texel := 1.0 / per_m
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# This texel's centre, metres from the middle.
			var p := Vector2((x + 0.5) / w * size.x - half.x, (y + 0.5) / h * size.y - half.y)
			var d := hover_distance(p, shape_half, radius, oval)
			var inner := clampf(-d / short, 0.0, 1.0)
			var fill := lerpf(HOVER_FILL_EDGE, HOVER_FILL_MIDDLE, smoothstep(0.0, 0.6, inner))
			var rim := 1.0 - smoothstep(HOVER_RIM - texel, HOVER_RIM + texel, -d)
			var inside := 1.0 - smoothstep(-texel, texel, d)
			if glow:
				var g := rim * inside
				img.set_pixel(x, y, Color(g, g, g, g))
			else:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(fill, rim) * inside))
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	print("[Seat] hover %s %s: %dx%d texels for %.2f x %.2f m" % ["glow" if glow else "light", "oval" if oval else "rounded", w, h, size.x, size.y])
	return tex


## Signed distance, metres, from `p` to the edge of a rounded rectangle of half-size `half` and corner `radius`
## (negative inside), or of the ellipse filling it when `oval` (approximate, exact on the axes, which an outline this
## thin needs). Pure.
static func hover_distance(p: Vector2, half: Vector2, radius: float, oval: bool) -> float:
	if oval:
		var short := minf(half.x, half.y)
		return ((p / half).length() - 1.0) * short
	var q := p.abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## The body a headset's laser hits (null for a trigger with no box to copy).
func laser_body() -> StaticBody3D:
	return _laser_body
