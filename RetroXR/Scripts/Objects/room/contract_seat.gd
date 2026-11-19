## ContractSeat — a Seat built from its model's contract: the RETRO XR sofas, stools, chairs and beds
## (RetroXR-models generic/seating and generic/beds, imported-assets/furniture/{seating,beds}/).
##
## The scene carries only the `Model` (ApplianceModel: the three levels, shown by distance) and the highlight; the
## rest is read from the contract at run time, as DrawerFurniture does for the Mission pair (a `.json` is a JSON
## resource and ships with the export):
## - the collision boxes (every list under `collision`), and the same boxes as the `PointerArea` (SeatPointerArea);
##   they follow the piece's PARTS (legs, rails, cushions; a row may be turned by its `basis`, three columns, or be a
##   `shape` "cylinder" about its local Y, `size` [2r, height, 2r]). Until 2026-11-20 each seat was one box from the
##   floor up, so the space under a sofa's legs was a wall;
## - the PLACES (Seat's header): a sofa's `seats` (one cushion each), or one place from `eye_point` / `seat_trigger`;
##   a bed's mattress is split in two along its length, the head end (the pillow) LYING at `lie_eye_point` and the
##   rest SITTING on the edge at `eye_point`. Each place is an `EyePointN` marker turned from the contract's `z_axis`
##   (-Z the way the eyes look) and a SeatTrigger slab naming it;
## - the stand points: the contract's `StandPoint` and its mirror on the other side, each place getting up onto the
##   one nearer to it (so the left end of a sofa gets up on the left);
## - a bed's drawers, built by FurnitureDrawers exactly as the Mission pair's (they slide out of the bed's SIDE).
##
## Frame: glTF metres, the origin the middle of the footprint on the floor; a seat's front (a bed's foot) is +Z.
## Nothing runs per frame while it stands empty, but for a piece with drawers, which polls its hold (DrawerPoll).
class_name ContractSeat
extends Seat

## The model's contract.
@export_file("*.json") var contract_path := ""
## A round seat (a round cushion, a pouf, a stool): its places light as an ellipse, not a rounded rectangle
## (SeatTrigger.round_shape). The contract does not say.
@export var round_seat := false
## A bowl's sides rise over its places' boxes: their light starts this much higher (SeatTrigger.hover_rise), metres.
@export var hover_rise := 0.0

## How far toward the foot of a bed, past the head on the pillow, a press LIES down (the rest of the mattress sits).
const LIE_ZONE_PAST_EYE := 0.25

@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

var _contract: Dictionary = {}
## The places: {trigger (SeatTrigger), eye (Marker3D), stand (Marker3D), lie (bool)}.
var _places: Array[Dictionary] = []
var _drawers: FurnitureDrawers = null
var _carry: CarryContents = null


## Polls a piece with drawers for its hold every physics frame: Seat's own physics process runs only while sat on.
class DrawerPoll extends Node:
	var seat: ContractSeat = null

	func _physics_process(delta: float) -> void:
		if seat != null:
			seat._step_drawers(delta)


func _ready() -> void:
	_contract = DeckFace.contract(contract_path, "ContractSeat")
	if _contract.is_empty():
		push_warning("[Seat] %s: no contract at %s; nothing to sit on" % [name, contract_path])
		super()
		return
	var boxes := _build_collision()
	_build_places()
	if _contract.get("drawers") is Array and not (_contract["drawers"] as Array).is_empty():
		_drawers = FurnitureDrawers.new(self, _model, "Seat")
		_drawers.build(_contract["drawers"])
		_carry = CarryContents.new()
		for d in _drawers.rows:
			_carry.add_bin(self, d["body"], (d["inner"] as AABB).grow(0.01), collision_layer)
		var poll := DrawerPoll.new()
		poll.name = "DrawerPoll"
		poll.seat = self
		# After whatever holds it has moved it this tick (CarryContents measures that), as DrawerFurniture.
		poll.process_physics_priority = 100
		add_child(poll)
	super()
	if _model != null:
		for i in range(1, _model.levels.size()):
			for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
				m.add_to_group("outline_exclude")
	else:
		push_warning("[Seat] %s: no Model node: nothing draws it" % name)
	print("[Seat] %s (%s%s): %d collision boxes, %d places (%s), %d drawers, from %s" % [name, type_id,
		", a floor seat" if is_floor_seat() else "", boxes,
		_places.size(), ", ".join(_places.map(func(p: Dictionary) -> String: return "%s%s" % [(p["eye"] as Node).name,
		" lie" if p["lie"] else ""])), _drawers.rows.size() if _drawers != null else 0, contract_path.get_file()])


