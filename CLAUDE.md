# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RetroXR is a VR retro-gaming room in Godot 4.7. Its core is `libretro-godot`, a GDExtension (C++, submodule, forked from SKurdt's SK.Libretro.Godot) that runs libretro emulator cores inside Godot and bridges Godot's scene system to the libretro API.

The app is `RetroXR`, package `com.xenu.retroxr`. The Godot project folder is `RetroXR/`,
and the desktop data root stays `~/retroxr/{roms,books,videos,…}` — it holds user ROMs, so
it is deliberately not renamed.

The Godot project in this repo:
- `RetroXR/` — VR arcade room (primary development target, godot-xr-tools based)

## Git Workflow

**Commit directly to `master` unless the user says otherwise.** This is a solo repo —
do not branch-per-feature by default; commit and (when asked) push straight to `master`.
Branch only when the user explicitly requests it.

## Build Commands

Requires SCons and MSVC (Windows), GCC/Clang (Linux), Xcode command-line tools (macOS),
or Android NDK (Android). The godot-cpp submodule must be initialized first:
```bash
git submodule update --init --recursive
```

### One command for every extension

`Tools/build.py` builds all seven GDExtensions for one platform. It first builds one
shared, trimmed `godot-cpp` static library for each target, then runs the extensions
sequentially with `build_library=no` (they still cannot share a scons invocation —
see below). Prefer it over the per-extension recipes further down, which are kept
because they document each build's quirks. The shared API allowlist is
`Tools/godot_cpp_profile.json`; add a Godot class there when extension C++ starts
including or calling it.

```bash
python Tools/build.py windows              # both template_debug and template_release
python Tools/build.py android --target release
python Tools/build.py linux --only vlc-godot
python Tools/build.py macos                    # host architecture, macOS 13.0 minimum
python Tools/build.py macos --arch x86_64      # Intel Mac binaries
python Tools/build.py windows --jobs 8 -- verbose=yes    # extra args go to scons
```

Asking for `linux` **from Windows** re-invokes the script inside WSL (`--distro`,
default `Ubuntu`), resetting HOME and PATH — WSL inherits the Windows environment,
whose PATH contains spaces and breaks a bare `export PATH="$HOME/.local/bin:$PATH"`.
Asking for it from Linux just builds. This replaced `Tools/build_linux.sh`.
It reports a per-extension pass/fail table and exits non-zero if anything failed.

**Not all seven ship everywhere.** `metaxr-audio` is windows/android only — it wraps
Meta's `MetaXRAudioUnity` blob, which Meta publishes for win-x64 and android-arm64
alone, and `metaxr_audio.gdextension` has no Linux or macOS entry. The C++ compiles for
Linux perfectly well (the loader just finds nothing and `is_available()` returns
false), so the skip is a shipping decision, not a compile failure. A whole-platform
run skips it with a note; `--only metaxr-audio` on Linux or macOS is an error.
`vlc-godot` is also skipped on macOS because no redistributable libVLC runtime/plugin
tree is vendored yet.

**scons is not installed system-wide in either WSL distro** (`Ubuntu` has g++ but no
scons; `FedoraLinux-44` has neither on PATH). Install it into the distro first.
On the native CachyOS box there is no `pip` on PATH at all (Python 3.14, externally
managed) — `uv tool install scons` is the one that works there, and it lands in
`~/.local/bin` just the same.

Build from the **workspace root** (not `-C Temp`):
```bash
# Windows (PowerShell)
$scons = "$env:APPDATA\Python\Python314\Scripts\scons.exe"   # pip install --user scons
& $scons platform=windows arch=x86_64 target=template_debug dev_build=yes
& $scons platform=windows arch=x86_64 target=template_release

# Android / Quest (bash — requires ANDROID_NDK_ROOT)
ANDROID_NDK_ROOT="C:/android/android-ndk-r27d" ANDROID_HOME="" \
  scons platform=android arch=arm64 target=template_debug ANDROID_HOME=""

# Linux desktop x86_64 (bash — GCC/Clang; SCons via `uv tool install scons`)
scons platform=linux arch=x86_64 target=template_debug
scons platform=linux arch=x86_64 target=template_release

# macOS (build arm64 and x86_64 separately; PDFium requires macOS 13.0)
scons platform=macos arch=arm64 target=template_debug macos_deployment_target=13.0
scons platform=macos arch=x86_64 target=template_release macos_deployment_target=13.0
```

The `SConstruct` is at the workspace root; `libretro-godot/Temp/SConscript` does the
actual build logic. (`Temp` is the `VariantDir` the root `SConstruct` declares over
`libretro-godot/`; there is no `Temp/` at the workspace root, so a bare `Temp/SConscript`
path is wrong.) Output libraries go to `RetroXR/libretro-godot/`.

The Linux build links `libvulkan.so.1`, `libSDL3.so.0`, and `libGL.so.1` by soname (no
`-dev`/`-devel` packages needed). All three render paths work on Linux: software, Vulkan
HW-render, and OpenGL HW-render (SDL3-created hidden GL window — needs a display server at
runtime). Desktop Linux support was added 2026-07-13 (Windows x86_64 + Android arm64 were
the original targets).

Linux build internals worth knowing: SCons isn't system-wide here — it's `pip install
--user scons` (lands in `~/.local/bin`, so prefix commands with `PATH="$HOME/.local/bin:$PATH"`).
`CallbackTrampolines.cpp` has a dedicated `EmitTrampolineSysV` (x86-64 System V ABI:
RDI/RSI/RDX/RCX/R8/R9 + XMM0-7 + AL) — the Windows `EmitTrampolineX64` uses the wrong ABI, so
Linux/Windows/Android each need their own trampoline. GDScript platform logic used to be
"Android-vs-else(=Windows)"; several files (`core_download_manager.gd`, `download_manifest.gd`,
`spawn_menu.gd`, `rom_library.gd`) were made explicitly Linux-aware (buildbot URL
`nightly/linux/x86_64/latest/`, `.so` ext, `$HOME/retroxr/...` roots). Runtime emulation of a
real core on Linux is only lightly verified — build + extension-load + type-resolution are proven.

The macOS libretro build currently supports software-rendered cores only: Vulkan needs
MoltenVK and the OpenGL path needs a packaged SDL3 runtime. Core downloads use libretro's
`nightly/apple/osx/<arch>/latest/` dylibs, and desktop data remains under `~/retroxr`.
Both extension architectures target macOS 13.0. An official arm64 2048 core was exercised
for 168 frames in a three-second runtime probe; VLC, Meta XR Audio and a signed/notarized
macOS export preset remain future packaging work.

A hardened Mac export will need library validation disabled for downloaded unsigned cores
and unsigned executable memory for callback trampolines; dynarec cores may also need the
JIT entitlement.

### The Quest ships a PATCHED engine

The stock 4.7.2 Android template has six defects on a Quest 3 that each have
a fix: a boot deadlock in the Forward Mobile shader lock scope; colour and
depth buffers stored every frame though nothing reads them (and their
subsampled twins); the swapchain loaded into tile memory every bin though the
pass overwrites it; the foveation density map left blank after any MSAA or
eye-buffer change (the update mode ONCE was demoted to DISABLED and never
re-armed, 28 ms instead of 13); and every frame going through a 10-bit scene
buffer plus a tonemap subpass even when that subpass is a copy. The fixes are
`docs/godot-4.7.2-*.patch`, applied on the engine branch `retroxr-4.7.2`
(4.7.2-stable + all of them) in `~/godot`, pushed to
https://github.com/RetroXR/godot/tree/retroxr-4.7.2. The prebuilt arm64
libraries from that branch live under `Tools/engine/` (Git LFS) and
`Tools/place_engine.py` swaps one into the Android build template's AAR:

```bash
python Tools/place_engine.py --target release   # what release.yml runs before the export
python Tools/place_engine.py --target debug     # for a local Quest export
python Tools/place_engine.py --target debug --restore
```

**The direct render path is a project setting**,
`rendering/renderer/mobile/render_directly_to_target` (on in `project.godot`;
the engine default is off). With it the scene is drawn in one subpass straight
into the swapchain, or resolved into it under MSAA, and the scene shader
applies the environment's tonemapper in its epilogue, and so does the sky
pass. It only engages when the tonemap subpass would be a copy: no glow and no
colour adjustments (a sky room measured 3.70 -> 3.59 ms, same picture).
`rendering/renderer/mobile/direct_target_srgb_view` (default on) draws through
an sRGB view so the hardware encodes and blending stays linear; off, the shader
encodes and transparent surfaces blend on encoded values. Measured 2026-09-09,
arcade slot, MAX foveation, GPU 545 MHz, App ms:

| view                        | subpass | direct |
|-----------------------------|--------:|-------:|
| full view 1.5x, MSAA 2x     | 5.7     | 4.3    |
| empty frame 1.75x           | 3.4     | 3.1    |
| full view 1.5x, no MSAA     | 3.3     | 3.7    |

So it is the MSAA path it pays for; the per-fragment Filmic costs more than the
subpass on a plain view. **Do not read an sRGB-view experiment off a screencap
alone**: RenderingDevice used to declare a framebuffer on a shared view with
the OWNER's format, so an sRGB view stored raw linear values (a picture three
times too dark in the mid-tones) with no error anywhere. Fixed in the same
patch; the resolve path had encoded correctly all along, which is how it was
caught.

Rebuild both libraries when a patch changes (each ~1 min incremental, the
first build of a tree ~5 min):
`cd ~/godot && ANDROID_HOME=C:/android scons platform=android arch=arm64
target=template_release generate_apk=no -j14` (and `template_debug`), then
copy `platform/android/java/lib/libs/<target>/arm64-v8a/libgodot_android.so`
over `Tools/engine/android/arm64-v8a/libgodot_android.template_<target>.so`.
`scons` is not on PATH in Git Bash: `$APPDATA/Python/Python314/Scripts/scons.exe`.
A shader include placed under `shaders/effects/` is not a dependency of the
forward_mobile shaders (their SCsub globs `*_inc.glsl` and `../*_inc.glsl`), and
one placed inside the `!MODE_UNSHADED` guard is missing from every unshaded
variant, which fails at pipeline creation with "no matching overloaded
function" and a SIGTRAP in a worker thread, not at build time. Measured earlier
the same day at 1.5x: App 13.1 -> 11.5 ms for the discardable and clear
patches; the deadlock fix booted 10/10 where stock hung on launch 2.

### Sibling GDExtensions (archive-godot, verlet-rope, vlc-godot, godot-pdfium, metaxr-audio, surround-godot)

Six other C++ GDExtensions live beside libretro-godot, each with the same layout (repo-root
`<name>/` with `SConstruct` + `SConscript` + `src/`, reusing `../libretro-godot/godot-cpp`,
deploying to `RetroXR/<name>/`). Build each **from its own directory** (each has its own
`VariantDir('Temp')`), or all at once with `Tools/build.py`.

- **archive-godot** — `RommArchiveExtractor`, a bounded-memory ZIP reader used by RomM
  downloads. It streams archive members directly to temporary files, validates their sizes
  and CRCs, then promotes them into place. It is pure godot-cpp and deliberately separate
  from the libretro emulator bridge.
  ```bash
  cd archive-godot && scons platform=macos arch=arm64 target=template_debug macos_deployment_target=13.0
  ```

