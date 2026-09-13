## Memory card panel resize probe -- does the corner grip grow the page, keep its
## bottom edge above the card, stop at its limits, and go dead when hidden?
##
## Every card family opens the same MemoryCardPanel, so one card stands for all.
## Windowed, because the page is a SubViewport:
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/vr/memcard_panel_resize_probe.tscn
##
## The drag goes the way a laser's does: press on the grip, then swing the same
## pointer's aim away across the room, off the grip. Writes before and after
## shots to res://probe_out/. Exits non-zero on failure.
extends Node

const VMU_SCENE := preload("res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn")
const PANEL_SCENE := preload("res://Scenes/UI/memory_card_panel.tscn")

var _fail := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	await _run()
	print("[probe] ---- %s ----" % ("all checks passed" if _fail == 0 else "%d FAILED" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, what: String, detail := "") -> void:
	if not cond:
		_fail += 1
	print("[probe] %s  %s%s" % ["PASS" if cond else "FAIL", what,
		"" if detail.is_empty() else "  - " + detail])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shoot(sv: SubViewport, path: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out"))
	img.save_png(path)
	print("[probe] wrote %s" % path)


## The page's bottom-left and top-right corners, in world space.
func _corners(v: XRToolsViewport2DIn3D) -> Array[Vector3]:
	var h := v.screen_size * 0.5
	return [v.global_transform * Vector3(-h.x, -h.y, 0.0),
		v.global_transform * Vector3(h.x, h.y, 0.0)]


func _run() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 900)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	sv.add_child(env)

	var card := VMU_SCENE.instantiate() as VmuCard
	sv.add_child(card)
	card.freeze = true
	var eye := Vector3(0.0, 0.40, 1.1)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.look_at_from_position(eye, Vector3(0.0, 0.40, 0.0), Vector3.UP)
	cam.fov = 40.0
	cam.current = true
	var panel := PANEL_SCENE.instantiate() as MemoryCardPanel
	sv.add_child(panel)
	await _frames(2)
	panel.show_for(card, cam)
	await _frames(8)

	var v := panel.get_node("MemoryCardViewport") as XRToolsViewport2DIn3D
	var grip := v.get_node_or_null("ResizeGrip") as PanelResizeGrip
	_ok(grip != null, "the card panel has a corner grip")
	if grip == null:
		return
	_ok(grip.collision_layer != 0, "and it can be pointed at while the panel shows")
	var px0 := v.viewport_size
	var density0 := v.viewport_size / v.screen_size
	var c0 := _corners(v)
	_ok(grip.global_position.distance_to(c0[1]) < 0.02, "the grip sits on the top-right corner",
		"%.1f mm away" % (grip.global_position.distance_to(c0[1]) * 1000.0))
	await _shoot(sv, "res://probe_out/memcard_panel_before.png")

	var pointer := Node3D.new()
	sv.add_child(pointer)
	var grip_start := grip.global_position
	var delta := Vector3(0.10, 0.12, 0.0)
	pointer.look_at_from_position(eye, grip_start, Vector3.UP)
	panel.resize_begin(pointer)
	for i in range(1, 13):
		pointer.look_at_from_position(eye, grip_start + delta * (float(i) / 12.0), Vector3.UP)
		await get_tree().process_frame
	await _frames(3)
	panel.resize_end()
	await _frames(2)

	var c1 := _corners(v)
	var density1 := v.viewport_size / v.screen_size
	_ok(v.viewport_size.x > px0.x and v.viewport_size.y > px0.y,
		"dragging the corner out grows the page", "%s -> %s" % [px0, v.viewport_size])
	_ok(density1.distance_to(density0) < 1.0,
		"at the same pixels per metre, so the text keeps its size", "%s -> %s" % [density0, density1])
	_ok(absf(c1[0].y - c0[0].y) < 0.002, "and the bottom edge stays where it was",
		"%.4f -> %.4f" % [c0[0].y, c1[0].y])
	var want := c0[1] + delta
	_ok(c1[1].distance_to(want) < 0.02, "the top-right corner follows the pointer",
		"off by %.1f mm" % (c1[1].distance_to(want) * 1000.0))
	_ok(grip.global_position.distance_to(c1[1]) < 0.02, "and the grip moves with the corner")

	# The panel's own quad must not be the scene's shared one, or every other
	# card's panel is resized with it. A second panel's _ready writes the authored
	# size into whatever mesh it was handed, so a shared mesh shows up here.
	var other := PANEL_SCENE.instantiate() as MemoryCardPanel
	sv.add_child(other)
	await _frames(2)
	var mine := (v.get_node("Screen") as MeshInstance3D).mesh as QuadMesh
	_ok(mine != null and mine.size.is_equal_approx(v.screen_size),
		"a second card's panel leaves this one's size alone",
		"%s vs %s" % [str(mine.size if mine != null else Vector2.ZERO), v.screen_size])
	await _shoot(sv, "res://probe_out/memcard_panel_after.png")

	panel.resize_page(Vector2(100000, 100000))
	await _frames(2)
	_ok(v.viewport_size.x <= px0.x * 2.5 + 0.5 and v.viewport_size.y <= px0.y * 2.5 + 0.5,
		"the page stops at two and a half times its size", str(v.viewport_size))
	panel.resize_page(Vector2(1, 1))
	await _frames(2)
	_ok(v.viewport_size.is_equal_approx(px0), "and never shrinks below where it started",
		"%s vs %s" % [v.viewport_size, px0])
	_ok(absf(_corners(v)[0].y - c0[0].y) < 0.002, "and comes back down to the same bottom edge")

	panel.hide_panel()
	await _frames(2)
	var shape: CollisionShape3D = null
	for c in grip.get_children():
		if c is CollisionShape3D:
			shape = c
	_ok(grip.collision_layer == 0, "a hidden panel's grip leaves the pointable layer")
	_ok(shape != null and shape.disabled, "and its collision shape is off")
