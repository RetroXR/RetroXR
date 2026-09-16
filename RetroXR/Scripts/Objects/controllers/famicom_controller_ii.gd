## FamicomControllerII — player 2's pad, the one with the microphone.
##
## The grille is not a capture device a core opens. It reaches the console as ONE
## BIT of player 2's pad — $4016 bit 2, a one-bit threshold detector sitting on
## the waveform — so this pad is handed a measured LEVEL rather than samples, and
## while the room is louder than the volume slider allows it holds that pad's
## START. RetroXR's build of fceumm turns player 2's START into the microphone,
## which costs nothing: a Controller II has no START to lose, because the
## microphone and its slider are moulded where Controller I has START and SELECT.
##
## The FLICKER is the core's job, not this pad's. A game looks for the bit
## alternating while there is sound rather than for it being held — Bokosuka Wars
## is strict about it — and fceumm toggles MicBit on every $4016 read while this
## button is down. Holding it steady here is therefore right, and a pad that
## tried to flicker as well would only alias against the core's own toggle.
class_name FamicomControllerII
extends FamicomController

## What the core reads as the microphone.
const MIC_BITS := 1 << ControllerBindings.JOYPAD_START

## Player 2's port, and only that one. The core looks at joy[1] alone, because
## that is the pad the microphone is wired into; a Controller II plugged into
## port 1 must hold NOTHING, or every noise in the room would be pressing player
## one's START and pausing the game.
const MIC_PORT := 1

## Slider positions at or below this switch the microphone off, which is what the
## far left of the real slider does.
const OFF_BELOW := 0.02
## The rms the gate wants just above that position, and at the slider's top. A
## Famicom player turns the slider up until the game answers, so the useful range
## is a shout down to something close to ordinary speech at arm's length.
const LOUD_RMS := 0.08
const QUIET_RMS := 0.004
## Once open, the gate holds until the room drops to this fraction of the
## threshold. Without it a voice sitting on the threshold would open and shut the
## bit every frame, which is a different signal from the one the core makes.
const RELEASE := 0.6

var _speaking := false
## Whether a level arrived since the last frame. A pad that stopped being fed --
## the player switched capture off in Options, the machine was powered down --
## must fall silent rather than latch on the last loud block it saw.
var _level_fresh := false
var _level := Vector2.ZERO
## The Libretro node the microphone bit is currently held on, or null.
var _pressed_on: Libretro = null

@onready var _volume: VRSlider = get_node_or_null("VolumeSlider") as VRSlider
@onready var _grille: Node3D = get_node_or_null("Model/Face/MicGrille") as Node3D


## No SELECT and no START: this pad has neither.
func small_controls() -> Dictionary:
	return {}


## Where this pad hears from — the grille itself, not the pad's origin. Answered
## directly rather than through seated_microphone(), because unlike a Dreamcast
## pad with a device in a slot, THIS pad is the microphone.
func microphone_position() -> Vector3:
	return _grille.global_position if _grille != null else global_position


## How far the volume slider is open, 0 at the far left.
func volume() -> float:
	return _volume.value if _volume != null else 1.0


## The rms this slider position demands, or 0 when the slider is off. A higher
## setting asks for less, logarithmically, so the slider's travel is even in
## decibels rather than crowding every useful position into its top.
static func threshold_for(volume_value: float) -> float:
	if volume_value <= OFF_BELOW:
		return 0.0
	var t := clampf((volume_value - OFF_BELOW) / (1.0 - OFF_BELOW), 0.0, 1.0)
	return LOUD_RMS * pow(QUIET_RMS / LOUD_RMS, t)


## Whether the room is loud enough for the bit to be set, given where the slider
## is and whether it was already set. Static and pure, so a test can drive the
## decision without a pad, a machine or a microphone.
static func hears(rms: float, volume_value: float, was_on: bool) -> bool:
	var threshold := threshold_for(volume_value)
	if threshold <= 0.0:
		return false
	return rms >= (threshold * RELEASE if was_on else threshold)


## One tick's measured loudness, (rms, peak), already scaled for how far this pad
## is from the player's head. Called by the Microphone autoload.
func on_microphone_level(level: Vector2) -> void:
	_level = level
	_level_fresh = true


func _process(delta: float) -> void:
	super(delta)
	_speaking = hears(_level.x, volume(), _speaking) if _level_fresh else false
	_level_fresh = false
	var target: Libretro = _mic_target() if _speaking else null
	if target != _pressed_on:
		_release_bit()
		if target != null:
			target.SetJoypadExtraButtons(MIC_PORT, MIC_BITS)
		_pressed_on = target


## Whether this pad's microphone can reach a core from `port_index` at all.
## Static and pure so a test can state the rule without a console.
static func drives_port(port_index: int) -> bool:
	return port_index == MIC_PORT


## The machine to hold the bit on, or null: a powered console this pad is plugged
## into, in player 2's port.
func _mic_target() -> Libretro:
	if not drives_port(get_port_index()):
		return null
	var system := get_connected_system()
	if system == null or not system.is_powered_on:
		return null
	return system.get_libretro_node()


func _release_bit() -> void:
	if is_instance_valid(_pressed_on):
		_pressed_on.SetJoypadExtraButtons(MIC_PORT, 0)
	_pressed_on = null


func _exit_tree() -> void:
	_release_bit()
	super()
