## ArcadeCabinetBuilder — builds an arcade cabinet's nodes from a spec (ArcadeCabinetSpecs).
##
## The same code bakes the shipped scenes out of band (Tools/gen/gen_arcade_cabinet.gd, `bake`) and
## builds a cabinet's FORM again in the room when the game in its bay wants another one
## (RetroSystemModelArcadeCabinet.morph_to): the shell, the monitor, the control deck and its panels,
## the coin doors, the front sockets or the guns' holsters, the pedal. What the machine is wired to
## (the bay with its door and power switch, the JAMMA socket, the composite input) is built only when
## baking and is never rebuilt: a board, a docked bay, a cord or the power button hangs on those.
##
## Every top-level node of the form carries FORM_META, so a morph knows exactly what to take away.
## Low detail on purpose: an example to be consolidated by hand, whose parts are TYPED MODULES
## (Scripts/Objects/arcade/) rather than a list of node names. Origin on the floor at the centre of the
## base, front toward +Z; the side silhouette is a polygon extruded across the width: a toe-kick, a coin
## area, a control-panel overhang, a monitor and a marquee.
class_name ArcadeCabinetBuilder
extends RefCounted

## Set on every top-level node a form owns (rebuilt by a morph). Never on the bay, the JAMMA socket or
## the composite input.
const FORM_META := &"arcade_form"
## The shipped variant a baked scene was built from (ArcadeCabinetSpecs.variants), on the scene's root.
const VARIANT_META := &"arcade_variant"

const SIDE_T := 0.02
## The flange a button stands in: how proud of the plate it is, so a pressed cap sinks into it.
const RIM_H := 0.005
const TUBE_DEPTH := 0.07

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
	"pedal": "res://Scripts/Objects/arcade/arcade_pedal_module.gd",
	"av_in": "res://Scripts/Objects/arcade/arcade_av_in_module.gd",
}

const BUTTON_COLORS := [
	Color(0.85, 0.12, 0.12), Color(0.95, 0.75, 0.10), Color(0.15, 0.65, 0.25),
	Color(0.15, 0.35, 0.85), Color(0.92, 0.92, 0.92), Color(0.55, 0.20, 0.70),
]

## Where a gun hangs, in the cabinet's frame: the gun's own -Z points DOWN (muzzle in the cup), its
## grip toward the player. Rolled -90 degrees about X.
const HOLSTER_Y := 0.80
const HOLSTER_Z := 0.545
## Where each cord goes in: on the front, beside the holster's bracket, 42 mm outboard of it.
const CORD_ENTRY_Y := 0.74
const CORD_ENTRY_Z := 0.402

var _root: Node3D
## The node every part is owned by: the scene root when baking, null in the room.
var _owner: Node = null
var _v: Dictionary = {}
var _sh: Dictionary = {}
var _w := 0.66
var _in_w := 0.62         # between the side panels
var _h := 1.80
var _tube := Vector2(0.44, 0.33)
var _body: StandardMaterial3D
var _trim: StandardMaterial3D
var _dark: StandardMaterial3D
var _metal: StandardMaterial3D
## The top-level nodes this builder made for the form, in the order it made them.
var form_nodes: Array[Node] = []


## `spec` is a row of ArcadeCabinetSpecs (or one derived from it), `root` the cabinet's root (the
## model). `bake` is true for the out-of-band generator: every part is then owned by the root.
func _init(spec: Dictionary, root: Node3D, bake: bool = false) -> void:
	_v = spec
	_root = root
	_owner = root if bake else null
	_sh = ArcadeCabinetSpecs.shapes()[str(_v.get("shape", "upright"))]
	_w = _sh["w"]
	_in_w = _w - 0.04
	_h = _sh["h"]
	_tube = _sh["tube"]
	_body = ArcadeParts.mat(_v["body"], 0.0, 0.55)
	_trim = ArcadeParts.mat(_v["trim"], 0.0, 0.4)
	_dark = ArcadeParts.mat(Color(0.03, 0.03, 0.035), 0.0, 0.8)
	_metal = ArcadeParts.mat(Color(0.65, 0.66, 0.70), 0.9, 0.35)


## The whole cabinet as the generator bakes it, in the order the shipped scenes were always laid out.
func bake() -> void:
	_root.set_meta(VARIANT_META, str(_v.get("variant", "")))
	var cab := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Cabinet") as Node3D)
	_build_shell(cab)
	_build_monitor()
	_build_deck()
	_build_coin_doors()
	_build_guns_or_sockets()
	_build_bay()
	_build_av_in()
	if bool(_v["pedal"]):
		_build_pedal()
	apply_metrics()


