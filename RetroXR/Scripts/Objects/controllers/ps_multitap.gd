## PsMultitap — Sony's PlayStation Multitap (SCPH-1070), a primitive stand-in. From
## photographs of the unit (docs/dev/four-player-adapters.md):
##
##   * A light grey V of two arms, its vertex toward the players and rounded, the
##     cord leaving the inner corner toward the console.
##   * Four ports, A and B on the left arm's outer face, C and D on the right's,
##     each a controller socket with a MEMORY CARD slot above it, lettered on top.
##   * ONE connector on the cord that goes into a console's controller port AND the
##     memory card slot over it (ControllerPlug.covers_card_slot): the console's own
##     slot for that port is filled by it, and the tap's slot A is that slot now.
##   * No switch.
##
## What the cores do: pcsx_rearmed (RetroXR's PlayStation core) turns its multitap on
## from an OPTION (pcsx_rearmed_multitap: port 1 / port 2 / both), pinned here from
## which ports hold a tap (ForcedCoreOptions.ps_multitap, live through
## RetroSystem.refresh_multitap_option). Its layout (pad.c): a tap in port 1 is
## players 1-4 on libretro ports 0-3, and the console's port 2 then reads libretro
## port 4 -- so a tap in port 1 moves whatever is in port 2 there
## (RetroSystem.set_socket_port); a tap in port 2 is players 2-5 (1-4), or 5-8
## (4-7) beside another tap. Empty tap sockets are announced as nothing: the tap
## reports no pad in them. The core emulates no cards on a tap: slot A is passed
## through as the console's slot for that port (MemoryCardController), and B, C and
## D take a card that no core reads.
##
## Sizes are estimates: arms 130 mm along their outer faces, 34 mm deep, 36 mm tall,
## at 90 degrees.
class_name PsMultitap
extends FourPlayerAdapter


const _PS1_PLUG := "res://Scenes/Objects/controllers/playstation/ps1_plug.res"

const ARM_LENGTH := 0.130
const ARM_DEPTH := 0.034
const HEIGHT := 0.036
## The vertex is rounded by a post of this radius, tangent to both outer faces.
const VERTEX_R := ARM_DEPTH
## Each port's distance from the vertex along its arm's outer face, A to D.
const PORT_T := [0.106, 0.058, 0.058, 0.106]
## Which arm each port is on: -1 left (A, B), +1 right (C, D).
const PORT_SIDE := [-1, -1, 1, 1]
const LETTERS := ["A", "B", "C", "D"]
## The controller socket's middle, and the card slot's, above the floor.
const SOCKET_Y := 0.012
const CARD_Y := 0.027

const GREY := Color(0.70, 0.70, 0.68)
const DARK := Color(0.03, 0.03, 0.035)
const INK := Color(0.30, 0.30, 0.32)

var _card_zones: Array = []
var _tap_cards: Array = [null, null, null, null]
## Where slot A's card is passed through to now: that console and its slot.
var _card_sys: RetroSystem = null
var _card_slot := -1
## The console whose port 2 this tap moved to libretro port 4 (a tap in port 1).
var _moved_port_two: RetroSystem = null


func _init() -> void:
	connector = Connectors.controller_port_of("psx")


func _ready() -> void:
	add_to_group(_tap_group())
	super._ready()


func save_type() -> String:
	return "ps_multitap"


func _tag() -> String:
	return "PsMultitap"


func _mode_text() -> String:
	return "no switch"


# ── What a kind of tap says (Ps2Multitap overrides these) ─────────────────────

## The group SystemPorts counts this kind of tap by (ps_multitap_sockets), so the
## core option follows only the taps its console's games read.
func _tap_group() -> String:
	return "ps_multitap"


## The console whose games read this tap as a multitap.
func _target_system() -> String:
	return "psx"


## The memory cards its slots take.
func _card_family() -> String:
	return "playstation"


## The connector's moulding.
func _plug_colour() -> Color:
	return GREY


## Where port `i`'s face is, +Z out of it and +Y up, and its point on that face
## at height `y`.
func _port_basis(i: int) -> Basis:
	return _face_basis(i)


func _port_point(i: int, y: float) -> Vector3:
	return _face_point(i, y)


## The controller socket's middle and the card slot's, above the floor.
func _socket_height() -> float:
	return SOCKET_Y


func _card_height() -> float:
	return CARD_Y


## Whether the console the lead is in reads this tap as a multitap: a SCPH-1070
## in a PlayStation, a SCPH-10090 in a PlayStation 2. The connectors are the same
## shape, so either goes into either console; in the other one, socket A is that
## controller port's pad and B-D reach nothing (docs/dev/four-player-adapters.md:
## a choice, not measured).
func _active() -> bool:
	return is_instance_valid(_system) and _system.systemid == _target_system()


# ── Where it is ───────────────────────────────────────────────────────────────

## The console socket the lead is in, or -1.
func _seat() -> int:
	if not is_instance_valid(_system) or _lead() == null:
		return -1
	var sockets := _system.cabinet_ports_of_plug(_lead())
	return sockets[0] if not sockets.is_empty() else -1


## The libretro port of player A: the port its own socket drives (port 2's moves
## to 4 beside a tap in port 1).
func _base() -> int:
	var seat := _seat()
	if seat < 0:
		return -1
	return _system.controller_ports().libretro_port_for(RETRO_DEVICE_JOYPAD, seat)


func _routes() -> Array[int]:
	var out: Array[int] = [-1, -1, -1, -1]
	var base := _base()
	if base < 0:
		return out
	if not _active():
		out[0] = base
		return out
	for i in range(SOCKETS):
		out[i] = base + i
	return out


func _owned_ports() -> Array[int]:
	var out: Array[int] = []
	var base := _base()
	if base >= 0:
		for i in range(SOCKETS if _active() else 1):
			out.append(base + i)
	return out


## Each port is the pad in its socket as itself, or nothing: the tap answers "no
## pad" for an empty socket.
func port_device(_machine: Node, port: int) -> Dictionary:
	var dev := socket_device(port - _base())
	return dev if not dev.is_empty() else {"type": RETRO_DEVICE_NONE, "names": PackedStringArray()}


func _dead_reason(_i: int) -> String:
	if is_instance_valid(_system) and not _active():
		return ": a %s's games do not read this tap; it is for the %s" % [_system.systemid, _target_system()]
	return ": the lead is in no console"


## The layout first (port 2 moves while a tap is in port 1), then the sockets, then
## slot A's card and the core's option.
func _build_routes() -> void:
	_lay_out(_seat())
	super._build_routes()
	_sync_card_a()
	if is_instance_valid(_system):
		_system.refresh_multitap_option()


func on_unplugged() -> void:
	var sys := _system
	super.on_unplugged()
	if _system == null and is_instance_valid(sys):
		_lay_out(-1)
		_sync_card_a()
		sys.refresh_multitap_option()


## In port 1, the console's port 2 reads libretro port 4; anywhere else, not by
## this tap's doing.
func _lay_out(seat: int) -> void:
	if seat == 0 and _active():
		if _moved_port_two != _system:
			_put_port_two_back()
			_moved_port_two = _system
			print("[%s] in port 1: the console's port 2 is libretro port 4 now" % _tag())
			_system.set_socket_port(1, 4)
	else:
		_put_port_two_back()


func _put_port_two_back() -> void:
	if is_instance_valid(_moved_port_two):
		print("[%s] out of port 1: the console's port 2 is its own again" % _tag())
		_moved_port_two.set_socket_port(1, -1)
	_moved_port_two = null


func _exit_tree() -> void:
	_put_port_two_back()
	if is_instance_valid(_card_sys) and _card_slot >= 0:
		_card_sys.memcards().on_memcard_removed(_card_slot)
	_card_sys = null
	_card_slot = -1
	super._exit_tree()


