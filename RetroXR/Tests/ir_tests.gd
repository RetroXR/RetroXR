## Infrared self-tests — which windows in a room are a pair, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/ir_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## A link cable is decided by which sockets its plugs are in. Infrared is
## decided by where two machines are and which way they look, so what is here
## is geometry (IrBus.in_view), the pairing that comes out of it (nearest
## partner, a dwell before a link and before a part, nothing in the way), and
## the hand-off of every change to a netplay session.
##
## Whether a linked pair actually trades a Mystery Gift needs two cores and two
## cartridges and is Tools/link/gbc_ir_room_probe; no core runs here. Which is
## also why nothing here ever lights a window by itself: the glow follows the
## cores' own peer count, and without a core that is nought.
extends Node

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CART_SCENE := "res://Scenes/Objects/media/cartridge.tscn"

var _pass := 0
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[ir] TIMEOUT")
		get_tree().quit(1))
	_test_view()
	await _test_pairing()
	await _test_hysteresis()
	await _test_power_and_family()
	await _test_nearest_wins()
	await _test_sight()
	await _test_rejoin_and_teardown()
	await _test_netplay()
	await _test_the_machine()
	await _test_two_machines()
	print("[ir] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ── harness ──────────────────────────────────────────────────────────────────

func _ok(cond: bool, name: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[ir] PASS  %s" % name)
	else:
		_fail += 1
		print("[ir] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(got: Variant, want: Variant, name: String) -> void:
	_ok(got == want, name, "got %s, want %s" % [str(got), str(want)])


## A machine as IrBus sees one: something that is on or off and has a core
## node. Its window is at its own origin, looking along its -Z.
class _Machine extends Node3D:
	var is_powered_on := true
	var libretro: Libretro = null
	var port: IrPort = null

	func get_libretro_node() -> Libretro:
		return libretro


class _Session extends RefCounted:
	var running := true
	var host := true
	var covered: Array = []
	var preparing: Array = []
	var scheduled: Array = []

	func netplay_running() -> bool:
		return running

	func netplay_covers(machine: Object) -> bool:
		return running and covered.has(machine)

	func netplay_prepares(machine: Object) -> bool:
		return not running and preparing.has(machine)

	func is_host() -> bool:
		return host

	func netplay_schedule_link(op: int, entries: Array) -> void:
		scheduled.append({"op": op, "entries": entries.duplicate(true)})


func _machine(label: String, at: Transform3D) -> _Machine:
	var m := _Machine.new()
	m.name = label
	m.libretro = Libretro.new()
	m.add_child(m.libretro)
	m.port = IrPort.new()
	m.port.name = "IrPort"
	m.add_child(m.port)
	add_child(m)
	m.global_transform = at
	# Stepped by hand below; a look arriving on its own between two steps would
	# be a dwell nobody counted.
	m.port.set_physics_process(false)
	return m


## A transform at `from` whose -Z looks at `at`.
func _looking(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


func _looks(n: int) -> void:
	for i in range(n):
		IrBus.look(get_tree())


func _paired(a: _Machine, b: _Machine) -> bool:
	return a.port.partner() == b.port and b.port.partner() == a.port


func _clear(nodes: Array) -> void:
	for node: Variant in nodes:
		if is_instance_valid(node):
			(node as Node).queue_free()
	await get_tree().process_frame
	IrBus.reset()


# ── what a window can see ────────────────────────────────────────────────────

func _test_view() -> void:
	var link := IrBus.LINK_RANGE
	var hold := IrBus.UNLINK_RANGE
	var a := _looking(Vector3.ZERO, Vector3(0, 0, -1))
	# The dwell cases below count looks, so they hold for any dwell at all. What
	# a dwell is FOR is time: a window swept past another, or a hand through
	# the beam, lasts a tenth of a second or two.
	var look := float(IrBus.LOOK_TICKS) / float(Engine.physics_ticks_per_second)
	_ok(IrBus.LINK_DWELL * look >= 0.2 and IrBus.LINK_DWELL * look <= 0.6,
		"view/a pair has to hold a moment before it links, and not a long one",
		"%.2f s" % (IrBus.LINK_DWELL * look))
	_ok(IrBus.UNLINK_DWELL * look >= 0.2 and IrBus.UNLINK_DWELL * look <= 0.6,
		"view/and be lost for a moment before it parts",
		"%.2f s" % (IrBus.UNLINK_DWELL * look))
	_ok(IrBus.LINK_ANGLE > 45.0, "view/the beam is wider than 45 degrees either side",
		"%.0f" % IrBus.LINK_ANGLE)
	_ok(IrBus.UNLINK_RANGE > IrBus.LINK_RANGE and IrBus.UNLINK_ANGLE > IrBus.LINK_ANGLE,
		"view/it takes more to part a pair than to make one")

	var facing := func(distance: float) -> Transform3D:
		return _looking(Vector3(0, 0, -distance), Vector3.ZERO)
	_ok(IrBus.in_view(a, facing.call(0.30), link, IrBus.LINK_ANGLE),
		"view/two windows face to face at 30 cm see each other")
	_ok(IrBus.in_view(a, facing.call(link - 0.005), link, IrBus.LINK_ANGLE),
		"view/and at the edge of reach")
	_ok(not IrBus.in_view(a, facing.call(link + 0.01), link, IrBus.LINK_ANGLE),
		"view/but not a centimetre past it")
	_ok(IrBus.in_view(a, facing.call(link + 0.01), hold, IrBus.UNLINK_ANGLE),
		"view/where a pair already linked still holds")
	_ok(not IrBus.in_view(a, facing.call(hold + 0.01), hold, IrBus.UNLINK_ANGLE),
		"view/until it is past that reach too")

	# The partner swung round the first window: still looking straight back at
	# it, so only the first window's own angle is in question.
	var around := func(degrees: float) -> Transform3D:
		var at := Vector3(0, 0, -0.30).rotated(Vector3.UP, deg_to_rad(degrees))
		return _looking(at, Vector3.ZERO)
	_ok(IrBus.in_view(a, around.call(IrBus.LINK_ANGLE - 1.0), link, IrBus.LINK_ANGLE),
		"view/a partner just inside the beam is seen")
	_ok(not IrBus.in_view(a, around.call(IrBus.LINK_ANGLE + 1.0), link, IrBus.LINK_ANGLE),
		"view/and just outside it is not")
	_ok(IrBus.in_view(a, around.call(IrBus.LINK_ANGLE + 1.0), hold, IrBus.UNLINK_ANGLE),
		"view/though a linked pair holds there")
	_ok(not IrBus.in_view(a, around.call(IrBus.UNLINK_ANGLE + 1.0), hold, IrBus.UNLINK_ANGLE),
		"view/and lets go past the wider angle")
	_ok(not IrBus.in_view(a, around.call(-IrBus.LINK_ANGLE - 1.0), link, IrBus.LINK_ANGLE),
		"view/the same on the other side")

	# Both ways round. Each of these has ONE window looking at the other, so a
	# rule that asked only one of them would pass one and fail the other.
	var away := Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(0, 0, -0.30))
	_ok(not IrBus.in_view(a, away, link, IrBus.LINK_ANGLE),
		"view/a window looking at one that looks away is not a pair")
	_ok(not IrBus.in_view(away, a, link, IrBus.LINK_ANGLE),
		"view/whichever of the two is asked")

	# Side by side and looking the same way: the two beams overlap from a hand's
	# width out to the end of their reach, and neither window is in the other's.
	var beside := _looking(Vector3(0.10, 0, 0), Vector3(0.10, 0, -1))
	_ok(not IrBus.in_view(a, beside, link, IrBus.LINK_ANGLE),
		"view/two windows side by side, looking the same way, see nothing")

	# The beam leaves along -Z. Behind the window is +Z, and a partner there,
	# looking at its back, is unseen.
	var behind := _looking(Vector3(0, 0, 0.30), Vector3.ZERO)
	_ok(not IrBus.in_view(a, behind, link, IrBus.LINK_ANGLE),
		"view/a window does not see what is behind it")


# ── pairing ──────────────────────────────────────────────────────────────────

func _test_pairing() -> void:
	IrBus.reset()
	# Made in the other order to the one their names sort in, so the head is
	# shown to come from the name.
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -0.30)))
	_ok(a.port.is_in_group(IrBus.PORT_GROUP), "pair/a window is in the bus's group")
	_ok(a.port.is_in_group(LinkPlug.ANY_GROUP), "pair/and in the one every lead sweep reads")
	_eq(a.port.link_port, 1, "pair/a Game Boy Color's transceiver is link port 1")
	_eq(a.port.cable, a.port, "pair/a window alone speaks for itself")
	_eq(a.port.linked_machines().size(), 0, "pair/and is on no bus")

	_looks(IrBus.LINK_DWELL - 1)
	_ok(not _paired(a, b), "pair/a pair in view is not linked before it has held")
	_eq(IrBus.joins, 0, "pair/and nothing has been said to the cores")
	_looks(1)
	_ok(_paired(a, b), "pair/it is linked once it has")
	_eq(IrBus.joins, 1, "pair/with one join")
	_looks(5)
	_eq(IrBus.joins, 1, "pair/and it is not joined again while it holds")

	var bus_a := a.port.linked_machines()
	var bus_b := b.port.linked_machines()
	_eq(bus_a.size(), 2, "pair/each window states the whole bus")
	_eq(bus_a, bus_b, "pair/and they state the same one")
	if bus_a.size() == 2:
		_eq(bus_a[0]["machine"], a, "pair/the head is the machine whose name sorts first")
		_eq([int(bus_a[0]["port"]), int(bus_a[1]["port"])], [1, 1], "pair/both on link port 1")
	_eq(a.port.cable, b.port.cable, "pair/both windows name ONE lead, so a sweep keeps the bus once")
	_eq(a.port.held_machines().size(), 2, "pair/and it is held, not just described")

	# No core has attached, so the cores cannot hear each other, and the window
	# says so: in view is not linked.
	_ok(not a.port.is_live() and not b.port.is_live(),
		"pair/a pair whose cores are not on the bus does not light its windows")
	await _clear([a, b])


