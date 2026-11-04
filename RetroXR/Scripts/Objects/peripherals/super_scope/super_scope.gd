## SuperScope — Nintendo's Super Scope (SNS-013, 1992) for the Super NES, a
## primitive stand-in. Everything below is from the photographs, the Wikipedia
## article and the cores' sources (docs/dev/super-scope.md):
##
##   * A cordless bazooka just under 61 cm long, its orange-ringed lens at the
##     MUZZLE, a pistol grip hanging under the barrel near the front, a curved
##     dark shoulder rest under the rear stock.
##   * On top, midway along, front to back: FIRE (purple), PAUSE (grey, round)
##     and the power switch, OFF / ON / TURBO. CURSOR is on the grip.
##   * Six AA cells, in the rear stock: two rows of three in a tube running
##     diagonally through it (the cut-away photograph), behind a door in the
##     stock's sloped underside. Here they lie six across the stock instead
##     (BatteryBay's layout), a stand-in's simplification.
##   * The sight clips onto either side of the barrel (SuperScopeSight).
##   * It talks to its receiver (SuperScopeReceiver, in the console's port 2) by
##     INFRARED from the window in the hump over the muzzle.
##
## It is a LightGun with no cord: the receiver's plug is what the console sees,
## and the scope pairs with the nearest seated receiver (_repair) and sends the
## gun's state down that port. What the infrared adds is a GATE (_link_ok): with
## the switch OFF, the cells flat or missing, or the receiver out of the beam or
## out of sight, the console hears a gun pointed off the screen with nothing
## pressed, as a receiver hearing nothing reports.
##
## The cores, measured: snes9x reads Fire = TRIGGER, Cursor = AUX_A, Turbo =
## AUX_B, Pause = START, and TURBO is a TOGGLE it flips on each rising edge
## (controls.cpp), where the hardware's is a switch that stays. So the hand never
## presses AUX_B (claim_button), and the scope pulses it whenever the switch and
## what the core believes part (_drive_turbo). bsnes reads a Super Scope only as
## a touchscreen pointer, so the scope plays on snes9x.
##
## Its frame: the origin is the middle of the grip (where the hand holds it),
## -Z toward the muzzle, +Y up. Sizes are scaled off the photographs to the 61 cm
## length; every number not in the paragraph above is an ESTIMATE.
class_name SuperScope
extends LightGun


const GROUP := "super_scope"
const SAVE_TYPE := "super_scope"

## The power switch's three positions, saved as an int.
const SWITCH_OFF := 0
const SWITCH_ON := 1
const SWITCH_TURBO := 2
const SWITCH_NAMES: Array[String] = ["OFF", "ON", "TURBO"]

# ── Geometry (metres, this frame) ─────────────────────────────────────────────

## The muzzle's front, the rear tip of the stock, and the barrel.
const MUZZLE_Z := -0.087
const REAR_Z := 0.520
const BARREL_Y := 0.086
const BARREL_RADIUS := 0.031
const BARREL_END_Z := 0.193
## The rear body: from the barrel's end to the stock's tip.
const BODY_W := 0.058
const BODY_BOTTOM := 0.055
const BODY_TOP := 0.112
## The stock's lower block, where the cells are.
const STOCK_Z := Vector2(0.255, 0.395)
const STOCK_BOTTOM := 0.0
## The grip: its size and its lean (its top forward).
const GRIP_SIZE := Vector3(0.032, 0.110, 0.040)
const GRIP_LEAN_DEG := -17.0
## The controls along the top, front to back.
const FIRE_Z := 0.225
const PAUSE_Z := 0.256
const SWITCH_Z := 0.283
const SWITCH_TRAVEL := 0.012
## The sight clips' middle on each side.
const CLIP_Z := 0.081
const CLIP_Y := BARREL_Y + 0.022
const CLIP_X := BARREL_RADIUS + 0.003

# ── The infrared (ESTIMATES: no figure was found) ─────────────────────────────

