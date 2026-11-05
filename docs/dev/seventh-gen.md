# §2u′ — the PlayStation 3 and the Xbox 360

Added 2026-11-05. Two systems, each on the libretro buildbot's own build of its only core:

| | PlayStation 3 | Xbox 360 |
|---|---|---|
| systemid (ES-DE folder) | `ps3` | `xbox360` |
| libretro's id (`SystemIds.LEGACY`) | `playstation3` | `xbox_360` |
| core | `rpcs3` (RPCS3, GPLv2, github.com/WizzardSK/rpcs3-libretro) | `xenia_edge` (Xenia Edge, BSD, github.com/WizzardSK/xenia-libretro) |
| buildbot zips (Windows; Android exists, hidden) | `rpcs3_libretro.dll.zip` / `rpcs3_libretro_android.so.zip` | `xenia_edge_libretro.dll.zip` / `xenia_edge_libretro_android.so.zip` |
| content | `iso pkg sfb sfo bin self elf`, full path | `iso xex zar xcp m3u`, full path |
| firmware | `PS3UPDAT.PUP`, required | none |
| video | HW: Vulkan (default) or GL 4.5 | HW: Vulkan 1.1 (negotiation v2, v1 fallback) or D3D12 |
| savestates | none, so no rewind and no netplay | none, so no rewind and no netplay |
| pads | up to 7 DualShock 3 | up to 4 Xbox 360 pads |
| RetroAchievements | none (`RaConsoles.UNSUPPORTED`) | none |
| ScreenScraper | 59 | 33 |
| in the room | placeholder box, SLOT loader (`SLOT_LOAD_SYSTEMS`), Blu-ray disc | placeholder box, front tray (`FRONT_TRAY_SYSTEMS`), DVD |

## Where the cores come from

**A second Xbox 360 core, `parallel_xbox360`** ("ParaLLEl Xbox360", a libretro fork of
Xenia Edge, BSD), has an `.info` (libretro-super `84ccaff5`, 2026-11-03) and NO build on
the buildbot for any platform yet (checked 2026-11-05). Its `.info` is in, so it lists
the moment one appears. It is hidden on Android like the others, xenia_edge stays the
recommended core, and it gets the same debugger-break pin, on the GUESS that the fork kept
Xenia Edge's option key. Peek its options when a build exists.

Nowhere special. Neither is in `CoreSources.SOURCES`: the download manager lists every
`*_libretro<ext>.zip` the buildbot serves, so both appear in the Cores tab with nothing
added there. **Desktop only** (the owner's call, 2026-11-05):
`CoreSources.HIDDEN_BUILDBOT_CORES` drops both rows on Android, though the buildbot does
publish Android builds, so a Quest has no core and no tile for either. That table sits
beside `SOURCES` rather than in it because a `SOURCES` row carries a repo and assets of
ours. Fork one only when a fix needs to ride with it, as xemu's did.

Their `.info` files were copied in by hand from libretro-super and renamed by
`Tools/rename_systemids.py`; all three are in the mirror's `b90a4ee4` base, so
`Tools/merge_core_info.py` treats them as ordinary upstream files
(`libretro-core-info/README.md`).

## Firmware: the PUP, at the top of the core's folder

RetroXR hands each core `system/<core>/`, so RPCS3's system directory IS
`system/rpcs3/`. The `.info` names `PS3UPDAT.PUP` bare, and `FirmwareRequirements`
resolves it to `system/rpcs3/PS3UPDAT.PUP`, one of the places the core looks. It
installs the PUP on its first content load into `dev_flash/` beside it, after which the
file is no longer read; it is still listed REQUIRED, so a PS3 whose PUP was deleted
after installing says "BIOS required". `seventh_gen_tests` fails if the row ever gains a
folder (the xemu trap, `xbox.md`).

No `BiosBoot` row for either: nobody has seen the XMB or the 360 dashboard come up with
nothing in the drive. A row goes in with the probe that shows it.

## A PS3 game can be a FOLDER

`ps3.tres` sets `folder_content`. A disc dump is a folder holding `PS3_DISC.SFB` and
`PS3_GAME/`; an installed (PSN) game a folder holding `PARAM.SFO`. `RomLibrary` descends
one level and hands the core that file, preferring `.sfb`, then `.sfo`, over anything
else the folder holds that the core declares (an update `.pkg`, a stray `.bin`:
`_MARKER_PREFERENCE`). Flat `.iso` and `.pkg` files list beside the folders as before.

**Every one of those markers is called the same thing**, and the library had keyed a
game by its file's stem everywhere: a shelf of forty dumps was ONE row, and each scrape
wrote its box art over the previous game's. `RomLibrary.content_stem(path)` is the name
a game is known by: the file's stem, except for a marker named for its FORMAT
(`GENERIC_MARKER_STEMS`: `PS3_DISC`, `PARAM`, `EBOOT`), where it is the game's folder,
climbing out of `PS3_GAME/USRDIR/`. It keys the library (`index_by_basename`, the RomM
match in `spawn_view`), the scraped media's file names (`ScrapeQueue`, `MediaDimensions`'
loaders, `RomMedia.scraped_for_rom`) and the manual. A ScummVM marker is named for its
game and keeps its stem.

