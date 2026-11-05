# The PocketStation — the room object (built 2026-11-05) and the pcsx_rearmed plan

**The RetroXR half is built; the pcsx_rearmed half is a plan.** A PocketStation is spawned from the
PlayStation's card (below "Memory Card"), seats in a PS1's card slot as that console's memory card, and
out of it runs the `pokket` core on its own card from the card panel, the VMU's arrangement (`VmuCard`).
What it does not do yet is answer the PlayStation AS a PocketStation: seated, a game sees a plain card
and offers no download. That half is the plan in "pcsx_rearmed" below.

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
   **The retail J110 circulates as at least THREE files**: the .info's `987d6438...`, retrobios's
   `0e4712cd...` (CRC `5b91d3e4`) and a player's `d3dc54ef...` (CRC `09881f33`, r/RetroArch,
   2026-08, where the post's author told them J110 renamed `pocketstation.bin` is the one); the 061
   there is `3bcdcef3...` (CRC `5fb47dd8`), retrobios's variant byte for byte. retrobios's J110 is the
   retail 110 by everything Pokket documents (SWI `0Ah`/`0Dh`/`0Eh` at the J110 addresses, SWI `0Fh`
   a `push` then `b .` for ever where the 061 still has `FlashWriteSerial`), and it boots the app.
   A mask ROM dumps the same twice, so one of them has a bad byte or there is an undocumented
   revision: unknown without the other files. **So RetroXR's overlay `pokket_libretro.info` drops the
   md5** (the BIOS page called every other J110 "wrong file"); `pocketstation_tests` `core/`.
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

## RetroXR (built 2026-11-05)

`PocketStation` (`Scripts/Objects/peripherals/pocketstation.gd`, `Scenes/Objects/peripherals/pocketstation.tscn`),
a `MemoryCard` of family `playstation` that is also a handheld. Not a RetroSystem, for the VMU's reason: it
is a card first, and has to stay one while seated.

- **Spawned** from the PlayStation's card (`SpawnCatalog` "psx", token `pocketstation`), a plain row, not
  the card shelf. Saved as its own kind (`ScenePersistence.PLAIN_SCENES`, its `_save_kind_rows` row ABOVE
  MemoryCard's, or it saves and comes back as a plain card: `pocketstation_tests saved/` goes red when it
  is moved below), card id and label through `_card_fields`. Which slot holds it is the console's.
- **A card**: a PS1 slot takes it by family; it mates along -Z as every card does, so the object wears the
  primitive turned half round about Y and shifted so 28 mm goes in, the hinge 1.4 mm out of the mouth
  and the base on the slot's axis (`Tools/models/pocketstation_seat_probe`: 28.2 mm in, 1.4 mm out). Its
  image is `save/memcards/playstation/<card_id>.mcr`, the shelf, the panel, renames and RomM as any card.
  Its name is on the back, where the real one is lettered.
- **A handheld**: the card panel (`MemoryCardPanel`, duck-typed as for a VMU) switches it on. The Games
  tab's first row is the unit's own card ("its own card"); a save marked as a PocketStation app
  (`PS1Card.is_pocketstation_app`, "MCX0"/"MCX1" at 0x52 of its title frame, `is_game` in `list_saves`)
  gets a Play button that boots the same card, since Pokket cannot jump past its BIOS menu; the rest of the
  Games tab is `roms/pocketstation/` (.mcs .pss .gme .mcr .mcd .bin). Pokket's save RAM is the whole flash,
  a `.mcr` byte for byte, so:
  - its own card runs on a SCRATCH copy (`user://pocketstation_play/<card_id>.mcr`, content and save path
    both), and at power-off, once the core has unloaded, the scratch goes back WHOLE through
    `CardSaveOps.write_card`; while a powered console holds the card it waits (VMU's rule: no core writes
    a card file directly). A scratch that is not a card image is left where it is and logged.
  - a library app keeps its own progress in `apps/<md5>.mcr` and never touches the card.
  - a new unit with no image is given a formatted one (`PS1Card.blank_image`) on its first start; a
    restored one with its image missing refuses (a blank would read as wiped saves).
