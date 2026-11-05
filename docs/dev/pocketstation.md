# The PocketStation and pcsx_rearmed — PLAN (2026-11-05)

**Nothing here is built.** Today the PocketStation is only a tile (`SystemInfo/pocketstation.tres`, an
icon, the buildbot's `pokket` core): spawned, it would be the procedural box taking a "cartridge", and
nothing joins it to a PlayStation. This is the plan for making it what it is: **a PlayStation memory
card that is also a handheld**, which is the VMU's arrangement (`VmuCard`), with the PS1 side done in
our pcsx_rearmed fork.

## What the hardware does

SCPH-4000 (Japan, 1999): a 128 KiB PS1 memory card with an ARM7 CPU, a 32 x 32 mono LCD, five buttons,
a speaker, infrared, an RTC and a CR2032. A game DOWNLOADS a minigame onto it (Final Fantasy VIII's
Chocobo World is offered from the game's Save menu), the player pulls it and plays on it, and plugs
it back for the game to read the result. That last step usually reaches the GAME's save in another
block of the same card (Pokket's `psemu.h`, "How an app reaches the PS1 save").

**Docked, the device's own kernel answers the card bus** (psx-spx, "Pocketstation BU commands").
Beside the standard `52h` read, `53h` get-ID and `57h` write (Sony-card answers, dummy bytes `00h`, two
new write errors `FDh`/`FEh`), it takes `50h` and `58h`..`5Fh`: get ID/version (`58h`), prepare file
execution (`59h`, dir_index + parameter), get dir_index, ComFlags, the serial F_SN and the BCD
date/time (`5Ah`), execute a function and move data either way (`5Bh`/`5Ch`), download notification
(`5Dh`) and the ComFlags pairs (`5Eh`/`5Fh`). **`5Bh`/`5Ch` FUNC 80h..FFh run functions out of the
downloaded APP's own table** (title sector `57h`: the number of them). An executable is marked in the
title sector's `50h..5Fh` region (`"MCX0"`/`"MCX1"` at `52h`, entrypoint at `5Ch`) and in its file
name (psx-spx: "replace '-' by 'P'" in the game code; verify on a real card).

## The decision: run the real device INSIDE pcsx_rearmed

Three ways were weighed:

- **A stand-in answering the commands in pcsx_rearmed (HLE).** Refused: `5Bh`/`5Ch` FUNC 80h+ call
  into the app, so only the device's CPU can answer them, and the kernel's dir_index/ComFlags
  behaviour is a second emulator to keep right.
- **The `pokket` libretro core as a separate machine on the link bus** (the Game Boy Printer's model).
  Refused: a card answers inside the byte exchange (/ACK within 100 µs of the clock, psx-spx), so the
  bus would be paying a grain and a horizon per BYTE, for some 140 bytes a sector.
- **Pokket's emulation core linked into pcsx_rearmed, every card byte handed to it.** Taken. Pokket's
  `core/` is MIT (`mentalfoundry/Pokket`, `core/LICENSE`) and has the API for exactly this
  (`psemu_com_set_docked`, `psemu_com_is_enabled`, `psemu_com_set_selected`, `psemu_com_transfer[_timed]`,
  `psemu_com_acked`); `mentalfoundry/PokketSX`, a DuckStation fork, does it this way and plays the
  PocketStation titles. Its clock maps onto the PS1's exactly (441 ticks of 33,868,800 Hz =
  13,312,640 `PSEMU_TIME_HZ` units), it never reads the host clock, and it has a savestate.
  **Licence:** vendor only Pokket's `core/` (MIT) into the fork (GPLv2+). PokketSX's glue
  (`src/core/pocketstation.cpp`) is GPL-3.0-only: read it for behaviour, write ours.

## pcsx_rearmed (RetroXR/pcsx_rearmed, branch `retroxr`)

1. **Vendor** Pokket `core/` at a pinned commit in `deps/pokket/`, built by `Makefile.libretro` on
   every target (C99, no dependencies). Pin the SAME commit the standalone core is built from
   (Pokket says not to rely on savestates across its versions).
2. **Per-slot device option** `pcsx_rearmed_memcard{1,2}_device` = `card` (default) | `pocketstation`,
   read at load and live (the hot-swap path `90aaa63e` added for `memcard{N}_inserted`), and
   `pcsx_rearmed_pocketstation{1,2}_id` for the device's serial (`psemu_set_hardware_id`; games read it
   through `5Ah` F_SN).
3. **BIOS** `pocketstation.bin` (16 KiB) from the system dir, the name the `pokket` core's .info
   already uses, so one file serves both. Missing: the slot stays a plain card and a WARN says why.
   **Any 16 KiB image boots, but only the retail J110 dump Pokket was traced on takes the date, time
   and volume writes** (`psemu_settings_offsets_known`: FNV-1a `0xB2E46838` over the 16 KiB, the .info's
   md5 `987d6438...`); on any other the RTC starts at its reset value (1 January 1999), which is still
   deterministic. Log which it is. The `retrobios` set on the dev machine has neither: its
   `pocketstation.bin` is tagged `C110`/`J110` but hashes `0xDDF1F248` (md5 `0e4712cd...`), and its
   variant is the `C061`/`J061` prototype, 60 bytes apart (2026-11-05).
4. **Device glue in our own file**, `libpcsxcore/pocketstation.c`: create, load the BIOS, load flash
   from `Mcd{N}Data`, dock, and run frame by frame until `psemu_com_is_enabled` (the kernel debounces
   the dock; until then the slot answers as EMPTY, as a card still going in would).
5. **SIO hook.** For a port whose device is a PocketStation, `sioWrite8` bypasses the `mcdst` machine:
   from `81h` on, every byte goes to `psemu_com_transfer` and its reply into `buf`, and the IRQ is
   scheduled at the device's acknowledge (`_timed`), not the fixed `SIO_CYCLES`; the last byte has no
   acknowledge. DTR dropped or `SIO_RESET` (`sioWriteCtrl16`) releases /SEL
   (`psemu_com_set_selected(ps, 0)`), without which the kernel answers one command and then nothing.
6. **In step with the console**: run the device to the PS1's cycle count before each byte and at each
   frame's end, by the exact ratio above. PokketSX also runs ahead to the acknowledge and keeps a
   state to undo it if the console's next input comes first; see whether scheduling the IRQ from
   `_timed`'s count makes that unnecessary before copying the idea.
7. **The device's flash IS the card.** When it writes (compare against a snapshot each frame), copy
   into `Mcd{N}Data` and `SaveMcd`, so RetroXR's `SAVE_RAM`/`SetSramBPath` mounting, `sram_flushed` and
   RomM all work unchanged. When the frontend swaps the card's data, reload the device's flash.
8. **The HLE BIOS bypasses the bus**: `psxbios.c` reads and writes `Mcd{N}Data` directly (15 sites),
   so device and card would part. A PocketStation needs the REAL PS1 BIOS; on HLE the slot is a plain
   card and a WARN says so.
9. **Savestates carry the device.** Unlike PokketSX ("the device is not part of save states"),
   `misc.c`'s freeze gains a versioned chunk per docked slot (`psemu_save_state`), because a
   PlayStation rolls back (§2g″) only because every load is exact. Under
   `pcsx_rearmed_netplay_deterministic` the device's date and time come from an option the host's
   spec sets, never the host clock.
10. **Log at WARN** (libretro-godot drops less): docked/undocked, communication enabled after N frames,
    BIOS missing, HLE fallback, the first sighting of each command byte, flash written (which blocks),
    the state chunk's size.
11. **Rebase first?** Upstream reworked SIO receive IRQs in `3a9e0a4ff` (2026-08-16), which the fork does
    not have and which touches exactly this code. Decide before starting; keep the hook small either way.

## RetroXR

1. **`PocketStation`, a `MemoryCard` of family `playstation` that is also a handheld** (VmuCard's
   arrangement, not a RetroSystem): its image is `save/memcards/playstation/<card_id>.mcr`, so the
   shelf, the panel, renames and RomM serve it unchanged; it saves and spawns as its own kind, offered
   beside Memory Card on the PlayStation's card.
2. **Seated**: `MemoryCardController` sets `pcsx_rearmed_memcard{N}_device=pocketstation` and the id
   option, both ways (a plain card sets `card` back), at load and on a live seat. Any other PS1 core
   sees a plain card (logged).
3. **Pulled**: it runs the `pokket` core on a SCRATCH copy of its image, drained back at power-off
   (VmuCard's rule: no core writes the card file directly), and seating it ends the game, as a VMU's
   does. 32 x 32 screen on the model, five buttons through `ControlPoke`, a voice, a CR2032 in a
   `BatteryBay` for power simulation.
4. **BIOS rows**: `pocketstation.bin` on the PlayStation's BIOS page (overlay `pcsx_rearmed` .info,
   optional) as well as the PocketStation's.
5. **Netplay**: docked, it is part of the PlayStation's deterministic state (item 9); a card moved
   mid-session is already refused. A loose PocketStation is local only at first.
6. **Model**: a primitive from the measured unit. Look the dimensions up first.

## Later

- The docked LCD: the PocketStation's screen shows while docked (the kernel rotates it 180°, LCD_MODE
  bit 7), so the seated model could show the device's frame: 128 bytes a frame out of pcsx_rearmed (a
  memory id like `SRAM_B_PCSX_MEMCARD2`).
