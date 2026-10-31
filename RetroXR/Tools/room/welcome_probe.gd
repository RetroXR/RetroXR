## The first-time welcome page (WelcomePanel) in the real room, and both of its pages flat.
##
## Opens the bedroom with the welcome due, waits for the page to stand in front of the camera and
## photographs it; presses Got it through the panel's own pointer body (the path a laser or the
## desktop crosshair takes, at the button's real place on the quad) and checks it went and was
## kept; asks for it again the way ABOUT does; then renders the desktop and headset pages flat.
##
##   --vr       the HEADSET's page, on a desk: no runtime controller models here, so the
##              ControllerDemo shows the stand-in, and the probe checks it presses each step's
##              button and moves through the steps.
##   --menu     after Got it, open the menu and go through it with the same pointer events:
##              CORES, then SPAWN, then TVs.
##   --linger=S seconds the page stays up before Got it (default 2.5); for a recording.
##
## Every press shows a cyan dot where it lands. To record it, Godot's movie writer at a fixed
## rate, so the clip on the page and the controllers run at their real speed:
##
##     "$godot" --path RetroXR --resolution 1280x800 --position 20,20 --write-movie out.avi \
##         --fixed-fps 30 res://Tools/room/welcome_probe.tscn -- --out=/tmp/welcome --menu
##
## WINDOWED (headless draws nothing), and it WRITES user://app_prefs.json -- back it up first:
##
##     cp "$APPDATA/Godot/app_userdata/RetroXR/app_prefs.json" /tmp/prefs.bak
##     ...run...
##     cp /tmp/prefs.bak "$APPDATA/Godot/app_userdata/RetroXR/app_prefs.json"
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")
const PAGE := preload("res://Scenes/UI/welcome_2d.tscn")

var _out := ""
var _vr := false
var _menu := false
var _linger := 2.5
var _failed := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--vr":
			_vr = true
		elif a == "--menu":
			_menu = true
		elif a.begins_with("--linger="):
			_linger = float(a.trim_prefix("--linger="))
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[welprobe] TIMEOUT")
		get_tree().quit(1))

	if _vr:
		Welcome2D.force_vr = 1
	AppPrefs.welcome_seen = 0
	print("[welprobe] welcome due: %s, page: %s" % [WelcomePanel.due(), "headset" if _vr else "desktop"])
	var t0 := Time.get_ticks_msec()
	add_child(SCENE.instantiate())

	var ctrl := _controller()
	var panel := await _wait_for_panel(60.0)
	if panel == null or ctrl == null:
		_fail("no welcome page after 60 s (controller %s)" % ctrl)
		_end()
		return
	print("[welprobe] page up %.1f s after the room was added; curtain active: %s" % [
		(Time.get_ticks_msec() - t0) / 1000.0, LoadingOverlay.is_active()])
	var cam := get_viewport().get_camera_3d()
	print("[welprobe] page %.2f m from the camera" % panel.global_position.distance_to(cam.global_position))
	await get_tree().create_timer(2.5).timeout
	print("[welprobe] the startup hint waits for the page: %s" % ctrl.get("_hint_waits_for_welcome"))
	_check_clip(panel)
	if _vr:
		await _check_demo(panel)
	await _shot("welcome_room%s.png" % ("_vr" if _vr else ""))
	await get_tree().create_timer(maxf(0.0, _linger - 2.5)).timeout

	# Got it, pressed where it really is on the quad.
	var page := panel.page()
	var got_it := page.find_child("GotIt", true, false) as Control if page != null else null
	if not await _press_on(panel.get_node_or_null("WelcomeViewport") as XRToolsViewport2DIn3D, got_it):
		_end()
		return
	await get_tree().create_timer(0.5).timeout
	var gone := not is_instance_valid(panel)
	var kept := int(JsonStore.read_dict(AppPrefs.PREFS_PATH).get("welcome_seen", -1))
	print("[welprobe] after Got it: page gone %s, saved welcome_seen %d, due %s" % [
		gone, kept, WelcomePanel.due()])
	if not gone or kept != WelcomePanel.VERSION or WelcomePanel.due():
		_fail("Got it did not put the page away and keep it")
	var hint: Variant = ctrl.get("_menu_hint")
	print("[welprobe] menu hint shown after the page: %s" % (hint != null and is_instance_valid(hint)))
	await get_tree().create_timer(0.5).timeout
	await _shot("welcome_dismissed.png")

	if _menu:
		await _walk_menu(ctrl)

	# ABOUT's "Show the welcome page again".
	ctrl.call("_on_welcome_requested")
	var again := await _wait_for_panel(5.0)
	print("[welprobe] shown again from ABOUT: %s" % (again != null))
	if again == null:
		_fail("ABOUT did not bring the page back")
	else:
		await get_tree().create_timer(1.0).timeout
		again.put_away("welcome_probe")

	for kind: Array in [[false, false], [true, false], [true, true]]:
		await _flat_page(kind[0], kind[1])
	_end()