# ── Cards ─────────────────────────────────────────────────────────────────────

## Slot A's card is the console's card for the port the tap is in; nothing else.
func _sync_card_a() -> void:
	var seat := _seat()
	var card: Node3D = _tap_cards[0] if is_instance_valid(_tap_cards[0]) else null
	var want_sys: RetroSystem = _system if seat >= 0 and seat < 2 and card != null 		and _system.card_family() == _card_family() else null
	var want_slot := seat if want_sys != null else -1
	if want_sys == _card_sys and want_slot == _card_slot:
		return
	if is_instance_valid(_card_sys) and _card_slot >= 0:
		print("[%s] slot A's card leaves the console's card slot %d" % [_tag(), _card_slot + 1])
		_card_sys.memcards().on_memcard_removed(_card_slot)
	_card_sys = want_sys
	_card_slot = want_slot
	if want_sys != null:
		print("[%s] slot A's card is the console's card %d" % [_tag(), want_slot + 1])
		want_sys.memcards().on_memcard_inserted(card, want_slot)


func _on_card_in(i: int, card: Node3D) -> void:
	_tap_cards[i] = card
	if i == 0:
		_sync_card_a()
	else:
		print("[%s] a card in slot %s: no core here reads a tap's slots B-D" % [_tag(), LETTERS[i]])


func _on_card_out(i: int) -> void:
	_tap_cards[i] = null
	if i == 0:
		_sync_card_a()


## A memory card of this tap's family, as the console's slot takes.
func _accepts_card(obj: Node3D) -> bool:
	return obj != null and "family" in obj and str(obj.get("family")) == _card_family()


## The card in each slot, A to D, null where empty (ScenePersistence).
func card_peripherals() -> Array:
	var out: Array = []
	for c: Variant in _tap_cards:
		out.append(c if is_instance_valid(c) else null)
	return out


## Put `card` back in slot `i` (a save's).
func restore_card(i: int, card: Node3D) -> void:
	if i < 0 or i >= _card_zones.size() or not is_instance_valid(card):
		return
	var zone := _card_zones[i] as XRToolsSnapZone
	if is_instance_valid(zone.picked_up_object):
		push_warning("[%s] card slot %s already holds a card" % [_tag(), LETTERS[i]])
		return
	if card is XRToolsPickable and (card as XRToolsPickable).is_picked_up():
		push_warning("[%s] that card is held elsewhere; slot %s left empty" % [_tag(), LETTERS[i]])
		return
	print("[%s] restoring a card into slot %s" % [_tag(), LETTERS[i]])
	zone.pick_up_object(card)


# ── Body ──────────────────────────────────────────────────────────────────────

## The outer corner where the two outer faces would meet.
static func _vertex() -> Vector3:
	return Vector3(0.0, 0.0, VERTEX_R * sqrt(2.0) * 0.5 + 0.03)


## The way port `i`'s face looks (its arm's outer normal) and its arm's direction
## away from the vertex.
static func _normal(i: int) -> Vector3:
	return Vector3(0.7071 * float(PORT_SIDE[i]), 0.0, 0.7071)


static func _along(i: int) -> Vector3:
	return Vector3(0.7071 * float(PORT_SIDE[i]), 0.0, -0.7071)


## A face's basis: +Z out of it, +Y up.
static func _face_basis(i: int) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(45.0 * float(PORT_SIDE[i])))


## Port `i`'s point on its face at height `y`.
static func _face_point(i: int, y: float) -> Vector3:
	return _vertex() + _along(i) * float(PORT_T[i]) + Vector3(0.0, y, 0.0)