- **verlet-rope** — `Xenu::VerletRope`, the simulated cable hanging off every controller and
  A/V plug. Lived inside `libretro-godot` until 2026-08-02 and was moved out (and purged from
  that submodule's history) because it never belonged there: it includes nothing from libretro
  and libretro includes nothing from it. Pure godot-cpp, no third-party dependency, so it is
  one of the simplest extensions to build.
  ```bash
  cd verlet-rope && scons platform=windows arch=x86_64 target=template_debug
  cd verlet-rope && scons platform=macos arch=arm64 target=template_debug macos_deployment_target=13.0
  ```

- **vlc-godot** — libVLC-backed `VlcPlayer`, used by both the DVD player **and** the VHS/VCR
  (the old `eirteam.ffmpeg` addon was dropped 2026-07-14 — libVLC is the single video backend;
  it also handles x265/HEVC, which eirteam.ffmpeg did not).
  ```bash
  cd vlc-godot
  PATH="$HOME/.local/bin:$PATH" scons platform=linux arch=x86_64 target=template_debug
  PATH="$HOME/.local/bin:$PATH" scons platform=linux arch=x86_64 target=template_release
  ```
  Linux links the system `libvlc` (Fedora `vlc-devel` provides `/lib64/libvlc.so` + headers;
  runtime needs `vlc-libs`). HEVC works out of the box via VLC's system plugin dir — no plugin
  bundling on Linux. Output: `RetroXR/vlc-godot/libvlc_godot.linux.template_{debug,release}.x86_64.so`.

- **godot-pdfium** — `PDFRenderer` (opens a PDF, renders a page to a Godot `Image`), backed by
  the bblanchon/pdfium-binaries `libpdfium`. Every platform's prebuilt is committed, so a fresh
  clone needs no fetch; `Tools/download_pdfium.sh` refreshes them when you do (it replaced the
  PowerShell script, which only knew win-x64 + android-arm64):
  ```bash
  Tools/download_pdfium.sh -p linux     # just this platform's lib; include/ untouched
  Tools/download_pdfium.sh -p mac       # macOS arm64 (`mac-x64` for Intel)
  cd godot-pdfium
  PATH="$HOME/.local/bin:$PATH" scons platform=linux arch=x86_64 target=template_debug
  PATH="$HOME/.local/bin:$PATH" scons platform=linux arch=x86_64 target=template_release
  scons platform=macos arch=arm64 target=template_debug macos_deployment_target=13.0
  ```
  On macOS, the two runtime dylibs coexist under `mac-arm64/` and `mac-x64/`; each extension
  uses an architecture-specific `@loader_path` load command. **Linux rpath gotcha:** the
  shipped `libpdfium.so` shares its SONAME with the Android arm64 copy
  that sits in the output-dir root (tracked in git, referenced by the android `[dependencies]`
  block). An x86_64 lib with the same name would clobber it and break Quest exports, so the
  Linux lib installs to a `linux-x64/` **subdir** and the SConscript adds
  `LINKFLAGS=["-Wl,-R,'$$ORIGIN/linux-x64'"]` (quote exactly like godot-cpp's `tools/linux.py` —
  an unquoted `$$ORIGIN` collapses to a bare `/linux-x64` under this SCons). godot-cpp already
  injects a bare `$ORIGIN` entry, so final RUNPATH is `$ORIGIN:$ORIGIN/linux-x64`; the loader
  skips the arch-mismatched arm64 lib and falls through to the x86_64 subdir. Verify with
  `objdump -p …so | grep RUNPATH` and `ldd …so | grep pdfium` (must resolve, not "not found").
  Added 2026-07-15.

- **surround-godot** — `Xenu::SurroundDecoder`, the Dolby Surround / Pro Logic II matrix
  decoder, and `Xenu::SurroundAudio`, the factory singleton `libretro-godot` reaches it
  through. All five platforms — pure C++ with no third-party runtime — though only
  windows/android have voices to place it on, since that is where `metaxr-audio` ships.
  It is an extension of its own for a LICENCE reason rather than a tidiness one:
  FreeSurround is GPLv2+, `libretro-godot` is MIT and published separately, and
  `metaxr-audio`'s GPLv3 §7 exception is not the user's to grant over Kothe's code.
  See §2r.
  ```bash
  cd surround-godot && scons platform=windows arch=x86_64 target=template_debug
  cd surround-godot && python tests/run_tests.py     # 24 assertions, no Godot needed
  ```

## Headless Testing & Validation

There is no unit-test framework in the xUnit sense, but there **is** a runner and it
gates CI. `Tools/run_tests.py` runs every `RetroXR/Tests/*.tscn` that has a `.gd` beside
it, in a stable order, and `.github/workflows/tests.yml` builds the six extensions and
runs it on every push. Beyond that the project is validated by running the Godot editor
**headless** for compile/scene checks, plus small "probe" scenes for functional tests.
All of it works without a VR headset (desktop fallback) and without a display.

```bash
python Tools/run_tests.py            # every suite
python Tools/run_tests.py --list     # name them and exit
python Tools/run_tests.py --update-baseline   # after deliberately adding cases
```

**A case count that DROPS fails the run.** `Tools/test_baseline.json` records each
suite's count, and the runner compares against it — because a suite whose group
quietly stops running still passes every case it did run and still exits 0,
which is the same blind spot as a suite nested in a subfolder. Only a drop
fails: a rise is how the suites grow, and a suite missing from the file is new
rather than broken, so adding cases never needs a second commit. A filtered run
(`--only`, or a forwarded `--only=<group>`) skips the check, since a lower count
there is the point. When a drop is deliberate, re-run with `--update-baseline`
and commit the JSON with the change that caused it.

Because the runner globs `Tests/*.tscn` **non-recursively**, `Tests/` stays flat. Do not
nest it into subfolders — a suite in a subdirectory is silently never run, which is the
one failure mode a green CI cannot show you. (`RetroXR/Tools/` is the opposite: it is
foldered by topic, see below.)

**The bar for living in `RetroXR/Tests/` is exact:** a scene that checks itself, runs
unattended with no ROM, core, headset or device, and **exits non-zero on failure**, so it
can gate a commit. The suites, with their measured case counts and runtimes (Windows,
debug build, 2026-08-27 — all passing):

| suite | cases | time | covers |
|---|---|---|---|
| `netplay_tests` | 685 | 32 s | the whole lockstep stack, two NetworkManagers deep (§2f) |
| `romm_tests` | 312 | 17 s | the pure-logic half of the RomM stack |
| `binding_tests` | 176 | 12 s | which control map a platform resolves to |
| `object_sync_tests` | 127 | 8 s | the shared-room network layer, 2–3 real ENet peers |
| `scene_tests` | 120 | 10 s | SceneManager and the save gates around it |
| `poster_tests` | 112 | 11 s | the posters feature, stick/peel/conform |
| `rope_tests` | 82 | 69 s | what a cable does when it meets furniture |
| `av_tests` | 41 | 35 s | what reaches a television's inputs (§2c) |
| `system_tests` | — | — | the machine controller's port, pad, save and disc rules |
| `link_tests` | — | — | which socket each end of a link lead belongs in |
| `state_tests` | — | — | savestate capture/restore rules |
| `expansion_tests` | — | — | the expansion units and their catalog |
| `bay_tests` | — | — | cartridge bays |
| `card_tests` / `deck_tests` | — | — | memory cards; the video decks |
| `motion_tests` | — | — | accel/gyro/IR device frames |
| `screen_cast_light_tests` | — | — | light the screen throws into the room |
| `time_of_day_tests` | — | — | the day/night cycle |
| `tv_resize_tests` | — | — | the TV's own geometry |
| `web_server_tests` | — | — | the built-in file server |
| `prop_lighting_tests` | 17 | 1 s | which of a room's meshes go on the baked prop shader, late spawns and despawns included |
| `scrape_tests` | 76 | 10 s | the ScreenScraper queue over a fake client: thread allowance, accept vs review, media wait, quota stop, the AutoScraper gate |
| `microphone_tests` | 55 | 25 s | the capture service: when the device opens, one read fanned out, the distance gain, a seated microphone's position, the DS pins, the DOL-022's slot value and its save round trip, and the HKT-7200 in a pad's slot |
| `famicom_tests` | 101 | 16 s | the Controller II microphone: the volume slider's threshold curve, the gate and its hysteresis, the level measured in C++, the service's one-measurement fan-out, which port the bit may reach, both pads, the captive pair's cords and wells, and the `famicom` systemid's table rows |
| `n64_vru_tests` | 37 | 30 s | the Voice Recognition Unit: no two coplanar faces on the dongle or the microphone, the device id a socket announces through the unit's own plug, seating in socket 4, the microphone in and out of the 3.5 mm jack, which way both cords leave, and the save round trip |
| `n64_cart_tests` | 107 | 10 s | the N64 cartridge: regional bodies, that they carry no mark and no unmapped normal-mapped triangle, which half each moulded part belongs to, per-instance and per-half shell materials, flake parameters and normal maps, repeated switch and reset, the label helper, the coloured-cartridge lookup by header and MD5, the scraped region, and a spawned cartridge |
| `speaker_tests` | 130 | 38 s | the surround rig (§2r): both cabinets' facing, the cabinet's own socket, a lead on each of the set's six outputs, the fold-down and its gains, the AUDIO OUTPUT key, the 1.2 m and 1 m stands, and the save round trip |

Counts are what the suite printed, not a target — they drift upward as cases are added,
so re-measure rather than trusting this table, and treat an unexplained DROP as a signal.

**Everything else is a probe and lives under `RetroXR/Tools/<topic>/`**, including the
ones that assert: they want real cores and ROMs (`cores/azahar_probe`, `cores/sram_probe`,
`cores/vb_probe`, `cores/nds_probe`, `cores/handheld_probe`, `cores/gl_video_probe`), a
headset or a Quest (`netplay/netplay_spike`), or they are reproductions of open bugs and
report failures BY DESIGN (`rope/three_plug_probe`). Moving one of those into `Tests/`
would make a red run meaningless.

### Where the probes live

`RetroXR/Tools/` is foldered by topic. A probe's scene, script and `.uid` sit together,
and a scene refers to its script by literal path, so a probe moved between folders needs
its `.tscn` rewritten too.

| folder | what it holds |
|---|---|
| `av/` | TVs, tuners, phosphor, decks, spatial audio |
| `cores/` | core behaviour, BIOS boot, options, dual-screen, GL video |
| `gen/` | mesh/material generators run with `--script` (no scene); `gen/plug_materials.gd` is the shared one |
| `input/` | controllers, bindings, mice, lightguns, memory cards |
| `link/` | link cables and two-core buses (§2e, §2g) |
| `models/` | geometry authoring, shell audits, model registry, room renders |
| `netplay/` | sessions, rollback, determinism, state transfer (§2f) |
| `perf/` | Quest device probes, spawn/menu cost, VRAM census |
| `room/` | tables, spawn menus, furniture placement |
| `rope/` | cables — the bit-exact oracles `rope/rope_bench` and `rope/rope_stress` |
| `state/` | save/restore, persistence, scene soak |
| `vr/` | grabs, pokes, pointers, sliders, capsense |

Three data directories sit beside them and are deliberately not foldered by topic:
`gblink/` (the ROMs `Tools/gen_gblink_rom.py` writes), `scan/` and
`azahar_stereo_homebrew/`.

`RetroXR/Tests/rope_tests.tscn` is the behaviour half of the rope's cover. Two kinds of
case: where a cord LIES (contact/ — table, over a corner to a floor socket, round a pipe,
on a ledge, heaped, bridging a gap; loose/ — a whole lead dropped flat, across an edge,
from height) and what a player DOES to one (handling/ — a real lead's plug yanked at
5 m/s, towed 2.5 m across the floor, pulled out through a 100 mm slot, carried over a
partition, a cord wrapped round a post and hauled tight), plus inextensibility,
determinism, anchor pinning, teleport re-lay, `set_rope_length` and sleep/wake. 82 cases,
~70 s, no GPU. It complements rather than replaces the two BIT-EXACT oracles in `Tools/`
(`rope_bench --settle` prints `still_awake=12`, `rope_stress` diffs a 22-row table): those
catch arithmetic drift, this catches a cord that jitters, tunnels or will not settle.
(The bench printed 15 until 2026-08-17: DepenetrateLay freed wedged lays and three more
bench ropes settle; the stress rows that moved are the two impossible lays. Re-baselined
deliberately — an UNINTENDED move in these numbers is still a stop-everything signal.)
Two defects this suite caught and got fixed the same day: `AlignAnchorPlug` used to apply
uncapped rotation steps about the cable anchor, a per-tick transform teleport that carried
a dropped lead's plug through a 100 mm floor (now capped at MAX_ALIGN_STEP); and a cord
laid straight through furniture — every restore/teleport re-lay can do this — left
particles wedged inside it for ever (now freed by `DepenetrateLay` on the first tick after
a lay). `Tools/rope/rope_video_probe.tscn` renders the same cases to PNG frames (windowed, not
`--headless`) for when a case has to be WATCHED — most of the traps below were caught on
its footage, not by an assertion.
```bash
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn
"$godot" --headless --path RetroXR res://Tests/rope_tests.tscn -- --only=contact
```
Four traps it already hit. **Measuring jitter after a rope sleeps measures nothing** —
`step()` on a sleeping rope is a no-op, so the answer is a confident 0.000 mm however
badly it chattered; the cases hold the cord awake with `wake()` and measure the tail
window of the hold (the first wakes just finish a slump sleep froze mid-way). **A rope
built with `VerletRope.new()` takes the C++ defaults**, which are softer than anything
that ships — these mirror `cable.tscn` (8 iterations, `collision_radius` 0.0045,
self-collision on) or every threshold describes a cord the room does not contain.
**Never initialise a cord in a state no hand can produce**: a straight lay from a
table-top socket to a floor socket passes through the slab and wedges particles 11 mm
inside it (a particle born inside a solid has no contact plane), and a lay pre-compressed
between close sockets buckles into a 318 mm standing arch and sleeps there — the cases
lay the cord clear and `_carry()` the end to its socket the way a hand does. And **a
long free-hanging span cannot be held awake at all**: `wake()` every tick feeds the edge
contact's chatter into the span's pendulum mode and pumps a 0.4 m swing the room cannot
reach, because the sleep system cuts that loop off — the corner case asserts what the
room actually does (brushed awake once, asleep again in 30 ticks, 8 mm of drift).
Everything else measures 0.0003–0.07 mm/tick held awake, heaps included.

`RetroXR/Tests/romm_tests.tscn` asserts the pure-logic half of the RomM stack — pair-QR
parsing, slug mapping and systemid collision, the sync fingerprint, cache path safety,
and the `scan_roms` disk walk. 312 cases, ~17 s, no server, no headset, no network.
```bash
"$godot" --headless --path RetroXR res://Tests/romm_tests.tscn 2>&1 | grep -a "\[test\]"
```
Every case in it is a bug that actually shipped, so it doubles as the regression record —
add to it when you fix something in that layer rather than starting a new probe. It uses a
scratch `__romm_selftest` system folder under the real roms root (the path is derived from
the systemid and cannot be pointed elsewhere) and removes it at both ends.

`RetroXR/Tests/scene_tests.tscn` covers SceneManager and the save gates around it — which
rooms keep slots, the per-room active slot and its prefs round-trip (including the legacy
single-room key), which room a launch opens in, the `is_room_ready` / `is_scene_content_ready` boundaries, the transition
state machine's coalescing, the periodic autosave, clearing and reloading the room you are
standing in, two restores racing into one room, a machine's core outliving its machine, the room's own
movable furniture, the video decks' teardown contract, and slot-manifest CRUD.
120 cases, ~10 s.
```bash
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn
"$godot" --headless --path RetroXR res://Tests/scene_tests.tscn -- --only=autosave
```
It deliberately does **not** drive a real transition: `change_scene()` loads MainScene.tscn,
whose SubViewports render every frame, and a headless run has no GPU to service them — that
hangs rather than fails (see the SubViewport gotcha below). The cases drive `_transitioning`
and `_pending_scene_id` directly and assert the decisions made from them.

Two traps it hit that the next case will hit too. A spawned system also registers its
captive cable in the `"spawned"` group, so the group is always bigger than the entry list —
measure a baseline rather than hardcoding a count. And tear a group's room down with
`clear_scene()`, not by freeing the systems: freeing only those leaves the cables standing
in the next group's room.

It writes to the player's real `user://scenes` — the slot dir is derived from the room id
and cannot be pointed elsewhere — so it snapshots `prefs.json`, the arcade manifest and the
active slots up front and restores them byte-for-byte at the end. Restoring the manifest
matters beyond deleting the test's own entry: any rewrite round-trips it through JSON, which
turns its version int into `1.0`.

`RetroXR/Tests/poster_tests.tscn` covers the posters feature — the image load and the
sheet it sizes (alpha scissor vs opaque, mipmaps, aspect, per-instance sub-resources),
sticking to a surface on release, riding the object it stuck to, peeling, conforming to
a curved shell, the options-menu contract, and the save/restore round trip. 112 cases, ~11 s.
```bash
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn
"$godot" --headless --path RetroXR res://Tests/poster_tests.tscn -- --only=conform
```
Physics runs fine headless — the dummy renderer stubs RENDERING, not Jolt — so the stick
and conform cases are real raycasts against real bodies. It writes its own PNG into the
player's posters folder (`scan_posters` derives that path) and removes it at both ends.

Two traps worth knowing before adding a case. A stuck poster is REPARENTED under its
host, so anything that walks the host's meshes sees the poster's own sheet — that is what
made the first conform sample every interior ray at depth zero. And a poster is placed by
RAY as often as by hand, where `dropped` never fires; a release has to be detected from
`freeze`, so a test that only simulates a hand grab proves nothing about the real gesture.

`RetroXR/Tests/binding_tests.tscn` covers the resolution rules behind per-platform
control overrides. Both stores — `ControllerBindings` (VR controllers) and
`GamepadBindings` (a real pad) — merge default → global → per-system, and a platform's
stored profile IS its override switch; there is no separate flag. So three rules are
load-bearing and each has cases here: a platform with no profile is indistinguishable
from global, a profile shadows global completely INCLUDING global edits made after it
(which is why a profile is always written whole), and clearing one puts that platform
back on global without touching anyone else's. DesktopBindings is the odd one
and has its own cases: its consumers all read the process-global InputMap, so a
platform's keys cannot be looked up per system — they are APPLIED, and the Scroll
Lock capture decides when (RetroController._sync_desktop_scope). Its legacy flat
file is read as the global layer, which is covered too, because losing it would
wipe every desktop player's key map on first launch. It also covers ConsolePadArt, the
table a platform's own controller is drawn from — that a control key's index in
GamepadBindings.TARGET_ORDER really is its RetroPad bit (the trick that lets one
table serve both the XR and the physical-pad sections), and that every control
has an anchor and a row. 176 cases, ~12 s.
```bash
"$godot" --headless --path RetroXR res://Tests/binding_tests.tscn
```
It writes the player's real `user://controller_bindings.json` and
`user://gamepad_bindings.json` — the paths are consts on the two classes and cannot be
pointed elsewhere — so both are snapshotted up front and restored at the end.

`RetroXR/Tests/object_sync_tests.tscn` covers the shared-room network layer with
two and three real in-process ENet peers: initial and replacement snapshots,
host/client spawning and despawning, rigid-body transform flow, grab arbitration,
release velocities, disconnect cleanup, event relay, plain + spring-latched
hinge mechanics (including push-push trays), knobs, plain + spring-return
sliders, levers, and remote head/hand avatars. Momentary button depression is
deliberately not replicated;
the semantic action it triggers is. The event cases cover platform power/reset,
tray/eject and media insertion, every TV bezel/remote action (power, volume,
mute, CRT, stereo/audio modes, aspect, source and channel), deck transports,
cables/ports, book controls, wall and pull-chain lights, blinds and time of day.
Late-join snapshots also carry the TV control state and those fixed room controls,
not only spawned objects. Articulated updates are capped at 64 per reliable
packet, with overflow retained for following packets rather than discarded. It
has no ROM, headset or display dependency.
Each group is independently runnable.
```bash
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn
"$godot" --headless --path RetroXR res://Tests/object_sync_tests.tscn -- --only=hinges
```

That a binding reaches a RUNNING core is deliberately not here: it needs a real system,
a real controller and the `binding_consumers` fan-out, and lives in
`Tools/input/binding_live_probe.tscn`. Drive that probe through the view's OWN
`_global_editor` rather than a fresh `ControlsBindingEditor` — a detached editor writes
to disk and reaches nobody, so every "applies immediately" case fails for a reason the
player never sees.

**For anything visual, a photo (or a VIDEO if it's animated — mp4 preferred over
animated GIF) is the preferred proof of validation, delivered inline in the chat.**
Headless runs catch parse/scene/shader errors but cannot confirm how something *looks*
(glyphs, layout, colors, animation). When a change is visual, capture a screenshot or
short recording and surface it inline — don't just report that the headless import
passed. To encode mp4 from probe PNG frames: `imageio` + `imageio-ffmpeg` are pip-installed
(`imageio.get_writer("out.mp4", fps=15, codec="libx264", pixelformat="yuv420p")`).

Godot binary (Windows) — use **Godot 4.7.2** (the project targets 4.7):
```
C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
```
**The doubled name is real** — the 4.7.2 download unpacked into a FOLDER called
`Godot_v4.7.2-stable_win64.exe` holding the exe and its `_console.exe`. The old
`Godot_v4.7-stable_win64\` folder is still installed beside it and is NOT the one to
use: `android/build` is stamped 4.7.2 (`android/.build_version`), so a 4.7 binary
fails every Quest export with `Android build version mismatch: Template installed:
4.7.2.stable / Requested version: 4.7.stable` — and that error names the template,
not the editor, so it reads as a broken template rather than the wrong exe.
Use the `_console.exe` variant so stdout/stderr is captured. `$proj` below is the
`RetroXR/` folder inside your checkout.

Godot binary (Linux): `~/Godot/Godot_v4.7.2-stable_linux.x86_64`
(the project targets Godot 4.7 — see `project.godot config/features`; `Godot_v4.6.3` also
sits in that dir). `$proj` on Linux is `<checkout>/RetroXR`. Note Godot
4.7 promoted "Not all code paths return a value" to a hard parse error for `Variant`-returning
virtual overrides (bit two `_property_get_revert` overrides in godot-xr-tools — fixed with a
trailing `return null`).

### 1. Compile / import check (catches parse, shader & scene-load errors)
```bash
"$godot" --headless --path "$proj" --editor --quit
```
This reimports resources, recompiles every GDScript, compiles shaders, and (critically)
**regenerates the global `class_name` cache**. Run it after adding or renaming any
`class_name`, or a probe that references the new class will fail with
`Could not find type "X" in the current scope`. Filter output for
`SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load|Failed to instantiate`.

### 2. Functional probe (exercises real code paths)
Write a tiny `probe.gd` (`extends Node`) + `probe.tscn`, run it, print `[probe] ...`
lines, then `get_tree().quit(0)`:
```bash
"$godot" --headless --path "$proj" res://probe.tscn 2>&1 | grep -a "\[probe\]"
```
Always **delete the probe `.gd`/`.tscn` (and generated `.uid`/`.import`) when done.**
Include a `get_tree().create_timer(5.0).timeout.connect(...quit)` safety net so a probe
can never hang the run.

### Gotchas
- **Warnings are treated as errors** for some warnings — notably inferring a `:=`
  variable from a `Variant` (e.g. `var x := ClassDB.instantiate(...)`). Use an explicit
  type (`var x: Object = ...`). `unsafe_method_access` (calling a method not on the
  static type, i.e. duck typing) is **not** an error, so it's fine.
- **A `SubViewport` with `render_target_update_mode = ALWAYS` hangs a headless run**
  (no GPU to service the render target). It renders fine in a real session — just don't
  drive extra `await process_frame`s over such a viewport in a headless probe; test the
  logic/wiring instead and eyeball the visual on-device.
- **Known headless noise to filter out** (pre-existing, not your change): OpenXR
  `xrCreateInstance failed`, missing GDExtension DLLs in the `template_debug` path
  (`libgodotopenxrvendors`, `godot-pdfium`, `libretro_godot`), `.NET Sdk not found`, and
  `xr_staging_shim.gd ... is_xr_class ... placeholder instance`. Grep these out.
- **A renamed/deleted source texture can leave the editor filesystem cache
  pointing at a dead `.godot/imported/*.ctex`.** Re-running an ordinary import
  may keep trusting that stale entry. Move/delete
  `RetroXR/.godot/editor/filesystem_cache*`, then run `--editor --import --quit`;
  Godot rebuilds the class cache and replacement texture imports. This is
  generated local state, not a file to commit.
- **A `.tscn` `Transform3D` lists the basis by ROWS**, not the columns the
  `Transform3D(x_axis, y_axis, z_axis, origin)` constructor takes. For a rotation the
  two differ by a transpose — an inverse — so a hand-written rotation comes out
  backwards. Copyable forms: `R_y(+90)`, local +Z → world +X, is
  `0, 0, 1, 0, 1, 0, -1, 0, 0`; `R_y(-90)` is `0, 0, -1, 0, 1, 0, 1, 0, 0`;
  `R_x(-90)` is `1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08`. **Never check one
  against a 180° or an otherwise symmetric matrix** — those read the same under both
  conventions and confirm whichever reading you already had, which is how the Wii
  ports and then the Game Boy link socket were both authored inside out. Print
  `node.transform.basis.x/.y/.z` from a throwaway probe and compare it with what you
  meant, before rendering anything.
- **PowerShell buffers `& $godot ... | Out-String` until the process exits**, so a
  backgrounded run shows an empty output file until it finishes. The Bash tool with
  `timeout 90 "$godot" ... 2>&1 | grep` streams and bounds the run — prefer it.

### Verify with a check that can fail

**A green check that cannot tell the two outcomes apart is not a check.** Ask what
the WRONG version would look like before believing the right one; if the answer is
"the same", that is not the check to use.

Two of them in a row cost the Game Boy link socket a whole round trip. It was
authored facing INTO the shell, and the render looked identical because a
rectangular port recess is symmetric, while the room probe passed either way because
a snap zone does not care which way round a plug goes in. Both were green and
neither could have gone red. What settles a facing is a printed basis, or a render
of something ASYMMETRIC — a seated lead, not an empty socket.

**And read the note before authoring, not after the bug.** The gotchas above and the
session memory are each one line in an index, which is enough to recognise a topic
and not enough to act on; acting from the summary is how the same mistake arrives a
second time. `.tscn` transforms, a model's facing and a port's seat all have notes,
and all three were sitting in the index while that socket was written backwards.

`libretro-godot/tests/run_tests.py` is the small Godot-free C++ harness for the
link coordinator and sensor-id encoding.

**`RetroXR/Tests/archive_tests.tscn` is the one GDExtension with a self-checking
suite**, because `RommArchiveExtractor` is the one that needs no display, codec,
core or server. 83 checks over a well-formed archive, the plan validation, a
damaged/truncated/non-ZIP/missing one, cancellation, `FirmwareInstaller`'s unpack of
a support archive (`firmware/`) and of a speech pack's remapped parts (`pack/`); every
fixture is built under `user://` at run time, so it carries no binary.

Two of its cases are hand-built STORED archives, and that is not fussiness.
**For a DEFLATED member the declared CRC is handed to `StreamPeerGZIP` as a gzip
trailer**, so a corrupt payload dies inside decompression and
`RommArchiveExtractor`'s own `crc != entry.crc32` comparison is never reached — a
"bad CRC" case built by flipping payload bytes passes with that check compiled
out. Only a STORED member isolates it. `ZIPPacker` always deflates, hence the
hand-rolled fixture.

The other four extensions stay probes and rebuild-plus-load: `verlet-rope` has
the bit-exact oracles in `Tools/rope/`, and `vlc-godot`, `godot-pdfium` and
`metaxr-audio` all need a display, a codec or Meta's blob. Adding a suite for
one of those would mean a red run that depends on the machine it ran on.

### 2b. The bedroom's saved visual probe

`RetroXR/Tools/models/bedroom_probe.tscn` — do NOT hand-roll another one. It carries the
still framings for that room (overview, bed, desk, window, TV corner, bookcases,
wardrobe, light switch) plus a flythrough: 360 deg in place at the room centre,
then a lap walking forward round a circle sized to clear the furniture.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20     res://Tools/models/bedroom_probe.tscn -- --mode=stills      # or flythrough, both
```

Windowed, not `--headless` — the dummy renderer returns a blank image. PNGs land
in `res://probe_out/` (gitignored). Encode a flythrough at 24 fps with imageio and
**pass `-crf 24`**: the default quality puts an 11 s clip at 21 MB, CRF 24 at 2 MB
with no visible difference.

It forces the ceiling-light energy to 0.6 on purpose. The scene authors 1.2 and
`QualityManager._adjust_lights` has not run that early, so a naive probe renders
the room brighter than any player sees it.

**Overwriting a texture in place needs a reimport.** A game run keeps serving the
cached `.ctex`, so two successive recolours of the bed's atlas appeared to do
nothing at all. Run `--editor --quit` between the overwrite and the render.

### 2c. The A/V suite — the one thing here that is an actual test suite

`RetroXR/Tests/av_tests.tscn` — 41 cases over what reaches a television's inputs and
what it shows. Headless, ~35 s, **exits non-zero on failure**, so it is the one probe
that can be run as a gate rather than read.

```bash
"$godot" --headless --path RetroXR res://Tests/av_tests.tscn
"$godot" --headless --path RetroXR res://Tests/av_tests.tscn -- --only=display
```

Groups: `routing/` (real TV + VCR + composite leads — cords into the wrong sockets, a
crossed pair, two leads on one deck, a cord pulled), `display/` (which input is shown,
what a blank input paints, a source that stops, a set switched off, snow on an
untuned aerial channel, a VGA monitor with no phono row, a source's own shader
stage, two sets sharing one machine), `guard/` (`can_paint` / `paint_screen` /
`release_screen`) and `audio/` (only the selected input is heard; a machine wired to
nothing is silent). Every case is a bug that shipped at least once.

Three things it took to make routing cases behave, all of them real behaviour rather
than test scaffolding:
- **Pulling a plug needs the whole panel shut.** Dropping one leaves it standing in a
  60 mm grab zone with four video sockets 18 mm apart around it, and the log reads
  `pulled VIDEO on TV` immediately followed by `seated VIDEO on TV`. `_unplug()` shuts
  every RcaPort in the room for the move.
- **And the plug frozen.** A live one falls back down past the panel and is caught by a
  socket on the way, ending up a perfectly good picture cord in the wrong input.
- **The phosphor accumulator hides the source.** With persistence on, the CRT material's
  `source_tex` is the ping-pong buffer, so the oracle is the set's own `_crt_source_tex`.

It is mutation-tested: reverting the deck to reading one cable, disabling the paint
guard, or restoring the frozen-frame bug each fails exactly the cases that name them.
Adding a case that cannot fail is worse than no case, so break the code and watch it go
red before believing a new one.

### 2d. The BIOS-boot survey — a probe that must stay one core per process

`RetroXR/Tools/cores/bios_boot_probe.tscn` + `Tools/bios_boot_survey.sh` are the provenance
of the `BiosBoot` table, and the only way to refresh it when a core is updated. The
probe reports one core's firmware status, its boot-ROM-ish option keys, and whether it
will start with no content; the survey drives every candidate and prints a table.

```bash
Tools/bios_boot_survey.sh                # every candidate
Tools/bios_boot_survey.sh mgba flycast   # just these
```

**Never loop cores inside one Godot process.** Starting a core with a game info it did
not expect runs code its author may never have exercised, and the extension is built
`-fno-exceptions` with no sandbox: of sixteen cores surveyed 2026-08-20, **six killed the
process** — mgba and parallel_n64 dereference a null `retro_game_info`, and
mednafen_saturn, neocd, dolphin and same_cdi die on a zeroed one. One process per attempt
is what makes a casualty cost one table row instead of the run.

Two things the survey settled that are easy to re-derive wrongly:

- **`supports_no_game` in the `.info` is useless here** — all sixteen candidates declare
  it `false`, yet flycast, pcsx2 (LRPS2) and the Dolphin fork's `retroxr` branch start
  with no content and draw their BIOS menus (measured 2026-09-15). Dolphin's core option
  `dolphin_gc_bios_region` picks which GameCube IPL: `auto` boots the first installed,
  USA then EUR then JAP. Upstream libretro Dolphin cannot start empty at all. The flag is not consulted anywhere; the table records what
  was measured. The installed pcee2 is refused before it is asked, because it does not
  declare `SET_SUPPORT_NO_GAME` to the bridge.
- **The usual mechanism is empty MEDIA, not an empty path.** Only pcsx_rearmed accepts a
  zero-byte image, and it gives the real PS1 BIOS. flycast (gdi/cdi/chd),
  mednafen_saturn, mednafen_pce and neocd all refuse one. mednafen_saturn takes a cue
  over one silent audio track instead (`BiosBoot` `empty_media_track`), which lands in
  the Saturn's CD player; a blank data track gets "Disc unsuitable for this system".

A disc console boots what its drive would read: the disc under a SHUT lid. An open lid,
or a disc taken out while the game ran, boots the BIOS where the table says the core can,
and otherwise refuses with "Lid open" / "No game inserted". Shutting a disc into a BIOS
run restarts the machine on it rather than swapping it in: measured 2026-09-15, neither
pcsx_rearmed's nor mednafen_saturn's BIOS boots a disc swapped in under it (20 s later,
still "Please insert PlayStation CD-ROM" / the CD player), and a core started with no
content has no disc list at all — flycast indexes that empty list when its tray shuts —
so those runs send the core no tray ops.

It **writes the player's real `core_options/`** — a core serialises its whole option set
on shutdown, and a crashed run can leave a key moved (a crashed mgba run flipped
`mgba_skip_bios` to `ON`). The survey snapshots the directory up front and restores it on
exit, including on failure. A probe run by hand does not, so restore by hand or re-run the
survey afterwards.

### 2e. The Game Boy link probes — three layers, two cores, two clocks

`RetroXR/Tools/link/gb_link_probe.tscn` drives the bus directly, `gb_link_room_probe.tscn`
drives the path a player uses (pick a lead up, push a plug into a socket), and
`gb_tetris_link_probe.tscn` runs a commercial two-player game over the result.
Probes rather than tests: they want a real core and, for Tetris, a real ROM.

```bash
"$godot" --headless --path RetroXR res://Tools/link/gb_link_probe.tscn -- --core=mgba
"$godot" --headless --path RetroXR res://Tools/link/gb_link_room_probe.tscn
"$godot" --headless --path RetroXR res://Tools/link/gb_tetris_link_probe.tscn -- --roms=Z:/roms --core=gambatte --core2=mgba
```

**Both cores, and between them.** gambatte and mGBA each carry a Game Boy, both
answer `RETRO_ENVIRONMENT_GET_LINK_INTERFACE`, and both call the wire `gb-sio-1`
with the same message layout -- so a gambatte Game Boy and an mGBA one join the
same cable, which `--core2` is there to prove. mGBA needs its GB driver as well
as its GBA one: they are separate cores with separate serial ports, and before
`gb_sio_netlink.c` a lead between two mGBA Game Boys carried nothing, silently.

The ROMs the first two run come from `Tools/gen_gblink_rom.py` and swap a known
byte for ever, painting the screen white while the byte coming back is right. No
assertion is made against an absolute shade -- a core picks a palette per game --
only that a cabled screen is neither of the two an uncabled pair shows. The
`_fast` pair is the same exchange at the Game Boy Color's 262144 Hz clock, a
transfer of 128 cycles against 4096, which is the one path a Game Boy cannot
reach: SC bit 1 reads back as one on a DMG whatever is written.

**Drive the two machines one at a time.** Tetris settles which unit owns the
clock by having both send 0x29 until one is listening when the other calls, so
two machines driven on the same emulated frame both call and neither listens --
the trace reads as two masters clocking the same tick for ever, each getting the
0xFF of a cable nobody is holding. Real hardware cannot stay there because two
people are never frame-perfect; a script can, and will. The same probe also
presses START and then LOOKS, because in Tetris that button picks a game type,
confirms a level, starts the match AND pauses it, and the pause travels down the
wire.

**Tetris DX is not a usable target.** Its 1PLAYER and 2PLAYER entries are greyed
out until a profile exists, so each machine needs a scripted name entry through
an on-screen keyboard first, and the two routes drift apart. The Game Boy Color
path is covered by the `_fast` ROMs instead.

### 2f. Netplay — a suite, and the one thing it cannot cover

`RetroXR/Tests/netplay_tests.tscn` is 685 cases over the whole lockstep stack,
headless, ~32 s, exits non-zero. Groups: `cores/` (the determinism allowlist),
`identity/` (which core builds may play each other), `wire/` (every packed
block's round trip, including per-port accelerometer, gyro, IR/touch and
lightgun state), `owners/` (who supplies which port on which frame),
`assemble/` (frame completion and pruning), `start/` (the asynchronous cold
start), `lockstep/`, `desync/`, `join/`, `leave/`, `rollback/`, `link/` (a
cabled pair as one session).

```bash
"$godot" --headless --path RetroXR res://Tests/netplay_tests.tscn
"$godot" --headless --path RetroXR res://Tests/netplay_tests.tscn -- --only=start
```

**It runs two — for the join cases, three — complete NetworkManagers in ONE
process**, each under its own `SceneMultiplayer`, over real loopback ENet. Do
not reach for two OS processes instead: the RPCs, channels, serialization and
handshake are already the real ones, and one process keeps the run deterministic
and headless. It replaced `Tools/netplay_session_probe.tscn`, which was the same
idea at a quarter of the coverage.

Godot 4.7 currently prints a fixed `ObjectDB` shutdown warning after these
in-process branch-ENet suites (`18 RefCounted` objects in the ordinary netplay
run). It is the engine's RPC cache interaction with the project's NetworkManager
autoload, not an accumulating session leak: one pair and many sequential pairs
leave the same fixed count, a raw ENet pair in this project reproduces it, and
the same raw pair in a minimal project without the autoload is clean. Removing
the autoload before connecting suppresses the warning but leaves Godot with a
dangling autoload singleton and eventually crashes the full suite, so do not
hide it that way. The passing case count and exit status remain the gate.

What no suite here can cover is a real core's arithmetic. That is
`Tools/netplay/netplay_spike.gd`, and it now has a **cross-machine leg**, which is the
only thing that tests the one payload lockstep actually puts on the wire — a
savestate, shipped for a late join or a desync resync:

```bash
machine 1:  ... res://Tools/netplay/netplay_spike.tscn -- --spike-state-out=Z:/np.bin
machine 2:  ... res://Tools/netplay/netplay_spike.tscn -- --spike-state-in=Z:/np.bin
```

Machine 1 writes its state, the frame, its core identity and its whole phase-A
CRC table; machine 2 loads that state into ITS core and replays the same input
timeline against machine 1's CRCs. Run it x86_64 → arm64 and back. Cold-start
CRC determinism was verified across those two in 2026-07-06; a foreign savestate
crossing between them was not, and a libretro state is a struct dump for most
cores.

**ROM/device validation still owed:** the automated suite proves that lightgun,
accelerometer, gyroscope and multi-point IR/touch values survive the network,
reach the native input handler and keep their sub-device index. It does not prove
that a real content core consumes those values correctly. In particular, Wii
Remote accel/gyro/IR through Dolphin and a real lightgun title still need a ROM,
the matching core and preferably the real controller. The user does not plan to
obtain a ROM, so leave this as an explicit unverified hardware/content check; do
not represent the mock/no-ROM suite as that proof.

**Cross-platform play is a build-identity problem before it is a determinism
problem.** `core_download_manager.gd` points every platform at
`nightly/<platform>/latest/`, so five separate builds are in play (win-x64,
linux-x64, android-arm64, osx-arm64, osx-x64) cut at five different times from
five different commits. Two Windows players who downloaded the same day are
byte-identical; a Windows player and a Quest player essentially never are. The
core FILE can therefore never be compared — what is compared is
`Libretro.GetCoreIdentity()`, which the C++ publishes from the emulation thread
once `retro_load_game` succeeds: `library_name`, `library_version`,
`api_version`, `serialize_size`. fceumm puts its git hash in the version
(`FCEUmm (SVN) 5cd4a43`), so nightly skew really is visible there.

That dictionary is **empty until content has loaded and empty again after it
stops**, which makes it the readiness test as well as the identity. That matters
more than it sounds: `StartContent` spins the emulation thread and returns, so a
core that is missing, refused or wedged fails ASYNCHRONOUSLY — a real fceumm
took **34 frames** to come up in a probe here. Reporting a peer ready before
then is reporting a peer with no core.

**The identity is published in two halves, at the two moments each half is safe
at, and both constraints are load-bearing:**

- `library_name`/`library_version`/`api_version` land **at load**. They were
  read from `retro_get_system_info` during `Core::Load` and cost no call into
  the core, so they are safe everywhere.
- `serialize_size` lands **after the first `retro_run`**, and is 0 until then.
  Dolphin answers `retro_serialize_size` by marshalling onto its CPU thread and
  walking every subsystem, so asking at load segfaults it on a machine that does
  not exist yet — and because the publish sat on the unconditional load path,
  that broke every Dolphin boot, not just netplay.

It cannot simply move to after the first frame either: **the netplay gate does
not run frame 0 until every peer reports ready, and readiness is this dictionary
being non-empty.** Requiring a frame deadlocks every cold start — measured, the
identity never arrived in 2888 ticks — and the symptom is a 10 s timeout saying
"core did not come up". So a reader comparing sizes across peers must treat 0 as
"not measured yet" rather than as a difference; at cold start both peers are
usually 0 and the version comparison carries the weight.

`RetroXR/Tools/netplay/core_identity_probe.tscn` is the guard for all of that, and it
needs a real core so it stays a probe. It runs the same core twice, gated (a
netplay cold start: identity must arrive with ZERO frames run) and ungated (the
size must really get measured), and exits non-zero.

```bash
"$godot" --headless --path RetroXR res://Tools/netplay/core_identity_probe.tscn -- \
  --ident-core=fceumm "--ident-rom=$HOME/retroxr/roms/nes/rom.nes"
```

**Run it against dolphin, not just a quick NES core** — fceumm cannot fail the
half that matters. And give Dolphin `--ident-leg=gated` and `--ident-leg=ungated`
in separate processes: both legs in one run means a restart, Dolphin is one of
the cores that will not unwind, and the abandoned thread segfaults on the way
out looking exactly like an identity crash.

### 2g. Netplay over a link cable — one session, two machines

**A link cable never crosses the network.** `LinkCoordinator` is a process-wide
singleton joining two cores in the SAME process, so under netplay every peer
replicates BOTH machines and it is determinism, not a wire, that keeps the two
buses agreeing. A cabled pair is therefore ONE session over TWO machines, which
is why `NetplaySession` holds a `_group` rather than a system.

Ports are named `machine * PORTS_PER_MACHINE + port`, so both machines' pads fit
in one assembled frame; each core is handed only its own 20-int block plus that
machine's aux and key blocks. Aux (tilt, touch) and keyboard ride with each
machine's own port-0 owner — copying the anchor's tilt into every linked handheld
is just as wrong as dropping the far handheld's input. A linked late join pauses
every local core at one boundary and transfers both core savestates plus
`LinkCoordinator`'s clock horizons and queued messages. The joiner restores the
physical bus first, then its external bus snapshot, then the core states, so it
cannot resume half of an in-flight serial conversation.

The per-machine launch spec also records `rom`, `empty_media`, or `no_content`.
That last mode is the cartridge-less GBA in single-pak play: it cold-boots mGBA
with the BIOS only, then an ordinary core savestate carries the downloaded
program, RAM, registers and link state just like a cartridge-backed machine.
Empty-disc BIOS menus use `empty_media` instead and regenerate the zero-byte
image locally; BIOS files themselves are never transferred. Every peer must
already have matching firmware. The no-ROM tests cover this launch/state
plumbing with mock cores. mGBA IS now in `NetplayCores` (verified, with
ROLLBACK/LOCKSTEP/DETERMINISM), so the core is no longer the blocker it once
was — but a real single-pak netplay run still needs a payload-carrying game ROM,
which the user does not plan to obtain. Leave THAT validation noted as
outstanding; do not read mGBA's presence in the table as proof single-pak play
was exercised end to end.

Late-join state is a bounded stream, not one RPC: 64 KiB reliable chunks, eight
in flight, cumulative acknowledgements, SHA-256 per payload, and a 256 MiB total
cap. The metadata is a chunked payload too, because it contains SRAM and the
external link-bus queues. Capture, transfer, core startup and state load all have
progress deadlines; a timeout tears the newcomer down, makes it a spectator and
releases the existing players. Firmware matching hashes every path declared by
the core (including directory contents), not only the files used to draw a BIOS
screen.

Two things this had to get right, and both are the same rule:

- **Every machine on every connected wire is in the session.** When it held one, the far end
  was ungated on the host and not running at all on a client, so the client's
  gated core sat on a bus whose other end never published — and the coordinator
  waits for a peer that is behind rather than guessing, with deliberately no
  timeout. Host fine, client wedged. A console can have several independent
  leads (four GameCube-to-GBA cables are the obvious case), so the group is the
  transitive merge of every cable bus touching the anchor, not the first match.
- **All THREE leads, not just the handheld one.** Every lead that can put two
  cores on a wire answers `linked_machines()` / `held_machines()`, and a machine
  finds its bus by asking the leads rather than searching its own sockets. That
  is not tidiness: a GameCube-to-GBA lead puts its wide end in a **controller**
  socket, so there is no `LinkPort` on the console side to walk out of, and a
  search from the machine would have decided a cabled GameCube was on no bus at
  all. `net_link_bus` therefore sweeps both the `link_plug` and `controller_plug`
  groups. (That the GC end is in `controller_plug` and not `link_plug` is pinned
  by `link_tests`; the same suite seats both ends through their real socket APIs
  and verifies that `net_link_bus` discovers the console through
  `controller_plug`.)
- **A plug seated mid-game lands on ONE agreed frame.** `LinkCoordinator.hpp`
  says so itself: the thing it cannot enforce is that Connect and Disconnect
  happen on the same emulated frame on every peer, and that is the caller's job.
  Nothing was doing it. The host now waits for every peer to acknowledge the
  reliable topology command, then holds the boundary until every local core has
  finished the preceding frame; only then does it change the bus and release
  that frame to any core. `link_cable._resolve` hands the decision to the host
  instead of joining on the spot whenever a hand moves.

`RetroXR/Tools/netplay/netplay_link_probe.tscn` is the real-core half — two gambatte
Game Boys, the real bus, ROMs from `Tools/gen_gblink_rom.py`:

```bash
python Tools/gen_gblink_rom.py     # once, into RetroXR/Tools/gblink/
"$godot" --headless --path RetroXR res://Tools/netplay/netplay_link_probe.tscn
```

Its two legs pull opposite ways and both must hold. Fed on both machines, the
pair runs and trades bytes (240 frames, 293/431 messages). Fed on only the near
one — a client before the group existed — **the near core reaches frame 2 and
stops dead.** That second leg is the reproduction, and a green there would mean
the bus had stopped waiting, which is worse than the hang: a cabled netplay pair
would desync instead of stalling.

`RetroXR/Tools/link/gc_gba_link_probe.tscn` is the same thing for the ASYMMETRIC
lead, which had been reasoned about and unit-tested and never once run with the
cores that actually speak the JOY bus. It wants Dolphin, mGBA and two commercial
ROMs, so it is a probe. It reproduces what `GcGbaCable` does on seating, in
order: `SetControllerPortDevice(port, (7 << 8) | 0)` then
`LinkConnect(gba, console_port, GBA_JOY_PORT)`.

```bash
"$godot" --headless --path RetroXR res://Tools/link/gc_gba_link_probe.tscn
"$godot" --headless --path RetroXR res://Tools/link/gc_gba_link_probe.tscn -- --gba-empty
```

First run, 2026-08-21, Four Swords Adventures against Super Mario Advance:
Dolphin attaches `gba-joy-1` at 486 MHz, mGBA at 16777216 Hz, `bus 0 [P1 on,
P2 on]`, peers 2/2, and **6247/6248 messages** over 1574 frames with both cores
in step. So the console-port end of the lead works with real cores.

**`--gba-empty` is the pairing the game actually wants**, and the difference is
stark: with no cartridge in the handheld the same run trades **82407/82408**
messages, thirteen times as many. Four Swords Adventures uses the GBA as a
screen and pad and uploads its own program over the wire, so a handheld holding
its own commercial cartridge is a legitimate cabling but not a conversation
either title was written for. Do not read a low byte count in the cartridge case
as a fault.

**The bus is cheap, and the teardown cost report does not say otherwise.**
Measured with `--no-cable`, which boots both cores side by side and never joins
them: uncabled **57.1 / 57.3 fps**, cabled **54.8 / 54.6 fps** over the same
28.4 s. About 4%. The report's "22368 ms blocked" over a 28.4 s run looks
alarming and is not lost time — the two cores are on separate threads, so one
blocking IS the other one working. Read the fps, not the blocked total.

What the report is good for is STALLS, and there is one real artifact: a single
~1 s hitch early on (967 ms on the console at 1034 ms in, 1197 ms on the
handheld at 2394 ms in), with only 1 and 6 further events over 20 ms in the
whole run. It lands during the program upload and does not recur. On a desktop
that is a hitch; in a headset it would be felt once, and it is the one number
worth watching if this ever reaches a Quest.

Both cores are now in `NetplayCores` (they were not when this section was first
written): `mgba` is `verified` with ROLLBACK/LOCKSTEP/DETERMINISM, `dolphin` is
`verified: false`, `state_transfer: false`, DETERMINISM only. So a session over
this pair can now be started — but note what the probes above do and do not
prove: they exercise the BUS with real cores, not a netplay session over it.
Dolphin having no transferable state is why it is DETERMINISM-only, which in
turn means no late join and no desync repair.

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

### 2k. PlayStation 2 memory cards — a filesystem, and two cores that own it

The `playstation2` card family, added 2026-09-09. Every other family here is a
flat table; the PS2's card is a real filesystem — a superblock, a doubly-indirect
FAT, and 512-byte directory entries two to a 1024-byte cluster, with 16 bytes of
ECC in every page's spare area (528 raw, 512 to the filesystem). Each save is a
DIRECTORY at the root, so a save's name is a folder name and its size is what its
whole subtree occupies. `PS2Card` is correspondingly larger than its siblings.

**Where the format came from, since none of it can be trusted on paper.** Upstream
PCSX2's `pcsx2/SIO/Memcard/MemoryCardFolder.cpp` synthesises a card image from a
host directory, which makes it a WRITING reference and not only a reading one —
geometry, FAT construction, directory layout and the ECC table are transliterated
from it. **PCSX2 has no formatter**: it creates a card as 8,650,752 bytes of 0xFF
and leaves the BIOS to format it, so `blank_image()` had to be written from the
Ross Ridge specification PCSX2 vendors alongside the code.

**The specification is wrong about `card_flags`**, and four fills with it. Measured
against a real 44-save PCSX2 card backup: `card_flags` is **0x2B**
(`CF_USE_ECC | CF_BAD_BLOCK`), not the 0x52 the spec calls the default — a value
with `CF_USE_ECC` clear, on a card whose every page carries ECC. Also measured:
an unused indirect-FAT slot is **0** while an unused bad-block slot is
**0xFFFFFFFF** (the two 32-entry lists are adjacent and filled differently), the
superblock page is zeroed past `card_flags` rather than 0xFF-filled, and a page's
spare area ends in four NULs rather than 0xFF.

**The check that settles all of it is one assertion.** A formatted card's
superblock never changes as saves come and go, so a blank card's first raw page
must equal the same page of ANY console-formatted card. It does, byte for byte,
and `card_tests` pins the SHA-256 (`5cf22726…`). That one case covers magic,
version, card_type, card_flags, every geometry field, both fill conventions and
the ECC algorithm together. The card itself is not committed — 8 MB of somebody
else's saves — so the digest stands in for it.

Four things a reading of the spec alone gets wrong, all with cases:

- A directory's `length` is a **SLOT count**, including `.`, `..` and every DEAD
  slot. It is a capacity, never a file count, and the append path decides where
  the next entry goes from `length % 2`.
- The root's `..` is **0xA426** — it drops `MODE_READ` and carries 0x2000, unlike
  every subdirectory's. Confirmed on the real card, not just in PCSX2.
- "Deleted" and "erased" are different tests: `mode != 0xFFFFFFFF` is valid,
  `mode & 0x8000` is used. A deleted file is valid-but-unused.
- Usable clusters are truncated to `(alloc_end/1000)*1000 - 1` = **7999**, not
  the 8135 the superblock allows, to match what the console reports. `total_blocks`
  is 7998 of those, because the root directory always holds one and a save can
  never have it — the same reason the PlayStation's card excludes its directory
  block.

**Icons are 3-D models**, not sprites: `icon.sys` names the save and three `.icn`
files (normal, copying, deleting — note Play!'s own accessor enum lists them in a
different order, so the file is the authority). `PS2Icon` parses them as data and
`PS2IconView` renders one per row in a SubViewport. Three traps, none of which
appears in a log:

- The PS2 authors icons with **+Y pointing DOWN**, so a straight read stands every
  one on its head. Caught on Indiana Jones' hat — the medallions and rings in the
  same card could not have shown it. Render something ASYMMETRIC.
- **A vertex color's scale depends on whether a texture modulates it.** Textured:
  the GS shifts the product down by 7, so 0x80 is NEUTRAL and the texture shows
  through unchanged — every textured icon on the test card reads a flat 127/128,
  which is what that looks like. Untextured: the color IS the surface, an
  ordinary 0-255. Divide by the wrong one and half the card is twice as bright as
  it should be. Indy's hat is `(35, 14, 5)` on the card and `(35, 14, 5)` in an
  independent rip of the same model.
- **A vertex color is sRGB and a renderer wants linear.** Handing the byte over
  as-is both brightens a color and flattens it toward gray — `(35, 14, 5)` is a
  7:3:1 ratio and comes out 1.6:1.2:1. That desaturation is the signature; look
  for it rather than for brightness. The TEXTURE is the opposite case: an albedo
  texture is already taken for display-referred, so converting it here too drops
  a textured icon to near-black.
- **Icons are drawn UNSHADED, with no lights at all.** The artist baked the
  shading into the vertex colors — Tekken's trophy has a bright top and a dark
  base with nothing shining on it — so lighting them again shades them twice.
  icon.sys does carry three directional lights and an ambient, and they are
  deliberately not read: several saves ship a placeholder the developer never set,
  and Indiana Jones has ambient pure RED with three lights that are pure red,
  green and blue down X, Y and Z, which renders his hat green.
- Judge this by MEASURING the output, not by eye. Unshaded, Tekken 5 renders
  `(255,253,61)`, `(93,69,50)`, `(91,56,56)` against an independent rip's
  `(255,253,61)`, `(94,68,48)`, `(92,55,55)`, and Indy renders the exact vertex
  bytes his card holds. Every wrong version above also *looked* plausible.

An `.icn` whose texture encoding or animation header is unrecognized costs the
texture or the animation rather than the whole model; five saves on the test card
showed nothing at all before that.

**Neither core takes a card through SAVE_RAM.** Both open files of their own, so
`MemcardMounts` describes where, and `memory_card_controller` copies a seated card
in before the core loads and drains it back on the poll that already exists for
Dolphin.

| | `pcsx2` (LRPS2) | `pcee2` (upstream port) |
|---|---|---|
| directory | `<system>/pcsx2/pcsx2/memcards` | `<system>/pcee2/pcsx2/memcards` |
| slot names | fixed `Mcd001.ps2` / `Mcd002.ps2` | the card's own id |
| empty slot | **phantom card** — unavoidable | `slot{1,2}_enable = disabled` |
| swap while running | next power cycle | re-opens live |

LRPS2's libretro build defaults to shared cards, which is the only mode with two
slots at all — its per-game branch names slot 1 after the ROM and DISABLES slot 2.
It keeps settings in memory and reads no ini, so those names cannot be redirected,
and it creates a card for any enabled slot whose file is missing.

**The mirror must land before the core loads, and this is load-bearing rather than
tidy.** pcee2 builds the list of cards it will offer by scanning that directory as
it registers its options — which is before the core has run any code that would
create the directory. So RetroXR creates it and fills it. A late mirror leaves the
two slot options unregistered, and `OptionsHandler::SetVariable` drops a key the
core never declared without failing, so the card would silently not be selected.

```bash
"$godot" --headless --path RetroXR res://Tests/card_tests.tscn -- --only=ps2
"$godot" --path RetroXR --resolution 900x760 --position 20,20 \
  res://Tools/input/ps2_card_probe.tscn -- --card=/path/to/card.ps2
```

The probe is **windowed, never `--headless`** — the icons are SubViewports, and
the dummy renderer returns a blank image while the size oracle happily reports the
right one. Without `--card` it generates its own saves, which proves the pipeline
and nothing about any real game's artwork.

**Both halves of the mount hang off one predicate.** `_core_owns_card_files`
decides whether a card is staged into the directory the core reads AND whether
the poller that drains the core's writes back is started. A core missing from it
loses both: the core invents a card of its own, the player saves into it, and the
save lives in a file RetroXR never reads — with the game's own LOAD screen
listing it perfectly, which is what makes the report confusing. That shipped once,
when a refactor lifted the old slot-count test into a named predicate that said
Dolphin alone. It asks `MemcardMounts` now, and `system_tests` pins it against
that table rather than a second list.

**A card can be swapped mid-game on pcee2 and cannot on pcsx2, and the reason is
the core rather than RetroXR.** LRPS2 has the whole machinery —
`VMManager::CheckForMemoryCardConfigChanges` does `FileMcd_EmuClose/EmuOpen` then
`AutoEject::Set`, a real eject the guest sees, and the libretro layer reaches
`ApplySettings()` on any option change. But it fires only when `Mcd[i].Enabled`,
`.Filename` or `McdEnableEjection` differ, all three of which come from an
in-memory settings interface, and LRPS2 declares exactly ONE memcard core option:
`pcsx2_shared_memory_cards`. So no key a frontend can set reaches any trigger. It
holds the card it opened at boot until the next power cycle, and nothing here can
change that without forking the core. `_set_card_presence` is no help either —
it is `pcsx_rearmed` only, because that is the core with a presence option.

Two things follow for a non-live core, both of which cost a bug. **A pull while
it runs must not delete the staged file or forget which card it belongs to**: the
core is still holding that card and flushes it on the way out, so the file is the
only route those writes have home. And **a staged copy belongs to the card that
FILLED it, not to whatever is in the slot now** (`_scratch_owners`) — swap a card
on one of these and the core goes on flushing the old one, so draining by the
seated card would overwrite a card the console never read with another card's
contents.

**pcee2 hot-swaps, but only because the directory is seeded.** It registers
`pcsx2_memcard_slot{1,2}_file` only when its scan found at least one card, and
that scan runs once, before the core loads — so a console powered on with both
slots empty leaves those keys unregistered for the whole session, and
`OptionsHandler::SetVariable` drops an undeclared key without failing, so every
later insert would be accepted and reach nothing. `_seed_card_directory` writes a
placeholder card to prevent that. The value need not be one of the candidates:
pcee2 says so in as many words — *"Runtime reads must not be gated by the
registration-time candidate list"* — and queries both keys every frame, so a card
first seated mid-game selects correctly though its name was never enumerated.

**Every card event prints a line**, `[MemoryCard] <machine>: …` — a card seated
or pulled, the route a mount took and what each slot resolved to, bytes staged
into a core's directory, bytes drained back out, and an image seen to change.
Events only; a poll tick that found nothing is silent. That is a direct answer to
the bug above: a drain that was never running and a drain that ran and found
nothing looked identical from outside, so every line names a slot, a file and a
byte count, which is what tells those two apart.

**LRPS2 runs on VULKAN here, and blanks fields through a null image.** Its
renderer option defaults to `Auto`, which asks the frontend what it prefers, and
RetroXR answers Vulkan (`g_preferred_hw_render`) — so the D3D11/OpenGL line in the
vendored `.info` describes neither what the core can do nor what it does here. The
overlay `pcsx2_libretro.info` says so. What follows from it: when the PS2's PCRTC
has nothing to merge, `GSDeviceVK::PresentRect` calls `set_image(nullptr)` and
then refreshes anyway, expecting the frontend to paint black. That is ordinary
traffic around every video-mode change — Ace Combat 04 does it on about 7% of
frames — and `ReadbackToPixels` used to log an error on each one. It now
distinguishes a RETRACTED image from one the core never published: the first is
silent and keeps the last frame, the second is a protocol error worth one line.

**Still owed:** netplay does not carry a PS2 card — `net_sram_file_bytes` is
slot-A-and-SAVE_RAM only, which is the same gap Dolphin has.

### 2l. A controller's own speaker — the controller audio interface

Dolphin emulates the Wii Remote's speaker completely, and stock Dolphin throws
everything a game sends it away: `SpeakerLogic::SpeakerData` returns at once unless
`MAIN_WIIMOTE_ENABLE_SPEAKER` is set, and it defaults to off. `Boot.cpp` sets it.

Switched on alone, the speaker would play in the console's main mix, i.e. out of
the television. So it comes out through a private environment call,
`RETRO_ENVIRONMENT_GET_CONTROLLER_AUDIO_INTERFACE` (96), in
`libretro-godot/src/ControllerAudioInterface.hpp` — kept byte-identical in the
Dolphin fork, like the Transfer Pak header. The core offers each controller
device's sound, every block, silence included, just before the main batch.
`push` returning false tells the core to mix that block into the main stream
instead, which is also what a frontend with no such interface gets.

The call takes a PORT and an INDEX. Index is the device on that controller: 0 is
a Wii Remote's speaker. It is there for the Dreamcast VMU buzzer, one per pad
slot, which flycast can already sound (`flycast_vmu_sound`) but through one
global generator that does not know which card beeped. Wiring that is future
work in the flycast fork; the interface needs no change for it.

- **Dolphin:** `Audio::ProbeControllerAudio` turns on
  `MAIN_WIIMOTE_AUDIO_ROUTING_ENABLED` and the four per-remote outputs ONLY when
  the frontend answers, which takes those channels out of `Mixer::Mix`; it runs
  before `BootCore` builds the mixer. `Stream::MixBlock` is now the one place a
  block is mixed and sent.
- **Frontend:** `AudioHandler::PushControllerFrames`. A voice is created the first
  time a device makes a non-silent block, so a remote that never beeps costs no
  voice. The fallback AudioStreamPlayer3D backend answers false, so on a platform
  without Meta XR Audio the beep plays from the set.
- **It is resampled at `m_last_ratio`, the main batch's ratio with the rate trim
  in it.** Resampled at the nominal ratio, the remote's voice drifts against a
  mixer whose depth the trim is holding steady.
- **An empty voice is first filled with silence to the MAIN voice's depth.** The
  MetaXRAudio mixer plays a voice with no prebuffer and counts an underrun on
  every block it finds one empty, so a voice fed in step with the main one but
  started from nothing sits at zero depth and crackles. Matching depth is also
  what makes the beep land with the game's own sound.
- **GDScript:** `Libretro.GetControllerAudioVoiceId(port, index)` is -1 until the
  voice exists. `wiimote.gd` `_update_speaker` poses it on the `Speaker` marker in
  `wiimote.tscn` (the middle of the grille, facing out of the face) with the
  distance law only: a game sets the speaker's volume itself, as it does on the
  hardware, so the television's level has no say.

`RetroXR/Tools/cores/wiimote_speaker_probe.tscn` is the check, and a probe because
it wants Dolphin and a Wii disc.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/wiimote_speaker_probe.tscn
```

**Measured 2026-09-13** against Wii Sports (USA) (Rev 1): the A press on the
health screen beeps the remote, and port 0 got voice 2 (main voices 0/1) 432 core
frames in, with samples queuing on it. The same run against the previous core
(`dolphin_libretro.dll.prespeaker`) pressed for 7200 frames and never got a voice,
so the oracle can go red.

Two traps it hit. **Windowed only:** under `--headless` the SDK reports itself
unavailable and there are no voices to give. And **the desktop Options switch
turns the SDK off for the whole process** — `SpatialAudioListener` applies
`AppPrefs.spatial_audio_sdk` at boot, and `is_available()` answers false while it is
off even with the library loaded, printing `not available ()` with an empty error.
The probe enables it for its own run. A desktop player with that option off hears
the remote from the television, which is the fallback working, not a bug.

### 2m. Sega CD backup memory — on the unit, on a cartridge, written at unload

A Sega CD game saves to the 8 KB of backup RAM inside the unit or to a Backup RAM
Cartridge in the Mega Drive's slot. Both are modelled: the `sega_cd` unit's row
declares `"memory": "sega_cd_memory"`, so the RetroExpansion carries a card id
saved with the room, and `sega_cd_ram_cart` is a MOUNT_CARTRIDGE unit with no BOOT
key whose memory family is `sega_cd_ram_cart`. The unit's memory is managed from
the console's System Settings **Saves** tab (a switch appears when a cartridge is
seated too); the cartridge also opens its own card panel and lives on the card
shelf, offered from the Sega CD's card.

**genesis_plus_gx never hands either over.** Read at source: both live in files in
`<root>/save/<core>`, read in `retro_load_game` (`bram_load`) and written only in
`retro_unload_game` (`bram_save`) — no SAVE_RAM, no memory map, not in savestates,
no periodic flush. `SegaCdStorage` pins the names for the run
(`genesis_plus_gx_system_bram` per bios, `_cart_bram` per cart, `_cart_size` from the
seated cartridge's image or disabled), stages the unit's image into all three
`scd_U/E/J.brm` (the region is the disc's, unknown until load) and the cartridge's
into `<size>_cart.brm`, then drains the file the core rewrote back to the image
that filled it for 12 s after StopContent, and clears the folder. A manifest on
disk lets a crash between the two recover at the next start. Files nobody's
manifest claims are older saves: moved into `legacy/`, never over, and a new unit
or cartridge starts from the most recent that fits. The folder is shared by every
machine on the core, so a second Sega CD is refused while it is in use.

The format is `SegaCdBram`, whose error correction is transliterated from buram
(Ian Karlsson, MIT); `card_tests` pins buram's own output for the same operations
by SHA-256, and `expansion_tests` covers staging (`scd_storage/`) and the units
and tab (`memory/`).

**Measured 2026-09-14** with `Tools/cores/sega_cd_bram_probe`, US BIOS 1.10:

- Its DATA STORAGE INFORMATION screen reports the staged images' own counts — 1
  item, 124 free built-in; 1 item, 252 free on a 128 Kbit cartridge.
- ERASE ITEM lists `RETROXR_MEM` by name, so the BIOS decodes the directory
  SegaCdBram writes, not just its counters.
- The BIOS's own COPY built-in → RAM, confirmed, leaves a cartridge file that
  SegaCdBram reads back as `RETROXR_CRT` + `RETROXR_MEM`, 250 free: a write by the
  real BIOS, through the core's unload, read by ours.
- With the cartridge **disabled**, the stock core's BIOS says the cartridge memory
  "IS NOT PRESENT". The source reads as if "disabled" (0xFF) still maps a cartridge,
  and a patched core behaves identically, so no fork is needed for it.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/sega_cd_bram_probe.tscn -- --root=<root with system/bios_CD_U.bin and cores/> \
  --cart=128k --at=11 --press=4:start,6:down,6.8:right,7.6:b --shot=C:/tmp/scd.png
```

That press list reaches the storage screen; B there opens the MENU (FORMAT, ERASE
ITEM and COPY for each memory, cursor on EXIT). A copy's confirmation defaults to
NO, so LEFT before B. Point `--root` at a throwaway root: the probe writes its
`save/` and `core_options/`.

Still owed, and why: picodrive (the Tower of Power runs on it) has its own route
and is not covered; netplay and savestates carry no backup memory, because the
core keeps it outside both; a crash before the core unloads loses that session's
writes, because nothing reaches disk until then; and the four options that
rebuild the machine (`system_hw`, `bios`, `region_detect`, `vdp_mode`) zero both
memories mid-game, so they are held while a Sega CD runs.

### 2n. Sega Saturn backup memory — in the console, on a cartridge behind the lid

A Saturn saves to 32 KB of System Memory on its board or to a 512 KB Backup RAM
Cartridge. The System Memory belongs to the console: `SystemInfo.console_memory`
names its family (`sega_saturn_memory`), `RetroSystem` builds a `ConsoleMemory`
child whose `card_id` is saved with the room (`console_memory` in the system
entry), and it is managed from the console's **Saves** tab by the card panel's own
code. The cartridge is the `sega_saturn_ram_cart` unit, MOUNT_ABOVE because the
Saturn's CartridgeSlot is its disc well: the console grows an ExpansionSocket, and
`RetroSystemModelDefault.configure_expansion_socket` moves it into a slot behind
the lid (`ProceduralDiscBay.seat_rear_slot`). The unit's size and the slot's depth
are estimates, not measurements. Both images are `SaturnBram`, the layout of
Yabause's HLE BIOS calls (`src/bios.c`).

**Beetle Saturn keeps the two differently**, read at source (`libretro.cpp`):

- The System Memory goes through SAVE_RAM in the "libretro"
  `beetle_saturn_save_method`; in "mednafen" the core writes a `.bkr` itself and
  exposes no SAVE_RAM. So `MemoryCardController._compose_sram_path` points every
  `mednafen_saturn` run at the console's image, disc or no disc. Other Saturn
  cores keep the per-disc route.
- The cartridge is a file the core owns in its save dir: `<disc>.bcr`, or
  `mednafen_saturn_libretro_shared.bcr` with `beetle_saturn_shared_ext` on. It is
  read at load and flushed ~180 frames after a write and again at unload.
  `SaturnStorage` pins shared_ext, stages the seated cartridge's image into that
  file, drains it while running and for 12 s after stop, and keeps a manifest for
  a crash, as SegaCdStorage does. One Saturn with a cartridge runs at a time.
- `beetle_saturn_cart` is pinned "Backup Memory" with a cartridge seated and
  "None" without. **That takes Auto Detect away**, and Auto Detect is what gives
  the Japanese titles that need a 1 MB or 4 MB Extended RAM cartridge their RAM:
  they will not run until there is a unit for that cartridge.

The first System Memory image made takes the saves games kept in per-disc `.srm`
files, which stay where they are. A new cartridge takes the saves in the per-disc
`.bcr` files Beetle made while it gave every disc a cartridge of its own; those
are moved to `legacy/` and renamed `.imported` once taken.

**Measured 2026-09-15** with `Tools/cores/saturn_bram_probe`, Beetle Saturn
v1.32.1 and BIOS NTSC-4-V1.01a, on the empty-media cue:

- A blank cartridge Beetle formatted itself hashes the same as
  `SaturnBram.blank_image(CART_SIZE)`; `card_tests` pins that digest.
- The BIOS Memory Manager lists `RETROXR_MEM RetroXR 4` from the image handed over
  through SAVE_RAM. Its "Memory available: 458" is Yabause's
  ((64 − 6) × free − 30) / 64 over SaturnBram's 506 free blocks, a different unit
  from the card panel's count.
- The BIOS's own copy to the cartridge leaves a `.bcr` that SaturnBram reads back
  byte-exact.
- Its copy of a 1500-byte cartridge save into System Memory comes back through
  SAVE_RAM as 27 blocks whose block list crosses a block, also byte-exact.

```bash
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/saturn_bram_probe.tscn -- --root=<throwaway root with system/mednafen_saturn and cores/> \
  --cart --at=28,31,34 --press=17:up,18:b,20:down,21:down,22:b,24:b,26.5:b,29.5:b --shot=C:/tmp/sat.png
```

The BIOS goes straight to its CD player on the empty-media cue. That press list
takes the top-middle icon (System Settings), then Memory Manager, and copies the
System Memory's first item to the cartridge; RetroPad B confirms and "OK to copy?"
defaults to Yes. Three downs inside Memory Manager reach "Copy Item to System".
Point `--root` at a throwaway root: the probe writes its `save/` and
`core_options/`.

Still owed: netplay and savestates carry no cartridge; no game has been run saving
to either memory; and the Extended RAM cartridge above.

### 2o. Microphones — one reader, and every machine that asked

libretro's microphone interface (`RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE`, 75 |
EXPERIMENTAL) is answered by `libretro-godot/src/MicrophoneHandler.cpp`, and the real
microphone is read by exactly one thing in the app: the `Microphone` autoload,
`Scripts/Audio/microphone_input.gd`.

**One reader, because Godot keeps one cursor.** `AudioServer.get_input_frames()` (Godot 4.6+)
advances a single process-wide read offset, so two readers would each get part of the audio
and neither would know. The service drains it once a frame and hands the same frames to every
machine that wants them. It must drain EVERY frame while the device is on: the ring is only
four driver buffers long — 2048 × 4 frames on Android, about 186 ms at OpenSL's hardcoded
44100 Hz with the mono input duplicated into both channels, and a 1 s buffer × 4 on WASAPI,
which rate-adjusts capture to the output mix rate. Nothing captures without
`audio/driver/enable_input=true`; `set_input_device_active` warns and fails.

**Which input, when the machine has more than one.** Options -> Microphone carries an **Input**
dropdown built from `AudioServer.get_input_device_list()` as the page opens (this desk offers
five; a Quest offers one and the row reads Default). `AppPrefs.microphone_device` stores the
NAME, never the index -- an index means a different microphone the moment one is unplugged --
and `Microphone.resolve_device` falls back to `Default` for a name the platform is not currently
offering, while KEEPING the preference: a USB microphone plugged back in is used again, and
capturing from nothing would read as a broken microphone rather than a missing one. The input is
selected BEFORE the device is switched on, because a driver opens the one it was pointed at, so
a preference changed mid-run closes and re-opens rather than leaving capture on the old input.

**The device opens only while a core is listening.** Each frame the service collects the
powered-on `retro_system` machines whose `Libretro.IsMicrophoneActive()` is true — a handle
open and enabled, the machine running and not in netplay — and turns the device on only while
that list is non-empty and Options → Microphone (`AppPrefs.microphone_enabled`, default on)
allows it. Every transition prints a `[Microphone]` line.

**Every open microphone hears the player, fading with distance.** Gain is
`SpatialAudioEmitter.distance_gain(mic, head, 0.5, audio_max_distance)`: full level within arm's
reach, 1/d beyond, nothing past the machine's own `audio_max_distance`. The reference distance
is the microphone's, not the speaker's `audio_unit_size` (3 m), under which a DS across the
room would get the player's voice at full level. `RetroSystem.microphone_position()` is a
seated microphone's body when there is one, otherwise the machine.

**How the extension answers.**
- **`open_mic` is a callback trampoline**, the eighth in `CallbackTrampolines`. Dolphin calls
  it from its CPU thread (`EXI_DeviceMic.cpp` `StreamStart`, reached from `TransferByte`),
  where the thread-local Wrapper was never set. Every later call carries the handle and may
  arrive on any thread.
- **Handles come from a process-wide pool of 32 that is never freed.** Each slot has its own
  mutex, and a handle is validated by address rather than dereferenced, so a Dolphin CPU thread
  reading during teardown gets -1 or silence, never freed memory. Four per core.
- **`read_mic` returns silence and the FULL count** whenever the mic is off, the machine is
  stopped or in netplay, or the ring runs dry; -1 only for a pointer that is not a handle.
  NooDS stores the result in a `size_t` and virtualjaguar assumes all-or-nothing reads.
  RetroArch answers the same way.
- **`get_params` reports the rate the core asked for,** and each handle resamples to it: linear,
  and pass-through when the rates match.
- **Latency is bounded per handle.** A 150 ms cap drops the oldest samples. 40 ms of silence is
  served after an enable, a flush or an underflow. A read that leaves more than 100 ms trims
  back to 60 ms. The trim is what keeps a core that reads less than it is sent from sitting at
  the cap.
- **Silent in netplay.** An `NpFrame` is 128 ints, 735 samples a frame have nowhere to ride, and
  a microphone is not the same on two peers anyway.
- **Not silenced by `SetAudioPlaying(false)`.** That follows display cabling ("a machine wired to
  nothing is silent"), and a console with no television still hears its microphone.

**Permissions.**
- **Android.** `input_start()` requests `RECORD_AUDIO` itself, and the grant callback restarts
  capture (`platform/android/java_godot_lib_jni.cpp`), so switching the device on is the whole
  request. The Quest preset declares `permissions/record_audio=true`. With nobody wearing the
  headset, grant it before launch — there is no one to tap the dialog:
  ```bash
  adb shell pm grant com.xenu.retroxr android.permission.RECORD_AUDIO
  ```
- **macOS.** Needs `privacy/microphone_usage_description` and `codesign/entitlements/audio_input`
  in the preset AND `com.apple.security.device.audio-input` in `entitlements/macos.entitlements`,
  because `release.yml` signs with that file rather than the preset's.

**Which cores hear a microphone**, read at source:

| core | hardware | asks for | switched by | calls from |
|---|---|---|---|---|
| melondsds | DS / DSi mic | 44100, 735 a frame | `melonds_mic_input` (default `microphone`), `melonds_mic_input_active` (default `hold`, on L3) | emulation thread |
| noods | DS mic | 44100 | `noods_micInputMode`, `noods_micButtonMode` (L2) | emulation thread |
| dolphin (fork) | GameCube DOL-022, Wii Speak, Logitech USB | the game's rate, a frame's worth at a time | see below; `dolphin_wiispeak_enable`, `dolphin_wii_logi_microphone_enable` | open and state on its CPU thread, reads in `retro_run` |
| azahar (buildbot) | 3DS mic | opens at 48000 and resamples itself | `citra_input_type` (`auto`, `none`, `static_noise`, `frontend`) | emulation thread |
| virtualjaguar | Jaguar voice modem | 8000 | — | emulation thread |
| mupen64plus-next (fork) | N64 Voice Recognition Unit | 48000, decoded by Vosk | the port's device id; captures while the game listens | opens and reads in `retro_run`, decodes on its own worker |
| flycast (fork) | Dreamcast HKT-7200 | 48000, decimated to the device's 8000 or 11025 | `reicast_device_port<N>_slot<M>` = `Microphone` | opens and reads in `retro_run`, drained on the emulation thread |

A mic that is only a BUTTON, with no audio behind it: DeSmuME (`desmume_mic_mode`, L3 "Make
Microphone Noise"), legacy melonDS (L2), and Nestopia and Mesen for the Famicom (below). No
libretro core hears a PS2 SingStar mic (LRPS2 has no USB microphone) or PSP Talkman
(PPSSPP's libretro build reports no recording).

**The DS listens the whole time, because a DS has no mic button.** melonDS DS gates its mic on
L3 with a default of `hold`, and the DS model masks L3 (`nds_model.gd`
`get_unsupported_button_mask`), so out of the box nothing could switch the mic on. The model
pins `melonds_mic_input=microphone` and `melonds_mic_input_active=always`, and the game decides
when it listens, as on the hardware. The host device therefore stays open for as long as a DS
runs on melonDS DS. DeSmuME has no audio path at all: its `physical` mode reads a buffer the
libretro frontend never fills.

**Measured 2026-09-15** with `Tools/cores/mic_probe`: melonDS DS 1.3.1 opened its microphone at
44100 Hz while loading Super Mario 64 DS and switched it on 4 frames in; over 6 s the service
opened the desktop device and pushed 279,343 host frames at 48000 Hz in 553 pushes. The probe
cannot run against a build without the interface, which has no `IsMicrophoneActive`.

**The GameCube Microphone (DOL-022) seats like a memory card, live.** The hardware:
- A 21 × 140 mm gray stick with an aqua push-to-talk button about 43 mm from the tip, 2 m of
  cord, and a memory-card-shaped plug unit 35.6 × 63 × 13.7 mm.
- It fits either memory card slot; Mario Party 6 and 7 ask for B.
- The button is ON THE MICROPHONE — the EXI status word carries it (`EXI_DeviceMic.h`: "The
  actual button on the mic") — and Mario Party 6 ignores speech until it is held. Odama talks on
  the controller's X instead, with the stick clipped to the pad.

In the Dolphin fork (v11):
- **`dolphin_memcard_a_path` / `_b_path` accept `mic`,** which `Memcard::Resolve` turns into the
  Microphone EXI device. `CheckForUpdates` already `ChangeDevice`s a slot whose answer changed —
  one emulated second of nothing, then the new device — so seating or pulling a microphone is a
  real eject and insert, exactly like a card.
- **`poll_microphone` polls every GameCube microphone that exists.** A `CEXIMic` adds itself to
  `g_gc_microphones` when it is built and removes itself first thing when it is destroyed, under
  `g_gc_microphones_lock`, so a swap on the CPU thread can never hand the libretro thread a
  device that is gone or not yet a microphone. It used to latch `dolphin_enable_gamecube_mic` on
  `IsUpdated`, which never fires for a value that arrived in the `.opt`: a microphone enabled at
  boot was never polled, and nothing said so.
- **The button is read whenever a microphone exists.** In the libretro build
  `GCPad::GetMicButton` ignores the pad number and ORs the button mapped by
  `dolphin_hotkey_activate_microphone` across all four ports (`GCPadEmu.cpp`). Standalone
  Dolphin reads slot A's button from pad 1 and slot B's from pad 2, which is what its forum
  answers describe, and does not apply here.
- **`GetRetroButtonId` did not know `L1` or `R1`,** though the option offers both. Its `L` ↔ `L2`
  swap is deliberate: a GameCube's analog L is libretro L2.
- **The older `dolphin_enable_gamecube_mic` still works,** and still loses slot B to a named card.
- **Seating or pulling a microphone says so,** as `Memory Card B: microphone seated` / `pulled`,
  a warning under BOOT.
- **Each poll reads a frame's worth**, `sample_rate` over the target refresh rate with the
  fraction carried (fork `9a2b37e`, after v11). v11 read one `buff_size_samples` buffer, 16 to
  64 samples, against the ~184 a frame an 11025 Hz game takes; the ring ran dry and
  `StreamReadOne` re-served the previous buffer several times a frame, a buzz no game could hear
  a word in. Measured 2026-09-16 in a player's session: Mario Party 6 answers speech through a
  DOL-022 in slot B with the fix, and did not with v11. It reaches players only with a v12
  release and a `known_tag` bump.

In RetroXR:
- **Objects.** `GcMicrophone` is the stick. `GcMicrophonePlug` is in group `memory_card` with
  `family = "gamecube"`, `is_microphone = true` and no `card_id`, so the shared `_accepts_card`
  seats it in either slot and `_mount_core_cards` writes `mic` for that slot, live through
  `set_core_option`.
- **The button.** The trigger of the hand holding the stick is the aqua button; on desktop it is
  the left mouse button, and the stick sets `desktop_shift_drop` so that click does not put it
  down (Shift+click does), which `microphone_tests` `gc/` pins. Every controller
  writes its whole button mask each frame, so a bit set by another object is gone by the next
  one. The stick uses `Libretro.SetJoypadExtraButtons(0, 1 << R3)`, ORed in when the core reads,
  and the machine pins `dolphin_hotkey_activate_microphone=R3` — no GameCube pad maps R3.
- **Saves.** The plug is on the cord rather than an entry of its own, so the stick's entry
  records `system` and `slot`, and `_apply_references` seats it again.
- **Group sweeps.** Anything that sweeps the `memory_card` group must not assume a card: the card
  poller skips an object with no `card_id`, and card numbering counts only `MemoryCard`s.

**A cord leaves a body along the anchor's local -Z**, which both of these are built against:
the DOL-022's grille and the NUS-021's are at -Z with the cord boss at +Z, so left at the
default each cord came out of the nose and doubled back through its own body. Both ropes now say
`start_exit_axis` and `end_exit_axis` explicitly. The oracle is a SIGN, not a look --
`microphone_tests` and `n64_vru_tests` dot the exit direction against the body's nose-to-boss
vector and want it positive; the default reads exactly -1.00.

**Measured 2026-09-15** with `Tools/input/gc_mic_probe` on the GameCube IPL, no disc. With the
DOL-022 in slot B the options file read `dolphin_memcard_b_path=mic` and
`dolphin_hotkey_activate_microphone=R3`, and v11 logged `Memory Card B: microphone seated` at
boot, `microphone pulled` when the plug came out mid-run and `microphone seated` when it went
back, with the IPL running through both. The same run against the previous build
(`+40a25ffd80`) passes every frontend check and prints none of the three lines: it refuses `mic`
as a card path, in a log category no frontend sees. That is why the line is a warning under
BOOT — the libretro listener leaves EXPANSIONINTERFACE disabled, and libretro-godot passes
nothing below a warning. The IPL never samples the microphone, so no handle was opened.

Shut BOTH card slots to pull the plug in a probe: slot A sits beside B and catches it, and the
mount log then reads `0=microphone`. `Tools/models/gc_microphone_render_probe` renders the stick
seated and prints the plug's axes — its +Z matches slot B's and the cord end points out of the
console.

```bash
"$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/cores/mic_probe.tscn
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/input/gc_mic_probe.tscn -- --root=<throwaway root with cores/dolphin_libretro.dll and system/dolphin/dolphin-emu/Sys>
```

**The N64 Voice Recognition Unit is built, and it is a speech recognizer rather than
a microphone.** The hardware: NUS-020 goes in controller socket 4, and its NUS-021
microphone hangs on a cord (clipped to the pad by NUS-025 in Hey You, Pikachu!), with an
ordinary pad in socket 1. Both VRU games want socket 4 — RMG offers the VRU on its last
port alone and says why (`RMG-Input/UserInterface/MainDialog.cpp`) — though `osVoiceInit`
takes any channel and the core attaches a VRU wherever the input plugin reports
`CONT_TYPE_VRU`.

**The emulation was already complete and unreachable.** `vru_controller.c` speaks the whole
joybus protocol, but `plugin.c:317` stamps every port `CONT_TYPE_STANDARD` and the five
recognition calls pointed at the no-ops in `dummy_input.c`, so no frontend could get at it.

In the fork (`retroxr-mupen64plus-next-libretro-v4`):
- **`RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, 0)` on a port makes it a VRU**, kept in
  `pad_types[]` beside the existing `pad_present[]` idiom and applied in
  `inputInitiateControllers` — which runs after `plugin_start_input`'s blanket overwrite and
  before the joybus channels are built, and is therefore the only window in which a VRU can
  be asked for. An id the core does not know still falls through to a pad.
- **It attaches at content load, not at reset.** `retro_reset` never re-enters the channel
  build, so a unit pushed in mid-game is heard at the next load; the core says so once, as a
  warning and an on-screen line naming a reload rather than a reset.
- **Five plugin calls, not three.** `ClearVRUWords` is the only signal that a new word list
  is starting — without it the grammar grows for ever. `SetVRUWordMask` really is unused.
  All five arrive on the emulation thread, so they only touch flags under a lock: Vosk lives
  on a worker of its own, and every microphone call belongs to the thread that runs
  `retro_run`.
- **The game decides when the unit listens, and nothing the player holds does.** The real
  VRU has no button: a game sends it "listen" and "stop" (`JCMD_VRU_WRITE_CONFIG` 0x4E /
  0xEF, arriving as `SetMicState(1)` / `(0)`), and the chip inside reports "busy" while
  someone talks and "ready" when they stop. `vru_controller.c` cannot hear, so it fakes that
  status from Z on the VRU's own port (its comment says HACK). Both working plugins raise that
  line from the game's own mic state — RMG-Input's `GetVRUMicState()` sets `Keys->Value =
  0x0020`, simple64-input-qt does the same with a 2 s timer — and so does
  `vru_recognizer_talking` now. Capture runs from the game's "listen" to its "stop", the stop
  queues the decode, and `ReadVRUResults`, which the game sends straight after, waits for that
  utterance's result (the references decode inside it, so the game is held either way).
  **The first build took the line from the player instead** — the NUS-021's trigger — and
  words were recognised, logged and never reached the game at the moment it asked. In Hey
  You, Pikachu! the player holds Z on their own controller; that is the game's business, and
  the "listen"/"stop" it sends is the only thing the core follows. `mupen64plus-vru-mic-mode`
  is gone with the button, and `mupen64plus-vru-port` with it: which socket holds a VRU is the
  port's device, "Voice Recognition Unit" in the controller list.
- **Vosk is opened at run time, never linked.** A `DT_NEEDED` on `libvosk` would make the
  N64 core everyone installs fail to load when the speech pack is absent. Missing library,
  missing symbol or missing model costs the recognition and nothing else: the VRU still
  attaches, the game still boots, and it simply never understands you.
- **A word is looked up, not guessed.** `vru_word_table.h` is generated by
  `tools/gen_vru_word_table.py` from RMG's `VRUwords.cpp` (GPLv3, so the recognizer is
  GPLv3): 677 unique keys out of 717 rows, first spelling winning, exactly as RMG's own
  lookup does. The table maps the big-endian phoneme codes a game sends to the text a
  recognizer listens for — including Densha de GO!'s Shift-JIS words, which RMG maps to
  English, so Densha de GO! 64 is played by speaking **English**. Pikachuu Genki de Chuu
  has no rows at all: it sends text, below. The lookup still runs first for every word,
  which is what keeps Densha de GO! on its English table text.
- **The model is chosen by what the grammar contains**, not by the ROM's country code: a
  word that decoded to kana wants `model-ja`, an all-ASCII list `model-en-us`.
  `mupen64plus-vru-language` overrides it, and forcing either one against its game hears
  nothing — Densha de GO!'s English text is not in `model-ja`, and Pikachuu Genki de Chuu's
  kana are not in `model-en-us`.
- **A Japanese title sends its words as Shift-JIS text**, one character to each uint16,
  and the unknown-word path used to copy those bytes straight into the grammar. Vosk reads
  and answers in UTF-8, so the grammar and the answers were in two encodings and no Japanese
  word could ever match. Four steps now:
  - **Decoded at the door** (`vru_recognizer_decode_word`) through a built-in kana table —
    hiragana `0x829F–0x82F1`, katakana `0x8340–0x8396` stepping over `0x837F`, `ー` `0x815B`,
    the full-width space — checked against Python's codec for all 171 codes. No iconv, since
    the core builds for MinGW and the NDK. A character outside it refuses the word, which
    still holds its slot, empty.
  - **Folded to katakana** (`vru_recognizer_fold_kana`). A game spells in hiragana; the
    model's lexicon spells ピカチュウ only in katakana and こんにちわ in both.
  - **Split into lexicon words** (`vru_segment_words`). Vosk 0.3.45's `UpdateGrammarFst`
    turns the list into a bigram model and DROPS each token its lexicon lacks, and most of
    what this game sends is not a lexicon word: it sends the ways a child might say one,
    ぴかっちゅう and ぴかてう beside ぴかちゅう. Each word goes to Vosk as the fewest
    `model-ja/graph/words.txt` words that spell it once folded — `ゲーム スタート`,
    `ピカ っちゅう`. When a stretch has both spellings the katakana one is given, because a
    hiragana entry can be a particle and は read as a particle is "wa". The 200,000-line
    lexicon is scanned once per list and not kept.
  - **Matched a whole folded word at a time.** Vosk's answer is folded the same way and a
    word matches when its folded phrase appears in it between spaces, so ぴかってう is not
    also heard as the かって inside it. English matching is unchanged.
- **Lists are bigger than they looked.** Pikachuu Genki de Chuu sends **84** words, where
  the recognizer held 64 and its grammar loop read past the array for the rest. It holds 256
  now (the count is a uint8) at 128 bytes each (40 uint16s of kana). A result is matched
  against the worker's own copy of the list the recognizer was built from, and an unreadable
  word's slot is held empty rather than keeping the last list's word, which used to match
  every utterance.
- **The reply is RMG's**, transcribed rather than invented: five (slot, distance) pairs
  defaulting to `0x7FFF`/0, distance = alternative rank × 256, matches sorted longest-first,
  `mic_level`/`voice_level` `0x0BB8` and `voice_length` `0x8004`. `error_flags` is `0x8000`
  when the decoder refuses the audio and **`0x4000` when something was heard that matched
  nothing** — that flag is the whole difference between "understood" and "did not", because
  the no-match reply also reports slot 0. **Every field is written on every read**, the error
  word included: they point into the joybus reply, which still holds old bytes, and the error
  word used to be written only on an error — a clean match reached Hey You, Pikachu! as
  `0xFE78`, both the decode-failed and the no-match bit. The selftest now starts that word at
  `0xFE78`, which a missed write reads straight back.
- **Every core log level now reaches the frontend.** `n64DebugCallback` mapped every
  `M64MSG_*` to `RETRO_LOG_INFO`, which frontends drop, so no warning the core raised was
  ever visible. It carries the real level across now, which is what makes the line below an
  oracle.
- **A real out-of-bounds read was fixed on the way past**: `vru_controller.c` tested
  `word[offset]` before the bound, reading two bytes past the controller struct.

In RetroXR:
- **It is three objects, as the hardware is three parts.** `N64Vru` is the dongle,
  `N64VruMic` the microphone, and `N64VruMicPlug` the 3.5 mm plug on the microphone's cord.
  The dongle hangs off a second cord that ends in an ordinary `ControllerPlug` — the same
  generic moulding every N64 pad wears, since `n64_controller.tscn` declares no
  `plug_mesh_path` of its own.
- **The PLUG is what a socket takes, not the box**, which is why this needed no new plug
  class. `ControllerPlug.set_controller(unit)` copies `device_type` and `systemid` off the
  dongle, the plug is the one in the `controller_plug` group, and `_bind_port` unwraps it
  with `get_controller()` before filing it in `_port_controllers` — so the console still
  sees a VRU and the unit still answers `microphone_position()`. The box was in that group
  until 2026-09-17 and its front end was moulded as a connector tongue to suit.
- **The microphone plugs in and pulls out.** The dongle carries a `MicJack` snap zone
  filtered on `N64VruMicPlug.GROUP` — its own group, because `snap_require` on
  `controller_plug` would take a console controller's plug, the trap `n64_pak_port.gd`
  names for the pad's expansion bay. It spawns plugged in, and the unit's entry records
  `mic` so a save remembers. **Out of the jack the unit reports ITS OWN position**, not the
  microphone's: `microphone_position()` is a total function with no way to say "nothing"
  (`system.gd:4182-4203` falls back to the console), so a microphone left on a table across
  the room must stop setting the gain. Whether the machine hears at all is not decided
  there and gets no N64-special case — the unit keeps announcing `DEVICE_VRU` while seated,
  because the NUS-020 is on the joybus with or without a microphone in it.
- **The NUS-021 has no button.** It is what the player speaks into and where the distance
  law measures from; when the unit listens is the game's decision, above.
- **No two faces may share a plane.** The microphone's grille used to be a flat collar
  ending on exactly the body's front cap at z −0.0475, one albedo 0.73 and one 0.18: the two
  cap triangle-fans interleaved and the nose drew as a flickering pinwheel. It is a ball
  head sunk into a tapered body now, and `n64_vru_tests` `faces/` walks both scenes'
  meshes and fails on any two coplanar faces **that point the same way** — a butt joint,
  where the normals oppose, is safe because culling draws only one of them. Reverted, it
  reports `Body|Grille at 0.0475`. `Tools/models/n64_vru_render_probe` renders the set
  (windowed, never `--headless`) and prints the facings.
- **`RetroSystem.microphone_position()` walks the controller ports** as well as the card
  slots, so the distance law follows the NUS-021 in the player's hand rather than the
  console.
- **The speech pack lives under the core's own system directory**,
  `<libretro>/system/mupen64plus_next/vru/`, holding `libvosk` (`.dll` with its MinGW
  runtime DLLs, `.so`, or `.dylib`, from the same Vosk 0.3.45 release as the header) and
  `model-en-us` / `model-ja` (`vosk-model-small-ja-0.22`, needed for the Japanese games).
  That directory is per core name, so the Quest's `mupen64plus_next_gles3` has one of its
  own. On Android it must stay on internal storage: `dlopen` outside the app's own
  namespace is refused.
- **It is downloaded from OPTIONS > Cores > BIOS / Extras**, on the Nintendo 64 page: one
  row per language, "Voice Recognition Unit speech: English" and "…: Japanese". A row is
  a **pack** (`SystemAssetCatalog.PACKS`), the kind of download libretro does not host:
  each part is a zip from its own author -- the library from Vosk's GitHub release
  (`vosk-win64` / `vosk-linux-x86_64` / `vosk-android` 0.3.45, `vosk-osx` 0.3.42, the
  last universal build Vosk published) and the models from alphacephei.com -- with the
  folder inside the zip to take (`from`), the folder of the system dir it goes to (`into`)
  and which files to keep (`only`, so the library zip leaves its headers and import
  library behind). A part already on disk is skipped, so the second language downloads
  only its model; a row reads Installed when every part's marker exists, and pressing it
  again re-fetches everything as a repair.
  - **GitHub answers a release asset with a 302 to a signed link that expires within the
    hour**, and `RommHttp` follows no redirects, so `FirmwareInstaller` resolves the URL
    with HEAD requests at the start of every attempt, not once.
  - **Measured 2026-09-16** against the real hosts into a scratch system dir: Japanese
    fetched the library (4 files) and its model (16), English then fetched only its model
    (14), 13 s in all; `vru_selftest` pointed at the result passes every English and
    Japanese case. `archive_tests` `pack/` covers the remapping, the `only` list, a zip
    missing a listed file or renamed underneath us, a member climbing out of `into`, URL
    splitting, the per-platform library name the core opens, and installed-means-every-part.
- **Every platform builds it.** `vosk_api.h` is vendored in the fork under
  `custom/dependencies/vosk/` with its Apache-2.0 licence. It was a git submodule, which
  the release workflow cannot check out (this repository vendors by subrepo, and a leftover
  gitlink makes `submodules: recursive` fail), so a build from the committed tree stopped at
  `vosk_api.h: No such file or directory` on every platform. `retroxr-release.yml` now has
  Linux x86_64 and macOS arm64/x86_64 jobs beside Windows and Android, and fails a Linux or
  macOS build that links libvosk.

**Measured 2026-09-15.** `tools/vru_selftest` loads the same library and model the core
loads, sends the word list the way a game sends it, and pushes a recorded utterance through
the same entry point the microphone feeds: a spoken "pikachu" comes back as slot 0 with no
error flags, and a control utterance the game is not listening for comes back `0x4000`,
refused. Swapping the two makes both checks fail, which is what makes them checks. Vosk's
own answers are `{"text": "pikachu"}` and `{"text": "[unk]"}`.

`Tools/input/vru_probe` then proves it against the game itself. With a NUS-020 in socket 4,
**Hey You, Pikachu! loads its vocabulary into the unit** -- the core logs the grammar it built
from the phoneme codes the game sent, which is also what proves the word table was transcribed
correctly:

```
["pikachu", ... , "hey", "come here", "this way", "good bye", "see you later", "bye bye",
 "start", "lets play", "hello", "open sesame", "go away", "good morning", "im sorry",
 "i choose you", "hey you pikachu", "pika pikachu", "pika pika pi", "pi ka ka pi",
 "bring that here", "go get it", "give it to me", ...]
```

and `Game controller 3 (VRU controller) attached` names `g_vru_controller_flavor`, so the joybus
device was selected rather than inferred. **One leg per process**: `--leg=control` runs the
same game with an empty socket and prints none of those lines. The probe speaks with Z held on
the socket-1 controller, but only a scene where Pikachu listens starts the unit, and its opening
is not one; the log says `VRU: the game started listening` when a scene does.

**Measured 2026-09-16 in a player's session**, Hey You, Pikachu! in gameplay, a real voice
through a C920 webcam, VRU Logging on: holding Z brackets each utterance with `the game started
listening` / `stopped listening`, and the game reads its answer 10 ms after the stop:

```
VRU: heard "hello" as word 14 "hello"
VRU: the game read 1 result(s), first slot 14, flags FE78 (10 ms)
VRU: heard "throw it" as word 41 "throw it"
```

and the player reported it working. `FE78` there is the unwritten error word above; the build
after that run writes 0, and has not yet been played. A scene loads its own list —
two grammars in that session held "stay at my house" and "throw it" in one and not the other.
**The log shows a blank line after every core line**: mupen ends each message in `\n`, the
libretro convention, and libretro-godot's `LogHandler` prints it with `print_line_rich`,
which adds another. Every core that follows the convention does the same there.

**Measured 2026-09-16, the Japanese half.** Pikachuu Genki de Chuu, same probe, a NUS-020 in
socket 4: the game sends 84 words, every one of them spelled by `model-ja`'s lexicon
(`ぴかっつう` as `ピカ っつう`, `きみにきめた` as `キミ ニキ メタ`, `つぎのすてーじへれっつごー` as
`つぎ のす テー ジヘ レッツゴー`), and an Open JTalk ぴかちゅう pushed through the microphone
interface comes back four times out of four as

```
VRU: heard "ピ カッ ちゅ" as word 9 "ぴかっちゅ"
```

-- one of the misheard spellings the game lists so that a child's "pikachu" still counts.
`--leg=control` with socket 4 empty prints no VRU line and loads no model. The selftest's
`engine-ja` group does the same offline: ぴかちゅう (whole in the lexicon) and げーむすたーと
(only as `ゲーム スタート`) each return their slot with no error, ばなな returns `0x4000`. Each
of five mutations fails exactly its own cases -- no Shift-JIS conversion, no fold, no katakana
preference, the English match rule, no segmentation. **The same selftest passes on Linux**
(WSL Ubuntu 24.04, gcc 13, Vosk 0.3.45's `libvosk.so` through `dlopen`), where
`make platform=unix` builds a core with no `libvosk` among its NEEDED entries.

Two traps from getting there. **A test that speaks the moment it sends the list is timing the
model load**, not the recognizer: `model-ja` takes seconds to open, `ReadVRUResults` waits
250 ms, and the reply comes back empty. `vru_recognizer_grammar_ready()` is what the selftest
waits on, the way a game has sent its list long before anyone talks. And **Japanese in a core
log arrives mangled twice**: libretro-godot widens each byte to a code point, and `ゅ` is UTF-8
`E3 82 85`, so its last byte becomes U+0085, a line break -- the line is cut there, and a
Python `splitlines()` cuts it again. Rebuild the bytes (code points below 256, plus cp1252 for
0x80-0x9F) and split on `\n` only.

```bash
"$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn
"$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn -- --only=faces
"$godot" --path RetroXR --resolution 900x700 --position 20,20 \
  res://Tools/models/n64_vru_render_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/input/vru_probe.tscn -- --root=<throwaway root> \
  --rom="<Hey You, Pikachu! or Pikachuu Genki de Chuu>" --leg=seated --speak=<48 kHz mono wav>
# in the fork
uv run tools/vru_render_ja_clips.py <clip dir>      # Open JTalk, pinned in the script
gcc -std=gnu99 -O1 -o vru_selftest tools/vru_selftest.c \
  custom/mupen64plus-core/plugin/vru_recognizer.c -Icustom -Icustom/mupen64plus-core \
  -Imupen64plus-core/src -Imupen64plus-core/src/api -Ilibretro-common/include \
  -Icustom/dependencies/vosk -Ilibretro -lpthread -ldl        # no -ldl on Windows
./vru_selftest <system dir> <english wav> <control wav> --ja-clips=<clip dir>
```

**Still owed.** Every utterance measured is synthesized speech, English from SAPI and
Japanese from Open JTalk, which is cleaner than any player; how well either model hears a
real voice is untested. Nobody has watched Pikachu obey on screen, in either language -- the
probe speaks during the opening, and what is proven is that the game asked for a word list
and got answers back. Densha de GO! 64 has not reached a word upload in a probe run: it wants
menu navigation first, so its table path is covered by the English selftest and not by the
game. The macOS jobs in `retroxr-release.yml` have not run -- the workflow runs on a tag or
by hand -- and a macOS RetroXR runs software-rendered cores only, so whether this core runs
there at all is untried. `core_sources.gd` names no Linux or macOS asset for this fork yet.
The speech pack download is measured on Windows only; the Android, Linux and macOS
libraries are chosen by `SystemAssetCatalog.library_part_id` from their zips' listings and
have not been installed through the app. Quest is built -- the arm64 library carries the
recognizer and resolves dlopen -- but unmeasured: libvosk is 8.9 MB and a loaded model about
300 MB, `model-ja` included. A pack installed while an N64 is running is not heard until
that machine is powered on again, because the recognizer tries the library once per load.

**The Dreamcast Microphone (HKT-7200) is built.** It fits either expansion socket on the pad
and has no button of its own: each game talks on a controller button, A in Seaman and Y in
Alien Front Online. Seaman will not start unless the pad is in port A with the VMU in socket 1
and the microphone in socket 2, which is why the core offers it in both.

**The device was already emulated and unreachable.** `maple_microphone` in
`core/hw/maple/maple_devs.cpp` speaks the whole protocol — 8000 or 11025 Hz, mono, read 240
samples at a time — but `StartAudioRecording`, `RecordAudio` and `StopAudioRecording` in
`shell/libretro/audiostream.cpp` were empty and `RecordAudio` returned 0, so the device
reported no samples for ever.

In the fork (`retroxr` branch):
- **One rule makes it safe:** the emulation thread never calls the frontend, takes a lock or
  waits. The three functions arrive there from inside maple DMA and only move atomics or drain
  a single-producer queue; every libretro microphone call belongs to the thread that runs
  `retro_run`, which is where the pump lives — outside the `retro_audio_upload()` branch,
  because that branch is skipped whenever the renderer is threaded and the rate unlimited.
- **Short reads are normal, not degraded.** 240 samples at 11025 Hz is 21.8 ms, longer than a
  frame, so a game polling once a frame structurally cannot get a full read. That is what the
  protocol's count byte is for, and it is why nothing here ever waits for more.
- **The frontend is asked for 48000 and the rate conversion happens in the core.** Asked for
  11025 it would decimate with no filter at all, folding a 9 kHz component back to 2025 Hz at
  full amplitude — onto the formants of the only two games that use this device.
  `MicrophoneResampler.h` is a windowed-sinc low-pass then interpolation between filtered
  samples: 95 taps for 11025 Hz, 133 for 8000.
- **The vendored `libretro.h` stops at environment call 74**, so `MicrophoneInterface.h`
  backports the definitions verbatim, guarded so the file empties itself the day
  `core/deps/libretro-common` is updated. The probe writes `interface_version` **going in**: a
  zero-initialised struct is refused, so the `probe_controller_interfaces()` pattern beside it
  would have failed silently.
- **`"Microphone"` joins both slot options**, across the table and all 43 translations. Those
  translated rows are generated from Crowdin upstream, so a future rebase onto master will drop
  them — the option keeps working, translated frontends lose the label.

In RetroXR:
- **`DcMicrophone` is a `JumpPack` clone.** A slot device costs no edits at all in `VmuPort`,
  `VmuStorage` or `system.gd`: those ask by method, so answering `slot_option_value()` with
  `"Microphone"` is the whole of the wiring. It carries the same origin rule as the card and
  the pack — a seat places an object's ORIGIN, so the connector sits at +42.5 mm.
- **The pads answer `seated_microphone()`, not `microphone_position()`**, and that distinction
  is load-bearing: `RetroSystem.microphone_position()` walks its port controllers for the first
  thing that can say where it hears from, so a pad that always answered would shadow a device
  that really is one — an N64 VRU in a later socket.
- **Power-on only**, like every slot device; the binding is read when the machine starts.

**Measured 2026-09-15** with `Tools/cores/dc_mic_probe` against Seaman (Japan, 2001 edition),
the pad in port A with a VMU in slot 1 and the microphone in slot 2. The game reaches its
microphone and switches it on, and the core says so:

```
[AUDIO] microphone: open, 48000 Hz from the frontend -> 11025 Hz for the game, 95 taps
```

with `maple_microphone::dma MDCF_MICControl` traffic either side of it and
`IsMicrophoneActive` true. **One leg per process**: `--leg=control` runs the same disc with
slot 2 empty, and the core neither opens a microphone nor prints that line.

That line is a WARNING rather than info on purpose — frontends drop everything below warn, and
it is the only way to tell a microphone a game is really using from one it was merely offered.

The core's own tests cover the two decisions that are easiest to undo later: a 9 kHz tone must
come out ≥40 dB down, which a filterless decimator fails at 1 dB, and the queue must never
hang, must bound its own latency and must drop what was queued before a savestate. The last of
those already caught a real defect — a drain that left a part-block behind, which would have
replayed pre-savestate audio into the game.

```bash
"$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn -- --only=dreamcast
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/cores/dc_mic_probe.tscn -- --root=<throwaway root> --rom=<a disc> --leg=seated
```

**Still owed.** Nobody has confirmed Seaman *understands* what is said to it — the game does
its own recognition, in Japanese, and what is proven here is that it opens the device and
receives audio at the rate it asked for. Alien Front Online is untested. Two microphones share
one stream, because `RecordAudio` carries no device identity: right for Seaman, wrong for a
multi-microphone game, and fixing it means changing shared core API. Quest is unbuilt for this
fork so far.

**The Famicom Controller II microphone is a BIT, not a capture device**, and that one fact
decides everything below. It is part of player 2's pad, where Start and Select are on Controller
I, and reaches the console at `$4016` bit 2 as an instantaneous one-bit threshold detector
sitting on the waveform:
- **The bit flickers between 0 and 1 while there is sound** and is a steady 0 in silence; the
  volume slider turns it off at far left.
- **Games look for the flicker** (Bokosuka Wars is strict about it). Zelda's Pols Voice, Hikari
  Shinwa's haggling (with A held on pad 2) and Takeshi no Chousenjou's karaoke use it.
- **The AV Famicom's second pad and the NES have no microphone.**

| core | where the mic is | when | the bit |
|---|---|---|---|
| nestopia | port 0, L3 | always | steady while held — a frontend must toggle it |
| mesen | port 0, L3 (mapped to player 2's mic) | only when Mesen decides the game is a Famicom: its database tag, FDS, Dendy, or an expansion device | pulsed one frame in three by the core |
| fceumm (fork) | **port 1's Start** | `fceumm_famicom_microphone` | toggled by the core on every `$4016` read while held |

**Why the fork, and why Start.** fceumm had no microphone at all (libretro-fceumm#521), and it
is the core that matters most here: the Android default, the only netplay-verified NES core and
the FDS boot core. Nestopia and Mesen both put the microphone on port 0's L3, which is
unavailable in fceumm — `bindmap[]` already gives L3 to A+B and R3 to Turbo A+B. Port 1's Start
is free AND hardware-correct, because a Controller II has no Start to lose.

In `C:\Users\rymcc\libretro-fceumm`, branch `retroxr`:
- `JPRead` nullifies player 2's Start at `$4017` while the option is on, and toggles bit 2 at
  `$4016` while the frontend holds the button. Two fixes against fceux, which fceumm forked
  from: the bit is set at `$4016` ONLY (fceux reports a microphone to `$4017` as well), and
  `MicBit` is in `FCEUCTRL_STATEINFO`, so a state restored mid-flicker does not resume on the
  opposite phase.
- `joy_readbit` is post-incremented, so the read that just delivered Start (bit 3, `JOY_START`
  is `0x08`) leaves the counter at **4** — that is why the nullify tests `== 4` and not `== 3`.
- The engage line is `log_cb` at **WARN** and only on a change. `FCEUD_Message` logs at info,
  which libretro-godot drops, and this is the only way to tell a microphone that is really live
  from one merely offered.
- Not guarded against a Four Score, which reassigns what `joy_readbit` counts. A Famicom
  microphone and an NES four-player adapter are not a combination any game asks for.

**The level is measured in C++ and is deliberately STATIC.** `Libretro.MeasureMicrophoneLevel`
(`libretro-godot/src/MicrophoneLevel.hpp`) returns the `(rms, peak)` of a block of host frames,
high-passed at 80 Hz and mixed to mono. GDScript cannot visit 800 frames a tick. It is not a
method on a running machine because **fceumm opens no microphone**: there is no handle to hang a
level off, and `IsMicrophoneActive()` never goes true for a Famicom, so a capture service that
asked only the core would never switch the device on for one. `RetroSystem.hears_microphone()`
answers that question instead, and `microphone_input.gd` measures **once per tick** and scales
per machine — rms and peak are both linear in the gain, which `tests/microphone_level_test.cpp`
pins, and that is what keeps the one-reader rule.

Two properties of the measure worth knowing. The high-pass is **seeded from the block's own
first sample**, so it starts matched to the signal and a block boundary contributes no step of
its own — that is what makes a stateless per-block measurement correct, and removing the seed
makes a tone measured over a DC offset read several per cent loud. The filter's OUTPUT still
starts from rest, so a tone already running when a block opens overshoots its amplitude by about
5% in `peak`, once; removing that would mean carrying state between blocks.

**In RetroXR:** `famicom` is a systemid of its own now, where it used to collapse into `nes`.
- `SystemInfo/famicom.tres`, a `model_registry` row, both icons (the theme's `HVC-001` file and
  the NES's `(J)` cartridge — see `Textures/SystemIcons/ATTRIBUTIONS.txt`), and rows in
  `romm_platforms`, `screenscraper_systems`, `ra_consoles`, `core_recommendations`,
  `media_dimensions`, `netplay_cores` and `spawn_catalog`.
- **The tile comes from the core-info overlay**, not from any of those: a systemid reaches the
  browser through `CoreInfoDatabase`, so `libretro-core-info-retroxr/fceumm_libretro.info` adds
  `famicom` to `secondary_systemids`. That same declaration is what gives a spawned Famicom a
  core at all — the Cores panel walks `systemids_of()` and adopts a first default for every
  platform an installed core serves.
- **`famicom_primitive.tscn`** is the HVC-001 at 220 x 150 x 60 mm: a dark red base the full
  width, a cream deck 114 mm wide on the middle of it, and the two 53 mm strips of base left
  either side as the controller wells. 114 + 53 + 53 is the whole width, which is why the
  machine has almost no wall between a cartridge and a controller, and why the cartridge mouth
  is simply the gap between the deck's front and rear blocks.
- **The pads are HARDWIRED, as they are on the machine.** Both cords leave the back through a
  grommet at each rear corner and there is no socket to unplug. `RetroSystemModel.captive_
  controllers()` names the two scenes and `captive_controller_rests()` says where they lie;
  `RetroSystem._spawn_captive_controllers` builds them with the console, seats each in a port
  and then LOCKS that port, hiding its recess and number. Everything downstream is unchanged —
  bindings, netplay and the core still see two ordinary port controllers.
  - **`RetroController.captive` keeps them out of the `"spawned"` group**, which is the whole
    reason the flag exists rather than a hidden port: persistence and object sync both sweep
    that group, so a captive pad a save could see would come back as a SECOND pad on every load.
    `RetroSystem._exit_tree` frees them and their cords instead, the way it frees its own
    captive A/V lead. Set the flag BEFORE `add_child`, or the pad's own `_ready` joins the group
    first.
  - **The plug mesh is hidden too.** A hardwired cord has no connector: the rope ends inside the
    grommet, and hiding the plug is also what puts it out of a hand's reach. A hidden plug has
    no moulding for the cord to leave BY, either, so `retro_controller.gd` gives a captive cord
    `end_anchor_offset = Vector3.ZERO` rather than the generic plug's `cable_anchor`: that boot
    offset is 40 mm of nothing here, and the cord ended in mid-air behind the machine.
  - **The two wells hold the pads MIRRORED, and the cord decides that.** A Famicom pad's cord
    leaves its far long edge (local -Z); turned lengthways into a 53 mm well that edge can only
    face the console's +X or -X, and the grommet each cord must reach is at its own rear corner.
    So the left rest is R_y(90) and the right R_y(-90), and each cord leaves over the OUTER wall
    of the well it lies in. Both turned the same way — which is what shipped — sent Controller
    II's lead inboard across the cartridge deck. The price is that the two pads face opposite
    ways lengthways, which is what a mirrored pair of wells does to a flat object.
  - **A stowed cord has to be LAID, not left to the rope.** `VerletRope._init_points` draws a
    straight line between its two anchors, and a stowed pad's boss is ~130 mm from its grommet
    while the cord is a metre long — so every particle starts at a seventh of its rest length
    and the solver spends the rest putting it somewhere. In a void it stands the cord up in
    arches over the machine and sleeps in them; on a desk it flings the spare out sideways and
    it comes to rest sprawled round the FRONT of the console, 120–180 mm past a front face at
    75 mm. `RetroSystemModel.captive_cord_routes(length)` answers with a polyline per cord —
    over the side of the well, down to the surface, round the rear corner, the spare coiled
    behind the machine, back into the grommet — which `RetroController._lay_captive_cord`
    resamples at equal arc length onto the particles and hands to `restore_points`.
    - **The coil's turns must clear `collision_radius` × 2, or the cord never sleeps.**
      controller_cable.tscn self-collides at 0.0036, so turns laid closer than 7.2 mm push each
      other apart for ever: four turns of a metre of cord sat 7.4 mm apart and crept across the
      desk all session at 0.13 mm a tick. Three turns sit 15 mm apart and the pair is asleep
      about 800 ticks after the lay. `_COIL_MAX_TURNS` is that cap.
    - **Measure the ROUTE for anything the route decides.** Where the spare ends up is decided
      by gravity and the desk, so a coil authored at deck height reads as flat a second later
      and a settled-height assertion cannot fail. `famicom_tests` asks the model for its routes
      and checks those; the settled cord is only asked the things settling cannot fix (it ends
      at the grommet, it is laid at about its own length, it never comes round the front).
  - **Each well is a snap zone, so a pad goes back in.** `RetroSystem._build_controller_well`
    puts one at each rest — the transform IS the rest, measured: a pad carries no snap grab
    point, so a zone seats one at its own basis. `snap_require = "hand_held_device"` (a zone
    with none never lights a ghost and no ray grab can reach it) plus a filter bound to the ONE
    pad that came out of that well, because a cord reaches its own rear corner and no other.
  - **Both scenes carry `cable_length = 1.0`** rather than the 1.80 m every other pad inherits
    from controller_cable.tscn. No dimensioned figure for an HVC-001 cord was found in a
    primary source; the Famicom's hardwired cords are famously short (Old School Gamer says
    18 in, against an NES lead "three times that length"), so a metre is an estimate made from
    that and from the reach a player needs to a console standing on a table. One constant.
  - **The order is load-bearing.** Controller I is port 1 and Controller II port 2, because the
    core reads the microphone off `joy[1]` alone — a Controller II built into player one's port
    would have no microphone at all.
- **One socket, and it is not composite.** The HVC-001's rear panel carries AC ADAPTER,
  TV/GAME, CH1/CH2 and RF SWITCH, and nothing else; everything the machine puts out goes down
  that one coax to the RXR-003 switch box and into the set's aerial socket. So
  `av_port_channels()` is `[VIDEO]` — the channel an RF feed resolves as everywhere in this room,
  the same thing the NES's own RF OUT says — and the built port is renamed `RfOut`, so a cord
  reads the same in a save on either machine. Listing a channel at all is also what stops the
  cabinet spawning a captive composite lead, which this console has none of. `configure_av_legend`
  hides the generic plate: it reads "AV OUT" over a "VIDEO" jack, which is the one thing this
  panel is not, and the scene prints "RF OUT" on the panel's own black strip above the socket,
  where the real machine silk-screens its four labels.
- **An RF cord carries the SOUND as well**, which is what makes this machine audible at all.
  `RcaPort.rf_feed` marks a modulator output — one coax, picture and sound — against a baseband
  composite jack, which carries nothing an amplifier can use. `AvSource.resolve` applies that
  sink **after every link has been walked**, and only if no dedicated audio cord claimed the
  sound: a machine wired both ways is still heard through its phono pair, whichever order
  `AvGraph` returns the links in, and RF is what a machine with no audio socket has instead. A
  set demodulates it onto BOTH its speakers, unlike a mono phono cord, which is heard from the
  one speaker its input drives. The NES's own RF OUT is marked too, so an NES reached ONLY over
  RF gains sound it never had — the same latent gap, invisible for as long as every machine with
  a coax also wore a phono pair. `av_tests` `wiring/an RF cord carries the sound as well` pins
  both halves, and goes red if the RF feed is allowed to outrank an audio cord.
- **`FamicomControllerII` holds port 1's Start** through `SetJoypadExtraButtons` while the room
  is louder than the volume slider allows, and **does not flicker** — that is the core's job,
  and a pad that flickered too would only alias against the core's own toggle. It holds nothing
  at all when seated in port 1 (`drives_port`), because the core reads `joy[1]` alone: a
  Controller II in player one's port that held the bit anyway would have every noise in the room
  pressing Start and pausing the game.
- The slider's threshold falls **logarithmically** from a shout to near-silence so its travel is
  even in decibels, with hysteresis at `RELEASE` so a voice sitting on the threshold does not
  chatter, and its far left switches the microphone off as the real one does.

```bash
"$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn
"$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn -- --only=gate
"$godot" --headless --path RetroXR res://Tools/cores/famicom_mic_probe.tscn -- \
  --root=<throwaway root with cores/fceumm_libretro.dll> \
  --rom="Z:/roms/nes/Bokosuka Wars (Japan).nes" --leg=mic
```

`Tools/models/famicom_render_probe` renders the machine front, top and rear and prints the
pads' ports and groups — windowed, never `--headless`, which returns a correctly sized blank. It
spawns no pads of its own: both arrive with the console, and a probe that made its own would put
four in the room.

**Measured 2026-09-15** against Bokosuka Wars (Japan) on the forked core: the option reached
`fceumm.opt` and the core logged `Famicom Controller II microphone on -- player 2's Start is now
the noise you make`. The same ROM on an NES machine (`--leg=nes`) prints nothing and gets no
`enabled` key, which is the leg that makes the first one mean something. **Wipe
`<root>/core_options` between legs** — a core serialises its whole option set on shutdown, so
the Famicom leg leaves the key behind for the NES leg to read.

Three things this does NOT show, and one trap. **`SnapshotMappedRam()` is not an oracle here**:
it is read on the main thread while emulation runs on its own, so the frame it catches varies —
the same leg run three times gave two different digests, and the mic and quiet legs gave the
SAME one. A "the game reacted" check needs the emulation gated to an exact frame AND a ROM
driven to the moment it listens; 1800 frames of Bokosuka Wars is its title screen. **The pad's
own bit has not been driven into a game by a hand**, only through the same call the pad makes.
And **the Disk System still hosts on `nes`**: `ExpansionCatalog`'s `host` is single-valued, so
the Famicom Disk System is on the NES's card despite the name.

**`famicom_tests`** is 72 headless cases over the threshold curve, the gate and its hysteresis,
the C++ measure read back from GDScript, the service's one-measurement fan-out, the port rule,
both pads, the captive pair the console builds, and every table row. Mutation-tested: making the
microphone drive any port, ignoring the slider's off position, dropping the distance scaling, or
letting a captive pad join the `"spawned"` group each fails exactly the cases that name them. It also waits for `ModelWarmer.is_warmed()` before quitting — SceneManager's boot
warm fires four process frames in, and a suite short enough to quit mid-warm prints a screenful
of parse errors from a loader thread as the class cache goes away.

**Others.**
- **Wii Speak and the Logitech USB microphone** are Dolphin options: `dolphin_wiispeak_enable`
  (with `dolphin_wiispeak_muted`, muted by default) and `dolphin_wii_logi_microphone_enable`.
  No source names a particular USB port.
- **The 3DS** listens through `citra_input_type=auto` or `frontend`.

**Still owed.**
- **A game answering the player.** There is no microphone-reading ROM here for any of these
  machines, so the probes prove the device, the handles and the hot swap — not Pikachu, a Pols
  Voice or a Mario Party minigame.
- **Netplay carries no microphone.**

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

**`PER_CORE_SYSTEMS` is `nintendo_64`, `nintendo_64dd` and `fds`**, and each is a measured
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
`nintendo_64` from the table, reversing the collision order, dropping the core from a clock's
name, or letting a delete take a lookalike save's clock each fails exactly its own cases.

### 2q. N64 cartridges — two regional bodies, a moulded colour, a scraped sticker

`RetroCartridge` builds an N64 cartridge from `imported-assets/carts/nintendo_64/`:
`n64_cartridge_usa.glb` (North America and PAL, which share a shape) or
`n64_cartridge_jpn.glb` (Japan's rear notches and latches). `N64CartShell` picks:

- **The body** from the market: the scraper's `region` for the ROM in
  `gamelist.json`, else the header's country byte at 0x3E.
- **The shell** from `N64CartColorsTable`, generated by `Tools/gen_n64_cart_colors.py`
  from micro-64's workbook (http://micro-64.com/database/ColouredN64Cartridges.xlsx)
  and mupen64plus-libretro-nx's ROM database. A game the table does not list is grey.
- **The sticker**: the scraped `media/label/<rom>.png` is painted onto the GLB's own
  UV-mapped `Label` mesh by `CartridgeLabel.apply_texture`, not laid over it on a quad.

**The bodies carry no mark**: no logo mesh, material or normal map, the moulded oval
left blank, and rear stickers keeping their warning text without the emblem, the
wordmark or a Nintendo copyright line. `n64_cart_tests` `branding/` fails if one comes
back; put the branded body in and it names `Nintendo_SVG_Relief`, `Nintendo_Molded_SVG`
and the recess normal map. They are 16,217 (USA) and 16,345 (Japan) triangles, and the
LODs are Godot's own (`meshes/generate_lods`): four levels on the front shell, three on
the rear shell, latches, board and mouth shield.

**A local ROM is looked up by header, never hashed.** The key is the header's CRC
pair plus the market (`"EC7011B7-7616D72B:us"`), 64 bytes in any byte order: 0.05 ms
against 105 ms for an MD5 of a 32 MB ROM on an SSD, and 13 s cold over a network
share. **The CRC pair alone is not an identity**: it does not cover the country byte,
and Ocarina of Time's USA and Japan releases share one, so a CRC-only table colours the
Japanese cartridge gold. `--check <rom dir>` hashes every candidate whole and fails
if MD5 and header ever disagree; measured 2026-09-17 on a 966-ROM No-Intro set, 126
candidates, 63 coloured, 0 disagreements. `N64CartShell.preset_for_md5` is there for
RomM rows, which report an MD5.

The workbook's shapes: `Grey/Blue` is a coloured run with a grey reissue (the release
is blue), `Yellow/NFR Grey` a coloured retail run and a grey not-for-resale one,
`Gold AUS/Grey PAL` a PAL ROM whose Australian run was gold. Australia shares Europe's
ROM, so that colour comes from `AUSTRALIA_*` only when the market is `au`. NFR and
reissue greys share the retail ROM and cannot be told apart by any hash.

**`CartridgeColor` recolours a shell**, on any node above the GLB:

```gdscript
CartridgeColor.apply_preset(cart, &"gold_silver")          # Pokemon Stadium 2
CartridgeColor.apply_color(cart, Color("#24479a"))
CartridgeColor.apply_two_tone(cart, &"black", Color.YELLOW)  # a Color or a preset id per half
CartridgeColor.reset_to_default(cart)
CartridgeLabel.apply_file(cart, "user://label.png")         # independent of the shell
```

- **Exterior plastic is found by material name** (`Shell_Plastic`,
  `Molded_Smooth_Plastic`, `Nintendo_Molded_SVG`) and **its half by the mesh that owns
  it**, not by material: `Front_Shell` and `Rear_Shell` SHARE one `Shell_Plastic`
  instance in the GLB, so painting by material would repaint both halves. Both
  `Bottom_Latch_Tongue`s belong to the rear half, as would a moulded logo patch
  (`Nintendo_SVG_Relief`), which the shipped bodies no longer carry. The mouth lining
  (`Mouth_Black`), its metal shield and the board keep their own materials.
- Each painted surface gets its own duplicate, cached in the mesh's metadata with the
  override it had before, so switching presets allocates nothing after the first
  time and a reset restores exactly what was there — including an override someone
  else set first.
- **`ModelMaterialFix.demetal` must not run on this model** (`_AUTHORED_MATERIALS`
  in `cartridge.gd`): its contacts and security screws are real metal, and the pass
  would flatten them to plastic.

**Presets are `Resources/n64_cartridge_shells.tres`**, editable in the inspector. Every
colour is a visual approximation — the source names colours, never values — sampled from
micro-64's photographs, white-balanced against the backdrop. `availability` tells
apart STANDARD grey, RELEASED colours, and OFFERED_ONLY ones no commercial cartridge
used (emerald green, pink, beige, dark and medium grey), which are estimates.

**Gold and silver are metal-flake plastic**, `Shaders/cartridge_flake_plastic.gdshader`:
flakes in object-space cells with random tilt, sparkling through the ordinary PBR lobe,
so only light and view move them. Two things it took:

- **A flake smaller than a pixel is replaced by its average**, which is its volume
  fraction, density x (4/3)pi r^3 = 0.058 x density. The first build used 0.16 and a
  gold cartridge across a room read as cream.
- **A flake is never fully metallic** (0.7). A fully metallic centre loses its diffuse
  and reflects whatever is behind the camera, so every flake rendered as a bright ring
  with a black middle.

```bash
python Tools/gen_n64_cart_colors.py                       # regenerate the table
python Tools/gen_n64_cart_colors.py --check Z:/roms/n64   # prove it against real ROMs
"$godot" --headless --path RetroXR res://Tests/n64_cart_tests.tscn
"$godot" --path RetroXR res://Tools/models/n64_cart_color_demo.tscn    # interactive
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/models/n64_cart_color_demo.tscn -- --out=<dir> [--stills] [--rom=<file.z64> ...]
```

**A normal-mapped triangle with no UV area shades black, and only on some faces.** As
exported, 96% of the front shell's area had every UV at (0, 1), so the plastic grain
had never shown on the front half, and a 2.4 mm strip down each side drew as a dark
band, navy in the bedroom and black in the arcade. With no UV area there is no
tangent; Godot falls back to one along +X, and on a face whose normal is also along X
the two are parallel, orthogonalising leaves nothing, and the face takes ambient light
only. Every other unmapped face pointed somewhere the fallback still works, which is
why it was one strip and not the whole shell. `Tools/glb/fix_unmapped_uvs.py`
box-projects such triangles at the rear shell's 12 mm tile, splitting a vertex shared
between projections, and moves no position, normal or already-mapped UV;
`n64_cart_tests` `uv/` fails on a body that needs it (the unpatched one names
`Front_Shell: 4914`). **Run it on any re-exported body.** Three reads of that band
were wrong first: the connector mouth, a shadow, and the generated LODs. What found it
was toggling `normal_enabled` on one shell in a macro render.

```bash
python Tools/glb/fix_unmapped_uvs.py <body.glb> --check    # exits 1 if it needs fixing
python Tools/glb/fix_unmapped_uvs.py <body.glb>            # rewrites in place
```

**Still owed:** the flake shader has not been measured on a Quest; the extracted
textures import lossless, 4096 x 2000 rear stickers included, and the grain and
blank-label maps are stored once per region.

**A player can force both at spawn.** A ROM row in the spawn menu held for two
seconds opens a sub-menu instead of spawning (`HoldPress`,
`Scripts/UI/widgets/hold_press.gd`; a short press still spawns as before): Body is
Auto / USA-PAL / Japan, Shell is Auto or any palette preset grouped by
`availability`. The choice lands on `RetroCartridge.shell_preset` and
`body_region`, set before the cartridge enters the tree. A forced body changes the
SHAPE only -- the colour is still looked up under the ROM's real market, so a
Japanese body on Ocarina of Time USA stays gold -- and a preset id the palette does
not hold falls back to the ROM's own. Neither is saved for a cartridge left alone,
because both are derived from its ROM; a forced one writes `shell_preset` /
`body_region` into its entry, which is also what object sync sends.
`n64_cart_tests` `forced/` and `spawn_menu_tests` `hold/` cover it. **`HoldPress`
listens to the button's own `pressed`, and a pooled ROM row sweeps every listener
off that signal on each bind** -- `_bind_rom_row` calls `ensure_connected()` after
the sweep, and `reset()` so a row rebound mid-hold forgets the last entry's press.

### 2r. Surround sound — a matrix decoder, six mono voices, and a phono row

Every sound in this room is two channels wide end to end: libretro's audio API is hard
stereo (the word "channel" appears twice in 7,600 lines of `libretro.h`) and `vlc-godot`
asks libVLC for stereo outright. But the spatial layer is built the other way round — **a
Meta XR Audio voice is MONO** (`MetaXRAudioServer.hpp`), and the mixer renders one mono
point source to binaural per voice. So **surround here is more VOICES, not more
channels**, and `speaker_pair.gd` already stated the other half: a sink is two markers and
a volume number, and the SOURCE owns its voices and walks them onto whatever
`get_speaker_positions()` hands back, every frame.

**It decodes Dolby Surround and Pro Logic II rather than upmixing**, which is the whole
point: a large part of the library is genuinely matrix-encoded, so the decoder is
recovering authored content rather than inventing it. GameCube/Wii is the strongest case
(the DSP mixer has a Surround channel and the AX/JAudio ucode does PLII), then PS2, then
exactly 16 N64 titles, the ~12 known SNES Dolby Surround games, PS1, and Dreamcast via
OS r11.

**The decoder is FreeSurround** (Christian Kothe, GPL-2.0-or-later), vendored from
**Dolphin's** `Externals/FreeSurround/` into its own extension, `surround-godot/`.

- **Not `tygyh/FreeSurround`**, which looks like better provenance and is broken: it drops
  the `kiss_fft_scalar=double` override while leaving `cplx` at `std::complex<double>`, so
  its FFT writes 8-byte complexes into a buffer read as 16-byte ones. Nothing restores it,
  and its `exports.props` still points at a Dolphin path for a `.vcxproj` the repo does not
  contain — it has never been built. Dolphin's copy declares `lt`/`rt`/`dst` as
  `std::vector<double>`, which makes that same mistake a COMPILE ERROR; verified by
  mutating the scalar and watching the build fail.
- **Its own extension, for licence reasons.** `libretro-godot` is MIT and published
  separately as `github.com/RetroXR/libretro-godot`, so GPL code cannot live there;
  `metaxr-audio` links Meta's proprietary blob under the GPLv3 §7 permission in
  `LICENSE-EXCEPTION.md`, which is the user's to grant over their own code and NOT over
  Kothe's. So the decoder is pure DSP that knows nothing of Meta and nothing of libretro.
- **Patents are expired.** US6920223B1 (Fosgate/Dolby, priority 1999-12-03) reads
  "Expired - Lifetime", estimated 2019-12-03.
- **`matrix4` from `bmc0/dsp` was the runner-up, rejected for one reason**: it produces NO
  centre channel (2/2 and 2/4 only) and does not implement the PLII inverse. Better
  engineering on every other axis — time domain, no FFT, ISC, actively maintained — so keep
  it as the fallback if artifacts disappoint, and read its power-compensation contour
  regardless. Do not take `matrix4_mb`: it needs FFTW3.
- **Core-side decoding is a dead end**, instructively: Dolphin's `MixSurround()` calls
  `Mix()` to get *the same stereo buffer the core already sends us*, then runs FreeSurround
  on it. The matrix is in the stereo pair — that is what matrix encoding means — so the
  decode is identical either side of the wire. It would reach 2 systems of 58 against
  58 of 58.

**Name the formats in player-facing text, not in our branding.** The SURROUND position's
OSD says `SURROUND — DOLBY PRO LOGIC II`, because a game's own options menu says "Dolby
Surround" and there is otherwise no way for a player to tell that this is the switch that
decodes it. Dolphin ships a "Dolby Pro Logic II Decoder" setting, VLC ships
`channel_mixer/dolby.c`, FFmpeg documents `-matrix_encoding dplii`. What to avoid is
narrow: no Dolby logos or device marks, no claim of certification or endorsement, and the
marks are not OUR branding — the extension is `surround-godot`, the class is
`SurroundDecoder`, and the About panel carries the trademark attribution.

**Three latency figures exist and mixing them up is easy.** FreeSurround's *inherent* delay
is `N/2` — `buffered()` returns exactly that — so 10.7 ms at N=1024/48 kHz.
`af_surround`'s total input-to-output delay is a full `win_size`, double that, which is
where an "85 ms" figure comes from. Dolphin's "80 ms" is a third framing again, a
buffer-size equivalence. A *pipeline* figure legitimately sits above `N/2`, since
`decode()` consumes N frames at a time while batches are ~800 — but say which you mean.
**N = 1024**: Dolphin measured it as having less steering glitch and less crosstalk than
512, and `sample_rate/N` is the bin width per-bin steering exists to buy.

**How the extensions reach each other.** `libretro-godot` is built against a trimmed
godot-cpp (`Tools/godot_cpp_profile.json`, 53 classes) with **no `ClassDBSingleton`**, and
adding a class there forces a full godot-cpp rebuild for every extension. `Engine` IS in
that list, so `surround-godot` exposes a **`SurroundAudio` factory singleton** with
`create_decoder(block_frames, sample_rate)` returning a `RefCounted` — the same
arm's-length route `AudioHandler` already takes to the mixer: found by string, optional at
runtime, absent without error. **A decoder is not a singleton and the factory is not one in
disguise**: the STFT carries state across blocks, so every source that decodes needs its
own, one per machine and one per deck.

**Six voices are per-machine opt-in, not a global mode.** `kMaxVoices` is 32 and a machine
already costs 2 main plus up to 8 controller voices, so at 6 main voices five powered-on
machines is 30 of 32. `SetSurroundEnabled` takes the four extra only while a set asks and
hands them back when it stops; an exhausted mixer, an absent extension and the fallback
backend each answer false and leave the stereo path untouched. **Degrade to stereo, never
to silence.**

Four things in that path are load-bearing rather than tidy:

- **The front pair IS `m_voice_l`/`m_voice_r`.** The emulation brake and the rate trim both
  read the depth of `m_voice_l` (`QueuedFrames`, `MsUntilSinkWantsFrames`), so it has to be
  a voice surround actually feeds. The first build gave the fronts voices of their own and
  left `m_voice_l` unpushed: it read empty for ever, the brake never held the core, the
  trim leant fast, and the six crept toward their 32768-frame rings — a player heard the
  game most of a second late. (The two idle voices also underran every block, which
  doubled the probe's underrun count; that was the evidence, and it was explained away.)
  All six are pushed the same frames, so FL's depth is every channel's. Four new voices.
- **The six are kept LEVEL.** A queue is a delay, and the fronts carry the stereo backlog
  across the switch while the four new voices start empty: FL and FR played 12–18 ms
  behind the centre for the whole session. `LevelSurroundVoices` tops an EMPTY channel voice
  up with silence to the fronts' depth — which is also the state `AdmitOnFirstPose` leaves
  a voice in when it drops a backlog pushed before the pose arrived, so a discarded top-up
  is simply made again.
- **The decode is in `PushFrames`**, which is already past the resampler and the DRC rate
  trim. Dolphin found a block decoder and time-stretching together "produces bad sound".
- **A new controller voice is pre-filled to the main voice's depth PLUS the decoder's
  latency.** The game's sound is now held back a window, so without the addition a Wii
  Remote beep leads the game by exactly that.
- **`set_bass_redirection` is what produces an LFE channel at all**, not a nicety. Without
  it the sub is silent and the band stays in the fronts.

**The room half.** The set's back panel grows a second socket row of six phono jacks titled
`SPEAKERS` — FL, FR, C, SUB, SL, SR in the consumer analog-5.1 colour code (white, red,
green, purple, blue, grey) — **above** the input row, because the stock body's floor is at
-0.2 against an input row at -0.15: 50 mm below, 350 above, and a legend plate needs more
than 50. A shell claims the row by carrying a `SpeakerOutSeat` marker, and that marker's
absence is the switch, as `VgaPortSeat`'s is for the DE-15.

**`AvLegend` needed a per-channel word override for it.** The derived word for the centre
channel is "AUDIO CENTER", 29 mm at the authored text size against an 18 mm socket pitch,
so three of the six would have printed over their neighbours. All or nothing per plate: a
partial override would mix two conventions on one legend.

**Which channel a cabinet carries is decided by the socket its lead is in.** A phono jack
is generic; the panel it is screwed to names it. `RcaPort.Channel` gained
`AUDIO_C, AUDIO_LFE, AUDIO_SL, AUDIO_SR, AUDIO_SPEAKER` — **appended**, because the int is
written into saves and onto the wire — and `AvSource.resolve`'s `int(in_ch) - 1` arithmetic
was retired for an explicit `CHANNEL_SPEAKER` lookup, which only worked because
`AUDIO_L`/`AUDIO_R` happen to be 1 and 2. A cabinet's own input is `AUDIO_SPEAKER`, the
generic end that takes whatever the far socket was named.

**STEREO OUT and SURROUND send the sound to the speakers and leave the set silent**, as a
real set switched to external speakers does — so with nothing plugged in, nothing is
heard. The first build folded a missing channel back onto the set's own pair, and a player
with no speakers plugged in heard SURROUND perfectly well out of the television and took
it for broken. A missing channel folds onto the speakers that ARE plugged in, walking a
fixed chain per channel (`TvFit._FOLD_CHAINS`): its own side first, so a rig of rear
speakers alone still images left-right; the centre and the sub to the phantom midpoint
between a cabled pair; and every chain names all six outputs, so one speaker plugged in
gives every channel somewhere to go. A channel landing on a speaker already playing its
own comes in **3 dB down**; one landing on a midpoint does not, since nothing else plays
there. Folding is placing a voice where a speaker is, so not a sample is touched. `speaker_tests`
`fold/nothing ever folds onto the set's own speakers` is the case that goes red if the old
rule returns.

**`RetroTV.get_speaker_positions()` answers by mode**, which is what makes AUDIO OUTPUT a
property of the set: on TV SPEAKERS it is the set's own pair, on STEREO OUT and SURROUND
the pair FL and FR resolve to. A deck and the tuner, which do not decode, follow it with no
code of their own, and nothing aims along the screen normal while `is_sound_external()`.
**STEREO OUT was not wired at all before this** — choosing it changed nothing, and the
stereo pair went on playing from the set.

**The AUDIO OUTPUT key** on the bezel and the remote steps through TV SPEAKERS, STEREO OUT
and SURROUND, all three always: with no speaker plugged in the external two go silent and
the OSD says `STEREO OUT — NO SPEAKERS CONNECTED` or `SURROUND — NO SPEAKERS CONNECTED`,
naming the position so two presses do not read the same. That outranks `SURROUND NEEDS
SPATIAL AUDIO`, because it is why nothing can be heard at all. Glyph `0xF1120`
(`md-volume_source`), checked against the shipped font's cmap by a case of its own, because
`transport_glyphs.gd` records having shipped a guessed codepoint that rendered as a
clapperboard. Its cap is deliberately NOT `audio_mode`'s palette: the two sit in the same
bezel row and both wear a speaker, and at mode 0 / TV SPEAKERS they were the same blue on
the same symbol, which read as one control pressed twice.

**Omnidirectional whenever surround is engaged.** `update_position` aims the stereo pair
along the set's screen normal, which is right for sound leaving one cabinet; a rig
scattered round a room has no single baffle to point along and two of the six are behind
the listener. The distance law measures from the middle of the RIG rather than per cabinet,
so a player standing beside the sub does not take the whole mix with them — the per-voice
HRTF already carries the individual distances. **The LFE is placed but not treated
specially**: Meta's guidance is that a predominantly low-frequency source wants pan and
attenuation rather than the HRTF, and a matrix source carries no discrete LFE anyway (ours
is a synthesised sub-120 Hz band), so it costs a voice either way.

**Linux and macOS get no surround**, by the same line HRTF already falls on: `metaxr-audio`
does not ship there, so there are no voices to place.

**With Meta XR Spatial Audio switched off, the key says `SURROUND NEEDS SPATIAL AUDIO`**
and the set still holds SURROUND, so a machine powered on later takes it up. It used to
name the format regardless — a player pressed it, read "PRO LOGIC II" and heard nothing
change. The message trusts a machine that is decoding over `SpatialAudioListener`'s flag,
which goes stale if anything switches the SDK behind the listener's back. **The Options
switch used to hide itself once turned off**: it was gated on `is_available()`, which
answers false while the SDK is disabled, so it vanished on the next build of the page. It
is gated on `SpatialAudioListener.sdk_installed()` now — the library reported a version.
A machine keeps the backend it booted with, so turning the SDK on needs a power cycle.

Every TV button logs a line, `[RetroTV] TV: pressed AUDIO OUTPUT`, connected ahead of the
button's own handler so it lands first; the remote prints `[TVRemote] TV: pressed <key>`.
AUDIO OUTPUT then reports the outcome, and each machine its own verdict: `[SystemAudio]
<machine>: surround on, 6 voices` or `declined — spatial audio is off`.

**The cabinets and their stands.** `Tools/gen/gen_speaker.gd` bakes a satellite
(95 x 165 x 110 mm) and a subwoofer (260 mm cube); `Tools/gen/gen_speaker_stand.gd` bakes
1.2 m and 1 m floor stands, the height being to the top plate's upper FACE, which is where
a cabinet's own origin lands. A stand's seat needs **no snap grab point** — the one piece
`ExpansionPort` had to invent a foot for — because a loudspeaker is baked with its origin
at its base centre, so a zone whose origin is the plate's face stands the cabinet on the
plate with no offset. `Loudspeaker` joins a group of its own for the plate's
`snap_require`, because `can_preview` refuses to draw the snap ghost for a zone without
one. The STAND records what is on it rather than the cabinet recording the stand, and
putting a stand away drops the cabinet rather than freeing it.

**Two mesh traps this cost, and both are now checks that refuse to save.** `_check_outward`
cannot judge an open funnel — it reads -1 on an axis it is edge-on to whichever way it is
wound — so the driver surface went unchecked and **shipped inside out**: the cone's faces
pointed backwards, culling dropped them, and through the baffle hole the box's own interior
is back-facing too, so the line of sight went in the front and out the back. A player saw
the wall through the speaker. `_check_forward` asserts the one thing that IS true of a
driver: it is only ever seen from in front of the baffle, so not one face of it may point
backwards. And **the cone wall takes the OPPOSITE winding to the surround above it** despite
both running front-to-back — the surround is a convex bead seen from outside, the cone a
concave funnel seen from inside. Separately, `_check_outward` picking the FIRST vertex at an
axis extreme false-positives on a tapered column, whose side wall legitimately faces
slightly upward at its bottom; the stand's copy takes the best-facing of every vertex at
the extreme.

**The composite legend plates OVERLAPPED, and it was z-fighting.** A plate measures
63.1 mm and the group pitch was 60, so each neighbour overlapped the next by 3.1 mm — and
every plate sits at the same standoff, so the overlap was two coplanar quads fighting. A
comment in `tv_panel.gd` said the plate was 57.6 mm with 2.4 mm to spare, and that figure
was believed, twice: once when the pitch was chosen, and once when the seam was first
diagnosed here as two white strips minified together, which removed the group divider and
left the overlap standing. The stock body's groups now sit at a **68 mm** pitch, 4.9 mm
clear, and `av_tests` `wiring/no two legend plates on the back panel overlap` measures the
plates the legend actually built — it went red on all three composite seams at 60 mm.
**Measure a printed width; never read one off a comment.** The divider stays gone: it
added nothing the plates' own borders do not already say.

**A speaker cable's plugs can be spawned in a colour.** The lead is neutral grey
because its channel belongs to the socket, not to it -- but six grey plugs behind a
set are hard to tell apart, so holding the Speaker Cable row for two seconds
(`HoldPress`, §2q) offers `RcaJack.PLUG_COLORS`. The menu sends
`speaker_cable:<id>`, the controller sets `CompositeCable.plug_color_id` before the
lead enters the tree, and `_cord_color` answers with it for every cord. Plugs only:
the jacket stays `wire_color`. The id is saved as `plug_color`, absent for a lead
left alone, and an id the table does not hold leaves the scene's grey. It changes
nothing about routing. `speaker_tests` `save/a lead keeps the plug colour it was
spawned in`.

**Binning a lead re-seated its plugs.** `CompositeCable.drop_and_free` releases every plug
IN PLACE, still standing in the panel, and every empty socket whose grab sphere the plug
body reaches takes it on the deferred `dropped` — the lead is freed at the end of the
frame, so those sockets end up holding freed plugs. Binning a lead from Composite 2 seated
its trio into SUB, SL and SR, 60.3 mm above; headless, the same case seats three input
sockets instead, so the speaker row exposed it rather than caused it. Every plug is now
disabled before the drop: `can_pick_up` refuses a disabled pickable and `let_go` does not
ask. `speaker_tests` `routing/binning a lead seats none of its plugs anywhere` counts
`has_picked_up` rather than reading state afterwards, because once the lead is freed a
socket holding a freed plug and an empty one both answer `is_instance_valid` false.

```bash
"$godot" --headless --path RetroXR res://Tests/speaker_tests.tscn
"$godot" --headless --path RetroXR res://Tests/speaker_tests.tscn -- --only=fold
python Tools/build.py windows --only surround-godot
cd surround-godot && python tests/run_tests.py     # 24 assertions, no Godot
"$godot" --path RetroXR --resolution 900x900 --position 20,20 \
  res://Tools/models/speaker_render_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 1320x600 --position 20,20 \
  res://Tools/av/tv_back_panel_probe.tscn -- --out=<dir>
"$godot" --path RetroXR --resolution 320x240 --position 20,20 \
  res://Tools/av/surround_probe.tscn -- --root=<libretro root> --core=fceumm --rom=<a ROM>
```

`speaker_tests` is 130 headless checks: `faces/`, `jack/`, `routing/`, `fold/`, `output/`,
`stand/`, `save/`. Mutation-tested — folding the surrounds to the midpoint, dropping the
3 dB, and a panel that never resolves each fail exactly the cases that name them.

**Latency and level are measured, not assumed.** After the feed check the probe takes the
surround depth twice and fails if it GREW by a decoder block or more — a snapshot cannot
see a creep, and the first latency check passed with the brake broken because five seconds
in the depth was still under any threshold. It then fails on more than one mixer block of
skew between the six. `--soak=<seconds>` samples the front voice every frame by the CLOCK
and fails on an upward trend between the first and last quarter. Frame counts are no clock
here: sharing the machine with a running game, the probe ran at 6 fps, so its "5 s" wait
was fifty. Measured 2026-09-18 after the fix: 55 ms stereo against 68 ms surround, 0 frames
of skew, and a 90 s soak at 54 ms then 53. Pass `--log-file` to a probe run while the
player is in a session, or it rotates their logs away.

**`surround_probe` is WINDOWED, never `--headless`**, and it carries a **stereo positive
control in the same run**, which is the only reason its numbers mean anything: an earlier
run read 0/6 voices fed and looked exactly like a broken decode, and the control then read
0/2 — the machine was silent for reasons that had nothing to do with surround. Measured
2026-09-18 with fceumm: stereo peak depth [1593, 1593] 2/2 fed, surround [2048 x6] 6/6
fed, the centre channel on its own cabinet, the two uncabled surrounds 3 dB down, and the
four extra voices handed back on the way out. Under `--headless` the SDK reports itself
unavailable, so there are no voices at all; and it is `mx.set_enabled(true)` that turns the
SDK on for a probe's own run, NOT `AppPrefs.spatial_audio_sdk`, which
`SpatialAudioListener` applies at BOOT. It also has to stand the cabling in at BOTH ends:
the real captive lead comes from the machine's model, which never spawns in a bare probe
scene, and the machine's OWN routing field is the load-bearing half — without it
`update_position` has no set, the voices are never posed, and `AdmitOnFirstPose` drops the
backlog of a voice that has never been placed.

**Still owed.**
- **Nobody has LISTENED to it**, on a Quest or anywhere. That is the acceptance test for
  the whole feature: Wind Waker or Metroid Prime (GC, PLII), one of the 16 N64 titles, DK64
  (which offers surround in its own options menu), Donkey Kong Country (SNES Dolby
  Surround). A centre-panned voice must come from the centre cabinet and a rear-encoded
  effect from the rear.
- **libVLC still asks for stereo**, so the DVD player and the VCR get no discrete 5.1 and
  the decks' `SpatialAudioEmitter` path is not wired for six. The libretro half — 58 of 58
  systems — is what is done.
- **No CPU measurement on a release build.** The per-bin loop runs N/2 bins at ~13
  double-precision libm calls each and is at least as expensive as the 16 transforms per
  block, so the performance order (float first, then hoist the transcendentals, then swap
  KissFFT for PFFFT) rests on a guess at which dominates rather than on a number. Upstream
  KissFFT has no NEON path at all — `USE_SIMD` covers SSE and LoongArch only — and the
  vendored copy is `double`.
- **Mono content pays six voices**, accepted deliberately. NES, Game Boy and Master System
  are mono at the hardware, so every decoder degenerates to "mono in the centre" — and six
  HRTF paths on a near-pure square wave is where comb filtering is most audible. If a
  player reports NES audio sounding hollow or phasey, an `L ~= R` correlation bypass is the
  cheap fix and this is the first thing to revisit.
- **QSound-era Capcom titles get double-processed**: QSound is pre-baked
  crosstalk-cancelled positional audio, not matrix surround, so decoding it and applying
  HRTF violates its assumptions twice over.
- **Netplay carries only the `audio_out` position**, not audio, which is right: each peer
  decodes its own, because each peer's speakers are in its own room.
- 7.1 (`cs_7point1`) would extend cleanly and nothing needs it.

### 3. Capturing a real screenshot on Linux (for visual validation)
`--headless` uses the dummy renderer — it **cannot** produce a screenshot (a probe that awaits
`RenderingServer.frame_post_draw` just hangs; `get_image()` is blank). To actually render a
RetroXR scene on this box, run Godot **on the real display** (`DISPLAY=:0`,
Vulkan Forward+ — a window briefly appears on the desktop, ok'd for validation) and draw into a
**`SubViewport`**, not the window viewport (the uncomposited window swapchain reads back as
clear-colour only). Xvfb does not work here (bwrap/glycin abort in the sandbox). Recipe:
```gdscript
var sv := SubViewport.new()
sv.size = Vector2i(1000, 750)
sv.own_world_3d = true
sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
add_child(sv)   # add WorldEnvironment + DirectionalLight3D + your scene + Camera3D as children
cam.current = true              # make_current() does NOT work inside a SubViewport
for i in range(8): await get_tree().process_frame
await RenderingServer.frame_post_draw
await get_tree().process_frame
sv.get_texture().get_image().save_png("res://shot.png")
```
Run `DISPLAY=:0 "$godot" --path "$proj" res://shot.tscn` (import first with `--headless … --import`).
Then **surface the PNG inline via the Read tool** — the user sees it through the Claude app (the
terminal itself doesn't paint it). Don't save renders to a folder; delete the probe + PNG when done.

## On-Device Testing (Quest over adb, nobody wearing the headset)

The Quest 3 usually sits on the desk on USB (`adb devices` → authorized; USB keeps it
charged). RetroXR can be exported, installed, launched, and probed on it fully
unattended. Verified end-to-end 2026-07-06 (x64↔arm64 netplay determinism run).

In Git Bash, `export MSYS_NO_PATHCONV=1` first or `/sdcard/...` args get mangled into
`C:/Program Files/Git/sdcard/...`.

### Export + install
```bash
"$godot" --headless --path "$proj" --export-debug "Quest" out.apk
adb install -r out.apk        # -r keeps app data
```
- **Stale-script trap**: the gradle export can silently ship an old compiled script —
  `RetroXR/android/build/src/main/assets/**.gdc` is not always re-staged after a source
  edit. If an on-device change doesn't take: `rm -rf RetroXR/android/build/src/main/assets
  RetroXR/android/build/build/intermediates/assets` and re-export. To verify before
  installing: a `.gdc` is a 12-byte `GDSC` header + zstd; decompress with Python 3.14's
  `compression.zstd` and grep the payload for a string you just added.
- `FileAccess.file_exists("res://….tscn")` is **false in exported builds** (paths are
  remapped into the pck) — use `ResourceLoader.exists()`.

### Launching with no one wearing it — ALL three are required
```bash
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close   # fake "worn"
adb shell setprop debug.oculus.guardian_pause 1                  # else a Guardian dialog blocks
adb shell monkey -p com.xenu.retroxr 1                           # GodotApp isn't exported; am start = Permission Denial
```
- The manifest must declare `oculus.software.handtracking` or the shell blocks with a
  controllers-required dialog (controllers are off/dead). That needs BOTH the export
  preset `meta_xr_features/hand_tracking=1` AND project.godot
  `xr/openxr/extensions/hand_tracking=true` — the vendors plugin only injects the
  manifest feature when the OpenXR project setting is on (enabled since b9f1481).
- If an OS dialog is showing, the launch is **cached** and fires once it clears
  (`adb shell input keyevent KEYCODE_BACK` can dismiss).
- Cleanup when done: `guardian_pause 0`, broadcast `prox_open`, `am force-stop`.

### Paths on device
- `user://` = **internal** `/data/user/0/com.xenu.retroxr/files/` — readable/writable via
  `run-as com.xenu.retroxr` (debug builds). Cores + system dirs live there
  (`files/libretro/…`, populated by the in-app CoreDownloadManager).
- ROMs/books/videos live on the **external** dir `/sdcard/Android/data/com.xenu.retroxr/files/`
  (plain `adb push`/`ls` works there).
- **Never `adb push` over a file, or into a directory, that the app itself writes.** The
  app is `other` for everything `shell` creates in its own tree, and no chmod fixes that
  sanely. Confirm the group list before theorising — `cat /proc/$(pidof
  com.xenu.retroxr)/status` reports `Groups: 3003 9997 20198 50198`, i.e. `inet`,
  `everybody`, `<uid>_cache` and `all_a<uid>`. **`ext_data_rw` (1078) is not among them**,
  and it is the group on every `adb`-created file and directory here. Owner is `shell`,
  group is unreachable, so only the `other` bits apply:
  - `adb push` lands a file `0644` — other `r--`. The app can read it forever and can
    never overwrite it. Fine for ROMs, fatal for state files.
  - `adb` creates directories `0770` — other `---`. The app cannot create anything inside
    one, so a system folder made by push gets no `.romm/` index. `romm_catalog.gd` ignores
    the return of `make_dir_recursive_absolute`, so this surfaces one line later and one
    level down as "Cannot write to …/nintendo_64/.romm".
  - Granting the app access through the bits alone would mean `0666` on files and `0777`
    on directories, because the group is useless to it. Don't. Let the app own what it
    writes: delete the pushed copy and let it be recreated in-app.
  - **`chmod 660` is actively harmful here** — it clears the `other` read bit the app was
    relying on, and grants write to a group the app is not in. A config the app can no
    longer read looks exactly like a config that was wiped.
  - Diagnose by owner, not by logs, and never with `run-as com.xenu.retroxr test -w …` —
    that shell does not get the app's storage mount view and reports NOT-WRITABLE for
    files the app demonstrably just wrote. The reliable tell is that every `.romm/` on the
    device is owned by the same uid as its parent directory, never a mix.
- Extra cores: same source the app uses (core_download_manager.gd) —
  `buildbot.libretro.com/nightly/android/latest/arm64-v8a/<core>_libretro_android.so.zip`.

### Running the netplay determinism spike on-device
`Tools/netplay/netplay_spike.tscn` reads its `--spike-*` args from `user://spike.cfg`
(one per line) when there are no command-line args, and deletes the cfg immediately so
a crash can't wedge the app. Nothing boots the probe automatically any more — the cfg-file
hooks in NetworkManager and the `run/main_scene.<feature>` probe presets were removed
2026-09-09 — so the scene has to be the one launched (a probe-only export, or a desktop run).
```bash
printf -- '--spike-core=fceumm
--spike-rom=/sdcard/Android/data/com.xenu.retroxr/files/roms/nes/ROM.nes
--spike-root=/data/user/0/com.xenu.retroxr/files/libretro
' > spike.cfg
adb push spike.cfg /data/local/tmp/
adb shell "cat /data/local/tmp/spike.cfg | run-as com.xenu.retroxr sh -c 'cat > files/spike.cfg'"
```
Then compare the `[crc]` lines against a Windows spike run.

### Log capture
The logcat ring buffer rotates away in **under a minute** (VrApi spam) — poll-grepping
loses boot output. Stream from before the launch instead:
```bash
adb logcat -c && adb logcat -s godot:* > quest.log &
```

## CI

Three workflows in `.github/workflows/`:

- **`tests.yml`** — the gate. Builds the seven GDExtensions for windows x86_64 debug via
  `python Tools/build.py windows --target debug`, installs Godot, imports the project,
  fails on any script or shader error, then runs `python Tools/run_tests.py`.
- **`release.yml`** — `preflight` → `quest` + `windows` → `release`, on a tag push or
  `workflow_dispatch`.
- **`sidequest.yml`** — the SideQuest listing.

Because `tests.yml` runs `Tools/run_tests.py`, which globs `Tests/*.tscn` non-recursively,
a suite added to `Tests/` is picked up with no CI edit — and a suite nested in a
subdirectory is silently skipped. See the testing section above.

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

## Android plugin

`qr-scanner-android/` is a Gradle/Kotlin Godot Android plugin (not a GDExtension, not
built by `Tools/build.py`). Its Godot-side half is `RetroXR/addons/retroxr_qr`. The other
in-repo addon that is ours rather than vendored is `RetroXR/addons/retroxr_build_stamp`,
which writes the `res://build_info.json` that `Scripts/Data/build_info.gd` reads.

## Architecture

### Multi-Instance Design (post-refactor)
Each `Libretro` GDExtension Node owns its own `Wrapper` instance and emulation thread. Multiple `Libretro` nodes can run simultaneously in the same scene, each with a different core/content. This replaced an earlier singleton design.

### Threading Model
Emulation runs on a dedicated `std::thread` owned by `Wrapper`. The main Godot thread communicates with it via a lock-free `ReaderWriterQueue` using a **command pattern** (`ThreadCommand` subclasses: `ThreadCommandCreateTexture`, `ThreadCommandInitAudio`, `ThreadCommandUpdateTexture`). The `Libretro` node's `_process()` drains this queue each frame.

Because libretro callbacks are static C functions, the correct `Wrapper*` is found via a `thread_local` pointer:
```cpp
// Set at emulation thread start, cleared at end:
thread_local Wrapper* t_current_wrapper = nullptr;

// All handlers and Core call:
Wrapper* w = Wrapper::GetCurrentThreadWrapper();
```
ThreadCommands that execute on the main thread carry an explicit `Wrapper*` and call `SetCurrentThreadWrapper` around their work so handler callbacks invoked during Execute() can also resolve the right instance.

### Key Classes (libretro-godot/src/)

- **Wrapper** — Per-instance emulation orchestrator. Owns the emulation thread, all handlers, the command queue, and a back-pointer `Libretro* m_libretro_node`. Exposes `GetCurrentThreadWrapper()` / `SetCurrentThreadWrapper(Wrapper*)` as static helpers for the thread-local pattern.
- **Core** — Dynamically loads a libretro core (`.dll` on Windows, `.so` on Linux/Android,
  `.dylib` on macOS) via `DynLib.hpp`, copies it to a temp directory for isolation, and
  binds all libretro callback function pointers. All callbacks resolve the current wrapper
  via `GetCurrentThreadWrapper()`.
- **Libretro** — The GDExtension Node exposed to GDScript. Instance methods only (`StartContent`, `StopContent`, `SetCoreOption`). Owns a `std::unique_ptr<Wrapper> m_wrapper`. Emits the `options_ready` signal via `NotifyOptionsReady()` (called from Wrapper across the thread boundary using `call_deferred`).

### Handler Subsystems
Each handler is owned by a `Wrapper` instance and manages one libretro subsystem:
- **VideoHandler** — Texture creation/updates, hardware rendering, rotation. It owns the
  HW-render contexts, and there are more than the software/Vulkan/OpenGL trio named
  elsewhere in this file: `VulkanContext` (with a `VulkanContextStub` for platforms
  without it), `D3D11Context` and `D3D12Context` on Windows, and `MacMetalLayer.mm` on
  macOS. `PixelSwizzle.hpp` handles the format conversions between them.
- **AudioHandler** — Audio stream generation and playback
- **InputHandler** — Per-port input state and joypad/mouse/keyboard mapping (Godot keycodes ↔ libretro keycodes). It does **not** read the global Godot `Input` singleton — there is not one reference to it in `InputHandler.cpp`. State is PUSHED in from GDScript, per port: `Libretro.SetJoypadState(port, buttons, alx, aly, arx, ary)` plus `SetMousePosition`/`SetMouseButtons`, `SetKeyState`, `SetLightgunPosition`/`SetLightgunButtons`, `SetPointerIndexState` (multi-touch/IR), `SetAnalogLeft`/`Right`, `SetSensorAccel`/`SetSensorGyro` and `SetPortDevice`. So two `Libretro` nodes in one scene have entirely independent controller state, which is what lets one room hold several machines — and what lets netplay replay a remote peer's port without touching local hardware. The callers are `retro_controller.gd`, `pad_receiver.gd`, `wiimote.gd`, `handheld_input.gd` and `netplay_session.gd`.
- **EnvironmentHandler** — Libretro environment callbacks (system dirs, VFS, disk control)
- **OptionsHandler** — Core option parsing (v1/v2 formats), categorization, persistence
- **MessageHandler** — Notification/message interface
- **LogHandler** — Log callback forwarding
- **RetroAchievements** — `RetroAchievements.cpp/.hpp`, backed by the `external/rcheevos`
  submodule, whose `src/`, `src/rcheevos/`, `src/rapi/` and `src/rhash/` trees are
  compiled straight into the extension (no external dependency). It hashes content by
  RetroAchievements' own console-specific rules rather than by plain file digest. The
  GDScript half lives in `RetroXR/Scripts/Data/ra/` (`ra_config`, `ra_consoles`,
  `ra_session`) and `RetroXR/Scripts/Net/ra/ra_http_bridge.gd`.
- **LinkCoordinator** — `LinkCoordinator.cpp/.hpp` + `LinkInterface.hpp`. A process-wide
  singleton joining two cores on one emulated wire; see §2g. Not per-`Wrapper`, unlike
  everything else in this list.

### Data Flow
```
GDScript UI → Libretro Node (instance) → Wrapper (per-node) → Core + Handlers → Libretro Core (.dll/.so/.dylib)
                                               ↑ ThreadCommand queue (ReaderWriterQueue) ↓
                                         Main thread (_process drains queue)
```

### Heap pointer tagging (Android)
`RegisterTypes.cpp` turns off Android's native heap pointer tagging when the extension
loads (`mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE)`, API 31+).
With it on, `malloc` pointers carry a tag in the top byte but a signal handler receives
fault addresses without it, so a core that matches faults against its own memory never
claims them: flycast without nvmem died on its first write to a protected RAM page
(flyinghead/flycast#2498). RetroArch opts out in its manifest instead
(libretro/RetroArch#19280).

### GDScript Side
- `RetroXR/Scenes/BootScene.tscn` is `run/main_scene` on every platform. It enters
  `SceneManager.boot_room()`: the last room a transition brought the player to, recorded
  once its contents finished arriving (`room` in `user://scenes/prefs.json`), else the
  arcade on Android and the bedroom elsewhere. A room run directly (F6, a suite, a probe)
  is never recorded. The root is still readying its children when the boot
  scene's `_ready` runs, so the swap is deferred: a room's `_ready` runs inside the first
  `SceneTree.process`, after that frame's `xrWaitFrame`, not inside `SceneTree.initialize`.
- `RetroXR/Scripts/Objects/systems/system.gd` — Per-arcade-cabinet controller. Has `@onready var _libretro: Libretro = $Libretro` wired to a child `Libretro` node in the scene tree.
- `RetroXR/Scenes/Objects/system.tscn` — Cabinet scene. Contains a `Libretro` child node. Its `unique_id` is the value 4000000010, but Godot writes it SIGNED, so the file reads `unique_id=-294967286` — grep for that, not for the decimal above.
- GDExtension registration at `MODULE_INITIALIZATION_LEVEL_SCENE`.

## Dependencies

- **godot-cpp** (submodule, 4.5 branch) — Godot C++ bindings
- **SDL3** — On Windows: core DLL loading (`DynLib.hpp`) + the OpenGL HW-render window. On Linux: the OpenGL HW-render window only (core loading uses `dlopen`); linked against the system `libSDL3.so.0` by soname, headers from `libretro-godot/external/SDL3/`. Not used on Android (`dlopen` + EGL via `DynLib.hpp`).
- **libretro-common** — Reference implementations for VFS, audio conversion, etc. (`libretro-godot/external/libretro-common/`)
- **rcheevos** (submodule, `libretro-godot/external/rcheevos/`) — RetroAchievements support, compiled into the extension. Carries no external dependency of its own.
- **Vulkan-Headers** (submodule, `libretro-godot/external/vulkan-headers/`) — headers for the Vulkan HW-render path.
- **moodycamel::ReaderWriterQueue** — Lock-free SPSC queue for cross-thread communication
- **godot-xr-tools v4.5.1 — FORKED IN PLACE, not a vendored drop-in.** VR locomotion,
  interactions, finger poses (`RetroXR/addons/godot-xr-tools/`). `plugin.cfg` still
  says 4.5.1 and it is no longer that: 30 commits have landed on it here, 59 files,
  +2841/-381, in snap_zone, player_body, the grab driver and pickable teardown —
  the local patch behind `function_pickup._on_grip_pressed` asking a controller
  whether it wants the grip, the snap zone releasing what it holds when it leaves
  the tree, and the `_property_get_revert` returns Godot 4.7 made mandatory.
  **Dropping a fresh upstream copy over this silently reverts all of it**, and the
  symptoms are grabs and teardown, which no headless suite covers. Diff before
  upgrading: `git log --oneline -- RetroXR/addons/godot-xr-tools`.
- **vlc-godot** (libVLC) — the `VlcPlayer` GDExtension; single video backend for both the DVD
  player and the VHS/VCR. Replaced `eirteam.ffmpeg` (dropped 2026-07-14; libVLC also does x265).
- **godot-pdfium** (PDFium) — the `PDFRenderer` GDExtension for rendering PDF pages (books) to
  Godot `Image`s. Prebuilt `libpdfium` from bblanchon/pdfium-binaries.
- **surround-godot** (FreeSurround) — the `SurroundDecoder` GDExtension, a Dolby Surround /
  Pro Logic II matrix decoder, plus the `SurroundAudio` factory singleton another extension
  reaches it through. GPL-2.0-or-later, vendored from Dolphin's copy, which is why it is an
  extension of its own rather than part of MIT-licensed `libretro-godot`. See §2r.

## Code Conventions

- C++latest standard (MSVC on Windows), C++20 (GCC/Clang/NDK elsewhere)
- Debug logging via `Log`, `LogOK`, `LogWarning`, `LogError` macros
- Libretro option data exposed to GDScript as `LibretroOptionCategory`, `LibretroOptionDefinition`, `LibretroOptionValue` objects
- Callback-based design throughout (video_refresh, audio_sample, input_poll, environment)
- All static libretro callbacks resolve their `Wrapper*` via `Wrapper::GetCurrentThreadWrapper()` — never store a raw global pointer
- `call_deferred` used when Wrapper needs to signal back to the `Libretro` node on the main thread (e.g. `NotifyOptionsReady`)

## Tools

Reusable, out-of-band scripts live in the repo-root `Tools/` (distinct from `RetroXR/Tools/`,
which holds in-editor probe scenes like `netplay_spike`).

What they need is declared in `Tools/requirements.txt` — numpy, pillow, scipy and
the imageio pair — so a fresh checkout does not discover them one ImportError at a
time: `python -m pip install -r Tools/requirements.txt`. Blender's `bpy`/`bmesh`/
`mathutils` are deliberately absent: `Tools/glb/*.py` run inside
`blender --background --python`, never as plain Python.

`RetroXR/imported-assets/` holds the CC BY / CC0 room and prop assets, which carry
LICENSE files and are credited in the About panel. The hardware wears the procedural
stand-ins in `RetroXR/Scenes/Objects/system_models/`.

**Only add 3D assets this project has the right to ship.** Everything in the repo must
be either our own work or licensed for redistribution, with its licence and attribution
carried alongside it.
- **`Tools/download_pdfium.sh`** — fetches prebuilt PDFium from bblanchon/pdfium-binaries into
  `godot-pdfium/external/pdfium/`. All five packages by default (`-p
  linux|win|mac|mac-x64|android` for one, `-r <tag>` to pin a release, `-n` to dry-run).
  Bash, so it runs on Linux, WSL, macOS and Git Bash; it superseded
  `Tools/download_pdfium.ps1`, which had no Linux or macOS platform at all. The `.ps1` is
  still in the tree but is NOT maintained — use the `.sh`. The
  `include/` headers are shared by all packages, so a **partial** run leaves them alone by
  default (`--headers` to force) — new declarations against an unrefreshed binary is how you
  get a link error on the platform you weren't building. Each `lib/<plat>/` carries a `VERSION`
  stamp of the release it came from, and the top-level one belongs to `include/`; they are
  allowed to differ, and the script prints them so you can see when they do.
- **Controller art** — three sources feed the Controls remap diagrams, and the
  licence of each is recorded in `RetroXR/Textures/Controllers/ATTRIBUTIONS.txt`.
  `bake_controller_art.py` bakes the Quest Touch art from a glTF (MIT), because a
  Touch controller's shape cannot be guessed. `gen_gamepad_art.py` DRAWS its pad —
  circles, capsules and a cross on a symmetric body — which keeps the anchors as
  chosen coordinates that cannot drift from a render; it is an Xbox *layout* and
  deliberately not an Xbox, so there is no mark being borrowed. The NES pad is a
  Wikimedia Commons drawing by Fant0men used under **CC BY-SA 3.0** with the
  Nintendo wordmark's eleven paths deleted — the repo's ONLY share-alike asset,
  so it carries two live obligations: the About panel must keep crediting it,
  and the modified file stays CC BY-SA (it does not relicense anything else).
  Its anchors are MEASURED out of a Godot render by
  `Tools/art/nes_pad_anchors.py` (red discs → A/B, black cross → d-pad, black pills →
  Select/Start) rather than chosen. That tool also counts leader-line
  intersections over a sweep of panel sizes, and the count must stay 0.
  ```bash
  python Tools/art/nes_pad_anchors.py RetroXR/probe_out/nes_colour_raw.png
  ```
  **A console pad's art is drawn inside `_draw()`, not parented as a TextureRect**
  — a Control renders its own `_draw()` behind its children, so a child texture
  hides the leader lines and anchor dots. Invisible with line art, whose body is
  nearly transparent; total with a colour illustration.
- **`Tools/gen_gblink_rom.py`** — builds the four Game Boy ROMs the link probes run,
  two at the Game Boy's clock and two at the Game Boy Color's. Ours, so they ship
  freely; the header logo carries only its first four bytes, which is the signature
  a loader matches to decide a file is a Game Boy ROM at all (mGBA refuses one
  without them) and not the artwork.
- **`Tools/glb/decimate_glb.py`** — Blender-headless triangle reduction for a downloaded shell.
  Sketchfab assets arrive subdivided for renders: the Atari 2600 console shipped 1,080,733
  triangles and 57.7 MB, against 27,893 for the NES. **Weld first** — these exports are
  triangle soup (that console was 230,787 disconnected islands, median one triangle), and
  Collapse cannot reduce an isolated triangle, so without the weld the body floors at 54 k
  however low you aim. Also drop the custom split normals and re-derive shading by angle:
  carried through a 98% cut they describe a surface that is gone, which showed up as a smeared
  cartridge slot and starburst facets across flat panels.
  ```bash
  "/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
    --python Tools/glb/decimate_glb.py -- --in <src>.glb --out <dst>.glb --target 25000
  ```
  `Tools/glb/glb_report.py` dumps a GLB's node tree, world AABBs and triangle budget;
  `Tools/glb/glb_diff.py` compares two and is the check that matters — every model's seat,
  port and jack constant is a hand-measured position in the GLB's frame, so a round trip has
  to preserve names, hierarchy, world placement and image names. Note the GLBs are **Git LFS**,
  so `git show HEAD:<path>` yields a pointer: pipe it through `git lfs smudge` to get a
  baseline to diff against.
