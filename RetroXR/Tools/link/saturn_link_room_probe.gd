## The Saturn Link Cable the way a player makes it: two Saturns built from
## system.tscn, a Saturn lead spawned into the room, each plug pushed into a
## Communication Connector through the socket's own API -- no LinkConnect.
##
## A probe, not a test: it wants the retroXR Beetle Saturn build, the BIOS and a
## link disc. Steeldom is the target because its title menu SAYS whether a
## partner is there (LINK MODE with one, 2P GAME without), and the player-2
## pilot on each screen follows the OTHER console's pad.
##
##   "$godot" --headless --path RetroXR res://Tools/link/saturn_link_room_probe.tscn -- \
##       --root=<root with system/mednafen_saturn and cores/> \
##       --rom="Z:/roms/saturn/Koutetsu Reiiki - Steeldom (Japan) (2M).chd" [--shot=<dir>] [--nocable]
##
## Times are emulated seconds (frames / 60) of machine A.
extends Node

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CABLE_SCENE := "res://Scenes/Objects/cables/saturn_link_cable.tscn"
const CORE := "mednafen_saturn"
const PAD := {"start": 1 << 3, "down": 1 << 5, "right": 1 << 7}

var root_dir := ""
var rom := ""
var shot := ""
## Control leg: the same script with the lead left on the table. The pairing
## checks must FAIL here, or they prove nothing.
var nocable := false

var _systems: Array[RetroSystem] = []
var _failures := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg == "--nocable":
			nocable = true
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[sat-room] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not FileAccess.file_exists(rom):
		print("[sat-room] SKIP  pass --root=<root> --rom=<Steeldom disc>")
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	for i in 2:
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "saturn"
		sys.core_name = CORE
		sys.core_directory = root_dir
		sys.name = "Saturn%s" % ["A", "B"][i]
		sys.position = Vector3(i * 0.6, 0.0, 0.0)
		add_child(sys)
		_systems.append(sys)
	await get_tree().process_frame

	var ports: Array[SaturnLinkPort] = []
	for sys in _systems:
		ports.append(sys.find_child("SaturnLinkPort", true, false) as SaturnLinkPort)
	_ok("each Saturn carries a Communication Connector", ports.count(null) == 0)
	if ports.count(null) > 0:
		return _finish()

	# Cabled BEFORE power, as a player sets a pair up on the table. Seating the
	# lead into machines that are off is ordinary; the link comes alive when both
	# cores attach.
	var lead := (load(CABLE_SCENE) as PackedScene).instantiate() as SaturnLinkCable
	add_child(lead)
	await get_tree().process_frame
	if not nocable:
		(ports[0] as XRToolsSnapZone).pick_up_object(lead.get_node("PlugA0"))
		(ports[1] as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB0"))
	await _frames(6)
	_eq("the lead resolves to both Saturns", lead.linked_machines().size(), 2)

	for sys in _systems:
		sys.rom_path = rom
		sys.power_on()
	for i in 2:
		_ok("Saturn %d powered on" % i, _systems[i].is_powered_on)
	await _until(3.0)
	_eq("the cores see a bus of two (A)", _lib(0).LinkPeerCount(0), 2)
	_eq("and (B)", _lib(1).LinkPeerCount(0), 2)

	# Title: Start past the intro, Start at PRESS START, then LINK MODE is the
	# second entry. A goes in first, B three seconds later -- two players are
	# never frame-perfect, and a script that is sends both into the same state.
	await _press_both("start", 38.6)
	await _press_both("start", 46.3)
	await _until(48.5)
	_snap("title")
	await _press(0, "down", 49.2)
	await _press(0, "start", 50.2)
	await _press(1, "down", 52.1)
	await _press(1, "start", 53.1)
	await _until(58.0)
	var before := [_crc(0, true), _crc(1, true)]
	_snap("select")
	# Only B moves. If the cable carries, player 2's pilot changes on A as well.
	await _press(1, "right", 58.5)
	await _until(60.5)
	var after := [_crc(0, true), _crc(1, true)]
	_snap("after_b_moves")
	_ok("B's own screen changed", after[1] != before[1])
	# NOT "A's screen changed": the select screen animates, so it changes
	# unplugged too (measured with --nocable). Equality with B is the check that
	# tells the two apart -- uncabled, A's player 2 is its own idle pad.
	_eq("A's screen followed B's pad across the lead: same pilot on both", after[0], after[1])
	_finish()


func _lib(i: int) -> Libretro:
	return _systems[i].find_child("Libretro", true, false) as Libretro


func _now() -> float:
	return float(_lib(0).GetFrameCount()) / 60.0


func _until(t: float) -> void:
	while _now() < t:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(i: int, button: String, at: float) -> void:
	await _until(at)
	_lib(i).SetJoypadState(0, PAD[button], 0, 0, 0, 0)
	await _until(at + 0.2)
	_lib(i).SetJoypadState(0, 0, 0, 0, 0, 0)


func _press_both(button: String, at: float) -> void:
	await _until(at)
	for i in 2:
		_lib(i).SetJoypadState(0, PAD[button], 0, 0, 0, 0)
	await _until(at + 0.2)
	for i in 2:
		_lib(i).SetJoypadState(0, 0, 0, 0, 0, 0)


## A digest of the player-2 half of the screen: the pilot portrait and mech.
func _crc(i: int, right_half: bool) -> String:
	var img: Image = _lib(i).GetVideoImage()
	if img == null or img.is_empty():
		return ""
	var w := img.get_width()
	var part := img.get_region(Rect2i(w / 2 if right_half else 0, 0, w / 2, img.get_height()))
	part.convert(Image.FORMAT_RGB8)
	return str(hash(part.get_data()))


func _snap(tag: String) -> void:
	if shot.is_empty():
		return
	for i in 2:
		var img: Image = _lib(i).GetVideoImage()
		if img != null and not img.is_empty():
			var flat := img.duplicate() as Image
			flat.convert(Image.FORMAT_RGB8)
			flat.save_png(shot.path_join("%s_%s.png" % [tag, ["A", "B"][i]]))


func _ok(name: String, cond: bool, detail := "") -> void:
	if not cond:
		_failures += 1
	print("[sat-room] %s  %s%s" % ["PASS" if cond else "FAIL", name, "" if cond or detail.is_empty() else "  -- " + detail])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	for sys in _systems:
		if is_instance_valid(sys) and sys.is_powered_on:
			sys.power_off()
	await _frames(60)
	print("[sat-room] ---- %s ----" % ("all passed" if _failures == 0 else "%d failed" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
