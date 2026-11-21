## ToyFigure — one figure's dump (FigureShelves) in the room: an amiibo, a
## Skylander, a Disney Infinity figure or a Lego Dimensions minifigure, as a
## standee of the shelf's art and the figure's name on its base. An amiibo dump
## filed under cards is a card instead. Set on its reader (NfcTouchZone, the
## GamePad's touchpoint) or on a spot of its base (ToyBase) and the dump is
## handed to the core.
##
## Frame: +Y up, the origin at the middle of the base's underside (the card's),
## which is where its tag is: nfc_point().
class_name ToyFigure
extends XRToolsPickable

const KIND := "toy_figure"
const GROUP := "toy_figure"

## The base each line stands its figures on: radius, height, color, and the
## standee above it.
const LOOKS := {
	FigureShelves.AMIIBO: {"r": 0.02, "h": 0.009, "color": Color(0.12, 0.12, 0.13), "standee": Vector2(0.036, 0.05)},
	FigureShelves.SKYLANDERS: {"r": 0.0225, "h": 0.008, "color": Color(0.15, 0.3, 0.55), "standee": Vector2(0.04, 0.06)},
	FigureShelves.INFINITY: {"r": 0.019, "h": 0.007, "color": Color(0.78, 0.84, 0.9), "standee": Vector2(0.036, 0.065)},
	# A toy tag: the thin round disc a minifigure or a vehicle stands on.
	FigureShelves.DIMENSIONS: {"r": 0.0165, "h": 0.003, "color": Color(0.85, 0.85, 0.86), "standee": Vector2(0.024, 0.042)},
}
## An amiibo card: a trading card, 54 x 85.6 mm.
const CARD := Vector3(0.054, 0.0008, 0.0856)
const CARD_COLOR := Color(0.96, 0.96, 0.95)

@export var type_id: String = KIND
## Which shelf it is from: FigureShelves.AMIIBO and the rest.
@export var systemid: String = FigureShelves.AMIIBO
## The dump: its path on disk, what a save keeps with the shelf.
@export var rom_path: String = ""

var figure: Dictionary = {}


func _ready() -> void:
	if not LOOKS.has(systemid):
		systemid = FigureShelves.AMIIBO
	figure = FigureShelves.figure_for_path(systemid, rom_path)
	_build()
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)


func is_card() -> bool:
	return systemid == FigureShelves.AMIIBO and bool(figure.get("is_card", FigureShelves.is_card_path(rom_path)))


func label() -> String:
	return str(figure.get("name", rom_path.get_file().get_basename()))


## Where its tag is, in the world: the base's underside, or the card's middle.
func nfc_point() -> Vector3:
	return global_transform * Vector3(0, CARD.y * 0.5 if is_card() else 0.0, 0)


func _build() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var aim := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	var art := SystemIcons.for_content(systemid)
	var name_label := Label3D.new()
	name_label.name = "Name"
	name_label.text = label()
	name_label.font_size = 32
	name_label.pixel_size = 0.0001
	name_label.outline_size = 0
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_card():
		var box := BoxShape3D.new()
		box.size = CARD
		_shape(col, box, Vector3(0, CARD.y * 0.5, 0))
		var aimed := BoxShape3D.new()
		aimed.size = CARD + Vector3(0.004, 0.006, 0.004)
		_shape(aim, aimed, Vector3(0, CARD.y * 0.5, 0))
		var body := BoxMesh.new()
		body.size = CARD
		_mesh("Card", body, Transform3D(Basis.IDENTITY, Vector3(0, CARD.y * 0.5, 0)), _mat(CARD_COLOR))
		# The art and the name on its face, the top edge toward -Z.
		var face := QuadMesh.new()
		face.size = Vector2(0.044, 0.044)
		_mesh("Art", face, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, CARD.y + 0.0002, -0.012)), _art(art))
		name_label.width = 440.0
		name_label.modulate = Color(0.1, 0.1, 0.1)
		name_label.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, CARD.y + 0.0002, 0.025))
		add_child(name_label)
		return
	var look: Dictionary = LOOKS[systemid]
	var r := float(look["r"])
	var h := float(look["h"])
	var standee: Vector2 = look["standee"]
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	_shape(col, cyl, Vector3(0, h * 0.5, 0))
	var stand := BoxShape3D.new()
	stand.size = Vector3(standee.x, standee.y, 0.004)
	var stand_col := CollisionShape3D.new()
	stand_col.name = "StandeeShape"
	add_child(stand_col)
	_shape(stand_col, stand, Vector3(0, h + standee.y * 0.5, 0))
	var aimed_box := BoxShape3D.new()
	aimed_box.size = Vector3(r * 2.0 + 0.004, h + standee.y + 0.004, r * 2.0 + 0.004)
	_shape(aim, aimed_box, Vector3(0, (h + standee.y) * 0.5, 0))
	var base := CylinderMesh.new()
	base.top_radius = r
	base.bottom_radius = r
	base.height = h
	_mesh("Base", base, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), _mat(look["color"]))
	var quad := QuadMesh.new()
	quad.size = standee
	_mesh("Standee", quad, Transform3D(Basis.IDENTITY, Vector3(0, h + standee.y * 0.5, 0)), _art(art))
	# The name round the base's front, as a figure's base is printed; on a toy
	# tag, which is too thin to print round, across its top in front of the figure.
	name_label.width = r * 2.0 * 9500.0
	if h < 0.005:
		name_label.modulate = Color(0.15, 0.15, 0.15)
		name_label.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, h + 0.0002, r * 0.6))
	else:
		name_label.modulate = Color(0.92, 0.92, 0.92) if (look["color"] as Color).get_luminance() < 0.5 else Color(0.12, 0.12, 0.12)
		name_label.transform = Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, r + 0.0004))
	add_child(name_label)


func _shape(col: CollisionShape3D, shape: Shape3D, at: Vector3) -> void:
	if col == null:
		return
	col.shape = shape
	col.position = at


func _mesh(node_name: String, mesh: Mesh, xf: Transform3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = mat
	add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	return m


## The art, both sides, its clear parts clear.
func _art(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	return m
