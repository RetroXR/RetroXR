## Films an NES-001 being hooked up in the bedroom, for the welcome page's second page
## (Welcome2D.HOOKUP_CLIP): the AV lead into the console and the set, a pad into port
## 1, the flap up, a cartridge laid in the tray and pressed down, the flap shut, POWER,
## and START on the pad -- every step through the same calls a hand's own makes
## (snap zones' pick_up_object, the model's flap and tray, the POWER VRButton), with a
## real core running a real homebrew ROM on the set at the end.
##
## Its own camera in a SubViewport, captions drawn over it, and the frames taken on
## the WALL clock at FPS (a slow frame is repeated, never stretched), because the core
## runs on its own thread in real time and a game-time video would show it fast or
## slow. The bedroom's PlayerRig is taken out, as bedroom_probe's --empty-room does:
## it is what restores the player's saved room, and no welcome page or menu belongs in
## the film. Mods off (--no-mods), so it is the stock NES.
##
## WINDOWED (headless draws nothing):
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 \
##         res://Tools/room/nes_hookup_probe.tscn -- --no-mods --out=/tmp/hookup \
##         [--rom=res://Tools/room/roms/brix.nes] [--core=fceumm] [--layout]
##     python Tools/art/encode_welcome_clip.py /tmp/hookup --clip hookup
##
## --layout places everything already connected and saves a still from each framing,
## to tune the stage by; nothing is recorded.
extends Node

const ROOM := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/mono_composite_cable.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/nes/nes_controller.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const TABLE_SCENE := preload("res://Scenes/Objects/furniture/table.tscn")

## BrickBreaker by Aleff Correa, MIT (roms/LICENSE-brix.txt).
const DEFAULT_ROM := "res://Tools/room/roms/brix.nes"
const GAME_LABEL := "BrickBreaker"
const START_BIT := 1 << 3

const FPS := 30
const SIZE := Vector2i(1280, 720)

## The stage: a table out from the wall with the string lights, its top found by
## casting down. The console and the set side by side, both facing the camera; the
## table stands 0.35 m clear of the wall so a camera fits behind the set, where its
## inputs are. The pad, the cart and the lead lie in front.
const DESK_XZ := Vector2(-1.4, -1.5)

var _out := ""
var _layout := false
var _rom := ""
var _core := "fceumm"
var _sv: SubViewport = null
var _cam: Camera3D = null
var _caption: Label = null
var _caption_box: PanelContainer = null
var _t0 := -1
var _frames := 0
var _recording := false
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_t := 1.0
var _cam_len := 1.0
var _failed := false

var _sys: RetroSystem = null
var _tv: RetroTV = null
var _cable: Node3D = null
var _pad: Node3D = null
var _cart: Node3D = null
var _top := 0.75
## The console's front, level, once it is turned to the camera.
var _front := Vector3.BACK


func _ready() -> void:
	_rom = ProjectSettings.globalize_path(DEFAULT_ROM)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--layout":
			_layout = true
		elif a.begins_with("--rom="):
			_rom = ProjectSettings.globalize_path(a.trim_prefix("--rom="))
		elif a.begins_with("--core="):
			_core = a.trim_prefix("--core=")
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("[hookup] TIMEOUT")
		get_tree().quit(1))
	print("[hookup] rom %s (exists %s), core %s" % [_rom, FileAccess.file_exists(_rom), _core])
	_run()


func _run() -> void:
	var room := ROOM.instantiate()
	var rig := room.get_node_or_null("PlayerRig")
	if rig != null:
		room.remove_child(rig)
		rig.free()
	add_child(room)
	_build_camera()
	var waited := 0
	while LoadingOverlay.is_active() and waited < 600:
		await get_tree().process_frame
		waited += 1
	LoadingOverlay.suspend()
	await _stage()
	if _failed:
		_end()
		return
	if _layout:
		await _connect_all_now()
		for shot: String in ["wide", "jacks", "tv_back", "front", "slot", "tv"]:
			_frame_on(shot, 0.0)
			await _tick(10)
			await _save_still("layout_%s.png" % shot)
		_end()
		return
	await _film()
	_end()


