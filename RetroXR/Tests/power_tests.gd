extends "res://Tests/test_suite.gd"

## Power (docs/dev/power.md): MainsPower's graph from the wall through strips,
## travel adapters and cords; PowerInput's answer and its words; the "Enable Power
## Simulation" option and a room with no outlets; a console that will not switch
## on unplugged, goes off when its plug is pulled, and a handheld whose slide, left
## ON, brings it back when its supply arrives.
##
## Runs with "Enable Power Simulation" ON unless a case says otherwise, and puts the
## player's value back. No core: a machine's start is core_start_stand_in.

const OUTLET := preload("res://Scenes/Objects/room/wall_outlet.tscn")
const STRIP := preload("res://Scenes/Objects/appliances/power_strip.tscn")
const ADAPTER := preload("res://Scenes/Objects/appliances/travel_adapter.tscn")
const C7_CORD := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn")
const C8_INLET := preload("res://Scenes/Objects/cables/iec_c8_port.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CELL_SCENE := "res://Scenes/Objects/batteries/battery_aa.tscn"
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const AMP_SCENE := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const CD_SCENE := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const BRICK_SCENE := preload("res://Scenes/Objects/power/power_brick.tscn")
const VB_PAD := preload("res://Scenes/Objects/controllers/vb/vb_controller.tscn")
const VB_TAP := preload("res://Scenes/Objects/power/vb_ac_tap.tscn")

var _only := ""
var _room: Node3D = null


func _ready() -> void:
	suite_tag = "power"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[power] TIMEOUT")
		get_tree().quit(1))
	var sim_before := AppPrefs.power_simulation
	var region_before := AppPrefs.mains_region
	AppPrefs.mains_region = MainsRegions.DEFAULT
	AppPrefs.power_simulation = true

	if _want("graph"):
		await _test_graph()
	if _want("input"):
		await _test_input()
	if _want("option"):
		await _test_option()
	if _want("console"):
		await _test_console()
	if _want("latch"):
		await _test_latch()
	if _want("rooms"):
		_test_rooms()
	if _want("tv"):
		await _test_tv()
	if _want("decks"):
		await _test_decks()
	if _want("bay"):
		await _test_bay()
	if _want("brick"):
		await _test_brick()
	if _want("save"):
		await _test_save()
	if _want("spawn"):
		_test_spawn()
	if _want("cabinet"):
		await _test_cabinet()
	if _want("models"):
		await _test_models()
	if _want("vb"):
		await _test_vb()

	AppPrefs.power_simulation = sim_before
	AppPrefs.mains_region = region_before
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _new_room(with_outlet := true) -> WallOutlet:
	_room = Node3D.new()
	_room.name = "PowerRoom"
	add_child(_room)
	if not with_outlet:
		return null
	var plate := OUTLET.instantiate() as WallOutlet
	plate.name = "WallOutlet"
	plate.position = Vector3(0, 0.3, -1)
	_room.add_child(plate)
	return plate


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("spawned"):
		if n.has_method("drop_and_free"):
			n.call("drop_and_free")
		else:
			n.queue_free()
	if is_instance_valid(_room):
		for n in _room.get_children():
			if n.has_method("drop_and_free"):
				n.call("drop_and_free")
		_room.queue_free()
	_room = null
	await _wait(4)


## Take the plug out of `port` and set it down well clear of every socket, or the
## socket (or the one beside it) snaps it straight back in.
var _parked := 0


func _pull(port: XRToolsSnapZone) -> void:
	var plug := port.picked_up_object as Node3D
	port.drop_object()
	if plug == null:
		return
	_parked += 1
	var away := Vector3(2.0 + _parked * 0.25, 0.05, 2.0)
	# A neighbour can take it as it is let go, before it has moved: drop it again
	# from wherever it went once it stands clear.
	for i in 4:
		var holder := _holder_of(plug)
		if holder != null:
			holder.drop_object()
		plug.global_position = away
		if plug is RigidBody3D:
			(plug as RigidBody3D).freeze = true
		await get_tree().physics_frame


func _holder_of(thing: Node3D) -> XRToolsSnapZone:
	for group: StringName in [&"port", CellSlots.SLOT_GROUP]:
		for n in get_tree().get_nodes_in_group(group):
			var zone := n as XRToolsSnapZone
			if zone != null and zone.picked_up_object == thing:
				return zone
	return null


func _cord() -> PowerCord:
	var cord := C7_CORD.instantiate() as PowerCord
	_room.add_child(cord)
	return cord


## A stand-in appliance: a pickable with a C8 inlet on it and a PowerInput.
func _appliance() -> Array:
	var body := XRToolsPickable.new()
	body.name = "Appliance"
	body.freeze = true
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	_room.add_child(body)
	var inlet := C8_INLET.instantiate() as PowerPort
	inlet.name = "PowerInlet"
	body.add_child(inlet)
	var input := PowerInput.on(body)
	input.label = "test appliance"
	input.add_inlet(inlet)
	return [body, inlet, input]


func _strip() -> PowerStrip:
	var strip := STRIP.instantiate() as PowerStrip
	_room.add_child(strip)
	return strip


# ── the graph ────────────────────────────────────────────────────────────────

func _test_graph() -> void:
	var plate := _new_room()
	var cord := _cord()
	var strip := _strip()
	var adapter := ADAPTER.instantiate() as TravelAdapter
	_room.add_child(adapter)
	await _wait(3)
	var top := plate.get_node("TopPort") as PowerPort
	var bottom := plate.get_node("BottomPort") as PowerPort

	_ok(MainsPower.socket_live(top), "graph/a wall receptacle is live")
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/a cord's appliance end is dead while its wall end is loose")
	_ok(not MainsPower.plug_live(cord.wall_plug), "graph/a wall plug never carries power out")
	top.pick_up_object(cord.wall_plug)
	await _wait(2)
	_ok(MainsPower.plug_live(cord.appliance_plug), "graph/its appliance end is live with the wall end in the wall")
	await _pull(top)
	await _wait(2)

	var socket := strip.sockets()[0]
	_ok(not MainsPower.socket_live(socket), "graph/a loose strip's sockets are dead")
	socket.pick_up_object(cord.wall_plug)
	await _wait(2)
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/a cord in a loose strip is dead")
	bottom.pick_up_object(strip.wall_plug)
	await _wait(2)
	_ok(MainsPower.socket_live(socket), "graph/a strip in the wall makes its sockets live")
	_ok(MainsPower.plug_live(cord.appliance_plug), "graph/and the cord in it")
	await _pull(bottom)
	await _wait(2)
	# Its own plug in one of its own sockets: a loop, and dead.
	strip.sockets()[1].pick_up_object(strip.wall_plug)
	await _wait(2)
	_ok(not MainsPower.socket_live(socket), "graph/a strip plugged into itself has no power")
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/nor does anything in it")
	await _pull(strip.sockets()[1])
	await _pull(socket)
	await _wait(2)

	adapter.socket.pick_up_object(cord.wall_plug)
	await _wait(2)
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/a cord in a loose travel adapter is dead")
	top.pick_up_object(adapter.wall_plug)
	await _wait(2)
	_ok(MainsPower.plug_live(cord.appliance_plug), "graph/the adapter in the wall feeds it")
	_ok(MainsPower.room_has_mains(get_tree()), "graph/the room has mains")
	await _clear()


