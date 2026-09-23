## CoreSources — cores retroXR ships itself, instead of taking from the buildbot.
##
## Almost every core comes from buildbot.libretro.com and needs nothing here. A
## core lands in this table when we maintain a fork of it, because then the
## buildbot's build is not the one we want the player to have.
##
## Eighteen of them, and most are here for the same reason: this room has cables
## in it, and libretro has nowhere to put the far end of one. Dolphin, mGBA,
## gambatte, pcsx_rearmed, Genesis Plus GX, the four Beetles (WonderSwan, Lynx,
## NeoPop, Saturn), VeMUlator and Virtual Jaguar each reach a link bus the
## frontend hosts. The netplay forks (fbneo and several of those) are here for
## savestates exact enough to roll back on.
##
## Every fork publishes Windows, Android, Linux x86_64 and macOS arm64/x86_64
## unless its row says otherwise.
##
## Two more are hardware the core could always emulate and no frontend could
## ever ask it to, because the libretro glue never surfaced it: the
## Satellaview's 8M Memory Pack in snes9x, and a cartridge-less 64DD disk in
## mupen64plus_next. (Azahar's stereo 3D was a third until upstream merged it
## in 2126.1; the buildbot's build now carries it, so it is back on that.)
## Play! is the odd one, and is here for two crashes that stop the buildbot's
## build running on a Quest at all. xemu is odder still: not a fork of a libretro
## core but a port nobody else builds, so the buildbot has no row for it to
## replace — see is_released and CoreDownloadManager._list_own_core.
##
## Dolphin is the one to read first if you want the shape of it. The buildbot
## build cannot do Wiimote IR passthrough — the frontend hands the emulated
## camera its real view of the sensor bar rather than a cursor position, and the
## option that switches it on only exists in our fork. Without it a Wii Remote in
## this room points by a constant fitted per game; with it, it points where you
## point.
##
## Each entry's comment says what its fork adds, and under which licence.
##
## Every binary is published on the fork it was built from, which is also what
## keeps it honest: four of the six are GPL, so the source for a distributed
## binary has to be there beside it, and a release tag on the source repo is the
## simplest arrangement that stays true. mGBA (MPL-2.0) and Play! (BSD) carry no
## such obligation and are published the same way anyway — it is the only way
## anyone can tell what they are running.
##
## Each fork builds its own release from that tag, so what ships is what the tag
## says. See .github/workflows/retroxr-release.yml on any of them.
##
## Deliberately keyed by the SAME core_name the buildbot uses ("dolphin", not
## "dolphin_retroxr"). The frontend derives system/<core> and save/<core> from
## that name, so a new one would strand the Sys folder, every GameCube memory
## card and the whole Wii NAND. Ours replaces the stock build in place and
## inherits all of it.
##
## Which is why mupen64plus_next is TWO entries. The buildbot publishes plain
## mupen64plus_next for Windows and only the _gles2 and _gles3 variants for
## Android, so one core has two names depending on where the player is standing,
## and matching them exactly is the whole point of the paragraph above. Both
## entries name the same repository and the same tag; they differ only in which
## platform they carry an asset for.
class_name CoreSources
extends RefCounted


