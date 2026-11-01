## ForcedCoreOptions — the core options a machine pins for a run.
##
## Some options are not preferences: they are what makes the hardware that
## hardware. A 64DD with its drive switched off has nothing to load a disk into;
## an N64 whose core defaults to "Expansion Pak installed" has 8 MB whether or
## not a player ever placed the pack. Each function here answers one such
## question, and every answer was MEASURED against the core rather than guessed
## — the comments say which probe and what it showed.
##
## Lifted out of RetroSystem, which had grown eight subsystems' vocabularies in
## one class. These decisions need no node: they are questions about a core and
## a machine's description, so they take that description as arguments and this
## file has no scene, no state and no side effects.
##
## RetroSystem.all_forced_options is still the entry point, and merges what the
## model demands on top of these. One place, so the .opt seam and the options
## panel can never disagree about which keys the player is allowed to move.
class_name ForcedCoreOptions
extends RefCounted


## Everything this machine pins for a run, in the order the layers apply.
static func all(core: String, systemid: String, rom_path: String,
		expansions: Array, card_family: String, seated_cards: Array[bool],
		media_path: String) -> Dictionary:
	var out: Dictionary = {}
	out.merge(removable_media(core, card_family, seated_cards), true)
	out.merge(disk_drive(core, systemid, expansions, media_path), true)
	out.merge(expansion_pak(core, expansions), true)
	out.merge(fm_sound_unit(core, systemid, expansions), true)
	out.merge(sonic_knuckles_lock_on(core, systemid, rom_path, expansions), true)
	out.merge(saturn_cart(core, systemid, expansions), true)
	out.merge(saturn_mpeg_card(core, systemid, expansions), true)
	out.merge(bios_pinned(core, systemid, rom_path), true)
	out.merge(declared_frame_rate(core), true)
	out.merge(vmu_sound(core), true)
	out.merge(microphone_hotkey(core, systemid), true)
	out.merge(dolphin_console(core, systemid), true)
	out.merge(game_boy_model(core, systemid), true)
	out.merge(ethernet_adapter(core, systemid, expansions), true)
	return out


## A network adapter in the console: its socket is the frontend's link bus
## (EthernetBus), protocol "ethernet", so an Ethernet cable from it to a hub
## puts the console on a LAN. Both directions, for the Expansion Pak's reason:
## a console with no adapter has no network, whatever a previous run left in the
## option file.
##
## Dolphin's SP1 device: "15" is the Ethernet Link Cable (the fork's
## EXIDeviceType::EthernetLink), "255" nothing. Pinned on the Wii too, which
## shares the one dolphin.opt with the GameCube: a "15" left by a GameCube run
## would otherwise reach a Wii playing a GameCube disc. Read at boot.
##
## The PS2 fork's pcsx2_dev9_eth: "link" is the cable, "disabled" no adapter.
## "enabled" (Sockets, the host's network) is not a piece of hardware and is not
## offered by the room. Read when content loads.
static func ethernet_adapter(core: String, systemid: String, expansions: Array) -> Dictionary:
	if core.begins_with("dolphin") and (systemid == "gc" or systemid == "wii"):
		var bba := systemid == "gc" and expansions.has("gamecube_broadband_adapter")
		return {"dolphin_gc_sp1": "15" if bba else "255"}
	if core == "pcsx2" and systemid == "ps2":
		return {"pcsx2_dev9_eth": "link" if expansions.has("ps2_network_adapter") else "disabled"}
	return {}


