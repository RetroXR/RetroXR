## Keep the tray solid to loose coins while XRTools makes held objects intangible.
## A kinematic coin-only shell carries contacts; coins move, sleep and spill through Jolt.
## Lives on the box, including when it is removed from or swapped between cabinets.
##
## THE BOX IS NEVER MOVED FROM HERE. It is wherever its hand, ray or slot put it, at full speed, as any held thing is. What may
## lag is the shell (_guard), which nobody sees: it follows the box (eased and capped while the box is carried, so a wall never
## crosses a coin between two steps; exactly, while it is seated), and each coin in it is DRAWN at the place in the drawn tray
## that its body has in the shell (_draw_coins). Until 2026-11-17 the box itself was eased and then redrawn at the shell's
## pose, which is one tick old: the box's pose was both what the shell was sent to and what came back from it a tick later.
## Seated, nothing else wrote the box (a grab driver at rest writes nothing), so its last two poses traded places for ever
## (the owner: "jumping up in to the cabinet in an odd area and then back down every other frame"), and its coins were thrown
## by a floor that jumped with it. Carried, it trailed the hand (30 ms, 3 m/s at most) and the ray.
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
## How the box is held. LOOSE: its own walls hold its coins. CARRIED (a hand, a ray) and SEATED (a snap zone): the shell does.
enum Mode { LOOSE, CARRIED, SEATED }
var _mode := Mode.LOOSE
## Where the SHELL is sent this tick, as a pose of the box: the box's own unless it is carried.
var _follow := Transform3D.IDENTITY
var _follow_v := Vector3.ZERO
var _follow_w := Vector3.ZERO
## The tray in the box's frame.
var _tray_local := Transform3D.IDENTITY
## [coin, its drawn mesh] by the coin's instance id, for the coins of this box and those still easing back onto their bodies
## after leaving it.
var _meshes: Dictionary = {}
## Whether any of them is drawn off its body.
var _drawn_off := false
const FOLLOW_TAU := 0.03
const MAX_CARRY_SPEED := 3.0
const MAX_CARRY_TURN := 12.0
## The most the shell's speed changes, metres per second squared: what its coins feel, whatever the box does. A seated box
## stays in its seat until the hand is some 10 cm out (the socket's hold, as for every seated thing) and then catches the hand
## up at 2 to 6 m/s; eased by FOLLOW_TAU alone the shell went after it at 2 to 6 g, and an ordinary pull threw coins out of the
## tray and against the cabinet (0 to 7 of 30, measured). The shell is not seen, so it may take its time.
const MAX_CARRY_ACCEL := 8.0
## And the slowing it plans for as it closes on the box, a little less, so that it can keep to it and not run past.
const MAX_CARRY_BRAKE := MAX_CARRY_ACCEL * 0.8
## The shell is ON the box once it is this near and this slow (metres or radians, and per second): at rest nothing is offset.
const ARRIVED := 0.00001
const ARRIVED_SPEED := 0.001
## How fast a coin that has left the tray (or was taken by a hand) is drawn back onto its body, per second (~0.1 s).
const DRAW_BACK_RATE := 12.0


func _ready() -> void:
	_box = get_parent() as XRToolsPickable
	_follow = _box.global_transform
	process_physics_priority = 100
	_box.picked_up.connect(_held)
	_refresh()


func _held(_what: Node3D) -> void:
	_refresh()


## The shell where the box is held now, outside the tick (taken into a hand, dressed).
func _refresh() -> void:
	_follow_box(0.0)
	_sync()


func _physics_process(delta: float) -> void:
	# Ray grabs do not emit the body's picked_up, so how it is held is read here, after the drivers.
	_follow_box(delta)
	_sync()
	_draw_coins(delta)
	for token in tokens:
		if is_instance_valid(token):
			token.continuous_cd = not _box.freeze
	_watch_time += delta
	if _watch_time >= 0.25:
		_watch_time = 0.0
		watch()


