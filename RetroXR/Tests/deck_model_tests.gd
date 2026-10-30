## The RETRO XR decks dressed with their models (ApplianceModel, DeckFace): the keys adopted onto the model's keys
## on the front panel, the phono sockets on its jacks, the vacuum fluorescent display over its display window, and
## the VCR's mechanism carrying a tape through its door and down onto its reels along the model's own contract.
##
##   godot --headless --path RetroXR res://Tests/deck_model_tests.tscn
##   godot --headless --path RetroXR res://Tests/deck_model_tests.tscn -- --only=vcr/tape
##
## Exits non-zero if anything fails. How the decks LOOK is Tools/av/deck_model_probe, windowed.
extends "res://Tests/test_suite.gd"

const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const TAPE_SCENE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const DVD_SCENE := preload("res://Scenes/Objects/appliances/dvd_player.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/dvd_disc.tscn")
const VCR_KEYS := {"PlayButton": "ButtonPlay", "PauseButton": "ButtonPause", "StopButton": "ButtonStop",
	"RewindButton": "ButtonRewind", "FastForwardButton": "ButtonFastForward", "EjectButton": "ButtonEject",
	"RecordButton": "ButtonRecord", "PowerButton": "ButtonPower"}

var _case := ""
var _failed_cases := {}
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "deckmodel"
	quiet_passes = true
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[deckmodel] TIMEOUT during '%s'" % _case)
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.split("=")[1]
	var cases: Array = [
		["vcr/dress/the keys are the model's, on the front, facing out", _vcr_keys],
		["vcr/dress/the sockets are on the model's jacks", _vcr_ports],
		["vcr/dress/the display window carries the VFD", _vcr_display],
		["vcr/vfd/the display redraws when what it shows changes, and only then", _vcr_vfd],
		["vcr/tape/a restored tape lies seated on the reels, its flap open", _vcr_restore],
		["vcr/tape/eject carries it out to the mouth, its flap shut", _vcr_eject],
		["vcr/tape/a tape let go at the mouth is carried in through the door", _vcr_load],
		["vcr/door/a held tape pushes the flap, which falls shut behind it", _vcr_hand_door],
		["dvd/dress/the keys are the model's, on the front, facing out", _dvd_keys],
		["dvd/dress/the sockets are on the model's jacks", _dvd_ports],
		["dvd/tray/an empty tray opens and closes, taking a disc only while out", _dvd_tray_empty],
		["dvd/tray/a disc laid on the open tray rides in, and out again on OPEN/CLOSE", _dvd_tray_disc],
		["dvd/tray/a restored disc lies in the shut tray", _dvd_restore],
		["dvd/vfd/the display names the tray and the disc", _dvd_vfd],
	]
	print("[deckmodel] running %d cases%s" % [cases.size(), "" if only.is_empty() else " matching '%s'" % only])
	for c: Array in cases:
		var case_name: String = c[0]
		if not only.is_empty() and not case_name.contains(only):
			continue
		_case = case_name
		var before := _case_count()
		await (c[1] as Callable).call()
		await _teardown()
		if _case_count() == before:
			_ok(false, "%s made no assertions — it aborted part way" % case_name)
		elif not _failed_cases.has(case_name):
			print("[deckmodel] PASS  %s" % case_name)
	print("[deckmodel] %d case(s) failed" % _failed_cases.size())
	_finish()


func _on_fail(_what: String) -> void:
	_failed_cases[_case] = true
	print("[deckmodel]         in case %s" % _case)


func _teardown() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _vcr() -> VCRPlayer:
	var vcr := VCR_SCENE.instantiate() as VCRPlayer
	vcr.freeze = true
	vcr.position = Vector3(_spawned.size() * 2.0, 1, 0)
	add_child(vcr)
	_spawned.append(vcr)
	return vcr


func _tape() -> VCRTape:
	var tape := TAPE_SCENE.instantiate() as VCRTape
	tape.freeze = true
	tape.position = Vector3(_spawned.size() * 2.0, 3, 3)
	add_child(tape)
	_spawned.append(tape)
	return tape


## A node's transform in the deck's frame.
func _local(vcr: Node3D, n: Node3D) -> Transform3D:
	return vcr.global_transform.affine_inverse() * n.global_transform


func _contract(vcr: VCRPlayer) -> Dictionary:
	return vcr._contract


# ── VCR ──────────────────────────────────────────────────────────────────────

