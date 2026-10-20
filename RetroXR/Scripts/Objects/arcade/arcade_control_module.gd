## ArcadeControlModule — one player's panel: a stick, six buttons and START, as ONE controller.
##
## The kind is `stick_buttons`. The parts are pictures that follow the input: the stick leans
## and the caps sink while their bits are held. Nothing on it is poked one by one: aiming at the
## panel lights all of it and a press attaches you to it (`PanelGrip`, see ArcadePanelGrip), as
## you would pick up a controller, except that you hold on to it instead of carrying it. While
## attached, your own controller plays this player (ArcadeInput).
##
## Parts are found by name inside this module's subtree: `Btn1`..`Btn6`, `Start` (meshes),
## `StickPivot` (a Node3D the shaft and ball hang from), `DialPivot` (a Node3D a paddle knob
## hangs from, turned by LEFT and RIGHT) and `PanelGrip` (the pointable box). Every one is
## optional: a Neo Geo panel has four buttons, a gun cabinet's has only START.
class_name ArcadeControlModule
extends ArcadeModule

signal attach_changed(player: int, attached: bool)

## How far the stick leans at full deflection.
const STICK_TILT_DEG := 16.0
## Per-frame blend toward the target lean.
const STICK_BLEND := 0.35
## How far a pressed cap sinks into the deck.
const CAP_PRESS := 0.006
## How fast a held LEFT or RIGHT turns a dial, radians a second (about one turn a second).
const DIAL_SPEED := TAU

var _caps: Array[Node3D] = []
var _cap_rest: Array[Vector3] = []
var _cap_bits: Array[int] = []
var _stick: Node3D = null
var _dial: Node3D = null
var _dial_dir := 0.0
var _dial_angle := 0.0
var _grip: ArcadePanelGrip = null
var _stick_target := Vector2.ZERO
var _stick_current := Vector2.ZERO
## The mask last drawn, so an unchanged one costs nothing: show_state runs every frame, and a
## `position =` dirties the transform and goes to the renderer even when it writes the value it holds.
var _shown_mask := -1
## Whether the stick's basis has been written at all (the first tick always writes it once).
var _stick_written := false


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
	_dial = find_child("DialPivot", true, false) as Node3D
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


## Whether this is a momentary panel (a gun cabinet's START) and it is being pressed now.
func start_held() -> bool:
	return _grip != null and _grip.momentary and _grip.held


func grip() -> ArcadePanelGrip:
	return _grip


## Show the state that reached the core: sink the caps it presses and lean the stick.
## `mask` is the joypad mask.
func show_state(mask: int) -> void:
	if mask == _shown_mask:
		return
	_shown_mask = mask
	for i in _caps.size():
		var pressed := (mask & (1 << _cap_bits[i])) != 0
		_caps[i].position = _cap_rest[i] + (Vector3(0, 0, -CAP_PRESS) if pressed else Vector3.ZERO)
	var x := float((mask >> ControllerBindings.JOYPAD_RIGHT) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_LEFT) & 1)
	var y := float((mask >> ControllerBindings.JOYPAD_DOWN) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_UP) & 1)
	_stick_target = Vector2(x, y)
	_dial_dir = x


func tick(delta: float) -> void:
	if _dial != null and _dial_dir != 0.0:
		_dial_angle = wrapf(_dial_angle + _dial_dir * DIAL_SPEED * delta, -PI, PI)
		_dial.basis = Basis(Vector3.BACK, _dial_angle)
	if _stick == null:
		return
	# Settled: the lerp never reaches its target, so it used to rewrite the same basis every frame for ever.
	if _stick_written and _stick_current == _stick_target:
		return
	_stick_written = true
	_stick_current = _stick_current.lerp(_stick_target, STICK_BLEND)
	if _stick_current.distance_squared_to(_stick_target) < 1.0e-6:
		_stick_current = _stick_target
	# Deck-local: +X right, +Y toward the monitor, the shaft along +Z. A turn about X
	# leans it toward -Y (the player) for a positive angle, which is "down" on the
	# pad; a turn about Y leans it toward +X, which is "right".
	_stick.basis = Basis.from_euler(Vector3(
		deg_to_rad(_stick_current.y * STICK_TILT_DEG),
		deg_to_rad(_stick_current.x * STICK_TILT_DEG), 0.0))


## The stick's lean as last shown, for the tests and the probe.
func stick_lean() -> Vector2:
	return _stick_current