## A light gun in a port. Current MAME reads a gun only when `mame_lightgun_mode` says so (its default,
## `none`, ignores a gun on the port: the cabinet's guns "did not work"), and it lists NO light-gun
## device among its controllers, so announcing one does nothing by itself. Pinned for the run while
## any port holds a gun; FinalBurn Neo lists a "Lightgun" device and needs nothing. Measured:
## arcade_load_probe --controllers on both cores.
##
## The older MAME cores name the same choice differently, and each defaults to the MOUSE for a game's
## X-Y input: with a gun that never moves a mouse, the crosshair sat in the middle and every shot went
## there (Quest 3, 2026-10-21; mame2003_plus is the Quest's arcade core). Option names read out of the
## cores' own binaries and then measured with `arcade_load_probe --options` on 2026-10-21: mame2003_plus
## `mame2003-plus_xy_device` (mouse|pointer|lightgun|disabled, default mouse), mame2010
## `mame_current_xy_type` (mouse|lightgun|none, default mouse), mame `mame_lightgun_mode` (none|lightgun|
## touchscreen, default none). mame2003 / mame2003_midway: see GUN_AS_POINTER (not measured with a game).
const LIGHTGUN_OPTION: Dictionary = {
	"mame": {"mame_lightgun_mode": "lightgun"},
	# Current MAME's other builds (the Quest's `mamearcade` is MAME 0.289 and registered the same 28
	# options as `mame` does here; the MESS build shares the source).
	"mamearcade": {"mame_lightgun_mode": "lightgun"},
	"mamemess": {"mame_lightgun_mode": "lightgun"},
	"mame2003_plus": {"mame2003-plus_xy_device": "lightgun"},
	"mame2010": {"mame_current_xy_type": "lightgun"},
	# MAME 2003 has no gun value at all: its X-Y device is mouse | pointer | disabled. The gun is
	# read as a POINTER, which LightGun feeds alongside its own state (gun_feeds_pointer).
	"mame2003": {"mame2003_mouse_device": "pointer"},
	"mame2003_midway": {"mame2003-mouse_device": "pointer"},
}

## The cores that can only read an aimed gun as an absolute POINTER.
const GUN_AS_POINTER: Array[String] = ["mame2003", "mame2003_midway"]


static func lightgun(core: String, has_gun: bool) -> Dictionary:
	if has_gun and LIGHTGUN_OPTION.has(core):
		return (LIGHTGUN_OPTION[core] as Dictionary).duplicate()
	return {}


## Whether a gun on this core's port has to be reported as a pointer too.
static func gun_feeds_pointer(core: String) -> bool:
	return GUN_AS_POINTER.has(core)


## Which Game Boy mGBA is. Left on Autodetect it reads the cartridge, and a
## header that says "Super Game Boy enhanced" (0x146 = 03, which the Game Boy
## Camera's does) boots as a Super Game Boy; `mgba_sgb_borders` defaults ON, so
## the picture comes out as the TV border, 256x224, on a handheld's 160x144
## screen. A handheld is not a Super Game Boy whatever is in it.
##
## The model is pinned where the machine says which one it is. A Game Boy
## Advance keeps Autodetect and loses only the border: the model there would
## recolour every Game Boy cartridge on the core that machine runs by default,
## which is a change to make on its own evidence, not in passing.
## gb_camera_feed_probe reads the picture size back from the core.
##
## Gambatte's model is gambatte_gb_hwmode, which defaults to Auto: a Color
## cartridge in a Game Boy would boot in color. "GB" is the core's FORCE_DMG,
## the machine a Color cartridge actually finds: a dual-mode game (Pokemon Gold)
## plays in four shades, and a Color-only one puts up its own "Game Boy Color
## only" screen. "GBC" is Auto unless the player has a gbc_bios.bin and boots it,
## when it forces the Color's boot ROM even for an original Game Boy game.
##
## A Game Boy Color colors an original Game Boy game itself, from the boot
## ROM's table of per-game palettes: that is gambatte_gb_colorization "GBC". The
## Game Boy keeps it off. Its panel (gameboy_lcd) quantizes brightness into the
## DMG's four greens, which a palette would only muddy. Both are pinned, because
## the two machines share one gambatte.opt and a Color's palette would otherwise
## follow the next cartridge into a Game Boy. gb_model_probe reads both back.
static func game_boy_model(core: String, systemid: String) -> Dictionary:
	if core.begins_with("gambatte"):
		match systemid:
			"gb":
				return {"gambatte_gb_hwmode": "GB", "gambatte_gb_colorization": "disabled"}
			"gbc":
				return {"gambatte_gb_hwmode": "GBC", "gambatte_gb_colorization": "GBC"}
		return {}
	if not core.begins_with("mgba"):
		return {}
	match systemid:
		"gb":
			return {"mgba_gb_model": "Game Boy", "mgba_sgb_borders": "OFF"}
		"gbc":
			return {"mgba_gb_model": "Game Boy Color", "mgba_sgb_borders": "OFF"}
		"gba":
			return {"mgba_sgb_borders": "OFF"}
	return {}