## Nintendo's own figure is that it aims best from about 3 m; the link is
## allowed twice that.
const RANGE_MIN := 0.30
const RANGE_MAX := 6.0
## Half the beam out of the scope's window, either way, and how far off its own
## face the receiver's window still hears it.
const BEAM_HALF := 30.0
const RECEIVER_HALF := 60.0
## How often the link is looked at (physics ticks), and pairing re-asked (seconds).
const LOOK_TICKS := 6
const REPAIR_SECONDS := 1.0

## How long a turbo pulse holds AUX_B down, and the gap after it: long enough
## that the core polls it at least once each way (a 60 Hz frame is 16.7 ms).
const TURBO_PULSE := 0.06

## What the console's core believes of the turbo toggle, kept on the CONSOLE: it
## outlives a receiver pulled and put back, and is the core's, not this scope's.
const TURBO_META := &"super_scope_core_turbo"

const SHELL := Color(0.74, 0.74, 0.72)
const SHELL_DARK := Color(0.6, 0.6, 0.62)
const STRIP := Color(0.24, 0.24, 0.26)
const REST := Color(0.3, 0.3, 0.32)
const LENS := Color(0.95, 0.32, 0.12)
const FIRE_COLOR := Color(0.36, 0.3, 0.72)
const CAP_GREY := Color(0.55, 0.55, 0.58)
const BLACK := Color(0.05, 0.05, 0.055)

## The OFF / ON / TURBO switch (saved).
@export var power_switch: int = SWITCH_OFF

var _receiver: SuperScopeReceiver = null
var _link_ok := false
var _look_tick := 0
var _repair_left := 0.0
var _supply: PowerInput = null
var _switch: VRSlider = null
var _clips: Array[XRToolsSnapZone] = []
var _sight: SuperScopeSight = null
var _seeded := false
## The turbo pulse in flight: time left down, then time left in the gap after.
var _pulse_down := 0.0
var _pulse_gap := 0.0
var _was_running := false
var _state_hooked: RetroSystem = null


func _init() -> void:
	systemid = "snes"
	device_names = PackedStringArray(["superscope", "super scope"])


func _ready() -> void:
	_build_body()
	super._ready()
	add_to_group(GROUP)
	# The hand's AUX_B never reaches the core: turbo is the switch's (_drive_turbo).
	claim_button(ControllerBindings.LIGHTGUN_AUX_B, true)
	power_switch = clampi(power_switch, SWITCH_OFF, SWITCH_TURBO)
	_switch.set_value_no_signal(power_switch * 0.5)
	_build_clips()
	if not has_meta(CoverSlots.RESTORING):
		_seed_sight.call_deferred()
	_repair.call_deferred()
	print("[SuperScope] ready: switch %s" % SWITCH_NAMES[power_switch])


func save_type() -> String:
	return SAVE_TYPE


# ── No cord: the receiver is the end in the console ───────────────────────────

func _spawn_cable() -> void:
	pass


## Its port is the receiver's to save (that object's own entry), not this one's.
func get_connected_system() -> RetroSystem:
	return null


func restore_port_connection(_system_arg: RetroSystem, _port_index: int) -> void:
	print("[SuperScope] a port restore was asked of the scope: the receiver keeps the port")


## The receiver it is paired with, or null.
func receiver() -> SuperScopeReceiver:
	return _receiver if is_instance_valid(_receiver) else null


## Whether the infrared reaches the receiver now: what the gate opens on.
func link_up() -> bool:
	return _link_ok


func set_power_switch(position: int) -> void:
	position = clampi(position, SWITCH_OFF, SWITCH_TURBO)
	if position == power_switch:
		return
	power_switch = position
	if _switch != null and not is_equal_approx(_switch.value, position * 0.5):
		_switch.set_value_no_signal(position * 0.5)
	print("[SuperScope] switch -> %s" % SWITCH_NAMES[position])
	_look_tick = LOOK_TICKS


func is_switched_on() -> bool:
	return power_switch != SWITCH_OFF


func _exit_tree() -> void:
	var rx := receiver()
	if rx != null and rx.scope == self:
		rx.scope = null
	_unbind()
	super._exit_tree()


# ── Pairing ───────────────────────────────────────────────────────────────────

