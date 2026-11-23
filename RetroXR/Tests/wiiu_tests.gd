## Wii U self-tests: the console stand-in, its two pictures, pairing, the GamePad's
## touch screen and motion axes. No core: what reaches Cemu is wiiu_boot_probe's.
##
##     "$godot" --headless --path RetroXR res://Tests/wiiu_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/wiiu_tests.tscn -- --only=pairing
##
## Groups: model views pairing ids touch axes cradle
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const GAMEPAD_SCENE := preload("res://Scenes/Objects/controllers/wiiu/wiiu_gamepad.tscn")
const PRO_SCENE := preload("res://Scenes/Objects/controllers/wiiu/wiiu_pro_controller.tscn")
const WIIMOTE_SCENE := preload("res://Scenes/Objects/controllers/wii/wiimote.tscn")
const CRADLE_SCENE := preload("res://Scenes/Objects/peripherals/wiiu/wiiu_gamepad_cradle.tscn")
const BRICK_SCENE := preload("res://Scenes/Objects/power/power_brick.tscn")

## The frame Cemu packs at 720p: the TV 1280 wide, the GamePad 853 x 480 beside it.
const TV_RECT := Rect2(0.0, 0.0, 1280.0 / 2133.0, 1.0)
const PAD_RECT := Rect2(1280.0 / 2133.0, 0.0, 853.0 / 2133.0, 480.0 / 720.0)

var _only := ""
var _spawned: Array[Node] = []


class TouchStub extends Node3D:
	var touches: Array = []
	func feed_touch(uv: Vector2, pressed: bool) -> void:
		touches.append([uv, pressed])


func _ready() -> void:
	suite_tag = "wiiu"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[wiiu] TIMEOUT")
		get_tree().quit(1))

	if _wants("model"):
		await _test_the_console_is_the_wii_u()
	if _wants("views"):
		await _test_each_picture_takes_its_view()
	if _wants("pairing"):
		await _test_the_gamepad_takes_port_zero()
	if _wants("ids"):
		await _test_remotes_take_cemus_ids_on_a_wii_u_only()
	if _wants("touch"):
		await _test_a_touch_lands_in_the_gamepad_view()
	if _wants("axes"):
		_test_the_gamepad_reads_androids_axes()
		_test_the_gamepad_asks_for_its_core_once_a_power_on()
	if _wants("cradle"):
		await _test_the_cradle_charges_the_gamepad()
	if _wants("speakers"):
		await _test_the_gamepad_plays_in_stereo()
	if _wants("home"):
		await _test_home_reaches_the_wii_u()
	if _wants("menu"):
		_test_an_empty_wii_u_boots_its_menu()
	if _wants("migrate"):
		_test_the_wii_u_moves_to_parallel_gx2()

	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	await _wait(2)
	_finish()


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _console(systemid := "wiiu") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 2.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(6)
	return sys


## A Libretro node's controller-audio calls, recorded: voice 5 is the left, 9 the
## right once stereo is asked for.
class FakeAudioLib extends Node:
	var stereo := {}
	func GetControllerAudioVoiceId(_port: int, _index: int) -> int:
		return 5
	func SetControllerAudioStereo(port: int, index: int, on: bool) -> void:
		stereo[Vector2i(port, index)] = on
	func GetControllerAudioRightVoiceId(port: int, index: int) -> int:
		return 9 if stereo.get(Vector2i(port, index), false) else -1


func _pad(scene: PackedScene) -> Node3D:
	var pad := scene.instantiate() as Node3D
	pad.position = Vector3(0, 2, _spawned.size() * 0.5)
	(pad as RigidBody3D).freeze = true
	add_child(pad)
	_spawned.append(pad)
	await _wait(2)
	return pad


# ── model/ ───────────────────────────────────────────────────────────────────

