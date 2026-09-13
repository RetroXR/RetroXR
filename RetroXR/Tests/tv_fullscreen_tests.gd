## tv_fullscreen_tests — the desktop overlay that takes a screen's picture to
## the window. Headless, no core, no headset: a real TV, a Game Boy, a DS and a
## 3DS from the shipped scenes, a camera, a LocomotionManager and the overlay,
## driven through open()/close() rather than the key.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const FULL := Rect2(0, 0, 1, 1)

var _checks := 0
var _failed := 0
var _only := ""
var _camera: Camera3D
var _turn: Node
var _reticle: CanvasLayer
var _loco: LocomotionManager
var _fs: TvFullscreen


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[test] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[test] %d checks, %d failures" % [_checks, _failed])
	print("[test] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[test] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ── fixtures ──────────────────────────────────────────────────────────────────


func _build_rig() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.5, 2.0)
	add_child(_camera)
	_camera.current = true
	_reticle = CanvasLayer.new()
	add_child(_reticle)
	_loco = LocomotionManager.new()
	add_child(_loco)
	_fs = TvFullscreen.new()
	add_child(_fs)
	_fs.configure(_camera, null, _turn_stub(), _reticle, _loco)


## A stand-in for the turn provider: anything with an `enabled` property.
func _turn_stub() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar enabled := true\n"
	script.reload()
	var node := Node.new()
	node.set_script(script)
	add_child(node)
	_turn = node
	return node


func _tv() -> RetroTV:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.position = Vector3(0, 1.5, 0)
	tv.freeze = true
	add_child(tv)
	await _wait(5)
	return tv


func _handheld(systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = Vector3(0, 1.5, 0.5)
	sys.freeze = true
	add_child(sys)
	await _wait(30)
	return sys


func _view() -> Rect2:
	return get_viewport().get_visible_rect()


func _rect_of(i: int) -> Rect2:
	var node := _fs._panels[i]["node"] as TextureRect
	return Rect2(node.position, node.size)


func _near(a: Rect2, b: Rect2, tol := 0.5) -> bool:
	return a.position.distance_to(b.position) <= tol and a.size.distance_to(b.size) <= tol


func _settle() -> void:
	# Past DURATION with margin; the lerp is clamped so overshoot is harmless.
	for i in 40:
		_fs._step(0.05)


# ── cases ─────────────────────────────────────────────────────────────────────


func _run() -> void:
	_build_rig()
	if _want("layout"):
		await _layout()
	if _want("tv"):
		await _tv_cases()
	if _want("freeze"):
		await _freeze_cases()
	if _want("handheld"):
		await _handheld_cases()
	if _want("dual"):
		await _dual_cases()
	if _want("lifetime"):
		await _lifetime_cases()


func _layout() -> void:
	var view := Rect2(0, 0, 1000, 600)
	var one := TvFullscreen.full_rects([4.0 / 3.0], view)
	_ok(one.size() == 1 and _near(one[0], Rect2(100, 0, 800, 600)),
		"layout/one 4:3 panel is height-fitted and centred in a wide window")
	var tall := TvFullscreen.full_rects([16.0 / 9.0], Rect2(0, 0, 400, 600))
	_ok(_near(tall[0], Rect2(0, 187.5, 400, 225)),
		"layout/one wide panel is width-fitted in a tall window")
	var two := TvFullscreen.full_rects([4.0 / 3.0, 4.0 / 3.0], view)
	_ok(two.size() == 2 and _near(two[0], Rect2(300, 0, 400, 300))
		and _near(two[1], Rect2(300, 300, 400, 300)),
		"layout/two panels stack top over bottom and share the window height")
	var mixed := TvFullscreen.full_rects([2.0, 1.0], Rect2(0, 0, 400, 600))
	_ok(_near(mixed[0], Rect2(0, 100, 400, 200)) and _near(mixed[1], Rect2(100, 300, 200, 200)),
		"layout/the widest panel sets the scale and narrower ones centre under it")
	_ok(TvFullscreen.full_rects([], view).is_empty(), "layout/no panels, no rects")

	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.3)
	mesh.mesh = quad
	mesh.position = Vector3(0, 1.5, 0)
	add_child(mesh)
	var whole := TvFullscreen.projected_rect(_camera, mesh, Vector2.ONE)
	var centre := _camera.unproject_position(mesh.global_position)
	_ok(_near(Rect2(whole.get_center(), Vector2.ZERO), Rect2(centre, Vector2.ZERO), 0.01),
		"layout/a projected quad is centred on its projected origin")
	_ok(absf(whole.size.x / whole.size.y - 4.0 / 3.0) < 0.01,
		"layout/a projected face-on quad keeps its aspect")
	var fitted := TvFullscreen.projected_rect(_camera, mesh, Vector2(1.0, 0.5))
	_ok(_near(Rect2(fitted.get_center(), Vector2.ZERO), Rect2(centre, Vector2.ZERO), 0.01)
		and is_equal_approx(fitted.size.y, whole.size.y * 0.5)
		and is_equal_approx(fitted.size.x, whole.size.x),
		"layout/the letterbox fit shrinks about the centre")
	mesh.free()