## Keep the receiver it has while that one is seated, else take the nearest
## seated one no other scope has. Called when any receiver seats or leaves, once
## a second, and on spawn.
func _repair() -> void:
	if not is_inside_tree():
		return
	var rx := receiver()
	if rx != null and rx.is_plugged_in() and rx.scope == self:
		if rx.get_connected_system() != _connected_system or rx.get_port_index() != _port_index:
			print("[SuperScope] the receiver moved to %s port %d" % [rx.get_connected_system().name, rx.get_port_index()])
			_unbind()
			_bind(rx)
		return
	var best: SuperScopeReceiver = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(SuperScopeReceiver.GROUP):
		var cand := n as SuperScopeReceiver
		if cand == null or not cand.is_plugged_in():
			continue
		if is_instance_valid(cand.scope) and cand.scope != self:
			continue
		var d := cand.lens_point().distance_to(window_point())
		if d < best_d:
			best = cand
			best_d = d
	if best == rx and (rx == null or _connected_system != null):
		return
	if rx != null and rx.scope == self:
		rx.scope = null
	_unbind()
	_receiver = best
	if best != null:
		best.scope = self
		print("[SuperScope] paired with the receiver in %s port %d, %.2f m away"
			% [best.get_connected_system().name, best.get_port_index(), best_d])
		_bind(best)


func _bind(rx: SuperScopeReceiver) -> void:
	var sys := rx.get_connected_system()
	if sys == null:
		return
	on_plugged_in(sys, rx.get_port_index())
	_was_running = sys.is_powered_on
	if not sys.is_powered_on:
		sys.set_meta(TURBO_META, false)
	if _state_hooked != sys:
		_unhook_state()
		sys.state_loaded.connect(_on_state_loaded)
		_state_hooked = sys
	_look_tick = LOOK_TICKS


## Off the port: every button let go and the aim off the screen FIRST, while the
## port is still this scope's to write, then LightGun's own unplug.
func _unbind() -> void:
	if _connected_system == null:
		return
	var lib := _connected_system.get_libretro_node()
	if lib != null:
		var was := _link_ok
		_link_ok = false
		for lid: int in _sent_ids():
			_set_button(lib, lid, false)
		_set_aim(lib, 0, 0, true)
		_link_ok = was
	_pulse_down = 0.0
	_pulse_gap = 0.0
	set_external_button(ControllerBindings.LIGHTGUN_AUX_B, false)
	_unhook_state()
	_link_ok = false
	on_unplugged()


func _unhook_state() -> void:
	if is_instance_valid(_state_hooked) and _state_hooked.state_loaded.is_connected(_on_state_loaded):
		_state_hooked.state_loaded.disconnect(_on_state_loaded)
	_state_hooked = null


## Every id the scope writes: the map's buttons and the turbo bit.
func _sent_ids() -> Array[int]:
	var ids: Array[int] = [ControllerBindings.LIGHTGUN_TRIGGER, ControllerBindings.LIGHTGUN_AUX_A,
		ControllerBindings.LIGHTGUN_AUX_B, ControllerBindings.LIGHTGUN_START]
	for source: String in _lightgun_map:
		var lid: Variant = _lightgun_map[source]
		if lid is int and int(lid) >= 0 and not ids.has(int(lid)):
			ids.append(int(lid))
	return ids


func _on_state_loaded(_state_id: String, ok: bool, _reason: String) -> void:
	if ok:
		print("[SuperScope] a savestate loaded: the core's turbo is the state's now, "
			+ "and the switch is believed to match (unverified)")


# ── The link ──────────────────────────────────────────────────────────────────

## The scope's infrared window: the hump over the muzzle, looking forward.
func window_point() -> Vector3:
	return global_transform * Vector3(0.0, BARREL_Y + BARREL_RADIUS + 0.008, MUZZLE_Z - 0.002)


## Whether the receiver is in the beam and in sight, and close enough.
func in_sight_of(rx: SuperScopeReceiver) -> bool:
	return _sight_problem(rx).is_empty()


