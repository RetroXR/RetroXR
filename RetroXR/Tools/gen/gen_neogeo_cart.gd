## Bakes the Neo Geo MVS cartridge to Scenes/Objects/media/neogeo_cart.tscn.
##
## Run once, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_neogeo_cart.gd
##
## An MVS game is a plastic CASSETTE, not a bare board: a dark shell with the game's label on
## its front, and the board's edge connector standing out of the bottom. The connector is
## documented (wiki.neogeodev.org: 240 contacts, 2 rows x 60 a side on a 2.54 mm pitch, so about
## 152 mm of fingers); the SHELL's size, colour and ribs are NOT: no source reached gave them,
## so they are estimates, drawn plausibly (about 200 x 130 x 22 mm, charcoal, a red band, a
## recessed label). Replace them with a measured cartridge when there is one; nothing else
## depends on the numbers but MediaDimensions.CART_SIZES["neogeo"], which is this size.
##
## Cartridge frame, as every cart: connector edge on -Y, label on +Z, the AABB centred, `Label` a
## UV-mapped sticker (UV 0..1) that CartridgeLabel paints.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_PATH := "res://Scenes/Objects/media/neogeo_cart.tscn"

const W := 0.200          # across the connector edge (X)
const H := 0.130          # edge tip to top (Y)
const T := 0.022          # thickness (Z)
const PCB_T := 0.0016
const FINGERS := 60
const PITCH := 0.00254
const SHELL_BOTTOM := -0.040      # where the shell ends and the board's edge begins


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "NeoGeoCart"

	var shell := U.mat(Color(0.085, 0.085, 0.095), 0.0, 0.55)
	var rib := U.mat(Color(0.13, 0.13, 0.145), 0.0, 0.6)
	var red := U.mat(Color(0.75, 0.08, 0.10), 0.0, 0.5)
	var pcb := U.mat(Color(0.04, 0.30, 0.15), 0.0, 0.55)
	var gold := U.mat(Color(0.85, 0.66, 0.22), 1.0, 0.3)
	var paper := U.mat(Color(0.93, 0.92, 0.89), 0.0, 0.8)
	var recess := U.mat(Color(0.05, 0.05, 0.055), 0.0, 0.7)

	var top := H * 0.5
	var shell_h := top - SHELL_BOTTOM
	var shell_c := (top + SHELL_BOTTOM) * 0.5
	U.box(root, root, "Shell", Vector3(W, shell_h, T), Vector3(0, shell_c, 0), shell)

	# The board's edge, standing out of the bottom of the shell.
	var edge_h := SHELL_BOTTOM - (-H * 0.5) + 0.004      # a little inside the shell
	U.box(root, root, "BoardEdge", Vector3(0.158, edge_h, PCB_T),
		Vector3(0, -H * 0.5 + edge_h * 0.5, 0), pcb)
	# The fingers: two rows of 60 on each face, 2.54 mm apart.
	var span := (FINGERS - 1) * PITCH
	var finger := BoxMesh.new()
	finger.size = Vector3(0.0014, 0.0075, 0.0002)
	for face in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = finger
		mm.instance_count = FINGERS * 2
		for row in 2:
			for i in FINGERS:
				mm.set_instance_transform(row * FINGERS + i, Transform3D(Basis.IDENTITY,
					Vector3(-span * 0.5 + i * PITCH, 0.0 if row == 0 else 0.0095, 0.0)))
		var mmi := U.node(root, root, "MultiMeshInstance3D", "FingersFront" if face == 0 else "FingersBack",
			Vector3(0, -H * 0.5 + 0.0065, (PCB_T * 0.5 + 0.0001) * (1.0 if face == 0 else -1.0))) as MultiMeshInstance3D
		mmi.multimesh = mm
		mmi.material_override = gold

	# The front: a red band under the top edge, a recessed panel and the label in it, and a
	# ridge down each side for a grip.
	var zf := T * 0.5
	U.box(root, root, "Band", Vector3(W, 0.007, 0.0006), Vector3(0, top - 0.0055, zf + 0.0003), red)
	U.box(root, root, "LabelRecess", Vector3(0.172, 0.078, 0.0006), Vector3(0, 0.014, zf + 0.0003), recess)
	var label := U.quad(root, root, "Label", Vector2(0.164, 0.070), Vector3(0, 0.014, zf + 0.0009), paper)
	label.name = "Label"
	for sx in [-1.0, 1.0]:
		U.box(root, root, "Rib%s" % ("L" if sx < 0 else "R"), Vector3(0.004, 0.070, 0.0010),
			Vector3(sx * (W * 0.5 - 0.006), 0.0, zf + 0.0005), rib)
	# Below the label, the gap where a thumb goes, and a recessed notch at the top.
	U.box(root, root, "ThumbGrip", Vector3(0.060, 0.012, 0.0008), Vector3(0, -0.020, zf + 0.0004), rib)
	U.box(root, root, "TopNotch", Vector3(0.054, 0.004, 0.012), Vector3(0, top - 0.001, 0), recess)

	quit(U.save(root, OUT_PATH))
