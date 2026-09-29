## RetroSystemModelGameBoyAdvance — GBA (landscape, 240×160 LCD).
##
## Two separate models wear this script:
##   * game_boy_advance.tscn — the detailed shell. Its GLB (imported-assets/
##     consoles/game_boy_advance/gba_console.glb, codex-photos/gba's debranded
##     mobile LOD0) is baked in as "Shell". Its controls are real meshes with real
##     pivots, driven below.
##   * game_boy_advance_primitive.tscn — the stand-in, whose authored controls the
##     handheld base's stand-in pass drives.
## Everything that touches the shell's meshes checks _glb first, so the stand-in
## keeps the shared behaviour.
class_name RetroSystemModelGameBoyAdvance
extends RetroSystemModelHandheld

## The GLB's own figures (node extras / codex-photos/gba/console/README.md): A, B,
## START and SELECT press 0.8 mm straight in, the D-pad rocks 0.07 rad about its
## centre, and each shoulder cap turns 0.06 rad about its inner hinge, the L one
## positive about +Z and the R one negative.
const _BUTTON_TRAVEL := 0.0008
const _DPAD_TILT := 0.07
const _SHOULDER_TURN := {"Shoulder_L": 0.06, "Shoulder_R": -0.06}
const _ANIM_W := 0.35
## The thumbwheel is 9 mm across. It turns by the distance its rim moves under the
## thumb, so a full sweep of the volume slider is 0.012 / 0.0045 rad, about 150°.
const _WHEEL_RADIUS := 0.0045
## The power lamp: green while the machine runs, unlit (the GLB's own dark lens)
## while it is off.
const _LED_COLOR := Color(0.25, 1.0, 0.35)

## The headphone jack on the bottom edge, in this node's frame: where the
## video-out lead plugs in on this model, aimed out along the edge's normal there.
## The handheld default puts the lead on the back edge at 30 % of the width, which
## on this shell is inside the R button.
const _AV_JACK_POS := Vector3(0.04184, -0.001563, 0.035901)
const _AV_JACK_OUT := Vector3(0.331, 0.0, 0.944)

var _presses: Array = []   # [node, rest, joypad bit]
var _hinges: Array = []    # [node, rest, joypad bit, radians]
var _dpad: Node3D = null
var _dpad_rest := Transform3D()
var _wheel: Node3D = null
var _wheel_rest := Transform3D()
var _wheel_value := NAN
var _led: MeshInstance3D = null
var _led_material: StandardMaterial3D = null


func _init() -> void:
	# MediaDimensions "gba": the cartridge model's own shell.
	cart_size = Vector3(0.060, 0.035, 0.009)
	# Keep the VideoHandler's nearest-filtered material instead of wrapping the
	# picture with the shared pixel-AA shader. This gives the GBA a raw point-
	# sampled image, matching frontends that present the core texture directly.
	_lcd_shader = null


func _on_shell_ready() -> void:
	if _glb == null:
		return
	_take_lcd_look()
	_adopt_knob(_power_switch, "PowerSwitch")
	# The wheel turns rather than slides, so it is not handed to the slider as its
	# knob (that would carry it along the edge). The slider's placeholder goes.
	if _volume_slider != null:
		var knob := _volume_slider.get_node_or_null("KnobMesh") as Node3D
		if knob != null:
			knob.visible = false
	_wheel = _glb.find_child("VolumeWheel", true, false) as Node3D
	if _wheel != null:
		_wheel_rest = _wheel.transform
	_led = _glb.find_child("PowerLED", true, false) as MeshInstance3D
	# The link socket's placeholder jack would stand in the GLB's own EXT socket.
	var jack := get_node_or_null("LinkPort/LinkJack") as Node3D
	if jack != null:
		jack.visible = false
	_bind_shell_controls()


## Draw the LCD as the GLB draws it while nothing is running: the shell's own
## Screen material goes on our quad (which is exactly on the GLB's), and the GLB's
## quad is hidden so the two cannot fight for the same depth.
func _take_lcd_look() -> void:
	var lcd := _glb.find_child("Screen", true, false) as MeshInstance3D
	if lcd == null or _screen == null:
		return
	_screen_off_material = lcd.get_active_material(0)
	_screen.set_surface_override_material(0, _screen_off_material)
	lcd.visible = false


