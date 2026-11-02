## NesSatellite — the NES Satellite's transmitter (NES-032, 1989), a primitive
## stand-in. Everything below is from Nintendo's instruction booklet and the
## photographs (docs/dev/four-player-adapters.md):
##
##   * A two-tone box, its lower band dark grey, with a recessed channel down its
##     left side holding four NES sockets two by two (1 and 2 nearest the player,
##     3 and 4 behind), the TURBO B and A buttons, the CTLR/GUN mode switch, the
##     power switch with its red LED, and at the far end the black infrared lens.
##   * SIX "C" cells, behind a battery door on the BOTTOM.
##   * The power switch is a push button: press it and the red LED lights; press it
##     again to turn it off; left seven minutes unused, it turns ITSELF off.
##   * TURBO A and B for all four sockets at once (as the Four Score's).
##   * Mode switch: CTLR for controllers, GUN for any game using the Zapper, which
##     must then be in socket 2.
##   * No 2/4 switch: it "operates differently in the three or four-player mode",
##     so a controller in socket 3 or 4 makes it a four-player adapter, and two-
##     player games want those sockets empty.
##   * The infrared reaches 1 to 15 feet, "approximately 60 degrees from side to side
##     and 30 degrees up and down", and nothing may stand between the lenses.
##
## The receiver (NesSatelliteReceiver) is what sits in the NES's two ports. This
## pairs with the nearest seated receiver no other transmitter has (_repair), and
## routes its sockets through it exactly as the Four Score does through its block
## (NesFourScore: ports 0-3, the second pad on a line two ports on, fceumm's
## Gamepad on 2 and 3). What the infrared adds is a GATE on the input, not on the
## routing: every pad's frame passes filter_port_input, which lets it through only
## while the link is up -- powered, cells in, a receiver seated, in range and in the
## beam and in sight -- and otherwise sends the console a released pad, as a
## receiver hearing nothing does. Routing stays put through a moment out of sight,
## so a hand passing between the lenses never re-plugs four pads.
##
## Sizes are estimates (no measurement was found): 175 x 56 x 240 mm.
## What the ON/OFF state of the TURBO buttons is across a power cycle is not known
## (they might be electronic toggles that reset): here they latch, as the Four
## Score's do, and keep their state.
class_name NesSatellite
extends NesFourScore


const GROUP := "nes_satellite"

const SAT_WIDTH := 0.175
const SAT_LENGTH := 0.240
const SAT_HEIGHT := 0.056
## The dark lower band; the light grey shell stands on it (above the battery
## pocket cut into the bottom, so the pocket shows no grey inside).
const BAND_HEIGHT := 0.0325
## The recessed channel's top, and its span across the box.
const RECESS_TOP := 0.0445
const RECESS_X := Vector2(-0.0875, -0.0075)
const COL_L := -0.0655
const COL_R := -0.0305

## The infrared, from the booklet: 1 to 15 feet, 60 degrees side to side, 30 up
## and down. The receiver's own acceptance is not given: its lens is wide and
## faces up and out, so anything in front of it within 80 degrees of its face.
const RANGE_MIN := 0.3048
const RANGE_MAX := 4.572
const BEAM_HALF_H := 30.0
const BEAM_HALF_V := 15.0
const RECEIVER_HALF := 80.0
## Seven minutes unused and it turns itself off.
const AUTO_OFF_SECONDS := 420.0
## How often the link is looked at (physics ticks), and pairing re-asked (seconds).
const LOOK_TICKS := 6
const REPAIR_SECONDS := 1.0

const SAT_LIGHT := Color(0.75, 0.75, 0.73)
const SAT_DARK := Color(0.45, 0.45, 0.46)

## The mode switch: GUN for the Zapper (socket 2), CTLR otherwise.
@export var gun_mode: bool = false

var _receiver: NesSatelliteReceiver = null
var _powered := false
var _link_ok := false
var _idle := 0.0
var _look_tick := 0
var _repair_left := 0.0
var _was_four := false
var _was_paired := false
## The receiver's ports as last routed: its second plug's seat comes a call after
## its first.
var _known_lines: Array[int] = [-1, -1]
var _supply: PowerInput = null
var _power_button: VRButton = null
var _power_led: StandardMaterial3D = null
var _gun_switch: VRSlider = null


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	_repair.call_deferred()


func save_type() -> String:
	return "nes_satellite"


func _tag() -> String:
	return "Satellite"