# ── PowerInput ───────────────────────────────────────────────────────────────

func _test_input() -> void:
	var plate := _new_room()
	var made := _appliance()
	var inlet := made[1] as PowerPort
	var input := made[2] as PowerInput
	var cord := _cord()
	var strip := _strip()
	var events: Array[bool] = []
	input.power_changed.connect(func(live: bool) -> void: events.append(live))
	await _wait(3)

	_ok(not input.is_live(), "input/nothing in the inlet: no power")
	_eq(input.describe(), "Not plugged in", "input/and it says so")
	inlet.pick_up_object(cord.appliance_plug)
	await _wait(3)
	_ok(not input.is_live(), "input/a cord in the inlet, its wall end loose: no power")
	_eq(input.describe(), "Power cord -- not plugged in", "input/it says the cord is not plugged in")
	strip.sockets()[0].pick_up_object(cord.wall_plug)
	await _wait(3)
	_eq(input.describe(), "Power cord -- in a power strip that is not plugged in",
		"input/in a loose strip, it says the strip is not plugged in")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(strip.wall_plug)
	await _wait(3)
	_ok(input.is_live(), "input/the strip in the wall: power")
	_eq(input.describe(), "Power cord, in a power strip", "input/it says where")
	_ok(events.has(true), "input/power_changed said it came", str(events))
	events.clear()
	await _pull(plate.get_node("TopPort") as PowerPort)
	await _wait(3)
	_ok(not input.is_live(), "input/the strip pulled: no power")
	_eq(events, [false] as Array[bool], "input/power_changed said it went, once")
	await _pull(strip.sockets()[0])
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(3)
	_eq(input.describe(), "Power cord, in a wall outlet", "input/straight into the wall")
	await _clear()

	# Cells: every bay filled, or nothing.
	_new_room()
	var host := XRToolsPickable.new()
	host.name = "CellHost"
	host.freeze = true
	_room.add_child(host)
	host.add_to_group("spawned")
	for i in 2:
		var marker := Node3D.new()
		marker.name = "BatteryAA%d" % (i + 1)
		marker.position = Vector3(i * 0.02, 0, 0)
		host.add_child(marker)
	CellSlots.build_seats(host)
	var cells_in := PowerInput.on(host)
	cells_in.label = "cell host"
	await _wait(3)
	_ok(not cells_in.is_live(), "input/cells: empty bays, no power")
	_eq(cells_in.describe(), "No batteries (takes 2 AA)", "input/cells: it says what it takes")
	var slots := CellSlots.of(host)
	var first := _cell()
	slots.slot("BatteryAA1").pick_up_object(first)
	await _wait(3)
	_ok(not cells_in.is_live(), "input/cells: one of two, no power")
	_eq(cells_in.describe(), "Batteries 1 of 2 AA -- needs 1 more", "input/cells: it says how many more")
	slots.slot("BatteryAA2").pick_up_object(_cell())
	await _wait(3)
	_ok(cells_in.is_live(), "input/cells: both in, power")
	await _pull(slots.slot("BatteryAA1"))
	await _wait(3)
	_ok(not cells_in.is_live(), "input/cells: one out again, none")
	await _clear()

	# A device that takes nothing modelled is always on, and a built-in pack always is.
	_new_room()
	var bare := Node3D.new()
	_room.add_child(bare)
	var nothing := PowerInput.on(bare)
	_ok(nothing.is_live(), "input/a device with no supply modelled is always powered")
	var pack := PowerInput.on(Node3D.new())
	pack.internal_battery = true
	_ok(pack.is_live(), "input/a built-in battery is power")
	pack.get_parent().free()
	await _clear()


func _cell() -> XRToolsPickable:
	var cell := (load(CELL_SCENE) as PackedScene).instantiate() as XRToolsPickable
	_room.add_child(cell)
	cell.add_to_group("spawned")
	return cell


# ── the option, and a room with no outlets ────────────────────────────────────

func _test_option() -> void:
	_new_room()
	var made := _appliance()
	var input := made[2] as PowerInput
	await _wait(3)
	_ok(not input.is_live(), "option/simulation on: an unplugged device has no power")
	var events: Array[bool] = []
	input.power_changed.connect(func(live: bool) -> void: events.append(live))
	AppPrefs.power_simulation = false
	MainsPower.changed(get_tree())
	await _wait(3)
	_ok(input.is_live(), "option/simulation off: it powers with nothing plugged in")
	_ok(not input.supplied(), "option/simulation off: and still says its own supply is not there")
	_ok(input.describe().begins_with("Power simulation off (Options)"), "option/simulation off: it says why",
		input.describe())
	_ok(events.has(true), "option/simulation off: the device heard", str(events))
	AppPrefs.power_simulation = true
	MainsPower.changed(get_tree())
	await _wait(3)
	_ok(not input.is_live(), "option/simulation on again: no power")
	await _clear()

	# No wall outlet anywhere: nothing could ever be plugged in, so everything powers.
	_new_room(false)
	var loose := _appliance()
	await _wait(3)
	var other_plates := get_tree().get_nodes_in_group(WallOutlet.GROUP)
	_ok(other_plates.is_empty(), "option/no plate is left in the tree", str(other_plates.size()))
	_ok((loose[2] as PowerInput).is_live(), "option/a room with no outlets powers everything")
	_ok((loose[2] as PowerInput).describe().begins_with("No outlets in this room"),
		"option/and says why", (loose[2] as PowerInput).describe())
	await _clear()


# ── a console ────────────────────────────────────────────────────────────────

func _machine(systemid: String, model_id: String = "") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.model_id = model_id
	sys.position = Vector3(1, 0.5, 0)
	sys.freeze = true
	_room.add_child(sys)
	sys.add_to_group("spawned")
	await _wait(6)
	sys._libretro.content_load_failed.disconnect(sys._on_content_load_failed)
	sys.core_start_stand_in = func() -> void: pass
	return sys


func _test_console() -> void:
	var plate := _new_room()
	# A Saturn wears the procedural box: its inlet is built from PowerProfiles.
	var sys := await _machine("saturn")
	var inlet := sys.get_node_or_null("PowerInlet") as PowerPort
	_ok(inlet != null, "console/a Saturn has a C8 inlet built on it")
	if inlet == null:
		await _clear()
		return
	_eq(inlet.connector, "iec_c7_polarized_plug", "console/the polarized one")
	var body := sys.body_aabb()
	# Set into the back so its face is flush (ApplianceMains.inlet_proud), not stuck on it.
	var face := inlet.position.z - ApplianceMains.inlet_proud(inlet)
	_ok(absf(face - body.position.z) < 0.001, "console/set into the back face, flush",
		"inlet face z %.4f, body back %.4f" % [face, body.position.z])
	_ok(inlet.transform.basis.z.dot(Vector3(0, 0, -1)) > 0.99, "console/facing out of the back",
		str(inlet.transform.basis.z))
	var input := PowerInput.of(sys)
	_ok(input != null and input.inlets().has(inlet), "console/its PowerInput takes the inlet")

	sys.power_on()
	await _wait(2)
	_ok(not sys.is_powered_on, "console/unplugged, it will not switch on")
	sys.toggle_power()
	await _wait(2)
	_ok(not sys.is_powered_on, "console/nor from its power button")

	var cord := _cord()
	await _wait(2)
	_ok(inlet.can_preview(cord.appliance_plug), "console/a plain C7 goes into its polarized inlet")
	inlet.pick_up_object(cord.appliance_plug)
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(3)
	sys.toggle_power()
	await _wait(2)
	_ok(sys.is_powered_on, "console/plugged in, it switches on")

	await _pull(plate.get_node("TopPort") as PowerPort)
	await _wait(4)
	_ok(not sys.is_powered_on, "console/pulling the plug switches it off")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(4)
	_ok(not sys.is_powered_on, "console/a push button is not latched: plugged back in, it stays off")

	AppPrefs.power_simulation = false
	await _pull(inlet)
	await _wait(3)
	sys.toggle_power()
	await _wait(2)
	_ok(sys.is_powered_on, "console/with power simulation off, it switches on unplugged")
	sys.power_off()
	AppPrefs.power_simulation = true
	await _clear()


