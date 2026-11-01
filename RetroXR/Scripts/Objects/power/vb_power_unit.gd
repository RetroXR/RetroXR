## VbPowerUnit — what clips onto the back of the Virtual Boy's controller and powers
## the console through the controller's cord (docs/dev/power.md): the VUE-007 battery
## pack (six AA cells behind an end lid) or the VUE-011 AC adapter tap (a DC jack the
## Super NES adapter's plug goes into; the Famicom's in Japan).
##
## The console has neither a power switch nor a supply of its own: both are on the
## controller, the switch on the block's top edge and the pack on its back. So the
## console's PowerInput reaches its supply THROUGH the controller in its port, the
## controller's through what is clipped on it, and this one's through its cells or
## its jack.
##
## A primitive of the RetroXR-models pack's measured outline (nintendo/virtual-boy/
## controller, MEASUREMENTS.md `pack`: 56.4 across, 34.2 thick, 64.0 long), in that
## model's BatteryPackPivot frame: its middle at the origin, +Y the face that lies on
## the controller's bay, -Z the cord end, +Z the lid end (the grips'). Its identity
## grab point seats it at the controller's PackMount. A mod dresses it in the model's
## pack or tap (xenu.vbpad); every place below is that model's, so nothing moves.
##
## The pack: open at its lid end, three columns of two cells lying end-on where the
## model's BatteryAA1-6 are (1-3 the front layer, against the controller, + toward
## the lid; 4-6 the back layer, + toward the far end, as the lid's plates and springs
## have them), the lid a CoverSlots cover that keeps them in. Live with all six in.
## The tap: the same box split into a base and a lid making up its back (the model's
## `tap.split`); in the base a channel from the gray DC jack, its socket facing the
## lid, to the grip end. The lid is a CoverSlots cover too: with it on, the jack takes
## no plug and the one in it cannot be pulled (CellSlots' rule for a bay), and it goes
## back on over a plug, as the real one closes over the SNS-002's.
##
## Pose only, as the N64 paks are: which controller it is on is saved on the
## CONTROLLER ("power_unit"). Its cells and lids are its CellSlots and CoverSlots,
## saved on it as any object's are; the plug in a tap's jack is saved by the
## adapter's lead. A tap also saves its variant (which jack it has).
class_name VbPowerUnit
extends XRToolsPickable

## Every unit is in this group; the controller's mount takes nothing else.
const GROUP := "vb_power_unit"
const KINDS: Array[String] = ["pack", "tap"]
## The save types (ScenePersistence.PLAIN_SCENES), by kind.
const TYPES := {"pack": "vb_battery_pack", "tap": "vb_ac_tap"}

## The outline, metres.
const SIZE := Vector3(0.0564, 0.0342, 0.064)
const LID := 0.003
## The pack's front wall (on the bay), its back, its sides and its far end.
const FRONT_WALL := 0.001
const BACK_WALL := 0.0009
const SIDE_WALL := 0.0025
const END_WALL := 0.0025
## A cell's diameter and the pitch of the three columns (MEASUREMENTS.md `cells`).
const CELL_D := 0.0145
const PITCH := 0.0155
## Each layer's middle cell, from the pack's middle: the model's BatteryAA2 and
## BatteryAA5 less its BatteryPackPivot. The front layer stands 2.5 mm nearer the lid,
## its + ends at the lid's buttons; the back layer's - ends at its springs.
const CELL_FRONT := Vector3(0.0, 0.00882, 0.00292)
const CELL_BACK := Vector3(0.0, -0.00888, 0.00042)
## Its lid's socket: what the lid fits (PortCover.group_for).
const LID_SOCKET := "vb_battery_pack_lid"

## The tap's split, from its middle along Y: its lid is the box's back from here, its
## base the front (the model's `tap.split`).
const TAP_SPLIT := 0.00025
## The channel's floor, 9.77 mm into the base from the split (`tap.depth`).
const TAP_FLOOR := 0.01002
## The jack's mouth: 19.8 mm toward the cord end from the middle (`tap.jack`, 6.5 mm
## from the box's cord end), its 7 mm block standing on the channel's floor.
const JACK_AT := Vector3(0.0, 0.00302, -0.0198)
## The tap lid's socket, and the lid: the back of the box down to 0.15 mm short of
## the split.
const TAP_LID_SOCKET := "vb_ac_tap_lid"
const TAP_LID_THICK := 0.0172

## The tap's jack by variant: the US tap takes the Super NES adapter's plug
## (SNS-002), the Japanese the Famicom's (HVC-002, 5.5 x 2.1 mm). Nothing else
## was sold: the Virtual Boy was a North American and Japanese machine.
const TAP_JACKS := {"usa": "snes_dc_plug", "jpn": "barrel_5_5x2_1"}

const PACK_COLOR := Color8(36, 36, 38)
const INSIDE := Color(0.05, 0.05, 0.055)
const DIVIDER := Color(0.1, 0.1, 0.105)
const CONTACT := Color(0.77, 0.77, 0.78)
const JACK_COLOR := Color(0.42, 0.42, 0.43)

const _DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")

