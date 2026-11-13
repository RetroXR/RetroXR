## ArcadeCoinSlot — a coin door's slot. Not a button: nothing is pressed, a coin goes in.
##
## IN A HEADSET a free hand that comes within REACH of the slot has a token pinched at its fingertip (the door's coin
## module hands over the mesh). Far out the token sits in the hand's own frame, face across the hand; within ALIGN_NEAR it
## has turned to stand edge-on in the slot's line. Push it through the slot's mouth (its centre crossing the mouth's plane
## going inward, within the opening) and it is in: `coin_entered(from)` with where the token was, and the module slides it on
## inside from there. A hand that holds something (a pad, a gun: PokeTip.is_poking false) has no token.
##
## WITH A POINTER (the desktop reticle, a laser) the slot is something to click: aimed at, it is outlined and shows the coin
## glyph; a press is `clicked`, and the module flies a token in from the corner of the view.
##
## The slot's frame is in its PARENT's frame (the coin door): `insert_dir`, the way a coin goes in; `slot_long`, the slot's
## long side; `slot_length` how long it is. A coin stands in the plane of those two (`slot_basis`).
class_name ArcadeCoinSlot
extends Area3D

## A token went in from a hand, which held it at `from` (world) as it crossed the mouth.
signal coin_entered(from: Transform3D)
## A pointer pressed the slot.
signal clicked

const POINTABLE_LAYER := 1 << 20
## A fingertip this close to the slot has a token in it (metres).
const REACH := 0.15
## Within this the token has turned to the slot's line.
const ALIGN_NEAR := 0.05
## How far past the slot's ends, and to either side of its line, a token still goes in.
const OPENING_SLACK := 0.006
const OPENING_ACROSS := 0.012
## After a token goes in, the hand is empty this long.
const REFILL_SECONDS := 0.4
## The token is pinched at the fingertip: its centre this far ahead of the tip.
const PINCH_AHEAD := 0.006
## md-hand_coin (Symbols Nerd Font), shown while a pointer is on the slot.
const COIN_GLYPH := 0xF1890

@export var insert_dir := Vector3(0, 0, -1)
@export var slot_long := Vector3(1, 0, 0)
@export var slot_length := 0.03

var _interactive := true
var _hover := {}
var _outline: WidgetOutline = null
var _glyph: Label3D = null
var _controllers: Array[XRController3D] = []
var _held: MeshInstance3D = null
var _held_by: XRController3D = null
var _side := {}
var _refill := 0.0


func _ready() -> void:
	collision_layer |= POINTABLE_LAYER
	_outline = WidgetOutline.attach(self)
	var lamp := get_node_or_null("ButtonMesh") as MeshInstance3D
	if lamp != null:
		_outline.set_source(lamp)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for node in XrControllers.all(get_tree()):
		_controllers.append(node as XRController3D)
	set_process(not _controllers.is_empty())


## The mesh and material a token in the hand wears (the door's coin module's).
func set_token(mesh: Mesh, material: Material) -> void:
	if _held == null:
		_held = MeshInstance3D.new()
		_held.name = "HeldCoin"
		_held.top_level = true
		_held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_held.visible = false
		add_child(_held)
	_held.mesh = mesh
	_held.material_override = material


func set_interactive(on: bool) -> void:
	_interactive = on
	collision_layer = (collision_layer | POINTABLE_LAYER) if on else 0
	if not on:
		_hover.clear()
		_hide_held()
		_sync_pointer()
	set_process(on and not _controllers.is_empty())


## The way a coin goes in, the slot's long side and the coin's face, in the world.
func insert_dir_world() -> Vector3:
	var p := get_parent() as Node3D
	return ((p.global_basis if p != null else Basis.IDENTITY) * insert_dir).normalized()


## A coin standing in the slot's line: x along the slot, y its face (the cylinder's axis), z = x × y (along the insert).
func slot_basis() -> Basis:
	var p := get_parent() as Node3D
	var b := p.global_basis if p != null else Basis.IDENTITY
	return slot_basis_of((b * insert_dir).normalized(), (b * slot_long).normalized())


