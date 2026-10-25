## ArcadeInput — what reaches the core from a cabinet.
##
## Per player (port 0 = P1, 1 = P2): the panel's pokeable buttons, the coin the coin
## door dropped, and, in direct mode, the player's OWN controller. Direct input is the
## primary way to play: a stick you cannot feel under your hand is no fun in VR, so
## the VR controllers (or the machine's selected physical pad, or the captured
## keyboard) drive the player whose panel you are attached to, through the same bindings
## and merge a handheld uses (an adapted copy of HandheldInput's forwarding; that one
## assumes the machine is in the hand). Attaching is a press on the panel (ArcadePanelGrip);
## WASD and the thumbsticks are held back from moving the player while you are attached.
##
## Everything goes out through NetworkManager.netplay_route, then SetJoypadState, the
## one seam: bypassing it would break lockstep.
##
## A controller seated in a front socket owns that port: the panel of that player
## goes quiet (ArcadeInputState.panel_speaks) so two writers never fight over one
## port's state.
class_name ArcadeInput
extends Node

const ANALOG_SCALE := 0x7fff
const DPAD_THRESHOLD := 0.35
const ICON_CAPTURE := 0xEC17
const ICON_SIZE := 0.03

const INPUT_THRESHOLDS: Dictionary = {
	"ax_button":     0.5,
	"by_button":     0.5,
	"primary_click": 0.5,
	"grip":          0.3,
	"trigger":       0.3,
}

const DESKTOP_BUTTON_MAP: Dictionary = {
	"RETRO_JOYPAD_B":      ControllerBindings.JOYPAD_B,
	"RETRO_JOYPAD_Y":      ControllerBindings.JOYPAD_Y,
	"RETRO_JOYPAD_SELECT": ControllerBindings.JOYPAD_SELECT,
	"RETRO_JOYPAD_START":  ControllerBindings.JOYPAD_START,
	"RETRO_JOYPAD_UP":     ControllerBindings.JOYPAD_UP,
	"RETRO_JOYPAD_DOWN":   ControllerBindings.JOYPAD_DOWN,
	"RETRO_JOYPAD_LEFT":   ControllerBindings.JOYPAD_LEFT,
	"RETRO_JOYPAD_RIGHT":  ControllerBindings.JOYPAD_RIGHT,
	"RETRO_JOYPAD_A":      ControllerBindings.JOYPAD_A,
	"RETRO_JOYPAD_X":      ControllerBindings.JOYPAD_X,
	"RETRO_JOYPAD_L":      ControllerBindings.JOYPAD_L,
	"RETRO_JOYPAD_R":      ControllerBindings.JOYPAD_R,
	"RETRO_JOYPAD_L2":     ControllerBindings.JOYPAD_L2,
	"RETRO_JOYPAD_R2":     ControllerBindings.JOYPAD_R2,
	"RETRO_JOYPAD_L3":     ControllerBindings.JOYPAD_L3,
	"RETRO_JOYPAD_R3":     ControllerBindings.JOYPAD_R3,
}

## Which players' panels the user is attached to (player -> true). One at a time: a controller
## plays one player, so attaching to a panel lets go of the other.
var attached: Dictionary = {}

## True while the user is attached to a panel: their own controller drives that player.
var playing: bool:
	get:
		return not attached.is_empty()

signal playing_changed(on: bool)

## Somebody used the cabinet while it was only showing its game (RetroSystem.attracting): a coin, a panel
## pressed, a gun or a pad taken in hand. `kind` is &"coin", &"panel" or &"grab". RetroSystem starts the
## real core on it.
signal first_use(kind: StringName)

