## A Game Boy printing to the Game Boy Printer in the room, cabled the way a hand
## cables it.
##
##     "$godot" --path RetroXR res://Tools/link/gb_printer_room_probe.tscn --resolution 960x720 --position 20,20 [-- --core=mgba] [-- --frames]
##
## gb_printer_probe drives the two cores directly. This drives the path a PLAYER
## uses: a Game Boy stand-in and a GbPrinter side by side, the printer switched on
## by its own power path, the ordinary dmg_link_cable pushed into both sockets
## through their snap zones -- and then the printer's own strip, its tear, and the
## printout that tear leaves standing in the room.
##
## WINDOWED, never --headless: the dummy renderer hands back blank frames, and the
## pictures are the proof (probe_out/gb_printer_room_*.png; --frames also writes
## the frames an mp4 of the paper coming out is made from).
##
## Writes a print into the player's REAL prints folder, because that is where a
## tear writes it, and deletes it again before it quits.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CABLE_SCENE := "res://Scenes/Objects/cables/dmg_link_cable.tscn"
const PRINTER_SCENE := "res://Scenes/Objects/peripherals/gb_printer.tscn"
const ROM := "res://Tools/gblink/printer.gb"
const EXPECTED := "res://Tools/gblink/printer_expected.png"
const OPTIONS := {
	"gambatte": [["gambatte_gb_link_mode", "Link Cable"], ["gambatte_gb_bootloader", "disabled"]],
	"mgba": [["mgba_link_cable", "ON"], ["mgba_use_bios", "OFF"],
		["mgba_gb_model", "Game Boy"], ["mgba_sgb_borders", "OFF"]],
}
const OUT := "res://probe_out"