## Only the parts a form owns, for a cabinet in the room that changes shape: everything bake() makes
## but the bay, the JAMMA socket and the composite input.
func build_form() -> void:
	var cab := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Cabinet") as Node3D)
	_build_shell(cab)
	_build_monitor()
	_build_deck()
	_build_coin_doors()
	_build_guns_or_sockets()
	if bool(_v["pedal"]):
		_build_pedal()
	apply_metrics()


## What the model needs of the shape (collision, pointer boxes, speakers, the options panel).
func apply_metrics() -> void:
	_root.set("cabinet_width", _w)
	_root.set("cabinet_height", _h)
	_root.set("marquee_bottom", _sh["marquee_bottom"])
	_root.set("glass_back_z", _sh["glass_back_z"])
	_root.set("marquee_front_z", _sh["marquee_front_z"])
	_root.set("screen_front_z", _sh["screen_front_z"])


func _form_node(n: Node) -> Node:
	n.set_meta(FORM_META, true)
	form_nodes.append(n)
	return n


func _build_guns_or_sockets() -> void:
	if int(_v["guns"]) > 0:
		_build_gun_holsters()
	elif bool(_v["sockets"]):
		_build_front_sockets()


# ── shell ───────────────────────────────────────────────────────────────────

func _build_shell(cab: Node3D) -> void:
	var side_mesh := _extrude(PackedVector2Array(_sh["profile"]), SIDE_T)
	for sx in [-1.0, 1.0]:
		var mi := ArcadeParts.node(_owner, cab, "MeshInstance3D", "SideL" if sx < 0 else "SideR",
			Vector3(sx * (_w - SIDE_T) * 0.5, 0, 0)) as MeshInstance3D
		mi.mesh = side_mesh
		mi.material_override = _body
	ArcadeParts.box(_owner, cab, "Rear", Vector3(_in_w, _h, 0.02), Vector3(0, _h * 0.5, -0.39), _body)
	var top: Array = _sh["top"]
	ArcadeParts.box(_owner, cab, "Top", Vector3(_in_w, 0.02, top[0]), Vector3(0, _h - 0.01, top[1]), _body)
	ArcadeParts.box(_owner, cab, "Floor", Vector3(_in_w, 0.02, 0.74), Vector3(0, 0.01, 0.0), _body)
	ArcadeParts.box(_owner, cab, "KickPlate", Vector3(_in_w, 0.09, 0.02), Vector3(0, 0.045, 0.34), _dark)
	# Coin area: the front between the bay door and the control panel.
	ArcadeParts.box(_owner, cab, "CoinFace", Vector3(_in_w, 0.28, 0.02), Vector3(0, 0.64, 0.39), _body)
	ArcadeParts.box(_owner, cab, "ApronUnder", Vector3(_in_w, 0.05, 0.07), Vector3(0, 0.785, 0.435), _body)
	ArcadeParts.box(_owner, cab, "Apron", Vector3(_in_w, 0.12, 0.02), Vector3(0, 0.86, 0.46), _body)
	ArcadeParts.box(_owner, cab, "ApronTrim", Vector3(_in_w, 0.012, 0.022), Vector3(0, 0.806, 0.462), _trim)
	# Marquee: a lit panel above the monitor, so it glows when the machine is on.
	var marquee_mat := ArcadeParts.mat(_v["marquee"], 0.0, 0.5, _v["glow"], 0.0)
	var mq: Dictionary = _sh["marquee"]
	var marquee := ArcadeParts.box(_owner, cab, "Marquee", Vector3(_in_w, mq["h"], 0.012), Vector3(0, mq["y"], mq["z"]), marquee_mat)
	var title := ArcadeParts.node(_owner, marquee, "Label3D", "MarqueeTitle", Vector3(0, 0, 0.0075)) as Label3D
	title.text = str(_v["title"])
	title.pixel_size = 0.0013
	# A long title is set smaller so it stays inside the marquee ("ARCADE" is the size that fits).
	title.font_size = int(96.0 * minf(1.0, 6.0 / float(str(_v["title"]).length())))
	title.modulate = Color(1.0, 0.95, 0.85)
	title.outline_size = 0
	title.no_depth_test = false
	ArcadeParts.box(_owner, cab, "MarqueeTrim", Vector3(_in_w, 0.012, 0.022), Vector3(0, mq["trim_y"], mq["z"]), _trim)
	# The underside of the marquee's overhang, closing the cabinet over the top of the glass.
	var under: Array = mq["under"]
	if not under.is_empty():
		ArcadeParts.box(_owner, cab, "MarqueeUnder", Vector3(_in_w, 0.012, under[0]), Vector3(0, under[1], under[2]), _dark)
	_build_art(cab, marquee, mq)


