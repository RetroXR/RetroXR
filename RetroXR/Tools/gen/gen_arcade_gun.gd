## Bakes the arcade light gun to Scenes/Objects/peripherals/arcade_light_gun.tscn.
##
## Run once, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_gun.gd
##
## The gun an arcade cabinet wears in its holster: the classic shape of the optical guns of
## the genre (Namco's Time Crisis and Point Blank, Sega's House of the Dead and Virtua Cop) --
## a black pistol body with a recoil housing under the barrel, a front and a rear sight, a
## trigger inside its guard, a tilted grip, and the ORANGE muzzle those guns carry. Real ones
## are about 24 cm long. It is an inherited scene of light_gun.tscn, so the script, the
## trigger, the cord, the hands and the pointer are the light gun's own and only the shape
## changes; the nodes the script reads (BarrelTip, CableAttachPoint, TriggerPivot...) keep
## their names and the gun still aims along its own -Z with the grip toward -Y.
##
## The arcade guns have no buttons on them, so the light gun's three aux/start caps are hidden:
## START and the coin are the cabinet's (ArcadeInput forwards them to the gun).
##
## `-- --variant=rifle` bakes the rifle a rifle cabinet rests on its post instead (Silent Scope, Golgo 13:
## Scenes/Objects/peripherals/arcade_light_rifle.tscn): the same pistol grip, trigger and cord boss in the
## same place (so the cabinet seats and cords it with the pistol's numbers), a long barrel, a stock to the
## shoulder and a scope on top. The scope's eyepiece is a cup flaring from the tube to 10 cm across and carries a screen (`ScopeScreen`, a 7.4 x 5.55 cm quad on
## the cup's end, facing the player's eye; it was a 3.7 x 2.8 cm one in a 4.6 cm eyepiece, too small to read a picture in): the cabinet's monitor module
## (ArcadeScreenModule) finds it by name and feeds it Silent Scope's second screen, or, for a rifle game of one screen (Golgo 13), the part of the picture
## the rifle points at, magnified.
##
## `-- --variant=stick` bakes a JOYSTICK-LIKE gun (Scenes/Objects/peripherals/arcade_light_stick.tscn): Sega's Rail Chase and Rail Chase 2 had no pistols to draw from a holster but
## a fixed controller the research calls "an analog stick with a trigger" (Arcade-Museum; MAME files the first as a light gun and the second as an analog stick). It
## is the same trigger, cord boss and grab point, with a tall rounded handle, a ball on its top and a short nose that points where it aims.
##
## `-- --variant=blaster` bakes Laser Ghost's gun (arcade_light_blaster.tscn): a big sci-fi blaster, about 40 cm long, with a finned barrel, a
## top-mounted laser imaging unit (the one detail the research gives: "a top-mounted laser imaging unit on the guns") and two buttons on the grip (fire and the
## limited-use special weapon). It is 40 cm from grip to muzzle, a pistol's 24 cm and more, and its swivel is 22 cm ahead of the grip so the muzzle still stops short of the glass at rest.
## The shape beyond that is an estimate: no photograph of the gun could be read.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const BASE := "res://Scenes/Objects/peripherals/light_gun.tscn"
const OUT := "res://Scenes/Objects/peripherals/arcade_light_gun.tscn"
const OUT_RIFLE := "res://Scenes/Objects/peripherals/arcade_light_rifle.tscn"
const OUT_STICK := "res://Scenes/Objects/peripherals/arcade_light_stick.tscn"
const OUT_BLASTER := "res://Scenes/Objects/peripherals/arcade_light_blaster.tscn"

## Where the cord leaves the gun, in the gun's frame (the butt of the grip). The cabinet reads
## the same number to lay the cord (RetroSystemModelArcadeCabinet.GUN_CORD_BOSS).
const CORD_BOSS := Vector3(0.0, -0.098, 0.056)
## The muzzle, where the aim ray starts.
const MUZZLE := Vector3(0.0, 0.034, -0.182)
const RIFLE_MUZZLE := Vector3(0.0, 0.034, -0.392)
const STICK_MUZZLE := Vector3(0.0, 0.040, -0.120)
const BLASTER_MUZZLE := Vector3(0.0, 0.030, -0.360)
## The scope's screen: the eyepiece cup (flaring to 10 cm across, ending at z 0.075) holds a 4:3 picture 7.4 cm wide, facing the eye (+Z); its diagonal (9.25 cm)
## is inside the cup's end.
const SCOPE_SCREEN := Vector2(0.074, 0.0555)
const SCOPE_CUP_RADIUS := 0.050

