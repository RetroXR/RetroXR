## DataPaths — where the player's own files live, on each platform.
##
## The ROMs, books, videos, posters, music and mods the player supplies, plus
## the libretro tree the app fills in for them. One three-branch platform switch
## rather than the eleven that had grown: RomLibrary alone carried eight copies
## of it, differing only in the folder name on the end, and CoreDownloadManager
## and WebFileServer each had another.
##
## Copies of a platform switch do not drift evenly — they drift by OMISSION, and
## that is exactly what had happened. WebFileServer.server_root() had the Android
## branch and the Windows fallback and no Linux/macOS branch at all, so on those
## two it read an unset USERPROFILE and served "/retroxr": not the player's
## files, and not a directory that exists.
##
## The desktop default stays `~/retroxr` rather than following the app's rename. It
## holds the player's own ROM library, so moving it would strand every file they
## already put there. The player can point the root elsewhere (see the
## "chosen root" section below, and Scripts/UI/data_root_dialog.gd).
class_name DataPaths
extends RefCounted

## The app's external files directory. Plain `adb push` reaches this one; it is
## deliberately NOT `user://`, which on Android is internal storage the shell
## cannot write. See CLAUDE.md on why pushing into the app's own tree is a trap.
##
## Named after the RUNNING package, which user:// already carries
## (/data/user/0/<package>/files), rather than spelled out. A probe-only export
## installs under its own id (docs/dev/quest-device.md), and Android does not let
## one package see another's folder here at all: with the real app's name written
## in, a probe build had no data root, and every write it made failed.
static func android_root() -> String:
	var package := OS.get_user_data_dir().get_base_dir().get_file()
	if not package.begins_with("com.xenu.retroxr"):
		package = "com.xenu.retroxr"
	return "/sdcard/Android/data/%s/files" % package


## The player's data root, or a named folder inside it.
##
## `sub` is appended when given, so `media_root("roms")` and `media_root()` are
## the same call. Windows backslashes are folded to "/" because everything
## downstream — path_join, the file server's URLs, the RomM cache keys —
## assumes one separator.
static func media_root(sub: String = "") -> String:
	var root := ""
	if OS.get_name() == "Android":
		root = android_root()
	else:
		root = configured_root()
		if root.is_empty():
			root = default_root()
	return root if sub.is_empty() else root + "/" + sub


## Where the data root is when the player has not chosen one: `~/retroxr`.
static func default_root() -> String:
	if OS.get_name() == "Android":
		return android_root()
	if OS.get_name() in ["Linux", "macOS"]:
		return OS.get_environment("HOME") + "/retroxr"
	return OS.get_environment("USERPROFILE").replace("\\", "/") + "/retroxr"


# ── the player's chosen root (desktop only) ───────────────────────────────────
#
# Stored in user://, which is the app's own folder and not under the root it
# names. DataPaths reads it itself instead of asking AppPrefs: the Mods autoload
# runs first and needs the root before any other autoload exists.

const CONFIG_PATH := "user://data_root.json"

static var _config_path_override := ""
static var _cache_loaded := false
static var _cached_root := ""
static var _cached_pending_from := ""


static func _config_file() -> String:
	return _config_path_override if not _config_path_override.is_empty() else CONFIG_PATH


## Test seam: point at another config file and drop the cache. "" restores.
static func set_config_path_for_tests(path: String) -> void:
	_config_path_override = path
	_cache_loaded = false


static func _load_config() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	_cached_root = ""
	_cached_pending_from = ""
	# A torn or hand-broken file reads as "no choice" (the default root) rather
	# than stranding the player, but it says so: JsonStore logs it under the tag.
	var parsed: Variant = JsonStore.parse_dict(_config_file(), "DataPaths")
	if parsed is Dictionary:
		var cfg: Dictionary = parsed
		_cached_root = normalize(str(cfg.get("path", "")))
		_cached_pending_from = normalize(str(cfg.get("pending_move_from", "")))


## Staged and renamed (JsonStore): the file carries pending_move_from, so a
## write torn in place would lose a data-root move half done.
static func _save_config() -> bool:
	return JsonStore.write_dict(_config_file(), {"path": _cached_root,
		"pending_move_from": _cached_pending_from}, "DataPaths")


