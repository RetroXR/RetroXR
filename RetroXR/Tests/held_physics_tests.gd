## held_physics_tests — HeldObjectPhysics (the HeldPhysics autoload), headless.
##
##   "$godot" --headless --path RetroXR res://Tests/held_physics_tests.tscn
##   "$godot" --headless --path RetroXR res://Tests/held_physics_tests.tscn -- --only=escape
##
## patch/  a body entering the tree loses the held layer (bit 17) from its mask
##         and nothing else, an Area3D keeps it, a pickable gets continuous CD.
## escape/ a pickable let go part way into a world shelf steps out toward the
##         camera and gets its layer, mask and freeze back; one resting ON the
##         shelf, a frozen one, and one inside another pickable are left alone.
## riders/ what stands on a body that is picked up is coupled to the held layer
##         while it is still under it, and woken and uncoupled once it is not; a
##         neighbour pressed against its side and a frozen body are not riders.
## fall/   a pickable that drops below the world comes back to where it last sat.
##
## Physics runs headless (the dummy renderer stubs rendering, not Jolt), so the
## shape queries are real. No grab is driven: a release is the pickable's own
## `dropped` signal, which is what the autoload listens to, and "held" is the
## state xr-tools leaves a held body in (frozen, on the held layer, mask 0).
extends "res://Tests/test_suite.gd"

const HOP := preload("res://Scripts/Interaction/held_object_physics.gd")
## The mask every pickable in this project carries: World, Pickable, SnapZone
## (17) and XRHand_Physics.
const PICKABLE_MASK := 196613

var _only := ""
var _hop: Node = null
var _spawned: Array[Node] = []
var _cam: Camera3D = null


func _ready() -> void:
	suite_tag = "held"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[held] TIMEOUT")
		get_tree().quit(1))

	_hop = get_node_or_null("/root/HeldPhysics")
	_ok(_hop != null, "setup/the HeldPhysics autoload is running")
	if _hop == null:
		_finish()
		return
	# The escape steps toward the camera, and a release with none does nothing.
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = Vector3(0, 1.5, 3)
	_cam.make_current()

	if _want("patch"):
		await _group_patch()
	if _want("escape"):
		await _group_escape()
	if _want("riders"):
		await _group_riders()
	if _want("fall"):
		await _group_fall()

	_clear()
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _box(body: CollisionObject3D, size: Vector3, at: Vector3) -> CollisionObject3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if body is RigidBody3D:
		(body as RigidBody3D).gravity_scale = 0.0
	add_child(body)
	(body as Node3D).global_position = at
	_spawned.append(body)
	return body


## A loose pickable on the Pickable layer (3) with the project's mask. `apart`
## keeps the solver from acting on an overlap the case set up on purpose: a
## collision exception stops the contact, and the escape's shape query, which
## only excludes the body itself, still sees the shelf it is in.
func _pickable(size: Vector3, at: Vector3, apart: Node = null) -> XRToolsPickable:
	var p := XRToolsPickable.new()
	p.collision_layer = 0b100
	p.collision_mask = PICKABLE_MASK
	if apart is PhysicsBody3D:
		p.add_collision_exception_with(apart as PhysicsBody3D)
	return _box(p, size, at) as XRToolsPickable


## Physics frames for `checks` passes of a check the autoload runs at `hz`. Its
## timers run on the physics step's fixed delta, so counting frames is exact
## where a wall-clock wait is not.
func _ticks_for(checks: int, hz: float) -> int:
	return int(ceil(Engine.physics_ticks_per_second / hz)) * checks + 1


func _shelf(size: Vector3, at: Vector3) -> StaticBody3D:
	var s := StaticBody3D.new()
	s.collision_layer = HOP.WORLD_BIT
	return _box(s, size, at) as StaticBody3D


# ── patch/ ───────────────────────────────────────────────────────────────────

func _group_patch() -> void:
	var rb := RigidBody3D.new()
	rb.collision_mask = PICKABLE_MASK
	_box(rb, Vector3.ONE * 0.1, Vector3(5, 1, 0))
	_eq(rb.collision_mask, PICKABLE_MASK & ~HOP.HELD_BIT,
		"patch/a body entering the tree loses the held layer and nothing else")

	var plain := RigidBody3D.new()
	plain.collision_mask = 0b101
	_box(plain, Vector3.ONE * 0.1, Vector3(5, 1, 1))
	_eq(plain.collision_mask, 0b101, "patch/a mask without the held layer is left exactly as it was")

	var zone := Area3D.new()
	zone.collision_mask = PICKABLE_MASK
	_box(zone, Vector3.ONE * 0.1, Vector3(5, 1, 2))
	_eq(zone.collision_mask, PICKABLE_MASK, "patch/an Area3D keeps it, so snap zones still see a held object")

	var p := _pickable(Vector3.ONE * 0.1, Vector3(5, 1, 3))
	_ok(p.continuous_cd, "patch/a pickable gets continuous collision detection")
	await _physics(1)
	_clear()


# ── escape/ ──────────────────────────────────────────────────────────────────

## Release `body` as xr-tools does (its `dropped` signal) and let the deferred
## escape run.
func _release(body: XRToolsPickable) -> void:
	body.dropped.emit(body)
	await get_tree().process_frame
	await _physics(1)


