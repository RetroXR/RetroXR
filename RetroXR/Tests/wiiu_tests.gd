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
	if _wants("cradle"):
		await _test_the_cradle_charges_the_gamepad()

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