## The places, in order (the first is the seat's own: `EyePoint`, `SeatTrigger`). For a test, a probe.
func places() -> Array[Dictionary]:
	return _places


## A bed's arrow runs along the mattress from the pillow toward the foot (+Z), which is what sets the bed against a wall
## the right way round; its first place is sitting on the EDGE, whose sideways facing said nothing about that.
func _facing_arrow_frame() -> Transform3D:
	for p: Dictionary in _places:
		if p["lie"]:
			var eye := p["eye"] as Node3D
			var trigger := p["trigger"] as Node3D
			return Transform3D(Basis(Vector3.UP, PI), Vector3(eye.position.x, trigger.position.y + 0.05, eye.position.z))
	return super()


## The drawers' handles (a bed's), or none.
func drawers() -> Array[VRDrawer]:
	if _drawers == null:
		return []
	return _drawers.handles()


## The middle of drawer `i`'s floor inside, in this node's frame, wherever the drawer is now (a test, a probe).
func drawer_seat_local(i: int) -> Vector3:
	return _drawers.seat_local(i)


## What a bed holds in place in its drawers while it is carried (a test, a probe), or null with no drawers.
func carry() -> CarryContents:
	return _carry


## The model's contract, as read.
func contract() -> Dictionary:
	return _contract


## A seat whose top is under this is sat on as the floor is (a floor cushion, a zabuton, a floor rocker): the eyes a
## floor-sitting adult's, under a metre, where a chair's are 1.2 m or more.
const FLOOR_SEAT_TOP := 0.3


## Whether this is a FLOOR seat: its contract's `seat_top` under FLOOR_SEAT_TOP. A bed names none: not a floor seat.
func is_floor_seat() -> bool:
	var top: Variant = _contract.get("seat_top")
	return top != null and float(top) < FLOOR_SEAT_TOP


func _step_drawers(delta: float) -> void:
	var held := freeze and collision_layer == picked_up_layer
	if _carry != null:
		_carry.step(self, held, delta)
	_drawers.step(held)


func _exit_tree() -> void:
	super()
	if _carry != null:
		_carry.release(self)


# ── building ───────────────────────────────────────────────────────────────

func _build_collision() -> int:
	var pointer := StaticBody3D.new()
	pointer.name = "PointerArea"
	pointer.collision_layer = SeatTrigger.POINTABLE_LAYER
	pointer.collision_mask = 0
	pointer.set_script(SeatPointerArea)
	var n := 0
	var collision: Dictionary = _contract.get("collision", {})
	for key: String in collision:
		if not collision[key] is Array:
			continue
		for row: Dictionary in collision[key]:
			add_child(_shape_from_row("Col%s_%s_%d" % [key.capitalize(), row.get("name", "Box"), n], row))
			pointer.add_child(_shape_from_row("Shape%d" % n, row))
			n += 1
	if n == 0:
		push_warning("[Seat] %s: the contract has no collision boxes" % name)
	add_child(pointer)
	return n


