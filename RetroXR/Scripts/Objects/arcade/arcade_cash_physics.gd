## Keep the tray solid to loose coins while XRTools makes held objects intangible.
## A synchronized kinematic shell carries contacts; coins move, sleep and spill through Jolt.
## Lives on the box, including when it is removed from or swapped between cabinets.
extends Node

var _box: XRToolsPickable
const COUNT_META := &"cash_coins"
const LIMIT := 60
var tokens: Array[RigidBody3D] = []
var _tray: MeshInstance3D
var _inner: AABB
var _restored := false
var _watch_time := 0.0
var _arriving: Dictionary = {}
var _guard: AnimatableBody3D
var _guard_shapes: Array[CollisionShape3D] = []
var _last_tray := Transform3D.IDENTITY
var _thickness := -1.0
var _peak_travel := 0.0
var _travel_hold := 0
var _follow := Transform3D.IDENTITY
var _follow_v := Vector3.ZERO
var _follow_w := Vector3.ZERO
const FOLLOW_TAU := 0.03
const MAX_CARRY_SPEED := 3.0
const MAX_CARRY_TURN := 12.0


func _ready() -> void:
	_box = get_parent() as XRToolsPickable
	_follow = _box.global_transform
	process_physics_priority = 100
	_box.picked_up.connect(_held)
	_sync()


func _held(_what: Node3D) -> void:
	_sync()


func _physics_process(delta: float) -> void:
	_follow_hand(delta)
	_sync()
	for token in tokens:
		if is_instance_valid(token):
			token.continuous_cd = not _box.freeze
	_watch_time += delta
	if _watch_time >= 0.25:
		_watch_time = 0.0
		watch()


## Smooth the BOX on physics ticks, not its contents. Render-rate hand poses
## otherwise jump the collision wall through a coin between solver steps.
## Snap zones retain their exact seating pose; a released box is fully dynamic.
func _follow_hand(delta: float) -> void:
	var by := _box.get_picked_up_by()
	var moving := _box.freeze and (_box.collision_layer & 4) == 0 and not by is XRToolsSnapZone
	var want := _box.global_transform
	if not moving:
		_follow = want
		_follow_v = Vector3.ZERO
		_follow_w = Vector3.ZERO
		return
	var w := 1.0 / FOLLOW_TAU
	_follow_v += ((want.origin - _follow.origin) * w*w - _follow_v * 2*w) * delta
	_follow_v = _follow_v.limit_length(MAX_CARRY_SPEED)
	_follow.origin += _follow_v * delta
	var turn := want.basis.orthonormalized().get_rotation_quaternion() * _follow.basis.orthonormalized().get_rotation_quaternion().inverse()
	if turn.w < 0:
		turn = -turn
	var angle := turn.get_angle()
	var error := turn.get_axis() * angle if angle > 0.00001 else Vector3.ZERO
	_follow_w += (error * w*w - _follow_w * 2*w) * delta
	_follow_w = _follow_w.limit_length(MAX_CARRY_TURN)
	if _follow_w.length() > 0.00001:
		_follow.basis = Basis(_follow_w.normalized(), _follow_w.length() * delta) * _follow.basis
	_follow.basis = _follow.basis.orthonormalized().scaled(want.basis.get_scale())
	_box.global_transform = _follow
	_box.force_update_transform()


func _sync() -> void:
	# Ray grabs do not emit the body's picked_up, so also check after the drivers.
	# Held tokens have mask 0: another hand can take one out freely.
	_box.collision_layer &= ~ArcadeToken.TRAY_LAYER
	if not is_instance_valid(_guard) or not is_instance_valid(_tray):
		return
	var at := _tray.global_transform
	var travel := 0.0
	var bounds := _tray.mesh.get_aabb()
	for i in 8:
		var corner := bounds.get_endpoint(i)
		travel = maxf(travel, (at * corner).distance_to(_last_tray * corner))
	_last_tray = at
	# Render-rate hand updates can alternate a jump with an unchanged physics
	# tick. Keep the contact backing while the solver finishes that jump.
	if travel >= _peak_travel:
		_peak_travel = travel
		_travel_hold = 5
	elif _travel_hold > 0:
		_travel_hold -= 1
	else:
		_peak_travel = maxf(travel, _peak_travel * 0.8)
	var held := _box.freeze and (_box.collision_layer & 4) == 0
	_guard.collision_layer = ArcadeToken.TRAY_LAYER if held else 0
	if held:
		# A kinematic wall can cross a whole coin between ticks. Extend only the
		# OUTSIDE of its coin-only collider, enough that the inner contact face
		# remains the nearest face after the move. Never change a coin's pose or
		# velocity, and never add a lid. Other room objects use the normal shell.
		_guard_wall(maxf(0.02, _peak_travel * 4.0 + ArcadeToken.DISC_HEIGHT * 2.0))
	_guard.global_transform = _box.global_transform
	_guard.force_update_transform()
	if held:
		# sync_to_physics returns the completed solver pose. Draw the box there
		# too, rather than a tick ahead of the coins (visible floor penetration).
		_box.global_transform = _guard.global_transform
		_box.force_update_transform()


