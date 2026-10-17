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
name and art, which is when the player is deciding whether to trust it. A pack
that was never mounted can still be mounted later in the session (see "Applying
without a restart" below); disabling, updating or removing one that IS mounted
takes effect on the NEXT launch, and the page says which is which.

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

**Mod models are deliberately kept out of `ModelWarmer`'s boot work** and loaded
lazily on first spawn, so boot time is not a function of how many mods are
installed. (Since 2026-09-30 the boot warms no stand-ins at all; it still pre-loads the
bespoke shells' GLBs.) `stand_in_ids()` / `bespoke_ids()` / `shell_assets()` read `_ROWS`
directly for that reason — do not "fix" them to use `_table()`.

**`RoomCatalog`** (`Scripts/Data/room_catalog.gd`) replaced four hand-synced tables
for one fact: `SceneManager.SCENE_PATHS` / `SCENE_TITLES` / `SLOT_ROOMS` and
`scene_view.gd`'s `ROOM_TITLES`. Those three consts are GONE, not shimmed.

**Several mods for one console (2026-10-06).** Two authors modelling the same
machine was always legal -- ids are namespaced, both rows are listed -- but three
things around it were not handled, and each has one home now:

- *Connectors (2026-10-17).* Every socket and plug has a `connector` set on the node
  in its scene (RcaPort/RcaPlug and their subclasses, PowerPort; controller plugs take
  their controller's via `Connectors.of`, `systemid` -> `Connectors.CONTROLLER_PORTS`).
  `Connectors` (Scripts/Objects/cables) holds what the game knows: labels, ALSO_FITS,
  the controller-port table, `ROOM` (connectors that fit nothing in particular) and
  `GAME_LEADS`. It is not a list of allowed names -- it was once (`ModConnectors.KNOWN`,
  refusing any other bare name), and a third author could not share a socket without
  a game release. Only spelling is checked.
- *The card reads objects, mods declare nothing to it.* `ConnectorScan` reads a mod
  object's SceneState (never instancing it): its root's role (`RetroController`,
  `LightGun`) and every `RcaPlug`'s connector, cached by path. `items_for` offers every
  mod object fitting the card's sockets (the platform's controller port plus the rows'
  `sockets`), ROOM connectors never matching, and each stand-in goes while nothing
  installed does its job: box while a mod row is on the card, pad/gun while one fits the
  controller port, Composite Cable while no row wears `composite_plug` (a row with no
  `sockets` does), a `GAME_LEADS` lead while no mod lead fits its socket. This replaced
  `replaces_standin`, `av_connector` and the uncommitted `provides_lead`. A scene's
  script DEFAULTS are read (`get_property_default_value`) but nothing set at run time
  is: the rule for authors is "set it on the node". `ModApi.problems()` adds
  `SpawnCatalog.socket_problems_for` live (a socket nothing fits; a row whose `sockets`
  disagree with the built console, noted by `RetroSystem._check_listed_sockets`).
  `ModHooks._matches` also matches a node's `connector`, which is how a mod dresses a
  plug whose class went (N64AvPlug and the other name-only scripts were removed).
- *Dressing.* `ModApi.dress(cls, key, cb)` is `on_node_added` with a first-come
  claim held in `ModHooks._dressers`. The loser gets a problem line (not a failure)
  and no watcher.
- *The row's token (2026-10-13).* A console row is asked for as
  `model:<systemid>:<model_id>`, and a mod's model id has a colon of its own.
  `SpawnMenuController` split the token at EVERY colon, so `xenu.sfc:shvc001` arrived
  as `xenu.sfc`, matched no row, and `resolve` handed back the platform's first row.
  A mod's console therefore spawned right while it was the only console on its card
  (which is why nobody saw it) and wrong beside any other: the Super Famicom beside
  the Super NES, a second row from the same mod. `SpawnCatalog.model_of_token` is now
  the one reader, next to `spawn_token`, which writes it.
  `spawn_menu_tests --only=tokens`.

The spawn card marks the row `SystemModelRegistry.resolve("", platform)` would pick
with `default` whenever it offers more than one console. Which mod that is follows
from priority and load order; the mark is the only place a player can see it.
`mod_tests --only=standins`.

**A row's colors (2026-10-13).** A row on a spawn card may carry `variants`:
`[{id, label, color}]`, the first the thing as it comes. Such a row can be HELD, the
hold the cartridge rows already had, for a panel of swatches; pressed, it spawns the
first as before. The game paints nothing: what a color IS belongs to the mod. There
is one path and three ways onto it:

- *A mod's console row* lists them on the row it registers (`register_model`,
  `override_model`). `SystemModelRegistry.variants_error` is part of `validate_row`.
- *A row a mod adds* lists them on the item it passes to `add_peripherals`.
- *A game-owned row a mod only dresses* (the N64 controller, the Wii Remote) is
  offered them by its spawn token: `ModApi.offer_variants(spawn, variants)`, kept in
  `SpawnCatalog.register_mod_row_variants` and withdrawn with the mod.

The token is `model_as:<variant>:<systemid>:<model_id>` for a console and
`as:<variant>:<the row's own token>` for anything else. `SpawnCatalog.spawn_token`
writes both and `variant_of_token` / `plain_token` / `model_of_token` read them. The
first swatch asks with the plain token, so the thing as it comes is saved exactly as
it was before any of this.

What is spawned is told its color BEFORE it enters the room, which is what lets a
node-added hook read it. A console gets `RetroSystem.model_variant` and calls its
model's `apply_variant(id)` once, after the model is added; an expansion cover has
the same property. Everything else gets metadata, `SystemModelRegistry.VARIANT_KEY`
(`variant_of`, `set_variant_of`), set in `SpawnMenuController._place_spawned`.
`ScenePersistence._serialize_node` / `_deserialize_object` wrap every kind and keep
`"model_variant"`, so no kind has a field of its own for it. An id the mod no longer
has, or a save loaded with the mod gone, is ignored.

A row marked `"unlisted": true` stays resolvable, for the saves that name it, and is
left off the card: how `xenu.gbc` retired the four rows it had before it had colors.

`spawn_menu_tests` (`_group_colors`), `system_tests` (`_test_model_variant`). Still
OWED: the panel and the translucent shells' filter gain on a headset.

**Cartridge shells from a mod (2026-10-06).** `ModApi.register_cart_shell` /
`ModCartShells` is `N64CartShell` and its siblings handed to a mod: bodies, an
optional palette, and a function from a ROM to `{body, preset}`. It is consulted
FIRST in the four places the shipped classes are named, and nowhere else:
`RetroCartridge.body_model_for` (static, so the warm before a spawn and the room
restore get the mod's GLB too), `MediaDimensions.cart_size(..., body_model)` /
`has_cart_size`, `CartridgeColor.get_palette`, and the hold menu
(`_has_spawn_options`, the Body row). A mod shell is never `demetal`led.
**What is painted is the mod's `tint` list**, not `EXTERIOR_PLASTIC`: the names are
the author's, so `CartridgeColor._source_of` asks `ModCartShells.is_tint` beside the
game's list (a union over every mod shell, not per system -- `_source_of` has no
system to ask about). No `tint` means no paint, no Shell section in the hold menu,
and a palette without it is refused: a picker that silently does nothing is what
this replaced.
`body_region` and `shell_preset` already were strings in the save, so a forced mod
body is saved with no new field; with the mod gone the id matches nothing and the
game's own choice returns. The function's answers are cached per ROM (it may open
the file, and a cartridge asks for its body on every drop) and it must be static,
for the reason every mod callback must. `cart_size` WITHOUT a body model still
answers from `CART_SIZES` where the game has a row, so a mod for a shipped system
moves no seat or bay constant. `mod_tests --only=cartshell`. The first real one is
`xenu.n64cart` in RetroXR-models (the branded N64 Game Pak, 2026-10-06): its
`n64cart_probe` mounts the pack, feeds it header-only ROMs and renders the result.
Still OWED: a cartridge mod for a system the game has NO body for, one whose bodies
differ in size, and any of it on a Quest -- that mod's bodies are 72 mesh nodes
each, against the shipped Quest tier's 9.

**The app downloads mods from mod.io, and from nowhere else** (reversed
2026-10-06; this paragraph used to say "no in-app browser, no download"). The old
objection was that the moment the app becomes the transport it owns what is inside
one. What changed is that the transport is now a host that scans uploads and that
the game's admin moderates, and the app's own vetting runs on every file before it
is installed. Netplay is unchanged: it still sends only a fingerprint
(`id@version`) in the `_register` handshake and rejects a mismatch rather than
shipping the pack to the peer — a pack handed from one player to another has been
through neither check.

## The mod browser (MODS tab)

`Scripts/UI/spawn_menu/views/mods_view.gd`, over four services owned by the
**`Modio` autoload** (`Scripts/Net/modio/modio_service.gd`, declared after `Mods`;
`autoload_order_tests` holds that): `ModioClient` (`Scripts/Net/modio/`),
`ModDownloader` (`Scripts/Data/mods/`), `ModArtCache` (`Scripts/UI/spawn_menu/`)
and `ModReviews` (`Scripts/Mods/`). The menu only borrows them.

**They are an autoload because the menu leaves the tree on every room change.**
As children of `SpawnMenu2D` their `_exit_tree` fired there, and the downloader's
cancels every download. It matters twice over for the install hook: bound to the
menu's view, it died with the menu, and a download that finished afterwards fell
back to `Mods.install` — installed with no review. `ModReviews.stage` is the hook
now and lives as long as the downloader does. Three sub-tabs: **Browse** (mod.io's
catalogue as tiles), **Packs** (its collections, `mods_packs_page.gd`) and
**Installed** (what was Options > Mods, moved whole).

- **mod.io game 14432**, `https://g-14432.modapi.io/v1`, REST from GDScript. The
  only maintained Godot plugin is a desktop-only Rust extension with no Android
  build. mod.io's C++ SDK is not used: it builds for Android only through CMake
  and JNI, and would be an eighth GDExtension.
- **API key only.** mod.io's docs describe a game key as "limited to read-only GET
  requests, due to the limited security it offers", sent by the client in the
  query string — so it is a constant in `modio_client.gd`, not a secret. No login
  means no subscribing, rating or commenting; those need OAuth and are not built.
- **Consent comes before everything.** mod.io's game terms ask for the player's
  agreement to its Terms and Privacy Policy "before using any mod.io
  functionality, such as on startup, or before launching any UGC browsers"
  (docs.mod.io/terms), which covers anonymous browsing. Browse and Packs show
  mod.io's own text, buttons and links (`GET /authenticate/terms`, the one request
  allowed first) and nothing else until it is accepted. **The gate is in
  `ModioClient._fetch_json`**, not in the page, so a page that forgets to ask
  cannot send a request. `ModioConsent` keeps the answer in
  `user://modio_consent.json` with the text's MD5; once a session the terms are
  re-read and changed wording asks again. Withdrawing (the button under Browse)
  cancels downloads, discards what was waiting, and clears both pages. Installed
  never asks. mod.io's text says an account "will be created for you"; that is
  their wording for the sign-in case, so the gate adds that RetroXR signs nobody in.