var _core := "gambatte"
var _frames_out := false
var _pass := 0
var _fail := 0
var _opt_path := ""
var _opt_backup := ""
var _had_opt := false
var _restored := false
var _written: Array[String] = []
var _frame_no := 0
## Frames for the mp4, kept in memory and written after: encoding a PNG every
## frame slowed the capture to a few a second.
var _film: Array[Image] = []
var _cam: Camera3D = null
## Everything drawn that is not under one of these is hidden for a picture: a
## console floats status and options panels beside itself, and they stand right
## in front of the camera (sega32x_probe's reason).
var _keep: Array[Node] = []


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[gb-printer-room] TIMEOUT")
		_finish())
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_core = arg.substr(7)
		elif arg == "--frames":
			_frames_out = true
	var root := CoreDownloadManager.default_core_root()
	for core in [_core, GbPrinter.CORE]:
		if CoreDownloadManager.installed_core_lib(core).is_empty():
			print("[gb-printer-room] SKIP  the %s core is not installed" % core)
			get_tree().quit(0)
			return
	if not FileAccess.file_exists(ProjectSettings.globalize_path(ROM)):
		print("[gb-printer-room] SKIP  run Tools/gen_gblink_rom.py first")
		get_tree().quit(0)
		return
	_write_options(root)
	_stage()

	# The Game Boy, exactly as the room builds one, and the printer from its scene.
	var gb := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	gb.systemid = "gb"
	# The stand-in by name: with no model a machine is the generic box, and the
	# box has no link socket.
	gb.model_id = "game_boy_primitive"
	gb.core_name = _core
	gb.name = "GameBoy"
	add_child(gb)
	gb.freeze = true
	gb.global_transform = Transform3D(Basis.IDENTITY, Vector3(-0.09, 0.0, 0.0))

	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	printer.name = "Printer"
	add_child(printer)
	printer.freeze = true
	# Turned so its back, where EXT.IN is, faces the Game Boy across the lead.
	printer.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-60.0)),
		Vector3(0.09, 0.0, 0.0))
	await _settle(2)

	_ok("the printer starts switched off", not printer.is_powered_on)
	_ok("and with only the end of the roll showing",
		printer.get_node("PaperPivot/Paper") != null)

	gb.rom_path = ProjectSettings.globalize_path(ROM)
	gb.power_on()
	_ok("the Game Boy powers on", gb.is_powered_on)
	_ok("the printer powers on by its own switch", printer.power_on())
	_ok("and says so", printer.is_powered_on)
	# The Game Boy's model, and the socket on it, are built while it comes up.
	await _settle(120)

	# By TYPE: the first node merely NAMED LinkPort under a machine is not the
	# socket (PickableHighlight mirrors the model's nodes by name).
	var found := gb.find_children("*", "LinkPort", true, false)
	var gb_port := found[0] as LinkPort if not found.is_empty() else null
	var pr_port := printer.get_node("LinkPort") as LinkPort
	_ok("the Game Boy has a link socket", gb_port != null)
	_ok("the printer's EXT.IN is a link socket", pr_port != null)
	_eq("which takes the Game Boy's lead", pr_port.connector, "link_plug")

	var lead := (load(CABLE_SCENE) as PackedScene).instantiate() as LinkCable
	lead.name = "Lead"
	add_child(lead)
	_keep.append_array([gb.get_node_or_null("GameBoyPrimitive"), printer, lead])
	await _settle(2)
	(gb_port as XRToolsSnapZone).pick_up_object(lead.get_node("PlugA0"))
	(pr_port as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB0"))
	await _settle(8)

	var gb_lib := gb.get_libretro_node()
	var pr_lib := printer.get_libretro_node() as Libretro
	_eq("the seated lead puts the Game Boy on a wire of two", gb_lib.LinkPeerCount(0), 2)
	_eq("with the printer", pr_lib.LinkPeerCount(0), 2)
	var machines := lead.linked_machines()
	_ok("the lead names the printer as a machine on its wire",
		machines.any(func(m: Dictionary) -> bool: return m["machine"] == printer))
	await _shot("cabled")

	# The print, as the paper comes out.
	var expected := Image.load_from_file(ProjectSettings.globalize_path(EXPECTED))
	expected.convert(Image.FORMAT_L8)
	var want_lines := expected.get_height()
	var started := Time.get_ticks_msec()
	var mid_taken := false
	while Time.get_ticks_msec() - started < 60000:
		await _settle(1)
		if _frames_out and Engine.get_process_frames() % 2 == 0:
			_frame()
		var img := pr_lib.GetVideoImage()
		var lines := img.get_height() if img != null and img.get_width() == 160 else 0
		if not mid_taken and lines >= want_lines / 2:
			mid_taken = true
			await _shot("printing")
		if lines >= want_lines:
			break
	for i in range(40):
		await _settle(1)
		if _frames_out and i % 3 == 0:
			_frame()
	var paper := pr_lib.GetVideoImage()
	print("[gb-printer-room] paper %dx%d after %.1f s" % [paper.get_width(), paper.get_height(),
		(Time.get_ticks_msec() - started) / 1000.0])
	_eq("the printer put out the whole print", Vector2i(paper.get_width(), paper.get_height()),
		Vector2i(160, want_lines))
	paper.convert(Image.FORMAT_L8)
	_ok("and it is the picture the Game Boy sent", paper.get_data() == expected.get_data())
	var strip_len := (printer.get_node("PaperPivot/Paper/ButtonMesh") as MeshInstance3D).mesh.get_aabb().size.y
	_ok("the strip in the room is that much paper", absf(strip_len - want_lines * GbPrinter.DOT_PITCH) < 0.0005,
		"%.4f m against %.4f" % [strip_len, want_lines * GbPrinter.DOT_PITCH])
	await _shot("printed")
	_write_film()

	# Tear it off: a printout standing above the slot, the size of the paper.
	var before := _posters()
	printer.tear()
	# Nobody's hand is here to take it, so it would drop; for the picture it is
	# stood up in front of the printer, as a hand holding it up would.
	for p: Poster in _posters():
		if not before.has(p):
			p.freeze = true
			p.global_transform = Transform3D(Basis.IDENTITY,
				printer.global_position + Vector3(0.0, 0.07, 0.09))
	await _settle(30)
	var after := _posters()
	_eq("tearing leaves one printout", after.size() - before.size(), 1)
	var printout: Poster = null
	for p: Poster in after:
		if not before.has(p):
			printout = p
	if printout != null:
		_written.append(printout.image_path)
		_ok("written into the prints folder",
			printout.image_path.begins_with(DataPaths.media_root(GbPrinter.PRINTS_DIR)),
			printout.image_path)
		var sheet := printout.get_sheet_size()
		_ok("as wide as the paper", absf(minf(sheet.x, sheet.y) - want_lines * GbPrinter.DOT_PITCH) < 0.001
			or absf(maxf(sheet.x, sheet.y) - GbPrinter.PAPER_WIDTH) < 0.001,
			"%s" % sheet)
		var saved := Image.load_from_file(printout.image_path)
		_eq("the file is the paper, margins and all",
			Vector2i(saved.get_width(), saved.get_height()),
			Vector2i(GbPrinterPaper.sheet_width(), want_lines))
		_keep.append(printout.get_node("Surface"))
	await _settle(10)
	var torn := pr_lib.GetVideoImage()
	_eq("and the printer has none left out", Vector2i(torn.get_width(), torn.get_height()),
		Vector2i(1, 1))
	await _shot("torn")

	# The lead comes out: the printer is alone again.
	(pr_port as XRToolsSnapZone).drop_object()
	await _settle(6)
	_eq("pulling the lead leaves the Game Boy alone", gb_lib.LinkPeerCount(0), 0)

	printer.power_off()
	gb.power_off()
	await _settle(60)
	_finish()


func _posters() -> Array:
	var out: Array = []
	for n in get_tree().current_scene.get_children():
		if n is Poster:
			out.append(n)
	return out


## A floor, a light and a camera looking at the two from in front and above.
func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.17, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.031, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.3, 0.25)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	_keep.append(floor_mesh)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0.02, 0.22, 0.30), Vector3(0.02, 0.02, 0.0))
	cam.current = true
	_cam = cam


