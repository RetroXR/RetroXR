# Systemids — ES-DE's folder names, and the three things that are not systemids

A systemid is ES-DE's folder name for the machine: `n64`, `snes`, `gb`, `psx`. Until
2026-09-18 it was libretro's (`nintendo_64`, `super_nes`, `game_boy`, `playstation`).
`Scripts/Data/systems/system_ids.gd` is the one table: `SystemIds.LEGACY` maps the 60 ids
that changed, and an id ES-DE has no folder for (`ereader`, `vmu`, `sega_pico`, `pcxt`, the
single-game cores) kept its name. Where ES-DE has regional folders the primary is the US
one for Sega and NEC — `genesis`, `segacd`, `tg16`, `tg-cd` — and `cdi` stayed `cdi`.

**Three namespaces look like systemids and are not. None of them moved, and all three are
persisted**, which is why the rename could not be a sed:

- a memory card's `family` — `playstation`, `gamecube`, `playstation2`, `sega_saturn*`,
  `sega_cd*`, `vmu`. It names `save/memcards/<family>/`. `CardFormat.romm_systemid()` is
  where a family becomes a systemid, through `SystemIds.canonical`.
- an expansion unit's id — `sega_cd`, `sufami_turbo`, `nintendo_64dd`, `jaguar_cd`. It names
  `save/carts/<host>/<expansion_id>/`. A unit's ROW holds systemids (`host`, `media`, `card`)
  and a BOOT key is `<host systemid>|<unit id>|…`, so `genesis|sega_cd|sega_32x` is right.
- a `model_id` — `nes`, `playstation`, `nintendo_64`, `atari_2600`. Saved in rooms and sent
  to netplay peers. The row's `"platform"` is the systemid.

File and folder names that merely contain an old id (`nintendo_64_model.gd`,
`imported-assets/carts/nintendo_64/`) stayed too.

## The .info files

`libretro-core-info/` is a `cp` mirror of the libretro-super fork, whose ids are
libretro's. `Tools/rename_systemids.py` rewrites `systemid` and the id left of each colon
in `secondary_systemids`, reading the table out of `system_ids.gd` so there is one. **Run it
after any refresh**, and on the fork's `dist/info` when that is convenient:

```bash
python Tools/rename_systemids.py RetroXR/libretro-core-info RetroXR/libretro-core-info-retroxr
python Tools/rename_systemids.py --check RetroXR/libretro-core-info     # exits 1 if any are left
```

`systems_data_tests` `ids/` fails while any `.info` declares an old id — the check that goes
red after an un-renamed refresh, where everything else would quietly index a platform
under a name nothing else uses.

## Ids that became ONE: `SystemIds.MERGED`

`LEGACY` is 1:1 by contract (`systems_data_tests` `ids/` fails if two old ids become the same
system) and its migration RENAMES the player's ROM folder. Neither is right for `mame`,
`fbneo` and `hbmame`, which are three emulators of the one `arcade` machine, so they live in
`MERGED`: `canonical()` reads them (saved rooms, bindings, ledgers, mods, `SystemInfo.for_system`,
`ScreenscraperSystems`, `RaConsoles`), `Tools/rename_systemids.py` rewrites the `.info` files with
them, and **nothing on disk is moved** — their ROM folders are `FOLDER_ALIASES["arcade"]`, scanned and
never written to. `LEGACY["fb_alpha"]` points straight at `arcade` (a chain would be read once).

## Old ids on a player's disk

| where | how it is read |
|---|---|
| `roms/<id>/` | `RomLibrary.rom_dir_for_system` composes, then resolves: the first of `SystemIds.folder_names()` that EXISTS — the id, the old id, then ES-DE's other folders (`sfc`, `megadrive`, `mark3`). `rom_dirs_for_system` is all of them, and `scan_roms` merges them into one tile. Only the first is written to. |
| `save/carts/<id>/` | `SystemIdMigration` moves it a file at a time through `SaveMigration._place`, so the RomM ledger follows. Until then `SramPaths.resolve_cart_save` finds it, as it always swept every folder. |
| bindings, `core_defaults.json`, `app_prefs.json` hidden systems, `romm_config.json`, `romm_cache.json`, the ledger's `rom_ids` | read through `SystemIds.rekeyed` / `rekeyed_paths` AS THEY LOAD. Not rewritten at boot: their autoloads have read them before anything can run, and would write the old keys back. A key under both names keeps the new one. |
| a saved room | `systemid` and `cart_systemid` through `canonical` at deserialize, and `rom_path` — and a book's `pdf_path`, since a scraped manual lives under `roms/<id>/media/` — through `RomLibrary.relocate`, which finds a file whose folder was since renamed. (The book was missed at first: its manual failed to open and, unloaded, it blocked every click around it — `book_tests`.) **Not** by bumping `ScenePersistence.VERSION`, which drops the slot. |
| a mod | every systemid handed to `ModApi` goes through `canonical`. |

`SystemIdMigration` runs from `boot_scene.gd` after `SaveMigration`, under its own key
(`"systemids"`) in the same marker file. **A ROM folder that will not move does not hold the
marker back** — a folder `adb` created on a Quest is not the app's to rename
(`quest-device.md`), and the resolve above means nothing is lost. A save that will not move
does.

**Netplay accepts the new ids only**, by decision: a build from before the rename and one
from after cannot play each other in either direction.

## A system missing on ONE platform only

A systemid here is only ever as good as the `.info` file behind it, and a `.info` file is
not a resource: it reaches an exported build only through `include_filter="**/*.info"`. A
preset without it ships an empty `CoreInfoDatabase`, and then a platform is invisible by
omission rather than by name — every installed core lands in the `"unknown"` bucket and no
default is ever adopted. Check the preset before suspecting the table above; `building.md`
has the failure's exact shape.

