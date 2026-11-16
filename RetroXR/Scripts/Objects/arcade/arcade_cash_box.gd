## ArcadeCashBox — a generated (morphing) cabinet's cash box: an open metal tray in a vault behind its coin doors, directly under
## the slots as on a real upright, that every coin a player puts in drops into as a token (the owner, 2026-11-17: "add the same
## coin logic and an area for coins to go with a coin tray for the morphing cabinet"; then, asked whether the tray was in a good
## place, "Yes" to moving it there: at the back of the bay it was far from the slots and behind the board).
##
## The coin doors stand on one panel hinged on its left edge (CoinPanel); swung open, the vault behind it is open and the tray
## stands on its floor. Its handle is a strip at the panel's right edge, so the slots and the returns on it are aimed at as
## before; shut, a slab behind it keeps a pointer from reaching the tray through it. The vault's room is cut out of the cabinet's
## collision and pointer boxes (RetroSystemModelArcadeCabinet.CASH_VAULT_META).
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
## The panel past the outer coin doors' middles each side, its bottom and top (above the bay's top, under the deck's lip), and
## its thickness; the vault's depth behind it and its walls' inset.
const PANEL_MARGIN := 0.085
const PANEL_Y := Vector2(0.515, 0.775)
const PANEL_T := 0.012
const VAULT_DEPTH := 0.20
const VAULT_WALL := 0.004
const OPEN_DEG := 100.0

var _vault: Node3D = null
var _tray: MeshInstance3D = null
var _panel_axis: Node3D = null
var _panel_turn: Node3D = null
var _pointer_slab: CollisionShape3D = null
## The box last seated in the vault (kept as the slot lets go of it on its way out of the tree).
var _seated: PortCover = null


func _ready() -> void:
	# (no model to build: only the cash box, which setup makes)
	set_physics_process(true)


## Build (again, after a morph: the coin doors are the form's) the panel and the vault behind `coins`, and the tray in it once.
func setup(cabinet: Node3D, coins: Array) -> void:
	var doors: Array[Node3D] = []
	for c in coins:
		if is_instance_valid(c) and (c as Node3D).is_inside_tree():
			doors.append(c as Node3D)
	if doors.is_empty():
		return
	var x0 := INF
	var x1 := -INF
	var face := -INF
	for d in doors:
		var at := cabinet.to_local(d.global_position)
		x0 = minf(x0, at.x)
		x1 = maxf(x1, at.x)
		face = maxf(face, at.z)
	x0 -= PANEL_MARGIN
	x1 += PANEL_MARGIN
	if _vault == null:
		_vault = Node3D.new()
		_vault.name = "CashVault"
		cabinet.add_child(_vault)
	# the vault's frame: its origin on the panel's back face, at the bottom, across the middle
	_vault.position = Vector3((x0 + x1) * 0.5, PANEL_Y.x, face - PANEL_T)
	var w := x1 - x0
	var h := PANEL_Y.y - PANEL_Y.x
	_open_face(cabinet, x0, x1)
	# (a deep deck's coin doors stood forward on blocks: the panel stands there now, the blocks would fill the vault)
	for blk in cabinet.find_children("CoinDoorBlock*", "MeshInstance3D", true, false):
		(blk as Node3D).visible = false
	_build_walls(w, h)
	_build_coin_panel(cabinet, doors, w, h)
	if _tray == null:
		_tray = MeshInstance3D.new()
		_tray.name = CASH_BOX
		_tray.mesh = tray_mesh(TRAY)
		_tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vault.add_child(_tray)
		_tray.position = Vector3(0.0, VAULT_WALL + 0.001, -VAULT_DEPTH * 0.5)
		_make_slot.call_deferred(_tray)
	# the vault's room out of the cabinet's collision and pointer boxes
	var room := AABB(_vault.position + Vector3(-w * 0.5, 0.0, -VAULT_DEPTH), Vector3(w, h, VAULT_DEPTH + PANEL_T + 0.01))
	cabinet.set_meta(RetroSystemModelArcadeCabinet.CASH_VAULT_META, room)
	var host := cabinet.get_parent() as Node3D
	if host != null and cabinet.has_method("configure_collision"):
		cabinet.call_deferred("configure_collision", host)
		_add_pointer_slab.call_deferred(host, room)


