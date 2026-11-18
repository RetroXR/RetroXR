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
## A coin in a HELD box (in a hand, on a ray, or seated in a cabinet that is itself carried) is as solid as any coin to what
## it meets, and PUSHES NOTHING. It is a room body driven by a shell that cannot be stopped, so on its own layers whatever
## stood in its way gave: a tray of thirty pulled out of a NAOMI Universal, an Aero City or a Blast City moved the cabinet
## (1 kg) 19 to 78 mm, and moved through a cabinet's deck or side, 60 to 115 mm (the owner, 2026-11-17: "why do i see the the
## coins and coin box 'push' the cabinet depending on where i move it"). Passing through the room with the tray, as the tray
## does, was tried and is not wanted (the owner: "the coins should have collision just like any other object").
##
## The engine's contacts are ONE-WAY when one body's mask has the other's layer and not the reverse: the body that is not
## seen is immovable in that contact (the Jolt module's contact listener, _try_override_collision_response). So the coin's
## layer is one no body's mask has, XRPickable (19: a hand's grab area finds it there) and the tray's, and its mask stays its
## own. What blocks it for good scrapes it out through the tray's side, and it is the room's coin again, on its own layers,
## the tick it is out of the tray (measured with that layer: the cabinets above 0.0 to 3 mm).
const HELD_COIN_LAYER := (1 << 18) | ArcadeToken.TRAY_LAYER
## Whether the box's coins are on that layer now: the box is carried, or seated in a thing that is itself carried.
var _one_way := false
## Every coin is looked at on the next pass, asleep or not (what it may touch has changed).
var _all_coins := false
## The slot the box is seated in, and the body that slot is part of.
var _slot: Node = null
var _slot_body: PhysicsBody3D = null
## The cabinet the coins in the tray do not meet AT ALL: its slot's while the box is seated, and while it is carried that of
## the nearest slot it fits within HOME_REACH and the tray's own length (its own on the way out, any on the way in), measured
## from the SHELL, where the coins are (it trails the box by 12 cm at 1.25 m/s: from the box, an Aero City scraped 2 of 30 out
## as the box left the reach with its coins still inside the cabinet). A cabinet's collision stands within a millimetre or two
## of its box (18 to 28 of 30 seated coins are in contact with it, at rest) and in places across the way the box comes out by:
## one-way coins alone, a Blast City scraped 4 of 30 out of a tray pulled straight out of it.
const HOME_REACH := 0.2
## Physics ticks between two looks for that slot while the box is carried.
const HOME_LOOK_TICKS := 9
var _home: PhysicsBody3D = null
var _home_wait := 0
## The coins excepted from _home, by instance id.
var _home_coins: Dictionary = {}
## The coins something has scraped out of the held tray, by instance id: the shell is done with them until the box is put
## down or seated (it would run them over again as the tray went on, and push them, the room's now, into whatever scraped
## them out). One is scraped out when its MIDDLE goes SCRAPE_DEPTH past a wall or the floor of the shell, under the rim (one
## that went over the rim was thrown or poured, and is left alone: _past). It is rough, and cannot be made fine: Jolt lets
## two bodies overlap by 20 mm before it does anything about it, and a coin is 25 mm across, so a FREE coin under a pile's
## weight stands up to 15 mm into a wall (measured, a 675 degrees/s spin) and nothing short of that tells a coin that is
## held back from one that is not. A rule at 5 mm of the disc let 27 of 60 free coins out through the wall of a spinning
## tray. Nor can it be read from the coin's contacts: those count what is within Jolt's 2 cm.
const SCRAPE_DEPTH := 0.008
## The coins whose middle is past a face of the shell now, by instance id: true for one that went there over the rim.
var _past: Dictionary = {}
var _scraped: Dictionary = {}
## The most a coin in a held tray moves against the shell, metres per second (one sliding or pouring is under 2). Held back
## by something while the shell drives on, a coin gathers speed before it is scraped out: two of sixty left a tray carried
## through a block at some 13 m/s and landed 5 m away. It is stopped as it is scraped out, too: what holds it has it.
const MAX_COIN_SPEED := 3.0
## And the most a scraped coin moves at all, for SCRAPE_SETTLE ticks from the one it was scraped out on. The coins a block
## holds back are a pile pressed between it and the shell's wall, and when the wall lets them go the pile springs apart: the
## ones at its back left at 4 to 5.6 m/s, in one step (so out of the tray's reach before any limit kept there could apply),
## and slid 2 m across the table. They drop where they are held instead.
const SCRAPED_SPEED := 1.0
const SCRAPE_SETTLE := 27
## The physics frame each scraped coin was scraped out on, by instance id.
var _scraped_at: Dictionary = {}
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
	var one_way := mode == Mode.CARRIED or (mode == Mode.SEATED and _seat_carried())
	if one_way != _one_way:
		_one_way = one_way
		_all_coins = true
		if not one_way:
			_room_coins()
	_set_home(_home_for(mode))
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