## Regional names — one tile, three names (`RegionalNames`)

The Genesis is the Mega Drive outside North America, the TurboGrafx-16 the PC Engine, the
SNES the Super Famicom in Japan. `SystemIds.FOLDER_ALIASES` already merges the regional
FOLDERS into one tile (`megadrive/` is read as `genesis`); `Scripts/Data/systems/regional_names.gd`
only picks the NAME the tile wears, from Options > Systems > Console Names.

- **The pick** (`AppPrefs.region_names`): `us` / `eu` / `jp` (USA first in the list), or
  `original` (the cores' own `.info` names, which are inconsistent: the TurboGrafx-16 tile
  reads "PC Engine"). Stored `""` means NOT PICKED YET: the region is then the OUTLET
  region's (`RegionalNames.outlet_region()`, from `mains_region`, itself seeded from the
  locale) and follows it if it moves -- North America and China are USA, Japan is Japan,
  every other outlet Europe, Brazil included (Tectoy sold the Mega Drive and Master System
  under those names). There is no "Auto" row: the dropdown just shows the
  outlet's region selected until the player picks one, and a pick then sticks.
- **Names** go through `CoreInfoDatabase.get_systemname_for_id`, so every grid, title and an
  in-room machine's label follow; a region a row omits falls back to its US name, and a
  system not in `NAMES` keeps its own.
- **Search**: every regional name and `EXTRA_ALIASES` spelling finds its tile in EVERY region
  (`GameSearch.system_aliases`), so with "Mega Drive" showing, "genesis" still finds it.
- **Cartridges**: a ROM's own market always wins (scraped region, file tag, header). Only an
  unknown one asks `RegionalNames.cart_market()` -- SNES, N64 and NES shells. That follows
  the picked region, else the outlet's, **and the outlet's for Original too**: Original is about labels. The
  first build tied it to the names answer, so Original quietly put every unknown SNES ROM
  back in the procedural box. `cart_market_for` / `names_region_for` are the pure halves.
  Brazil reads Europe's NAMES but North America's CARTRIDGES (`cart_market_for` "br" -> "us").
- **A cartridge PINS its fallback** (`RetroCartridge.fallback_market`, saved as
  `fallback_market` only when the ROM names no region): set the first time its body is
  chosen, then passed to every shell call as `pinned`. Without it a saved unknown-region
  SNES cart came back a different body -- a different SIZE -- after a region change, since
  `body_region` is saved only when the player forced one. `rom_market()` on each shell is the
  market without the fallback; `uses_fallback_market()` says whether a ROM needs a pin.
- **A fallback Super Famicom shell wears its market's PAL sticker**: `eur` for Europe, `ukv`
  for Australia (`SnesCartShell.FALLBACK_STICKERS`), never for a ROM that names its own
  region. It had a Japanese back before.
- **Mod objects with regional variants** (Saturn, 32X, SFC, Super Game Boy, SNES pad, GunCon
  1/2, N64 paks, GC and PS2 network adapters) spawn the PLAYER'S region's variant when the
  row has no default of the player's own (`SpawnMenuSpawnView._row_default` ->
  `RegionalNames.variant_for_region`). Mods spell regions their own way, so a variant is read
  by its id's first word (`us`/`usa`/`us_gray`, `eu`/`eur`/`pal`/`ukv`/`noe`/`fr`/`de`,
  `jp`/`jpn`/`jp_black`: `VARIANT_REGIONS`), or by a `"region"` key a mod may give it. The
  answer is a concrete variant and is what the object saves, so a region change never
  re-dresses a saved pad. **MAKE DEFAULT on the FIRST variant now stores its id**
  (`_kept_default`): stored as `""` it read as "never chosen", and the region beat the pick.
- **Add-on names are display-only** (`RegionalNames.ADDON_NAMES`, `display_label_of`):
  "Mega-CD" / "Super 32X" on nameplates, spawn rows, toasts and the Sega CD card's name.
  `ExpansionCatalog.label_of` stays FIXED, because `RetroExpansion` mints a unit's memory
  `card_id` from it and that id is a persisted save folder.
- **A suite resolves to `""`** (no renames, no fallback) unless it sets
  `RegionalNames.test_region`, or names and cartridges would follow the CI machine's locale.
- **Dropdown rows are `[label, id]`; `REGIONS` rows are `[id, label]`.** Passed through
  unswapped, the list read `us`/`eu`/`jp` and every pick was refused -- the dropdown did
  nothing. `game_search_tests rows/` builds the real list and checks each id.
- **Netplay agrees through the pin.** A session spawn and a late joiner's snapshot are the
  same `ScenePersistence` entries a save writes, and the cartridge pins in `_ready`, before
  `object_sync.local_spawn` serializes it -- so the SPAWNING peer's market rides in the entry
  and every peer builds that body, whatever its own region. Before, each peer fell back to
  its own: an SFC shell on one, a Type A (another size) on the next. `game_search_tests
  wire/` does the round trip, with the field stripped as its control. What it does not
  cover: a peer whose copy of the ROM NAMES a region the spawner's did not (a different file
  name or scrape) uses its own ROM's market, as known-region cartridges always have.
- The base game ships no regional CONSOLE or controller models (`imported-assets/consoles`
  has none); the regional ones are the mods' variants above.
- **Not yet**: a machine already in the room keeps its nameplate until respawned
  (`system.gd` reads the name at spawn), and mods cannot add regional names (`NAMES` has
  no overlay). The scraper's Region Priority (Options > Scraper) is a separate setting by
  design: it orders which region's ART a scrape picks, and does not follow this one.