- **`X-Modio-Platform` is sent** (`windows`/`linux`/`mac`, and `oculus` on a Quest).
  The game has no platforms configured, so it changes nothing yet (measured
  2026-10-06: same reply with and without). Whether a sideloaded build may claim
  `oculus` is unanswered; `android` is the fallback.
- **The tag filter is mod.io's own list** (`GET /games/<id>/tags`, flattened; one
  group, "Object", when this was written).
- **What mod.io's game terms require is on the page**: its name beside the
  catalogue, and a Report button on every mod (it opens
  `https://mod.io/report/mods/<id>/widget`, which takes a report without a login).
  Remove neither.
- **Nothing reaches mod.io until the tab is first opened** (`ensure_fetched`).
- **A download address is asked for again at the press** (`get_mod`), never taken
  from the listing: mod.io signs each one and lets it expire.
- **The redirect is followed on the GET**, not probed with a HEAD as
  `FirmwareInstaller` does for GitHub: a CDN signature made for a GET need not
  answer a HEAD. `RommHttp.download_to_file` returns the response headers on an
  HTTP error for this.
- **Uploads are zip only.** mod.io stores a zip; the app fetches it into
  `mods/.incoming/` and installs it as `mods/<id>.zip`, as-is. A `.pck` is still
  fine dropped in by hand.