## The page's clip is there and playing.
func _check_clip(panel: WelcomePanel) -> void:
	var player := panel.page().clip_player() if panel.page() != null else null
	var playing := player != null and player.is_playing()
	print("[welprobe] menu clip: %s, playing %s, at %.1f s" % [
		"present" if player != null else "MISSING", playing,
		player.stream_position if player != null else -1.0])
	if not playing:
		_fail("the menu clip is not playing on the page")


## The headset page's controllers: there, at the stage, pressing each step's button,
## and moving on to the next step.
func _check_demo(panel: WelcomePanel) -> void:
	var demo := panel.demo()
	if demo == null:
		_fail("the headset page has no controller demo")
		return
	print("[welprobe] demo: left %s, right %s" % [demo.source_of("left"), demo.source_of("right")])
	var steps: Array[int] = []
	demo.step_changed.connect(func(i: int, _n: int, _c: String) -> void: steps.append(i))
	var models: Dictionary = demo.get("_models")
	var moved := {}
	# Game time, as the demo runs on: under the movie writer a frame takes longer
	# than its 1/30 s and a clock on the wall would see half the loop.
	var watched := 0.0
	var loop := ControllerDemo.STEP_SECONDS * ControllerDemo.STEPS.size() + 0.6
	while watched < loop:
		watched += get_process_delta_time()
		for hand: String in models:
			var m: Dictionary = models[hand]
			var skel := m["skeleton"] as Skeleton3D
			if skel == null:
				continue
			for bone_name: String in m["driven"]:
				var b := skel.find_bone(bone_name)
				var off := skel.get_bone_pose_position(b).distance_to(skel.get_bone_rest(b).origin) \
					+ skel.get_bone_pose_rotation(b).angle_to(skel.get_bone_rest(b).basis.get_rotation_quaternion()) * 0.01
				moved["%s/%s" % [hand, bone_name]] = maxf(float(moved.get("%s/%s" % [hand, bone_name], 0.0)), off)
		await get_tree().process_frame
	var pressed: Array = []
	for key: String in moved:
		if float(moved[key]) > 0.0005:
			pressed.append(key)
	print("[welprobe] demo pressed: %s; steps reached %s" % [pressed, steps])
	# Every step's own buttons, on its own hand, moved at some point in the loop.
	for step: Dictionary in ControllerDemo.STEPS:
		for bone_name: String in step["press"]:
			var key := "%s/%s" % [step["hand"], bone_name]
			if not key in pressed:
				_fail("the demo never pressed %s (\"%s\")" % [key, step["caption"]])
	if steps.size() < ControllerDemo.STEPS.size():
		_fail("the demo went through %d steps of %d" % [steps.size(), ControllerDemo.STEPS.size()])


## Open the menu and go through it as a player would: CORES, SPAWN, TVs.
func _walk_menu(ctrl: Node3D) -> void:
	ctrl.call("_show_menu")
	await get_tree().create_timer(1.0).timeout
	var vp := ctrl.get_node_or_null("SpawnMenuViewport") as XRToolsViewport2DIn3D
	var menu := vp.get_scene_instance() as Control if vp != null else null
	if menu == null:
		_fail("no menu to walk")
		return
	# Each press, and something only the view it opens shows: a press that lands
	# anywhere else leaves it unseen.
	for step: Array in [["CORES", "Download All Recommended"], ["SPAWN", "Compact"],
			["TVs", "Classic TV"]]:
		var b := _button(menu, step[0])
		await _press_on(vp, b)
		await get_tree().create_timer(1.8).timeout
		var shows := _button_containing(menu, step[1]) != null
		print("[welprobe] menu: pressed %s, '%s' showing: %s" % [step[0], step[1], shows])
		if not shows:
			_fail("pressing %s on the menu did not open it" % step[0])
	await _shot("welcome_menu.png")
	ctrl.call("_hide_menu")
	await get_tree().create_timer(0.6).timeout