## A handheld's slide latches: left ON with no supply, the machine comes on when the
## supply arrives, and goes off (the slide still ON) when it goes.
func _test_latch() -> void:
	var plate := _new_room()
	var gb := await _machine("gb", "game_boy_primitive")
	var jack := gb.find_child("DcInPort", true, false) as DcPort
	var input := PowerInput.of(gb)
	_ok(jack != null and input != null and input.inlets().has(jack),
		"latch/a Game Boy's DC IN is its inlet")
	var slide: VRSlider = gb.get_model().latching_power_switch()
	_ok(slide != null, "latch/its power slide latches")
	if jack == null or slide == null:
		await _clear()
		return
	# A lead whose appliance end is the Game Boy's adapter plug.
	var cord := _cord()
	(cord.appliance_plug as RcaPlug).set_connector("dmg_dc_plug")
	await _wait(2)
	jack.pick_up_object(cord.appliance_plug)
	await _wait(2)

	slide.set_value(1.0)
	await _wait(3)
	_ok(not gb.is_powered_on, "latch/slide ON with the adapter loose: nothing")
	_ok(slide.value > 0.5, "latch/and the slide stays ON")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(4)
	_ok(gb.is_powered_on, "latch/the adapter into the wall: it comes on")
	await _pull(plate.get_node("TopPort") as PowerPort)
	await _wait(4)
	_ok(not gb.is_powered_on, "latch/the adapter pulled: it goes off")
	_ok(slide.value > 0.5, "latch/its slide still ON")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(4)
	_ok(gb.is_powered_on, "latch/and back on with the supply")
	slide.set_value(0.0)
	await _wait(3)
	_ok(not gb.is_powered_on, "latch/slid OFF, it is off")
	await _clear()


# ── the rooms ────────────────────────────────────────────────────────────────

## The Arcade Room's plates, read off the scene as authored (no room is entered): on
## a wall's inner face, 0.3 m up, the plate's +Z into the room, none in the north
## doorway, and one within 2 m of anywhere along every wall.
func _test_rooms() -> void:
	var room := (load(RoomCatalog.path_of("arcade")) as PackedScene).instantiate() as Node3D
	var outlets := room.get_node_or_null("Outlets") as Node3D
	_ok(outlets != null, "rooms/the Arcade Room has its outlets")
	if outlets == null:
		room.free()
		return
	var plates := 0
	var walls := {"north": 0, "south": 0, "east": 0, "west": 0}
	for child in outlets.get_children():
		var plate := child as Node3D
		if plate == null or plate.scene_file_path != OUTLET.resource_path:
			continue
		plates += 1
		var at := outlets.transform * plate.position
		var out := (outlets.transform.basis * plate.transform.basis).z.normalized()
		var wall := ""
		if is_equal_approx(at.z, 5.0):
			wall = "south"
		elif is_equal_approx(at.z, -5.0):
			wall = "north"
		elif is_equal_approx(at.x, 5.0):
			wall = "east"
		elif is_equal_approx(at.x, -5.0):
			wall = "west"
		_ok(not wall.is_empty(), "rooms/%s is on a wall's inner face" % plate.name, str(at))
		_ok(is_equal_approx(at.y, 0.3), "rooms/%s is 0.3 m up" % plate.name, str(at.y))
		# Into the room: toward the middle along the wall's normal.
		var inward := Vector3(-signf(at.x), 0, 0) if wall in ["east", "west"] else Vector3(0, 0, -signf(at.z))
		_ok(out.dot(inward) > 0.999, "rooms/%s faces into the room" % plate.name, str(out))
		if wall == "north":
			_ok(absf(at.x) >= 0.6 + 0.05, "rooms/%s is not in the doorway" % plate.name, str(at.x))
		if not wall.is_empty():
			walls[wall] += 1
	_ok(plates >= 18, "rooms/a plate every 2 m round the room", str(plates))
	for wall: String in walls:
		_ok(int(walls[wall]) >= 4, "rooms/the %s wall has its plates" % wall, str(walls[wall]))
	room.free()


# ── a set's inlet, the decks' own cords ─────────────────────────────────────

func _spawn(packed: PackedScene, at: Vector3) -> Node3D:
	var obj := packed.instantiate() as Node3D
	obj.position = at
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	_room.add_child(obj)
	obj.add_to_group("spawned")
	return obj

func _test_tv() -> void:
	var plate := _new_room()
	# The spawn menu's set, the RETRO XR one, whose model has a PowerCordExit.
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	tv.position = Vector3(0, 0.5, 0)
	tv.freeze = true
	_room.add_child(tv)
	tv.add_to_group("spawned")
	await _wait(6)
	var input := tv.power_input()
	_ok(input != null, "tv/the set has a PowerInput")
	# Its own cord, as the decks have (2026-11-01; it was a C8 inlet).
	var cord := input.captive as CaptiveMainsCord if input != null else null
	_ok(cord != null, "tv/a cord of its own")
	_ok(tv.get_node_or_null("PowerInlet") == null and input != null and input.inlets().is_empty(),
		"tv/and no inlet")
	if cord == null:
		await _clear()
		return
	_ok(cord.exit != null and bool(cord.exit.get_meta(&"from_model", false)),
		"tv/it leaves from the RETRO XR model's PowerCordExit")
	_ok(not tv.is_on(), "tv/switched on, unplugged: dark")
	_ok(tv.is_switched_on(), "tv/its switch is still in")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(4)
	_ok(tv.is_on(), "tv/plugged in: on")
	_eq(input.describe(), "Built-in cord, in a wall outlet", "tv/it says where")
	await _pull(plate.get_node("TopPort") as PowerPort)
	await _wait(4)
	_ok(not tv.is_on(), "tv/pulled: dark again")
	tv.remote_power_toggle()
	_ok(tv.is_switched_on(), "tv/the remote does nothing to a set with no power")
	# The menu's section reads the same words, and has Show Power Cord (a cord of its own).
	var holder := VBoxContainer.new()
	add_child(holder)
	var rows := PowerMenuRows.build(holder, input, cord)
	_ok(rows.find_child("ShowPowerCord", true, false) != null, "tv/its menu has Show Power Cord")
	_ok((rows.find_child("PowerSupply", true, false) as Label).text.ends_with(input.describe()),
		"tv/its menu says the supply")
	holder.queue_free()
	# The Plain Monitor is a computer monitor: a C14 inlet for a kettle lead, no cord.
	var monitor := TV_SCENE.instantiate() as RetroTV
	monitor.tv_model = "crt_plain"
	monitor.position = Vector3(-1.5, 0.5, 0)
	monitor.freeze = true
	_room.add_child(monitor)
	monitor.add_to_group("spawned")
	await _wait(6)
	var m_inlet := monitor.get_node_or_null("PowerInlet") as PowerPort
	_ok(m_inlet != null and m_inlet.connector == "iec_c13_plug" and monitor.power_input().captive == null,
		"tv/the Plain Monitor has a C14 inlet and no cord of its own")
	# A set whose model has no exit (the Classic box) still has its cord, leaving from
	# the back its model really has there, not from behind its bounds.
	var plain := _spawn(TV_SCENE, Vector3(1.5, 0.5, 0)) as RetroTV
	await _wait(6)
	var plain_cord := plain.power_input().captive as CaptiveMainsCord if plain.power_input() != null else null
	_ok(plain_cord != null, "tv/the Classic set has its own cord too")
	if plain_cord != null:
		var exit_z := plain_cord.exit.position.z
		var back_z := ApplianceModel.node_bounds(plain, plain).position.z
		_ok(exit_z > back_z + 0.003, "tv/and it leaves from its drawn back, not the bounds' rearmost point",
			"exit z %.3f, bounds' back %.3f" % [exit_z, back_z])
	await _clear()



