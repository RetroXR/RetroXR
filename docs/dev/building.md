# Building the GDExtensions

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

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

## `**/*.info` belongs in EVERY export preset

`CoreInfoDatabase` reads `res://libretro-core-info/` and `res://libretro-core-info-retroxr/`.
A `.info` file has no Godot importer, so `export_filter="all_resources"` does not carry it —
only `include_filter="**/*.info"` does. Until 2026-09-25 only the Android presets had it, and
a Linux/Windows/macOS export shipped with an EMPTY core database. Nothing errors: the Cores
panel still lists the installed `.so`/`.dll` by filename, but with no `.info` behind it
`CoreInfoDatabase.systemids_of()` returns empty, every core is filed under the `"unknown"`
bucket (`cores_view.gd`), `CoreDefaults.adopt_missing()` adopts nothing, and the Systems tab
ends up holding one tile named after whichever core sorted first. A fresh Linux install
reproduced it exactly: 51 cores downloaded, `core_defaults.json` = `{"unknown": "arduous"}`.

Two habits keep it from coming back: the filter is on all four shipping presets, and
`docs/dev/systemids.md` is the place to look when a system is missing on one platform only.
`Tools/rename_systemids.py` is run on the source directories, so the exported copies are
rewritten by export, not by hand.