func _test_the_console_is_the_wii_u() -> void:
	var sys := await _console()
	var model := sys.get_model()
	_ok(model is RetroSystemModelWiiU, "model/a wiiu console wears the Wii U stand-in", str(model))
	var link := sys.get_wii_link()
	_ok(link != null and link.is_wiiu(), "model/it pairs wireless pads, as a Wii U")
	if link != null:
		_eq(link.first_remote_slot(), 1, "model/remotes start at port 1 (0 is the GamePad's)")
		_ok(link.get_sensor_bar_port() != null, "model/it has a SENSOR BAR socket")
	_ok(model.find_child("DCIn", true, false) != null, "model/the AC ADAPTER inlet is a DC mouth")
	var slot := sys.get_node_or_null("CartridgeSlot") as Node3D
	if slot == null:
		slot = sys.find_child("*Slot*", true, false) as Node3D
	if slot != null:
		var at := sys.to_local(slot.global_position)
		_ok(at.z > 0.12 and absf(at.y - 0.0339) < 0.002,
			"model/the disc slot is in the front face, 33.9 mm up", str(at))
	var shown := 0
	for z: Node3D in sys.get_port_zones():
		if z.visible or (z as XRToolsSnapZone).enabled:
			shown += 1
	_eq(shown, 0, "model/no wired controller sockets: every pad is wireless")
	_eq(model.get_forced_core_options().get("cemu_wiimote_pointer", ""), "ir",
		"model/remotes aim through the IR camera")
	_eq(model.get_forced_core_options().get("cemu_gamepad_motion_filter", ""), "exact",
		"model/the GamePad's motion is exact: no bias learning, no slow-turn gate")


# ── views/ ───────────────────────────────────────────────────────────────────

func _test_each_picture_takes_its_view() -> void:
	var sys := await _console()
	var model := sys.get_model() as RetroSystemModelWiiU
	_ok(model.live_video_rect(0) == null, "views/no views: the TV shows the whole frame")
	_ok(model.gamepad_rect() == null, "views/no views: no GamePad window")
	# What GetVideoViews hands over for Cemu's map, a RIGHT eye thrown in to be
	# ignored. Read once so the cache is primed, then laid over it.
	model._refresh_views()
	model._views = [
		{"rect": PAD_RECT, "screen": 1, "eye": 0, "aspect": 16.0 / 9.0},
		{"rect": Rect2(0.5, 0.5, 0.1, 0.1), "screen": 0, "eye": 2, "aspect": 1.0},
		{"rect": TV_RECT, "screen": 0, "eye": 0, "aspect": 16.0 / 9.0},
	]
	_eq(model.live_video_rect(0), TV_RECT, "views/the TV takes screen 0")
	_eq(model.live_video_rect(1), null, "views/only channel 0 is the TV's")
	_eq(model.gamepad_rect(), PAD_RECT, "views/the GamePad takes screen 1")
	# And what a set cabled to it is staged with (get_video_stage's window).
	_eq(sys.video_window(0), TV_RECT, "views/a set cabled to it shows the TV window")
	model._views = []
	_eq(sys.video_window(0), null, "views/and the whole frame again without views")


# ── pairing/ ─────────────────────────────────────────────────────────────────

func _test_the_gamepad_takes_port_zero() -> void:
	var sys := await _console()
	var link := sys.get_wii_link()
	var pad := await _pad(GAMEPAD_SCENE) as WiiUGamePad
	var pro := await _pad(PRO_SCENE) as WiiUProController
	var remote := await _pad(WIIMOTE_SCENE)
	_eq(link.pair(pro), 1, "pairing/a Pro Controller takes port 1, not the GamePad's")
	_eq(link.pair(pad), 0, "pairing/the GamePad takes port 0")
	_eq(link.pair(remote), 2, "pairing/a remote takes the next free port")
	_eq(pad.get_port_index(), 0, "pairing/the GamePad knows its port")
	_eq(pro.get_port_index(), 1, "pairing/so does the Pro Controller")
	var pad2 := await _pad(GAMEPAD_SCENE)
	_eq(link.pair(pad2), -1, "pairing/a second GamePad is refused while port 0 is held")
	link.unpair(pad)
	_eq(pad.get_port_index(), -1, "pairing/SYNC again lets go")
	_eq(link.pair(pad2), 0, "pairing/and port 0 is free for another")
	_eq(link.free_slot(), 3, "pairing/the free ports are 1-3 only")
	# A Wii's remotes still start at 0.
	var wii := await _console("wii")
	_eq(wii.get_wii_link().free_slot(), 0, "pairing/a Wii's first free slot is still 0")