## Where the shell goes this tick. Carried, it is eased after the box: a hand's or a ray's pose otherwise jumps the collision
## wall through a coin between solver steps. Seated or loose, it is the box's own pose. The box is only READ.
func _follow_box(delta: float) -> void:
	var now := _box.global_transform
	var mode := Mode.LOOSE
	if _box.freeze and (_box.collision_layer & 4) == 0:
		mode = Mode.SEATED if _box.get_picked_up_by() is XRToolsSnapZone else Mode.CARRIED
	if mode != _mode:
		# A carry that ends (let go, or taken by a slot) ends with the shell wherever its easing had it.
		if mode != Mode.CARRIED and _mode != Mode.LOOSE:
			_hand_off(now, mode)
		_mode = mode
	if mode != Mode.CARRIED:
		_follow = now
		_follow_v = Vector3.ZERO
		_follow_w = Vector3.ZERO
		return
	var w := 1.0 / FOLLOW_TAU
	# Toward the box at the speed its distance allows (eased in over FOLLOW_TAU when near, never faster than it can stop from
	# when far, MAX_CARRY_SPEED at most), its speed changed by MAX_CARRY_ACCEL at most. It stays BEHIND the box, on the way the
	# box came: no lead from the box's own speed, which would carry it on past a box that stops.
	var to := now.origin - _follow.origin
	var dist := to.length()
	var close := minf(minf(dist * w, sqrt(2.0 * MAX_CARRY_BRAKE * dist)), MAX_CARRY_SPEED)
	var want_v := to / dist * close if dist > 0.0000001 else Vector3.ZERO
	_follow_v = _follow_v.move_toward(want_v, MAX_CARRY_ACCEL * delta)
	_follow.origin += _follow_v * delta
	var turn := now.basis.orthonormalized().get_rotation_quaternion() * _follow.basis.orthonormalized().get_rotation_quaternion().inverse()
	if turn.w < 0:
		turn = -turn
	var angle := turn.get_angle()
	var error := turn.get_axis() * angle if angle > 0.00001 else Vector3.ZERO
	_follow_w += (error * w*w - _follow_w * 2*w) * delta
	_follow_w = _follow_w.limit_length(MAX_CARRY_TURN)
	if _follow_w.length() > 0.00001:
		_follow.basis = Basis(_follow_w.normalized(), _follow_w.length() * delta) * _follow.basis
	_follow.basis = _follow.basis.orthonormalized().scaled(now.basis.get_scale())
	if _follow.origin.distance_to(now.origin) < ARRIVED and error.length() < ARRIVED \
			and _follow_v.length() < ARRIVED_SPEED and _follow_w.length() < ARRIVED_SPEED:
		_follow = now
		_follow_v = Vector3.ZERO
		_follow_w = Vector3.ZERO


## The end of a carry: the shell goes to the box at once (the box's own walls take over, or its seat is exact), and the coins in
## it go with it as one rigid thing, keeping their motion in the tray. Without it a box let go mid-swing left its coins where
## the shell trailed, outside it. The one place a coin's pose is written; it is drawn there already (_draw_coins).
func _hand_off(now: Transform3D, mode: Mode) -> void:
	if not is_instance_valid(_guard) or not is_instance_valid(_tray):
		return
	# sync_to_physics: the shell's node is where the last step left it, as the coins' are.
	var shell := _guard.global_transform
	var move := now * shell.affine_inverse()
	if move.is_equal_approx(Transform3D.IDENTITY):
		return
	var turn := move.basis.orthonormalized()
	var box_v := _box.linear_velocity if mode == Mode.LOOSE else Vector3.ZERO
	var box_w := _box.angular_velocity if mode == Mode.LOOSE else Vector3.ZERO
	var inside := _tray.mesh.get_aabb().grow(maxf(0.01, _thickness + ArcadeCoinModule.COIN_RADIUS))
	var frame := (shell * _tray_local).affine_inverse()
	for token in tokens:
		if not is_instance_valid(token) or token.freeze:
			continue
		var at := token.global_transform
		if not inside.has_point(frame * at.origin):
			continue
		var to := move * at.origin
		var slide := token.linear_velocity - _follow_v - _follow_w.cross(at.origin - shell.origin)
		var spin := token.angular_velocity - _follow_w
		token.global_transform = Transform3D(turn * at.basis, to)
		token.linear_velocity = turn * slide + box_v + box_w.cross(to - now.origin)
		token.angular_velocity = turn * spin + box_w
		token.sleeping = false
		_mesh_of(token).transform = Transform3D.IDENTITY


