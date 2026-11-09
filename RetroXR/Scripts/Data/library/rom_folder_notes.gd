## RomFolderNotes — what the ROM library will make of a folder under roms/, said
## to a player who is putting files there by hand (the Web File Manager).
##
## The library never says why a file is missing: RomLibrary.scan_roms() keeps what
## matches the system's extensions, looks in no subfolder, and drops the rest in
## silence. A .gba uploaded into roms/snes/, a game put in roms/gba/Golden Sun/, a
## folder named for a machine RetroXR has no core for -- each simply never shows.
## This answers, per entry, with the SAME rules the scan uses:
##
##   the system  SystemIds.systemid_for_folder() (aliases and old names included)
##   the types   CoreInfoDatabase.extensions_for_systemid(), as the browser asks,
##               or the library list of the three that keep their own
##               (PocketStation, VMU, e-Reader)
##   subfolders  entered only for a folder_content system (one game a folder),
##               and arcade disc folders, which ride with the board beside them
##
## Notes are ADVICE, never a refusal: a core's .info list is not perfect, and a
## file that might still work is the player's to keep. Each is a code the page
## words:
##   "unknown_folder"  a folder directly under roms/ that is no system
##   "not_listed"      a file the library will not show in this system
##   "not_scanned"     a folder (or anything inside one) the library never opens
##   "loose"           a file directly in roms/, outside every system's folder
##
## Left alone on purpose: what the app writes itself (media/, .romm, gamelist.json),
## dotfiles, a file sharing its name with a game beside it (Game.srm by Game.sfc),
## the track files of a .cue/.gdi/.ccd/.mds set (only the descriptor is listed),
## and anything a RomM download put there: the browser lists those through the
## server's index whatever their type (a .zip, a folder of discs), not by the scan.
class_name RomFolderNotes
extends RefCounted


## Files and folders the app keeps inside a system's ROM folder.
const APP_ENTRIES := ["media", "gamelist.json", "gamelist.xml"]

## Files the app keeps directly in roms/ (ScraperConfig, RaConfig and
## RommCacheManifest write them there; web_server_tests holds the names to theirs).
const ROOT_APP_FILES := ["scraper_config.json", "ra_config.json", "romm_cache.json"]

## Folders the app makes in roms/ that are no system: `unknown` is where a core
## with no systemid is filed, made with the rest and shown as no tile.
const ROOT_APP_DIRS := ["unknown"]

## A disc set's descriptors, and the track files one of them makes a companion.
const SET_DESCRIPTORS := ["cue", "gdi", "ccd", "mds"]
const SET_TRACKS := ["bin", "raw", "img", "sub", "wav", "mdf", "iso"]


## {system, systemid, exts, here, notes} for `dir_path`, given what is in it.
##   system    the platform's display name ("" outside a system's folder)
##   exts      what that system lists, sorted (empty outside one)
##   here      a note on the folder itself ("" when it is fine)
##   notes     entry name -> note, for entries that have one
## `owned` is what RomM downloads hold in this system's folder, as paths relative
## to it (romm_owned()); they are never noted.
## Empty when `dir_path` is not under `roms_root` at all.
static func describe(roms_root: String, dir_path: String, dirs: Array, files: Array,
		owned: PackedStringArray = PackedStringArray()) -> Dictionary:
	var root := roms_root.simplify_path()
	var full := dir_path.simplify_path()
	if full == root:
		return _describe_root(dirs, files)
	if not full.begins_with(root + "/"):
		return {}

	var parts := full.substr(root.length() + 1).split("/", false)
	var systemid := SystemIds.systemid_for_folder(parts[0])
	var exts := extensions_for(systemid)
	var out := {"system": "", "systemid": "", "exts": [], "here": "", "notes": {}}
	if exts.is_empty():
		out["here"] = "unknown_folder"
		return out
	out["system"] = display_name(systemid)
	out["systemid"] = systemid
	var sorted := exts.duplicate()
	sorted.sort()
	out["exts"] = sorted

	if parts.size() > 1:
		# Inside a subfolder: fine only where the scan goes, and then everything
		# below it is the game's own business.
		if _holds_owned(owned, "/".join(parts.slice(1))):
			return out
		if not _subfolder_scanned(systemid, root.path_join(parts[0]), parts[1]):
			out["here"] = "not_scanned"
			for d: Variant in dirs:
				out["notes"][str(d)] = "not_scanned"
			for f: Variant in files:
				out["notes"][str(f)] = "not_scanned"
		return out

	var notes: Dictionary = out["notes"]
	for d: Variant in dirs:
		var name := str(d)
		if name.begins_with(".") or name in APP_ENTRIES or _holds_owned(owned, name):
			continue
		if not _subfolder_scanned(systemid, full, name):
			notes[name] = "not_scanned"
	var games: Dictionary = {}       # lowercase stem of every listed file
	var has_set := false
	for f: Variant in files:
		var ext := str(f).get_extension().to_lower()
		if ext in exts:
			games[str(f).get_basename().to_lower()] = true
		if ext in SET_DESCRIPTORS and ext in exts:
			has_set = true
	for f: Variant in files:
		var name := str(f)
		if name.begins_with(".") or name in APP_ENTRIES:
			continue
		var ext := name.get_extension().to_lower()
		if ext in exts or name in owned:
			continue
		if games.has(name.get_basename().to_lower()):
			continue  # a save, a cover, a track: it rides with its game
		if has_set and ext in SET_TRACKS:
			continue
		notes[name] = "not_listed"
	return out


