## SaveMigration — moves cartridge saves from save/<core>/ into
## save/carts/<systemid>/ (see SramPaths), once per data root.
##
## Each file is resolved on its own, never a folder at a time: one core's folder
## holds more than one system's saves. The systemid comes from the saved room that
## holds the cartridge, else from the ROM library folder holding a ROM of the same
## name. A file neither names stays put, where SramPaths.resolve_cart_save still
## finds it.
##
## Only RetroXR's own files move: <core>/<game stem>/<save_id>.srm and a unit's
## <core>/<expansion_id>/<expansion_id>.srm. Anything else under save/<core>/
## belongs to the core.
class_name SaveMigration
extends RefCounted

const MARKER := ".retroxr_save_layout.json"
const LAYOUT := 2


## The player's own save tree, unless its marker says it is already done. The
## marker is not written while a move failed, so a failure is retried next launch.
static func run_once(ledger: Object) -> void:
	var save_root := CoreDownloadManager.default_core_root().path_join("save")
	var marker := save_root.path_join(MARKER)
	if JsonStore.get_int(JsonStore.read_dict(marker), "layout", 1) >= LAYOUT:
		return
	var report := run(save_root, ScenePersistence.ROOMS_DIR, RomLibrary.default_roms_root(), ledger)
	print("[SaveMigration] moved %d, left %d unresolved, %d failed"
		% [report["moved"].size(), report["left"].size(), report["failed"].size()])
	if report["failed"].is_empty():
		JsonStore.write_dict(marker, {"layout": LAYOUT}, "SaveMigration")


## Report: {moved: [[from, to], ...], left: [path, ...], failed: [path, ...]}.
##
## `ledger` answers rekey(old_path, new_path) -> bool and save_state(); null skips
## the sync ledger.
static func run(save_root: String, rooms_dir: String, roms_root: String,
		ledger: Object) -> Dictionary:
	var report := {"moved": [], "left": [], "failed": []}
	if not DirAccess.dir_exists_absolute(save_root):
		return report
	var rooms := room_systemids(rooms_dir)
	var stems := {}
	var stems_built := false
	var groups := {}
	for core: String in DirAccess.get_directories_at(save_root):
		if core == "carts" or core == "memcards":
			continue
		var core_dir := save_root.path_join(core)
		for dir_name: String in DirAccess.get_directories_at(core_dir):
			for file_name: String in DirAccess.get_files_at(core_dir.path_join(dir_name)):
				if file_name.get_extension().to_lower() != "srm":
					continue
				var base := file_name.get_basename()
				var path := core_dir.path_join(dir_name).path_join(file_name)
				var systemid := ""
				if base == dir_name and ExpansionCatalog.has(dir_name):
					systemid = ExpansionCatalog.host_of(dir_name)
				elif rooms.has(base):
					systemid = str(rooms[base])
				elif is_minted_id(base):
					if not stems_built:
						stems = stem_index(roms_root)
						stems_built = true
					systemid = str(stems.get(dir_name, ""))
				else:
					continue
				if systemid.is_empty():
					report["left"].append(path)
					continue
				if systemid in SramPaths.PER_CORE_SYSTEMS:
					continue
				var dest := save_root.path_join("carts").path_join(systemid) \
					.path_join(dir_name).path_join(file_name)
				if not groups.has(dest):
					groups[dest] = []
				groups[dest].append({"path": path, "label": core})

	var rekeyed := false
	for dest: String in groups:
		rekeyed = _place(dest, groups[dest], ledger, report) or rekeyed
	if rekeyed and ledger != null:
		ledger.call("save_state")
	return report


## save_id -> systemid for every cartridge a saved room holds.
static func room_systemids(rooms_dir: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(rooms_dir):
		return out
	for room: String in DirAccess.get_directories_at(rooms_dir):
		var room_dir := rooms_dir.path_join(room)
		for file_name: String in DirAccess.get_files_at(room_dir):
			if file_name.get_extension() == "json" and file_name != "manifest.json":
				_collect(JsonStore.read_dict(room_dir.path_join(file_name)), out)
	return out


## ROM stem -> the systemid folder holding it, "" where two folders do. Reads each
## system folder and its per-game folders.
static func stem_index(roms_root: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(roms_root):
		return out
	for folder: String in DirAccess.get_directories_at(roms_root):
		# The folder may still carry the id from before the rename, or be another
		# of ES-DE's names for the machine.
		var systemid := SystemIds.systemid_for_folder(folder)
		if SystemInfo.for_system(systemid) == null:
			continue
		var sys_dir := roms_root.path_join(folder)
		var dirs: Array[String] = [sys_dir]
		for game: String in DirAccess.get_directories_at(sys_dir):
			dirs.append(sys_dir.path_join(game))
		for dir: String in dirs:
			for file_name: String in DirAccess.get_files_at(dir):
				var stem := file_name.get_basename()
				out[stem] = "" if out.has(stem) and out[stem] != systemid else systemid
	return out


## A save_id as RetroCartridge mints one.
static func is_minted_id(s: String) -> bool:
	if s.length() != 16:
		return false
	for c in s:
		if not c in "0123456789abcdef":
			return false
	return true


static func _collect(value: Variant, out: Dictionary) -> void:
	if value is Dictionary:
		var d: Dictionary = value
		var save_id := str(d.get("save_id", ""))
		var systemid := SystemIds.canonical(str(d.get("cart_systemid", "")))
		if not save_id.is_empty() and not systemid.is_empty():
			out[save_id] = systemid
		for v: Variant in d.values():
			_collect(v, out)
	elif value is Array:
		for v: Variant in value:
			_collect(v, out)


## The newest file takes `dest`; every other claimant, including a file already
## there, keeps its bytes under <save_id>.<label>.srm beside it.
static func _place(dest: String, sources: Array, ledger: Object, report: Dictionary) -> bool:
	var entries: Array = sources.duplicate()
	if FileAccess.file_exists(dest):
		entries.append({"path": dest, "label": "carts"})
	for e: Dictionary in entries:
		e["mtime"] = FileAccess.get_modified_time(str(e["path"]))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["mtime"]) > int(b["mtime"]))
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var rekeyed := false
	for i in range(1, entries.size()):
		var aside := _free_name(dest, str(entries[i]["label"]))
		rekeyed = _move(str(entries[i]["path"]), aside, ledger, report) or rekeyed
	if str(entries[0]["path"]) != dest:
		rekeyed = _move(str(entries[0]["path"]), dest, ledger, report) or rekeyed
	return rekeyed


static func _free_name(dest: String, label: String) -> String:
	var dir := dest.get_base_dir()
	var base := "%s.%s" % [dest.get_file().get_basename(), label]
	var candidate := dir.path_join(base + ".srm")
	var n := 2
	while FileAccess.file_exists(candidate):
		candidate = dir.path_join("%s %d.srm" % [base, n])
		n += 1
	return candidate


static func _move(from: String, to: String, ledger: Object, report: Dictionary) -> bool:
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		push_warning("[SaveMigration] cannot move %s -> %s (%s)" % [from, to, error_string(err)])
		report["failed"].append(from)
		return false
	report["moved"].append([from, to])
	print("[SaveMigration] %s -> %s" % [from, to])
	DirAccess.remove_absolute(from.get_base_dir())
	return ledger != null and bool(ledger.call("rekey", from, to))
