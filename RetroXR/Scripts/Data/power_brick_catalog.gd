## PowerBrickCatalog — every AC adapter the game ships, as primitives sized from the
## RetroXR-models item that will replace each one (docs/dev/power.md).
##
## A row is one adapter; its `variants` are the models sold in different regions,
## keyed by RetroXR-models' own model names (usa, jpn, eur, ukv, aus, kor, asia).
## A variant is the REGION an adapter was bought in: its prongs, and for some its
## shape (the US NES-002 is a wall wart, the PAL NES-002E an in-line brick). A brick
## keeps its variant for good (it is saved); in another region's wall it goes in
## through a travel adapter, as a real one would.
##
## Row fields:
##   label      the spawn menu's row.
##   fits       systemids / model ids whose card offers it (PowerProfiles names the
##              brick too; this is the reverse lookup for the card).
##   dc_plug    the connector of its DC plug: the plug's STANDARD (Connectors), so it
##              goes into whatever takes that barrel. A variant may override it.
##   plug_mm    the DC plug's size, x y z in mm (the item's `plug` model, size_mm).
##   source     the RetroXR-models item, for the model swap (`model` once imported).
##   cord       the colour of its leads, both of them: the item's own `*_Cord` material
##              (params.py), so the rope runs on from the stub the model draws. Most are
##              black; the Wii's and the 3DS's light gray, the PSone's its blue-gray body.
##   plug_model a GLB scene for the DC plug (a mod's, override_brick), its origin the
##              face that stops against the jack, the barrel along +Z, a `CordExit` node
##              where the lead leaves. A variant may name its own.
##   variants   model name -> {form, size_mm, dc, ac?, ac_in?, dc_plug?}:
##     form       "wall_wart"  the body carries the prongs and plugs into the wall
##                "inline"     a body on the cord, its mains cord fixed
##                "inlet"      a body with a C8 inlet; a figure-eight cord feeds it
##                "dock"       the whole body is the plug (the N64's), mains cord fixed
##                "battery_pack" a charged pack, no mains side at all
##     size_mm    the body's x y z in mm (asset_stats.json size_mm).
##     dc / ac / ac_in  anchors in mm in the model's frame (asset_stats anchors_mm):
##                where the DC cord leaves, the mains cord leaves, the C8 inlet is.
##     model      a GLB scene the body wears instead of its box (a mod's,
##                override_brick), in the form's frame below; its `DCCordAnchor`,
##                `ACCordAnchor` and `ACInAnchor` nodes are where the cords and the inlet
##                go. The anchors are points: which way a cord leaves is the face of the
##                model's bounds it is on.
##     model_offset  a Transform3D the model is put at in the form's frame (the N64's
##                module, whose GLB is framed for its own build), identity if absent.
##
## Frames. A wall wart's is a wall plug's: origin on its mating face, its blades
## along +Z, the body behind (-Z). An in-line or pack body's origin is on its floor
## under its middle, long axis Z. These match the models' published anchors as far as
## the stats say; the import of each model is where they are checked against it.
class_name PowerBrickCatalog
extends RefCounted

## The spawn token of a brick: this + its id (+ "as:<variant>:" for a variant).
const PREFIX := "power_brick:"

## A model name's wall plug: the prongs that region's adapter has.
const VARIANT_PLUGS := {
	"usa": "nema_1_15_plug",
	"jpn": "nema_1_15_plug",
	"eur": "cee_7_16_plug",
	"kor": "cee_7_16_plug",
	"ukv": "bs_1363_plug",
	"asia": "bs_1363_plug",
	"aus": "as_3112_2pin_plug",
}

## Which model a mains region's shops sold. A region with none of an adapter's falls
## back to the first one the adapter lists.
const REGION_VARIANT := {
	"na": "usa", "jp": "jpn", "uk": "ukv", "au": "aus",
	"eu": "eur", "fr": "eur", "ch": "eur", "it": "eur", "dk": "eur", "za": "eur",
	"in": "eur", "il": "eur", "br": "eur", "cn": "aus",
}

