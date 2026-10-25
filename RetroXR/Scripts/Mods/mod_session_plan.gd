## ModSessionPlan — what a player refused by a host for its mods can do about it.
##
## A host refuses a peer whose running mods are not exactly its own (the netplay
## handshake compares id@version lists), and since protocol 13 it sends the
## refused peer its list. Everything else is worked out HERE, on the joiner, from
## that list, the joiner's own mods and what mod.io says -- nothing touches the
## network or the disk, so the decisions can be tested without either.
##
## Packs are never sent between players: a pack handed from one player to another
## has been through neither mod.io's scan nor this game's moderation. So each
## difference is one of:
##   get           the host's version is on mod.io: download it (scan, review,
##                 as the MODS tab does any download)
##   host_update   mod.io has a NEWER version than the host's: a download would
##                 still not match, so the host updates (or both do)
##   not_on_modio  the host's version is newer than mod.io's, or mod.io no longer
##                 has the mod at all
##   by_hand       the host installed it by hand, with no mod.io page to fetch
##   switch_on     installed here at the host's version, but not running
##   switch_off    running here, and not on the host
class_name ModSessionPlan
extends RefCounted

const GET := "get"
const HOST_UPDATE := "host_update"
const NOT_ON_MODIO := "not_on_modio"
const BY_HAND := "by_hand"
const SWITCH_ON := "switch_on"
const SWITCH_OFF := "switch_off"


