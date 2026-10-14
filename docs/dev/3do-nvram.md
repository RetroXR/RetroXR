# §2n-3do — the 3DO's NVRAM, the console's own

A 3DO saves every game to 32 KB of battery-backed NVRAM on its board, as a Saturn saves to
its System Memory, and it is modelled the same way: `SystemInfo/3do.tres` declares
`console_memory = "3do_nvram"` (and `save_device`), so every 3DO in the room carries a
`ConsoleMemory` whose `card_id` is saved with the room, is managed from the console's
**Saves** tab by the card panel's own code, and keeps its image at
`save/memcards/3do_nvram/<card_id>.nvram`.

### The layout — `ThreeDoNvram`

Portfolio OS's "linked memory" file system, read from the OS itself
(trapexit/portfolio_os: `src/filesystem/LinkedMemFileSystem.c`, `includes/filesystem.h`,
`discdata.h`) and from Opera (`libopera/opera_nvram.c`). Big-endian. A 132-byte disc label
(record type 1, `ZZZZZ`, structure version 2, block size **1**, root avatar 0 = the list's
offset), then one circular doubly-linked list from an anchor: every block is fingerprint,
flink, blink, block count (header included), header count. A file's header is 64 bytes
(then byte count, unique id, type, a 32-byte name); a free block's is 20. The list runs in
address order and wraps to the anchor — that is how the OS finds the last block.

- **A block is a byte, so the card panel's unit is a byte.** A save costs the bytes its file
  occupies past its header; free is the OS's own figure (`LinkedMemDoStat`): every free
  block less a 64-byte header. On a blank, both are 32552.
- **Writing is the OS's allocator**, first fit from the anchor, split only when 64 + 32
  (`LINKED_MEM_SLACK`) would be left, otherwise the file takes the whole block. Deleting
  marks the block free and joins the free run either side. Names compare without case.
- A file is exported as RetroXR's own `.3dosav` (magic `3DOSAVE\0`, name, type, unique id,
  byte count, then every byte the file occupies) — nothing standard carries a 3DO file's
  type and end of file with its data. RomM also accepts `.srm` / `.nvram` whole images.

### Getting it to Opera — `ThreeDoStorage`

**Opera exposes NO SAVE_RAM** (`retro_get_memory_data` returns NULL): it keeps the NVRAM in
a file of its own under the save directory (`<root>/save/opera/`), read in
`retro_load_game`, written in `retro_unload_game`, on reset and before an ODE disc switch.
Its default, `opera_nvram_storage = "per game"`, gives every disc its own NVRAM under
`opera/per_game/<rom stem>.<version>.srm` — not how the machine works. So `ThreeDoStorage`
pins `opera_nvram_storage = "shared"` and `opera_nvram_version = "0"`, which names ONE file,
`opera/shared/nvram.0.srm`, and does what `SaturnStorage` does for a cartridge: stage the
console's image into it before content starts, drain it back every 2 s while running and
for 12 s after stop, a manifest for a crash, **one 3DO at a time** (the file is shared by
every machine on the core). `MemoryCardController._compose_sram_path` returns `""` for a 3DO
on Opera: a per-disc `.srm` would never be filled.

- An unclaimed shared file (the player had switched the option on; an older Opera's
  `3DO.nvram` in the save dir, which Opera still falls back to) is moved into `legacy/`, and
  a NEW console's NVRAM starts from it (renamed `.imported` once taken). The FIRST image of
  the family ever made also takes the saves Opera kept per game, which stay where they are.
- Not staged in a netplay start: Opera carries the NVRAM in its savestate, so a session's
  state transfer would hand every peer the HOST's, and draining it back would write the
  host's saves over this console's. Opera is not netplay-vetted anyway.
- A savestate carries the whole 32 KB too, so loading an old state rewinds every game's
  saves on that console, as a Saturn's System Memory through SAVE_RAM does.
- **A BIOS goes in `system/opera/`** (RetroXR hands each core `system/<core>/`), named as
  Opera's `.info` names it (`panafz10.bin`, …), and is chosen by `opera_bios`.
- Opera emulates no FZ-EM256 or any other external saver: its XBUS carries only the CD
  drive. Portfolio could mount a linked-memory volume on a "gamesaver" cartridge, so a
  fork would have the OS side for free.

### Measured 2026-10-14

`Tools/cores/three_do_nvram_probe`, Opera 1.0.0 `5a09dc4` (buildbot nightly), Panasonic
FZ-10 BIOS (`panafz10.bin`), Gex (USA Europe). One leg per process, windowed:

- `--blank`: Opera's own formatted NVRAM is `ThreeDoNvram.blank_image()` byte for byte
  (`card_tests` pins its SHA-256).
- Gex's disc OS creates `GEX_Videos` (1460 bytes, type four spaces) at boot. Laid into a
  blank by `ThreeDoNvram.write_file`, it is the image the OS wrote **byte for byte** — once
  the split-off free block carries the rest of the entry the OS first wrote (its name and
  type; 14 bytes differed before that).
- Default leg: an image holding a file RetroXR wrote comes back with it read exact, and
  Gex's file placed after it in the first free block, split as `write_file` splits.
- `--broken` (the control for "the OS checks NVRAM"): the same image with the file's
  forward link bent by 4 comes back REPAIRED, identical to the default leg's result. A
  disc's Portfolio OS runs `lmadm -a … nvram` at startup (`filesystem/fscheck.c`), so the
  default leg coming back unchanged is the OS reading RetroXR's layout and finding it whole.
- `--pergame` (the control for the pin): with Opera on its default the shared file is not
  touched and Gex writes `opera/per_game/Gex (USA Europe).0.srm` instead.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/three_do_nvram_probe.tscn -- --root=<throwaway root with cores/opera_libretro.dll and system/opera/panafz10.bin> \
  --rom="<roms>/3do/Gex (USA Europe).chd" --run=45 --at=10,25,44 --shot=C:/tmp/3do.png [--blank|--broken|--pergame]
```

Point `--root` at a throwaway root: the probe writes its `save/` and `core_options/`.

Still owed, and why: no save made in GAMEPLAY (Gex writes its file at boot; nothing here has
saved a game in progress or deleted one, so the OS's delete is read from source, not
measured); Opera's embedded "Opera Boot" (upstream `684926f`, 2026-10-13) is newer than the
buildbot core measured, and with no BIOS file that core boots nothing; a RomM round trip of a
`.3dosav`; the Quest; and a crash loses everything since the last reset, as nothing reaches
the file until the core unloads.