## Which console dolphin is. A disc says so itself, but an empty drive does not,
## and one dolphin.opt serves both machines: without this a GameCube started
## after a Wii would read the Wii's "boot discs through the menu" and boot a Wii
## menu. The fork boots the System Menu from an empty drive only for "wii", and
## honours the menu option only when it is not "gamecube". Pinned on every run,
## not only an empty one, because a disc run reads it too.
static func dolphin_console(core: String, systemid: String) -> Dictionary:
	if not core.begins_with("dolphin"):
		return {}
	if systemid == "wii":
		return {"dolphin_console": "wii"}
	if systemid == "gc":
		return {"dolphin_console": "gamecube"}
	return {}


## The GameCube Microphone's button. Dolphin reads it from the joypad bit this
## option names, on any port; GcMicrophone holds R3, which no GameCube pad sends.
static func microphone_hotkey(core: String, systemid: String) -> Dictionary:
	if core.begins_with("dolphin") and systemid == "gc":
		return {"dolphin_hotkey_activate_microphone": "R3"}
	# The Famicom's Controller II microphone, which RetroXR's build of fceumm
	# reads as player 2's Start. An upstream build never declares the key and
	# OptionsHandler drops one the core did not declare without failing, so the
	# machine simply plays as an NES with a second pad.
	if core.begins_with("fceumm") and systemid == "famicom":
		return {"fceumm_famicom_microphone": "enabled"}
	return {}


## Make the console report an EMPTY slot when no card is seated.
##
## The SAVE_RAM interface cannot express this: it always hands back a 128 KB
## buffer, so an unbacked run still looks like a card — merely a blank one, and
## the game offers to format it instead of saying no card is present.
## pcsx_rearmed's own memcard1 option can, because "none" disables the slot down
## at the SIO level (McdDisable -> no_device), which is what the hardware does.
##
## Read by the core at content load, so it is composed here with the other
## start-time options rather than swapped mid-run. Cores built before the option
## shipped ignore the key harmlessly, so this is safe on an older build.
## `seated_cards` is one entry per slot: whether a card is in it right now.
static func removable_media(core: String, card_family: String,
		seated_cards: Array[bool]) -> Dictionary:
	# The PlayStation FAMILY, not merely any console with card slots. These keys
	# are pcsx_rearmed's own and mean nothing to another console's core, so a
	# GameCube must not write them into a .opt on the strength of having slots.
	if card_family != "playstation" or not core.begins_with("pcsx_rearmed"):
		return {}
	var out: Dictionary = {}
	for slot in 2:
		var seated: bool = slot < seated_cards.size() and seated_cards[slot]
		# "libretro" is what hands the card's bytes to the frontend. Slot 2 goes
		# through a core-specific memory id; the core's default for it is a shared
		# card every game can see and no object in the room accounts for.
		out["pcsx_rearmed_memcard%d" % (slot + 1)] = "libretro" if seated else "none"
		# Whether the card is actually IN the slot, which is a different question
		# from what kind of card the slot holds and the only one that can change
		# while the game runs. Set here too so a machine starts up agreeing with
		# the room: the key is read at load like the others, and _set_card_presence
		# keeps it honest from then on.
		out["pcsx_rearmed_memcard%d_inserted" % (slot + 1)] = \
			"enabled" if seated else "disabled"
	return out


## Any unit whose bay takes 64DD disks: the retail drive or the development unit.
static func _has_disk_drive(expansions: Array) -> bool:
	for id in expansions:
		if ExpansionCatalog.media_of(str(id)) == "n64dd":
			return true
	return false