var _host: Node3D = null
var _model: RetroSystemModel = null
var _controls: Array[ArcadeControlModule] = []
var _pulses: Dictionary = {}
var _doors: Array[ArcadeCoinModule] = []
## How many ports the coin doors reach (a door's player + 1, the highest): a game with more coin slots than
## panels (Robotron's three) still has each door's coin sent.
var _door_ports := 0
## Coins the cabinet has taken that the GAME has not had yet: put in while it only showed its game, or
## while the core was still coming up (a credit dropped into a board running its power-on tests is lost).
## They go in once the game can count them (game_ready), or at once when somebody presses START on a game
## that has started; the coin return gives them back; switching off rolls them out into the cups.
var _escrow := ArcadeInputState.CoinEscrow.new()
## The core's frame count when this run was first seen, -1 while nothing runs (frames_run).
var _run_base := -1
## Seconds since this run was first seen: what stands in for the frame count on a bridge without one.
var _run_seconds := 0.0
## A suite stands in for a running core's frame counter with this; -1 asks the core.
var frame_override := -1
## START pressed while coins were held lets them in now (ArcadeInputState.start_lets_coins_in).
var _letting_in := false
## START is held back until the held coins are in and this has run out, so the game sees the credit first.
var _start_hold := 0.0
## Ports whose START was pressed while it was held back: each gets one START once it is let through.
var _queued_start: Dictionary = {}
## Ports being sent that one START now (port -> seconds left).
var _start_pulse: Dictionary = {}

var _button_map: Dictionary = ControllerBindings.DEFAULT_BUTTON_MAP.duplicate()
var _stick_map: Dictionary = ControllerBindings.DEFAULT_STICK_MAP.duplicate()
var _pad_button_map: Dictionary = GamepadBindings.DEFAULT_BUTTON_MAP.duplicate()
var _pad_stick_map: Dictionary = GamepadBindings.DEFAULT_STICK_MAP.duplicate()
var _latch := InputLatch.new()
var _capture: ScrollLockCapture = null
var _locomotion_manager: LocomotionManager = null
## Whether WE put this machine's key map into the global InputMap (see _sync_desktop_scope).
var _owns_desktop_scope := false
var _left_vr_ctrl: XRController3D = null
var _right_vr_ctrl: XRController3D = null

## What was last sent per port, for the probe and the tests.
var last_sent: Dictionary = {}
## What the CORE last heard per port (port -> mask, and axes as a Vector4i): an input the core already
## holds is not pushed again. Cleared when the machine goes off, so a restart is told afresh.
var _heard_mask: Dictionary = {}
var _heard_axes: Dictionary = {}
## A port nobody is playing: shared, read only.
const _NEUTRAL := {"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": 0}


## `host` is the RetroSystem, `model` the cabinet's model, `controls` one module per
## player in port order, and `coins` the coin doors (each routed to its player).
func setup(host: Node3D, model: RetroSystemModel, controls: Array, coins: Array) -> void:
	_host = host
	_model = model
	_wire(controls, coins)
	_load_bindings()
	_capture = ScrollLockCapture.attach(host, _can_capture, ICON_CAPTURE, ICON_SIZE)
	add_to_group(ControllerBindings.CONSUMER_GROUP)
	_find_vr_nodes.call_deferred()


## The cabinet built a new form (RetroSystemModelArcadeCabinet.morph_to): its panels and coin doors are new
## nodes. Whoever was attached lets go (that panel is gone); coins held for a player stay held.
func rewire(controls: Array, coins: Array) -> void:
	var was := playing
	attached.clear()
	if was:
		_update_locomotion_block()
		playing_changed.emit(false)
	_wire(controls, coins)
	_show_held()


func _wire(controls: Array, coins: Array) -> void:
	_controls.clear()
	for c in controls:
		var panel := c as ArcadeControlModule
		_controls.append(panel)
		if panel != null and not panel.attach_changed.is_connected(_on_attach_changed):
			panel.attach_changed.connect(_on_attach_changed)
	_doors.clear()
	_door_ports = 0
	for coin in coins:
		var door := coin as ArcadeCoinModule
		if door == null:
			continue
		_doors.append(door)
		_door_ports = maxi(_door_ports, door.player + 1)
		var pulse: ArcadeInputState.CoinPulse = _pulses.get(door.player)
		if pulse == null:
			pulse = ArcadeInputState.CoinPulse.new()
			_pulses[door.player] = pulse
		if not door.return_pressed.is_connected(_on_return_pressed):
			door.coin_inserted.connect(_on_coin.bind(pulse))
			door.return_pressed.connect(_on_return_pressed)


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	if _owns_desktop_scope:
		_owns_desktop_scope = false
		DesktopBindings.apply_for_system("")
	if _locomotion_manager != null:
		_locomotion_manager.clear_owner(VrHold.vr_block_owner(self))
	if _capture != null:
		_capture.release()


