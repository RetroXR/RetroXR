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
## A cap's label: font size in pixels, metres a pixel, how far above the deck it is printed, and the
## cap's radius when its mesh cannot say.
const LABEL_FONT := 20
const LABEL_PIXEL := 0.00045
const LABEL_LIFT := 0.0015
const CAP_RADIUS := 0.0155
## How fast a held LEFT or RIGHT turns a dial, radians a second (about one turn a second).
const DIAL_SPEED := TAU

var _caps: Array[Node3D] = []
## Each cap's flange (`<cap>Rim`, fixed, of the cap's colour), or null where a scene has none.
var _cap_rims: Array[Node3D] = []
var _cap_rest: Array[Vector3] = []
var _cap_bits: Array[int] = []
## Which of the six buttons each cap is (0-based), or -1 for START, which every game has.
var _cap_button: Array[int] = []
## The label on a cap, made the first time a core names one (Label3D, a child of the cap so it sinks with it).
var _cap_labels: Dictionary = {}
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
	_cap_rims.clear()
	_cap_rest.clear()
	_cap_bits.clear()
	_cap_button.clear()
	for i in ArcadeProfiles.BUTTON_COUNT:
		_add_cap("Btn%d" % (i + 1), ArcadeProfiles.BUTTON_BITS[i], i)
	_add_cap("Start", ArcadeProfiles.START_BIT, -1)
	_stick = find_child("StickPivot", true, false) as Node3D
	_dial = find_child("DialPivot", true, false) as Node3D
	_grip = find_child("PanelGrip", true, false) as ArcadePanelGrip
	if _grip != null:
		_grip.toggled.connect(func(on: bool) -> void: attach_changed.emit(player, on))


func _add_cap(node_name: String, bit: int, button: int) -> void:
	var cap := find_child(node_name, true, false) as Node3D
	if cap == null:
		return
	_caps.append(cap)
	_cap_rims.append(find_child(node_name + "Rim", true, false) as Node3D)
	_cap_rest.append(cap.position)
	_cap_bits.append(bit)
	_cap_button.append(button)


## Show only what the game in the bay has: the panel at all (a one-player game has no second),
## the stick, the caps it reads, and the words the core gave them. `profile` null, or a game the
## table does not know, puts the whole panel back.
func apply_profile(profile: ArcadeGameProfile) -> void:
	var on_panel := profile == null or profile.panel_visible(player)
	visible = on_panel
	ArcadeModule.set_pointable(_grip, on_panel)
	if not on_panel:
		set_attached(false)
	if _stick != null:
		_stick.visible = profile == null or profile.stick_visible()
	for i in _caps.size():
		var button := _cap_button[i]
		if button < 0:
			continue
		_caps[i].visible = profile == null or profile.button_visible(player, button)
		# A button the game does not have leaves no empty flange behind.
		if _cap_rims[i] != null:
			_cap_rims[i].visible = _caps[i].visible
		_label_cap(i, "" if profile == null else profile.button_label(player, button))


## Put words on a cap, or take them off. The words are printed on the deck just under the cap (a cap is
## 31 mm across and tilts away from a player, so words on its top cannot be read); they do not sink with it.
func _label_cap(index: int, text: String) -> void:
	var label := _cap_labels.get(index) as Label3D
	if text.is_empty():
		if label != null:
			label.visible = false
		return
	if label == null:
		var cap := _caps[index]
		var holder := cap.get_parent() as Node3D
		if holder == null:
			return
		label = Label3D.new()
		label.name = "CapLabel"
		label.font_size = LABEL_FONT
		label.pixel_size = LABEL_PIXEL
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		label.shaded = false
		label.double_sided = false
		# The monitor-side row of caps is labelled above its caps, the rest below theirs: two rows of
		# caps are only ~50 mm apart, and words under the top row land on the bottom row.
		var above := _cap_rest[index].y > _mean_cap_y() + 0.005
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if above else VERTICAL_ALIGNMENT_TOP
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var radius := CAP_RADIUS
		# Measured on the flange where the button has one: it is the widest part, and a word printed
		# inside it would be under it.
		var shape := _cap_rims[index] if _cap_rims[index] != null else cap
		if shape is MeshInstance3D and (shape as MeshInstance3D).mesh != null:
			var box := (shape as MeshInstance3D).get_aabb()
			radius = maxf(box.size.x, box.size.y) * 0.5
		label.position = _cap_rest[index] + Vector3(0.0, (radius + 0.002) * (1.0 if above else -1.0), LABEL_LIFT)
		holder.add_child(label)
		_cap_labels[index] = label
	label.text = text
	label.visible = true


## The mean height of the six buttons' caps on the panel (0 with none).
func _mean_cap_y() -> float:
	var sum := 0.0
	var n := 0
	for i in _caps.size():
		if _cap_button[i] >= 0:
			sum += _cap_rest[i].y
			n += 1
	return sum / float(n) if n > 0 else 0.0


## The label text on a cap (0-based, the six buttons), or "" when it has none, for the tests.
func cap_label(button: int) -> String:
	for i in _caps.size():
		if _cap_button[i] == button:
			var label := _cap_labels.get(i) as Label3D
			return label.text if label != null and label.visible else ""
	return ""


## Is the cap for button `button` (0-based) drawn, for the tests.
func cap_shown(button: int) -> bool:
	for i in _caps.size():
		if _cap_button[i] == button:
			return _caps[i].visible
	return false


func stick_shown() -> bool:
	return _stick != null and _stick.visible


## Attach to (or let go of) this panel, as a press on it does.
func set_attached(on: bool) -> void:
	# A panel the game does not use (apply_profile) is not there to attach to.
	if _grip != null and (visible or not on):
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