func _mode_text() -> String:
	return "%s, %s" % ["GUN" if gun_mode else "CTLR", "four-player" if _four_player() else "two-player"]


## No cord: the receiver is the end that sits in the console.
func _has_cable() -> bool:
	return false


func _lead() -> Node3D:
	return _receiver if is_instance_valid(_receiver) else null


## Its seat is the receiver's to save (that object's own entry), not this one's.
func get_connected_system() -> RetroSystem:
	return null


func get_cabinet_port() -> int:
	return -1


func restore_port_connection(_system_arg: RetroSystem, _port_index: int) -> void:
	pass


## Four players when something is in socket 3 or 4 (and the switch is at CTLR).
func _four_player() -> bool:
	return not gun_mode and (socket_plug(2) != null or socket_plug(3) != null)


func is_powered() -> bool:
	return _powered


func link_up() -> bool:
	return _link_ok


## The receiver it is paired with, or null.
func receiver() -> NesSatelliteReceiver:
	return _lead() as NesSatelliteReceiver


# ── Pairing ───────────────────────────────────────────────────────────────────

## Take the nearest seated receiver that no other transmitter has, or keep the one
## it has while that one is still seated. Called when any receiver seats or leaves,
## once a second, and on spawn.
func _repair() -> void:
	if not is_inside_tree():
		return
	var keep := _receiver != null and is_instance_valid(_receiver) and _receiver.is_plugged_in() \
		and _receiver.transmitter == self
	if keep:
		if _receiver.get_connected_system() != _system:
			print("[Satellite] the receiver moved to %s" % _receiver.get_connected_system().name)
			_teardown()
			_system = _receiver.get_connected_system()
			_resync()
		elif _lead_ports() != _known_lines:
			# Its second plug seated after the first told it: route that line too.
			_resync()
		_known_lines = _lead_ports()
		return
	var best: NesSatelliteReceiver = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(NesSatelliteReceiver.GROUP):
		var rx := n as NesSatelliteReceiver
		if rx == null or not rx.is_plugged_in():
			continue
		if is_instance_valid(rx.transmitter) and rx.transmitter != self:
			continue
		var d := rx.global_position.distance_to(_lens_point())
		if d < best_d:
			best = rx
			best_d = d
	if best == _receiver:
		return
	if is_instance_valid(_receiver) and _receiver.transmitter == self:
		_receiver.transmitter = null
	_teardown()
	_receiver = best
	_system = best.get_connected_system() if best != null else null
	if best != null:
		best.transmitter = self
		print("[Satellite] paired with the receiver in %s, %.2f m away" % [_system.name, best_d])
	elif _was_paired:
		print("[Satellite] no receiver to pair with")
	_was_paired = best != null
	_resync()
	_was_four = _four_player()
	_known_lines = _lead_ports()



## A pad in socket 3 or 4 (or none any more) changes what the unit is: the ports
## are told again.
func _on_sub_snapped(i: int, plug: Node3D) -> void:
	super._on_sub_snapped(i, plug)
	_check_four()


func _on_sub_released(i: int) -> void:
	super._on_sub_released(i)
	_check_four()


func _check_four() -> void:
	var four := _four_player()
	if four == _was_four:
		return
	_was_four = four
	print("[Satellite] %s" % ("a controller in socket 3 or 4: four-player mode" if four
		else "sockets 3 and 4 empty: one or two-player mode"))
	if is_instance_valid(_system):
		_resync()


func _dead_reason(i: int) -> String:
	if i >= 2 and gun_mode:
		return ": at GUN only sockets 1 and 2 are carried"
	return ": no receiver is paired"


## In CTLR the Zapper's light lines are not carried: a gun in socket 2 is a pad
## with nothing pressed, as far as the console can tell. At GUN it is the Zapper.
func port_device(machine: Node, port: int) -> Dictionary:
	var dev := super.port_device(machine, port)
	if not gun_mode and (int(dev.get("type", 0)) & RetroSystem.RETRO_DEVICE_MASK) == RetroSystem.RETRO_DEVICE_LIGHTGUN:
		return {"type": RETRO_DEVICE_JOYPAD, "names": PackedStringArray()}
	return dev


# ── The link ──────────────────────────────────────────────────────────────────

