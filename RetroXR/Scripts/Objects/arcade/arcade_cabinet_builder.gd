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
## Where a slot handle's dome centre stands above its carriage, in the carriage's frame (Panic Park): the hands' reach point
## (ArcadePanelHands.SlideGrab.handle).
const SLOT_HANDLE_Z := 0.095
## Where a slot's lever rail runs across the deck and where each START stands above it (the deck panel's own y, +Y toward the screen): the deck is 0.07 m deeper than
## an upright's (ArcadeCabinetSpecs.SLOT_DECK_EXTRA), a hand's breadth of it in front of the lever and the START clear of the handle's dome.
const SLOT_LEVER_Y := -0.035
const SLOT_START_Y := 0.075
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
	"service": "res://Scripts/Objects/arcade/arcade_service_module.gd",
	"seat": "res://Scripts/Objects/room/cockpit_seat.gd",
	"seat_trigger": "res://Scripts/Objects/room/seat_trigger.gd",
}

## The rifle a `rifle` gun cabinet rests on its post (Tools/gen/gen_arcade_gun.gd `--variant=rifle`).
const RIFLE_SCENE := "res://Scenes/Objects/peripherals/arcade_light_rifle.tscn"

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
## Where the top-level nodes of what is being built go: the root itself when baking, a stage that is not in the
## tree while a form is built in the room (build_form).
var _top: Node3D
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
## Solid boxes the form adds to the cabinet's own (a cockpit, a dance stage, deck wings), in the cabinet's
## frame: the model's collision takes them (FORM_BOXES_META), and its pointer boxes the ones to aim at.
var form_boxes: Array[AABB] = []
## Solid parts the shape adds to the shell's own (a sit-down cabinet's hood and the wedge of glass in front of its housing), in the cabinet's frame:
## the model's collision takes them (SOLID_BOXES_META), unlike a form's boxes, which are only aimed at.
var solid_boxes: Array[AABB] = []


## `spec` is a row of ArcadeCabinetSpecs (or one derived from it), `root` the cabinet's root (the
## model). `bake` is true for the out-of-band generator: every part is then owned by the root.
func _init(spec: Dictionary, root: Node3D, bake: bool = false) -> void:
	_v = spec
	_root = root
	_top = root
	_owner = root if bake else null
	_sh = ArcadeCabinetSpecs.shapes()[str(_v.get("shape", "upright"))]
	# A deck deeper than the shape's own (a slot's: Panic Park's levers with START above them).
	if float(_v.get("deck_extra", 0.0)) > 0.0:
		_sh = ArcadeCabinetSpecs.deepened(_sh, float(_v["deck_extra"]))
	# The width is the cabinet's (a spec may keep it across forms), the shape the form's.
	_w = float(_v.get("width", _sh["w"]))
	_in_w = _w - 0.04
	_h = _sh["h"]
	_tube = tube_of(_v)
	_body = ArcadeParts.mat(_v["body"], 0.0, 0.55)
	_trim = ArcadeParts.mat(_v["trim"], 0.0, 0.4)
	_dark = ArcadeParts.mat(Color(0.03, 0.03, 0.035), 0.0, 0.8)
	_metal = ArcadeParts.mat(Color(0.65, 0.66, 0.70), 0.9, 0.35)


## The whole cabinet as the generator bakes it, in the order the shipped scenes were always laid out.
func bake() -> void:
	_root.set_meta(VARIANT_META, str(_v.get("variant", "")))
	var cab := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Cabinet") as Node3D)
	_build_shell(cab)
	_build_monitor()
	_build_deck()
	_build_coin_doors()
	_build_guns_or_sockets()
	_build_bay()
	_build_service()
	_build_av_in()
	_build_extras()
	apply_metrics()


## Only the parts a form owns, for a cabinet in the room that changes shape: everything bake() makes
## but the bay, the JAMMA socket and the composite input.
##
## Built on a stage that is NOT in the tree and moved onto the cabinet whole, as a loaded scene arrives: a node
## that is scripted and configured BEFORE it enters the tree gets its _ready (a panel's grip, which makes itself
## pointable there, and a button or a hinge, which make themselves ready to be worked). Scripted after it had
## entered, as these once were, none ran: every panel and wheel a morph built could not be aimed at or taken
## hold of, and only the baked ones could.
func build_form() -> void:
	var stage := Node3D.new()
	_top = stage
	var cab := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Cabinet") as Node3D)
	_build_shell(cab)
	_build_monitor()
	_build_deck()
	_build_coin_doors()
	_build_guns_or_sockets()
	_build_extras()
	_top = _root
	for part in stage.get_children():
		stage.remove_child(part)
		_root.add_child(part)
	stage.free()
	apply_metrics()


## What stands on the floor in front: a gun game's pedals, a driving cockpit, a dance stage.
func _build_extras() -> void:
	for i in (_v.get("gun_pedals", []) as Array).size():
		_build_pedal(i)
	if _v.has("cockpit"):
		_build_cockpit(_v["cockpit"])
	if _v.has("bench"):
		_build_bench(_v["bench"])
	if _v.has("bike"):
		_build_bike(_v["bike"])
	if _v.has("cycle"):
		_build_cycle(_v["cycle"])
	if _v.has("stage"):
		_build_stage(_v["stage"])


## Metadata on the cabinet's root: the solid-looking parts its form adds beyond the shell (a cockpit, a
## stage, deck wings), as AABBs in the cabinet's frame. The model gives them POINTER boxes (aimed at, they are
## the cabinet, to take hold of) and no collision: a player walks into a cockpit or onto a stage.
const FORM_BOXES_META := &"arcade_form_boxes"
## Metadata on the cabinet's root: the shape's solid parts beyond the shell (`solid_boxes`), as AABBs in the cabinet's frame.
const SOLID_BOXES_META := &"arcade_solid_boxes"
## The cabinet's base on the floor with what the form adds, a Rect2 in (x, z) (GroundPlacement's rectangle);
## absent while it is the shell's own.
const FOOTPRINT_META := &"arcade_footprint"


## What the model needs of the shape (collision, pointer boxes, speakers, the options panel).
func apply_metrics() -> void:
	_root.set("cabinet_width", _w)
	_root.set("cabinet_height", _h)
	_root.set("marquee_bottom", _sh["marquee_bottom"])
	_root.set("glass_back_z", _sh["glass_back_z"])
	_root.set("marquee_front_z", _sh["marquee_front_z"])
	_root.set("screen_front_z", _sh["screen_front_z"])
	if form_boxes.is_empty():
		if _root.has_meta(FORM_BOXES_META):
			_root.remove_meta(FORM_BOXES_META)
	else:
		_root.set_meta(FORM_BOXES_META, form_boxes.duplicate())
	if solid_boxes.is_empty():
		if _root.has_meta(SOLID_BOXES_META):
			_root.remove_meta(SOLID_BOXES_META)
	else:
		_root.set_meta(SOLID_BOXES_META, solid_boxes.duplicate())
	var shell := Rect2(Vector2(-_w * 0.5, -0.40), Vector2(_w, 0.80))
	var rect := shell
	for b in form_boxes:
		rect = rect.merge(Rect2(Vector2(b.position.x, b.position.z), Vector2(b.size.x, b.size.z)))
	if rect.is_equal_approx(shell):
		if _root.has_meta(FOOTPRINT_META):
			_root.remove_meta(FOOTPRINT_META)
	else:
		_root.set_meta(FOOTPRINT_META, rect)


# ── the screen ──────────────────────────────────────────────────────────────

## The most glass the shape has room for: the width between the side panels (less the frame) and the slanted
## edge's length (less the frame top and bottom).
func glass_limits() -> Vector2:
	return ArcadeCabinetSpecs.glass_limits(_sh, _in_w)


## The tube a spec's cabinet is drawn with, metres (ArcadeCabinetSpecs.tube_of): what the constructor lays the monitor out with, and what
## the tests measure.
static func tube_of(spec: Dictionary) -> Vector2:
	return ArcadeCabinetSpecs.tube_of(spec)


## The tube a screen spec asks for, fitted to the glass (ArcadeCabinetSpecs.tube_for).
static func tube_for(screen: Dictionary, limits: Vector2, native: Vector2, native_inches: float) -> Vector2:
	return ArcadeCabinetSpecs.tube_for(screen, limits, native, native_inches)


## [x, y, w, h] as a Rect2 (a spec holds plain arrays).
static func _part_of(a: Array) -> Rect2:
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


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
	# A body wider than the bay's door (a form wider than the cabinet it is built on: three or four players, a gun
	# cabinet's wide body) is closed beside it: the bay is baked with the cabinet and a form never rebuilds it,
	# so its door keeps the width it had (`door_width`, ArcadeCabinetSpecs.for_game).
	var door_w := float(_v.get("door_width", _in_w - 0.02))
	if _in_w > door_w + 0.03:
		var cheek := (_in_w - door_w) * 0.5
		for sx in [-1.0, 1.0]:
			ArcadeParts.box(_owner, cab, "LowerFace%s" % ("L" if sx < 0 else "R"), Vector3(cheek, 0.41, 0.02),
				Vector3(sx * (door_w * 0.5 + cheek * 0.5), 0.295, 0.39), _body)
	# The apron's face stands at the shape's `apron_z` (0.47 unless the deck was made deeper); the control panel overhangs the coin face as far.
	var apron_z := float(_sh.get("apron_z", 0.47))
	ArcadeParts.box(_owner, cab, "ApronUnder", Vector3(_in_w, 0.05, apron_z - 0.40), Vector3(0, 0.785, (0.40 + apron_z) * 0.5), _body)
	ArcadeParts.box(_owner, cab, "Apron", Vector3(_in_w, 0.12, 0.02), Vector3(0, 0.86, apron_z - 0.01), _body)
	ArcadeParts.box(_owner, cab, "ApronTrim", Vector3(_in_w, 0.012, 0.022), Vector3(0, 0.806, apron_z - 0.008), _trim)
	if apron_z > 0.47 + 0.001:
		solid_boxes.append(AABB(Vector3(-_w * 0.5, 0.78, 0.47), Vector3(_w, 0.14, apron_z - 0.47)))
	if _sh.has("hood"):
		_build_hood(cab, _sh["hood"])
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


## How many steps the glass's wedge is cut into for the shape's collision (the glass is 0.22 m of run: 4 steps keep it within 3 cm of the slope).
const HOOD_GLASS_STEPS := 4


## The monitor's hood of a sit-down cabinet (the shape's `hood`): a shelf over the bay door's swing from the lower body's front (`z0`) to the glass's
## bottom edge (`z1`), as thick as the lip (`y0` to `y1`), closed underneath and along its front, which the silhouette's side panels leave open. It is
## solid, with the wedge of glass above it (steps along the glass's slope, each as far forward as the glass is at its middle) over the coin face's depth:
## nothing held or pushed passes through the housing. It is NOT a pointer box: over the coin doors it would stand between a laser and their slots.
func _build_hood(cab: Node3D, hood: Dictionary) -> void:
	var z0 := float(hood["z0"])
	var z1 := float(hood["z1"])
	var y0 := float(hood["y0"])
	var y1 := float(hood["y1"])
	ArcadeParts.box(_owner, cab, "HoodUnder", Vector3(_in_w, 0.012, z1 - z0), Vector3(0, y0 + 0.006, (z0 + z1) * 0.5), _dark)
	ArcadeParts.box(_owner, cab, "HoodFront", Vector3(_in_w, y1 - y0, 0.02), Vector3(0, (y0 + y1) * 0.5, z1 - 0.01), _body)
	ArcadeParts.box(_owner, cab, "HoodTrim", Vector3(_in_w, 0.012, 0.022), Vector3(0, y0 + 0.006, z1 - 0.011), _trim)
	solid_boxes.append(AABB(Vector3(-_w * 0.5, y0, 0.40), Vector3(_w, y1 - y0, z1 - 0.40)))
	var ga: Vector2 = _sh["glass_a"]
	var gb: Vector2 = _sh["glass_b"]
	for k in HOOD_GLASS_STEPS:
		var t0 := float(k) / float(HOOD_GLASS_STEPS)
		var t1 := float(k + 1) / float(HOOD_GLASS_STEPS)
		var front := lerpf(ga.x, gb.x, (t0 + t1) * 0.5)
		var ya := lerpf(ga.y, gb.y, t0)
		var yb := lerpf(ga.y, gb.y, t1)
		solid_boxes.append(AABB(Vector3(-_w * 0.5, ya, 0.40), Vector3(_w, yb - ya, front - 0.40)))


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
	var mod := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Screen", Vector3(0, mid.y, mid.x))) as Node3D
	mod.set_script(load(SCRIPTS["screen"]))
	mod.basis = basis
	if _v.has("screen"):
		# The picture is fitted to the TUBE's shape, which a vertical game turns on its side.
		mod.set("glass_size", _tube)
		# A scope game: the monitor shows its screen cut out of the frame and the rifle's scope the other (ArcadeScreenModule).
		var scope: Dictionary = (_v["screen"] as Dictionary).get("scope", {})
		if scope.has("zoom"):
			mod.set("scope_zoom", float(scope["zoom"]))
		elif not scope.is_empty():
			mod.set("main_part", _part_of(scope["main"]))
			mod.set("scope_part", _part_of(scope["lens"]))
			mod.set("scope_frame_aspect", float(scope["aspect"]))
	var length := along.length()
	# How far behind the glass the picture stands: the tube's own depth, and a hologram cabinet's deep stage on top.
	var back := TUBE_DEPTH + float((_v.get("holo", {}) as Dictionary).get("depth", 0.0))
	# The tube's enclosure: a dark board behind the picture, as wide as the cabinet.
	ArcadeParts.box(_owner, mod, "Bezel", Vector3(_in_w, length, 0.012), Vector3(0, 0, -back - 0.006), _dark)
	var screen := ArcadeParts.quad(_owner, mod, "CabinetScreen", _tube, Vector3(0, 0.005, -back + 0.0005),
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
	# The window is cut to the tube, 3 cm round it, and the rest of the front is the cabinet's own board: a tall
	# narrow picture (a monitor on its side) is seen in a tall narrow opening, a small tube in a small one, and
	# the cabinet reads as built for the game rather than as a landscape recess a picture floats in.
	glass_h = minf(glass_h, _tube.y + 0.06)
	var mask := _body
	var glass := ArcadeParts.quad(_owner, mod, "Glass", Vector2(glass_w, glass_h), Vector3(0, 0, -0.004), glass_mat)
	glass.name = "Glass"
	var bar_t := 0.012
	var fz := -bar_t * 0.5
	var side_w := (_in_w - glass_w) * 0.5
	var top_h := (length - glass_h) * 0.5
	for sx in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "FrameSide%s" % ("L" if sx < 0 else "R"), Vector3(side_w, length, bar_t),
			Vector3(sx * (glass_w * 0.5 + side_w * 0.5), 0, fz), mask)
	for sy in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "Frame%s" % ("Top" if sy > 0 else "Bottom"), Vector3(glass_w, top_h, bar_t),
			Vector3(0, sy * (glass_h * 0.5 + top_h * 0.5), fz), mask)
	if back > TUBE_DEPTH:
		_build_holo_stage(mod, glass_w, glass_h, back)


