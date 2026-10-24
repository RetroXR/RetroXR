## Bakes the four arcade bays to Scenes/Objects/peripherals/arcade_bay_<kind>.tscn.
##
## Run once per kind, out of band (and after Tools/gen/gen_arcade_cabinet.gd, which bakes the socket
## the cabinet side of a JAMMA lead goes in; this script instances the cable's socket the same way):
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_bay.gd -- --kind=jamma
##
## A bay is the box a board stands in, separate from the cabinet (ArcadeBayUnit). It is a pickable that
## clips into the cabinet's BayMount and is joined to a cabinet standing elsewhere by a JAMMA lead. What
## differs between the kinds is the connector the board goes into: a JAMMA edge socket for the JAMMA,
## laserdisc and discrete-logic bays (a laserdisc and a DICE board are JAMMA boards in this room), and
## the Neo Geo's cassette slot for the MVS. Origin on the floor at the middle of the base, front +Z, so
## the cabinet's mount marker (the compartment's floor) is where the bay's origin stands.
##
## The JAMMA bay is two boxes in one block: a CD-ROM bay under (a slot-loading drive for the CHD a few
## games need, with an EJECT button that pushes the disc half out), and the JAMMA shelf and board seat
## above it, lifted by the drive's height. They are one object, not separable. The other kinds have no
## drive: nothing they play has a disc.
##
## The sizes are ESTIMATES, like the cabinet's: no source gave a bay box's size.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_DIR := "res://Scenes/Objects/peripherals/"

const SCRIPT_UNIT := "res://Scripts/Objects/arcade/arcade_bay_unit.gd"
const SCRIPT_GRAB := "res://addons/godot-xr-tools/objects/grab_points/grab_point.gd"
const SCRIPT_HIGHLIGHT := "res://Scripts/Objects/highlights/pickable_highlight.gd"
const PORT_SCENE := "res://Scenes/Objects/cables/jamma_port.tscn"

## What a board stands on: the socket's top above the base, and the board's own half height
## (CART_SIZES arcade: 300 mm tall), so the seat is the socket's top plus half of it.
const SOCKET_TOP := 0.07
const BOARD_H := 0.30

## The CD-ROM bay under the JAMMA shelf: its height, and how far its slot's mouth sits up the front face.
const DRIVE_H := 0.05
const SLOT_Y := 0.026
const SCRIPT_BUTTON := "res://Scripts/Objects/widgets/vr_button.gd"


## kind -> its look and its size: base W x H x D, the colours, the legend on the front.
func _kinds() -> Dictionary:
	return {
		"jamma": {"size": Vector3(0.40, 0.05, 0.30), "body": Color(0.16, 0.17, 0.20),
			"trim": Color(0.90, 0.16, 0.28), "legend": "JAMMA", "pcb": Color(0.05, 0.32, 0.16)},
		"laserdisc": {"size": Vector3(0.40, 0.05, 0.30), "body": Color(0.12, 0.07, 0.20),
			"trim": Color(0.95, 0.75, 0.15), "legend": "LASERDISC", "pcb": Color(0.07, 0.13, 0.33)},
		"discrete": {"size": Vector3(0.40, 0.05, 0.30), "body": Color(0.22, 0.13, 0.07),
			"trim": Color(0.90, 0.85, 0.70), "legend": "DICE", "pcb": Color(0.30, 0.19, 0.07)},
		"mvs": {"size": Vector3(0.34, 0.035, 0.20), "body": Color(0.55, 0.56, 0.60),
			"trim": Color(0.85, 0.07, 0.10), "legend": "NEO GEO"},
	}


