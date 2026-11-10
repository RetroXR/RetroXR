## A pad lying on a table with its cord in a heap, its plug held where a
## console's port would be: does the cord go to sleep and STAY asleep?
##
##   "$godot" --headless --path RetroXR res://Tools/rope/pad_cord_probe.tscn
##   ... -- --system=genesis   a REAL console on the table, the plug in its port
##   ... -- --loose   the plug left loose on the table instead of held in a port
##   ... -- --console a console-sized box round the port (the cord's first
##                    particles are then inside a solid for good)
##
## The real pad scene, its own cable, and the ENGINE ticking everything (the pad
## and the plug are Jolt's). rope_jitter_probe's bare ropes have plain nodes for
## ends; a pad's cord runs from a point on one physics body to another body,
## which is where a cord that will not lie still usually gets it from.
## Prints each wake after the first sleep, with what the pad was doing.

extends Node

const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TICKS := 1800

var _pad: RigidBody3D
var _rope: VerletRope
var _plug: RigidBody3D
var _tick := -240
var _prev := PackedVector3Array()
var _first := -1
var _wakes := 0
var _asleep := false
var _worst := 0.0
var _awake := 0
var _pad_prev := Vector3.ZERO
var _pad_travel := 0.0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[padcord] TIMEOUT"); get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	_box(Vector3(0, 0.70, 0), Vector3(2.0, 0.10, 2.0))
	_box(Vector3(0, -0.05, 0), Vector3(6.0, 0.10, 6.0))
	if args.has("--console"):
		# From 8 cm in FRONT of the port: the cord leaves the plug 4 cm behind its
		# seat, and it is the cord's particles that have to be inside.
		_box(Vector3(0.32, 0.78, 0), Vector3(0.40, 0.06, 0.20))
	# --system=<id>: a REAL console on the table and the pad's plug seated in its
	# first port, as a room has it (the scene has to be the current one: the pad
	# adds its cable to it).
	var system_id := ""
	for arg: String in args:
		if arg.begins_with("--system="):
			system_id = arg.trim_prefix("--system=")
	var sys: RetroSystem = null
	if not system_id.is_empty():
		sys = SYSTEM_SCENE.instantiate() as RetroSystem
		sys.systemid = system_id
		sys.position = Vector3(0.35, 0.80, 0)
		add_child(sys)
		for k in 30:
			await get_tree().physics_frame
	_pad = PAD_SCENE.instantiate()
	if not system_id.is_empty():
		_pad.set("systemid", system_id)
	_pad.position = Vector3(-0.10, 0.80, 0.10)
	add_child(_pad)
	# The pad makes its cable on a deferred call.
	for k in 4:
		await get_tree().physics_frame
	_plug = _pad.call("get_plug")
	if _plug == null:
		print("[padcord] the pad made no plug")
		get_tree().quit(1)
		return
	_rope = _plug.get_parent().get_node("VerletRope")
	if sys != null:
		sys.restore_controller_plug(0, _plug)
		for k in 10:
			await get_tree().physics_frame
		print("[padcord] plug seated in %s: at %s, console at %s" % [system_id,
			str(_plug.global_position), str(sys.global_position)])
	elif not args.has("--loose"):
		_plug.freeze = true
		_plug.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.20, 0.775, 0.0))
		_rope._init_points()
	print("[padcord] cord %d x %.0f mm, plug %s" % [_rope.segment_count, _rope.segment_length * 1000.0,
		"loose" if args.has("--loose") else "held in a port"])
	_prev = _rope.get_points()
	_pad_prev = _pad.global_position
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _rope == null:
		return
	_tick += 1
	var now := _rope.get_points()
	var sleeping := _rope.is_sleeping()
	if _tick >= 0:
		if sleeping and _first < 0:
			_first = _tick
		if _first >= 0 and _tick > _first:
			if _asleep and not sleeping:
				_wakes += 1
				if _wakes <= 12:
					print("[padcord] woke at tick %d: pad moved %.3f mm this tick, pad sleeping=%s, plug sleeping=%s" % [
						_tick, _pad.global_position.distance_to(_pad_prev) * 1000.0,
						str(_pad.sleeping), str(_plug.sleeping)])
			if not sleeping:
				_awake += 1
			for i in mini(now.size(), _prev.size()):
				_worst = maxf(_worst, now[i].distance_to(_prev[i]))
		_pad_travel += _pad.global_position.distance_to(_pad_prev)
	_asleep = sleeping
	_prev = now
	_pad_prev = _pad.global_position
	if _tick >= TICKS:
		var m: Dictionary = _rope.get_sleep_metrics()
		print("[padcord] first asleep at tick %d, then %d wakes, awake %d of %d ticks, worst single-tick move %.3f mm, pad travel %.2f mm" % [
			_first, _wakes, _awake, TICKS - maxi(_first, 0), _worst * 1000.0, _pad_travel * 1000.0])
		print("[padcord] at the end: asleep=%s max_velocity %.4f mm rms %.4f mm stretch_error %.3f contact_error %.4f" % [
			str(_rope.is_sleeping()), float(m["max_velocity"]) * 1000.0, float(m["rms_velocity"]) * 1000.0,
			float(m["stretch_error"]), float(m["contact_error"])])
		get_tree().quit(0)


func _box(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = centre
	body.add_child(col)
