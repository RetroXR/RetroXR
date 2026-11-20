## WiiUGamePad — the Wii U GamePad (WUP-010) as a primitive: 255.7 x 133.9 mm,
## the screen's 137.3 x 77.2 active area in the middle, held flat in both hands
## with the screen up and its top edge away (-Z), as the handhelds are.
##
## It pairs to libretro port 0 (WiiLink: the GamePad's port on a Wii U), and is
## then four things at once:
##   - a pad: the RETRO XR pad's controls and bindings (WiiUWirelessPad);
##   - a screen: the GamePad's picture out of the frame Cemu packs, the window
##     RetroSystemModelWiiU.gamepad_rect() names (video views);
##   - a touch screen: a TVTouchSurface on the glass, a fingertip or the laser, to
##     the console's pointer on port 0, inside that same window;
##   - a motion sensor: accel and gyro from its pose (MotionSampler) on Android's
##     axes, which Cemu takes for the GamePad (+X right, +Y the top edge, +Z out of
##     the screen; at rest flat, (0, 0, 1) g).
## And its speaker: the console's controller audio voice for port 0, posed here.
class_name WiiUGamePad
extends WiiUWirelessPad

## Measured: RetroXR-models nintendo/wiiu/gamepad (MEASUREMENTS.md).
const BODY := Vector3(0.2557, 0.024, 0.1339)
const SCREEN := Vector2(0.1373, 0.0772)
const SCREEN_Y := BODY.y * 0.5 + 0.0006

const SHELL := Color(0.93, 0.93, 0.915)
const DARK := Color(0.07, 0.07, 0.08)
const GLASS_OFF := Color(0.02, 0.02, 0.025)
const DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")
## Its AC port, on the top edge: the WUP-011's plug, as the cradle's back takes.
## Never renamed: a save names the socket a plug is in by it.
const AC_PORT_NAME := "ACAdapterPort"
const CHARGE_ON := Color(1.0, 0.45, 0.05)
const CHARGE_OFF := Color(0.12, 0.1, 0.08)

var _screen: MeshInstance3D = null
var _touch: TVTouchSurface = null
var _screen_mat: ShaderMaterial = null
var _off_mat: StandardMaterial3D = null
var _last_tex: Texture2D = null
var _last_rect := Rect2(-1, -1, -1, -1)
var _motion := MotionSampler.new()
var _speaker: Marker3D = null
var _speaker_voice := -1
var _speaker_gain := -1.0
var _mx: Object = null
var _listener: Node = null
## The cradle it stands in, or null (WiiUGamePadCradle.set by its seat).
var _cradle: Node = null
var _power: PowerInput = null
var _charge_mat: StandardMaterial3D = null
var _charging := false
var _charge_poll := 0


func _init() -> void:
	device_type = RETRO_DEVICE_JOYPAD
	systemid = "wiiu"
	super._init()


func wants_gamepad_port() -> bool:
	return true


