## Combination sets — a VCR or DVD player built into a television's cabinet.
##
## A cabinet names a deck with a VcrSeat / DvdSeat marker (RetroTVShell) and the
## set builds it (TvDecks): the ordinary deck, made part of the set, on the
## composite input after the cabinet's phono row. These cases pin what that
## promises: which input, what SOURCE calls it, that the deck is the set's and not
## a loose object (no body, no lead, saved on the set, named through the set on
## the wire), and that its buttons come out where the cabinet says.
##
##   godot --headless --path RetroXR res://Tests/combo_tv_tests.tscn
##   godot --headless --path RetroXR res://Tests/combo_tv_tests.tscn -- --only=save
##
## Exits non-zero if anything fails. How a combination set LOOKS is
## Tools/av/combo_tv_probe, windowed.
extends "res://Tests/test_suite.gd"

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const TAPE_SCENE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/dvd_disc.tscn")
const COMBO_SHELL := "res://Tests/fixtures/combo_tv_shell.tscn"
## The fixture with its phono row widened to three, written out at run time, so
## the second deck has no input left.
const CROWDED_SHELL := "user://combo_tv_tests_crowded_shell.tscn"
const COMBO_ID := "combo_tv_tests:combo"
const CROWDED_ID := "combo_tv_tests:crowded"


## NetworkManager reduced to what NetObjectSync asks of its parent.
class StubNM extends Node:
	var world: Node = null
	func is_host() -> bool: return true
	func is_client() -> bool: return false
	func is_active() -> bool: return false
	func world_root_node() -> Node: return world


var _case := ""
var _failed_cases := {}
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "combo"
	# A check prints only when it fails; each CASE prints its PASS below.
	quiet_passes = true
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[combo] TIMEOUT during '%s'" % _case)
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.split("=")[1]

	_check_eq(RetroTV.register_mod_shell(COMBO_ID, COMBO_SHELL, "Combo", "combo_tv_tests"),
		"", "the fixture cabinet registers")
	_write_crowded_shell()
	_check_eq(RetroTV.register_mod_shell(CROWDED_ID, CROWDED_SHELL, "Crowded", "combo_tv_tests"),
		"", "the crowded cabinet registers")

	var cases: Array = [
		["deck/the cabinet's decks take the inputs after its phono row", _d_inputs],
		["deck/a set without the markers builds no deck", _d_none],
		["deck/a deck with no input left is left out", _d_crowded],
		["deck/a built-in deck is no pickable, no body and no lead", _d_not_loose],
		["deck/moving the set carries its decks", _d_carried],
		["source/SOURCE stops on each deck, by its name", _s_cycle],
		["source/the deck's input has no sockets to fight it", _s_no_sockets],
		["display/the selected deck is the input's host", _v_host],
		["audio/only the selected deck is heard", _a_selected],
		["controls/each panel stands up on the front, its layout kept", _c_front],
		["save/the media in both decks survives a save and a load", _p_round_trip],
		["save/a set saves no loose copy of its decks", _p_no_copy],
		["net/a built-in deck is named through its set", _n_named],
	]

	print("[combo] running %d cases%s" % [cases.size(),
		"" if only.is_empty() else " matching '%s'" % only])
	for c: Array in cases:
		var name: String = c[0]
		if not only.is_empty() and not name.contains(only):
			continue
		_case = name
		var before := _case_count()
		await (c[1] as Callable).call()
		await _teardown()
		if _case_count() == before:
			_ok(false, "%s made no assertions — it aborted part way" % name)
		elif not _failed_cases.has(name):
			print("[combo] PASS  %s" % name)

	RetroTV.drop_mod_shells("combo_tv_tests")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CROWDED_SHELL))
	print("[combo] %d case(s) failed" % _failed_cases.size())
	_finish()


# ── Checks ────────────────────────────────────────────────────────────────────

## TestSuite._ok has printed the check; name the case it was in.
func _on_fail(_what: String) -> void:
	_failed_cases[_case] = true
	print("[combo]         in case %s" % _case)


func _check_eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s: got %s, want %s" % [what, got, want])


# ── Building a room ───────────────────────────────────────────────────────────

func _tv(model: String = COMBO_ID) -> RetroTV:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.tv_model = model
	tv.freeze = true
	tv.position = Vector3(_spawned.size() * 3.0, 1, 0)
	add_child(tv)
	tv.add_to_group("spawned")
	_spawned.append(tv)
	return tv


