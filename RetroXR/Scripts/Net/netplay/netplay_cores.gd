## NetplayCores — which cores may hold a netplay session, how they may hold one,
## and the options each is pinned to.
##
## Vetted with Tools/netplay/netplay_spike.gd. `verified` is cold-start determinism:
## two processes running the same inputs from frame 0 produce identical RAM-CRC
## streams, which is all a session needs while everybody starts together.
## `state_transfer` is savestate reload fidelity, which only a late join and a
## desync resync need. `strategies` is how a session may be RUN — see Strategy.
## `cross_play` is whether two peers on different CPU architectures may play at
## all. A core not listed here falls back to the "LIVE on host" placeholder.
##
## `options` are forced on every peer at cold start so a peer's own core-option
## config cannot introduce divergence.
##
## core_name -> { verified, state_transfer, strategies, cross_play, crc_interval,
##                scratch_saves, systems, options }
class_name NetplayCores
extends RefCounted

## How a session keeps its peers in step.
##
## LOCKSTEP and DETERMINISM share one transport — the same frame scheduler, the
## same input path — so nothing here selects a different way of moving bytes.
## What separates them is what happens when peers stop agreeing: LOCKSTEP ships a
## savestate to repair the odd one out, DETERMINISM cannot (its cores have no
## transferable state) and so makes divergence impossible up front, then reports
## it and stops. ROLLBACK is the only one that is a different transport.
enum Strategy { LOCKSTEP = 0, ROLLBACK = 1, DETERMINISM = 2 }

## Preferred first: a core that can do more than one gets the strongest its whole
## group agrees on.
const STRATEGY_ORDER: Array = [Strategy.ROLLBACK, Strategy.DETERMINISM, Strategy.LOCKSTEP]

## Frames between RAM CRC checkpoints when a core does not ask for its own. The
## C++ default is the same number; a core with a large RAM asks for a longer one
## because the whole region is hashed inline on the emulation thread.
const DEFAULT_CRC_INTERVAL := 60