## The slots a game's art is hung in when its board is in the bay (RetroSystemModelArcadeCabinet
## `on_media_inserted`): the marquee's face and the outside of each side. Unit quads, hidden, scaled
## by the model to the art's proportions inside the `box` metadata (metres) for the marquee; the sides' are
## their own silhouette. A BoxMesh and the extruded sides carry no UVs for a picture, so these stand a hair in front.
func _build_art(cab: Node3D, marquee: Node3D, mq: Dictionary) -> void:
	var mq_art := ArcadeParts.quad(_owner, marquee, "MarqueeArt", Vector2.ONE, Vector3(0, 0, 0.0068), _art_mat())
	mq_art.visible = false
	mq_art.set_meta("box", Vector2(_in_w - 0.04, float(mq["h"]) - 0.04))
	# Each side's art is the side's own silhouette, a hair outside the panel, with UVs laid flat over its
	# bounds: the picture fills the whole flank and the model crops it (uv1_scale/offset), so a cover
	# of any proportions covers it and what does not fit is cut.
	for sx in [-1.0, 1.0]:
		var art := ArcadeParts.node(_owner, cab, "MeshInstance3D", "SideArtL" if sx < 0 else "SideArtR", Vector3.ZERO) as MeshInstance3D
		art.mesh = _side_art_mesh(sx)
		art.mesh.surface_set_material(0, _art_mat())
		art.visible = false
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p: Vector2 in _sh["profile"]:
			lo = lo.min(p)
			hi = hi.max(p)
		# Width over height of the flank as it stands in the world (z over y): what a picture is cropped to.
		art.set_meta("aspect", (hi.x - lo.x) / (hi.y - lo.y))


## The outside face of a side panel: the silhouette (z, y) at x = sx * (w/2 + 0.5 mm), facing out, UV 0..1
## over its bounds, left to right as a person standing at that side sees it (the front is on the right
## of the left flank, on the left of the right one), top of the picture up.
func _side_art_mesh(sx: float) -> ArrayMesh:
	var poly := PackedVector2Array(_sh["profile"])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := hi - lo
	var x := sx * (_w * 0.5 + 0.0005)
	var normal := Vector3(sx, 0, 0)
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		var vs: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for k in 3:
			var p := poly[tris[t + k]]
			vs.append(Vector3(x, p.y, p.x))
			var u := (p.x - lo.x) / span.x
			uvs.append(Vector2(u if sx < 0.0 else 1.0 - u, 1.0 - (p.y - lo.y) / span.y))
		# Clockwise seen from outside is the front: flip a triangle wound the other way.
		if (vs[1] - vs[0]).cross(vs[2] - vs[0]).dot(normal) > 0.0:
			vs.reverse()
			uvs.reverse()
		for k in 3:
			st.set_normal(normal)
			st.set_uv(uvs[k])
			st.add_vertex(vs[k])
	return st.commit()


func _art_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	return m


# ── monitor ─────────────────────────────────────────────────────────────────

func _build_monitor() -> void:
	# The glass is the silhouette's own slanted edge, so it is part of the cabinet and not a
	# panel in front of it; the tube is TUBE_DEPTH behind it, inside, between the side panels,
	# and the frame is a black bezel hiding the tube's edge. Local +Z is the glass's normal
	# (up and out toward the player), so everything "behind the glass" is a negative z.
	var a: Vector2 = _sh["glass_a"]
	var b: Vector2 = _sh["glass_b"]
	var mid := (a + b) * 0.5
	var along := b - a
	var theta := atan2(along.x, along.y)   # rotation about X taking +Y onto `along` (z, y)
	var basis := Basis(Vector3.RIGHT, theta)
	var mod := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Screen", Vector3(0, mid.y, mid.x))) as Node3D
	mod.set_script(load(SCRIPTS["screen"]))
	mod.basis = basis
	var length := along.length()
	# The tube's enclosure: a dark board behind the picture, as wide as the cabinet.
	ArcadeParts.box(_owner, mod, "Bezel", Vector3(_in_w, length, 0.012), Vector3(0, 0, -TUBE_DEPTH - 0.006), _dark)
	var screen := ArcadeParts.quad(_owner, mod, "CabinetScreen", _tube, Vector3(0, 0.005, -TUBE_DEPTH + 0.0005),
		ArcadeParts.mat(Color(0.015, 0.017, 0.02), 0.0, 0.12))
	screen.name = "CabinetScreen"
	# The classic glass: a translucent pane flush with the cabinet's front, the picture showing
	# through it, in a black frame whose outer face is the glass's own plane.
	var glass_mat := ArcadeParts.mat(Color(0.55, 0.65, 0.75, 0.035), 0.0, 0.04)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	glass_mat.metallic_specular = 1.0
	var glass_w := _tube.x + 0.06
	var glass_h := length - 0.11
	var glass := ArcadeParts.quad(_owner, mod, "Glass", Vector2(glass_w, glass_h), Vector3(0, 0, -0.004), glass_mat)
	glass.name = "Glass"
	var bar_t := 0.012
	var fz := -bar_t * 0.5
	var side_w := (_in_w - glass_w) * 0.5
	var top_h := (length - glass_h) * 0.5
	for sx in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "FrameSide%s" % ("L" if sx < 0 else "R"), Vector3(side_w, length, bar_t),
			Vector3(sx * (glass_w * 0.5 + side_w * 0.5), 0, fz), _dark)
	for sy in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "Frame%s" % ("Top" if sy > 0 else "Bottom"), Vector3(glass_w, top_h, bar_t),
			Vector3(0, sy * (glass_h * 0.5 + top_h * 0.5), fz), _dark)


