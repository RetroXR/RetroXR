## PowerProfiles — what each machine runs on: the inlet or jack on its back, the
## cells in its bays, or a battery built in. Read by RetroSystem when it builds its
## PowerInput (docs/dev/power.md).
##
## Keyed by model id first (a handheld's shell decides, and two models of a platform
## can differ), then by systemid. A machine with no row takes no modelled supply and
## is always powered, which is the right answer for hardware nobody has looked up yet.
##
## Facts are RetroXR-models' `remaining-models.md` power lines (each adapter's plug,
## each console's inlet), never guessed: a row names the standard of the PLUG the
## machine takes, so two machines that take the same barrel take each other's adapter
## as they do on the hardware (Connectors). Voltage is not modelled.
##
## Row fields:
##   inlet     "c8" (a figure-eight C7 cord, internal PSU), "c8p" (the polarized one),
##             "c14" (a C13 kettle lead), "dc" (an AC adapter's DC plug), "dock" (the
##             N64's NUS-002, which docks into the back). Omitted: no inlet (cells only,
##             or a built-in battery).
##   plug      for "dc": the connector of the adapter plug the jack takes.
##   brick     the PowerBrickCatalog row of the machine's own AC adapter.
##   internal  a rechargeable pack built in; its DC jack only charges it.
##   cells     a note for the menu and the docs only: the bays are the model's
##             BatteryAA<n> markers (CellSlots), which is what is counted.
##   bay       for a primitive with no bay of its own: the one BatteryBay builds.
##   dc_jack   the DC IN socket scene the stand-in authors, built by SystemPower for a
##             mod's shell that has none (it goes in the model's own inlet).
##   (A mod's model row can carry its own as `"power": {...}`, these same fields.)
##   through   "controller": the supply comes up a controller's cord from the pack or
##             tap on it (the Virtual Boy; VbController, VbPowerUnit).
class_name PowerProfiles
extends RefCounted

