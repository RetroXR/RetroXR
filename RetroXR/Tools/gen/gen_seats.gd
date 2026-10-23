## Bakes the seats (Scripts/Objects/room/seat.gd) to Scenes/Objects/furniture/seat_*.tscn:
## a racing seat, a stool, a floor cushion, a chair, a sofa and a bed.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_seats.gd [-- --only=seat_chair]
##
## FRAME. Origin on the floor at the middle of the seat, the seat FACES -Z (the way the eyes
## look). `EyePoint` is where the head goes (seat height + a sitting adult's eye height above
## it, ~0.78 m; a lying one on the bed is on the pillow); `StandPoint` is on the floor at
## the seat's side, where the player is put when they get up (to a side because the front is
## often a cabinet or a screen). `SeatTrigger` is a slab proud of the cushion, the thing you press.
##
## Primitive boxes on purpose, like the arcade cabinet: an example to be replaced by a model
## that keeps the script and the three markers. Sizes are ordinary furniture, none measured.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")
const OUT_DIR := "res://Scenes/Objects/furniture/"
const SCRIPT_SEAT := "res://Scripts/Objects/room/seat.gd"
const SCRIPT_TRIGGER := "res://Scripts/Objects/room/seat_trigger.gd"
const SCRIPT_HIGHLIGHT := "res://Scripts/Objects/highlights/pickable_highlight.gd"
## A sitting adult's eye height above the seat.
const EYE_ABOVE := 0.78