# ── control deck ────────────────────────────────────────────────────────────

func _build_deck() -> void:
	# The deck runs from the apron's top edge (z 0.47, y 0.92) up to the monitor
	# (z 0.30, y 1.00). Its local +Y is up-and-back along the slope, +Z its normal.
	var a := Vector2(0.47, 0.92)
	var b := Vector2(0.30, 1.00)
	var mid := (a + b) * 0.5
	var along := b - a
	var theta := atan2(along.x, along.y)
	var deck := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Deck", Vector3(0, mid.y, mid.x))) as Node3D
	deck.basis = Basis(Vector3.RIGHT, theta)
	ArcadeParts.box(_owner, deck, "DeckPlate", Vector3(_in_w, along.length(), 0.012), Vector3(0, 0, -0.006), _dark)

	var players: Array = _v["players"]
	for i in players.size():
		_build_player(deck, i, players[i])


## One player's panel, from its spec (see ArcadeCabinetSpecs): a stick with N buttons, a paddle dial,
## or START alone, and always START on the front edge.
func _build_player(deck: Node3D, index: int, spec: Dictionary) -> void:
	var mod := ArcadeParts.node(_owner, deck, "Node3D", "Player%d" % (index + 1)) as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", index)
	var kind: String = spec["kind"]
	var start_x: float = spec["start_x"]
	var left := start_x - 0.02
	var right := start_x + 0.02
	if kind == "stick":
		var stick_x: float = spec["stick_x"]
		# The stick: a base plate, then a pivot carrying shaft and ball.
		ArcadeParts.cylinder(_owner, mod, "StickBase", 0.034, 0.004, Vector3(stick_x, 0.015, 0.002), _metal, Vector3.BACK)
		var pivot := ArcadeParts.node(_owner, mod, "Node3D", "StickPivot", Vector3(stick_x, 0.015, 0.004)) as Node3D
		ArcadeParts.cylinder(_owner, pivot, "StickShaft", 0.006, 0.07, Vector3(0, 0, 0.035), _metal, Vector3.BACK)
		var ball := ArcadeParts.node(_owner, pivot, "MeshInstance3D", "StickBall", Vector3(0, 0, 0.085)) as MeshInstance3D
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		# 24 x 12 (Godot's default 64 x 32 is 4224 triangles for a ball of 4.4 cm).
		sm.radial_segments = 24
		sm.rings = 12
		ball.mesh = sm
		ball.material_override = ArcadeParts.mat(Color(0.85, 0.10, 0.10) if index == 0 else Color(0.10, 0.25, 0.85), 0.0, 0.3)
		left = minf(left, stick_x - 0.045)
		right = maxf(right, stick_x + 0.045)
		# The buttons: plain caps, not controls of their own.
		var buttons: Array = spec["buttons"]
		for k in buttons.size():
			var bt: Dictionary = buttons[k]
			var pos: Vector2 = bt["pos"]
			var radius: float = bt["radius"]
			_cap(mod, "Btn%d" % (k + 1), Vector3(pos.x, pos.y, 0.0), radius, BUTTON_COLORS[int(bt["color"])], 0.012)
			left = minf(left, pos.x - radius - 0.02)
			right = maxf(right, pos.x + radius + 0.02)
	elif kind == "dial":
		# A paddle dial (Pong): a base ring and a knob that turns with LEFT and RIGHT.
		var dial_x: float = spec["dial_x"]
		var dpos := Vector3(dial_x, 0.015, 0.0)
		ArcadeParts.cylinder(_owner, mod, "DialBase", 0.036, 0.006, dpos + Vector3(0, 0, 0.003), _metal, Vector3.BACK)
		var dpivot := ArcadeParts.node(_owner, mod, "Node3D", "DialPivot", dpos + Vector3(0, 0, 0.006)) as Node3D
		ArcadeParts.cylinder(_owner, dpivot, "DialKnob", 0.027, 0.024, Vector3(0, 0, 0.012),
			ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.4), Vector3.BACK)
		ArcadeParts.box(_owner, dpivot, "DialMark", Vector3(0.004, 0.018, 0.003), Vector3(0, 0.014, 0.0245),
			ArcadeParts.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4))
		left = minf(left, dial_x - 0.045)
		right = maxf(right, dial_x + 0.045)
	_cap(mod, "Start", Vector3(start_x, -0.07, 0.0), 0.011, Color(0.92, 0.92, 0.92), 0.008)
	# The whole panel is ONE pointable thing: aiming at any of it lights all of it, and a press
	# attaches you to it as to a controller (ArcadePanelGrip). A panel with only START has nothing
	# to take hold of: its press is START itself (`momentary`).
	var grip := ArcadeParts.node(_owner, mod, "Area3D", "PanelGrip", Vector3.ZERO) as Area3D
	grip.set_script(load(SCRIPTS["panel"]))
	grip.collision_layer = 0
	grip.collision_mask = 0
	var gcol := ArcadeParts.node(_owner, grip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var gshape := BoxShape3D.new()
	gcol.shape = gshape
	if kind == "start":
		grip.set("momentary", true)
		grip.set("panel_size", Vector2(0.07, 0.07))
		grip.position = Vector3(start_x, -0.07, 0.03)
		gshape.size = Vector3(0.07, 0.07, 0.08)
	else:
		var width := right - left
		grip.set("panel_size", Vector2(width, 0.185))
		grip.position = Vector3((left + right) * 0.5, -0.01, 0.03)
		gshape.size = Vector3(width, 0.185, 0.08)


## A button on the deck, as a pushbutton is made: the cap, which sinks when its bit is held, in a
## flange of the same colour that stays where it is (`<name>Rim`, a short cone wider than the cap, so
## the cap reads as standing in a rim of its own colour instead of a bare cylinder sticking out of
## the plate). Not pokeable by itself. Returns the cap, the node the control module moves.
func _cap(parent: Node3D, node_name: String, pos: Vector3, radius: float,
		color: Color, height: float) -> MeshInstance3D:
	var m := ArcadeParts.mat(color, 0.0, 0.3)
	var rim := ArcadeParts.cylinder(_owner, parent, node_name + "Rim", radius * 1.22, RIM_H,
		pos + Vector3(0, 0, RIM_H * 0.5), m, Vector3.BACK)
	(rim.mesh as CylinderMesh).top_radius = radius * 1.10
	# The cap's own sides lean in a little toward its top, as a moulded button's do.
	var cap := ArcadeParts.cylinder(_owner, parent, node_name, radius, height, pos + Vector3(0, 0, height * 0.5),
		m, Vector3.BACK)
	(cap.mesh as CylinderMesh).top_radius = radius * 0.88
	return cap


# ── coin doors ──────────────────────────────────────────────────────────────

func _build_coin_doors() -> void:
	var xs: Array = _v["coins"]
	for i in xs.size():
		var x: float = xs[i]
		var door := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "CoinDoor%d" % (i + 1), Vector3(x, 0.64, 0.40))) as Node3D
		door.set_script(load(SCRIPTS["coin"]))
		door.set("player", i)
		ArcadeParts.box(_owner, door, "Plate", Vector3(0.10, 0.20, 0.006), Vector3(0, 0, 0.003), _metal)
		ArcadeParts.box(_owner, door, "ReturnCup", Vector3(0.05, 0.03, 0.008), Vector3(0, -0.055, 0.004), _dark)
		ArcadeParts.cylinder(_owner, door, "ReturnButton", 0.012, 0.006, Vector3(0, -0.08, 0.006), _trim, Vector3.BACK)
		# The slot: a lit lip you poke.
		var lip := ArcadeParts.node(_owner, door, "Area3D", "CoinSlot", Vector3(0, 0.045, 0.006)) as Area3D
		lip.set_script(load(SCRIPTS["button"]))
		lip.collision_layer = 0
		lip.collision_mask = 0
		lip.set("trigger_radius", 0.02)
		lip.set("depress_depth", 0.002)
		lip.set("depress_axis", Vector3(0, 0, -1))
		var col := ArcadeParts.node(_owner, lip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.07, 0.045, 0.04)
		col.shape = shape
		col.position = Vector3(0, 0, 0.012)
		ArcadeParts.box(_owner, lip, "ButtonMesh", Vector3(0.034, 0.010, 0.004), Vector3(0, 0, 0.002),
			ArcadeParts.mat(Color(1.0, 0.8, 0.2), 0.0, 0.4, Color(1.0, 0.7, 0.1), 0.8))
		var tag := ArcadeParts.node(_owner, door, "Label3D", "CoinLabel", Vector3(0, 0.075, 0.0065)) as Label3D
		tag.text = "COIN"
		tag.pixel_size = 0.0006
		tag.font_size = 48
		tag.modulate = Color(0.1, 0.1, 0.12)
		tag.outline_size = 0
		ArcadeParts.node(_owner, door, "Marker3D", "CoinSpawn", Vector3(0, 0.075, 0.075))
		ArcadeParts.node(_owner, door, "Marker3D", "CoinDrop", Vector3(0, 0.045, 0.0))