func _test_hysteresis() -> void:
	IrBus.reset()
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	_looks(IrBus.LINK_DWELL)
	_ok(_paired(a, b), "hold/a pair to start from")

	b.global_transform = _looking(Vector3(0, 1, -0.70), Vector3(0, 1, 0))
	_looks(IrBus.UNLINK_DWELL + 4)
	_ok(_paired(a, b), "hold/carried out to 70 cm, past where it could link, it holds")
	_eq(IrBus.joins, 1, "hold/and is not rejoined")

	b.global_transform = _looking(Vector3(0, 1, -0.90), Vector3(0, 1, 0))
	_looks(IrBus.UNLINK_DWELL - 1)
	_ok(_paired(a, b), "hold/out of reach, it is not parted before the dwell")
	_looks(1)
	_ok(not _paired(a, b), "hold/and is parted after it")
	_eq(a.port.linked_machines().size(), 0, "hold/leaving the window on no bus")

	b.global_transform = _looking(Vector3(0, 1, -0.70), Vector3(0, 1, 0))
	_looks(IrBus.LINK_DWELL + 4)
	_ok(not _paired(a, b), "hold/and 70 cm does not link it again")

	# A hand through the beam: out for less than the dwell, back, out again for
	# less than the dwell. Two blips are not one loss.
	b.global_transform = _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0))
	_looks(IrBus.LINK_DWELL)
	_ok(_paired(a, b), "hold/linked again up close")
	var joins := IrBus.joins
	for blip in range(2):
		b.global_transform = _looking(Vector3(0, 1, -0.90), Vector3(0, 1, 0))
		_looks(IrBus.UNLINK_DWELL - 1)
		b.global_transform = _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0))
		_looks(1)
	_ok(_paired(a, b), "hold/two short losses do not add up to a part")
	_eq(IrBus.joins, joins, "hold/nor to a rejoin")

	# And a window swept past another is not a link.
	b.global_transform = _looking(Vector3(0, 1, -0.90), Vector3(0, 1, 0))
	_looks(IrBus.UNLINK_DWELL)
	for sweep in range(3):
		b.global_transform = _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0))
		_looks(IrBus.LINK_DWELL - 1)
		b.global_transform = _looking(Vector3(0, 1, -0.90), Vector3(0, 1, 0))
		_looks(1)
	_ok(not _paired(a, b), "hold/a window swept past another three times never links")
	_eq(IrBus.joins, joins, "hold/and the cores are never told")
	await _clear([a, b])