## A hologram window (Time Traveler): the picture stands `back` behind the glass at the far end of a black tunnel cut to
## the window, with a low plinth in front of it for the props the hologram stood among. The picture then floats in a
## dark stage, and a head that moves sees it move against the frame, which a flat glass never shows. (The real cabinet
## threw its CRT's picture up onto a curved mirror; here the picture is drawn where the image appeared.)
func _build_holo_stage(mod: Node3D, glass_w: float, glass_h: float, back: float) -> void:
	var depth := back - 0.012
	for sx in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "HoloSide%s" % ("L" if sx < 0 else "R"), Vector3(0.012, glass_h, depth),
			Vector3(sx * (glass_w * 0.5 - 0.006), 0, -0.012 - depth * 0.5), _dark)
	for sy in [-1.0, 1.0]:
		ArcadeParts.box(_owner, mod, "Holo%s" % ("Roof" if sy > 0 else "Floor"), Vector3(glass_w, 0.012, depth),
			Vector3(0, sy * (glass_h * 0.5 - 0.006), -0.012 - depth * 0.5), _dark)
	ArcadeParts.box(_owner, mod, "HoloPlinth", Vector3(glass_w * 0.5, 0.03, depth * 0.40),
		Vector3(0, -glass_h * 0.5 + 0.027, -0.012 - depth * 0.68), ArcadeParts.mat(Color(0.12, 0.12, 0.14), 0.3, 0.4))


# ── control deck ────────────────────────────────────────────────────────────

func _build_deck() -> void:
	# The deck runs from the apron's top edge (z 0.47, y 0.92) up to the monitor
	# (z 0.30, y 1.00). Its local +Y is up-and-back along the slope, +Z its normal.
	var a: Vector2 = _sh.get("deck_a", Vector2(0.47, 0.92))
	var b: Vector2 = _sh.get("deck_b", Vector2(0.30, 1.00))
	var mid := (a + b) * 0.5
	var along := b - a
	var theta := atan2(along.x, along.y)
	var deck := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Deck", Vector3(0, mid.y, mid.x))) as Node3D
	deck.basis = Basis(Vector3.RIGHT, theta)
	var players: Array = _v["players"]
	# The body is as wide as its panels need (ArcadeCabinetSpecs.body_width), so the plate runs side to side.
	var depth := along.length()
	ArcadeParts.box(_owner, deck, "DeckPlate", Vector3(_in_w, depth, 0.012), Vector3(0, 0, -0.006), _dark)
	# Two levers in ONE slot: the rail runs across the deck under both (Panic Park).
	if not players.is_empty() and str((players[0] as Dictionary).get("kind", "")) == "slot":
		var rail_w := ArcadeCabinetSpecs.SLOT_TRAVEL * 4.0 + 0.10
		ArcadeParts.box(_owner, deck, "SlotRail", Vector3(rail_w, 0.03, 0.004),
			Vector3(0, SLOT_LEVER_Y, 0.002), ArcadeParts.mat(Color(0.01, 0.01, 0.012), 0.0, 0.9))

	for i in players.size():
		_build_player(deck, i, players[i])


## One player's panel, from its spec (see ArcadeCabinetSpecs): a stick with N buttons, two sticks, a
## trackball, buttons alone, a paddle dial, a rotary joystick (a stick whose shaft turns), a stand-up racer's wheel, a dancer's START with the stage's arrows
## on the floor, or START alone, and always START. The parts keep the names the control module finds them by
## (ArcadeControlModule): StickPivot, StickPivot2, BallPivot, DialPivot, WheelPivot, ShifterPivot, GasPivot,
## BrakePivot, Btn1..10, Pad<Dir>, Start.
func _build_player(deck: Node3D, index: int, spec: Dictionary) -> void:
	var mod := ArcadeParts.node(_owner, deck, "Node3D", "Player%d" % (index + 1)) as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", int(spec.get("player", index)))
	var kind: String = spec["kind"]
	var start_x: float = spec["start_x"]
	var extent := ArcadeCabinetSpecs.panel_extent(spec)
	var top := 0.0825
	var bottom := -0.1025
	# The panel in the cabinet's frame, for what stands on the floor in front (a racer's pedals, a dancer's
	# arrows): placed in the cabinet's frame and carried into the panel's, as the panel is one controller.
	var to_panel := Transform3D(deck.basis, deck.position).affine_inverse()
	if kind == "stick" or kind == "twin" or kind == "rotary":
		_stick(mod, "StickPivot", spec["stick_x"], index, kind == "rotary")
		if kind == "twin":
			_stick(mod, "StickPivot2", spec["stick2_x"], index)
	elif kind == "ball":
		# A trackball: a ball half sunk in a ring, spinning with the input (Centipede, Golden Tee).
		var ball_x: float = spec["ball_x"]
		ArcadeParts.cylinder(_owner, mod, "BallRing", 0.046, 0.008, Vector3(ball_x, 0.012, 0.004), _metal, Vector3.BACK)
		var bpivot := ArcadeParts.node(_owner, mod, "Node3D", "BallPivot", Vector3(ball_x, 0.012, -0.004)) as Node3D
		var ball := ArcadeParts.node(_owner, bpivot, "MeshInstance3D", "Ball", Vector3.ZERO) as MeshInstance3D
		var bm := SphereMesh.new()
		bm.radius = 0.038
		bm.height = 0.076
		bm.radial_segments = 24
		bm.rings = 12
		ball.mesh = bm
		ball.material_override = ArcadeParts.mat(_player_color(index).lerp(Color.WHITE, 0.25), 0.0, 0.25)
		# A seam on the ball, so its spin shows.
		ArcadeParts.box(_owner, bpivot, "BallSeam", Vector3(0.078, 0.004, 0.004), Vector3.ZERO,
			ArcadeParts.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4))
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
	elif kind == "wheel":
		# A stand-up racer: the wheel stands out of the panel toward the player, a gear lever beside it, and
		# the two pedals at the cabinet's foot, clear of the bay door's swing (Final Lap, Pole Position).
		var wheel_x: float = spec["wheel_x"]
		var wb := deck.basis.inverse() * Basis(Vector3.RIGHT, deg_to_rad(60.0))
		_wheel(mod, Vector3(wheel_x, -0.01, 0.10), wb, 0.13)
		top = 0.15
		bottom = -0.13
		if bool(spec.get("shifter", false)):
			_shifter(mod, Vector3(wheel_x + 0.21, 0.0, 0.0), Basis.IDENTITY)
		if bool(spec.get("pedals", true)):
			_pedals(mod, to_panel, Vector3(wheel_x, 0.0, 0.96))
	elif kind == "slot":
		# A lever in the slot (Panic Park): a carriage on the rail with an upright lever and a ball, red for player 1
		# and blue for player 2, each in its own half and meeting the other's in the middle.
		top = 0.115
		bottom = -0.135
		var carriage := ArcadeParts.node(_owner, mod, "Node3D", "SlidePivot", Vector3(float(spec["slot_x"]), SLOT_LEVER_Y, 0.0)) as Node3D
		ArcadeParts.box(_owner, carriage, "CarriageBlock", Vector3(0.09, 0.06, 0.016), Vector3(0, 0, 0.008), _metal)
		ArcadeParts.cylinder(_owner, carriage, "LeverShaft", 0.012, 0.07, Vector3(0, 0, 0.051), _metal, Vector3.BACK)
		# The handle is a big flat dome, a button's size and more (9 cm across), red or blue: what a player slides along the slot.
		var lever_ball := ArcadeParts.node(_owner, carriage, "MeshInstance3D", "LeverBall", Vector3(0, 0, SLOT_HANDLE_Z)) as MeshInstance3D
		var lm := SphereMesh.new()
		lm.radius = 0.045
		lm.height = 0.056
		lm.radial_segments = 28
		lm.rings = 14
		lever_ball.mesh = lm
		lever_ball.material_override = ArcadeParts.mat(_player_color(index), 0.0, 0.25)
	elif kind == "pad":
		# A dancer: START on the deck, and the stage's arrows (Pump It Up's five panels) on the floor in front.
		_arrows(mod, to_panel, Vector3(float(spec.get("stage_x", 0.0)), 0.0, STAGE_Z), int(spec.get("arrows", 4)), index)
	elif kind == "music":
		# A rhythm game's own controller: a turntable and keys, domes, a guitar, pads, a drum (ArcadeInstruments).
		_build_instrument(mod, spec, index, to_panel)
		top = float(spec["y1"]) + 0.01
		bottom = float(spec["y0"]) - 0.01
	for k in (spec.get("buttons", []) as Array).size():
		var bt: Dictionary = spec["buttons"][k]
		var pos: Vector2 = bt["pos"]
		_cap(mod, "Btn%d" % (k + 1), Vector3(pos.x, pos.y, 0.0), bt["radius"], BUTTON_COLORS[int(bt["color"])], 0.012)
	if kind == "slot":
		# Panic Park's START is a big round button in its player's colour, ABOVE the lever that player slides (toward the screen), out of its way.
		_cap(mod, "Start", Vector3(start_x, SLOT_START_Y, 0.0), 0.028, _player_color(index), 0.014)
	else:
		_cap(mod, "Start", Vector3(start_x, float(spec.get("start_y", -0.07)), 0.0), 0.011, Color(0.92, 0.92, 0.92), 0.008)
	var label := str(spec.get("label", ""))
	if not label.is_empty():
		# An alternating game's two STARTs say which is which (1P, 2P), on the deck under each.
		var tag := ArcadeParts.node(_owner, mod, "Label3D", "StartLabel", Vector3(start_x, -0.092, 0.001)) as Label3D
		tag.text = label
		tag.pixel_size = 0.0005
		tag.font_size = 32
		tag.modulate = Color(0.92, 0.92, 0.92)
		tag.outline_size = 0
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
	elif kind == "pad":
		# Taken hold of at its START, as a pad you do not carry: the arrows are for the feet.
		grip.set("panel_size", Vector2(0.12, 0.10))
		grip.position = Vector3(start_x, -0.06, 0.03)
		gshape.size = Vector3(0.12, 0.10, 0.08)
	else:
		var width := extent.y - extent.x
		var height := top - bottom
		grip.set("panel_size", Vector2(width, height))
		grip.position = Vector3((extent.x + extent.y) * 0.5, (top + bottom) * 0.5, 0.03)
		gshape.size = Vector3(width, height, 0.08 if kind != "wheel" else 0.22)


## A rhythm game's controller on a player's panel, from its layout (ArcadeInstruments): `Btn<n>` are MAME's buttons (a key, a dome, a drum pad, a sector of a drum: what a finger presses and
## the input sinks), `DialPivot` a turntable or a knob, and what has no button (a guitar's body, a drum's shell) is only drawn. Every flat part is built with its local Y along the panel's normal,
## as a cap is, so a finger's zone and the press are the same for all of them.
func _build_instrument(mod: Node3D, spec: Dictionary, index: int, to_panel: Transform3D) -> void:
	if spec.has("dial"):
		var d: Dictionary = spec["dial"]
		if str(d["kind"]) == "turntable":
			_turntable(mod, d["pos"], float(d["radius"]), float(d["plinth"]))
		else:
			_knob(mod, d["pos"], float(d["radius"]), float(d["plinth"]), float(d.get("z", 0.0)))
	for part: Dictionary in spec["parts"]:
		_instrument_part(mod, part, index)
	if spec.has("pedal"):
		_bass_pedal(mod, to_panel, spec["pedal"])