# ── front sockets ───────────────────────────────────────────────────────────

func _build_front_sockets() -> void:
	var sockets := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Sockets", Vector3.ZERO)) as Node3D
	sockets.set_script(load(SCRIPTS["sockets"]))
	# Rolled 180 degrees about Z with +Z out of the face, as the NES authors its
	# seats, so a plug seats connector-in and upright.
	for i in 2:
		var seat := ArcadeParts.node(_owner, sockets, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(-0.24 if i == 0 else 0.24, 0.86, 0.47)) as Marker3D
		seat.basis = Basis(Vector3.BACK, PI)
		ArcadeParts.box(_owner, sockets, "Recess%d" % (i + 1), Vector3(0.034, 0.026, 0.004),
			Vector3(-0.24 if i == 0 else 0.24, 0.86, 0.4685), _dark)


# ── guns in holsters ────────────────────────────────────────────────────────

## Two guns on the front, hung muzzle-down in a holster on the apron either side of the coin
## doors, each on a cord that goes into the cabinet. The Sockets module carries the cord entries
## (the system's controller-port zones) and the Holster markers where the guns hang; the model
## builds the guns and hangs them (RetroSystemModelArcadeCabinet.captive_controllers).
func _build_gun_holsters() -> void:
	var sockets := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Sockets", Vector3.ZERO)) as Node3D
	sockets.set_script(load(SCRIPTS["sockets"]))
	var count: int = int(_v["guns"])
	for i in count:
		var side := -1.0 if i == 0 else 1.0
		var sx := side * (_w * 0.5 - 0.09)
		var entry_x := sx + side * 0.042
		# Where the cord goes in, +Z out of the face, as the front sockets are authored.
		var seat := ArcadeParts.node(_owner, sockets, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(entry_x, CORD_ENTRY_Y, CORD_ENTRY_Z)) as Marker3D
		seat.basis = Basis(Vector3.BACK, PI)
		ArcadeParts.cylinder(_owner, sockets, "Grommet%d" % (i + 1), 0.017, 0.008,
			Vector3(entry_x, CORD_ENTRY_Y, CORD_ENTRY_Z + 0.004), _dark, Vector3.BACK)
		# Where the gun hangs.
		var holster := ArcadeParts.node(_owner, sockets, "Marker3D", "Holster%d" % (i + 1),
			Vector3(sx, HOLSTER_Y, HOLSTER_Z)) as Marker3D
		holster.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		# The bracket: a plate on the apron's face, a spacer out over the coin face below it, and the
		# cup the muzzle rests in.
		ArcadeParts.box(_owner, sockets, "HolsterPlate%d" % (i + 1), Vector3(0.07, 0.30, 0.012),
			Vector3(sx, 0.78, 0.478), ArcadeParts.mat(Color(0.10, 0.10, 0.12), 0.0, 0.5))
		ArcadeParts.box(_owner, sockets, "HolsterBand%d" % (i + 1), Vector3(0.072, 0.012, 0.014),
			Vector3(sx, 0.665, 0.478), _trim)
		ArcadeParts.box(_owner, sockets, "HolsterSpacer%d" % (i + 1), Vector3(0.07, 0.14, 0.070),
			Vector3(sx, 0.69, 0.438), _dark)
		ArcadeParts.cylinder(_owner, sockets, "HolsterCup%d" % (i + 1), 0.030, 0.045,
			Vector3(sx, 0.6175, 0.511), _dark, Vector3.UP)
		ArcadeParts.box(_owner, sockets, "HolsterStrap%d" % (i + 1), Vector3(0.05, 0.010, 0.040),
			Vector3(sx, 0.725, 0.505), _metal)