## Each part: [name, size, centre, material key]. `shapes` are collision boxes [size, centre]; the
## `trigger` is the cushion's footprint [size x, size z, top y]; `stand_x` the side the player gets up on.
func _families() -> Dictionary:
	return {
		"seat_racing": {
			"title": "Racing Seat", "mass": 15.0, "seat_top": 0.30, "eye_above": 0.72, "stand_x": 0.62,
			"parts": [
				["Rails", Vector3(0.50, 0.04, 0.80), Vector3(0, 0.02, 0.0), "frame"],
				["Base", Vector3(0.44, 0.10, 0.46), Vector3(0, 0.09, 0.05), "frame"],
				["Cushion", Vector3(0.40, 0.10, 0.42), Vector3(0, 0.25, 0.04), "shell"],
				["Back", Vector3(0.42, 0.55, 0.10), Vector3(0, 0.58, 0.30), "shell"],
				["BolsterL", Vector3(0.07, 0.30, 0.38), Vector3(-0.215, 0.43, 0.10), "shell"],
				["BolsterR", Vector3(0.07, 0.30, 0.38), Vector3(0.215, 0.43, 0.10), "shell"],
				["Stitch", Vector3(0.05, 0.50, 0.012), Vector3(0, 0.58, 0.245), "trim"],
			],
			"shapes": [[Vector3(0.50, 0.30, 0.80), Vector3(0, 0.15, 0.0)], [Vector3(0.44, 0.55, 0.12), Vector3(0, 0.58, 0.30)]],
			"trigger": [0.40, 0.42, 0.30], "trigger_z": 0.04,
		},
		"seat_stool": {
			"title": "Stool", "mass": 4.0, "seat_top": 0.75, "eye_above": EYE_ABOVE, "stand_x": 0.5,
			"parts": [
				["Seat", Vector3(0.36, 0.05, 0.36), Vector3(0, 0.725, 0), "wood"],
				["LegFL", Vector3(0.04, 0.70, 0.04), Vector3(-0.15, 0.35, -0.15), "frame"],
				["LegFR", Vector3(0.04, 0.70, 0.04), Vector3(0.15, 0.35, -0.15), "frame"],
				["LegBL", Vector3(0.04, 0.70, 0.04), Vector3(-0.15, 0.35, 0.15), "frame"],
				["LegBR", Vector3(0.04, 0.70, 0.04), Vector3(0.15, 0.35, 0.15), "frame"],
				["Rest", Vector3(0.34, 0.025, 0.34), Vector3(0, 0.28, 0), "frame"],
			],
			"shapes": [[Vector3(0.36, 0.05, 0.36), Vector3(0, 0.725, 0)], [Vector3(0.34, 0.70, 0.34), Vector3(0, 0.35, 0)]],
			"trigger": [0.36, 0.36, 0.75], "trigger_z": 0.0,
		},
		"seat_chair": {
			"title": "Chair", "mass": 6.0, "seat_top": 0.46, "eye_above": EYE_ABOVE, "stand_x": 0.55,
			"parts": [
				["Seat", Vector3(0.44, 0.04, 0.44), Vector3(0, 0.44, 0), "wood"],
				["Back", Vector3(0.44, 0.46, 0.04), Vector3(0, 0.69, 0.20), "wood"],
				["LegFL", Vector3(0.04, 0.42, 0.04), Vector3(-0.19, 0.21, -0.19), "frame"],
				["LegFR", Vector3(0.04, 0.42, 0.04), Vector3(0.19, 0.21, -0.19), "frame"],
				["LegBL", Vector3(0.04, 0.42, 0.04), Vector3(-0.19, 0.21, 0.19), "frame"],
				["LegBR", Vector3(0.04, 0.42, 0.04), Vector3(0.19, 0.21, 0.19), "frame"],
			],
			"shapes": [[Vector3(0.44, 0.46, 0.44), Vector3(0, 0.23, 0)], [Vector3(0.44, 0.48, 0.05), Vector3(0, 0.70, 0.20)]],
			"trigger": [0.44, 0.44, 0.46], "trigger_z": 0.0,
		},
		"seat_cushion": {
			"title": "Floor Cushion", "mass": 1.0, "seat_top": 0.13, "eye_above": 0.70, "stand_x": 0.6,
			"parts": [["Pad", Vector3(0.55, 0.13, 0.55), Vector3(0, 0.065, 0), "fabric"]],
			"shapes": [[Vector3(0.55, 0.13, 0.55), Vector3(0, 0.065, 0)]],
			"trigger": [0.55, 0.55, 0.13], "trigger_z": 0.0,
		},
		"seat_sofa": {
			"title": "Sofa", "mass": 40.0, "seat_top": 0.44, "eye_above": EYE_ABOVE, "stand_x": 1.2,
			"parts": [
				["Base", Vector3(1.80, 0.20, 0.85), Vector3(0, 0.15, 0), "frame"],
				["Cushions", Vector3(1.40, 0.14, 0.70), Vector3(0, 0.37, -0.05), "fabric"],
				["Back", Vector3(1.80, 0.50, 0.18), Vector3(0, 0.60, 0.33), "fabric"],
				["ArmL", Vector3(0.20, 0.34, 0.85), Vector3(-0.80, 0.37, 0), "fabric"],
				["ArmR", Vector3(0.20, 0.34, 0.85), Vector3(0.80, 0.37, 0), "fabric"],
			],
			"shapes": [[Vector3(1.80, 0.44, 0.85), Vector3(0, 0.22, 0)], [Vector3(1.80, 0.50, 0.18), Vector3(0, 0.60, 0.33)]],
			"trigger": [1.40, 0.70, 0.44], "trigger_z": -0.05,
		},
		"seat_bed": {
			"title": "Bed", "mass": 60.0, "seat_top": 0.52, "eye_above": 0.14, "stand_x": 1.1, "eye_z": 0.70,
			"parts": [
				["Frame", Vector3(1.40, 0.30, 2.00), Vector3(0, 0.25, 0), "frame"],
				["Mattress", Vector3(1.34, 0.17, 1.94), Vector3(0, 0.435, 0), "fabric"],
				["Pillow", Vector3(0.55, 0.10, 0.34), Vector3(0, 0.57, 0.70), "sheet"],
				["Headboard", Vector3(1.40, 0.70, 0.08), Vector3(0, 0.55, 1.00), "wood"],
			],
			"shapes": [[Vector3(1.40, 0.52, 2.00), Vector3(0, 0.26, 0)], [Vector3(1.40, 0.70, 0.08), Vector3(0, 0.55, 1.00)]],
			"trigger": [1.34, 1.94, 0.52], "trigger_z": 0.0,
		},
	}


