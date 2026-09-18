# §2h, §2i, §2j — Super Game Boy, Sufami Turbo, DS Slot-2

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2h. The Super Game Boy — an adapter cartridge, and the core that can run one

A Super Game Boy is a Super Famicom cartridge with a Game Boy slot in its roof, so
it is the same three-layer object as the BS-X cartridge and is modelled the same
way: `ExpansionCatalog.MOUNT_CARTRIDGE`, a cartridge to the console and a console
to the cartridge. Two units, `super_game_boy` and `super_game_boy_2`.

**Snes9x cannot serve it at any price, and this is not obvious from the source.**
`libretro/libretro.cpp` defines `RETRO_GAME_TYPE_SUPER_GAME_BOY 0x104|0x1000`
right beside the BS-X and Sufami Turbo constants, so grepping for it finds a hit
and suggests support. It is vestigial: the `subsystems[]` array actually passed to
`RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO` holds only `multicart_addon` and `bsx`, and
`retro_load_game_special` drops that game type into `default:` and reports the load
failed. The row therefore pins **bsnes**, which is why `RetroSystem._resolve_core`
letting a stack's core beat the console's default is load-bearing here rather than
a nicety — a Super Famicom is a snes9x machine until one of these goes into it.

Verified in bsnes-libretro, `bsnes/target-libretro/libretro.cpp`:

```c
sgb_roms[]   = { "Game Boy ROM" (gb|gbc), "Super Game Boy ROM" (smc|sfc|swc|fig) }
subsystems[] = { "Super Game Boy", "sgb", sgb_roms, 2, RETRO_GAME_TYPE_SGB }
```
with `retro_load_game_special` assigning `gameBoy.location = info[0]` and
`superFamicom.location = info[1]`. So the ident is `sgb` and the **handheld's**
cartridge goes FIRST — the reverse of the BS-X pairing, which is shell-first. The
two orders are written out per row for exactly that reason; do not assume one from
the other.

**A BIOS is required, and it is the adapter's own cartridge**: `SGB1.sfc`
(md5 `b15ddb15721c657d82c5bab6db982ee9`) and `SGB2.sfc`, declared in
`bsnes_libretro.info` and installed to `libretro/system/bsnes/`. Each unit names
one and is gated on it independently, so a player with one dump is offered one
adapter. `rom_from_firmware` on the row is what lets the adapter find its own
program there: unlike the BS-X cartridge, which is spawned from a `.sfc` in the
library and carries it in `rom_path`, a Super Game Boy is spawned from a menu and
has no library file at all — without that flag its `rom_path` stays empty, the
pair comes up one short and degrades to a plain load **silently**.

The SGB2 is a real difference and costs nothing to model: the original derives its
clock from the SNES and runs the handheld about 2.4% fast, the revision carries its
own crystal. Because the cartridge IS the program the console runs, handing the
core a different dump is the whole of the change — a core that emulated the adapter
internally would have needed an option instead.

**What actually picks the revision is the dump's own SNES header, not its
filename.** Verified at source and against both files: the titles at `0x7FC0` read
`Super GAMEBOY` and `Super GAMEBOY2`, bsnes matches those against its bundled board
database, and `Cartridge::loadICD` reads `icd.Revision`/the oscillator out of the
board that matched. `icd.cpp` then branches on that single number, with its own
comment saying why — *"SGB1 uses the CPU oscillator (~2.4% faster than a real Game
Boy), SGB2 uses a dedicated oscillator"* — and it settles three things at once:

```cpp
if(Frequency == 0) { GB_init(&sameboy, GB_MODEL_SGB_NO_SFC);
                     GB_load_boot_rom_from_buffer(&sameboy, &SGB1BootROM[0], 256); }
else               { GB_init(&sameboy, GB_MODEL_SGB2_NO_SFC);
                     GB_load_boot_rom_from_buffer(&sameboy, &SGB2BootROM[0], 256); }
```
with `frequency()` returning `Frequency ? Frequency : system.cpuFrequency()`.