### What a download has to get through

Four checks, in this order, and then the player:

1. **mod.io's scan.** `ModioClient.scan_problem`: only `virus_status == 1` with
   `virus_positive == 0` is fetched, asked of the FRESH reply at the press. A file
   never scanned is refused with the rest — it is the one check the game cannot
   make itself — and its tile reads "Being scanned by mod.io".
2. **mod.io's MD5**, in the downloader.
3. **The loader's own vetting** (`inspect`).
4. **No games, no programs** (`ModContentPolicy`, through `ModManager.vet`): every
   extension a core loads as content, less text, pictures and sound, plus native
   code. `.md` is refused on purpose — it is a Mega Drive ROM as well as Markdown.
   Applied to DOWNLOADS only; a pack the player copied in is not held to it. The
   same list belongs in mod.io's upload rules.
5. **The review.** The downloader's install hook is `ModReviews.stage`, so a
   vetted file is parked, not installed. The review shows the full-access
   warning, what the mod **Replaces**, any file two mods both replace, and an
   "Enable" switch that starts OFF (applied from Installed). Discard deletes the file.
   **A download nobody answered for is deleted at the next launch**
   (`_sweep_incoming`, after `_apply_pending`); a `.part` is kept so it can resume.

**Room is checked before the first byte** (`ModDownloader.space_problem`): twice
the file plus 16 MiB, less what a partial already holds — twice because a bundle
is opened beside the download before the download is deleted. A size mod.io did
not state, or a volume that reports 0 free, is not refused: unknown is not full.
`get_space_left` on a Quest's `/sdcard` path is UNMEASURED.

