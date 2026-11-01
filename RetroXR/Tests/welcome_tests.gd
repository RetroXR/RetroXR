## welcome_tests — the welcome page (WelcomePanel, Welcome2D).
##
## Three things can go wrong and none of them shows in a headless run of the room:
## the page will not go away for good (Don't Show Again is not kept), will not come
## back (OPTIONS > General cannot switch it on, or shows the wrong state), or tells
## a new player the wrong thing. The last is the likeliest — the README had the
## desktop drop on Ctrl + click while the code had it on Shift — so the copy is
## held to the bindings the code really has.
##
## The headset page's controllers (ControllerDemo) press the buttons through the
## same ControllerRig the hand's own controller uses; rig/ holds that reader to a
## rig of known travel, demo/ holds every step to bones a controller really has
## and checks the presses land on the step's own hand.
##
## No SubViewport: the page is built straight into the tree, and the 3D panel is
## driven outside it. Writes the player's real user://app_prefs.json, snapshotted
## and put back byte for byte.
##
##   "$godot" --headless --path RetroXR res://Tests/welcome_tests.tscn
extends "res://Tests/test_suite.gd"

## Cases in this file, NOT counting the guard below -- it is checked before
## it has recorded itself.
const EXPECTED_CASES := 51


func _ready() -> void:
	suite_tag = "welcome"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[welcome] TIMEOUT")
		get_tree().quit(1))

	_group_prefs()
	await _group_dismiss()
	_group_options()
	_group_copy()
	await _group_page()
	_group_rig()
	await _group_demo()

	_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")

	_finish()


# ── prefs/ ────────────────────────────────────────────────────────────────────

func _group_prefs() -> void:
	_eq(_app_prefs_default("show_welcome"), true, "prefs/a fresh install shows the welcome page at start")

	var was: bool = AppPrefs.show_welcome
	AppPrefs.show_welcome = true
	_ok(WelcomePanel.due(), "prefs/switched on: the page comes up at start")
	AppPrefs.show_welcome = false
	_ok(not WelcomePanel.due(), "prefs/switched off: it does not")
	AppPrefs.show_welcome = was

	var back := _app_prefs_round_trip({"show_welcome": false})
	_eq(back.get("show_welcome"), false, "prefs/switched off survives a save and a load")

	# The one way to change it saves it and says so; saying nothing when nothing
	# changed is what lets the OPTIONS switch follow without a loop.
	var path: String = AppPrefs.PREFS_PATH
	var saved_file: Variant = _snapshot_file(path)
	AppPrefs.show_welcome = true
	var heard: Array = []
	var listen := func(on: bool) -> void: heard.append(on)
	AppPrefs.show_welcome_changed.connect(listen)
	AppPrefs.set_show_welcome(false)
	AppPrefs.set_show_welcome(false)
	_ok(heard == [false] and not bool(JsonStore.read_dict(path).get("show_welcome", true)),
		"prefs/set_show_welcome saves it and says so, once", str(heard))
	AppPrefs.show_welcome_changed.disconnect(listen)
	AppPrefs.show_welcome = was
	_restore_file(path, saved_file)


# ── dismiss/ ──────────────────────────────────────────────────────────────────

func _group_dismiss() -> void:
	var path: String = AppPrefs.PREFS_PATH
	var saved_file: Variant = _snapshot_file(path)
	var was: bool = AppPrefs.show_welcome

	# The page's two buttons say which was pressed.
	var page := (load("res://Scenes/UI/welcome_2d.tscn") as PackedScene).instantiate() as Welcome2D
	page.vr_override = 0
	add_child(page)
	await get_tree().process_frame
	var pressed: Array = []
	page.dismissed.connect(func(for_good: bool) -> void: pressed.append(for_good))
	var got_it := page.find_child("GotIt", true, false) as Button
	var never := page.find_child("NeverAgain", true, false) as Button
	_ok(got_it != null and never != null, "dismiss/the page has Got it and Don't Show Again")
	if got_it != null and never != null:
		got_it.pressed.emit()
		never.pressed.emit()
	_eq(pressed, [false, true], "dismiss/Got it closes it for now, Don't Show Again for good")
	_ok(page.find_children("*", "Label", true, false).any(
			func(n: Node) -> bool: return (n as Label).text == Welcome2D.AGAIN_NOTE)
		and Welcome2D.AGAIN_NOTE.contains("OPTIONS > General"),
		"dismiss/the page says where to switch it back on")
	page.queue_free()

	# Got it: gone, and back at the next start.
	AppPrefs.show_welcome = true
	var panel := WelcomePanel.new()
	var heard := [0]
	panel.dismissed.connect(func() -> void: heard[0] += 1)
	panel._on_page_dismissed(false)
	panel._on_page_dismissed(false)
	_eq(heard[0], 1, "dismiss/a second press of a dismissed page does nothing")
	_ok(WelcomePanel.due(), "dismiss/after Got it it still comes up at the next start")

	# Don't Show Again: off at start, kept on disk.
	var for_good := WelcomePanel.new()
	for_good._on_page_dismissed(true)
	_ok(not WelcomePanel.due() and not bool(JsonStore.read_dict(path).get("show_welcome", true)),
		"dismiss/after Don't Show Again it is off at start, and saved so")

	# Put away any other way, nothing changes.
	AppPrefs.show_welcome = true
	var away := WelcomePanel.new()
	away.put_away("welcome_tests")
	_ok(WelcomePanel.due(), "dismiss/put away unread, it still comes up at the next start")

	await get_tree().process_frame
	AppPrefs.show_welcome = was
	_restore_file(path, saved_file)


