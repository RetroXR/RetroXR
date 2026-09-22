## BiosBoot — which machines can show their own BIOS, and what it takes.
##
## Two separate things live here because a player thinks of them as one:
##
##   * `empty_media` — the machine switched on with NOTHING in it lands in the
##     console's own BIOS. A PlayStation with no disc shows "Please insert
##     PlayStation CD-ROM" and its CD player / memory card menu.
##   * `splash` — a game IS loaded, and the machine plays the real boot ROM
##     first instead of skipping straight to it. The GameCube IPL animation.
##
## Both are gated on `boot_rom`, which is the answer to "is the BIOS actually
## there?". It is an ANY-OF group, and that is the thing the .info's own
## `firmwareN_opt` flag cannot express: pcsx_rearmed lists four PS1 BIOSes all
## marked optional because you need exactly one of them, and neocd lists twelve
## for the same reason. Reading `optional` there would conclude a machine with
## no BIOS at all is fully provisioned.
##
## PROVENANCE. Every row was measured by Tools/bios_boot_probe, run one core
## per process by Tools/bios_boot_survey.sh. Nothing here is
## inferred from the .info files, and in particular nothing is inferred from
## `supports_no_game`: all sixteen candidates declare it false, including
## pcsx_rearmed, whose BIOS this feature demonstrably reaches.
##
## What the survey ruled OUT, so nobody re-derives these rows from the tables in
## the original request:
##
##   * Few cores start with no content at all. Sixteen were tried both ways the
##     libretro API allows (a null retro_game_info and a zeroed one) and six
##     crash the process outright: mgba and parallel_n64 dereference a null,
##     while mednafen_saturn, neocd, same_cdi and upstream dolphin die on a
##     zeroed one. flycast, pcsx2 and RetroXR's dolphin fork start on a null one
##     and draw their BIOS menus; the
##     installed pcee2 does not declare SET_SUPPORT_NO_GAME, so it is refused.
##     That is why the usual mechanism here is empty MEDIA -- a real file,
##     taking the ordinary content path -- and not an empty path.
##   * Only pcsx_rearmed accepts a zero-byte image. flycast (gdi/cdi/chd),
##     mednafen_saturn, mednafen_pce and neocd all refuse one. mednafen_saturn
##     takes a cue sheet over one silent audio track (`empty_media_track`),
##     which lands in the Saturn's CD player; a blank data track is "Disc
##     unsuitable for this system".
##   * mgba, flycast, mednafen_pce and pcsx_rearmed already ship with their
##     boot-ROM options set the way this feature wants them. mgba's and
##     pcsx_rearmed's measured keys carry a `splash` anyway: these values are
##     PINNED every launch rather than seeded once, and a pin's job is to beat a
##     saved value, which a shipped default cannot do -- a run that left
##     mgba_skip_bios "ON" behind is the case, and the survey itself produced
##     one. flycast and mednafen_pce have no `splash` because the survey never
##     recorded their key names, and a key a core does not declare is rejected
##     rather than applied.
##   * The N64 has no BIOS. Both N64 cores' only firmware entry is the 64DD IPL,
##     and the N64's own boot animation lives in each cartridge's IPL3. The real
##     machine here is nintendo_64dd, which does boot to the 64DD menu.
##
## Keyed on "<core>/<systemid>", never on core alone. mgba wants gba_bios.bin on
## a GBA and the Game Boy boot ROMs on a Game Boy; dolphin wants an IPL on a
## GameCube and a NAND on a Wii; and the filenames differ between cores serving
## one machine too (sameboy's dmg_boot.bin against gambatte's gb_bios.bin).
class_name BiosBoot


