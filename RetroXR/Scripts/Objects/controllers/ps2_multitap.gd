## Ps2Multitap — Sony's PlayStation 2 Multitap (SCPH-10090), a primitive stand-in.
## From Evan-Amos's photograph of the unit (Wikimedia Commons, public domain;
## docs/dev/four-player-adapters.md):
##
##   * A black, flat, rectangular box, its sides ribbed with the PlayStation 2's
##     horizontal grooves.
##   * Four ports, A and B side by side on one long face, C and D on the other,
##     each a controller socket with a MEMORY CARD slot over it; the letters are
##     on top beside each port, with a card mark beside A. Going round from the
##     cord's end: A, B on the front, then C, D back along the far face.
##   * The cord leaves one short end, and ends in one connector that fills a
##     console's controller port AND the card slot over it -- PsMultitap's
##     arrangement, the PlayStation's.
##   * No switch.
##
## What the cores do: pcee2 and RetroXR's LRPS2 build (pcsx2, fork v7+) both turn
## the tap on from pcsx2_multitap (disabled / port1 / port2 / both, read live), with
## pcee2's layout in both: libretro ports are 1A, then 1B-1D with a tap in port 1,
## then 2A, then 2B-2D with a tap in port 2. So a tap in port 1 is players 1-4 and
## the console's port 2 is libretro port 4 -- the same layout as pcsx_rearmed's,
## which is why everything but the body is PsMultitap's. Neither core emulates a
## card on a tap: slot A is the console's slot for that port, B-D no core's.
##
## Sizes are estimates: 140 x 78 x 31 mm, the ports 64 mm apart on each face.
class_name Ps2Multitap
extends PsMultitap


const LENGTH := 0.140
const DEPTH := 0.078
const TALL := 0.031
## Each port's middle along the box (x), A to D: A and B on the front (+Z), C
## and D on the back (-Z), D at the cord's end as A is.
const PORT_X := [-0.032, 0.032, 0.032, -0.032]
const PORT_FRONT := [true, true, false, false]
## The sides' ribs: plates of this pitch with a groove between.
const RIBS := 5
const GROOVE := 0.0012

const BLACK := Color(0.085, 0.085, 0.09)
const CORE := Color(0.025, 0.025, 0.028)
const PRINT := Color(0.62, 0.62, 0.64)


func save_type() -> String:
	return "ps2_multitap"


func _tag() -> String:
	return "Ps2Multitap"


func _tap_group() -> String:
	return "ps2_multitap"


func _target_system() -> String:
	return "ps2"


func _card_family() -> String:
	return "playstation2"


func _plug_colour() -> Color:
	return BLACK


func _port_basis(i: int) -> Basis:
	return Basis.IDENTITY if PORT_FRONT[i] else Basis(Vector3.UP, PI)


func _port_point(i: int, y: float) -> Vector3:
	var z := DEPTH * 0.5 if PORT_FRONT[i] else -DEPTH * 0.5
	return Vector3(float(PORT_X[i]), y, z)


## From the photograph: the card slot in the second rib from the top, the socket
## in the fourth.
func _socket_height() -> float:
	return 0.0095


func _card_height() -> float:
	return 0.0225


## The PlayStation's connector, moulded black as the photograph's is.
func _dress_plug(plug: ControllerPlug) -> void:
	super._dress_plug(plug)
	var model := plug.get_node_or_null("PlugModel") as GeometryInstance3D
	if model != null:
		model.material_override = _material(BLACK, 0.5)
	else:
		push_warning("[Ps2Multitap] the connector has no PlugModel to colour")


func _build_body() -> void:
	var black := _material(BLACK, 0.5)
	var core := _material(CORE, 0.8)
	var dark := _material(DARK, 0.9)
	var ink := _material(PRINT, 0.6)
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)

	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var box := BoxShape3D.new()
		box.size = Vector3(LENGTH, TALL, DEPTH)
		shape.shape = box
		shape.position = Vector3(0.0, TALL * 0.5, 0.0)

	# The ribs: a core set in by the grooves' depth, and plates standing out of it.
	var inset := 0.0016
	_add_box(body, Vector3(LENGTH - 2.0 * inset, TALL, DEPTH - 2.0 * inset),
		Transform3D(Basis.IDENTITY, Vector3(0.0, TALL * 0.5, 0.0)), core, "Core")
	var pitch := (TALL + GROOVE) / float(RIBS)
	for r in RIBS:
		var bottom := float(r) * pitch
		var top := minf(bottom + pitch - GROOVE, TALL)
		_add_box(body, Vector3(LENGTH, top - bottom, DEPTH),
			Transform3D(Basis.IDENTITY, Vector3(0.0, (top + bottom) * 0.5, 0.0)), black, "Rib%d" % (r + 1))

	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in range(SOCKETS):
		var fb := _port_basis(i)
		var out := fb.z
		# The controller socket's mouth and the card slot's slit, set in the face.
		_add_box(body, Vector3(0.041, 0.0105, 0.0016), Transform3D(fb, _port_point(i, _socket_height()) + out * 0.0003), dark)
		_add_box(body, Vector3(0.044, 0.0060, 0.0016), Transform3D(fb, _port_point(i, _card_height()) + out * 0.0003), dark)
		# The letter on top, over the port, read from that face.
		var top := _port_point(i, TALL + 0.0004) - out * 0.008
		# About 7 mm tall, as the photograph's letters are beside a 41 mm socket.
		var lbl := _add_label(body, LETTERS[i], Transform3D(fb * flat, top), PRINT, 18, 0.0004)
		lbl.name = "SocketLabel%d" % (i + 1)
		_labels.append(lbl)
	# Slot A's card mark: a small card outline on top beside the letter.
	var mark_at := _port_point(0, TALL + 0.0004) - _port_basis(0).z * 0.008 + Vector3(0.010, 0.0, 0.0)
	_add_box(body, Vector3(0.007, 0.0004, 0.009), Transform3D(Basis.IDENTITY, mark_at), ink, "CardMark")
	# The unit's name across the top, as the real one has it (no maker's mark).
	var name_lbl := _add_label(body, "MULTITAP", Transform3D(Basis(Vector3.UP, PI * 0.5) * flat,
		Vector3(0.010, TALL + 0.0004, 0.0)), PRINT, 26, 0.0004)
	name_lbl.name = "NameLabel"

	# The cord leaves the middle of the short end at -X: the attach point's -Z is
	# that way (Basis(UP, +90 deg) turns +Z onto +X), set here rather than in the
	# scene so the rows-versus-columns trap of a .tscn basis cannot invert it.
	_cable_attach_point.transform = Transform3D(Basis(Vector3.UP, PI * 0.5),
		Vector3(-LENGTH * 0.5 - 0.004, TALL * 0.5, 0.0))
	var boot := MeshInstance3D.new()
	boot.name = "CordBoot"
	var boot_cyl := CylinderMesh.new()
	boot_cyl.top_radius = 0.0035
	boot_cyl.bottom_radius = 0.0055
	boot_cyl.height = 0.010
	boot.mesh = boot_cyl
	boot.material_override = black
	add_child(boot)
	# Its axis along X, the wide end (the cylinder's -Y) against the body.
	boot.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5),Vector3(-LENGTH * 0.5 - 0.004, TALL * 0.5, 0.0))