## Every pad's frame: a press keeps the unit awake and blinks the receiver; with no
## link the console hears a released pad; with one, TURBO as the Four Score.
func filter_port_input(port: int, pad: Dictionary) -> Dictionary:
	var pressed := int(pad.get("btn", 0)) != 0
	for axis: String in ["alx", "aly", "arx", "ary"]:
		if absi(int(pad.get(axis, 0))) > 4096:
			pressed = true
	if pressed:
		_idle = 0.0
	if not _link_ok:
		var quiet := pad.duplicate()
		quiet["btn"] = 0
		for axis: String in ["alx", "aly", "arx", "ary"]:
			quiet[axis] = 0
		return quiet
	if pressed and is_instance_valid(_receiver):
		_receiver.flash()
	return super.filter_port_input(port, pad)


## The lens's middle and the way it looks (-Z, the box's front), in world space.
func _lens_point() -> Vector3:
	return global_transform * Vector3((RECESS_X.x + RECESS_X.y) * 0.5, RECESS_TOP + 0.004, -SAT_LENGTH * 0.5 - 0.001)


## Whether the receiver is in the beam and in sight, and close enough.
func in_sight_of(rx: NesSatelliteReceiver) -> bool:
	if rx == null or not is_instance_valid(rx) or not rx.is_inside_tree():
		return false
	var from := _lens_point()
	var to := rx.lens_point()
	var d := to - from
	var dist := d.length()
	if dist < RANGE_MIN or dist > RANGE_MAX:
		return false
	var local := global_basis.orthonormalized().inverse() * d
	if local.z >= 0.0:
		return false
	var side := rad_to_deg(atan2(absf(local.x), -local.z))
	var up := rad_to_deg(atan2(absf(local.y), -local.z))
	if side > BEAM_HALF_H or up > BEAM_HALF_V:
		return false
	if rx.lens_normal().dot(-d / dist) < cos(deg_to_rad(RECEIVER_HALF)):
		return false
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, IrBus.SIGHT_MASK)
	var skip: Array[RID] = [get_rid(), rx.get_rid()]
	var console := rx.get_connected_system()
	if console != null:
		skip.append(console.get_rid())
	query.exclude = skip
	query.hit_from_inside = true
	return world.direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_repair_left -= delta
	if _repair_left <= 0.0:
		_repair_left = REPAIR_SECONDS
		_repair()
	if _powered:
		_idle += delta
		if _idle >= AUTO_OFF_SECONDS:
			print("[Satellite] seven minutes unused: it turns itself off")
			_set_powered(false)
	_look_tick += 1
	if _look_tick < LOOK_TICKS:
		return
	_look_tick = 0
	var ok := _powered and is_instance_valid(_receiver) and _receiver.is_plugged_in() and in_sight_of(_receiver)
	if ok != _link_ok:
		_link_ok = ok
		print("[Satellite] link %s%s" % ["up" if ok else "down", "" if ok else " (%s)" % _why_down()])
		if ok and is_instance_valid(_receiver):
			_receiver.flash(0.3)


## Why the link is down, for the log line.
func _why_down() -> String:
	if not _powered:
		return "off"
	if not is_instance_valid(_receiver):
		return "no receiver paired"
	if not _receiver.is_plugged_in():
		return "the receiver is in no console"
	var dist := _receiver.lens_point().distance_to(_lens_point())
	if dist < RANGE_MIN or dist > RANGE_MAX:
		return "%.2f m away: works from 0.30 to 4.57 m" % dist
	return "out of the beam or something in the way"


# ── Power ─────────────────────────────────────────────────────────────────────

func press_power() -> void:
	if _powered:
		_set_powered(false)
		return
	if _supply != null and not _supply.is_live():
		print("[Satellite] the power switch does nothing: %s" % _supply.why_not())
		return
	_set_powered(true)


func _set_powered(on: bool) -> void:
	if on == _powered:
		return
	_powered = on
	_idle = 0.0
	if _power_led != null:
		_power_led.emission_enabled = on
		_power_led.albedo_color = Color(1.0, 0.12, 0.08) if on else Color(0.3, 0.06, 0.05)
	print("[Satellite] power %s" % ("on (the red LED lights)" if on else "off"))
	if not on and _link_ok:
		_link_ok = false
		print("[Satellite] link down (off)")


func _on_supply_changed(live: bool) -> void:
	if not live and _powered:
		print("[Satellite] the cells came out with it on: off")
		_set_powered(false)


