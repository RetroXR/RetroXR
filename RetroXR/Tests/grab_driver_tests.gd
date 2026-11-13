## XRToolsGrabDriver self-tests: the C++ tick (grab-godot's GrabDriverTick) against the GDScript one it replaced.
##
##     "$godot" --headless --path RetroXR res://Tests/grab_driver_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## One scripted room is played twice, tick for tick, once with XRToolsGrabDriver.native_tick off (the GDScript
## _physics_process, which is the reference) and once with it on, and every driven object's pose is recorded after the
## drivers have run each physics tick. The two recordings must agree (`ab/`). What is in the room covers every branch
## of the tick: objects resting in sockets that settle and stop ticking and wake when the socket moves (`rest/`), a
## cartridge in a console in a socket that is carried (a stack, whose drivers must run in order: `stack/`), a lerp
## from a ranged grab into a hand that then carries the object past an empty socket that previews it (`preview/`), a
## two-handed hold with aim (`two_hand/`), a swivel-mounted thing that constrains its own hold (`constrain/`), a target
## freed while held (`freed/`), and the holder graph changing under resting drivers (`epoch/`). The checks outside
## `ab/` hold for BOTH runs, so a fault common to the two is caught too.
extends "res://Tests/test_suite.gd"

const TICKS := 150
const DRIVEN := ["A", "B", "C", "D", "F", "G", "L"]

var _world: Node3D
var _nodes: Dictionary = {}
var _tick := 0
var _frames: Array = []
var _notes: Dictionary = {}
var _native_run := false


class Marker extends Node:
	var on_tick: Callable
	func _physics_process(_d: float) -> void:
		on_tick.call()


func _ready() -> void:
	suite_tag = "grab_driver"
	show_pass_detail = true
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[grab_driver] TIMED OUT")
		get_tree().quit(1))
	var have_native := ClassDB.class_exists(&"GrabDriverTick")
	_ok(have_native, "native/grab-godot's GrabDriverTick is loaded (python Tools/build.py <platform> --only grab-godot)")
	_ok(XRToolsGrabDriver.native_tick == have_native, "native/drivers tick in C++ by default wherever the class exists")
	var was: bool = XRToolsGrabDriver.native_tick

	XRToolsGrabDriver.native_tick = false
	var gd := await _run(false)
	if have_native:
		XRToolsGrabDriver.native_tick = true
		var cpp := await _run(true)
		_compare(gd, cpp)
	XRToolsGrabDriver.native_tick = was
	_finish()


## The scripted room, played once. Returns {frames: [{name: Transform3D}], notes: {...}}.
func _run(native: bool) -> Dictionary:
	_native_run = native
	_nodes.clear()
	_frames = []
	_notes = {}
	_tick = 0
	_world = Node3D.new()
	_world.name = "World_%s" % ("cpp" if native else "gd")
	add_child(_world)
	var before := Marker.new()
	before.process_physics_priority = -100   # before every driver (hands -80, sockets -70 and down the stack)
	before.on_tick = _script_tick
	_world.add_child(before)
	var after := Marker.new()
	after.process_physics_priority = 100     # after every driver
	after.on_tick = _record_tick
	_world.add_child(after)
	_build()
	var label := "cpp" if native else "gd"
	await _wait_until(func() -> bool: return _tick >= TICKS, 30.0)
	_ok(_tick >= TICKS, "%s/the scripted room ran its %d ticks" % [label, TICKS], str(_tick))
	_checks(label)
	var out := {"frames": _frames, "notes": _notes}
	_world.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


func _pickable(n: String, at: Vector3, size: Vector3, script: Script = null) -> XRToolsPickable:
	var p: XRToolsPickable = script.new() if script != null else XRToolsPickable.new()
	p.name = n
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	p.add_child(cs)
	p.position = at
	p.gravity_scale = 0.0
	_world.add_child(p)
	_nodes[n] = p
	return p