func _test_decks() -> void:
	var plate := _new_room()
	var vcr := _spawn(VCR_SCENE, Vector3(-0.6, 0.3, 0)) as VCRPlayer
	var amp := _spawn(AMP_SCENE, Vector3(0.6, 0.3, 0)) as SurroundAmp
	var cd := _spawn(CD_SCENE, Vector3(1.4, 0.3, 0)) as CDPlayer
	await _wait(8)
	_ok(vcr.power_input() != null and vcr.power_input().captive != null, "decks/the VCR has its own cord")
	_ok(not vcr.mains_live(), "decks/unplugged, the VCR has no power")
	_ok(not vcr._mains_gate("PLAY"), "decks/and its keys do nothing")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(
		(vcr.power_input().captive as CaptiveMainsCord).wall_plug)
	await _wait(4)
	_ok(vcr.mains_live() and vcr._mains_gate("PLAY"), "decks/plugged in, its keys work")
	_ok(amp.power_input() != null, "decks/the amplifier has its own cord")
	_eq(amp.effective_volume(), 0.0, "decks/an unplugged amplifier puts out nothing")
	_ok(not amp.mains_live(), "decks/unplugged amplifier: no power")
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(
		(amp.power_input().captive as CaptiveMainsCord).wall_plug)
	await _wait(4)
	_ok(amp.mains_live(), "decks/the amplifier plugged in has power")
	_ok(cd.power_input() != null and not cd.mains_live(), "decks/the CD player is its own and unplugged")
	_ok(not cd._mains_gate("PLAY"), "decks/its PLAY does nothing")
	await _clear()


# ── a handheld's battery bay ─────────────────────────────────────────────────

func _test_bay() -> void:
	_new_room()
	var gb := await _machine("gb", "game_boy_primitive")
	var slots := CellSlots.of(gb)
	var covers := CoverSlots.of(gb)
	_ok(slots != null and slots.seats().size() == 4, "bay/a Game Boy has four seats",
		str(slots.seats().size() if slots != null else -1))
	_ok(slots != null and CellSlots.size_of_seat(slots.seats()[0]) == "AA", "bay/for AA cells")
	_ok(covers != null and covers.sockets().size() == 1, "bay/and one battery cover")
	if slots == null or covers == null or covers.sockets().is_empty():
		await _clear()
		return
	var socket := covers.sockets()[0]
	await _wait(3)
	_ok(covers.is_on(socket), "bay/fresh from the menu its cover is on")
	_ok(slots.is_blocked(), "bay/with the cover on, the bay is shut")
	var input := PowerInput.of(gb)
	_ok(not input.is_live(), "bay/no cells, no adapter: no power")
	_ok(input.describe().contains("No batteries (takes 4 AA)"), "bay/it says what it takes", input.describe())
	await _pull(covers.slot(socket))
	await _wait(3)
	_ok(not slots.is_blocked(), "bay/cover off: the bay is open")
	for seat: String in slots.seats():
		slots.slot(seat).pick_up_object(_cell())
	await _wait(4)
	_ok(input.is_live(), "bay/four cells in: power")
	gb.toggle_power()
	await _wait(2)
	_ok(gb.is_powered_on, "bay/and it switches on")
	await _pull(slots.slot(slots.seats()[0]))
	await _wait(4)
	_ok(not gb.is_powered_on, "bay/a cell out while running: it goes off")
	# A handheld with a pack built in needs nothing.
	var ds := await _machine("nds", "nds_primitive")
	_ok(PowerInput.of(ds).is_live(), "bay/a DS runs on its built-in battery")
	await _clear()


# ── an AC adapter ────────────────────────────────────────────────────────────

func _brick(id: String, variant: String, at: Vector3) -> PowerBrick:
	var brick := BRICK_SCENE.instantiate() as PowerBrick
	brick.brick_id = id
	brick.variant = variant
	brick.position = at
	_room.add_child(brick)
	brick.add_to_group("spawned")
	return brick


func _test_brick() -> void:
	var plate := _new_room()
	var fc := await _machine("famicom", "famicom")
	var jack := fc.get_node_or_null("PowerInlet") as DcPort
	_ok(jack != null and jack.connector == "barrel_5_5x2_1", "brick/a Famicom has a 5.5 x 2.1 DC jack built on",
		jack.connector if jack != null else "none")
	var wart := _brick("hvc_ac_adapter", "jpn", Vector3(-0.5, 0.3, 0.5))
	await _wait(4)
	_eq(wart.form, "wall_wart", "brick/the HVC-002 is a wall wart")
	_ok(wart.get_node_or_null("Body") == null and wart.wall_plug != null, "brick/its body is its wall plug")
	_eq(wart.wall_plug.connector, "nema_1_15_plug", "brick/with Japan's blades")
	_eq(wart.dc_plug.connector, "barrel_5_5x2_1", "brick/and a 5.5 x 2.1 plug")
	if jack == null:
		await _clear()
		return
	jack.pick_up_object(wart.dc_plug)
	await _wait(3)
	fc.toggle_power()
	await _wait(2)
	_ok(not fc.is_powered_on, "brick/its adapter not in the wall: the Famicom stays off")
	_eq(PowerInput.of(fc).describe(), "AC adapter -- not plugged in", "brick/and says why")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(wart.wall_plug)
	await _wait(3)
	fc.toggle_power()
	await _wait(2)
	_ok(fc.is_powered_on, "brick/the adapter in the wall: it switches on")
	_eq(PowerInput.of(fc).describe(), "AC adapter, in a wall outlet", "brick/and says where")
	fc.power_off()
	# The PAL NES adapter is an in-line brick, its mains cord fixed, a 2.5 mm hole.
	var pal := _brick("nes_ac_adapter", "eur", Vector3(0.5, 0.3, 0.5))
	await _wait(4)
	_eq(pal.form, "inline", "brick/the NES-002E is an in-line brick")
	_eq(pal.wall_plug.connector, "cee_7_16_plug", "brick/on a Europlug")
	_eq(pal.dc_plug.connector, "barrel_5_5x2_5", "brick/its plug a 5.5 x 2.5")
	_ok(pal.dc_plug.is_in_group(jack.snap_require), "brick/which goes into a 5.5 x 2.1 jack too")
	var snes := _brick("snes_ac_adapter", "usa", Vector3(0, 0.3, 1))
	await _wait(2)
	_ok(not snes.dc_plug.is_in_group(jack.snap_require), "brick/a Super NES plug does not")
	# An inlet brick is fed by a figure-eight cord.
	var slim := _brick("ps2_slim_ac_adapter", "usa", Vector3(1.0, 0.3, 0.5))
	await _wait(4)
	_ok(slim.inlet != null and slim.wall_plug == null, "brick/the slim PS2's brick has a C8 inlet and no plug")
	var cord := _cord()
	await _wait(2)
	slim.inlet.pick_up_object(cord.appliance_plug)
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(cord.wall_plug)
	await _wait(3)
	_ok(MainsPower.plug_live(slim.dc_plug), "brick/a live cord in its inlet: its DC plug has power")
	# The N64's NUS-002 docks into its back: the module is the plug.
	var n64 := await _machine("n64", "nintendo_64")
	var dock := n64.get_node_or_null("PowerInlet") as DcPort
	var module := _brick("n64_psu", "usa", Vector3(1.5, 0.3, 0.5))
	await _wait(4)
	_eq(module.form, "dock", "brick/the NUS-002 docks")
	_ok(dock != null and module.dc_plug.is_in_group(dock.snap_require), "brick/into the N64's back")
	if dock != null:
		dock.pick_up_object(module.dc_plug)
		await _pull(plate.get_node("BottomPort") as PowerPort)
		(plate.get_node("BottomPort") as PowerPort).pick_up_object(module.wall_plug)
		await _wait(3)
		_ok(PowerInput.of(n64).is_live(), "brick/docked and in the wall: the N64 has power")
	# A battery pack has power of its own.
	var pack := _brick("dmg_battery_pack", "usa", Vector3(-1.0, 0.3, 0.5))
	await _wait(4)
	_ok(MainsPower.plug_live(pack.dc_plug), "brick/the DMG-03 pack is charged")
	await _clear()