- Carrying the clock and the running state between the docked device and the standalone core (two
  instances of one Pokket version; `psemu_save_state` through a sidecar). At first only flash crosses,
  and a pulled PocketStation boots through its BIOS.
- Infrared between two PocketStations: Pokket's IR edge API (`psemu_ir_pop_tx_edge` /
  `psemu_ir_push_rx_edge`) behind `IrPort`/`IrBus`, as the Game Boy Color's.

## Proving it

- `Tools/cores/pocketstation_dock_probe` (real core, PS1 BIOS, `pocketstation.bin`, a PocketStation
  title, a scratch home; one core and one leg per process): `dock` (the game offers and writes the
  minigame: a file with the `MCX0` header appears), `plain` (control: same game, plain card, not
  offered), `hle` (falls back and says so), `undock` (the `pokket` core boots that app from the same
  image, a non-blank LCD) and the return trip (the game reads what the app wrote).
- `psx_rollback_probe` with a docked PocketStation matching lockstep, and a mutation leg with the
  device left out of the state that must diverge.
- Suites: seating sets the option both ways and on restore, scratch and drain, the spawn row, the
  refusal mid-session.
- The docked device's cost per frame on a Quest.

**Open:** which titles to test (FF8 (J) and its Chocobo World is the known one); whether pcsx_rearmed's
fixed per-byte timing satisfies the PocketStation library without upstream's SIO rework; and the
executable-name marker.

Sources: psx-spx `pocketstation` and `controllersandmemorycards`; `mentalfoundry/Pokket`
(`core/include/psemu/psemu.h`, read 2026-11-05); `mentalfoundry/PokketSX` (`README.md`,
`src/core/pocketstation.h`).