# ── options/ ──────────────────────────────────────────────────────────────────

## OPTIONS > General > Show Welcome Page at Start: the real row, from the real
## builder, switched as a player switches it.
func _group_options() -> void:
	var path: String = AppPrefs.PREFS_PATH
	var saved_file: Variant = _snapshot_file(path)
	var was: bool = AppPrefs.show_welcome

	AppPrefs.show_welcome = false
	var view := SpawnMenuOptionsView.new()
	var vbox := VBoxContainer.new()
	view.add_child(vbox)
	var toggle := view.call("_build_welcome_option", vbox) as VRToggle
	var titled := vbox.find_children("*", "Label", true, false).any(
		func(n: Node) -> bool: return (n as Label).text == "Show Welcome Page at Start")
	_ok(toggle != null and titled and not toggle.button_pressed,
		"options/General has Show Welcome Page at Start, showing it off when it is off")

	if toggle != null:
		toggle.button_pressed = true
	_ok(WelcomePanel.due() and bool(JsonStore.read_dict(path).get("show_welcome", false)),
		"options/switching it on brings the page back at start, and is saved")

	# The page's Don't Show Again with the tab already built: the switch follows.
	AppPrefs.set_show_welcome(false)
	_ok(toggle != null and not toggle.button_pressed and not WelcomePanel.due(),
		"options/Don't Show Again on the page moves the switch, which stays off")

	view.free()
	AppPrefs.show_welcome = was
	_restore_file(path, saved_file)


# ── copy/ ─────────────────────────────────────────────────────────────────────

func _group_copy() -> void:
	var vr := "\n".join(Welcome2D.do_lines(true))
	var desk := "\n".join(Welcome2D.do_lines(false))

	_ok(desk.contains("Tab") and not desk.contains("stick"),
		"copy/the desktop page opens the menu with Tab and names no stick")
	_ok(vr.contains("LEFT stick") and not vr.contains("Tab") and not vr.contains("F11"),
		"copy/the headset page opens the menu with the left stick and names no key")

	# The drop is the verb a player cannot discover, and the one the README got
	# wrong. Held to HeldHint's glyphs, which are what the room itself teaches.
	_ok("keyboard_shift_outline" in HeldHint.DESKTOP_DROP_GLYPHS and desk.contains("Shift + click")
		and not desk.contains("Ctrl"),
		"copy/the desktop drop is Shift + click, as HeldHint teaches it")
	# Keyboard capture on a held pad: the two keys ScrollLockCapture really toggles on.
	_ok(KEY_F3 in ScrollLockCapture.TOGGLE_KEYS and KEY_SCROLLLOCK in ScrollLockCapture.TOGGLE_KEYS
		and desk.contains("F3") and desk.contains("Scroll Lock"),
		"copy/the desktop page names F3 and Scroll Lock for playing a held pad from the keyboard")
	var words: Array[String] = []
	for glyph: String in HeldHint.VR_DROP_GLYPHS:
		for word: String in ["grip", "trigger", "stick"]:
			if glyph.contains(word):
				words.append(word)
	_ok(words == ["grip", "trigger", "stick"] and vr.contains("grip + trigger + stick click"),
		"copy/the headset drop is grip + trigger + stick click, as HeldHint teaches it", str(words))

	var roms := Welcome2D.roms_folder()
	_ok(roms.contains(DataPaths.media_root("roms").trim_prefix("/sdcard/"))
		and vr.contains(roms) and desk.contains(roms),
		"copy/both pages name the real ROM folder", roms)
	_ok(not vr.contains(Welcome2D.ROMS_TOKEN) and not desk.contains(Welcome2D.ROMS_TOKEN),
		"copy/no page shows the folder's placeholder")
	_ok(" ".join(Welcome2D.DONT).contains("you don't own"),
		"copy/the DON'T says to use only games you own")

	# A Quest loads files through the Web File Manager only: its ROM line says how,
	# and its DON'T warns off every other way in, and says why.
	var quest := "\n".join(Welcome2D.do_lines(true, true))
	_ok(quest.contains("Web File Manager") and quest.contains("OPTIONS > File Server")
		and quest.contains(WebFileServer.headset_url()) and not quest.contains(Welcome2D.roms_folder()),
		"copy/on a Quest, the ROM line sends files through the Web File Manager, at the headset's own address too")
	var quest_dont := " ".join(Welcome2D.dont_lines(true))
	_ok(quest_dont.contains("file manager") and quest_dont.contains("USB") and quest_dont.contains("adb")
		and quest_dont.contains("uid") and quest_dont.contains("Web File Manager only")
		and quest_dont.contains("you don't own"),
		"copy/on a Quest, a DON'T warns off file managers, USB and adb, says why, and keeps the rest")
	_ok(not " ".join(Welcome2D.dont_lines(false)).contains("uid")
		and "\n".join(Welcome2D.do_lines(true, false)).contains(Welcome2D.roms_folder()),
		"copy/off a Quest, the folder line stays and there is no Quest warning")