const SOURCES := {
	"dolphin": {
		"repo":  "RetroXR/dolphin",
		# The release this app was built knowing about. NOT part of the download
		# URL — see base_url. It is only the version to show when GitHub cannot be
		# reached, so an offline player still sees something truthful rather than
		# a blank.
		"known_tag": "retroxr-dolphin-libretro-v13",
		"label": "Dolphin (retroXR build)",
		# Per platform, because we only publish what we build. A platform absent
		# here is not an error — the manager falls back to the buildbot for it.
		# Since v13 Dolphin publishes all four: Windows, Android, Linux x86_64,
		# and macOS as one thin dylib per architecture (see asset_for).
		"assets": {
			"Windows": "dolphin_libretro.dll.zip",
			"Android": "dolphin_libretro_android.so.zip",
			"Linux":   "dolphin_libretro.so.zip",
			"macOS":   "dolphin_libretro_{arch}.dylib.zip",
		},
	},
	# mGBA, for the half of the link cable that is not the console.
	#
	# mGBA has carried its own lockstep coordinator for years and it was simply
	# unreachable: nothing in libretro can express a cable, and every core
	# instance is loaded from its own copy of the library, so two Game Boy
	# Advances in one process share no globals and have exactly one thing in
	# common, which is the frontend. Our build talks to a link bus the frontend
	# hosts instead, and that is what makes two handhelds in one room able to
	# play together, single-cartridge play work, and a GameCube lead reach a
	# handheld at all.
	#
	# Unlike Dolphin this is not a GPL obligation -- mGBA is MPL-2.0 -- but the
	# source sits on the tag beside the binary for the same practical reason: it
	# is the only way anyone can tell what they are running.
	#
	# The Android asset DOES carry the "_android" infix, unlike azahar's. Worth
	# saying because the two sit next to each other in this file and the wrong
	# name here fails silently, as a core that simply never downloads.
	"mgba": {
		"repo":  "RetroXR/mgba",
		"known_tag": "retroxr-mgba-libretro-v7",
		"label": "mGBA (retroXR build)",
		"assets": {
			"Windows": "mgba_libretro.dll.zip",
			"Android": "mgba_libretro_android.so.zip",
			"Linux":   "mgba_libretro.so.zip",
			"macOS":   "mgba_libretro_{arch}.dylib.zip",
		},
	},
	# Play!, the PS2 core. Two of the three fixes are the difference between a
	# core that runs on Quest and one that does not: the buildbot's Android build
	# points its data directory at /sdcard, which scoped storage will not let it
	# create, and the exception that follows escapes retro_init and aborts the
	# whole frontend. Past that, every thread the core starts asked to attach to
	# a JavaVM that a dlopen'd library never receives, and the assert guarding it
	# is compiled out of a release build. The third fix is visible on both
	# platforms — sprites are snapped to whole pixels, closing the column of
	# black seams the GS's corner sampling leaves down an OpenGL-rendered frame.
	#
	# Play! is BSD, so unlike Dolphin the binary carries no source obligation;
	# the fork is where it is built from all the same.
	"play": {
		"repo":  "RetroXR/Play-",
		"known_tag": "retroxr-play-libretro-v2",
		"label": "Play! (retroXR build)",
		"assets": {
			"Windows": "play_libretro.dll.zip",
			"Android": "play_libretro_android.so.zip",
			"Linux":   "play_libretro.so.zip",
			"macOS":   "play_libretro_{arch}.dylib.zip",
		},
	},
	# LRPS2, the PCSX2-derived PS2 core -- the one the PS2 tile recommends. What
	# the fork adds is the console's i.LINK port (pcsx2/FW.cpp): a real IEEE 1394
	# bus on the frontend's link interface, protocol `ps2-ilink-1394`, behind the
	# pcsx2_ilink option. It is what the room's i.LINK cable and six-port hub
	# drive -- Gran Turismo 3's i.LINK Battle, its three-screen Broadcast set-up
	# included, and Time Crisis II's cooperative mode (docs/dev/ps2-ilink.md). The
	# buildbot's build has no link port at all, so a cable to it joins nothing.
	# The fork also carries the native AArch64 port that makes an Android build
	# possible.
	#
	# GPL-3.0, so the tag beside the binary is the source obligation, as Dolphin's.
	"pcsx2": {
		"repo":  "RetroXR/ps2",
		"known_tag": "retroxr-pcsx2-libretro-v1",
		"label": "LRPS2 (retroXR build)",
		"assets": {
			"Windows": "pcsx2_libretro.dll.zip",
			"Android": "pcsx2_libretro_android.so.zip",
			"Linux":   "pcsx2_libretro.so.zip",
			"macOS":   "pcsx2_libretro_{arch}.dylib.zip",
		},
	},
	# gambatte, the other end of every Game Boy cable in the room.
	#
	# The Game Boy's serial port is two wires and a clock, and libretro has never
	# had anywhere to put the far end of them. Our build speaks `gb-sio-1` over a
	# bus the frontend hosts, and gambatte_gb_link_mode gains a fourth value,
	# "Link Cable", which is the DEFAULT — with no bus, or a bus with nothing
	# cabled to it, the driver hands back the 0xFF of an open line, which is
	# exactly what the port does on the stock build. So the default costs an
	# uncabled player nothing.
	#
	# Deliberately the same wire format mGBA's Game Boy driver uses, which is
	# what lets a gambatte Game Boy and an mGBA one join the SAME cable. The two
	# drivers have to stay field-for-field in step; a field one latches and the
	# other does not is invisible from either side alone.
	#
	# It also carries two accuracy fixes the cable work uncovered, neither of
	# them about cables: the progressive serial shift took its bits off the top
	# of the incoming byte rather than from where the transfer had reached, and
	# a savestate was missing the blit event and blank-LCD flag, which slipped a
	# frame on reload with the LCD off. That second one is what kept gambatte out
	# of rollback netplay.
	#
	# gambatte is GPLv2, so the source obligation is Dolphin's, not mGBA's — the
	# tag beside the binary is what meets it.
	"gambatte": {
		"repo":  "RetroXR/gambatte-libretro",
		"known_tag": "retroxr-gambatte-libretro-v3",
		"label": "gambatte (retroXR build)",
		"assets": {
			"Windows": "gambatte_libretro.dll.zip",
			"Android": "gambatte_libretro_android.so.zip",
			"Linux":   "gambatte_libretro.so.zip",
			"macOS":   "gambatte_libretro_{arch}.dylib.zip",
		},
	},
	# genesis_plus_gx, for the Game Gear's Gear-to-Gear Cable.
	#
	# The stock core's EXT port has no far end. Our build puts it on the
	# frontend's link bus as `gg-ext-1` (the RetroArch#19454 interface): the UART
	# delivers a byte ten bit times after it is written, and the parallel pins
	# cross the way the real cable wires them. Uncabled it behaves exactly as the
	# stock core does, so there is no option to turn it on. The same core runs the
	# Mega Drive, Master System and Sega CD rows, which also get the fork's one
	# other change: a disabled Sega CD RAM cartridge reads as absent.
	"genesis_plus_gx": {
		"repo":  "RetroXR/Genesis-Plus-GX",
		"known_tag": "retroxr-genesis_plus_gx-libretro-v3",
		"label": "Genesis Plus GX (retroXR build)",
		"assets": {
			"Windows": "genesis_plus_gx_libretro.dll.zip",
			"Android": "genesis_plus_gx_libretro_android.so.zip",
			"Linux":   "genesis_plus_gx_libretro.so.zip",
			"macOS":   "genesis_plus_gx_libretro_{arch}.dylib.zip",
		},
	},
	# mednafen_wswan, for the WonderSwan's Communication Cable.
	#
	# The stock core's serial port completes every byte into thin air and never
	# receives one. Our build puts the UART on the frontend's link bus as
	# `ws-sio-1` (the RetroArch#19454 interface): a byte is stamped with the tick
	# its stop bit leaves, 3200 CPU cycles at 9600 baud and 800 at 38400, and the
	# far unit latches it when its own clock gets there. Uncabled it behaves
	# exactly as the stock core does, so there is no option to turn it on.
	#
	# A WonderSwan and a WonderSwan Color are the same core and the same wire.
	"mednafen_wswan": {
		"repo":  "RetroXR/beetle-wswan-libretro",
		"known_tag": "retroxr-mednafen_wswan-libretro-v3",
		"label": "Beetle WonderSwan (retroXR build)",
		"assets": {
			"Windows": "mednafen_wswan_libretro.dll.zip",
			"Android": "mednafen_wswan_libretro_android.so.zip",
			"Linux":   "mednafen_wswan_libretro.so.zip",
			"macOS":   "mednafen_wswan_libretro_{arch}.dylib.zip",
		},
	},
	# mednafen_lynx, for ComLynx.
	#
	# Stock Mikey had a transmit hook nothing was attached to. Our build puts the
	# UART on the frontend's link bus as `comlynx-1`, modelled as the one
	# open-collector wire it is: a byte is broadcast when written, stamped with
	# the tick its stop bit leaves, and every unit -- the sender included --
	# hears the same bytes in the same order, overlapping frames ANDed. Up to
	# eight chain, as on the real cable. Uncabled it runs as the stock core does.
	# docs/dev/lynx-link.md.
	"mednafen_lynx": {
		"repo":  "RetroXR/beetle-lynx-libretro",
		"known_tag": "retroxr-mednafen_lynx-libretro-v1",
		"label": "Beetle Lynx (retroXR build)",
		"assets": {
			"Windows": "mednafen_lynx_libretro.dll.zip",
			"Android": "mednafen_lynx_libretro_android.so.zip",
			"Linux":   "mednafen_lynx_libretro.so.zip",
			"macOS":   "mednafen_lynx_libretro_{arch}.dylib.zip",
		},
	},
	# mednafen_ngp, for the SNK link cable.
	#
	# NeoPop stubbed its comms hooks, so a Neo Geo Pocket never saw the other end
	# of a cable. Our build puts SIO0 on the frontend's link bus as `ngp-sio-1`
	# at the 6.144 MHz CPU clock, bytes paced at 19200 baud, the /RTS-/CTS pair
	# carried as its own message, and NeoPop's swapped INTRX0/INTTX0 put right
	# (KOF R-1/R-2 and SNK vs. Capcom run their own serial handlers and never
	# linked without it). Uncabled it runs as the stock core does.
	# docs/dev/ngp-link.md.
	"mednafen_ngp": {
		"repo":  "RetroXR/beetle-ngp-libretro",
		"known_tag": "retroxr-mednafen_ngp-libretro-v2",
		"label": "Beetle NeoPop (retroXR build)",
		"assets": {
			"Windows": "mednafen_ngp_libretro.dll.zip",
			"Android": "mednafen_ngp_libretro_android.so.zip",
			"Linux":   "mednafen_ngp_libretro.so.zip",
			"macOS":   "mednafen_ngp_libretro_{arch}.dylib.zip",
		},
	},
	# pcsx_rearmed, for the PlayStation's serial port.
	#
	# SIO1 — the port at 1F801050h that the official Link Cable plugs into — had
	# never been emulated at all: sio1ReadStat16 returned a bare 0xa0 and there
	# was nothing behind it. Our build implements the port and speaks `psx-sio-1`
	# over the frontend's bus.
	#
	# With no bus the port still answers 0xa0, which is what every existing
	# session sees, and that matters more than it sounds: it is what stops
	# Armored Core and Formula 1 misdetecting a cable that is not there.
	# pcsx_rearmed_link_cable is on by default and is not restart-time.
	#
	# pcsx_rearmed is GPLv2, so the source has to sit on the tag beside the
	# binary — same arrangement as Dolphin and gambatte.
	"pcsx_rearmed": {
		"repo":  "RetroXR/pcsx_rearmed",
		"known_tag": "retroxr-pcsx-rearmed-libretro-v4",
		"label": "PCSX-ReARMed (retroXR build)",
		"assets": {
			"Windows": "pcsx_rearmed_libretro.dll.zip",
			"Android": "pcsx_rearmed_libretro_android.so.zip",
			"Linux":   "pcsx_rearmed_libretro.so.zip",
			"macOS":   "pcsx_rearmed_libretro_{arch}.dylib.zip",
		},
	},
	# Beetle Saturn, for the Saturn Link Cable.
	#
	# Mednafen had never emulated the SH-2's serial port -- the SCI behind the
	# Communication Connector -- so a cable had nothing to plug into. Our build
	# implements it (and the DMA a port can pace, which Daytona USA CE sends its
	# packets with) and speaks `saturn-sci-1` over the frontend's bus, joining
	# only the slave SH-2's lines: crossing the master's hangs both consoles in
	# the boot library's dev-host probe. beetle_saturn_link_cable is on by
	# default and not restart-time; off is the stock core.
	#
	# Beetle Saturn is GPLv2, so the source for these binaries sits on the tag.
	"mednafen_saturn": {
		"repo":  "RetroXR/beetle-saturn-libretro",
		"known_tag": "retroxr-beetle-saturn-libretro-v2",
		"label": "Beetle Saturn (retroXR build)",
		"assets": {
			"Windows": "mednafen_saturn_libretro.dll.zip",
			"Android": "mednafen_saturn_libretro_android.so.zip",
			"Linux":   "mednafen_saturn_libretro.so.zip",
			"macOS":   "mednafen_saturn_libretro_{arch}.dylib.zip",
		},
	},
	# snes9x, for the Satellaview's 8M Memory Pack.
	#
	# The BS-X shell has always run on this core; what it had nowhere to put was
	# the 1 MB of removable flash a download is stored in. There was no memory id
	# for the pack, it was absent from the savestate, and S9xResetBSX erased it to
	# 0x00 — where a flash write is an AND, so every byte written to it was
	# discarded while the fixed 0x80 status register reported success. A download
	# hung rather than failed.
	#
	# Our build gives the pack its own id, restores it after the reset that ends
	# a load, advertises the `bsx` subsystem so a translated shell can be paired
	# with a pack, tells the shell when the slot is EMPTY — which it reports in
	# its own words rather than ours — and publishes the front-panel ACCESS lamp
	# through the LED interface.
	#
	# One fix in it is not about the Satellaview: g_rom_dir was set only in
	# retro_load_game, so every subsystem load ran with it empty and each path
	# built from it resolved against a drive root. That is the Sufami Turbo's
	# beside-the-cartridge STBIOS.bin lookup as much as the BS-X's stream files.
	#
	# snes9x is non-commercial rather than GPL, so the tag beside the binary is
	# not an obligation here; it is where the build comes from all the same.
	# VeMUlator, so the VMU can be a machine rather than only a card.
	#
	# The buildbot's build cannot be unloaded. VE_VMS_FLASH::flashWriter is the
	# one member its constructor never initialises, and the destructor closes it
	# behind a guard that therefore tests garbage — and retro_unload_game calls
	# reset(), which builds a FRESH flash object, so even a session that opened a
	# real writer dies on the way out. Powering a minigame down took the whole app
	# with it, every time.
	#
	# Its extension check also took the FIRST dot in the path. On Android that is
	# inside the package name, so nothing matched, no ROM was loaded, and the CPU
	# was started anyway. A path with no dot handed NULL to strcmp.
	#
	# v2: each XRAM bank is 0x7C bytes, but every access adds the game's STAD to
	# the index and reaches up to 0xFF past the end. Chao Adventure 2 sets STAD
	# and writes there constantly, so the heap was corrupt by the time a stop
	# freed it, and stopping the game crashed.
	#
	# v4: v3's timer rework reaches the speaker only through P17, and the HLE
	# boot never set port 1 as the BIOS leaves it, so with no BIOS installed
	# every game was silent. The HLE now sets P1FCR/P1DDR the BIOS's way.
	#
	# VeMUlator is GPLv3, so the source for these binaries sits on the tag.
	"vemulator": {
		"repo":  "RetroXR/vemulator-libretro",
		"known_tag": "retroxr-vemulator-libretro-v4",
		"label": "VeMUlator (retroXR build)",
		"assets": {
			"Windows": "vemulator_libretro.dll.zip",
			"Android": "vemulator_libretro_android.so.zip",
			"Linux":   "vemulator_libretro.so.zip",
			"macOS":   "vemulator_libretro_{arch}.dylib.zip",
		},
	},
	# flycast, so a VMU's screen can be on the VMU.
	#
	# Stock flycast has no second video output. Its only way of showing a VMU
	# screen is to composite the 48 x 32 panel into the finished frame at a
	# corner, so a frontend that wants that screen on the card in the room has to
	# crop it back out — and the game's pixels underneath it are gone before the
	# frame is ever handed over. Our build hands the panel over through the
	# controller display interface instead, and each card's beep through the
	# controller audio interface.
	#
	# It also carries the reason flycast has never run on a Quest. posix_vmem.cpp
	# asks for ASharedMemory_create and falls back to /dev/ashmem when the symbol
	# is null; Android 11 took that device away from apps, and the libretro build
	# linked no libandroid, so the symbol was ALWAYS null. nvmem was disabled, the
	# dynarec's fastmem had nothing behind it, and the core died one frame in.
	# Measured on a Quest 3: dead at frame 1 before, 1375 frames at 60 fps after.
	#
	# flycast is GPLv2, so the source for these binaries sits on the tag.
	"flycast": {
		"repo":  "RetroXR/flycast",
		"known_tag": "retroxr-flycast-libretro-v4",
		"label": "Flycast (retroXR build)",
		"assets": {
			"Windows": "flycast_libretro.dll.zip",
			"Android": "flycast_libretro_android.so.zip",
			"Linux":   "flycast_libretro.so.zip",
			"macOS":   "flycast_libretro_{arch}.dylib.zip",
		},
	},
	"snes9x": {
		"repo":  "RetroXR/snes9x",
		"known_tag": "retroxr-snes9x-libretro-v2",
		"label": "Snes9x (retroXR build)",
		"assets": {
			"Windows": "snes9x_libretro.dll.zip",
			"Android": "snes9x_libretro_android.so.zip",
			"Linux":   "snes9x_libretro.so.zip",
			"macOS":   "snes9x_libretro_{arch}.dylib.zip",
		},
	},
	# FCEUmm, for the microphone in a Famicom's second controller.
	#
	# The Controller II microphone is a one-bit threshold detector at $4016 bit 2,
	# and FCEUmm had no microphone at all. Nestopia and Mesen put theirs on port
	# 0's L3, which this core already gives to A+B. Our build puts it on player
	# 2's Start instead -- a button a Controller II does not have -- behind
	# fceumm_famicom_microphone: the core toggles the bit on every $4016 read
	# while the frontend holds it, which is the flicker games look for, nullifies
	# Start at $4017, and keeps the bit's phase in the savestate.
	#
	# This is the Android default NES core and the only netplay-verified one, so
	# the fork has to stay a drop-in: with the option off it is the stock core.
	#
	# FCEUmm is GPLv2, so the source for these binaries sits on the tag.
	"fceumm": {
		"repo":  "RetroXR/libretro-fceumm",
		"known_tag": "retroxr-fceumm-libretro-v2",
		"label": "FCEUmm (retroXR build)",
		"assets": {
			"Windows": "fceumm_libretro.dll.zip",
			"Android": "fceumm_libretro_android.so.zip",
			"Linux":   "fceumm_libretro.so.zip",
			"macOS":   "fceumm_libretro_{arch}.dylib.zip",
		},
	},
	# mupen64plus_next, for a 64DD disk with no cartridge behind it.
	#
	# Mario Artist and Kyojin no Doshin shipped on a disk alone, and this core
	# could always boot one — none of it was reachable. emu_step_load_data()
	# issued M64CMD_ROM_OPEN unconditionally, so is_valid_rom() rejected a disk
	# and M64CMD_DISK_OPEN was never sent. Our build detects a disk at load,
	# supplies the media loader's get_dd_disk, and closes the disk path with
	# DISK_CLOSE rather than a ROM_CLOSE the core refuses.
	#
	# Windows only, because the buildbot publishes no Android build under this
	# name — see mupen64plus_next_gles3 below, which is the same fork and the
	# same tag.
	#
	# mupen64plus is GPLv2, so the source has to sit on the tag beside the
	# binary — same arrangement as Dolphin, gambatte and pcsx_rearmed.
	"mupen64plus_next": {
		"repo":  "RetroXR/mupen64plus-libretro-nx",
		"known_tag": "retroxr-mupen64plus-next-libretro-v5",
		"label": "Mupen64Plus-Next (retroXR build)",
		"assets": {
			"Windows": "mupen64plus_next_libretro.dll.zip",
			"Linux":   "mupen64plus_next_libretro.so.zip",
			"macOS":   "mupen64plus_next_libretro_{arch}.dylib.zip",
		},
	},
	# The same core and the same tag, under the name the buildbot gives its
	# Android build. Not a second fork: the buildbot ships mupen64plus_next for
	# Windows and mupen64plus_next_gles2 / _gles3 for Android, and CoreSources is
	# keyed by the buildbot's name so ours replaces the stock build in place.
	#
	# gles3 and not gles2 because gles2 does not work here. Measured on a Quest:
	# it runs at full speed and never draws a pixel, while the gles3 build of the
	# same core renders the same ROM correctly. It is also the build
	# CoreRecommendations already names for nintendo_64 on Android.
	"mupen64plus_next_gles3": {
		"repo":  "RetroXR/mupen64plus-libretro-nx",
		"known_tag": "retroxr-mupen64plus-next-libretro-v5",
		"label": "Mupen64Plus-Next GLES3 (retroXR build)",
		"assets": {
			"Android": "mupen64plus_next_gles3_libretro_android.so.zip",
		},
	},
	# xemu, the original Xbox. The one entry here that is not a fork of a libretro
	# core: upstream xemu has no libretro port, and the vendored xemu .info
	# describes someone's older attempt that the buildbot never built. Ours is a
	# new frontend (ui/libretro) over the whole machine, with the NV2A on Vulkan so
	# it runs on a Quest, handing over a software framebuffer.
	#
	# It is the one entry the BUILDBOT HAS NO ROW FOR, so there is nothing for
	# _apply_own_sources to override: CoreDownloadManager lists an own-only core
	# itself (_list_own_core) — from known_tag at once, and from the version probe
	# when this app was built knowing no release. That second case is how this
	# entry began: it carried a `branch` and an EMPTY known_tag until the first
	# release was cut, nothing offered a download that could only 404, and the
	# release then reached installed copies with no app build. `branch` stays
	# because it is still true — the tags sit on it — and is_released is what
	# tells the two states apart for the next core that starts that way.
	#
	# v3 is 777f199ed5: no emulator change, but the first release built by CI
	# (.github/workflows/retroxr-release.yml; v1 and v2 were built by hand) and
	# the first Linux x86_64 build, its dependencies linked in statically.
	#
	# v2 is bcced37b6d. Checked 2026-09-20 through the URLs this file composes:
	# /releases/latest names the tag, both assets answer 200, each zip holds the
	# bare library at its root, and the bytes served are the bytes built. The
	# release also carries two LICENSE-*.txt assets, which nothing here asks for
	# by name.
	#
	# v2 is four lines of ui/libretro/core.c over v1: retro_load_game reads an
	# EMPTY content path as no content at all. That is what the app sends on a
	# no_content start -- system.gd unsets the NULL convention the line after
	# StartContent, so the reset wins the race and a ZEROED struct goes, and a
	# zeroed one carries an empty path. v1 took it on a cold start, where the DVD
	# path is empty anyway, but with the machine already running it asked QEMU to
	# insert a medium with no name.
	#
	# Measured on the v2 Windows build before publishing: an empty tray boots the
	# stock disk's placeholder at 452 lit pixels of 307,200 in a band at
	# x 25..280, y 25..31, the disk is held against a write handle, and the same
	# frame comes back after a stop and a second power-on in one process. Those
	# are v1's numbers exactly, which is how this says nothing else moved.
	#
	# xemu is GPLv2, so the tag beside the binary is an obligation, as Dolphin's is.
	# virtualjaguar, for JagLink.
	#
	# The Jaguar's JagLink/CatBox cable is JERRY's UART out of the DSP port. Our
	# build carries it over the frontend's link bus as `jag-uart-1`: a character
	# is posted when it starts shifting out, stamped at its stop bit, and lands
	# in the partner's receive register at that tick. The core's
	# virtualjaguar_netlink option defaults to `auto`, which takes the bus
	# whenever the frontend offers one; with none it is the upstream core.
	# docs/dev/jag-link.md. GPLv3.
	"virtualjaguar": {
		"repo":  "RetroXR/virtualjaguar-libretro",
		"known_tag": "retroxr-virtualjaguar-libretro-v1",
		"label": "Virtual Jaguar (retroXR build)",
		"assets": {
			"Windows": "virtualjaguar_libretro.dll.zip",
			"Android": "virtualjaguar_libretro_android.so.zip",
			"Linux":   "virtualjaguar_libretro.so.zip",
			"macOS":   "virtualjaguar_libretro_{arch}.dylib.zip",
		},
	},
	# fbneo, so the Neo Geo can roll back.
	#
	# Stock fbneo desyncs on the first rewind: a YM2610 restore lost or recomputed
	# the ADPCM-A levels and registers, the envelope and LFO counters, Delta-T's
	# now_data and the resampler position. Our build saves all of it, and adds
	# fbneo-netplay-deterministic, which pins the uPD4990A clock and the random
	# seed and turns hiscores off. NetplayCores["fbneo"] sets rollback_needs_pins,
	# so a build that does not declare that option still gets lockstep.
	#
	# FBNeo's licence is non-commercial; the tag beside the binary is its source.
	"fbneo": {
		"repo":  "RetroXR/FBNeo",
		"known_tag": "retroxr-fbneo-libretro-v1",
		"label": "FBNeo (retroXR build)",
		"assets": {
			"Windows": "fbneo_libretro.dll.zip",
			"Android": "fbneo_libretro_android.so.zip",
			"Linux":   "fbneo_libretro.so.zip",
			"macOS":   "fbneo_libretro_{arch}.dylib.zip",
		},
	},
	"xemu": {
		"repo":  "RetroXR/xemu",
		"branch": "retroxr",
		"known_tag": "retroxr-xemu-libretro-v3",
		"label": "xemu (retroXR build)",
		# No macOS: the OpenGL renderer makes its context through an SDL window on
		# the core's own thread, and Cocoa only creates windows on the main one.
		"assets": {
			"Windows": "xemu_libretro.dll.zip",
			"Android": "xemu_libretro_android.so.zip",
			"Linux":   "xemu_libretro.so.zip",
		},
	},
}


