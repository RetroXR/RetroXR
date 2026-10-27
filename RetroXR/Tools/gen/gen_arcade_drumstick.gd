## Bakes a Taiko drummer's stick (a bachi) to Scenes/Objects/peripherals/arcade_drumstick.tscn.
##
## Run once, out of band (after `--editor --quit` has put the class_names in the cache):
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_drumstick.gd
##
## A plain wooden stick about 32 cm long and 2 cm thick, lighter at the head, with a wrapped grip and a ring at the butt where the cord goes in. The origin is the middle of the grip: that is the
## GRAB POINT (identity, as a card's and a microphone's are: a snap zone seats an object by composing its grab point, so the cradle's own transform is the whole of the seating), the stick lies along
## -Z toward its head, and the cord leaves the butt at +Z. ArcadeDrumstick.CORD_BOSS and TIP are these numbers, and the cabinet builds its cradles to the same (ArcadeCabinetBuilder._gear_rest).
##
## `Swing` carries everything that is seen of the stick but not its body, so a click on the desktop can dip the head about the hand without moving what the hand holds (ArcadeDrumstick._animate).
##
## The size is the usual bachi's (30 to 33 cm; the arcade sticks are the same kind) and nothing has measured the cabinet's own: an estimate.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")
const OUT := "res://Scenes/Objects/peripherals/arcade_drumstick.tscn"

const RADIUS := 0.0105
const BUTT := 0.092
const HEAD := -0.232
const SHAFT_FROM := 0.090
const SHAFT_TO := -0.205


func _initialize() -> void:
	var root := RigidBody3D.new()
	root.name = "ArcadeDrumstick"
	root.set_script(load("res://Scripts/Objects/arcade/arcade_drumstick.gd"))
	root.collision_layer = 4
	root.collision_mask = 196613
	root.mass = 0.08
	root.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	root.linear_damp = 3.0
	root.angular_damp = 6.0
	var friction := PhysicsMaterial.new()
	friction.friction = 0.8
	root.physics_material_override = friction
	root.add_to_group("arcade_gear", true)

	var wood := U.mat(Color(0.78, 0.60, 0.36), 0.0, 0.7)
	var pale := U.mat(Color(0.90, 0.76, 0.54), 0.0, 0.6)
	var wrap := U.mat(Color(0.50, 0.10, 0.09), 0.0, 0.85)
	var metal := U.mat(Color(0.62, 0.63, 0.67), 0.85, 0.3)

	# The body the physics and the hand know: a capsule along the stick.
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS + 0.003
	shape.height = BUTT - HEAD + 0.004
	var body := U.node(root, root, "CollisionShape3D", "CollisionShape3D", Vector3(0, 0, (BUTT + HEAD) * 0.5)) as CollisionShape3D
	body.shape = shape
	body.basis = Basis(Vector3.RIGHT, PI * 0.5)

	var swing := U.node(root, root, "Node3D", "Swing") as Node3D
	var shaft_len := SHAFT_FROM - SHAFT_TO
	var shaft := U.cylinder(root, swing, "Shaft", RADIUS, shaft_len, Vector3(0, 0, (SHAFT_FROM + SHAFT_TO) * 0.5), wood, Vector3.BACK)
	(shaft.mesh as CylinderMesh).top_radius = RADIUS * 0.92
	# The head: a little thicker and paler, ending in a rounded tip.
	var head_len := SHAFT_TO - HEAD + 0.012
	var head := U.cylinder(root, swing, "Head", RADIUS * 1.18, head_len - 0.012, Vector3(0, 0, SHAFT_TO - (head_len - 0.012) * 0.5 + 0.004), pale, Vector3.BACK)
	(head.mesh as CylinderMesh).radial_segments = 16
	var tip := U.node(root, swing, "MeshInstance3D", "HeadTip", Vector3(0, 0, HEAD + RADIUS * 1.18)) as MeshInstance3D
	var ball := SphereMesh.new()
	ball.radius = RADIUS * 1.18
	ball.height = RADIUS * 2.36
	ball.radial_segments = 16
	ball.rings = 8
	ball.material = pale
	tip.mesh = ball
	# The grip's wrap, and the ring at the butt the cord ties on (CORD_BOSS).
	U.cylinder(root, swing, "GripWrap", RADIUS * 1.10, 0.080, Vector3(0, 0, 0.040), wrap, Vector3.BACK)
	U.cylinder(root, swing, "ButtCap", RADIUS * 1.15, 0.010, Vector3(0, 0, BUTT - 0.005), metal, Vector3.BACK)
	U.cylinder(root, swing, "CordRing", 0.0055, 0.006, Vector3(0, 0, BUTT + 0.003), metal, Vector3.BACK)
	U.node(root, swing, "Marker3D", "CableAttachPoint", Vector3(0, 0, BUTT))

	# What the hand grabs by: the middle of the grip, identity.
	var grab := U.node(root, root, "Marker3D", "GrabPoint") as Marker3D
	grab.visible = false
	grab.set_script(load("res://addons/godot-xr-tools/objects/grab_points/grab_point.gd"))
	var light := U.node(root, root, "Node3D", "PickableHighlight") as Node3D
	light.set_script(load("res://Scripts/Objects/highlights/pickable_highlight.gd"))

	# The laser finds it: a box a little fatter than the stick, on the pointer layer.
	var pointer := U.node(root, root, "StaticBody3D", "PointerArea") as StaticBody3D
	pointer.collision_layer = 1048576
	pointer.collision_mask = 0
	var pointer_shape := U.node(root, pointer, "CollisionShape3D", "CollisionShape3D", Vector3(0, 0, (BUTT + HEAD) * 0.5)) as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.05, BUTT - HEAD + 0.03)
	pointer_shape.shape = box

	quit(U.save(root, OUT))
