## An empty snap zone that takes only what is DROPPED into it watches its sphere
## only while a hand holds something. All the time, the 151 empty sockets, bays
## and slots of the Starlight Arcade were 85% of Jolt's step (performance.md).
##   godot --headless --path RetroXR res://Tests/snap_watch_tests.tscn
extends "res://Tests/test_suite.gd"

const ZONE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")


func _ready() -> void:
	await _idle_and_held()
	await _range_and_full()
	await _kill_switch()
	await _object_gate()
	_finish()


func _zone(at: Vector3, mode: XRToolsSnapZone.SnapMode) -> XRToolsSnapZone:
	var z := ZONE.instantiate() as XRToolsSnapZone
	z.snap_mode = mode
	z.position = at
	add_child(z)
	return z


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle_and_held() -> void:
	var z := _zone(Vector3(0, 0, 0), XRToolsSnapZone.SnapMode.DROPPED)
	await _frames(3)
	_ok(not z.monitoring, "idle/an empty zone with nothing held does not watch")
	var held := Node.new()
	XRToolsSnapZone.note_hold(held, true)
	await _frames(2)
	_ok(z.monitoring, "held/a hand takes something: the empty zone watches")
	var second := Node.new()
	XRToolsSnapZone.note_hold(second, true)
	XRToolsSnapZone.note_hold(held, false)
	await _frames(2)
	_ok(z.monitoring, "held/one of two let go: it keeps watching")
	XRToolsSnapZone.note_hold(second, false)
	await _frames(2)
	_ok(z.monitoring, "release/the last let go: it still watches while the drop is taken")
	await get_tree().create_timer(XRToolsSnapZone.IDLE_OFF_DELAY + 0.2).timeout
	await _frames(2)
	_ok(not z.monitoring, "release/%.1f s on, it stops watching" % XRToolsSnapZone.IDLE_OFF_DELAY)
	# Let go, taken again and let go again inside the delay: the FIRST let-go's
	# stop must not land before the second drop has had its own delay.
	XRToolsSnapZone.note_hold(held, true)
	XRToolsSnapZone.note_hold(held, false)
	await get_tree().create_timer(XRToolsSnapZone.IDLE_OFF_DELAY * 0.5).timeout
	XRToolsSnapZone.note_hold(held, true)
	XRToolsSnapZone.note_hold(held, false)
	await get_tree().create_timer(XRToolsSnapZone.IDLE_OFF_DELAY * 0.7).timeout
	await _frames(2)
	_ok(z.monitoring, "release/a second let-go gets its own delay, not what was left of the first")
	await get_tree().create_timer(XRToolsSnapZone.IDLE_OFF_DELAY * 0.6).timeout
	await _frames(2)
	_ok(not z.monitoring, "release/and stops when that has run out")
	held.free()
	second.free()
	z.free()


func _range_and_full() -> void:
	var r := _zone(Vector3(2, 0, 0), XRToolsSnapZone.SnapMode.RANGE)
	await _frames(3)
	_ok(r.monitoring, "range/a RANGE zone snaps what arrives, so it always watches")
	var full := _zone(Vector3(4, 0, 0), XRToolsSnapZone.SnapMode.DROPPED)
	var thing := XRToolsPickable.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	thing.add_child(shape)
	thing.position = Vector3(4, 0, 0)
	add_child(thing)
	await _frames(2)
	full.pick_up_object(thing)
	var held := Node.new()
	XRToolsSnapZone.note_hold(held, true)
	await _frames(2)
	_ok(not full.monitoring, "full/a zone holding something does not watch, held or not")
	XRToolsSnapZone.note_hold(held, false)
	await get_tree().create_timer(XRToolsSnapZone.IDLE_OFF_DELAY + 0.2).timeout
	held.free()
	full.drop_object()
	thing.free()
	r.free()
	full.free()


func _kill_switch() -> void:
	XRToolsSnapZone.idle_unmonitored = false
	var z := _zone(Vector3(6, 0, 0), XRToolsSnapZone.SnapMode.DROPPED)
	await _frames(3)
	_ok(z.monitoring, "switch/with idle_unmonitored off, an empty zone watches as it always did")
	XRToolsSnapZone.idle_unmonitored = true
	XRToolsSnapZone._apply_all_monitoring("snap_watch_tests")
	await _frames(2)
	_ok(not z.monitoring, "switch/on again, it stops")
	z.free()


## An object's own snap_gate: no preview and no "no reason found" while it says no,
## and the zone takes it once it says yes (a PocketStation's cover, xenu.pocketstation).
func _object_gate() -> void:
	var z := _zone(Vector3(8, 0, 0), XRToolsSnapZone.SnapMode.DROPPED)
	z.snap_require = "gate_test"
	var obj := Node3D.new()
	obj.add_to_group("gate_test")
	add_child(obj)
	await _frames(2)
	_ok(z.can_preview(obj), "gate/with no gate, the zone previews it")
	var shut := {"why": "cover shut"}
	obj.set_meta(XRToolsSnapZone.SNAP_GATE_META, func(_zone: XRToolsSnapZone) -> String: return str(shut["why"]))
	_ok(not z.can_preview(obj), "gate/the object saying no stops the preview")
	_ok(XRToolsSnapZone.gate_refusal(obj, z) == "cover shut", "gate/and says why")
	_ok("cover shut" in z._why_no_preview(obj), "gate/the preview log names the object's reason")
	shut["why"] = ""
	_ok(z.can_preview(obj), "gate/saying yes lets it in again")
	obj.set_meta(XRToolsSnapZone.SNAP_GATE_META, Callable())
	_ok(z.can_preview(obj), "gate/an invalid gate is no gate")
	obj.free()
	z.free()