func _vcr_keys() -> void:
	var vcr := _vcr()
	await _frames(2)
	var model := vcr.get_node("Model") as ApplianceModel
	_eq(model.levels.size(), 3, "the model's three levels are built")
	for button_name: String in VCR_KEYS:
		var b := vcr.get_node(button_name) as VRButton
		var key := model.part(VCR_KEYS[button_name]) as MeshInstance3D
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		_ok(cap.visible and cap.mesh == key.mesh, "%s wears the model's %s" % [button_name, key.name])
		_ok(not key.visible, "%s: the model's own key is hidden, so it is not drawn twice" % button_name)
		_ok(_local(vcr, b).origin.distance_to(_local(vcr, key).origin) < 0.0005,
			"%s sits on the key's face (got %s)" % [button_name, _local(vcr, b).origin])
		_ok(_local(vcr, b).basis.y.normalized().dot(Vector3.BACK) > 0.999,
			"%s faces out of the front, along its +Y like every cap" % button_name)
		var press := _local(vcr, b).basis * b.depress_axis
		_ok(press.normalized().dot(Vector3.FORWARD) > 0.999, "%s presses into the front" % button_name)
	var play := _local(vcr, vcr.get_node("PlayButton") as Node3D).origin
	var pause := _local(vcr, vcr.get_node("PauseButton") as Node3D).origin
	_ok(play.x < pause.x and absf(play.y - pause.y) < 0.0005 and play.z > 0.135,
		"PLAY is left of PAUSE in one row, standing proud of the 135 mm face")


func _vcr_ports() -> void:
	var vcr := _vcr()
	await _frames(2)
	for spec: Array in [["VideoOut", 0.082], ["AudioLOut", 0.100], ["AudioROut", 0.118]]:
		var port := vcr.get_node(spec[0]) as Node3D
		var t := _local(vcr, port)
		_ok(t.origin.distance_to(Vector3(spec[1], 0.0, -0.145)) < 0.0005,
			"%s 10 mm proud of the model's jack (got %s)" % [spec[0], t.origin])
		_ok(t.basis.z.normalized().dot(Vector3.FORWARD) > 0.999, "%s: its +Z points out of the back" % spec[0])
		_ok(not bool(port.get("show_jack")), "%s draws no jack over the model's" % spec[0])


func _vcr_display() -> void:
	var vcr := _vcr()
	await _frames(2)
	var model := vcr.get_node("Model") as ApplianceModel
	for d in model.parts("Display"):
		_ok(not d.visible, "the model's black display panel is hidden (%s)" % d.get_path())
	var vfd := vcr.get_node_or_null("Vfd") as VfdDisplay
	_ok(vfd != null, "a VfdDisplay is on the deck")
	if vfd == null:
		return
	var at := _local(vcr, vfd)
	_ok(at.origin.distance_to(Vector3(0.105, 0.0155, 0.1314)) < 0.0005, "over the display window (got %s)" % at.origin)
	_ok(vfd.size_m.is_equal_approx(Vector2(0.126, 0.025)), "the size of the model's 126 x 25 mm panel")
	_ok(not (vcr.get_node("VCRClock") as Node3D).visible, "the old clock is not drawn")


func _vcr_vfd() -> void:
	var vcr := _vcr()
	await _frames(2)
	vcr._update_vfd()
	var empty := vcr._vfd_key
	_ok(not bool(vcr._vfd_state.get("tape", true)) and float(vcr._vfd_state.get("secs", 0.0)) < 0.0,
		"no tape: no counter, the cassette unlit")
	var tape := _tape()
	tape.tape_time = 65.4
	vcr.restore_media(tape)
	vcr._update_vfd()
	_ok(vcr._vfd_key != empty and bool(vcr._vfd_state["tape"]) and int(vcr._vfd_state["secs"]) == 65,
		"a tape in at 1:05: the counter reads it and the cassette lights (state %s)" % vcr._vfd_state)
	var key := vcr._vfd_key
	tape.tape_time = 65.9
	vcr._update_vfd()
	_eq(vcr._vfd_key, key, "the same second: nothing to redraw")
	tape.tape_time = 66.0
	vcr._update_vfd()
	_ok(vcr._vfd_key != key, "the next second: redrawn")
	vcr._on_power_pressed()
	vcr._update_vfd()
	_ok(not vcr._power_on and vcr._vfd_key.begins_with("0|"), "POWER puts the display to standby")
	var led := (vcr.get_node("Model") as ApplianceModel).part("PowerLed") as MeshInstance3D
	_ok(led.material_override == vcr._led_off_mat, "and the lamp goes out")
	vcr._on_power_pressed()
	_ok(vcr._power_on and led.material_override == vcr._led_on_mat, "and both come back")