func _test_power_and_family() -> void:
	IrBus.reset()
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	b.is_powered_on = false
	_looks(IrBus.LINK_DWELL + 3)
	_ok(not _paired(a, b), "power/a machine that is off is nobody's partner")
	b.is_powered_on = true
	_looks(IrBus.LINK_DWELL)
	_ok(_paired(a, b), "power/switched on, it is")
	a.is_powered_on = false
	_looks(1)
	_ok(not _paired(a, b), "power/and a pair is parted at once when either is switched off")
	a.is_powered_on = true

	b.port.ir_family = "tv_remote"
	_looks(IrBus.LINK_DWELL + 3)
	_ok(not _paired(a, b), "power/a window of another family is no partner")
	await _clear([a, b])


func _test_nearest_wins() -> void:
	IrBus.reset()
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var near := _machine("Gbc_near", _looking(Vector3(-0.05, 1, -0.20), Vector3(0, 1, 0)))
	var far := _machine("Gbc_far", _looking(Vector3(0.10, 1, -0.40), Vector3(0, 1, 0)))
	_ok(IrBus.in_view(a.global_transform, far.global_transform, IrBus.LINK_RANGE, IrBus.LINK_ANGLE),
		"nearest/the further one could be a partner too")
	_looks(IrBus.LINK_DWELL + 2)
	_ok(_paired(a, near), "nearest/a window between two takes the nearer")
	_eq(far.port.partner(), null, "nearest/and the further is left alone: a window has one partner")
	_eq(IrBus.joins, 1, "nearest/one pair, one join")

	near.is_powered_on = false
	_looks(IrBus.LINK_DWELL + 1)
	_ok(_paired(a, far), "nearest/with the nearer one off, the further is taken")
	await _clear([a, near, far])


