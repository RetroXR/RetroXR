## Sega CD backup memory probe — does genesis_plus_gx take the memory RetroXR
## stages for a Sega CD, keep it, and show it to the BIOS?
##
## Stages an internal image, and optionally a Backup RAM Cartridge, built by
## SegaCdBram into <root>/save/<core>/ under the names SegaCdStorage uses, each
## holding one known save. Pins the options SegaCdStorage pins, boots the content
## (the US BIOS by default, which opens its own menu), presses a scripted
## sequence of buttons, saves frames, stops, and lists what the core left behind.
##
## Needs a real core, BIOS and, for a game, a disc, so it is a probe. Windowed,
## never --headless (the frames come back blank), and one core per process. Point
## --root at a throwaway root holding system/bios_CD_U.bin and cores/: the probe
## writes that root's save/ and core_options/.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/cores/sega_cd_bram_probe.tscn -- --root=C:/tmp/scdroot \
##     --cart=128k --at=4,8,12 --press=6:start,9:down --shot=C:/tmp/scd.png
##
## --press takes seconds:button pairs, RetroPad names (a b x y start select up
## down left right l r); each press is held for a quarter of a second.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const CART_ARG := {"128k": 0x4000, "256k": 0x8000, "512k": 0x10000,
	"1meg": 0x20000, "2meg": 0x40000, "4meg": 0x80000}
const PRESS_MS := 250

var root_dir := ""
var core := "genesis_plus_gx"
var rom := ""
var cart := "none"
var insert := true
var sample_at: Array[float] = [4.0, 8.0, 12.0]
var presses: Array = []
var shot := ""

var _lib: Node = null
var _load_failed := ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--core="):
			core = arg.trim_prefix("--core=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--cart="):
			cart = arg.trim_prefix("--cart=")
		elif arg == "--no-insert":
			insert = false
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
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[scdprobe] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not DirAccess.dir_exists_absolute(root_dir):
		print("[scdprobe] SKIP: pass --root=<root with system/ and cores/>")
		get_tree().quit(2)
		return
	if rom.is_empty():
		rom = root_dir.path_join("system").path_join("bios_CD_U.bin")
	if not FileAccess.file_exists(rom):
		print("[scdprobe] SKIP: no content at %s" % rom)
		get_tree().quit(2)
		return
	if cart != "none" and not CART_ARG.has(cart):
		print("[scdprobe] SKIP: --cart must be none or one of %s" % str(CART_ARG.keys()))
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	var save_dir := root_dir.path_join("save").path_join(core)
	DirAccess.make_dir_recursive_absolute(save_dir)
	var memory := SegaCdBram.blank_image(SegaCdBram.INTERNAL_SIZE)
	if insert:
		memory = SegaCdBram.write_file(memory, "RETROXR_MEM".to_ascii_buffer(),
			SegaCdBram.MODE_RAW, _pattern(SegaCdBram.RAW_BLOCK_DATA))
	for name: String in SegaCdStorage.REGION_FILES:
		_write(save_dir.path_join(name), memory)
	var cart_size := 0
	if cart != "none":
		cart_size = int(CART_ARG[cart])
		var image := SegaCdBram.blank_image(cart_size)
		if insert:
			image = SegaCdBram.write_file(image, "RETROXR_CRT".to_ascii_buffer(),
				SegaCdBram.MODE_PROTECTED, _pattern(SegaCdBram.PROTECTED_BLOCK_DATA))
		_write(save_dir.path_join(str(SegaCdStorage.CART_SIZES[cart_size][1])), image)
	var opts := SegaCdStorage.forced_options(core, true, cart_size)
	CoreOptionsStore.merge_values(root_dir, core, opts)
	print("[scdprobe] core=%s rom=%s options=%s" % [core, rom, str(opts)])
	_list("staged", save_dir)

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _load_failed = reason)
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
		print("[scdprobe] refused: %s" % _load_failed)

	_lib.StopContent()
	await get_tree().create_timer(3.0).timeout
	_list("after stop", save_dir)
	get_tree().quit(0)


func _list(when: String, save_dir: String) -> void:
	var names: Array[String] = []
	for name: String in SegaCdStorage.REGION_FILES:
		names.append(name)
	for size: int in SegaCdStorage.CART_SIZES:
		names.append(str(SegaCdStorage.CART_SIZES[size][1]))
	for name: String in names:
		var path := save_dir.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		var data := FileAccess.get_file_as_bytes(path)
		var listing: PackedStringArray = []
		for e: Dictionary in SegaCdBram.list_files(data):
			listing.append("%s(%s,%d)" % [e["name"], "P" if int(e["mode"]) else "raw", e["size"]])
		print("[scdprobe] %s %s: %d bytes card=%s free=%d saves=%s sha=%s" % [when, name,
			data.size(), SegaCdBram.is_card_image(data), SegaCdBram.free_blocks(data),
			",".join(listing), _sha(data).left(12)])


func _sample(at: float) -> void:
	var img: Image = _lib.GetVideoImage()
	var size := "(no image)"
	if img != null and not img.is_empty():
		size = "%dx%d" % [img.get_width(), img.get_height()]
		if not shot.is_empty():
			var rgb := PackedByteArray()
			rgb.resize(img.get_width() * img.get_height() * 3)
			var i := 0
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					rgb[i] = int(c.r * 255.0)
					rgb[i + 1] = int(c.g * 255.0)
					rgb[i + 2] = int(c.b * 255.0)
					i += 3
			Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, rgb) \
				.save_png(shot.get_basename() + ("_%05.1f." % at).replace(" ", "0") + shot.get_extension())
	print("[scdprobe] t=%4.1f frames=%d size=%s" % [at, int(_lib.GetFrameCount()), size])


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
