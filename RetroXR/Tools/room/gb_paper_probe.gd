## gb_paper_probe — how the Game Boy Printer's paper LOOKS: a real printer on a
## real table printing a metre of paper, which lies across the table and over its
## edge; then the printer carried along the table with its paper trailing. Writes
## numbered frames (for an mp4) and three stills.
##
##     "$godot" --path RetroXR --resolution 960x540 --position 20,20 res://Tools/room/gb_paper_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing. `--length=0.6`
## prints less; `--speed=0.08` is the paper's speed out of the slot, m/s (the real
## printer's is nearer 0.01, which is a long film).
extends Node3D

const PRINTER := preload("res://Scenes/Objects/peripherals/gb_printer.tscn")
const TABLE_TOP := 0.75
const DT := 1.0 / 60.0

var out_dir := ""
var length := 1.0
var speed := 0.08
var _frame := 0
var _cam: Camera3D
const VIEW_FROM := Vector3(0.55, TABLE_TOP + 0.33, 0.22)
const VIEW_AT := Vector3(0.0, TABLE_TOP + 0.02, -0.2)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--length="):
			length = float(arg.trim_prefix("--length="))
		elif arg.begins_with("--speed="):
			speed = float(arg.trim_prefix("--speed="))
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("gb_paper_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	Engine.max_fps = 60
	_build_room()
	_run.call_deferred()


func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.31, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	# A table 1.0 x 0.6 m; the paper runs back along it and over its far edge.
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.03, 1.0)
	shape.shape = box
	table.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.13)
	wood.roughness = 0.7
	bm.material = wood
	mesh.mesh = bm
	table.add_child(mesh)
	table.position = Vector3(0.0, TABLE_TOP - 0.015, -0.3)
	add_child(table)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(6, 0.2, 6)
	fs.shape = fb
	fs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(fs)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.5, 0.48, 0.45)
	plane.material = fmat
	fm.mesh = plane
	floor_body.add_child(fm)
	add_child(floor_body)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 45
	_cam.current = true
	_look(VIEW_FROM, VIEW_AT)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)


## A picture to print: a row of marks every 3 cm, so stretch and twist show.
func _picture(lines: int) -> Image:
	var img := Image.create(GbPrinterPaper.DOTS, lines, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in lines:
		var band := y % 218
		for x in GbPrinterPaper.DOTS:
			var dark := false
			if band < 6:
				dark = true
			elif band > 60 and band < 160:
				var cx := x - 80
				var cy := band - 110
				dark = cx * cx + cy * cy < 1600 and (cx * cx + cy * cy > 900 or (x / 8 + y / 8) % 2 == 0)
			if dark:
				img.set_pixel(x, y, Color.BLACK)
	return img


func _shot(name: String) -> void:
	# The boot's loading panel covers the main viewport until a room says it is
	# ready, and comes up after the first frames: put aside before every picture.
	LoadingOverlay.suspend()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))


func _film() -> void:
	await _shot("frame_%04d.png" % _frame)
	_frame += 1


func _run() -> void:
	if not GbThermalRibbon.has_solver():
		print("[probe] FAIL: paper-godot has no PaperSheetSolver")
		get_tree().quit(1)
		return
	var printer := PRINTER.instantiate() as GbPrinter
	add_child(printer)
	printer.freeze = true
	printer.global_position = Vector3(0.0, TABLE_TOP + 0.0305, 0.1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var total := int(length / GbPrinter.DOT_PITCH)
	var picture := _picture(total)
	var paper := printer.paper()
	var out := GbPrinter.STUB_LENGTH
	var sharpest := 0.0
	var tick := 0
	var stills := {0.15: "still_15cm.png", 0.4: "still_40cm.png"}
	while out < length:
		out = minf(length, out + speed * DT)
		var lines := maxi(1, int(out / GbPrinter.DOT_PITCH))
		var tex := ImageTexture.create_from_image(picture.get_region(Rect2i(0, total - lines, GbPrinterPaper.DOTS, lines)))
		printer._lay_paper(tex, lines)
		await get_tree().process_frame
		sharpest = maxf(sharpest, paper.sharpest_turn())
		tick += 1
		if tick % 4 == 0:
			await _film()
		for at: float in stills.keys():
			if out >= at:
				await _shot(stills[at])
				print("[probe] %.0f cm out: sharpest turn so far %.0f deg" % [at * 100.0, rad_to_deg(sharpest)])
				stills.erase(at)
	var settled := await _settle(printer)
	await _shot("still_full.png")
	var lowest := INF
	var side := 0.0
	for p in paper.positions:
		lowest = minf(lowest, printer.to_global(p).y)
		side = maxf(side, absf(p.x))
	print("[probe] %.2f m printed: %d rows of %.0f mm, sharpest turn while printing %.0f deg, at rest %.0f deg; lowest point %.3f m (table top %.3f); %.0f mm to the side; at rest after %.1f s" % [
		paper.out, paper.segments + 1, paper.ds * 1000.0, rad_to_deg(sharpest), rad_to_deg(paper.sharpest_turn()),
		lowest, TABLE_TOP, side * 1000.0, settled])
	# From above the far end, where the old strip stood in pleats.
	_look(Vector3(0.3, TABLE_TOP + 0.1, -0.02), Vector3(0.0, TABLE_TOP + 0.02, -0.25))
	await get_tree().process_frame
	await _shot("still_close.png")
	_look(VIEW_FROM, VIEW_AT)
	# Carried 20 cm along the table and set down: the paper trails and follows.
	var from := printer.global_position
	for i in 150:
		var t := smoothstep(0.0, 1.0, i / 90.0)
		printer.global_position = from + Vector3(0.2 * t, 0.0, 0.0)
		await get_tree().physics_frame
		await get_tree().process_frame
		sharpest = maxf(sharpest, paper.sharpest_turn())
		if i % 4 == 0:
			await _film()
	settled = await _settle(printer)
	await _shot("still_carried.png")
	print("[probe] carried 20 cm: sharpest turn %.0f deg, at rest after %.1f s; %d frames in %s" % [
		rad_to_deg(sharpest), settled, _frame, out_dir])
	get_tree().quit(0)


## Film until the paper rests (15 s at most); how long that took, seconds.
func _settle(printer: GbPrinter) -> float:
	var frames := 0
	while frames < 900 and not (printer._paper_resting and frames > 30):
		await get_tree().process_frame
		if frames % 4 == 0:
			await _film()
		frames += 1
		if frames % 120 == 0 and OS.get_cmdline_user_args().has("--trace"):
			var paper := printer.paper()
			var fast := 0
			for i in paper.velocities.size():
				if paper.velocities[i].length() > paper.velocities[fast].length():
					fast = i
			@warning_ignore("integer_division")
			print("[probe]   %d s: %.2f mm/s; fastest row %d of %d (side %d) at %s moving %s; %d patches" % [
				frames / 60, paper.move_speed * 1000.0, fast / 2, paper.segments + 1, fast % 2,
				printer.to_global(paper.positions[fast]) - Vector3(0, TABLE_TOP, 0), paper.velocities[fast], paper.patches.size()])
	return frames / 60.0 if printer._paper_resting else -1.0