## One part of an instrument: a box (a key, a neck), a disc or a dome (a pad, a button; a dome has a rim of its own colour, as a pad has a hoop) or a sector (a drum's face or rim).
func _instrument_part(mod: Node3D, part: Dictionary, index: int) -> void:
	var pos: Vector2 = part["pos"]
	var h := float(part["h"])
	var base_z := float(part.get("z", 0.0))
	var color: Color = _player_color(index).lerp(Color(0.25, 0.05, 0.05), 0.35) if bool(part.get("player_color", false)) else part["color"]
	var node_name := str(part["name"])
	var button := int(part.get("btn", 0))
	if button > 0:
		node_name = "Btn%d" % button
	var m := ArcadeParts.mat(color, 0.0, 0.35)
	match str(part["shape"]):
		"box":
			var size: Vector2 = part["size"]
			var key := ArcadeParts.box(_owner, mod, node_name, Vector3(size.x, h, size.y), Vector3(pos.x, pos.y, base_z + h * 0.5), m)
			key.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
		"dome":
			if button > 0:
				_cap(mod, node_name, Vector3(pos.x, pos.y, base_z), float(part["radius"]), color, h)
			else:
				ArcadeParts.cylinder(_owner, mod, node_name, float(part["radius"]), h, Vector3(pos.x, pos.y, base_z + h * 0.5), m, Vector3.BACK)
		"disc":
			ArcadeParts.cylinder(_owner, mod, node_name, float(part["radius"]), h, Vector3(pos.x, pos.y, base_z + h * 0.5), m, Vector3.BACK)
		"sector":
			var node := ArcadeParts.node(_owner, mod, "MeshInstance3D", node_name, Vector3(pos.x, pos.y, base_z + h * 0.5)) as MeshInstance3D
			var mesh := ArcadeInstruments.sector_mesh(float(part["r0"]), float(part["r1"]), float(part["a0"]), float(part["a1"]), h)
			mesh.surface_set_material(0, m)
			node.mesh = mesh
			node.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
			node.set_meta(&"sector", {"r0": float(part["r0"]), "r1": float(part["r1"]), "a0": deg_to_rad(float(part["a0"])), "a1": deg_to_rad(float(part["a1"]))})


## A DJ's turntable: a metal plinth and a platter of black vinyl that turns about its spindle (`DialPivot`, with LEFT and RIGHT or a hand: a hand takes it anywhere on the platter).
func _turntable(mod: Node3D, pos: Vector2, radius: float, plinth: float) -> void:
	ArcadeParts.cylinder(_owner, mod, "TurntableBase", plinth, 0.012, Vector3(pos.x, pos.y, 0.006), _metal, Vector3.BACK)
	var pivot := ArcadeParts.node(_owner, mod, "Node3D", "DialPivot", Vector3(pos.x, pos.y, 0.012)) as Node3D
	pivot.set_meta(&"reach", radius)
	ArcadeParts.cylinder(_owner, pivot, "DialKnob", radius, 0.008, Vector3(0, 0, 0.004), ArcadeParts.mat(Color(0.04, 0.04, 0.05), 0.2, 0.25), Vector3.BACK)
	ArcadeParts.cylinder(_owner, pivot, "PlatterLabel", radius * 0.34, 0.0006, Vector3(0, 0, 0.0083), ArcadeParts.mat(Color(0.80, 0.12, 0.12), 0.0, 0.5), Vector3.BACK)
	for k in 2:
		# A groove's ring, lighter than the vinyl, so the turn shows even where the mark is not.
		ArcadeParts.cylinder(_owner, pivot, "PlatterGroove%d" % (k + 1), radius * (0.62 + 0.18 * float(k)), 0.0004, Vector3(0, 0, 0.0082 - 0.0001 * float(k)),
			ArcadeParts.mat(Color(0.10, 0.10, 0.12), 0.3, 0.2), Vector3.BACK)
	ArcadeParts.box(_owner, pivot, "DialMark", Vector3(0.006, radius * 0.5, 0.0008), Vector3(0, radius * 0.62, 0.0090), ArcadeParts.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4))
	ArcadeParts.cylinder(_owner, pivot, "Spindle", 0.004, 0.010, Vector3(0, 0, 0.012), _metal, Vector3.BACK)


## A knob (a guitar's effect knob): a ring and a knob that turns (`DialPivot`).
func _knob(mod: Node3D, pos: Vector2, radius: float, plinth: float, base_z: float = 0.0) -> void:
	ArcadeParts.cylinder(_owner, mod, "DialBase", plinth, 0.006, Vector3(pos.x, pos.y, base_z + 0.003), _metal, Vector3.BACK)
	var pivot := ArcadeParts.node(_owner, mod, "Node3D", "DialPivot", Vector3(pos.x, pos.y, base_z + 0.006)) as Node3D
	ArcadeParts.cylinder(_owner, pivot, "DialKnob", radius, 0.020, Vector3(0, 0, 0.010), ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.4), Vector3.BACK)
	ArcadeParts.box(_owner, pivot, "DialMark", Vector3(0.003, radius * 0.8, 0.002), Vector3(0, radius * 0.5, 0.0205), ArcadeParts.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4))


## A bass drum's pedal on the floor in front of the cabinet, `pedal.x` along the deck and `pedal.btn` the button it presses: a flat pad on a plate that goes DOWN under a foot (or a hand
## that reaches it), not into the deck's slope.
func _bass_pedal(mod: Node3D, to_panel: Transform3D, pedal: Dictionary) -> void:
	var x := float(pedal["x"])
	var z := BASS_PEDAL_Z
	var plate := ArcadeParts.box(_owner, mod, "BassPedalPlate", Vector3(0.20, 0.016, 0.30), Vector3.ZERO, _dark)
	plate.transform = to_panel * Transform3D(Basis.IDENTITY, Vector3(x, 0.008, z))
	var tread := ArcadeParts.box(_owner, mod, "Btn%d" % int(pedal["btn"]), Vector3(0.15, 0.020, 0.24), Vector3.ZERO, ArcadeParts.mat(pedal["color"], 0.0, 0.7))
	tread.transform = to_panel * Transform3D(Basis.IDENTITY, Vector3(x, 0.026, z))
	tread.set_meta(&"press_offset", to_panel.basis * Vector3(0.0, -0.012, 0.0))
	form_boxes.append(AABB(Vector3(x - 0.10, 0.0, z - 0.15), Vector3(0.20, 0.05, 0.30)))


## A joystick: a base plate, then a pivot carrying shaft and ball (player 1 red, 2 blue, then green, yellow...). A ROTARY one (`twist`: Ikari Warriors, Top Gunner's bootleg)
## has a collar on the shaft as well, the part that turns (`DialPivot`, as any dial does, with LEFT and RIGHT or with a hand) with a white mark on its top so the turn shows;
## it leans with the stick.
func _stick(mod: Node3D, pivot_name: String, x: float, index: int, twist: bool = false) -> void:
	var suffix := pivot_name.trim_prefix("StickPivot")
	ArcadeParts.cylinder(_owner, mod, "StickBase" + suffix, 0.034, 0.004, Vector3(x, 0.015, 0.002), _metal, Vector3.BACK)
	var pivot := ArcadeParts.node(_owner, mod, "Node3D", pivot_name, Vector3(x, 0.015, 0.004)) as Node3D
	ArcadeParts.cylinder(_owner, pivot, "StickShaft", 0.006, 0.07, Vector3(0, 0, 0.035), _metal, Vector3.BACK)
	var ball := ArcadeParts.node(_owner, pivot, "MeshInstance3D", "StickBall", Vector3(0, 0, 0.085)) as MeshInstance3D
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	# 24 x 12 (Godot's default 64 x 32 is 4224 triangles for a ball of 4.4 cm).
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	ball.material_override = ArcadeParts.mat(_player_color(index), 0.0, 0.3)
	if twist:
		var collar := ArcadeParts.node(_owner, pivot, "Node3D", "DialPivot", Vector3(0, 0, 0.026)) as Node3D
		ArcadeParts.cylinder(_owner, collar, "DialKnob", 0.016, 0.020, Vector3.ZERO, ArcadeParts.mat(Color(0.80, 0.80, 0.82), 0.6, 0.3), Vector3.BACK)
		ArcadeParts.box(_owner, collar, "DialMark", Vector3(0.004, 0.010, 0.002), Vector3(0, 0.0105, 0.0105), ArcadeParts.mat(Color(0.85, 0.10, 0.10), 0.0, 0.4))


## The stick-ball colour of each player's panel: red, blue (the two the generic cabinet always had), green,
## yellow, purple, orange.
static func _player_color(index: int) -> Color:
	const COLORS := [Color(0.85, 0.10, 0.10), Color(0.10, 0.25, 0.85), Color(0.12, 0.62, 0.20),
		Color(0.90, 0.75, 0.08), Color(0.55, 0.18, 0.70), Color(0.95, 0.45, 0.08)]
	return COLORS[index % COLORS.size()]


## A steering wheel on a column: `WheelPivot` turns about the wheel's axis (its local Y) with the steering.
## `pos` and `basis` are in `parent`'s frame, the wheel's plane its local XZ, `radius` the rim's.
func _wheel(parent: Node3D, pos: Vector3, basis: Basis, radius: float) -> void:
	var mount := ArcadeParts.node(_owner, parent, "Node3D", "WheelMount", pos) as Node3D
	mount.basis = basis
	# The column, from behind the hub back into whatever the wheel stands on.
	ArcadeParts.cylinder(_owner, mount, "WheelColumn", 0.022, 0.16, Vector3(0, -0.08, 0), _dark, Vector3.UP)
	var pivot := ArcadeParts.node(_owner, mount, "Node3D", "WheelPivot", Vector3.ZERO) as Node3D
	var rim := ArcadeParts.node(_owner, pivot, "MeshInstance3D", "WheelRim", Vector3.ZERO) as MeshInstance3D
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.014
	tm.outer_radius = radius + 0.014
	tm.rings = 32
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.6)
	ArcadeParts.cylinder(_owner, pivot, "WheelHub", 0.040, 0.03, Vector3.ZERO, _metal, Vector3.UP)
	# Three spokes, the bottom one straight down, and a mark at the top so a turn shows.
	for i in 3:
		var a := deg_to_rad(90.0 + 120.0 * float(i))
		var dir := Vector3(cos(a), 0.0, sin(a))
		var spoke := ArcadeParts.box(_owner, pivot, "WheelSpoke%d" % (i + 1), Vector3(0.022, 0.012, radius - 0.03),
			dir * (radius * 0.5), _metal)
		spoke.basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	ArcadeParts.box(_owner, pivot, "WheelMark", Vector3(0.03, 0.006, 0.03), Vector3(0, 0.012, -radius),
		ArcadeParts.mat(Color(0.95, 0.75, 0.10), 0.0, 0.4))


## A gear lever: a gaiter, a stick and a knob, `ShifterPivot` leaning with the gear.
func _shifter(parent: Node3D, pos: Vector3, basis: Basis) -> void:
	ArcadeParts.cylinder(_owner, parent, "ShifterBoot", 0.03, 0.02, pos + basis * Vector3(0, 0, 0.01), _dark, basis * Vector3.BACK)
	var pivot := ArcadeParts.node(_owner, parent, "Node3D", "ShifterPivot", pos + basis * Vector3(0, 0, 0.02)) as Node3D
	pivot.basis = basis
	ArcadeParts.cylinder(_owner, pivot, "ShifterStick", 0.007, 0.12, Vector3(0, 0, 0.06), _metal, Vector3.BACK)
	var knob := ArcadeParts.node(_owner, pivot, "MeshInstance3D", "ShifterKnob", Vector3(0, 0, 0.125)) as MeshInstance3D
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	sm.radial_segments = 16
	sm.rings = 8
	knob.mesh = sm
	knob.material_override = ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.35)


## A driver's two pedals: organ pedals hinged on an axle across a pressed-steel footplate with a rubber heel
## mat, BRAKE on the left (the wider pad) and GAS on the right, each a pivot (`BrakePivot`, `GasPivot`) at its
## heel that tips down when pressed. `at` is the footplate's centre on the floor in the CABINET's frame,
## `to_parent` carries that into `parent`'s frame.
func _pedals(parent: Node3D, to_parent: Transform3D, at: Vector3) -> void:
	var rubber := ArcadeParts.mat(Color(0.05, 0.05, 0.055), 0.0, 0.9)
	var plate := ArcadeParts.box(_owner, parent, "Footplate", Vector3(0.34, 0.03, 0.32), Vector3.ZERO, _dark)
	plate.transform = to_parent * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.015, 0))
	var heel := ArcadeParts.box(_owner, parent, "FootMat", Vector3(0.30, 0.004, 0.09), Vector3.ZERO, rubber)
	heel.transform = to_parent * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.032, 0.115))
	# The axle both pedals hinge on, held by a post at each end.
	var axle := ArcadeParts.cylinder(_owner, parent, "PedalAxle", 0.008, 0.30, Vector3.ZERO, _metal, Vector3.RIGHT)
	axle.transform = to_parent * Transform3D(axle.basis, at + Vector3(0, 0.052, 0.07))
	for k in [-1.0, 1.0]:
		var post := ArcadeParts.box(_owner, parent, "PedalPost%s" % ("L" if k < 0 else "R"), Vector3(0.02, 0.04, 0.03),
			Vector3.ZERO, _metal)
		post.transform = to_parent * Transform3D(Basis.IDENTITY, at + Vector3(k * 0.15, 0.04, 0.07))
	for p in [["Brake", -0.075, 0.100], ["Gas", 0.075, 0.075]]:
		var pivot := ArcadeParts.node(_owner, parent, "Node3D", "%sPivot" % str(p[0])) as Node3D
		# On the axle, the pad rising toward the screen 32 degrees, as a car's does.
		pivot.transform = to_parent * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(32.0)),
			at + Vector3(float(p[1]), 0.052, 0.07))
		_pedal_tread(pivot, str(p[0]), float(p[2]), 0.21)
	form_boxes.append(AABB(at + Vector3(-0.17, 0.0, -0.16), Vector3(0.34, 0.17, 0.32)))