func _media(scene: PackedScene) -> Node3D:
	var media := scene.instantiate() as Node3D
	(media as RigidBody3D).freeze = true
	media.position = Vector3(_spawned.size() * 3.0, 1, 2)
	add_child(media)
	media.add_to_group("spawned")
	_spawned.append(media)
	return media


func _vcr(tv: RetroTV) -> VCRPlayer:
	return tv.decks().deck_of_kind("vcr") as VCRPlayer


func _dvd(tv: RetroTV) -> DVDPlayer:
	return tv.decks().deck_of_kind("dvd") as DVDPlayer


## The fixture with three phono inputs: Composite 1-3, then the VCR on the last
## composite input and no room for the DVD.
func _write_crowded_shell() -> void:
	var shell := (load(COMBO_SHELL) as PackedScene).instantiate() as RetroTVShell
	shell.av_inputs = 3
	for child in shell.get_children():
		child.owner = shell
	var packed := PackedScene.new()
	packed.pack(shell)
	ResourceSaver.save(packed, CROWDED_SHELL)
	shell.free()


func _teardown() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)


func _wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


# ── deck/ ─────────────────────────────────────────────────────────────────────

func _d_inputs() -> void:
	var tv := _tv()
	await _wait(5)
	_check_eq(tv.panel().panel_inputs(), 1, "the fixture keeps one phono row")
	_ok(tv.decks().deck_on(0) == null, "Composite 1 is the phono row's, not a deck's")
	_ok(tv.decks().deck_on(1) is VCRPlayer, "the VCR is on the input after it")
	_ok(tv.decks().deck_on(2) is DVDPlayer, "and the DVD player on the one after that")
	_ok(tv.decks().deck_on(3) == null, "and nothing on the last")
	_check_eq(tv.decks().decks().size(), 2, "two decks, in input order")
	_check_eq(_vcr(tv).name, &"BuiltInVcr", "the VCR's node name, which is its address")
	_check_eq(_dvd(tv).name, &"BuiltInDvd", "the DVD's node name")
	_check_eq(_vcr(tv).built_into, tv, "the VCR knows the set it is in")


func _d_none() -> void:
	var stock := _tv("")
	var monitor := _tv("crt_plain")
	await _wait(5)
	_ok(stock.decks().decks().is_empty(), "the stock set has no deck")
	_ok(monitor.decks().decks().is_empty(), "a shipped cabinet without the markers has none")
	_check_eq(stock.source_name(RetroTV.Source.COMPOSITE_2), "COMPOSITE 2",
		"and its inputs keep their own names")


func _d_crowded() -> void:
	var tv := _tv(CROWDED_ID)
	await _wait(5)
	_check_eq(tv.panel().panel_inputs(), 3, "three phono rows")
	_ok(tv.decks().deck_on(3) is VCRPlayer, "the VCR takes the last composite input")
	_ok(_dvd(tv) == null, "the DVD player has no input left and is not built")
	_ok(tv.get_node_or_null("BuiltInDvd") == null, "not even as a node that nothing can reach")


func _d_not_loose() -> void:
	var tv := _tv()
	await _wait(5)
	for deck: MediaTransport in tv.decks().decks():
		var what := str(deck.name)
		_ok(not deck.enabled, "%s: a hand cannot take it out of the set" % what)
		_ok(deck.freeze and deck.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC,
			"%s: frozen STATIC, so it rides the set rigidly" % what)
		_check_eq(deck.collision_layer, 0, "%s: no collision layer" % what)
		_check_eq(deck.collision_mask, 0, "%s: no collision mask" % what)
		_ok(not deck.is_in_group("spawned"), "%s: not a room object of its own" % what)
		for port_name: String in ["VideoOut", "AudioLOut", "AudioROut"]:
			var port := deck.get_node(port_name) as XRToolsSnapZone
			_ok(not port.enabled and not port.visible,
				"%s: %s is switched off, so no lead can take the picture" % [what, port_name])
		_ok(deck._slot.host == tv, "%s: its media is collision-excepted against the SET" % what)
		for node: Node3D in deck._housing():
			_ok(not node.visible, "%s: %s hidden inside the cabinet" % [what, node.name])
		_ok((deck.get_node("PointerArea") as CollisionObject3D).collision_layer != 0,
			"%s: still something the remote can aim at" % what)
		_check_eq(deck.connected_tv, tv, "%s: feeds its set" % what)
		_ok(deck._feed_video and deck._feed_left == 0 and deck._feed_right == 1,
			"%s: picture and both channels, uncrossed" % what)
	# A cable graph change must not undo the feed: the deck has no sockets on it.
	_vcr(tv).on_av_topology_changed([])
	_check_eq(_vcr(tv).connected_tv, tv, "a plug moving elsewhere leaves the VCR on its set")


