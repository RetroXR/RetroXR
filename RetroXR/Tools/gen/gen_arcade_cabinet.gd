## Bakes the Generic Arcade Cabinet to Scenes/Objects/system_models/arcade_cabinet.tscn.
##
## Run once, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_cabinet.gd
##
## A classic upright, 0.66 W x 1.80 H x 0.80 D (0.87 over the control panel), low
## detail on purpose: an example to be consolidated by hand, whose parts are TYPED
## MODULES (Scripts/Objects/arcade/) rather than a list of node names, so a better
## model, or a mod's own cabinet, only has to honour that contract. Origin on the
## floor at the centre of the base, front toward +Z.
##
## The side silhouette is a polygon extruded across the width: a toe-kick, a coin
## area, a control-panel overhang, a tilted monitor and a marquee.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_PATH := "res://Scenes/Objects/system_models/arcade_cabinet.tscn"

const W := 0.66
const IN_W := 0.62      # between the side panels
const SIDE_T := 0.02

# Side silhouette, (z, y), front toward +z.
const PROFILE := [
	Vector2(-0.40, 0.00), Vector2(0.34, 0.00), Vector2(0.34, 0.09), Vector2(0.40, 0.09),
	Vector2(0.40, 0.78), Vector2(0.47, 0.80), Vector2(0.47, 0.92), Vector2(0.30, 1.00),
	Vector2(0.15, 1.46), Vector2(0.36, 1.46), Vector2(0.36, 1.80), Vector2(-0.40, 1.80),
]

const SCRIPTS := {
	"model": "res://Scripts/Objects/system_models/arcade_cabinet_model.gd",
	"screen": "res://Scripts/Objects/arcade/arcade_screen_module.gd",
	"control": "res://Scripts/Objects/arcade/arcade_control_module.gd",
	"coin": "res://Scripts/Objects/arcade/arcade_coin_module.gd",
	"bay": "res://Scripts/Objects/arcade/arcade_bay_module.gd",
	"sockets": "res://Scripts/Objects/arcade/arcade_socket_module.gd",
	"panel": "res://Scripts/Objects/arcade/arcade_panel_grip.gd",
	"button": "res://Scripts/Objects/widgets/vr_button.gd",
	"hinge": "res://Scripts/Objects/widgets/vr_hinge.gd",
}

var _root: Node3D
var _body: StandardMaterial3D
var _trim: StandardMaterial3D
var _dark: StandardMaterial3D
var _metal: StandardMaterial3D

const BUTTON_COLORS := [
	Color(0.85, 0.12, 0.12), Color(0.95, 0.75, 0.10), Color(0.15, 0.65, 0.25),
	Color(0.15, 0.35, 0.85), Color(0.92, 0.92, 0.92), Color(0.55, 0.20, 0.70),
]


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "ArcadeCabinet"
	_root.set_script(load(SCRIPTS["model"]))

	_body = U.mat(Color(0.14, 0.17, 0.33), 0.0, 0.55)
	_trim = U.mat(Color(0.90, 0.16, 0.28), 0.0, 0.4)
	_dark = U.mat(Color(0.03, 0.03, 0.035), 0.0, 0.8)
	_metal = U.mat(Color(0.65, 0.66, 0.70), 0.9, 0.35)

	var cab := U.node(_root, _root, "Node3D", "Cabinet") as Node3D
	_build_shell(cab)
	_build_monitor()
	_build_deck()
	_build_coin_doors()
	_build_front_sockets()
	_build_bay()
	quit(U.save(_root, OUT_PATH))


# ── shell ───────────────────────────────────────────────────────────────────