const CORES: Dictionary = {
	"fceumm": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": true,
		"systems": ["nes", "famicom"],
		"options": {},
	},
	"gambatte": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"systems": ["gb", "game_boy_color"],
		"options": {"gambatte_frame_dupe": "disabled"},
	},
	"tgbdual": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"systems": ["gb", "game_boy_color"],
		"options": {"tgbdual_gblink_enable": "disabled"},
	},
	"mgba": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP, Strategy.DETERMINISM],
		"cross_play": false,
		# ereader: the card tile. A swipe is a frame-scheduled disc op, and the
		# fork's savestate carries the scanner, so rollback and late join hold.
		"systems": ["gba", "gb", "game_boy_color", "ereader"],
		"options": {},
	},
	"gpsp": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"systems": ["gba"],
		"options": {"gpsp_rtc_time_source": "deterministic"},
	},
	"dolphin": {
		"verified": false,
		"state_transfer": false,
		"strategies": [Strategy.DETERMINISM],
		"cross_play": false,
		"crc_interval": 900,
		"scratch_saves": true,
		"systems": ["gc", "wii"],
		"options": {
			"dolphin_determinism": "enabled",
			"dolphin_main_cpu_thread": "enabled",
			"dolphin_main_mmu": "disabled",
			"dolphin_main_accurate_cpu_cache": "disabled",
			"dolphin_dsp_hle": "enabled",
			"dolphin_dsp_jit": "enabled",
			"dolphin_fastmem": "enabled",
		},
	},
	"snes9x": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"systems": ["snes", "sufami"],
		"options": {},
	},
	"genesis_plus_gx": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"systems": ["megadrive", "genesis", "segacd", "gamegear", "mastersystem"],
		"options": {},
	},
	# The standalone VMU (VmuCard), not a RetroSystem. Savestates and the fixed
	# clock need the RetroXR fork past retroxr-vemulator-libretro-v2. It
	# publishes no SYSTEM_RAM or memory map, so the CRC is a savestate's. The BIOS
	# is pinned off because one peer having the file and another not is two
	# different machines; the HLE boot is the same everywhere.
	"vemulator": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"crc_from_state": true,
		"systems": ["vmu"],
		"options": {
			"clock": "fixed",
			"bios": "disabled",
			"enable_flash_write": "enabled",
			"serial_link": "disabled",
		},
	},
	# The Atari Lynx on RetroXR's fork (beetle-lynx-libretro, retroxr branch),
	# which carries ComLynx. `link_rollback`: a cabled group of these can roll
	# back TOGETHER (Wrapper::NetplayGroupIteration) instead of dropping to
	# lockstep, because lynx_fixed_frames ends every unit's frame on the same
	# tick of the bus. Measured by Tools/netplay/lynx_rollback_probe: Warbirds
	# over the cable, 20 group rewinds, every CRC equal to lockstep.
	# `power_on_stagger`: frames between one unit being switched on and the
	# next, as players in a room do -- identical units powered on together
	# transmit on identical ticks and collide on every byte (lynx-link.md).
	"mednafen_lynx": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP],
		"cross_play": false,
		"link_rollback": true,
		"handheld_rollback": true,
		"power_on_stagger": 7,
		"systems": ["atarilynx"],
		"options": {"lynx_fixed_frames": "enabled"},
	},
	# The Neo Geo Pocket / Color on RetroXR's fork (beetle-ngp-libretro, retroxr
	# branch), which carries the SNK link cable. `ngp_rtc` runs the clock on
	# emulated time (stock read the host's, so peers disagreed from frame 1) and
	# `ngp_fixed_frames` ends every unit's frame on one bus tick, which is what
	# `link_rollback` needs. Measured by Tools/netplay/ngp_link_netplay_probe and
	# rewind_probe (docs/dev/ngp-link.md): 0 bad of 300 rewinds on three games,
	# 0 bad of 100 cabled group restores, 92 of them mid-conversation. The
	# options need core release v2+; v1 ignores them. `power_on_stagger`: two
	# units switched on together stall a game settling which end leads.
	"mednafen_ngp": {
		"verified": true,
		"state_transfer": true,
		"strategies": [Strategy.ROLLBACK, Strategy.LOCKSTEP, Strategy.DETERMINISM],
		"cross_play": false,
		"link_rollback": true,
		"handheld_rollback": true,
		"power_on_stagger": 37,
		"systems": ["ngp", "ngpc"],
		"options": {"ngp_rtc": "deterministic", "ngp_fixed_frames": "enabled"},
	},
	"pcsx_rearmed": {
		"verified": true,
		"state_transfer": false,
		"strategies": [Strategy.DETERMINISM],
		"cross_play": false,
		"systems": ["psx"],
		"options": {},
	},
}


## True when a cabled group of this core can roll back together rather than
## drop to lockstep: its frames end on the same tick of the link bus on every
## unit, so "every machine at frame N" is one instant on the wire.
static func link_rollback_capable(core_name: String) -> bool:
	return bool((CORES.get(core_name, {}) as Dictionary).get("link_rollback", false))


## True when a HANDHELD on this core may still roll back: it feeds the core
## nothing but its buttons. A handheld otherwise forces lockstep because its
## motion sensors travel in the aux block, which only the lockstep scheduler
## carries; the Lynx has none, and a hand-over is a scheduled port transfer
## under rollback like any other.
static func handheld_rollback_capable(core_name: String) -> bool:
	return bool((CORES.get(core_name, {}) as Dictionary).get("handheld_rollback", false))


## Frames between switching on one cabled machine of this core and the next
## at a cold start, or 0 when they may all start together.
static func power_on_stagger(core_name: String) -> int:
	return int((CORES.get(core_name, {}) as Dictionary).get("power_on_stagger", 0))


## Debug: let an UNVETTED core start a session anyway.
##
## The allowlist refuses to start rather than risk a silent desync, but the
## session already detects one — periodic RAM CRCs, a savestate resync, three
## strikes to spectator. Refusing to start is belt-and-braces, and it forecloses
## its own evidence: a core cannot be shown deterministic-in-practice if nothing
## may run it. This switch is how a core gets MEASURED before it is listed.
##
## A static, deliberately, and never written to AppPrefs: a debug option that
## survives a restart is one a player can be left stranded in.
static var debug_allow_unverified := false