## A pedal's tread, reaching along -Z from the hinge at `parent`'s origin (the heel) for `length`: a steel
## under-plate, a ribbed black rubber face and a lip at the toe that keeps a shoe from sliding off. Part of
## `parent`, so it tips with it. Named `<prefix>Deck`, `Pad`, `Rib<n>`, `ToeLip`.
func _pedal_tread(parent: Node3D, prefix: String, width: float, length: float) -> void:
	var rubber := ArcadeParts.mat(Color(0.05, 0.05, 0.055), 0.0, 0.9)
	ArcadeParts.box(_owner, parent, prefix + "Deck", Vector3(width, 0.012, length), Vector3(0, 0.0, -length * 0.5), _metal)
	ArcadeParts.box(_owner, parent, prefix + "Pad", Vector3(width - 0.012, 0.006, length - 0.02),
		Vector3(0, 0.009, -length * 0.5), rubber)
	for i in int((length - 0.03) / 0.035):
		ArcadeParts.box(_owner, parent, "%sRib%d" % [prefix, i + 1], Vector3(width - 0.012, 0.004, 0.009),
			Vector3(0, 0.0125, -0.025 - 0.035 * float(i)), rubber)
	ArcadeParts.box(_owner, parent, prefix + "ToeLip", Vector3(width, 0.024, 0.010), Vector3(0, 0.009, -length + 0.005), _metal)


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
		var door := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "CoinDoor%d" % (i + 1), Vector3(x, 0.64, 0.40))) as Node3D
		door.set_script(load(SCRIPTS["coin"]))
		door.set("player", i)
		ArcadeParts.box(_owner, door, "Plate", Vector3(0.10, 0.20, 0.006), Vector3(0, 0, 0.003), _metal)
		ArcadeParts.box(_owner, door, "ReturnCup", Vector3(0.05, 0.03, 0.008), Vector3(0, -0.055, 0.004), _dark)
		# The coin return: a cap you press, which gives back a coin the game has not counted
		# (ArcadeCoinModule.return_pressed). The cap is the button's own mesh, so it sinks when pressed.
		var ret := ArcadeParts.node(_owner, door, "Area3D", "CoinReturn", Vector3(0, -0.08, 0.006)) as Area3D
		ret.set_script(load(SCRIPTS["button"]))
		ret.collision_layer = 0
		ret.collision_mask = 0
		ret.set("trigger_radius", 0.015)
		ret.set("depress_depth", 0.003)
		ret.set("depress_axis", Vector3(0, 0, -1))
		var rcol := ArcadeParts.node(_owner, ret, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
		var rshape := BoxShape3D.new()
		rshape.size = Vector3(0.034, 0.030, 0.03)
		rcol.shape = rshape
		rcol.position = Vector3(0, 0, 0.008)
		ArcadeParts.cylinder(_owner, ret, "ButtonMesh", 0.012, 0.006, Vector3.ZERO, _trim, Vector3.BACK)
		# Its legend to the right of the cap, inside the plate (the cup is above it, the plate's edge below).
		var rtag := ArcadeParts.node(_owner, door, "Label3D", "ReturnLabel", Vector3(0.016, -0.08, 0.0065)) as Label3D
		rtag.text = "RETURN"
		rtag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rtag.pixel_size = 0.0004
		rtag.font_size = 24
		rtag.modulate = Color(0.1, 0.1, 0.12)
		rtag.outline_size = 0
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
	var sockets := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Sockets", Vector3.ZERO)) as Node3D
	sockets.set_script(load(SCRIPTS["sockets"]))
	# Rolled 180 degrees about Z with +Z out of the face, as the NES authors its
	# seats, so a plug seats connector-in and upright. Two at the apron's ends; a cabinet for three or four
	# players has a socket for each, spread between them.
	var count := clampi(int(_v.get("socket_count", 2)), 2, 4)
	var xs := _socket_xs(count)
	for i in count:
		var x: float = xs[i]
		var seat := ArcadeParts.node(_owner, sockets, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(x, 0.86, 0.47)) as Marker3D
		seat.basis = Basis(Vector3.BACK, PI)
		ArcadeParts.box(_owner, sockets, "Recess%d" % (i + 1), Vector3(0.034, 0.026, 0.004),
			Vector3(x, 0.86, 0.4685), _dark)


## Where `count` pad sockets go along the apron: two at its ends; more, one under each player's panel when
## there is a panel for each, else spread over the body.
func _socket_xs(count: int) -> Array:
	var centres := ArcadeCabinetSpecs.panel_centres(_v["players"])
	if count > 2 and centres.size() == count:
		return centres
	var half := 0.24 + maxf(_in_w - 0.62, 0.0) * 0.4
	var out: Array = []
	for i in count:
		out.append(-half + 2.0 * half * float(i) / float(count - 1))
	return out


# ── guns ────────────────────────────────────────────────────────────────────

## The guns on the front, each on a cord that goes into the cabinet: hung muzzle-down in a holster on the
## apron (`holster`, Time Crisis and House of the Dead), resting on a swivel post on the deck (`mounted`,
## Operation Wolf's Uzi, Terminator 2), or one rifle on a post in the middle with its scope (`rifle`, Silent
## Scope). The Sockets module carries the cord entries (the system's controller-port zones) and the Holster
## markers where the guns rest; the model builds the guns and hangs them there
## (RetroSystemModelArcadeCabinet.captive_controllers).
func _build_gun_holsters() -> void:
	var sockets := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Sockets", Vector3.ZERO)) as Node3D
	sockets.set_script(load(SCRIPTS["sockets"]))
	var style := str(_v.get("gun_style", "holster"))
	if style == "rifle":
		sockets.set("gun_scene", RIFLE_SCENE)
	var xs := ArcadeCabinetSpecs.gun_xs(int(_v["guns"]), _w, style)
	for i in xs.size():
		var sx := float(xs[i])
		if style == "dash":
			_dash_holster(sockets, i, sx)
			continue
		# The cord goes in on the front beside the gun, outboard of it; a gun in the middle's to its right, clear
		# of a coin door standing under it.
		var side := signf(sx) if absf(sx) > 0.01 else 1.0
		var entry_x := sx + side * 0.042
		for cx: float in _v.get("coins", []):
			if absf(sx) <= 0.01 and absf(cx - entry_x) < 0.075:
				entry_x = sx + 0.10
		# Where the cord goes in, +Z out of the face, as the front sockets are authored.
		var seat := ArcadeParts.node(_owner, sockets, "Marker3D", "PortSeat%d" % (i + 1),
			Vector3(entry_x, CORD_ENTRY_Y, CORD_ENTRY_Z)) as Marker3D
		seat.basis = Basis(Vector3.BACK, PI)
		ArcadeParts.cylinder(_owner, sockets, "Grommet%d" % (i + 1), 0.017, 0.008,
			Vector3(entry_x, CORD_ENTRY_Y, CORD_ENTRY_Z + 0.004), _dark, Vector3.BACK)
		if style == "holster":
			_holster(sockets, i, sx)
		else:
			_gun_mount(sockets, i, sx, style == "rifle")


## A holster on the apron: the gun hangs in it muzzle-down, its grip toward the player (rolled -90 degrees
## about X).
func _holster(sockets: Node3D, i: int, sx: float) -> void:
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


## A holster on the dash of a two-seat cockpit (Lucky & Wild): the apron's bracket (`_holster`) on the dash pedestal's face toward the seats, the gun hanging muzzle-down in
## its cup between the two players, and the cord going into the dash beside it, outboard of the gun. The pedestal stands at DASH_FACE_Z.
const DASH_FACE_Z := 1.08
const DASH_HOLSTER_Y := 0.55
const DASH_ENTRY_Y := 0.52


func _dash_holster(sockets: Node3D, i: int, sx: float) -> void:
	var side := signf(sx) if absf(sx) > 0.01 else 1.0
	var entry_x := sx + side * 0.07
	var seat := ArcadeParts.node(_owner, sockets, "Marker3D", "PortSeat%d" % (i + 1), Vector3(entry_x, DASH_ENTRY_Y, DASH_FACE_Z + 0.002)) as Marker3D
	seat.basis = Basis(Vector3.BACK, PI)
	ArcadeParts.cylinder(_owner, sockets, "Grommet%d" % (i + 1), 0.017, 0.008, Vector3(entry_x, DASH_ENTRY_Y, DASH_FACE_Z + 0.004), _dark, Vector3.BACK)
	var plate_z := DASH_FACE_Z + 0.008
	var holster := ArcadeParts.node(_owner, sockets, "Marker3D", "Holster%d" % (i + 1), Vector3(sx, DASH_HOLSTER_Y, plate_z + 0.067)) as Marker3D
	holster.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	ArcadeParts.box(_owner, sockets, "HolsterPlate%d" % (i + 1), Vector3(0.07, 0.30, 0.012), Vector3(sx, DASH_HOLSTER_Y - 0.02, plate_z),
		ArcadeParts.mat(Color(0.10, 0.10, 0.12), 0.0, 0.5))
	ArcadeParts.box(_owner, sockets, "HolsterBand%d" % (i + 1), Vector3(0.072, 0.012, 0.014), Vector3(sx, DASH_HOLSTER_Y - 0.135, plate_z), _trim)
	ArcadeParts.cylinder(_owner, sockets, "HolsterCup%d" % (i + 1), 0.030, 0.045, Vector3(sx, DASH_HOLSTER_Y - 0.1825, plate_z + 0.033), _dark, Vector3.UP)
	ArcadeParts.box(_owner, sockets, "HolsterStrap%d" % (i + 1), Vector3(0.05, 0.010, 0.040), Vector3(sx, DASH_HOLSTER_Y - 0.075, plate_z + 0.027), _metal)


## A post on the front of the deck with a swivel on top that the gun is FIXED to (Operation Wolf's Uzi, a rifle
## on a taller post: Silent Scope's), aimed at the screen at rest (its own -Z the cabinet's -Z). The gun does not
## leave it: a hand turns it about the swivel (`Pivot<n>`, the marker the gun is bolted to; LightGun.fix_to_mount) and
## nothing it does takes it off the cabinet. The swivel is a ball in a collar over the post's head, so the gun's body
## can turn on it without a cradle's cheeks in its way.
func _gun_mount(sockets: Node3D, i: int, sx: float, rifle: bool) -> void:
	var foot := Vector3(sx, 0.92, 0.47)
	var tall := 0.20 if rifle else 0.13
	var top := foot + Vector3(0, tall, 0)
	ArcadeParts.cylinder(_owner, sockets, "MountBase%d" % (i + 1), 0.05, 0.02, foot + Vector3(0, 0.01, 0), _metal, Vector3.UP)
	ArcadeParts.cylinder(_owner, sockets, "MountPost%d" % (i + 1), 0.018, tall, foot + Vector3(0, tall * 0.5, 0), _dark, Vector3.UP)
	# The collar on the post's head and the ball the gun swivels on, a hand's breadth of travel either way.
	ArcadeParts.cylinder(_owner, sockets, "MountCollar%d" % (i + 1), 0.032, 0.016, top - Vector3(0, 0.012, 0), _metal, Vector3.UP)
	var ball := ArcadeParts.node(_owner, sockets, "MeshInstance3D", "MountBall%d" % (i + 1), top + Vector3(0, 0.004, 0)) as MeshInstance3D
	var sphere := SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.056
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = _metal
	ball.mesh = sphere
	# The pivot: what the gun is bolted to, the ball's middle, under the gun's body: a rifle's 25 cm ahead of its
	# grip and a pistol-shaped gun's 8 cm (so a rifle's muzzle stops 3 cm short of the glass at rest).
	var pivot := ArcadeParts.node(_owner, sockets, "Marker3D", "Pivot%d" % (i + 1), top + Vector3(0, 0.004, 0.0)) as Marker3D
	pivot.basis = Basis.IDENTITY
	# A rifle's long stock is a lever (the barrel points from the hand through the pivot); a short gun is turned by
	# the way the hand points.
	pivot.set_meta("lever", rifle)
	# The gun's origin at rest, behind the pivot.
	var rest := ArcadeParts.node(_owner, sockets, "Marker3D", "Holster%d" % (i + 1),
		top + Vector3(0, 0.022, 0.25 if rifle else 0.08)) as Marker3D
	rest.basis = Basis.IDENTITY


# ── foot pedals ─────────────────────────────────────────────────────────────

## Where a gun pedal's middle stands in front of the cabinet: its tread's toe just inside the reach of the bay
## door lying open (0.40 m out from the coin face).
const PEDAL_Z := 0.90


## A Time Crisis-style foot pedal on the floor in front of the deck, with its cable running to the
## cabinet: one in the middle, or one under each gun of a game that has them (`gun_pedals`, player `index`).
## Wired: ArcadePedalModule presses its player's button 2, and tips `PedalPlate` down about `PedalHinge`,
## so those two keep their names.
func _build_pedal(index: int) -> void:
	# A pedal under each of two or three guns; one gun's in the middle, where its one player stands.
	var under: Array = _v.get("gun_pedals", [])
	var x := 0.0 if under.size() < 2 else float(under[index]) * 0.75
	var pedal := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Pedal%d" % (index + 1), Vector3(x, 0.0, PEDAL_Z))) as Node3D
	pedal.set_script(load(SCRIPTS["pedal"]))
	pedal.set("player", index)
	# A pressed-steel base bolted to the floor, a cheek each side of the hinge, the pin, and the tread hinged
	# at its heel (toward the player) with its toe, toward the screen, raised 22 degrees on its spring.
	var steel := ArcadeParts.mat(Color(0.20, 0.20, 0.22), 0.75, 0.45)
	ArcadeParts.box(_owner, pedal, "PedalBase", Vector3(0.20, 0.010, 0.34), Vector3(0, 0.005, 0.0), steel)
	for sx in [-1.0, 1.0]:
		ArcadeParts.box(_owner, pedal, "PedalCheek%s" % ("L" if sx < 0 else "R"), Vector3(0.012, 0.075, 0.11),
			Vector3(sx * 0.094, 0.0475, 0.12), steel)
		for sz in [-1.0, 1.0]:
			ArcadeParts.cylinder(_owner, pedal, "PedalBolt%s%s" % ["L" if sx < 0 else "R", "F" if sz < 0 else "B"],
				0.007, 0.004, Vector3(sx * 0.085, 0.012, sz * 0.15), _metal, Vector3.UP)
	ArcadeParts.cylinder(_owner, pedal, "PedalHinge", 0.009, 0.20, Vector3(0, 0.052, 0.12), _metal, Vector3.RIGHT)
	var plate := ArcadeParts.node(_owner, pedal, "Node3D", "PedalPlate", Vector3(0, 0.052, 0.12)) as Node3D
	plate.basis = Basis(Vector3.RIGHT, deg_to_rad(22.0))
	_pedal_tread(plate, "Pedal", 0.15, 0.25)
	# The lead: a strain-relief boot on the base's cabinet end, the cord on across the floor to the cabinet.
	ArcadeParts.cylinder(_owner, pedal, "PedalBoot", 0.012, 0.04, Vector3(0, 0.016, -0.18), _dark, Vector3.BACK)
	ArcadeParts.cylinder(_owner, pedal, "PedalCable", 0.005, 0.30, Vector3(0, 0.005, -0.35), _dark, Vector3.BACK)
	form_boxes.append(AABB(Vector3(x - 0.10, 0.0, PEDAL_Z - 0.17), Vector3(0.20, 0.10, 0.34)))


# ── a sit-down cockpit ──────────────────────────────────────────────────────

## How wide each seat of a two-seat cockpit is.
const RACEGUN_SEAT_W := 0.40

## Where the cockpit's platform starts (clear of the bay door, which opens 40 cm out, and under the monitor's hood) and ends: 32 cm behind the seat, which is
## as far back as the headrest.
const COCKPIT_Z0 := 0.84
const COCKPIT_Z1 := 1.90
## A flight cockpit's stick console between the knees and its throttle console by the left hand: where they stand front to back, how high the
## stick turns on its console, and where the grip is on the shaft (the grip's centre, from the pivot).
const STICK_Z := 1.18
const STICK_BASE_Y := 0.40
const FLIGHT_GRIP_Z := 0.27
const THROTTLE_Z := 1.30
## A driving cockpit's gear lever, by the driver's right hand: the seat's own distance (0.26 m ahead of it).
const SHIFTER_Z := 1.32
## Where a driving cockpit's pedals stand (the footplate's middle): the heel just short of the seat's base, the toes at the dash.
const PEDALS_Z := 1.22
## The cabin's walls: from the front pillar's foot (CABIN_Z0, on the platform beside the dash) back to CABIN_Z1, as tall as CABIN_H over the platform. Each
## is one panel whose front edge slants from the roof's front corner (CABIN_FRONT_Z) down to the sill (CABIN_SILL_Y) at the pillar: the shape of a canopy's
## side, and the line of the glass carried on up to the roof and down to the platform (the glass leans back 25 degrees, 0.46 m of run for every metre of
## rise, and so does this edge). The roof runs forward over the housing's marquee (ROOF_FRONT_Z), a hand's breadth above it, and the lock-on lamps hang
## under it just ahead of the marquee's face (CABIN_LAMP_Z), where a seated player's eyes see them above the picture.
const CABIN_Z0 := 0.86
const CABIN_Z1 := 1.82
const CABIN_H := 1.52
const CABIN_FRONT_Z := 0.50
const CABIN_SILL_Y := 0.84
const ROOF_FRONT_Z := 0.20
const CABIN_LAMP_Z := 0.76


## A sit-down cockpit in front of the monitor housing (Daytona USA, Sega Rally, Ridge Racer, After Burner II): a
## platform, a seat and a dash with START on it. A DRIVING cockpit has the wheel on the dash, the two pedals in the footwell under it and a
## gear lever by the right hand; on the Model 3 twins a roof over the seat. A FLIGHT cockpit (`flight`) has a stick between the knees and,
## where the game reads one (`throttle`), a throttle lever by the left hand, in a cabin (`cabin`: walls and a roof) where the game's was. A
## game whose cabinet moved (`motion`) has all of it on a `MotionPivot` that ArcadeControlModule tilts with the stick or the wheel. The driver's
## controls are ONE controller (Player1, taken hold of at the wheel or the stick), as a panel is. No collision: a player walks in and sits on
## their own chair.
func _build_cockpit(spec: Dictionary) -> void:
	var cp := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Cockpit", Vector3.ZERO)) as Node3D
	var flight := bool(spec.get("flight", false))
	var depth := COCKPIT_Z1 - COCKPIT_Z0
	var zc := (COCKPIT_Z0 + COCKPIT_Z1) * 0.5
	# A cockpit of two seats (Lucky & Wild): the driver's on the left, with the wheel and the pedal in front of it, the gunner's on the right.
	var seats := clampi(int(spec.get("seats", 1)), 1, 2)
	var seat_x := ArcadeCabinetSpecs.RACEGUN_SEAT_X if seats > 1 else 0.0
	var driver_x := -seat_x
	# What the driver sits in is on `base`: the cockpit itself, or the base that moves under it.
	var base := cp
	if bool(spec.get("motion", false)):
		base = ArcadeParts.node(_owner, cp, "Node3D", "MotionPivot", Vector3.ZERO) as Node3D
		base.set_meta(&"motion_centre", Vector3(0.0, PLATFORM_TOP, zc))
	ArcadeParts.box(_owner, base, "Platform", Vector3(_w, 0.10, depth), Vector3(0, 0.05, zc), _body)
	# A band round the platform's edge, under its top (a band flush with the top would fight it for the face).
	ArcadeParts.box(_owner, base, "PlatformTrim", Vector3(_w + 0.004, 0.012, depth + 0.004), Vector3(0, 0.084, zc), _trim)
	# The dash: a pedestal at the platform's front, its top leaning toward the driver.
	ArcadeParts.box(_owner, base, "Dash", Vector3(_w - 0.10, 0.60, 0.20), Vector3(0, 0.40, 0.98), _body)
	var dash_top := ArcadeParts.box(_owner, base, "DashTop", Vector3(_w - 0.08, 0.02, 0.26), Vector3(0, 0.71, 1.00), _dark)
	dash_top.basis = Basis(Vector3.RIGHT, deg_to_rad(18.0))
	if seats > 1:
		_build_driver_seat(base, driver_x, SEAT_Z, "DriverSeat", RACEGUN_SEAT_W, -(RACEGUN_SEAT_W * 0.5 + 0.25))
		_build_driver_seat(base, seat_x, SEAT_Z, "GunnerSeat", RACEGUN_SEAT_W, RACEGUN_SEAT_W * 0.5 + 0.25)
	else:
		_build_driver_seat(base)
	if not flight:
		# The gear lever's console, by the driver's right hand.
		ArcadeParts.box(_owner, base, "ShifterConsole", Vector3(0.12, 0.44, 0.30), Vector3(_w * 0.5 - 0.10, 0.32, SHIFTER_Z), _body)
	if bool(spec.get("roof", false)) and not flight:
		# Two posts behind the seat and a canopy forward over the driver to the monitor housing (the overhead
		# marquee of Sega's Model 3 twins).
		for k in [-1.0, 1.0]:
			ArcadeParts.box(_owner, base, "RoofPost%s" % ("L" if k < 0 else "R"), Vector3(0.05, 1.90, 0.05),
				Vector3(k * (_w * 0.5 - 0.03), 1.05, COCKPIT_Z1 - 0.05), _body)
		ArcadeParts.box(_owner, base, "Roof", Vector3(_w, 0.05, COCKPIT_Z1 + 0.10), Vector3(0, 2.025, (COCKPIT_Z1 - 0.10) * 0.5), _body)
		ArcadeParts.box(_owner, base, "RoofTrim", Vector3(_w + 0.004, 0.012, COCKPIT_Z1 + 0.104), Vector3(0, 1.995, (COCKPIT_Z1 - 0.10) * 0.5), _trim)
		var lit := ArcadeParts.mat(_v["marquee"], 0.0, 0.5, _v["glow"], 0.0)
		ArcadeParts.box(_owner, base, "RoofSign", Vector3(_w - 0.06, 0.16, 0.012), Vector3(0, 1.90, COCKPIT_Z1 - 0.06), lit)
	if flight and bool(spec.get("cabin", false)):
		_build_cabin(base)
	# The driver's controls, one controller.
	var mod := ArcadeParts.node(_owner, base, "Node3D", "Player1") as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", int(spec.get("player", 0)))
	# START on the dash, left of the wheel, in a frame whose +Z is out of the dash's top.
	var panel := ArcadeParts.node(_owner, mod, "Node3D", "DashPanel", Vector3(-0.36 if seats > 1 else -0.22, 0.725, 1.02)) as Node3D
	panel.basis = Basis(Vector3.RIGHT, deg_to_rad(-72.0))
	_cap(panel, "Start", Vector3.ZERO, 0.012, Color(0.92, 0.92, 0.92), 0.008)
	if seats > 1:
		# The gunner's START, on the dash at the other end, its own controller (player 2) the way a deck panel's START is: the panel's frame has its START 7 cm
		# down its own Y, so the frame stands that much up it for the cap to land where the driver's is, mirrored.
		var gunner := ArcadeParts.node(_owner, base, "Node3D", "GunnerPanel", Vector3(0.36, 0.725, 1.02)) as Node3D
		gunner.basis = Basis(Vector3.RIGHT, deg_to_rad(-72.0))
		gunner.position += gunner.basis.y * 0.07
		_build_player(gunner, 1, {"kind": "start", "start_x": 0.0, "player": 1})
	var grip := ArcadeParts.node(_owner, mod, "Area3D", "PanelGrip") as Area3D
	grip.set_script(load(SCRIPTS["panel"]))
	grip.collision_layer = 0
	grip.collision_mask = 0
	var gcol := ArcadeParts.node(_owner, grip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var gshape := BoxShape3D.new()
	gcol.shape = gshape
	if flight:
		_flight_controls(base, mod, panel, spec)
		# The grip faces the driver, round the stick's head.
		grip.position = Vector3(0, STICK_BASE_Y + 0.34, STICK_Z)
		grip.set("panel_size", Vector2(0.32, 0.32))
		gshape.size = Vector3(0.32, 0.32, 0.30)
	else:
		var wb := Basis(Vector3.RIGHT, deg_to_rad(60.0))
		var wheel_at := Vector3(driver_x, 0.82, 1.20)
		_wheel(mod, wheel_at, wb, 0.15)
		_pedals(mod, Transform3D.IDENTITY, Vector3(driver_x, 0.10, PEDALS_Z))
		if bool(spec.get("shifter", true)):
			_shifter(mod, Vector3(_w * 0.5 - 0.10, 0.54, SHIFTER_Z), Basis.IDENTITY.rotated(Vector3.RIGHT, -PI * 0.5))
		# The grip faces the driver: its +Z along the wheel's axis.
		grip.position = wheel_at
		grip.basis = wb * Basis(Vector3.RIGHT, -PI * 0.5)
		grip.set("panel_size", Vector2(0.36, 0.36))
		gshape.size = Vector3(0.36, 0.36, 0.16)
	form_boxes.append(AABB(Vector3(-_w * 0.5, 0.0, COCKPIT_Z0), Vector3(_w, 0.10, depth)))
	# The seat is aimed at as the cabinet except on its cushion, which is the seat's own (a sitting press): a box over
	# the whole seat would stand between the laser and the trigger that lies 3 cm proud of the cushion. So the base
	# under the cushion and the back behind it, and nothing above.
	var cushion_top := ((_sh["glass_a"] as Vector2).y + (_sh["glass_b"] as Vector2).y) * 0.5 - EYE_ABOVE_CUSHION
	var seat_w := RACEGUN_SEAT_W if seats > 1 else 0.48
	for sx: float in ([driver_x, seat_x] if seats > 1 else [driver_x]):
		form_boxes.append(AABB(Vector3(sx - seat_w * 0.5, PLATFORM_TOP, SEAT_Z - 0.23), Vector3(seat_w, cushion_top - 0.03 - PLATFORM_TOP, 0.46)))
		form_boxes.append(AABB(Vector3(sx - seat_w * 0.5, cushion_top, SEAT_Z + 0.23), Vector3(seat_w, 1.25 - cushion_top, 0.17)))
	form_boxes.append(AABB(Vector3(-(_w - 0.10) * 0.5, 0.10, 0.88), Vector3(_w - 0.10, 0.62, 0.20)))
	if flight and bool(spec.get("cabin", false)):
		# The cabin's walls are the cabinet too, to take hold of by; its roof is left open to the laser, or it would stand over every control.
		for k in [-1.0, 1.0]:
			form_boxes.append(AABB(Vector3(k * (_w * 0.5 - 0.02) - 0.02, PLATFORM_TOP, CABIN_Z0), Vector3(0.04, CABIN_H, CABIN_Z1 - CABIN_Z0)))


## A flight cockpit's controls (Player1's): the stick between the knees on its console, a gaiter, a shaft and a grip with the first buttons on its
## head, the next two on the throttle's knob where there is a throttle and on the stick's head where there is none, the last two on the dash by
## START. The stick's frame stands with its +Z up and its +Y toward the screen, so it leans as a deck stick does (ArcadeControlModule._pose_stick);
## the throttle lever's top moves toward -Z for forward (ThrottlePivot), and both are the controller's own parts: found by name, held by the hands.
func _flight_controls(base: Node3D, mod: Node3D, dash_panel: Node3D, spec: Dictionary) -> void:
	var rubber := ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.6)
	var throttle := bool(spec.get("throttle", false))
	# The stick's grip is the player's colour, as a deck stick's ball is: black on the black dash it was lost.
	var grip_paint := ArcadeParts.mat(_player_color(int(spec.get("player", 0))), 0.0, 0.3)
	ArcadeParts.box(_owner, base, "StickConsole", Vector3(0.30, STICK_BASE_Y - 0.10, 0.30), Vector3(0, (STICK_BASE_Y + 0.10) * 0.5, STICK_Z), _body)
	var frame := ArcadeParts.node(_owner, mod, "Node3D", "StickFrame", Vector3(0, STICK_BASE_Y, STICK_Z)) as Node3D
	frame.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	ArcadeParts.cylinder(_owner, frame, "StickGaiter", 0.05, 0.07, Vector3(0, 0, 0.035), _dark, Vector3.BACK)
	var pivot := ArcadeParts.node(_owner, frame, "Node3D", "StickPivot", Vector3(0, 0, 0.03)) as Node3D
	ArcadeParts.cylinder(_owner, pivot, "StickShaft", 0.011, FLIGHT_GRIP_Z, Vector3(0, 0, FLIGHT_GRIP_Z * 0.5), _metal, Vector3.BACK)
	# The grip: a rubber handle lying along the shaft's axis, with a flat head on top that the first buttons stand in.
	var grip := ArcadeParts.node(_owner, pivot, "MeshInstance3D", "StickBall", Vector3(0, 0, FLIGHT_GRIP_Z)) as MeshInstance3D
	var gm := CapsuleMesh.new()
	gm.radius = 0.030
	gm.height = 0.13
	gm.radial_segments = 16
	gm.rings = 4
	gm.material = grip_paint
	grip.mesh = gm
	grip.basis = Basis(Vector3.RIGHT, PI * 0.5)
	var head := ArcadeParts.node(_owner, pivot, "Node3D", "StickHead", Vector3(0, 0, FLIGHT_GRIP_Z + 0.06)) as Node3D
	_cap(head, "Btn1", Vector3(-0.015, 0.0, 0.0), 0.010, BUTTON_COLORS[0], 0.009)
	_cap(head, "Btn2", Vector3(0.015, 0.0, 0.0), 0.010, BUTTON_COLORS[1], 0.009)
	if not throttle:
		_cap(head, "Btn3", Vector3(-0.015, 0.0, 0.0) + Vector3(0, 0.026, 0), 0.0085, BUTTON_COLORS[2], 0.009)
		_cap(head, "Btn4", Vector3(0.015, 0.026, 0.0), 0.0085, BUTTON_COLORS[3], 0.009)
	else:
		# The throttle: a console by the left hand with a lever standing up out of it, its knob a thumb's reach from two buttons.
		var tx := -(_w * 0.5 - 0.10)
		ArcadeParts.box(_owner, base, "ThrottleConsole", Vector3(0.12, 0.40, 0.34), Vector3(tx, 0.30, THROTTLE_Z), _body)
		var lever := ArcadeParts.node(_owner, mod, "Node3D", "ThrottlePivot", Vector3(tx, 0.50, THROTTLE_Z)) as Node3D
		ArcadeParts.cylinder(_owner, lever, "ThrottleShaft", 0.010, 0.18, Vector3(0, 0.09, 0), _metal, Vector3.UP)
		var knob := ArcadeParts.node(_owner, lever, "MeshInstance3D", "ThrottleKnob", Vector3(0, 0.20, 0)) as MeshInstance3D
		var km := CapsuleMesh.new()
		km.radius = 0.027
		km.height = 0.09
		km.radial_segments = 16
		km.rings = 4
		km.material = rubber
		knob.mesh = km
		var tip := ArcadeParts.node(_owner, lever, "Node3D", "ThrottleHead", Vector3(0, 0.245, 0)) as Node3D
		tip.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		_cap(tip, "Btn3", Vector3(-0.012, 0.0, 0.0), 0.0095, BUTTON_COLORS[2], 0.008)
		_cap(tip, "Btn4", Vector3(0.012, 0.0, 0.0), 0.0095, BUTTON_COLORS[3], 0.008)
	# The last two buttons beside START on the dash.
	_cap(dash_panel, "Btn5", Vector3(0.05, 0.0, 0.0), 0.012, BUTTON_COLORS[4], 0.008)
	_cap(dash_panel, "Btn6", Vector3(0.09, 0.0, 0.0), 0.012, BUTTON_COLORS[5], 0.008)


## The cabin round a flight cockpit's seat (After Burner's, G-LOC's, Galaxy Force's): a panel each side, its front edge slanting up from the sill
## to the roof's front corner as a canopy's does, a roof over them that runs forward over the monitor housing, and the lock-on lamps along its front;
## open behind, where the player gets in. The shape is an estimate: the research found words for these cabinets, no photograph.
func _build_cabin(base: Node3D) -> void:
	var z1 := CABIN_Z1
	var top := PLATFORM_TOP + CABIN_H
	var side := PackedVector2Array([Vector2(CABIN_FRONT_Z, top), Vector2(z1, top), Vector2(z1, PLATFORM_TOP),
		Vector2(CABIN_Z0, PLATFORM_TOP), Vector2(CABIN_Z0, CABIN_SILL_Y)])
	var panel_mesh := _extrude(side, 0.04)
	panel_mesh.surface_set_material(0, _body)
	for k in [-1.0, 1.0]:
		var name_side := "L" if k < 0 else "R"
		var x: float = k * (_w * 0.5 - 0.02)
		var wall := ArcadeParts.node(_owner, base, "MeshInstance3D", "CabinWall" + name_side, Vector3(x, 0, 0)) as MeshInstance3D
		wall.mesh = panel_mesh
		ArcadeParts.box(_owner, base, "CabinTrim" + name_side, Vector3(0.044, 0.02, z1 - CABIN_FRONT_Z), Vector3(x, top - 0.01, (CABIN_FRONT_Z + z1) * 0.5), _trim)
	var roof_z0 := ROOF_FRONT_Z
	ArcadeParts.box(_owner, base, "CabinRoof", Vector3(_w, 0.05, z1 - roof_z0), Vector3(0, top + 0.025, (roof_z0 + z1) * 0.5), _body)
	# Lock-on lights along the front of the roof, over the monitor surround where the real cabin had them (research: the lights, not their number).
	var lamp := ArcadeParts.mat(Color(0.9, 0.12, 0.10), 0.0, 0.4, Color(1.0, 0.1, 0.1), 1.2)
	for i in 5:
		ArcadeParts.box(_owner, base, "CabinLamp%d" % (i + 1), Vector3(0.05, 0.012, 0.05),
			Vector3((float(i) - 2.0) * 0.1, top - 0.006, CABIN_LAMP_Z), lamp)


## Where the driver's seat stands, front to back (the cushion's middle), and the platform's top it stands on. The eyes (4 cm behind it) are 0.95 m from the
## picture, which fills 28 degrees of the view: 0.36 m from the glass's lower edge to the wheel and 0.42 m on to the eyes, as a cabinet's were.
const SEAT_Z := 1.58
const PLATFORM_TOP := 0.10
## A sitting adult's eye height above the cushion (the racing seat furniture's own, gen_seats.gd).
const EYE_ABOVE_CUSHION := 0.72


## A seat that can be sat in (CockpitSeat; seats.md): a base, the cushion, a back leaning back and
## a headrest, with the markers a seat needs. THE EYES ARE AT THE MIDDLE OF THE GLASS: the `racer` body is built
## for a seated driver to look straight into its monitor (1.12 m), and the cushion is an adult's eye height under
## them. MAME says nothing of where a driver sat, so the screen is what a seat is fitted to. The node stands on the
## platform, at the cushion; the parts and markers are in its frame. `x` and `z` are where it stands (a bench has two, side by side, a
## narrower `width` each), `stand_x` which side of it the player gets up onto, `eye_cap` the highest the eyes may be (a bench in front of a TALL
## glass is a bench, not a stool).
func _build_driver_seat(cp: Node3D, x: float = 0.0, z: float = SEAT_Z, node_name: String = "DriverSeat",
		width: float = 0.48, stand_x: float = -0.62, eye_cap: float = INF) -> void:
	var eye_y := minf(((_sh["glass_a"] as Vector2).y + (_sh["glass_b"] as Vector2).y) * 0.5, eye_cap)
	var cushion := eye_y - EYE_ABOVE_CUSHION - PLATFORM_TOP     # the cushion's top, above the platform
	var seat := ArcadeParts.node(_owner, cp, "Node3D", node_name, Vector3(x, PLATFORM_TOP, z)) as Node3D
	seat.set_script(load(SCRIPTS["seat"]))
	var seat_mat := ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.7)
	var base_h := cushion - 0.08
	var base_w := minf(0.36, width - 0.06)
	ArcadeParts.box(_owner, seat, "SeatBase", Vector3(base_w, base_h, 0.36), Vector3(0, base_h * 0.5, 0.02), _dark)
	ArcadeParts.box(_owner, seat, "SeatCushion", Vector3(width, 0.08, 0.46), Vector3(0, cushion - 0.04, 0.0), seat_mat)
	# The back leans BACK, away from the screen (+Z), and the headrest on top of it.
	var back := ArcadeParts.box(_owner, seat, "SeatBack", Vector3(width, 0.62, 0.08), Vector3(0, cushion + 0.30, 0.24), seat_mat)
	back.basis = Basis(Vector3.RIGHT, deg_to_rad(14.0))
	var head := ArcadeParts.box(_owner, seat, "SeatHead", Vector3(minf(0.30, width - 0.10), 0.16, 0.08), Vector3(0, cushion + 0.69, 0.34), seat_mat)
	head.basis = back.basis
	# The cushion you press: 3 cm proud of the surface (a seat's own rule, gen_seats.gd).
	var trigger := ArcadeParts.node(_owner, seat, "Area3D", "SeatTrigger", Vector3(0, cushion + 0.005, 0.0)) as Area3D
	trigger.set_script(load(SCRIPTS["seat_trigger"]))
	var tcol := ArcadeParts.node(_owner, trigger, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var tshape := BoxShape3D.new()
	tshape.size = Vector3(width - 0.02, 0.03, 0.44)
	tcol.shape = tshape
	ArcadeParts.node(_owner, seat, "Marker3D", "EyePoint", Vector3(0, eye_y - PLATFORM_TOP, 0.04))
	# Getting up is to the driver's side (the left): the front is the dash and the right the gear lever.
	ArcadeParts.node(_owner, seat, "Marker3D", "StandPoint", Vector3(stand_x, -PLATFORM_TOP, 0.02))


## The seat a rider sits in on a bike or a bicycle (`RiderSeat`, a CockpitSeat): no seat of its own is drawn, the saddle is the machine's, only what makes it a
## seat: the cushion you press, on the saddle's top (`saddle` its width and length), the eyes above it (`eye_above`, a little toward the bars by `eye_dz`: a rider
## leans forward) and the floor to get up onto, beside the stand (`stand_x`). It stands at `floor_y`, the floor the rider's own feet are taken to be on (the stand's top
## for a bike, the pedals' height for a bicycle): a headset adds its person's own height to it, so a person on a real chair has their eyes about where a rider's are.
## It is NOT on the leaning part: a bike that leaned its rider 14 degrees would swing a head 30 cm; the rider's own body does the leaning.
func _build_rider_seat(parent: Node3D, floor_y: float, z: float, saddle_top: float, saddle: Vector2, eye_above: float, eye_dz: float, stand_x: float) -> void:
	var seat := ArcadeParts.node(_owner, parent, "Node3D", "RiderSeat", Vector3(0.0, floor_y, z)) as Node3D
	seat.set_script(load(SCRIPTS["seat"]))
	var trigger := ArcadeParts.node(_owner, seat, "Area3D", "SeatTrigger", Vector3(0.0, saddle_top - floor_y + 0.005, 0.0)) as Area3D
	trigger.set_script(load(SCRIPTS["seat_trigger"]))
	var tcol := ArcadeParts.node(_owner, trigger, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var tshape := BoxShape3D.new()
	tshape.size = Vector3(saddle.x - 0.02, 0.03, saddle.y - 0.04)
	tcol.shape = tshape
	ArcadeParts.node(_owner, seat, "Marker3D", "EyePoint", Vector3(0.0, saddle_top - floor_y + eye_above, eye_dz))
	ArcadeParts.node(_owner, seat, "Marker3D", "StandPoint", Vector3(stand_x, -floor_y, 0.02))


# ── a bench for a ride ──────────────────────────────────────────────────────

## Where a bench's platform starts and ends, and where its seats are front to back: a seat's width apart, close enough to the guns on the front
## of the deck (0.47 m out) to reach them with the arm bent.
const BENCH_Z0 := 0.84
const BENCH_Z1 := 1.56
const BENCH_SEAT_Z := 1.16
## A bench's seated eyes: the middle of a wide body's glass is 1.33 m up, which would put the cushion 0.61 m off the floor.
const BENCH_EYE_Y := 1.20


## The bench a ride was played on (Rail Chase, The Lost World, Jurassic Park): a platform in front of the guns and a seat each, two at most, side by side
## on it, the player's own to sit in (CockpitSeat). The guns stay where they are on the deck. The real benches moved with the ride; this one does
## not, because nothing the cabinet is given says how (the game's motion data is not in the libretro API), and a bench that rocked to no purpose
## under a headset would be harm for nothing.
func _build_bench(spec: Dictionary) -> void:
	var seats := clampi(int(spec.get("seats", 1)), 1, 2)
	var bench := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Bench", Vector3.ZERO)) as Node3D
	var depth := BENCH_Z1 - BENCH_Z0
	var zc := (BENCH_Z0 + BENCH_Z1) * 0.5
	ArcadeParts.box(_owner, bench, "BenchPlatform", Vector3(_w, 0.10, depth), Vector3(0, 0.05, zc), _body)
	ArcadeParts.box(_owner, bench, "BenchTrim", Vector3(_w + 0.004, 0.012, depth + 0.004), Vector3(0, 0.084, zc), _trim)
	var width := 0.40 if seats > 1 else 0.48
	var xs: Array = [0.0] if seats == 1 else [-0.21, 0.21]
	for i in seats:
		# Each player gets up on the outside of their own seat.
		_build_driver_seat(bench, float(xs[i]), BENCH_SEAT_Z, "BenchSeat%d" % (i + 1), width, -0.62 if xs[i] <= 0.0 else 0.62, BENCH_EYE_Y)
	form_boxes.append(AABB(Vector3(-_w * 0.5, 0.0, BENCH_Z0), Vector3(_w, 0.10, depth)))
	# The seats are aimed at as the cabinet except on their cushions (as the cockpit's): the base under each, the back behind it.
	var cushion_top := minf(((_sh["glass_a"] as Vector2).y + (_sh["glass_b"] as Vector2).y) * 0.5, BENCH_EYE_Y) - EYE_ABOVE_CUSHION
	for x: float in xs:
		form_boxes.append(AABB(Vector3(x - width * 0.5, PLATFORM_TOP, BENCH_SEAT_Z - 0.23), Vector3(width, cushion_top - 0.03 - PLATFORM_TOP, 0.46)))
		form_boxes.append(AABB(Vector3(x - width * 0.5, cushion_top, BENCH_SEAT_Z + 0.23), Vector3(width, 1.25 - cushion_top, 0.17)))


# ── a ride-on motorbike ─────────────────────────────────────────────────────

## A ride-on motorbike in front of the monitor housing (Hang-On, Harley-Davidson, Manx TT): a body you
## straddle on a stand, the seat, the tank, and the handlebars. The bike leans with the steering
## (`LeanPivot`, as the real one tipped under the rider), and the rider takes hold of it at the bars.
## Where a bike's saddle is: its top (the BikeSeat box's, on the LeanPivot at 0.12 m: 0.12 + 0.55 + 0.04), its middle front to back, and the floor the rider's feet are
## taken to be on (the stand's top).
const BIKE_SADDLE_TOP := 0.71
const BIKE_SADDLE_Z := 1.73
const BIKE_FLOOR_Y := 0.10


func _build_bike(spec: Dictionary) -> void:
	var bk := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Bike", Vector3.ZERO)) as Node3D
	ArcadeParts.box(_owner, bk, "BikeStand", Vector3(0.40, 0.10, 1.10), Vector3(0, 0.05, 1.45), _dark)
	ArcadeParts.box(_owner, bk, "BikeStandTrim", Vector3(0.404, 0.012, 1.104), Vector3(0, 0.084, 1.45), _trim)
	var mod := ArcadeParts.node(_owner, bk, "Node3D", "Player1") as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", int(spec.get("player", 0)))
	# The bike leans about its long axis, at the stand.
	var lean := ArcadeParts.node(_owner, mod, "Node3D", "LeanPivot", Vector3(0, 0.12, 1.45)) as Node3D
	var paint := ArcadeParts.mat(_v["trim"], 0.2, 0.35)
	ArcadeParts.box(_owner, lean, "BikeFrame", Vector3(0.10, 0.36, 0.90), Vector3(0, 0.26, 0.0), _dark)
	ArcadeParts.box(_owner, lean, "BikeFairing", Vector3(0.30, 0.34, 0.30), Vector3(0, 0.52, -0.40), paint)
	ArcadeParts.box(_owner, lean, "BikeTank", Vector3(0.26, 0.16, 0.34), Vector3(0, 0.56, -0.08), paint)
	ArcadeParts.box(_owner, lean, "BikeSeat", Vector3(0.24, 0.08, 0.44), Vector3(0, 0.55, 0.28),
		ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.7))
	ArcadeParts.box(_owner, lean, "BikeTail", Vector3(0.22, 0.16, 0.16), Vector3(0, 0.56, 0.52), paint)
	# The bars: a crossbar on the fork with a grip at each end (the right one the throttle).
	var bars := ArcadeParts.node(_owner, lean, "Node3D", "Handlebars", Vector3(0, 0.74, -0.30)) as Node3D
	ArcadeParts.cylinder(_owner, bars, "BarCross", 0.012, 0.56, Vector3.ZERO, _metal, Vector3.RIGHT)
	for k in [-1.0, 1.0]:
		ArcadeParts.cylinder(_owner, bars, "BarGrip%s" % ("L" if k < 0 else "R"), 0.018, 0.11,
			Vector3(k * 0.26, 0, 0), ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.6), Vector3.RIGHT)
	# START on top of the bars' clamp, standing up out of it.
	var clamp := ArcadeParts.node(_owner, bars, "Node3D", "BarPanel", Vector3(0.0, 0.014, 0.0)) as Node3D
	clamp.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	ArcadeParts.box(_owner, bars, "BarClamp", Vector3(0.08, 0.016, 0.05), Vector3(0, 0.006, 0), _dark)
	_cap(clamp, "Start", Vector3.ZERO, 0.011, Color(0.92, 0.92, 0.92), 0.008)
	var grip := ArcadeParts.node(_owner, lean, "Area3D", "PanelGrip", Vector3(0, 0.74, -0.30)) as Area3D
	grip.set_script(load(SCRIPTS["panel"]))
	grip.collision_layer = 0
	grip.collision_mask = 0
	grip.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	grip.set("panel_size", Vector2(0.62, 0.20))
	var gcol := ArcadeParts.node(_owner, grip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(0.62, 0.20, 0.14)
	gcol.shape = gshape
	# The rider's seat: on the saddle (a box 0.24 x 0.44 whose top is 0.71 m up, at z 1.73), the eyes 0.68 m above it. Not on the LeanPivot.
	_build_rider_seat(bk, BIKE_FLOOR_Y, BIKE_SADDLE_Z, BIKE_SADDLE_TOP, Vector2(0.24, 0.44), 0.68, -0.06, -0.50)
	# Aimed at, the machine is the cabinet (to hold and carry): its front (the fairing, the tank, the bars' stand) and its tail UNDER the saddle's top,
	# which is the seat's own (a box over it would stand between the laser and the trigger).
	form_boxes.append(AABB(Vector3(-0.20, 0.0, 0.90), Vector3(0.40, 0.75, BIKE_SADDLE_Z - 0.22 - 0.90)))
	form_boxes.append(AABB(Vector3(-0.20, 0.0, BIKE_SADDLE_Z - 0.22), Vector3(0.40, BIKE_SADDLE_TOP - 0.03, 0.90 + 1.10 - (BIKE_SADDLE_Z - 0.22))))


# ── a ride-on bicycle ───────────────────────────────────────────────────────

## Where a bicycle's stand starts and ends front to back (clear of the bay door's swing, as the cockpit's platform).
const CYCLE_Z0 := 0.84
const CYCLE_Z1 := 2.14
## Where the bicycle's saddle is (its top and middle, front to back) and the floor the rider's feet are taken to be on: the pedals' height.
const CYCLE_SADDLE_TOP := 0.975
const CYCLE_SADDLE_Z := 1.86
const CYCLE_FLOOR_Y := 0.40


## A tube from one point to another in `parent`'s frame: what a bicycle's frame is made of.
func _rod(parent: Node3D, node_name: String, from: Vector3, to: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	var d := to - from
	return ArcadeParts.cylinder(_owner, parent, node_name, radius, d.length(), (from + to) * 0.5, material, d.normalized())


## A stationary bicycle in front of the monitor housing (Prop Cycle): a frame on a stand, a saddle, handlebars on a stem
## and a crank with its two pedals. The bars (`BarsPivot`) turn and tip with the left stick, MAME's `IPT_AD_STICK_X` and
## `_Y` (the grips steer the craft and tilt it up or down), and the crank (`CrankPivot`) turns with the right stick's Y, the
## "Cycle Pedal" (`IPT_AD_STICK_Z`: the faster it is turned the more the game reads). The rider takes hold of the bars; the
## controls are ONE controller (Player1) as a panel is. No collision: a player steps up to it.
func _build_cycle(spec: Dictionary) -> void:
	var cy := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Cycle", Vector3.ZERO)) as Node3D
	var depth := CYCLE_Z1 - CYCLE_Z0
	var zc := (CYCLE_Z0 + CYCLE_Z1) * 0.5
	ArcadeParts.box(_owner, cy, "CycleStand", Vector3(0.56, 0.10, depth), Vector3(0, 0.05, zc), _dark)
	ArcadeParts.box(_owner, cy, "CycleStandTrim", Vector3(0.564, 0.012, depth + 0.004), Vector3(0, 0.084, zc), _trim)
	var mod := ArcadeParts.node(_owner, cy, "Node3D", "Player1") as Node3D
	mod.set_script(load(SCRIPTS["control"]))
	mod.set("player", int(spec.get("player", 0)))
	var paint := ArcadeParts.mat(_v["trim"], 0.2, 0.35)
	var rubber := ArcadeParts.mat(Color(0.08, 0.08, 0.09), 0.0, 0.7)
	var bb := Vector3(0.0, 0.40, 1.62)       # the bottom bracket, the crank's axle
	var seat := Vector3(0.0, 0.90, 1.82)     # the top of the seat tube, under the saddle
	var head := Vector3(0.0, 0.88, 1.20)     # the head tube, under the stem
	var rear := Vector3(0.0, 0.32, 2.00)     # the rear axle, held up on a post
	_rod(mod, "SeatTube", bb, seat, 0.022, paint)
	_rod(mod, "TopTube", seat + Vector3(0, -0.05, -0.02), head, 0.020, paint)
	_rod(mod, "DownTube", bb, head + Vector3(0, -0.05, 0.0), 0.024, paint)
	_rod(mod, "ChainStay", bb, rear, 0.014, paint)
	_rod(mod, "SeatStay", seat + Vector3(0, -0.08, 0), rear, 0.012, paint)
	_rod(mod, "Fork", head, Vector3(0.0, 0.10, 1.10), 0.016, _metal)
	_rod(mod, "RearPost", rear, Vector3(0.0, 0.10, rear.z), 0.016, _metal)
	var saddle := ArcadeParts.box(_owner, mod, "Saddle", Vector3(0.15, 0.05, 0.27), seat + Vector3(0, 0.05, 0.04), rubber)
	saddle.basis = Basis(Vector3.RIGHT, deg_to_rad(-6.0))
	var stem_top := head + Vector3(0.0, 0.14, -0.02)
	_rod(mod, "Stem", head, stem_top, 0.014, _metal)
	# The bars: a crossbar on the stem with a grip at each end and a brake lever in front of it, START on the clamp.
	var bars := ArcadeParts.node(_owner, mod, "Node3D", "BarsPivot", stem_top) as Node3D
	ArcadeParts.cylinder(_owner, bars, "BarCross", 0.012, 0.58, Vector3.ZERO, _metal, Vector3.RIGHT)
	for k in [-1.0, 1.0]:
		ArcadeParts.cylinder(_owner, bars, "BarGrip%s" % ("L" if k < 0 else "R"), 0.018, 0.11,
			Vector3(k * 0.30, 0, 0), rubber, Vector3.RIGHT)
		ArcadeParts.box(_owner, bars, "BrakeLever%s" % ("L" if k < 0 else "R"), Vector3(0.02, 0.02, 0.09),
			Vector3(k * 0.25, -0.012, -0.05), _metal)
	var clamp := ArcadeParts.node(_owner, bars, "Node3D", "BarPanel", Vector3(0.0, 0.014, 0.0)) as Node3D
	clamp.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	ArcadeParts.box(_owner, bars, "BarClamp", Vector3(0.08, 0.016, 0.05), Vector3(0, 0.006, 0), _dark)
	_cap(clamp, "Start", Vector3.ZERO, 0.011, Color(0.92, 0.92, 0.92), 0.008)
	# The crank: an axle through the frame, a chainring, and an arm and a pedal each side, a half turn apart.
	var crank := ArcadeParts.node(_owner, mod, "Node3D", "CrankPivot", bb) as Node3D
	ArcadeParts.cylinder(_owner, crank, "CrankAxle", 0.012, 0.30, Vector3.ZERO, _metal, Vector3.RIGHT)
	ArcadeParts.cylinder(_owner, crank, "Chainring", 0.085, 0.006, Vector3(0.06, 0, 0), _metal, Vector3.RIGHT)
	for k in [1.0, -1.0]:
		var side := "R" if k > 0 else "L"
		ArcadeParts.box(_owner, crank, "CrankArm" + side, Vector3(0.022, 0.17, 0.03), Vector3(k * 0.10, k * 0.085, 0), _metal)
		ArcadeParts.box(_owner, crank, "CrankPedal" + side, Vector3(0.10, 0.022, 0.09), Vector3(k * 0.14, k * 0.17, 0), rubber)
	# The rider's hands are one controller, taken hold of at the bars.
	var grip := ArcadeParts.node(_owner, mod, "Area3D", "PanelGrip", stem_top) as Area3D
	grip.set_script(load(SCRIPTS["panel"]))
	grip.collision_layer = 0
	grip.collision_mask = 0
	grip.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	grip.set("panel_size", Vector2(0.66, 0.20))
	var gcol := ArcadeParts.node(_owner, grip, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(0.66, 0.20, 0.14)
	gcol.shape = gshape
	# The rider's seat: on the saddle (0.15 x 0.27, its top 0.975 m up at z 1.86), the eyes 0.72 m above it, the rider's feet taken to be at the pedals' height.
	_build_rider_seat(cy, CYCLE_FLOOR_Y, CYCLE_SADDLE_Z, CYCLE_SADDLE_TOP, Vector2(0.15, 0.27), 0.72, -0.04, -0.55)
	# Aimed at it is the cabinet (to hold and carry), under the bars: a box that reached them would hide their grip from a
	# laser, which hits the nearest pointable.
	form_boxes.append(AABB(Vector3(-0.28, 0.0, CYCLE_Z0), Vector3(0.56, 0.75, depth)))


# ── a dance stage ───────────────────────────────────────────────────────────

## Where the middle of a dancer's square is, and its side: three panels of 30 cm.
const STAGE_Z := 1.30
const STAGE_SIDE := 0.90
## Where a bass drum's pedal stands on the floor in front of the cabinet (the cabinet's z): the player's right foot, clear of the bay door's swing.
const BASS_PEDAL_Z := 0.95


## The stage in front of a dance cabinet (Dance Dance Revolution, Pump It Up): a square for each dancer,
## nine panels of 30 cm, with the safety bar behind. The arrows are the dancers' own (each player's
## controller, ArcadeCabinetBuilder._arrows); this is what does not move. Barely off the floor, and no
## collision: a player stands on it with their own feet.
func _build_stage(spec: Dictionary) -> void:
	var st := _form_node(ArcadeParts.node(_owner, _top, "Node3D", "Stage", Vector3.ZERO)) as Node3D
	var xs: Array = spec.get("xs", [0.0])
	for i in xs.size():
		var x := float(xs[i])
		ArcadeParts.box(_owner, st, "StageBase%d" % (i + 1), Vector3(STAGE_SIDE, 0.02, STAGE_SIDE),
			Vector3(x, 0.01, STAGE_Z), _metal)
		# The fixed panels the arrows leave (DDR's centre and corners, Pump It Up's edges).
		for row in 3:
			for col in 3:
				if _is_arrow(int(spec.get("arrows", 4)), row, col):
					continue
				ArcadeParts.box(_owner, st, "StageTile%d_%d%d" % [i + 1, row, col], Vector3(0.27, 0.006, 0.27),
					Vector3(x + (col - 1) * 0.30, 0.023, STAGE_Z + (row - 1) * 0.30), _dark)
		# The safety bar: two posts at the back corners and the rail across.
		for k in [-1.0, 1.0]:
			ArcadeParts.cylinder(_owner, st, "BarPost%d%s" % [i + 1, "L" if k < 0 else "R"], 0.02, 0.95,
				Vector3(x + k * 0.42, 0.495, STAGE_Z + 0.48), _metal, Vector3.UP)
		ArcadeParts.cylinder(_owner, st, "BarRail%d" % (i + 1), 0.022, 0.86, Vector3(x, 0.97, STAGE_Z + 0.48),
			_metal, Vector3.RIGHT)
		form_boxes.append(AABB(Vector3(x - STAGE_SIDE * 0.5, 0.0, STAGE_Z - STAGE_SIDE * 0.5),
			Vector3(STAGE_SIDE, 0.02, STAGE_SIDE + 0.10)))


## Is the panel at (row, col) of the 3 x 3 square an arrow? Four arrows: the edges' middles (up, left, right,
## down); five: the corners and the centre; six (DDR Solo): the four and the two corners on the screen's side
## (up-left and up-right), the other two corners and the centre left bare.
static func _is_arrow(arrows: int, row: int, col: int) -> bool:
	if arrows == 5:
		return (row != 1 and col != 1) or (row == 1 and col == 1)
	if arrows == 6:
		return (row == 1) != (col == 1) or (row == 0 and col != 1)
	return (row == 1) != (col == 1)


## A dancer's arrows on the stage at `at` (the square's middle, cabinet frame): Pad<Dir> caps the module sinks
## with the joypad's directions (DDR Solo's up-left and up-right panels are PadUpLeft and PadUpRight, MAME's buttons 3 and 4), or
## Pump It Up's five as Btn1..5 (down-left, up-left, centre, up-right, down-right). Carried into the panel's frame by `to_parent`.
func _arrows(parent: Node3D, to_parent: Transform3D, at: Vector3, arrows: int, index: int) -> void:
	var color := _player_color(index)
	var cells: Array = []
	if arrows == 5:
		cells = [["Btn1", 2, 0], ["Btn2", 0, 0], ["Btn3", 1, 1], ["Btn4", 0, 2], ["Btn5", 2, 2]]
	else:
		cells = [["PadUp", 0, 1], ["PadLeft", 1, 0], ["PadRight", 1, 2], ["PadDown", 2, 1]]
		if arrows == 6:
			cells.append(["PadUpLeft", 0, 0])
			cells.append(["PadUpRight", 0, 2])
	for c: Array in cells:
		var pos := at + Vector3((int(c[2]) - 1) * 0.30, 0.026, (int(c[1]) - 1) * 0.30)
		var plate := ArcadeParts.box(_owner, parent, str(c[0]), Vector3(0.27, 0.008, 0.27), Vector3.ZERO,
			ArcadeParts.mat(color.lerp(Color.WHITE, 0.15), 0.0, 0.3, color, 0.0))
		plate.transform = to_parent * Transform3D(Basis.IDENTITY, pos)
		# The arrow's mark: a white bar pointing the way (for Pump's, toward the corner it is in).
		var mark := ArcadeParts.box(_owner, plate, "Mark", Vector3(0.05, 0.004, 0.16), Vector3(0, 0.006, 0),
			ArcadeParts.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4))
		var dir := Vector2(int(c[2]) - 1, int(c[1]) - 1)
		if dir.length_squared() > 0.0:
			mark.basis = Basis(Vector3.UP, atan2(dir.x, dir.y))


# ── composite input ─────────────────────────────────────────────────────────

## The cabinet's composite INPUT: a rectangle on the compartment floor beside the power supply (which stands to the
## right at the back; this is the other side of it), three phono sockets on its top facing UP so a hand leaning
## in puts a plug straight down, a yellow plate with COMPOSITE IN in front of them, and a LED on its front
## that says whether it takes input (ArcadeAvInModule: only while the compartment holds no unit). The sockets
## are the cabinet's, not any bay unit's.
func _build_av_in() -> void:
	var rca := load("res://Scenes/Objects/cables/rca_port.tscn") as PackedScene
	var mod := ArcadeParts.node(_owner, _top, "Node3D", "AvIn", Vector3.ZERO) as Node3D
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


# ── service switches ────────────────────────────────────────────────────────

## The TEST and SERVICE switches on a small bracket on the compartment's floor, at the side OPPOSITE the power switch
## (which is at x +0.17: these are at -0.17), standing up out of the shelf as it does so a hand or a ray from above
## reaches them with the door open. Each is a VRButton whose frame has +Z up and sinks along -Z; the module
## (ArcadeServiceModule) says which one was pressed. Baked with the cabinet: every real one had them, and the game's
## profile only says whether they are on show.
func _build_service() -> void:
	var mod := ArcadeParts.node(_owner, _top, "Node3D", "Service", Vector3.ZERO) as Node3D
	mod.set_script(load(SCRIPTS["service"]))
	var floor_y := 0.105
	var z := 0.22
	ArcadeParts.box(_owner, mod, "ServicePlate", Vector3(0.20, 0.004, 0.085), Vector3(-0.17, floor_y + 0.002, z + 0.020), _metal)
	# The operator's selector on a second bracket in front of it: a row of five (left, down, up, right, enter), for a test menu worked with
	# the first player's stick and button 1 on a cabinet that has neither.
	ArcadeParts.box(_owner, mod, "SelectPlate", Vector3(0.25, 0.004, 0.085), Vector3(-0.16, floor_y + 0.002, z + 0.100), _metal)
	# [node name, the words on the bracket, x, z, colour, font size, the label's node name]
	var items: Array = [
		["TestButton", "TEST", -0.22, z, Color(0.85, 0.12, 0.12), 44, "TestLabel"],
		["ServiceButton", "SERVICE", -0.12, z, Color(0.95, 0.75, 0.10), 44, "ServiceLabel"],
	]
	var selector: Array = [["LeftButton", "<", -0.255, "LeftLabel"], ["DownButton", "DOWN", -0.21, "DownLabel"],
		["UpButton", "UP", -0.165, "UpLabel"], ["RightButton", ">", -0.12, "RightLabel"], ["EnterButton", "ENTER", -0.065, "EnterLabel"]]
	for entry: Array in selector:
		items.append([entry[0], entry[1], entry[2], z + 0.085, Color(0.20, 0.34, 0.80) if entry[1] != "ENTER" else Color(0.15, 0.62, 0.30), 30, entry[3]])
	for item: Array in items:
		var x: float = item[2]
		var bz: float = item[3]
		var btn := ArcadeParts.node(_owner, mod, "Area3D", str(item[0]), Vector3(x, floor_y + 0.004, bz)) as Area3D
		btn.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		btn.set_script(load(SCRIPTS["button"]))
		btn.collision_layer = 0
		btn.collision_mask = 0
		btn.set("trigger_radius", 0.018 if item[5] == 44 else 0.017)
		btn.set("depress_depth", 0.004)
		btn.set("depress_axis", Vector3(0, 0, -1))
		var col := ArcadeParts.node(_owner, btn, "CollisionShape3D", "CollisionShape3D") as CollisionShape3D
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.05, 0.05, 0.05) if item[5] == 44 else Vector3(0.04, 0.05, 0.04)
		col.shape = shape
		col.position = Vector3(0, 0, 0.020)
		ArcadeParts.cylinder(_owner, btn, "ButtonMesh", 0.012, 0.012, Vector3(0, 0, 0.006),
			ArcadeParts.mat(item[4] as Color, 0.0, 0.4), Vector3.BACK)
		var tag := ArcadeParts.node(_owner, mod, "Label3D", str(item[6]),
			Vector3(x, floor_y + 0.0045, bz + 0.050 if item[5] == 44 else bz + 0.040)) as Label3D
		tag.basis = Basis(Vector3.RIGHT, -PI * 0.5)       # lies flat on the bracket, reads from the front
		tag.text = str(item[1])
		tag.pixel_size = 0.0006
		tag.font_size = int(item[5])
		# White, outlined in black: black on the grey bracket could not be read.
		tag.modulate = Color(1.0, 1.0, 1.0)
		tag.outline_size = 10
		tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
		tag.shaded = false


# ── bay ─────────────────────────────────────────────────────────────────────

func _build_bay() -> void:
	var bay := ArcadeParts.node(_owner, _top, "Node3D", "Bay", Vector3.ZERO) as Node3D
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