## The 64DD is a drive bolted under an N64, and parallel_n64 models it behind an
## option: with parallel-n64-64dd-hardware disabled there is no drive and a disk
## has nothing to load into. So this machine pins it on, the way the Virtual Boy
## pins its stereo split -- it is what makes the hardware that hardware, not a
## preference.
##
## Keyed on the systemid as well as the core, and deliberately not added to
## CoreOptionsStore.HARDWARE_PINNED: that table is per key, and the same core
## runs the plain nintendo_64, where the drive really is the player's choice.
static func disk_drive(core: String, systemid: String, expansions: Array,
		media_path: String) -> Dictionary:
	# A 64DD reaches a machine two ways, and the systemid only says one of them.
	# Launching a disk from the library makes a nintendo_64dd machine; bolting
	# the drive under a console leaves the console a nintendo_64 with an
	# expansion, and asking only about the systemid misses it entirely -- which
	# left the assembled machine running with its drive switched off, on the one
	# machine that visibly has one.
	if systemid != "n64dd" and not _has_disk_drive(expansions):
		return {}
	if core == "parallel_n64":
		return {"parallel-n64-64dd-hardware": "enabled"}
	# mupen64plus_next boots a bare disk correctly and then draws nothing at all
	# under GLideN64, which is its default renderer. Measured on the same core,
	# the same disk and the same machine, changing only this option: GLideN64
	# reaches the 64DD IPL logo and goes black and stays black, while parallel
	# and angrylion both reach Mario Artist's title screen. The emulation is
	# fine either way -- the frame counter climbs identically in all three -- so
	# this is a renderer that cannot draw a cartridge-less boot, not a machine
	# that fails to start.
	#
	# parallel rather than angrylion because angrylion is a software rasteriser
	# and this has to run on a headset. Pinned for the same reason the drive
	# above is: with the default the player gets a black screen, and no amount
	# of fiddling elsewhere fixes it.
	#
	# Only while this core is actually being offered Vulkan, which is the
	# default for every core and can be overridden per core in CORES > Manager >
	# FRONTEND. ParaLLEl-RDP is a Vulkan renderer: pinning it on a core the
	# player has moved to GL would turn a black screen into a refused load,
	# which is a worse answer to the same question. Angrylion is the fallback
	# because it needs no API at all -- slow, and still a picture.
	#
	# Only when the cartridge slot is empty, which is the boot GLideN64 cannot
	# draw. With a cartridge in, the same core and the same drive render
	# perfectly on the stock renderer -- measured -- and forcing a different one
	# there would be changing the player's picture for no reason, on a file
	# every nintendo_64 machine shares.
	#
	# Cartridge-less is a fact about what the CORE is handed, not about whether
	# the console's own slot is occupied, and the two come apart here. A machine
	# spawned as a nintendo_64dd holds its disk in that very slot and still boots
	# with no cartridge; an assembled machine keeps the cartridge in the console
	# and the disk in the drive underneath. Reading the slot alone got this
	# backwards for the standalone machine -- the case the pin was written for --
	# and it went black again.
	var cartridge_less := systemid == "n64dd" or media_path.is_empty()
	if core == "mupen64plus_next" and cartridge_less:
		var api := AppPrefs.hw_render_for(core)
		return {"mupen64plus-rdp-plugin": "parallel" if api == "vulkan" else "angrylion"}
	return {}


## The Expansion Pak is a physical RAM module with no media of its own -- unlike
## the 64DD above, there is no launch recipe for it, so this is the only thing
## it does at all.
##
## Both cores were measured (Tools/cores/core_options_probe.gd) rather than
## guessed, and both already emulate WITH the pak installed by default:
## mupen64plus_next's mupen64plus-ForceDisableExtraMem defaults to False (the
## description reads "Disable Expansion Pak", so False means the pak stays in),
## and parallel_n64's parallel-n64-disable_expmem defaults to "enabled" (its own
## description is "Enable Expansion Pak RAM", so "enabled" names the RAM, not
## the disabling). That is why this pins BOTH directions and not only the
## attached one, unlike _disk_drive_options above -- a bare console has to be
## pushed OFF the core's own default, or every Nintendo 64 in the room would
## already have 8 MB whether or not a player ever placed the pack.
static func expansion_pak(core: String, expansions: Array) -> Dictionary:
	var attached := expansions.has("expansion_pak")
	if core == "mupen64plus_next":
		return {"mupen64plus-ForceDisableExtraMem": "False" if attached else "True"}
	if core == "parallel_n64":
		return {"parallel-n64-disable_expmem": "enabled" if attached else "disabled"}
	return {}