**A bundle is one upload holding a build per platform** (`ModManager._unwrap`,
through `vet`). mod.io stores one zip per mod; a zip with no manifest of its own
and containers at its top level is opened, each is inspected, and the one that
runs here is what gets reviewed and installed — which is also how a `.pck`, which
mod.io will not take bare, travels. None that fits is refused with each build's
reason; MORE than one that fits is refused too, rather than picked by a rule the
author cannot see. Only the top level is searched. `vet()` returns `path`, the
pack to install, and every caller must use it and not the download's own name.

**A failed request used to raise instead of reporting.** The error path handed a
bare `[]` to a callback typed `Array[Dictionary]`, which Godot refuses outright, so
the page never saw the error. `_no_rows()` is typed for that reason.

### Packs — mod.io collections

A pack is a mod.io **collection**; "pack" is the menu's word and `collection` the
code's, because a pack is also the `.zip`/`.pck` container. The endpoints answer
with only the game key (measured 2026-10-06, on an empty catalogue):
`/games/<id>/collections` and `/collections/<cid>/mods`.

- `ModCollectionPlan` is pure and holds every decision: what to fetch, what is
  already here, what is skipped and why, which shipped files two mods both replace,
  and what removing a pack removes.
- **Installing** fetches each member exactly as a single mod is fetched, then asks
  ONE question for the lot (`SpawnMenuModsPacksPage._fill_review`): each member's
  Replaces, conflicts between members and with installed mods, what was skipped,
  and "Enable all", OFF. A member that fails is skipped; the rest
  carry on.
- **A mod's `source` records who wants it**: `collections` (pack ids) and
  `individual`. A mod that was here before a pack named it is the player's own.
  **Removing a pack removes only what it alone brought** (`plan_remove`).