var _root: Node3D


func _initialize() -> void:
	var rifle := "--variant=rifle" in OS.get_cmdline_user_args()
	var stick := "--variant=stick" in OS.get_cmdline_user_args()
	var blaster := "--variant=blaster" in OS.get_cmdline_user_args()
	_root = (load(BASE) as PackedScene).instantiate() as Node3D
	_root.name = "ArcadeLightRifle" if rifle else ("ArcadeLightStick" if stick else ("ArcadeLightBlaster" if blaster else "ArcadeLightGun"))

	var black := U.mat(Color(0.065, 0.065, 0.075), 0.0, 0.42)
	var grey := U.mat(Color(0.19, 0.20, 0.22), 0.0, 0.5)
	var orange := U.mat(Color(0.95, 0.38, 0.05), 0.0, 0.4)
	var metal := U.mat(Color(0.60, 0.61, 0.65), 0.85, 0.3)
	var red := U.mat(Color(0.75, 0.10, 0.10), 0.0, 0.5)

	# The body: slide and barrel in one block, the recoil housing under it, the grip behind.
	_reshape("Barrel", Vector3(0.044, 0.050, 0.20), Vector3(0, 0.034, -0.050), black)
	_reshape("Grip", Vector3(0.038, 0.105, 0.048), Vector3(0, -0.045, 0.046), black,
		Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	U.box(_root, _root, "RecoilHousing", Vector3(0.036, 0.026, 0.115), Vector3(0, 0.003, -0.080), grey)
	U.box(_root, _root, "RecoilBand", Vector3(0.038, 0.028, 0.012), Vector3(0, 0.003, -0.135), red)
	# The orange muzzle ring, and a front and rear sight.
	U.cylinder(_root, _root, "Muzzle", 0.019, 0.026, Vector3(0, 0.034, -0.158), orange, Vector3.BACK)
	U.box(_root, _root, "FrontSight", Vector3(0.006, 0.012, 0.010), Vector3(0, 0.065, -0.132), black)
	U.box(_root, _root, "RearSight", Vector3(0.020, 0.010, 0.008), Vector3(0, 0.063, 0.036), black)
	# The trigger guard around the (unchanged) trigger.
	U.box(_root, _root, "GuardBottom", Vector3(0.006, 0.004, 0.046), Vector3(0, -0.022, 0.004), black)
	U.box(_root, _root, "GuardFront", Vector3(0.006, 0.030, 0.004), Vector3(0, -0.008, -0.019), black)
	# Where the steel-reinforced cord goes into the butt.
	U.cylinder(_root, _root, "CordBoot", 0.011, 0.020, CORD_BOSS + Vector3(0, 0.006, -0.004), metal, Vector3.UP)

	if rifle:
		# The rifle: the barrel runs on 21 cm past the pistol's, a forestock under it (what the post holds),
		# a stock back to the shoulder, and a scope on two rings.
		_reshape("Barrel", Vector3(0.040, 0.044, 0.42), Vector3(0, 0.034, -0.170), black)
		U.box(_root, _root, "Forestock", Vector3(0.046, 0.030, 0.20), Vector3(0, 0.004, -0.150), grey)
		var stock := U.box(_root, _root, "Stock", Vector3(0.040, 0.075, 0.24), Vector3(0, 0.000, 0.190), black)
		stock.basis = Basis(Vector3.RIGHT, deg_to_rad(8.0))
		U.box(_root, _root, "ButtPad", Vector3(0.042, 0.090, 0.016), Vector3(0, -0.012, 0.312), grey)
		U.cylinder(_root, _root, "Scope", 0.019, 0.20, Vector3(0, 0.094, -0.060), black, Vector3.BACK)
		var cup := U.cylinder(_root, _root, "ScopeEye", 0.023, 0.04, Vector3(0, 0.094, 0.055), black, Vector3.BACK)
		(cup.mesh as CylinderMesh).top_radius = SCOPE_CUP_RADIUS
		(cup.mesh as CylinderMesh).radial_segments = 32
		U.cylinder(_root, _root, "ScopeLens", 0.023, 0.03, Vector3(0, 0.094, -0.170), grey, Vector3.BACK)
		# The scope's own screen, in the eyepiece cup: 4:3 like the screen it shows, inside the cup's end. It is dark until a game feeds it.
		var screen_mat := U.mat(Color(0.015, 0.017, 0.02), 0.0, 0.12)
		U.quad(_root, _root, "ScopeScreen", SCOPE_SCREEN, Vector3(0, 0.094, 0.0753), screen_mat)
		for z in [-0.11, 0.0]:
			U.box(_root, _root, "ScopeRing%d" % (1 if z < 0.0 else 2), Vector3(0.016, 0.032, 0.012),
				Vector3(0, 0.070, z), metal)
		U.cylinder(_root, _root, "RifleMuzzle", 0.017, 0.022, RIFLE_MUZZLE + Vector3(0, 0, 0.011), orange, Vector3.BACK)
		for n in ["Muzzle", "RecoilHousing", "RecoilBand", "FrontSight", "RearSight"]:
			var part := _root.get_node_or_null(n) as Node3D
			if part != null:
				_root.remove_child(part)
				part.free()

	if stick:
		_build_stick(black, grey, red, metal)
	if blaster:
		_build_blaster(black, grey, metal)

	# No buttons on an arcade gun.
	for n in ["AuxAButton", "AuxBButton", "StartButton"]:
		(_root.get_node(n) as Node3D).visible = false

	(_root.get_node("BarrelTip") as Node3D).position = RIFLE_MUZZLE if rifle else (STICK_MUZZLE if stick else (BLASTER_MUZZLE if blaster else MUZZLE))
	(_root.get_node("CableAttachPoint") as Node3D).position = CORD_BOSS
	# The grab point the cabinet's wells seat the gun by (RetroSystemModelArcadeCabinet.GUN_GRAB).
	for n in ["GrabPoint", "HandRight", "HandLeft"]:
		(_root.get_node(n) as Node3D).position = Vector3(0, -0.040, 0.048)

	# A larger body to collide with and to point at.
	var body := BoxShape3D.new()
	var pointer := BoxShape3D.new()
	var centre := Vector3(0, -0.012, -0.040)
	if rifle:
		body.size = Vector3(0.10, 0.17, 0.72)
		pointer.size = Vector3(0.12, 0.19, 0.74)
	elif stick:
		body.size = Vector3(0.07, 0.23, 0.17)
		pointer.size = Vector3(0.09, 0.25, 0.19)
		centre = Vector3(0, -0.005, -0.030)
	elif blaster:
		body.size = Vector3(0.12, 0.22, 0.44)
		pointer.size = Vector3(0.14, 0.24, 0.46)
		centre = Vector3(0, 0.0, -0.130)
	else:
		body.size = Vector3(0.05, 0.17, 0.25)
		pointer.size = Vector3(0.07, 0.19, 0.28)
	var col := _root.get_node("CollisionShape3D") as CollisionShape3D
	col.shape = body
	col.position = centre
	var pcol := _root.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	pcol.shape = pointer
	pcol.position = col.position

	_root.set("cable_length", 1.4)
	quit(U.save(_root, OUT_RIFLE if rifle else (OUT_STICK if stick else (OUT_BLASTER if blaster else OUT))))


## Rail Chase's controller: the pistol's own grip, trigger and cord boss, made a joystick's. The handle is a tall rounded post leaning back a little with a ball on its top
## (what a palm closes over), the trigger where an index finger rests, and a short nose in front of the ball that points where the stick aims; a red thumb cap on the
## ball. Nothing of the pistol's barrel, recoil housing or sights is left.
func _build_stick(black: Material, grey: Material, red: Material, metal: Material) -> void:
	for n in ["RecoilHousing", "RecoilBand", "Muzzle", "FrontSight", "RearSight", "GuardBottom", "GuardFront"]:
		var part := _root.get_node_or_null(n) as Node3D
		if part != null:
			_root.remove_child(part)
			part.free()
	_reshape("Barrel", Vector3(0.036, 0.034, 0.100), Vector3(0, 0.040, -0.070), black)
	_reshape("Grip", Vector3(0.050, 0.150, 0.050), Vector3(0, -0.034, 0.040), black, Basis(Vector3.RIGHT, deg_to_rad(-9.0)))
	var knob := U.node(_root, _root, "MeshInstance3D", "StickBall", Vector3(0, 0.060, 0.050)) as MeshInstance3D
	var ball := SphereMesh.new()
	ball.radius = 0.032
	ball.height = 0.064
	ball.radial_segments = 20
	ball.rings = 10
	ball.material = grey
	knob.mesh = ball
	U.cylinder(_root, _root, "StickCap", 0.011, 0.010, Vector3(0, 0.086, 0.050), red, Vector3.UP)
	U.cylinder(_root, _root, "StickCollar", 0.034, 0.016, Vector3(0, -0.092, 0.058), metal, Vector3.UP)
	var band := U.box(_root, _root, "GripBand", Vector3(0.054, 0.012, 0.054), Vector3(0, -0.016, 0.044), grey)
	band.basis = Basis(Vector3.RIGHT, deg_to_rad(-9.0))
	U.box(_root, _root, "NoseTip", Vector3(0.030, 0.026, 0.020), Vector3(0, 0.040, -0.122), red)


## Laser Ghost's gun, built big: a heavy body with a finned barrel, a laser imaging unit on its back with a domed lens, a side cell and a thick grip with two caps (fire and the
## special weapon) on its top. Its origin, grip, trigger, cord boss and grab point are the pistol's, so the cabinet mounts and cords it with the same numbers.
func _build_blaster(black: Material, grey: Material, metal: Material) -> void:
	for n in ["RecoilHousing", "RecoilBand", "Muzzle", "FrontSight", "RearSight", "GuardBottom", "GuardFront"]:
		var part := _root.get_node_or_null(n) as Node3D
		if part != null:
			_root.remove_child(part)
			part.free()
	var teal := U.mat(Color(0.05, 0.62, 0.62), 0.0, 0.35)
	var glow := U.mat(Color(0.20, 0.95, 0.35), 0.0, 0.25)
	var blue := U.mat(Color(0.10, 0.25, 0.85), 0.0, 0.4)
	var red := U.mat(Color(0.85, 0.10, 0.10), 0.0, 0.4)
	# The body and the thick barrel it carries, with the finned collars of its cooling jacket.
	_reshape("Barrel", Vector3(0.082, 0.092, 0.250), Vector3(0, 0.030, -0.075), black)
	U.cylinder(_root, _root, "BlasterBarrel", 0.030, 0.170, Vector3(0, 0.030, -0.270), grey, Vector3.BACK)
	for i in 4:
		U.cylinder(_root, _root, "BlasterFin%d" % (i + 1), 0.042, 0.012, Vector3(0, 0.030, -0.195 - 0.035 * float(i)), metal, Vector3.BACK)
	U.cylinder(_root, _root, "BlasterMuzzle", 0.036, 0.028, Vector3(0, 0.030, -0.345), teal, Vector3.BACK)
	U.cylinder(_root, _root, "BlasterEmitter", 0.020, 0.018, Vector3(0, 0.030, -0.356), glow, Vector3.BACK)
	# The laser imaging unit on top: a box with a domed lens looking forward and a lamp.
	U.box(_root, _root, "ImagingUnit", Vector3(0.062, 0.050, 0.120), Vector3(0, 0.096, -0.070), grey)
	U.cylinder(_root, _root, "ImagingLens", 0.024, 0.030, Vector3(0, 0.098, -0.145), black, Vector3.BACK)
	U.cylinder(_root, _root, "ImagingGlass", 0.018, 0.010, Vector3(0, 0.098, -0.163), teal, Vector3.BACK)
	U.box(_root, _root, "ImagingLamp", Vector3(0.014, 0.010, 0.020), Vector3(0, 0.124, -0.045), glow)
	# A power cell along the left side, and a stay from it to the grip.
	U.cylinder(_root, _root, "BlasterCell", 0.024, 0.170, Vector3(-0.056, 0.014, -0.090), teal, Vector3.BACK)
	U.box(_root, _root, "CellStay", Vector3(0.034, 0.014, 0.020), Vector3(-0.040, 0.014, 0.000), metal)
	# The grip, thick, with the fire and special-weapon caps on its top face.
	_reshape("Grip", Vector3(0.056, 0.125, 0.064), Vector3(0, -0.050, 0.050), black, Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	U.cylinder(_root, _root, "FireCap", 0.011, 0.008, Vector3(0.0, 0.018, 0.058), red, Vector3.UP)
	U.cylinder(_root, _root, "SpecialCap", 0.009, 0.008, Vector3(0.0, 0.018, 0.034), blue, Vector3.UP)
	U.box(_root, _root, "GuardBottom", Vector3(0.006, 0.004, 0.050), Vector3(0, -0.022, 0.004), black)
	U.box(_root, _root, "GuardFront", Vector3(0.006, 0.030, 0.004), Vector3(0, -0.008, -0.021), black)


## Give an inherited mesh node a box of its own: the material on the MESH, no override.
func _reshape(node_name: String, size: Vector3, pos: Vector3, material: Material,
		basis: Basis = Basis.IDENTITY) -> void:
	var mi := _root.get_node(node_name) as MeshInstance3D
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	mi.set_surface_override_material(0, null)
	mi.transform = Transform3D(basis, pos)