# ── page/ ─────────────────────────────────────────────────────────────────────

## Every line is on the page that is built, either way round, and it can be measured.
func _group_page() -> void:
	_ok(ResourceLoader.exists(Welcome2D.MENU_CLIP), "page/the menu clip ships with the build")
	_ok(ResourceLoader.exists(Welcome2D.HOOKUP_CLIP), "page/the hookup clip ships with the build")

	# Next and Back, pressed as a player presses them.
	var two := (load("res://Scenes/UI/welcome_2d.tscn") as PackedScene).instantiate() as Welcome2D
	two.vr_override = 0
	var two_box := Control.new()
	two_box.size = WelcomePanel.VIEWPORT_SIZE
	add_child(two_box)
	two_box.add_child(two)
	await get_tree().process_frame
	var next := two.find_child("Next", true, false) as Button
	var back := two.find_child("Back", true, false) as Button
	var heard: Array = []
	two.page_changed.connect(func(i: int) -> void: heard.append(i))
	if next != null:
		next.pressed.emit()
	var texts: Array = two.find_children("*", "Label", true, false).filter(
		func(n: Node) -> bool: return (n as Label).is_visible_in_tree()).map(
		func(n: Node) -> String: return (n as Label).text)
	_ok(two.page_index() == 1 and not (two.find_child("PageWelcome", true, false) as Control).visible
		and Welcome2D.HOOKUP_TITLE in texts and Welcome2D.HOOKUP_CREDIT in texts
		and two.hookup_player() != null and two.hookup_player().stream != null
		and back != null and back.visible and not next.visible,
		"page/Next shows the hookup page: its clip, its words, the credit and Back", str(heard))
	_ok(two.clip_player().paused and not two.hookup_player().paused,
		"page/only the page shown plays its clip")
	if back != null:
		back.pressed.emit()
	_ok(two.page_index() == 0 and next.visible and not back.visible and not two.clip_player().paused
		and two.hookup_player().paused and heard == [1, 0],
		"page/Back returns to the welcome, its clip playing again", str(heard))
	two_box.queue_free()

	# A Quest's page carries its own lines.
	var qpage := (load("res://Scenes/UI/welcome_2d.tscn") as PackedScene).instantiate() as Welcome2D
	qpage.vr_override = 1
	qpage.android_override = 1
	var qbox := Control.new()
	qbox.size = WelcomePanel.VIEWPORT_SIZE
	add_child(qbox)
	qbox.add_child(qpage)
	await get_tree().process_frame
	var qshown: Array[String] = []
	for node: Node in qpage.find_children("*", "Label", true, false):
		qshown.append((node as Label).text)
	var qmissing: Array[String] = []
	for line: String in Welcome2D.do_lines(true, true) + Welcome2D.dont_lines(true):
		if line not in qshown:
			qmissing.append(line)
	_ok(qmissing.is_empty() and Welcome2D.QUEST_ROMS_LINE in qshown and Welcome2D.DONT_QUEST[0] in qshown,
		"page/a Quest's page shows the Web File Manager line and its own DON'T", str(qmissing))
	qbox.queue_free()
	for vr: bool in [false, true]:
		var page := (load("res://Scenes/UI/welcome_2d.tscn") as PackedScene).instantiate() as Welcome2D
		page.vr_override = 1 if vr else 0
		# At the panel's own width, as it is in its viewport: a headless window is
		# whatever size it is, and the lines wrap to it.
		var box := Control.new()
		box.size = WelcomePanel.VIEWPORT_SIZE
		add_child(box)
		box.add_child(page)
		await get_tree().process_frame
		await get_tree().process_frame
		var shown: Array[String] = []
		for node: Node in page.find_children("*", "Label", true, false):
			shown.append((node as Label).text)
		var missing: Array[String] = []
		for line: String in Welcome2D.do_lines(vr) + Welcome2D.dont_lines():
			if line not in shown:
				missing.append(line)
		_ok(missing.is_empty() and Welcome2D.TITLE in shown,
			"page/the %s page shows its title and every line" % ("headset" if vr else "desktop"),
			str(missing))
		# The panel is made as tall as this; nothing, or more than it allows, and
		# the page is a sliver or loses its Got it button.
		var h := page.content_height()
		_ok(h > WelcomePanel.MIN_PX * 0.5 and h < WelcomePanel.MAX_PX,
			"page/the %s page measures a height the panel can take" % ("headset" if vr else "desktop"),
			"%d px" % h)
		var clip := page.clip_player()
		_ok(clip != null and clip.stream != null and clip.loop,
			"page/the %s page plays the menu clip, looping" % ("headset" if vr else "desktop"))
		if vr:
			page.set_step(1, 5, "TEST CAPTION")
			var said := page.find_child("StepCaption", true, false) as Label
			_ok(page.stage_rect().has_area() and said != null and said.text.begins_with("2 / 5")
				and said.text.contains("TEST CAPTION"),
				"page/the headset page has the controllers' stage, and says the step under it")
		else:
			_ok(not page.stage_rect().has_area() and page.find_child("StepCaption", true, false) == null,
				"page/the desktop page has no controllers' stage")
		box.queue_free()


