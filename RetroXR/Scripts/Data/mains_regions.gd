## MainsRegions — which wall outlet the room has, by the player's region.
##
## A wall outlet is not one object the world over: a US duplex takes a US plug and
## nothing else, a Schuko takes a Schuko or a Europlug, and so on. The player picks
## their region on the OPTIONS tab (AppPrefs.mains_region), every WallOutlet and
## PowerStrip in the room shows that region's receptacles, and a plug goes into one
## only when it would on the hardware -- Connectors.ALSO_FITS says which.
##
## Each region names its plate mesh and its sockets. Sockets are always TopPort and
## BottomPort, in that order, whatever the plate's layout: a save names a seated
## plug's socket by node name, so a cord left in the wall comes back in the same
## receptacle after the region changes, if it still fits there.
##
## A shipped const table, with `extra` as the overlay a mod adds regions to.
class_name MainsRegions
extends RefCounted

## The region a fresh install starts with when the locale names none we know.
const DEFAULT := "na"

const REGIONS := {
	"na": {
		"label": "North America",
		"types": "Type A/B",
		"mesh": "res://Scenes/Objects/room/wall_outlet_duplex.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.022, 0.0086),
				"connector": "nema_5_15_plug"},
			{"name": "BottomPort", "position": Vector3(0, -0.022, 0.0086),
				"connector": "nema_5_15_plug"},
		],
		# Spawn tokens of the game's cords whose wall plug this outlet takes,
		# listed first on the menu's Power tab.
		"cords": ["power_cord", "nema_1_15_to_c7_cord",
			"nema_1_15_polarized_to_c7_polarized_cord", "power_strip"],
		# The power strip as sold here: what its sockets take, and its own plug.
		"strip": {"socket": "nema_5_15_plug", "plug": "nema_5_15_plug",
			"plug_mesh": "res://Scenes/Objects/cables/nema_5_15_plug_ivory.res"},
	},
}

## Country code (from OS.get_locale()) -> region, for the first-run default.
const COUNTRIES := {
	"US": "na", "CA": "na", "MX": "na", "TW": "na", "PH": "na", "TH": "na",
}

## Language -> region, for a locale that names no country.
const LANGUAGES := {
	"en": "na",
}

## Regions a mod adds, keyed like REGIONS. Merged over the shipped table.
static var extra := {}


## Every region id, shipped first, in table order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in REGIONS:
		out.append(id)
	for id: String in extra:
		if not out.has(id):
			out.append(id)
	return out


static func has(id: String) -> bool:
	return extra.has(id) or REGIONS.has(id)


## `id` if it is a region, else DEFAULT.
static func resolve(id: String) -> String:
	return id if has(id) else DEFAULT


## The region's entry; DEFAULT's for an id that is not one.
static func of(id: String) -> Dictionary:
	var key := resolve(id)
	return (extra.get(key, REGIONS.get(key, {})) as Dictionary)


## What the OPTIONS dropdown calls a region: "North America (Type A/B)".
static func label_of(id: String) -> String:
	var spec := of(id)
	return "%s (%s)" % [spec.get("label", id), spec.get("types", "")]


## The region for a locale such as "en_GB" or "ja", or DEFAULT.
static func for_locale(locale: String) -> String:
	var parts := locale.replace("-", "_").split("_")
	if parts.size() > 1:
		var region := str(COUNTRIES.get(parts[1].to_upper(), ""))
		if has(region):
			return region
	var by_language := str(LANGUAGES.get(parts[0].to_lower(), ""))
	return by_language if has(by_language) else DEFAULT


## Whether a plug of `connector` goes into a socket of `socket_connector`.
static func fits(connector: String, socket_connector: String) -> bool:
	return Connectors.groups_of(connector).has(socket_connector)