- Ids come back from `mods.json` as FLOATS; `collections_of` reads them as ints.
- A collection's members are capped at 500 (`MEMBER_PAGES_MAX`); mod.io's own
  count is shown when a pack is cut short.
- **There is no Subscribe.** That needs a login.

### Install, update, remove — `ModManager`

**A test suite boots with no mods** (`_is_test_run()`: a `res://Tests/` scene on the
command line). The state is read but nothing pending is applied and nothing is
discovered or mounted. `mod_browser_tests` never used the autoload — it builds its own
managers with `mods_root_override` / `state_path_override` — so it is unaffected.

`install(staged, source)`, `vet(path)`, `remove(id)`, `inspect(path)`,
`remove_unreadable(path)`, `source(id)`, `set_source(id, source)`,
`find_by_source(key, value)`, and the `mods_changed` signal. There was no such API
before; the loader only ever read.

- **`install` is the boot's own vetting on one file** (`inspect`: reader, manifest,
  inventory, platform). A pack that would be refused at the next launch is refused
  now, with the same sentence, deleted, and never reaches the mods root.
- **A download lands DISABLED** unless that id was already enabled. Fetching is not
  consent; the switch is, and its page shows what the mod claims.
- **One container per id.** The new file is `<id>.zip`, and whatever held that id
  before goes — a hand-installed `My Cool Mod v1.zip`, or both halves of a double
  install — because two files with one id refuse both at the next boot.
- **A MOUNTED pack is not touched in-session.** The engine keeps a mounted container
  open until exit (Windows refuses the delete; elsewhere the old copy would go on
  being read). The update is parked in `mods/.incoming/`, the move recorded in
  `user://mods.json` (`pending`), and `_apply_pending` makes it at the next launch
  before discovery. The record keeps describing what is mounted, so the netplay
  fingerprint stays true for the session; `update_staged` / `removal_staged` carry
  what is waiting. `ModRecord.mounted` is the flag — true for FAILED as well as
  LOADED.
- **`pending` is read from a JSON file**, so every name in it is reduced to its last
  component and must be a `.zip`/`.pck`: it cannot reach outside the mods root.
- `user://mods.json` also holds `sources` (`{modio_id, file_id, profile_url}` per
  mod id), which is how a Browse tile knows it is installed and whether mod.io now
  offers a different file.

### Applying without a restart (2026-10-14)

The Installed page has ONE button over everything waiting (`_fill_banner`, drawn
above the list AND above a mod's own page, which is where its switch is):

- **Apply now** when every waiting change is in `ModManager.apply_plan()`'s
  `live`: switched on, never mounted, and with no claim that shadows a shipped file.
  The controller closes the menu and calls `SceneManager.reload_room(prepare)`,
  whose `prepare` is `Mods.apply_live()`, run inside `_run_transition` once the old
  room is freed and before the new one loads. That is the state a boot is in when
  the autoloads run, and it is the point: hooks fire on `node_added` before a
  node's `_ready` (the n64pad reshell has to run before the controller looks for
  its controls), so dressing a room that is already standing is NOT equivalent.
  The room is rebuilt and the player stays where they stood (`_seat_player_rig`
  `keep_place`). `mods_applied` then rebuilds what was read once: the spawn menu's
  TVs tab, both grids (`refresh_after_core_change("")`) and the local scan cache.
  `SystemIcons.forget()` drops its cached misses.
