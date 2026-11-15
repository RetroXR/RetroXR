## ArcadeToken — a RETRO XR arcade token as a loose thing: the ones a cash box holds and spills (ArcadeCabinetFromModel), picked up
## by a hand or the desktop pointer like any small object, and put into a coin slot by pushing it through the slot's mouth
## (ArcadeCoinSlot), where it goes in as a coin does (the owner, 2026-11-15: "can you put a physical coin in coin slots").
## Built in code: the token's mesh (ArcadeCoinModule.token_mesh), a coin's disc to physics, its rim beveled to an edge.
class_name ArcadeToken
extends XRToolsPickable

const GROUP := &"arcade_token"
## A disc thicker to physics than the token is to the eye: a 2 mm disc jitters on a floor and slips through thin sheet.
const DISC_HEIGHT := 0.003
## How far in from the rim each face starts: the rim comes to an edge round the disc's middle. A square rim (a cylinder) is a
## band DISC_HEIGHT wide that a token stood on, steady up to 7 degrees off upright; on an edge it stands only balanced, and
## anything off upright falls flat. Deeper bevels (1 mm and more) make facets a token rests on half over.
const RIM_BEVEL := 0.0006
const MASS := 0.008
## Its inertia, as a multiple of a real 8 g disc's (m r^2 / 4 across, m r^2 / 2 about its axis). Jolt cannot invert one that
## small (a product of the moments under about 1e-19) and quietly gives the body a metre ball's instead (0.4 m: some 10,000
## times too much), so a token never turned under its own weight: let go at a slant it landed on its rim and stayed there,
## standing (measured 2026-11-15: from 30, 60 and 90 degrees it stayed at 30, 60 and 90). Twice a real one's clears it with
## room to spare (1.5 times is the least that does) and every slant then falls flat.
const INERTIA_SCALE := 2.0


static func make(at: Transform3D, parent: Node) -> ArcadeToken:
	var token := ArcadeToken.new()
	token.name = "ArcadeToken"
	token.collision_layer = 4
	token.collision_mask = 1 | 4
	token.mass = MASS
	var r2 := ArcadeCoinModule.COIN_RADIUS * ArcadeCoinModule.COIN_RADIUS
	token.inertia = Vector3(0.25, 0.5, 0.25) * MASS * r2 * INERTIA_SCALE
	token.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.15
	token.physics_material_override = pm
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = disc_shape()
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


## A token come to rest standing on its rim, near enough upright (its face's normal within this of level), is given a
## nudge to tip it over: let go exactly on edge, even on its beveled rim it balanced there and went to sleep standing.
const STANDING_UP_Y := 0.25
## How hard each nudge is (an angular impulse, N m s: about 0.025 rad/s to the token), and the most a token gets before
## it is left be (one leaning on a wall, held up by it), until it is picked up and let go again.
const NUDGE := 2.0e-8
const MAX_NUDGES := 40

var _nudges := 0


static var _disc: ConvexPolygonShape3D = null


## The token in a hand nearest `at`, or null.
static func held_near(tree: SceneTree, at: Vector3) -> ArcadeToken:
	var best: ArcadeToken = null
	var best_d := INF
	for n in tree.get_nodes_in_group(GROUP):
		var t := n as ArcadeToken
		if t == null or t.is_queued_for_deletion() or not t.is_picked_up():
			continue
		var d := t.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = t
	return best


## The physics disc, one shared by every token: a ring of points at the rim on its middle plane, and each face's ring
## RIM_BEVEL in.
static func disc_shape() -> ConvexPolygonShape3D:
	if _disc == null:
		var pts := PackedVector3Array()
		var r := ArcadeCoinModule.COIN_RADIUS
		var half := Vector3(0.0, DISC_HEIGHT * 0.5, 0.0)
		for i in 32:
			var a := TAU * i / 32.0
			var c := Vector3(cos(a), 0.0, sin(a))
			pts.append(c * r)
			pts.append(c * (r - RIM_BEVEL) + half)
			pts.append(c * (r - RIM_BEVEL) - half)
		_disc = ConvexPolygonShape3D.new()
		_disc.points = pts
	return _disc


func _ready() -> void:
	super()
	add_to_group(GROUP)
	dropped.connect(func(_p: Variant) -> void: _nudges = 0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _nudges >= MAX_NUDGES:
		return
	var face := state.transform.basis.y.normalized()
	if absf(face.y) > STANDING_UP_Y or state.linear_velocity.length_squared() > 0.0004 			or state.angular_velocity.length_squared() > 0.25:
		return
	# Turn the face's normal up toward whichever way it already leans (either, exactly on edge).
	if face.y < 0.0:
		face = -face
	var axis := face.cross(Vector3.UP)
	if axis.length_squared() < 1e-8:
		return
	state.apply_torque_impulse(axis.normalized() * NUDGE)
	_nudges += 1