# ── ids/ ─────────────────────────────────────────────────────────────────────

func _test_remotes_take_cemus_ids_on_a_wii_u_only() -> void:
	var wiiu := (await _console()).get_wii_link()
	var wii := (await _console("wii")).get_wii_link()
	var remote := await _pad(WIIMOTE_SCENE)
	var pad := await _pad(GAMEPAD_SCENE)
	# Dolphin's ids are the remote's kind; Cemu's are RETRO_DEVICE_SUBCLASS(JOYPAD, n).
	var want := {1: 257, 513: 1281, 769: 1793, 1793: 2049, 2049: 2305, 2305: 2561}
	for dolphin: int in want:
		_eq(wiiu.wireless_device_id(remote, dolphin), want[dolphin],
			"ids/remote %d is Cemu's %d on a Wii U" % [dolphin, want[dolphin]])
		_eq(wii.wireless_device_id(remote, dolphin), dolphin, "ids/and stays %d on a Wii" % dolphin)
	_eq(wiiu.wireless_device_id(remote, 1281), WiiLink.CEMU_CLASSIC,
		"ids/a mod's extension (a Classic Controller Pro) is Cemu's Classic")
	_eq(wiiu.wireless_device_id(pad, 1), 1, "ids/the GamePad is a plain joypad, untranslated")
	_eq(wiiu.wireless_device_id(pad, WiiLink.CEMU_PRO), WiiLink.CEMU_PRO, "ids/a Pro Controller's id is its own")


# ── touch/ ───────────────────────────────────────────────────────────────────

func _test_a_touch_lands_in_the_gamepad_view() -> void:
	var sys := await _console()
	var pad := await _pad(GAMEPAD_SCENE) as WiiUGamePad
	sys.get_wii_link().pair(pad)
	_ok(pad._touch != null, "touch/a paired GamePad's glass takes touches")
	if pad._touch == null:
		return
	var stub := TouchStub.new()
	add_child(stub)
	_spawned.append(stub)
	pad._touch.host = stub
	pad._touch.uv_rect = PAD_RECT
	var half: Vector2 = pad._touch._size * 0.5
	pad._touch._send_touch_local(Vector2.ZERO, true)
	pad._touch._send_touch_local(Vector2(-half.x, half.y), true)    # top-left of the glass
	pad._touch._send_touch_local(Vector2(half.x, -half.y), false)   # bottom-right, lifted
	_eq(stub.touches.size(), 3, "touch/three touches reached the console")
	if stub.touches.size() == 3:
		var mid: Vector2 = stub.touches[0][0]
		var tl: Vector2 = stub.touches[1][0]
		var br: Vector2 = stub.touches[2][0]
		_ok(mid.is_equal_approx(PAD_RECT.get_center()), "touch/the middle of the glass is the middle of the view", str(mid))
		_ok(tl.is_equal_approx(PAD_RECT.position), "touch/its top-left is the view's", str(tl))
		_ok(br.is_equal_approx(PAD_RECT.end) and stub.touches[2][1] == false,
			"touch/its bottom-right is the view's, released", str(br))
	_ok(is_equal_approx(pad._touch._size.x, WiiUGamePad.SCREEN.x)
		and is_equal_approx(pad._touch._size.y, WiiUGamePad.SCREEN.y),
		"touch/the touch area is the 137.3 x 77.2 mm glass", str(pad._touch._size))


# ── axes/ ────────────────────────────────────────────────────────────────────

class CountingWiiU extends RetroSystem:
	var asked := 0
	var core := "parallel_gx2"
	func resolve_core_name() -> String:
		asked += 1
		return core


