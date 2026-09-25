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
