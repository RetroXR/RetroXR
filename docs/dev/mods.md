# Mods — maintainer notes

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

## Mods

A mod is ONE file — a `.zip` (recommended) or `.pck` resource pack — in
`<data root>/mods/`. It can add consoles, platforms, rooms, props, TV cabinets and
controllers, or replace something shipped. `docs/modding.md` is the author-facing
guide; this section is what a maintainer needs.

`Scripts/Mods/` holds the loader: `mod_manager.gd` (the `Mods` autoload, placed
before `AppPrefs`), `mod_manifest.gd`, `mod_pack_reader.gd`, `mod_api.gd`,
`retro_mod.gd`, `mod_hooks.gd`, `mod_shaders.gd`.

**The load order is the design.** A pack is opened, listed, its `mod.json` and
thumbnail read, and its inventory checked — all WITHOUT mounting — before anything
is loaded. That matters because `ProjectSettings.load_resource_pack` cannot be
undone: mounting to find out what a mod is would commit to every mod on disk.
Reading without mounting is also what lets the Mods page show a disabled mod's
name and art, which is when the player is deciding whether to trust it. Enabling
or disabling therefore takes effect on the NEXT launch, and the page says so.

**`ModPackReader` handles both containers.** Zip is `ZIPReader`. Pck parses the
pack directory and reads members at their recorded offsets — written against a
pack this engine actually produced, because **Godot 4.7 writes pck format 4**,
whose header differs from the 4.0-era format 2 (flags, then `file_base`, then a
`dir_offset` the directory must be SEEKED to; paths stored without the `res://`
prefix; offsets relative to `file_base` when the `REL_FILEBASE` flag is set). A
`.pck` storing `mod.json` compressed is refused rather than decompressed.

**The namespace rule is the enforcement.** Everything a pack ships must live under
`res://mods/<id>/`; anything else must be in the manifest's `claims`, or the pack
is refused. A mod claiming nothing is mounted with `replace_files` off and
provably cannot touch a shipped file. This is also what stops an author's stale
copy of `vr_hinge.gd` replacing the real one, and `project.binary` /
`global_script_class_cache.cfg` are refused even if claimed.

**Overlays, never edits.** The shipped `const` tables stay the base layer and each
gained a `static var` overlay merged by a small accessor: `SystemModelRegistry`
(plus `validate_row()`, extracted from `model_registry_probe` so probe and loader
share one definition), `SystemInfo`, `ConsolePadArt`, `MediaDimensions`,
`ScreenscraperSystems`, `SpawnCatalog`, `ScenePersistence.PLAIN_SCENES`,
`RetroTV._SHELL_SCENES`, `RoomCatalog`.

**Mod models are deliberately kept out of `ModelWarmer`'s boot warm** and warmed
lazily on first spawn, so boot time is not a function of how many mods are
installed. `stand_in_ids()` / `bespoke_ids()` / `shell_assets()` read `_ROWS`
directly for that reason — do not "fix" them to use `_table()`.

**`RoomCatalog`** (`Scripts/Data/room_catalog.gd`) replaced four hand-synced tables
for one fact: `SceneManager.SCENE_PATHS` / `SCENE_TITLES` / `SLOT_ROOMS` and
`scene_view.gd`'s `ROOM_TITLES`. Those three consts are GONE, not shimmed.

**A mod is never distributed by the app.** No in-app browser, no download, and
netplay sends only a fingerprint (`id@version`) in the existing `_register`
handshake, rejecting a mismatch rather than shipping the pack to the peer. Keep it
that way: a mod is a file the player chose to install, and the moment the app
becomes the transport it owns what is inside one.

`RetroXR/Tests/mod_tests.tscn` is 137 headless checks and needs no mod installed;
fixtures are built into `user://` at run time. Almost none of it mounts anything,
for the reason above.

```bash
python Tools/mods/new_mod.py xenu.snes --name "Super Nintendo"
"$godot" --headless --path RetroXR --script res://Tools/mods/pack_mod.gd -- --id=xenu.snes
"$godot" --headless --path RetroXR res://Tests/mod_tests.tscn -- --only=removal
```

**Mods are authored INSIDE a checkout of RetroXR**, in `RetroXR/mods/<id>/`
(gitignored, and excluded from every export preset). Not a convenience: a `.tscn`
records a `uid` as well as a path, and a uid minted elsewhere does not exist here;
and a stub tree cannot resolve `NetworkManager`, which `RetroSystemModel` needs and
which is an autoload a pack can never add.

**Two invariants that were documented but unenforced, and both were already
broken** — `mod_tests` `consistency/` now checks them. `SystemInfo.media_type` is
read by NOTHING (`MediaDimensions.disc_loader` is what the cabinet uses) and had
drifted: `playstation2` and `playstation_portable` claimed `DISC_INSERT` though a
sliding tray and a hinged UMD door are both `DISC_TRAY`, and `scummvm` claimed
`CARTRIDGE` though it is deliberately a CD system. `DISC_INSERT` means the Wii and
only the Wii.
