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

## Each region: what the dropdown calls it, its plate mesh (Tools/gen/
## gen_wall_outlet.gd bakes one per region from this table), its two receptacles
## -- where the seated plug's origin goes, turned by "rotation", and the socket
## connector, whose holes are MainsSpecs.SOCKETS' -- the cords whose wall plug
## fits it, listed first on the Power tab, and the power strip sold there: its
## sockets and plug, and the "deck" its sockets stand in on top of the US body,
## "height" mm tall with the sockets "port" mm up it, using "every" other one
## where the region's plugs are too wide for the strip's 36 mm pitch.
##
## Positions are metres on the plate, +X across the wall, +Y up, +Z out of it. A
## flush receptacle's face is at its z; a recessed one's well runs from the plate
## face down to it.
const REGIONS := {
	"na": {
		"label": "North America",
		"glyph": 0xF07E9,  # md-power_socket_us
		"types": "Type A/B",
		"mesh": "res://Scenes/Objects/room/wall_outlet_duplex.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.0212, 0.0086),
				"connector": "nema_5_15_plug"},
			{"name": "BottomPort", "position": Vector3(0, -0.0177, 0.0086),
				"connector": "nema_5_15_plug"},
		],
		"cords": ["power_cord", "nema_1_15_to_c7_cord",
			"nema_1_15_polarized_to_c7_polarized_cord", "power_strip"],
		"strip": {"socket": "nema_5_15_plug", "plug": "nema_5_15_plug",
			"plug_mesh": "res://Scenes/Objects/cables/nema_5_15_plug_ivory.res"},
	},
	"jp": {
		"label": "Japan",
		"glyph": 0xF1109,  # md-power_socket_jp
		"types": "Type A",
		"mesh": "res://Scenes/Objects/room/wall_outlet_jp.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.0188, 0.0088),
				"connector": "jis_c8303_socket"},
			{"name": "BottomPort", "position": Vector3(0, -0.0202, 0.0088),
				"connector": "jis_c8303_socket"},
		],
		"cords": ["nema_1_15_to_c7_cord", "nema_1_15_polarized_to_c7_polarized_cord",
			"power_strip"],
		"strip": {"socket": "jis_c8303_socket", "plug": "nema_1_15_plug",
			"plug_mesh": "res://Scenes/Objects/cables/nema_1_15_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_jp.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"eu": {
		"label": "Europe (Schuko)",
		"glyph": 0xF1107,  # md-power_socket_de
		"types": "Type C/F",
		"mesh": "res://Scenes/Objects/room/wall_outlet_eu.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0355, 0, 0.0045),
				"connector": "cee_7_3_socket"},
			{"name": "BottomPort", "position": Vector3(0.0355, 0, 0.0045),
				"connector": "cee_7_3_socket"},
		],
		"cords": ["cee_7_7_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "cee_7_3_socket", "plug": "cee_7_7_plug",
			"plug_mesh": "res://Scenes/Objects/cables/cee_7_7_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_eu.res",
			"height": 19.0, "port": 1.5, "every": 2},
	},
	"fr": {
		"label": "France / Belgium",
		"glyph": 0xF1108,  # md-power_socket_fr
		"types": "Type C/E",
		"mesh": "res://Scenes/Objects/room/wall_outlet_fr.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0355, 0, 0.0050),
				"connector": "cee_7_5_socket"},
			{"name": "BottomPort", "position": Vector3(0.0355, 0, 0.0050),
				"connector": "cee_7_5_socket"},
		],
		"cords": ["cee_7_7_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "cee_7_5_socket", "plug": "cee_7_7_plug",
			"plug_mesh": "res://Scenes/Objects/cables/cee_7_7_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_fr.res",
			"height": 16.5, "port": 1.5, "every": 2},
	},
	"uk": {
		"label": "UK / Ireland",
		"glyph": 0xF07E8,  # md-power_socket_uk
		"types": "Type G",
		"mesh": "res://Scenes/Objects/room/wall_outlet_uk.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0407, -0.0201, 0.0090),
				"connector": "bs_1363_plug"},
			{"name": "BottomPort", "position": Vector3(0.0407, -0.0201, 0.0090),
				"connector": "bs_1363_plug"},
		],
		"cords": ["bs_1363_cord", "bs_1363_c7_cord", "power_strip"],
		"strip": {"socket": "bs_1363_plug", "plug": "bs_1363_plug",
			"plug_mesh": "res://Scenes/Objects/cables/bs_1363_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_uk.res",
			"height": 3.0, "port": 3.0, "every": 2},
	},
	"au": {
		"label": "Australia / New Zealand",
		"glyph": 0xF0905,  # md-power_socket_au
		"types": "Type I",
		"mesh": "res://Scenes/Objects/room/wall_outlet_au.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0225, -0.0089, 0.0090),
				"connector": "as_3112_socket"},
			{"name": "BottomPort", "position": Vector3(0.0225, -0.0089, 0.0090),
				"connector": "as_3112_socket"},
		],
		"cords": ["as_3112_cord", "as_3112_c7_cord", "power_strip"],
		"strip": {"socket": "as_3112_socket", "plug": "as_3112_plug",
			"plug_mesh": "res://Scenes/Objects/cables/as_3112_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_au.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"cn": {
		"label": "China",
		"glyph": 0xF0905,  # md-power_socket_au: Type I, as there
		"types": "Type A/I",
		"mesh": "res://Scenes/Objects/room/wall_outlet_cn.res",
		"sockets": [
			# The two-slot group over the three-slot one, which is the Australian
			# socket turned upside down: earth on top.
			{"name": "TopPort", "position": Vector3(0, 0.0118, 0.0090),
				"connector": "gb_1002_2pin_socket"},
			{"name": "BottomPort", "position": Vector3(0, -0.0143, 0.0090),
				"rotation": Vector3(0, 0, 180), "connector": "as_3112_socket"},
		],
		"cords": ["as_3112_cord", "nema_1_15_to_c7_cord", "power_strip"],
		"strip": {"socket": "as_3112_socket", "plug": "as_3112_plug",
			"plug_mesh": "res://Scenes/Objects/cables/as_3112_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_cn.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"ch": {
		"label": "Switzerland",
		"glyph": 0xF0FB3,  # md-power_socket_ch
		"types": "Type C/J",
		"mesh": "res://Scenes/Objects/room/wall_outlet_ch.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0200, 0.0010, 0.0030),
				"connector": "sev_1011_socket"},
			{"name": "BottomPort", "position": Vector3(0.0200, 0.0010, 0.0030),
				"connector": "sev_1011_socket"},
		],
		"cords": ["sev_1011_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "sev_1011_socket", "plug": "sev_1011_plug",
			"plug_mesh": "res://Scenes/Objects/cables/sev_1011_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_ch.res",
			"height": 14.5, "port": 1.5, "every": 1},
	},
	"it": {
		"label": "Italy",
		"glyph": 0xF14FF,  # md-power_socket_it
		"types": "Type C/L",
		"mesh": "res://Scenes/Objects/room/wall_outlet_it.res",
		"sockets": [
			# Italian modules stand upright: the three holes run up and down.
			{"name": "TopPort", "position": Vector3(-0.0225, 0, 0.0090),
				"rotation": Vector3(0, 0, 90), "connector": "cei_23_50_socket"},
			{"name": "BottomPort", "position": Vector3(0.0225, 0, 0.0090),
				"rotation": Vector3(0, 0, 90), "connector": "cei_23_50_socket"},
		],
		"cords": ["cei_23_50_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "cei_23_50_socket", "plug": "cei_23_50_plug",
			"plug_mesh": "res://Scenes/Objects/cables/cei_23_50_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_it.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"dk": {
		"label": "Denmark",
		"glyph": 0xF0427,  # md-power_socket: the set has no Type K
		"types": "Type C/K",
		"mesh": "res://Scenes/Objects/room/wall_outlet_dk.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0250, 0.0045, 0.0090),
				"connector": "ds_k_socket"},
			{"name": "BottomPort", "position": Vector3(0.0250, 0.0045, 0.0090),
				"connector": "ds_k_socket"},
		],
		"cords": ["ds_k_cord", "europlug_c7_cord", "cee_7_7_cord", "power_strip"],
		"strip": {"socket": "ds_k_socket", "plug": "ds_k_plug",
			"plug_mesh": "res://Scenes/Objects/cables/ds_k_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_dk.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"za": {
		"label": "South Africa",
		"glyph": 0xF0427,  # md-power_socket: the set has no Type M/N
		"types": "Type C/M/N",
		"mesh": "res://Scenes/Objects/room/wall_outlet_za.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.0250, 0.0020),
				"connector": "sans_164_2_socket"},
			{"name": "BottomPort", "position": Vector3(0, -0.0390, 0.0120),
				"connector": "bs_546_plug"},
		],
		"cords": ["sans_164_2_cord", "bs_546_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "sans_164_2_socket", "plug": "sans_164_2_plug",
			"plug_mesh": "res://Scenes/Objects/cables/sans_164_2_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_za.res",
			"height": 11.5, "port": 1.5, "every": 1},
	},
	"in": {
		"label": "India",
		"glyph": 0xF0427,  # md-power_socket: the set has no Type D
		"types": "Type C/D/M",
		"mesh": "res://Scenes/Objects/room/wall_outlet_in.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0330, -0.0110, 0.0090),
				"connector": "is_1293_socket"},
			{"name": "BottomPort", "position": Vector3(0.0330, -0.0143, 0.0090),
				"connector": "bs_546_plug"},
		],
		"cords": ["is_1293_cord", "bs_546_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "is_1293_socket", "plug": "is_1293_plug",
			"plug_mesh": "res://Scenes/Objects/cables/is_1293_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_in.res",
			"height": 3.0, "port": 3.0, "every": 2},
	},
	"il": {
		"label": "Israel",
		"glyph": 0xF0427,  # md-power_socket: the set has no Type H
		"types": "Type C/H",
		"mesh": "res://Scenes/Objects/room/wall_outlet_il.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(-0.0225, 0.0045, 0.0090),
				"connector": "si_32_socket"},
			{"name": "BottomPort", "position": Vector3(0.0225, 0.0045, 0.0090),
				"connector": "si_32_socket"},
		],
		"cords": ["si_32_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "si_32_socket", "plug": "si_32_plug",
			"plug_mesh": "res://Scenes/Objects/cables/si_32_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_il.res",
			"height": 3.0, "port": 3.0, "every": 1},
	},
	"br": {
		"label": "Brazil",
		"glyph": 0xF0FB3,  # md-power_socket_ch: Type N is the Swiss J's shape
		"types": "Type C/N",
		"mesh": "res://Scenes/Objects/room/wall_outlet_br.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.0239, 0.0020),
				"connector": "nbr_14136_socket"},
			{"name": "BottomPort", "position": Vector3(0, -0.0209, 0.0020),
				"connector": "nbr_14136_socket"},
		],
		"cords": ["nbr_14136_cord", "europlug_c7_cord", "power_strip"],
		"strip": {"socket": "nbr_14136_socket", "plug": "nbr_14136_plug",
			"plug_mesh": "res://Scenes/Objects/cables/nbr_14136_plug.res",
			"deck": "res://Scenes/Objects/appliances/power_strip_deck_br.res",
			"height": 11.5, "port": 1.5, "every": 1},
	},
}

