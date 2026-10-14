## 3DO NVRAM probe — does Opera read the NVRAM ThreeDoStorage stages, write it
## back to the same file, and does the 3DO's own OS leave what ThreeDoNvram
## writes alone?
##
## Stages an NVRAM image under ThreeDoStorage.NVRAM_FILE holding one file written
## by ThreeDoNvram, pins ThreeDoStorage's options and a BIOS, boots --rom, presses
## a scripted sequence of buttons, saves frames, stops, and lists what the core
## left. One leg per process:
##
##   (default)  the image above
##   --blank    nothing staged: Opera formats its own, which blank_image() must
##              equal byte for byte
##   --broken   the image above with its file's forward link bent, the control
##              for "the OS checks NVRAM": a disc's Portfolio OS runs
##              `lmadm -a nvram` at startup (filesystem/fscheck.c), so if it ran,
##              this comes back repaired, and the default leg coming back
##              unchanged means the OS read RetroXR's layout and found it whole
##   --pergame  the image staged, but Opera left on its own "per game" default:
##              the control for the pin -- the shared file must come back
##              untouched and the game's own file appear instead
##
## Needs a real core, BIOS and disc, so it is a probe. Windowed, never --headless
## (the frames come back blank), one core per process. Point --root at a
## throwaway root holding cores/opera_libretro.dll and system/<bios>: the probe
## writes that root's save/ and core_options/.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/cores/three_do_nvram_probe.tscn -- --root=C:/tmp/root3do \
##     --rom="C:/roms/3do/Gex (USA Europe).chd" --run=40 --at=10,20,30 --shot=C:/tmp/3do.png
##
## --press takes seconds:button pairs, RetroPad names (a b x y start select up
## down left right l r); each press is held for a quarter of a second. --rom=
## left empty boots the BIOS with no disc. --bios= is the opera_bios value: a file
## in system/opera/ (panafz10.bin by default), or "opera-boot-internal" for the
## boot ROM Opera embeds from 684926f on (the buildbot core measured, 5a09dc4,
## predates it and boots nothing without a file). --keep starts from the files a
## previous run left rather than fresh ones.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const PRESS_MS := 250
const PROBE_FILE := "RetroXR.probe"
const PROBE_TYPE := 0x52585250  # "RXRP"
const PROBE_BYTES := 300

var root_dir := ""
var core := "opera"
var rom := ""
var bios := "panafz10.bin"
var leg := "staged"
var keep := false
var run_for := 30.0
var sample_at: Array[float] = []
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
		elif arg.begins_with("--bios="):
			bios = arg.trim_prefix("--bios=")
		elif arg in ["--blank", "--broken", "--pergame"]:
			leg = arg.trim_prefix("--")
		elif arg == "--keep":
			keep = true
		elif arg.begins_with("--run="):
			run_for = float(arg.trim_prefix("--run="))
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--at="):
			for piece: String in arg.trim_prefix("--at=").split(",", false):
				sample_at.append(float(piece))
		elif arg.begins_with("--press="):
			for piece: String in arg.trim_prefix("--press=").split(",", false):
				var bits := piece.split(":")
				if bits.size() == 2 and BUTTONS.has(bits[1]):
					presses.append([float(bits[0]), int(BUTTONS[bits[1]])])
	get_tree().create_timer(run_for + 120.0).timeout.connect(func() -> void:
		print("[3doprobe] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not FileAccess.file_exists(
			root_dir.path_join("cores").path_join("opera_libretro.dll")):
		print("[3doprobe] SKIP: pass --root=<root with cores/opera_libretro.dll and system/>")
		get_tree().quit(2)
		return
	if not rom.is_empty() and not FileAccess.file_exists(rom):
		print("[3doprobe] SKIP: no disc at %s" % rom)
		get_tree().quit(2)
		return
	if not shot.is_empty():
		DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	await _run()


func _run() -> void:
	var save_dir := root_dir.path_join("save").path_join(core)
	var shared := save_dir.path_join(ThreeDoStorage.NVRAM_FILE)
	var per_game := save_dir.path_join(ThreeDoStorage.PER_GAME_DIR).path_join(
		"%s.%s.srm" % [rom.get_file().get_basename(), ThreeDoStorage.NVRAM_VERSION])
	DirAccess.make_dir_recursive_absolute(shared.get_base_dir())
	if not keep:
		DirAccess.remove_absolute(shared)
		DirAccess.remove_absolute(per_game)
		if leg != "blank":
			_write(shared, _image(leg == "broken"))
	var opts := ThreeDoStorage.forced_options(core, true)
	if leg == "pergame":
		opts["opera_nvram_storage"] = "per game"
	opts["opera_bios"] = bios
	CoreOptionsStore.merge_values(root_dir, core, opts)
	print("[3doprobe] leg=%s core=%s rom=%s options=%s" % [leg, core, rom, str(opts)])
	var before := {shared: _stamp(shared), per_game: _stamp(per_game)}
	_list("staged", shared)

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _load_failed = reason)
	if rom.is_empty():
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", true)
	_lib.StartContent(root_dir, core, rom)

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
		if now >= int(run_for * 1000.0):
			break
		await get_tree().process_frame
	if not _load_failed.is_empty():
		print("[3doprobe] refused: %s" % _load_failed)

	_lib.StopContent()
	await get_tree().create_timer(3.0).timeout
	for path: String in [shared, per_game]:
		var rewritten: bool = _stamp(path) != str(before[path])
		print("[3doprobe] %s %s" % [path.get_file(), "WRITTEN by the core" if rewritten else "not touched"])
	_list("after stop", shared)
	_list("after stop", per_game)
	get_tree().quit(0)