func _d_carried() -> void:
	var tv := _tv()
	await _wait(5)
	var vcr := _vcr(tv)
	var offset := vcr.global_position - tv.global_position
	tv.global_position += Vector3(0.7, 0.2, -0.4)
	tv.rotate_y(0.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _wait(2)
	# Its pose in the set's frame is the marker's, whatever the set did...
	var local := tv.global_transform.affine_inverse() * vcr.global_position
	_ok(local.distance_to(Vector3(-0.07, -0.07, 0.05)) < 0.001,
		"the VCR is still at its marker in the set's frame (got %s)" % local)
	_ok(vcr.global_basis.z.dot(tv.global_basis.z) > 0.999, "and faces the way the set does")
	# What the remote's ray meets is the PHYSICS body, not the node.
	var pointer := vcr.get_node("PointerArea") as StaticBody3D
	var server: Transform3D = PhysicsServer3D.body_get_state(pointer.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM)
	_ok(server.origin.distance_to(pointer.global_position) < 0.001,
		"the deck's pointer body moved with it in the physics server too")
	# ...which is not where it was in the world: the control, since a deck that
	# stayed put would fail the first check only if the set had moved at all.
	_ok(vcr.global_position.distance_to(tv.global_position - Vector3(0.7, 0.2, -0.4) + offset) > 0.1,
		"so it is not where it was left in the world")


# ── source/ ───────────────────────────────────────────────────────────────────

func _s_cycle() -> void:
	var tv := _tv()
	await _wait(5)
	_check_eq(tv.current_source, RetroTV.Source.COMPOSITE_1, "a new set is on Composite 1")
	var seen: Array[String] = []
	for i in 4:
		tv.cycle_source()
		seen.append(tv.source_name(tv.current_source))
	_check_eq(seen, ["VCR", "DVD", "RF", "COMPOSITE 1"],
		"SOURCE tours the phono row, both decks and the aerial")
	tv.set_source(RetroTV.Source.COMPOSITE_2)
	_check_eq(tv._source_banner(), "VCR", "the banner names the deck")
	_check_eq(tv.current_source, RetroTV.Source.COMPOSITE_2,
		"a deck's input is selectable although the cabinet prints no sockets for it")
	tv.set_source(RetroTV.Source.COMPOSITE_4)
	_check_eq(tv.current_source, RetroTV.Source.COMPOSITE_1,
		"the input past the decks has neither, and is not selectable")


func _s_no_sockets() -> void:
	var tv := _tv()
	await _wait(5)
	for input: int in [1, 2]:
		for port: RcaPort in tv.panel()._av_ports[input]:
			_ok(not port.enabled and not port.visible,
				"input %d: %s is off, so a lead cannot land on a deck's input" % [input + 1, port.name])
	_ok(tv.get_node_or_null("AvLegend2") == null, "and no legend is printed for it")


# ── display/ and audio/ ───────────────────────────────────────────────────────

func _v_host() -> void:
	var tv := _tv()
	await _wait(5)
	_ok(tv.panel().selected_system() == null, "Composite 1 has nothing on it")
	tv.set_source(RetroTV.Source.COMPOSITE_2)
	_ok(tv.panel().selected_system() == _vcr(tv), "on VCR the VCR is the host the glass reads")
	tv.set_source(RetroTV.Source.COMPOSITE_3)
	_ok(tv.panel().selected_system() == _dvd(tv), "on DVD the DVD player is")
	_ok(tv.can_paint(_dvd(tv)) and not tv.can_paint(_vcr(tv)),
		"and only the selected deck may paint")


func _a_selected() -> void:
	var tv := _tv()
	await _wait(5)
	var vcr := _vcr(tv)
	var dvd := _dvd(tv)
	_check_eq([vcr._volume_linear, dvd._volume_linear], [0.0, 0.0],
		"on Composite 1 neither deck is heard")
	tv.set_source(RetroTV.Source.COMPOSITE_2)
	_ok(vcr._volume_linear > 0.0 and dvd._volume_linear == 0.0, "on VCR only the VCR is heard")
	tv.set_source(RetroTV.Source.COMPOSITE_3)
	_ok(vcr._volume_linear == 0.0 and dvd._volume_linear > 0.0, "on DVD only the DVD player is")
	tv.remote_mute_toggle()
	_check_eq(dvd._volume_linear, 0.0, "and the set's MUTE reaches it")


# ── controls/ ─────────────────────────────────────────────────────────────────

func _c_front() -> void:
	var tv := _tv()
	await _wait(5)
	var front := tv.global_basis.z.normalized()
	for deck: MediaTransport in tv.decks().decks():
		for child in deck.get_children():
			# A key of the deck's own box (the VCR's POWER) is hidden with it.
			if not child is VRButton or deck._housing().has(child):
				continue
			var b := child as VRButton
			var facing := b.global_basis.y.normalized()
			_ok(facing.dot(front) > 0.999,
				"%s/%s faces out of the cabinet's front (by sign: dot %.3f)"
					% [deck.name, b.name, facing.dot(front)])
			var local := tv.global_transform.affine_inverse() * b.global_position
			_ok(local.z >= 0.185 - 0.0002 and local.z <= 0.188,
				"%s/%s stands on the 185 mm front, at most 3 mm proud (got %.4f)" % [deck.name, b.name, local.z])
	var vcr := _vcr(tv)
	var at := func(deck: Node, n: String) -> Vector3:
		return tv.global_transform.affine_inverse() * (deck.get_node(n) as Node3D).global_position
	# The RETRO XR decks' keys are on their FRONT, beside their slot and display: a deck seated flush keeps them
	# there and the cabinet's controls marker (made for the old top panels) does not part them.
	var row := ["RewindButton", "PlayButton", "FastForwardButton", "StopButton", "EjectButton", "PauseButton",
		"RecordButton"]
	for i in range(1, row.size()):
		_ok(at.call(vcr, row[i - 1]).x < at.call(vcr, row[i]).x, "VCR: %s left of %s" % [row[i - 1], row[i]])
		_ok(absf(at.call(vcr, row[i]).y - at.call(vcr, "PlayButton").y) < 0.0005,
			"VCR: %s level with PLAY" % row[i])
	var play: Vector3 = at.call(vcr, "PlayButton")
	_ok(absf(play.x - 0.0) < 0.0005 and absf(play.y + 0.0855) < 0.0005,
		"VCR: PLAY stays on the deck's face, 70 mm right of and 15.5 mm under its seat (got %s)" % play)
	_ok(not (vcr.get_node("PowerButton") as VRButton).visible,
		"VCR: POWER is the deck's own box's, hidden in the cabinet")
	var dvd := _dvd(tv)
	_ok(at.call(dvd, "UpButton").y > at.call(dvd, "DownButton").y,
		"DVD: the menu cluster's UP is above its DOWN")
	_ok(at.call(dvd, "LeftButton").x < at.call(dvd, "RightButton").x,
		"DVD: LEFT is left of RIGHT")
	var eject: Vector3 = at.call(dvd, "EjectButton")
	_ok(absf(eject.x + 0.094) < 0.0005 and absf(eject.y + 0.187) < 0.0005,
		"DVD: OPEN/CLOSE stays by its tray on the deck's face (got %s)" % eject)
	# The slot stayed where the deck put it. It is where the holder takes a tape, 17 mm behind the cabinet's
	# 185 mm face with 35 mm of spine out of it.
	var slot := tv.global_transform.affine_inverse() * (vcr.get_node("TapeSlot") as Node3D).global_position
	_ok(slot.distance_to(Vector3(-0.14, -0.059, 0.168)) < 0.0005,
		"the tape slot is at the cabinet's door, 17 mm in (got %s)" % slot)
	_ok((vcr.get_node("Vfd") as Node3D).visible and (dvd.get_node("Vfd") as Node3D).visible,
		"both decks' displays show on the cabinet's face")


# ── save/ ─────────────────────────────────────────────────────────────────────

func _p_round_trip() -> void:
	var tv := _tv()
	await _wait(5)
	var tape := _media(TAPE_SCENE) as VCRTape
	tape.video_label = "HOLIDAY 1989"
	var disc := _media(DISC_SCENE) as DVDDisc
	disc.dvd_label = "FEATURE"
	_vcr(tv).restore_media(tape)
	_dvd(tv).restore_media(disc, 0.5)
	await _wait(3)
	_ok(_vcr(tv).get_snapped_tape() == tape, "the tape is in the built-in VCR")

	var persistence := ScenePersistence.new()
	var objects: Array = persistence._collect_objects(self)
	_check_eq(ScenePersistence._objects_validation_error(objects), "", "the save validates")
	var tv_entry := {}
	for o: Dictionary in objects:
		if str(o.get("type", "")) == "tv":
			tv_entry = o
	var decks: Dictionary = tv_entry.get("decks", {})
	_ok(decks.has("vcr") and decks.has("dvd"), "the set's record names both decks' media")
	_ok(is_equal_approx(float((decks.get("dvd", {}) as Dictionary).get("yaw", 0.0)), 0.5),
		"with the disc's spin")

	await _teardown()
	await _wait(5)
	persistence = ScenePersistence.new()
	var spawned: Dictionary = persistence.instantiate_objects(self, objects)
	var tv2: RetroTV = null
	for node: Variant in spawned.values():
		_spawned.append(node)
		if node is RetroTV:
			tv2 = node
		if node is RigidBody3D:
			(node as RigidBody3D).freeze = true
	await _wait(10)
	_ok(tv2 != null, "the set comes back")
	if tv2 == null:
		return
	var tape2 := _vcr(tv2).get_snapped_tape() as VCRTape
	var disc2 := _dvd(tv2).get_snapped_disc() as DVDDisc
	_ok(tape2 != null and tape2.video_label == "HOLIDAY 1989", "the tape is back in its VCR")
	_ok(disc2 != null and disc2.dvd_label == "FEATURE", "the disc is back in its DVD player")


func _p_no_copy() -> void:
	var tv := _tv()
	await _wait(5)
	var persistence := ScenePersistence.new()
	var objects: Array = persistence._collect_objects(self)
	var kinds: Array = objects.map(func(o: Dictionary) -> String: return str(o.get("type", "")))
	_check_eq(kinds, ["tv"], "one set, and no vcr_player or dvd_player beside it")
	# Asked directly, as ObjectSync does of anything it might register.
	_check_eq(persistence.serialize_node(_vcr(tv), 0, {}), {},
		"a built-in deck serialises to nothing on its own")
	_ok(not tv.get_control_state().is_empty() and not objects[0].has("decks"),
		"an empty combination set writes no decks field")


# ── net/ ──────────────────────────────────────────────────────────────────────

func _n_named() -> void:
	var host_tv := _tv()
	var peer_tv := _tv()
	peer_tv.name = "SomeOtherName"
	await _wait(5)
	var nm := StubNM.new()
	nm.world = self
	add_child(nm)
	_spawned.append(nm)
	var host_sync := NetObjectSync.new()
	nm.add_child(host_sync)
	var peer_nm := StubNM.new()
	peer_nm.world = self
	add_child(peer_nm)
	_spawned.append(peer_nm)
	var peer_sync := NetObjectSync.new()
	peer_nm.add_child(peer_sync)
	host_sync._bind(host_tv, 41)
	peer_sync._bind(peer_tv, 41)

	var wire := host_sync._encode_args({"vcr": _vcr(host_tv), "tv": host_tv})
	_check_eq(wire.get("vcr"), {"$id": 41, "$sub": "BuiltInVcr"},
		"the VCR goes on the wire as its set's id and its path inside the set")
	_check_eq(wire.get("tv"), {"$id": 41}, "the set itself as before")
	var got := peer_sync._decode_args(wire)
	_ok(got.get("vcr") == _vcr(peer_tv),
		"and comes off it as the far peer's own VCR, whatever that set is called")
	_ok(peer_sync._resolve_id(41, "BuiltInDvd") == _dvd(peer_tv),
		"a media-state broadcast finds the DVD player the same way")
	_ok(peer_sync._resolve_id(41, "NoSuchDeck") == null, "and a path that is not there is null")