## True when we publish this core ourselves AND have a build for this platform.
## Both halves matter: the Linux answer is "we know this core, but not here".
static func has(core_name: String) -> bool:
	return not asset_for(core_name).is_empty()


## The release asset filename for this platform, or "" when we do not build one.
##
## A macOS asset names its architecture, "{arch}" standing for arm64 or x86_64:
## each fork publishes one thin dylib per architecture, as the buildbot does, and
## both unzip to the same <core>_libretro.dylib.
static func asset_for(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	if src.is_empty():
		return ""
	var asset := str((src.get("assets", {}) as Dictionary).get(OS.get_name(), ""))
	return asset.replace("{arch}", mac_arch())


## The architecture a macOS asset is published for, named as the release names
## it. Anything unrecognised gets arm64, matching the buildbot URL's fallback.
static func mac_arch() -> String:
	var arch := Engine.get_architecture_name()
	return arch if arch in ["arm64", "x86_64"] else "arm64"


## Directory URL the asset hangs off, shaped like the buildbot's so the download
## manager can concatenate a filename onto either without caring which it has.
##
## Deliberately the /releases/latest/ form and NOT a tagged one. A tag in here
## would mean every new core build needed a new app build to point at it, and an
## installed copy of retroXR could never be given a fixed core — which is the
## whole point of having a download manager. GitHub resolves `latest` to the
## newest non-prerelease release, so publishing a build is enough to ship it.
##
## The consequence to know: `latest` is per REPOSITORY, not per product. A
## release cut on that fork for anything other than a core build would capture
## this URL. Mark such releases as pre-releases — GitHub's `latest` skips those.
static func base_url(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	if src.is_empty():
		return ""
	return "https://github.com/%s/releases/latest/download/" % src.get("repo", "")


## Where to ASK what the newest build is called. A stable download URL is only
## half of shipping updates: the manager decides whether to offer one by
## comparing versions, so without this the app would keep fetching whatever is
## latest while insisting the player is already up to date.
static func api_url(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	if src.is_empty():
		return ""
	return "https://api.github.com/repos/%s/releases/latest" % src.get("repo", "")


## Stands in for the buildbot's timestamp. The download manager only ever tests
## it for INEQUALITY against what the manifest stored, to decide whether to offer
## an update — so a release tag serves as well as a date, and unlike a date it
## only changes when the build does.
##
## This is the fallback; the live value comes from api_url.
static func version_of(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	return str(src.get("known_tag", ""))


## The branch a core is built from when no release names a tag yet, or "".
##
## Every other entry is pinned by known_tag and leaves this out: a tag says
## exactly what was built, and a branch only says where to look. It is here for a
## core that exists as source before it exists as a release.
static func branch_of(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	return str(src.get("branch", ""))


## Where a person can read the source this core is built from: the tag when one
## is known, else the branch, else the repository.
static func source_url(core_name: String) -> String:
	var src: Dictionary = SOURCES.get(core_name, {})
	if src.is_empty():
		return ""
	var repo := "https://github.com/%s" % src.get("repo", "")
	var ref := version_of(core_name)
	if ref.is_empty():
		ref = branch_of(core_name)
	return repo if ref.is_empty() else "%s/tree/%s" % [repo, ref]


## False for a core this app was built knowing no release of. Its download URL
## is still the /releases/latest/ form, so the first release reaches players on
## its own — but until the version probe hears of one there is nothing to offer,
## and the download manager must not list a row that can only 404.
static func is_released(core_name: String) -> bool:
	return not version_of(core_name).is_empty()


## Core names we publish AND build for this platform, for callers that need to
## walk them (the version probe).
static func active_core_names() -> Array[String]:
	var out: Array[String] = []
	for core_name: Variant in SOURCES:
		if has(str(core_name)):
			out.append(str(core_name))
	return out