func _zone(n: String, parent: Node3D, at: Vector3, distance: float = 0.1) -> XRToolsSnapZone:
	var z := (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate() as XRToolsSnapZone
	z.name = n
	z.grab_distance = distance
	z.position = at
	parent.add_child(z)
	_nodes[n] = z
	return z


func _node(n: String, at: Vector3, parent: Node3D = null) -> Node3D:
	var h := Node3D.new()
	h.name = n
	h.position = at
	(parent if parent != null else _world).add_child(h)
	_nodes[n] = h
	return h


func _build() -> void:
	# rest/: a cartridge resting in a socket on a carrier that moves only between ticks 50 and 60.
	var c1 := _node("Carrier1", Vector3(0, 1, 0))
	_zone("Z1", c1, Vector3.ZERO)
	_pickable("A", Vector3(0.03, 1.04, 0.01), Vector3(0.1, 0.02, 0.07))
	# stack/: a console B in socket Z2 on a carrier, with a cartridge C in the console's own socket Z3.
	var c2 := _node("Carrier2", Vector3(2, 1, 0))
	_zone("Z2", c2, Vector3.ZERO, 0.3)
	var b := _pickable("B", Vector3(2.02, 1.02, 0), Vector3(0.3, 0.08, 0.2))
	_zone("Z3", b, Vector3(0, 0.06, 0.02))
	_pickable("C", Vector3(2.05, 1.12, 0.03), Vector3(0.1, 0.02, 0.07))
	# preview/: an object lerped into a hand from range, carried past an empty socket that previews it.
	_node("H", Vector3(-2, 1, 0))
	var d := _pickable("D", Vector3(-2.4, 1.1, 0.05), Vector3(0.1, 0.02, 0.07))
	d.add_to_group("cart")
	d.rotation = Vector3(0.2, 0.4, 0.1)
	var z4 := _zone("Z4", _world, Vector3(-2, 1, 0.5))
	z4.snap_require = "cart"
	z4.rotation = Vector3(0, 0.6, 0)
	z4.preview_offset = Vector3(0, 0.02, 0)
	# two_hand/: one object, two hands, the second aiming.
	_node("H2a", Vector3(4, 1, 0))
	_node("H2b", Vector3(4.3, 1.1, 0.1))
	_pickable("F", Vector3(4, 1, 0), Vector3(0.4, 0.05, 0.05))
	# constrain/: a thing that says where its hold really puts it (a gun on a swivel).
	_node("H3", Vector3(6, 1, 0))
	var src := GDScript.new()
	src.source_code = "extends \"res://addons/godot-xr-tools/objects/pickable.gd\"\n" \
		+ "func constrain_grab(d: Transform3D) -> Transform3D:\n" \
		+ "\treturn Transform3D(d.basis.orthonormalized(), Vector3(6, 1.5, 0))\n"
	src.reload()
	_pickable("G", Vector3(6, 1, 0), Vector3(0.1, 0.1, 0.3), src)
	# freed/ and epoch/: a socket whose object is freed while held, which later takes another.
	var c5 := _node("Carrier5", Vector3(8, 1, 0))
	_zone("Z5", c5, Vector3.ZERO)
	_pickable("K", Vector3(8, 1.03, 0), Vector3(0.1, 0.02, 0.07))
	_pickable("L", Vector3(8.2, 1.0, 0.1), Vector3(0.1, 0.02, 0.07))


func _n(n: String) -> Node3D:
	return _nodes.get(n) as Node3D


## Before every driver, each tick: what happens in the room.
func _script_tick() -> void:
	var t := _tick
	var s := float(t) / 60.0
	if t == 1:
		# Assembled leaf first (the order that once had a stack's drivers backwards).
		(_n("Z3") as XRToolsSnapZone).pick_up_object(_n("C"))
		(_n("Z2") as XRToolsSnapZone).pick_up_object(_n("B"))
		(_n("Z1") as XRToolsSnapZone).pick_up_object(_n("A"))
		(_n("Z5") as XRToolsSnapZone).pick_up_object(_n("K"))
		_hand_grab("D", "H", true, false)
		_hand_grab("F", "H2a", false, false)
		var g2 := Grab.new(Grabber.new(_n("H2b")), _n("F") as XRToolsPickable, null, true)
		g2.drive_position = 0.4
		g2.drive_angle = 0.25
		g2.drive_aim = 0.6
		(_n("F") as XRToolsPickable)._grab_driver.add_grab(g2)
		_hand_grab("G", "H3", false, false)
	# rest/: the carrier moves only from 50 to 60.
	if t > 50 and t <= 60:
		_n("Carrier1").position += Vector3(0.004, 0.001, -0.002)
		_n("Carrier1").rotation.y += 0.03
	# stack/: the console's socket is carried from 20 to 60.
	if t > 20 and t <= 60:
		_n("Carrier2").position += Vector3(0.0, 0.003, 0.005)
		_n("Carrier2").rotation += Vector3(0.01, 0.02, 0.0)
	# preview/: the hand goes to the empty socket (10-40), waits (40-60), leaves (60-90).
	var h := _n("H")
	if t > 10 and t <= 40:
		h.position = Vector3(-2, 1, 0).lerp(Vector3(-2.01, 1.0, 0.5), (t - 10) / 30.0)
		h.rotation.x += 0.01
	elif t > 60 and t <= 90:
		h.position = Vector3(-2.01, 1.0, 0.5).lerp(Vector3(-2.3, 1.2, 1.2), (t - 60) / 30.0)
	# two_hand/ and constrain/: always moving.
	_n("H2a").position = Vector3(4, 1, 0) + Vector3(cos(s * 3.0), sin(s * 2.0), 0) * 0.1
	_n("H2a").rotation = Vector3(s * 0.5, s, 0)
	_n("H2b").position = Vector3(4.3, 1.1, 0.1) + Vector3(0, cos(s * 4.0), sin(s * 3.0)) * 0.1
	_n("H3").position = Vector3(6, 1, 0) + Vector3(sin(s * 2.0), 0, cos(s * 2.0)) * 0.2
	_n("H3").rotation = Vector3(0, s * 2.0, s)
	# freed/: the object in Z5 goes while held.
	if t == 80:
		_n("K").free()
		_nodes.erase("K")
	# epoch/: Z5 takes L, which changes the holder graph under every resting driver.
	if t == 100:
		(_n("Z5") as XRToolsSnapZone).pick_up_object(_n("L"))
	_tick += 1


func _hand_grab(obj: String, hand: String, lerp: bool, precise: bool) -> void:
	var p := _n(obj) as XRToolsPickable
	p.freeze = true
	var g := Grab.new(Grabber.new(_n(hand)), p, null, precise)
	p._grab_driver = XRToolsGrabDriver.create_lerp(p, g, 2.5) if lerp else XRToolsGrabDriver.create_snap(p, g)
	_nodes[obj + "_driver"] = p._grab_driver


func _driver(obj: String) -> XRToolsGrabDriver:
	var p := _nodes.get(obj) as XRToolsPickable
	if p == null or not is_instance_valid(p):
		return null
	return p._grab_driver


## Whether a driver's tick runs this frame, whichever of the two runs it.
func _ticking(obj: String) -> bool:
	var d := _driver(obj)
	if d == null:
		return false
	return d._tick.is_physics_processing() if d._tick != null else d.is_physics_processing()


## After every driver, each tick: what each driven object is now.
func _record_tick() -> void:
	var t := _tick - 1
	var row := {}
	for n: String in DRIVEN:
		var p := _n(n)
		if p != null and is_instance_valid(p):
			row[n] = p.global_transform
	_frames.append(row)
	# What only one tick can show.
	if t == 45:
		_notes["A_ticking_at_45"] = _ticking("A")
		_notes["D_blend_at_45"] = _driver("D")._preview_blend
		_notes["D_to_preview_at_45"] = _n("D").global_position.distance_to(
			(_n("Z4") as XRToolsSnapZone).preview_pose_for(_n("D"), 1.0).origin)
		_notes["D_state_at_45"] = _driver("D").state
	if t == 55:
		_notes["A_ticking_at_55"] = _ticking("A")
		_notes["A_to_zone_at_55"] = _n("A").global_position.distance_to(_n("Z1").global_position)
	if t == 40:
		_notes["C_to_zone_at_40"] = _n("C").global_position.distance_to(_n("Z3").global_position)
		_notes["B_to_zone_at_40"] = _n("B").global_position.distance_to(_n("Z2").global_position)
		var dc := _driver("C")
		var db := _driver("B")
		_notes["C_priority"] = dc.process_physics_priority
		_notes["B_priority"] = db.process_physics_priority
		if dc._tick != null:
			_notes["C_tick_priority"] = dc._tick.process_physics_priority
			_notes["C_driver_self_ticking"] = dc.is_physics_processing()
	if t == 95:
		_notes["D_blend_at_95"] = _driver("D")._preview_blend
		_notes["D_to_hand_at_95"] = _n("D").global_position.distance_to(_n("H").global_position)
		_notes["G_origin_at_95"] = _n("G").global_position
		_notes["A_ticking_at_95"] = _ticking("A")
	if t == 79:
		_nodes["K_zone_driver"] = _driver("K")
	if t == 101:
		_notes["A_ticking_at_101"] = _ticking("A")
	if t == 105:
		# A driver at rest when its target went is not ticking to notice: the next wake (here Z5 taking L, which
		# changes the holder graph) finds it, and it goes then.
		_notes["K_driver_gone"] = not is_instance_valid(_nodes.get("K_zone_driver"))
	if t == TICKS - 1:
		_notes["A_ticking_at_end"] = _ticking("A")
		_notes["L_to_zone_at_end"] = _n("L").global_position.distance_to(_n("Z5").global_position)


func _checks(label: String) -> void:
	var nt := _notes
	_ok(nt.get("A_ticking_at_45") == false, "%s/rest/a driver resting in a socket that has not moved stops ticking" % label,
		str(nt.get("A_ticking_at_45")))
	_ok(nt.get("A_ticking_at_55") == true, "%s/rest/its socket moving wakes it" % label, str(nt.get("A_ticking_at_55")))
	_ok(float(nt.get("A_to_zone_at_55", 1.0)) < 1e-4, "%s/rest/and it is where the moving socket is, the same tick" % label,
		str(nt.get("A_to_zone_at_55")))
	_ok(nt.get("A_ticking_at_95") == false, "%s/rest/it rests again once the socket is still" % label,
		str(nt.get("A_ticking_at_95")))
	_ok(nt.get("A_ticking_at_101") == true, "%s/epoch/the holder graph changing wakes a resting driver" % label,
		str(nt.get("A_ticking_at_101")))
	_ok(nt.get("A_ticking_at_end") == false, "%s/epoch/and it rests again" % label, str(nt.get("A_ticking_at_end")))
	_ok(float(nt.get("C_to_zone_at_40", 1.0)) < 1e-4 and float(nt.get("B_to_zone_at_40", 1.0)) < 1e-4,
		"%s/stack/console and cartridge are in their carried sockets the same tick (no frame of trail)" % label,
		"C %s, B %s" % [str(nt.get("C_to_zone_at_40")), str(nt.get("B_to_zone_at_40"))])
	_ok(int(nt.get("C_priority", 0)) == -69 and int(nt.get("B_priority", 0)) == -70,
		"%s/stack/the cartridge's driver runs after the console's (-69 after -70)" % label,
		"C %s, B %s" % [str(nt.get("C_priority")), str(nt.get("B_priority"))])
	if _native_run:
		_ok(int(nt.get("C_tick_priority", 0)) == -69, "cpp/stack/the C++ tick runs at its driver's priority",
			str(nt.get("C_tick_priority")))
		_ok(nt.get("C_driver_self_ticking") == false, "cpp/native/the script's own _physics_process is off",
			str(nt.get("C_driver_self_ticking")))
	_ok(int(nt.get("D_state_at_45", -1)) == XRToolsGrabDriver.GrabState.SNAP,
		"%s/preview/the ranged grab's lerp has arrived" % label, str(nt.get("D_state_at_45")))
	_ok(float(nt.get("D_blend_at_45", 0.0)) >= 1.0 and float(nt.get("D_to_preview_at_45", 1.0)) < 1e-3,
		"%s/preview/held at the empty socket, the object is shown in it" % label,
		"blend %s, %s m off" % [str(nt.get("D_blend_at_45")), str(nt.get("D_to_preview_at_45"))])
	_ok(float(nt.get("D_blend_at_95", 1.0)) <= 0.0 and float(nt.get("D_to_hand_at_95", 1.0)) < 0.5,
		"%s/preview/carried away, it is back in the hand" % label,
		"blend %s, %s m from the hand" % [str(nt.get("D_blend_at_95")), str(nt.get("D_to_hand_at_95"))])
	_ok((nt.get("G_origin_at_95", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(6, 1.5, 0)),
		"%s/constrain/the object's own constrain_grab decides where the hold puts it" % label, str(nt.get("G_origin_at_95")))
	_ok(nt.get("K_driver_gone") == true, "%s/freed/a driver whose target was freed while held goes away" % label)
	_ok(float(nt.get("L_to_zone_at_end", 1.0)) < 1e-4, "%s/epoch/the socket that lost its object takes another" % label,
		str(nt.get("L_to_zone_at_end")))


func _compare(gd: Dictionary, cpp: Dictionary) -> void:
	var fa: Array = gd["frames"]
	var fb: Array = cpp["frames"]
	_ok(fa.size() == fb.size() and fa.size() >= TICKS, "ab/both runs recorded every tick", "%d / %d" % [fa.size(), fb.size()])
	for n: String in DRIVEN:
		var worst := 0.0
		var worst_tick := -1
		var missing := 0
		var moved := 0.0
		for i in mini(fa.size(), fb.size()):
			var ra: Dictionary = fa[i]
			var rb: Dictionary = fb[i]
			if ra.has(n) != rb.has(n):
				missing += 1
				continue
			if not ra.has(n):
				continue
			var a: Transform3D = ra[n]
			var b: Transform3D = rb[n]
			var dev := maxf(a.origin.distance_to(b.origin), maxf((a.basis.x - b.basis.x).length(),
				maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length())))
			if dev > worst:
				worst = dev
				worst_tick = i
			if i > 0 and (fa[i - 1] as Dictionary).has(n):
				var p: Transform3D = (fa[i - 1] as Dictionary)[n]
				moved = maxf(moved, maxf(a.origin.distance_to(p.origin), (a.basis.x - p.basis.x).length()))
		_ok(missing == 0 and worst < 1e-5,
			"ab/%s: the C++ tick puts it where the GDScript tick did, every tick" % n,
			"worst %s at tick %d, %d ticks present in one run only" % [str(worst), worst_tick, missing])
		# A comparison of two objects that never moved would pass on anything.
		if n != "L":
			_ok(moved > 1e-4, "ab/%s: and it moved in the run (the comparison can tell)" % n, "%.4f in a tick" % moved)
	for k: String in gd["notes"]:
		if k.begins_with("C_tick") or k == "C_driver_self_ticking":
			continue
		var va: Variant = gd["notes"][k]
		var vb: Variant = cpp["notes"].get(k)
		var same: bool = (absf(float(va) - float(vb)) < 1e-5) if (va is float) else (va == vb)
		_ok(same, "ab/note %s is the same in both runs" % k, "%s / %s" % [str(va), str(vb)])
