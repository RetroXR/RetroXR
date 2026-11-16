## ArcadeCashBox — a generated (morphing) cabinet's cash box: an open metal tray standing at the front of its bay, behind the
## bay's drop-down door, that every coin a player puts in drops into as a token (the owner, 2026-11-17: "add the same coin logic
## and an area for coins to go with a coin tray for the morphing cabinet").
##
## It is the model cabinets' cash box, the same code: an ArcadeCabinetFromModel that builds nothing but its CashBoxLiftOff, so
## the tray is a cover in a slot of its own (taken out, carried with its coins, put back, saved with its count), its coins are
## the box's (ArcadeCashPhysics), a coin given back leaves it, and a loose one a load brings back is dressed as the tray. Its
## socket is its own (SOCKET): a model cabinet's box and this one never dress as each other.
class_name ArcadeCashBox
extends ArcadeCabinetFromModel

const SOCKET := "cabinet_generic_cash_box"
## The tray, metres: across, tall, front to back (its pull across the front's top the last CASH_PULL of it).
const TRAY := Vector3(0.17, 0.10, 0.13)
## Clear of the bay's left and back walls by this much.
const CLEAR := 0.02


func _ready() -> void:
	# (no model to build: only the cash box, which setup makes)
	pass


## Make the tray on the bay's floor at its back left (the board stands in the middle, the service switches at the front left,
## the power switch at the front right and the power supply at the back right), and its slot once the cabinet is in its machine.
func setup(bay: Node3D) -> void:
	var floor_mesh := bay.get_node_or_null("BayFloor") as MeshInstance3D
	if floor_mesh == null or not floor_mesh.mesh is BoxMesh:
		return
	var floor_size := (floor_mesh.mesh as BoxMesh).size
	var floor_top := floor_mesh.position.y + floor_size.y * 0.5
	var part := MeshInstance3D.new()
	part.name = CASH_BOX
	part.mesh = tray_mesh(TRAY)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bay.add_child(part)
	var back := floor_mesh.position.z - floor_size.z * 0.5
	part.position = Vector3(-floor_size.x * 0.5 + CLEAR + TRAY.x * 0.5, floor_top + 0.001, back + CLEAR + TRAY.z * 0.5)
	_make_slot.call_deferred(part)


func _make_slot(part: MeshInstance3D) -> void:
	if not is_instance_valid(part) or not part.is_inside_tree():
		return
	var out := LIFT_OFF_OUT
	var zone := CoverSlots.shell_cover(part, SOCKET, out)
	if zone == null:
		return
	_loose_lift_offs[SOCKET] = [part, out]
	zone.has_picked_up.connect(_dress_lift_off.bind(part, out))
	_cash_zone = zone
	_cash_source = part
	if zone.picked_up_object != null:
		_dress_lift_off(zone.picked_up_object, part, out)
	for c in get_tree().get_nodes_in_group(PortCover.group_for(SOCKET)):
		_dress_loose(c)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## A coin door of the cabinet: its coins go into the box, and one it gives back comes out of it.
func take_coins(coin: ArcadeCoinModule) -> void:
	if not coin.coin_inserted.is_connected(_bank_coin):
		coin.coin_inserted.connect(_bank_coin)
	if not coin.coin_returned.is_connected(_unbank_coin):
		coin.coin_returned.connect(_unbank_coin)


static var _steel: StandardMaterial3D = null


## A cash box's sheet steel, brushed (the owner, 2026-11-17: "give the coin box a material, it looks so flat"): galvanized gray,
## metallic, its roughness and its normal a noise stretched one way into fine streaks, laid on every face at one scale
## (triplanar). One shared by every cash box, the model cabinets' too (ArcadeCashPhysics.configure wears it on the tray).
static func steel() -> StandardMaterial3D:
	if _steel != null:
		return _steel
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	grain.frequency = 0.08
	grain.fractal_octaves = 3
	var rough := NoiseTexture2D.new()
	rough.noise = grain
	rough.width = 256
	rough.height = 8
	rough.seamless = true
	var bump := NoiseTexture2D.new()
	bump.noise = grain
	bump.width = 256
	bump.height = 8
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 1.6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.60, 0.62, 0.65)
	m.metallic = 0.72
	m.roughness = 0.55
	m.roughness_texture = rough
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = bump
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(12.0, 12.0, 12.0)
	_steel = m
	return m


## An open tray of 1.5 mm sheet in its own frame, its middle at the origin's x and z and its floor at y 0: the floor, four walls
## and a pull (a lip) across the top of its front. Pure.
static func tray_mesh(size: Vector3) -> ArrayMesh:
	var mat := steel()
	var t := CASH_SHEET
	var front := size.z * 0.5 - CASH_PULL
	var back := -size.z * 0.5
	var d := front - back
	var zc := (front + back) * 0.5
	var parts := [
		AABB(Vector3(-size.x * 0.5, 0.0, back), Vector3(size.x, t, d)),
		AABB(Vector3(-size.x * 0.5, 0.0, back), Vector3(size.x, size.y, t)),
		AABB(Vector3(-size.x * 0.5, 0.0, front - t), Vector3(size.x, size.y, t)),
		AABB(Vector3(-size.x * 0.5, 0.0, back), Vector3(t, size.y, d)),
		AABB(Vector3(size.x * 0.5 - t, 0.0, back), Vector3(t, size.y, d)),
		# the pull: a lip across the front's top, the box's last CASH_PULL
		AABB(Vector3(-size.x * 0.25, size.y - 0.004, front), Vector3(size.x * 0.5, 0.004, CASH_PULL)),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: AABB in parts:
		var bm := BoxMesh.new()
		bm.size = b.size
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, b.get_center()))
	st.set_material(mat)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh
