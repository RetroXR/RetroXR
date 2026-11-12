## pack_mod — build a mod pack out of res://mods/<id>/, and prove it is loadable.
##
##   godot --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --id=xenu.snes
##   godot --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --id=xenu.snes --out=Z:/xenu.snes.zip
##   godot --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --check=Z:/xenu.ps2.zip
##
## EVERY PACK NEEDS A PREVIEW IMAGE: res://mods/<id>/thumbnail.png, 16:9 and at
## least 512x288. It is the tile the mod browser shows for an installed mod, and
## the same file is the logo on the mod's mod.io page. A pack without one is not
## written. (The loader still accepts an old pack that has none; only the packer
## insists.)
##
## Writes a .zip resource pack, which is the recommended format: Godot mounts one
## exactly as it does a .pck, and it can be read member-by-member WITHOUT being
## mounted, which is how the Mods page shows a disabled mod's name and thumbnail.
##
## Source files (.gd, .tscn, .tres, .json, .gdshader and the like) are packed
## verbatim.
##
## MODELS, TEXTURES AND AUDIO are packed in their IMPORTED form. Godot never loads
## a .glb or a .png itself: it loads what the file's .import names, under
## res://.godot/imported/. That folder is outside the mod's namespace, and the
## loader refuses a pack that writes outside res://mods/<id>/ (which is also why a
## plain --export-pack of a mod is refused). So each imported file goes into the
## pack under res://mods/<id>/_imported/, and the .import is rewritten to name it
## there. Import first -- open the project in the editor once, or
##
##   godot --headless --path RetroXR --import
##
## -- or the asset is reported as not imported and nothing is written. Both
## families of compressed texture the project imports (desktop and Quest) go in,
## so one pack runs everywhere. thumbnail.png alone goes in as the plain PNG,
## since the Mods page reads it without mounting the pack.
##
## --check=<pack> puts a pack made some other way through the same verification.
##
## Either way, the result is read back through ModPackReader before this exits. A pack whose manifest the loader cannot find is a mod that silently
## fails to appear in the list, and finding that out at pack time is much cheaper
## than finding it out on a headset.
extends SceneTree

## Never packed, whatever a mod's folder happens to contain. Each of these would
## replace the running game's own copy rather than merely failing.
const FORBIDDEN_NAMES := ["project.binary", "project.godot",
	"global_script_class_cache.cfg", "uid_cache.bin"]

## Packed verbatim when they have no .import beside them.
const SOURCE_EXTS := ["gd", "tscn", "tres", "json", "txt", "md",
	"gdshader", "gdshaderinc", "uid", "png", "svg"]

## Where a pack carries its imported files, inside its own namespace.
const IMPORTED_DIR := "_imported"


func _init() -> void:
	var mod_id := ""
	var out := ""
	var check := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--id="):
			mod_id = a.substr(5)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--check="):
			check = a.substr(8)
	if not check.is_empty():
		quit(0 if _check(check) else 1)
		return
	if mod_id.is_empty():
		print("usage: --id=<mod id> [--out=<path>]   or   --check=<pack>")
		quit(1)
		return

	var src := "res://mods/%s" % mod_id
	if not DirAccess.dir_exists_absolute(src):
		print("[pack] no such mod: %s" % src)
		quit(1)
		return
	var manifest_path := src + "/mod.json"
	if not FileAccess.file_exists(manifest_path):
		print("[pack] %s has no mod.json" % src)
		quit(1)
		return

	var manifest := ModManifest.parse(JsonStore.read_dict(manifest_path, "pack_mod"))
	if not manifest.error.is_empty():
		print("[pack] mod.json is not usable: %s" % manifest.error)
		quit(1)
		return
	if manifest.id != mod_id:
		print("[pack] mod.json says id '%s' but it lives in mods/%s/"
			% [manifest.id, mod_id])
		quit(1)
		return

	# Before anything is written, so a mod with no picture leaves no pack behind
	# that looks finished.
	var thumb_err := ModManifest.thumbnail_error(
		FileAccess.get_file_as_bytes(src.path_join(ModManifest.THUMBNAIL_NAME)))
	if not thumb_err.is_empty():
		print("[pack] %s" % thumb_err)
		quit(1)
		return

	if out.is_empty():
		out = "%s/%s.zip" % [RomLibrary.default_mods_root(), mod_id]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())

	var members := PackedStringArray()
	_collect(src, members)
	if members.is_empty():
		print("[pack] nothing to pack in %s" % src)
		quit(1)
		return

	# Pack path -> bytes. Gathered in full before the zip is opened, so a mod with
	# an asset that is not imported leaves no half-written pack behind.
	var entries := {}
	var skipped := PackedStringArray()
	var problems := PackedStringArray()
	var thumb_path := src.path_join(ModManifest.THUMBNAIL_NAME)
	for path: String in members:
		var base := path.get_file()
		var ext := path.get_extension().to_lower()
		if FORBIDDEN_NAMES.has(base):
			skipped.append(path + "  (would replace the game's own)")
			continue
		# The Mods page reads the thumbnail as a plain PNG out of the unmounted
		# pack, so it goes in as the file and its .import stays behind.
		if path == thumb_path:
			entries[path] = FileAccess.get_file_as_bytes(path)
			continue
		if path == thumb_path + ".import":
			continue
		if ext == "import":
			_take_import(path, src, entries, problems)
			continue
		# An imported asset's source: its .import and imported file stand for it.
		if FileAccess.file_exists(path + ".import"):
			continue
		if not SOURCE_EXTS.has(ext):
			problems.append("%s has no .import, so it is not imported; run "
				% path + "godot --headless --path RetroXR --import")
			continue
		var data := FileAccess.get_file_as_bytes(path)
		if data.is_empty() and FileAccess.get_open_error() != OK:
			skipped.append(path + "  (unreadable)")
			continue
		entries[path] = data
	if not problems.is_empty():
		for p: String in problems:
			print("[pack] FAILED: %s" % p)
		quit(1)
		return

	var z := ZIPPacker.new()
	var err := z.open(out)
	if err != OK:
		print("[pack] cannot write %s (error %d)" % [out, err])
		quit(1)
		return
	for path: String in entries:
		# Stored without the res:// prefix, which is how a zip resource pack is
		# laid out and what ModPackReader expects.
		z.start_file(path.trim_prefix("res://"))
		z.write_file(entries[path])
		z.close_file()
	z.close()

	for s: String in skipped:
		print("[pack] skipped %s" % s)
	print("[pack] wrote %s (%d files)" % [out, entries.size()])
	quit(0 if _verify(out, manifest, entries.keys()) else 1)