func _test_the_gamepad_asks_for_its_core_once_a_power_on() -> void:
	# Asked every physics step, resolve_core_name() (which reads the core defaults
	# file) cost a Quest 76 ms a step and held the room at 6-7 fps.
	var pad := WiiUGamePad.new()
	var sys := CountingWiiU.new()
	sys.is_powered_on = true
	pad._connected_system = sys
	for i in 90:
		pad.reads_android_axes()
	var first := sys.asked
	_ok(first <= 2 and not pad.reads_android_axes(),
		"axes/the core is looked up once, not every step", "asked %d times in 90 steps" % first)
	pad._physics_process(1.0 / 90.0)
	sys.is_powered_on = false
	pad._physics_process(1.0 / 90.0)
	sys.core = "cemu"
	sys.is_powered_on = true
	_ok(pad.reads_android_axes() and sys.asked > first,
		"axes/a power cycle looks again", "asked %d" % sys.asked)
	pad.free()
	sys.free()


func _test_the_gamepad_reads_androids_axes() -> void:
	# At rest the sensor reads +1 g straight up; which Android axis that lands on
	# says which way the pad is held.
	var cases := [
		[Basis.IDENTITY, Vector3(0, 0, 1), "flat, screen up: +Z (out of the screen)"],
		[Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1, 0), "held up, top edge up: +Y"],
		[Basis(Vector3.BACK, -PI * 0.5), Vector3(-1, 0, 0), "rolled onto its left edge: -X"],
	]
	for c: Array in cases:
		var s := MotionSampler.new()
		var xf := Transform3D(c[0] as Basis, Vector3.ZERO)
		for i in 60:
			s.sample(xf, 1.0 / 60.0)
		var got := WiiUGamePad.android_axes(s.accel_local(xf.basis))
		_ok(got.is_equal_approx(c[1] as Vector3) or got.distance_to(c[1] as Vector3) < 0.01,
			"axes/" + String(c[2]), str(got))
	# Turning about the screen's normal (yaw while flat) is Android's Z.
	var spin := MotionSampler.new()
	for i in 30:
		spin.sample(Transform3D(Basis(Vector3.UP, 0.02 * i), Vector3.ZERO), 1.0 / 60.0)
	var w := WiiUGamePad.android_axes(spin.gyro_local(Basis(Vector3.UP, 0.58)))
	_ok(w.z > 1.0 and absf(w.x) < 0.05 and absf(w.y) < 0.05,
		"axes/a flat turn is a spin about Android's Z", str(w))
	# parallel-gx2 reads SDL's controller axes, which are the pad's own: flat,
	# gravity is +Y (out of the face); held up, top edge up, it is -Z (the top
	# edge is -Z, the player +Z); and a flat turn is about Y. Only the old fork
	# gets Android's.
	_ok(not WiiUGamePad.core_reads_android_axes("parallel_gx2") and WiiUGamePad.core_reads_android_axes("cemu"),
		"axes/parallel-gx2 gets SDL's axes, the old Cemu fork Android's")
	for c: Array in [[Basis.IDENTITY, Vector3(0, 1, 0), "flat: +Y"],
			[Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -1), "held up, top edge up: -Z"]]:
		var s2 := MotionSampler.new()
		var xf2 := Transform3D(c[0] as Basis, Vector3.ZERO)
		for i in 60:
			s2.sample(xf2, 1.0 / 60.0)
		var g := s2.accel_local(xf2.basis)
		_ok(g.distance_to(c[1] as Vector3) < 0.01, "axes/SDL " + String(c[2]), str(g))
	var w2 := spin.gyro_local(Basis(Vector3.UP, 0.58))
	_ok(w2.y > 1.0 and absf(w2.x) < 0.05 and absf(w2.z) < 0.05,
		"axes/SDL: a flat turn is a spin about Y", str(w2))
	# A SLOW turn counts too: 0.03 degrees a tick at 90 Hz (2.7 deg/s), tilted
	# off the vertical so every axis has a share. Quaternion.get_angle() read it
	# as exactly 0, and a held GamePad's slow turns never reached the core.
	var slow := MotionSampler.new()
	var axis := Vector3(0.3, 0.9, 0.2).normalized()
	var step := deg_to_rad(0.03)
	var sent := Vector3.ZERO
	for i in 91:
		slow.sample(Transform3D(Basis(axis, step * i), Vector3.ZERO), 1.0 / 90.0)
		if i > 10:
			sent += slow.gyro_world / 90.0
	var want := axis * step * 80.0
	_ok(sent.distance_to(want) < want.length() * 0.05,
		"axes/a slow turn of 0.03 deg a tick reaches the gyro, on its own axis",
		"%s, want %s" % [sent, want])


