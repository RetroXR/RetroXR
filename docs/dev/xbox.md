# §2u — the Xbox, on xemu

Added 2026-09-19. The systemid is `xbox` (ES-DE's and libretro's agree, so no `LEGACY` row).
The core is `xemu`: RetroXR's own libretro port of xemu, a frontend (`ui/libretro/`) over the
whole QEMU machine. It is not a fork of a libretro core — upstream xemu has none, and the
vendored `xemu_libretro.info` describes someone's older attempt the buildbot never built.

## Where the core comes from — our own release, which began as a branch

`github.com/RetroXR/xemu`, branch **`retroxr`**, released as **`retroxr-xemu-libretro-v1`**
(`17e738cbd4`) on 2026-09-19. `CoreSources.SOURCES["xemu"]` carries that `known_tag` and
still names the `branch`, which the tags sit on.

- **The buildbot has no xemu row** for `_apply_own_sources` to override, which no other entry
  can say, so an own-only core is listed by `_list_own_core`: from `known_tag` at once, and
  otherwise **when the version probe hears of a release**.
- That second case is how this entry began, and is kept for the next core that starts that
  way (`is_released`): with an empty `known_tag` the core was unlisted — nothing offered a
  download that could only 404, the probe's 404 was logged as the expected answer, not warned
  about — and the first release then reached installed copies **with no app build**.
- Checked through the URLs `CoreSources` composes: `/releases/latest` names the tag (not a
  pre-release), `xemu_libretro.dll.zip` and `xemu_libretro_android.so.zip` both answer 200
  with the bare library at the zip root (sha256 `57014994…` and `85a293fb…`). The release
  also carries two `LICENSE-*.txt` assets, which nothing asks for by name. **Built locally —
  that fork has no release workflow yet**, unlike the others. xemu is GPLv2: the tag beside
  the binary is an obligation.
- **Installed through the app's own downloader, end to end** (2026-09-19, Windows, the live
  buildbot and GitHub): 238 rows listed, 227 of them the buildbot's and none of those xemu;
  the version probe answered `retroxr-xemu-libretro-v1`; the xemu row carried our asset and
  `source: retroxr`; the download unpacked to the same bytes as the zip's library; and
  `cores_manifest.json` gained exactly one row, `xemu` at that tag — which is what lets a v2
  read as UPDATE. Before that the core was hand-placed, which counts as installed and
  records no version. Halo then booted on it, 2,767 frames in 50 s, both Memory Unit
  options declared.
- This build reports `0.8.136-107-g17e738cbd4`. Earlier ones said `…-49-gf9b14039e5`, the
  fork's MASTER head, whatever they were built from — which matters to netplay, where
  `GetCoreIdentity()` is what tells two builds apart.
- A later release: move `known_tag` and the tag in the overlay `.info`'s header together.
  A hand-placed core still counts as installed everywhere (the tiles, the Manager and
  "Download All Recommended" all read the disk).

## The overlay `.info` differs from the fork's in one way that matters

`libretro-core-info-retroxr/xemu_libretro.info` is the fork's `ui/libretro/xemu_libretro.info`
with the three retroXR name fields and **bare firmware paths**. The fork writes
`xemu/mcpx_1.0.bin`, for a frontend with one shared system directory. RetroXR hands every
core `system/<core>/`; the core sees a system directory already named `xemu` and uses it as
its own folder; and `FirmwareRequirements.destination` resolves against that same directory.
Left as the fork has them the paths name `system/xemu/xemu/` — the BIOS tab reports present
files missing, and a RomM firmware install lands where the core never looks.
`xbox_tests` `system/` fails on a `/` in any of them. **Re-apply this when refreshing the
overlay from the fork.**

Runtime files, all in `system/xemu/`: `mcpx_1.0.bin` (512 bytes), a flash BIOS — **either
`Complex_4627v1.03.bin` or `Complex_4627.bin`**, two different Complex 4627 dumps (md5
`21445c6f…` and `ec00e31e…`), each measured 2026-09-20 alone in the folder to boot Halo to
its menu and an empty tray to the placeholder. Both are listed OPTIONAL in the `.info`,
because `firmwareN_opt` cannot say "one of these"; what requires one is `BiosBoot`'s
`boot_rom` group with `media_needs_boot_rom`, the same mechanism a regional PlayStation set
uses. The core takes more names than these and any `.bin` of 256 KiB or 1 MiB, but the list
stays at what has been BOOTED here: a retail 3944 stops at "Your Xbox requires service" and
a retail 5838 draws nothing, `xbox_hdd.qcow2` (mandatory, NOT generated — the stock
xemu image), `xbox_eeprom.bin` (optional, generated). The core also writes its shader caches
there (`shaders_vk/`, `vk_pipeline_cache.bin`, `shaders/`, `shader_cache_list`): they are
neither firmware nor saves.