## Reload bindings from disk (called after the user saves new bindings).
func reload_bindings() -> void:
	_load_bindings()


func _load_bindings() -> void:
	var systemid := str(_host.get("systemid")) if _host != null else ""
	var bindings := ControllerBindings.get_for_system(systemid)
	_button_map = bindings["buttons"]
	_stick_map = bindings["sticks"]
	var pad := GamepadBindings.get_for_system(systemid)
	_pad_button_map = pad["buttons"]
	_pad_stick_map = pad["sticks"]


func _find_vr_nodes() -> void:
	var rig := PadInputShared.find_rig(get_tree())
	_locomotion_manager = rig["locomotion"]
	_left_vr_ctrl = rig["left"]
	_right_vr_ctrl = rig["right"]
	_update_locomotion_block()


func _on_coin(player: int, pulse: ArcadeInputState.CoinPulse) -> void:
	if _host == null:
		return
	if bool(_host.get("attracting")):
		# The coin starts the game and then counts in it: held until the game is up to count it.
		_escrow.hold(player)
		_show_held()
		first_use.emit(&"coin")
		return
	if bool(_host.get("is_powered_on")):
		if _host.has_method("attract_touch"):
			_host.call("attract_touch")
		# Into a game still coming up, or behind coins still waiting: held. Otherwise straight in.
		if not _escrow.is_empty() or not game_ready():
			_escrow.hold(player)
			_show_held()
		else:
			pulse.insert()
		return
	# A cabinet that is off cannot take a coin: it goes through the mech and out into the cup.
	var door := _door_of(player)
	if door != null:
		door.return_coin()


## The coin return on `player`'s door: one coin the game has not had comes back out, if there is one.
func _on_return_pressed(player: int) -> void:
	if _escrow.take_back(player):
		var door := _door_of(player)
		if door != null:
			door.return_coin()
		_show_held()


## Every coin still held rolls out into its door's cup (the cabinet went off with them in it).
func _return_held() -> void:
	if _escrow.is_empty():
		return
	var all := _escrow.take_all()
	for player: int in all:
		var door := _door_of(player)
		for i in int(all[player]):
			if door != null:
				door.return_coin()
	_show_held()


## Each door shows whether coins are held for its player (its lamp blinks).
func _show_held() -> void:
	for door in _doors:
		if is_instance_valid(door):
			door.set_held(_escrow.held(door.player))


func _door_of(player: int) -> ArcadeCoinModule:
	for door in _doors:
		if is_instance_valid(door) and door.player == player:
			return door
	return null


## Coins the cabinet holds for `player` that the game has not had yet (for the tests and the probe).
func held_coins(player: int = -1) -> int:
	return _escrow.total() if player < 0 else _escrow.held(player)


# ── how far the game has come ────────────────────────────────────────────────

## How many frames the core has emulated since this run began: the GAME's time, so a slow load, or a Quest
## running the game below full speed, waits as long as the game itself takes. 0 while nothing runs.
func frames_run() -> int:
	if _run_base < 0:
		return 0
	var now := _frame_count()
	if now < _run_base:
		# The bridge started its count again (an abandoned run's wrapper is a new one): count from there.
		_run_base = 0
	return now - _run_base


## Is the game up to count a coin? Its own boot time (ArcadeGameProfile.boot_seconds) in its own frames.
func game_ready() -> bool:
	return ArcadeInputState.game_ready(frames_run(), boot_frames())