# ── cradle/ ──────────────────────────────────────────────────────────────────

func _test_the_cradle_charges_the_gamepad() -> void:
	var prefs := get_node("/root/AppPrefs")
	var sim_was: bool = prefs.get("power_simulation")
	prefs.set("power_simulation", false)
	var cradle := CRADLE_SCENE.instantiate() as WiiUGamePadCradle
	cradle.freeze = true
	add_child(cradle)
	_spawned.append(cradle)
	var pad := await _pad(GAMEPAD_SCENE) as WiiUGamePad
	await _wait(3)
	var jack := cradle.get_node_or_null(WiiUGamePadCradle.INLET_NAME) as DcPort
	var top := pad.get_node_or_null(WiiUGamePad.AC_PORT_NAME) as DcPort
	_ok(jack != null and jack.connector == "wiiu_gamepad_dc_plug", "cradle/its back takes the GamePad's adapter")
	_ok(top != null and top.connector == "wiiu_gamepad_dc_plug", "cradle/so does the GamePad's top")
	var brick := BRICK_SCENE.instantiate() as PowerBrick
	brick.brick_id = "wiiu_gamepad_ac_adapter"
	brick.variant = "usa"
	brick.position = Vector3(0.5, 0.3, 0.5)
	add_child(brick)
	brick.add_to_group("spawned")
	_spawned.append(brick)
	await _wait(4)
	_ok(brick.dc_plug != null and brick.dc_plug.is_in_group(jack.snap_require), "cradle/the WUP-011's plug fits it")
	_ok(brick.dc_plug != null and brick.dc_plug.is_in_group(top.snap_require), "cradle/and the GamePad's own port")
	var seat := cradle.get_node("PadSeat") as XRToolsSnapZone
	seat.pick_up_object(pad)
	await _wait(3)
	_ok(cradle.seated_pad() == pad, "cradle/the GamePad seats in it")
	var up := pad.global_transform.basis.y
	_ok(up.z > 0.9 and up.y > 0.1, "cradle/standing on its bottom edge, screen forward, leaning back", str(up))
	var c := cradle.global_position
	_ok(cradle.hand_takes_at(c + Vector3(0.0, 0.07, 0.0)), "cradle/a hand just over it takes it")
	_ok(not cradle.hand_takes_at(c + Vector3(0.11, 0.075, 0.0)), "cradle/a hand on the seated GamePad's grip does not")
	_eq(pad.preview_radius(), 0.07, "cradle/a held GamePad snaps in from 12 cm (seat 5 + 7)")
	_ok(not pad.is_charging(), "cradle/nothing in its jack: no charge")
	jack.pick_up_object(brick.dc_plug)
	await _wait(20)
	_ok(cradle.is_powered() and pad.is_charging(), "cradle/the adapter in: the GamePad charges")
	_ok(pad._charge_mat.emission_enabled, "cradle/its orange lamp is lit")
	# A save records the GamePad in it, and a restore puts it back.
	var sp := ScenePersistence.new()
	var rec: Dictionary = sp.serialize_node(cradle, 1, {pad: 7})
	_eq(str(rec.get("type", "")), "wiiu_gamepad_cradle", "cradle/saved as a cradle")
	_eq(rec.get("gamepad"), 7, "cradle/naming the GamePad in it")
	seat.drop_object()
	await _wait(20)
	_ok(not pad.is_charging(), "cradle/lifted out: no charge")
	_ok(not sp.serialize_node(cradle, 1, {pad: 7}).has("gamepad"), "cradle/an empty cradle names none")
	pad.global_position = cradle.global_position + Vector3(0.6, 0.2, 0.0)
	sp._restore_wiiu_cradle(self, 1, cradle, {7: pad}, rec)
	await _wait(10)
	_ok(cradle.seated_pad() == pad and seat.picked_up_object == pad, "cradle/a restore stands it back in the cradle")
	seat.drop_object()
	await _wait(3)
	prefs.set("power_simulation", sim_was)