func _build_places() -> void:
	var sit_axis := _marker_axis("EyePoint", Vector3(0, 0, -1))
	var trig: Dictionary = _contract.get("seat_trigger", {})
	if trig.is_empty() or not _contract.has("eye_point"):
		push_warning("[Seat] %s: the contract has no eye_point / seat_trigger: nowhere to sit" % name)
		return
	var tc := _v3(trig["centre"])
	var ts := _v3(trig["size"])
	# The stand points: the contract's, and its mirror across the seat when it is off to one side.
	var stands: Array[Marker3D] = []
	var sp := _v3(_contract.get("stand_point", [0.0, 0.0, 0.5]))
	stands.append(_marker("StandPoint", sp, Basis.IDENTITY))
	if absf(sp.x) > 0.01:
		stands.append(_marker("StandPoint2", Vector3(-sp.x, sp.y, sp.z), Basis.IDENTITY))
	var rows: Array = []   # [eye position, axis, trigger centre, trigger size, lie]
	var seats: Array = _contract.get("seats", [])
	if not seats.is_empty():
		for s: Dictionary in seats:
			rows.append([_v3(s["eye_point"]), sit_axis, _v3(s["seat_trigger"]["centre"]),
				_v3(s["seat_trigger"]["size"]), false])
		# The middle cushion first: it is the seat's own place (EyePoint / SeatTrigger: the facing arrow, a plain sit()).
		rows.sort_custom(func(a: Array, b: Array) -> bool: return absf((a[0] as Vector3).x) < absf((b[0] as Vector3).x))
	elif _contract.get("lie_eye_point") != null:
		# A bed: the mattress, split across its length. The foot is +Z, so the head end is the low z.
		var lie := _v3(_contract["lie_eye_point"])
		var z0 := tc.z - ts.z * 0.5
		var z1 := tc.z + ts.z * 0.5
		var split := clampf(lie.z + LIE_ZONE_PAST_EYE, z0 + 0.1, z1 - 0.1)
		rows.append([_v3(_contract["eye_point"]), sit_axis, Vector3(tc.x, tc.y, (split + z1) * 0.5),
			Vector3(ts.x, ts.y, z1 - split), false])
		rows.append([lie, _marker_axis("LieEyePoint", Vector3(0, 0, -1)), Vector3(tc.x, tc.y, (z0 + split) * 0.5),
			Vector3(ts.x, ts.y, split - z0), true])
	else:
		rows.append([_v3(_contract["eye_point"]), sit_axis, tc, ts, false])
	for i in rows.size():
		var r: Array = rows[i]
		var suffix := "" if i == 0 else str(i + 1)
		var eye := _marker("EyePoint" + suffix, r[0], _axis_basis(r[1]))
		var stand := stands[0]
		for s in stands:
			if _flat(s.position).distance_to(_flat(r[0])) < _flat(stand.position).distance_to(_flat(r[0])):
				stand = s
		# The trigger is turned to the place's heading: seated, its laser slab grows toward the sitter's knees, its -Z
		# (SeatTrigger.stand_zone), and these seats face +Z (a bed's edge +X).
		var turn := Basis(Vector3.UP, Seat.yaw_of(eye.basis))
		var fit := fit_trigger(r[2], r[3], _collision_rows())
		var trigger := SeatTrigger.new()
		trigger.name = "SeatTrigger" + suffix
		trigger.transform = Transform3D(turn, fit[0])
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = (turn.inverse() * (fit[1] as Vector3)).abs()
		shape.shape = box
		trigger.add_child(shape)
		# The light keeps the contract's place: the cushion, not the box grown over its edges.
		trigger.hover_box = AABB(turn.inverse() * ((r[2] as Vector3) - (fit[0] as Vector3)), Vector3.ZERO)
		trigger.hover_box.size = (turn.inverse() * (r[3] as Vector3)).abs()
		if not (fit[1] as Vector3).is_equal_approx(r[3]) or not (fit[0] as Vector3).is_equal_approx(r[2]):
			print("[Seat] %s %s: the place's trigger fitted over the surface it marks: %s at %s (contract %s at %s)" % [
				name, trigger.name, str(fit[1]), str(fit[0]), str(r[3]), str(r[2])])
		trigger.round_shape = round_seat
		trigger.hover_rise = hover_rise
		trigger.eye_point = NodePath("../" + eye.name)
		trigger.stand_point = NodePath("../" + stand.name)
		add_child(trigger)
		_places.append({"trigger": trigger, "eye": eye, "stand": stand, "lie": r[4]})