func _vcr_restore() -> void:
	var vcr := _vcr()
	await _frames(2)
	var tape := _tape()
	vcr.restore_media(tape)
	await _frames(2)
	var rows: Array = _contract(vcr)["load"]
	var want: Array = (rows[-1] as Dictionary)["tape_center"]
	var t := _local(vcr, tape)
	_ok(t.origin.distance_to(Vector3(want[0], want[1], want[2])) < 0.0005,
		"seated where the model's Load ends (got %s, want %s)" % [t.origin, want])
	_ok(t.basis.z.normalized().dot(Vector3.UP) > 0.999 and t.basis.y.normalized().dot(Vector3.FORWARD) > 0.999,
		"flat, its top up and its flap into the deck")
	_ok(absf(t.origin.x + 0.07) < 0.001 and t.origin.z < 0.135 - 0.052 and t.origin.y < 0.0,
		"inside the body, its spine behind the front, lowered onto the reels")
	var cassette := tape.get_node("Cassette") as VhsCassette
	_ok(is_equal_approx(cassette.door_open, 1.0), "its own flap is open on the reels")
	var door := (vcr.get_node("Model") as ApplianceModel).part("Door")
	_ok(absf(door.rotation.x) < 0.01, "the deck's flap is shut in front of it")
	_ok(not tape.enabled, "and no hand can take it out of the deck")


func _vcr_eject() -> void:
	var vcr := _vcr()
	await _frames(2)
	var tape := _tape()
	vcr.restore_media(tape)
	await _frames(2)
	vcr._on_eject_pressed()
	_ok(vcr._ride_media == tape, "EJECT starts the mechanism")
	_ok(await _wait_until(func() -> bool: return vcr._ride_media == null, 6.0), "and it finishes")
	var t := _local(vcr, tape)
	var slot := _local(vcr, vcr.get_node("TapeSlot") as Node3D)
	_ok(t.origin.distance_to(slot.origin) < 0.0005, "parked at the mouth, 35 mm of spine out (got %s)" % t.origin)
	_ok(t.origin.z + 0.052 > 0.135 + 0.03, "its spine stands out of the front")
	_ok(is_equal_approx((tape.get_node("Cassette") as VhsCassette).door_open, 0.0), "its own flap shut again")
	_ok(tape.enabled, "and a hand can take it")
	var door := (vcr.get_node("Model") as ApplianceModel).part("Door")
	_ok(rad_to_deg(door.rotation.x) > 70.0, "the deck's flap rides on it (%.1f deg)" % rad_to_deg(door.rotation.x))


func _vcr_load() -> void:
	var vcr := _vcr()
	await _frames(2)
	var tape := _tape()
	vcr._slot._accept(tape, false)
	_ok(vcr._ride_media == tape and vcr._ride_anim == "Load", "the slot hands it to the mechanism")
	var start := _local(vcr, tape).origin
	var slot := _local(vcr, vcr.get_node("TapeSlot") as Node3D).origin
	_ok(start.distance_to(slot) < 0.0005, "which takes it where the holder grips it, at the mouth")
	var door := (vcr.get_node("Model") as ApplianceModel).part("Door")
	var widest := 0.0
	var deadline := Time.get_ticks_msec() + 6000
	while vcr._ride_media != null and Time.get_ticks_msec() < deadline:
		widest = maxf(widest, rad_to_deg(door.rotation.x))
		await get_tree().process_frame
	_ok(vcr._ride_media == null, "the load finishes")
	_ok(widest > 70.0, "the flap was pushed open as the tape went through (%.1f deg)" % widest)
	_ok(absf(door.rotation.x) < 0.01, "and fell shut behind it")
	var rows: Array = _contract(vcr)["load"]
	var want: Array = (rows[-1] as Dictionary)["tape_center"]
	_ok(_local(vcr, tape).origin.distance_to(Vector3(want[0], want[1], want[2])) < 0.0005,
		"the tape ends seated on the reels")
	_ok(vcr._slot.is_media_seated(), "and the slot calls it seated")