func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var shell := _mk_mat(SHELL, 0.3)
	var dark := _mk_mat(DARK, 0.5)
	_mk_box(model, "Body", BODY, Vector3.ZERO, shell)
	# The ridge across the back the fingers hook behind.
	_mk_box(model, "Ridge", Vector3(BODY.x * 0.86, 0.016, 0.03), Vector3(0.0, -0.019, -0.03), shell)
	# The bezel round the glass.
	_mk_box(model, "Bezel", Vector3(0.162, 0.0008, 0.092), Vector3(0.0, BODY.y * 0.5 + 0.0002, 0.0), dark)
	# The glass, a +Z quad turned to face up, its picture's top toward -Z.
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN
	_screen.mesh = quad
	_screen.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, SCREEN_Y, 0.0))
	model.add_child(_screen)
	# Left: stick over D-pad. Right: stick over A/B/X/Y.
	var top := BODY.y * 0.5
	_mk_stick(model, "StickL", Vector3(-0.1, top + 0.005, -0.03), dark)
	_mk_dpad(model, Vector3(-0.1, top + 0.002, 0.02), dark)
	_mk_stick(model, "StickR", Vector3(0.1, top + 0.005, -0.03), dark)
	_mk_face(model, "FaceX", "X", Vector3(0.1, top + 0.002, 0.008), dark)
	_mk_face(model, "FaceB", "B", Vector3(0.1, top + 0.002, 0.032), dark)
	_mk_face(model, "FaceY", "Y", Vector3(0.088, top + 0.002, 0.02), dark)
	_mk_face(model, "FaceA", "A", Vector3(0.112, top + 0.002, 0.02), dark)
	# + and - under the face buttons, HOME, TV and POWER beside them.
	_mk_cyl(model, "Start", 0.0028, 0.003, Vector3(0.112, top + 0.0015, 0.05), dark)
	_mk_cyl(model, "Select", 0.0028, 0.003, Vector3(0.096, top + 0.0015, 0.05), dark)
	_mk_cyl(model, "Home", 0.0035, 0.002, Vector3(0.0, top + 0.001, 0.055), dark)
	_mk_cyl(model, "TV", 0.0025, 0.002, Vector3(0.095, top + 0.001, -0.055), dark)
	_mk_cyl(model, "Power", 0.0025, 0.002, Vector3(0.108, top + 0.001, -0.055), dark)
	# L and R on the top edge, ZL and ZR under them on the ridge.
	_mk_box(model, "ShoulderL", Vector3(0.032, 0.008, 0.006), Vector3(-0.09, 0.004, -BODY.z * 0.5 - 0.002), shell)
	_mk_box(model, "ShoulderR", Vector3(0.032, 0.008, 0.006), Vector3(0.09, 0.004, -BODY.z * 0.5 - 0.002), shell)
	_mk_box(model, "TriggerL", Vector3(0.03, 0.01, 0.012), Vector3(-0.09, -0.02, -0.052), shell)
	_mk_box(model, "TriggerR", Vector3(0.03, 0.01, 0.012), Vector3(0.09, -0.02, -0.052), shell)
	# Its own AC port in the top edge (RetroXR-models: x -54 mm), +Z out of the edge.
	var jack := DC_PORT.instantiate() as DcPort
	jack.name = AC_PORT_NAME
	jack.connector = WiiUGamePadCradle.PLUG
	jack.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-0.054, 0.0, -BODY.z * 0.5))
	add_child(jack)
	# The battery lamp, orange while it charges.
	_charge_mat = StandardMaterial3D.new()
	_charge_mat.albedo_color = CHARGE_OFF
	_charge_mat.emission = CHARGE_ON
	_mk_cyl(model, "ChargeLed", 0.0012, 0.0008, Vector3(-0.08, top + 0.0004, 0.055), _charge_mat)
	# The speakers' middle, under the screen.
	_speaker = Marker3D.new()
	_speaker.name = "Speaker"
	_speaker.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, top, 0.052))
	add_child(_speaker)
	var label := Label3D.new()
	label.name = "SyncLabel"
	label.text = "SYNC"
	label.font_size = 24
	label.pixel_size = 0.0002
	label.outline_size = 0
	label.modulate = Color(0.4, 0.4, 0.4)
	# On the back, read the right way round with the top edge up: x to the
	# GamePad's -X, up its top edge (-Z), facing out of the back (-Y).
	label.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)),
		Vector3(0.021, -BODY.y * 0.5 - 0.0004, 0.05))
	model.add_child(label)


func _ready() -> void:
	super._ready()
	add_to_group(WiiUGamePadCradle.PAD_GROUP)
	_power = PowerInput.on(self)
	_power.label = "Wii U GamePad (%s)" % name
	_power.add_inlet(get_node(AC_PORT_NAME))
	_off_mat = StandardMaterial3D.new()
	_off_mat.albedo_color = GLASS_OFF
	_off_mat.roughness = 0.08
	_off_mat.metallic_specular = 0.8
	_screen.set_surface_override_material(0, _off_mat)


func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	_motion.reset()
	if _touch == null:
		_touch = TVTouchSurface.new()
		_touch.setup(system, Rect2(0, 0, 1, 1), _screen)
		_screen.add_child(_touch)
	else:
		_touch.host = system


func on_unplugged() -> void:
	super.on_unplugged()
	if _touch != null:
		_touch.queue_free()
		_touch = null
	_show_off()


func _process(delta: float) -> void:
	super._process(delta)
	_update_screen()
	_charge_poll -= 1
	if _charge_poll <= 0:
		_charge_poll = 15
		_update_charging()
	if _connected_system != null:
		var lib := _connected_system.get_libretro_node()
		if is_instance_valid(lib):
			_update_speaker(lib)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _connected_system == null or not _connected_system.is_powered_on:
		return
	_motion.sample(global_transform, delta)
	var lib := _connected_system.get_libretro_node()
	if not is_instance_valid(lib):
		return
	var b := global_transform.basis
	var a := android_axes(_motion.accel_local(b))
	var w := android_axes(_motion.gyro_local(b))
	if not NetworkManager.netplay_set_aux_sensor(_connected_system, _port_index, 0,
			int(a.x * 1000.0), int(a.y * 1000.0), int(a.z * 1000.0)):
		lib.SetSensorAccel(_port_index, a.x, a.y, a.z)
	if not NetworkManager.netplay_set_aux_sensor(_connected_system, _port_index, 0,
			int(w.x * 100.0), int(w.y * 100.0), int(w.z * 100.0), true):
		lib.SetSensorGyro(_port_index, w.x, w.y, w.z)


