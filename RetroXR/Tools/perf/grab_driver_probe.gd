## What XRToolsGrabDriver costs a physics tick, per driver, in three states (2026-11-13: 213 of them were 0.9 ms
## of a Quest 3's debug frame before they learned to rest). Builds N pickables in N snap zones, or held by N bare
## "hands", and times the band of physics priorities the drivers run in (hands -80, sockets -70) between two
## marker nodes, over TICKS ticks. Run WINDOWED (CLAUDE.md), one leg per process:
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/perf/grab_driver_probe.tscn -- --leg=rest|move|jitter|hand [--n=200] [--native=0|1]
##
##   rest   every zone still: the drivers settle, stop ticking (REST_AFTER), and cost what is left
##   move   every zone's carrier moves a millimetre a tick: every driver computes and pushes every tick
##   jitter every zone's carrier moves by float noise: every driver wakes and early-outs every tick (an awake body)
##   hand   every pickable held by a moving bare Node3D (no zone): the hand-held path, preview search included
##   --zones=M  M empty snap zones far away (the hand leg's preview search walks every live zone)
##   --native=0 forces the GDScript tick (XRToolsGrabDriver.native_tick off), =1 the C++ one where it exists
extends Node3D

const TICKS := 240
const WARM := 60

var _leg := "rest"
var _n := 200
var _zones := 0
var _carriers: Array[Node3D] = []
var _t0 := 0
var _sum := 0
var _ticks := 0
var _samples: Array[int] = []


class Marker extends Node:
	var on_tick: Callable
	func _physics_process(_d: float) -> void:
		on_tick.call()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--leg="):
			_leg = a.substr(6)
		elif a.begins_with("--n="):
			_n = int(a.substr(4))
		elif a.begins_with("--zones="):
			_zones = int(a.substr(8))
		elif a.begins_with("--native="):
			XRToolsGrabDriver.native_tick = a.substr(9) == "1"
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[gdprobe] TIMED OUT")
		get_tree().quit(2))
	print("[gdprobe] leg=%s n=%d native_tick=%s" % [_leg, _n, str(XRToolsGrabDriver.native_tick)])

	var a := Marker.new()
	a.process_physics_priority = -1000
	a.on_tick = func() -> void: _t0 = Time.get_ticks_usec()
	add_child(a)
	var b := Marker.new()
	b.process_physics_priority = -60
	b.on_tick = _end_tick
	add_child(b)

	var zone_scene := load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene
	for i in _n:
		var carrier := Node3D.new()
		carrier.position = Vector3((i % 20) * 0.5, 1.0, (i / 20) * 0.5)
		add_child(carrier)
		_carriers.append(carrier)
		var p := XRToolsPickable.new()
		p.name = "P%d" % i
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1, 0.02, 0.07)
		cs.shape = box
		p.add_child(cs)
		p.position = carrier.position + Vector3(0, 0.05, 0)
		add_child(p)
		if _leg == "hand":
			var g := Grab.new(Grabber.new(carrier), p, null, false)
			p.freeze = true
			p._grab_driver = XRToolsGrabDriver.create_snap(p, g)
		else:
			var z := zone_scene.instantiate() as XRToolsSnapZone
			z.grab_distance = 0.1
			carrier.add_child(z)
	for i in _zones:
		# Empty sockets elsewhere in the room: the hand-held preview search walks every live zone.
		var z := zone_scene.instantiate() as XRToolsSnapZone
		z.position = Vector3(i * 0.3, -5.0, 0)
		add_child(z)
	if _leg != "hand":
		await get_tree().physics_frame
		for i in _n:
			var z := _carriers[i].get_child(0) as XRToolsSnapZone
			z.pick_up_object(get_node("P%d" % i))


func _end_tick() -> void:
	var dt := Time.get_ticks_usec() - _t0
	_ticks += 1
	if _leg == "jitter":
		# Float noise, as a socket on an awake body gets: under is_equal_approx's tolerance, so nothing is pushed,
		# but the zone's transform notification wakes the driver every tick and it never rests.
		for c in _carriers:
			c.position.x += 1e-7 if _ticks % 2 == 0 else -1e-7
	elif _leg != "rest":
		for c in _carriers:
			c.position.x += 0.001
	if _ticks <= WARM:
		return
	_sum += dt
	_samples.append(dt)
	if _ticks == WARM + TICKS:
		_samples.sort()
		var awake := 0
		for d in get_tree().root.find_children("*_driver", "", true, false):
			var gd := d as XRToolsGrabDriver
			if gd != null and (gd._tick.is_physics_processing() if gd._tick != null else gd.is_physics_processing()):
				awake += 1
		var mean := float(_sum) / TICKS
		print("[gdprobe] leg=%s n=%d ticking=%d: band mean %.1f us/tick, median %d us, p95 %d us, %.3f us per driver"
			% [_leg, _n, awake, mean, _samples[TICKS / 2], _samples[TICKS * 95 / 100], mean / maxf(_n, 1)])
		get_tree().quit(0)