func _sync() -> void:
	# Held tokens have mask 0: another hand can take one out freely.
	_box.collision_layer &= ~ArcadeToken.TRAY_LAYER
	if not is_instance_valid(_guard) or not is_instance_valid(_tray):
		return
	_tray_local = _box.global_transform.affine_inverse() * _tray.global_transform
	var at := _follow * _tray_local
	var travel := 0.0
	var bounds := _tray.mesh.get_aabb()
	for i in 8:
		var corner := bounds.get_endpoint(i)
		travel = maxf(travel, (at * corner).distance_to(_last_tray * corner))
	_last_tray = at
	# A carry can alternate a jump with an unchanged physics tick. Keep the contact backing while the solver finishes that jump.
	if travel >= _peak_travel:
		_peak_travel = travel
		_travel_hold = 5
	elif _travel_hold > 0:
		_travel_hold -= 1
	else:
		_peak_travel = maxf(travel, _peak_travel * 0.8)
	var held := _mode != Mode.LOOSE
	_guard.collision_layer = ArcadeToken.TRAY_LAYER if held else 0
	if held:
		# A kinematic wall can cross a whole coin between ticks. Extend only the
		# OUTSIDE of its coin-only collider, enough that the inner contact face
		# remains the nearest face after the move. Never add a lid. Other room
		# objects use the normal shell.
		_guard_wall(maxf(0.02, _peak_travel * 4.0 + ArcadeToken.DISC_HEIGHT * 2.0))
	_guard.global_transform = _follow
	_guard.force_update_transform()


## Draw each coin in the tray where its body stands in the shell: the shell is a tick behind the box at least (the solver's
## completed pose) and further while a carry eases it, and a coin drawn on its body would stand through the tray's floor and
## walls by that much. Only the coin's mesh is moved, on the physics tick (the room's transforms are interpolated from ticks).
## Nothing to do, and nothing done, while the shell is on the box: seated or held still.
func _draw_coins(delta: float) -> void:
	if not is_instance_valid(_guard) or not is_instance_valid(_tray):
		return
	var shell := _guard.global_transform
	var shift := _box.global_transform * shell.affine_inverse() if _mode != Mode.LOOSE else Transform3D.IDENTITY
	var off := not shift.is_equal_approx(Transform3D.IDENTITY)
	if not off and not _drawn_off:
		return
	var back := minf(1.0, delta * DRAW_BACK_RATE)
	var inside := _tray.mesh.get_aabb().grow(maxf(0.01, _thickness + ArcadeCoinModule.COIN_RADIUS))
	var frame := (shell * _tray_local).affine_inverse()
	var gone: Array[int] = []
	_drawn_off = false
	for id: int in _meshes:
		# (untyped until known alive: a typed assignment of a freed coin is itself the error)
		var pair: Array = _meshes[id]
		if not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
			gone.append(id)
			continue
		var token := pair[0] as RigidBody3D
		var mesh := pair[1] as Node3D
		var at := token.global_transform
		if off and not token.freeze and inside.has_point(frame * at.origin):
			mesh.transform = at.affine_inverse() * (shift * at)
			_drawn_off = true
			continue
		# Out of the tray, in a hand, or the shell has arrived: back onto its body.
		var drawn := mesh.transform
		if not off or drawn.is_equal_approx(Transform3D.IDENTITY):
			mesh.transform = Transform3D.IDENTITY
			if not tokens.has(token):
				gone.append(id)
		else:
			mesh.transform = drawn.interpolate_with(Transform3D.IDENTITY, back)
			_drawn_off = true
	for id in gone:
		_meshes.erase(id)


## A coin's drawn mesh, noted for _draw_coins.
func _mesh_of(token: RigidBody3D) -> Node3D:
	var id := token.get_instance_id()
	if not _meshes.has(id):
		_meshes[id] = [token, token.get_node("Mesh")]
	return (_meshes[id] as Array)[1] as Node3D