# ── rig/ ──────────────────────────────────────────────────────────────────────

## ControllerRig against rigs of known travel: the stand-in's own clip, and one
## made here with a stick that both leans and clicks.
func _group_rig() -> void:
	var model := ControllerStandIn.build(true)
	var skel := model.get_node("Skeleton3D") as Skeleton3D
	var anim := model.get_node("AnimationPlayer") as AnimationPlayer
	var driven := ControllerRig.read(skel, anim.get_animation(ControllerStandIn.CLIP))
	var names := driven.keys()
	names.sort()
	_eq(names, ["b_button_x", "b_button_y", "b_thumbstick", "b_trigger_front", "b_trigger_grip"],
		"rig/reading a rig finds every bone its clip moves, and no other")

	var trigger := skel.find_bone("b_trigger_front")
	var rest := skel.get_bone_rest(trigger).basis.get_rotation_quaternion()
	ControllerRig.actuate(skel, driven, "b_trigger_front", 1.0)
	var full := rad_to_deg(skel.get_bone_pose_rotation(trigger).angle_to(rest))
	_ok(absf(full - ControllerStandIn.TRIGGER_TURN) < 0.5,
		"rig/a full pull turns the trigger as far as the clip does", "%.2f deg" % full)
	ControllerRig.actuate(skel, driven, "b_trigger_front", 0.5)
	var half := rad_to_deg(skel.get_bone_pose_rotation(trigger).angle_to(rest))
	_ok(absf(half - ControllerStandIn.TRIGGER_TURN * 0.5) < 0.5,
		"rig/half a pull is half the travel", "%.2f deg" % half)
	model.free()

	# A stick whose clip leans it AND clicks it: the click alone must not lean.
	var s2 := Skeleton3D.new()
	s2.add_bone("b_thumbstick")
	s2.set_bone_rest(0, Transform3D.IDENTITY)
	s2.reset_bone_pose(0)
	var clip := Animation.new()
	var rot := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(rot, NodePath("Skeleton3D:b_thumbstick"))
	clip.rotation_track_insert_key(rot, 0.0, Quaternion.IDENTITY)
	clip.rotation_track_insert_key(rot, 0.5, Quaternion(Vector3.RIGHT, deg_to_rad(12.0)))
	var pos := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(pos, NodePath("Skeleton3D:b_thumbstick"))
	clip.position_track_insert_key(pos, 0.0, Vector3.ZERO)
	clip.position_track_insert_key(pos, 1.0, Vector3(0, -0.002, 0))
	var d2 := ControllerRig.read(s2, clip)
	ControllerRig.actuate(s2, d2, "b_thumbstick", 1.0, false, true)
	_ok(s2.get_bone_pose_rotation(0).is_equal_approx(Quaternion.IDENTITY)
		and absf(s2.get_bone_pose_position(0).y + 0.002) < 0.0001,
		"rig/a click without the turn moves the stick down and does not lean it",
		"rot %s pos %s" % [s2.get_bone_pose_rotation(0), s2.get_bone_pose_position(0)])
	ControllerRig.actuate(s2, d2, "b_thumbstick", 1.0)
	_ok(rad_to_deg(s2.get_bone_pose_rotation(0).angle_to(Quaternion.IDENTITY)) > 11.5,
		"rig/with the turn, the same bone leans as far as its clip")
	s2.free()