## The body the box's slot is part of (a cabinet), or null.
func _seat_body() -> PhysicsBody3D:
	var slot: Node = _box.get_picked_up_by()
	if slot != _slot:
		_slot = slot
		_slot_body = _body_of(slot)
	return _slot_body if is_instance_valid(_slot_body) else null


func _body_of(node: Node) -> PhysicsBody3D:
	var n := node
	while n != null and not n is PhysicsBody3D:
		n = n.get_parent()
	return n as PhysicsBody3D


## Whether the thing the box is seated in is itself in a hand (a cabinet carried with its tray in it).
func _seat_carried() -> bool:
	var body := _seat_body() as RigidBody3D
	return body != null and body.freeze and (body.collision_layer & 4) == 0


## The cabinet the tray's coins do not meet (see HOME_REACH).
func _home_for(mode: Mode) -> PhysicsBody3D:
	if mode == Mode.SEATED:
		return _seat_body()
	if mode != Mode.CARRIED:
		return null
	_home_wait -= 1
	if _home_wait > 0:
		return _home if is_instance_valid(_home) else null
	_home_wait = HOME_LOOK_TICKS
	var best: Node = null
	var best_d := HOME_REACH + (_tray.mesh.get_aabb().get_longest_axis_size() if is_instance_valid(_tray) else 0.0)
	for z in get_tree().get_nodes_in_group(CoverSlots.SLOT_GROUP):
		var zone := z as XRToolsSnapZone
		if zone == null or zone.snap_require.is_empty() or not _box.is_in_group(zone.snap_require):
			continue
		var d := zone.global_position.distance_to(_follow.origin)
		if d < best_d:
			best_d = d
			best = zone
	return _body_of(best)


func _set_home(body: PhysicsBody3D) -> void:
	if body == _home:
		return
	for id: int in _home_coins:
		var coin: Variant = _home_coins[id]
		if is_instance_valid(coin) and is_instance_valid(_home):
			(coin as PhysicsBody3D).remove_collision_exception_with(_home)
	_home_coins.clear()
	_home = body
	_all_coins = true


## Whether a coin in the tray meets _home: not while it is in the tray.
func _keep_home(token: RigidBody3D, in_tray: bool) -> void:
	var id := token.get_instance_id()
	var excepted := _home_coins.has(id)
	var want := in_tray and is_instance_valid(_home)
	if want == excepted:
		return
	if want:
		token.add_collision_exception_with(_home)
		_home_coins[id] = token
	else:
		if is_instance_valid(_home):
			token.remove_collision_exception_with(_home)
		_home_coins.erase(id)


## A coin's layer: the held coins' while it is in a held tray (it meets everything and pushes nothing), its own otherwise.
func _held_layer(token: RigidBody3D, on: bool) -> void:
	if on == (token.collision_layer == HELD_COIN_LAYER):
		return
	if on:
		token.collision_layer = HELD_COIN_LAYER
		return
	var own := token as XRToolsPickable
	token.collision_layer = own.original_collision_layer if own != null else 4


## Every coin of the box is the room's again (one in a hand has the hold's layers, and gets its own back from it), and the
## shell takes back the ones it had let go of.
func _room_coins() -> void:
	for id: int in _meshes:
		var coin: Variant = (_meshes[id] as Array)[0]
		if is_instance_valid(coin) and not (coin as RigidBody3D).freeze:
			_held_layer(coin as RigidBody3D, false)
	for id: int in _scraped:
		var coin: Variant = _scraped[id]
		if is_instance_valid(coin) and is_instance_valid(_guard):
			_guard.remove_collision_exception_with(coin as PhysicsBody3D)
	_scraped.clear()
	_scraped_at.clear()
	_past.clear()


