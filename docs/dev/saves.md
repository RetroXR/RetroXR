# §2p — where a save lives

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

### 2p. Where a save lives — per system, not per core

A cartridge's battery is filed under the system it belongs to, so it survives a change of
core, and a Transfer Pak reads the same file a Game Boy playing that cartridge does.
`Scripts/Data/sram_paths.gd` composes every path:

```
save/carts/<systemid>/<game stem>/<save_id>.srm          a cartridge's battery
save/carts/<systemid>/<game stem>/<save_id>.<core>.rtc   its real-time clock, one per core
save/carts/<systemid>/<expansion_id>/<expansion_id>.srm  a unit's own battery (BS-X, e-Reader)
save/<core>/<game stem>/<save_id>.srm                    on SramPaths.PER_CORE_SYSTEMS
save/memcards/<family>/<card_id>.<ext>                   memory cards
states/<core>/<game stem>/…                              savestates
```

**`save/<core>/` is the core's own directory and cannot be renamed.** `Wrapper.cpp` hands it
to the core as `RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY`, and the cores that write their own files
keep them there — bsnes's `<rom>.srm`, genesis_plus_gx's `.brm`, mednafen_saturn's `.bcr`,
desmume's `.dsv`, opera's `nvram`. RetroXR's own tree is therefore a sibling, like `memcards/`.

**Savestates stay per core.** A libretro savestate is the core's own struct dump.

**Sharing a file across cores is safe because the file is SAVE_RAM and nothing else.**
`WrapperStorage.cpp` persists only `RETRO_MEMORY_SAVE_RAM` and writes the file itself; no core
names it. Read at source:

| core | SAVE_RAM |
|---|---|
| sameboy | `mbc_ram` / `mbc_ram_size` |
| gambatte | `savedata_ptr()` / `savedata_size()` |
| fceumm, cartridge | `iNESCart.SaveGame[0]` / `SaveGameLen[0]` |
| mesen | `mapper->GetSaveRam()` |
| snes9x | the SRAM, capped at `0x20000` |

**`PER_CORE_SYSTEMS` is `n64`, `n64dd` and `fds`**, and each is a measured
incompatibility rather than a precaution:

- Both N64 cores return a `save_memory_data` struct with **no magic and no version**.
  mupen64plus-next's is `eeprom[0x800]`, `mempack[0x8000 * 4]`, `sram[0x8000]`,
  `flashram[0x20000]`, 296,960 bytes. parallel-n64's has the same four fields in the same order
  and then `disk[0x0435B0C0]`, 70,924,480 bytes in all. **The matching prefix is the trap.** The
  desktop default is parallel_n64 and the Quest's is mupen64plus_next, and the bridge reads
  `min(region, file)` but writes the whole region, so one shared file would be 70 MB on the
  desktop and every Quest flush would truncate it, taking the 64DD disk with it.
- fceumm answers SAVE_RAM for an FDS game with `FDSROM_ptr()` — the whole disk image. Mesen
  answers with the mapper's save RAM.

**A cartridge's clock is kept per core, beside its battery.** Cores expose an MBC3 real-time
clock as `RETRO_MEMORY_RTC`, and each lays it out its own way, so unlike the battery a clock
cannot be shared:

| core | clock |
|---|---|
| gambatte | 8 bytes, `uint64_t baseTime_`: when the clock read zero |
| sameboy | 32 bytes, its `rtc` section: `rtc_real`, `rtc_latched`, `last_rtc_second`, `rtc_cycles` |
| mGBA | 48 bytes, `GBMBCRTCSaveBuffer`: live and latched counters and a Unix time |
| snes9x | 20 bytes of S-RTC or SPC7110 registers; unmeasured |

`Libretro.SetRtcPath` hands the bridge the file; `SramPaths.rtc_path` names it
`<save_id>.<core>.rtc` beside whichever file the battery resolved to, and
`MemoryCardController.rtc_path_for_run` answers `""` for a card machine, a console's own memory
and a machine with nothing seated. The netplay start always passes `""`: a clock read from
each peer's own file is a different time on every peer. `delete_save` removes every core's
clock for that `save_id`, and not the clock of `<save_id>.<core>.srm`, the older copy a
migration kept.

In the bridge (`WrapperStorage.cpp`): the path is taken from a mutex-guarded "next" copy at
content load, not hot-swapped, because a cartridge cannot change under a running machine. It
is loaded with the battery, after `retro_load_game` and before the first `retro_run` — **mGBA
copies its whole save buffer, clock included, into the machine on that first run**, so later is
too late. It loads only a file of exactly the core's size, since part of a struct is not a time.
It is flushed with the battery and never announced through `sram_flushed`, which would have
RomM upload it as a save. **A clock with no file yet is written even when unchanged**: gambatte's
value is a start time that only moves when a game sets the clock, so writing only on change
restarted the clock at zero every power-on.

**The Transfer Pak keeps the cartridge's clock too**, through `get_rtc(port)`, the last member
of `retro_transfer_pak_interface` (call 95), declared in `TransferPakInterface.hpp` and in the
fork's `libretro/transferpak_interface.h`. The interface is experimental and RetroXR ships both
ends, so it grows in place rather than by a second call. `TransferPak.cart_rtc_path` names
`<save_id>.<n64 core>.rtc` beside the battery — the battery is shared with a Game Boy, the clock
is the N64 core's own layout — and `RetroSystem` sets it with `SetTransferPakClock` BEFORE
`SetTransferPak`, whose generation bump is what makes the core read the cartridge and ask.

