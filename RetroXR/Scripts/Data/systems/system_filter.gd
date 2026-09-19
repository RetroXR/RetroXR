## SystemFilter — systemids hidden from system-browsing UI.
##
## The bundled core-info database carries 139 distinct systemids, but a chunk of
## those are not consoles: media players, libretro's test core, and cores that
## ship a single game rather than emulate a platform. They add tiles to the
## Download grid that nobody wants to browse.
##
## Usage:
##   if SystemFilter.is_hidden(sid): continue
##   var visible := SystemFilter.filter_ids(core_db.get_unique_systemids())
##   var visible := SystemFilter.filter_systems(systems)   # Array of Dictionary
##
## Set `SystemFilter.enabled = false` to show all 139 systemids again; the
## Options view exposes this as the "System Filter" switch.
class_name SystemFilter
extends RefCounted


## Players, virtual machines and test harnesses — nothing here emulates a
## console, so a hardware tile for it is meaningless.
const NOT_A_SYSTEM: PackedStringArray = [
	"adv_test_core",    # advanced_tests — libretro's own test harness
	"game_music",       # gme — chiptune/VGM player
	"internet_radio",   # radio — streaming radio
	"mess",             # mamemess — multi-system, no single platform
	"movie",            # mpv — video player
	"music",            # pocketcdg — CD+G karaoke
	"native32",         # native32emu — runs native win32 binaries
	"redbook",          # audio-CD playback
	"rvvm",             # RISC-V virtual machine
]

## Cores that ship one game (or one game's engine) instead of a platform.
const SINGLE_GAME: PackedStringArray = [
	"2048",
	"anarch",
	"bomberman",        # mrboom
	"craft",            # Minecraft clone
	"cruzes",
	"dinothawr",
	"doukutsu-rs",      # Cave Story
	"gong",             # Pong clone
	"jumpnbump",
	"nxengine",         # Cave Story, second core
	"openlara",         # Tomb Raider
	"sdlpal",
	"superbroswar",
	"syobonaction",
	"xrick",            # Rick Dangerous
]

## Single-game FPS engines. Split from SINGLE_GAME because they are the most
## defensible arcade fixtures in that group — clear this array to show them.
const FPS_ENGINES: PackedStringArray = [
	"doom",             # prboom
	"doom3",           # boom3, boom3_xp
	"quake",          # tyrquake
	"quake_2",
	"quake3",
	"wolfenstein",
]

## When false, is_hidden() always reports false and every systemid is browsable.
static var enabled: bool = true


## True when this systemid should be kept out of system-browsing UI.
static func is_hidden(systemid: String) -> bool:
	if not enabled:
		return false
	return systemid in NOT_A_SYSTEM \
		or systemid in SINGLE_GAME \
		or systemid in FPS_ENGINES


## Every hidden systemid, sorted. Useful for a settings screen or a probe.
static func hidden_ids() -> Array[String]:
	var ids: Array[String] = []
	for group: PackedStringArray in [NOT_A_SYSTEM, SINGLE_GAME, FPS_ENGINES]:
		for sid: String in group:
			ids.append(sid)
	ids.sort()
	return ids


## Drop hidden entries from a plain list of systemids.
static func filter_ids(ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for sid: String in ids:
		if not is_hidden(sid):
			out.append(sid)
	return out


## Drop hidden entries from an Array of Dictionaries carrying a "systemid" key,
## the shape the browser widgets are fed.
static func filter_systems(systems: Array) -> Array:
	var out: Array = []
	for s: Dictionary in systems:
		if not is_hidden(str(s.get("systemid", ""))):
			out.append(s)
	return out