Two things follow. **The boot ROMs are compiled into bsnes**, so `sgb1.boot.rom` and
`sgb2.boot.rom` are never wanted here even though higan and bsnes-mercury ask for
them — a Super Game Boy runs on this core with nothing but the two `.sfc`. And
**`SGB1.sfc`/`SGB2.sfc` are only where RetroXR looks**: an SGB1 dump installed under
the other name yields two adapters that are both an SGB1, and the spawn gate will
not catch it, because `firmware_present` accepts a `MISMATCH` md5 on purpose (see
BS-X.bin). The BIOS / Extras tab is where that verdict is visible.

They are carded on the **Game Boy** tile, not the Super Famicom's, because
`ExpansionCatalog.card_systemid` files a unit under its media and these run Game
Boy cartridges. That is also where a player is standing when they want one.

`RetroXR/Tools/cores/sgb_probe.tscn` is the measurement, and it needs a real core,
a real `.gb` and the SGB dump, so it is a probe. **The oracle is the frame size,
and it cannot pass by accident**: a Game Boy frame is 160×144 and a Super Game Boy
frame is 256×224, because in SGB mode the SNES is the machine drawing. It does not
depend on the ROM having any SGB support — a game that sends no border packets
still gets the adapter's default frame — so a generated test ROM answers it.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/sgb_probe.tscn -- --core=bsnes \
  --rom="$HOME/retroxr/roms/game_boy/game.gb" --leg=subsystem --shot=res://sgb.png
```

One core AND one leg per process.

**Measured 2026-08-30, and the half that needs no copyrighted dump is settled.**
bsnes publishes, at runtime:

```
Subsystem 'sgb' (Super Game Boy): 2 rom(s), id=4353
Subsystem 'bsx' (BS-X Satellaview): 2 rom(s), id=4368
```

so the ident and the rom count in the catalog row are confirmed against the
running core, not only against its source. **Note the two ids**: bsnes calls SGB
4353, and snes9x calls BS-X 4353. The same number means two different machines in
two different cores, which is exactly why `_start_subsystem_content` resolves by
IDENT and lets the core's own published table supply the id. Never hardcode one.

**bsnes refuses a bare `.gb`** — `retro_load_game` came back false, "This core
refused the game", zero frames — so there is no plain-load path to fall back on
and the subsystem really is the mechanism. (That control run had no `SGB1.sfc`
installed, so it does not distinguish "bsnes has no standalone Game Boy mode"
from "bsnes wanted SGB mode and could not find the cartridge"; either reading
leaves the row as written.)

**The subsystem leg passes end to end**, measured against Donkey Kong (World)
(Rev A) (SGB Enhanced) with the No-Intro `SGB1.sfc`
(md5 `b15ddb15721c657d82c5bab6db982ee9`, 256 KB) in `libretro/system/bsnes/`:
1596 frames at **256×224**, and the arcade-cabinet border rendered in colour with
the Game Boy screen inset. The whole path is proven — catalog row, ident, pair
order, firmware lookup and core.

**Two traps the picture cost, and neither shows up in a log.** The core's frame
carries an alpha channel it never fills, so a straight `img.save_png` writes a
fully transparent image — 13 KB of real picture that every viewer paints as a
blank white rectangle. `sgb_probe` flattens to `FORMAT_RGB8` before saving. And
`--headless` gives back a correctly SIZED frame with nothing drawn into it, so
the size oracle reads 256×224 and passes while the shot is blank; run windowed
whenever the border is what you are checking.

Sample late, and more than once. The frame is 256×224 from the very first frame,
because the SNES draws the whole field whether or not the border has arrived —
the border lands when the game sends its SGB packets, which for Donkey Kong is
somewhere past ten seconds. `--at=8,16,26` rather than one fixed moment.

**bsnes saves through its own VFS, not through RetroXR's SRAM path, and this is
true of every bsnes machine rather than only the Super Game Boy.** Read at source
and confirmed on disk:

```cpp
void *retro_get_memory_data(unsigned id) { return nullptr; }
size_t retro_get_memory_size(unsigned id) { return 0; }
```

Every id, `RETRO_MEMORY_SAVE_RAM` included — so `SetSramPath` and everything
`SramPaths` composes reaches nothing. bsnes instead answers `save.ram` out of
`program.cpp`'s VFS by asking for `RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY` and
appending the loaded ROM's base name, which lands at
`libretro/save/bsnes/<rom>.srm`. Playing a Game Boy game through the adapter
leaves exactly that file, and no `cart_save_dir` subdirectory is created at all.

The save is therefore the Game Boy cartridge's, which is right — the battery is
in the cartridge, not the adapter, and `ExpansionCatalog` deliberately gives the
adapter no `save_owner` for that reason. But it is keyed to the ROM's **filename**
where every other core's is keyed to the cartridge's `save_id`, so renaming a ROM
orphans its save, and two copies under different names keep separate ones. The
Saves panel, save backup and netplay's SRAM transfer all read the `SramPaths`
file, which for this core is not the one being written. Not yet reconciled;
`expansion_tests` pins RetroXR's half and says in as many words that it is not
claiming the core's.

### 2i. The Sufami Turbo — two cartridges in one adapter

The Bandai adapter that goes in a Super Famicom slot and takes **two** small
cartridges, nine of whose thirteen games link the one in slot B into the game in
slot A. It is the only unit in `ExpansionCatalog` with more than one bay, and the
reason a bay is addressed by index at all.

**snes9x has the same dead constant here that it has for the Super Game Boy.**
`RETRO_GAME_TYPE_SUFAMI_TURBO` is `#define`d *and* has a working `case` in
`retro_load_game_special`, and is registered in no subsystem — so no frontend can
reach it. Do not be fooled by the grep hit; that is twice now in one core.

What IS advertised, confirmed at runtime, is:

```
Subsystem 'multicart_addon' (Multi-Cart Link): 2 rom(s), id=4357
Subsystem 'bsx' (BS-X): 2 rom(s), id=4353
```

The Multi-Cart Link case sniffs the FIRST cartridge with `is_SufamiTurbo_Cart`
(size in `0x80000..0x100000`, `"BANDAI SFC-ADX"` at 0, and *not* `"SFC-ADX BACKUP"`
at 0x10 — that marker is what makes STBIOS.bin the BIOS rather than a cartridge),
loads `STBIOS.bin`, and calls `LoadMultiCartMem(A, B, bios)`. One cartridge is a
first-class configuration, not half a pair: `retro_load_game` sniffs the same
header and maps slot B empty.

**A missing STBIOS.bin does not silently degrade** — measured, because the obvious
guess was wrong. `rom_loaded` stays false and the load is refused outright: zero
frames, `content_load_failed`. Note `Cart is Sufami Turbo...` prints in that case
too, so that line alone is not a pass. The line that means it really mapped is
`Map_SufamiTurboLoROMMap`.

**Measured 2026-08-30** with the No-Intro set: SD Ultra Battle Ultraman Densetsu
in slot A and Seven Densetsu in slot B, 767 frames at 256×224, and the game
itself reporting the B cassette's backup state — which is the proof the link is
live, since a game that could not see slot B would not mention it. Poi Poi Ninja
World runs the single-cartridge path.

**Both cartridges keep their saves, and it took a bridge change to do it.**
`retro_get_memory_size` answers `RETRO_MEMORY_SAVE_RAM` and
`RETRO_MEMORY_SNES_SUFAMI_TURBO_A_RAM` from the same case — slot A alone — while
slot B sits under `_B_RAM` at `(4 << 8) | RETRO_MEMORY_SAVE_RAM`, a core-specific
id defined in snes9x's own `libretro.cpp` rather than in `libretro.h`. Reading
only `SAVE_RAM` gave 16384 bytes whether one cartridge was in or two, so a linked
pair kept half its progress; SD Ultra Battle said as much every launch, reporting
that the B cassette's backup was not initialised.

