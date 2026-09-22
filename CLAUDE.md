# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This file is the index. The detail lives in `docs/dev/*.md`** (moved out verbatim
2026-09-18). **Read the matching doc BEFORE authoring in its area, not after the bug** —
a one-line summary is enough to recognise a topic and not enough to act on; acting from
the summary is how the same mistake arrives a second time. When you learn something new
about a topic, add it to that topic's doc, and only touch this file if a rule here changes.

## Project Overview

RetroXR is a VR retro-gaming room in Godot 4.7. Its core is `libretro-godot`, a GDExtension (C++, submodule, forked from SKurdt's SK.Libretro.Godot) that runs libretro emulator cores inside Godot and bridges Godot's scene system to the libretro API.

The app is `RetroXR`, package `com.xenu.retroxr`. The Godot project folder is `RetroXR/`
(godot-xr-tools based), and the desktop data root stays `~/retroxr/{roms,books,videos,…}` —
it holds user ROMs, so it is deliberately not renamed.

## Git Workflow

**Commit directly to `master` unless the user says otherwise.** This is a solo repo —
do not branch-per-feature by default; commit and (when asked) push straight to `master`.
Branch only when the user explicitly requests it.

## Build — full notes: `docs/dev/building.md`, `docs/dev/extensions.md`

Needs SCons + MSVC (Windows), GCC/Clang (Linux), Xcode CLT (macOS) or the Android NDK, and
`git submodule update --init --recursive` first.

`Tools/build.py` builds all seven GDExtensions for one platform (one shared trimmed
`godot-cpp` per target, then each extension with `build_library=no`), prints a pass/fail
table and exits non-zero on failure. Prefer it over the per-extension recipes.

```bash
python Tools/build.py windows              # both template_debug and template_release
python Tools/build.py android --target release
python Tools/build.py linux --only vlc-godot      # from Windows this re-invokes inside WSL
python Tools/build.py macos [--arch x86_64]       # macOS 13.0 minimum
python Tools/build.py windows --jobs 8 -- verbose=yes    # extra args go to scons
```

- **`build.py` is PER-PLATFORM, and the binaries are gitignored.** A C++ change rebuilt for
  windows leaves `android` on whatever was last built for it, and the Quest only says so
  when the renamed method is CALLED (`Nonexistent function 'open' in base 'PDFRenderer'`)
  — that shipped as "PDF manuals do not open on Quest" for 18 days (2026-09-20,
  `extensions.md`). Rebuild **both targets**; a missing android build exports a 0-byte `.so`.
- **`Tools/godot_cpp_profile.json` is the shared API allowlist** — add a Godot class there
  when extension C++ starts using it (forces a godot-cpp rebuild for every extension).
- The seven: `libretro-godot` (MIT, submodule, published separately), `archive-godot`
  (`RommArchiveExtractor`), `verlet-rope` (`Xenu::VerletRope`), `vlc-godot` (`VlcPlayer`,
  the single video backend), `godot-pdfium` (`PDFRenderer`), `metaxr-audio`,
  `surround-godot` (GPL FreeSurround — its own extension for licence reasons, §2r). Each
  is `<name>/` with its own `SConstruct`, built **from its own directory**, deploying to
  `RetroXR/<name>/`.
- **Not all ship everywhere:** `metaxr-audio` is windows/android only (Meta's blob);
  `vlc-godot` is skipped on macOS. `--only metaxr-audio` on Linux/macOS is an error.
- libretro-godot itself builds from the **workspace root** (`SConstruct` there;
  `libretro-godot/Temp/SConscript` is a VariantDir, there is no root `Temp/`). Output:
  `RetroXR/libretro-godot/`.
- scons is not on PATH: Windows `$APPDATA/Python/Python314/Scripts/scons.exe`; Linux/WSL
  `~/.local/bin` (`uv tool install scons` on CachyOS, `pip install --user scons` elsewhere).
- Linux, Windows and Android each need their own callback trampoline ABI
  (`CallbackTrampolines.cpp`). macOS runs software-rendered cores only.
- godot-pdfium's Linux lib installs to a `linux-x64/` subdir with a quoted `$$ORIGIN` rpath
  so it cannot clobber the Android `libpdfium.so` of the same name — see extensions.md.

### The Quest ships a PATCHED engine — `docs/dev/engine-patches.md`

Stock 4.7.2 has six Quest defects fixed by `docs/godot-4.7.2-*.patch`, applied on engine
branch `retroxr-4.7.2` in `~/godot` (github.com/RetroXR/godot). Prebuilt arm64 libs live
in `Tools/engine/` (Git LFS):

```bash
python Tools/place_engine.py --target release   # what release.yml runs before the export
python Tools/place_engine.py --target debug     # local Quest export (--restore to undo)
```

`rendering/renderer/mobile/render_directly_to_target` is ON in `project.godot` (pays on the
MSAA path). Never judge an sRGB-view experiment from a screencap alone. Rebuild recipe,
measurements and shader-include traps are in the doc.

## Testing & validation — full notes: `docs/dev/testing.md`

```bash
python Tools/run_tests.py            # every suite; gates CI (tests.yml)
python Tools/run_tests.py --list
python Tools/run_tests.py --update-baseline   # after a DELIBERATE drop in case count
"$godot" --headless --path RetroXR res://Tests/<suite>.tscn [-- --only=<group>]
```

- The runner globs `RetroXR/Tests/*.tscn` **non-recursively** — `Tests/` stays FLAT; a
  suite in a subfolder is silently never run.
- **A case count that DROPS fails the run** (`Tools/test_baseline.json`). A rise or a new
  suite is fine. Filtered runs skip the check.
- **The bar for `Tests/`:** checks itself, runs unattended with no ROM, core, headset or
  device, and exits non-zero on failure. Everything else is a **probe** under
  `RetroXR/Tools/<topic>/` (`av cores gen input link models netplay perf room rope state
  vr`), including asserting ones that need real cores/ROMs or reproduce open bugs. A probe's
  `.tscn` names its script by literal path — rewrite it when moving one.
- ~45 suites (`--list` names them): netplay, romm, binding, object_sync, scene, poster, rope,
  av, system, link, state, expansion, card, deck, microphone, famicom, n64_vru, n64_cart,
  speaker, archive, mod, spawn_menu, autoload_order, … Measured counts, timings and each
  suite's traps are in testing.md.
- **Several suites write the player's REAL data** (`user://scenes`, bindings JSON, the roms
  root, posters folder) because the paths cannot be redirected — they snapshot and restore
  byte-for-byte. Keep that pattern when adding cases.
- **Mutation-test new cases**: break the code and watch the case go red. Every case in
  `romm_tests`/`av_tests` is a bug that shipped; add to them when fixing that layer.
- `rope_bench --settle` (`still_awake=12`) and `rope_stress` are BIT-EXACT oracles — an
  unintended move in those numbers is a stop-everything signal.
- `scene_tests` never drives a real `change_scene()` (SubViewports hang headless).
- netplay suites print a fixed Godot `ObjectDB` shutdown warning — expected, do not "fix"
  it by removing the autoload.
- `libretro-godot/tests/run_tests.py` and `surround-godot/tests/run_tests.py` are Godot-free
  C++ harnesses.

**For anything visual, a photo (or an mp4 for animation) delivered inline in the chat is
the proof of validation** — headless cannot show how something looks. Encode with
`imageio` (`codec="libx264"`, pass `-crf 24`). Visual probes run **windowed, never
`--headless`** (the dummy renderer returns a correctly sized BLANK image, so size oracles
pass on nothing): `--resolution 320x240 --position 20,20`.

### Godot binary — use 4.7.2

```
C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```
The doubled name is real (a FOLDER named `.exe`). Use `_console.exe`. The older
`Godot_v4.7-stable_win64\` beside it fails every Quest export with a misleading "Android
build version mismatch". Linux: `~/Godot/Godot_v4.7.2-stable_linux.x86_64`.

### Compile / import check
```bash
"$godot" --headless --path RetroXR --editor --quit
```
Reimports, recompiles every script and shader, and **regenerates the `class_name` cache** —
run it after adding/renaming a `class_name`, and between overwriting a texture and rendering
it. Filter for `SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load|Failed to instantiate`.

### Functional probe
Tiny `probe.gd` (`extends Node`) + `probe.tscn`, print `[probe] …`, `get_tree().quit(0)`,
with a `create_timer(5.0)` quit as a safety net. **Delete the probe and its `.uid`/`.import`
when done.** Run through Bash with `timeout 90 "$godot" … 2>&1 | grep -a "\[probe\]"` —
PowerShell buffers output until exit.

### Gotchas
- **Some warnings are errors**, notably `:=` inferred from a `Variant`
  (`var x: Object = ClassDB.instantiate(...)`). Duck typing (`unsafe_method_access`) is fine.
  4.7 also requires every path of a `Variant`-returning virtual override to return.
- **A `SubViewport` with `UPDATE_ALWAYS` hangs a headless run** — test wiring, not frames.
- **Headless noise to ignore:** OpenXR `xrCreateInstance failed`, missing GDExtension DLLs
  in the `template_debug` path, `.NET Sdk not found`, `xr_staging_shim.gd … placeholder
  instance` (`Tools/run_tests.py` filters the same list).
- **Stale texture import:** delete `RetroXR/.godot/editor/filesystem_cache*`, then
  `--editor --import --quit`.
- **A `.tscn` `Transform3D` lists the basis by ROWS**, the constructor takes columns — a
  hand-written rotation comes out inverted. `R_y(+90)` = `0,0,1, 0,1,0, -1,0,0`;
  `R_y(-90)` = `0,0,-1, 0,1,0, 1,0,0`. Never check against a 180° or symmetric matrix;
  print `node.transform.basis.x/.y/.z` from a probe first.
- `FileAccess.file_exists("res://….tscn")` is false in exported builds — use
  `ResourceLoader.exists()`.
- **Never raise a live `VerletRope`'s `segment_count` (or `tube_sides`/`smoothing`) without
  re-laying it.** The setter resizes nothing while the solver bounds its loops by
  `segment_count + 1`, so the next tick writes off the end of `m_points` — heap corruption,
  then a silent death seconds later with nothing logged. `_init_points()` must follow in the
  SAME frame; a `call_deferred` re-lay is already too late. Unfixed in the extension (§2r).
- A cord leaves a body along its anchor's local **-Z**; assert the exit direction by SIGN.
- No two same-facing coplanar faces on a generated mesh (z-fights); measure printed widths,
  never trust one from a comment.

### Verify with a check that can fail

**A green check that cannot tell the two outcomes apart is not a check.** Ask what the WRONG
version would look like first. A facing is settled by a printed basis or a render of
something ASYMMETRIC (a seated lead, not an empty socket). Probes that compare against a
core carry a control leg, **one core and one leg per process** — starting a core wrongly
can kill the process (extension is `-fno-exceptions`, no sandbox).

## Feature notes — read the doc before touching the area

| § | doc (`docs/dev/`) | what it covers, and the rules most often broken |
|---|---|---|
| 2b | `bedroom-probe.md` | `Tools/models/bedroom_probe.tscn` — do NOT hand-roll another; it forces ceiling light 0.6 on purpose. |
| 2c | `av-suite.md` | `av_tests`. Pulling a plug needs every RcaPort shut AND the plug frozen; with phosphor on, the oracle is `_crt_source_tex`. |
| 2d | `bios-boot.md` | `BiosBoot` table provenance. **Never loop cores in one process.** `.info` `supports_no_game` is useless; the usual mechanism is empty MEDIA. The survey writes the real `core_options/` and restores it. DS/DSi home screen: `ds_boot_probe`; melondsds no-content, melonds a zero-byte `.nds`, desmume card-only; `also_needs` is all-of, `retire_files` moves a core's poison leftovers aside; probe a REAL data root too (saved `/notfound` firmware path, `wfcsettings.bin`). |
| 2e | `gb-link.md` | gambatte and mGBA share wire `gb-sio-1`. Drive the two machines one at a time; Tetris DX is not a usable target. Game Gear: genesis_plus_gx on `gg-ext-1` (UART + parallel pins, byte-time delivery, no framing error with no cable); Faceball/MK/MK2 need the two machines powered on at different times. |
| 2e′ | `ws-link.md` | WonderSwan Communication Cable: our `mednafen_wswan` fork speaks `ws-sio-1` (RetroArch#19454 API), a byte stamped at its stop bit; `LinkPort` on `wonderswan.tscn`, lead is `gb_link_cable`. Three game-driven core fixes (flush on port-off, level send IRQ, One Piece SRAM). Game probe: one leg per process, confirm one unit at a time, `--nocable` control leg. |
| 2e′ | `ws-link.md` | WonderSwan Communication Cable: our `mednafen_wswan` fork speaks `ws-sio-1` (RetroArch#19454 API), a byte stamped at its stop bit; `LinkPort` on `wonderswan.tscn`, lead is `gb_link_cable`. Game probe: one game per process, with a `--nocable` control leg. |
| 2e-sat | `saturn-link.md` | Saturn Link Cable: our `mednafen_saturn` fork (Beetle) emulates the SH-2 SCI — it never existed — on wire `saturn-sci-1`, **slave SH-2 only** (a master-line crossover hangs both at boot). Bytes announced at shift START; DRCR RXI/TXI now pace DMA (Daytona). Link games: Steeldom, GunGriffon II, Daytona **Circuit Edition (JP)**, Doom, Gebockers, Hyper Reverthion — NOT Hyper Duel / Virtual On. `saturn_link_*` extends `psx_link_*`, own plug group. `SS_SCI_TRACE` floods stall the core. |
| 2e‴ | `lynx-link.md` | ComLynx: our `mednafen_lynx` fork speaks `comlynx-1`, 2–8 units on the GBA lead (`link_cable`, its junction chains more). A byte lands at its STOP BIT, a unit's own echo goes through the shared inbox, overlapping frames AND — each one was a game failing without it. **Probes stagger power-on** (identical units on identical clocks collide on every byte: received == sent is the tell) and run ONE at a time. BIOS in `system/mednafen_lynx/`. Gauntlet and California Games still start alone. |
| 2f | `netplay.md` | `netplay_tests` runs 2–3 NetworkManagers in ONE process. Cross-platform play is a build-identity problem: compare `GetCoreIdentity()`, published in two halves (`serialize_size` 0 = not measured yet; requiring a frame deadlocks cold start). Real-ROM sensor/lightgun validation is OWED — never present the mock suite as that proof. |
| 2g | `netplay.md` | A link cable never crosses the network: every machine on every connected wire is in the session; all three lead types answer `linked_machines()`; a plug seated mid-game lands on ONE host-agreed frame. dolphin is DETERMINISM-only (no state transfer). |
| 2h | `expansion-carts.md` | Super Game Boy: snes9x's SGB constant is vestigial → row pins **bsnes**; ident `sgb`, Game Boy ROM FIRST; resolve subsystems by IDENT, never a hardcoded id; bsnes saves via its own VFS, not SramPaths. |
| 2i | `expansion-carts.md` | Sufami Turbo: snes9x `multicart_addon`; STBIOS.bin required; slot B saves via `SetSramBPath`, keyed to the cartridge; a core-info overlay REPLACES an entry, so it must be a whole copy. |
| 2j | `expansion-carts.md` | DS Slot-2: `Slot2Catalog`, melondsds `gba` subsystem; the GBA save file must EXIST and be NON-EMPTY before load (seeded by `Slot2Catalog.blank_gba_save`). |
| 2k | `ps2-cards.md` | `PS2Card` filesystem (`card_flags` 0x2B, blank image pinned by SHA-256). Icons: +Y down, unshaded, vertex colour scale depends on texture. Staging and draining both hang off `_core_owns_card_files`; pcsx2 cannot hot-swap, pcee2 only with a seeded directory. |
| 2l | `controller-audio.md` | Env call 96, Wii Remote speaker; header kept byte-identical in the Dolphin fork. |
| 2m | `sega-backup-memory.md` | Sega CD: genesis_plus_gx writes BRAM only at unload → `SegaCdStorage` stages, drains, manifests. |
| 2n | `sega-backup-memory.md` | Saturn: System Memory via SAVE_RAM, cartridge `.bcr` via `SaturnStorage`; pinning the cart option removes Auto Detect (Extended RAM carts owed). |
| 2o | `microphones.md` | ONE reader (the `Microphone` autoload) because Godot keeps one cursor; device open only while a core listens; silent in netplay. DS, GameCube DOL-022, N64 VRU (Vosk, opened at run time, the GAME decides when it listens), Dreamcast HKT-7200, and the Famicom (a BIT, a `famicom` systemid, captive hardwired pads kept out of `"spawned"`, RF carries sound). |
| 2p | `saves.md` | `SramPaths`: batteries per SYSTEM, clocks and savestates per CORE; `PER_CORE_SYSTEMS` = N64, 64DD, FDS (measured incompatibilities). `resolve_cart_save` moves NOTHING; `SaveMigration` runs once at boot. `save/<core>/` is the core's own dir. |
| 2q | `n64-cartridges.md` | `N64CartShell` (header CRC + market, never hashed), `CartridgeColor`, flake shader. Bodies carry no marks. Run `Tools/glb/fix_unmapped_uvs.py` on any re-exported body; never `demetal` this model. `HoldPress` spawn sub-menu. |
| 2r | `surround.md` | FreeSurround from DOLPHIN's copy; surround is six mono VOICES, per-machine opt-in; the fronts ARE `m_voice_l/r`; external modes silence the set and nothing ever folds onto its own speakers; degrade to stereo, never silence. `surround_probe` is windowed with a stereo control. Nobody has listened to it yet. |
| 2s | `systemids.md` | A systemid is ES-DE's folder name (`n64`, `snes`, `psx`); `SystemIds.LEGACY` reads the old ones. **Card `family`, expansion ids and `model_id`s look like systemids, are persisted, and did NOT move.** Run `Tools/rename_systemids.py` after any `.info` refresh. Prefs are re-keyed as they LOAD, never rewritten at boot. |
| 2t | `tv-aerial.md` | ONE coax socket, ONE dial: Famicom 1/2, NES 3/4 and an **Antenna**'s channels merged numerically (`rf_dial`). `Source.TV` is RETIRED, not removed — its value is on disk and the wire, never renumber. The Antenna is a `CompositeCable` with a CAPTIVE end (no `PlugA0`): walk cords through `_plug_at`. `TVLineup` (reception, on the Antenna) vs `TVTuner` (playback, on the set); the tuner's settings are on the ANTENNA's Tab menu. No network in a suite: `Antenna.lineup_override` stays set until a restore has SETTLED. A real broadcast through one is OWED. |
| 2u | `xbox.md` | The Xbox on **xemu**, RetroXR's own port: `CoreSources` names `RetroXR/xemu` at `retroxr-xemu-libretro-v2` (branch `retroxr`); the buildbot has NO xemu row to override, so `_list_own_core` lists it — from `known_tag`, or from the version probe for a core with no known release, which is how this one began. The overlay `.info` uses BARE firmware paths (the fork's `xemu/…` would mean `system/xemu/xemu/`). XISO only, no savestates, **one Xbox at a time** (`XboxStorage`). An EMPTY tray boots the dashboard (`BiosBoot` `xemu/xbox`, `no_content`), which on the stock disk is a placeholder drawing one line of text — and measuring that needs EVERY pixel, not a sample grid. Saves live in ONE shared `xbox_hdd.qcow2`: a game's `UDATA`/`TDATA/<title id>` is LIFTED out read-only after stop (`Qcow2Image`, `FatxVolume`, title id from `default.xbe`) and pushed like a card save, upload-only, in a hand-written deterministic zip. A real RomM upload is OWED — never present the fake-server case as that proof. **Memory Units** (`XboxMuCard`, family `xbox_mu`) go in a CONTROLLER, two to a pad, in the SAME sockets as a VMU (`VmuPort.XBOX_SLOT_GROUP`; its origin is 40 mm below the connector, not its centre). xemu takes no path: `XboxStorage` stages each into `memory_unit_port<N>[b].img`, flips `xemu_memory_unit_port<N>[b]`, drains to the unit that FILLED the file and only a tree that walks whole; hot-plug is LIVE. `XboxMemoryUnit` reads AND writes the FATX, and a hard-disk lift (`UDATA/<title id>/…`) inserts into a unit — the way home. Slot B needs core `03a3fb9ea2`+ (an older one is detected and toasted). NEVER write a slot's file while its option is on: OFF → 0.5 s → drain → stage → ON. The core logs `memory unit 1A detected / read / written to by the console` at WARN — measured: both slots detected AND read, live hot-plug too. That the console PARSES a save RetroXR wrote is still unproven: no game here lists a unit (Halo detects, Conker reads and lists nothing). |
| 2v | `books.md` | `PDFBook` paper is bent in the VERTEX stage (rest shape → fold → flop), never rebuilt. **Anything that moves a sheet must move the block under it from the same numbers** (shared `.gdshaderinc`s; that bug shipped twice). `BookFlop` is a few pendulums, not cloth: the body is FROZEN while held so motion comes from the pose; only a HAND makes a book hang (not a snap zone); the tick is default-off and disarms exactly flat; physics never changes `BookState`. A book is held WHERE it was taken (`pick_up` overrides the fork's origin-into-hand patch, clamped onto the book) and by one or two hands — GRIP holds, TRIGGER is the page, so the old grip quick-flip is GONE, do not bring it back. `hardback` (default off, options panel, saved) zeroes the bend rather than stiffening it. The page being turned BENDS (a partial curl, cycloid inverse — not the old origami crease that snapped a sliver over) and FOLLOWS the hand: the leaf also LIFTS about the gutter as a RIGID hinge applied before the droop, in CLOSED FORM (never search for the lift — it is not monotone and the page jitters); zero for a low pull, so the old roll-over is untouched; paper cannot stretch, so a hand out of reach gets a taut page pointing at it and the gap left is REAL. Judge a turn's continuity by a point on the PAPER, not the lift angle. Only the turning leaf widens its hinge arc with height (a lifted sheet over the tight bend stretches 3.7×). Flop is cosmetic and local: never on the wire, and only `hardback` is saved. How it looks is `book_flop_probe` (windowed) + the headset, not the suite. **A page texture NEVER reaches the main thread except as the upload**: the PNGs in `user://pdf_cache/` outlive the app, and reading one inline (it needs no render, so it looked free) cost 14 ms a page and made every turn of an already-read book hitch while the first read was smooth — both branches of `_get_page_texture` go to the pool, and `_drain_uploads` spends uploads a frame, spread first — **2 on desktop, 1 on Quest**, where an upload is 6–7.5 ms of an 11.1 ms frame (measured on device: a turn went 50–112 ms → 0.5 ms, a reopen 327 ms → 0.5; page PIXELS are the remaining lever). A page stays in `_pending_renders` until its TEXTURE exists, which is what `_drain_renders` means. `Tools/perf/page_turn_probe` (windowed). **Read a broken book by its COVER: cream is `_loading_texture` and means it loaded; navy is the scene's authored `Mat_cover` and means the file never opened** — `_apply_dimensions()` bails on `_page_count == 0`, so no shader, no page stacks, and collision left as an open spread centred on the SPINE (the 2026-09-20 Quest "odd collision"). No `user://pdf_cache/<md5>/` is the other tell. Every failure return calls `_show_load_failure()`; a `push_error` cannot be read in a headset. A book that failed STAYS failed — `pdf_path` is set before the attempt, so re-assigning it is a no-op. **The lift hands over to the roll by bearing TIMES height (2→5 cm above the far page)** — never remove it (a set-down page sinks 30 mm through the far block) and never go back to bearing alone (a held page lets go past upright, 11–22 cm); it is a measured trade, see `books.md`. A mid-turn texture refresh must go through `_relay_turning_leaf()` or it re-lays the page being turned beneath itself, and the first/last leaf is a COVER that takes its cover mesh and block with it. A released page FINISHES THE WAY IT WAS BEING TURNED: with any lift (>5°) it falls over (lift→π, onto the far page); winding the lift back while the roll closes slides it 24 mm UNDER the page it lands on. |

Probes for Meta XR Audio features (`2l`, `2r`, mics) need the SDK enabled in the probe via
`mx.set_enabled(true)`; under `--headless` it reports unavailable and there are no voices.
A core's diagnostic line must be logged at **WARN** — libretro-godot drops everything below.

## On-device (Quest over adb) — `docs/dev/quest-device.md`

In Git Bash `export MSYS_NO_PATHCONV=1` first.

```bash
python Tools/place_engine.py --target debug
"$godot" --headless --path RetroXR --export-debug "Quest" out.apk && adb install -r out.apk
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close   # fake "worn"
adb shell setprop debug.oculus.guardian_pause 1
adb shell monkey -p com.xenu.retroxr 1          # am start = Permission Denial
adb logcat -c && adb logcat -s godot:* > quest.log &   # ring buffer rotates in <1 min
```
All three launch steps are required; undo them after (`guardian_pause 0`, `prox_open`,
`am force-stop`). Hand tracking must be on in BOTH the preset and `project.godot`.

- **Stale-script trap:** if a change does not take on device,
  `rm -rf RetroXR/android/build/src/main/assets RetroXR/android/build/build/intermediates/assets`
  and re-export.
- `user://` is internal `/data/user/0/com.xenu.retroxr/files/` (`run-as`); ROMs are on
  `/sdcard/Android/data/com.xenu.retroxr/files/`.
- **Never `adb push` over a file, or into a directory, that the app itself writes** — the
  app is `other` for everything `shell` creates (0644 files it can never overwrite, 0770
  dirs it cannot enter), and `chmod 660` makes it worse. Let the app recreate it.
- Microphone unattended: `adb shell pm grant com.xenu.retroxr android.permission.RECORD_AUDIO`.

## CI

Three workflows in `.github/workflows/`: **`tests.yml`** (the gate — builds the extensions
for windows debug, imports, fails on any script/shader error, runs `Tools/run_tests.py`),
**`release.yml`** (`preflight` → `quest` + `windows` → `release`, on a tag or dispatch),
**`sidequest.yml`**. A suite added to `Tests/` is picked up with no CI edit.

## Mods — `docs/dev/mods.md` (maintainer), `docs/modding.md` (authors)

One `.zip`/`.pck` in `<data root>/mods/`. Loader in `Scripts/Mods/`; the `Mods` autoload
must come BEFORE `AppPrefs` (`autoload_order_tests` enforces the boot order). A pack is read and validated WITHOUT
mounting (mounting cannot be undone), so enable/disable applies next launch. Everything a
pack ships lives under `res://mods/<id>/` unless listed in `claims`. Shipped `const` tables
stay the base with `static var` overlays; mod models stay out of `ModelWarmer`'s boot warm
(`stand_in_ids()` etc. read `_ROWS` on purpose). `RoomCatalog` replaced the old
`SCENE_PATHS`/`SCENE_TITLES`/`SLOT_ROOMS` consts. **The app never distributes a mod** —
netplay sends only an `id@version` fingerprint. Mods are authored inside a checkout, in
`RetroXR/mods/<id>/`. `SystemInfo.media_type` is read by nothing; `DISC_INSERT` means the Wii.

## Android plugin

`qr-scanner-android/` is a Gradle/Kotlin Godot Android plugin (not a GDExtension, not
built by `Tools/build.py`); its Godot half is `RetroXR/addons/retroxr_qr`.
`RetroXR/addons/retroxr_build_stamp` writes the `res://build_info.json` that
`Scripts/Data/build_info.gd` reads.

## Architecture — full notes: `docs/dev/architecture.md`

- **Multi-instance:** each `Libretro` node owns a `Wrapper` and its emulation `std::thread`;
  many can run at once. Main ↔ emulation thread talk through a lock-free
  `ReaderWriterQueue` of `ThreadCommand`s drained in `Libretro._process()`.
- **Static libretro callbacks resolve their instance via
  `Wrapper::GetCurrentThreadWrapper()`** (a `thread_local`) — never store a raw global
  pointer. Main-thread commands carry an explicit `Wrapper*` and set it around `Execute()`.
  Use `call_deferred` to signal back to the node (e.g. `NotifyOptionsReady`).
- **Classes:** `Wrapper` (orchestrator), `Core` (loads the core via `DynLib.hpp`, copied to
  a temp dir), `Libretro` (the GDScript-facing node: `StartContent`, `StopContent`,
  `SetCoreOption`, …). Handlers per Wrapper: Video (software, Vulkan, OpenGL, D3D11/12,
  Metal layer), Audio, Input, Environment, Options, Message, Log, RetroAchievements
  (rcheevos compiled in). `LinkCoordinator` is the one process-wide singleton (§2g).
- **Input is PUSHED per port from GDScript** (`SetJoypadState`, `SetJoypadExtraButtons`,
  mouse, keys, lightgun, pointer, sensors, `SetPortDevice`) — `InputHandler` never reads the
  global `Input`, which is what lets several machines and netplay replay coexist.
- Android heap pointer tagging is switched off at extension load (`RegisterTypes.cpp`).
- GDScript side: `Scenes/BootScene.tscn` is the main scene on every platform and defers
  into `SceneManager.boot_room()`; `Scripts/Objects/systems/system.gd` is the per-machine
  controller with a child `Libretro` node (`system.tscn` `unique_id=-294967286`, signed).

## Dependencies

godot-cpp (submodule, 4.5 branch), SDL3 (Windows core loading + GL window; Linux GL window
only; not Android), libretro-common, rcheevos (submodule), Vulkan-Headers (submodule),
moodycamel ReaderWriterQueue, libVLC, PDFium (prebuilts committed; refresh with
`Tools/download_pdfium.sh`, not the unmaintained `.ps1`), FreeSurround.

**godot-xr-tools v4.5.1 is FORKED IN PLACE** (`RetroXR/addons/godot-xr-tools/`, 30 local
commits in snap_zone, player_body, grab driver, pickable teardown). Dropping a fresh
upstream copy over it silently reverts all of it, and no headless suite covers grabs. Diff
first: `git log --oneline -- RetroXR/addons/godot-xr-tools`.

## Code Conventions

- C++latest (MSVC), C++20 elsewhere. Logging via `Log`, `LogOK`, `LogWarning`, `LogError`.
- Option data reaches GDScript as `LibretroOptionCategory` / `Definition` / `Value` objects.
- Write code that matches the surrounding file's comment density and idiom.

## Tools — full notes: `docs/dev/tools.md`

Repo-root `Tools/` holds out-of-band scripts (`RetroXR/Tools/` holds probe scenes).
`python -m pip install -r Tools/requirements.txt`; `Tools/glb/*.py` run inside
`blender --background --python`. GLBs are **Git LFS** (`git show` yields a pointer — pipe
through `git lfs smudge`). `decimate_glb.py` must WELD first; `glb_diff.py` checks a round
trip preserved names, hierarchy and placement, because seat/port constants are hand-measured
in the GLB's frame.

**Only add 3D assets this project has the right to ship**, with licence and attribution
alongside (`RetroXR/imported-assets/`, credited in the About panel). The NES pad drawing is
the repo's ONLY CC BY-SA asset: the About panel must keep crediting it and the modified file
stays CC BY-SA. A console pad's art is drawn inside `_draw()`, not parented as a TextureRect.