# ── demo/ ─────────────────────────────────────────────────────────────────────

func _group_demo() -> void:
	# Every step names bones a controller's rig has on that hand, and ones the
	# hand's own controller drives (ControllerModel): a typo would press nothing.
	var known: Array = ControllerModel.ACTION_BONES.values() + ControllerModel.AX_BONES.values() \
		+ ControllerModel.BY_BONES.values()
	var bad: Array[String] = []
	for step: Dictionary in ControllerDemo.STEPS:
		var model := ControllerStandIn.build(step["hand"] == "left")
		var skel := model.get_node("Skeleton3D") as Skeleton3D
		for bone_name: String in step["press"]:
			if skel.find_bone(bone_name) < 0 or not bone_name in known:
				bad.append("%s/%s" % [step["hand"], bone_name])
		model.free()
	_ok(bad.is_empty(), "demo/every step presses bones a controller has", str(bad))

	_ok(ControllerDemo.copy_art(null) == null, "demo/no art to copy is no copy")

	# Pressed one after another, held together.
	var demo := ControllerDemo.new()
	var early := [demo._press_amount(0.6, 0, 3), demo._press_amount(0.6, 2, 3)]
	var late := [demo._press_amount(2.0, 0, 3), demo._press_amount(2.0, 2, 3)]
	_ok(early[0] > 0.9 and early[1] == 0.0 and late[0] > 0.99 and late[1] > 0.99,
		"demo/a combination presses its buttons one after another, then all together",
		"0.6 s %s, 2.0 s %s" % [early, late])

	# No runtime models: the stand-in, held on the combination step.
	var combo := 3
	demo.hold_step = combo
	var heard := []
	demo.step_changed.connect(func(i: int, n: int, c: String) -> void: heard.append([i, n, c]))
	add_child(demo)
	demo.setup(null, null)
	_ok(demo.source_of("left") == "stand-in" and demo.source_of("right") == "stand-in",
		"demo/with no runtime model, each hand shows the stand-in")
	_ok(not heard.is_empty() and heard[0][0] == combo and heard[0][1] == ControllerDemo.STEPS.size()
		and heard[0][2] == ControllerDemo.STEPS[combo]["caption"],
		"demo/it says which step it is on, and the step's words", str(heard))
	await get_tree().process_frame
	await get_tree().process_frame
	var models: Dictionary = demo.get("_models")
	var down: Array[String] = []
	for hand: String in models:
		var skel := (models[hand] as Dictionary)["skeleton"] as Skeleton3D
		for bone_name: String in (models[hand] as Dictionary)["driven"]:
			var b := skel.find_bone(bone_name)
			if skel.get_bone_pose_position(b).distance_to(skel.get_bone_rest(b).origin) > 0.0005 \
					or skel.get_bone_pose_rotation(b).angle_to(skel.get_bone_rest(b).basis.get_rotation_quaternion()) > 0.05:
				down.append("%s/%s" % [hand, bone_name])
	down.sort()
	_eq(down, ["right/b_thumbstick", "right/b_trigger_front", "right/b_trigger_grip"],
		"demo/on the combination step, the right hand's three buttons are down and nothing else")
	demo.queue_free()