func _materials() -> Dictionary:
	return {
		"wood": U.mat(Color(0.52, 0.36, 0.22), 0.0, 0.7),
		"frame": U.mat(Color(0.14, 0.14, 0.16), 0.5, 0.45),
		"fabric": U.mat(Color(0.62, 0.20, 0.22), 0.0, 0.9),
		"shell": U.mat(Color(0.07, 0.07, 0.08), 0.0, 0.6),
		"trim": U.mat(Color(0.85, 0.12, 0.12), 0.0, 0.8),
		"sheet": U.mat(Color(0.90, 0.90, 0.92), 0.0, 0.95),
	}


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var mats := _materials()
	var fams := _families()
	var failed := false
	for id: String in fams:
		if not only.is_empty() and only != id:
			continue
		var root := _bake(id, fams[id], mats)
		failed = failed or U.save(root, OUT_DIR + id + ".tscn") != OK
		root.free()
	quit(1 if failed else 0)


func _bake(id: String, f: Dictionary, mats: Dictionary) -> Node3D:
	var root := RigidBody3D.new()
	root.name = "Seat"
	root.set_script(load(SCRIPT_SEAT))
	root.set("type_id", id)
	root.mass = float(f["mass"])
	root.collision_layer = 4
	root.collision_mask = 196613
	root.linear_damp = 5.0
	root.angular_damp = 8.0
	root.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var phys := PhysicsMaterial.new()
	phys.friction = 0.8
	phys.bounce = 0.0
	root.physics_material_override = phys
	for p: Array in f["parts"]:
		U.box(root, root, p[0], p[1], p[2], mats[p[3]])
	var i := 0
	for s: Array in f["shapes"]:
		i += 1
		var cs := U.node(root, root, "CollisionShape3D", "Col%d" % i, s[1]) as CollisionShape3D
		var bs := BoxShape3D.new()
		bs.size = s[0]
		cs.shape = bs
	var hl := U.node(root, root, "Node3D", "PickableHighlight")
	hl.set_script(load(SCRIPT_HIGHLIGHT))
	# Ray targeting for carrying: the whole body. The cushion's trigger stands proud of it.
	var ptr := U.node(root, root, "StaticBody3D", "PointerArea") as StaticBody3D
	ptr.collision_layer = 1 << 20
	ptr.collision_mask = 0
	i = 0
	for s: Array in f["shapes"]:
		i += 1
		var pc := U.node(root, ptr, "CollisionShape3D", "Shape%d" % i, s[1]) as CollisionShape3D
		var pb := BoxShape3D.new()
		pb.size = s[0]
		pc.shape = pb
	# The cushion you press: 3 cm proud of the surface.
	var trig_size: Array = f["trigger"]
	var trig := U.node(root, root, "Area3D", "SeatTrigger",
		Vector3(0.0, float(trig_size[2]) + 0.005, float(f.get("trigger_z", 0.0)))) as Area3D
	trig.set_script(load(SCRIPT_TRIGGER))
	var tc := U.node(root, trig, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var tb := BoxShape3D.new()
	tb.size = Vector3(float(trig_size[0]), 0.03, float(trig_size[1]))
	tc.shape = tb
	var eye_z := float(f.get("eye_z", float(f.get("trigger_z", 0.0))))
	U.node(root, root, "Marker3D", "EyePoint", Vector3(0.0, float(f["seat_top"]) + float(f["eye_above"]), eye_z))
	U.node(root, root, "Marker3D", "StandPoint", Vector3(float(f["stand_x"]), 0.0, 0.0))
	return root