# ── foot pedal ──────────────────────────────────────────────────────────────

## A Time Crisis-style foot pedal on the floor in front of the deck, with its cable running to
## the cabinet. DRAWN ONLY: ArcadePedalModule is `active = false` and nothing reads it. How a
## pedal should reach the core is its own analysis (docs/dev/arcade.md).
func _build_pedal() -> void:
	var pedal := _form_node(ArcadeParts.node(_owner, _root, "Node3D", "Pedal", Vector3(0.0, 0.0, 0.80))) as Node3D
	pedal.set_script(load(SCRIPTS["pedal"]))
	# The base plate, the hinge, and the footplate raised toe-up on its heel.
	ArcadeParts.box(_owner, pedal, "PedalBase", Vector3(0.16, 0.012, 0.26), Vector3(0, 0.006, 0.0), _dark)
	ArcadeParts.cylinder(_owner, pedal, "PedalHinge", 0.010, 0.15, Vector3(0, 0.020, 0.09), _metal, Vector3.RIGHT)
	var plate := ArcadeParts.box(_owner, pedal, "PedalPlate", Vector3(0.13, 0.014, 0.20), Vector3(0, 0.050, -0.01),
		ArcadeParts.mat(Color(0.75, 0.10, 0.10), 0.0, 0.45))
	plate.basis = Basis(Vector3.RIGHT, deg_to_rad(18.0))
	# The cable, flat on the floor, back toward the cabinet.
	ArcadeParts.box(_owner, pedal, "PedalCable", Vector3(0.012, 0.008, 0.30), Vector3(0, 0.004, -0.28), _dark)