- **Restart now** for the rest: a running pack switched off, updated or removed (a
  `_pending` move), a mounted pack that failed, or a mod whose claims shadow a
  shipped file. Its replace-files mount could not displace a copy already in the
  resource cache. `SceneManager.restart_app()` carries the room and quits:
  - **Desktop: a waiter, not `set_restart_on_exit`.** `relaunch_command` starts
    `powershell Wait-Process -Id <pid>; Start-Process ...` (Windows) or a
    `sh` `kill -0` loop (Linux/macOS) before the quit, so the new process starts
    once the old one has GONE, however it went. `set_restart_on_exit` only fires
    at the very end of `Main::cleanup`, and **quitting with things in the room
    sometimes dies in teardown** (measured 2026-10-14 on Windows, mods or none: 4
    of 7 quits with consoles or a set spawned exited 139, 0 of 3 with the room
    empty; nothing reached the event log and stdout is lost with the process, so
    the faulting module is UNKNOWN). With the engine's restart that was no
    relaunch at all; with the waiter it relaunched 3 of 3, including a run whose
    parent crashed. Waiting also keeps two instances off one OpenXR session.
    `set_restart_on_exit` stays the fallback if the waiter cannot start.
  - **Android: `set_restart_on_exit`**, which it honours though Godot's docs say
    otherwise: `_terminate` -> `Main::cleanup` -> `OS_Android::create_instance` ->
    `GodotActivity.onNewGodotInstanceRequested` -> `ProcessPhoenix.triggerRebirth`
    (engine 4.7.2, unpatched there). **Measured on a Quest 3, 2026-10-14**
    (`mods_apply_probe`, one run, nobody wearing it): the `:phoenix` activity
    lived 0.15 s, the old process exited with no native crash, and the new one
    reached `XR_SESSION_STATE_FOCUSED` 10 s after the press -- immersive, back in
    the arcade with the room carried. Between the two it goes through Horizon's
    ordinary app-launch transition, and Horizon did place a volumetric window
    for the `:phoenix` activity; whether a wearer sees it is not known. A
    teardown crash there would cost the relaunch (no waiter on Android); the
    carry is still marked in the prefs, so the next launch comes back to the
    room either way.
  - `restart_args` passes nothing on Android (the activity re-adds its `_cl_`
    line) and re-adds `--path` from an editor binary. Consoles power off and flush
    SRAM on the way out as on any quit.

**The room is carried, not saved.** Both paths call `SceneManager.carry_room()`:
the room is written as it stands to `<room>/_carry.json` (beside the slots, in no
manifest), the room id goes in `prefs.json` as `"carry"`, and the next restore OF
THAT ROOM (`SpawnMenuController._autoload_slot`, which a boot comes through too)
loads it instead of the slot, once, then deletes it. A failed carry falls back to
the slot. The leave-save a room change makes is not enough: it is skipped in a
Clean Room, with the autosave switch off, and in rooms with no slots.

**Refused:** in a netplay session (`apply_plan`'s `blocked`, and again inside
`reload_room`/`restart_app`). Peers compared fingerprints once, at the handshake,
and a host's room change tells its clients to change to the room they are already
in, which does nothing. The button is also disabled until the room's content has
settled, and a restart is refused while any download runs or a mod review waits
(`SpawnMenu2D.busy_reason`): every downloader cancels on exit and
`_sweep_incoming` deletes parked reviews at the next launch.

**`ModRecord.loaded`** is "this mod's code is running this session". `status`
follows the switch (`_status_for`): flipping a switch back is not a change any more
(it used to leave the mod PENDING and ask for a restart that changed nothing), and
**`fingerprint()` keys on `loaded`**, because a running mod switched off goes on
running until the restart and a peer must still be told it is there.

**`rescan()`** runs whenever Installed is shown, so a pack dropped in by hand, by
adb or over the LAN server appears without a restart. Only NEW ids get records; a
second container for a known id is left for the next boot's duplicate rule, since
re-recording a running mod mid-session would rewrite what netplay reads.
Unreadable files are read again (an adb push may have been mid-copy).

**A live mod registers after every boot mod**, whatever its priority. Where two
mods claim one thing first-come (`dress`, `override_model`, cart and expansion
shells) the next launch can settle it the other way. Documented, not fixed. And a
mod that was off at boot already had its props pruned from the restored room
(`_prune_unknown_types`); applying it does not bring them back.

`mod_browser_tests` `apply/` (classification, rescan, and a REAL mount of a
fixture pack under its own namespace, from a folder outside `_dir` because Windows
holds a mounted zip open), `scene_tests` `carry/` and `restart/`,
`spawn_menu_tests` `tvs/`. A restart is never driven from a suite: a mutation that
broke its refusal would relaunch the suite for ever.

