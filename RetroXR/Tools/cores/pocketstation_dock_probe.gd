## pocketstation_dock_probe — a PocketStation game on a real pcsx_rearmed, with a
## PocketStation (or, as the control, a plain card) in the PlayStation's card slot 1.
##
## The oracle is the GAME: what it offers and what it writes to the card, read off its
## own screens (saved where --shots / --every ask) and off the card image afterwards
## (every save listed, a PocketStation app marked as one). The card is seated through
## the console's real slot, so the PocketStation's own seating runs.
##
##     "$godot" --headless --path RetroXR res://Tools/cores/pocketstation_dock_probe.tscn -- \
##         --root=<scratch libretro root: cores/pcsx_rearmed_libretro.dll, system/pcsx_rearmed/*.bin> \
##         --rom="<a PocketStation game>.cue" --leg=pocketstation --out=<dir> \
##         --steps="1800-1806:start,2400-2406:cross" --shots=1790,2390 --every=600
##
## ONE LEG PER PROCESS (a core started wrongly can take the process with it):
##   --leg=pocketstation   a PocketStation in slot 1
##   --leg=plain           the control: a plain PlayStation memory card in slot 1
##
## --steps: comma-separated `from-to:buttons`, the buttons joined by `+` from cross circle
## square triangle start select up down left right l1 r1 l2 r2, held on player 1's pad
## over the core's frames from..to. The fixture card's image is the player's real
## save/memcards/playstation/ folder's and is removed at the end unless --keep.
##
## Crash Bandicoot 3 - Buttobi! Sekai Isshuu (Japan, Asia), SCPS-10073, is what this was
## first run against (docs/dev/pocketstation.md).
##
## --state-at=F: at core frame F take a savestate (S1), load it straight back and take
## another (S2): with a PocketStation docked, the two must be the same byte for byte
## (its CPU, RAM and flash included), and the run then goes on FROM the loaded state, so
## a download in progress at F must still land on the card.
extends Node

const BITS := {"cross": 0, "square": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "circle": 8, "triangle": 9, "l1": 10, "r1": 11, "l2": 12, "r2": 13}
const CARD_ID := "__PSDOCK_PROBE"

var root_dir := ""
var rom_path := ""
var leg := "pocketstation"
var out_dir := ""
var every := 0
var keep := false
var _steps: Array = []
var _shots: Array[int] = []
var _pad: Node = null
var _card: Node3D = null
var _lib: Object = null
var _sent := -1
var state_at := -1
var _s1 := PackedByteArray()
var _state_done := false
var state_ok := true


func _ready() -> void:
	var steps_arg := ""
	var shots_arg := ""
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a.begins_with("--steps="):
			steps_arg = a.trim_prefix("--steps=")
		elif a.begins_with("--shots="):
			shots_arg = a.trim_prefix("--shots=")
		elif a.begins_with("--every="):
			every = int(a.trim_prefix("--every="))
		elif a == "--keep":
			keep = true
		elif a.begins_with("--state-at="):
			state_at = int(a.trim_prefix("--state-at="))
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[psdock] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/pcsx_rearmed_libretro.dll")) \
			or not FileAccess.file_exists(rom_path) or out_dir.is_empty() or not leg in ["pocketstation", "plain"]:
		print("[psdock] need --root=, --rom=, --out= and --leg=pocketstation|plain")
		get_tree().quit(1)
		return
	for s in steps_arg.split(",", false):
		var parts := s.split(":")
		var span := parts[0].split("-")
		var mask := 0
		for b in parts[1].split("+", false):
			if not BITS.has(b):
				print("[psdock] unknown button %s" % b)
			mask |= 1 << int(BITS.get(b, 0))
		_steps.append({"from": int(span[0]), "to": int(span[1]), "mask": mask})
	for f in shots_arg.split(",", false):
		_shots.append(int(f))
	_remove_fixture()
	await _run()