- **Will not run** seated ("seated in a slot"), with no `pokket` core (offered on the PlayStation's BIOS /
  Extras page as well as its own tile, `cores_view._BIOS_EXTRA_CORES`), with no
  `system/pokket/pocketstation.bin`, or while its last run's core is still unloading.
- **Controls**: Pokket reads up/down/left/right and A (Action). The hand is `VmuInput` unchanged (A/X is
  Action, the stick the four buttons; Scroll Lock captures the keyboard on desktop) and fingertips are
  `ControlPoke` over the model's caps, which sink along the model's -Y.
- **Screen** `Model/LidHinge/Screen` through the window shader (`show_picture`); the speaker voices are
  posed on the unit, out of its back.
- `pocketstation_tests` (catalog, frame, saved, controls, seat, apps, carry; controls and saved
  mutation-tested). `Tools/models/pocketstation_seat_probe` (windowed): seated in a PS1, and an
  asymmetric "F" through `show_picture` on a loose one, upright and unmirrored.
  `Tools/models/pocketstation_menu_probe` (windowed, `--image=` a card, `--root=` a scratch root with
  Pokket): the unit's own panel tab by tab, then switched on from it (Saves shows "Playing ...", the
  LCD the BIOS). **Pokket's only options are its IR link's** (`pokket_link_*`, the two-unit subsystem
  load RetroXR never makes), so `PocketStation.single_unit_options` drops them and the Options tab
  hides. A Japanese app's title lists as its ASCII alone (Dokodemo Crash-kun's is "3"): `Sjis`
  drops kana and kanji by design, and the serial on the row is what tells the app apart.
- **Not yet:** a game PLAYED on the unit and its progress carried back (the app boots, see "Crash Bandicoot 3" below), netplay (no `net_*`; a session
  does not offer it), the docked protocol (pcsx_rearmed below), carrying the clock or a running app
  across dock/undock, infrared, a `BatteryBay`, the crystal body, and opening an existing shelf card AS a
  PocketStation (a unit is spawned with a card of its own). Headset feel OWED.

The plan's other items: **seated**, `MemoryCardController` sets `pcsx_rearmed_memcard{N}_device=pocketstation`
and the id option once the fork has them, both ways; **netplay**, docked it is part of the PlayStation's
deterministic state (item 9 of the fork).

## Crash Bandicoot 3 (J), measured (2026-11-05)

`Crash Bandicoot 3 - Buttobi! Sekai Isshuu (Japan, Asia)` (SCPS-10073) carries the PocketStation app
**Dokodemo Crash-kun**. Run with `Tools/cores/pocketstation_dock_probe` (headless, a scratch libretro
root holding the installed `pcsx_rearmed` and the four PS1 BIOS files, `--leg=pocketstation`) on
RetroXR's fork r26 9a26363, `scph5500.bin` (the core picks the Japanese BIOS by itself):