func _build_shell(cab: Node3D) -> void:
	var side_mesh := _extrude(PackedVector2Array(PROFILE), SIDE_T)
	for sx in [-1.0, 1.0]:
		var mi := U.node(_root, cab, "MeshInstance3D", "SideL" if sx < 0 else "SideR",
			Vector3(sx * (W - SIDE_T) * 0.5, 0, 0)) as MeshInstance3D
		mi.mesh = side_mesh
		mi.material_override = _body
	U.box(_root, cab, "Rear", Vector3(IN_W, 1.80, 0.02), Vector3(0, 0.90, -0.39), _body)
	U.box(_root, cab, "Top", Vector3(IN_W, 0.02, 0.76), Vector3(0, 1.79, -0.02), _body)
	U.box(_root, cab, "Floor", Vector3(IN_W, 0.02, 0.74), Vector3(0, 0.01, 0.0), _body)
	U.box(_root, cab, "KickPlate", Vector3(IN_W, 0.09, 0.02), Vector3(0, 0.045, 0.34), _dark)
	# Coin area: the front between the bay door and the control panel.
	U.box(_root, cab, "CoinFace", Vector3(IN_W, 0.28, 0.02), Vector3(0, 0.64, 0.39), _body)
	U.box(_root, cab, "ApronUnder", Vector3(IN_W, 0.05, 0.07), Vector3(0, 0.785, 0.435), _body)
	U.box(_root, cab, "Apron", Vector3(IN_W, 0.12, 0.02), Vector3(0, 0.86, 0.46), _body)
	U.box(_root, cab, "ApronTrim", Vector3(IN_W, 0.012, 0.022), Vector3(0, 0.806, 0.462), _trim)
	# Marquee: a lit panel above the monitor, so it glows when the machine is on.
	var marquee_mat := U.mat(Color(0.95, 0.35, 0.20), 0.0, 0.5, Color(1.0, 0.45, 0.25), 0.0)
	var marquee := U.box(_root, cab, "Marquee", Vector3(IN_W, 0.31, 0.012), Vector3(0, 1.62, 0.354), marquee_mat)
	var title := U.node(_root, marquee, "Label3D", "MarqueeTitle", Vector3(0, 0, 0.0075)) as Label3D
	title.text = "ARCADE"
	title.pixel_size = 0.0013
	title.font_size = 96
	title.modulate = Color(1.0, 0.95, 0.85)
	title.outline_size = 0
	title.no_depth_test = false
	U.box(_root, cab, "MarqueeTrim", Vector3(IN_W, 0.012, 0.022), Vector3(0, 1.459, 0.354), _trim)


# ── monitor ─────────────────────────────────────────────────────────────────

func _build_monitor() -> void:
	# The tube runs from the deck's back edge (z 0.30, y 1.00) to the marquee's underside
	# (z 0.15, y 1.46): tilted back about 18 degrees, so the picture looks up at the player
	# as it does on a real cabinet, behind a pane of glass in a black frame.
	var a := Vector2(0.30, 1.00)
	var b := Vector2(0.15, 1.46)
	var mid := (a + b) * 0.5
	var along := b - a
	var theta := atan2(along.x, along.y)   # rotation about X taking +Y onto `along` (z, y)
	var basis := Basis(Vector3.RIGHT, theta)
	var mod := U.node(_root, _root, "Node3D", "Screen", Vector3(0, mid.y, mid.x)) as Node3D
	mod.set_script(load(SCRIPTS["screen"]))
	mod.basis = basis
	U.box(_root, mod, "Bezel", Vector3(IN_W, along.length(), 0.012), Vector3.ZERO, _dark)
	var screen := U.quad(_root, mod, "CabinetScreen", Vector2(0.38, 0.285), Vector3(0, 0.005, 0.0072),
		U.mat(Color(0.015, 0.017, 0.02), 0.0, 0.12))
	screen.name = "CabinetScreen"
	# The classic glass: a pane a few centimetres in front of the tube, with a black frame
	# around it that hides the tube's edge. Translucent, so the picture shows through.
	var glass_mat := U.mat(Color(0.55, 0.65, 0.75, 0.035), 0.0, 0.04)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	glass_mat.metallic_specular = 1.0
	var glass := U.quad(_root, mod, "Glass", Vector2(0.46, 0.36), Vector3(0, 0.005, 0.040), glass_mat)
	glass.name = "Glass"
	var bar_t := 0.014
	var fz := 0.046
	var side_w := (IN_W - 0.46) * 0.5
	var top_h := (along.length() - 0.36) * 0.5 - 0.0
	for sx in [-1.0, 1.0]:
		U.box(_root, mod, "FrameSide%s" % ("L" if sx < 0 else "R"), Vector3(side_w, along.length(), bar_t),
			Vector3(sx * (0.23 + side_w * 0.5), 0, fz), _dark)
	for sy in [-1.0, 1.0]:
		U.box(_root, mod, "Frame%s" % ("Top" if sy > 0 else "Bottom"), Vector3(0.46, top_h, bar_t),
			Vector3(0, 0.005 + sy * (0.18 + top_h * 0.5), fz), _dark)


