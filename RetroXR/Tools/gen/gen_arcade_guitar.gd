## Bakes a GuitarFreaks guitar to Scenes/Objects/peripherals/arcade_guitar.tscn.
##
## Run once, out of band (after `--editor --quit` has put the class_names in the cache):
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_guitar.gd
##
## A plastic Les Paul-like controller about 0.65 m long: a body of two bouts (the lower the bigger), a neck with a head, three fret buttons on the neck's far end (red, green, blue, the red the
## farthest from the body, as MAME's "P1 Button R/G/B" read), a pick bar on the lower bout, a wail button on the upper, an effect knob, and the jack the cord ties on at the bottom of the body.
##
## THE FRAME. The guitar hangs in its holster on the cabinet's front as it stands: +Y up the neck toward the head, +Z the face (the side with the buttons) toward the player, +X the player's
## right, the origin at the body's WAIST (where the body hand takes it): the holster's marker is the guitar's own pose, identity.
##
## THE HOLD. Five grab points (ArcadeGuitarGrab), each the pose of a controller on the guitar: the body in the right hand with the neck out to the left, forward and up (the neck in the left
## hand), the mirror of both for the other way about, and the desktop's. A pose is built from where the neck and the face go in the controller's own frame (-Z forward, +Y up, +X right): the neck to the
## player's left and forward and a little up, the face forward and up, as a guitar worn at the waist lies. The pose is a guess at a way of holding that nothing has measured in a headset.
##
## The sizes are an estimate: nothing has measured a real GuitarFreaks guitar.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")
const OUT := "res://Scenes/Objects/peripherals/arcade_guitar.tscn"

## Where the neck and the face go in the controller's frame when the right hand holds the body (left, up, forward; forward, up, a touch right).
const NECK_IN_HAND := Vector3(-0.75, 0.30, -0.60)
const FACE_IN_HAND := Vector3(0.35, 0.55, -0.75)
## Where each hand's palm is on the guitar: the body hand behind the waist, the neck hand behind the neck.
const BODY_PALM := Vector3(0.0, -0.060, -0.030)
const NECK_PALM := Vector3(0.0, 0.27, -0.022)
## The desktop's hand is the camera's lower right (DesktopPickup): the guitar lies across the lower part of the view, its neck out to the left and a little away, its face up toward the eye
## so the frets and the pick that answer the keys can be seen.
const NECK_ON_DESKTOP := Vector3(-0.90, 0.12, -0.42)
const FACE_ON_DESKTOP := Vector3(0.12, 0.62, 0.78)
## Where the guitar's waist is in that hand's frame: a little farther off and lower than the pivot, so a guitar as long as a person's arm is not all of the view.
const WAIST_ON_DESKTOP := Vector3(0.02, -0.10, -0.28)


## The pose of a controller on the guitar: the guitar's axes in the hand's frame (columns) turned the other way, plus where the palm is. `mirror` is the left-handed player's guitar.
static func grip(palm: Vector3, mirror: bool) -> Transform3D:
	var neck := NECK_IN_HAND
	var face := FACE_IN_HAND
	if mirror:
		neck.x = -neck.x
		face.x = -face.x
	return pose(neck, face, palm)


## The same for a hand that holds the guitar with its waist at `waist` in the hand's own frame (the desktop's: a view's corner, not a palm).
static func pose_at(neck_dir: Vector3, face_dir: Vector3, waist: Vector3) -> Transform3D:
	var t := pose(neck_dir, face_dir, Vector3.ZERO)
	t.origin = -(t.basis * waist)
	return t


## The pose of a hand's frame on the guitar when the neck points along `neck` and the face along `face` in that frame (the face is made square to the neck).
static func pose(neck_dir: Vector3, face_dir: Vector3, palm: Vector3) -> Transform3D:
	var neck := neck_dir.normalized()
	var face := face_dir.normalized()
	var z := (face - face.dot(neck) * neck).normalized()
	var x := neck.cross(z).normalized()
	var guitar_in_hand := Basis(x, neck, z)
	return Transform3D(guitar_in_hand.transposed(), palm)


