## SuperScopeSight — the Super Scope's detachable sight, a primitive stand-in.
## From the photographs (docs/dev/super-scope.md): a grey tube about 13 cm long
## with a black rubber eyepiece at its rear end, standing on a bracket that clips
## onto the barrel's side. The barrel carries a pair of clips on EACH side, so the
## sight goes on the left for a right-handed player and on the right for a
## left-handed one, as the manual has it.
##
## Its frame is the clip's: the origin is where the bracket meets the barrel, +Y
## up, -Z toward the muzzle. The identity grab point seats it at either of the
## scope's SightClip zones (SuperScope), which stand where the clips are.
##
## Cosmetic: the game is told where the BARREL points, as with every gun here,
## whether the sight is on or not. Pose only, as the Virtual Boy's pack is:
## which clip it is on is saved on the SCOPE ("sight").
class_name SuperScopeSight
extends XRToolsPickable


## Every sight is in this group; the scope's clips take nothing else.
const GROUP := "super_scope_sight"
## The save type (ScenePersistence.PLAIN_SCENES).
const SAVE_TYPE := "super_scope_sight"

## The tube, the eyepiece and the bracket, metres. The tube's length is the
## photograph's (about 0.21 of the 61 cm gun); the rest are estimates.
const TUBE_RADIUS := 0.0135
const TUBE_LENGTH := 0.120
const EYE_RADIUS := 0.0165
const EYE_LENGTH := 0.028
## How far above the clip the tube's axis stands, and how far behind it the
## tube's middle is (the eyepiece end overhangs toward the player).
const TUBE_RISE := 0.048
const TUBE_BACK := 0.020
const BRACKET := Vector3(0.012, 0.040, 0.110)

const GREY := Color(0.47, 0.48, 0.5)
const BLACK := Color(0.06, 0.06, 0.065)


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	add_to_group(GROUP)
	_build()


func save_type() -> String:
	return SAVE_TYPE


## The middle of the eyepiece's open end, in this frame: what a probe looks
## through.
static func eye_point() -> Vector3:
	return Vector3(0.0, TUBE_RISE, TUBE_BACK + TUBE_LENGTH * 0.5 + EYE_LENGTH)


func _build() -> void:
	var grey := _mat(GREY, 0.55)
	var black := _mat(BLACK, 0.85)
	# Along Z: a cylinder stands along +Y, so it is laid down by R_x(90).
	var lay := Basis(Vector3.RIGHT, PI * 0.5)
	_cyl("Tube", TUBE_RADIUS, TUBE_LENGTH, Transform3D(lay, Vector3(0.0, TUBE_RISE, TUBE_BACK)), grey)
	_cyl("Eyepiece", EYE_RADIUS, EYE_LENGTH, Transform3D(lay,
		Vector3(0.0, TUBE_RISE, TUBE_BACK + (TUBE_LENGTH + EYE_LENGTH) * 0.5)), black)
	# The open end of the eyepiece: a dark disc a hair inside it.
	_cyl("EyeHole", EYE_RADIUS * 0.6, 0.001, Transform3D(lay, eye_point() - Vector3(0, 0, 0.0008)), _mat(Color.BLACK, 1.0))
	_box("Bracket", BRACKET, Vector3(0.0, TUBE_RISE * 0.5 - 0.004, TUBE_BACK * 0.5), grey)
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(EYE_RADIUS * 2.0, TUBE_RISE + TUBE_RADIUS, TUBE_LENGTH + EYE_LENGTH)
		col.shape = box
		col.position = Vector3(0.0, (TUBE_RISE + TUBE_RADIUS) * 0.5, TUBE_BACK + EYE_LENGTH * 0.5)


func _cyl(node_name: String, radius: float, height: float, xform: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 20
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat
	add_child(mi)
	mi.transform = xform
	return mi


func _box(node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	mi.position = at
	return mi


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
