# §2m, §2n, §2n′, §2n″ — Sega CD and Saturn backup memory, the Saturn's other cartridges and its Video CD Card

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2m. Sega CD backup memory — on the unit, on a cartridge, written at unload

A Sega CD game saves to the 8 KB of backup RAM inside the unit or to a Backup RAM
Cartridge in the Mega Drive's slot. Both are modelled: the `sega_cd` unit's row
declares `"memory": "sega_cd_memory"`, so the RetroExpansion carries a card id
saved with the room, and `sega_cd_ram_cart` is a MOUNT_CARTRIDGE unit with no BOOT
key whose memory family is `sega_cd_ram_cart`. The unit's memory is managed from
the console's System Settings **Saves** tab (a switch appears when a cartridge is
seated too); the cartridge also opens its own card panel and lives on the card
shelf, offered from the Sega CD's card.

**genesis_plus_gx never hands either over.** Read at source: both live in files in
`<root>/save/<core>`, read in `retro_load_game` (`bram_load`) and written only in
`retro_unload_game` (`bram_save`) — no SAVE_RAM, no memory map, not in savestates,
no periodic flush. `SegaCdStorage` pins the names for the run
(`genesis_plus_gx_system_bram` per bios, `_cart_bram` per cart, `_cart_size` from the
seated cartridge's image or disabled), stages the unit's image into all three
`scd_U/E/J.brm` (the region is the disc's, unknown until load) and the cartridge's
into `<size>_cart.brm`, then drains the file the core rewrote back to the image
that filled it for 12 s after StopContent, and clears the folder. A manifest on
disk lets a crash between the two recover at the next start. Files nobody's
manifest claims are older saves: moved into `legacy/`, never over, and a new unit
or cartridge starts from the most recent that fits. The folder is shared by every
machine on the core, so a second Sega CD is refused while it is in use.

The format is `SegaCdBram`, whose error correction is transliterated from buram
(Ian Karlsson, MIT); `card_tests` pins buram's own output for the same operations
by SHA-256, and `expansion_tests` covers staging (`scd_storage/`) and the units
and tab (`memory/`).

**Measured 2026-09-14** with `Tools/cores/sega_cd_bram_probe`, US BIOS 1.10:

- Its DATA STORAGE INFORMATION screen reports the staged images' own counts — 1
  item, 124 free built-in; 1 item, 252 free on a 128 Kbit cartridge.
- ERASE ITEM lists `RETROXR_MEM` by name, so the BIOS decodes the directory
  SegaCdBram writes, not just its counters.
- The BIOS's own COPY built-in → RAM, confirmed, leaves a cartridge file that
  SegaCdBram reads back as `RETROXR_CRT` + `RETROXR_MEM`, 250 free: a write by the
  real BIOS, through the core's unload, read by ours.
- With the cartridge **disabled**, the stock core's BIOS says the cartridge memory
  "IS NOT PRESENT". The source reads as if "disabled" (0xFF) still maps a cartridge,
  and a patched core behaves identically, so no fork is needed for it.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/sega_cd_bram_probe.tscn -- --root=<root with system/bios_CD_U.bin and cores/> \
  --cart=128k --at=11 --press=4:start,6:down,6.8:right,7.6:b --shot=C:/tmp/scd.png
```

That press list reaches the storage screen; B there opens the MENU (FORMAT, ERASE
ITEM and COPY for each memory, cursor on EXIT). A copy's confirmation defaults to
NO, so LEFT before B. Point `--root` at a throwaway root: the probe writes its
`save/` and `core_options/`.

Still owed, and why: picodrive (the Tower of Power runs on it) has its own route
and is not covered; netplay and savestates carry no backup memory, because the
core keeps it outside both; a crash before the core unloads loses that session's
writes, because nothing reaches disk until then; and the four options that
rebuild the machine (`system_hw`, `bios`, `region_detect`, `vdp_mode`) zero both
memories mid-game, so they are held while a Sega CD runs.

### 2n. Sega Saturn backup memory — in the console, on a cartridge behind the lid

A Saturn saves to 32 KB of System Memory on its board or to a 512 KB Backup RAM
Cartridge. The System Memory belongs to the console: `SystemInfo.console_memory`
names its family (`sega_saturn_memory`), `RetroSystem` builds a `ConsoleMemory`
child whose `card_id` is saved with the room (`console_memory` in the system
entry), and it is managed from the console's **Saves** tab by the card panel's own
code. The cartridge is the `sega_saturn_ram_cart` unit, MOUNT_ABOVE because the
Saturn's CartridgeSlot is its disc well: the console grows an ExpansionSocket, and
`RetroSystemModelDefault.configure_expansion_socket` moves it into a slot behind
the lid (`ProceduralDiscBay.seat_rear_slot`). The unit's size and the slot's depth
are estimates, not measurements. Both images are `SaturnBram`, the layout of
Yabause's HLE BIOS calls (`src/bios.c`).

**Beetle Saturn keeps the two differently**, read at source (`libretro.cpp`):

- The System Memory goes through SAVE_RAM in the "libretro"
  `beetle_saturn_save_method`; in "mednafen" the core writes a `.bkr` itself and
  exposes no SAVE_RAM. So `MemoryCardController._compose_sram_path` points every
  `mednafen_saturn` run at the console's image, disc or no disc. Other Saturn
  cores keep the per-disc route.
- The cartridge is a file the core owns in its save dir: `<disc>.bcr`, or
  `mednafen_saturn_libretro_shared.bcr` with `beetle_saturn_shared_ext` on. It is
  read at load and flushed ~180 frames after a write and again at unload.
  `SaturnStorage` pins shared_ext, stages the seated cartridge's image into that
  file, drains it while running and for 12 s after stop, and keeps a manifest for
  a crash, as SegaCdStorage does. One Saturn with a cartridge runs at a time.
- `beetle_saturn_cart` is pinned to whatever is in the slot -- "Backup Memory"
  with this cartridge, "None" with nothing -- by `ForcedCoreOptions.saturn_cart`,
  not by `SaturnStorage`, because the slot takes four other cartridges too (§2n′).
  Auto Detect stays away: it would fit a cartridge nobody put in the slot.

The first System Memory image made takes the saves games kept in per-disc `.srm`
files, which stay where they are. A new cartridge takes the saves in the per-disc
`.bcr` files Beetle made while it gave every disc a cartridge of its own; those
are moved to `legacy/` and renamed `.imported` once taken.

**Measured 2026-09-15** with `Tools/cores/saturn_bram_probe`, Beetle Saturn
v1.32.1 and BIOS NTSC-4-V1.01a, on the empty-media cue:

- A blank cartridge Beetle formatted itself hashes the same as
  `SaturnBram.blank_image(CART_SIZE)`; `card_tests` pins that digest.
- The BIOS Memory Manager lists `RETROXR_MEM RetroXR 4` from the image handed over
  through SAVE_RAM. Its "Memory available: 458" is Yabause's
  ((64 − 6) × free − 30) / 64 over SaturnBram's 506 free blocks, a different unit
  from the card panel's count.
- The BIOS's own copy to the cartridge leaves a `.bcr` that SaturnBram reads back
  byte-exact.
- Its copy of a 1500-byte cartridge save into System Memory comes back through
  SAVE_RAM as 27 blocks whose block list crosses a block, also byte-exact.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/saturn_bram_probe.tscn -- --root=<throwaway root with system/mednafen_saturn and cores/> \
  --cart --at=28,31,34 --press=17:up,18:b,20:down,21:down,22:b,24:b,26.5:b,29.5:b --shot=C:/tmp/sat.png
```

The BIOS goes straight to its CD player on the empty-media cue. That press list
takes the top-middle icon (System Settings), then Memory Manager, and copies the
System Memory's first item to the cartridge; RetroPad B confirms and "OK to copy?"
defaults to Yes. Three downs inside Memory Manager reach "Copy Item to System".
Point `--root` at a throwaway root: the probe writes its `save/` and
`core_options/`.

Still owed: netplay and savestates carry no cartridge; no game has been run saving
to either memory.

### 2n′. The other cartridges for that slot — Extended RAM and two ROM cartridges

Four more units stand in the same slot behind the lid, in the Backup RAM
Cartridge's shell (`sega_saturn_ram_cart.gd`'s `SIZE`; Sega Retro: the Extended RAM
Cartridge "looks virtually the same"), so only one cartridge of the five is ever
in, as on the hardware:

| unit | Beetle `beetle_saturn_cart` | YabaSanshiro `yabasanshiro_addon_cart` |
|---|---|---|
| (empty slot) | `None` | `none` |
| `sega_saturn_ram_cart` | `Backup Memory` | `none` |
| `sega_saturn_extram_1m` (HSS-0150) | `Extended RAM (1MB)` | `1M_extended_ram` |
| `sega_saturn_extram_4m` (HSS-0167) | `Extended RAM (4MB)` | `4M_extended_ram` |
| `sega_saturn_kof95_rom` | `The King of Fighters '95` | — (runs Beetle) |
| `sega_saturn_ultraman_rom` | `Ultraman: Hikari no Kyojin Densetsu` | — (runs Beetle) |

`ForcedCoreOptions.saturn_cart` pins it **both ways**, the Expansion Pak's shape:
Beetle on Auto Detect fits a cartridge from its own game database (a Backup RAM
Cartridge for any disc it does not list), and **YabaSanshiro defaults to the 4 MB
cartridge**, so until this every Saturn on a Quest had 4 MB nobody put in it --
which Beetle's database says Real Bout Garou Densetsu and Samurai Spirits: Amakusa
Kourin refuse. Which game wants which cartridge is that database
(`mednafen/ss/db.c`: 22 discs want 1 MB, 7 want 4 MB); nothing in the room reads
it, so a disc without its cartridge shows whatever the game itself shows.

- **RAM cartridges** keep no saves (no memory family), have no BOOT row and change
  no core: a game that wants the RAM saves to the console's System Memory, and the
  slot being taken is why.
- **ROM cartridges** are half a game, the dump the core opens from its system
  directory (`mpr-18811-mx.ic1`, `mpr-19367-mx.ic1`, the names Beetle's .info
  declares), so each names it as `firmware`: always offered, its spawn row reads
  "BIOS missing" in red without it, and a Saturn with it seated refuses to start.
  Each has a BOOT row naming `mednafen_saturn` and no `roms` -- the disc still
  boots -- because YabaSanshiro has no ROM cartridges at all; on a Quest seating one
  runs Beetle. A cartridge restored into a room whose dump has gone opens nothing
  and the core runs with an empty slot (`cart.c` falls through).
- **"none" is not a value YabaSanshiro declares** (`4M_extended_ram|1M_extended_ram`)
  but a branch its `check_variables` takes, read before `YabauseInit`;
  libretro-godot passes a pinned value through unchecked (`SetVariable`,
  `DeserializeFromFile` check only the key).

**Measured 2026-10-14:** `Tools/cores/core_options_probe` peeked the installed
Beetle (36 options) and a buildbot YabaSanshiro: every Beetle string in the table is
one it declares, and YabaSanshiro declares `yabasanshiro_addon_cart` defaulting to
`4M_extended_ram`. `expansion_tests --only=saturncart` (mutation-tested: dropping
the empty pin, leaving SaturnStorage pinning the slot, a ROM row without its core,
and one without its dump each turn a case red). `Tools/models/saturn_cart_render_probe`
(windowed) photographs each of the five seated and prints what it pins.

```bash
"$godot" --path RetroXR --resolution 960x720 --position 20,20   res://Tools/models/saturn_cart_render_probe.tscn -- --out=C:/tmp/satcarts
```

Still owed: **no game has been run with any of them** -- this machine has no Saturn
BIOS and no disc that wants a cartridge -- so that X-Men vs. Street Fighter boots on
the 4 MB cartridge, and refuses without it, is read at source, not seen; YabaSanshiro
taking "none" is read at source too; Kronos and other Saturn cores pin nothing; a
real two-peer session with a cartridge seated.

### 2n″. The Video CD Card — a slot of its own in the back

Beetle Saturn has emulated the card since upstream libretro's 2026-08-06 work (in our
fork from v1): `mpeg.c` is the CD block's MPEG command surface, decoding on
libretro-common's rmpeg1/rmp3, composited as VDP2's external background, behind
`beetle_saturn_mpeg_card` (default disabled, restart-time) and the card ROM
`mpeg_card.bin` (`ss.mpeg_card_path`). **The ROM's bytes are never read**:
`MPEG_GetROM` has no caller, and `MPEG_Auth` authenticates exactly when the file
opened, so any dump works and none can be checked. Not modelled by the core: the
image/sector transfer commands 0xA7-0xAA.