# ── speakers/ ────────────────────────────────────────────────────────────────

## The GamePad has two speakers, one by each bottom corner, and plays the
## console's sound for it in stereo: left on the D-pad's side, right on the
## buttons'. Folded to one voice (an older libretro-godot) it plays from between.
func _test_the_gamepad_plays_in_stereo() -> void:
	var pad := await _pad(GAMEPAD_SCENE) as WiiUGamePad
	var l := pad.get_node_or_null("SpeakerL") as Marker3D
	var r := pad.get_node_or_null("SpeakerR") as Marker3D
	_ok(l != null and r != null, "speakers/the GamePad has a left and a right speaker")
	if l == null or r == null:
		return
	_ok(is_equal_approx(l.position.x, -0.0844) and is_equal_approx(r.position.x, 0.0844)
		and is_equal_approx(l.position.z, 0.0541) and is_equal_approx(r.position.z, 0.0541),
		"speakers/at the slots by the bottom corners, 84.4 mm either side, 54.1 mm below the middle",
		"%s %s" % [l.position, r.position])
	# Left is the D-pad's side, which the NFC mark sits under (NFC_AT, -X).
	_ok(signf(l.position.x) == signf(WiiUGamePad.NFC_AT.x), "speakers/the left one is on the D-pad's side")
	_ok(pad.speaker_position(0, true).is_equal_approx(l.global_position)
		and pad.speaker_position(1, true).is_equal_approx(r.global_position),
		"speakers/in stereo each voice plays from its own speaker")
	_ok(pad.speaker_position(0, false).is_equal_approx((l.global_position + r.global_position) * 0.5),
		"speakers/folded to one voice it plays from between the two")
	var lib := FakeAudioLib.new()
	add_child(lib)
	_spawned.append(lib)
	pad._port_index = 0
	pad._update_speaker(lib)
	_ok(lib.stereo.get(Vector2i(0, 0), false) == true, "speakers/the pad asks its console for stereo",
		str(lib.stereo))
	_ok(pad._speaker_voices[0] == 5 and pad._speaker_voices[1] == 9, "speakers/and takes its left and right voices",
		str(pad._speaker_voices))


# ── home/ ────────────────────────────────────────────────────────────────────