func _vcr_hand_door() -> void:
	var vcr := _vcr()
	await _frames(2)
	var door := (vcr.get_node("Model") as ApplianceModel).part("Door")
	var slot := _local(vcr, vcr.get_node("TapeSlot") as Node3D).origin
	var tape := _tape()
	# Held flat, flap first, half way from touching the flap to the holder's grip (34 mm in).
	var seat := Basis(Vector3.RIGHT, -PI / 2.0)
	tape.global_transform = vcr.global_transform * Transform3D(seat, slot + Vector3(0, 0, 0.0345))
	vcr._follow_hand(1.0 / 60.0)
	var held := rad_to_deg(door.rotation.x)
	_ok(held > 60.0 and held < 85.0, "the flap stands open on the held tape (%.1f deg)" % held)
	# Turned round, spine first: it does not push the flap.
	var other := _vcr()
	await _frames(2)
	var other_door := (other.get_node("Model") as ApplianceModel).part("Door")
	tape.global_transform = other.global_transform * Transform3D(Basis(Vector3.UP, PI) * seat,
		slot + Vector3(0, 0, 0.0345))
	other._follow_hand(1.0 / 60.0)
	_ok(absf(other_door.rotation.x) < 0.01, "a tape held spine first leaves the flap shut")
	# Taken away: the flap falls, not jumps.
	tape.global_position += Vector3(0, 2, 0)
	vcr._follow_hand(0.05)
	var falling := rad_to_deg(door.rotation.x)
	_ok(falling > 0.0 and falling < held, "the flap falls when the tape is gone (%.1f deg)" % falling)
	vcr._follow_hand(1.0)
	_ok(absf(door.rotation.x) < 0.01, "and lies shut")


# ── DVD ──────────────────────────────────────────────────────────────────────

func _dvd() -> DVDPlayer:
	var dvd := DVD_SCENE.instantiate() as DVDPlayer
	dvd.freeze = true
	dvd.position = Vector3(_spawned.size() * 2.0, 1, 0)
	add_child(dvd)
	_spawned.append(dvd)
	return dvd


func _disc() -> DVDDisc:
	var disc := DISC_SCENE.instantiate() as DVDDisc
	disc.freeze = true
	disc.position = Vector3(_spawned.size() * 2.0, 3, 3)
	add_child(disc)
	_spawned.append(disc)
	return disc


## Run the player's tray to the end of whatever it is doing.
func _settle(dvd: DVDPlayer) -> bool:
	return await _wait_until(func() -> bool: return dvd._tray_anim == "", 5.0)


func _tray_z(dvd: DVDPlayer) -> float:
	return _local(dvd, (dvd.get_node("Model") as ApplianceModel).part("Tray")).origin.z


func _dvd_keys() -> void:
	var dvd := _dvd()
	await _frames(2)
	var model := dvd.get_node("Model") as ApplianceModel
	for button_name: String in DVDPlayer.KEYS:
		var b := dvd.get_node(button_name) as VRButton
		var key := model.part(DVDPlayer.KEYS[button_name]) as MeshInstance3D
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		_ok(cap.visible and cap.mesh == key.mesh and not key.visible, "%s wears the model's %s" % [button_name, key.name])
		_ok(_local(dvd, b).origin.distance_to(_local(dvd, key).origin) < 0.0005, "%s sits on the key's face" % button_name)
		_ok(_local(dvd, b).basis.y.normalized().dot(Vector3.BACK) > 0.999, "%s faces out of the front" % button_name)
	var at := func(n: String) -> Vector3: return _local(dvd, dvd.get_node(n) as Node3D).origin
	_ok(at.call("UpButton").y > at.call("SelectButton").y and at.call("SelectButton").y > at.call("DownButton").y,
		"the pad: UP over ENTER over DOWN")
	_ok(at.call("LeftButton").x < at.call("SelectButton").x and at.call("SelectButton").x < at.call("RightButton").x,
		"and LEFT, ENTER, RIGHT across")
	_ok(at.call("PrevChapterButton").x < at.call("PlayButton").x and at.call("PlayButton").x < at.call("NextChapterButton").x,
		"the transport row reads |<< ... PLAY ... >>| left to right")
	_ok(at.call("EjectButton").x < at.call("PlayButton").x, "OPEN/CLOSE stands by the tray, left of the transport")


func _dvd_ports() -> void:
	var dvd := _dvd()
	await _frames(2)
	for spec: Array in [["VideoOut", 0.082], ["AudioLOut", 0.100], ["AudioROut", 0.118]]:
		var port := dvd.get_node(spec[0]) as Node3D
		var t := _local(dvd, port)
		_ok(t.origin.distance_to(Vector3(spec[1], 0.0, -0.155)) < 0.0005,
			"%s 10 mm proud of the model's jack (got %s)" % [spec[0], t.origin])
		_ok(t.basis.z.normalized().dot(Vector3.FORWARD) > 0.999, "%s: its +Z points out of the back" % spec[0])