## Why the receiver cannot hear the scope, or "" when it can.
func _sight_problem(rx: SuperScopeReceiver) -> String:
	if rx == null or not is_instance_valid(rx) or not rx.is_inside_tree():
		return "no receiver"
	var from := window_point()
	var to := rx.lens_point()
	var d := to - from
	var dist := d.length()
	if dist < RANGE_MIN or dist > RANGE_MAX:
		return "%.2f m away (works %.2f to %.1f m)" % [dist, RANGE_MIN, RANGE_MAX]
	var fwd := -global_basis.orthonormalized().z
	var off := rad_to_deg(fwd.angle_to(d / dist))
	if off > BEAM_HALF:
		return "%.0f degrees off the beam (half %.0f)" % [off, BEAM_HALF]
	var face := rad_to_deg(rx.lens_normal().angle_to(-d / dist))
	if face > RECEIVER_HALF:
		return "%.0f degrees off the receiver's window (half %.0f)" % [face, RECEIVER_HALF]
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return ""
	var query := PhysicsRayQueryParameters3D.create(from, to, IrBus.SIGHT_MASK)
	var skip: Array[RID] = [get_rid(), rx.get_rid()]
	if is_instance_valid(_sight):
		skip.append(_sight.get_rid())
	var console := rx.get_connected_system()
	if console != null:
		skip.append(console.get_rid())
	query.exclude = skip
	query.hit_from_inside = true
	var hit := world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var who: Object = hit.get("collider")
		return "%s is in the way" % (who.name if who is Node else "something")
	return ""


## Why the link is down, "" when it is up.
func _link_problem() -> String:
	if power_switch == SWITCH_OFF:
		return "the switch is OFF"
	if _supply != null and not _supply.is_live():
		return _supply.why_not()
	var rx := receiver()
	if rx == null or not rx.is_plugged_in():
		return "no receiver in a console"
	return _sight_problem(rx)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_repair_left -= delta
	if _repair_left <= 0.0:
		_repair_left = REPAIR_SECONDS
		_repair()
	_look_tick += 1
	if _look_tick < LOOK_TICKS:
		return
	_look_tick = 0
	var why := _link_problem()
	var ok := why.is_empty()
	if ok != _link_ok:
		_link_ok = ok
		print("[SuperScope] link %s%s" % ["up" if ok else "down", "" if ok else ": " + why])


## What the port was last told of each button (lightgun id -> down), and whether
## the aim was off the screen: the gate's output, for the tests and the debug report.
var sent: Dictionary = {}
var sent_offscreen := true


## The gate on every button: with no link the console hears nothing pressed.
func _set_button(libretro: Libretro, button: int, pressed: bool) -> void:
	var down := _told(button, pressed) and _link_ok
	sent[button] = down
	if not NetworkManager.netplay_set_lightgun_button(_connected_system, _port_index, button, down):
		libretro.SetLightgunButton(_port_index, button, down)


## The gate on the aim: with no link the gun is off the screen.
func _set_aim(libretro: Libretro, x: int, y: int, offscreen: bool) -> void:
	if not _link_ok:
		sent_offscreen = true
		super._set_aim(libretro, 0, 0, true)
		return
	sent_offscreen = offscreen
	super._set_aim(libretro, x, y, offscreen)


# ── Turbo ─────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	super._process(delta)
	_drive_turbo(delta)


## What the console's core believes of turbo, false when nothing says otherwise.
func core_turbo() -> bool:
	if _connected_system == null:
		return false
	return bool(_connected_system.get_meta(TURBO_META, false))


## The core flips turbo on each press of AUX_B; the switch stays where it is put.
## So one press is sent whenever the two part, and only while the link carries
## it (the hardware sends nothing with the switch OFF, so the core keeps what it
## had). A new run of the core starts with turbo off.
func _drive_turbo(delta: float) -> void:
	if _connected_system == null:
		return
	var running := _connected_system.is_powered_on
	if running != _was_running:
		_was_running = running
		if not running:
			_connected_system.set_meta(TURBO_META, false)
	if _pulse_down > 0.0:
		_pulse_down -= delta
		if _pulse_down <= 0.0:
			set_external_button(ControllerBindings.LIGHTGUN_AUX_B, false)
			_pulse_gap = TURBO_PULSE
		return
	if _pulse_gap > 0.0:
		_pulse_gap -= delta
		return
	if not running or not _link_ok:
		return
	var want := power_switch == SWITCH_TURBO
	if want == core_turbo():
		return
	_connected_system.set_meta(TURBO_META, want)
	_pulse_down = TURBO_PULSE
	set_external_button(ControllerBindings.LIGHTGUN_AUX_B, true)
	print("[SuperScope] turbo %s: one press of the core's toggle" % ("on" if want else "off"))