## A blank image holding one file of PROBE_BYTES, or the same with that file's
## forward link bent four bytes past where the next block starts.
func _image(broken: bool) -> PackedByteArray:
	var image := ThreeDoNvram.write_file(ThreeDoNvram.blank_image(), PROBE_FILE, PROBE_TYPE,
		0, PROBE_BYTES, _pattern(PROBE_BYTES))
	if broken:
		var at := ThreeDoNvram.index_of(image, PROBE_FILE)
		ThreeDoNvram._put_u32(image, at + ThreeDoNvram.OFF_FLINK,
			ThreeDoNvram._u32(image, at + ThreeDoNvram.OFF_FLINK) + 4)
	return image


func _list(when: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		print("[3doprobe] %s %s: absent" % [when, path.get_file()])
		return
	var data := FileAccess.get_file_as_bytes(path)
	var listing: PackedStringArray = []
	for e: Dictionary in ThreeDoNvram.list_files(data):
		var contents := ThreeDoNvram.read_file(data, int(e["at"]))
		var read := ""
		if str(e["name"]) == PROBE_FILE:
			read = " read %s" % ("exact" if contents.slice(0, PROBE_BYTES) == _pattern(PROBE_BYTES) else "DIFFERS")
		listing.append("%s(type %08x, %d bytes in %d at %d%s)" % [e["name"], e["type"],
			e["bytes"], e["blocks"], e["at"], read])
	var chain: PackedStringArray = []
	for b: Dictionary in ThreeDoNvram.blocks(data):
		chain.append("%d:%s/%d" % [b["at"], "file" if int(b["fingerprint"]) == ThreeDoNvram.FINGERPRINT_FILE
			else "free", b["count"]])
	print("[3doprobe] %s %s: %d bytes nvram=%s list=%s free=%d files=%s blank=%s sha=%s" % [when,
		path.get_file(), data.size(), ThreeDoNvram.is_card_image(data),
		"[%s]" % " ".join(chain) if not chain.is_empty() else "BROKEN",
		ThreeDoNvram.free_bytes(data), ", ".join(listing),
		data == ThreeDoNvram.blank_image(), _sha(data).left(16)])
	print("[3doprobe]   label %s" % data.slice(0, ThreeDoNvram.LABEL_SIZE + 40).hex_encode())


func _sample(at: float) -> void:
	var img: Image = _lib.GetVideoImage()
	var size := "(no image)"
	if img != null and not img.is_empty():
		size = "%dx%d" % [img.get_width(), img.get_height()]
		if not shot.is_empty():
			var flat := img.duplicate() as Image
			flat.convert(Image.FORMAT_RGB8)
			flat.save_png(shot.get_basename() + ("_%05.1f." % at).replace(" ", "0") + shot.get_extension())
	print("[3doprobe] t=%4.1f frames=%d size=%s" % [at, int(_lib.GetFrameCount()), size])


func _stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return "%d:%s" % [FileAccess.get_modified_time(path), _sha(FileAccess.get_file_as_bytes(path))]


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