**`Tools/mods/mods_apply_probe`** is the end-to-end check, in the real app,
WINDOWED, against a scratch `APPDATA` and `USERPROFILE` (it refuses to run without
`probe_home.txt` in both): it boots BootScene, furnishes the room, presses Apply
now on a mod that claims nothing (`-- --mod=`, default `xenu.panasonic`), checks
the room, the player and the TVs tab, spawns the mod's set, switches the mod off
and presses Restart now. The relaunched process is the probe again (its scene is
on the command line) and reports phase 2 in `result2.txt`; it never restarts from
there. Passed 3 of 3 on Windows, 2026-10-14, and 1 of 1 on a Quest 3 (Apply now
rebuilt the arcade in 9 s with every object in place; the restart as above).

On a Quest it is a probe-only export (quest-device.md): `project.godot` names it
for the feature `modsapplyprobe`, and `export_presets.cfg` has the preset,
`Quest mods apply probe`, under its OWN `package/unique_name`
(`com.xenu.retroxr.maprobe`), so it installs beside the real app. Launch it once so the app makes its own folders (it refuses: no
markers), then `adb push` `probe_home.txt` to its `files/` and the mod into
`files/mods/`, put the other marker in `user://` with `run-as <pkg> sh -c 'echo
probe > files/probe_home.txt'`, launch again, and read
`files/mods_apply_probe/result1.txt` / `result2.txt` through `run-as`. The room
PNGs come back ALL BLACK on a Quest (the XR view does not read back); the menu
PNG is real. The checks and `XR_SESSION_STATE_*` in logcat are the proof there.
Uninstall the package after.

### Preview images

A Browse tile shows the logo the author uploaded to mod.io (the app cannot open a
pack it has not downloaded); an Installed tile shows the pack's own
`res://mods/<id>/thumbnail.png`, read without mounting. `pack_mod.gd` **refuses to
write a pack without one** — 16:9, at least 512x288, mod.io's own floor, so the
same file serves as both — and `--check=<pack>` puts an `--export-pack` pack
through the same verification. The LOADER never insists: a pack from before the
rule still loads and gets a placeholder tile.

**An exported pack only carries the raw PNG if its import type is "Keep File".**
Imported as a texture, the export ships a `.ctex` in its place and the loader finds
no thumbnail. `xenu.ps2.pck` has none: it is built by `mods/build_mod.py` in the
RetroXR-models repo, whose source ships no `thumbnail.png` yet.

### Still owed