const _ROWS := {
	# ── consoles with an internal power supply: a C8 inlet on the back ────────────
	"psx":        {"inlet": "c8p"},   # PS1: polarized C7 cord (US)
	"ps2":        {"inlet": "c8p"},   # the fat PS2, as the PS1
	"saturn":     {"inlet": "c8p"},
	"dreamcast":  {"inlet": "c8p"},
	"cdimono1":   {"inlet": "c8p"},
	"xbox":       {"inlet": "c8"},    # non-polarized C7
	"3do":        {"inlet": "c8"},    # FZ-10's
	# ── consoles on an AC adapter: a DC jack ─────────────────────────────────────
	"nes":        {"inlet": "dc", "plug": "barrel_5_5x2_1", "brick": "nes_ac_adapter"},
	"famicom":    {"inlet": "dc", "plug": "barrel_5_5x2_1", "brick": "hvc_ac_adapter"},
	"snes":       {"inlet": "dc", "plug": "snes_dc_plug", "brick": "snes_ac_adapter"},
	"sfc":        {"inlet": "dc", "plug": "barrel_5_5x2_1", "brick": "hvc_ac_adapter"},
	"n64":        {"inlet": "dock", "plug": "n64_psu_dock", "brick": "n64_psu"},
	"gc":         {"inlet": "dc", "plug": "gc_dc_plug", "brick": "gamecube_ac_adapter"},
	"wii":        {"inlet": "dc", "plug": "wii_dc_plug", "brick": "wii_ac_adapter"},
	# The Genesis model is the Model 2: Sega's MK-2103, the 32X's adapter too.
	"genesis":    {"inlet": "dc", "plug": "eiaj_03", "brick": "sega_mk2103_adapter"},
	"mastersystem": {"inlet": "dc", "plug": "barrel_5_5x2_1"},
	"atarijaguar": {"inlet": "dc", "plug": "barrel_5_5x2_1", "brick": "jaguar_ac_adapter"},
	"neogeo_mvs_console": {"inlet": "dc", "plug": "barrel_5_5x2_1"},
	"pcengine":   {"inlet": "dc", "plug": "barrel_5_5x2_1"},
	"tg16":       {"inlet": "dc", "plug": "barrel_5_5x2_1"},
	# The PC tower's model authors its own C14 inlet; the row only says so.
	"pc_tower":   {"inlet": "c14"},
	# An arcade cabinet: a C14 inlet on its back, the kettle lead apart (SystemPower).
	"arcade":     {"inlet": "c14"},
	"daphne":     {"inlet": "c14"},
	"dice":       {"inlet": "c14"},
	"arcade_cabinet_generic": {"inlet": "c14"},
	"arcade_cabinet_neogeo":  {"inlet": "c14"},
	"arcade_cabinet_daphne":  {"inlet": "c14"},
	"arcade_cabinet_daphne_gun": {"inlet": "c14"},
	"arcade_cabinet_dice":    {"inlet": "c14"},
	# ── handhelds: cells in their bays, and a DC jack where the hardware has one ─
	# A pack built in (GBA SP, DS, 3DS, PSP) is always charged: the machine is always
	# powered, and its jack only charges it.
	# `bay` builds a primitive's compartment (BatteryBay): which cells, which way they
	# lie, where on the back ([u, v] of the body, +v toward +Z, the end away from a
	# portrait machine's screen), split into two grips' compartments or not.
	"game_boy_primitive":       {"cells": "4 x AA", "brick": "dmg_battery_pack",
		"dc_jack": "res://Scenes/Objects/cables/dmg_dc_port.tscn",
		"bay": {"size": "AA", "count": 4, "along": "x", "at": [0.0, 0.2]}},
	"game_boy_color_primitive": {"cells": "2 x AA", "brick": "gbc_ac_adapter",
		"dc_jack": "res://Scenes/Objects/cables/gbc_dc_port.tscn",
		"bay": {"size": "AA", "count": 2, "along": "x", "at": [0.0, 0.28]}},
	# No DC jack on a GBA: the AGB-008 module goes in the bay instead of the cells.
	"game_boy_advance":         {"cells": "2 x AA", "brick": "agb_power_module"},
	"game_boy_advance_primitive": {"cells": "2 x AA", "brick": "agb_power_module",
		"bay": {"size": "AA", "count": 2, "along": "x", "at": [0.0, 0.05]}},
	"game_boy_advance_sp_primitive": {"internal": true, "brick": "ags_ac_adapter"},
	"nds_primitive":            {"internal": true, "brick": "ags_ac_adapter"},
	"n3ds_primitive":           {"internal": true, "brick": "wap_ac_adapter"},
	"psp_primitive":            {"internal": true, "brick": "psp_ac_adapter"},
	# Three cells in each grip, standing the long way.
	"game_gear":                {"cells": "6 x AA", "brick": "gamegear_ac_adapter",
		"dc_jack": "res://Scenes/Objects/cables/gg_dc_port.tscn",
		"bay": {"size": "AA", "count": 3, "along": "z", "at": [0.36, 0.0], "split": true}},
	# The PAG-1200's plug is the Game Boy's 3.5 mm one (PowerBrickCatalog), so the jack too.
	"atari_lynx":               {"cells": "6 x AA", "brick": "lynx_ac_adapter",
		"dc_jack": "res://Scenes/Objects/cables/dmg_dc_port.tscn",
		"bay": {"size": "AA", "count": 3, "along": "z", "at": [0.36, 0.0], "split": true}},
	"wonderswan":               {"cells": "1 x AA",
		"bay": {"size": "AA", "count": 1, "along": "x", "at": [0.0, 0.3]}},
	"wonderswan_color":         {"cells": "1 x AA",
		"bay": {"size": "AA", "count": 1, "along": "x", "at": [0.0, 0.3]}},
	"neo_geo_pocket":           {"cells": "2 x AA",
		"bay": {"size": "AA", "count": 2, "along": "x", "at": [0.0, 0.0]}},
	"neo_geo_pocket_color":     {"cells": "2 x AA",
		"bay": {"size": "AA", "count": 2, "along": "x", "at": [0.0, 0.0]}},
	"pokemon_mini":             {"cells": "1 x AAA",
		"bay": {"size": "AAA", "count": 1, "along": "x", "at": [0.0, 0.1]}},
	"supervision":              {"cells": "4 x AA",
		"bay": {"size": "AA", "count": 4, "along": "x", "at": [0.0, 0.22]}},
	# Nothing on the console: the VUE-007 pack (6 x AA) or the VUE-011 tap clips onto
	# the controller, and the supply comes up its cord.
	"virtualboy":               {"cells": "6 x AA, in the controller's pack", "through": "controller"},
}

## Rows a mod adds or replaces (ModApi), over the shipped ones.
static var extra := {}


## The row for a machine: its model's, else its platform's, else {}.
static func for_machine(model_id: String, systemid: String) -> Dictionary:
	for key: String in [model_id, systemid]:
		if key.is_empty():
			continue
		if extra.has(key):
			return extra[key]
		if _ROWS.has(key):
			return _ROWS[key]
		# A mod's model says what it runs on in its own row ("power"): a PSone is on
		# the PlayStation's platform and takes an adapter, where a PS1 takes a cord.
		if key == model_id:
			var own: Variant = SystemModelRegistry.row_for(model_id).get("power")
			if own is Dictionary and not (own as Dictionary).is_empty():
				return own
	# A mod's model of a machine the game has a stand-in for (xenu.gb's colours, a 3DS
	# XL): the stand-in's row, which the facts are about. Rows are keyed by model id, so
	# without this a Game Boy in another shell had no supply at all.
	for stand_in: Variant in SystemModelRegistry.stand_in_ids():
		var stand_in_id := str(stand_in)
		if stand_in_id != model_id and SystemModelRegistry.platform_of(stand_in_id) == systemid:
			if extra.has(stand_in_id):
				return extra[stand_in_id]
			if _ROWS.has(stand_in_id):
				return _ROWS[stand_in_id]
	return {}


## The connector a profile's inlet takes, or "" for one with none.
static func inlet_connector(profile: Dictionary) -> String:
	match str(profile.get("inlet", "")):
		"c8":
			return "iec_c7_plug"
		"c8p":
			return "iec_c7_polarized_plug"
		"c14":
			return "iec_c13_plug"
		"dc", "dock":
			return str(profile.get("plug", ""))
	return ""