A scrape HASHES the marker it is handed, which for a folder dump is a small `.sfb`
ScreenScraper will not know, so a dump is found by NAME: `ScreenscraperClient.romnom_for`
sends the folder (`romnom=Uncharted (USA)`), not `PS3_DISC.SFB`. A whole disc image is
hashed in full, md5 AND sha1, which for a 25 GB Blu-ray or an 8 GB 360 disc is minutes of
reading on the scrape's worker thread; nothing caps it. Not run against the live API. An
encrypted (redump) `.iso` needs its `.dkey` beside it, or in `system/rpcs3/data/redump/`.

## One option pinned: Xenia's debugger break

Xenia Edge ships `xenia_break_on_unimplemented_instructions` ON, a debugger break that,
with no debugger attached, ends the process (its docs: it "ends RetroArch"). Here the
process is the room and every machine in it, so `ForcedCoreOptions.no_debug_break` pins
it OFF for `xenia_edge`. Not measured against a game.

## Saves live in the system folder

Neither core uses libretro save files (`libretro_saves = false`): RPCS3 keeps the
console's hard disk under `system/rpcs3/dev_hdd0/`, Xenia Edge its content under
`system/xenia_edge/Xenia-Edge/content/`. So nothing reaches `RommSaveSync`, and a game's
saves are NOT backed up. Lifting them out as the Xbox does is not built.

## Checked, and owed

**Both buildbot DLLs load in libretro-godot on Windows** (2026-11-05, the nightlies of
2026-11-04, 35.1 MB and 7.5 MB zips): `core_options_probe --core=<name> --root=<a
throwaway root holding cores/>` peeks 95 options from `rpcs3_libretro.dll` and 47 from
`xenia_edge_libretro.dll`. That is a dlopen and `retro_set_environment`, nothing more:
both cores refuse to start with no content (`supports_no_game = false`), and neither
asks for its HW context before `retro_load_game`.

`seventh_gen_tests`: every table above for both systems, the `.info` ids and extensions,
the PUP's path, and `folders/` (keys, markers, manual), mutation-tested on the key and
the marker preference. The Blu-ray's "silver even when dual-layer" rule in
`disc_finish()` is NOT under test: it needs an image over 4.5 GiB.

**How they stand in the room:** `Tools/models/seventh_gen_render_probe` (windowed,
`--out=<prefix>`) spawns both placeholder boxes with a disc of each in front, then slides
the 360's tray out: the PS3 builds a `MediaSlot` and no tray, the 360 a `MediaTray` with a
front slide (2026-11-05, both shots checked by eye). The placeholder draws four port
sockets on the PS3 although `native_ports` is 7.

OWED, every one of them: a game booted on either (which is also the first test of RPCS3's
Vulkan path and Xenia's Vulkan negotiation against our VideoHandler), the Quest (hidden, never tried), real console and pad models, power inlets
(`PowerProfiles` has no row, so both are always powered), the saves.