func _hide_panels() -> void:
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var wanted := n is Light3D
		for k in _keep:
			if is_instance_valid(k) and (k == n or k.is_ancestor_of(n)):
				wanted = true
				break
		if not wanted:
			(n as VisualInstance3D).visible = false


func _shot(name: String) -> void:
	_hide_panels()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := "%s/gb_printer_room_%s_%s.png" % [OUT, _core, name]
	img.save_png(path)
	print("[gb-printer-room] wrote %s" % path)


func _frame() -> void:
	_hide_panels()
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	_film.append(img)


func _write_film() -> void:
	if _film.is_empty():
		return
	var dir := "%s/gb_printer_room_frames" % OUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for img in _film:
		img.save_png("%s/%05d.png" % [dir, _frame_no])
		_frame_no += 1
	print("[gb-printer-room] wrote %d film frames" % _frame_no)
	_film.clear()


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gb-printer-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[gb-printer-room] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	for path in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			print("[gb-printer-room] removed %s" % path)
	_restore()
	print("[gb-printer-room] ---- %s: %d passed, %d failed ----" % [_core, _pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _write_options(root: String) -> void:
	_opt_path = "%s/core_options/%s.opt" % [root, _core]
	_had_opt = FileAccess.file_exists(_opt_path)
	_opt_backup = FileAccess.get_file_as_string(_opt_path) if _had_opt else ""
	var wanted: Array = OPTIONS[_core]
	var lines: PackedStringArray = []
	for line in _opt_backup.split("\n", false):
		var keep := true
		for pair: Array in wanted:
			if line.begins_with(str(pair[0])):
				keep = false
		if keep:
			lines.append(line)
	for pair: Array in wanted:
		lines.append('%s = "%s"' % [pair[0], pair[1]])
	DirAccess.make_dir_recursive_absolute(_opt_path.get_base_dir())
	var w := FileAccess.open(_opt_path, FileAccess.WRITE)
	w.store_string("\n".join(lines) + "\n")
	w.close()


func _restore() -> void:
	if _restored or _opt_path.is_empty():
		return
	_restored = true
	if not _had_opt:
		DirAccess.remove_absolute(_opt_path)
		return
	var w := FileAccess.open(_opt_path, FileAccess.WRITE)
	if w != null:
		w.store_string(_opt_backup)
		w.close()