## One row per difference, host's mods first in its order, then the joiner's
## extras.
##   host    the host's running mods: [{id, version, name, modio_id}]
##   local   every mod installed here: [{id, version, name, loaded, modio_id}]
##   modio   modio_id -> mod.io's current file version ("" when mod.io keeps none),
##           for the ids mod.io answered for
##   asked   whether mod.io has been asked: until it has, a mod with a mod.io id
##           is a `get` with `checking` set, as a row cannot say more yet
## A row: {id, name, kind, host_version, local_version, modio_id, modio_version,
## checking}.
static func rows(host: Array, local: Array, modio: Dictionary = {}, asked := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mine := {}
	for entry: Variant in local:
		if entry is Dictionary:
			mine[str((entry as Dictionary).get("id", ""))] = entry
	var theirs := {}
	for entry: Variant in host:
		if not entry is Dictionary:
			continue
		var h := entry as Dictionary
		var id := str(h.get("id", ""))
		if id.is_empty():
			continue
		theirs[id] = true
		var want := str(h.get("version", ""))
		var l: Dictionary = mine.get(id, {})
		var have := str(l.get("version", ""))
		if not l.is_empty() and have == want:
			if bool(l.get("loaded", false)):
				continue
			out.append(_row(h, l, SWITCH_ON))
			continue
		var modio_id := int(h.get("modio_id", 0))
		if modio_id <= 0:
			out.append(_row(h, l, BY_HAND))
			continue
		if not asked:
			var pending := _row(h, l, GET)
			pending["checking"] = true
			out.append(pending)
			continue
		if not modio.has(modio_id):
			out.append(_row(h, l, NOT_ON_MODIO))
			continue
		var on_modio := str(modio[modio_id])
		var row: Dictionary
		if on_modio.is_empty() or on_modio == want:
			# An upload that states no version cannot be checked before it comes
			# down; the review shows what arrived.
			row = _row(h, l, GET)
		elif ModManifest.version_at_least(on_modio, want):
			row = _row(h, l, HOST_UPDATE)
		else:
			row = _row(h, l, NOT_ON_MODIO)
		row["modio_version"] = on_modio
		out.append(row)
	for entry: Variant in local:
		if not entry is Dictionary:
			continue
		var l := entry as Dictionary
		var id := str(l.get("id", ""))
		if bool(l.get("loaded", false)) and not theirs.has(id):
			out.append(_row({}, l, SWITCH_OFF))
	return out


static func _row(h: Dictionary, l: Dictionary, kind: String) -> Dictionary:
	var name := str(h.get("name", ""))
	if name.is_empty():
		name = str(l.get("name", ""))
	var id := str(h.get("id", l.get("id", "")))
	return {
		"id": id,
		"name": name if not name.is_empty() else id,
		"kind": kind,
		"host_version": str(h.get("version", "")),
		"local_version": str(l.get("version", "")),
		"modio_id": int(h.get("modio_id", 0)),
		"modio_version": "",
		"checking": false,
	}


## The mod.io ids of the rows a Get can fetch: `get` rows, checked or not.
static func fetchable(plan: Array) -> Array[int]:
	var out: Array[int] = []
	for row: Dictionary in plan:
		if row["kind"] == GET and int(row["modio_id"]) > 0 and not out.has(int(row["modio_id"])):
			out.append(int(row["modio_id"]))
	return out


## Whether every difference is one the joiner can settle on its own (get,
## switch_on, switch_off) -- otherwise the host has to change something too.
static func joiner_can_fix(plan: Array) -> bool:
	for row: Dictionary in plan:
		if row["kind"] in [HOST_UPDATE, NOT_ON_MODIO, BY_HAND]:
			return false
	return true


## The order the panel shows kinds in: what the joiner fetches or switches on
## first, then what is the host's to change, then the joiner's extras -- which,
## for a player with a large collection, can be most of the list.
const ORDER := [GET, SWITCH_ON, HOST_UPDATE, NOT_ON_MODIO, BY_HAND, SWITCH_OFF]
const TITLES := {
	GET: "On mod.io", SWITCH_ON: "Installed here, switched off",
	HOST_UPDATE: "The host needs to update", NOT_ON_MODIO: "Not on mod.io at the host's version",
	BY_HAND: "Installed by hand on the host", SWITCH_OFF: "Running here, not on the host",
}


## The plan's rows by kind, in ORDER, kinds with no rows left out:
## [[kind, rows], ...].
static func grouped(plan: Array) -> Array:
	var out: Array = []
	for kind: String in ORDER:
		var rows_of: Array[Dictionary] = []
		for row: Dictionary in plan:
			if row["kind"] == kind:
				rows_of.append(row)
		if not rows_of.is_empty():
			out.append([kind, rows_of])
	return out


## One sentence for the whole plan: "1 to get from mod.io, 83 to switch off;
## 2 are the host's to change". "" for no difference.
static func summary(plan: Array) -> String:
	var n := {}
	for row: Dictionary in plan:
		n[row["kind"]] = int(n.get(row["kind"], 0)) + 1
	var mine := PackedStringArray()
	if n.has(GET):
		mine.append("%d to get from mod.io" % n[GET])
	var switch := int(n.get(SWITCH_ON, 0)) + int(n.get(SWITCH_OFF, 0))
	if switch > 0:
		mine.append("%d to switch %s" % [switch, "on" if not n.has(SWITCH_OFF)
			else ("off" if not n.has(SWITCH_ON) else "on or off")])
	var theirs := int(n.get(HOST_UPDATE, 0)) + int(n.get(NOT_ON_MODIO, 0)) + int(n.get(BY_HAND, 0))
	var out := ", ".join(mine)
	if theirs > 0:
		var tail := "%d %s the host's to change" % [theirs, "is" if theirs == 1 else "are"]
		out = tail if out.is_empty() else "%s; %s" % [out, tail]
	return out


## The line a row's player reads, without its action.
static func describe(row: Dictionary) -> String:
	var name := str(row["name"])
	var want := str(row["host_version"])
	var have := str(row["local_version"])
	match str(row["kind"]):
		GET:
			if bool(row.get("checking", false)):
				return "%s %s -- on mod.io, checking its version" % [name, want]
			if have.is_empty():
				return "%s %s -- missing; on mod.io" % [name, want]
			return "%s -- you have %s, the host %s; on mod.io" % [name, have, want]
		HOST_UPDATE:
			return "%s -- the host runs %s, mod.io has %s: the host needs to update" % [
				name, want, str(row["modio_version"])]
		NOT_ON_MODIO:
			if str(row["modio_version"]).is_empty():
				return "%s %s -- no longer on mod.io" % [name, want]
			return "%s -- the host runs %s, newer than mod.io's %s" % [
				name, want, str(row["modio_version"])]
		BY_HAND:
			return "%s %s -- the host installed it by hand; it has no mod.io page" % [name, want]
		SWITCH_ON:
			return "%s %s -- installed here, switched off" % [name, want]
		SWITCH_OFF:
			return "%s %s -- running here, not on the host" % [name, have]
	return name
