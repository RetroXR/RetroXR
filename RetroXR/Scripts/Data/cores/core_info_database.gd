## CoreInfoDatabase — in-memory store of all parsed libretro .info entries.
##
## Usage:
##   var db := CoreInfoDatabase.new()
##   db.load_from_project()  # auto-resolves path to libretro-core-info/
##   # or:
##   db.load(absolute_dir)
##
## The database is a plain RefCounted; create one instance and pass it around
## (e.g. owned by SpawnMenu2D, shared with download/manager tabs).
class_name CoreInfoDatabase
extends RefCounted


## All parsed core info entries. Each is a Dictionary with keys from the .info
## format (display_name, corename, systemname, systemid, secondary_systemids,
## license, description, supported_extensions, manufacturer, core_name,
## info_path, ...).
var cores: Array[Dictionary] = []

# Internal fast-lookup indices built during load().
var _by_core_name: Dictionary  = {}  # core_name -> Dictionary
var _by_systemid:  Dictionary  = {}  # systemid  -> Array[Dictionary]
# systemid -> Array[String]: the extensions cores declared for it as a SECONDARY
# platform. Only ids that appear in some core's `secondary_systemids` are keys.
var _secondary_exts: Dictionary = {}
# Every systemid that is some core's own `systemid`. A key of _by_systemid that
# is NOT in here was reached only through `secondary_systemids`.
var _primary_ids: Dictionary = {}

static var _shared: CoreInfoDatabase = null

## Platforms mods added to cores the game already has:
## systemid -> {core_name: String, exts: Array[String], owner: String}.
##
## Static and read at query time rather than folded into the indices, because
## there is no single database: the spawn menu parses its own, shared() caches
## another, and the tests build more. A mod applies after any of them may have
## loaded, and nothing would reload them. ModApi.register_core_system fills it.
static var _mod_systems: Dictionary = {}


## Lazily-loaded process-wide instance, for callers that want a single lookup and
## should not pay to re-parse every .info file to get it. Safe to cache: the
## directory ships inside the pck and cannot change at runtime.
static func shared() -> CoreInfoDatabase:
	if _shared == null:
		_shared = CoreInfoDatabase.new()
		_shared.load_from_project()
	return _shared