## The coin face (the builder's CoinFace: the front between the bay's door and the control panel) with the panel's opening in
## it: the face hidden, four strips of it round the opening in its place (beside the face, so a morph that builds another face
## takes them with the old one).
func _open_face(cabinet: Node3D, x0: float, x1: float) -> void:
	var face := cabinet.find_child("CoinFace", true, false) as MeshInstance3D
	if face == null or not face.mesh is BoxMesh:
		return
	var parent := face.get_parent() as Node3D
	for c in parent.get_children():
		if str(c.name).begins_with("CoinFaceAround"):
			parent.remove_child(c)
			c.queue_free()
	face.visible = false
	var fs := (face.mesh as BoxMesh).size
	var fc := face.position
	var fx0 := fc.x - fs.x * 0.5
	var fx1 := fc.x + fs.x * 0.5
	var fy0 := fc.y - fs.y * 0.5
	var fy1 := fc.y + fs.y * 0.5
	var mat := face.get_active_material(0)
	# (left, right, below, above), each [x0, x1, y0, y1] in the face's parent's frame
	for r: Array in [[fx0, x0, fy0, fy1], [x1, fx1, fy0, fy1], [x0, x1, fy0, PANEL_Y.x], [x0, x1, PANEL_Y.y, fy1]]:
		if r[1] - r[0] <= 0.0005 or r[3] - r[2] <= 0.0005:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "CoinFaceAround"
		var bm := BoxMesh.new()
		bm.size = Vector3(r[1] - r[0], r[3] - r[2], fs.z)
		mi.mesh = bm
		mi.material_override = mat
		parent.add_child(mi)
		mi.position = Vector3((r[0] + r[1]) * 0.5, (r[2] + r[3]) * 0.5, fc.z)


## The vault's lining: back, sides, floor and top, dark sheet.
func _build_walls(w: float, h: float) -> void:
	for c in _vault.get_children():
		if str(c.name).begins_with("VaultWall"):
			_vault.remove_child(c)
			c.queue_free()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.07, 0.08)
	dark.roughness = 0.8
	var t := VAULT_WALL
	var d := VAULT_DEPTH
	for spec: Array in [[Vector3(w, h, t), Vector3(0, h * 0.5, -d + t * 0.5)], [Vector3(t, h, d), Vector3(-w * 0.5 + t * 0.5, h * 0.5, -d * 0.5)],
			[Vector3(t, h, d), Vector3(w * 0.5 - t * 0.5, h * 0.5, -d * 0.5)], [Vector3(w, t, d), Vector3(0, t * 0.5, -d * 0.5)],
			[Vector3(w, t, d), Vector3(0, h - t * 0.5, -d * 0.5)]]:
		var mi := MeshInstance3D.new()
		mi.name = "VaultWall"
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = dark
		_vault.add_child(mi)
		mi.position = spec[1]


## The panel the coin doors stand on, hinged on its left edge, its handle a strip at its right.
func _build_coin_panel(cabinet: Node3D, doors: Array[Node3D], w: float, h: float) -> void:
	if _panel_axis == null:
		_panel_axis = Node3D.new()
		_panel_axis.name = "CoinPanelAxis"
		_vault.add_child(_panel_axis)
		# VRHinge turns its target about the target's own X: X down the hinge (-Y: the left edge opens outward at + angles)
		_panel_axis.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(-w * 0.5, 0.0, 0.0))
		_panel_turn = Node3D.new()
		_panel_turn.name = "CoinPanel"
		_panel_axis.add_child(_panel_turn)
	else:
		_panel_axis.position = Vector3(-w * 0.5, 0.0, 0.0)
		for c in _panel_turn.get_children():
			if not c is ArcadeCoinModule:
				_panel_turn.remove_child(c)
				c.queue_free()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.13, 0.13, 0.15)
	body.metallic = 0.4
	body.roughness = 0.45
	var plate := MeshInstance3D.new()
	plate.name = "PanelPlate"
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, PANEL_T)
	plate.mesh = bm
	plate.material_override = body
	_panel_turn.add_child(plate)
	plate.global_transform = _vault.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, PANEL_T * 0.5))
	var handle := MeshInstance3D.new()
	handle.name = "PanelHandle"
	var hm := BoxMesh.new()
	hm.size = Vector3(0.016, 0.08, 0.014)
	handle.mesh = hm
	handle.material_override = steel()
	_panel_turn.add_child(handle)
	handle.global_transform = _vault.global_transform * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 0.022, h * 0.5, PANEL_T + 0.007))
	# the coin doors go with the panel
	for d in doors:
		if d.get_parent() != _panel_turn:
			d.reparent(_panel_turn, true)
	var grab := Area3D.new()
	grab.name = "CoinPanelGrab"
	grab.set_script(load(SCRIPT_HINGE))
	grab.collision_layer = 0
	grab.collision_mask = 0
	grab.set("engage_radius", 0.10)
	grab.set("target", _panel_turn)
	grab.set("min_deg", 0.0)
	grab.set("max_deg", OPEN_DEG)
	grab.set("grip_engages", true)
	grab.set("box_engages", true)
	_panel_turn.add_child(grab)
	grab.global_transform = _vault.global_transform * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 0.022, h * 0.5, PANEL_T + 0.01))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.04, h * 0.8, 0.03)
	col.shape = shape
	grab.add_child(col)