func _dvd_tray_empty() -> void:
	var dvd := _dvd()
	await _frames(2)
	var shut := _tray_z(dvd)
	var slot := dvd.get_node("DiscSlot") as XRToolsSnapZone
	_ok(not dvd.is_tray_open() and not slot.enabled, "it starts shut, and the slot takes nothing")
	dvd._on_eject_pressed()
	_ok(await _settle(dvd), "OPEN/CLOSE runs the tray out")
	_ok(absf(_tray_z(dvd) - shut - 0.14) < 0.001, "140 mm out (moved %.4f)" % (_tray_z(dvd) - shut))
	_ok(dvd.is_tray_open() and slot.enabled, "and the slot takes a disc there")
	var seat := _local(dvd, (dvd.get_node("Model") as ApplianceModel).part("DiscSeat")).origin
	_ok(_local(dvd, slot).origin.distance_to(seat + Vector3(0, 0.002, 0)) < 0.0005,
		"the slot is on the tray's seat (got %s, seat %s)" % [_local(dvd, slot).origin, seat])
	_ok(seat.z - 0.06 > 0.145, "a disc there is all outside the 145 mm front")
	dvd._on_eject_pressed()
	_ok(await _settle(dvd), "OPEN/CLOSE runs it back in")
	_ok(absf(_tray_z(dvd) - shut) < 0.001 and not slot.enabled, "shut again, and the slot takes nothing")


func _dvd_tray_disc() -> void:
	var dvd := _dvd()
	await _frames(2)
	dvd._on_eject_pressed()
	await _settle(dvd)
	var disc := _disc()
	dvd._slot._accept(disc, false)
	_ok(dvd._tray_anim == "Close", "a disc laid on the open tray closes it")
	await _settle(dvd)
	var seat := _local(dvd, (dvd.get_node("Model") as ApplianceModel).part("DiscSeat")).origin
	_ok(_local(dvd, disc).origin.distance_to(seat + Vector3(0, 0.002, 0)) < 0.0005,
		"the disc rode in on the seat (got %s, seat %s)" % [_local(dvd, disc).origin, seat])
	_ok(seat.z < 0.145 - 0.06, "and is all inside the player")
	_ok(dvd.has_media() and dvd._slot.is_media_seated() and not disc.enabled, "loaded, out of a hand's reach")
	dvd._on_eject_pressed()
	_ok(dvd._tray_anim == "Open", "OPEN/CLOSE takes it out")
	await _settle(dvd)
	_ok(_local(dvd, disc).origin.z - 0.06 > 0.145 and disc.enabled and dvd._slot.is_parked(),
		"out on the tray, where a hand can take it")
	dvd._on_eject_pressed()
	await _settle(dvd)
	_ok(dvd._slot.is_media_seated() and _local(dvd, disc).origin.z < 0.085, "and OPEN/CLOSE again takes it back in")


func _dvd_restore() -> void:
	var dvd := _dvd()
	await _frames(2)
	var shut := _tray_z(dvd)
	var disc := _disc()
	dvd.restore_media(disc, 0.7)
	await _settle(dvd)
	_ok(absf(_tray_z(dvd) - shut) < 0.001 and not dvd.is_tray_open(), "the tray stays shut")
	var seat := _local(dvd, (dvd.get_node("Model") as ApplianceModel).part("DiscSeat")).origin
	_ok(_local(dvd, disc).origin.distance_to(seat + Vector3(0, 0.002, 0)) < 0.0005, "the disc lies in it")
	_ok(absf(dvd.disc_seat_yaw() - 0.7) < 0.01, "at the spin it was saved at (got %.3f)" % dvd.disc_seat_yaw())


func _dvd_vfd() -> void:
	var dvd := _dvd()
	await _frames(2)
	dvd._update_vfd()
	_eq(dvd._vfd_state.get("word"), "NO DISC", "shut and empty")
	dvd._on_eject_pressed()
	dvd._update_vfd()
	_eq(dvd._vfd_state.get("word"), "OPEN", "the tray going out")
	await _settle(dvd)
	var disc := _disc()
	dvd._slot._accept(disc, false)
	dvd._update_vfd()
	_eq(dvd._vfd_state.get("word"), "CLOSE", "the tray coming in")
	await _settle(dvd)
	dvd._update_vfd()
	_eq(dvd._vfd_state.get("word"), "LOADING", "a disc just taken in")
	dvd._loading_until = 0
	dvd._update_vfd()
	_eq(dvd._vfd_state.get("word"), "STOP", "and then a disc that is not playing")
	var key := dvd._vfd_key
	dvd._update_vfd()
	_eq(dvd._vfd_key, key, "nothing changed: nothing to redraw")