func _tv_cases() -> void:
	var tv := await _tv()
	_ok(not _fs.is_active(), "tv/idle until asked")
	_ok(TvFullscreen.panels_for(tv).size() == 1, "tv/one panel")
	_ok(_fs.open(tv), "tv/open on a television")
	_ok(_fs.is_active() and _fs.visible, "tv/overlay shown")
	var start := TvFullscreen.projected_rect(_camera, tv.screen_mesh(), tv.display().aspect_fit())
	_ok(_near(_rect_of(0), start), "tv/first frame sits on the glass, letterboxed like the picture")
	_ok(_fs._backdrop.color.a == 0.0, "tv/backdrop clear at the start")
	_ok(_fs._panels[0]["node"].texture == tv.display().screen_texture(),
		"tv/the overlay samples what the glass samples")
	_settle()
	var full := TvFullscreen.full_rects([RetroTV.ASPECT_4_3], _view())[0]
	_ok(_near(_rect_of(0), full), "tv/after the lerp the picture fills the window at 4:3")
	_ok(is_equal_approx(_fs._backdrop.color.a, 1.0), "tv/backdrop opaque once up")
	tv.widescreen = true
	_fs._step(0.0)
	var wide := TvFullscreen.full_rects([RetroTV.ASPECT_16_9], _view())[0]
	_ok(_near(_rect_of(0), wide), "tv/the widescreen button reshapes the window picture")
	tv.widescreen = false
	_ok(not _fs.open(tv), "tv/a second open while up is refused")
	_fs.close()
	_ok(_fs.is_active(), "tv/close starts the return lerp rather than cutting")
	_fs._step(DURATION_HALF())
	_ok(_fs.is_active() and not _near(_rect_of(0), full) and not _near(_rect_of(0), start),
		"tv/mid-return the picture is between window and glass")
	_settle()
	_ok(not _fs.is_active() and _fs._panels.is_empty(), "tv/back on the glass, overlay gone")
	tv.free()
	await _wait(2)


func DURATION_HALF() -> float:
	return TvFullscreen.DURATION * 0.5


func _freeze_cases() -> void:
	var tv := await _tv()
	_reticle.visible = true
	_turn.set("enabled", true)
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE), "freeze/walking free before")
	_fs.open(tv)
	_ok(_loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE), "freeze/walking blocked while up")
	_ok(_turn.get("enabled") == false, "freeze/mouse-look off while up")
	_ok(not _reticle.visible, "freeze/crosshair hidden while up")
	_fs.close()
	_ok(_loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE),
		"freeze/still blocked during the return lerp")
	_settle()
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE), "freeze/walking free after")
	_ok(_turn.get("enabled") == true, "freeze/mouse-look back after")
	_ok(_reticle.visible, "freeze/crosshair back after")
	tv.free()
	await _wait(2)