## The mains leads the game ships, by spawn token: the Power tab's rows, and what
## Tools/gen/gen_mains_cords.gd bakes. "plug" is the wall plug of a cord that
## gen_mains_cords.gd makes from the US lead ("grounded": the C13 one, else the
## two-wire C7 one); the US leads themselves name none.
const CORDS := {
	"power_cord": {"label": "NEMA 5-15P to C13 Cable"},
	"nema_1_15_to_c7_cord": {"label": "NEMA 1-15P to C7 Cable"},
	"nema_1_15_polarized_to_c7_polarized_cord": {"label": "Polarized NEMA 1-15P to C7P Cable"},
	"cee_7_7_cord": {"label": "Schuko (CEE 7/7) to C13 Cable", "plug": "cee_7_7_plug",
		"node": "SchukoCord"},
	"europlug_c7_cord": {"label": "Europlug to C7 Cable", "plug": "cee_7_16_plug",
		"grounded": false, "node": "EuroplugCord"},
	"bs_1363_cord": {"label": "UK BS 1363 to C13 Cable", "plug": "bs_1363_plug",
		"node": "Bs1363Cord"},
	"bs_1363_c7_cord": {"label": "UK BS 1363 to C7 Cable", "plug": "bs_1363_plug",
		"grounded": false, "node": "Bs1363C7Cord"},
	"as_3112_cord": {"label": "AS/NZS 3112 to C13 Cable", "plug": "as_3112_plug",
		"node": "As3112Cord"},
	"as_3112_c7_cord": {"label": "AS/NZS 3112 2-Pin to C7 Cable", "plug": "as_3112_2pin_plug",
		"grounded": false, "node": "As3112C7Cord"},
	"sev_1011_cord": {"label": "Swiss SEV 1011 to C13 Cable", "plug": "sev_1011_plug",
		"node": "Sev1011Cord"},
	"cei_23_50_cord": {"label": "Italian CEI 23-50 to C13 Cable", "plug": "cei_23_50_plug",
		"node": "Cei2350Cord"},
	"ds_k_cord": {"label": "Danish Type K to C13 Cable", "plug": "ds_k_plug",
		"node": "DanishCord"},
	"sans_164_2_cord": {"label": "SANS 164-2 to C13 Cable", "plug": "sans_164_2_plug",
		"node": "Sans1642Cord"},
	"nbr_14136_cord": {"label": "Brazilian NBR 14136 to C13 Cable", "plug": "nbr_14136_plug",
		"node": "Nbr14136Cord"},
	"bs_546_cord": {"label": "15 A Round-Pin (Type M) to C13 Cable", "plug": "bs_546_plug",
		"node": "Bs546Cord"},
	"is_1293_cord": {"label": "Indian 6 A (Type D) to C13 Cable", "plug": "is_1293_plug",
		"node": "Is1293Cord"},
	"si_32_cord": {"label": "Israeli SI 32 to C13 Cable", "plug": "si_32_plug",
		"node": "Si32Cord"},
}