## From the pad's own frame (+X right, +Y out of the screen, -Z the top edge) to
## Android's (+X right, +Y the top edge, +Z out of the screen), which Cemu reads.
## A proper rotation, so it holds for angular velocity too.
static func android_axes(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


# ── Charging ─────────────────────────────────────────────────────────────────

## The cradle it was set in, or null when lifted out.
func set_cradle(cradle: Node) -> void:
	_cradle = cradle
	_update_charging()


## Charging: in a cradle with its supply, or the adapter in its own top port with
## power by the room's rule. Only the lamp: no charge is modelled, and the GamePad
## runs either way.
func is_charging() -> bool:
	if is_instance_valid(_cradle) and _cradle.has_method("is_powered") and bool(_cradle.call("is_powered")):
		return true
	var jack := get_node_or_null(AC_PORT_NAME) as Port
	return jack != null and jack.seated_plug() != null and _power != null and _power.is_live()


func _update_charging() -> void:
	var now := is_charging()
	if now == _charging:
		return
	_charging = now
	print("[WiiU] GamePad %s" % ("charging" if now else "not charging"))
	if _charge_mat != null:
		_charge_mat.albedo_color = CHARGE_ON if now else CHARGE_OFF
		_charge_mat.emission_enabled = now


# ── The screen ───────────────────────────────────────────────────────────────

## The window of the console's frame this glass shows, or null to show nothing.
func picture_rect() -> Variant:
	if _connected_system == null or not _connected_system.is_powered_on:
		return null
	var model := _connected_system.get_model()
	if model == null or not model.has_method("gamepad_rect"):
		return null
	var r: Variant = model.call("gamepad_rect")
	# No views yet: the core is drawing its own layout, which is the TV's frame.
	return r if r is Rect2 else Rect2(0, 0, 1, 1)


func _update_screen() -> void:
	var r: Variant = picture_rect()
	var tex: Texture2D = _connected_system.get_video_texture() \
		if r is Rect2 and _connected_system.has_method("get_video_texture") else null
	if tex == null:
		_show_off()
		return
	if _screen_mat == null:
		_screen_mat = ShaderMaterial.new()
		_screen_mat.shader = RetroTV.window_shader()
	if tex != _last_tex:
		_last_tex = tex
		_screen_mat.set_shader_parameter("source_tex", tex)
	var rect: Rect2 = r
	if rect != _last_rect:
		_last_rect = rect
		_screen_mat.set_shader_parameter("source_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		if _touch != null:
			_touch.uv_rect = rect
		print("[WiiU] GamePad shows %s of the frame" % [str(rect)])
	if _screen.get_surface_override_material(0) != _screen_mat:
		_screen.set_surface_override_material(0, _screen_mat)


func _show_off() -> void:
	if _screen != null and _off_mat != null and _screen.get_surface_override_material(0) != _off_mat:
		_screen.set_surface_override_material(0, _off_mat)
		_last_tex = null
		_last_rect = Rect2(-1, -1, -1, -1)


# ── The speaker ──────────────────────────────────────────────────────────────

## The console's voice for the GamePad's speaker (controller audio, port 0 index
## 0), on the pad, by the distance law alone, as the Wii Remote's.
func _update_speaker(libretro: Node) -> void:
	if not libretro.has_method("GetControllerAudioVoiceId"):
		return
	var voice: int = libretro.GetControllerAudioVoiceId(_port_index, 0)
	if voice != _speaker_voice:
		_speaker_voice = voice
		_speaker_gain = -1.0
		if voice >= 0:
			print("[WiiU] GamePad speaker on voice %d" % voice)
			if _mx == null and Engine.has_singleton("MetaXRAudio"):
				_mx = Engine.get_singleton("MetaXRAudio")
			if _mx != null:
				_mx.set_voice_directivity(voice, SpatialAudioEmitter.SPEAKER_DIRECTIVITY)
	if voice < 0 or _mx == null:
		return
	if not is_instance_valid(_listener):
		_listener = get_node_or_null("/root/SpatialAudioListener")
		if _listener == null:
			return
	var listener_pos: Vector3 = _listener.get_listener_position()
	var pos := _speaker.global_position
	var b := _speaker.global_transform.basis
	_mx.set_voice_pose(voice, SpatialAudioEmitter.hold_off_head(pos, listener_pos),
		b.y.normalized(), -b.z.normalized())
	var gain := SpatialAudioEmitter.distance_gain(pos, listener_pos,
		_connected_system.audio_unit_size, _connected_system.audio_max_distance)
	if not is_equal_approx(gain, _speaker_gain):
		_speaker_gain = gain
		_mx.set_voice_gain(voice, gain)