## The region whose outlet glyph stands for a model name in the menu.
const VARIANT_REGION := {
	"usa": "na", "jpn": "jp", "eur": "eu", "kor": "eu", "ukv": "uk", "asia": "uk", "aus": "au",
}

const VARIANT_LABELS := {
	"usa": "North America", "jpn": "Japan", "eur": "Europe", "kor": "Korea",
	"ukv": "United Kingdom", "asia": "Asia", "aus": "Australia",
}


static func _wart(size: Array, dc: Array) -> Dictionary:
	return {"form": "wall_wart", "size_mm": size, "dc": dc}


static func _inline(size: Array, dc: Array, ac: Array) -> Dictionary:
	return {"form": "inline", "size_mm": size, "dc": dc, "ac": ac}


static func _inlet(size: Array, dc: Array, ac_in: Array) -> Dictionary:
	return {"form": "inlet", "size_mm": size, "dc": dc, "ac_in": ac_in}


static var _rows_cache := {}


## The shipped rows. A function, not a const: the variants are built with helpers.
static func _shipped() -> Dictionary:
	if not _rows_cache.is_empty():
		return _rows_cache
	var nes_pal := _inline([57.0, 50.6, 114.0], [0.0, 25.0, 57.0], [0.0, 25.0, -57.0])
	nes_pal["dc_plug"] = "barrel_5_5x2_5"
	var gc := _inline([67.0, 40.0, 153.0], [0.0, 20.0, 76.5], [0.0, 20.0, -76.5])
	var wii := _inline([55.0, 45.6, 171.0], [0.0, 14.0, 85.5], [0.0, 14.0, -85.5])
	var mk2103_us := _wart([57.0, 85.0, 69.65], [-10.0, -46.5, -34.0])
	var mk2103_eu := _wart([57.0, 93.5, 74.0], [-8.0, -53.5, -38.0])
	var wap := _wart([46.0, 77.5, 39.7], [0.0, -44.5, -11.5])
	var mgb := _wart([44.0, 71.5, 57.12], [0.0, -42.0, -20.0])
	var psone := _wart([50.0, 94.5, 43.5], [0.0, -55.5, -13.5])
	_rows_cache = {
		"nes_ac_adapter": {"label": "NES AC Adapter (NES-002)", "cord": Color8(24, 24, 26), "fits": ["nes"],
			"dc_plug": "barrel_5_5x2_1", "plug_mm": [9.6, 9.6, 38.0], "source": "nintendo/nes/psu",
			"variants": {"usa": _wart([57.0, 100.5, 81.3], [0.0, -57.0, -32.0]),
				"eur": nes_pal, "ukv": nes_pal, "aus": nes_pal}},
		# The Famicom's and the Super Famicom's: one adapter, 5.5 x 2.1.
		"hvc_ac_adapter": {"label": "Famicom AC Adapter (HVC-002)", "cord": Color8(24, 24, 26), "fits": ["famicom", "sfc", "virtualboy"],
			"dc_plug": "barrel_5_5x2_1", "plug_mm": [9.6, 9.6, 38.0], "source": "nintendo/snes/psu",
			"variants": {"jpn": _wart([57.0, 96.5, 81.6], [0.0, -55.0, -32.0])}},
		"snes_ac_adapter": {"label": "Super NES AC Adapter (SNS-002)", "cord": Color8(24, 24, 26), "fits": ["snes", "virtualboy"],
			"dc_plug": "snes_dc_plug", "plug_mm": [10.4, 10.4, 39.0], "source": "nintendo/snes/psu",
			"variants": {"usa": _wart([57.0, 96.5, 81.3], [0.0, -55.0, -32.0])}},
		# NUS-002: the whole module docks into the console's back; its mains cord is fixed.
		"n64_psu": {"label": "Nintendo 64 Power Supply (NUS-002)", "fits": ["n64"],
			"dc_plug": "n64_psu_dock", "source": "nintendo/n64/psu",
			"variants": {"usa": {"form": "dock", "size_mm": [113.64, 42.65, 73.41],
				"ac": [0.0, 21.0, -36.7]},
				"jpn": {"form": "dock", "size_mm": [113.64, 42.65, 73.41], "ac": [0.0, 21.0, -36.7]},
				"eur": {"form": "dock", "size_mm": [113.64, 42.65, 73.41], "ac": [0.0, 21.0, -36.7]},
				"ukv": {"form": "dock", "size_mm": [113.64, 42.65, 73.41], "ac": [0.0, 21.0, -36.7]}}},
		"gamecube_ac_adapter": {"label": "GameCube AC Adapter (DOL-002)", "cord": Color8(24, 24, 26), "fits": ["gc"],
			"dc_plug": "gc_dc_plug", "plug_mm": [17.8, 14.0, 56.5], "source": "nintendo/gamecube/psu",
			"variants": {"usa": gc, "jpn": gc, "eur": gc, "ukv": gc, "aus": gc}},
		"wii_ac_adapter": {"label": "Wii AC Adapter (RVL-002)", "cord": Color8(200, 200, 198), "fits": ["wii"],
			"dc_plug": "wii_dc_plug", "plug_mm": [13.1, 17.5, 53.0], "source": "nintendo/wii/psu",
			"variants": {"usa": wii, "jpn": wii, "eur": wii, "ukv": wii, "aus": wii, "kor": wii}},
		# Sega's MK-2103: the Genesis Model 2's, the 32X's, the Nomad's and the US Game Gear's.
		"sega_mk2103_adapter": {"label": "Sega AC Adapter (MK-2103)", "cord": Color8(26, 26, 28), "fits": ["genesis", "sega32x"],
			"dc_plug": "eiaj_03", "plug_mm": [9.8, 9.8, 44.0], "source": "sega/32x/psu",
			"variants": {"usa": mk2103_us, "jpn": mk2103_us, "eur": mk2103_eu, "ukv": mk2103_eu,
				"aus": mk2103_eu}},
		"jaguar_ac_adapter": {"label": "Jaguar AC Adapter (PP-912)", "cord": Color8(24, 24, 26), "fits": ["atarijaguar"],
			"dc_plug": "barrel_5_5x2_1", "plug_mm": [9.7, 9.7, 40.0], "source": "atari/jaguar/psu",
			"variants": {"usa": _wart([60.0, 81.5, 72.7], [-8.0, -46.5, -28.0])}},
		"psone_ac_adapter": {"label": "PSone AC Adapter (SCPH-113)", "cord": Color8(98, 102, 112), "fits": ["psone", "psx"],
			"dc_plug": "eiaj_03", "plug_mm": [9.5, 25.5, 22.5], "source": "sony/ps1/psu-psone",
			"variants": {"usa": psone, "jpn": psone, "eur": psone, "ukv": psone}},
		# The slim PS2's brick has a C8 inlet: a figure-eight cord feeds it.
		"ps2_slim_ac_adapter": {"label": "PS2 Slim AC Adapter (SCPH-70100)", "cord": Color8(24, 24, 26), "fits": ["ps2_slim", "ps2"],
			"dc_plug": "eiaj_03", "plug_mm": [10.6, 10.6, 45.0], "source": "sony/ps2/psu-slim",
			"variants": {"usa": _inlet([60.0, 28.8, 145.5], [0.0, 12.0, 83.5], [0.0, 12.0, -60.8])}},
		# ── the handhelds' ─────────────────────────────────────────────────────
		# DMG-03: a rechargeable pack on a cord into the Game Boy's DC IN.
		"dmg_battery_pack": {"label": "Game Boy Battery Pack (DMG-03)", "cord": Color8(24, 24, 26), "fits": ["gb"],
			"dc_plug": "dmg_dc_plug", "plug_mm": [7.6, 21.1, 20.0], "source": "nintendo/gb/psu",
			"variants": {"usa": {"form": "battery_pack", "size_mm": [60.0, 33.04, 118.5],
				"dc": [0.0, 15.0, 66.0]}}},
		"gbc_ac_adapter": {"label": "Game Boy Color AC Adapter (MGB-005)", "cord": Color8(24, 24, 26), "fits": ["gbc"],
			"dc_plug": "gbc_dc_plug", "plug_mm": [6.8, 6.8, 33.0], "source": "nintendo/gbc/psu",
			"variants": {"usa": mgb, "jpn": mgb, "eur": mgb, "aus": mgb}},
		"ags_ac_adapter": {"label": "GBA SP / DS AC Adapter (AGS-002)", "cord": Color8(24, 24, 26), "fits": ["nds"],
			"dc_plug": "ext2_plug", "plug_mm": [15.8, 10.0, 37.0], "source": "nintendo/gba/psu-sp",
			"variants": {"usa": _wart([53.0, 75.3, 41.9], [0.0, -43.4, -11.8])}},
		"wap_ac_adapter": {"label": "3DS AC Adapter (WAP-002)", "cord": Color8(206, 206, 204), "fits": ["n3ds", "nds"],
			"dc_plug": "dsi_dc_plug", "plug_mm": [10.6, 8.6, 35.5], "source": "nintendo/3ds/psu",
			"variants": {"usa": wap, "jpn": wap, "eur": wap, "ukv": wap, "aus": wap}},
		"psp_ac_adapter": {"label": "PSP AC Adapter (PSP-380)", "cord": Color8(24, 24, 26), "fits": ["psp"],
			"dc_plug": "psp_dc_plug", "plug_mm": [8.0, 23.5, 21.5], "source": "sony/psp/psu",
			"variants": {"usa": _inlet([46.0, 22.12, 74.5], [0.0, 8.0, 44.0], [0.0, 11.0, -29.7])}},
		"gamegear_ac_adapter": {"label": "Game Gear AC Adapter", "cord": Color8(26, 26, 28), "fits": ["gamegear"],
			"dc_plug": "gg_dc_plug", "plug_mm": [10.0, 10.0, 42.0], "source": "sega/game-gear/psu",
			"variants": {"jpn": mk2103_eu, "eur": mk2103_eu, "ukv": mk2103_eu, "asia": mk2103_eu}},
		"lynx_ac_adapter": {"label": "Lynx AC Adapter (PAG-1200)", "cord": Color8(24, 24, 26), "fits": ["atarilynx"],
			"dc_plug": "dmg_dc_plug", "plug_mm": [7.9, 7.9, 33.5], "source": "atari/lynx/psu",
			"variants": {"usa": _wart([57.0, 78.5, 66.8], [-6.0, -44.5, -25.0])}},
	}
	return _rows_cache