## Country code (from OS.get_locale()) -> region, for the first-run default.
const COUNTRIES := {
	"US": "na", "CA": "na", "MX": "na", "TW": "na", "PH": "na", "TH": "na",
	"JP": "jp",
	"DE": "eu", "AT": "eu", "NL": "eu", "SE": "eu", "NO": "eu", "FI": "eu", "ES": "eu",
	"PT": "eu", "GR": "eu", "RU": "eu", "UA": "eu", "TR": "eu", "RO": "eu", "HU": "eu",
	"FR": "fr", "BE": "fr", "PL": "fr", "CZ": "fr", "SK": "fr",
	"GB": "uk", "IE": "uk", "MT": "uk", "CY": "uk", "HK": "uk", "SG": "uk", "MY": "uk",
	"AU": "au", "NZ": "au", "AR": "au",
	"CN": "cn",
	"CH": "ch", "LI": "ch",
	"IT": "it", "SM": "it", "VA": "it",
	"DK": "dk", "GL": "dk",
	"ZA": "za",
	"IN": "in",
	"IL": "il",
	"BR": "br",
}

## Language -> region, for a locale that names no country.
const LANGUAGES := {
	"en": "na", "ja": "jp", "de": "eu", "fr": "fr", "it": "it", "da": "dk", "zh": "cn",
	"he": "il", "pt": "br", "hi": "in",
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


## The region's outlet as a Nerd Font glyph (the symbols font, MenuIcons): its
## own power_socket where the set has one, else the plain socket.
static func glyph_of(id: String) -> int:
	return int(of(id).get("glyph", 0xF0427))


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
