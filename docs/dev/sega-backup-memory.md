# §2m, §2n — Sega CD and Saturn backup memory

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
- `beetle_saturn_cart` is pinned "Backup Memory" with a cartridge seated and
  "None" without. **That takes Auto Detect away**, and Auto Detect is what gives
  the Japanese titles that need a 1 MB or 4 MB Extended RAM cartridge their RAM:
  they will not run until there is a unit for that cartridge.

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
to either memory; and the Extended RAM cartridge above.
