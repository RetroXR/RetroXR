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
## shoulder and a scope on top. The scope's eyepiece carries a small screen (`ScopeScreen`, a 3.7 x 2.8 cm quad on the eyepiece's end, facing the
## player's eye): the cabinet's monitor module (ArcadeScreenModule) finds it by name and feeds it Silent Scope's second screen.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const BASE := "res://Scenes/Objects/peripherals/light_gun.tscn"
const OUT := "res://Scenes/Objects/peripherals/arcade_light_gun.tscn"
const OUT_RIFLE := "res://Scenes/Objects/peripherals/arcade_light_rifle.tscn"

## Where the cord leaves the gun, in the gun's frame (the butt of the grip). The cabinet reads
## the same number to lay the cord (RetroSystemModelArcadeCabinet.GUN_CORD_BOSS).
const CORD_BOSS := Vector3(0.0, -0.098, 0.056)
## The muzzle, where the aim ray starts.
const MUZZLE := Vector3(0.0, 0.034, -0.182)
const RIFLE_MUZZLE := Vector3(0.0, 0.034, -0.392)
## The scope's screen: the eyepiece (a cylinder 4.6 cm across, ending at z 0.065) holds a 4:3 picture 3.7 cm wide, facing the eye (+Z).
const SCOPE_SCREEN := Vector2(0.037, 0.0278)

var _root: Node3D


func _initialize() -> void:
	var rifle := "--variant=rifle" in OS.get_cmdline_user_args()
	_root = (load(BASE) as PackedScene).instantiate() as Node3D
	_root.name = "ArcadeLightRifle" if rifle else "ArcadeLightGun"

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
		U.cylinder(_root, _root, "ScopeEye", 0.023, 0.03, Vector3(0, 0.094, 0.050), black, Vector3.BACK)
		U.cylinder(_root, _root, "ScopeLens", 0.023, 0.03, Vector3(0, 0.094, -0.170), grey, Vector3.BACK)
		# The scope's own screen, in the eyepiece: 4:3 like the screen it shows, inside the eyepiece's 4.6 cm. It is dark until a game feeds it.
		var screen_mat := U.mat(Color(0.015, 0.017, 0.02), 0.0, 0.12)
		U.quad(_root, _root, "ScopeScreen", SCOPE_SCREEN, Vector3(0, 0.094, 0.0653), screen_mat)
		for z in [-0.11, 0.0]:
			U.box(_root, _root, "ScopeRing%d" % (1 if z < 0.0 else 2), Vector3(0.016, 0.032, 0.012),
				Vector3(0, 0.070, z), metal)
		U.cylinder(_root, _root, "RifleMuzzle", 0.017, 0.022, RIFLE_MUZZLE + Vector3(0, 0, 0.011), orange, Vector3.BACK)
		for n in ["Muzzle", "RecoilHousing", "RecoilBand", "FrontSight", "RearSight"]:
			var part := _root.get_node_or_null(n) as Node3D
			if part != null:
				_root.remove_child(part)
				part.free()

	# No buttons on an arcade gun.
	for n in ["AuxAButton", "AuxBButton", "StartButton"]:
		(_root.get_node(n) as Node3D).visible = false

	(_root.get_node("BarrelTip") as Node3D).position = RIFLE_MUZZLE if rifle else MUZZLE
	(_root.get_node("CableAttachPoint") as Node3D).position = CORD_BOSS
	# The grab point the cabinet's wells seat the gun by (RetroSystemModelArcadeCabinet.GUN_GRAB).
	for n in ["GrabPoint", "HandRight", "HandLeft"]:
		(_root.get_node(n) as Node3D).position = Vector3(0, -0.040, 0.048)

	# A larger body to collide with and to point at.
	var body := BoxShape3D.new()
	body.size = Vector3(0.05, 0.17, 0.25) if not rifle else Vector3(0.05, 0.17, 0.72)
	var col := _root.get_node("CollisionShape3D") as CollisionShape3D
	col.shape = body
	col.position = Vector3(0, -0.012, -0.040) if not rifle else Vector3(0, -0.012, -0.040)
	var pointer := BoxShape3D.new()
	pointer.size = Vector3(0.07, 0.19, 0.28) if not rifle else Vector3(0.07, 0.19, 0.74)
	var pcol := _root.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	pcol.shape = pointer
	pcol.position = col.position

	_root.set("cable_length", 1.4)
	quit(U.save(_root, OUT_RIFLE if rifle else OUT))


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