The card is `sega_saturn_vcd_card`, a MOUNT_ABOVE unit with **`socket: "mpeg_card"`**:
it is not a cartridge (Sega Retro: it goes in "through the door the battery is
accessed from"; MAME's forum: a PCMCIA-like slot in the back near the battery), so
it has a socket of its own and stays in while cartridges come and go behind the
lid. A row's `socket` names the console socket a MOUNT_ABOVE unit takes;
`RetroSystem._build_unit_sockets` grows one per name (`MpegCardSocket`) with its own
filter (`_accepts_expansion_in`), and `RetroSystemModel.configure_unit_socket`
places it. **The card is "a metal cassette with side rails that slides in label side
down"** through a bay opening 61.6 x 33 mm (RetroXR-models' Saturn console research,
off a photograph), so `ExpansionPort.seat_through_back` turns the socket that way --
+Y out of the back, the card's face down -- and leaves `CARD_HANDLE` (12 mm) out as
a handle, where the real card goes all the way in and its door shuts over it. The
card is 58 mm wide to clear that opening; its 100 mm depth and 16 mm thickness are
estimates. The placeholder box puts the slot at x = -0.075, away from its A/V row
(`ProceduralDiscBay.seat_back_card_slot`). **A model that does not place it gets it
through the middle of its back panel, plate hidden** (the base class): the first
build left the socket on the roof where RetroSystem builds every socket, and the
Saturn mod (`xenu.saturn`, built before the hook) showed its connector plate over
the disc well, card or no card -- its own probe caught it as a stand-in mesh drawn.
**`_on_expansion_lifted` now unbinds only the units their OWN socket stopped
holding** -- it used to unbind every MOUNT_ABOVE unit, which with one socket was the
same thing and with two pulled the card out whenever a cartridge came out.