func _build_body() -> void:
	var grey := _material(GREY, 0.55)
	var dark := _material(DARK, 0.9)
	var ink := _material(INK, 0.7)
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	# Collision: each arm its own box and the vertex its post, so the space between
	# the arms is open (a hull of the V would fill it).
	var shapes: Array[CollisionShape3D] = []
	var first := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if first != null:
		shapes.append(first)
	for extra: String in ["CollisionRight", "CollisionVertex"]:
		var c := CollisionShape3D.new()
		c.name = extra
		add_child(c)
		shapes.append(c)
	for side: int in [-1, 1]:
		var i := 0 if side < 0 else 3
		var along := _along(i)
		var n := _normal(i)
		var mid_t := (VERTEX_R + ARM_LENGTH) * 0.5
		var centre := _vertex() + along * mid_t - n * (ARM_DEPTH * 0.5) + Vector3(0.0, HEIGHT * 0.5, 0.0)
		var arm_size := Vector3(ARM_LENGTH - VERTEX_R, HEIGHT, ARM_DEPTH)
		_add_box(body, arm_size, Transform3D(_face_basis(i), centre), grey,
			"Arm%s" % ("Left" if side < 0 else "Right"))
		var shape_i := 0 if side < 0 else 1
		if shape_i < shapes.size():
			var arm_box := BoxShape3D.new()
			arm_box.size = arm_size
			shapes[shape_i].shape = arm_box
			shapes[shape_i].transform = Transform3D(_face_basis(i), centre)
	# The rounded vertex: a post tangent to both outer faces.
	var post := MeshInstance3D.new()
	post.name = "Vertex"
	var cyl := CylinderMesh.new()
	cyl.top_radius = VERTEX_R
	cyl.bottom_radius = VERTEX_R
	cyl.height = HEIGHT
	cyl.radial_segments = 32
	post.mesh = cyl
	post.material_override = grey
	body.add_child(post)
	var post_at := _vertex() - Vector3(0.0, 0.0, VERTEX_R * sqrt(2.0))
	post.position = post_at + Vector3(0.0, HEIGHT * 0.5, 0.0)
	if shapes.size() > 2:
		var post_shape := CylinderShape3D.new()
		post_shape.radius = VERTEX_R
		post_shape.height = HEIGHT
		shapes[2].shape = post_shape
		shapes[2].position = post.position

	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in range(SOCKETS):
		var fb := _face_basis(i)
		var out := _normal(i)
		# The controller socket's mouth and the card slot's slit, both set in the face.
		_add_box(body, Vector3(0.041, 0.0110, 0.0016), Transform3D(fb, _face_point(i, SOCKET_Y) + out * 0.0003), dark)
		_add_box(body, Vector3(0.044, 0.0065, 0.0016), Transform3D(fb, _face_point(i, CARD_Y) + out * 0.0003), dark)
		# The letter on top, over the port.
		var top := _face_point(i, HEIGHT + 0.0004) - out * 0.010
		var lbl := _add_label(body, LETTERS[i], Transform3D(Basis(Vector3.UP, deg_to_rad(45.0 * float(PORT_SIDE[i]))) * flat, top),
			INK, 22)
		lbl.name = "SocketLabel%d" % (i + 1)
		_labels.append(lbl)
	# Slot A's card mark: a small card outline on top beside the letter.
	var mark_at := _face_point(0, HEIGHT + 0.0004) - _normal(0) * 0.010 + _along(0) * 0.010
	_add_box(body, Vector3(0.007, 0.0004, 0.009), Transform3D(_face_basis(0), mark_at), ink, "CardMark")

	var boot := MeshInstance3D.new()
	var boot_cyl := CylinderMesh.new()
	boot_cyl.top_radius = 0.0035
	boot_cyl.bottom_radius = 0.005
	boot_cyl.height = 0.010
	boot.mesh = boot_cyl
	boot.material_override = grey
	add_child(boot)
	boot.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), _cable_attach_point.position + Vector3(0, 0, 0.003))