## How many frames this game takes to come up: the table's seconds for its driver at the core's own rate.
func boot_frames() -> int:
	var seconds := ArcadeProfiles.BOOT_SECONDS
	var profile: ArcadeGameProfile = _model.call("game_profile") if _model != null and _model.has_method("game_profile") else null
	if profile != null and profile.known:
		seconds = profile.boot_seconds()
	var fps := 60.0
	var lib := _libretro()
	if lib != null and lib.has_method("GetDeclaredFps"):
		var declared := float(lib.call("GetDeclaredFps"))
		if declared > 1.0:
			fps = declared
	return int(ceil(seconds * fps))


func _frame_count() -> int:
	if frame_override >= 0:
		return frame_override
	var lib := _libretro()
	if lib != null and lib.has_method("GetFrameCount"):
		return int(lib.call("GetFrameCount"))
	# A bridge with no counter (a platform not rebuilt): the room's time stands in.
	return int(_run_seconds * 60.0)


func _libretro() -> Object:
	if _host != null and _host.has_method("get_libretro_node"):
		return _host.call("get_libretro_node") as Object
	return null


## Is anyone at the cabinet? A panel attached, or a gun or pad in a HAND (a gun lying in its holster is
## in the port and is nobody's). The idle clock that puts the core away reads this.
func engaged() -> bool:
	if playing:
		return true
	if _host == null or not _host.has_method("get_port_controllers"):
		return false
	for holder: Variant in _host.get_port_controllers():
		if holder != null and is_instance_valid(holder) and held_by_hand(holder):
			return true
	return false


## True when `holder` (a pad or gun) is carried by a hand rather than sitting in a socket or a holster.
static func held_by_hand(holder: Object) -> bool:
	if not holder.has_method("is_picked_up") or not holder.call("is_picked_up"):
		return false
	if "captive_well" in holder:
		var well: Variant = holder.get("captive_well")
		if well != null and is_instance_valid(well) and (well as Object).get("picked_up_object") == holder:
			return false
	return true


## While the cabinet only shows its game: has anything been taken in hand or attached?
func _watch_for_use() -> void:
	if playing:
		first_use.emit(&"panel")
	elif engaged():
		first_use.emit(&"grab")


func _can_capture() -> bool:
	return playing and _host != null and bool(_host.get("is_powered_on"))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.is_echo() or _capture == null:
		return
	if _capture.handle_key(key):
		get_viewport().set_input_as_handled()


func _update_locomotion_block() -> void:
	if _locomotion_manager != null:
		var owner_key := VrHold.vr_block_owner(self)
		_locomotion_manager.set_block(owner_key, LocomotionManager.CHANNEL_LEFT, playing)
		_locomotion_manager.set_block(owner_key, LocomotionManager.CHANNEL_RIGHT, playing)
	if _capture != null:
		_capture.refresh()