## "pack" (VUE-007) or "tap" (VUE-011).
@export var kind := "pack"
## The tap's: "usa" or "jpn". "" settles to the player's outlet region's.
@export var variant := ""

## The tap's jack, or null on a pack.
var jack: DcPort = null
## Its intake: the pack's cells, or the tap's jack.
var input: PowerInput = null
## The plug this switched off under the tap's closed lid, to switch back on.
var _held_shut: XRToolsPickable = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	if not KINDS.has(kind):
		push_warning("[Power] VB power unit of unknown kind '%s': built as a pack" % kind)
		kind = "pack"
	if kind == "tap" and not TAP_JACKS.has(variant):
		var want := str(PowerBrickCatalog.REGION_VARIANT.get(
			MainsRegions.resolve(AppPrefs.mains_region), "usa"))
		variant = want if TAP_JACKS.has(want) else "usa"
	input = PowerInput.on(self)
	input.noun = unit_label()
	_fit_shapes()
	if kind == "pack":
		_build_pack()
	else:
		_build_tap()
	print("[Power] %s built%s" % [unit_label(), " (jack %s, %s)" % [jack.connector, variant]
		if jack != null else ", six AA seats"])


## What the player calls it.
func unit_label() -> String:
	return "battery pack" if kind == "pack" else "AC adapter tap"


## The save type of this one.
func save_type() -> String:
	return str(TYPES.get(kind, TYPES["pack"]))


## So Port.get_device() finds an owner for the tap's jack, which is what a save
## records the adapter's plug against (EthernetHub's reason). Nothing about picture
## or sound passes here.
func on_av_topology_changed(_links: Array) -> void:
	pass


## The controller it is clipped to, or null when it is loose.
func get_controller() -> Node3D:
	var n := get_picked_up_by()
	while n != null:
		if n is RetroController:
			return n as Node3D
		n = n.get_parent()
	return null


## The primitive's own meshes (a dressing mod hides them; the seats, the lid's slot
## and the jack stay): the boxes directly under its Shell, never the zones' own
## highlight meshes below them.
func shell_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var shell := get_node_or_null("Shell")
	if shell != null:
		for n: Node in shell.get_children():
			if n is MeshInstance3D:
				out.append(n as MeshInstance3D)
	return out


# ── building it ──────────────────────────────────────────────────────────────

func _fit_shapes() -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var box := BoxShape3D.new()
		box.size = SIZE
		shape.shape = box
	var pointer := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if pointer != null:
		var target := BoxShape3D.new()
		target.size = SIZE + Vector3(0.012, 0.012, 0.012)
		pointer.shape = target


func _build_pack() -> void:
	var root := Node3D.new()
	root.name = "Shell"
	add_child(root)
	var inner_z := SIZE.z - LID
	var mid_z := -LID * 0.5
	var hy := SIZE.y * 0.5
	var hx := SIZE.x * 0.5
	# Front (against the bay) and back walls, the two sides, the far end.
	_box(root, Vector3(SIZE.x, FRONT_WALL, inner_z), Vector3(0, hy - FRONT_WALL * 0.5, mid_z), PACK_COLOR)
	_box(root, Vector3(SIZE.x, BACK_WALL, inner_z), Vector3(0, -hy + BACK_WALL * 0.5, mid_z), PACK_COLOR)
	var side_h := SIZE.y - FRONT_WALL - BACK_WALL
	var side_y := (FRONT_WALL - BACK_WALL) * 0.5
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(SIDE_WALL, side_h, inner_z), Vector3(s * (hx - SIDE_WALL * 0.5), side_y, mid_z),
			PACK_COLOR)
	var far := -SIZE.z * 0.5
	_box(root, Vector3(SIZE.x - SIDE_WALL * 2.0, side_h, END_WALL),
		Vector3(0, side_y, far + END_WALL * 0.5), PACK_COLOR)
	# The dark inside, seen down the open end with the lid off, and the dividers
	# between the three columns.
	_box(root, Vector3(SIZE.x - SIDE_WALL * 2.0, side_h, 0.0006),
		Vector3(0, side_y, far + END_WALL + 0.0003), INSIDE)
	for s: float in [-0.5, 0.5]:
		_box(root, Vector3(PITCH - CELL_D, side_h, inner_z - END_WALL),
			Vector3(s * PITCH, side_y, mid_z + END_WALL * 0.5), DIVIDER)
	# Six cells, three columns of two. The front layer's + ends toward the lid, the
	# back layer's toward the far end; the marker's +Y out of the pack's back.
	var n := 0
	for layer: int in 2:
		var mid := CELL_FRONT if layer == 0 else CELL_BACK
		var plus := Vector3.BACK if layer == 0 else Vector3.FORWARD
		for col: int in 3:
			n += 1
			var marker := Node3D.new()
			marker.name = "BatteryAA%d" % n
			var out := Vector3.DOWN
			marker.transform = Transform3D(Basis(out.cross(plus), out, plus),
				mid + Vector3((col - 1) * PITCH, 0, 0))
			root.add_child(marker)
			# The far end's plate (a + end) or spring (a - end).
			_box(root, Vector3(0.007, 0.007, 0.0008),
				Vector3((col - 1) * PITCH, mid.y, far + END_WALL + 0.0007), CONTACT)
	# The lid over the open end, its outer face +Z.
	var lid_out := Vector3.BACK
	var lid_x := Vector3.RIGHT
	var seat := Transform3D(Basis(lid_x, lid_out, lid_x.cross(lid_out)),
		Vector3(0, 0, SIZE.z * 0.5 - LID * 0.5))
	var lid_slot := CoverSlots.on(self).build(LID_SOCKET, root, seat, Vector3(SIZE.x, LID, SIZE.y))
	lid_slot.has_picked_up.connect(_tint_lid)
	if lid_slot.picked_up_object != null:
		_tint_lid(lid_slot.picked_up_object)
	CellSlots.build_seats(root)


