## GameSearch — the two searches of the Games tab that look past one system.
##
## 1. System aliases: a tile answers to its RetroXR folder names and to every
##    RomM slug that maps onto it, so "gba" finds Game Boy Advance. The tile still
##    shows the system's proper name.
## 2. Global game search: one query across every system's local ROM folders and
##    every synced RomM index. `search_all` is pure file reading with nothing
##    shared, so it runs on a worker; the caller resolves every main-thread-only
##    fact (folders, extensions, cached paths) into the jobs first.
class_name GameSearch
extends RefCounted

## The pseudo-system id the browser opens for the results page. Never a real
## systemid: the `__` prefix is what keeps it out of the hide/unhide button.
const PAGE_ID := "__search__"
## Rows the results page shows. A one-letter query would otherwise build
## thousands of buttons; the page says when it stopped.
const RESULT_LIMIT := 200
## Per-system share of the RomM index search, so one huge platform cannot eat the
## whole page before the others are read.
const PER_SYSTEM_LIMIT := 60
## Shortest query that searches. One letter matches half the library.
const MIN_QUERY := 2

static var _slugs_by_system: Dictionary = {}


## Every name a system answers to, lowercase: its systemid, its folder names, the
## RomM slugs that map onto it, and the slug/fs_slug of the platform the server
## actually holds for it (a user override can point a slug nobody mapped).
static func system_aliases(systemid: String, romm_platform: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	_add_alias(out, systemid)
	for folder: String in SystemIds.folder_names(systemid):
		_add_alias(out, folder)
	if _slugs_by_system.is_empty():
		for slug: String in RommPlatforms.SLUG_MAP:
			var sid := str(RommPlatforms.SLUG_MAP[slug])
			if not _slugs_by_system.has(sid):
				_slugs_by_system[sid] = []
			(_slugs_by_system[sid] as Array).append(slug)
	for slug: String in _slugs_by_system.get(systemid, []):
		_add_alias(out, slug)
	for name: String in RegionalNames.search_aliases(systemid):
		_add_alias(out, name)
	for key: String in ["slug", "fs_slug"]:
		var v: Variant = romm_platform.get(key)
		if v != null:
			_add_alias(out, str(v))
	return out


static func _add_alias(out: PackedStringArray, alias: String) -> void:
	var a := alias.strip_edges().to_lower()
	if not a.is_empty() and not out.has(a):
		out.append(a)


## Does a tile with this display name and these aliases answer to `needle`?
## `needle` is already stripped and lowercased.
static func system_matches(needle: String, display_name: String,
		aliases: PackedStringArray) -> bool:
	if needle.is_empty() or display_name.to_lower().contains(needle):
		return true
	for a: String in aliases:
		if a.contains(needle):
			return true
	return false


## Search every job's local folder and RomM index for `term`.
##
## A job is {systemid, name, index_dir, local_dirs, exts, folders, cached}:
## `cached` is rom_id -> local path for what the RomM cache holds. Returns
## {rows, truncated}; a row is {systemid, system_name, label, path, source
## ("both" / "server" / "local"), rom_id, entry, regions}. Safe on a worker.
static func search_all(jobs: Array, term: String, limit: int = RESULT_LIMIT) -> Dictionary:
	var rows: Array[Dictionary] = []
	var needle := SearchFold.fold(term.strip_edges())
	if needle.length() < MIN_QUERY:
		return {"rows": rows, "truncated": false}

	for job: Dictionary in jobs:
		rows.append_array(_search_system(job, needle))

	sort_rows(rows, term)
	var truncated := rows.size() > limit
	if truncated:
		rows.resize(limit)
	return {"rows": rows, "truncated": truncated}


## Games whose name STARTS with the query first (the one being typed), then
## alphabetical, then by system. The one order for the page: the server's rows
## merged in later go through here too, or its answer reshuffles the list.
static func sort_rows(rows: Array[Dictionary], term: String) -> void:
	var needle := SearchFold.fold(term.strip_edges())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := SearchFold.fold(str(a["label"])).begins_with(needle)
		var pb := SearchFold.fold(str(b["label"])).begins_with(needle)
		if pa != pb:
			return pa
		var c := str(a["label"]).naturalnocasecmp_to(str(b["label"]))
		if c != 0:
			return c < 0
		return str(a["system_name"]) < str(b["system_name"])
	)


static func _search_system(job: Dictionary, needle: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sid := str(job.get("systemid", ""))
	var sname := str(job.get("name", sid))
	var local := _scan_local(job, needle)
	var cached: Dictionary = job.get("cached", {})
	var matched: Dictionary = {}

	var dir := str(job.get("index_dir", ""))
	if not dir.is_empty():
		for hit: Dictionary in RommCatalog.search_dir(dir, needle, PER_SYSTEM_LIMIT):
			var key := str(hit["fs_base"])
			var path := str(cached.get(int(hit["rom_id"]), ""))
			if path.is_empty() and local.has(key):
				path = str((local[key] as Dictionary)["path"])
			if not path.is_empty():
				matched[key] = true
			out.append({
				"systemid": sid, "system_name": sname, "label": hit["label"],
				"path": path, "source": "both" if not path.is_empty() else "server",
				"rom_id": hit["rom_id"], "entry": hit["entry"], "regions": hit["regions"],
			})

	for key: String in local:
		if matched.has(key):
			continue
		var rom: Dictionary = local[key]
		out.append({
			"systemid": sid, "system_name": sname, "label": rom["label"],
			"path": rom["path"], "source": "local", "rom_id": 0, "entry": {},
			"regions": PackedStringArray(),
		})
	return out


## Local games whose file name contains the query, keyed by lowercase stem so a
## .cue and its .bin are one game. A folder-content system (ScummVM) also counts
## each subfolder holding a file a core loads.
static func _scan_local(job: Dictionary, needle: String) -> Dictionary:
	var by_stem: Dictionary = {}
	var exts: Array = job.get("exts", [])
	if exts.is_empty():
		return by_stem
	var folders := bool(job.get("folders", false))
	for dir_path: String in job.get("local_dirs", PackedStringArray()):
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not f.begins_with("."):
				var is_dir := dir.current_is_dir()
				var stem := f if is_dir else f.get_basename()
				if (is_dir and folders) or (not is_dir and f.get_extension().to_lower() in exts):
					if SearchFold.fold(stem).contains(needle):
						var key := stem.to_lower()
						# A descriptor outranks its data file, the way the system
						# page's own scan prefers a .cue to its .bin.
						if not by_stem.has(key) or f.get_extension().to_lower() in ["cue", "m3u", "gdi", "ccd"]:
							by_stem[key] = {"label": stem, "path": dir_path.path_join(f)}
			f = dir.get_next()
		dir.list_dir_end()
	return by_stem