## A coin a hand or a ray has taken is no coin of the tray's: it meets the cabinet again wherever it is let go.
func _coin_taken(coin: Variant, _by: Variant = null) -> void:
	if is_instance_valid(coin) and coin is RigidBody3D:
		_keep_home(coin as RigidBody3D, false)


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
		if not is_instance_valid(token) or token.freeze or _scraped.has(token.get_instance_id()):
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
## Nothing to do, and nothing done, while the shell is on the box and the box is not held: seated or loose, at rest.
##
## The same pass keeps what each coin may touch (HELD_COIN_LAYER, HOME_REACH): in the tray of a held box it pushes nothing,
## out of it (thrown, poured, scraped out) it is the room's again on that tick.
func _draw_coins(delta: float) -> void:
	if not is_instance_valid(_guard) or not is_instance_valid(_tray):
		return
	var shell := _guard.global_transform
	var shift := _box.global_transform * shell.affine_inverse() if _mode != Mode.LOOSE else Transform3D.IDENTITY
	var off := not shift.is_equal_approx(Transform3D.IDENTITY)
	if not off and not _drawn_off and not _one_way and not _all_coins:
		return
	# (a coin asleep in a box held still has nothing to be told: neither where it is drawn nor what it touches has changed)
	var skip_asleep := not off and not _drawn_off and not _all_coins
	_all_coins = false
	var back := minf(1.0, delta * DRAW_BACK_RATE)
	var inside := _tray.mesh.get_aabb().grow(maxf(0.01, _thickness + ArcadeCoinModule.COIN_RADIUS))
	var frame := (shell * _tray_local).affine_inverse()
	var bounds := _tray.mesh.get_aabb()
	var rim := bounds.end.y
	# the shell's inner faces (_guard_wall's), and how far into one a coin's middle may be before it is being held back
	var face_lo := bounds.position + Vector3.ONE * ArcadeCabinetFromModel.CASH_SHEET
	var face_hi := bounds.end - Vector3(ArcadeCabinetFromModel.CASH_SHEET, 0.0, ArcadeCabinetFromModel.CASH_PULL + ArcadeCabinetFromModel.CASH_SHEET)
	var driven := maxf(SCRAPE_DEPTH, _peak_travel * 1.5)
	var gone: Array[int] = []
	_drawn_off = false
	for id: int in _meshes:
		# (untyped until known alive: a typed assignment of a freed coin is itself the error)
		var pair: Array = _meshes[id]
		if not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
			gone.append(id)
			continue
		var token := pair[0] as RigidBody3D
		if skip_asleep and token.sleeping:
			continue
		var mesh := pair[1] as Node3D
		var at := token.global_transform
		var place := frame * at.origin
		var in_tray := not token.freeze and inside.has_point(place)
		var settling := false
		if not token.freeze:
			if _one_way and not _scraped.has(id):
				# how far its middle is past a face of the shell
				var into := maxf(maxf(face_lo.x - place.x, place.x - face_hi.x), maxf(face_lo.z - place.z, place.z - face_hi.z))
				into = maxf(into, face_lo.y - place.y)
				var past := in_tray and into > driven
				if past and not _past.has(id):
					_past[id] = place.y >= rim
					# driven into the shell under its rim: held back by something, scraped out, and stopped (what holds it has it)
					if place.y < rim:
						_guard.add_collision_exception_with(token)
						_scraped[id] = token
						_scraped_at[id] = Engine.get_physics_frames()
						token.linear_velocity = Vector3.ZERO
						token.angular_velocity = Vector3.ZERO
				elif not past and _past.has(id):
					_past.erase(id)
				if in_tray and not _scraped.has(id):
					var against := token.linear_velocity - _follow_v
					if against.length_squared() > MAX_COIN_SPEED * MAX_COIN_SPEED:
						token.linear_velocity = _follow_v + against.limit_length(MAX_COIN_SPEED)
			elif _one_way and Engine.get_physics_frames() - int(_scraped_at.get(id, 0)) < SCRAPE_SETTLE:
				settling = true
				if token.linear_velocity.length_squared() > SCRAPED_SPEED * SCRAPED_SPEED:
					token.linear_velocity = token.linear_velocity.limit_length(SCRAPED_SPEED)
			_held_layer(token, _one_way and in_tray)
		_keep_home(token, in_tray)
		# (a scraped coin is drawn where it is: it is the room's in all but its layer)
		if off and in_tray and not _scraped.has(id):
			mesh.transform = at.affine_inverse() * (shift * at)
			_drawn_off = true
			continue
		# Out of the tray, in a hand, or the shell has arrived: back onto its body.
		var drawn := mesh.transform
		if not off or drawn.is_equal_approx(Transform3D.IDENTITY):
			mesh.transform = Transform3D.IDENTITY
			# (one just scraped out is kept in sight while it settles)
			if not settling and not tokens.has(token):
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
		_all_coins = true
		var own := token as XRToolsPickable
		if own != null:
			own.picked_up.connect(_coin_taken)
			own.ray_grabbed.connect(_coin_taken)
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
	_room_coins()
	_set_home(null)
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
		_home_coins.erase(token.get_instance_id())
		_scraped.erase(token.get_instance_id())
		_past.erase(token.get_instance_id())
		_scraped_at.erase(token.get_instance_id())
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
			# (out of the tray: it meets the cabinet again, whether or not the pass above was running to see it go)
			_keep_home(token, false)
	var lost := tokens.size() - kept.size()
	tokens = kept
	if lost > 0:
		_box.set_meta(COUNT_META, maxi(int(_box.get_meta(COUNT_META, 0)) - lost, tokens.size()))