## A controller socket on its face: +Z out, rolled half round about Z as the
## console's front ports are, so a plug (grab point turned about X) seats upright.
func _socket_transform(i: int) -> Transform3D:
	return Transform3D(_port_basis(i) * Basis(Vector3.BACK, PI), _port_point(i, _socket_height()))


func _socket_fits(plug: Node3D) -> bool:
	var c := Connectors.of(plug)
	return c.is_empty() or c == connector


func _build_mode_switch() -> VRSlider:
	return null


## The four card slots, over the sockets: as the console's (no roll -- a card has no
## grab point to compose one with; playstation_model.gd).
func _build_extra_controls() -> void:
	for i in range(SOCKETS):
		var zone: XRToolsSnapZone = SNAP_ZONE_SCENE.instantiate()
		zone.name = "CardSlot%s" % LETTERS[i]
		zone.snap_require = "memory_card"
		zone.snap_filter = _accepts_card
		zone.grab_distance = 0.04
		add_child(zone)
		zone.transform = Transform3D(_port_basis(i), _port_point(i, _card_height()))
		var idx := i
		zone.has_picked_up.connect(func(obj: Node3D) -> void: _on_card_in(idx, obj))
		zone.has_dropped.connect(func() -> void: _on_card_out(idx))
		_card_zones.append(zone)


## The connector: the PlayStation's controller plug with a card tongue standing over
## it, which goes into the card slot above the port. Placed for the console it seats
## in (_place_tongue), since the slot's height above the port is that model's.
func _dress_plug(plug: ControllerPlug) -> void:
	plug.covers_card_slot = true
	plug.set_plug_mesh(_PS1_PLUG)
	var tongue := MeshInstance3D.new()
	tongue.name = "CardTongue"
	var box := BoxMesh.new()
	box.size = Vector3(0.040, 0.0045, 0.026)
	tongue.mesh = box
	tongue.material_override = _material(_plug_colour(), 0.55)
	plug.add_child(tongue)
	tongue.position = Vector3(0.0, 0.0145, -0.004)
	_shape_hood(plug)
	PointerFit.watch(plug)


## The moulding that makes plug and tongue one connector: a block over the back of
## both, from the plug's top to the tongue's, so what goes into the slot and the
## port is one piece with a gap only where the console's face goes between them.
func _shape_hood(plug: Node3D) -> void:
	var tongue := plug.get_node_or_null("CardTongue") as Node3D
	if tongue == null:
		return
	var hood := plug.get_node_or_null("ConnectorHood") as MeshInstance3D
	if hood == null:
		hood = MeshInstance3D.new()
		hood.name = "ConnectorHood"
		hood.material_override = _material(_plug_colour(), 0.55)
		plug.add_child(hood)
	var plug_top := 0.0048
	var plug_back := -0.0317
	var top := tongue.position.y + 0.00225
	var front := tongue.position.z - 0.006
	var box := BoxMesh.new()
	box.size = Vector3(0.040, maxf(0.001, top - plug_top + 0.001), maxf(0.002, front - plug_back))
	hood.mesh = box
	hood.position = Vector3(0.0, (top + plug_top) * 0.5, (front + plug_back) * 0.5)


## The tongue in the card slot of the port the lead seated in.
func _place_tongue() -> void:
	var lead := _lead()
	var seat := _seat()
	if lead == null or seat < 0:
		return
	var tongue := lead.get_node_or_null("CardTongue") as Node3D
	var slots: Array = _system.memcard_slots()
	if tongue == null or seat >= slots.size():
		return
	var slot := slots[seat] as Node3D
	var at := slot.global_position + slot.global_basis.z.normalized() * 0.010
	tongue.position = lead.global_transform.affine_inverse() * at
	_shape_hood(lead)
	print("[%s] the connector's card tongue sits in card slot %d (%.1f mm over the plug)"
		% [_tag(), seat + 1, tongue.position.y * 1000.0])


func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	_place_tongue()