func _run() -> void:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "psx"
	sys.core_directory = root_dir
	sys.core_name = "pcsx_rearmed"
	add_child(sys)
	sys.freeze = true
	for i in 10:
		await get_tree().physics_frame
	_pad = (load("res://Scenes/Objects/controllers/playstation/ps1_controller.tscn") as PackedScene).instantiate()
	add_child(_pad)
	(_pad as Node3D).global_position = Vector3(0, 0, 0.6)
	var scene := "res://Scenes/Objects/peripherals/pocketstation.tscn" if leg == "pocketstation" \
		else "res://Scenes/Objects/media/memory_card.tscn"
	_card = (load(scene) as PackedScene).instantiate() as Node3D
	_card.set("card_id", CARD_ID)
	_card.set("card_label", CARD_ID)
	_card.set("minted", true)
	add_child(_card)
	_card.global_position = Vector3(0.2, 0.1, 0.4)
	for i in 6:
		await get_tree().physics_frame
	sys.restore_controller_plug(0, _pad.call("get_plug"))
	sys.memcard_slots()[0].pick_up_object(_card)
	for i in 12:
		await get_tree().physics_frame
	(_pad as Node).set_physics_process(false)
	(_pad as Node).set_process(false)
	print("[psdock] %s: card in slot 1 is %s (%s), seated %s" % [leg, _card.get_class(),
		str(_card.get_script().resource_path.get_file()), sys.get_snapped_memcard(0) == _card])
	if _card is PocketStation:
		print("[psdock] the PocketStation says: seated %s, blocker '%s'" % [
			(_card as PocketStation).is_seated(), (_card as PocketStation).standalone_blocker()])

	sys.rom_path = rom_path
	sys.toggle_power()
	_lib = sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 60000
	while (_lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if (_lib.GetCoreIdentity() as Dictionary).is_empty():
		print("[psdock] the core never came up")
		await _finish(1)
		return
	var ident: Dictionary = _lib.GetCoreIdentity()
	print("[psdock] core %s %s" % [ident.get("library_name", "?"), ident.get("library_version", "?")])
	var last := 0
	for f: int in _shots:
		last = maxi(last, f)
	for st: Dictionary in _steps:
		last = maxi(last, int(st["to"]) + 1)
	if every > 0:
		last = maxi(last, every)
	var shot_i := 0
	var sorted_shots := _shots.duplicate()
	sorted_shots.sort()
	var next_every := every
	while true:
		var frame := int(_lib.GetFrameCount())
		_drive(frame)
		while shot_i < sorted_shots.size() and frame >= sorted_shots[shot_i]:
			_shot(sorted_shots[shot_i])
			shot_i += 1
		if every > 0 and frame >= next_every:
			_shot(frame)
			next_every += every
		if frame > last:
			break
		if state_at >= 0 and not _state_done and frame >= state_at:
			_state_done = true
			await _state_round_trip()
		await get_tree().process_frame
	_lib.RequestSramFlush()
	for i in 30:
		await get_tree().process_frame
	sys.toggle_power()
	for i in 90:
		await get_tree().process_frame
	_report_card()
	await _finish(0 if state_ok else 1)


## S1, load it, S2: the same bytes, or the load lost something.
func _state_round_trip() -> void:
	# Held still (lockstep with no inputs posted runs no frame, and still takes the
	# save and load commands between frames), so S2 sees exactly what the load left.
	_lib.SetNetplayMode(true, 0x1, -1)
	for i in 10:
		await get_tree().process_frame
	_lib.RequestSaveState()
	var saved: Array = await _lib.savestate_ready
	_s1 = saved[0]
	var f1: int = saved[1]
	print("[psdock] state S1: %d bytes at frame %d" % [_s1.size(), f1])
	_lib.RequestLoadState(_s1, f1)
	var ok: bool = await _lib.savestate_loaded
	print("[psdock] state S1 loaded back: %s" % ok)
	_lib.RequestSaveState()
	var again: Array = await _lib.savestate_ready
	var s2: PackedByteArray = again[0]
	print("[psdock] state S2 at frame %d (S1 was %d)" % [int(again[1]), f1])
	var diff := 0
	var first := -1
	if s2.size() == _s1.size():
		for i in range(s2.size()):
			if s2[i] != _s1[i]:
				diff += 1
				if first < 0:
					first = i
	_lib.SetNetplayMode(false, 0x1, -1)
	state_ok = ok and s2.size() == _s1.size() and diff == 0
	print("[psdock] %s  save -> load -> save: %d of %d bytes differ%s" % ["PASS" if state_ok else "FAIL",
		diff if s2.size() == _s1.size() else -1, _s1.size(), "" if first < 0 else " (first at %d)" % first])


func _drive(frame: int) -> void:
	var mask := 0
	for st: Dictionary in _steps:
		if frame >= int(st["from"]) and frame <= int(st["to"]):
			mask |= int(st["mask"])
	if mask == _sent:
		return
	_sent = mask
	_pad.call("_deliver_joypad", {"btn": mask, "alx": 0, "aly": 0, "arx": 0, "ary": 0})


func _shot(frame: int) -> void:
	var img: Image = _lib.call("GetVideoImage")
	if img == null or img.is_empty():
		print("[psdock] frame %d: no image" % frame)
		return
	var path := out_dir.path_join("%s_%05d.png" % [leg, frame])
	img.save_png(path)
	print("[psdock] frame %d -> %s" % [frame, path])
	# The docked device's own screen, as the console's core hands it over (the device
	# display interface: location 1, a memory card slot; port 0, slot 1).
	if _lib.has_method("GetDeviceScreenTexture"):
		var lcd := _lib.call("GetDeviceScreenTexture", 1, 0, 0) as Texture2D
		var limg: Image = lcd.get_image() if lcd != null else null
		if limg == null or limg.is_empty():
			print("[psdock] frame %d: no device screen" % frame)
		else:
			var big := limg.duplicate() as Image
			big.resize(limg.get_width() * 8, limg.get_height() * 8, Image.INTERPOLATE_NEAREST)
			big.save_png(out_dir.path_join("%s_%05d_lcd.png" % [leg, frame]))
			print("[psdock] frame %d: device screen %dx%d" % [frame, limg.get_width(), limg.get_height()])


## What the game left on the card: every save, a PocketStation app marked.
func _report_card() -> void:
	var path := SramPaths.find_card(CARD_ID, "playstation")
	if path.is_empty():
		print("[psdock] card: no image")
		return
	var data := FileAccess.get_file_as_bytes(path)
	var saves := PS1Card.list_saves(data, false)
	print("[psdock] card %s: %d save(s), %d block(s) free" % [path.get_file(), saves.size(), PS1Card.free_blocks(data)])
	for s: Dictionary in saves:
		print("[psdock]   %-22s %d block(s)  %s%s" % [s["name"], int(s["blocks"]), s["title"],
			"  [PocketStation app]" if bool(s.get("pocketstation", false)) else ""])


func _remove_fixture() -> void:
	var path := SramPaths.find_card(CARD_ID, "playstation")
	if not path.is_empty() and not keep:
		DirAccess.remove_absolute(path)


func _finish(code: int) -> void:
	if not keep:
		_remove_fixture()
	print("[psdock] done")
	get_tree().quit(code)