func _initialize() -> void:
	var root := RigidBody3D.new()
	root.name = "ArcadeGuitar"
	root.set_script(load("res://Scripts/Objects/arcade/arcade_guitar.gd"))
	root.collision_layer = 4
	root.collision_mask = 196613
	root.mass = 1.4
	root.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	root.linear_damp = 3.0
	root.angular_damp = 6.0
	var friction := PhysicsMaterial.new()
	friction.friction = 0.8
	root.physics_material_override = friction
	root.add_to_group("arcade_gear", true)

	var red := U.mat(Color(0.70, 0.12, 0.12), 0.0, 0.35)
	var wood := U.mat(Color(0.18, 0.10, 0.07), 0.0, 0.6)
	var black := U.mat(Color(0.08, 0.08, 0.10), 0.0, 0.5)
	var metal := U.mat(Color(0.65, 0.66, 0.70), 0.85, 0.3)
	var white := U.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4)

	# The body: two bouts a little apart in front of one another, the lower the bigger, a plate on the face.
	U.cylinder(root, root, "BodyLower", 0.130, 0.040, Vector3(0.0, -0.055, 0.0), red, Vector3.BACK)
	U.cylinder(root, root, "BodyUpper", 0.095, 0.040, Vector3(0.0, 0.062, 0.0), red, Vector3.BACK)
	U.box(root, root, "BodyWaist", Vector3(0.13, 0.13, 0.040), Vector3(0.0, 0.005, 0.0), red)
	U.box(root, root, "Pickguard", Vector3(0.18, 0.15, 0.004), Vector3(0.0, -0.060, 0.021), black)
	# The neck and its head, the head a little wider.
	U.box(root, root, "GuitarNeck", Vector3(0.044, 0.260, 0.022), Vector3(0.0, 0.280, -0.004), wood)
	U.box(root, root, "GuitarHead", Vector3(0.058, 0.058, 0.018), Vector3(0.0, 0.439, -0.004), black)
	for k in 3:
		U.cylinder(root, root, "Tuner%d" % k, 0.005, 0.014, Vector3(-0.034 if k == 0 else 0.034, 0.425 + 0.018 * (k % 2), -0.004), metal, Vector3.RIGHT)
	# The three fret buttons, the red the farthest from the body.
	var fret_colours := [Color(0.92, 0.12, 0.12), Color(0.15, 0.75, 0.25), Color(0.15, 0.40, 0.95)]
	var fret_y := [0.355, 0.315, 0.275]
	for k in 3:
		U.cylinder(root, root, "Fret%d" % (k + 1), 0.0115, 0.010, Vector3(0.0, fret_y[k], 0.011), U.mat(fret_colours[k], 0.0, 0.3), Vector3.BACK)
	# The pick: a flat bar across the lower bout, which a thumb or a pick flicks up or down. The wail: a white button on the upper bout. The effect knob beside the pick.
	U.box(root, root, "Pick", Vector3(0.070, 0.016, 0.012), Vector3(0.0, -0.095, 0.030), metal)
	U.cylinder(root, root, "Wail", 0.012, 0.010, Vector3(-0.050, 0.105, 0.025), white, Vector3.BACK)
	var knob := U.node(root, root, "Node3D", "Knob", Vector3(0.065, -0.020, 0.022)) as Node3D
	U.cylinder(root, knob, "KnobBody", 0.014, 0.016, Vector3(0.0, 0.0, 0.008), black, Vector3.BACK)
	U.box(root, knob, "KnobMark", Vector3(0.003, 0.011, 0.002), Vector3(0.0, 0.007, 0.017), white)
	# The jack at the bottom of the body, where the cord is tied.
	U.cylinder(root, root, "Jack", 0.011, 0.024, Vector3(0.0, -0.190, 0.0), metal, Vector3.UP)
	# A cord leaves what it is tied to along that node's -Z (the rope's boot): turned so that is the guitar's own down, it leaves the jack straight down and not into the cabinet behind.
	var attach := U.node(root, root, "Marker3D", "CableAttachPoint", Vector3(0.0, -0.205, 0.0)) as Marker3D
	attach.basis = Basis(Vector3.RIGHT, -PI * 0.5)

	# What the body is to the physics: a box round each bout and the neck.
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.26, 0.34, 0.045)
	(U.node(root, root, "CollisionShape3D", "BodyShape", Vector3(0.0, -0.015, 0.0)) as CollisionShape3D).shape = body_shape
	var neck_shape := BoxShape3D.new()
	neck_shape.size = Vector3(0.058, 0.32, 0.030)
	(U.node(root, root, "CollisionShape3D", "NeckShape", Vector3(0.0, 0.305, -0.004)) as CollisionShape3D).shape = neck_shape

	# Where the hands take it.
	var points := [
		["BodyR", ArcadeGuitarGrab.BODY, ArcadeGuitarGrab.RIGHT, grip(BODY_PALM, false)],
		["NeckL", ArcadeGuitarGrab.NECK, ArcadeGuitarGrab.LEFT, grip(NECK_PALM, false)],
		["BodyL", ArcadeGuitarGrab.BODY, ArcadeGuitarGrab.LEFT, grip(BODY_PALM, true)],
		["NeckR", ArcadeGuitarGrab.NECK, ArcadeGuitarGrab.RIGHT, grip(NECK_PALM, true)],
		["Desktop", ArcadeGuitarGrab.DESKTOP, ArcadeGuitarGrab.RIGHT, pose_at(NECK_ON_DESKTOP, FACE_ON_DESKTOP, WAIST_ON_DESKTOP)],
	]
	for p: Array in points:
		var marker := U.node(root, root, "Marker3D", str(p[0])) as Marker3D
		marker.set_script(load("res://Scripts/Objects/arcade/arcade_guitar_grab.gd"))
		marker.set("role", int(p[1]))
		marker.set("hand_side", int(p[2]))
		marker.transform = p[3]
	var light := U.node(root, root, "Node3D", "PickableHighlight") as Node3D
	light.set_script(load("res://Scripts/Objects/highlights/pickable_highlight.gd"))

	# The laser finds it: a box a little fatter than the guitar, on the pointer layer.
	var pointer := U.node(root, root, "StaticBody3D", "PointerArea") as StaticBody3D
	pointer.collision_layer = 1048576
	pointer.collision_mask = 0
	var pointer_shape := U.node(root, pointer, "CollisionShape3D", "CollisionShape3D", Vector3(0.0, 0.14, 0.0)) as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(0.34, 0.70, 0.09)
	pointer_shape.shape = box

	quit(U.save(root, OUT))