`Libretro.SetSramBPath` now carries slot B to a file of its own, with ordinary
save semantics — read back at content load, written when it changes — unlike
`SetPackPath`, which writes over the medium and never reads. The A id is
deliberately NOT used: the core answers it and plain `SAVE_RAM` from one case, so
asking for both would write one cartridge's save to two files.

The path is keyed off the **cartridge**, not the slot (`RetroSystem._slot_b_save_path`),
so a game carries its save between the two wells and lending it to a different
pairing does not overwrite it.

**Every dump is named `.sfc`, not `.st`.** `libretro-core-info-retroxr/snes9x_libretro.info`
overrides `sufami_turbo:st,sfc` for that reason — otherwise the library files them
under `super_nes` and the adapter's bay refuses them. That override is a WHOLE
copy of the vendored file: the overlay replaces an entry rather than merging, so
a one-line file would delete snes9x's firmware declarations with it.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/sufami_probe.tscn -- \
  "--a=$HOME/retroxr/roms/sufami_turbo/<A>.sfc" \
  "--b=$HOME/retroxr/roms/sufami_turbo/<B>.sfc" --sram=/tmp/t.srm
```

The probe cannot read its own log — `Libretro` publishes no log signal — so the
branch is asserted by the CALLER grepping the run. `--sram` reports the flushed
size, which is how the save limit above was measured.

### 2j. The DS's Slot-2 — a second slot on the console, not an expansion

A Nintendo DS has a GBA cartridge slot moulded into its front edge, and some DS
games read it (the Pokémon dual-slot transfer, Mega Man ZX, Portrait of Ruin).
It is the one console with a second NATIVE slot, so it is not an
`ExpansionCatalog` unit: `Slot2Catalog` (one row, `nds` → `game_boy_advance`)
tells `RetroSystem` to build a `Slot2` snap zone, `handheld_model.configure_slot2`
poses it on the front edge (an authored `Slot2Seat` marker wins, as `CartSeat`
does), and `ExpansionLaunch` reads the row as a launch recipe with two new tokens,
`slot2` and `slot2_save`. The recipe exists only while a GBA cartridge is seated,
which is what pins `melondsds` — DeSmuME publishes no such subsystem.

**Verified in JesseTG/melonds-ds (`src/libretro/info.cpp`, `core/core.cpp`):**

```
slot_1_2_roms[] = { "Nintendo DS (Slot 1)" nds, "GBA (Slot 2)" gba, "GBA Save Data" srm|sav (need_fullpath, optional) }
subsystems[]    = { "gba" (3 roms), "gbanosav" (2 roms) }
```
`game[0]` is the DS card, `game[1]` the GBA ROM (the core asserts its data was
read into memory — the bridge does that for every `need_fullpath=false` entry),
`game[2]` the GBA save PATH. **The GBA save never goes through
`retro_get_memory_data`**: the core opens that path itself and **throws on a path
that does not exist** ("Failed to open GBA save file", load refused), tolerates an
empty file, and writes the SRAM back to it itself. So the `slot2_save` token
CREATES the file when it is missing, keyed off the GBA cartridge's own `save_id`
under the GBA game's stem (the save follows the GBA game between DS games).
`gbanosav` is not a fallback: it never writes a save.

The bridge needed no change; `WrapperEmuThread.cpp` already handles per-rom
`need_fullpath` and refuses a missing file up front. Netplay starts every
machine through the single-ROM path, so a DS with a GBA cartridge boots its
DS card alone in a session — not extended.

`expansion_tests` `slot2/` (27 cases) pins the gates, the pose (printed basis:
top edge out of +Z, label down), the recipe order and the save file's existence.
What no suite covers is the core actually taking the pair: that needs melondsds,
the DS firmware, a DS ROM and a GBA ROM, and has not been measured yet — the
log line to look for is `Loading subsystem 'gba' (id=...) with 3 file(s)`.