func _test_sight() -> void:
	IrBus.reset()
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.40), Vector3(0, 1, 0)))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.30, 0.30, 0.02)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.collision_layer = 1
	wall.global_position = Vector3(0, 1, -0.20)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_ok(not IrBus.sight_clear(a.port, b.port), "sight/a wall between two windows is in the way")
	_looks(IrBus.LINK_DWELL + 3)
	_ok(not _paired(a, b), "sight/so they do not link, though each is in the other's beam")

	# Beside the line rather than across it: the same wall is no obstacle.
	wall.global_position = Vector3(0.40, 1, -0.20)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(IrBus.sight_clear(a.port, b.port), "sight/the same wall beside the line is not")
	_looks(IrBus.LINK_DWELL)
	_ok(_paired(a, b), "sight/and they link")

	wall.global_position = Vector3(0, 1, -0.20)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_looks(IrBus.UNLINK_DWELL - 1)
	_ok(_paired(a, b), "sight/a wall put between a pair does not part it before the dwell")
	_looks(1)
	_ok(not _paired(a, b), "sight/and does after it")

	# A hand is not furniture: what stands in the way is the room and the loose
	# things in it.
	wall.collision_layer = 1 << 17
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(IrBus.sight_clear(a.port, b.port), "sight/a hand's own collider between them does not block")
	wall.collision_layer = 1 << 2
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(not IrBus.sight_clear(a.port, b.port), "sight/a loose object between them does")
	await _clear([a, b, wall])


func _test_rejoin_and_teardown() -> void:
	IrBus.reset()
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	_looks(IrBus.LINK_DWELL)
	_eq(IrBus.joins, 1, "rejoin/a pair to start from")

	# A core restarted without anything in the room moving: the wire went with
	# the old core, and saying it again is one more join.
	b.port.rejoin()
	_eq(IrBus.joins, 2, "rejoin/a restarted core's pair is stated again")
	_ok(_paired(a, b), "rejoin/and is still a pair")

	b.is_powered_on = false
	a.port.rejoin()
	_eq(IrBus.joins, 2, "rejoin/a machine switched off is not rejoined")
	_ok(not _paired(a, b), "rejoin/and its pair is gone")

	b.is_powered_on = true
	_looks(IrBus.LINK_DWELL)
	_ok(_paired(a, b), "teardown/a pair again")
	b.queue_free()
	await get_tree().process_frame
	_eq(a.port.partner(), null, "teardown/a machine taken out of the room leaves its partner alone")
	_eq(a.port.linked_machines().size(), 0, "teardown/and on no bus")
	_looks(2)
	_eq(a.port.cable, a.port, "teardown/and the room can be looked at again without it")
	await _clear([a])