func _initialize() -> void:
	var kind := "jamma"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			kind = a.substr(7)
	var all := _kinds()
	if not all.has(kind):
		push_error("unknown kind: %s (%s)" % [kind, ", ".join(all.keys())])
		quit(1)
		return
	var v: Dictionary = all[kind]
	var size: Vector3 = v["size"]

	var root := RigidBody3D.new()
	root.name = "ArcadeBay"
	root.collision_layer = 4
	root.collision_mask = 196613
	root.mass = 2.0
	root.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	root.linear_damp = 5.0
	root.angular_damp = 8.0
	var phys := PhysicsMaterial.new()
	phys.friction = 0.8
	root.physics_material_override = phys
	root.set_script(load(SCRIPT_UNIT))
	root.set("bay_kind", kind)
	root.set("type_id", "arcade_bay_" + kind)

	var body := U.mat(v["body"], 0.3, 0.55)
	var trim := U.mat(v["trim"], 0.0, 0.4)
	var dark := U.mat(Color(0.03, 0.03, 0.035), 0.0, 0.7)
	var metal := U.mat(Color(0.65, 0.66, 0.70), 0.9, 0.35)

	var top := size.y
	var seat: Marker3D
	# Only the JAMMA bay carries the CD-ROM bay; everything else of it stands on top.
	var lift := DRIVE_H if kind == "jamma" else 0.0
	var deck: Node3D = root
	if lift > 0.0:
		deck = U.node(root, root, "Node3D", "Deck", Vector3(0, lift, 0)) as Node3D
		_build_drive(root, size, dark, metal, trim)
	if kind == "mvs":
		seat = _build_mvs(root, size, body, dark, metal)
		top = 0.035 + 0.030
	else:
		seat = _build_jamma_board(root, deck, size, v["pcb"], dark, metal)
		top = SOCKET_TOP + lift
	seat.name = "CartSeat"
	if kind == "mvs":
		U.box(root, root, "Stripe", Vector3(size.x, 0.006, 0.002), Vector3(0, size.y - 0.008, size.z * 0.5 + 0.001), trim)
		var legend := U.node(root, root, "Label3D", "Legend", Vector3(0, size.y * 0.5, size.z * 0.5 + 0.0025)) as Label3D
		legend.text = str(v["legend"])
		legend.pixel_size = 0.0006
		legend.font_size = 48
		legend.modulate = Color(0.95, 0.93, 0.85)
		legend.outline_size = 0
	else:
		# A coloured strip along the shelf's front edge, and the board's name silk-screened on it.
		U.box(root, deck, "Stripe", Vector3(size.x, 0.004, 0.002), Vector3(0, 0.009, size.z * 0.5 + 0.001), trim)
		var silk := U.node(root, deck, "Label3D", "Legend", Vector3(-0.07, 0.0365, 0.115)) as Label3D
		silk.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		silk.text = str(v["legend"])
		silk.pixel_size = 0.0007
		silk.font_size = 48
		silk.modulate = Color(0.92, 0.92, 0.80)
		silk.outline_size = 0

	# The sockets are on the FRONT, where a hand reaches them when the bay stands in its compartment with the
	# door open (the back faces the cabinet's rear wall): the JAMMA socket and, beside it, three phono INs.
	var port_y := size.y * 0.5 if kind == "mvs" else 0.034
	var port_scene := load(PORT_SCENE) as PackedScene
	if port_scene != null:
		var port := port_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		port.name = "JammaPort"
		deck.add_child(port)
		port.owner = root
		port.position = Vector3(0, port_y, size.z * 0.5 + 0.004)

	# Collision: the base box (a board in the slot is its own body). Pointer: a box a ray finds.
	var col := U.node(root, root, "CollisionShape3D", "CollisionShape3D", Vector3(0, top * 0.5, 0)) as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, top, size.z)
	col.shape = shape
	# Set back 10 mm from the front face: a ray finds the NEAREST pointable, and a box proud of the face
	# would hide the drive's EJECT button behind it.
	var pointer := U.node(root, root, "StaticBody3D", "PointerArea", Vector3(0, top * 0.5, -0.01)) as StaticBody3D
	pointer.collision_layer = 1048576
	pointer.collision_mask = 0
	var pcol := U.node(root, pointer, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(size.x + 0.02, top + 0.02, size.z)
	pcol.shape = pshape

	# IDENTITY grab point: a snap zone composes it, so the bay's origin lands exactly on the mount.
	var grab := U.node(root, root, "Marker3D", "GrabPoint") as Marker3D
	grab.visible = false
	grab.set_script(load(SCRIPT_GRAB))
	var hl := U.node(root, root, "Node3D", "PickableHighlight") as Node3D
	hl.set_script(load(SCRIPT_HIGHLIGHT))

	quit(U.save(root, OUT_DIR + "arcade_bay_%s.tscn" % kind))


## A JAMMA board's place, drawn as a motherboard on a shelf: a wooden mounting plate with a bracket
## along the back (where the sockets go, as a PC card's bracket carries its ports), a PCB on four brass
## standoffs, the 56-way edge connector the board stands in (ivory housing, 28 contacts a side, slot on
## top) with the harness running out of it as a bundle of coloured wires, the screw terminals the power
## supply's +5 V / +12 V / GND leads fork onto, and the usual crowd of chips, capacitors and a crystal.
## Nothing here is a measured part: the connector's pitch (3.96 mm, 28 a side) is the one real number.
## The seat is the connector's top plus half a board (SOCKET_TOP + BOARD_H / 2); returns CartSeat.
## Everything is parented to `deck`, which stands on the CD-ROM bay's top for the JAMMA kind.
func _build_jamma_board(root: Node, deck: Node3D, size: Vector3, pcb: Color, dark: Material, metal: Material) -> Marker3D:
	var wood := U.mat(Color(0.52, 0.40, 0.27), 0.0, 0.85)
	var green := U.mat(pcb, 0.0, 0.5)
	var trace := U.mat(pcb.lightened(0.18), 0.0, 0.45)
	var ivory := U.mat(Color(0.86, 0.82, 0.66), 0.0, 0.6)
	var gold := U.mat(Color(0.85, 0.66, 0.22), 1.0, 0.3)
	var chip := U.mat(Color(0.06, 0.06, 0.07), 0.0, 0.45)
	var brass := U.mat(Color(0.75, 0.60, 0.25), 0.9, 0.35)
	# The shelf and the bracket along its back.
	U.box(root, deck, "Base", Vector3(size.x, 0.018, size.z), Vector3(0, 0.009, 0), wood)
	U.box(root, deck, "Bracket", Vector3(size.x, 0.05, 0.003), Vector3(0, 0.025, -size.z * 0.5 + 0.0015), metal)
	# A second bracket along the FRONT, carrying the sockets a hand and a cord reach.
	U.box(root, deck, "FrontBracket", Vector3(size.x, 0.05, 0.003), Vector3(0, 0.025 + 0.018, size.z * 0.5 - 0.0015), metal)
	# The PCB on four standoffs.
	var pw := size.x - 0.04
	var pd := size.z - 0.06
	var pcb_y := 0.0335
	U.box(root, deck, "Pcb", Vector3(pw, 0.003, pd), Vector3(0, pcb_y, 0.01), green)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			U.cylinder(root, deck, "Standoff%s%s" % ["L" if sx < 0 else "R", "B" if sz < 0 else "F"], 0.004, 0.016,
				Vector3(sx * (pw * 0.5 - 0.008), 0.026, 0.01 + sz * (pd * 0.5 - 0.008)), brass)
	# Traces: lighter strips running between the parts.
	for i in 7:
		U.box(root, deck, "Trace%d" % i, Vector3(pw - 0.06, 0.0004, 0.0016),
			Vector3(0, pcb_y + 0.0017, -0.09 + i * 0.026), trace)
	for i in 5:
		U.box(root, deck, "TraceV%d" % i, Vector3(0.0016, 0.0004, pd - 0.06),
			Vector3(-0.14 + i * 0.07, pcb_y + 0.0017, 0.01), trace)
	# The edge connector: an ivory housing the board's comb goes into, a slot on top, contacts down both long sides.
	U.box(root, deck, "JammaSocket", Vector3(0.12, 0.035, 0.045), Vector3(0, pcb_y + 0.0015 + 0.0175, 0.0), ivory)
	U.box(root, deck, "SocketSlot", Vector3(0.112, 0.002, 0.006), Vector3(0, SOCKET_TOP + 0.0001, 0.0), U.mat(Color(0, 0, 0), 0.0, 0.9))
	for side in [-1.0, 1.0]:
		U.box(root, deck, "Contacts%s" % ("B" if side < 0 else "F"), Vector3(0.108, 0.006, 0.0008),
			Vector3(0, SOCKET_TOP - 0.006, side * 0.0229), gold)
	# Power terminals at the front left: three screw posts on a green block, red / yellow / black.
	U.box(root, deck, "PowerBlock", Vector3(0.05, 0.014, 0.016), Vector3(0.13, pcb_y + 0.0085, 0.10), U.mat(Color(0.10, 0.45, 0.20), 0.0, 0.6))
	for i in 3:
		U.cylinder(root, deck, "Terminal%d" % (i + 1), 0.0045, 0.006, Vector3(0.115 + i * 0.015, pcb_y + 0.017, 0.10),
			U.mat([Color(0.85, 0.12, 0.10), Color(0.92, 0.75, 0.10), Color(0.08, 0.08, 0.09)][i], 0.3, 0.5))
	# The CPU, other chips, a crystal and capacitors.
	U.box(root, deck, "Cpu", Vector3(0.052, 0.008, 0.016), Vector3(-0.09, pcb_y + 0.0055, -0.07), chip)
	U.box(root, deck, "Gfx", Vector3(0.030, 0.006, 0.030), Vector3(0.10, pcb_y + 0.0045, -0.06), chip)
	for i in 4:
		U.box(root, deck, "Chip%d" % (i + 1), Vector3(0.026, 0.005, 0.009), Vector3(0.07 + i * 0.001, pcb_y + 0.004, 0.06 + i * 0.016 - 0.02), chip)
	U.box(root, deck, "Crystal", Vector3(0.012, 0.004, 0.005), Vector3(-0.03, pcb_y + 0.0035, -0.10), metal)
	for i in 5:
		U.cylinder(root, deck, "Cap%d" % (i + 1), 0.007, 0.018, Vector3(-0.15 + i * 0.019, pcb_y + 0.0105, -0.115),
			U.mat(Color(0.10, 0.16, 0.42) if i % 2 == 0 else Color(0.06, 0.06, 0.07), 0.2, 0.5))
	# The harness: a bundle of coloured wires from the back of the connector out through the bracket.
	var wires := [Color(0.85, 0.12, 0.10), Color(0.92, 0.75, 0.10), Color(0.12, 0.45, 0.20),
		Color(0.15, 0.30, 0.75), Color(0.90, 0.90, 0.90), Color(0.08, 0.08, 0.09)]
	for i in wires.size():
		U.cylinder(root, deck, "Wire%d" % (i + 1), 0.0035, 0.20,
			Vector3(-0.02 + i * 0.008, pcb_y + 0.012 + (i % 2) * 0.004, -0.17), U.mat(wires[i], 0.0, 0.6), Vector3.BACK)
	return U.node(root, deck, "Marker3D", "CartSeat", Vector3(0, SOCKET_TOP + BOARD_H * 0.5, 0.0)) as Marker3D


## The CD-ROM bay: a slot-loading drive under the JAMMA shelf, the same width and depth. Its faceplate
## (front, +Z) has the slot a disc goes into, an EJECT button and a light; `DiscSeat` is the slot's mouth,
## where ArcadeBayUnit puts a snap zone. A disc rides in through it flat, label up, and EJECT pushes it
## half out again for a hand to take. Nothing of the mechanism inside is drawn: the case is solid.
func _build_drive(root: Node, size: Vector3, dark: Material, metal: Material, trim: Material) -> void:
	var case_mat := U.mat(Color(0.74, 0.73, 0.68), 0.0, 0.55)    # beige computer-case plastic
	var front_z := size.z * 0.5
	U.box(root, root, "DriveCase", Vector3(size.x, DRIVE_H, size.z), Vector3(0, DRIVE_H * 0.5, 0), case_mat)
	U.box(root, root, "DriveTrim", Vector3(size.x, 0.003, 0.002), Vector3(0, DRIVE_H - 0.0015, front_z + 0.001), trim)
	# The slot: a dark lip across the face, wide enough for a 120 mm disc.
	U.box(root, root, "DiscSlot", Vector3(0.14, 0.005, 0.004), Vector3(0, SLOT_Y, front_z + 0.001), dark)
	U.box(root, root, "DiscSlotLip", Vector3(0.15, 0.0015, 0.003), Vector3(0, SLOT_Y + 0.0035, front_z + 0.001), metal)
	var legend := U.node(root, root, "Label3D", "DriveLegend", Vector3(-0.12, 0.012, front_z + 0.0025)) as Label3D
	legend.text = "CD-ROM"
	legend.pixel_size = 0.0004
	legend.font_size = 48
	legend.modulate = Color(0.12, 0.12, 0.14)
	legend.outline_size = 0
	# A light that glows while the drive holds a disc (ArcadeBayUnit lights it).
	U.box(root, root, "DriveLed", Vector3(0.008, 0.004, 0.002), Vector3(0.10, 0.012, front_z + 0.001),
		U.mat(Color(0.1, 0.1, 0.1), 0.0, 0.4, Color(0.2, 1.0, 0.3), 0.0))
	# EJECT: a VRButton poked from the front, on the right of the face.
	var btn := U.node(root, root, "Area3D", "EjectButton", Vector3(0.15, 0.025, front_z + 0.001)) as Area3D
	btn.set_script(load(SCRIPT_BUTTON))
	btn.collision_layer = 0
	btn.collision_mask = 0
	btn.set("trigger_radius", 0.014)
	btn.set("depress_depth", 0.003)
	btn.set("depress_axis", Vector3(0, 0, -1))
	var col := U.node(root, btn, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.04, 0.03, 0.04)
	col.shape = shape
	col.position = Vector3(0, 0, 0.012)
	U.box(root, btn, "ButtonMesh", Vector3(0.026, 0.012, 0.004), Vector3(0, 0, 0.002),
		U.mat(Color(0.86, 0.84, 0.78), 0.0, 0.45))
	var tag := U.node(root, root, "Label3D", "EjectLegend", Vector3(0.15, 0.009, front_z + 0.0025)) as Label3D
	tag.text = "EJECT"
	tag.pixel_size = 0.0004
	tag.font_size = 40
	tag.modulate = Color(0.12, 0.12, 0.14)
	tag.outline_size = 0
	# The slot's mouth: the snap zone sits here, and a seated disc's centre rides in from here.
	U.node(root, root, "Marker3D", "DiscSeat", Vector3(0, SLOT_Y, front_z))


## The Neo Geo MVS unit: a metal tray holding the green motherboard, with the cartridge slot standing
## up out of the middle of it (the vertical-slot MVS; the cassette stands in it, label to the front).
## Returns the CartSeat marker, where the cassette's centre stands. Origin on the floor.
func _build_mvs(root: Node, size: Vector3, tray: Material, black: Material, metal: Material) -> Marker3D:
	var green := U.mat(Color(0.04, 0.30, 0.15), 0.0, 0.55)
	var chip := U.mat(Color(0.07, 0.07, 0.08), 0.0, 0.5)
	var gold := U.mat(Color(0.85, 0.66, 0.22), 1.0, 0.3)
	U.box(root, root, "MvsTray", Vector3(size.x, size.y, size.z), Vector3(0, size.y * 0.5, 0), tray)
	var board_y := size.y + 0.0015
	U.box(root, root, "MvsBoard", Vector3(size.x - 0.02, 0.003, size.z - 0.01), Vector3(0, board_y, 0.0), green)
	var slot_top := board_y + 0.0015 + 0.030
	U.box(root, root, "MvsSlot", Vector3(0.178, 0.030, 0.032), Vector3(0, board_y + 0.0015 + 0.015, 0.0), black)
	U.box(root, root, "MvsSlotMouth", Vector3(0.164, 0.002, 0.018), Vector3(0, slot_top + 0.0001, 0.0),
		U.mat(Color(0.0, 0.0, 0.0), 0.0, 0.9))
	for i in 3:
		U.box(root, root, "MvsChipL%d" % (i + 1), Vector3(0.034, 0.008, 0.026),
			Vector3(-0.125 + i * 0.002, board_y + 0.0055, -0.055 + i * 0.045), chip)
	for i in 3:
		U.box(root, root, "MvsChipR%d" % (i + 1), Vector3(0.030, 0.007, 0.022),
			Vector3(0.125, board_y + 0.005, -0.055 + i * 0.045), chip)
	U.box(root, root, "MvsEdgeConn", Vector3(0.150, 0.006, 0.010), Vector3(0, board_y + 0.0045, -0.088), gold)
	U.box(root, root, "MvsPower", Vector3(0.040, 0.016, 0.030), Vector3(0.140, board_y + 0.009, 0.075), metal)
	# The cassette's edge goes INSERT into the slot: its centre is half its height above the tip.
	var insert := 0.020
	var cart_h := 0.130
	return U.node(root, root, "Marker3D", "CartSeat", Vector3(0, slot_top - insert + cart_h * 0.5, 0.0)) as Marker3D