# ── composite input ─────────────────────────────────────────────────────────

## The cabinet's composite INPUT: a rectangle on the compartment floor beside the power supply (which stands to the
## right at the back; this is the other side of it), three phono sockets on its top facing UP so a hand leaning
## in puts a plug straight down, a yellow plate with COMPOSITE IN in front of them, and a LED on its front
## that says whether it takes input (ArcadeAvInModule: only while the compartment holds no unit). The sockets
## are the cabinet's, not any bay unit's.
func _build_av_in() -> void:
	var rca := load("res://Scenes/Objects/cables/rca_port.tscn") as PackedScene
	var mod := ArcadeParts.node(_owner, _root, "Node3D", "AvIn", Vector3.ZERO) as Node3D
	mod.set_script(load(SCRIPTS["av_in"]))
	var cx := -0.20
	var cz := -0.29
	var floor_y := 0.105
	var h := 0.10
	var top := floor_y + h
	ArcadeParts.box(_owner, mod, "InBox", Vector3(0.16, h, 0.14), Vector3(cx, floor_y + h * 0.5, cz), _metal)
	ArcadeParts.box(_owner, mod, "InPlate", Vector3(0.15, 0.001, 0.030), Vector3(cx, top + 0.0005, cz + 0.045),
		ArcadeParts.mat(Color(0.95, 0.80, 0.12), 0.0, 0.5))
	var tag := ArcadeParts.node(_owner, mod, "Label3D", "InLegend", Vector3(cx, top + 0.0020, cz + 0.045)) as Label3D
	tag.basis = Basis(Vector3.RIGHT, -PI * 0.5)       # lies flat on the plate, reads from the front
	tag.text = "COMPOSITE IN"
	tag.pixel_size = 0.00075
	# Small enough to sit inside the 15 cm plate with a margin (arcade_tests measures it); at 32 it ran off the end.
	tag.font_size = 22
	tag.modulate = Color(0.05, 0.05, 0.06)
	tag.outline_size = 0
	var led := ArcadeParts.box(_owner, mod, "InLed", Vector3(0.014, 0.014, 0.002), Vector3(cx + 0.055, floor_y + 0.07, cz + 0.071),
		ArcadeParts.mat(Color(0.25, 0.04, 0.04), 0.0, 0.5))
	led.name = "InLed"
	if rca == null:
		return
	for i in 3:
		var jack := rca.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		jack.name = ["VideoIn", "AudioLIn", "AudioRIn"][i]
		mod.add_child(jack)
		jack.owner = _owner
		jack.set("direction", 1)             # RcaPort.Direction.IN
		jack.set("channel", [0, 1, 2][i])    # VIDEO, AUDIO_L, AUDIO_R
		var x := cx - 0.045 + 0.045 * i
		# +Z (out of the socket) turned to +Y: the plug goes in from above.
		jack.position = Vector3(x, top + 0.010, cz - 0.012)
		jack.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		# A colour disc under each socket (yellow video, white left, red right), as a console's jacks are marked.
		ArcadeParts.cylinder(_owner, mod, "InDisc%d" % (i + 1), 0.0125, 0.0015, Vector3(x, top + 0.00075, cz - 0.012),
			ArcadeParts.mat([Color(0.95, 0.80, 0.10), Color(0.92, 0.92, 0.92), Color(0.85, 0.10, 0.10)][i], 0.0, 0.5))


# ── bay ─────────────────────────────────────────────────────────────────────