# ── saved and restored ───────────────────────────────────────────────────────

func _test_save() -> void:
	var plate := _new_room()
	var vcr := _spawn(VCR_SCENE, Vector3(0.6, 0.3, 0)) as VCRPlayer
	var wart := _brick("hvc_ac_adapter", "jpn", Vector3(-0.5, 0.3, 0.5))
	await _wait(8)
	var cord := vcr.power_input().captive as CaptiveMainsCord
	(plate.get_node("TopPort") as PowerPort).pick_up_object(cord.wall_plug)
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(wart.wall_plug)
	await _wait(4)
	var sp := ScenePersistence.new("arcade")
	var ids := {vcr: 0, wart: 1}
	var entries := [sp.serialize_node(vcr, 0, ids), sp.serialize_node(wart, 1, ids)]
	_ok((entries[0] as Dictionary).has("mains_cord"), "save/a deck's entry carries its cord")
	_eq(str(((entries[0] as Dictionary)["mains_cord"] as Dictionary).get("port", "")), "TopPort",
		"save/and the socket its plug is in")
	_eq(str((entries[1] as Dictionary).get("kind", "")), "power_brick", "save/a brick saves as a lead")
	_eq(str((entries[1] as Dictionary).get("variant", "")), "jpn", "save/with its region's model")
	for e: Dictionary in entries:
		_eq(ScenePersistence._entry_validation_error(e, {0: true, 1: true}), "",
			"save/the entry validates (%s)" % e.get("type", ""))
	await _clear()
	# The same room again: its plate at the same path, which is how a save names it.
	var room_plate := _new_room()
	await _wait(3)
	var spawned := sp.instantiate_objects(_room, entries)
	await _wait(12)
	var vcr2 := spawned.get(0) as VCRPlayer
	var wart2 := spawned.get(1) as PowerBrick
	_ok(vcr2 != null and wart2 != null, "save/both came back")
	if vcr2 == null or wart2 == null:
		await _clear()
		return
	var cord2 := vcr2.power_input().captive as CaptiveMainsCord
	_ok(cord2 != null and PowerCord.socket_holding(cord2.wall_plug) == room_plate.get_node("TopPort"),
		"save/the deck's plug is back in its socket")
	_eq(wart2.variant, "jpn", "save/the brick is the same model")
	_ok(PowerCord.socket_holding(wart2.wall_plug) == room_plate.get_node("BottomPort"),
		"save/and back in the wall")
	# A deck's cord put away is saved put away.
	vcr2.set_mains_cord_hidden(true)
	await _wait(3)
	var hidden := sp.serialize_node(vcr2, 0, {vcr2: 0})
	_ok(bool((hidden.get("mains_cord", {}) as Dictionary).get("hidden", false)), "save/a hidden cord saves hidden")
	await _clear()


# ── the spawn menu's rows ────────────────────────────────────────────────────

func _test_spawn() -> void:
	var rows := PowerSpawnRows.cord_rows()
	var c13: Dictionary = rows[0]
	var c7: Dictionary = rows[1]
	_eq(str(c13["key"]), "cord_c13", "spawn/a C13 row")
	_eq(str(PowerSpawnRows.region_default(c13, "na")["token"]), "power_cord", "spawn/US: the 5-15P lead")
	_eq(str(PowerSpawnRows.region_default(c13, "uk")["token"]), "bs_1363_cord", "spawn/UK: the BS 1363 lead")
	_eq(str(PowerSpawnRows.region_default(c7, "eu")["token"]), "europlug_c7_cord", "spawn/Europe's C7: Europlug")
	_eq(str(PowerSpawnRows.region_default(c7, "za")["token"]), "europlug_c7_cord",
		"spawn/a region listing no C7 of its own still gets one that fits")
	var kept := PowerSpawnRows.default_of(c13, "bs_1363_cord", "na")
	_eq(str(kept["token"]), "bs_1363_cord", "spawn/MAKE DEFAULT beats the region")
	_eq(str(PowerSpawnRows.default_of(c13, "no_such_cord", "na")["token"]), "power_cord",
		"spawn/a default the row no longer lists falls back to the region")
	for v: Dictionary in c13["variants"]:
		_ok(ScenePersistence.LEAD_SCENES.has(str(v["token"])), "spawn/%s still spawns and restores" % v["token"])
	var nes := PowerSpawnRows.brick_row("nes_ac_adapter")
	_eq(str(PowerSpawnRows.region_default(nes, "uk")["id"]), "ukv", "spawn/NES adapter in the UK: the UK one")
	_eq(str(PowerSpawnRows.region_default(nes, "na")["id"]), "usa", "spawn/in the US: the US one")
	_eq(str(PowerSpawnRows.region_default(PowerSpawnRows.brick_row("snes_ac_adapter"), "uk")["id"]), "usa",
		"spawn/an adapter with no UK model: its first")
	var parsed := SpawnCatalog.parse_token(str(PowerSpawnRows.region_default(nes, "uk")["token"]))
	_eq(int(parsed["kind"]), SpawnCatalog.TokenKind.POWER_BRICK, "spawn/its token reads back as a brick")
	_eq(str(parsed["brick_id"]), "nes_ac_adapter", "spawn/which brick")
	_eq(str(parsed["variant"]), "ukv", "spawn/which model")
	var on_card := false
	for item: Dictionary in SpawnCatalog.items_for("nes"):
		if item.has("power_row") and str(item.get("spawn", "")) == PowerBrickCatalog.PREFIX + "nes_ac_adapter":
			on_card = true
	_ok(on_card, "spawn/the NES card offers its adapter")
	var c7_on_card := false
	for item: Dictionary in SpawnCatalog.items_for("dreamcast"):
		if item.has("power_row"):
			c7_on_card = true
	_ok(c7_on_card, "spawn/the Dreamcast card offers a figure-eight cord")

	# A row's mark: the flag of where the model was sold and the outlet its REAL plug
	# goes in. A US adapter's plug is a two-blade Type A; it showed North America's B.
	var snes := PowerSpawnRows.brick_row("snes_ac_adapter")
	var usa: Dictionary = (snes["variants"] as Array)[0]
	_eq(str(usa.get("plug", "")), "nema_1_15_plug", "spawn/a US adapter's variant names its plug")
	var mark := PowerSpawnRows.mark_of(usa)
	_ok(mark.begins_with(MainsRegions.flag_of("na")) and mark.ends_with(String.chr(0xF1109)),
		"spawn/its mark is the US flag and a Type A outlet, not North America's Type B", mark)
	_eq(MainsRegions.plug_type("nema_1_15_polarized_plug"), "Type A", "spawn/a polarized 1-15 is a Type A too")
	var us_cord := PowerSpawnRows.region_default(c13, "na")
	_ok(PowerSpawnRows.mark_of(us_cord).ends_with(String.chr(MainsRegions.glyph_of("na"))),
		"spawn/the US C13 lead's 5-15P is a Type B")
	# A mod's model can say what it runs on (a PSone on the PlayStation's platform).
	var row := {"platform": "psx", "label": "Test PSone",
		"scene": "res://Scenes/Objects/system_models/game_boy_primitive.tscn",
		"power": {"inlet": "dc", "plug": "eiaj_03", "brick": "psone_ac_adapter"}}
	_eq(SystemModelRegistry.register_mod_row("power.test:psone", row, "power.test"), "",
		"spawn/a model row with its own power registers")
	_eq(str(PowerProfiles.for_machine("power.test:psone", "psx").get("plug", "")), "eiaj_03",
		"spawn/and its own power wins over its platform's figure-eight inlet")
	SystemModelRegistry.drop_mod("power.test")
	_ok(PowerBrickCatalog.for_machine("", "psx").has("psone_ac_adapter"),
		"spawn/the PlayStation card offers the PSone's adapter")