# ── a netplay session ────────────────────────────────────────────────────────

func _test_netplay() -> void:
	IrBus.reset()
	var session := _Session.new()
	IrBus.netplay_manager_override = session
	var a := _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	var b := _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	session.covered = [a, b]

	_looks(IrBus.LINK_DWELL)
	_eq(session.scheduled.size(), 1, "netplay/a pair in a running session is scheduled by the host")
	_eq(IrBus.joins, 0, "netplay/and NOT joined on the spot")
	if session.scheduled.size() == 1:
		var op: Dictionary = session.scheduled[0]
		_eq(op["op"], 1, "netplay/the operation is a join")
		var entries: Array = op["entries"]
		_eq(entries.size(), 2, "netplay/of both machines")
		if entries.size() == 2:
			_eq(entries[0]["machine"], a, "netplay/head first")
			_eq([int(entries[0]["port"]), int(entries[1]["port"])], [1, 1],
				"netplay/on the infrared port, not the cable's")
	_eq(a.port.linked_machines().size(), 2,
		"netplay/the pair is stated to the session, which is how it finds the far machine")
	_looks(6)
	_eq(session.scheduled.size(), 1, "netplay/a pair that holds is scheduled once")

	b.global_transform = _looking(Vector3(0, 1, -0.90), Vector3(0, 1, 0))
	_looks(IrBus.UNLINK_DWELL)
	_eq(session.scheduled.size(), 2, "netplay/parting it is scheduled too")
	if session.scheduled.size() == 2:
		_eq(session.scheduled[1]["op"], 0, "netplay/as a pull")
	_eq(IrBus.joins, 0, "netplay/and still nothing was done on the spot")

	# A peer that is not the host decides nothing: it is told.
	session.scheduled.clear()
	session.host = false
	b.global_transform = _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0))
	_looks(IrBus.LINK_DWELL)
	_eq(session.scheduled.size(), 0, "netplay/a peer that is not the host schedules nothing")
	_eq(IrBus.joins, 0, "netplay/and joins nothing")
	session.host = true
	await _clear([a, b])

	# Half in a session: the far machine is not one the session is running.
	session = _Session.new()
	IrBus.netplay_manager_override = session
	a = _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	b = _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	session.covered = [a]
	_looks(IrBus.LINK_DWELL + 3)
	_eq(session.scheduled.size(), 0, "netplay/a pair half in a session is not scheduled")
	_eq(IrBus.joins, 0, "netplay/and is not joined locally either, which would fork this peer")
	await _clear([a, b])

	# A session that is still starting. Sight is each peer's own, so a join made
	# now would be at frame zero here and not at all on a peer who has the two
	# machines a centimetre further apart.
	session = _Session.new()
	IrBus.netplay_manager_override = session
	a = _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	b = _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	session.running = false
	session.preparing = [a, b]
	_looks(IrBus.LINK_DWELL + 4)
	_eq(IrBus.joins, 0, "netplay/a session that is still starting gets no join before frame zero")
	_eq(session.scheduled.size(), 0, "netplay/and none scheduled into a session with no frames")
	_eq(a.port.linked_machines().size(), 0, "netplay/the pair waits")
	session.running = true
	session.covered = [a, b]
	_looks(1)
	_eq(session.scheduled.size(), 1, "netplay/and is scheduled on the first look after it runs")
	_eq(IrBus.joins, 0, "netplay/by the host, not on the spot")
	await _clear([a, b])

	# The same wait when the pair was already linked: the session restarts both
	# cores, and each asks for its links to be stated again.
	session = _Session.new()
	session.running = false
	IrBus.netplay_manager_override = session
	a = _machine("Gbc_a", _looking(Vector3(0, 1, 0), Vector3(0, 1, -1)))
	b = _machine("Gbc_b", _looking(Vector3(0, 1, -0.30), Vector3(0, 1, 0)))
	_looks(IrBus.LINK_DWELL)
	_eq(IrBus.joins, 1, "netplay/a pair linked before any session")
	session.preparing = [a, b]
	a.port.rejoin()
	_eq(IrBus.joins, 1, "netplay/is not rejoined by a session that is starting it")
	_eq(a.port.linked_machines().size(), 0, "netplay/it waits instead")
	session.running = true
	session.covered = [a, b]
	_looks(1)
	_eq(session.scheduled.size(), 1, "netplay/and the host schedules it once frames are running")
	await _clear([a, b])