## HOME on every Wii U controller that has one to press. The GamePad and the Pro
## Controller have no RetroPad id left, so HOME is RetroXR's joypad id 16, which
## libretro-godot now keeps past the sixteen; a Wii Remote paired with a Wii U
## speaks the Cemu fork's layout, HOME on L, and Dolphin's on a Wii.
func _test_home_reaches_the_wii_u() -> void:
	var wiiu := await _console()
	for scene: PackedScene in [GAMEPAD_SCENE, PRO_SCENE]:
		var pad := await _pad(scene) as WiiUWirelessPad
		var cap: Dictionary = {}
		for b: Dictionary in pad._anim.buttons:
			if (b["node"] as Node).name == &"Home":
				cap = b
		_ok(not cap.is_empty() and int(cap["bit"]) == WiiUWirelessPad.HOME_BIT and WiiUWirelessPad.HOME_BIT == 16,
			"home/the %s's HOME cap presses, on joypad id 16" % pad.name, str(cap.get("bit", "none")))
	# Past the 16: the console's Libretro node keeps bit 16 rather than cutting it off.
	var gp := _spawned[_spawned.size() - 2] as WiiUGamePad
	gp._connected_system = wiiu
	gp._port_index = 0
	var lib := wiiu.get_libretro_node()
	gp._deliver_joypad({"btn": (1 << WiiUWirelessPad.HOME_BIT) | (1 << ControllerBindings.JOYPAD_A),
		"alx": 0, "aly": 0, "arx": 0, "ary": 0})
	var peek: PackedInt32Array = lib.PeekJoypadState(0) if lib != null and lib.has_method("PeekJoypadState") 		else PackedInt32Array()
	_ok(peek.size() > 0 and (peek[0] & (1 << 16)) != 0 and (peek[0] & (1 << ControllerBindings.JOYPAD_A)) != 0,
		"home/libretro-godot keeps HOME (bit 16) beside the RetroPad's buttons", str(peek))
	gp._deliver_joypad({"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": 0})
	gp._connected_system = null
	gp._port_index = -1

	# The Wii Remote: the Cemu fork's buttons on a Wii U, Dolphin's on a Wii.
	var up := Wiimote.cemu_bits(false, false)
	_ok(up["home"] == ControllerBindings.JOYPAD_L and up["a"] == ControllerBindings.JOYPAD_B
		and up["b"] == ControllerBindings.JOYPAD_A and up["one"] == ControllerBindings.JOYPAD_Y
		and up["two"] == ControllerBindings.JOYPAD_X and not up.has("shake"),
		"home/a remote on a Wii U: HOME on L, A on B, B on A, 1 on Y, 2 on X (libretro_map_wiimote)")
	var nc := Wiimote.cemu_bits(true, false)
	_ok(nc["one"] == ControllerBindings.JOYPAD_L2 and nc["two"] == ControllerBindings.JOYPAD_R2
		and nc["home"] == ControllerBindings.JOYPAD_L, "home/with a Nunchuk 1 and 2 move to L2 and R2 (libretro_map_nunchuk)")
	var side := Wiimote.cemu_bits(false, true)
	_ok(side["two"] == ControllerBindings.JOYPAD_B and side["one"] == ControllerBindings.JOYPAD_A
		and side["right"] == ControllerBindings.JOYPAD_UP and side["home"] == ControllerBindings.JOYPAD_L,
		"home/sideways: 2 on B, 1 on A, the cross a quarter turn")
	var remote := await _pad(WIIMOTE_SCENE) as Wiimote
	remote._connected_system = wiiu
	_ok(remote._button_mask({"home": true}) == 1 << ControllerBindings.JOYPAD_L,
		"home/a remote paired with a Wii U sends HOME on L", str(remote._button_mask({"home": true})))
	var wii := await _console("wii")
	remote._connected_system = wii
	_ok(remote._button_mask({"home": true}) == 1 << ControllerBindings.JOYPAD_R3,
		"home/and on a Wii still Dolphin's R3", str(remote._button_mask({"home": true})))
	remote._connected_system = null


# ── menu/ ────────────────────────────────────────────────────────────────────