func _process(delta: float) -> void:
	if _host == null:
		return
	_sync_desktop_scope()
	if bool(_host.get("attracting")):
		_watch_for_use()
		return
	var powered := bool(_host.get("is_powered_on"))
	if not powered:
		if playing:
			for panel in _controls:
				if panel != null:
					panel.set_attached(false)
		_end_run()
		if not _heard_mask.is_empty():
			_heard_mask.clear()
			_heard_axes.clear()
		return
	if _run_base < 0:
		_run_base = _frame_count()
		_run_seconds = 0.0
	_run_seconds += delta
	var controllers: Array = _host.get_port_controllers() if _host.has_method("get_port_controllers") else []
	var players := maxi(maxi(_controls.size(), 2), _door_ports)
	# What every player is pressing first, then the coins and START: a held coin goes in before a START.
	var masks: Array[int] = []
	var hands: Array[int] = []
	var states: Array[Dictionary] = []
	var start_pressed := false
	for p in players:
		var holder: Variant = controllers[p] if p < controllers.size() else null
		var state := {"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": 0}
		if attached.has(p):
			state = _direct_state()
		var mask := ArcadeInputState.compose(0, int(state["btn"]), false, _unsupported())
		# A momentary panel (a gun cabinet's START) is read while it is pressed.
		if p < _controls.size() and _controls[p] != null and _controls[p].start_held():
			mask |= 1 << ArcadeProfiles.START_BIT
		# The gun in a hand has START and SELECT of its own (stick click and grip). MAME 0.289 reads a start
		# and a credit off the joypad only, so they are sent as the joypad's too (below).
		var hand := 0
		if holder is LightGun:
			var held_gun := holder as LightGun
			if held_gun.hand_button(ControllerBindings.LIGHTGUN_START):
				hand |= 1 << ArcadeProfiles.START_BIT
			if held_gun.hand_button(ControllerBindings.LIGHTGUN_SELECT):
				hand |= 1 << ArcadeProfiles.COIN_BIT
		start_pressed = start_pressed or ((mask | hand) & (1 << ArcadeProfiles.START_BIT)) != 0
		masks.append(mask)
		hands.append(hand)
		states.append(state)
	var hold_start := _step_held_coins(delta, start_pressed)
	for p in players:
		var holder: Variant = controllers[p] if p < controllers.size() else null
		var owned := holder != null
		var mask := masks[p]
		var hand := hands[p]
		if _pulses.has(p) and (_pulses[p] as ArcadeInputState.CoinPulse).advance(delta):
			mask |= 1 << ArcadeProfiles.COIN_BIT
		if hold_start:
			# START waits for the credit; a press now is remembered and sent once, after it.
			if ((mask | hand) & (1 << ArcadeProfiles.START_BIT)) != 0:
				_queued_start[p] = true
			mask &= ~(1 << ArcadeProfiles.START_BIT)
			hand &= ~(1 << ArcadeProfiles.START_BIT)
		elif _start_pulse.has(p):
			mask |= 1 << ArcadeProfiles.START_BIT
			_start_pulse[p] = float(_start_pulse[p]) - delta
			if float(_start_pulse[p]) <= 0.0:
				_start_pulse.erase(p)
		if p < _controls.size() and _controls[p] != null:
			var st: Dictionary = states[p]
			_controls[p].show_state(mask, Vector4i(int(st["alx"]), int(st["aly"]), int(st["arx"]), int(st["ary"])))
		if owned:
			# A gun in the port is not a joypad: it aims and fires itself. The cabinet's START and
			# coin reach the core TWICE: as the gun's own START and SELECT, and as the joypad's
			# START and SELECT on that port, which is where MAME and FinalBurn read a credit and
			# a start even in a light-gun game (the extension answers a core's joypad query
			# whatever device the port announced). Only those two bits: the gun writes no pad.
			if holder is LightGun:
				var held_gun := holder as LightGun
				_forward_to_gun(held_gun, mask)
				var aux := (1 << ArcadeProfiles.START_BIT) | (1 << ArcadeProfiles.COIN_BIT)
				_send(p, (mask | hand) & aux, _NEUTRAL)
			continue
		_send(p, mask, states[p])


## The held coins, once a frame while the core runs: one goes in when the game is up to count it, or at
## once when somebody presses START on a game that has started (`start_pressed`). Returns whether START is
## to be held back now: while coins are held or going in, and START_AFTER_COIN_SECONDS after, so the game
## sees the credit before the start. A START pressed meanwhile is queued, and sent once when it is let go.
func _step_held_coins(delta: float, start_pressed: bool) -> bool:
	if ArcadeInputState.start_lets_coins_in(frames_run(), ArcadeProfiles.MIN_BOOT_FRAMES, start_pressed, _escrow.total()):
		_letting_in = true
	var who := _escrow.next(delta, _letting_in or game_ready())
	if who >= 0:
		if _pulses.has(who):
			(_pulses[who] as ArcadeInputState.CoinPulse).insert()
		_show_held()
	var coin_going := false
	for pulse: ArcadeInputState.CoinPulse in _pulses.values():
		coin_going = coin_going or pulse.active()
	if not _escrow.is_empty() or coin_going:
		_start_hold = ArcadeProfiles.START_AFTER_COIN_SECONDS
		return true
	_letting_in = false
	if _start_hold > 0.0:
		_start_hold = maxf(0.0, _start_hold - delta)
		if _start_hold > 0.0:
			return true
		for port: int in _queued_start:
			_start_pulse[port] = ArcadeProfiles.COIN_PULSE_SECONDS
		_queued_start.clear()
	return false