func _bind_shell_controls() -> void:
	for spec: Array in [["Button_A", ControllerBindings.JOYPAD_A], ["Button_B", ControllerBindings.JOYPAD_B],
			["Start", ControllerBindings.JOYPAD_START], ["Select", ControllerBindings.JOYPAD_SELECT]]:
		var n := _glb.find_child(spec[0], true, false) as Node3D
		if n != null:
			_presses.append([n, n.transform, int(spec[1])])
	_dpad = _glb.find_child("DPad", true, false) as Node3D
	if _dpad != null:
		_dpad_rest = _dpad.transform
	for nm: String in _SHOULDER_TURN:
		var cap := _glb.find_child(nm, true, false) as Node3D
		if cap != null:
			var bit := ControllerBindings.JOYPAD_L if nm == "Shoulder_L" else ControllerBindings.JOYPAD_R
			_hinges.append([cap, cap.transform, bit, float(_SHOULDER_TURN[nm])])


## Every transform here is in the control meshes' parent frame, the GLB's own:
## +Z out of the face, +Y up it. Each mesh's origin is its real pivot.
func animate_controls(btn: int, lstick: Vector2, rstick: Vector2) -> void:
	if _glb == null:
		super(btn, lstick, rstick)
		return
	for e: Array in _presses:
		var rest: Transform3D = e[1]
		var pressed := 1.0 if (btn >> int(e[2])) & 1 else 0.0
		_ease(e[0], Transform3D(rest.basis, rest.origin + Vector3(0, 0, -_BUTTON_TRAVEL * pressed)))
	if _dpad != null:
		var up := float((btn >> ControllerBindings.JOYPAD_UP) & 1) - float((btn >> ControllerBindings.JOYPAD_DOWN) & 1)
		var right := float((btn >> ControllerBindings.JOYPAD_RIGHT) & 1) - float((btn >> ControllerBindings.JOYPAD_LEFT) & 1)
		# UP sinks the +Y arm (a turn about -X), RIGHT the +X arm (about +Y).
		var r := Basis(Vector3.RIGHT, -up * _DPAD_TILT) * Basis(Vector3.UP, right * _DPAD_TILT)
		_ease(_dpad, Transform3D(r * _dpad_rest.basis, _dpad_rest.origin))
	for e: Array in _hinges:
		var rest: Transform3D = e[1]
		var turn: float = float(e[3]) if (btn >> int(e[2])) & 1 else 0.0
		_ease(e[0], Transform3D(Basis(Vector3.BACK, turn) * rest.basis, rest.origin))


func _ease(node: Node3D, target: Transform3D) -> void:
	node.transform = node.transform.interpolate_with(target, _ANIM_W)


## The wheel follows the slider's VALUE every frame rather than its signal, so a
## value set without one (a restore, a peer's switch) turns it too. It sits as
## modelled at full volume, where the slider starts.
func _process(delta: float) -> void:
	super(delta)
	if _wheel == null or _volume_slider == null or _volume_slider.value == _wheel_value:
		return
	_wheel_value = _volume_slider.value
	var turn := (_wheel_value - 1.0) * _volume_slider.travel / _WHEEL_RADIUS
	_wheel.transform = Transform3D(Basis(Vector3.BACK, turn) * _wheel_rest.basis, _wheel_rest.origin)


func on_power_on() -> void:
	super()
	_light_led(true)


func on_power_off() -> void:
	super()
	_light_led(false)


func _light_led(on: bool) -> void:
	if _led == null:
		return
	if not on:
		_led.set_surface_override_material(0, null)
		return
	if _led_material == null:
		_led_material = StandardMaterial3D.new()
		_led_material.albedo_color = _LED_COLOR.darkened(0.6)
		_led_material.roughness = 0.24
		_led_material.emission_enabled = true
		_led_material.emission = _LED_COLOR
		_led_material.emission_energy_multiplier = 2.0
	_led.set_surface_override_material(0, _led_material)


func configure_cable_attach(attach_point: Node3D) -> void:
	super(attach_point)
	if _glb == null:
		return
	attach_point.position = _AV_JACK_POS
	aim_cable_exit(attach_point, _AV_JACK_OUT.normalized())