# ── The sight ─────────────────────────────────────────────────────────────────

## The sight on its clip, or null.
func get_sight() -> SuperScopeSight:
	return _sight if is_instance_valid(_sight) else null


## Which side the sight is on: "left", "right" or "".
func sight_side() -> String:
	for i in _clips.size():
		if _clips[i].has_snapped_object():
			return "left" if i == 0 else "right"
	return ""


## Put a save's sight back on `side` ("left" / "right").
func restore_sight(sight: SuperScopeSight, side: String) -> void:
	_seeded = true
	if not is_instance_valid(sight):
		return
	var i := 1 if side == "right" else 0
	if i >= _clips.size() or _clips[i].has_snapped_object():
		push_warning("[SuperScope] sight clip %s is not free; the sight is left where it lies" % side)
		return
	print("[SuperScope] restoring the sight on the %s" % ("right" if i == 1 else "left"))
	_clips[i].pick_up_object(sight)


func _build_clips() -> void:
	for side: float in [-1.0, 1.0]:
		var zone := CoverSlots.make_zone("SightClipL" if side < 0.0 else "SightClipR", SuperScopeSight.GROUP, 0.05, self)
		zone.position = Vector3(side * CLIP_X, CLIP_Y, CLIP_Z)
		zone.has_picked_up.connect(_on_sight_in)
		zone.has_dropped.connect(_on_sight_out)
		_clips.append(zone)


## A fresh scope comes with its sight on the left clip, where a right-handed
## player's eye is. A restored one is told by its save (restore_sight).
func _seed_sight() -> void:
	if _seeded or not is_inside_tree() or _clips.is_empty() or _clips[0].has_snapped_object():
		return
	_seeded = true
	if not is_in_group("spawned"):
		return
	var sight := preload("res://Scenes/Objects/peripherals/super_scope_sight.tscn").instantiate() as SuperScopeSight
	get_tree().current_scene.add_child(sight)
	sight.global_transform = _clips[0].global_transform
	_clips[0].pick_up_object(sight)
	print("[SuperScope] came with its sight, on the left")


func _on_sight_in(what: Node3D) -> void:
	_sight = what as SuperScopeSight
	if _sight == null:
		return
	add_collision_exception_with(_sight)
	SeatedCollision.lend(self, _sight, _sight.get_picked_up_by())
	print("[SuperScope] sight on the %s" % sight_side())


func _on_sight_out() -> void:
	if is_instance_valid(_sight):
		remove_collision_exception_with(_sight)
		SeatedCollision.withdraw(self, _sight)
		print("[SuperScope] sight off")
	_sight = null


# ── Controls ──────────────────────────────────────────────────────────────────

## Fire, Pause and Cursor are caps a hand's buttons press and a fingertip can
## press too (ControlPoke, through _anim_btns). No trigger blade: Fire is the cap.
func _cache_controls() -> void:
	for spec: Array in [["FireButton", ControllerBindings.LIGHTGUN_TRIGGER],
			["PauseButton", ControllerBindings.LIGHTGUN_START],
			["CursorButton", ControllerBindings.LIGHTGUN_AUX_A]]:
		var m := get_node_or_null(String(spec[0])) as MeshInstance3D
		if m == null:
			push_warning("[SuperScope] no %s to animate" % spec[0])
			continue
		var dir: Vector3 = Vector3.DOWN
		if m.has_meta(&"press_dir"):
			dir = m.get_meta(&"press_dir")
		_anim_btns.append({"node": m, "rest": m.transform, "lid": spec[1], "dir": dir})
	_trigger_pivot = null