## A slab behind the shut panel in the cabinet's pointer area, so a pointer at the panel finds the cabinet, not the tray.
func _add_pointer_slab(host: Node3D, room: AABB) -> void:
	var area := host.find_child("PointerArea", true, false) as Node3D
	if area == null:
		return
	if is_instance_valid(_pointer_slab):
		_pointer_slab.queue_free()
	_pointer_slab = CollisionShape3D.new()
	_pointer_slab.name = "PointerCashPanel"
	var slab := BoxShape3D.new()
	slab.size = Vector3(room.size.x, room.size.y, 0.02)
	_pointer_slab.shape = slab
	area.add_child(_pointer_slab)
	var cab := get_parent() as Node3D
	_pointer_slab.global_position = cab.to_global(Vector3(room.get_center().x, room.get_center().y, room.end.z - PANEL_T - 0.015))


## Shut (within a few degrees), the slab stands; open, it is gone, and a token lying in a return cup (held still there, the
## cup's) drops: the cup has swung away with the panel.
var _was_open := false


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_panel_turn):
		return
	var open := absf(_panel_turn.rotation.x) >= deg_to_rad(4.0)
	if is_instance_valid(_pointer_slab) and _pointer_slab.disabled != open:
		_pointer_slab.disabled = open
	if open and not _was_open:
		for c in _panel_turn.get_children():
			if c is ArcadeCoinModule:
				for t: Variant in (c as Node).get("_cup_tokens"):
					if is_instance_valid(t) and (t as RigidBody3D).freeze:
						(t as RigidBody3D).freeze = false
						(t as RigidBody3D).sleeping = false
	_was_open = open


## The cabinet going (deleted, or the room cleared): the tray in its vault goes with it, and the coins in that tray. Left, it was
## a loose box where the cabinet had stood, inside the next one put there.
func _exit_tree() -> void:
	# (the slot has let go of it on its own way out by now: the box last seated is remembered)
	var box := _seated as Node
	if box == null or not is_instance_valid(box) or box.is_queued_for_deletion():
		return
	if (box as XRToolsPickable).is_picked_up() and not (box as XRToolsPickable).get_picked_up_by() is XRToolsSnapZone:
		return
	var state := _cash_state(box as PortCover)
	if state != null:
		for t: Variant in state.get("tokens"):
			if is_instance_valid(t):
				(t as Node).queue_free()
	box.queue_free()


func _forget_seated() -> void:
	if is_instance_valid(_cash_zone) and _cash_zone.picked_up_object == null:
		_seated = null


## Whether the coin panel is open (the vault reachable).
func is_open() -> bool:
	return is_instance_valid(_panel_turn) and absf(_panel_turn.rotation.x) >= deg_to_rad(4.0)


func _make_slot(part: MeshInstance3D) -> void:
	if not is_instance_valid(part) or not part.is_inside_tree():
		return
	var out := LIFT_OFF_OUT
	var zone := CoverSlots.shell_cover(part, SOCKET, out)
	if zone == null:
		return
	_loose_lift_offs[SOCKET] = [part, out]
	zone.has_picked_up.connect(_dress_lift_off.bind(part, out))
	# Seated, the tray is part of the machine: it and the cabinet do not collide (its floor and walls, solid to its coins, stood
	# against the vault's sides and turned a cabinet let go leaning off its feet); taken out, it is a thing in the room again.
	var host := CoverSlots.host_of(part) as PhysicsBody3D
	if host != null:
		zone.has_picked_up.connect(func(b: Node3D) -> void:
			_seated = b as PortCover
			if b is PhysicsBody3D:
				(b as PhysicsBody3D).add_collision_exception_with(host))
		zone.has_dropped.connect(func() -> void:
			# forgotten a moment later: on the cabinet's way out the slot lets go first, and _exit_tree still needs it
			_forget_seated.call_deferred()
			for b in host.get_collision_exceptions():
				if b is PortCover and (b as PortCover).socket_id == SOCKET:
					host.remove_collision_exception_with(b))
	_cash_zone = zone
	_cash_source = part
	if zone.picked_up_object != null:
		_seated = zone.picked_up_object as PortCover
		_dress_lift_off(zone.picked_up_object, part, out)
		if host != null and zone.picked_up_object is PhysicsBody3D:
			(zone.picked_up_object as PhysicsBody3D).add_collision_exception_with(host)
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