# ── Body ──────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	var dark := _material(SAT_DARK, 0.6)
	var light := _material(SAT_LIGHT, 0.55)
	var black := _material(BLACK, 0.25)
	var socket_dark := _material(Color(0.02, 0.02, 0.02), 0.9)
	var bezel := _material(BLACK, 0.7)
	var hw := SAT_WIDTH * 0.5
	var hl := SAT_LENGTH * 0.5

	# The dark body, the full footprint up to the recess floor: the box the battery
	# pocket is cut into (BatteryBay), so its bottom is the battery door's face.
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	var box := BoxMesh.new()
	box.size = Vector3(SAT_WIDTH, RECESS_TOP, SAT_LENGTH)
	body.mesh = box
	body.material_override = dark
	add_child(body)
	body.position = Vector3(0.0, RECESS_TOP * 0.5, 0.0)
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(SAT_WIDTH, SAT_HEIGHT, SAT_LENGTH)
		col.shape = shape
		col.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, SAT_HEIGHT * 0.5, 0.0))
	# The light grey shell on the dark band: the raised right part and the
	# channel's skin, each standing a hair outside the dark box so no two faces lie
	# in one plane.
	var o := 0.0005
	var raised_w := hw + o - RECESS_X.y
	_add_box(self, Vector3(raised_w, SAT_HEIGHT - BAND_HEIGHT + o, SAT_LENGTH + 2.0 * o), Transform3D(Basis.IDENTITY,
		Vector3(RECESS_X.y + raised_w * 0.5, (BAND_HEIGHT + SAT_HEIGHT + o) * 0.5, 0.0)), light, "ShellRaised")
	var chan_w := RECESS_X.y - (-hw - o)
	_add_box(self, Vector3(chan_w, RECESS_TOP + o - BAND_HEIGHT, SAT_LENGTH + 2.0 * o), Transform3D(Basis.IDENTITY,
		Vector3(-hw - o + chan_w * 0.5, (BAND_HEIGHT + RECESS_TOP + o) * 0.5, 0.0)), light, "ShellChannel")
	# The lens: black, filling the channel's far end up to the top.
	var lens_d := 0.040
	_add_box(self, Vector3(RECESS_X.y - RECESS_X.x - 0.002, SAT_HEIGHT - RECESS_TOP + 0.002, lens_d), Transform3D(Basis.IDENTITY,
		Vector3((RECESS_X.x + RECESS_X.y) * 0.5, (RECESS_TOP + SAT_HEIGHT) * 0.5, -hl + lens_d * 0.5 - o * 2.0)), black, "Lens")
	_top = Node3D.new()
	_top.name = "Top"
	add_child(_top)

	var floor_y := RECESS_TOP + o
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in range(SOCKETS):
		var at := _socket_at(i)
		_add_box(_top, Vector3(0.021, 0.0016, 0.030), Transform3D(Basis.IDENTITY, Vector3(at.x, floor_y + 0.0008, at.y)), bezel)
		_add_box(_top, Vector3(0.0165, 0.0012, 0.025), Transform3D(Basis.IDENTITY, Vector3(at.x, floor_y + 0.0017, at.y)), socket_dark)
		var lbl := _add_label(_top, str(i + 1), Transform3D(flat, Vector3(at.x, floor_y + 0.0004, at.y + 0.0185)), PRINT_RED, 18)
		lbl.name = "SocketLabel%d" % (i + 1)
		_labels.append(lbl)
	_add_label(_top, "B", Transform3D(flat, Vector3(COL_L - 0.014, floor_y + 0.0004, 0.016)), PRINT_RED, 16)
	_add_label(_top, "A", Transform3D(flat, Vector3(COL_R + 0.014, floor_y + 0.0004, 0.016)), PRINT_RED, 16)
	_add_label(_top, "TURBO", Transform3D(flat, Vector3((COL_L + COL_R) * 0.5, floor_y + 0.0004, 0.030)), PRINT_RED, 12)
	_add_label(_top, "CTLR", Transform3D(flat, Vector3(COL_L - 0.004, floor_y + 0.0004, -0.010)), PRINT_RED, 12)
	_add_label(_top, "GUN", Transform3D(flat, Vector3(COL_R + 0.006, floor_y + 0.0004, -0.010)), PRINT_RED, 12)
	_add_label(_top, "POWER", Transform3D(flat, Vector3(COL_L, floor_y + 0.0004, -0.050)), PRINT_RED, 12)
	_add_box(_top, Vector3(0.026, 0.0008, 0.010), Transform3D(Basis.IDENTITY, Vector3((COL_L + COL_R) * 0.5, floor_y + 0.0004, -0.020)), socket_dark)
	# The red power LED, just short of the lens.
	var led := MeshInstance3D.new()
	led.name = "PowerLed"
	var sphere := SphereMesh.new()
	sphere.radius = 0.002
	sphere.height = 0.004
	led.mesh = sphere
	_power_led = _material(Color(0.3, 0.06, 0.05), 0.3)
	_power_led.emission = Color(1.0, 0.15, 0.1)
	_power_led.emission_energy_multiplier = 2.5
	led.material_override = _power_led
	_top.add_child(led)
	led.position = Vector3(COL_R, floor_y + 0.0015, -0.068)

	# Six C cells behind a door on the bottom (BatteryBay: the pocket, contacts,
	# seats and cover, saved and synced as every cover in the room is).
	var seats := BatteryBay.build(self, AABB(Vector3(-hw, 0.0, -hl), Vector3(SAT_WIDTH, RECESS_TOP, SAT_LENGTH)),
		{"size": "C", "count": 6, "along": "z", "at": [0.0, 0.1]}, "nes_satellite_battery_cover", SAT_DARK, body)
	print("[Satellite] battery bay built: %d C seats" % seats)
	_supply = PowerInput.on(self)
	_supply.label = "NES Satellite (%s)" % name
	_supply.power_changed.connect(_on_supply_changed)