func coin_layer_active() -> bool:
	return is_instance_valid(_guard) and _guard.collision_layer != 0


## The tray as the coins' bodies have it: the shell's while it holds them (the pose the last step left it at, as theirs are),
## the drawn tray's otherwise. Ask a coin's place in the tray through this, never through the drawn tray.
func tray_frame() -> Transform3D:
	if coin_layer_active():
		return _guard.global_transform * _tray_local
	return _tray.global_transform


## Where a new coin's body goes for the pose `in_tray` (the tray's frame): the shell as the next step will have it.
func _coin_pose(in_tray: Transform3D) -> Transform3D:
	if _mode == Mode.CARRIED and is_instance_valid(_guard):
		return _follow * _tray_local * in_tray
	return _tray.global_transform * in_tray


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
		# Top-level, and its node is the solver's completed pose (sync_to_physics): the pose the coins' bodies are at, which
		# _draw_coins and tray_frame read.
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
		_tray_local = _box.global_transform.affine_inverse() * _tray.global_transform
		_last_tray = _tray.global_transform
		_guard_wall(0.02)
		_refresh()


func _exit_tree() -> void:
	for token in tokens:
		if is_instance_valid(token):
			token.continuous_cd = true
	for id: int in _meshes:
		var mesh: Variant = (_meshes[id] as Array)[1]
		if is_instance_valid(mesh):
			(mesh as Node3D).transform = Transform3D.IDENTITY
	_meshes.clear()
	if is_instance_valid(_guard):
		_guard.queue_free()


func restore(places: Array[Transform3D]) -> void:
	if _restored or not is_instance_valid(_tray):
		return
	_restored = true
	for place in places:
		_spawn(_coin_pose(place))


func _spawn(at: Transform3D) -> void:
	var room := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var token := ArcadeToken.make(at, room)
	token.continuous_cd = not _box.freeze
	tokens.append(token)
	_mesh_of(token)
	_arriving[token.get_instance_id()] = Engine.get_physics_frames() + 45


func bank() -> void:
	if not is_instance_valid(_tray):
		return
	watch()
	if tokens.size() < LIMIT:
		_spawn(_coin_pose(_tray.global_transform.affine_inverse() * ArcadeCabinetFromModel._cash_drop_pose(_tray)))
	_box.set_meta(COUNT_META, int(_box.get_meta(COUNT_META, 0)) + 1)


func unbank() -> void:
	watch()
	var count := int(_box.get_meta(COUNT_META, 0))
	# Past the physical cap, refund the banked overflow before removing a body.
	if count <= tokens.size() and not tokens.is_empty():
		var token: RigidBody3D = tokens.pop_back()
		_arriving.erase(token.get_instance_id())
		_meshes.erase(token.get_instance_id())
		token.queue_free()
	_box.set_meta(COUNT_META, maxi(count - 1, 0))


func watch() -> void:
	if not _restored or not is_instance_valid(_tray):
		return
	# During a fast carry a contact may be inside the outward collision backing
	# while Jolt resolves it. Do not discard it (and re-enable CCD) mid-contact.
	var margin := maxf(0.01, _thickness + ArcadeCoinModule.COIN_RADIUS) if coin_layer_active() else 0.01
	var inside := _tray.mesh.get_aabb().grow(margin)
	# (the tray as the coins' bodies have it: the drawn one is ahead of them while the shell trails)
	var frame := tray_frame().affine_inverse()
	var kept: Array[RigidBody3D] = []
	for token in tokens:
		if not is_instance_valid(token) or token.is_queued_for_deletion():
			continue
		var id := token.get_instance_id()
		if inside.has_point(frame * token.global_position) or Engine.get_physics_frames() < int(_arriving.get(id, 0)):
			kept.append(token)
			# (one that fell out of the tray's reach and back in is drawn in it again)
			_mesh_of(token)
		else:
			_arriving.erase(id)
			token.continuous_cd = true
	var lost := tokens.size() - kept.size()
	tokens = kept
	if lost > 0:
		_box.set_meta(COUNT_META, maxi(int(_box.get_meta(COUNT_META, 0)) - lost, tokens.size()))