func _button_containing(root: Node, part: String) -> Control:
	for node: Node in root.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if b.is_visible_in_tree() and "text" in b and part in str(b.get("text")):
			return b
	return null


func _button(root: Node, label: String) -> Control:
	for node: Node in root.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if b.is_visible_in_tree() and "text" in b and str(b.get("text")) == label:
			return b
	return null


func _controller() -> Node3D:
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("spawn_menu_controller.gd"):
			return n as Node3D
	return null


func _wait_for_panel(seconds: float) -> WelcomePanel:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for n: Node in get_tree().root.find_children("WelcomePanel", "Node3D", true, false):
			if n is WelcomePanel and not n.is_queued_for_deletion():
				return n as WelcomePanel
		await get_tree().process_frame
	return null


## A pointer's enter, press and release on `control`'s centre, through the quad's
## body: the 2D point is mapped back onto the quad as the body maps it forward.
## A cyan dot marks the spot for a moment, so a recording shows where it landed.
func _press_on(vp: XRToolsViewport2DIn3D, control: Control) -> bool:
	# The viewport's OWN body, by name: the menu hosts other quads inside it (the
	# toast popout has a body too), and the last body found was one of those.
	var body := vp.get_node_or_null("StaticBody3D") as Node3D if vp != null else null
	var shape := vp.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D \
		if vp != null else null
	if body == null or shape == null or control == null:
		_fail("no body (%s), shape (%s) or control (%s) to press" % [body, shape, control])
		return false
	var px := control.get_global_rect().get_center()
	var local := Vector3((px.x / vp.viewport_size.x - 0.5) * vp.screen_size.x,
		(0.5 - px.y / vp.viewport_size.y) * vp.screen_size.y, 0.0)
	var at := shape.global_transform * local
	# A bent menu is hit on its arc, which CurvedPanel flattens back to this point.
	var curve := vp.get_node_or_null("CurvedPanel") as CurvedPanel
	if curve != null and curve.is_curved():
		at = curve.global_transform * curve.surface_pose(local.x, local.y, 0.0).origin
	print("[welprobe] pressing %s at %s px, %s in the room" % [control.name, px, at])
	var dot := _dot(at)
	var pointer := Node3D.new()
	add_child(pointer)
	XRToolsPointerEvent.entered(pointer, body, at)
	XRToolsPointerEvent.moved(pointer, body, at, at)
	await get_tree().create_timer(0.35).timeout
	XRToolsPointerEvent.pressed(pointer, body, at)
	XRToolsPointerEvent.released(pointer, body, at)
	XRToolsPointerEvent.exited(pointer, body, at)
	pointer.queue_free()
	get_tree().create_timer(0.4).timeout.connect(dot.queue_free)
	return true


func _dot(at: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.008
	mesh.height = 0.016
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.95, 1.0)
	mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = at
	return mi


## One page, flat, at the panel's own pixel size: the desktop's, the headset's,
## or a Quest's (`android`, its file lines).
func _flat_page(vr: bool, android := false) -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(WelcomePanel.VIEWPORT_SIZE)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sub)
	var page := PAGE.instantiate() as Welcome2D
	page.vr_override = 1 if vr else 0
	page.android_override = 1 if android else 0
	sub.add_child(page)
	for i in 3:
		await get_tree().process_frame
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var file := "welcome_page_%s.png" % ("quest" if android else ("vr" if vr else "desktop"))
	sub.get_texture().get_image().save_png(_out.path_join(file))
	print("[welprobe] wrote %s" % file)
	sub.queue_free()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(file))
	print("[welprobe] wrote %s" % file)


func _fail(why: String) -> void:
	_failed = true
	print("[welprobe] FAIL %s" % why)


func _end() -> void:
	Welcome2D.force_vr = -1
	print("[welprobe] %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