## Where socket `i` stands on the channel floor, (x, z): 1 and 2 nearest the
## player (+Z), 3 and 4 behind them.
static func _socket_at(i: int) -> Vector2:
	var x := COL_L if i % 2 == 0 else COL_R
	var z := 0.088 if i < 2 else 0.050
	return Vector2(x, z)


func _socket_transform(i: int) -> Transform3D:
	var at := _socket_at(i)
	var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.BACK, PI)
	return Transform3D(b, Vector3(at.x, RECESS_TOP + 0.0021, at.y))


## No 2/4 switch: the CTLR/GUN slide is built with the other controls.
func _build_mode_switch() -> VRSlider:
	return null


func _build_extra_controls() -> void:
	var floor_y := RECESS_TOP + 0.0005
	_turbo_b_button = _build_turbo_button("TurboB", Vector3(COL_L, floor_y + 0.003, 0.016), "b")
	_turbo_a_button = _build_turbo_button("TurboA", Vector3(COL_R, floor_y + 0.003, 0.016), "a")
	_turbo_a_button.set_latched_pressed(turbo_a)
	_turbo_b_button.set_latched_pressed(turbo_b)
	# CTLR on the left, GUN on the right, as the photograph's legend reads.
	var cap: Array = _oval_cap(0.010, 0.014, 0.005)
	_gun_switch = _add_slide(_top, "ModeSwitch", Vector3((COL_L + COL_R) * 0.5, floor_y + 0.0028, -0.020),
		Vector3(1, 0, 0), 0.010, 1.0 if gun_mode else 0.0, _material(CAP_GREY, 0.5), cap[0], cap[1])
	_gun_switch.value_changed.connect(func(v: float) -> void: set_gun_mode(v >= 0.5))
	# The power switch: a push button (the unit itself remembers on or off).
	var b := VRButton.new()
	b.name = "PowerSwitch"
	b.state_tint = false
	b.depress_depth = 0.002
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.013, 0.010, 0.020)
	shape.shape = bs
	b.add_child(shape)
	var pcap: Array = _oval_cap(0.0115, 0.017, 0.006)
	var mesh := MeshInstance3D.new()
	mesh.name = "ButtonMesh"
	mesh.mesh = pcap[0]
	mesh.scale = pcap[1]
	mesh.material_override = _material(CAP_GREY, 0.5)
	b.add_child(mesh)
	_top.add_child(b)
	b.position = Vector3(COL_R, floor_y + 0.003, -0.048)
	b.button_pressed.connect(press_power)
	_power_button = b


func set_gun_mode(on: bool) -> void:
	if on == gun_mode:
		return
	gun_mode = on
	if _gun_switch != null and _gun_switch.value != (1.0 if on else 0.0):
		_gun_switch.set_value_no_signal(1.0 if on else 0.0)
	print("[Satellite] mode switch -> %s" % ("GUN" if on else "CTLR"))
	_was_four = _four_player()
	if is_instance_valid(_system):
		_resync()
