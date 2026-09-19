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
	return ids


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
func is_secondary_systemid(systemid: String) -> bool:
	return _secondary_exts.has(systemid) and not _primary_ids.has(systemid)


## Return the human-readable systemname for a given systemid.
## Uses the first matching entry. Returns the systemid itself if not found.
##
## A secondary-only platform is named by SystemInfo, not by its cores: every
## entry indexed under it belongs to the parent machine, so Game Gear would
## otherwise be labelled "Sega 8/16-bit (Various)".
func get_systemname_for_id(systemid: String) -> String:
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