## A place's trigger must WIN the ray over the body on the whole surface it marks, or aiming there picks the seat up
## instead of sitting. Measured on the contracts (2026-11-17): every bed's trigger top was FLUSH with its mattress box's
## (which of two coplanar faces a ray reports is arbitrary), the mattresses were wider than their triggers (±0.82 m vs
## ±0.76), a rocker's seat reached 4 cm past its trigger's front, and on every seat the cushion's front and sides, under a
## 3 cm slab, were the body's: aimed at a cushion's front edge from standing, the seat was lifted.
## The SURFACE is every collision box overlapping the trigger whose top is no more than SURFACE_BELOW under the
## trigger's top (higher ones are backs and arms, deliberately the body's). The trigger's top is kept TRIGGER_PROUD over it,
## each side of the trigger the surface overhangs by no more than EDGE_SNAP is pushed to OUTSET past the surface's edge
## (farther is a sofa's seat running under its back: left alone), and its bottom goes TRIGGER_DROP under the surface's top,
## so the top of the cushion's front and sides is the trigger's. Legs, base, back and arms stay the body to carry it by.
const TRIGGER_PROUD := 0.03
const SURFACE_BELOW := 0.08
const EDGE_SNAP := 0.1
const TRIGGER_OUTSET := 0.02
const TRIGGER_DROP := 0.06


## `centre`/`size`: the contract's trigger, in the seat's frame; `boxes`: [[centre, size], ...] the collision boxes.
## Returns [centre, size] of the fitted trigger. Pure.
static func fit_trigger(centre: Vector3, size: Vector3, boxes: Array) -> Array:
	var lo := centre - size * 0.5
	var hi := centre + size * 0.5
	var surface_top := -INF
	var s_lo := Vector3(INF, 0.0, INF)
	var s_hi := Vector3(-INF, 0.0, -INF)
	for b: Array in boxes:
		var b_lo: Vector3 = (b[0] as Vector3) - (b[1] as Vector3) * 0.5
		var b_hi: Vector3 = (b[0] as Vector3) + (b[1] as Vector3) * 0.5
		if b_hi.x <= lo.x or b_lo.x >= hi.x or b_hi.z <= lo.z or b_lo.z >= hi.z:
			continue
		# A SHELL: one box round the place, over its middle and above it (the papasan's bowl is one solid box from
		# 0.30 to 0.82 m, its trigger at 0.475 buried inside: every laser met the bowl). The trigger wraps the shell from
		# its top down to TRIGGER_DROP under the place (the box's front is a wall to 0.82 m where the real bowl dips, so a
		# ray at the front of the cushion met it); under that, the shell and its base stay the body.
		if b_hi.y > hi.y + 0.001 and b_lo.y < lo.y and b_lo.x <= centre.x and b_hi.x >= centre.x \
				and b_lo.z <= centre.z and b_hi.z >= centre.z:
			var top := b_hi.y + TRIGGER_PROUD
			var c_lo := Vector3(b_lo.x - TRIGGER_OUTSET, maxf(b_lo.y, hi.y - TRIGGER_DROP), b_lo.z - TRIGGER_OUTSET)
			var c_hi := Vector3(b_hi.x + TRIGGER_OUTSET, top, b_hi.z + TRIGGER_OUTSET)
			return [(c_lo + c_hi) * 0.5, c_hi - c_lo]
		if b_hi.y > hi.y + 0.001 or b_hi.y < hi.y - SURFACE_BELOW:
			continue
		surface_top = maxf(surface_top, b_hi.y)
		s_lo = Vector3(minf(s_lo.x, b_lo.x), 0.0, minf(s_lo.z, b_lo.z))
		s_hi = Vector3(maxf(s_hi.x, b_hi.x), 0.0, maxf(s_hi.z, b_hi.z))
	if surface_top == -INF:
		return [centre, size]
	hi.y = maxf(hi.y, surface_top + TRIGGER_PROUD)
	lo.y = minf(lo.y, surface_top - TRIGGER_DROP)
	if s_lo.x < lo.x + 0.001 and lo.x - s_lo.x <= EDGE_SNAP:
		lo.x = s_lo.x - TRIGGER_OUTSET
	if s_hi.x > hi.x - 0.001 and s_hi.x - hi.x <= EDGE_SNAP:
		hi.x = s_hi.x + TRIGGER_OUTSET
	if s_lo.z < lo.z + 0.001 and lo.z - s_lo.z <= EDGE_SNAP:
		lo.z = s_lo.z - TRIGGER_OUTSET
	if s_hi.z > hi.z - 0.001 and s_hi.z - hi.z <= EDGE_SNAP:
		hi.z = s_hi.z + TRIGGER_OUTSET
	return [(lo + hi) * 0.5, hi - lo]