## The core stopped (or never started): the run is over, and every coin still held rolls out into its cup.
func _end_run() -> void:
	_run_base = -1
	_run_seconds = 0.0
	_return_held()
	_letting_in = false
	_start_hold = 0.0
	_queued_start.clear()
	_start_pulse.clear()


## A panel was attached to or let go of (a press on it, or the machine going off).
func _on_attach_changed(player: int, on: bool) -> void:
	var was := playing
	if on:
		# One controller, one panel: attaching here lets go of the other.
		for other in _controls:
			if other != null and other.player != player and other.is_attached():
				other.set_attached(false)
		attached[player] = true
	else:
		attached.erase(player)
	if was != playing:
		_update_locomotion_block()
		playing_changed.emit(playing)
	if on and _host != null and bool(_host.get("attracting")):
		first_use.emit(&"panel")
	# Attaching IS the claim on the keyboard (a pad you pick up needs Scroll Lock as well,
	# but a panel you pressed has no other way to say it): the keys play this player at once.
	if on and _capture != null:
		_capture.set_active(true)


## Point the InputMap at this machine's key map while the keyboard is captured, and put the
## global map back when it lets go (the same rule as RetroController: the map is global to
## the process, so only the holder of the capture may drive it). Without this the
## RETRO_JOYPAD_* actions carry the global keys, and an arcade profile's keys never arrive.
func _sync_desktop_scope() -> void:
	var active := _capture != null and _capture.is_active()
	if active:
		if not _owns_desktop_scope:
			_owns_desktop_scope = true
			DesktopBindings.apply_for_system(str(_host.get("systemid")))
	elif _owns_desktop_scope:
		_owns_desktop_scope = false
		DesktopBindings.apply_for_system("")


## START and the coin, as the buttons a light gun has for them. The gun ORs them with its own.
func _forward_to_gun(gun: LightGun, mask: int) -> void:
	gun.set_external_button(ControllerBindings.LIGHTGUN_START, (mask >> ArcadeProfiles.START_BIT) & 1 == 1)
	gun.set_external_button(ControllerBindings.LIGHTGUN_SELECT, (mask >> ArcadeProfiles.COIN_BIT) & 1 == 1)


func _unsupported() -> int:
	return _model.get_unsupported_button_mask() if _model != null else 0


func _send(port: int, mask: int, state: Dictionary) -> void:
	last_sent[port] = mask
	if NetworkManager.netplay_route(_host, port, {"btn": mask, "alx": state["alx"],
			"aly": state["aly"], "arx": state["arx"], "ary": state["ary"]}):
		return
	var axes := Vector4i(int(state["alx"]), int(state["aly"]), int(state["arx"]), int(state["ary"]))
	if _heard_mask.get(port, -1) == mask and _heard_axes.get(port, Vector4i.ZERO) == axes:
		return
	_heard_mask[port] = mask
	_heard_axes[port] = axes
	_host.get_libretro_node().SetJoypadState(port, mask, axes.x, axes.y, axes.z, axes.w)


# ── Direct input: the player's own controller ────────────────────────────────