## True if the core is on the allowlist AND has passed determinism vetting.
static func is_capable(core_name: String) -> bool:
	if debug_allow_unverified and not core_name.is_empty():
		return true
	var e: Dictionary = CORES.get(core_name, {})
	return bool(e.get("verified", false))


## Deterministic core options to force on every peer for this core (may be empty).
##
## dolphin_cpu_core is deliberately absent from every entry. Its valid values are
## architecture-specific — JIT64 exists only on x86_64, JITARM64 only on arm64 —
## so a literal here would leave one architecture unable to boot at all. What
## keeps peers agreeing on it instead is `cross_play`: a core that cannot be
## trusted across architectures only ever plays same-arch, where the shipped
## default is the same number on both ends.
static func forced_options(core_name: String) -> Dictionary:
	var e: Dictionary = CORES.get(core_name, {})
	return (e.get("options", {}) as Dictionary).duplicate()


## Which strategies this core is vetted for, strongest first. Empty when the core
## is unlisted or unverified — an unverified core has no evidence for any of them.
##
## An entry with no `strategies` key answers LOCKSTEP: it is the one strategy
## that asks nothing of a core beyond the cold-start determinism `verified`
## already means.
static func strategies_for(core_name: String) -> Array:
	if not is_capable(core_name):
		return []
	var e: Dictionary = CORES.get(core_name, {})
	var listed: Array = e.get("strategies", [Strategy.LOCKSTEP])
	var out: Array = []
	for s: int in STRATEGY_ORDER:
		if listed.has(s):
			out.append(s)
	return out


## The strongest strategy this core is VETTED for, or -1 when it is not.
##
## For anything that describes a core to the player rather than gating a
## session. It deliberately ignores debug_allow_unverified: that switch makes
## is_capable() answer true for every core name there is, so a caller using it
## to decide what to show would mark the whole list the moment it is flipped.
static func listed_strategy(core_name: String) -> int:
	if not CORES.has(core_name):
		return -1
	if not bool((CORES[core_name] as Dictionary).get("verified", false)):
		return -1
	var listed: Array = strategies_for(core_name)
	return int(listed[0]) if not listed.is_empty() else -1


## True when the core supports rollback netplay: verified deterministic AND
## cheap enough to savestate every frame (rollback rewinds via a state ring).
static func rollback_capable(core_name: String) -> bool:
	return strategies_for(core_name).has(Strategy.ROLLBACK)


## True when a state captured from this core can be restored by another peer,
## which is what a late join and a desync resync both put on the wire. False
## means a session still PLAYS, from a cold start, with everyone present.
##
## Deliberately NOT covered by debug_allow_unverified: that switch exists to let
## a core be measured, and shipping it a state that will not restore measures
## nothing. An unlisted core answers false here.
static func state_transfer_capable(core_name: String) -> bool:
	var e: Dictionary = CORES.get(core_name, {})
	return bool(e.get("verified", false)) and bool(e.get("state_transfer", false))


## True when two peers on DIFFERENT CPU architectures may share a session with
## this core — a Quest against a desktop, which is the only cross-platform axis
## this app has.
##
## Defaults to false, like `verified`: absence of evidence is not evidence. It is
## independent of the strategy on purpose. A core can be determinism-only and
## still cross-play, or rollback-capable and still same-arch only; they answer
## different questions. Dolphin is the worked example of why the question exists
## at all — it picks its CPU backend from the host architecture.
static func allows_cross_play(core_name: String) -> bool:
	var e: Dictionary = CORES.get(core_name, {})
	return bool(e.get("verified", false)) and bool(e.get("cross_play", false))


## Frames between RAM CRC checkpoints for this core.
##
## The whole of RETRO_MEMORY_SYSTEM_RAM is hashed inline on the emulation thread,
## so the cost scales with the machine: free for a 2 KB NES, tens of milliseconds
## for a GameCube's 24 MB. A large core buys back the hitch with a longer gap.
static func crc_interval(core_name: String) -> int:
	var e: Dictionary = CORES.get(core_name, {})
	return int(e.get("crc_interval", DEFAULT_CRC_INTERVAL))