static func slot_basis_of(insert: Vector3, long: Vector3) -> Basis:
	var x := (long - insert * long.dot(insert)).normalized()
	var y := insert.cross(x).normalized()
	return Basis(x, y, x.cross(y))


## Where the token goes in: a little out from the slot, against the insert direction.
func mouth() -> Vector3:
	return global_position - insert_dir_world() * 0.015


## Where a token in a hand is: pinched at the tip, in the hand's frame (face across the hand) far from the slot, turned to the
## slot's own within ALIGN_NEAR. Pure.
static func held_coin_pose(tip: Vector3, hand: Basis, slot_pos: Vector3, slot: Basis) -> Transform3D:
	var h := hand.orthonormalized()
	var in_hand := Basis(h.y, h.x, -h.z)
	var d := tip.distance_to(slot_pos)
	var w := 1.0 - smoothstep(ALIGN_NEAR, ALIGN_NEAR * 2.5, d)
	var q := Quaternion(in_hand).slerp(Quaternion(slot.orthonormalized()), w)
	return Transform3D(Basis(q), tip - h.z * PINCH_AHEAD)


func _process(delta: float) -> void:
	_refill = maxf(0.0, _refill - delta)
	var slot_pos := global_position
	var best: XRController3D = null
	var best_d := REACH
	for c in _controllers:
		if not is_instance_valid(c) or not c.get_is_active() or not PokeTip.is_poking(c):
			continue
		var d := PokeTip.tip_of(c).distance_to(slot_pos)
		if d < best_d:
			best_d = d
			best = c
	if best == null or _refill > 0.0 or _held == null or _held.mesh == null:
		if best == null:
			_side.clear()
		_hide_held()
		return
	var pose := held_coin_pose(PokeTip.tip_of(best), best.global_basis, slot_pos, slot_basis())
	_held.global_transform = pose
	_held.visible = true
	_held_by = best
	# In: the token's centre crosses the mouth's plane going inward, inside the opening.
	var into := insert_dir_world()
	var rel := pose.origin - mouth()
	var depth := rel.dot(into)
	var sb := slot_basis()
	var along := absf(rel.dot(sb.x))
	var across := absf(rel.dot(sb.y))
	var id := best.get_instance_id()
	var was: float = _side.get(id, -1.0)
	_side[id] = depth
	if was < 0.0 and depth >= 0.0 and along <= slot_length * 0.5 + OPENING_SLACK and across <= OPENING_ACROSS:
		_refill = REFILL_SECONDS
		_hide_held()
		Haptics.click(best, true, &"coin_slot")
		coin_entered.emit(pose)


func _hide_held() -> void:
	if _held != null:
		_held.visible = false
	_held_by = null


## The hand holding a token now, if any (for the tests and the module).
func held_by() -> XRController3D:
	return _held_by if _held != null and _held.visible else null


func pointer_event(event: XRToolsPointerEvent) -> void:
	if not _interactive:
		return
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hover[event.pointer] = true
		XRToolsPointerEvent.Type.EXITED:
			_hover.erase(event.pointer)
		XRToolsPointerEvent.Type.PRESSED:
			_hover[event.pointer] = true
			Haptics.click(Haptics.controller_of(event.pointer), true, &"coin_slot")
			clicked.emit()
	_sync_pointer()


func _sync_pointer() -> void:
	var on := not _hover.is_empty()
	if _outline != null:
		_outline.sync(on)
	if on and _glyph == null:
		_glyph = Label3D.new()
		_glyph.name = "HoverGlyph"
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		var symbols: Font = load(VRHinge.SYMBOL_FONT_PATH)
		if symbols != null:
			fv.fallbacks = [symbols]
		_glyph.font = fv
		_glyph.font_size = 96
		_glyph.pixel_size = 0.03 / 96.0
		_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_glyph.no_depth_test = true
		_glyph.render_priority = 2
		_glyph.outline_size = 18
		_glyph.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
		_glyph.text = String.chr(COIN_GLYPH)
		add_child(_glyph)
		_glyph.position = -insert_dir.normalized() * 0.03 + Vector3(0, 0.03, 0)
	if _glyph != null:
		_glyph.visible = on