## Rows a mod adds or replaces (ModApi), over the shipped ones.
static var extra := {}

## A mod's models over a shipped adapter (ModApi.override_power_brick): id ->
## {"row": the changes, "owner": the mod's id}. Merged per variant, so a mod
## naming a model for "usa" leaves the other regions' primitives as they are.
static var _overrides := {}

## The fields a mod may change on a shipped adapter: its look, never its shape or
## what it fits (those are the hardware's, and saves and the other players rely on
## them).
const OVERRIDE_ROW_FIELDS := ["plug_model"]
const OVERRIDE_VARIANT_FIELDS := ["model", "plug_model", "model_offset"]


static func _table() -> Dictionary:
	if extra.is_empty():
		return _shipped()
	return _shipped().merged(extra, true)


static func ids() -> Array:
	return _table().keys()


static func has(id: String) -> bool:
	return _table().has(id)


static func row(id: String) -> Dictionary:
	var r: Dictionary = _table().get(id, {})
	if not _overrides.has(id) or r.is_empty():
		return r
	var changes: Dictionary = _overrides[id]["row"]
	var out := r.duplicate(true)
	for field: String in OVERRIDE_ROW_FIELDS:
		if changes.has(field):
			out[field] = changes[field]
	var variants: Dictionary = out.get("variants", {})
	for name: String in (changes.get("variants", {}) as Dictionary):
		if variants.has(name):
			variants[name] = (variants[name] as Dictionary).merged(changes["variants"][name], true)
	return out