# ── the Game Boy Color itself ────────────────────────────────────────────────

func _system(systemid: String, label: String) -> RetroSystem:
	var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	sys.systemid = systemid
	sys.name = label
	add_child(sys)
	sys.freeze = true
	return sys


func _test_the_machine() -> void:
	IrBus.reset()
	var gbc := _system("gbc", "Gbc")
	var gb := _system("gb", "Gb")
	await get_tree().process_frame
	await get_tree().process_frame

	var port := gbc.find_child("IrPort", true, false) as IrPort
	_ok(port != null, "machine/the Game Boy Color has an infrared port")
	_eq(gb.find_child("IrPort", true, false), null, "machine/the Game Boy has none")
	if port == null:
		await _clear([gbc, gb])
		return
	port.set_physics_process(false)
	_eq(port.get_machine(), gbc, "machine/the port knows its machine")
	_eq(port.get_libretro(), gbc.get_libretro_node(), "machine/and its core")
	_eq(port.link_port, 1, "machine/it is link port 1; the link cable is 0")
	var socket := gbc.find_child("LinkPort", true, false) as LinkPort
	_ok(socket != null and socket.link_port != port.link_port,
		"machine/so the two links cannot be mistaken for one another")

	# Out of the top edge, by sign: the beam points the way the window is from
	# the middle of the shell, not back through it.
	var to_local := gbc.global_transform.affine_inverse()
	var where := to_local * port.global_position
	var beam := to_local.basis * port.beam_axis()
	_ok(beam.dot(where) > 0.0 and absf(beam.normalized().dot(where.normalized())) > 0.9,
		"machine/the beam leaves the edge its window is on, outward",
		"window %s mm, beam %s" % [where * 1000.0, beam])

	# The glow follows the port's link, on the window's own surface.
	var window := gbc.find_child("IrWindow", true, false) as MeshInstance3D
	var dark := window.get_surface_override_material(0)
	port.set_live(true)
	var lit := window.get_surface_override_material(0) as StandardMaterial3D
	_ok(lit != null and lit != dark and lit.emission_enabled,
		"machine/the window glows while its link is up")
	if lit != null and lit.emission_enabled:
		# Faint is a measured word here: at 0.55 the photograph showed a bright
		# red panel beside the power lamp, at 0.12 an ember behind dark glass.
		_ok(lit.emission_energy_multiplier <= 0.2 and lit.emission.r > lit.emission.g * 4.0,
			"machine/faintly, and red", "energy %.2f, %s" % [lit.emission_energy_multiplier, lit.emission])
	port.set_live(false)
	_eq(window.get_surface_override_material(0), dark, "machine/and is the dark window again when it drops")
	await _clear([gbc, gb])


func _face(a: RetroSystem, b: RetroSystem, distance: float, swing_degrees := 0.0) -> void:
	var port_a := a.find_child("IrPort", true, false) as IrPort
	var port_b := b.find_child("IrPort", true, false) as IrPort
	a.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	# Turned to look back at the first, then swung about its own long edge so
	# the first sits off toward the back of its shell.
	var turned := Basis.IDENTITY.rotated(Vector3.UP, PI)
	b.global_transform = Transform3D(turned, Vector3(0, 1, 0))
	var want := port_a.global_position + port_a.beam_axis().rotated(
		a.global_transform.basis.x.normalized(), deg_to_rad(swing_degrees)) * distance
	b.global_position += want - port_b.global_position