func _build_bay() -> void:
	var bay := ArcadeParts.node(_owner, _root, "Node3D", "Bay", Vector3.ZERO) as Node3D
	bay.set_script(load(SCRIPTS["bay"]))
	bay.set("bay_kind", str(_v["bay"]))
	var interior := ArcadeParts.mat(Color(0.05, 0.05, 0.06), 0.0, 0.9)
	ArcadeParts.box(_owner, bay, "BayFloor", Vector3(_in_w - 0.02, 0.01, 0.76), Vector3(0, 0.095, 0.0), interior)
	ArcadeParts.box(_owner, bay, "BayRear", Vector3(_in_w - 0.02, 0.40, 0.01), Vector3(0, 0.30, -0.375), interior)
	ArcadeParts.box(_owner, bay, "BayLeft", Vector3(0.01, 0.40, 0.76), Vector3(-(_in_w * 0.5 - 0.015), 0.30, 0.0), interior)
	ArcadeParts.box(_owner, bay, "BayRight", Vector3(0.01, 0.40, 0.76), Vector3(_in_w * 0.5 - 0.015, 0.30, 0.0), interior)
	# No ceiling over the compartment: a player who leans into the cabinet sees the bay from above, and a
	# bay is taken out upward through the open top. The shell's own floor above (the deck) closes it.
	ArcadeParts.box(_owner, bay, "Psu", Vector3(0.16, 0.15, 0.14), Vector3(0.20, 0.18, -0.29), _metal)
	# The board is not drawn here: the bay is a separate object (ArcadeBayUnit, baked by
	# gen_arcade_bay.gd) that clips into the BayMount, standing on the compartment's floor, and
	# brings its own socket, its harness and the seat the board stands on. What stays is the shell
	# it stands in: the walls, the power supply, the door, the power switch and the JAMMA socket
	# on the back that a bay standing elsewhere is wired to.
	ArcadeParts.node(_owner, bay, "Marker3D", "BayMount", Vector3(0, 0.10, 0.0))
	var jamma_port := load("res://Scenes/Objects/cables/jamma_port.tscn") as PackedScene
	if jamma_port != null:
		# GEN_EDIT_STATE_INSTANCE: only what this node changes is saved, not the base scene's own script and
		# signals again (a script set twice connects the zone's signals twice).
		var port := jamma_port.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		port.name = "JammaPort"
		_root.add_child(port)
		port.owner = _owner
		# On the back panel, +Z out of it (a console's jacks are turned the same way).
		port.position = Vector3(0, 0.30, -0.41)
		port.basis = Basis(Vector3.RIGHT, PI)
	# The power switch is in the bay beside the JAMMA socket, on the floor in front of the
	# board where the door lies flat once it is open: it stands up out of the shelf, so a
	# hand or a ray from above reaches it, and the board never hides it. Local +Y is out of
	# the face (up here); the button sinks along -Y.
	var ps := ArcadeParts.node(_owner, bay, "Marker3D", "PowerSwitch", Vector3(0.17, 0.105, 0.22)) as Marker3D
	var plabel := ArcadeParts.node(_owner, bay, "Label3D", "PowerLabel", Vector3(0.17, 0.1055, 0.27)) as Label3D
	plabel.basis = Basis(Vector3.RIGHT, -PI * 0.5)       # lies flat, reads from the front
	plabel.text = "POWER"
	plabel.pixel_size = 0.0007
	plabel.font_size = 48
	plabel.modulate = Color(0.9, 0.9, 0.95)
	plabel.outline_size = 0
	ps.name = "PowerSwitch"

	# The door: a drop-down panel hinged on its bottom edge, +X the hinge axis.
	var pivot := ArcadeParts.node(_owner, bay, "Node3D", "DoorPivot", Vector3(0, 0.10, 0.40)) as Node3D
	ArcadeParts.box(_owner, pivot, "DoorMesh", Vector3(_in_w - 0.02, 0.40, 0.02), Vector3(0, 0.20, -0.01), _body)
	ArcadeParts.box(_owner, pivot, "DoorTrim", Vector3(_in_w - 0.02, 0.012, 0.022), Vector3(0, 0.394, -0.009), _trim)
	ArcadeParts.box(_owner, pivot, "DoorHandle", Vector3(0.12, 0.018, 0.016), Vector3(0, 0.36, 0.008), _metal)
	# The grab box rides the door (a child of the pivot), so a door that has swung open
	# can still be taken hold of. It covers the HANDLE STRIP along the top edge only: a box
	# over the whole door made most of the cabinet's front a door, and aiming anywhere there
	# worked the door instead of picking the cabinet up. (The model blocks a pointer from
	# reaching the board through a shut door with its own pointer slab.)
	var grab := ArcadeParts.node(_owner, pivot, "Area3D", "DoorGrab", Vector3(0, 0.34, 0.012)) as Area3D
	grab.set_script(load(SCRIPTS["hinge"]))
	grab.collision_layer = 0
	grab.collision_mask = 0
	grab.set("engage_radius", 0.12)
	var col := ArcadeParts.node(_owner, grab, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = Vector3(_in_w - 0.12, 0.12, 0.04)
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
