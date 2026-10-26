## CoreInfoParser — static utility for reading libretro .info files.
##
## .info format is a simple key = "value" text file with # comments.
## Each filename is "{core_name}_libretro.info"; stripping that suffix gives
## the core_name used to match DLL filenames ({core_name}_libretro.dll).
class_name CoreInfoParser


## Parse a single .info file at the given absolute path.
## Returns a Dictionary with all key/value pairs found, plus:
##   "core_name"  — derived from the filename stem (e.g. "fceumm")
##   "info_path"  — the absolute path that was parsed
## Missing fields are absent from the dict (callers should use .get("key", "")).
static func parse_info_file(path: String) -> Dictionary:
	var result: Dictionary = {}

	# Derive core_name from filename: "fceumm_libretro.info" -> "fceumm"
	var filename: String = path.get_file()           # "fceumm_libretro.info"
	var stem: String = filename.get_basename()       # "fceumm_libretro"
	if stem.ends_with("_libretro"):
		stem = stem.left(stem.length() - "_libretro".length())
	result["core_name"] = stem
	result["info_path"] = path

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[CoreInfoParser] could not open %s (error %d)" % [path, FileAccess.get_open_error()])
		return result

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()

		# Skip blank lines and comments
		if line.is_empty() or line.begins_with("#"):
			continue

		# Split on the FIRST '=' only
		var eq_pos: int = line.find("=")
		if eq_pos < 0:
			continue

		var key: String   = line.left(eq_pos).strip_edges()
		var raw_val: String = line.right(line.length() - eq_pos - 1).strip_edges()

		# Strip surrounding quotes if present
		if raw_val.begins_with('"') and raw_val.ends_with('"') and raw_val.length() >= 2:
			raw_val = raw_val.substr(1, raw_val.length() - 2)

		if key.is_empty():
			continue

		# "notes" may be split across several lines (bk_libretro.info does it).
		# Its own separator is "|", so joining on that reconstructs one value —
		# last-wins would drop the firmware checksum table. Every other key is
		# single-valued.
		if key == "notes" and result.has(key):
			result[key] = str(result[key]) + "|" + raw_val
		else:
			result[key] = raw_val

	file.close()
	return result


## Parse all *.info files found directly inside info_dir (non-recursive).
## Returns an Array of Dictionaries, one per file, sorted by display_name.
## Files that cannot be opened are skipped with a warning.
static func parse_all(info_dir: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	var dir := DirAccess.open(info_dir)
	if dir == null:
		push_error("[CoreInfoParser] cannot open info directory '%s' (error %d)" % [info_dir, DirAccess.get_open_error()])
		return results

	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".info"):
			var full_path: String = info_dir.path_join(fname)
			var entry: Dictionary = parse_info_file(full_path)
			if entry.get("core_name", "") != "":
				results.append(entry)
		fname = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically by display_name for consistent UI ordering
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("display_name", a.get("core_name", "")).naturalnocasecmp_to(
			b.get("display_name", b.get("core_name", ""))) < 0
	)

	return results