## The FM Sound Unit adds a YM2413 chip an export Master System never had.
## genesis_plus_gx_ym2413 (measured, Tools/cores/core_options_probe.gd) defaults
## to "auto", which follows the ROM's own region byte -- a fact about the
## cartridge, not about whether this room's player ever placed the accessory.
## So "auto" is left alone for nothing: pinned "enabled" with the unit on and
## "disabled" with it off, the same both-directions shape as the Expansion Pak
## above and for the same reason.
##
## Gated on systemid rather than only on expansions, unlike the Pak: this
## core also runs the Mega Drive, Game Gear and SG-1000, none of which this key
## means anything for, and expansions is empty on all of them regardless --
## without the gate every one of those machines would be pinned "disabled" too.
static func fm_sound_unit(core: String, systemid: String, expansions: Array) -> Dictionary:
	if systemid != "mastersystem" or core != "genesis_plus_gx":
		return {}
	return {"genesis_plus_gx_ym2413": "enabled" if expansions.has("fm_sound_unit") else "disabled"}


## Sonic & Knuckles' lock-on (the `sonic_knuckles` unit): ON only while a game
## stands in the adapter's own slot, which is when the stack hands the core that
## game rather than the adapter's sk.bin; then genesis_plus_gx maps the S&K ROM
## over it (md_cart.c TYPE_SK). OFF with the slot empty -- S&K locked onto its own
## ROM is not a machine anyone can build -- and OFF on a bare Genesis, for the
## Expansion Pak's reason: the key lives in the one shared .opt, and a value left
## by a lock-on run would make the next plain Genesis load try to lock on.
##
## Genesis only, as fm_sound_unit is Master System only: the same core runs the
## Game Gear, Master System and Sega CD, and this key means nothing to them. Read
## at load, so a game seated while the console runs plays on its next power-on.
static func sonic_knuckles_lock_on(core: String, systemid: String, rom_path: String,
		expansions: Array) -> Dictionary:
	if systemid != "genesis" or core != "genesis_plus_gx":
		return {}
	var on := false
	if expansions.has("sonic_knuckles") and not rom_path.is_empty():
		var own := ExpansionCatalog.firmware_rom_path("sonic_knuckles")
		on = own.is_empty() or rom_path.simplify_path() != own.simplify_path()
	return {"genesis_plus_gx_lock_on": "sonic & knuckles" if on else "disabled"}


## What is in the cartridge slot behind a Saturn's lid, by unit id, as each core
## names it. One slot, so at most one of these is ever seated; "" is the empty
## slot. Read at source, not guessed: Beetle Saturn's values are the ones its
## libretro_core_options.h declares for beetle_saturn_cart, YabaSanshiro's the
## strings its libretro.c compares yabasanshiro_addon_cart against.
##
## YabaSanshiro has RAM cartridges and nothing else -- no backup cartridge, no ROM
## cartridges -- so those leave its slot empty. The two ROM cartridges never reach
## it anyway: their BOOT rows run Beetle. "none" is not in the list YabaSanshiro
## DECLARES (that is "4M_extended_ram|1M_extended_ram") but it is a branch its
## code takes, and libretro-godot hands a pinned value over unchecked.
const SATURN_CARTS := {
	"": {"beetle": "None", "yabasanshiro": "none"},
	"sega_saturn_ram_cart": {"beetle": "Backup Memory", "yabasanshiro": "none"},
	"sega_saturn_extram_1m": {"beetle": "Extended RAM (1MB)", "yabasanshiro": "1M_extended_ram"},
	"sega_saturn_extram_4m": {"beetle": "Extended RAM (4MB)", "yabasanshiro": "4M_extended_ram"},
	"sega_saturn_kof95_rom": {"beetle": "The King of Fighters '95", "yabasanshiro": "none"},
	"sega_saturn_ultraman_rom": {"beetle": "Ultraman: Hikari no Kyojin Densetsu", "yabasanshiro": "none"},
}


## Pinned in both directions, the Expansion Pak's shape and for its reason: Beetle
## left on Auto Detect fits a cartridge from its own game database (a Backup RAM
## Cartridge for anything it does not list), and YabaSanshiro defaults to the 4 MB
## cartridge, so without the empty pin every Saturn in the room would have a
## cartridge nobody put in it -- on a Quest, a 4 MB one, which Beetle's database
## says two of the 1 MB games refuse.
static func saturn_cart(core: String, systemid: String, expansions: Array) -> Dictionary:
	if systemid != "saturn":
		return {}
	var fitted := ""
	for id: Variant in expansions:
		if SATURN_CARTS.has(str(id)) and not str(id).is_empty():
			fitted = str(id)
			break
	var values: Dictionary = SATURN_CARTS[fitted]
	if core.begins_with("mednafen_saturn"):
		return {"beetle_saturn_cart": values["beetle"]}
	if core == "yabasanshiro":
		return {"yabasanshiro_addon_cart": values["yabasanshiro"]}
	return {}


