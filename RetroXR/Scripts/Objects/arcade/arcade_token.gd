## ArcadeToken — a RETRO XR arcade token as a loose thing: the ones a cash box holds and spills (ArcadeCabinetFromModel), picked up
## by a hand or the desktop pointer like any small object, and put into a coin slot by pushing it through the slot's mouth
## (ArcadeCoinSlot), where it goes in as a coin does (the owner, 2026-11-15: "can you put a physical coin in coin slots").
## Built in code: the token's mesh (ArcadeCoinModule.token_mesh), a coin's disc to physics.
class_name ArcadeToken
extends XRToolsPickable

const GROUP := &"arcade_token"
## A disc thicker to physics than the token is to the eye: a 2 mm disc jitters on a floor and slips through thin sheet.
const DISC_HEIGHT := 0.003


static func make(at: Transform3D, parent: Node) -> ArcadeToken:
	var token := ArcadeToken.new()
	token.name = "ArcadeToken"
	token.collision_layer = 4
	token.collision_mask = 1 | 4
	token.mass = 0.008
	token.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.15
	token.physics_material_override = pm
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var disc := CylinderShape3D.new()
	disc.radius = ArcadeCoinModule.COIN_RADIUS
	disc.height = DISC_HEIGHT
	col.shape = disc
	token.add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = ArcadeCoinModule.token_mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	token.add_child(mesh)
	var highlight := Node3D.new()
	highlight.name = "PickableHighlight"
	highlight.set_script(load("res://Scripts/Objects/highlights/pickable_highlight.gd"))
	token.add_child(highlight)
	parent.add_child(token)
	token.global_transform = at
	return token


func _ready() -> void:
	super()
	add_to_group(GROUP)