## Parse a `secondary_systemids` value into [{id: String, exts: Array[String]}].
## Format: "gamegear:gg|segacd:cue,iso,chd" — pipe between platforms, comma
## between that platform's extensions. Malformed entries are skipped.
static func parse_secondary_systemids(raw: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair: String in raw.split("|"):
		var colon := pair.find(":")
		if colon < 0:
			continue
		var id := pair.left(colon).strip_edges()
		if id.is_empty():
			continue
		var exts: Array[String] = []
		for e: String in pair.right(pair.length() - colon - 1).split(","):
			var ext := e.strip_edges().to_lower()
			if not ext.is_empty() and ext not in exts:
				exts.append(ext)
		out.append({"id": id, "exts": exts})
	return out


## Every systemid a core serves — its own first, then the platforms it named in
## `secondary_systemids`. Anything grouping installed or downloadable cores by
## platform must walk this, not `systemid` alone, or a multi-system core is only
## ever offered under its parent machine.
static func systemids_of(entry: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var primary := str(entry.get("systemid", "")).strip_edges()
	if not primary.is_empty():
		ids.append(primary)
	for sub: Dictionary in parse_secondary_systemids(str(entry.get("secondary_systemids", ""))):
		var id: String = sub["id"]
		if id not in ids:
			ids.append(id)
	for id: String in mod_systemids_of_core(str(entry.get("core_name", ""))):
		if id not in ids:
			ids.append(id)
	return ids


# ---------------------------------------------------------------------------
# Platforms added by mods
# ---------------------------------------------------------------------------

## Add `systemid` as a platform `core_name` serves, reading `exts`, as if the
## core's .info had named it in `secondary_systemids`. With that core installed
## the platform gets a Games tile and a default core like any other.
##
## "" on success, else why it was refused. Refused: a core the database does not
## know (a mod cannot ship one), an id some shipped core already serves (this
## adds platforms; it does not regroup the game's), an id another mod holds, and
## an extension the core does not read (a core handed a file it never claimed
## does not boot it, and ModContentPolicy's list of extensions that cannot ride
## in a pack is built from what the cores declare).
static func register_mod_system(systemid: String, core_name: String, exts: Array,
		owner_id: String = "") -> String:
	if systemid.is_empty():
		return "systemid is empty"
	if systemid == "unknown":
		return "'unknown' is where cores with no systemid are filed, not a platform"
	var db := shared()
	var core := db.get_by_core_name(core_name)
	if core.is_empty():
		return "no core named '%s' in the core database" % core_name
	if _mod_systems.has(systemid):
		var holder := str((_mod_systems[systemid] as Dictionary)["owner"])
		if holder != owner_id:
			return "%s is already added by mod '%s'" % [systemid, holder]
	elif db._by_systemid.has(systemid):
		return "%s is already a platform of the game's own cores" % systemid
	var reads: Array[String] = []
	for e: String in str(core.get("supported_extensions", "")).split("|"):
		reads.append(e.strip_edges().to_lower())
	var list: Array[String] = []
	for e: Variant in exts:
		var ext := str(e).strip_edges().trim_prefix(".").to_lower()
		if ext.is_empty() or ext in list:
			continue
		if ext not in reads:
			return "%s does not read .%s" % [core_name, ext]
		list.append(ext)
	if list.is_empty():
		return "%s needs at least one extension" % systemid
	_mod_systems[systemid] = {"core_name": core_name, "exts": list, "owner": owner_id}
	return ""


## Take back one mod's platforms.
static func drop_mod(owner_id: String) -> void:
	for systemid: String in _mod_systems.keys():
		if str((_mod_systems[systemid] as Dictionary)["owner"]) == owner_id:
			_mod_systems.erase(systemid)


## True while a mod has `systemid` on one of the cores.
static func is_mod_system(systemid: String) -> bool:
	return _mod_systems.has(systemid)


## The core a mod put `systemid` on, or "" for any other platform.
static func mod_core_of(systemid: String) -> String:
	if not _mod_systems.has(systemid):
		return ""
	return str((_mod_systems[systemid] as Dictionary)["core_name"])


## The platforms mods added to this core, in the order they were added.
static func mod_systemids_of_core(core_name: String) -> Array[String]:
	var out: Array[String] = []
	if core_name.is_empty():
		return out
	for systemid: String in _mod_systems:
		if str((_mod_systems[systemid] as Dictionary)["core_name"]) == core_name:
			out.append(systemid)
	return out


## Extensions (lowercase, no dots) that belong to this systemid: the union of
## supported_extensions across the cores whose OWN systemid this is, plus what
## any other core declared for it in `secondary_systemids`.
##
## A core reached only as a secondary contributes its declared subset and not its
## whole list. Genesis Plus GX reads fifteen extensions and one of them is Game
## Gear's; counting the rest would file every .md in the Game Gear library, and
## would push md/cue/chd/32x into Master System's the moment those cores name it.
static func extensions_for_systemid(systemid: String) -> Array[String]:
	var db := shared()
	var exts: Array[String] = []

	for entry: Dictionary in db.get_by_systemid(systemid):
		if str(entry.get("systemid", "")) != systemid:
			continue
		for e: String in str(entry.get("supported_extensions", "")).split("|"):
			var s := e.strip_edges().to_lower()
			if not s.is_empty() and s not in exts:
				exts.append(s)

	for e: String in db._secondary_exts.get(systemid, [] as Array[String]):
		if e not in exts:
			exts.append(e)

	if _mod_systems.has(systemid):
		for e: String in (_mod_systems[systemid] as Dictionary)["exts"]:
			if e not in exts:
				exts.append(e)

	return exts


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

## Load all .info files from an absolute directory path.
func load_directory(info_dir: String) -> void:
	cores = CoreInfoParser.parse_all(info_dir)
	_rebuild_indices()
	print("[CoreInfoDatabase] Loaded %d cores from: %s" % [cores.size(), info_dir])


## Convenience: load from the vendored core-info files at
## res://libretro-core-info/ (see that directory's README for their provenance),
## then lay our own on top.
func load_from_project() -> void:
	var info_dir: String = "res://libretro-core-info"
	print("[CoreInfoDatabase] Resolved info dir: %s" % info_dir)
	load_directory(info_dir)
	load_overlay(OVERLAY_DIR)


## Where our own .info files live, laid over the vendored set.
const OVERLAY_DIR := "res://libretro-core-info-retroxr"


## Load .info files that REPLACE the vendored entry of the same core_name.
##
## A separate directory rather than edits in place: res://libretro-core-info is
## vendored wholesale from libretro's repository, so anything written there is
## lost the next time it is refreshed, silently and without a conflict to notice.
## A core we ship our own build of usually needs its own description too — ours
## describes the fork, not the upstream core — and this is where that goes.
##
## Missing directory is not an error; there simply is no overlay.
func load_overlay(info_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(info_dir):
		return
	var overlay := CoreInfoParser.parse_all(info_dir)
	if overlay.is_empty():
		return
	var by_name: Dictionary = {}
	for entry: Dictionary in overlay:
		by_name[entry.get("core_name", "")] = entry
	var merged: Array[Dictionary] = []
	for entry: Dictionary in cores:
		var cn: String = entry.get("core_name", "")
		if by_name.has(cn):
			merged.append(by_name[cn])
			by_name.erase(cn)
		else:
			merged.append(entry)
	# Anything left described a core the vendored set does not carry at all.
	for entry: Variant in by_name.values():
		merged.append(entry as Dictionary)
	cores = merged
	_rebuild_indices()
	print("[CoreInfoDatabase] Applied %d retroXR core-info overrides" % overlay.size())


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Return the entry for a core by its core_name stem (e.g. "fceumm").
## Returns an empty Dictionary if not found.
func get_by_core_name(core_name: String) -> Dictionary:
	return _by_core_name.get(core_name, {})


## Return all entries whose systemid matches (e.g. "nes").
## Returns an empty array if no entries match.
func get_by_systemid(systemid: String) -> Array[Dictionary]:
	if _by_systemid.has(systemid):
		var result: Array[Dictionary] = []
		result.assign(_by_systemid[systemid])
		return result
	if _mod_systems.has(systemid):
		var core := get_by_core_name(str((_mod_systems[systemid] as Dictionary)["core_name"]))
		if not core.is_empty():
			var one: Array[Dictionary] = [core]
			return one
	return []


## Return sorted list of all distinct systemid strings present in the database.
func get_unique_systemids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _by_systemid.keys():
		if key != "":
			ids.append(key)
	ids.sort()
	return ids


## True when no core claims this systemid as its own and it exists only because
## one or more cores named it in `secondary_systemids`.
##
## A platform a mod added counts: it too is named by SystemInfo (the mod's own
## descriptor), not by the core it rides on.
func is_secondary_systemid(systemid: String) -> bool:
	if _primary_ids.has(systemid):
		return false
	return _secondary_exts.has(systemid) or _mod_systems.has(systemid)


## Labels that beat every core's own `systemname`. The Game Boy, WonderSwan and
## Neo Geo Pocket cores name both models ("Game Boy/Game Boy Color"), which was
## right while one tile held both; each Color has a tile of its own now, named
## by SystemInfo.
const SYSTEM_LABELS := {
	"gb": "Game Boy",
	"ngp": "Neo Geo Pocket",
	"wonderswan": "WonderSwan",
	# Every PS2 core's .info says "Sony PlayStation 2"; the PlayStation's tile
	# has no maker in it, so neither does this one.
	"ps2": "PlayStation 2",
	# Five systemids used to be named "Arcade (various)" by whichever core was
	# indexed first (and "CP System I" when that was a CPS-only build). One is
	# Arcade now; the two that are not MAME/FinalBurn romsets say what they are.
	"arcade": "Arcade",
	"daphne": "Arcade (Daphne)",
	"dice": "Arcade (DICE)",
}


## Return the human-readable systemname for a given systemid.
## Uses the first matching entry. Returns the systemid itself if not found.
##
## A secondary-only platform is named by SystemInfo, not by its cores: every
## entry indexed under it belongs to the parent machine, so Game Gear would
## otherwise be labelled "Sega 8/16-bit (Various)".
func get_systemname_for_id(systemid: String) -> String:
	return RegionalNames.name_for(systemid, RegionalNames.effective_region(), _base_systemname(systemid))


func _base_systemname(systemid: String) -> String:
	if SYSTEM_LABELS.has(systemid):
		return SYSTEM_LABELS[systemid]
	if is_secondary_systemid(systemid):
		var info := SystemInfo.for_system(systemid)
		return info.display_name if info != null and not info.display_name.is_empty() \
			else systemid

	# Only a core whose OWN systemid this is may name it. A secondary can be
	# indexed first and is usually a multi-system core, so Super NES took
	# mesen2's "Nintendo Entertainment System / Super Nintendo Entertainment
	# System / Game Boy / ..." the moment mesen2 declared it.
	for entry: Dictionary in get_by_systemid(systemid):
		if str(entry.get("systemid", "")) == systemid:
			return entry.get("systemname", systemid)
	return systemid


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

## Print a summary to the Godot Output panel. Useful during development.
func debug_print_summary() -> void:
	print("=== CoreInfoDatabase Summary ===")
	print("  Total cores : %d" % cores.size())
	print("  Unique systemids: %d" % get_unique_systemids().size())
	print("")
	print("  Sample entry (fceumm):")
	var sample := get_by_core_name("fceumm")
	if not sample.is_empty():
		for k: String in ["core_name","display_name","systemname","systemid","license","description"]:
			print("    %-25s = %s" % [k, sample.get(k, "<missing>")])
	else:
		print("    (not found)")
	print("")
	print("  Systems with 3+ cores:")
	for sid: String in get_unique_systemids():
		var entries := get_by_systemid(sid)
		if entries.size() >= 3:
			print("    %-30s (%d cores)  systemname='%s'" % [
				sid,
				entries.size(),
				get_systemname_for_id(sid)
			])
	print("================================")


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _rebuild_indices() -> void:
	_by_core_name.clear()
	_by_systemid.clear()
	_secondary_exts.clear()
	_primary_ids.clear()

	for entry: Dictionary in cores:
		var cn: String = entry.get("core_name", "")
		if cn != "":
			_by_core_name[cn] = entry

		var sid: String = entry.get("systemid", "")
		if sid != "":
			_primary_ids[sid] = true
			_index_under(sid, entry)

		# The other platforms this core covers, each with the subset of its
		# extensions that belongs to that platform. A core is queryable under
		# every one of them.
		for sub: Dictionary in parse_secondary_systemids(
				str(entry.get("secondary_systemids", ""))):
			var sub_id: String = sub["id"]
			_index_under(sub_id, entry)
			if not _secondary_exts.has(sub_id):
				_secondary_exts[sub_id] = [] as Array[String]
			var list: Array[String] = _secondary_exts[sub_id]
			for ext: String in sub["exts"]:
				if ext not in list:
					list.append(ext)


func _index_under(systemid: String, entry: Dictionary) -> void:
	if not _by_systemid.has(systemid):
		_by_systemid[systemid] = []
	var bucket: Array = _by_systemid[systemid]
	if entry not in bucket:
		bucket.append(entry)