## What the core is, as far as the room cares

- `iso|xiso`, by full path. **XISO only** — no archive, no CHD: QEMU opens the file. A disc
  in a `.7z` is extracted, never handed over.
- A software framebuffer (`hw_render = false`), 640x480 at 60 fps, though it needs GL 4.0 or
  Vulkan 1.1 underneath; Android is Vulkan only.
- **No save states**, so no rewind, no netplay.
- Port devices are `Xbox Controller`, `Xbox Controller S` and `None` — which is why `xbox`
  is in `system_tests`' `without_gun` list although guns were sold for it.
- RetroAchievements: none (`RaConsoles.UNSUPPORTED`; rcheevos reserves console 22, RA has no
  sets, and the core publishes no memory map).
- Diagnostics below WARN are dropped by libretro-godot; the core's user-facing failures come
  as `SET_MESSAGE` + ERROR.

## One Xbox at a time

QEMU builds its machine once per process. Since `9d29e0b3c6` the first copy of the library
loaded owns the machine and every later copy forwards to it, so sequential launches work
(unload, load the next disc, even from a fresh temp copy) and a SECOND running console is
refused by the core. `XboxStorage.busy_elsewhere` refuses first, in the room's words, the way
a second Sega CD is refused. Every loaded copy stays pinned in memory (~100 MB a launch);
reusing one temp path per core in libretro-godot would fix that and is not done.

## Saves, and how they reach RomM

Every game saves to the console's hard disk. The core copies `system/xemu/xbox_hdd.qcow2` and
the EEPROM to `save/xemu/xemu/` on first use and only ever writes the copies — ONE disk for
every game, because libretro-godot hands out `save/<core>/`, never a per-content directory.
Optional 8 MB Memory Units are `save/xemu/xemu/memory_unit_port1..4.img`.

There is no `SAVE_RAM`, so no `sram_flushed`, so `RommSaveSync` never hears of an Xbox save.
And the disk cannot be what is backed up: a record holds one `rom_id` and the games would
fight over it (the reason `push_card_save` gives for memory cards), and it is ~300 MB once a
game has built its cache. So it is treated as a card is — **the one game's saves are lifted
out and pushed under that game, upload-only**:

1. `XboxStorage.note_started` records the disc as content starts (the tray may hold another
   by the time it stops).
2. `backup_after_stop` waits `SETTLE_AFTER_OFF_SEC` (8 s). `retro_unload_game` blocks until
   the machine is paused, and the pause is `vm_stop()`, which runs `bdrv_flush_all()` — but
   `StopContent` returns before the emulation thread gets there.
3. On a worker thread: `XboxDisc.title_of` reads the **title id** from the certificate of the
   disc's `default.xbe` (Halo `4d530004`, Conker `4d530051`); `XboxHddSaves.lift` opens the
   qcow2 READ-ONLY (`Qcow2Image`), reads the FATX data partition E: at `0xABE80000`
   (`FatxVolume`) and takes `UDATA/<title>` and `TDATA/<title>`; `pack` makes the archive,
   its paths `UDATA/<title id>/…` and `TDATA/<title id>/…` — the title id IN them, so the
   archive says whose it is and a Memory Unit can take its UDATA half as it stands.
4. `SaveSync.push_card_save(key, rom_id, "xemu", <title id>, label, bytes, "zip")`, key
   `card_save_key(<hdd path>, <title id>)`, gated on `is_key_enabled` like a card save.

**Everything read is checked**, because the parked core may still hold the image: a name that
is not a name, a cluster off the volume, a chain that loops, runs through a free cluster, or
disagrees with its file's size fails the WHOLE lift. A failed lift uploads nothing, so a torn
read can cost a backup and never replace one. A game that never saved is no files with
`ok = true` — not a failure, and nothing to upload.