## Pack what an .import names under the mod's own _imported/ folder, and the
## .import itself rewritten to name the copies. Only its [remap] section goes in:
## that is all a running game reads (the rest is the editor's import settings).
func _take_import(path: String, src: String, entries: Dictionary,
		problems: PackedStringArray) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		problems.append("%s cannot be read" % path)
		return
	var slim := ConfigFile.new()
	if not cfg.has_section("remap"):
		cfg.set_value("remap", "importer", "keep")
	var moved := 0
	for key: String in cfg.get_section_keys("remap"):
		var value: Variant = cfg.get_value("remap", key)
		if key == "path" or key.begins_with("path."):
			var from := str(value)
			if not FileAccess.file_exists(from):
				problems.append("%s is not imported yet (%s is missing); run "
					% [path.trim_suffix(".import"), from]
					+ "godot --headless --path RetroXR --import")
				return
			var to := src.path_join(IMPORTED_DIR).path_join(from.get_file())
			entries[to] = FileAccess.get_file_as_bytes(from)
			value = to
			moved += 1
		slim.set_value("remap", key, value)
	if moved == 0:
		# "Keep File" and skipped imports name nothing: the source itself is the
		# resource, so it goes in as it is.
		var source := path.trim_suffix(".import")
		entries[source] = FileAccess.get_file_as_bytes(source)
		return
	entries[path] = slim.encode_to_text().to_utf8_buffer()


## Walk the mod's folder. Uses DirAccess rather than a res:// glob so it also
## works on a folder that has not been imported yet.
func _collect(dir_path: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect(full, into)
		else:
			into.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## Verify a pack made some other way -- an --export-pack one -- with the same
## checks, reading its manifest out of the pack itself.
func _check(path: String) -> bool:
	var r := ModPackReader.open(path)
	if not r.error.is_empty():
		print("[pack] FAILED verification: %s" % r.error)
		return false
	var manifest: ModManifest = null
	for member: String in r.files():
		if member.begins_with(ModManifest.NAMESPACE_ROOT) and member.ends_with("/mod.json") \
				and member.count("/") == 4:
			manifest = ModManifest.parse(r.read_json(member))
			break
	r.close()
	if manifest == null:
		print("[pack] FAILED verification: no mod.json under res://mods/<id>/")
		return false
	if not manifest.error.is_empty():
		print("[pack] FAILED verification: manifest unreadable: %s" % manifest.error)
		return false
	return _verify(path, manifest)


## Read the finished pack back the way the loader will. This is the check that
## matters: everything above can succeed and still produce a pack the Mods page
## never shows.
func _verify(path: String, manifest: ModManifest, expected: Array = []) -> bool:
	var r := ModPackReader.open(path)
	if not r.error.is_empty():
		print("[pack] FAILED verification: %s" % r.error)
		return false
	var files := r.files()
	var found := ModManifest.parse(r.read_json(manifest.own_root() + "mod.json"))
	var thumb := r.read(manifest.own_root() + ModManifest.THUMBNAIL_NAME)
	r.close()
	if not found.error.is_empty():
		print("[pack] FAILED verification: manifest unreadable: %s" % found.error)
		return false
	if found.id != manifest.id:
		print("[pack] FAILED verification: manifest id changed in the pack")
		return false
	var inventory := manifest.inventory_error(files)
	if not inventory.is_empty():
		print("[pack] FAILED verification: the loader would refuse this pack: %s"
			% inventory)
		return false
	var thumb_err := ModManifest.thumbnail_error(thumb)
	if not thumb_err.is_empty():
		print("[pack] FAILED verification: %s" % thumb_err)
		return false
	if not ResourceLoader.exists(manifest.entry) and not files.has(manifest.entry):
		print("[pack] FAILED verification: entry script %s is not in the pack"
			% manifest.entry)
		return false
	for member: String in expected:
		if not files.has(member):
			print("[pack] FAILED verification: %s is missing from the pack" % member)
			return false
	print("[pack] verified: the loader can read %s %s"
		% [manifest.id, manifest.version])
	return true