## The Video CD Card in the slot in a Saturn's back. Beetle's
## beetle_saturn_mpeg_card defaults to disabled, so this pins ON what a player
## seated -- and OFF what they did not, the same both-ways shape as the slot
## above, so an option somebody turned on in a menu is not a card nobody put in.
## Restart-time in the core, which a pin always is: it is written before boot.
## Netplay pins it off for a session (NetplayCores), whatever is seated.
static func saturn_mpeg_card(core: String, systemid: String, expansions: Array) -> Dictionary:
	if systemid != "saturn" or not core.begins_with("mednafen_saturn"):
		return {}
	return {"beetle_saturn_mpeg_card":
		"enabled" if expansions.has("sega_saturn_vcd_card") else "disabled"}


## The measured options that make this machine show its own boot screen, unless
## the player has taken them back in OPTIONS > Systems.
##
## Which half of the row applies is decided from what is in the slot, not from
## the table: an empty slot reaches the BIOS by different keys from a loaded
## game, and reading it from rom_path means the options panel shows the pin that
## matches what the machine would actually start with right now.
##
## Pinned rather than seeded because a pin is the only kind of write that beats a
## saved value. A core serialises its whole option set on shutdown, so one run
## that left mgba_skip_bios "ON" behind would otherwise skip the BIOS for ever.
static func bios_pinned(core: String, systemid: String, rom_path: String) -> Dictionary:
	if AppPrefs.bios_boot_override:
		return {}
	var empty := rom_path.is_empty() and BiosBoot.can_boot_empty(core, systemid)
	return BiosBoot.pinned_options(core, systemid, empty)

## Make flycast say when a game's frame rate changes, because with threaded
## rendering on it decides how much time a retro_run covers.
##
## MEASURED against Goin' Quackers, which runs at double speed without this.
## flycast's retro_run, under config::ThreadedRendering, is
##
##     for (int i = 0; i < 5 && is_dupe; i++)
##         is_dupe = !emu.render();
##
## — it keeps emulating until a frame comes out that is not a duplicate. A game
## locked to 30 fps renders every OTHER vblank, so one call advances two of them.
## Call that sixty times a second, as a core declaring 59.94 invites, and the
## machine lives 120 vblanks per second. Twice as fast, and only in the parts
## that are locked below 60: Goin' Quackers' menus and gameplay run at double
## speed while its FMV, which does render every vblank, is perfect.
##
## The option is how the core tells the frontend, through SET_SYSTEM_AV_INFO,
## that the rate has changed. Measured with Tools/cores/pacing_probe: at 35 s
## the core announced 29.972650 and the call rate fell from 60.00/s to 30.00/s
## inside a second, because Wrapper stores the new fps and the emulation loop
## re-reads it every pass. With the option off that announcement never comes and
## the call rate stays pinned at the stale 59.9453.
##
## Forced rather than recommended, and the trade is deliberate. flycast's own
## text says to disable it for games whose frame rate is UNLOCKED (it names Ecco
## the Dolphin and Unreal Tournament), where the rate wobbles and the
## renegotiation wobbles with it. That costs smoothness. Leaving it off costs
## correct speed, on every locked-30 game there is, and a player cannot be
## expected to know that a menu running at double speed is a frontend option.
## The core ignores the key when Auto Skip Frame is on, which is its own
## documented interaction and harmless here.
static func declared_frame_rate(core: String) -> Dictionary:
	if not core.begins_with("flycast"):
		return {}
	return {"reicast_detect_vsync_swap_interval": "enabled"}


## flycast sounds VMU beeps only with this on. Our fork hands each card's beep to
## the controller audio interface, so it plays from the card.
static func vmu_sound(core: String) -> Dictionary:
	if not core.begins_with("flycast"):
		return {}
	return {"reicast_vmu_sound": "enabled"}