**The archive is written by hand, not with `ZIPPacker`**, which stamps entries with the time
they were packed: the md5 would move on every power-off, and `RommSaveSync` uploads when the
md5 moves. `pack` sorts paths, stores rather than deflates, and dates everything 1980-01-01.
Its CRC-32 is read out of a gzip trailer (the engine has no CRC-32 to call); `xbox_tests`
pins it to the published check value.

Refused rather than guessed at in `Qcow2Image`: encryption, a backing file, compressed
clusters, an external data file, extended L2 entries. The dirty bit is accepted — it is about
refcounts, which nothing reads.

**Measured 2026-09-19**, `Tools/cores/xbox_boot_probe`, xemu `9d29e0b3c6` on Windows (RTX
5070 Ti, GL renderer), each leg its own process from a throwaway root holding the pristine
4.5 MB disk:

| disc | frames | what it reached | lifted 8 s after stop |
|---|---|---|---|
| Halo - Combat Evolved (USA) (Rev 2) | 2,789 in 50 s | main menu, by scripted Start/A | `UDATA/` TitleMeta, TitleImage, SaveImage — 14,370 bytes |
| Conker - Live & Reloaded (USA) | 5,024 in 90 s | the bar menu | the same three plus `TDATA/preferences.bin` — 15,436 bytes |