func _handheld_cases() -> void:
	var gb := await _handheld("game_boy")
	var model := gb.get_model()
	_ok(model != null and model.is_handheld(), "handheld/the Game Boy is a handheld")
	var panels := TvFullscreen.panels_for(gb)
	_ok(panels.size() == 1, "handheld/one panel")
	if panels.is_empty():
		gb.free()
		return
	var screen := model.get_builtin_screen()
	_ok(panels[0]["mesh"] == screen, "handheld/the panel is the HandheldScreen quad")
	_ok(panels[0]["region"] == FULL, "handheld/whole frame")
	var quad := screen.mesh as QuadMesh
	var want := quad.size.x * absf(screen.scale.x) / (quad.size.y * absf(screen.scale.y))
	_ok(is_equal_approx(panels[0]["aspect_fn"].call(), want),
		"handheld/aspect is the authored quad's, no letterbox")
	_ok(panels[0]["fit_fn"].call() == Vector2.ONE, "handheld/no letterbox fit")
	_ok(_fs.open(gb), "handheld/open on a Game Boy")
	_ok(_near(_rect_of(0), TvFullscreen.projected_rect(_camera, screen, Vector2.ONE)),
		"handheld/starts on the panel")
	_ok(_fs._panels[0]["node"].texture == null, "handheld/nothing running, nothing drawn")
	_settle()
	_ok(_near(_rect_of(0), TvFullscreen.full_rects([want], _view())[0]),
		"handheld/fills the window at the panel's aspect")
	_fs.close()
	_settle()
	_ok(not _fs.is_active(), "handheld/back on the panel")

	# A pickable hit deep inside the shell resolves to the machine.
	var target := InteractionTarget.new()
	target.kind = InteractionTarget.KIND_POINTER
	target.hit_node = screen
	_ok(TvFullscreen.device_from_target(target) == gb,
		"handheld/a hit on the screen quad resolves to the machine")
	_ok(TvFullscreen.device_from_target(InteractionTarget.none()) == null,
		"handheld/an empty target resolves to nothing")
	_ok(not _fs.open(null), "handheld/open on nothing is refused")

	# The picture on a TV: the panel is dark, so there is nothing to take.
	var script := GDScript.new()
	script.source_code = "extends RetroSystemModel\nfunc is_handheld() -> bool: return true\nfunc host_picture_on_tv() -> bool: return true\nfunc channel_screens() -> Array[MeshInstance3D]: return []\n"
	script.reload()
	var away := RetroSystemModel.new()
	away.set_script(script)
	var host := SYSTEM_SCENE.instantiate() as RetroSystem
	host.systemid = "game_boy"
	host.freeze = true
	add_child(host)
	await _wait(30)
	host._model = away
	_ok(TvFullscreen.panels_for(host).is_empty(),
		"handheld/cabled to a television, the handheld has no picture to take")
	away.free()
	host._model = null
	host.free()
	gb.free()
	await _wait(2)


func _dual_cases() -> void:
	var ds := await _handheld("nds")
	var model := ds.get_model()
	_ok(model is RetroSystemModelDualScreen, "dual/the DS is a dual-screen model")
	var panels := TvFullscreen.panels_for(ds)
	_ok(panels.size() == 2, "dual/two panels")
	if panels.size() < 2:
		ds.free()
		return
	var screens: Array[MeshInstance3D] = model.channel_screens()
	_ok(panels[0]["mesh"] == screens[0] and panels[1]["mesh"] == screens[1],
		"dual/top then bottom, the order the channels are described in")
	_ok(panels[0]["region"] == Rect2(0, 0, 1, 0.5) and panels[1]["region"] == Rect2(0, 0.5, 1, 0.5),
		"dual/each panel shows its half of the composite")
	_ok(_fs.open(ds), "dual/open on a DS")
	_ok(_near(_rect_of(0), TvFullscreen.projected_rect(_camera, screens[0], Vector2.ONE))
		and _near(_rect_of(1), TvFullscreen.projected_rect(_camera, screens[1], Vector2.ONE)),
		"dual/each panel starts on its own quad")
	_settle()
	var aspects: Array[float] = [panels[0]["aspect_fn"].call(), panels[1]["aspect_fn"].call()]
	var full := TvFullscreen.full_rects(aspects, _view())
	_ok(_near(_rect_of(0), full[0]) and _near(_rect_of(1), full[1]),
		"dual/top over bottom, both inside the window")
	_ok(_rect_of(0).end.y <= _rect_of(1).position.y + 0.5, "dual/top panel sits above the bottom")

	# Region cropping goes through an atlas over the live texture.
	var tex := ImageTexture.create_from_image(Image.create(256, 384, false, Image.FORMAT_RGB8))
	_fs._panels[1]["texture_fn"] = func() -> Texture2D: return tex
	_fs._step(0.0)
	var atlas := _fs._panels[1]["node"].texture as AtlasTexture
	_ok(atlas != null and atlas.atlas == tex and atlas.region == Rect2(0, 192, 256, 192),
		"dual/the bottom panel is the lower half of the frame, in pixels")
	_fs.close()
	_settle()
	ds.free()
	await _wait(2)

	var n3ds := await _handheld("3ds")
	var stereo := TvFullscreen.panels_for(n3ds)
	_ok(stereo.size() == 2 and stereo[0]["region"] == Rect2(0, 0, 0.5, 0.5),
		"dual/a stereo top screen shows the left eye as its channel already describes")
	n3ds.free()
	await _wait(2)


func _lifetime_cases() -> void:
	var tv := await _tv()
	_fs.open(tv)
	_settle()
	_ok(_fs.is_active(), "lifetime/up")
	tv.free()
	await _wait(1)
	_ok(not _fs.is_active() and _fs._panels.is_empty(), "lifetime/device freed, overlay gone at once")
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE),
		"lifetime/device freed, walking released")

	get_viewport().use_xr = true
	var tv2 := await _tv()
	_ok(not _fs.open(tv2), "lifetime/no-op in XR")
	get_viewport().use_xr = false
	tv2.free()
	await _wait(2)
