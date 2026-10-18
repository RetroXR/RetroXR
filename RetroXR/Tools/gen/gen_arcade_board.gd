## Bakes the generic JAMMA arcade board to Scenes/Objects/media/arcade_board.tscn.
##
## Run once, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_board.gd
##
## A JAMMA board is a flat PCB with a gold comb on one short edge: 56 contacts, 28
## a side, 3.96 mm apart, which is the cabinet harness's female connector's
## standard (1985). Chips and connectors stand on the top face, and the shell a
## cartridge has is simply not there. One generic board that stands for all of
## them -- real ones were every shape.
##
## Cartridge frame, so everything a RetroCartridge does with a body keeps working:
## connector edge on -Y, label on +Z, the AABB centred. Its size is the CART_SIZES
## row for mame/fbneo (0.20 x 0.30 x 0.035): the 111 mm comb sits in the 200 mm
## edge. `Label` is a UV-mapped sticker (UV 0..1), which CartridgeLabel paints.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_PATH := "res://Scenes/Objects/media/arcade_board.tscn"

const W := 0.20           # along the comb edge (X)
const H := 0.30           # insertion length (Y)
const T := 0.035          # thickness incl. components (Z)
const PCB_T := 0.0016
const FINGERS := 28
const PITCH := 0.00396


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "ArcadeBoard"

	var pcb_mat := U.mat(Color(0.04, 0.32, 0.16), 0.0, 0.55)
	var gold := U.mat(Color(0.85, 0.66, 0.22), 1.0, 0.3)
	var chip := U.mat(Color(0.05, 0.05, 0.06), 0.0, 0.5)
	var epoxy := U.mat(Color(0.16, 0.16, 0.18), 0.0, 0.8)
	var metal := U.mat(Color(0.72, 0.72, 0.75), 0.9, 0.35)
	var blue := U.mat(Color(0.10, 0.18, 0.55), 0.0, 0.5)
	var paper := U.mat(Color(0.93, 0.92, 0.89), 0.0, 0.8)

	var z0 := -T * 0.5                      # bottom of the board
	var pcb_top := z0 + PCB_T
	U.box(root, root, "PCB", Vector3(W, H, PCB_T), Vector3(0, 0, z0 + PCB_T * 0.5), pcb_mat)

	# The comb, both faces: FINGERS contacts a side on a PITCH, centred on the edge.
	var span := (FINGERS - 1) * PITCH
	var finger := BoxMesh.new()
	finger.size = Vector3(0.0023, 0.0165, 0.0002)
	for side in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = finger
		mm.instance_count = FINGERS
		for i in FINGERS:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				Vector3(-span * 0.5 + i * PITCH, 0.0, 0.0)))
		var mmi := U.node(root, root, "MultiMeshInstance3D", "CombTop" if side == 0 else "CombBottom",
			Vector3(0, -H * 0.5 + 0.0105,
				pcb_top + 0.0001 if side == 0 else z0 - 0.0001)) as MultiMeshInstance3D
		mmi.multimesh = mm
		mmi.material_override = gold

	# The ROM module: a raised block the label sits on. The label is the top face of
	# the board the player reads, so it gets the biggest flat area.
	var block_h := 0.008
	var block_c := Vector3(0.0, 0.035, pcb_top + block_h * 0.5)
	U.box(root, root, "RomBlock", Vector3(0.115, 0.082, block_h), block_c, epoxy)
	var label := U.quad(root, root, "Label", Vector2(0.106, 0.074),
		Vector3(block_c.x, block_c.y, pcb_top + block_h + 0.0002), paper)
	label.name = "Label"

	# The main CPU and a row of ROM chips along the top, and glue logic by the comb.
	U.box(root, root, "Cpu", Vector3(0.082, 0.026, 0.0065), Vector3(0.0, 0.112, pcb_top + 0.00325), chip)
	for i in 4:
		U.box(root, root, "Rom%d" % (i + 1), Vector3(0.050, 0.014, 0.005),
			Vector3(-0.070 + i * 0.047, 0.138, pcb_top + 0.0025), chip)
	for i in 3:
		U.box(root, root, "Logic%d" % (i + 1), Vector3(0.030, 0.012, 0.004),
			Vector3(-0.060 + i * 0.058, -0.055, pcb_top + 0.002), chip)
	U.box(root, root, "Sound", Vector3(0.036, 0.036, 0.005), Vector3(0.070, -0.020, pcb_top + 0.0025), chip)

	# The tallest parts set the board's thickness: an electrolytic and a header.
	var cap_h := T - PCB_T
	U.cylinder(root, root, "Electrolytic", 0.009, cap_h,
		Vector3(0.080, 0.080, pcb_top + cap_h * 0.5), blue, Vector3.BACK)
	for k in 2:
		U.cylinder(root, root, "Cap%d" % (k + 1), 0.004, 0.011,
			Vector3(-0.085, -0.040 + k * 0.014, pcb_top + 0.0055), metal, Vector3.BACK)
	U.box(root, root, "Header", Vector3(0.046, 0.008, 0.012), Vector3(-0.045, -0.100, pcb_top + 0.006), chip)

	quit(U.save(root, OUT_PATH))