func coin_layer_active() -> bool:
	return is_instance_valid(_guard) and _guard.collision_layer != 0


func _guard_wall(thickness: float) -> void:
	var t := snappedf(thickness + 0.0025, 0.005)
	if is_equal_approx(t, _thickness):
		return
	_thickness = t
	var b := _tray.mesh.get_aabb()
	var lo := b.position + Vector3.ONE * ArcadeCabinetFromModel.CASH_SHEET
	var hi := b.end - Vector3(ArcadeCabinetFromModel.CASH_SHEET, 0.0, ArcadeCabinetFromModel.CASH_PULL + ArcadeCabinetFromModel.CASH_SHEET)
	var parts := [
		AABB(Vector3(lo.x - t, lo.y - t, lo.z - t), Vector3(hi.x - lo.x + 2*t, t, hi.z - lo.z + 2*t)),
		AABB(Vector3(lo.x - t, lo.y - t, lo.z - t), Vector3(hi.x - lo.x + 2*t, hi.y - lo.y + t, t)),
		AABB(Vector3(lo.x - t, lo.y - t, hi.z), Vector3(hi.x - lo.x + 2*t, hi.y - lo.y + t, t)),
		AABB(Vector3(lo.x - t, lo.y - t, lo.z - t), Vector3(t, hi.y - lo.y + t, hi.z - lo.z + 2*t)),
		AABB(Vector3(hi.x, lo.y - t, lo.z - t), Vector3(t, hi.y - lo.y + t, hi.z - lo.z + 2*t))]
	var local := _box.global_transform.affine_inverse() * _tray.global_transform
	for i in 5:
		(_guard_shapes[i].shape as BoxShape3D).size = (parts[i] as AABB).size
		_guard_shapes[i].transform = Transform3D(local.basis, local * (parts[i] as AABB).get_center())


func configure(tray: MeshInstance3D, inner: AABB) -> void:
	_tray = tray
	_inner = inner
	# brushed sheet steel, not a flat gray (ArcadeCashBox.steel)
	tray.material_override = ArcadeCashBox.steel()
	if _guard == null:
		_guard = AnimatableBody3D.new()
		_guard.name = "CashCoinCollider"
		_guard.top_level = true
		_guard.sync_to_physics = true
		_guard.transform = _box.global_transform
		_guard.collision_layer = 0
		_guard.collision_mask = 0
		_guard.physics_material_override = _box.physics_material_override
		for i in 5:
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			_guard.add_child(shape)
			_guard_shapes.append(shape)
		_box.add_child(_guard)
		_last_tray = _tray.global_transform
		_guard_wall(0.02)
		_sync()


func _exit_tree() -> void:
	for token in tokens:
		if is_instance_valid(token):
			token.continuous_cd = true
	if is_instance_valid(_guard):
		_guard.queue_free()


func restore(places: Array[Transform3D]) -> void:
	if _restored or not is_instance_valid(_tray):
		return
	_restored = true
	for place in places:
		_spawn(_tray.global_transform * place)


func _spawn(at: Transform3D) -> void:
	var room := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var token := ArcadeToken.make(at, room)
	token.continuous_cd = not _box.freeze
	tokens.append(token)
	_arriving[token.get_instance_id()] = Engine.get_physics_frames() + 45


func bank() -> void:
	if not is_instance_valid(_tray):
		return
	watch()
	if tokens.size() < LIMIT:
		_spawn(ArcadeCabinetFromModel._cash_drop_pose(_tray))
	_box.set_meta(COUNT_META, int(_box.get_meta(COUNT_META, 0)) + 1)


func unbank() -> void:
	watch()
	var count := int(_box.get_meta(COUNT_META, 0))
	# Past the physical cap, refund the banked overflow before removing a body.
	if count <= tokens.size() and not tokens.is_empty():
		var token: RigidBody3D = tokens.pop_back()
		_arriving.erase(token.get_instance_id())
		token.queue_free()
	_box.set_meta(COUNT_META, maxi(count - 1, 0))


func watch() -> void:
	if not _restored or not is_instance_valid(_tray):
		return
	# During a fast carry a contact may be inside the outward collision backing
	# while Jolt resolves it. Do not discard it (and re-enable CCD) mid-contact.
	var margin := maxf(0.01, _thickness + ArcadeCoinModule.COIN_RADIUS) if coin_layer_active() else 0.01
	var inside := _tray.mesh.get_aabb().grow(margin)
	var kept: Array[RigidBody3D] = []
	for token in tokens:
		if not is_instance_valid(token) or token.is_queued_for_deletion():
			continue
		var id := token.get_instance_id()
		if inside.has_point(_tray.to_local(token.global_position)) or Engine.get_physics_frames() < int(_arriving.get(id, 0)):
			kept.append(token)
		else:
			_arriving.erase(id)
			token.continuous_cd = true
	var lost := tokens.size() - kept.size()
	tokens = kept
	if lost > 0:
		_box.set_meta(COUNT_META, maxi(int(_box.get_meta(COUNT_META, 0)) - lost, tokens.size()))
