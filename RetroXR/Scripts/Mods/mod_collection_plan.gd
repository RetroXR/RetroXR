## ModCollectionPlan — what installing or removing a mod pack comes to.
##
## A pack is a mod.io collection: a named list of mods. Nothing here touches the
## network or the disk. It is handed what mod.io said and what is installed and
## answers with a plan, so the decisions can be tested without either.
##
## A mod's `source` (ModManager.source) is where the bookkeeping lives:
##   modio_id     mod.io's id for the mod
##   file_id      the file that is installed
##   collections  ids of the packs that brought it in
##   individual   true when the player also installed it on its own
class_name ModCollectionPlan
extends RefCounted


## Sort a pack's members into what to fetch, what is already here and what
## cannot be installed, with the reason.
##   members    parsed mods (ModioClient.parse_mod), in the pack's order
##   installed  modio_id -> file_id of every mod.io mod on this device
## Returns {fetch: Array[Dictionary], have: Array[Dictionary],
##          skip: Array of {name, why}}.
static func plan_install(members: Array, installed: Dictionary) -> Dictionary:
	var fetch: Array[Dictionary] = []
	var have: Array[Dictionary] = []
	var skip: Array[Dictionary] = []
	var seen := {}
	for entry: Variant in members:
		var mod := entry as Dictionary
		var mod_id := int(mod.get("id", 0))
		if mod_id <= 0 or seen.has(mod_id):
			continue
		seen[mod_id] = true
		var file_id := int(mod.get("file_id", 0))
		if file_id <= 0 or str(mod.get("download_url", "")).is_empty():
			skip.append({"name": str(mod.get("name", "")), "why": "has no file to download yet"})
			continue
		if installed.has(mod_id) and int(installed[mod_id]) == file_id:
			have.append(mod)
			continue
		var scan := ModioClient.scan_problem(mod)
		if not scan.is_empty():
			skip.append({"name": str(mod.get("name", "")), "why": scan})
			continue
		fetch.append(mod)
	return {"fetch": fetch, "have": have, "skip": skip}


## Files more than one mod wants to replace.
##   claims  name -> the shipped paths that mod replaces (its shadowing claims):
##           the pack's members, and the mods already installed
## Returns one sentence per contested path, sorted, so the list reads the same
## every time.
static func conflicts(claims: Dictionary) -> PackedStringArray:
	var by_path := {}
	for name: Variant in claims:
		for path: Variant in (claims[name] as Array):
			if not by_path.has(path):
				by_path[path] = []
			if not (by_path[path] as Array).has(str(name)):
				(by_path[path] as Array).append(str(name))
	var out := PackedStringArray()
	var paths := by_path.keys()
	paths.sort()
	for path: Variant in paths:
		var names: Array = by_path[path]
		if names.size() > 1:
			names.sort()
			out.append("%s both replace %s" % [" and ".join(PackedStringArray(names)), str(path)])
	return out


## A member's source once pack `collection_id` has installed it, given what was
## kept about it before ({} for a mod that was not here).
static func source_after_install(before: Dictionary, mod_id: int, file_id: int,
		profile_url: String, collection_id: int) -> Dictionary:
	var out := before.duplicate(true)
	# A mod that was here with no pack to its name was installed on its own, and
	# stays wanted on its own whatever happens to this pack.
	if not before.is_empty() and collections_of(before).is_empty():
		out["individual"] = true
	out["modio_id"] = mod_id
	out["file_id"] = file_id
	out["profile_url"] = profile_url
	var packs := collections_of(before)
	if not packs.has(collection_id):
		packs.append(collection_id)
	out["collections"] = packs
	return out


## The same for a mod installed on its own from the Browse page.
static func source_after_single(before: Dictionary, mod_id: int, file_id: int,
		profile_url: String) -> Dictionary:
	var out := before.duplicate(true)
	out["modio_id"] = mod_id
	out["file_id"] = file_id
	out["profile_url"] = profile_url
	out["individual"] = true
	return out


## What removing pack `collection_id` does to each installed mod.
##   sources  mod id -> source, for every installed mod
## Returns {remove: Array[String], keep: Dictionary of id -> its new source}.
## A mod is removed only when this pack was the last thing that wanted it.
static func plan_remove(collection_id: int, sources: Dictionary) -> Dictionary:
	var remove: Array[String] = []
	var keep := {}
	var ids := sources.keys()
	ids.sort()
	for id: Variant in ids:
		var source := sources[id] as Dictionary
		var packs := collections_of(source)
		if not packs.has(collection_id):
			continue
		packs.erase(collection_id)
		if packs.is_empty() and not is_individual(source):
			remove.append(str(id))
		else:
			var after := source.duplicate(true)
			after["collections"] = packs
			keep[str(id)] = after
	return {"remove": remove, "keep": keep}


## Where a pack stands on this device, from its members and what is installed:
##   ""          none of it is here
##   "partial"   some members are here
##   "update"    all that can be are here, and mod.io offers a newer file for one
##   "installed" every member that can be installed is, at mod.io's file
static func pack_state(members: Array, installed: Dictionary) -> String:
	var plan := plan_install(members, installed)
	var have := (plan["have"] as Array).size()
	var stale := 0
	var missing := 0
	for entry: Variant in (plan["fetch"] as Array):
		if installed.has(int((entry as Dictionary).get("id", 0))):
			stale += 1
		else:
			missing += 1
	if have + stale == 0:
		return ""
	if missing > 0:
		return "partial"
	return "update" if stale > 0 else "installed"


static func state_text(state: String) -> String:
	match state:
		"partial":   return "Partly installed"
		"update":    return "Update available"
		"installed": return "Installed"
	return ""


static func collections_of(source: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = source.get("collections", [])
	if raw is Array:
		for v: Variant in (raw as Array):
			# JSON hands every number back as a float.
			if (v is int or v is float) and not out.has(int(v)):
				out.append(int(v))
	return out


static func is_individual(source: Dictionary) -> bool:
	return source.get("individual") is bool and bool(source["individual"])