## An arcade cabinet takes a kettle lead in the C14 inlet on its back; a deck a room
## authors (not spawned) starts with its own cord put away.
func _test_cabinet() -> void:
	var plate := _new_room()
	var cab := SYSTEM_SCENE.instantiate() as RetroSystem
	cab.systemid = "arcade"
	cab.model_id = "arcade_cabinet_generic"
	cab.position = Vector3(0, 0, 0.2)
	cab.freeze = true
	_room.add_child(cab)
	cab.add_to_group("spawned")
	await _wait(10)
	var input := cab.power_input()
	var inlet := cab.get_node_or_null("PowerInlet") as PowerPort
	_ok(inlet != null and input != null and input.inlets().has(inlet), "cabinet/an arcade cabinet has a mains inlet")
	_ok(input != null and input.captive == null, "cabinet/and no cord of its own")
	if inlet != null:
		_eq(inlet.connector, "iec_c13_plug", "cabinet/a C14: the kettle lead goes in")
		# Flush in the drawn back panel, which stands in from the bounds' rearmost point.
		var face := inlet.position.z - ApplianceMains.inlet_proud(inlet)
		var back := cab.body_aabb().position.z
		_ok(face >= back - 0.001 and face <= back + 0.06, "cabinet/set into its back",
			"inlet face %.3f, bounds' back %.3f" % [face, back])
		_ok(not input.is_live(), "cabinet/unplugged, no power")
		var lead := preload("res://Scenes/Objects/cables/power_cord.tscn").instantiate() as PowerCord
		_room.add_child(lead)
		await _wait(2)
		inlet.pick_up_object(lead.appliance_plug)
		(plate.get_node("TopPort") as PowerPort).pick_up_object(lead.wall_plug)
		await _wait(3)
		_ok(input.is_live(), "cabinet/its lead in the wall: power")
	var on_card := false
	for item: Dictionary in SpawnCatalog.items_for("arcade"):
		if item.has("power_row") and str((item["power_row"] as Dictionary).get("key", "")) == "cord_c13":
			on_card = true
	_ok(on_card, "cabinet/the arcade card offers the kettle lead")
	var authored := VCR_SCENE.instantiate() as VCRPlayer
	authored.position = Vector3(2, 0.5, 0)
	authored.freeze = true
	_room.add_child(authored)
	await _wait(6)
	var its: CaptiveMainsCord = authored.power_input().captive as CaptiveMainsCord
	_ok(its != null and its.hidden, "cabinet/a deck a room authors starts with its cord put away")
	_ok(authored.mains_live(), "cabinet/and counts as plugged in")
	authored.queue_free()
	await _clear()


# ── a mod's models (ModApi.override_power_brick) ─────────────────────────────