In both, the disk **opened for reading while the core held it for writing** (QEMU's Windows
open shares reads only; Godot's `FileAccess.READ` denies nothing, which is what that needs),
and both started from a disk with no saves, so what was lifted is what the game wrote during
the run.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/xbox_boot_probe.tscn -- --root=<throwaway root> \
  --rom="<disc>.iso" --at=8,20,35,50 --press=38:start,42:a --shot=C:/tmp/xbox.png
"$godot" --headless --path RetroXR res://Tools/cores/xbox_saves_probe.tscn -- \
  --iso="<disc>.iso" --hdd="<a COPY of xbox_hdd.qcow2>" --zip=C:/tmp/saves.zip
```

The throwaway root needs `cores/xemu_libretro.dll` and `system/xemu/` with the three files;
the probe writes its `save/` and `core_options/`. `xbox_saves_probe`'s oracle for `pack` is
`python -m zipfile -l`, not the engine reading back its own conventions.

`xbox_tests` builds every fixture itself — a sparse qcow2 of an 8 GB disk, a FATX volume with
fragmented chains, an XISO whose directory tree makes `default.xbe` a left turn — and was
mutation-tested: unchecked chain length, a free cluster in a directory's chain, unvalidated
names, a file not cut to its size, compressed clusters, the COPIED flag, the zero flag, a
tree that never turns left, a seek that ignores the partition base, and an unsorted archive
each fail exactly their own cases. **A fixture trap worth knowing:** a `PackedByteArray`
read out of a `Dictionary` is a COPY. The first fixture poked copies, left every FAT entry
zero, and would have passed every torn/ case for the wrong reason — the unbroken-disk
control case is what caught it.

## Switched on with an empty tray

An Xbox with nothing in it boots its DASHBOARD, and the dashboard is software on the HARD
DISK rather than anything in the BIOS — so what a player sees is whatever their disk carries.
`BiosBoot`'s `xemu/xbox` row is what allows it: `no_content` (there is no blank disc to hand
an Xbox) gated on the flash BIOS being installed.

Without that row an Xbox could not be switched on empty AT ALL, and a disc sitting in a tray
still open got "Close the tray" instead — the verdict asks "can this machine start empty?"
before it asks about the tray, so one missing row produced both complaints.

**The stock image has a placeholder where a dashboard would be.** `C:\xboxdash.xbe` on the
4.5 MB image is an nxdk sample, title id `ffff0002`, name `hello`, and all it draws is one
line: "Please insert an Xbox disc...". That is the machine working. A real dashboard needs a
disk image the player supplies, and nothing here can ship one.

**Measured 2026-09-20**, the v1 release core, OpenGL and Vulkan alike: 452 lit pixels of
307,200, in a band at x 25..280, y 25..31 of 640x480 — and the same after a stop and a second
start in one process, which is the power cycle a core that read a missing path as a medium
named `""` would fail on. Both no-content conventions were tried and this core takes either.

**A warning about how that was measured, which cost a day.** The first pass sampled every
eighth pixel and reported the frame as uniform black — a line of 8-pixel text is twelve rows
high, and a sparse grid steps between the strokes. On that reading the empty boot was written
off as useless and a whole mechanism was built to refuse it. `xbox_boot_probe` counts every
pixel now and prints the bounding box beside the count, because "lit=0.000" was the wrong
answer to a question nothing else could check.

**A latent bug this uncovered, not fixed here.** `no_content` is supposed to hand the core a
NULL game info: `system.gd` sets `SetNoContentPassesNull(true)`, calls `StartContent`, and
sets it back to false on the next line. But `StartContent` only spawns the emulation thread
and returns, and that thread reads the flag later, when it loads the core — so the reset wins
the race and every no-content start passes a ZEROED struct instead. Measured both ways here:
with the reset the core logs "passing a zeroed game info", without it "a null game info".
xemu takes either, so the Xbox is unaffected, but the rows that are NOT are `mgba/gba`,
`dolphin/gc` and `pcsx2/ps2` — and this table's own header says dolphin "dies on a zeroed
one". Worth fixing on its own, with those three tested; the default is already `true`, so the
reset may simply be wrong.

## Memory Units — in the controller, two to a pad

An Xbox's games save to the hard disk. A **Memory Unit** (8 MB) is where a player COPIES a
save to carry it, and it goes in a CONTROLLER, two to a pad: the console calls them 1A and 1B
for the pad in port 1. Here it is `XboxMuCard` (`Scenes/Objects/controllers/xbox/xbox_mu.tscn`),
family **`xbox_mu`**, image `save/memcards/xbox_mu/<card_id>.xmu` — the unit's 8 MB, byte for
byte. It carries `card_id`, `family`, `card_label` and `minted`, so the memory card panel,
the card shelf and a saved room treat it as they treat a VMU. `xbox.tres` declares NO
`card_family` (that drives CONSOLE slots) and no `save_device` (games do not save here).

**It shares the VMU's sockets rather than having a pair of its own.** The pad an Xbox wears
is the primitive box, the same one a Dreamcast wears, and both consoles carry their two
slots in the pad's top edge — a second pair would be two sockets in one place. `VmuPort`
accepts a second group, `XBOX_SLOT_GROUP`; the primitive pad and the pad receiver take
either console's devices, a pad made for one console only that console's. Everything else
is asked of whatever is seated, by method: a unit answers `slot_option_value()` with
`"None"` (what a Dreamcast should hear about it) and `VmuStorage`, which asks for CARDS, is
handed none. Seating is saved on the pad under `"vmus"`, unchanged. **Its origin is 40 mm
below the connector end, like the VMU's, not at its own centre** — a seat places an origin,
and the body's 40 x 50 x 12 mm is an ESTIMATE nobody has measured.

**xemu takes no path for a unit.** Each is a fixed file in the core's save folder, switched
on by its own option (`XboxStorage.UNIT_SLOTS`, one line a slot):

| slot | option | file in `save/xemu/xemu/` |
|---|---|---|
| A, top | `xemu_memory_unit_port<N>` | `memory_unit_port<N>.img` |
| B, bottom | `xemu_memory_unit_port<N>b` | `memory_unit_port<N>b.img` |

So `XboxStorage` STAGES a seated unit's image into that file and switches the option on —
and every other slot's OFF, because the options persist in the core's `.opt` — then DRAINS
what the console writes back: every 5 s while it runs, for 12 s after it stops, and for 6 s
after a pull. Three rules from the cards before it: a drain goes to the unit that FILLED the
file; a file that does not check out is never copied back (`XboxMemoryUnit.is_consistent`
walks the WHOLE tree — `is_card_image` asks only about the root, and a unit cut off inside a
save still lists from its root); an empty slot's file is left alone, not deleted.

**Hot-plug is live**, unlike the VMU's: the core re-reads these options whenever one changes
(`update_variables` → `cmd_sync_ports` → `sync_memory_unit`), so `reapply` stages and flips
the option mid-game. `reapply_vmu` on the machine calls both storages; each ignores what is
not its own.

**Slot B needs a core that has it**, which is `03a3fb9ea2` and later: the libretro port
wired the top slot only (`MEMORY_UNIT_SLOT 0`) until slot B was asked for on 2026-09-19,
under the names above. An older build declares no `…port<N>b` option, which `XboxStorage`
reads from what the running core declares: a unit in the lower slot gets a toast saying so
rather than looking seated and doing nothing.

**Never write a slot's file while its option is on** — the console may hold the unit's FAT
in memory. The core's answers, which the code is built on: switching an option off unplugs
the USB device, which flushes and CLOSES the file before the `retro_run` that sees the
change returns; `retro_unload_game` flushes the units but leaves them open (the machine is
parked), which is fine, because nothing here writes them until the next start; while bound,
writes reach the host page cache at once, so a drain reads current bytes. So seating over a
slot used this run is OFF → `UNIT_RELEASE_SEC` (0.5 s) → drain the old unit home → stage →
ON (`_seat_once_released`); a slot never enabled this run is staged and switched on at once.

**The console's own view comes from the core**, at WARN (libretro-godot drops anything
lower) and as a message, once per bind: `xemu: memory unit 1A detected by the console` (the
guest's USB `SET_CONFIGURATION`), `… read by the console` (a mount reads the superblock),
`… written to by the console`. Grep a run for `memory unit`.

**The format** (`XboxMemoryUnit`, static; `XboxMuCardFormat` forwards): a bare FATX volume —
superblock, one 16-bit FAT, 2 KB clusters, root in cluster 1, 4,096 clusters — read through
`FatxVolume` over an `XboxRawImage`, and WRITTEN here too, which the hard disk never is.
A blank matches xemu's `create_fatx_image` field for field; it cannot be pinned by hash,
because xemu's volume id is `rand()`. Saves are `UDATA/<title id>/<save id>/`, with the
game's `TitleMeta.xbx`, `TitleImage.xbx` and `SaveImage.xbx` beside the save folders and
shared by them; `name` is `<title id>/<save id>`, `serial` the title id, sizes in the
console's 16 KB BLOCKS. A 2 KB cluster is 32 directory entries, so a directory GROWS.

**The writer's conventions were checked against the console's own kernel**, by dumping raw
entries off a disk Conker had saved to: names padded with `0xFF`, a directory ended by an
`0xFF` entry, chains ended `0xFFFF`/`0xFFFFFFFF`, folders `0x10`, timestamps packed from the
year 2000 (the kernel's read 26) — all as written here — and ONE thing that was not: the four
`.xbx` files the console's save API writes (TitleMeta, TitleImage, SaveImage, SaveMeta) carry
the SYSTEM attribute, `0x04`, where a game's own file is `0x00`. An archive carries no
attributes, so `_attr_for` restores them by that rule.

**One save as a file is an archive of `UDATA/<title id>/…`** — the layout Xbox save archives
already use, and the one `XboxHddSaves` lifts off the hard disk in. That is what makes a
Memory Unit **the way home for a hard disk backup**: `saves_in_download` splits a lift into
one archive a save, `insert_save` writes one onto a unit, and the console copies it to the
disk from there. Nothing in RetroXR writes the qcow2. `CardFormat.library_systemid()`
(default `id()`) is `xbox` for this family, and `RommSaveSync.rom_id_for_serial` matches a
save's title id against each disc's `default.xbe`, so a save backs up under its game from
the panel without that game having to run.

**Measured 2026-09-19**, `xbox_boot_probe --unit=…`, Windows, GL renderer. First the 12:43
dll, from before slot B:

- The core DECLARES `xemu_memory_unit_port1` and has NO `…port1b` — what the lower-slot
  toast keys on.
- **The unit in 1A is attached:** mid-run a second WRITE handle on
  `memory_unit_port1.img` is refused exactly as on `xbox_hdd.qcow2` (the control), while
  the 1B file opens freely.

Then `03a3fb9ea2`, which has both slots and the three messages, with Conker:

- Both options declared. **RetroXR-FORMATTED blank units in 1A and 1B are each DETECTED and
  READ by the console**, both files held mid-run, and both md5s unchanged after the unload:
  the kernel does not reformat a RetroXR blank.
- **Hot-plug, live, both slots:** option off at 78 s and 80 s → two seconds later each file
  is CLOSED (a write handle opens) and walks whole; a fresh unit staged and switched on at
  84 s and 88 s → `detected` and `read` again for each, mid-game, no restart.
- Three real Halo profiles (`savegame.bin` 3.67 MB each, 225 blocks) lifted from a disk Halo
  had written; two fit a unit, written by `insert_save`, and read back consistent after the
  core's unload.
- **No game here puts a unit's contents on screen.** Halo only ever `detects`: it never
  offers a unit when saving a profile, and on a fresh disk with two profiles on unit 1A its
  profile list is EMPTY. Conker `reads` both units at its Profiles screen and still does not
  list from them — control: its profile `1` on the HARD DISK lists as `1` then `New Profile`;
  the same profile only on a RetroXR-written unit, profile-less disk, lists `New Profile`
  alone. New profiles go to the hard disk with no device prompt and no `written`. (It likely
  reads units for Xbox Live accounts.) On hardware, copying to a unit is the DASHBOARD's job.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/xbox_boot_probe.tscn -- --root=<throwaway root> --rom="<disc>.iso" \
  --unit=1A,1B [--unit-save | --unit-from=<a qcow2 with that game's saves>] \
  --at=58,66 --press=26:x,30:x,34:x,38:x,42:x,50:down,52:down,54:b --shot=C:/tmp/mu.png
```

Conker: `--press=40:start,45:start,55:b,60:b,65:b,70:b` reaches its Profiles screen by
~72 s (both `read` lines arrive on the way); `76:b,81:start,86:b` opens the New Profile
keyboard, and `92:right,94:b,97:left,99:b` types `1` and presses Create.
`--pull=1A:78 --seat=1A:84` is the hot-plug leg.

RetroPad **B is the Xbox's A** (bottom face button) and RetroPad X its Y: `a` in a press
list confirms nothing. `x` skips Halo's intro videos and does nothing on its menus, which
Start does not — a second Start selects Campaign once a cached disk boots faster. That
press list opens Settings → SELECT PROFILE TO EDIT; `60:x` there is CREATE NEW.

## Still owed

- **A real upload to a real RomM.** The server here has no Xbox platform, so no `rom_id`
  exists to attach to; what is proven is the lift on real disks, and the multipart request
  byte-for-byte against the fake server (`romm_tests` `xbox/`). Never present that as the
  end-to-end proof.
- **Restore.** Writing FATX into a disk a parked core may hold is not built; the server is a
  backup and never a source.
- **That the console PARSES what RetroXR's writer writes.** Proven: it detects and reads a
  RetroXR-formatted unit in either slot and does not reformat it. NOT proven: that it
  followed a directory entry `insert_save` wrote — and the two discs here CANNOT show it.
  Measured with the core's own SCSI trace (Memory Units are its only SCSI disks), Conker at
  its Profiles screen, a RetroXR-written unit in 1A: **the guest reads sector 0, the
  superblock, 8 sectors, four times, and nothing else** — not the FAT at sector 8, not the
  root directory at 24, never `/UDATA/` at 28. It mounts the unit and never looks inside,
  which is also why it lists nothing; Halo does not even get that far. So it needs a title
  whose save screen offers Memory Units, or a disk image with the player's OWN dashboard on
  C: (boot with no `--rom`, `--unit=1A --unit-from=<a disk with saves>`, open Memory). The
  probe prints each unit's sector map; reads at 28, 32, 36 on a written unit and not on a
  blank one are the proof. Until then, never say a save RetroXR put on a unit was seen by
  the console.

  ```bash
  XEMU_LIBRETRO_TRACE='scsi_*,usb_msd_*' XEMU_LIBRETRO_LOG=C:/tmp/xemu_trace.log "$godot" … xbox_boot_probe.tscn -- … --unit=1A
  grep -o "scsi_disk_dma_command_READ[^(]*(sector [0-9]*, count [0-9]*)" C:/tmp/xemu_trace.log
  ```

  Both variables must be in the environment before the core loads; the lines go to the file
  (a GUI Godot has no stderr to show them), carry no `pid@time:` prefix in this build, and
  **the exact event names enabled nothing where the wildcards did**. The events do not say
  WHICH unit, so seat one.
- A Memory Unit in a HEADSET, and on the Quest build through RetroXR — nobody has held one.
- A unit's saves have no icons (`SaveImage.xbx` is an XPR0 DXT1 texture nobody decodes).
- A release, and with it `known_tag`. The Quest build exists and runs; nothing here has been
  tried on a headset through RetroXR.
- No console, pad or case model: the placeholder box, the generic pad, a 120 mm DVD.