`ForcedCoreOptions.saturn_mpeg_card` pins the option both ways on Beetle. The card
names `mpeg_card.bin` as firmware, so without the file its row reads "BIOS missing" and power-on refuses --
RetroXR's `.info` overlay declares it (optional), with the md5 of the one dump
tested, `b3841bb91201eee6c0db229b2c66d54c`, which is NOT a published hash; another
dump reads MISMATCH and still works. YabaSanshiro has no decoder, so the card's BOOT
row runs Beetle, and so does each ROM cartridge's pair with it (a stack's recipe is
keyed by every unit that names one, so `kof95|vcd_card` must be spelled out or the
pair falls back to the player's core). Netplay pins the option off
(`NetplayCores`), card or no card: `net_start_core` writes the session's pins, then
the machine's, and now writes `NetplayCores.forced_options` back over both -- the
machine's "enabled" used to win. That key is the only one the two ever share.

**Measured 2026-10-14:** `expansion_tests --only=vcdcard` (30 checks; mutation-tested:
the old unbind-everything, a socket that takes any unit, an unturned slot, a missing
pair recipe and a missing `.info` row each turn a case red); `saturn_cart_render_probe`
photographs the card in the back beside a 4 MB cartridge. Still owed: **no Video CD
or MPEG game has been played** -- no Saturn BIOS or disc on this machine -- so the
picture, the sound and Lunar: Silver Star Story's MPEG edition are unseen; netplay
with the card. **The Saturn mod seats it for real from 0.2.0** (RetroXR-models
`mods/xenu.saturn`, its `configure_unit_socket`): on the shell's `ExpansionBay`
marker, with `BatteryCover` off while a card is in; its `saturn_probe` checks the
bay, the fit (58 x 16 mm in the 61.6 x 33 mm opening) and the door, 145 checks.
A mod's override must not call `super()` or anything newer than the oldest build
it loads in -- GDScript refuses to compile it there, and the console with it.