## The roms/ folder itself: each folder is a system or it is not, and a file
## there belongs to none.
static func _describe_root(dirs: Array, files: Array) -> Dictionary:
	var notes: Dictionary = {}
	for d: Variant in dirs:
		var name := str(d)
		if name.begins_with(".") or name in ROOT_APP_DIRS:
			continue
		if extensions_for(SystemIds.systemid_for_folder(name)).is_empty():
			notes[name] = "unknown_folder"
	for f: Variant in files:
		var name := str(f)
		if name.begins_with(".") or name in ROOT_APP_FILES:
			continue
		notes[name] = "loose"
	return {"system": "", "systemid": "", "exts": [], "here": "", "notes": notes}


## What the library lists for `systemid`, as its callers ask for it.
static func extensions_for(systemid: String) -> Array[String]:
	var exts := CoreInfoDatabase.extensions_for_systemid(systemid)
	var own: Array = []
	match systemid:
		PocketStation.LIBRARY_SYSTEMID:
			own = PocketStation.LIBRARY_EXTENSIONS
		VmuCard.LIBRARY_SYSTEMID:
			own = VmuCard.LIBRARY_EXTENSIONS
		EReaderCards.SYSTEMID:
			own = ["raw"]
	for e: Variant in own:
		if str(e) not in exts:
			exts.append(str(e))
	return exts


static func display_name(systemid: String) -> String:
	var info := SystemInfo.for_system(systemid)
	if info != null and not info.display_name.is_empty():
		return info.display_name
	return systemid


## Whether the scan enters `sub` inside the system folder `system_dir`.
static func _subfolder_scanned(systemid: String, system_dir: String, sub: String) -> bool:
	if sub.begins_with(".") or sub in APP_ENTRIES:
		return true  # the app's own; not the player's to be warned about
	var info := SystemInfo.for_system(systemid)
	if info != null and info.folder_content:
		return true
	if ArcadeDiscs.applies(systemid):
		for ext: String in ArcadeDiscs.BOARD_EXTS:
			if FileAccess.file_exists(system_dir.path_join(sub + "." + ext)):
				return true
	return false


## Whether a RomM download holds `rel` itself or anything below it.
static func _holds_owned(owned: PackedStringArray, rel: String) -> bool:
	for p: String in owned:
		if p == rel or p.begins_with(rel + "/"):
			return true
	return false


## The systemid of the system folder `dir_path` is in, or "" outside one.
static func systemid_at(roms_root: String, dir_path: String) -> String:
	var root := roms_root.simplify_path()
	var full := dir_path.simplify_path()
	if not full.begins_with(root + "/"):
		return ""
	return SystemIds.systemid_for_folder(full.substr(root.length() + 1).split("/", false)[0])


## Every file RomM downloads hold for `systemid`, relative to its ROM folder: each
## group's members and launch file. Read straight off the manifest
## (RommCacheManifest.read_entries(), which publishes nothing), so it is safe from
## the server's thread.
static func romm_owned(systemid: String) -> PackedStringArray:
	var out := PackedStringArray()
	if systemid.is_empty():
		return out
	var entries := RommCacheManifest.read_entries()
	for key: String in entries:
		var group: Dictionary = entries[key]
		if str(group.get("systemid", "")) != systemid:
			continue
		for member: Dictionary in group.get("members", []):
			var rel := str(member.get("path", "")).replace("\\", "/").simplify_path()
			if not rel.is_empty() and rel not in out:
				out.append(rel)
		var launch := str(group.get("launch", "")).replace("\\", "/").simplify_path()
		if not launch.is_empty() and launch not in out:
			out.append(launch)
	return out