## With no disc a Wii U boots its Wii U Menu: BiosBoot's parallel_gx2/wiiu row (and
## the old Cemu fork's cemu/wiiu) starts the
## core with NO content, gated on the menu being in the core's mlc01, and the
## fork boots the first region's men.rpx it finds (US, EU, JP), as this does.
func _test_an_empty_wii_u_boots_its_menu() -> void:
	for core: String in ["parallel_gx2", "cemu"]:
		_ok(BiosBoot.boots_with_no_content(core, "wiiu"), "menu/a Wii U on %s starts with no content" % core)
		_ok(BiosBoot.empty_media_extension(core, "wiiu").is_empty(), "menu/and no blank disc stands in (%s)" % core)
		_ok(bool(BiosBoot.entry(core, "wiiu").get("wiiu_menu", false)),
			"menu/gated on the installed Wii U Menu, not on a firmware file (%s)" % core)
	_ok(WiiUSystemMenu.mlc_dir().ends_with("save/parallel_gx2/Cemu/mlc01"), "menu/parallel-gx2's own mlc01",
		WiiUSystemMenu.mlc_dir())
	var mlc := "user://wiiu_menu_test/mlc01"
	DirAccess.make_dir_recursive_absolute(mlc)
	_ok(WiiUSystemMenu.menu_path_in(mlc).is_empty() and WiiUSystemMenu.installed_region_in(mlc).is_empty(),
		"menu/an mlc01 with no menu has none")
	for id: String in ["10040000", "10040200"]:
		var code := mlc.path_join("sys/title/00050010/%s/code" % id)
		DirAccess.make_dir_recursive_absolute(code)
		FileAccess.open(code.path_join("men.rpx"), FileAccess.WRITE).store_8(0)
	_ok(WiiUSystemMenu.installed_region_in(mlc) == "EUR", "menu/EU before JP, as the fork tries them",
		WiiUSystemMenu.installed_region_in(mlc))
	var us := mlc.path_join("sys/title/00050010/10040100/code")
	DirAccess.make_dir_recursive_absolute(us)
	FileAccess.open(us.path_join("men.rpx"), FileAccess.WRITE).store_8(0)
	_ok(WiiUSystemMenu.installed_region_in(mlc) == "USA"
		and WiiUSystemMenu.menu_path_in(mlc).ends_with("10040100/code/men.rpx"),
		"menu/US first", WiiUSystemMenu.menu_path_in(mlc))
	OS.move_to_trash(ProjectSettings.globalize_path("user://wiiu_menu_test"))
	# The Wii's row is unchanged: its gate is Dolphin's NAND.
	_ok(bool(BiosBoot.entry("dolphin", "wii").get("wii_menu", false))
		and not bool(BiosBoot.entry("dolphin", "wii").get("wiiu_menu", false)),
		"menu/a Wii still asks for its own System Menu")


# ── migrate/ ─────────────────────────────────────────────────────────────────

## The Wii U moved from the Cemu fork to parallel-gx2: the old core's mlc01 is
## MOVED to the new one's where it has none, its system files copied where the new
## one lacks them, and nothing of the new core's is ever overwritten.
func _test_the_wii_u_moves_to_parallel_gx2() -> void:
	var root := ProjectSettings.globalize_path("user://wiiu_migrate_test")
	OS.move_to_trash(root) if DirAccess.dir_exists_absolute(root) else OK
	var save := root.path_join("save")
	var sys := root.path_join("system")
	var put := func(path: String, text: String) -> void:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	put.call(save.path_join("cemu/Cemu/mlc01/usr/save/00050000/10102000/user/common/save.dat"), "nintendo land")
	put.call(sys.path_join("cemu/Cemu/cafeLibs/swkbd.rpl"), "keyboard")
	put.call(sys.path_join("cemu/Cemu/keys.txt"), "old keys")
	put.call(sys.path_join("parallel_gx2/Cemu/keys.txt"), "new keys")
	var report := WiiUCoreMigration.run(save, sys)
	_ok(FileAccess.get_file_as_string(save.path_join("parallel_gx2/Cemu/mlc01/usr/save/00050000/10102000/user/common/save.dat")) == "nintendo land"
		and not DirAccess.dir_exists_absolute(save.path_join("cemu/Cemu/mlc01")),
		"migrate/the old core's mlc01 is moved to parallel-gx2's", str(report))
	_ok(FileAccess.get_file_as_string(sys.path_join("parallel_gx2/Cemu/cafeLibs/swkbd.rpl")) == "keyboard",
		"migrate/the native keyboard (cafeLibs) is copied across")
	_ok(FileAccess.get_file_as_string(sys.path_join("parallel_gx2/Cemu/keys.txt")) == "new keys",
		"migrate/a file the new core already has is not overwritten")
	_ok(WiiUCoreMigration.run(save, sys).is_empty(), "migrate/run again, there is nothing left to do")
	# Both cores holding an mlc01: neither is touched.
	put.call(save.path_join("cemu/Cemu/mlc01/x.dat"), "old")
	var both := WiiUCoreMigration.run(save, sys)
	_ok(FileAccess.file_exists(save.path_join("cemu/Cemu/mlc01/x.dat"))
		and not FileAccess.file_exists(save.path_join("parallel_gx2/Cemu/mlc01/x.dat"))
		and str(both).contains("both cores"), "migrate/two mlc01s are both left as they are, and said", str(both))
	OS.move_to_trash(root)