func _test_two_machines() -> void:
	IrBus.reset()
	var a := _system("gbc", "Gbc_a")
	var b := _system("gbc", "Gbc_b")
	await get_tree().process_frame
	await get_tree().process_frame
	var port_a := a.find_child("IrPort", true, false) as IrPort
	var port_b := b.find_child("IrPort", true, false) as IrPort
	if port_a == null or port_b == null:
		_ok(false, "room/two Game Boy Colors with ports")
		await _clear([a, b])
		return
	port_a.set_physics_process(false)
	port_b.set_physics_process(false)
	a.is_powered_on = true
	b.is_powered_on = true

	# Back to back first: the same two machines, the same distance, and nothing
	# but the way they look to stop them.
	_face(a, b, 0.30)
	b.global_transform = Transform3D(a.global_transform.basis, b.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_looks(IrBus.LINK_DWELL + 2)
	_eq(port_a.partner(), null, "room/two machines looking the same way do not link")

	_face(a, b, 0.30)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(IrBus.sight_clear(port_a, port_b),
		"room/a machine's own shell is not in the way of its window")
	_looks(IrBus.LINK_DWELL)
	_eq(port_a.partner(), port_b, "room/two Game Boy Colors face to face link")

	# What netplay asks of a machine, and it is asked through the same sweep
	# every lead answers.
	var bus: Array = b.net_link_bus()
	_eq(bus.size(), 2, "room/the machine's own sweep finds the bus from the far end")
	_eq(a.net_link_buses().size(), 1, "room/once, though both windows are in the sweep")
	var group: Array = b.net_link_group()
	_eq(group.size(), 2, "room/so a session started on either takes both")
	if group.size() == 2:
		_eq(group[0], b, "room/itself first")

	var joins := IrBus.joins
	a.net_refresh_link_cables()
	_eq(IrBus.joins, joins + 1, "room/a core restart re-states the link through that sweep")

	# A cartridge stands 18 mm out of the same edge, behind the window. With the
	# partner off toward the back of the shell the straight line from one window
	# to the other passes through it. It is seated, which is to say HELD, and
	# nothing that is held stands in the way (IrBus.SIGHT_MASK).
	var carts: Array = []
	for sys: RetroSystem in [a, b]:
		var cart := (load(CART_SCENE) as PackedScene).instantiate() as RetroCartridge
		cart.systemid = "gbc"
		cart.game_label = "IR"
		add_child(cart)
		cart.global_position = sys.global_position + Vector3(0, 0.3, 0)
		carts.append(cart)
	await get_tree().process_frame
	await get_tree().process_frame
	a.restore_cartridge(carts[0])
	b.restore_cartridge(carts[1])
	for wait in range(20):
		await get_tree().physics_frame
	_face(a, b, 0.20, -50.0)
	for wait in range(4):
		await get_tree().physics_frame
	_ok(IrBus.in_view(port_a.global_transform, port_b.global_transform,
			IrBus.LINK_RANGE, IrBus.LINK_ANGLE),
		"room/a partner 50 degrees toward the back of the shell is in the beam")
	_ok(IrBus.sight_clear(port_a, port_b),
		"room/and the unit's own cartridge, between the two windows, does not hide it")
	# And the line really does pass through one, or the case above proves
	# nothing: asked of the held layer alone, the first thing it meets is a
	# cartridge.
	var through := PhysicsRayQueryParameters3D.create(
		port_a.global_position, port_b.global_position, 1 << 16)
	var met: Dictionary = port_a.get_world_3d().direct_space_state.intersect_ray(through)
	_ok(met.get("collider") is RetroCartridge,
		"room/though the line between them does pass through a cartridge",
		"met %s" % str(met.get("collider")))

	a.is_powered_on = false
	a.net_refresh_link_cables()
	_eq(port_b.partner(), null, "room/switching one off parts the pair through the machine's own call")
	# Taken out before the machines go, so what a release defers has run while
	# the cartridges are still there to be released.
	a.net_release_cartridge()
	b.net_release_cartridge()
	await get_tree().process_frame
	await _clear([a, b] + carts)