const _ROWS := {
	# ── Nintendo ─────────────────────────────────────────────────────────────
	# The one machine here that boots with NOTHING in it rather than with an
	# empty image, and the only reason it can is that this fork's mgba was taught
	# to. Upstream's retro_load_game dereferences the game info without checking
	# it, so the core could not even be asked; it declares SET_SUPPORT_NO_GAME
	# now and creates a Game Boy Advance directly when there is no content.
	#
	# It is worth having beyond the BIOS animation. A GBA with no cartridge is
	# what sits on the end of a GameCube lead in Four Swords Adventures and what
	# receives a program in single-cartridge play: the BIOS draws its screen and
	# then listens on the link port, which is the whole of how both work.
	#
	"mgba/gba": {
		"boot_rom": ["gba_bios.bin"],
		"empty_media": "",
		"no_content": true,
		"empty_options": {"mgba_use_bios": "ON", "mgba_skip_bios": "OFF"},
		"splash": {"mgba_use_bios": "ON", "mgba_skip_bios": "OFF"},
		"why": "Boots its own BIOS with no cartridge, and then listens on the link port",
	},
	# The DS's home screen is the FIRMWARE's menu, not the BIOS's: firmware.bin
	# carries it, and the two BIOSes are what run it, so all three must be there
	# (`also_needs` is all-of where `boot_rom` is any-of). With a cartridge in,
	# booting through the firmware rather than straight into the card is what
	# puts the menu up with the card -- and a GBA cartridge in Slot-2 -- listed
	# on it, as the hardware does; the player taps the card to start it.
	#
	# The DSi is the same DS machine with the core's console mode switched to
	# DSi, which is the player's choice and so is never pinned here. It needs
	# the dsi_* files as well and lands in the DSi Menu, which lists the card
	# beside System Settings.
	#
	# MEASURED 2026-09-21 with Tools/cores/ds_boot_probe, one core per process,
	# a real DS firmware and BIOS pair and a DSi NAND:
	#   melondsds  no content  -> DS home screen, "There is no DS Card inserted"
	#                             and "no Game Pak"; console mode dsi -> the DSi
	#                             health screen, a touch -> the DSi Menu. With
	#                             Super Mario 64 DS in -> listed on both menus;
	#                             with a GBA cartridge in Slot-2 as well -> "Start
	#                             GBA game." on the DS menu.
	#   melonds    declares no SET_SUPPORT_NO_GAME, so it cannot be asked with
	#              nothing; a ZERO-BYTE .nds reaches the same empty menu, and
	#              console mode DSi the DSi Menu (touch mode must be Touch, which
	#              the DS model pins). Card listed on both.
	#   desmume    no no-content support and refuses the empty image, so an empty
	#              DS stays "no game inserted"; with a card and the external
	#              BIOS/firmware on, the DS menu with the card listed. No DSi mode.
	#
	# The BIOS lookup in melondsds tries system/melondsds/melonDS DS/ first and
	# logs a failure there before finding the files one level up -- that line is
	# noise, not the cause of anything.
	#
	# melondsds lists the firmware files it FOUND as the values of its path
	# options and saves the choice -- so a core first run before the firmware was
	# installed has "/notfound" saved, keeps it for ever, and draws "Oh no!
	# melonDS DS couldn't start... /notfound" once the files are there (measured
	# on a real data root). The paths are pinned to the standard names for that
	# reason; the row is gated on those files, so the DS pin cannot dangle.
	"melondsds/nds": {
		"boot_rom": ["firmware.bin"],
		"also_needs": ["bios7.bin", "bios9.bin"],
		"empty_media": "",
		"no_content": true,
		"empty_options": {"melonds_boot_mode": "native", "melonds_sysfile_mode": "native",
			"melonds_firmware_nds_path": "firmware.bin",
			"melonds_firmware_dsi_path": "dsi_firmware.bin"},
		"splash": {"melonds_boot_mode": "native", "melonds_sysfile_mode": "native",
			"melonds_firmware_nds_path": "firmware.bin",
			"melonds_firmware_dsi_path": "dsi_firmware.bin"},
		# The built-in firmware's Wi-Fi profile ("melonAP"), written by a run
		# with NO firmware installed. Left there, the core merges it into the
		# real firmware and the menu dies at once -- ARM9 "PC in non executable
		# region 00800204", a white screen. Measured with a control leg: the
		# same pristine firmware.bin boots without it and crashes with it. The
		# core does not write it again once real firmware is in use.
		"retire_files": ["melonDS DS/wfcsettings.bin"],
		"why": "Boots to the DS home screen (or the DSi Menu), listing whatever cartridges are in",
	},
	"melonds/nds": {
		"boot_rom": ["firmware.bin"],
		"also_needs": ["bios7.bin", "bios9.bin"],
		"empty_media": "nds",
		"empty_options": {"melonds_boot_directly": "disabled"},
		"splash": {"melonds_boot_directly": "disabled"},
		"why": "Boots to the DS home screen (or the DSi Menu); an empty card slot takes a blank card image",
	},
	"desmume/nds": {
		"boot_rom": ["firmware.bin"],
		"also_needs": ["bios7.bin", "bios9.bin"],
		"empty_media": "",
		"splash": {"desmume_use_external_bios": "enabled", "desmume_boot_into_bios": "enabled"},
		"why": "Boots a DS card through the home screen; DeSmuME cannot start with the slot empty",
	},
	# ── Sony ─────────────────────────────────────────────────────────────────
	# The one machine that reaches a full BIOS UI. Verified visually: an empty
	# .cue gives the real "Please insert PlayStation CD-ROM" screen, from which
	# the CD player and memory card manager are reachable. Its four BIOSes are
	# regional and any one will do.
	"pcsx_rearmed/psx": {
		"boot_rom": ["scph5501.bin", "scph5500.bin", "scph5502.bin", "psxonpsp660.bin"],
		"empty_media": "cue",
		"empty_options": {"pcsx_rearmed_show_bios_bootlogo": "enabled",
			"pcsx_rearmed_bios": "auto"},
		"splash": {"pcsx_rearmed_show_bios_bootlogo": "enabled",
			"pcsx_rearmed_bios": "auto"},
		"why": "An empty disc gives the PS1 BIOS; measured, and the only machine where this works",
	},
	# Two PS2 cores, and they do NOT share the option key -- pcee2 says
	# pcsx2_fast_boot where LRPS2 says pcsx2_fastboot. Measured; the natural
	# guess is the wrong way round.
	"pcee2/ps2": {
		"boot_rom": ["pcsx2/bios"],
		"empty_media": "",
		"splash": {"pcsx2_fast_boot": "disabled"},
		"why": "Fast Boot skips the PS2 boot animation and browser",
	},
	"pcsx2/ps2": {
		"boot_rom": ["pcsx2/bios"],
		"empty_media": "",
		"no_content": true,
		"empty_options": {"pcsx2_fastboot": "disabled"},
		"splash": {"pcsx2_fastboot": "disabled"},
		"why": "Same switch as pcee2 under a different key",
	},

	# ── Nintendo ─────────────────────────────────────────────────────────────
	# GameCube only. A Wii row would need a NAND dump, which dolphin's .info
	# does not declare a path for, so there is nothing to check the option
	# against -- and enabling the Wii menu without one gives a black screen.
	"dolphin/gc": {
		"boot_rom": [
			"dolphin-emu/Sys/GC/USA/IPL.bin",
			"dolphin-emu/Sys/GC/EUR/IPL.bin",
			"dolphin-emu/Sys/GC/JAP/IPL.bin",
		],
		"empty_media": "",
		"no_content": true,
		"splash": {"dolphin_skip_gc_bios": "disabled"},
		"why": "Plays the GameCube IPL animation before the disc",
	},
	# The 64DD, not the N64. parallel_n64 is the nintendo_64dd core and this is
	# a genuine boot-to-menu; pointing it at a plain N64 would boot every
	# cartridge through a disk drive that is not there.
	"parallel_n64/n64dd": {
		"boot_rom": ["64DD_IPL.bin"],
		"empty_media": "",
		"splash": {"parallel-n64-boot-device": "64DD IPL"},
		"why": "Boots the 64DD IPL menu rather than straight into the disk",
	},

	# ── Sega ─────────────────────────────────────────────────────────────────
	# One core, five machines, one option key -- but a different boot ROM each
	# time, which is exactly why these rows cannot be keyed on the core alone.
	"genesis_plus_gx/genesis": {
		"boot_rom": ["bios_MD.bin"],
		"empty_media": "",
		"splash": {"genesis_plus_gx_bios": "enabled"},
		"why": "Plays the Mega Drive TMSS startup screen",
	},
	"genesis_plus_gx/mastersystem": {
		"boot_rom": ["bios_U.sms", "bios_E.sms", "bios_J.sms"],
		"empty_media": "",
		"splash": {"genesis_plus_gx_bios": "enabled"},
		"why": "Plays the Master System boot ROM",
	},
	"genesis_plus_gx/gamegear": {
		"boot_rom": ["bios.gg"],
		"empty_media": "",
		"splash": {"genesis_plus_gx_bios": "enabled"},
		"why": "Plays the Game Gear boot ROM",
	},
	"genesis_plus_gx/segacd": {
		"boot_rom": ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"],
		"empty_media": "",
		"splash": {"genesis_plus_gx_bios": "enabled"},
		"why": "Plays the Sega CD boot ROM; the CD BIOS is required for the system anyway",
		# A Sega CD disc will not start without one: the core opens the BIOS for
		# the disc's region and refuses the game when it is not there.
		"media_needs_boot_rom": true,
	},
	"flycast/dreamcast": {
		"boot_rom": ["dc/dc_boot.bin"],
		"empty_media": "",
		"no_content": true,
		"empty_options": {"reicast_hle_bios": "disabled"},
		"why": "Boots the Dreamcast menu with no disc in it",
	},
	"mednafen_saturn/saturn": {
		"boot_rom": ["sega_101.bin", "mpr-17933.bin"],
		"empty_media": "cue",
		"empty_media_track": "audio",
		"why": "A silent audio CD gives the Saturn's CD player and memory manager",
	},

	# ── Microsoft ────────────────────────────────────────────────────────────
	# Switched on with an empty tray an Xbox boots its DASHBOARD, and the
	# dashboard is software on the HARD DISK rather than anything in the BIOS --
	# so what a player sees is whatever their disk carries. The stock xemu image
	# has a placeholder where a dashboard would be, and all it draws is one line:
	# "Please insert an Xbox disc...". That is the machine working rather than
	# failing, and it is also the whole of what this row buys until someone
	# supplies a disk with a real dashboard on it.
	#
	# `no_content`, not empty media: there is no blank disc to hand an Xbox, and
	# the core declares SET_SUPPORT_NO_GAME.
	#
	# TWO flash BIOSes, and either will do -- an any-of group exactly like the
	# PlayStation's regional set above, which is the thing the .info's own
	# `firmwareN_opt` cannot say. Both are Complex 4627 dumps and they are
	# different files (md5 21445c6f… and ec00e31e…); each was measured alone in
	# the system folder on 2026-09-20 and boots Halo to its menu. The core takes
	# more names than these, and any .bin of the right size, but a dump nobody
	# here has BOOTED does not go in this list: a retail 3944 stops at "Your Xbox
	# requires service" and a retail 5838 draws nothing.
	#
	# `media_needs_boot_rom`, because with both of them optional in the .info
	# nothing else would notice a console with no BIOS at all -- a disc would
	# start into the core's own error instead of a card naming what is missing.
	#
	# MEASURED 2026-09-20, the v1 release core, on the OpenGL renderer and the
	# Vulkan one alike: 452 lit pixels of 307,200, in a band at x 25..280,
	# y 25..31 -- and twice in one process, stopped and started again, which is
	# the power cycle a core that read a missing path as a medium named "" would
	# fail on. Both no-content conventions were tried and this core takes either.
	#
	# That measurement is also a warning about HOW it was taken. The first pass
	# sampled every eighth pixel and reported the frame as uniform black, because
	# a line of 8-pixel text is twelve rows high and a sparse grid steps between
	# the strokes. A whole day went on that false reading. xbox_boot_probe counts
	# every pixel now and prints the bounding box with it.
	"xemu/xbox": {
		"boot_rom": ["Complex_4627v1.03.bin", "Complex_4627.bin"],
		"empty_media": "",
		"no_content": true,
		"media_needs_boot_rom": true,
		"why": "Boots the console's own dashboard with no disc in the tray",
	},
}