- **A real download, measured 2026-10-06** with the first mod published (the
  PlayStation 2, mod 6431594, a 4.7 MB zip from RetroXR-models' `build_mod.py
  --zip`). `Tools/mods/modio_live_probe` is the check: the real client and
  downloader against mod.io, into a scratch loader, touching nothing of the
  player's. What it and curl showed:
  - `binary_url` is `…/mods/<id>/files/<fid>/download` and answers **302** to
    `binary.modcdn.io/…zip?verify=…`. It needs **no token and no API key**.
  - The CDN answers `Accept-Ranges: bytes` and a Range request with 206, and the
    first hop answers a HEAD (302), so following on the GET was caution, not need.
  - mod.io's scan had passed (`virus_status` 1) within minutes of the upload, and
    the file's MD5 matched what was built.
  - The pack passed the deny-list as built: `.ctex`, `.scn`, `.import`, `.gd`,
    `.tscn`, `.json` and `thumbnail.png`.
  - `logo.thumb_1280x720` answered 307 while the two smaller sizes answered 200:
    sizes are made on demand. `ModArtCache` marks a failed address dead for the
    session, so a logo asked for too soon after an upload stays blank until a
    restart. Seen once, on the 640 size, minutes after the upload; not reproduced.
- **Curation is ON now**: an uploaded mod is "Pending" until a game admin presses
  Activate on its page, and is not listed before that.
- **Still unmeasured:** a Quest, a large file on a slow link, and a resume.
- **Four suites assume no mod is loaded**, and run against the player's own
  `Mods` autoload: with the PlayStation 2 mod enabled on the machine, `mod_tests`
  (the empty fingerprint), `link_tests` (it finds the shell's `ILinkPort` MARKER
  by name before the socket) and `system_tests` (a PS2 no longer wears the box)
  each fail one case. CI has no mods. Turn them off before reading a local run.
- **A real pack.** No collection existed either, so the Mod Collection fields are
  read off mod.io's schema page, not a live reply, and no pack has been installed
  end to end. `mod_browser_tests` `collection/` is the plan, not that proof.
- **The game's mod.io settings**: curation was `0` (uploads go live unreviewed, and
  collections have a curation switch of their own) and no platforms were
  configured.
- **A pack install does not survive the menu.** The downloads do, and each lands
  in `ModReviews`, but the batch that ties them into one question is the Packs
  page's: lose the menu mid-pack and its members come back as single reviews,
  with no record of the pack.
- **A room change with a download running**, on a headset. The autoload is the
  reason it should survive; nobody has watched it do so.
- **The Quest's mods folder may be unwritable** if it was ever made by `adb push`
  (owned by shell). The downloader says so; it cannot fix it.
- The tab in a headset, and nine nav buttons on the bar (they fit by measurement:
  839 of 1072 px).
- **Both buttons as a WEARER sees them.** On a Quest 3 the probe passed and the
  relaunch came back FOCUSED (above), but nobody had the headset on: whether the
  0.15 s `:phoenix` window shows, and what the ~10 s through Horizon's launch
  transition looks like, are unseen. One Quest run, so whether a Quest ever
  shares the desktop's teardown crash is not settled either.
- **The teardown crash itself** (see Restart now above): an ordinary quit with
  things in the room exits 139 about half the time on Windows. Unfixed and not
  located; consoles power off first, so whether a save is ever lost to it is not
  known either.

**A mod's lead saves as a lead.** A mod prop is written to a slot as its type and
pose, which is all a crate needs. A lead (`CompositeCable`, `PowerCord`, `PowerStrip`)
registered through `register_object` used to be written the same way, so a room came
back with the lead on the floor and nothing plugged in. `_serialize_node` now gives a
mod lead the ordinary lead entry (`plugs`, `cord_length`, `body`) under the MOD's type;
both restore passes already read a lead by class. `mod_tests` `objects/` holds it, with
a shipped lead standing in for the mod's scene.

**A mod's pad saves as a pad.** The same short-circuit wrote a mod-registered
`RetroController` as a bare pose, so it came back as the right pad, unplugged. A mod
object that is a controller is now left to the controller branch, which records the
scene it came from (how every pad is told apart) and the port it is in;
`is_known_controller_scene` already allowed a scene a mod registered.

`RetroXR/Tests/mod_tests.tscn` is 203 headless checks and needs no mod installed;
fixtures are built into `user://` at run time. Almost none of it mounts anything,
for the reason above. **It asserts that NO mod is loaded** (`netplay/no mods means
an empty fingerprint`), so it fails by one on a machine with a mod enabled.

`RetroXR/Tests/mod_browser_tests.tscn` is 149 checks on install / update / remove,
the pending moves, the catalogue parser, the thumbnail rule and a download over a
loopback server (redirect, checksum, resume, a server that ignores `Range`, a pack
the loader refuses). Each case builds its OWN `ModManager`, never added to the
tree, over a scratch root (`mods_root_override`, `state_path_override`): the
`Mods` autoload and the player's mods folder are never touched, and `mounted` is
set by hand rather than by mounting.

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
drifted: `ps2` and `psp` claimed `DISC_INSERT` though a
sliding tray and a hinged UMD door are both `DISC_TRAY`, and `scummvm` claimed
`CARTRIDGE` though it is deliberately a CD system. `DISC_INSERT` means the Wii and
only the Wii.