# ── the stage ─────────────────────────────────────────────────────────────────

func _stage() -> void:
	var table := TABLE_SCENE.instantiate() as Node3D
	table.set("freeze", true)
	add_child(table)
	table.global_position = Vector3(DESK_XZ.x, 0.0, DESK_XZ.y)
	await _settle(10)
	_top = _surface_y(DESK_XZ)
	print("[hookup] table top at %.3f m" % _top)
	var base := Vector3(DESK_XZ.x, _top, DESK_XZ.y)
	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.tv_model = "retroxr_crt"
	_tv.freeze = true
	add_child(_tv)
	_tv.global_position = base + Vector3(0.12, 0.0, -0.08)
	_tv.add_to_group("spawned")

	_sys = SYSTEM_SCENE.instantiate() as RetroSystem
	_sys.systemid = "nes"
	_sys.model_id = "nes"
	_sys.core_name = _core
	_sys.freeze = true
	add_child(_sys)
	_sys.global_position = base + Vector3(-0.36, 0.06, -0.05)
	_sys.add_to_group("spawned")

	_cart = CART_SCENE.instantiate() as Node3D
	_cart.set("rom_path", _rom)
	_cart.set("systemid", "nes")
	_cart.set("game_label", GAME_LABEL)
	_cart.set("freeze", true)
	add_child(_cart)
	_cart.global_position = base + Vector3(-0.08, 0.03, 0.25)
	_cart.rotation_degrees = Vector3(-90, 0, 0)

	_pad = PAD_SCENE.instantiate() as Node3D
	_pad.set("freeze", true)
	add_child(_pad)
	_pad.global_position = base + Vector3(-0.62, 0.03, 0.27)
	_pad.add_to_group("spawned")

	_cable = CABLE_SCENE.instantiate() as Node3D
	add_child(_cable)
	_cable.global_position = base + Vector3(0.25, 0.05, 0.27)
	await _settle(200)
	# The console's front to the camera, the way the set faces. The front is the
	# console's own axis nearest its controller ports: the ports sit right of the
	# middle, so aiming at them turned it 37 deg off.
	var front := _front_axis()
	_sys.rotate_y(-atan2(front.x, front.z))
	print("[hookup] console turned %.0f deg so its front faces the camera"
		% rad_to_deg(atan2(front.x, front.z)))
	await _settle(10)
	# Both stood ON the table: placed by their origins they were not (the set's
	# origin is not its underside, and it sat sunk into the top).
	_rest_on(_tv, _top)
	_rest_on(_sys, _top)
	await _settle(30)
	_front = _front_axis()
	print("[hookup] staged: console %s, set %s, pad plug %s" % [_sys.global_position,
		_tv.global_position, _pad.call("get_plug") if _pad.has_method("get_plug") else null])
	for need: Array in [["VideoOut", _sys], ["AudioLOut", _sys], ["CompositePort", _tv],
			["AudioLIn", _tv], ["ControllerPort1", _sys], ["CartridgeSlot", _sys], ["PowerButton", _sys]]:
		if (need[1] as Node).find_child(need[0], true, false) == null:
			_fail("no %s on %s" % [need[0], (need[1] as Node).name])


## Everything connected at once, no motion: for --layout.
func _connect_all_now() -> void:
	_port(_sys, "VideoOut").pick_up_object(_plug("PlugA0"))
	_port(_sys, "AudioLOut").pick_up_object(_plug("PlugA1"))
	_port(_tv, "CompositePort").pick_up_object(_plug("PlugB0"))
	_port(_tv, "AudioLIn").pick_up_object(_plug("PlugB1"))
	_port(_sys, "ControllerPort1").pick_up_object(_pad.call("get_plug"))
	_sys.restore_cartridge(_cart)
	await _settle(60)