func _group_escape() -> void:
	# A shelf whose front face is at z = 0.3, toward the camera.
	var shelf := _shelf(Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0))
	await _physics(2)

	# Let go 8 cm into its front: buried, not resting.
	var inside := _pickable(Vector3.ONE * 0.1, Vector3(0, 0.3, 0.27), shelf)
	var layer := inside.collision_layer
	var mask := inside.collision_mask
	await _physics(2)
	await _release(inside)
	var z := inside.global_position.z
	_ok(z > 0.33 and z < 0.27 + HOP.MAX_TRAVEL,
		"escape/a body let go inside the shelf steps out toward the camera",
		"front of shelf at 0.30, body's back at %.3f" % (z - 0.05))
	_ok(inside.collision_layer == layer and inside.collision_mask == mask and not inside.freeze,
		"escape/and gets its own layer, mask and freeze back",
		"layer %d mask %d freeze %s" % [inside.collision_layer, inside.collision_mask, inside.freeze])

	# The control: resting on top is a contact of depth zero, not a burial.
	var on_top := _pickable(Vector3.ONE * 0.1, Vector3(0.1, 0.65, 0.0), shelf)
	await _physics(2)
	var top_at := on_top.global_position
	await _release(on_top)
	_ok(on_top.global_position.is_equal_approx(top_at),
		"escape/one resting on the shelf is not moved", str(on_top.global_position - top_at))

	# Frozen: an owner (a tray, a slot) has claimed the pose.
	var seated := _pickable(Vector3.ONE * 0.1, Vector3(-0.1, 0.3, 0.27), shelf)
	seated.freeze = true
	await _physics(2)
	var seated_at := seated.global_position
	await _release(seated)
	_ok(seated.global_position.is_equal_approx(seated_at), "escape/a frozen one is left where it was seated")

	# World only: inside another pickable is the solver's business (a disc in its console).
	var console := RigidBody3D.new()
	console.collision_layer = 0b10
	console.freeze = true
	_box(console, Vector3(0.4, 0.4, 0.4), Vector3(3, 0.3, 0))
	var disc := _pickable(Vector3.ONE * 0.1, Vector3(3, 0.3, 0), console)
	await _physics(2)
	var disc_at := disc.global_position
	await _release(disc)
	_ok(disc.global_position.is_equal_approx(disc_at), "escape/one inside another pickable is not pushed out")
	_clear()


# ── riders/ ──────────────────────────────────────────────────────────────────

func _group_riders() -> void:
	var support := RigidBody3D.new()
	support.collision_mask = PICKABLE_MASK
	_box(support, Vector3(0.4, 0.4, 0.4), Vector3(-3, 0.2, 0))
	var rider := RigidBody3D.new()
	rider.collision_mask = PICKABLE_MASK
	_box(rider, Vector3.ONE * 0.1, Vector3(-3, 0.45, 0))
	# Pressed against its side: touching, but standing on the floor, not on it.
	var neighbour := RigidBody3D.new()
	neighbour.collision_mask = PICKABLE_MASK
	_box(neighbour, Vector3.ONE * 0.1, Vector3(-3 + 0.25, 0.1, 0))
	var frozen := RigidBody3D.new()
	frozen.collision_mask = PICKABLE_MASK
	frozen.freeze = true
	_box(frozen, Vector3.ONE * 0.1, Vector3(-3 + 0.12, 0.45, 0))
	await _physics(3)
	var rider_mask := rider.collision_mask

	_hop.watch_riders(support)
	_ok(rider.collision_mask & HOP.HELD_BIT != 0,
		"riders/what stands on a body that is picked up is coupled to the held layer")
	_ok(neighbour.collision_mask & HOP.HELD_BIT == 0, "riders/a neighbour pressed against its side is not")
	_ok(frozen.collision_mask & HOP.HELD_BIT == 0, "riders/nor is a frozen body sitting on it")

	# Held as xr-tools holds it, and still right there underneath.
	support.freeze = true
	support.collision_layer = HOP.HELD_BIT
	support.collision_mask = 0
	rider.sleeping = true
	await _physics(_ticks_for(3, HOP.RIDER_CHECK_HZ))
	_ok(rider.collision_mask & HOP.HELD_BIT != 0,
		"riders/while it is still underneath the rider stays coupled")

	# Carried off: the rider loses its floor.
	support.global_position += Vector3(2, 0, 0)
	await _physics(_ticks_for(2, HOP.RIDER_CHECK_HZ))
	_ok(rider.collision_mask == rider_mask and not rider.sleeping,
		"riders/once it is carried away the rider is woken and uncoupled",
		"mask %d (was %d), sleeping %s" % [rider.collision_mask, rider_mask, rider.sleeping])
	_clear()


# ── fall/ ────────────────────────────────────────────────────────────────────

func _group_fall() -> void:
	var p := _pickable(Vector3.ONE * 0.1, Vector3(7, 1, 0))
	# The fall watch runs at 4 Hz and remembers a pose only once it is at rest.
	await _physics(_ticks_for(2, HOP.FALL_CHECK_HZ))
	p.global_position = Vector3(7, HOP.FALL_LIMIT_Y - 3.0, 0)
	await _physics(_ticks_for(2, HOP.FALL_CHECK_HZ))
	_ok(p.global_position.distance_to(Vector3(7, 1, 0)) < 0.01,
		"fall/a pickable below the world comes back to where it last sat",
		str(p.global_position))
	_clear()
