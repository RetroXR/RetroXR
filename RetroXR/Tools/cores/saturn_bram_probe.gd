## Sega Saturn backup memory probe — does Beetle Saturn take the System Memory
## RetroXR hands it through SAVE_RAM and the cartridge SaturnStorage stages, and
## does its BIOS read what SaturnBram writes and write what SaturnBram reads?
##
## Builds a System Memory image, handed over with SetSramPath as a Saturn's own
## memory is, and optionally a Backup RAM Cartridge staged under
## SaturnStorage.CART_FILE, each holding one known save. Pins SaturnStorage's
## options, boots the BIOS on the empty-media cue a Saturn with nothing in it gets
## (or --rom), presses a scripted sequence of buttons, saves frames, stops, and
## lists what the core left in both.
##
## Needs a real core and BIOS, so it is a probe. Windowed, never --headless (the
## frames come back blank), and one core per process. Point --root at a throwaway
## root holding system/mednafen_saturn/ and cores/: the probe writes that root's
## save/ and core_options/.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/cores/saturn_bram_probe.tscn -- --root=C:/tmp/satroot --cart \
##     --at=4,8,12 --press=6:a,9:down --shot=C:/tmp/sat.png
##
## --press takes seconds:button pairs, RetroPad names (a b x y start select up
## down left right l r); each press is held for a quarter of a second. --keep
## starts from the images a previous run left rather than fresh ones.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const PRESS_MS := 250
const MEMORY_FILE := "probe_system_memory.bkr"

var root_dir := ""
var core := "mednafen_saturn"
var rom := ""
var cart := false
var keep := false
var sample_at: Array[float] = [4.0, 8.0, 12.0]
var presses: Array = []
var shot := ""

var _lib: Node = null
var _load_failed := ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg == "--cart":
			cart = true
		elif arg == "--keep":
			keep = true
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--at="):
			sample_at.clear()
			for piece: String in arg.trim_prefix("--at=").split(",", false):
				sample_at.append(float(piece))
		elif arg.begins_with("--press="):
			for piece: String in arg.trim_prefix("--press=").split(",", false):
				var bits := piece.split(":")
				if bits.size() == 2 and BUTTONS.has(bits[1]):
					presses.append([float(bits[0]), int(BUTTONS[bits[1]])])
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[satprobe] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not DirAccess.dir_exists_absolute(root_dir.path_join("system")):
		print("[satprobe] SKIP: pass --root=<root with system/mednafen_saturn and cores/>")
		get_tree().quit(2)
		return
	if rom.is_empty():
		rom = BiosBoot.empty_media_path("cue", "audio")
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[satprobe] SKIP: no content at %s" % rom)
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	var save_dir := root_dir.path_join("save").path_join(core)
	DirAccess.make_dir_recursive_absolute(save_dir)
	var memory_path := save_dir.path_join(MEMORY_FILE)
	var cart_path := save_dir.path_join(SaturnStorage.CART_FILE)
	if not keep:
		var memory := SaturnBram.write_file(SaturnBram.blank_image(SaturnBram.INTERNAL_SIZE),
			"RETROXR_MEM".to_ascii_buffer(), 0, "RetroXR".to_ascii_buffer(), 0, _pattern(200))
		_write(memory_path, memory)
		if cart:
			_write(cart_path, SaturnBram.write_file(SaturnBram.blank_image(SaturnBram.CART_SIZE),
				"RETROXR_CRT".to_ascii_buffer(), 0, "Cartridge".to_ascii_buffer(), 0, _pattern(1500)))
		else:
			DirAccess.remove_absolute(cart_path)
	var opts := SaturnStorage.forced_options(core, cart)
	CoreOptionsStore.merge_values(root_dir, core, opts)
	print("[satprobe] core=%s rom=%s options=%s" % [core, rom, str(opts)])
	_list("staged", memory_path, cart_path)

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _load_failed = reason)
	_lib.SetSramPath(memory_path)
	_lib.StartContent(root_dir, core, rom)

	var end_at := 0.0
	for t: float in sample_at:
		end_at = maxf(end_at, t)
	for p: Array in presses:
		end_at = maxf(end_at, float(p[0]) + 0.5)
	var t0 := Time.get_ticks_msec()
	var next_sample := 0
	var sorted := sample_at.duplicate()
	sorted.sort()
	while _load_failed.is_empty():
		var now := Time.get_ticks_msec() - t0
		var mask := 0
		for p: Array in presses:
			var at := int(float(p[0]) * 1000.0)
			if now >= at and now < at + PRESS_MS:
				mask |= 1 << int(p[1])
		_lib.SetJoypadState(0, mask, 0, 0, 0, 0)
		if next_sample < sorted.size() and now >= int(float(sorted[next_sample]) * 1000.0):
			_sample(float(sorted[next_sample]))
			next_sample += 1
		if now >= int(end_at * 1000.0):
			break
		await get_tree().process_frame
	if not _load_failed.is_empty():
		print("[satprobe] refused: %s" % _load_failed)

	_lib.StopContent()
	await get_tree().create_timer(3.0).timeout
	_list("after stop", memory_path, cart_path)
	get_tree().quit(0)


func _list(when: String, memory_path: String, cart_path: String) -> void:
	for path: String in [memory_path, cart_path]:
		if not FileAccess.file_exists(path):
			print("[satprobe] %s %s: absent" % [when, path.get_file()])
			continue
		var data := FileAccess.get_file_as_bytes(path)
		var listing: PackedStringArray = []
		for e: Dictionary in SaturnBram.list_files(data):
			var payload := SaturnBram.read_file(data, int(e["block"]))
			# Every save the probe writes is _pattern of its size, so a copy the BIOS
			# made must read back as exactly that.
			var read := "exact" if payload == _pattern(int(e["size"])) \
				else ("DIFFERS" if payload.size() == int(e["size"]) else "BROKEN")
			listing.append("%s[%s](lang %d, %d bytes, %d blocks, date %d, read %s)" % [e["name"],
				e["comment"], e["language"], e["size"], e["blocks"], e["date"], read])
		print("[satprobe] %s %s: %d bytes card=%s free=%d saves=%s sha=%s" % [when, path.get_file(),
			data.size(), SaturnBram.is_card_image(data), SaturnBram.free_blocks(data),
			", ".join(listing), _sha(data).left(12)])
		var starts: PackedStringArray = []
		var bs := SaturnBram.block_size(data.size())
		for b in range(SaturnBram.RESERVED_BLOCKS, SaturnBram.block_count(data)):
			if data[b * bs] & SaturnBram.START_FLAG:
				starts.append("%d:%s" % [b, data.slice(b * bs, b * bs + 40).hex_encode()])
		if not starts.is_empty():
			print("[satprobe]   flagged blocks %s" % " ".join(starts))


func _sample(at: float) -> void:
	var img: Image = _lib.GetVideoImage()
	var size := "(no image)"
	if img != null and not img.is_empty():
		size = "%dx%d" % [img.get_width(), img.get_height()]
		if not shot.is_empty():
			var flat := img.duplicate() as Image
			flat.convert(Image.FORMAT_RGB8)
			flat.save_png(shot.get_basename() + ("_%05.1f." % at).replace(" ", "0") + shot.get_extension())
	print("[satprobe] t=%4.1f frames=%d size=%s" % [at, int(_lib.GetFrameCount()), size])


func _pattern(bytes: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in bytes:
		out.append((i * 37 + 5) & 0xFF)
	return out


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _sha(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()