In the fork (`retroxr-mupen64plus-next-libretro`), the MBC3 clock gained a storage backend,
attached in `main.c` after `init_gb_cart` and before power-on; `poweron_mbc3_rtc` loads a kept
clock and a register write saves one, in the same 48-byte layout mGBA uses. Saving on writes
alone is enough: counters plus the host time they were last brought up to date at stay valid
however much time passes. Four bugs came out of the same code, each with a selftest case:

- **Power-on set `last_time = 0`**, so the first read added the whole Unix time: a day count
  wrapped past 511 with the overflow carry set, before a game had touched it.
- **`(days & 0x100)` was ORed into a `uint8_t`**, which truncates it: the counter never reached
  day 256.
- **The hour rollover did `++DAYS_L`**, which wraps at 255 without carrying into bit 8.
- **A write did not commit the time elapsed first**, so a restored clock a game then set gained
  the gap since the last update. The halt bit, a TODO, is honored now as well.

`tools/mbc3_rtc_selftest.c` in the fork runs the real `mbc3_rtc.c` over a hand-moved clock and a
fake storage (the build line is in its header); each of the six fixes, reverted, fails exactly
its own cases. `Tools/cores/transferpak_clock_probe` is the end-to-end check, against Pokémon
Stadium (USA) and `rtc_probe`'s cartridge in port 0. **Its oracle is the savestate**, which
writes per port the 28 fingerprint bytes, five `uint32`s, the clock's `int64 last_time` at +48
and its counters at +56. Measured 2026-09-16: `fresh` holds the current time and writes a
48-byte file of it; `kept` holds day 100 from a clock written five hours earlier. The core from
before the change fails both, with `last_time=0` and day 0. **Still owed:** no game has been run
reading a clock through the pak — Pokémon Stadium 2 with a Gold, Silver or Crystal cartridge is
the case — and the fork change reaches players only with a new release and a `known_tag` bump.

**A clock does not follow a cartridge between cores** — desktop runs a Game Boy on sameboy, the
Quest on gambatte, and the pak on mupen64plus — which would take a converter between the
layouts above.

**Measured 2026-09-16** with `Tools/cores/rtc_probe`, which builds its own cartridge (MBC3 +
TIMER + RAM + BATTERY) whose program sets the clock to day 100 on the first boot and copies the
day it reads back into battery RAM on the next, in a NEW process. The oracle is what the game
saw. gambatte, sameboy and mGBA all read day 100; with the bridge's restore skipped they read
0, 0 and 242.

**Latch before writing the clock.** The probe's first program wrote the day without latching
first; gambatte and sameboy took it, but mGBA filed the write under its latched copy while its
live clock ran from host time, saved a Unix time of `-1`, and read back day 87. Real games latch
first, and so does the probe now.

```bash
"$godot" --headless --path RetroXR res://Tools/cores/rtc_probe.tscn -- \
  --root=<throwaway root with cores/gambatte_libretro.dll> --core=gambatte --leg=set
"$godot" --headless --path RetroXR res://Tools/cores/rtc_probe.tscn -- \
  --root=<same root> --core=gambatte --leg=read
```

mGBA reports `GBA_SIZE_FLASH1M` for SAVE_RAM until its save-type autodetect settles. The first
flush comes after that, so a file lands at the game's real size.

**Which system a save is filed under** is the medium's own `systemid`
(`SramPaths.media_systemid`), else the host's. The Transfer Pak passes its `MEDIA_SYSTEMID`
instead, because it is the one bay that never back-fills a blank cartridge's `systemid`.

**Compose, then resolve.** `cart_save_path` composes the canonical path. `resolve_cart_save`
returns it when it exists, else wherever that `save_id` already has a file — the per-core
layout, or another system's folder — else the canonical path. It **moves nothing**, which is
what lets `_compose_sram_path` and `net_sram_file_bytes` call it while a core runs: the bridge
keeps the path it was handed at power-on and writes to that string on every flush, so a file
renamed underneath a running core silently stops persisting.

**`SaveMigration` moves the old tree once**, from `boot_scene.gd` before any room is built,
guarded by `save/.retroxr_save_layout.json`. Every file is resolved on its own, because one
core's folder holds several systems' saves — Pokémon Stadium and a Transfer Pak's Pokémon Red
both sat under `mupen64plus_next`:

1. the saved room holding that `save_id` (its `cart_systemid`);
2. else the ROM library folder holding a ROM of that stem — unless two folders do;
3. else it stays where it is, and `resolve_cart_save` still finds it.

Only `<core>/<stem>/<save_id>.srm` (a 16-hex id, or one a room names) and
`<core>/<expansion_id>/<expansion_id>.srm` move; anything else under `save/<core>/` is the
core's. When two cores hold a copy of one `save_id`, the newer keeps the name and the older
becomes `<save_id>.<core>.srm` beside it, where the Saves panel lists it. Each move carries its
RomM ledger record (`RommSaveSync.rekey`), so the next sync compares against the same
`last_hash` instead of forking a conflict. A failed move leaves the marker unwritten, so it is
retried next launch.

**Measured 2026-09-16** on a copy of this desk's save tree against its real rooms and ROM
library: 24 moved, 1 left (`BS F-Zero (flash-mode test)`, which nothing names), 0 failed, in
540 ms, with the 12 N64 saves left in place.

`system_tests` `sram/`, `rtc/` and `migrate/` cover it, the migration over a scratch tree and
never the player's saves. Mutation-tested: filing the Transfer Pak under no system, dropping
`n64` from the table, reversing the collision order, dropping the core from a clock's
name, or letting a delete take a lookalike save's clock each fails exactly its own cases.
