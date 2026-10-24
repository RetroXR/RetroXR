## Bakes the consolized Neo Geo MVS to Scenes/Objects/system_models/neogeo_console.tscn.
##
## Run once, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_neogeo_console.gd
##
## A rectangular dark box, 340 x 220 x 60 mm (an ESTIMATE: no SNK console of this kind ever existed
## and the community builds have no standard shape), with a slot standing up from the roof for the
## MVS cassette, two controller ports and POWER and RESET on the front, and three phono jacks on the
## back. The script is neogeo_console_model.gd, which seats the system's parts on the markers.
## Origin on the floor at the centre of the base, front toward +Z, like every model that draws its body.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_PATH := "res://Scenes/Objects/system_models/neogeo_console.tscn"

const W := 0.34
const H := 0.06
const D := 0.22
## The cassette: its edge goes this far into the slot, and it is this tall (CART_SIZES["neogeo"]).
const INSERT := 0.020
const CART_H := 0.130


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "NeoGeoConsole"
	root.set_script(load("res://Scripts/Objects/system_models/neogeo_console_model.gd"))

	var body := U.mat(Color(0.10, 0.10, 0.115), 0.0, 0.5)
	var trim := U.mat(Color(0.78, 0.07, 0.10), 0.0, 0.45)
	var dark := U.mat(Color(0.03, 0.03, 0.035), 0.0, 0.7)
	var metal := U.mat(Color(0.60, 0.61, 0.65), 0.85, 0.35)
	var vent := U.mat(Color(0.05, 0.05, 0.055), 0.0, 0.8)

	U.box(root, root, "Body", Vector3(W, H, D), Vector3(0, H * 0.5, 0), body)
	# A red stripe round the front, and vents on the roof either side of the slot.
	U.box(root, root, "Stripe", Vector3(W + 0.001, 0.006, 0.0008), Vector3(0, H - 0.012, D * 0.5 + 0.0004), trim)
	for sx in [-1.0, 1.0]:
		for i in 5:
			U.box(root, root, "Vent%s%d" % ["L" if sx < 0 else "R", i], Vector3(0.060, 0.0006, 0.004),
				Vector3(sx * 0.115, H + 0.0003, -0.075 + i * 0.012), vent)

	# The cartridge slot, standing up from the middle of the roof. The cassette's edge (its
	# connector) goes INSERT into it and its label faces the front.
	var slot_w := 0.188
	var slot_h := 0.020
	var slot_y := H + slot_h * 0.5
	U.box(root, root, "SlotHousing", Vector3(slot_w, slot_h, 0.036), Vector3(0, slot_y, -0.03), dark)
	U.box(root, root, "SlotMouth", Vector3(slot_w - 0.012, 0.0008, 0.020), Vector3(0, H + slot_h + 0.0004, -0.03),
		U.mat(Color(0, 0, 0), 0.0, 0.9))
	var slot_top := H + slot_h
	var seat := U.node(root, root, "Marker3D", "CartSeat",
		Vector3(0, slot_top - INSERT + CART_H * 0.5, -0.03)) as Marker3D
	seat.name = "CartSeat"

	# The front: a panel with the two controller ports, POWER and RESET on the roof's front edge.
	var front := U.node(root, root, "Node3D", "Front") as Node3D
	U.box(root, front, "PortPanel", Vector3(0.26, 0.022, 0.001), Vector3(0, 0.026, D * 0.5 + 0.0005), dark)
	for i in 2:
		U.node(root, front, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(-0.07 if i == 0 else 0.07, 0.026, D * 0.5))
	U.node(root, front, "Marker3D", "PowerSeat", Vector3(-0.145, H, 0.07))
	U.node(root, front, "Marker3D", "ResetSeat", Vector3(0.145, H, 0.07))

	# The back: three phono jacks on 18 mm centres, each turned so +Z points out of the back and
	# standing 10 mm out of the panel, where a phono plug's origin belongs (as the generic box does).
	var rear := U.node(root, root, "Node3D", "Rear") as Node3D
	for i in 3:
		var jack := U.node(root, rear, "Marker3D", "AvSeat%d" % (i + 1),
			Vector3(0.082 + 0.018 * i, 0.040, -D * 0.5 - 0.010)) as Marker3D
		jack.basis = Basis(Vector3.RIGHT, PI)
	U.cylinder(root, rear, "DcJack", 0.008, 0.012, Vector3(-0.10, 0.030, -D * 0.5 - 0.004), metal, Vector3.BACK)

	quit(U.save(root, OUT_PATH))