- **The download does NOT need a PocketStation.** Title menu → おまけ (third row) → ポケットステーション →
  あたらしくダウンロード → はい (left, then circle: the cursor starts on いいえ) → オッケー, and the game
  writes `BISCPSP10073-PDA`, 12 blocks, onto what the core presents as a PLAIN card, with a progress
  bar and no error. The frames: `--steps="3700-3706:down,3760-3766:down,3840-3846:circle,5100-5106:circle,5700-5706:circle,5900-5906:left,6000-6006:circle,6300-6306:circle"`
  (circle confirms; core frames at 60 a second). So for this game the pcsx_rearmed half is not
  needed to get the app onto the card; what it would add is the rest (whatever the game reads back
  from a docked unit, `5Ah`'s clock and serial among it).
- **The app file is named as psx-spx says**: the game code's `-` becomes `P` (`SCPSP10073`), and its
  title frame carries `MCX0`, which `PS1Card.is_pocketstation_app` reads (`[PocketStation app]` in the
  probe's listing).
- **The app plays on the unit.** `Tools/cores/pocketstation_play_probe` (the unit's own `power_on`,
  Pokket v1.23 from the buildbot in a scratch root via `PocketStation.core_directory`, the C110
  `retrobios` dump, the card the dock probe left) goes HELLO -> heart -> the date/time screen
  (`99/01/01`) -> Down, Action -> the app's icon -> Right, Action -> Dokodemo Crash-kun's title
  (おためし) and Crash: `--every=32 --steps="400-402:down,440-442:action,480-482:right,520-522:action"`
  (core frames at 32 a second). Nothing was played long enough to write to the card (md5 unchanged).
- **The first report here said it held on HELLO, and that was the PROBE**: it `resize()`d the image
  `GetVideoImage()` returns, which is the video handler's own, and `VideoHandler::UpdateTexture` drops
  every later frame whose size no longer matches it, so the LCD froze on the first shot. The "point it
  stopped at" moved only because each run used a different `--every` (`testing.md` already warned;
  the DMG-07 probe hit the same thing the day before). Pokket's `core/` is deterministic (no host
  clock anywhere), so a stop point that moves between runs is the frontend's or the probe's.

## The primitive (built 2026-11-05)

`Scenes/Objects/peripherals/pocketstation_model.tscn`: a plain `Node3D` of parts, lying flat as the
handheld primitives do (screen +Y, the infrared end -Z, the card edge +Z, centred, metres). The
PocketStation object wears it. `Tools/models/pocketstation_render_probe`
(windowed) renders it beside a PS1 memory card and prints its size, **42.0 x 14.2 x 65.8 mm**: Sony's
64 x 42 x 13.5 mm body plus what stands proud of it (Sony's manual: "approx. 42 x 14.8 x 65 mm
including protrusions").

- **Sources.** Sony's press release of 1998-10-08 (最大外形寸法 64 x 42 x 13.5 mm, ~30 g with the
  battery; five input buttons and a reset button; IrDA plus remote-control infrared; ONE red LED;
  CR2032; white and crystal); photos measured for the layout (Evan Amos and Qurren on Wikimedia
  Commons, front; consolevariations.com, back and the lid opened), scaled to the 42 mm width.
- **The screen section is a LID hinged at the seam** 34.6 mm from the top: the step across the
  face is its edge over the thinner base, and opened it shows two screws and the unit's printed ID
  (`ID.A03067239` on the one photographed). So the model is a 7.5 mm base the whole length, and a
  6 mm lid on its upper part under `LidHinge` (turn its X to open it; the probe shows 70 degrees).
  What the lid is FOR is not settled: docked the device lies flat and the kernel rotates the picture
  180 degrees (LCD_MODE bit 7), which needs no lid at all.
- **The outline is a tombstone** (a semicircular top the body's width, straight sides, 3 mm corners
  at the card end), extruded by `PocketStationShell` (`Scripts/Objects/peripherals/pocketstation_shell.gd`).
  Boxes and cylinders could not make the LID: its straight part (13.6 mm) is shorter than its arc's
  radius (20.5 mm), so a whole cylinder poked out past the hinge as a puck (the first render).
- **Parts by name**, for the object to wire: `Screen` (a 21 mm square for the 32 x 32 LCD) on
  `ScreenBezel`, `IrWindow` and `Led` at the top edge, `ButtonUp/Left/Right/Down/Action` (Pokket's
  `PSEMU_BUTTON_*`; each in a grey `...Well` that makes a white button read on a white body),
  `SpeakerGrille`, `BatteryCover`, `ResetHole` (the small hole by the grille, taken to be the reset),
  five screws, `CardEdge`, `StrapLug`. No SONY or PocketStation lettering.
- **Not modelled:** the crystal body, the bezel's rounded corners, the raised panel round the
  buttons, the grille's holes, the strap.

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