## The contract's collision boxes as [[centre, size], ...]: a turned row or a cylinder as its axis-aligned bounds.
func _collision_rows() -> Array:
	var out: Array = []
	var collision: Dictionary = _contract.get("collision", {})
	for key: String in collision:
		if collision[key] is Array:
			for row: Dictionary in collision[key]:
				out.append(row_bounds(row))
	return out


## A collision row's turn: its `basis` (three columns), or none.
static func row_basis(row: Dictionary) -> Basis:
	var cols: Variant = row.get("basis")
	if not cols is Array or (cols as Array).size() != 3:
		return Basis.IDENTITY
	return Basis(_v3(cols[0]), _v3(cols[1]), _v3(cols[2]))


## A collision row's axis-aligned bounds in the seat's frame, as [centre, size]. Pure.
static func row_bounds(row: Dictionary) -> Array:
	var c := _v3(row["centre"])
	var h := _v3(row["size"]) * 0.5
	var b := row_basis(row)
	var e := Vector3(absf(b.x.x) * h.x + absf(b.y.x) * h.y + absf(b.z.x) * h.z,
		absf(b.x.y) * h.x + absf(b.y.y) * h.y + absf(b.z.y) * h.z,
		absf(b.x.z) * h.x + absf(b.y.z) * h.y + absf(b.z.z) * h.z)
	return [c, e * 2.0]


## The CollisionShape3D for a contract row: a box, or a cylinder about its local Y; turned by its `basis`.
static func _shape_from_row(shape_name: String, row: Dictionary) -> CollisionShape3D:
	var s := _v3(row["size"])
	var cs := _box(shape_name, _v3(row["centre"]), s)
	if String(row.get("shape", "box")) == "cylinder":
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(s.x, s.z) * 0.5
		cyl.height = s.y
		cs.shape = cyl
	cs.basis = row_basis(row)
	return cs


## A contract marker's z axis (its +Z: -Z is the way the eyes look), or `fallback`.
func _marker_axis(node_name: String, fallback: Vector3) -> Vector3:
	for m: Dictionary in _contract.get("markers", []):
		if String(m.get("node", "")) == node_name and m.get("z_axis") is Array:
			return _v3(m["z_axis"])
	return fallback


## The basis whose +Z is `z` (the way the eyes look is its -Z), up kept up.
static func _axis_basis(z: Vector3) -> Basis:
	var zn := z.normalized()
	var x := Vector3.UP.cross(zn).normalized()
	return Basis(x, zn.cross(x).normalized(), zn)


func _marker(marker_name: String, at: Vector3, basis: Basis) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.transform = Transform3D(basis, at)
	add_child(m)
	return m


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _box(shape_name: String, centre: Vector3, size: Vector3) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = box
	cs.position = centre
	return cs


static func _v3(a: Variant) -> Vector3:
	var arr := a as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
