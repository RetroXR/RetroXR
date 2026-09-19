## SystemIdMigration — moves the folders named for a systemid to the name it has
## now (see SystemIds), once per data root.
##
## Two trees are named by systemid: save/carts/<systemid>/ and roms/<systemid>/.
## Everything ELSE keyed by one is a JSON file an autoload has already read by
## the time anything can run, so those are read through SystemIds as they load
## (BindingStore, CoreDefaults, AppPrefs, RommConfig, RommCacheManifest and the
## save-sync ledger's rom ids) and nothing here touches them.
##
## SAVES move a file at a time through SaveMigration's own placement, so a save
## under both names keeps the newer and sets the older aside, and the RomM
## ledger follows each file. Until they move, SramPaths.resolve_cart_save still
## finds them: it sweeps every folder under save/carts/.
##
## A ROM FOLDER moves whole -- its gamelist, media and RomM index go with it --
## and only when nothing is already at the new name. It can fail: a folder adb
## made on a Quest is not the app's to rename. RomLibrary.rom_dir_for_system
## asks the disk which name exists, so a folder left behind is still the
## library. That is why a failed ROM move is reported and does not hold the
## marker back, where a failed save move does.
class_name SystemIdMigration
extends RefCounted

const MARKER_KEY := "systemids"
const VERSION := 1


## The player's own trees, unless the marker says it is already done.
static func run_once(ledger: Object) -> void:
	var save_root := CoreDownloadManager.default_core_root().path_join("save")
	var marker := save_root.path_join(SaveMigration.MARKER)
	var state := JsonStore.read_dict(marker)
	if JsonStore.get_int(state, MARKER_KEY, 0) >= VERSION:
		return
	var report := run(save_root, RomLibrary.default_roms_root(), ledger)
	print("[SystemIdMigration] saves: moved %d, %d failed; rom folders: moved %d, %d left"
		% [report["moved"].size(), report["failed"].size(),
			report["folders"].size(), report["folders_left"].size()])
	if report["failed"].is_empty():
		state[MARKER_KEY] = VERSION
		JsonStore.write_dict(marker, state, "SystemIdMigration")


## Report: {moved: [[from, to], ...], failed: [path, ...],
##          folders: [[from, to], ...], folders_left: [path, ...]}.
##
## `ledger` answers rekey(old_path, new_path) -> bool and save_state(); null skips
## it. The roots are arguments so a test can point this at a scratch tree.
static func run(save_root: String, roms_root: String, ledger: Object) -> Dictionary:
	var report := {"moved": [], "left": [], "failed": [], "folders": [], "folders_left": []}
	var rekeyed := false
	var carts := save_root.path_join("carts")
	for old: String in SystemIds.LEGACY:
		var from := carts.path_join(old)
		if DirAccess.dir_exists_absolute(from):
			rekeyed = _move_saves(from, carts.path_join(SystemIds.LEGACY[old]), ledger, report) or rekeyed
	if rekeyed and ledger != null:
		ledger.call("save_state")

	for old: String in SystemIds.LEGACY:
		var from := roms_root.path_join(old)
		var to := roms_root.path_join(SystemIds.LEGACY[old])
		if not DirAccess.dir_exists_absolute(from):
			continue
		if DirAccess.dir_exists_absolute(to) or DirAccess.rename_absolute(from, to) != OK:
			report["folders_left"].append(from)
			print("[SystemIdMigration] %s stays; it is still read as %s" % [from, SystemIds.LEGACY[old]])
			continue
		report["folders"].append([from, to])
		print("[SystemIdMigration] %s -> %s" % [from, to])
	RomLibrary.forget_rom_dirs()
	return report


## Every file under save/carts/<old>/<game>/ to the same place under <new>.
static func _move_saves(from: String, to: String, ledger: Object, report: Dictionary) -> bool:
	var rekeyed := false
	for game: String in DirAccess.get_directories_at(from):
		var game_dir := from.path_join(game)
		for file_name: String in DirAccess.get_files_at(game_dir):
			var source := game_dir.path_join(file_name)
			var dest := to.path_join(game).path_join(file_name)
			var label := from.get_file()
			if file_name.get_extension() == "srm":
				rekeyed = SaveMigration._place(dest, [{"path": source, "label": label}],
					ledger, report) or rekeyed
			elif not FileAccess.file_exists(dest):
				# A clock, or a save set aside earlier: nothing to weigh it against.
				DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
				rekeyed = SaveMigration._move(source, dest, ledger, report) or rekeyed
		DirAccess.remove_absolute(game_dir)
	DirAccess.remove_absolute(from)
	return rekeyed