## Backslashes folded to "/", trailing slashes dropped, "." and ".." resolved.
## "" stays "".
static func normalize(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	p = p.simplify_path()
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.left(-1)
	return p


## Whether this platform lets the player move the root. Android's is fixed.
static func can_configure() -> bool:
	return OS.get_name() != "Android"


## The saved root, only if it is usable right now; "" means "use the default".
## A drive that is unplugged must not strand the player in an empty library, so
## an unusable saved path is ignored with a warning rather than followed.
static func configured_root() -> String:
	if not can_configure():
		return ""
	_load_config()
	if _cached_root.is_empty():
		return ""
	if not DirAccess.dir_exists_absolute(_cached_root):
		push_warning("[DataPaths] saved data folder is missing, using the default: %s" % _cached_root)
		return ""
	return _cached_root


## Whether the player has chosen a root, usable or not.
static func has_configured_root() -> bool:
	_load_config()
	return not _cached_root.is_empty()


## The exact destination of a pending move, even if its drive is unavailable.
## A move must never follow configured_root's fallback into a different folder.
static func saved_root() -> String:
	_load_config()
	return _cached_root


## Save `path` as the root. "" when accepted, else why not. Does not move files.
static func set_root(path: String, move_from: String = "") -> String:
	var why := validate(path)
	if not why.is_empty():
		return why
	_load_config()
	_cached_root = normalize(path)
	_cached_pending_from = normalize(move_from)
	return "" if _save_config() else "Could not save the setting."


## Save a choice for the NEXT process. The running room and its shutdown saves
## must keep using the old root, including when the new setting cannot be saved.
static func schedule_root_change(path: String, move_files: bool) -> String:
	var from := media_root()
	if normalize(path) == normalize(from):
		return "That is the folder already in use."
	if move_files:
		var why := DataRootMigration.check(from, path)
		if not why.is_empty():
			return why
	_load_config()
	var old_root := _cached_root
	var old_pending := _cached_pending_from
	var result := set_root(path, from if move_files else "")
	_cached_root = old_root
	_cached_pending_from = old_pending
	return result


## Forget the choice and go back to the default.
static func clear_root() -> void:
	_load_config()
	_cached_root = ""
	_cached_pending_from = ""
	if FileAccess.file_exists(_config_file()):
		DirAccess.remove_absolute(_config_file())


## Whether `path` can serve as the data root. Returns "" when ok, else the reason.
##
## Not a pure check: it CREATES the folder when it is missing, and writes then
## deletes a probe file in it to prove it is writable, because that is the only
## honest test of a drive. A path the player then rejects keeps the (empty)
## folder this made. set_root() calls it on every save.
static func validate(path: String) -> String:
	var p := normalize(path)
	if not can_configure():
		return "This platform's data folder cannot be changed."
	if p.is_empty():
		return "Choose a folder."
	if not p.is_absolute_path() or p.begins_with("res://") or p.begins_with("user://"):
		return "Choose a full folder path."
	var app_dir := normalize(ProjectSettings.globalize_path("user://"))
	if p == app_dir or p.begins_with(app_dir + "/"):
		return "That is the app's own settings folder."
	var err := DirAccess.make_dir_recursive_absolute(p)
	if err != OK and not DirAccess.dir_exists_absolute(p):
		return "That folder cannot be created."
	var probe := p + "/.retroxr_write_test"
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return "That folder is not writable."
	f.close()
	DirAccess.remove_absolute(probe)
	return ""


## The folder an interrupted or requested move still has to empty, or "".
static func pending_move_from() -> String:
	_load_config()
	return _cached_pending_from


static func clear_pending_move() -> bool:
	_load_config()
	var previous := _cached_pending_from
	_cached_pending_from = ""
	if not _save_config():
		_cached_pending_from = previous
		return false
	return true


## A normal desktop boot with an unfinished move. Mods and room startup wait
## until BootScene finishes it; suites and probes never move a player's files.
static func migration_mode() -> bool:
	if not can_configure() or Engine.is_editor_hint():
		return false
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://"):
			return false
	_load_config()
	return not _cached_pending_from.is_empty()


## Root of the libretro tree — cores, system/, save/.
##
## Android is the one platform where this is NOT under media_root: cores live in
## INTERNAL storage (`user://`), a different filesystem from the ROMs on /sdcard,
## because the app must be able to write them and the shell must not. That is a
## deliberate split rather than an oversight, which is why it is stated here
## instead of being folded into media_root.
static func libretro_root() -> String:
	if OS.get_name() == "Android":
		return OS.get_user_data_dir() + "/libretro"
	return media_root("libretro")
