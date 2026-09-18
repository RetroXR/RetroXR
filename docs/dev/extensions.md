# The sibling GDExtensions

Moved verbatim out of `CLAUDE.md` on 2026-09-18; `CLAUDE.md` keeps the summary and links here.

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