## Give a shipped adapter a mod's models. "" when it took, else why not.
static func override_brick(id: String, changes: Dictionary, owner_id: String) -> String:
	if not _shipped().has(id):
		return "'%s' is not a shipped power brick" % id
	if changes.is_empty():
		return "no changes given for '%s'" % id
	if _overrides.has(id):
		return "'%s' is already dressed by mod '%s'" % [id, _overrides[id]["owner"]]
	for field: String in changes:
		if field != "variants" and not OVERRIDE_ROW_FIELDS.has(field):
			return "'%s' cannot be changed on a power brick (only %s and variants)" \
				% [field, ", ".join(OVERRIDE_ROW_FIELDS)]
	var shipped_variants: Dictionary = (_shipped()[id] as Dictionary).get("variants", {})
	var given: Variant = changes.get("variants", {})
	if not given is Dictionary:
		return "variants is not a dictionary"
	for name: Variant in (given as Dictionary):
		if not shipped_variants.has(str(name)):
			return "'%s' has no %s model (it has %s)" % [id, name, ", ".join(shipped_variants.keys())]
		var v: Variant = (given as Dictionary)[name]
		if not v is Dictionary:
			return "variant %s is not a dictionary" % name
		for field: String in (v as Dictionary):
			if not OVERRIDE_VARIANT_FIELDS.has(field):
				return "'%s' cannot be changed on a variant (only %s)" \
					% [field, ", ".join(OVERRIDE_VARIANT_FIELDS)]
		for field: String in ["model", "plug_model"]:
			var path := str((v as Dictionary).get(field, ""))
			if not path.is_empty() and not ResourceLoader.exists(path):
				return "%s %s: no such scene %s" % [name, field, path]
	var plug := str(changes.get("plug_model", ""))
	if not plug.is_empty() and not ResourceLoader.exists(plug):
		return "plug_model: no such scene %s" % plug
	_overrides[id] = {"row": changes.duplicate(true), "owner": owner_id}
	print("[Power] brick %s dressed by mod %s" % [id, owner_id])
	return ""


