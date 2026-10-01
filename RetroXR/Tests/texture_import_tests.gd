## texture_import_tests — a 3D model's textures reach the GPU compressed.
##
## A GLB's extracted textures import as Lossless, with "Detect 3D" set to flip
## them to VRAM Compressed the first time the EDITOR draws one. Imported headless,
## or never opened, they are never drawn: 101 of them shipped that way until
## 2026-09-30, every cartridge and console from that month. Lossless on a Quest
## means a PNG decoded on the CPU at load and uploaded as RGBA8 — ~532 MiB of
## them against ~100 MiB as ETC2 / ASTC, and slower to load.
##
## So this walks res://imported-assets and fails on any raster texture that does
## not import VRAM Compressed with mipmaps and a mobile (ETC2/ASTC) file, and on
## any normal map not imported as one (two channels; the engine rebuilds Z).
## High Quality (ASTC 4x4 on a Quest) is chosen per texture and is not checked:
## tools.md says which textures want it and how that was measured.
##
## Reads .import files only; no renderer, no device.
##
##   "$godot" --headless --path RetroXR res://Tests/texture_import_tests.tscn
extends Node

const ROOT := "res://imported-assets"
const RASTER := ["png", "jpg", "jpeg", "webp", "tga", "bmp"]
## "normal" as a word of the file name: _normal, Normal_, NormalGL. Not
## "trees_NormalTree_Bark", which is a tree's bark.
const NORMAL_NAME := "(?i)(^|[_. -])normal(gl|dx)?([_. -]|$)"

var _passed := 0
var _failed := 0


func _ready() -> void:
	var imports: Array[String] = []
	_walk(ROOT, imports)
	var textures := 0
	var lossless: Array[String] = []
	var no_mips: Array[String] = []
	var no_mobile: Array[String] = []
	var normals: Array[String] = []
	var normal_name := RegEx.create_from_string(NORMAL_NAME)
	for path: String in imports:
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK or str(cfg.get_value("remap", "importer", "")) != "texture":
			continue
		var src := path.trim_suffix(".import")
		# An .import left behind by a deleted image imports nothing.
		if not FileAccess.file_exists(src):
			continue
		textures += 1
		if int(cfg.get_value("params", "compress/mode", 0)) != 2:
			lossless.append(src)
			continue
		if not bool(cfg.get_value("params", "mipmaps/generate", false)):
			no_mips.append(src)
		if not (cfg.has_section_key("remap", "path.etc2") or cfg.has_section_key("remap", "path.astc")):
			no_mobile.append(src)
		if normal_name.search(src.get_file().get_basename()) != null \
				and int(cfg.get_value("params", "compress/normal_map", 0)) != 1:
			normals.append(src)

	# A walk that finds nothing passes every case below.
	_ok(textures >= 100, "found the model textures (%d)" % textures)
	_ok(lossless.is_empty(), "every model texture imports VRAM Compressed", _list(lossless))
	_ok(no_mips.is_empty(), "...with mipmaps", _list(no_mips))
	_ok(no_mobile.is_empty(), "...and an ETC2 or ASTC file for the Quest", _list(no_mobile))
	_ok(normals.is_empty(), "every normal map imports as a normal map", _list(normals))

	print("[teximport] %d cases, %s" % [_passed + _failed,
		"PASS" if _failed == 0 else "%d FAILURE(S)" % _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f: String in dir.get_files():
		if f.ends_with(".import") and f.trim_suffix(".import").get_extension().to_lower() in RASTER:
			out.append(dir_path.path_join(f))
	for d: String in dir.get_directories():
		_walk(dir_path.path_join(d), out)


func _list(paths: Array[String]) -> String:
	if paths.is_empty():
		return ""
	var shown := ", ".join(paths.slice(0, 5))
	return shown + (" and %d more" % (paths.size() - 5) if paths.size() > 5 else "")


func _ok(cond: bool, what: String, detail := "") -> void:
	if cond:
		_passed += 1
		print("[teximport] ok   %s" % what)
	else:
		_failed += 1
		print("[teximport] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])
