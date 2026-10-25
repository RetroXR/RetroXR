## ArcadeInputState — the pure half of the cabinet's input.
##
## Which joypad bits a panel's buttons are, how a coin becomes a pulse, who owns a
## port. No nodes, no core: ArcadeInput (the node) feeds these and sends the result,
## and arcade_tests pins them without a scene.
class_name ArcadeInputState
extends RefCounted


## The joypad mask of a panel's six buttons, `held` indexed from button 1 (any
## shorter array is padded with "up"), plus START.
static func panel_mask(held: Array, start: bool) -> int:
	var mask := 0
	for i in mini(held.size(), ArcadeProfiles.BUTTON_COUNT):
		if held[i]:
			mask |= 1 << ArcadeProfiles.BUTTON_BITS[i]
	if start:
		mask |= 1 << ArcadeProfiles.START_BIT
	return mask


## A stick's direction as the four D-pad bits. `dir` is in screen terms, x right
## and y DOWN positive, past `threshold` on an axis counting as pressed.
static func direction_mask(dir: Vector2, threshold: float = 0.35) -> int:
	var mask := 0
	if dir.x <= -threshold:
		mask |= 1 << ControllerBindings.JOYPAD_LEFT
	elif dir.x >= threshold:
		mask |= 1 << ControllerBindings.JOYPAD_RIGHT
	if dir.y <= -threshold:
		mask |= 1 << ControllerBindings.JOYPAD_UP
	elif dir.y >= threshold:
		mask |= 1 << ControllerBindings.JOYPAD_DOWN
	return mask


## What reaches the core for one player: the panel's buttons OR the player's own
## controller (direct input), plus the coin while its pulse lasts, minus the bits
## the machine has no control for.
static func compose(panel: int, direct: int, coin: bool, unsupported: int = 0) -> int:
	var mask := panel | direct
	if coin:
		mask |= 1 << ArcadeProfiles.COIN_BIT
	return mask & ~unsupported


## Whether a player's built-in panel may speak. A controller seated in that
## player's front socket owns the port, and two writers on one port would trample
## each other's SetJoypadState: the panel goes quiet.
static func panel_speaks(port_has_controller: bool) -> bool:
	return not port_has_controller


## Has the core run long enough for a coin to go in? `frames_run` is how many frames it has emulated since it
## was started (Libretro.GetFrameCount, so a slow load or a Quest running the game at half speed waits in
## the GAME's time, not the room's), `wait_frames` the one wait every game gets (ArcadeProfiles.COIN_WAIT_SECONDS).
## Nothing earlier counts: a board still running its RAM and ROM tests reads no coin input at all.
static func game_ready(frames_run: int, wait_frames: int) -> bool:
	return frames_run >= wait_frames


## A coin may be let in early when the player presses START with coins still held, once the core has
## run at least `min_frames`: whoever presses START is looking at a game that is up, which the wait
## cannot know (it errs long on purpose).
static func start_lets_coins_in(frames_run: int, min_frames: int, start_pressed: bool, held: int) -> bool:
	return start_pressed and held > 0 and frames_run >= min_frames


## Coins the cabinet has taken but the GAME has not been given yet (the coin mech's escrow): put in while
## the cabinet only showed its game (the core is not running), or while the core was still booting. A credit
## dropped into a board that is still testing its RAM is lost, so these wait until the game can count them,
## and go in one at a time, a pulse and a gap apart, so each counts. The coin return gives them back.
class CoinEscrow extends RefCounted:
	var _held: Dictionary = {}
	var _gap := 0.0

	func hold(player: int) -> void:
		_held[player] = int(_held.get(player, 0)) + 1

	func held(player: int) -> int:
		return int(_held.get(player, 0))

	func total() -> int:
		var n := 0
		for p: int in _held:
			n += int(_held[p])
		return n

	func is_empty() -> bool:
		return total() == 0

	## One coin of `player`'s back out (the coin return). True when there was one to give back.
	func take_back(player: int) -> bool:
		var n := held(player)
		if n <= 0:
			return false
		if n == 1:
			_held.erase(player)
		else:
			_held[player] = n - 1
		return true

	## Everything held, emptied: {player: coins}. The caller rolls them out into the return cups.
	func take_all() -> Dictionary:
		var out := _held.duplicate()
		_held.clear()
		_gap = 0.0
		return out

	## The player whose coin goes into the game now, or -1. Only while `open` (the game can count it), the
	## lowest player first, ArcadeProfiles.COIN_PULSE_SECONDS + COIN_GAP_SECONDS apart.
	func next(delta: float, open: bool) -> int:
		_gap = maxf(0.0, _gap - delta)
		if not open or _gap > 0.0 or _held.is_empty():
			return -1
		var players := _held.keys()
		players.sort()
		var who: int = players[0]
		take_back(who)
		_gap = ArcadeProfiles.COIN_PULSE_SECONDS + ArcadeProfiles.COIN_GAP_SECONDS
		return who


## A coin in flight: held for a moment so the core reads it, then released.
class CoinPulse extends RefCounted:
	var _remaining := 0.0

	func insert() -> void:
		_remaining = ArcadeProfiles.COIN_PULSE_SECONDS

	## Step the pulse; true while the coin's bit is to be held.
	func advance(delta: float) -> bool:
		if _remaining <= 0.0:
			return false
		_remaining -= delta
		return true

	func active() -> bool:
		return _remaining > 0.0
