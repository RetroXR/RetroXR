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
