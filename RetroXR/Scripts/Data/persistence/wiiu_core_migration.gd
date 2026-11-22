## WiiUCoreMigration — the Wii U moved from RetroXR's Cemu fork (`cemu`) to
## libretro's parallel-gx2 (`parallel_gx2`), and a core's files live under its
## own name: save/<core>/Cemu/mlc01 (the console's memory: saves, accounts, an
## installed system dump, the Wii U Menu) and system/<core>/Cemu (cafeLibs, the
## native keyboard among them; keys.txt; titles/, updates and DLC). Moved once,
## so a player's Wii U is the same Wii U on the new core.
##
## Never overwrites: mlc01 is MOVED (a rename, 754 MB is not copied at boot)
## only where the new core has none; a system file or a titles/ entry is copied
## only where the new core lacks it. Both cores holding an mlc01 is left alone
## and said in the log. Nothing to do once the old one is gone, so no marker.
class_name WiiUCoreMigration
extends RefCounted

const OLD_CORE := "cemu"
const NEW_CORE := "parallel_gx2"
## What the system folder carries that the new core reads too. The shader cache
## and the log are the core's own and rebuild.
const SYSTEM_ENTRIES := ["cafeLibs", "keys.txt", "titles"]


static func run_once() -> void:
	var root := CoreDownloadManager.default_core_root()
	var report := run(root.path_join("save"), root.path_join("system"))
	for line: String in report:
		print("[WiiUCoreMigration] %s" % line)


## Returns what it did and why, one line each (empty when there was nothing).
static func run(save_root: String, system_root: String) -> Array[String]:
	var out: Array[String] = []
	var old_mlc := save_root.path_join(OLD_CORE).path_join("Cemu/mlc01")
	var new_mlc := save_root.path_join(NEW_CORE).path_join("Cemu/mlc01")
	if DirAccess.dir_exists_absolute(old_mlc):
		if DirAccess.dir_exists_absolute(new_mlc):
			out.append("both cores have an mlc01; %s is used, %s is left as it is" % [new_mlc, old_mlc])
		else:
			DirAccess.make_dir_recursive_absolute(new_mlc.get_base_dir())
			var err := DirAccess.rename_absolute(old_mlc, new_mlc)
			out.append("mlc01 moved to %s" % new_mlc if err == OK
				else "could not move %s to %s (error %d); left where it is" % [old_mlc, new_mlc, err])
	var old_sys := system_root.path_join(OLD_CORE).path_join("Cemu")
	var new_sys := system_root.path_join(NEW_CORE).path_join("Cemu")
	if DirAccess.dir_exists_absolute(old_sys):
		for entry: String in SYSTEM_ENTRIES:
			_copy_missing(old_sys.path_join(entry), new_sys.path_join(entry), out)
	return out


## Copy `from` (a file, or a folder's tree) to `to`, file by file, skipping any
## file `to` already has.
static func _copy_missing(from: String, to: String, out: Array[String]) -> void:
	if FileAccess.file_exists(from):
		if FileAccess.file_exists(to):
			return
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var err := DirAccess.copy_absolute(from, to)
		out.append("copied %s" % to if err == OK else "could not copy %s (error %d)" % [from, err])
		return
	if not DirAccess.dir_exists_absolute(from):
		return
	DirAccess.make_dir_recursive_absolute(to)
	for f: String in DirAccess.get_files_at(from):
		_copy_missing(from.path_join(f), to.path_join(f), out)
	for d: String in DirAccess.get_directories_at(from):
		_copy_missing(from.path_join(d), to.path_join(d), out)