# ── Body ──────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	var shell := _mat(SHELL, 0.55)
	var dark := _mat(SHELL_DARK, 0.6)
	var strip := _mat(STRIP, 0.5)
	var rest := _mat(REST, 0.7)
	var black := _mat(BLACK, 0.3)
	var lay := Basis(Vector3.RIGHT, PI * 0.5)
	# The barrel, its orange lens ring at the muzzle, and the hump over it that
	# holds the infrared window.
	var barrel_len := BARREL_END_Z - MUZZLE_Z
	_cyl("Barrel", BARREL_RADIUS, barrel_len, Transform3D(lay, Vector3(0, BARREL_Y, MUZZLE_Z + barrel_len * 0.5)), dark)
	_cyl("LensRing", BARREL_RADIUS * 0.92, 0.012, Transform3D(lay, Vector3(0, BARREL_Y, MUZZLE_Z - 0.004)), _mat(LENS, 0.4))
	_cyl("Lens", BARREL_RADIUS * 0.7, 0.002, Transform3D(lay, Vector3(0, BARREL_Y, MUZZLE_Z - 0.0105)), black)
	_box("Hump", Vector3(0.036, 0.022, 0.075), Vector3(0, BARREL_Y + BARREL_RADIUS - 0.002, MUZZLE_Z + 0.0375 + 0.001), shell)
	_box("IrWindow", Vector3(0.016, 0.010, 0.002), Vector3(0, BARREL_Y + BARREL_RADIUS + 0.008, MUZZLE_Z), black)
	# The rear body over the barrel's end to the stock's tip, its top a light shell.
	var body_len := REAR_Z - (BARREL_END_Z - 0.06)
	var body_mid := (REAR_Z + BARREL_END_Z - 0.06) * 0.5
	_box("RearBody", Vector3(BODY_W, BODY_TOP - BODY_BOTTOM, body_len),
		Vector3(0, (BODY_TOP + BODY_BOTTOM) * 0.5, body_mid), shell)
	# The dark strip along the top the controls stand in.
	_box("TopStrip", Vector3(0.024, 0.0016, 0.115), Vector3(0, BODY_TOP + 0.0008, 0.245), strip)
	# The stock's lower block, the cells' bay cut into its underside, and the
	# shoulder rest behind it.
	var stock := _box("StockBlock", Vector3(BODY_W - 0.002, BODY_BOTTOM - STOCK_BOTTOM + 0.004, STOCK_Z.y - STOCK_Z.x),
		Vector3(0, (BODY_BOTTOM + STOCK_BOTTOM) * 0.5 - 0.002, (STOCK_Z.x + STOCK_Z.y) * 0.5), shell)
	var rest_mesh := _box("ShoulderRest", Vector3(0.05, 0.012, 0.16), Vector3.ZERO, rest)
	rest_mesh.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12.0)), Vector3(0, 0.032, 0.455))
	# The grip, leaning forward at the top, with the CURSOR button on its back
	# face near the top, pressed toward the muzzle.
	var grip_basis := Basis(Vector3.RIGHT, deg_to_rad(GRIP_LEAN_DEG))
	var grip := _box("Grip", GRIP_SIZE, Vector3.ZERO, shell)
	grip.transform = Transform3D(grip_basis, Vector3.ZERO)
	var ribs := _box("GripRibs", Vector3(GRIP_SIZE.x + 0.001, GRIP_SIZE.y * 0.6, 0.012), Vector3.ZERO, rest)
	ribs.transform = Transform3D(grip_basis, grip_basis * Vector3(0, -0.01, -GRIP_SIZE.z * 0.5 + 0.0055))
	var cursor := _cyl("CursorButton", 0.0045, 0.004, Transform3D(grip_basis * lay,
		grip_basis * Vector3(0, GRIP_SIZE.y * 0.32, GRIP_SIZE.z * 0.5 + 0.0015)), black)
	cursor.set_meta(&"press_dir", (grip_basis * Vector3.FORWARD).normalized())
	# FIRE and PAUSE, round caps on the strip, and the switch behind them.
	_cyl("FireButton", 0.0075, 0.006, Transform3D(Basis.IDENTITY, Vector3(0, BODY_TOP + 0.0036, FIRE_Z)), _mat(FIRE_COLOR, 0.35))
	_cyl("PauseButton", 0.0055, 0.005, Transform3D(Basis.IDENTITY, Vector3(0, BODY_TOP + 0.0031, PAUSE_Z)), _mat(CAP_GREY, 0.45))
	_build_switch()
	# The sight clips' tabs, on both sides.
	for side: float in [-1.0, 1.0]:
		for dz: float in [-0.063, 0.063]:
			_box("ClipTab", Vector3(0.004, 0.010, 0.016), Vector3(side * (BARREL_RADIUS + 0.001), CLIP_Y, CLIP_Z + dz), shell)
	# Six AA cells across the stock, behind a door in its underside (BatteryBay:
	# the pocket, contacts, seats and cover, saved and synced as every cover is).
	var bay_box := stock.transform * stock.get_aabb()
	var seats := BatteryBay.build(self, bay_box, {"size": "AA", "count": 6, "along": "x", "at": [0.0, 0.0]},
		"super_scope_battery_cover", SHELL, stock)
	print("[SuperScope] battery bay built: %d AA seats" % seats)
	_supply = PowerInput.on(self)
	_supply.label = "Super Scope (%s)" % name
	_supply.power_changed.connect(_on_supply_changed)
	_fit_shapes()