## A scene shaped as RetroXR-models' adapters are: a body box and empties named as
## theirs, saved where a mod's would load from.
func _fake_model(path: String, size: Vector3, center: Vector3, anchors: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "FakeAdapter"
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = center
	root.add_child(mesh)
	mesh.owner = root
	for anchor_name: String in anchors:
		var a := Node3D.new()
		a.name = anchor_name
		a.position = anchors[anchor_name]
		root.add_child(a)
		a.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()


func _test_models() -> void:
	var plate := _new_room()
	var brick_path := "user://power_test_brick.tscn"
	var wart_path := "user://power_test_wart.tscn"
	var plug_path := "user://power_test_plug.tscn"
	# The PAL NES brick's frame: floor at the origin, cords out of the +-Z ends.
	_fake_model(brick_path, Vector3(0.06, 0.05, 0.12), Vector3(0, 0.025, 0),
		{"DCCordAnchor": Vector3(0, 0.025, 0.06), "ACCordAnchor": Vector3(0, 0.025, -0.06)})
	# The US wart: blades out of the face along +Z, the body behind it, the lead out of the bottom.
	_fake_model(wart_path, Vector3(0.057, 0.1, 0.08), Vector3(0, -0.007, -0.04),
		{"DCCordAnchor": Vector3(0, -0.057, -0.032)})
	# The plug: the hood's face at the origin, the barrel in front, the lead 28.5 mm back.
	_fake_model(plug_path, Vector3(0.0096, 0.0096, 0.038), Vector3(0, 0, -0.0095),
		{"CordExit": Vector3(0, 0, -0.0285)})

	_ok(not PowerBrickCatalog.override_brick("no_such_brick", {"plug_model": plug_path}, "test.mod").is_empty(),
		"models/an unknown adapter is refused")
	_ok(not PowerBrickCatalog.override_brick("nes_ac_adapter", {"variants": {"kor": {"model": brick_path}}},
		"test.mod").is_empty(), "models/a region it was never sold in is refused")
	_ok(not PowerBrickCatalog.override_brick("nes_ac_adapter", {"dc_plug": "eiaj_03"}, "test.mod").is_empty(),
		"models/its plug's standard is the game's, not the mod's")
	_ok(not PowerBrickCatalog.override_brick("nes_ac_adapter",
		{"variants": {"eur": {"model": "res://mods/nothing/here.glb"}}}, "test.mod").is_empty(),
		"models/a scene that is not there is refused")
	var err := PowerBrickCatalog.override_brick("nes_ac_adapter", {"plug_model": plug_path,
		"variants": {"eur": {"model": brick_path}, "usa": {"model": wart_path}}}, "test.mod")
	_eq(err, "", "models/a mod dresses the NES adapter")
	_ok(not PowerBrickCatalog.override_brick("nes_ac_adapter", {"plug_model": plug_path}, "other.mod").is_empty(),
		"models/a second mod cannot dress it again")

	var pal := _brick("nes_ac_adapter", "eur", Vector3(0.5, 0.3, 0.5))
	var wart := _brick("nes_ac_adapter", "usa", Vector3(-0.5, 0.3, 0.5))
	var plain := _brick("nes_ac_adapter", "ukv", Vector3(0, 0.3, 1.0))
	await _wait(4)
	var body := pal.get_node("Body") as Node3D
	_ok(body.get_node_or_null("Model") != null and body.get_node_or_null("Box") == null,
		"models/the PAL brick wears the model, no box")
	var dc_anchor := body.get_node_or_null("DcAnchor") as Node3D
	_ok(dc_anchor != null and dc_anchor.position.distance_to(Vector3(0, 0.025, 0.06)) < 0.0005,
		"models/its DC cord leaves from the model's DCCordAnchor",
		str(dc_anchor.position) if dc_anchor != null else "none")
	_ok(dc_anchor != null and (-dc_anchor.transform.basis.z).dot(Vector3(0, 0, 1)) > 0.99,
		"models/out of the +Z end it is on")
	var shape := (body.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_ok(shape.size.distance_to(Vector3(0.06, 0.05, 0.12)) < 0.001, "models/its box is the model's",
		str(shape.size))
	_ok(pal.dc_plug.get_node_or_null("Model") != null and not (pal.dc_plug.get_node("PlugTip") as Node3D).visible,
		"models/its DC plug wears the plug model")
	_ok(pal.dc_plug.cable_anchor.distance_to(Vector3(0, 0, -0.0285)) < 0.0005,
		"models/the lead leaves the plug at its CordExit", str(pal.dc_plug.cable_anchor))
	_eq(pal.dc_plug.connector, "barrel_5_5x2_5", "models/and it is still the PAL 5.5 x 2.5 plug")
	_ok(wart.wall_plug.get_node_or_null("Model") != null and wart.wall_plug.get_node_or_null("Box") == null
		and not (wart.wall_plug.get_node("PlugTip") as Node3D).visible,
		"models/the US wart wears its model, blades and all")
	var wart_shape := (wart.wall_plug.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_ok(wart_shape.size.z <= 0.081, "models/the wart's box stops at its face, not its blades",
		str(wart_shape.size))
	var wart_anchor := wart.wall_plug.get_node_or_null("DcAnchor") as Node3D
	_ok(wart_anchor != null and (-wart_anchor.transform.basis.z).dot(Vector3(0, -1, 0)) > 0.99,
		"models/its lead leaves its bottom")
	_ok((plain.get_node("Body") as Node3D).get_node_or_null("Box") != null,
		"models/a region the mod gave no model keeps the primitive")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(wart.wall_plug)
	await _wait(3)
	_ok(MainsPower.plug_live(wart.dc_plug), "models/a dressed wart still powers its plug")

	PowerBrickCatalog.drop_mod("test.mod")
	var again := _brick("nes_ac_adapter", "eur", Vector3(1.0, 0.3, 1.0))
	await _wait(4)
	_ok((again.get_node("Body") as Node3D).get_node_or_null("Box") != null,
		"models/the mod withdrawn, the box is back")
	await _clear()
	for path: String in [brick_path, wart_path, plug_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ── the Virtual Boy: its supply is on its controller ─────────────────────────

func _vb_pad(at: Vector3) -> VbController:
	var pad := VB_PAD.instantiate() as VbController
	pad.position = at
	pad.freeze = true
	_room.add_child(pad)
	pad.add_to_group("spawned")
	await _wait(6)
	return pad


func _test_vb() -> void:
	var plate := _new_room()
	var vb := await _machine("virtualboy", "virtual_boy_primitive")
	var input := PowerInput.of(vb)
	_ok(input != null and input.through.is_valid() and input.inlets().is_empty(),
		"vb/the console has no supply of its own: it comes through a controller")
	if input == null:
		await _clear()
		return
	vb.toggle_power()
	await _wait(2)
	_ok(not vb.is_powered_on, "vb/no controller: it will not switch on")
	_ok(input.why_not().begins_with("No controller plugged in"), "vb/and says so", input.why_not())

	var pad := await _vb_pad(Vector3(1.5, 0.5, 0))
	var pack := pad.get_power_unit()
	_ok(pack != null and pack.kind == "pack", "vb/a fresh controller comes with its battery pack on")
	if pack == null:
		await _clear()
		return
	var mount := pad.get_node("PackMount") as XRToolsSnapZone
	var on_back := pad.to_local(pack.global_position)
	_ok(on_back.distance_to(VbController.PACK_MOUNT_AT) < 0.002, "vb/on the controller's back", str(on_back))
	var cells := CellSlots.of(pack)
	_ok(cells != null and cells.seats().size() == 6, "vb/the pack has six seats",
		str(cells.seats().size() if cells != null else -1))
	_ok(cells != null and CellSlots.size_of_seat(cells.seats()[0]) == "AA", "vb/for AA cells")
	var covers := CoverSlots.of(pack)
	_ok(covers != null and covers.is_on(VbPowerUnit.LID_SOCKET), "vb/its end lid is on")
	_ok(cells != null and cells.is_blocked(), "vb/and with the lid on, nothing goes in")
	if cells == null or covers == null:
		await _clear()
		return
	# A cell's + end: the front layer's toward the lid (+Z), the back layer's away.
	var first := pack.find_child("BatteryAA1", true, false) as Node3D
	var fourth := pack.find_child("BatteryAA4", true, false) as Node3D
	_ok(first != null and first.transform.basis.z.dot(Vector3.BACK) > 0.99
		and fourth != null and fourth.transform.basis.z.dot(Vector3.FORWARD) > 0.99,
		"vb/front cells + toward the lid, back cells + toward the far end")
	_ok(first != null and first.position.y > fourth.position.y, "vb/the front layer is the one on the controller")

	vb.restore_controller_plug(0, pad.get_plug())
	await _wait(4)
	_ok(vb.get_port_controllers()[0] == pad, "vb/the controller is in the console's port")
	vb.toggle_power()
	await _wait(2)
	_ok(not vb.is_powered_on, "vb/an empty pack: no power")
	_ok(input.why_not().contains("Battery pack: No batteries (takes 6 AA)"), "vb/it says the pack is empty",
		input.why_not())

	await _pull(covers.slot(VbPowerUnit.LID_SOCKET))
	await _wait(3)
	_ok(not cells.is_blocked(), "vb/the lid off, the pack is open")
	var seats := cells.seats()
	for i in 5:
		cells.slot(seats[i]).pick_up_object(_cell())
	await _wait(3)
	var slide := pad.latching_power_switch()
	_ok(slide != null, "vb/the controller's POWER slide latches")
	slide.set_value(1.0)
	await _wait(3)
	_ok(not vb.is_powered_on, "vb/switch ON, five cells: nothing")
	_ok(input.why_not().contains("5 of 6 AA"), "vb/one short, it says so", input.why_not())
	cells.slot(seats[5]).pick_up_object(_cell())
	await _wait(4)
	_ok(vb.is_powered_on, "vb/the sixth cell in under a switch left ON: it comes on")
	_ok(input.describe().begins_with("Controller: Battery pack: Batteries (6 AA)"), "vb/its supply, said",
		input.describe())

	await _pull(mount)
	await _wait(4)
	_ok(pad.get_power_unit() == null, "vb/the pack is off the controller")
	_ok(not vb.is_powered_on, "vb/the pack taken off while running: it goes off")
	_ok(slide.value > 0.5, "vb/the switch still ON")

	# The tap in the pack's place, the Super NES adapter in it.
	var tap := VB_TAP.instantiate() as VbPowerUnit
	tap.position = Vector3(1.8, 0.5, 0.4)
	tap.freeze = true
	_room.add_child(tap)
	await _wait(3)
	_eq(tap.variant, "usa", "vb/a tap in North America is the US one")
	_eq(tap.jack.connector if tap.jack != null else "", "snes_dc_plug",
		"vb/which takes the Super NES adapter's plug")
	mount.pick_up_object(tap)
	await _wait(3)
	_ok(pad.get_power_unit() == tap, "vb/the tap goes on in the pack's place")
	_ok(not vb.is_powered_on, "vb/a tap with nothing in it: no power")
	var tap_covers := CoverSlots.of(tap)
	var tap_lid := tap_covers.slot(VbPowerUnit.TAP_LID_SOCKET) if tap_covers != null else null
	_ok(tap_lid != null and tap_covers.is_on(VbPowerUnit.TAP_LID_SOCKET), "vb/the tap comes with its lid on")
	_ok(not tap.jack.enabled, "vb/and with the lid on, its jack takes nothing")
	var lid_cover := tap_lid.picked_up_object as Node3D if tap_lid != null else null
	if tap_lid != null:
		await _pull(tap_lid)
	await _wait(3)
	_ok(tap.jack.enabled, "vb/the lid off, the jack is open")
	var snes := _brick("snes_ac_adapter", "usa", Vector3(0.5, 0.3, 0.5))
	await _wait(4)
	_ok(tap.jack.can_preview(snes.dc_plug), "vb/the SNS-002's plug fits the tap")
	tap.jack.pick_up_object(snes.dc_plug)
	(plate.get_node("TopPort") as PowerPort).pick_up_object(snes.wall_plug)
	await _wait(4)
	_ok(vb.is_powered_on, "vb/the adapter into the tap and the wall: on (its switch was left ON)")
	_ok(input.describe().begins_with("Controller: AC adapter tap: AC adapter, in a wall outlet"),
		"vb/its supply, said", input.describe())
	# The lid closes over the plug, as the real one closes over the SNS-002's.
	if tap_lid != null and lid_cover != null:
		tap_lid.pick_up_object(lid_cover)
	await _wait(3)
	_ok(tap_covers.is_on(VbPowerUnit.TAP_LID_SOCKET) and not snes.dc_plug.enabled,
		"vb/the lid back on over the plug: the plug cannot be pulled")
	_ok(vb.is_powered_on, "vb/and the console stays on")

	# The save: the controller names what is on it; the tap keeps its jack.
	var sp := ScenePersistence.new("arcade")
	var ids := {pad: 0, tap: 1}
	ids[snes] = 3
	var pad_entry := sp.serialize_node(pad, 0, ids)
	var tap_entry := sp.serialize_node(tap, 1, ids)
	var snes_entry := sp.serialize_node(snes, 3, ids)
	var in_tap := false
	for rec: Dictionary in snes_entry.get("plugs", []):
		if str(rec.get("port", "")) == "DcIn" and rec.get("device") == 1:
			in_tap = true
	_ok(in_tap, "save/vb: the adapter's plug is saved in the TAP's jack", str(snes_entry.get("plugs")))
	_eq(pad_entry.get("power_unit"), 1, "save/vb: the controller's entry names the unit on it")
	_eq(str(tap_entry.get("type", "")), "vb_ac_tap", "save/vb: a tap saves as one")
	_eq(str(tap_entry.get("variant", "")), "usa", "save/vb: with its jack")
	_eq(ScenePersistence._entry_validation_error(pad_entry, {0: true, 1: true}), "",
		"save/vb: the controller's entry validates")
	var bare := sp.serialize_node(await _vb_pad(Vector3(-1.0, 0.5, 0.5)), 2, {})
	_ok(bare.has("power_unit"), "save/vb: a pad with its pack in, but not in the map, still writes the key")

	# Unplugging the controller from the console cuts it.
	var port := vb.controller_ports().zones[0] as XRToolsSnapZone
	await _pull(port)
	await _wait(4)
	_ok(not vb.is_powered_on, "vb/the controller unplugged: off")
	_ok(input.why_not().begins_with("No controller plugged in"), "vb/and it says why", input.why_not())
	await _clear()

	# Restored: the tap on the pad, the plain old pad (no key) gets its pack.
	_new_room()
	await _wait(3)
	var old_pad := pad_entry.duplicate(true)
	old_pad.erase("power_unit")
	old_pad["id"] = 2
	var before := get_tree().get_nodes_in_group(VbPowerUnit.GROUP)
	snes_entry["plugs"] = (snes_entry["plugs"] as Array).filter(
		func(rec: Dictionary) -> bool: return str(rec.get("port", "")) == "DcIn")
	var spawned := sp.instantiate_objects(_room, [pad_entry, tap_entry, old_pad, snes_entry])
	await _wait(12)
	var pad2 := spawned.get(0) as VbController
	var tap2 := spawned.get(1) as VbPowerUnit
	var old2 := spawned.get(2) as VbController
	_ok(pad2 != null and tap2 != null and pad2.get_power_unit() == tap2, "save/vb: the tap is back on its pad")
	_ok(tap2 != null and tap2.jack != null and tap2.jack.connector == "snes_dc_plug", "save/vb: the same jack")
	_ok(old2 != null and old2.get_power_unit() != null and old2.get_power_unit().kind == "pack",
		"save/vb: a pad saved before packs comes back with one")
	var made := 0
	for n in get_tree().get_nodes_in_group(VbPowerUnit.GROUP):
		if not before.has(n):
			made += 1
	_eq(made, 2, "save/vb: and no other pack was made (the tap and the old pad's)")
	var snes2 := spawned.get(3) as PowerBrick
	_ok(snes2 != null and tap2 != null and tap2.jack.picked_up_object == snes2.dc_plug,
		"save/vb: the adapter's plug is back in the tap")
	await _clear()

	# Japan's tap takes the Famicom adapter's plug.
	var region := AppPrefs.mains_region
	AppPrefs.mains_region = "jp"
	_new_room()
	var jp := VB_TAP.instantiate() as VbPowerUnit
	_room.add_child(jp)
	await _wait(2)
	_eq(jp.variant, "jpn", "vb/a tap bought in Japan")
	_eq(jp.jack.connector if jp.jack != null else "", "barrel_5_5x2_1", "vb/takes the HVC-002's plug")
	AppPrefs.mains_region = region
	await _clear()
