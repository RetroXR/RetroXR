## PowerSpawnRows — the Power tab's rows that come in one model per outlet region:
## a power cord of each kind and every AC adapter (docs/dev/power.md).
##
## A row is {key, label, variants}, each variant {id, label, region, token}: the token
## is what the spawn menu emits for it, the region whose outlet glyph stands for it.
## A plain press spawns the row's default, which is the player's MAKE DEFAULT pick if
## the row still lists it, else the one for the Options outlet region (region_default);
## a long press asks which.
##
## Cords are grouped by their APPLIANCE end -- a C13 kettle lead, a C7 figure-eight --
## and a region's variant is the cord its own `cords` list names (MainsRegions). A
## region with no cord of a kind gets the first one whose wall plug fits its outlet.
class_name PowerSpawnRows
extends RefCounted

## The two cord kinds, by appliance end. The polarized C7P cord is one of the C7 row.
const CORD_KINDS := [
	{"key": "cord_c13", "label": "Power Cord (C13)", "ends": ["iec_c13_plug"]},
	{"key": "cord_c7", "label": "Figure-8 Power Cord (C7)",
		"ends": ["iec_c7_plug", "iec_c7_polarized_plug"]},
]

## The appliance end and the wall plug of every cord the game ships, by token. The
## three US scenes carry no "plug" in MainsRegions.CORDS, so their plugs are here.
const _US_PLUGS := {
	"power_cord": "nema_5_15_plug",
	"nema_1_15_to_c7_cord": "nema_1_15_plug",
	"nema_1_15_polarized_to_c7_polarized_cord": "nema_1_15_polarized_plug",
}


## The cord token's appliance end: C7 for an ungrounded or figure-eight cord, C7P for
## the polarized one, else C13.
static func cord_end(token: String) -> String:
	if token == "nema_1_15_polarized_to_c7_polarized_cord":
		return "iec_c7_polarized_plug"
	if token == "nema_1_15_to_c7_cord":
		return "iec_c7_plug"
	var row: Dictionary = MainsRegions.CORDS.get(token, {})
	return "iec_c7_plug" if row.get("grounded", true) == false else "iec_c13_plug"


## The cord token's wall plug connector.
static func cord_plug(token: String) -> String:
	if _US_PLUGS.has(token):
		return str(_US_PLUGS[token])
	return str((MainsRegions.CORDS.get(token, {}) as Dictionary).get("plug", "nema_5_15_plug"))


## The first region that lists `token` among its cords: the one whose glyph it wears.
static func cord_region(token: String) -> String:
	for id: String in MainsRegions.ids():
		if (MainsRegions.of(id).get("cords", []) as Array).has(token):
			return id
	return MainsRegions.DEFAULT


## The cord rows: one per kind, a variant per cord of that kind, the regions' order.
static func cord_rows() -> Array:
	var out := []
	for kind: Dictionary in CORD_KINDS:
		var variants := []
		var seen := {}
		for id: String in MainsRegions.ids():
			for token: String in MainsRegions.of(id).get("cords", []):
				if seen.has(token) or not MainsRegions.CORDS.has(token) \
						or not (kind["ends"] as Array).has(cord_end(token)):
					continue
				seen[token] = true
				variants.append({"id": token, "token": token, "region": id, "plug": cord_plug(token),
					"label": str((MainsRegions.CORDS[token] as Dictionary).get("label", token))})
		# Any cord no region lists, last: an import is still a real thing to own.
		for token: String in MainsRegions.CORDS:
			if not seen.has(token) and (kind["ends"] as Array).has(cord_end(token)):
				variants.append({"id": token, "token": token, "region": cord_region(token),
					"plug": cord_plug(token),
					"label": str((MainsRegions.CORDS[token] as Dictionary).get("label", token))})
		out.append({"key": kind["key"], "label": kind["label"], "variants": variants, "cord": true})
	return out


## An adapter's row: a variant per model it comes in, each wearing its region's glyph.
static func brick_row(id: String) -> Dictionary:
	var row := PowerBrickCatalog.row(id)
	var variants := []
	for name: String in PowerBrickCatalog.variants_of(id):
		variants.append({
			"id": name,
			"token": "%s%s:%s%s" % [SpawnCatalog.AS, name, PowerBrickCatalog.PREFIX, id],
			"region": str(PowerBrickCatalog.VARIANT_REGION.get(name, MainsRegions.DEFAULT)),
			"label": str(PowerBrickCatalog.VARIANT_LABELS.get(name, name)),
			"plug": _brick_plug(id, name),
		})
	return {"key": "brick:%s" % id, "label": str(row.get("label", id)), "variants": variants,
		"brick": id}


## The wall plug a brick's model has, or "" for one with no mains plug of its own
## (an inlet brick takes a figure-eight cord; the DMG-03 is a battery pack).
static func _brick_plug(id: String, name: String) -> String:
	var form := str(PowerBrickCatalog.variant(id, name).get("form", "wall_wart"))
	if form == "inlet" or form == "battery_pack":
		return ""
	return PowerBrickCatalog.wall_plug_of(name)


## What a model's row and tile show: the flag of where it was sold and the outlet its
## plug really goes in (its type, not its region's: North America's outlet is a B,
## its adapters' plugs an A). Drawn in MenuIcons.symbols(), whose fallbacks carry both.
static func mark_of(v: Dictionary) -> String:
	var region := str(v.get("region", MainsRegions.DEFAULT))
	return "%s %s" % [MainsRegions.flag_of(region),
		String.chr(MainsRegions.plug_glyph(str(v.get("plug", "")), region))]


## "Japan, Type A plug" -- a model's words for a tooltip.
static func words_of(v: Dictionary) -> String:
	var kind := MainsRegions.plug_type(str(v.get("plug", "")))
	return "%s%s" % [str(v.get("label", "")), ", %s plug" % kind if not kind.is_empty() else ""]


## The adapter rows, in the catalog's order.
static func brick_rows() -> Array:
	var out := []
	for id: String in PowerBrickCatalog.ids():
		out.append(brick_row(id))
	return out


## The variant a plain press spawns for a player in outlet region `region`, ignoring
## any MAKE DEFAULT pick (the caller asks AppPrefs first).
static func region_default(row: Dictionary, region: String) -> Dictionary:
	var variants: Array = row.get("variants", [])
	if variants.is_empty():
		return {}
	var want := MainsRegions.resolve(region)
	if row.has("brick"):
		var name := PowerBrickCatalog.variant_for_region(str(row["brick"]), want)
		for v: Dictionary in variants:
			if str(v["id"]) == name:
				return v
		return variants[0]
	# The region's own cord of this kind.
	for token: String in MainsRegions.of(want).get("cords", []):
		for v: Dictionary in variants:
			if str(v["token"]) == token:
				return v
	# Else the first whose wall plug goes into this region's outlet.
	var sockets: Array = MainsRegions.of(want).get("sockets", [])
	var socket := str((sockets[0] as Dictionary).get("connector", "")) if not sockets.is_empty() else ""
	for v: Dictionary in variants:
		if Connectors.groups_of(cord_plug(str(v["token"]))).has(socket):
			return v
	return variants[0]


## The variant a plain press spawns: `kept` (a MAKE DEFAULT pick, a variant id) while
## the row lists it, else region_default.
static func default_of(row: Dictionary, kept: String, region: String) -> Dictionary:
	if not kept.is_empty():
		for v: Dictionary in row.get("variants", []):
			if str(v["id"]) == kept:
				return v
	return region_default(row, region)