# ── control deck ────────────────────────────────────────────────────────────

func _build_deck() -> void:
	# The deck runs from the apron's top edge (z 0.47, y 0.92) up to the monitor
	# (z 0.30, y 1.00). Its local +Y is up-and-back along the slope, +Z its normal.
	var a := Vector2(0.47, 0.92)
	var b := Vector2(0.30, 1.00)
	var mid := (a + b) * 0.5
	var along := b - a
	var theta := atan2(along.x, along.y)
	var deck := U.node(_root, _root, "Node3D", "Deck", Vector3(0, mid.y, mid.x)) as Node3D
	deck.basis = Basis(Vector3.RIGHT, theta)
	U.box(_root, deck, "DeckPlate", Vector3(IN_W, along.length(), 0.012), Vector3(0, 0, -0.006), _dark)

	_build_player(deck, 0, -0.255, [-0.175, -0.115, -0.055], -0.115)
	_build_player(deck, 1, 0.055, [0.135, 0.195, 0.255], 0.195)



func _build_player(deck: Node3D, index: int, stick_x: float, button_xs: Array, start_x: float) -> void:
	var mod := U.node(_root, deck, "Node3D", "Player%d" % (index + 1)) as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", index)
	# The stick: a base plate, then a pivot carrying shaft and ball.
	U.cylinder(_root, mod, "StickBase", 0.034, 0.004, Vector3(stick_x, 0.015, 0.002), _metal, Vector3.BACK)
	var pivot := U.node(_root, mod, "Node3D", "StickPivot", Vector3(stick_x, 0.015, 0.004)) as Node3D
	U.cylinder(_root, pivot, "StickShaft", 0.006, 0.07, Vector3(0, 0, 0.035), _metal, Vector3.BACK)
	var ball := U.node(_root, pivot, "MeshInstance3D", "StickBall", Vector3(0, 0, 0.085)) as MeshInstance3D
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	ball.mesh = sm
	ball.material_override = U.mat(Color(0.85, 0.10, 0.10) if index == 0 else Color(0.10, 0.25, 0.85), 0.0, 0.3)
	# Six buttons in two rows, START on the front edge: plain caps, not controls of their own.
	var k := 0
	for row in 2:
		for col in 3:
			var x: float = button_xs[col] + (0.012 if row == 0 else 0.0)
			var y := 0.040 if row == 0 else -0.012
			_cap(mod, "Btn%d" % (k + 1), Vector3(x, y, 0.0), 0.0155, BUTTON_COLORS[k], 0.012)
			k += 1
	_cap(mod, "Start", Vector3(start_x, -0.07, 0.0), 0.011, Color(0.92, 0.92, 0.92), 0.008)
	# The whole panel is ONE pointable thing: aiming at any of it lights all of it, and a press
	# attaches you to it as to a controller (ArcadePanelGrip).
	var grip := U.node(_root, mod, "Area3D", "PanelGrip", Vector3.ZERO) as Area3D
	grip.set_script(load(SCRIPTS["panel"]))
	grip.collision_layer = 0
	grip.collision_mask = 0
	var gcol := U.node(_root, grip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(0.285, 0.185, 0.08)
	gcol.shape = gshape
	var left := minf(stick_x - 0.045, start_x - 0.02)
	var right := maxf(button_xs[2] + 0.012 + 0.02, start_x + 0.02)
	grip.position = Vector3((left + right) * 0.5, -0.01, 0.03)
	gshape.size.x = right - left


## A button cap on the deck: a cylinder that sinks when its bit is held. Not pokeable by itself.
func _cap(parent: Node3D, node_name: String, pos: Vector3, radius: float,
		color: Color, height: float) -> MeshInstance3D:
	return U.cylinder(_root, parent, node_name, radius, height, pos + Vector3(0, 0, height * 0.5),
		U.mat(color, 0.0, 0.3), Vector3.BACK)


# ── coin doors ──────────────────────────────────────────────────────────────

func _build_coin_doors() -> void:
	for i in 2:
		var x := -0.14 if i == 0 else 0.14
		var door := U.node(_root, _root, "Node3D", "CoinDoor%d" % (i + 1), Vector3(x, 0.64, 0.40)) as Node3D
		door.set_script(load(SCRIPTS["coin"]))
		door.set("player", i)
		U.box(_root, door, "Plate", Vector3(0.10, 0.20, 0.006), Vector3(0, 0, 0.003), _metal)
		U.box(_root, door, "ReturnCup", Vector3(0.05, 0.03, 0.008), Vector3(0, -0.055, 0.004), _dark)
		U.cylinder(_root, door, "ReturnButton", 0.012, 0.006, Vector3(0, -0.08, 0.006), _trim, Vector3.BACK)
		# The slot: a lit lip you poke.
		var lip := U.node(_root, door, "Area3D", "CoinSlot", Vector3(0, 0.045, 0.006)) as Area3D
		lip.set_script(load(SCRIPTS["button"]))
		lip.collision_layer = 0
		lip.collision_mask = 0
		lip.set("trigger_radius", 0.02)
		lip.set("depress_depth", 0.002)
		lip.set("depress_axis", Vector3(0, 0, -1))
		var col := U.node(_root, lip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.07, 0.045, 0.04)
		col.shape = shape
		col.position = Vector3(0, 0, 0.012)
		U.box(_root, lip, "ButtonMesh", Vector3(0.034, 0.010, 0.004), Vector3(0, 0, 0.002),
			U.mat(Color(1.0, 0.8, 0.2), 0.0, 0.4, Color(1.0, 0.7, 0.1), 0.8))
		var tag := U.node(_root, door, "Label3D", "CoinLabel", Vector3(0, 0.075, 0.0065)) as Label3D
		tag.text = "COIN"
		tag.pixel_size = 0.0006
		tag.font_size = 48
		tag.modulate = Color(0.1, 0.1, 0.12)
		tag.outline_size = 0
		U.node(_root, door, "Marker3D", "CoinSpawn", Vector3(0, 0.075, 0.075))
		U.node(_root, door, "Marker3D", "CoinDrop", Vector3(0, 0.045, 0.0))


# ── front sockets ───────────────────────────────────────────────────────────

func _build_front_sockets() -> void:
	var sockets := U.node(_root, _root, "Node3D", "Sockets", Vector3.ZERO) as Node3D
	sockets.set_script(load(SCRIPTS["sockets"]))
	# Rolled 180 degrees about Z with +Z out of the face, as the NES authors its
	# seats, so a plug seats connector-in and upright.
	for i in 2:
		var seat := U.node(_root, sockets, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(-0.24 if i == 0 else 0.24, 0.86, 0.47)) as Marker3D
		seat.basis = Basis(Vector3.BACK, PI)
		U.box(_root, sockets, "Recess%d" % (i + 1), Vector3(0.034, 0.026, 0.004),
			Vector3(-0.24 if i == 0 else 0.24, 0.86, 0.4685), _dark)


# ── bay ─────────────────────────────────────────────────────────────────────

func _build_bay() -> void:
	var bay := U.node(_root, _root, "Node3D", "Bay", Vector3.ZERO) as Node3D
	bay.set_script(load(SCRIPTS["bay"]))
	var interior := U.mat(Color(0.05, 0.05, 0.06), 0.0, 0.9)
	U.box(_root, bay, "BayFloor", Vector3(IN_W - 0.02, 0.01, 0.76), Vector3(0, 0.095, 0.0), interior)
	U.box(_root, bay, "BayRear", Vector3(IN_W - 0.02, 0.40, 0.01), Vector3(0, 0.30, -0.375), interior)
	U.box(_root, bay, "BayLeft", Vector3(0.01, 0.40, 0.76), Vector3(-0.295, 0.30, 0.0), interior)
	U.box(_root, bay, "BayRight", Vector3(0.01, 0.40, 0.76), Vector3(0.295, 0.30, 0.0), interior)
	U.box(_root, bay, "BayCeiling", Vector3(IN_W - 0.02, 0.01, 0.76), Vector3(0, 0.505, 0.0), interior)
	U.box(_root, bay, "Psu", Vector3(0.16, 0.15, 0.14), Vector3(0.20, 0.18, -0.29), _metal)
	# The harness: its female JAMMA connector on the floor, and the bundle running
	# back from it. The board's comb goes into the top of the block.
	U.box(_root, bay, "JammaSocket", Vector3(0.12, 0.02, 0.045), Vector3(0, 0.11, 0.0),
		U.mat(Color(0.85, 0.80, 0.55), 0.0, 0.6))
	U.cylinder(_root, bay, "Harness", 0.012, 0.34, Vector3(0, 0.115, -0.21),
		U.mat(Color(0.10, 0.10, 0.12), 0.0, 0.7), Vector3.BACK)
	# The board stands in the socket facing the front: connector -Y, label +Z.
	var seat := U.node(_root, bay, "Marker3D", "CartSeat", Vector3(0, 0.27, 0.0)) as Marker3D
	# The power switch is in the bay beside the JAMMA socket, on the floor in front of the
	# board where the door lies flat once it is open: it stands up out of the shelf, so a
	# hand or a ray from above reaches it, and the board never hides it. Local +Y is out of
	# the face (up here); the button sinks along -Y.
	var ps := U.node(_root, bay, "Marker3D", "PowerSwitch", Vector3(0.17, 0.105, 0.22)) as Marker3D
	var plabel := U.node(_root, bay, "Label3D", "PowerLabel", Vector3(0.17, 0.1055, 0.27)) as Label3D
	plabel.basis = Basis(Vector3.RIGHT, -PI * 0.5)       # lies flat, reads from the front
	plabel.text = "POWER"
	plabel.pixel_size = 0.0007
	plabel.font_size = 48
	plabel.modulate = Color(0.9, 0.9, 0.95)
	plabel.outline_size = 0
	ps.name = "PowerSwitch"
	seat.name = "CartSeat"

	# The door: a drop-down panel hinged on its bottom edge, +X the hinge axis.
	var pivot := U.node(_root, bay, "Node3D", "DoorPivot", Vector3(0, 0.10, 0.40)) as Node3D
	U.box(_root, pivot, "DoorMesh", Vector3(0.60, 0.40, 0.02), Vector3(0, 0.20, -0.01), _body)
	U.box(_root, pivot, "DoorTrim", Vector3(0.60, 0.012, 0.022), Vector3(0, 0.394, -0.009), _trim)
	U.box(_root, pivot, "DoorHandle", Vector3(0.12, 0.018, 0.016), Vector3(0, 0.36, 0.008), _metal)
	# The grab box rides the door (a child of the pivot), so a door that has swung open
	# can still be taken hold of. It covers the HANDLE STRIP along the top edge only: a box
	# over the whole door made most of the cabinet's front a door, and aiming anywhere there
	# worked the door instead of picking the cabinet up. (The model blocks a pointer from
	# reaching the board through a shut door with its own pointer slab.)
	var grab := U.node(_root, pivot, "Area3D", "DoorGrab", Vector3(0, 0.34, 0.012)) as Area3D
	grab.set_script(load(SCRIPTS["hinge"]))
	grab.collision_layer = 0
	grab.collision_mask = 0
	grab.set("engage_radius", 0.12)
	var col := U.node(_root, grab, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.50, 0.12, 0.04)
	col.shape = shape


# ── extrusion ───────────────────────────────────────────────────────────────

## Extrude a (z, y) polygon along X, `thickness` thick and centred, flat-shaded.
func _extrude(poly: PackedVector2Array, thickness: float) -> ArrayMesh:
	var half := thickness * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	for side in [1.0, -1.0]:
		var normal := Vector3(side, 0, 0)
		for t in range(0, tris.size(), 3):
			var vs: Array[Vector3] = []
			for k in 3:
				var p := poly[tris[t + k]]
				vs.append(Vector3(side * half, p.y, p.x))
			_tri(st, vs[0], vs[1], vs[2], normal)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var edge := q - p
		# Outward normal of this wall, whichever way the polygon winds.
		var out2 := Vector2(edge.y, -edge.x).normalized()
		if _signed_area(poly) < 0.0:
			out2 = -out2
		var n := Vector3(0, out2.y, out2.x)
		var a := Vector3(-half, p.y, p.x)
		var b := Vector3(-half, q.y, q.x)
		var c := Vector3(half, q.y, q.x)
		var d := Vector3(half, p.y, p.x)
		_tri(st, a, b, c, n)
		_tri(st, a, c, d, n)
	return st.commit()


## One flat triangle with `normal`, wound so it faces that way.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var facing := (b - a).cross(c - a)
	if facing.dot(normal) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)


func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5
