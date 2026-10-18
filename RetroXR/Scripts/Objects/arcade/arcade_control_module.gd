## ArcadeControlModule — one player's panel: a stick, six buttons and START, as ONE controller.
##
## The kind is `stick_buttons`. The parts are pictures that follow the input: the stick leans
## and the caps sink while their bits are held. Nothing on it is poked one by one: aiming at the
## panel lights all of it and a press attaches you to it (`PanelGrip`, see ArcadePanelGrip), as
## you would pick up a controller, except that you hold on to it instead of carrying it. While
## attached, your own controller plays this player (ArcadeInput).
##
## Parts are found by name inside this module's subtree: `Btn1`..`Btn6`, `Start` (meshes),
## `StickPivot` (a Node3D the shaft and ball hang from) and `PanelGrip` (the pointable box).
class_name ArcadeControlModule
extends ArcadeModule

signal attach_changed(player: int, attached: bool)

## How far the stick leans at full deflection.
const STICK_TILT_DEG := 16.0
## Per-frame blend toward the target lean.
const STICK_BLEND := 0.35
## How far a pressed cap sinks into the deck.
const CAP_PRESS := 0.006

var _caps: Array[Node3D] = []
var _cap_rest: Array[Vector3] = []
var _cap_bits: Array[int] = []
var _stick: Node3D = null
var _grip: ArcadePanelGrip = null
var _stick_target := Vector2.ZERO
var _stick_current := Vector2.ZERO


func _init() -> void:
	kind = ArcadeProfiles.KIND_STICK_BUTTONS


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_caps.clear()
	_cap_rest.clear()
	_cap_bits.clear()
	for i in ArcadeProfiles.BUTTON_COUNT:
		_add_cap("Btn%d" % (i + 1), ArcadeProfiles.BUTTON_BITS[i])
	_add_cap("Start", ArcadeProfiles.START_BIT)
	_stick = find_child("StickPivot", true, false) as Node3D
	_grip = find_child("PanelGrip", true, false) as ArcadePanelGrip
	if _grip != null:
		_grip.toggled.connect(func(on: bool) -> void: attach_changed.emit(player, on))


func _add_cap(node_name: String, bit: int) -> void:
	var cap := find_child(node_name, true, false) as Node3D
	if cap == null:
		return
	_caps.append(cap)
	_cap_rest.append(cap.position)
	_cap_bits.append(bit)


## Attach to (or let go of) this panel, as a press on it does.
func set_attached(on: bool) -> void:
	if _grip != null:
		_grip.set_attached(on)


func is_attached() -> bool:
	return _grip != null and _grip.attached


func grip() -> ArcadePanelGrip:
	return _grip


## Show the state that reached the core: sink the caps it presses and lean the stick.
## `mask` is the joypad mask.
func show_state(mask: int) -> void:
	for i in _caps.size():
		var pressed := (mask & (1 << _cap_bits[i])) != 0
		_caps[i].position = _cap_rest[i] + (Vector3(0, 0, -CAP_PRESS) if pressed else Vector3.ZERO)
	var x := float((mask >> ControllerBindings.JOYPAD_RIGHT) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_LEFT) & 1)
	var y := float((mask >> ControllerBindings.JOYPAD_DOWN) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_UP) & 1)
	_stick_target = Vector2(x, y)


func tick(_delta: float) -> void:
	if _stick == null:
		return
	_stick_current = _stick_current.lerp(_stick_target, STICK_BLEND)
	# Deck-local: +X right, +Y toward the monitor, the shaft along +Z. A turn about X
	# leans it toward -Y (the player) for a positive angle, which is "down" on the
	# pad; a turn about Y leans it toward +X, which is "right".
	_stick.basis = Basis.from_euler(Vector3(
		deg_to_rad(_stick_current.y * STICK_TILT_DEG),
		deg_to_rad(_stick_current.x * STICK_TILT_DEG), 0.0))


## The stick's lean as last shown, for the tests and the probe.
func stick_lean() -> Vector2:
	return _stick_current
