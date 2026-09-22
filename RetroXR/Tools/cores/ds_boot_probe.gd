## ds_boot_probe — does a DS core boot to the DS / DSi home screen, with nothing
## in it or with a cartridge sitting in a slot?
##
## Needs real cores and real firmware, so it is a probe. Windowed, never
## --headless (frames come back blank), and ONE core per process. Point --root at
## a THROWAWAY root holding cores/<core>_libretro.dll and system/<core>/{bios7,
## bios9,firmware}.bin (+ dsi_bios7, dsi_bios9, dsi_firmware, dsi_nand for DSi):
## the probe writes that root's core_options/ and save/.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/cores/ds_boot_probe.tscn -- --root=C:/tmp/dsroot --core=melondsds \
##     --opt=melonds_console_mode=dsi --at=5,15 --shot=C:/tmp/ds.png [--rom=<x.nds>]
##     [--gba=<x.gba>]   (melondsds only: the Slot-2 subsystem, --rom goes in slot 1)
##     [--press=8:a,9:touch=128:100]  [--options]  (print every option key and value)
##
## No --rom starts with NO CONTENT, the NULL convention RetroSystem uses for a
## `no_content` BiosBoot row.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const PRESS_MS := 250

var root_dir := ""
var core := ""
var rom := ""
var gba := ""
var shot := ""
var print_options := false
var opts: Dictionary = {}
var sample_at: Array[float] = [5.0, 15.0]
var presses: Array = []
## [seconds, x, y] of every touch, in bottom-screen pixels (256x192).
var touches: Array = []

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
		elif arg.begins_with("--gba="):
			gba = arg.trim_prefix("--gba=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg == "--options":
			print_options = true
		elif arg.begins_with("--opt="):
			var kv := arg.trim_prefix("--opt=")
			opts[kv.get_slice("=", 0)] = kv.substr(kv.find("=") + 1)
		elif arg.begins_with("--at="):
			sample_at.clear()
			for piece: String in arg.trim_prefix("--at=").split(",", false):
				sample_at.append(float(piece))
		elif arg.begins_with("--press="):
			for piece: String in arg.trim_prefix("--press=").split(",", false):
				var bits := piece.split(":")
				if bits.size() == 2 and BUTTONS.has(bits[1]):
					presses.append([float(bits[0]), int(BUTTONS[bits[1]])])
				elif bits.size() == 3 and bits[1].begins_with("touch="):
					touches.append([float(bits[0]), int(bits[1].trim_prefix("touch=")), int(bits[2])])
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[dsprobe] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or core.is_empty():
		print("[dsprobe] SKIP: pass --root=<throwaway root> --core=<core>")
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	print("[dsprobe] core=%s rom=%s gba=%s opts=%s" % [core, rom if not rom.is_empty() else "(none)",
		gba if not gba.is_empty() else "(none)", opts])
	if not opts.is_empty():
		CoreOptionsStore.merge_values(root_dir, core, opts)
	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _load_failed = reason)
	_lib.connect("options_ready", _on_options_ready)
	if not gba.is_empty():
		# The third file is the GBA save, which the core opens itself and refuses
		# the load over when it does not exist (Slot2Catalog).
		var sav := root_dir.path_join("slot2_probe.sav")
		# Seeded the way ExpansionLaunch seeds a first run: an empty file is refused.
		var f := FileAccess.open(sav, FileAccess.WRITE)
		f.store_buffer(Slot2Catalog.blank_gba_save(gba))
		f.close()
		_lib.StartSubsystemContent(root_dir, core, rom, "gba", PackedStringArray([rom, gba, sav]))
	elif rom.is_empty():
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", true)
		_lib.StartContent(root_dir, core, "")
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", false)
	else:
		_lib.StartContent(root_dir, core, rom)

	var end_at := 0.0
	for t: float in sample_at:
		end_at = maxf(end_at, t)
	var sorted := sample_at.duplicate()
	sorted.sort()
	var next_sample := 0
	var t0 := Time.get_ticks_msec()
	while _load_failed.is_empty():
		var now := Time.get_ticks_msec() - t0
		var mask := 0
		for p: Array in presses:
			var at := int(float(p[0]) * 1000.0)
			if now >= at and now < at + PRESS_MS:
				mask |= 1 << int(p[1])
		_lib.SetJoypadState(0, mask, 0, 0, 0, 0)
		var touching := false
		for t: Array in touches:
			var at := int(float(t[0]) * 1000.0)
			if now >= at and now < at + PRESS_MS:
				touching = true
				# Pointer space is -0x7fff..0x7fff over the whole 256x384 frame; the
				# bottom screen is its lower half.
				var px := int((float(t[1]) / 256.0) * 65534.0) - 32767
				var py := int(((192.0 + float(t[2])) / 384.0) * 65534.0) - 32767
				_lib.SetPointerState(0, px, py, true)
		if not touching and not touches.is_empty():
			_lib.SetPointerState(0, 0, 0, false)
		if next_sample < sorted.size() and now >= int(float(sorted[next_sample]) * 1000.0):
			_sample(float(sorted[next_sample]))
			next_sample += 1
		if now >= int(end_at * 1000.0):
			break
		await get_tree().process_frame
	if not _load_failed.is_empty():
		print("[dsprobe] REFUSED: %s" % _load_failed)
	_lib.StopContent()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if _load_failed.is_empty() else 1)


func _on_options_ready(_categories: Dictionary, definitions: Dictionary, values: Dictionary) -> void:
	for key: String in opts:
		print("[dsprobe] option %s: core %s it, value now %s" % [key,
			"DECLARES" if definitions.has(key) else "does NOT declare", values.get(key, "-")])
	if not print_options:
		return
	var keys: Array = definitions.keys()
	keys.sort()
	for key: String in keys:
		var d: Object = definitions[key]
		var choices := PackedStringArray()
		for v: Variant in d.get("values") if d.get("values") != null else []:
			choices.append(str(v.get("value")) if v is Object else str(v))
		print("[dsprobe] opt %s = %s  [%s]" % [key, values.get(key, "-"), "|".join(choices)])


func _sample(at: float) -> void:
	var img: Image = _lib.GetVideoImage()
	if img == null or img.is_empty():
		print("[dsprobe] t=%5.1f frames=%d (no image)" % [at, int(_lib.GetFrameCount())])
		return
	var flat := img.duplicate() as Image
	flat.convert(Image.FORMAT_RGB8)
	if not shot.is_empty():
		flat.save_png(shot.get_basename() + ("_%05.1f." % at).replace(" ", "0") + shot.get_extension())
	# Every pixel: a home screen is mostly white and a crashed one uniformly one
	# colour, so the count of distinct colours is what tells them apart.
	var raw := flat.get_data()
	var colours: Dictionary = {}
	var lit := 0
	for i: int in range(0, raw.size(), 3):
		if raw[i] + raw[i + 1] + raw[i + 2] > 16:
			lit += 1
		colours[(raw[i] >> 3) << 10 | (raw[i + 1] >> 3) << 5 | (raw[i + 2] >> 3)] = true
	print("[dsprobe] t=%5.1f frames=%d size=%dx%d lit=%.3f colours=%d" % [at,
		int(_lib.GetFrameCount()), flat.get_width(), flat.get_height(),
		float(lit) / maxf(1.0, float(raw.size() / 3)), colours.size()])