## Take back what mod `owner_id` gave (ModApi.withdraw).
static func drop_mod(owner_id: String) -> void:
	for id: String in _overrides.keys():
		if _overrides[id]["owner"] == owner_id:
			_overrides.erase(id)
	for id: String in extra.keys():
		if (extra[id] as Dictionary).get("owner", "") == owner_id:
			extra.erase(id)


## The variants an adapter comes in, in the order its row lists them.
static func variants_of(id: String) -> Array:
	return (row(id).get("variants", {}) as Dictionary).keys()


## One variant of an adapter, its row's own fields under it (dc_plug, plug_mm).
## An unknown variant is the first.
static func variant(id: String, name: String) -> Dictionary:
	var r := row(id)
	var all: Dictionary = r.get("variants", {})
	if all.is_empty():
		return {}
	var v: Dictionary = all.get(name, all[all.keys()[0]])
	var out := v.duplicate(true)
	if not out.has("dc_plug"):
		out["dc_plug"] = str(r.get("dc_plug", ""))
	out["plug_mm"] = r.get("plug_mm", [9.0, 9.0, 35.0])
	if not out.has("plug_model") and r.has("plug_model"):
		out["plug_model"] = r["plug_model"]
	if not out.has("cord") and r.has("cord"):
		out["cord"] = r["cord"]
	return out


## The variant a player in mains region `region` gets by default: the one sold
## there, else the adapter's first.
static func variant_for_region(id: String, region: String) -> String:
	var all := variants_of(id)
	if all.is_empty():
		return ""
	var want := str(REGION_VARIANT.get(MainsRegions.resolve(region), "usa"))
	return want if all.has(want) else str(all[0])


## The wall plug a variant's prongs are.
static func wall_plug_of(name: String) -> String:
	return str(VARIANT_PLUGS.get(name, "nema_1_15_plug"))


## The bricks whose row fits a machine (its model id or systemid).
static func for_machine(model_id: String, systemid: String) -> Array:
	var out := []
	for id: String in ids():
		var fits: Array = row(id).get("fits", [])
		if fits.has(model_id) or fits.has(systemid):
			out.append(id)
	return out