## The row for one machine, or {} when it has nothing to offer.
static func entry(core_name: String, systemid: String) -> Dictionary:
	if core_name.is_empty() or systemid.is_empty():
		return {}
	return _ROWS.get(core_name + "/" + systemid, {})


## Does a game of this systemid need one of the row's boot ROMs to start at all,
## rather than only for a splash? The .info cannot say: genesis_plus_gx marks
## every Sega CD BIOS optional, because the same core runs Genesis cartridges
## without one.
static func media_needs_boot_rom(core_name: String, systemid: String) -> bool:
	return bool(entry(core_name, systemid).get("media_needs_boot_rom", false))


## The row power_on reports when such a game has none of its boot ROMs, in the
## shape missing_required returns plus `any_of`: the regional files, any one of
## which would do.
static func media_boot_rom_row(core_name: String, systemid: String) -> Dictionary:
	var wanted: Array = entry(core_name, systemid).get("boot_rom", [])
	if wanted.is_empty():
		return {}
	var info := SystemInfo.for_system(systemid)
	var name := info.display_name if info != null else systemid
	return {"path": str(wanted[0]), "desc": "%s BIOS" % name, "dest": "", "any_of": wanted}


## [media_boot_rom_row] when this game needs a boot ROM and none is installed,
## otherwise [].
static func missing_for_media(core_name: String, systemid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if media_needs_boot_rom(core_name, systemid) and not boot_rom_present(core_name, systemid):
		var row := media_boot_rom_row(core_name, systemid)
		if not row.is_empty():
			out.append(row)
	return out


## The regional boot ROMs such a game needs that are not installed. The core
## wants the one for the disc's region, which nothing here can read before the
## core does, so a refused load with some of these missing is most likely that.
static func absent_media_boot_roms(core_name: String, systemid: String) -> Array[String]:
	var out: Array[String] = []
	if not media_needs_boot_rom(core_name, systemid):
		return out
	var present := {}
	for status_row: Dictionary in _firmware_rows(core_name):
		if int(status_row.get("status", -1)) == FirmwareState.Status.PRESENT:
			present[str(status_row.get("path", ""))] = true
	for file: Variant in entry(core_name, systemid).get("boot_rom", []):
		if not present.has(str(file)):
			out.append(str(file))
	return out


## Is this machine's boot ROM actually on disk?
##
## ANY of the group satisfies it -- they are regional alternatives, not a set.
## A MISMATCH does not count: a file whose md5 disagrees with the .info is the
## wrong dump, classically a PS1 BIOS from the wrong region, and booting it is
## a worse outcome than not offering the boot at all.
static func boot_rom_present(core_name: String, systemid: String) -> bool:
	var row := entry(core_name, systemid)
	if row.is_empty():
		return false
	var wanted: Array = row.get("boot_rom", [])
	if wanted.is_empty():
		return false
	# `also_needs` is the opposite shape: every one of these, as well as one of
	# the group. A DS menu is in its firmware but runs on its two BIOSes.
	var needed: Dictionary = {}
	for file: Variant in row.get("also_needs", []):
		needed[str(file)] = true
	var any_of := false
	for status_row: Dictionary in _firmware_rows(core_name):
		var path := str(status_row.get("path", ""))
		if int(status_row.get("status", -1)) != FirmwareState.Status.PRESENT:
			continue
		if wanted.has(path):
			any_of = true
		needed.erase(path)
	return any_of and needed.is_empty()


## Extension of the empty image that reaches this machine's BIOS, or "" when
## switching it on with an empty slot cannot get there.
static func empty_media_extension(core_name: String, systemid: String) -> String:
	return str(entry(core_name, systemid).get("empty_media", ""))


## Can this machine be switched on with nothing in it and show its own BIOS?
## The two halves are separate on purpose: a PlayStation with no BIOS installed
## has to keep saying "no game inserted", because an empty disc would only get
## it to a black screen.
static func can_boot_empty(core_name: String, systemid: String) -> bool:
	var has_empty := not empty_media_extension(core_name, systemid).is_empty()
	if not has_empty and not boots_with_no_content(core_name, systemid):
		return false
	return boot_rom_present(core_name, systemid)


## Does this machine start with NOTHING handed to it, rather than with an empty
## image standing in for a disc?
##
## Two different mechanisms, and the difference is not cosmetic. Empty media is a
## real file taking the ordinary content path, which is what a PlayStation needs
## because its BIOS wants a drive to look at. No content at all is the core being
## asked to start with a null game info, which most cores do not survive -- of
## sixteen surveyed, six took the process down -- so this is opt-in per row and
## measured, never assumed.
static func boots_with_no_content(core_name: String, systemid: String) -> bool:
	return bool(entry(core_name, systemid).get("no_content", false))


## Options that make an empty-slot boot take the measured BIOS path. They are
## explicit even when they match a core's shipped defaults: netplay cannot let
## one peer's saved option skip the BIOS while another waits in it.
static func empty_boot_options(core_name: String, systemid: String) -> Dictionary:
	return (entry(core_name, systemid).get("empty_options", {}) as Dictionary).duplicate()


## Firmware paths whose bytes decide the BIOS boot. Public for netplay's local
## fingerprint; firmware is never transferred.
static func boot_rom_paths(core_name: String, systemid: String) -> Array:
	var row := entry(core_name, systemid)
	return (row.get("boot_rom", []) as Array) + (row.get("also_needs", []) as Array)


## Core options that make a loaded game play its boot ROM first. Empty unless
## the boot ROM is there -- every one of these tells a core to run a file, and
## switching them on without it is how a machine that used to start a game ends
## up on a black screen instead.
static func splash_options(core_name: String, systemid: String) -> Dictionary:
	var row := entry(core_name, systemid)
	var splash: Dictionary = row.get("splash", {})
	if splash.is_empty():
		return {}
	if not boot_rom_present(core_name, systemid):
		return {}
	return splash.duplicate()


## The options this machine's run pins, for the slot it is actually starting
## with. An empty slot and a loaded game reach the BIOS by different keys, so the
## caller says which boot it is rather than this guessing from the table.
##
## Both halves stay separately callable: net_boot_spec composes a launch
## description rather than a set of pins, and picks its own half.
static func pinned_options(core_name: String, systemid: String, empty_boot: bool) -> Dictionary:
	if empty_boot:
		return empty_boot_options(core_name, systemid)
	return splash_options(core_name, systemid)


## Every key any row for this core pins, as a set. For the core manager, which
## edits a core's options with no machine in front of it and so has no systemid
## to ask with -- a key one of this core's machines pins is shown locked for all
## of them, which is the safe way round: the alternative offers an edit that the
## next power-on silently reverts.
##
## Keys only. A value here would be a value for the wrong machine, since one core
## serves several and genesis_plus_gx's five rows share a key.
static func pinned_keys_for_core(core_name: String) -> Dictionary:
	var out: Dictionary = {}
	if core_name.is_empty():
		return out
	for row_key: String in _ROWS:
		if row_key.get_slice("/", 0) != core_name:
			continue
		var row: Dictionary = _ROWS[row_key]
		for group: String in ["splash", "empty_options"]:
			for key: Variant in (row.get(group, {}) as Dictionary):
				out[str(key)] = true
	return out


## Move aside the files the row names under `retire_files`: leftovers a core
## wrote in some earlier state that break the boot this row pins. Only when the
## boot ROM is present, because only then is that boot taken. Renamed, never
## deleted -- it is the core's file, and a player may want it back. Returns the
## paths moved.
static func retire_stale_files(core_name: String, systemid: String) -> Array[String]:
	var out: Array[String] = []
	if not boot_rom_present(core_name, systemid):
		return out
	for rel: Variant in entry(core_name, systemid).get("retire_files", []):
		var path := FirmwareRequirements.destination(core_name, str(rel))
		if not FileAccess.file_exists(path):
			continue
		var aside := path + ".retroxr-retired"
		var n := 1
		while FileAccess.file_exists(aside):
			n += 1
			aside = path + ".retroxr-retired%d" % n
		if DirAccess.rename_absolute(path, aside) == OK:
			push_warning("[BiosBoot] moved %s aside to %s: it breaks the %s boot" % [path, aside.get_file(), systemid])
			out.append(path)
	return out


## Files this core cannot run at all without, and has not got.
##
## Straight from the .info's own required flag rather than from `boot_rom`:
## those two answer different questions. `boot_rom` asks whether a BIOS UI is
## reachable, which is a bonus; this asks whether the core will start, which
## decides whether the power button does anything. A machine can be missing its
## boot ROM and still play games perfectly (a Mega Drive), or have every
## optional file and still refuse to start (a PS2 with no bios folder).
##
## Returns the FirmwareState rows, each carrying `path`, `desc` and `dest`.
static func missing_required(core_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _firmware_rows(core_name):
		if int(row.get("status", -1)) == FirmwareState.Status.MISSING_REQUIRED:
			out.append(row)
	return out


static func _firmware_rows(core_name: String) -> Array[Dictionary]:
	var reqs := FirmwareRequirements.for_core(core_name)
	if reqs.is_empty():
		return [] as Array[Dictionary]
	return FirmwareState.shared().evaluate(core_name, reqs)


# ── Empty media ───────────────────────────────────────────────────────────────

## A 4 s track, the shortest a CD may carry.
const _SILENT_TRACK_SECTORS := 300
const _RAW_SECTOR_BYTES := 2352


## What the empty image holds: "" for a zero-byte file, "audio" for a cue sheet
## over one silent audio track.
static func empty_media_track(core_name: String, systemid: String) -> String:
	return str(entry(core_name, systemid).get("empty_media_track", ""))


## This machine's empty image, created if it is not already there; "" when the
## machine has none or it could not be written.
static func empty_media_for(core_name: String, systemid: String) -> String:
	return empty_media_path(empty_media_extension(core_name, systemid),
		empty_media_track(core_name, systemid))


## Where the empty image for `extension` and `track` lives, without creating it.
static func empty_media_file(extension: String, track := "") -> String:
	if extension.is_empty():
		return ""
	var stem := "no_disc" if track.is_empty() else "no_disc_" + track
	return _empty_media_dir().path_join(stem + "." + extension)


## Is `path` one of the empty images rather than a game?
static func is_empty_media(path: String) -> bool:
	return not path.is_empty() \
		and path.simplify_path().get_base_dir() == _empty_media_dir().simplify_path() \
		and path.get_file().begins_with("no_disc")


static func _empty_media_dir() -> String:
	return CoreDownloadManager.default_core_root().path_join("temp")


## A blank image for a machine switched on with an empty slot.
##
## Kept in the libretro temp dir rather than the ROM library: it is not a game,
## nothing should index it, and a player browsing their PlayStation folder must
## never be offered it. One file per extension and track, reused -- it is
## read-only to the core, so two machines can share it.
##
## Returns "" if it could not be written, which the caller must treat as "this
## machine cannot show its BIOS" rather than pressing on with an empty path.
static func empty_media_path(extension: String, track := "") -> String:
	var path := empty_media_file(extension, track)
	if path.is_empty():
		return ""
	var dir := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		push_warning("[BiosBoot] cannot create %s" % dir)
		return ""
	if track == "audio":
		var bin := path.get_basename() + ".bin"
		var silence := PackedByteArray()
		silence.resize(_SILENT_TRACK_SECTORS * _RAW_SECTOR_BYTES)
		silence.fill(0)
		if not _write_once(bin, silence):
			return ""
		var sheet := 'FILE "%s" BINARY\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n' % bin.get_file()
		return path if _write_once(path, sheet.to_utf8_buffer()) else ""
	return path if _write_once(path, PackedByteArray()) else ""


## Write `bytes` to `path` unless a file of that size is already there.
static func _write_once(path: String, bytes: PackedByteArray) -> bool:
	var existing := FileAccess.open(path, FileAccess.READ)
	if existing != null:
		var size := existing.get_length()
		existing.close()
		if size == bytes.size():
			return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[BiosBoot] cannot write %s" % path)
		return false
	f.store_buffer(bytes)
	f.close()
	return true