## The joypad state of whatever the player is holding: both VR controllers through
## the per-system bindings, then the selected physical pad merged in, then the
## captured keyboard. Same sources and the same rules as a held handheld.
func _direct_state() -> Dictionary:
	var btn := 0
	var alx := 0
	var aly := 0
	var arx := 0
	var ary := 0
	var vr_active := false
	for ctrl in [_left_vr_ctrl, _right_vr_ctrl]:
		if not is_instance_valid(ctrl) or not (ctrl as XRController3D).get_is_active():
			continue
		vr_active = true
		var left_hand: bool = (ctrl as XRController3D).tracker == &"left_hand"
		btn |= _apply_buttons_for_ctrl(ctrl, left_hand)
	if vr_active:
		var lstick := _stick_of(_left_vr_ctrl)
		var rstick := _stick_of(_right_vr_ctrl)
		var lt: String = _stick_map.get("stick_left", "left+dpad")
		var rt: String = _stick_map.get("stick_right", "right")
		if "left" in lt:
			alx = int(lstick.x * ANALOG_SCALE)
			aly = int(-lstick.y * ANALOG_SCALE)
		elif "right" in lt:
			arx = int(lstick.x * ANALOG_SCALE)
			ary = int(-lstick.y * ANALOG_SCALE)
		if "dpad" in lt:
			btn |= PadInputShared.threshold_to_dpad(lstick)
		if "right" in rt:
			arx = int(rstick.x * ANALOG_SCALE)
			ary = int(-rstick.y * ANALOG_SCALE)
		elif "left" in rt:
			alx = int(rstick.x * ANALOG_SCALE)
			aly = int(-rstick.y * ANALOG_SCALE)
		if "dpad" in rt:
			btn |= PadInputShared.threshold_to_dpad(rstick)
	if _capture != null and _capture.is_active():
		for action: String in DESKTOP_BUTTON_MAP:
			if Input.is_action_pressed(action):
				btn |= 1 << int(DESKTOP_BUTTON_MAP[action])
		var lx := Input.get_axis("RETRO_ANALOG_LEFT_X_NEGATIVE", "RETRO_ANALOG_LEFT_X_POSITIVE")
		var ly := Input.get_axis("RETRO_ANALOG_LEFT_Y_NEGATIVE", "RETRO_ANALOG_LEFT_Y_POSITIVE")
		var rx := Input.get_axis("RETRO_ANALOG_RIGHT_X_NEGATIVE", "RETRO_ANALOG_RIGHT_X_POSITIVE")
		var ry := Input.get_axis("RETRO_ANALOG_RIGHT_Y_NEGATIVE", "RETRO_ANALOG_RIGHT_Y_POSITIVE")
		alx = int(lx * ANALOG_SCALE)
		aly = int(-ly * ANALOG_SCALE)
		arx = int(rx * ANALOG_SCALE)
		ary = int(-ry * ANALOG_SCALE)
	return _merge_pad_state(btn, alx, aly, arx, ary)


func _stick_of(ctrl: XRController3D) -> Vector2:
	return ctrl.get_vector2("primary") if is_instance_valid(ctrl) and ctrl.get_is_active() else Vector2.ZERO


func _apply_buttons_for_ctrl(ctrl: XRController3D, left_hand: bool) -> int:
	var bits := 0
	for full_source: String in _button_map:
		var bit: int = _button_map[full_source]
		if bit < 0:
			continue
		var vr_input: String
		if full_source.begins_with("right_"):
			if left_hand:
				continue
			vr_input = full_source.substr(6)
		elif full_source.begins_with("left_"):
			if not left_hand:
				continue
			vr_input = full_source.substr(5)
		else:
			vr_input = full_source
		var threshold: float = INPUT_THRESHOLDS.get(vr_input, 0.5)
		var key := "%d:%s" % [ctrl.get_instance_id(), vr_input]
		if _latch.pressed(key, ctrl.get_float(vr_input), threshold):
			bits |= 1 << bit
	return bits


## Merge the SELECTED physical pad into the current state. Buttons OR together; each
## analog stick takes whichever source has the larger magnitude.
func _merge_pad_state(btn: int, alx: int, aly: int, arx: int, ary: int) -> Dictionary:
	var device := GamepadBindings.resolve_device(_host.pad_guid, _host.pad_ordinal)
	var pad := GamepadBindings.poll(_pad_button_map, _pad_stick_map, device)
	btn |= int(pad["btn"])
	var plx: int = pad["alx"]
	var ply: int = pad["aly"]
	var prx: int = pad["arx"]
	var pry: int = pad["ary"]
	if plx * plx + ply * ply > alx * alx + aly * aly:
		alx = plx
		aly = ply
	if prx * prx + pry * pry > arx * arx + ary * ary:
		arx = prx
		ary = pry
	return {"btn": btn, "alx": alx, "aly": aly, "arx": arx, "ary": ary}