func _build_switch() -> void:
	var knob := MeshInstance3D.new()
	knob.name = "PowerSwitchKnob"
	var cap := BoxMesh.new()
	cap.size = Vector3(0.007, 0.005, 0.006)
	knob.mesh = cap
	knob.material_override = _mat(CAP_GREY, 0.5)
	add_child(knob)
	var at := Vector3(0, BODY_TOP + 0.0034, SWITCH_Z)
	# At value 0 (OFF), the -axis end, which is the REAR (+Z): the slider anchors on
	# the knob where it is.
	knob.position = at + Vector3(0, 0, SWITCH_TRAVEL * 0.5)
	var slider := VRSlider.new()
	slider.name = "PowerSwitch"
	# OFF at the rear, ON in the centre, TURBO at the front, toward the muzzle (US
	# 5,310,192: first position off, second on, third continuous fire; the manual:
	# "slide this switch forward to the center position to turn the power on").
	slider.axis_local = Vector3(0, 0, -1)
	slider.travel = SWITCH_TRAVEL
	slider.steps = 3
	slider.value = 0.0
	slider.collision_layer = 1 | (1 << 20)
	slider.engage_radius = 0.016
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.014, 0.010, SWITCH_TRAVEL + 0.010)
	col.shape = box
	slider.add_child(col)
	add_child(slider)
	slider.position = at
	slider.set_knob_mesh(knob)
	slider.value_changed.connect(func(v: float) -> void: set_power_switch(roundi(v * 2.0)))
	_switch = slider


## The pick-up box and the ray's box: the whole gun, as boxes. A shape for the
## body and one for the grip, so a hand on the grip takes it.
func _fit_shapes() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var length := REAR_Z - MUZZLE_Z
	var mid := Vector3(0, (BODY_TOP + STOCK_BOTTOM) * 0.5 + 0.01, (REAR_Z + MUZZLE_Z) * 0.5)
	if col != null:
		var box := BoxShape3D.new()
		box.size = Vector3(BODY_W, BODY_TOP + 0.02 - STOCK_BOTTOM, length)
		col.shape = box
		col.position = mid
	var grip_col := CollisionShape3D.new()
	grip_col.name = "GripShape"
	var grip_box := BoxShape3D.new()
	grip_box.size = GRIP_SIZE
	grip_col.shape = grip_box
	add_child(grip_col)
	grip_col.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(GRIP_LEAN_DEG)), Vector3.ZERO)
	var pointer := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if pointer != null:
		var pbox := BoxShape3D.new()
		pbox.size = Vector3(BODY_W + 0.02, BODY_TOP + GRIP_SIZE.y * 0.5 + 0.03, length + 0.02)
		pointer.shape = pbox
		pointer.position = Vector3(0, (BODY_TOP - GRIP_SIZE.y * 0.5) * 0.5, mid.z)


func _on_supply_changed(live: bool) -> void:
	print("[SuperScope] cells %s" % ("in: live" if live else "out or flat: %s" % _supply.why_not()))
	_look_tick = LOOK_TICKS


func _cyl(node_name: String, radius: float, height: float, xform: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 24
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat
	add_child(mi)
	mi.transform = xform
	return mi


func _box(node_name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	mi.position = at
	return mi


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