# ── the film ──────────────────────────────────────────────────────────────────

func _film() -> void:
	_recording = true
	_t0 = Time.get_ticks_msec()
	_say("The NES, a TV, an AV lead, a pad and a cartridge")
	_frame_on("wide", 0.0)
	await _hold(2.0)

	_say("1  The AV lead into the console: yellow is the picture, red the sound")
	_frame_on("jacks", 1.2)
	await _hold(1.2)
	await _seat(_plug("PlugA0"), _port(_sys, "VideoOut"), 1.1)
	await _seat(_plug("PlugA1"), _port(_sys, "AudioLOut"), 1.1)
	await _hold(0.6)

	_say("2  ...and into the TV's inputs, yellow to yellow, red to red")
	_frame_on("tv_back", 1.2)
	await _hold(1.2)
	await _seat(_plug("PlugB0"), _port(_tv, "CompositePort"), 1.1)
	await _seat(_plug("PlugB1"), _port(_tv, "AudioLIn"), 1.1)
	await _hold(0.6)

	_say("3  A controller into port 1")
	_frame_on("front", 1.2)
	await _hold(1.0)
	await _seat(_pad.call("get_plug") as Node3D, _port(_sys, "ControllerPort1"), 1.2)
	await _hold(0.6)

	var model := _sys.get_model()
	_frame_on("slot", 1.0)
	await _hold(1.0)
	_say("4  Lift the flap")
	model.call("play_open")
	await _hold(1.0)
	_say("5  Lay the cartridge in the tray...")
	var slot := _port(_sys, "CartridgeSlot")
	await _seat(_cart, slot, 1.4, "preview")
	await _hold(0.6)
	_say("6  ...and press it down until it clicks")
	_sys.toggle_cart_tray()
	await _hold(1.2)
	_say("7  Shut the flap")
	model.call("play_close")
	await _hold(1.0)
	print("[hookup] tray down %s, reading %s" % [_sys.is_tray_down(), _sys.get_snapped_cartridge() == _cart])
	if not _sys.is_tray_down():
		_fail("the tray did not latch down")

	_say("8  Press POWER")
	await _hold(0.6)
	(_sys.get_node("PowerButton") as VRButton).button_pressed.emit()
	await _hold(1.0)
	_frame_on("tv", 1.4)
	var shown := await _wait_for_picture(12.0)
	print("[hookup] powered %s, picture on the set %s" % [_sys.is_powered_on, shown])
	if not shown:
		_fail("no picture on the set")
	_say("The game is on. Press START on the controller to play")
	await _hold(3.0)

	_say("9  START")
	var before := _snapshot()
	var poke := PressPoke.new(_pad)
	_pad.set("_poke", poke)
	poke.held = START_BIT
	await _hold(0.35)
	poke.held = 0
	await _hold(2.0)
	var changed := _changed(before, _snapshot())
	print("[hookup] the game changed after START: %s" % changed)
	if not changed:
		_fail("START changed nothing on the set")
	# BrickBreaker's first START shows its instructions; the second starts play.
	_say("10  START again, and play")
	poke.held = START_BIT
	await _hold(0.35)
	poke.held = 0
	await _hold(3.0)
	_say("That is all there is to it. Every console in the room works the same way")
	await _hold(3.0)
	_recording = false
	print("[hookup] wrote %d frames (%.1f s)" % [_frames, float(_frames) / FPS])


