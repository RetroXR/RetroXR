## RetroSystemModelGameBoyAdvance — GBA (landscape, 240×160 LCD).
##
## Two separate models wear this script:
##   * game_boy_advance.tscn — the detailed shell. Its GLB (imported-assets/
##     consoles/game_boy_advance/gba_console.glb, codex-photos/nintendo/gba/console's debranded
##     mobile LOD0) is baked in as "Shell". Its controls are real meshes with real
##     pivots, driven below.
##   * game_boy_advance_primitive.tscn — the stand-in, whose authored controls the
##     handheld base's stand-in pass drives.
## Everything that touches the shell's meshes checks _glb first, so the stand-in
## keeps the shared behaviour.
class_name RetroSystemModelGameBoyAdvance
extends RetroSystemModelHandheld

## The GLB's own figures (node extras / codex-photos/nintendo/gba/console/console/README.md): A, B,
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

## The cartridge slot, in this node's frame, from the laser-scanned shell: 61 mm
## wide, its front wall (the screen side) at y = -3.09 mm, and its back and side
## walls stopping at z = -33.2 mm, 7.8 mm short of the top edge. Above them the
## slot is open to the back, which is where a seated cartridge shows.
const _SLOT_HALF_WIDTH := 0.031
const _SLOT_FRONT_Y := -0.0031
const _SLOT_WALL_Z := -0.0332
## The seat is the GBA cartridge's middle, and that is 0.875 mm behind the
## slot's middle, because a GBA cart's grip bulges toward its label. A Game Boy
## cart has no grip: centred on the seat it stood 0.7 mm into the back wall, so
## its own middle goes on the slot's instead. +Z in the cart's frame is its
## label, which faces the back of the console.
const _SLOT_MIDDLE_FROM_SEAT := 0.000875

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


## A Game Boy or Game Boy Color cartridge goes in to the GBA's connector, 30 mm
## proud of the top edge (see RetroSystemModelHandheld.foreign_cart_seat), and
## on this shell centred on the slot rather than on the GBA cart's grip.
func foreign_cart_seat(foreign: Vector3) -> Vector3:
	var seat := super(foreign)
	if _glb != null:
		seat.z += _SLOT_MIDDLE_FROM_SEAT
	return seat


## A seated cartridge stands inside the body's bounds on this shell: the slot is in
## the back half of the top edge, and a GBA cart ends 0.3 mm past the front top.
## One box for the body (the base's, padded 5 mm) put shell in front of the cart
## from every direction, so the desktop pointer always took the console. Carve
## the slot out of both the body and its pointer box, as the NES does its bay:
## what is left in front of the cart is only what is really there.
func configure_handheld_body(host: Node3D) -> void:
	super(host)
	if _glb == null:
		return
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		var size := (col.shape as BoxShape3D).size
		_carve_slot(col, AABB(col.position - size * 0.5, size))


## Reuse `col` for everything below the slot walls' top and give its body three
## siblings: the front top over the slot, and the shoulders either side of it.
func _carve_slot(col: CollisionShape3D, env: AABB) -> void:
	var lo := env.position
	var hi := env.end
	var parts := [
		["", AABB(Vector3(lo.x, lo.y, _SLOT_WALL_Z),
			Vector3(hi.x - lo.x, hi.y - lo.y, hi.z - _SLOT_WALL_Z))],
		["SlotFrontTop", AABB(Vector3(lo.x, _SLOT_FRONT_Y, lo.z),
			Vector3(hi.x - lo.x, hi.y - _SLOT_FRONT_Y, _SLOT_WALL_Z - lo.z))],
		["SlotLeftShoulder", AABB(Vector3(lo.x, lo.y, lo.z),
			Vector3(-_SLOT_HALF_WIDTH - lo.x, _SLOT_FRONT_Y - lo.y, _SLOT_WALL_Z - lo.z))],
		["SlotRightShoulder", AABB(Vector3(_SLOT_HALF_WIDTH, lo.y, lo.z),
			Vector3(hi.x - _SLOT_HALF_WIDTH, _SLOT_FRONT_Y - lo.y, _SLOT_WALL_Z - lo.z))],
	]
	var parent := col.get_parent()
	for part: Array in parts:
		var part_name: String = part[0]
		var a: AABB = part[1]
		var target := col
		if not part_name.is_empty():
			target = parent.get_node_or_null(NodePath(part_name)) as CollisionShape3D
			if target == null:
				target = CollisionShape3D.new()
				target.name = part_name
				parent.add_child(target)
		var shape := BoxShape3D.new()
		shape.size = a.size
		target.shape = shape
		target.position = a.get_center()


## The grab stub is what shows: from the cart's grip end down to where the slot
## walls stop. The handheld default, 28 % of a GBA cart's length, is 3.6 mm more
## than shows on this shell, and a Game Boy cart shows 38 mm.
func play_cartridge_insert(cartridge: Node3D, slot: Node3D) -> void:
	super(cartridge, slot)
	if _glb == null or slot == null or not cartridge.has_method("set_seated_grab_stub") \
			or not ("systemid" in cartridge):
		return
	var media := str(cartridge.get("systemid"))
	var size := MediaDimensions.cart_size(media)
	var seat := Vector3.ZERO
	if not media.is_empty() and media != _systemid_of(slot):
		seat = foreign_cart_seat(size)
	var grip := to_local(slot.global_transform * (Vector3(0.0, size.y * 0.5, 0.0) - seat))
	cartridge.call("set_seated_grab_stub", maxf(_SLOT_WALL_Z - grip.z, 0.0) + 0.004)