func _build_tap() -> void:
	var root := Node3D.new()
	root.name = "Shell"
	add_child(root)
	var hy := SIZE.y * 0.5
	var hx := SIZE.x * 0.5
	var hz := SIZE.z * 0.5
	# The base: solid from the channel's floor to the face on the bay, and a rim 2 mm
	# wide round the channel up to the split.
	_box(root, Vector3(SIZE.x, hy - TAP_FLOOR, SIZE.z), Vector3(0, (hy + TAP_FLOOR) * 0.5, 0), PACK_COLOR)
	var rim_h := TAP_FLOOR - TAP_SPLIT
	var rim_y := (TAP_FLOOR + TAP_SPLIT) * 0.5
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.002, rim_h, SIZE.z), Vector3(s * (hx - 0.001), rim_y, 0), PACK_COLOR)
		_box(root, Vector3(SIZE.x - 0.004, rim_h, 0.002), Vector3(0, rim_y, s * (hz - 0.001)), PACK_COLOR)
	# The channel's floor, dark.
	_box(root, Vector3(SIZE.x - 0.004, 0.0004, SIZE.z - 0.004), Vector3(0, TAP_FLOOR - 0.0002, 0), INSIDE)
	# The gray jack, standing on the floor, its mouth 2.8 mm under the split.
	_box(root, Vector3(0.012, TAP_FLOOR - JACK_AT.y, 0.014),
		Vector3(JACK_AT.x, (TAP_FLOOR + JACK_AT.y) * 0.5, JACK_AT.z), JACK_COLOR)
	jack = _DC_PORT.instantiate() as DcPort
	jack.name = "DcIn"
	jack.connector = str(TAP_JACKS.get(variant, TAP_JACKS["usa"]))
	# The socket's +Z toward the lid (-Y), its +Y toward the grips.
	var z := Vector3.DOWN
	var y := Vector3.BACK
	jack.transform = Transform3D(Basis(y.cross(z), y, z), JACK_AT)
	add_child(jack)
	input.add_inlet(jack)
	jack.has_picked_up.connect(func(_what: Node3D) -> void: _refresh_jack.call_deferred())
	jack.has_dropped.connect(func() -> void: _refresh_jack.call_deferred())
	# The lid: the box's back, its outer face -Y.
	var out := Vector3.DOWN
	var x := Vector3.RIGHT
	var lid_mid := (-hy + TAP_SPLIT - 0.00015) * 0.5
	var seat := Transform3D(Basis(x, out, x.cross(out)), Vector3(0, lid_mid, 0))
	var lid_slot := CoverSlots.on(self).build(TAP_LID_SOCKET, root, seat,
		Vector3(SIZE.x, TAP_LID_THICK, SIZE.z))
	lid_slot.has_picked_up.connect(func(what: Node3D) -> void:
		_tint_lid(what)
		_refresh_jack.call_deferred())
	lid_slot.has_dropped.connect(func() -> void: _refresh_jack.call_deferred())
	_refresh_jack.call_deferred()


## The tap's jack shut while its lid is on: it takes no plug, and the plug in it
## cannot be taken out (CellSlots._refresh's arrangement).
func _refresh_jack() -> void:
	if jack == null or not is_inside_tree():
		return
	var covers := CoverSlots.of(self)
	var shut := covers != null and covers.is_on(TAP_LID_SOCKET)
	jack.enabled = not shut
	var plug := jack.picked_up_object as XRToolsPickable
	if is_instance_valid(_held_shut) and _held_shut != plug:
		_held_shut.enabled = true
		_held_shut = null
	if is_instance_valid(plug):
		plug.enabled = not shut
		_held_shut = plug if shut else null


func _exit_tree() -> void:
	if is_instance_valid(_held_shut):
		_held_shut.enabled = true
	_held_shut = null
	super()


## A lid wears the unit's colour while it is on it, and keeps it once off.
func _tint_lid(what: Node3D) -> void:
	var mesh := what.get_node_or_null("Mesh") as MeshInstance3D if what != null else null
	if mesh != null and mesh.material_override == null:
		mesh.material_override = _material(PACK_COLOR)


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.3 if color == CONTACT else 0.55
	m.metallic = 0.85 if color == CONTACT else 0.0
	return m


static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mi.mesh = box
	mi.position = at
	root.add_child(mi)