## True when this core's desync CRC must come from a SAVESTATE, not live RAM.
##
## Reading RAM between frames assumes the core is quiescent when retro_run
## returns, and a core that emulates its CPU on a thread of its own is not:
## Dolphin comes back on a GPU field boundary while its CPU thread keeps
## writing, so the hash races that thread and two peers disagree even when the
## emulation is identical -- a check that reports divergence at random.
##
## A savestate is the one snapshot such a core has to make coherent. It is far
## more expensive, which is what a longer crc_interval pays for.
##
## DOLPHIN CANNOT USE IT, which is the awkward part: measured, asking it to
## serialize from the emulation thread between frames wedges it at frame 1.
## retro_serialize marshals onto its CPU thread and waits; that thread is
## waiting on the GPU FIFO; and the GPU loop only runs inside retro_run, which
## the caller has already returned from. The same reasoning applies to every
## RequestSaveState under the netplay gate, so a Dolphin late join or resync
## would wedge in the same place -- which is a much better reason for its
## state_transfer:false than the one recorded there.
##
## So the oracle a threaded core needs has to be taken from INSIDE the frame,
## not between frames, and that is not something the frontend can reach today.
static func crc_from_state(core_name: String) -> bool:
	var e: Dictionary = CORES.get(core_name, {})
	return bool(e.get("crc_from_state", false))


## True when this core's saves must be redirected to an empty per-session folder.
##
## For cores that manage their own save files outside RETRO_MEMORY_SAVE_RAM, the
## frontend's SRAM sync is a no-op and two peers' saves differ silently. Dolphin
## is the case: it returns 0 for SAVE_RAM and keeps GameCube memory cards in a
## folder of its own, shared by every game.
static func uses_scratch_saves(core_name: String) -> bool:
	var e: Dictionary = CORES.get(core_name, {})
	return bool(e.get("scratch_saves", false))

## Every vetted core covering this system, strongest first.
##
## `systems` had no reader until this: the session gate is by core NAME, so the
## table knew which machine each entry was for and could not be asked. Ranking
## is strategy first (STRATEGY_ORDER), then state_transfer, then cross_play --
## the order a player feels them in. A core that cannot hold a session at all is
## not a candidate, so this ignores debug_allow_unverified for the same reason
## listed_strategy does: that switch answers true for every name there is, and a
## suggestion built on it would recommend cores with no evidence behind them.
static func cores_for_system(systemid: String) -> Array[String]:
	if systemid.is_empty():
		return [] as Array[String]
	var ranked: Array = []
	for core: String in CORES:
		var e: Dictionary = CORES[core]
		if not (e.get("systems", []) as Array).has(systemid):
			continue
		var strategy := listed_strategy(core)
		if strategy < 0:
			continue
		ranked.append({
			"core": core,
			"rank": STRATEGY_ORDER.find(strategy),
			"state": 0 if state_transfer_capable(core) else 1,
			"cross": 0 if allows_cross_play(core) else 1,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		if int(a["state"]) != int(b["state"]):
			return int(a["state"]) < int(b["state"])
		if int(a["cross"]) != int(b["cross"]):
			return int(a["cross"]) < int(b["cross"])
		return str(a["core"]) < str(b["core"]))
	var out: Array[String] = []
	for r: Dictionary in ranked:
		out.append(str(r["core"]))
	return out


## The core to offer instead of `core_name` on this system, or "" if there is
## none. Never suggests the core it was asked about, even when that core is
## vetted -- a substitute for something that already works is noise.
static func suggest_substitute(core_name: String, systemid: String) -> String:
	for candidate: String in cores_for_system(systemid):
		if candidate != core_name:
			return candidate
	return ""


## Why this core may not hold a session, or "" when it may.
##
## is_capable() answers the gate; this answers the player. The two cases read
## the same to a bool and want different remedies: an UNLISTED core has never
## been measured and wants a different core, while a LISTED one failed vetting
## and wants its own entry revisited. Reports the real reason even while
## debug_allow_unverified is forcing the gate open, so the explainer does not
## go blank the moment the switch is flipped.
static func why_not_capable(core_name: String) -> String:
	if core_name.is_empty():
		return "no core is selected"
	if not CORES.has(core_name):
		return "'%s' has never been vetted for netplay determinism" % core_name
	if not bool((CORES[core_name] as Dictionary).get("verified", false)):
		return "'%s' is listed but its cold-start determinism is unproven" % core_name
	return ""