## Move `obj` to just off `zone`'s seat (or its preview perch) over `seconds`, then
## seat it with the zone's own pick_up_object, as a hand letting go there does.
func _seat(obj: Node3D, zone: XRToolsSnapZone, seconds: float, aim := "seat") -> void:
	if obj == null or zone == null:
		_fail("nothing to seat (%s into %s)" % [obj, zone])
		return
	var seat := zone.preview_pose_for(obj) if aim == "preview" else zone.snap_pose_for(obj)
	# Just off the seat, back along the way it goes in and a little above, so the
	# last stretch reads as pushing it home.
	var back := seat.origin + seat.basis.z.normalized() * 0.06 + Vector3.UP * 0.03
	var start := obj.global_transform
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	var n := maxi(1, int(seconds * FPS))
	for i in n:
		var k := smoothstep(0.0, 1.0, float(i + 1) / n)
		var to := Transform3D(start.basis.slerp(seat.basis, k),
			start.origin.lerp(back, k) if k < 0.85 else back.lerp(seat.origin, (k - 0.85) / 0.15))
		obj.global_transform = to
		await _tick(1)
	zone.pick_up_object(obj)
	await _hold(0.3)


func _wait_for_picture(seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _sys.is_powered_on and _sys.sends_video_to(_tv) and _sys.get_video_texture() != null:
			return true
		await _tick(1)
	return false


func _snapshot() -> Image:
	var tex := _sys.get_video_texture()
	return tex.get_image() if tex != null else null


func _changed(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return a != b
	return a.get_data() != b.get_data()


# ── camera, captions, frames ──────────────────────────────────────────────────

func _build_camera() -> void:
	_sv = SubViewport.new()
	_sv.size = SIZE
	_sv.own_world_3d = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.02
	_cam.fov = 55.0
	_sv.add_child(_cam)
	_cam.current = true
	_caption_box = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.1, 0.78)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 22
	bg.content_margin_right = 22
	bg.content_margin_top = 10
	bg.content_margin_bottom = 12
	_caption_box.add_theme_stylebox_override("panel", bg)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_caption_box.add_child(_caption)
	_sv.add_child(_caption_box)
	_caption_box.visible = false


func _say(text: String) -> void:
	_caption.text = text
	_caption_box.visible = true
	_caption_box.reset_size()
	_caption_box.position = Vector2((SIZE.x - _caption_box.get_combined_minimum_size().x) * 0.5, SIZE.y - 86)
	print("[hookup] %s" % text)


## Point the camera at a part of the stage, easing there over `seconds`.
func _frame_on(shot: String, seconds: float) -> void:
	var target := Vector3.ZERO
	var eye := Vector3.ZERO
	match shot:
		"wide":
			target = (_sys.global_position + _tv.global_position) * 0.5 + Vector3(0, 0.1, 0)
			eye = target + Vector3(0.2, 0.5, 1.15)
		"jacks":
			# The console's jack side, which faces the set.
			target = _port(_sys, "VideoOut").global_position
			eye = target + Vector3.BACK * 0.42 + Vector3.UP * 0.24 + Vector3.RIGHT * 0.12
		"tv_back":
			# The set's inputs are on its back, against the window: looked down on
			# from above its right shoulder.
			# From behind the set, looking down at its input panel: the table stands
			# clear of the wall for this.
			target = _port(_tv, "CompositePort").global_position
			var tv_back := -_tv.global_transform.basis.z
			tv_back.y = 0.0
			eye = target + tv_back.normalized() * 0.26 + Vector3.UP * 0.3 + Vector3.RIGHT * 0.12
		"front":
			target = (_port(_sys, "ControllerPort1").global_position
				+ _port(_sys, "ControllerPort2").global_position) * 0.5
			eye = target + _front * 0.5 + Vector3.UP * 0.28 + Vector3.LEFT * 0.08
		"slot":
			target = _port(_sys, "CartridgeSlot").global_position
			eye = target + _front * 0.38 + Vector3.UP * 0.34
		"tv":
			# Aimed below the screen's middle, so the set sits high in the frame and
			# the caption bar under it covers table, not picture.
			var tv_front := _tv.global_transform.basis.z.normalized()
			target = _tv.global_position + Vector3(0, -0.02, 0) + tv_front * 0.12
			eye = target + tv_front * 0.75 + Vector3.UP * 0.12
	var to := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	if seconds <= 0.0:
		_cam.global_transform = to
		_cam_t = 1.0
		return
	_cam_from = _cam.global_transform
	_cam_to = to
	_cam_len = seconds
	_cam_t = 0.0


## Lift or lower `body` so the lowest point it draws sits at `y`.
func _rest_on(body: Node3D, y: float) -> void:
	var box := _world_bounds(body)
	if box.size.length() < 0.001:
		print("[hookup] %s draws nothing to stand on; left where it is" % body.name)
		return
	body.global_position.y += y - box.position.y
	print("[hookup] %s stood on the table (its underside was %+.3f m off it)"
		% [body.name, box.position.y - y])


## Everything `node` draws, in world space. A cord or plug hanging off it is not
## part of it, so pickables under it are skipped.
func _world_bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for vis: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var g := vis as GeometryInstance3D
		if not g.is_visible_in_tree() or _under_pickable(g, node):
			continue
		var b := g.global_transform * g.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _under_pickable(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is XRToolsPickable:
			return true
		p = p.get_parent()
	return false


## The console's front, level: whichever of its own four sides the controller
## ports are on.
func _front_axis() -> Vector3:
	var mid := (_port(_sys, "ControllerPort1").global_position
		+ _port(_sys, "ControllerPort2").global_position) * 0.5
	var b := _sys.global_transform.basis.orthonormalized()
	var local := b.inverse() * (mid - _sys.global_position)
	var axis := Vector3(signf(local.x), 0, 0) if absf(local.x) > absf(local.z) \
		else Vector3(0, 0, signf(local.z))
	var world := b * axis
	world.y = 0.0
	return world.normalized()


## Which way is "out" from `body` at `point`, level.
func _outward(body: Node3D, point: Vector3) -> Vector3:
	var d := point - body.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.BACK


func _process(delta: float) -> void:
	if _cam_t < 1.0 and _cam != null:
		_cam_t = minf(1.0, _cam_t + delta / _cam_len)
		var k := smoothstep(0.0, 1.0, _cam_t)
		_cam.global_transform = Transform3D(_cam_from.basis.slerp(_cam_to.basis, k),
			_cam_from.origin.lerp(_cam_to.origin, k))


## `n` frames, each written as many times as the wall clock says it is owed.
func _tick(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		if not _recording:
			continue
		var owed := int((Time.get_ticks_msec() - _t0) * FPS / 1000.0) + 1
		if owed <= _frames:
			continue
		var img := _sv.get_texture().get_image()
		var first := _out.path_join("f_%05d.jpg" % _frames)
		img.save_jpg(first, 0.92)
		_frames += 1
		while _frames < owed:
			DirAccess.copy_absolute(first, _out.path_join("f_%05d.jpg" % _frames))
			_frames += 1


func _hold(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await _tick(1)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _save_still(name: String) -> void:
	await RenderingServer.frame_post_draw
	_sv.get_texture().get_image().save_png(_out.path_join(name))
	print("[hookup] wrote %s" % name)


func _surface_y(xz: Vector2) -> float:
	var space := _cam.get_world_3d().direct_space_state
	# Every layer: furniture is not on the world layer the room's walls and floor are.
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 2.2, xz.y), Vector3(xz.x, -0.5, xz.y),
		0xFFFFFFFF)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _port(body: Node, port_name: String) -> XRToolsSnapZone:
	return body.find_child(port_name, true, false) as XRToolsSnapZone


func _plug(plug_name: String) -> Node3D:
	return _cable.get_node_or_null(plug_name) as Node3D


func _fail(why: String) -> void:
	_failed = true
	print("[hookup] FAIL %s" % why)


func _end() -> void:
	print("[hookup] %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


## A fingertip on the pad that holds whatever bits `held` names: the pad merges it
## into what it sends (AnimatedController._send_joypad), so the core reads it and
## the cap is drawn down, as a real finger's press is.
class PressPoke extends ControlPoke:
	var held := 0

	func poll() -> Dictionary:
		return {"btn": held, "lstick": Vector2.ZERO, "rstick": Vector2.ZERO}
