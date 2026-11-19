# RetroXR

**[retroxr.app](https://retroxr.app)** — install, how to play, and the devlog.
**[Discord](https://discord.gg/pgUkRhafca)** · **[SideQuest](https://sidequestvr.com/app/61366/retroxr)**

A VR retro-gaming room in Godot 4: the hardware is physical. Spawn a console, a TV and a
cartridge, plug in the AV cable, the controller and the game, and play. No emulator windows.

- **Consoles, handhelds and arcade cabinets** run on libretro cores; arcade cabinets morph to the game in them
- **Link cables, multitaps, light guns, printers and expansions** work as the real ones do
- **DVDs, VHS, CDs, cassettes, records, books and magazines** from your own files
- **Furniture, doors and drawers**, optional power simulation, and spatial (HRTF) audio
- **RomM** library and BIOS sync, **mod.io** mods, and rollback **netplay** (experimental)

Most consoles are still primitive stand-ins. **Modellers are welcome**: models must be
free of trademarked text and images.

## Your files

The data folder is `%USERPROFILE%\retroxr` (Windows), `~/retroxr` (Linux/macOS) or
`/sdcard/Android/data/com.xenu.retroxr/files` (Quest); move it in Options > Storage. On a
Quest, upload through the app's Web File Manager.

| Folder | Holds |
|---|---|
| `roms/<system>/` | games (ES-DE folder names: `snes`, `psx`, …) |
| `dvd/` | a `VIDEO_TS/` folder, `.iso` or `.img` |
| `videos/` | `.mp4` `.mkv` `.avi` `.webm` `.mov`; an `.m3u` is one tape of several |
| `music/` | an album is a folder of tracks; a `#SIDE B` line in its `.m3u` splits a tape or LP |
| `books/` | `.pdf` and `.cbz` |
| `tv/` | `.m3u` IPTV playlists |

Everything spawns from the **Tab** menu. Cores, defaults, core options and BIOS files are
under **CORES**.

## Forked cores

Most cores are the libretro buildbot's. These are RetroXR's forks, mostly to carry link
cables and devices between cores: [Dolphin](https://github.com/RetroXR/dolphin),
[FBNeo](https://github.com/RetroXR/FBNeo), [FCEUmm](https://github.com/RetroXR/libretro-fceumm),
[Flycast](https://github.com/RetroXR/flycast), [Gambatte](https://github.com/RetroXR/gambatte-libretro),
[Genesis Plus GX](https://github.com/RetroXR/Genesis-Plus-GX), [mGBA](https://github.com/RetroXR/mgba),
[Mupen64Plus-Next](https://github.com/RetroXR/mupen64plus-libretro-nx), [PCSX-ReARMed](https://github.com/RetroXR/pcsx_rearmed),
[PS2](https://github.com/RetroXR/ps2), [Play!](https://github.com/RetroXR/Play-),
[Snes9x](https://github.com/RetroXR/snes9x), [VeMUlator](https://github.com/RetroXR/vemulator-libretro),
[Virtual Jaguar](https://github.com/RetroXR/virtualjaguar-libretro), [xemu](https://github.com/RetroXR/xemu),
Beetle [Lynx](https://github.com/RetroXR/beetle-lynx-libretro) / [NeoPop](https://github.com/RetroXR/beetle-ngp-libretro) /
[Saturn](https://github.com/RetroXR/beetle-saturn-libretro) / [VB](https://github.com/RetroXR/beetle-vb-libretro) /
[WonderSwan](https://github.com/RetroXR/beetle-wswan-libretro), and two new cores,
[Game Boy Printer](https://github.com/RetroXR/gbprinter-libretro) and the
[DMG-07 4 Player Adapter](https://github.com/RetroXR/dmg07-libretro). Each builds from its `retroxr` branch.

## Development

Developer notes live in [`CLAUDE.md`](CLAUDE.md) and [`docs/dev/`](docs/dev/).

### Building

```bash
git submodule update --init --recursive
pip install --user scons
python Tools/build.py windows               # or linux, macos, android; --target release, --only <name>
```

That builds the nine GDExtensions (`libretro-godot`, `archive-godot`, `verlet-rope`, `vlc-godot`,
`godot-pdfium`, `metaxr-audio`, `surround-godot`, `paper-godot`, `grab-godot`) and prints a
pass/fail table. A fresh clone will not run without them. Needs MSVC, GCC/Clang, the Xcode
command-line tools, or for Android the NDK (`ANDROID_NDK_ROOT` set, `ANDROID_HOME` empty). Linux
links the system libVLC (`vlc-devel` to build, `vlc-libs` to run); macOS skips `vlc-godot` and
`metaxr-audio`.

### The patched engine

Every release runs RetroXR's patched Godot 4.7.2
([github.com/RetroXR/godot](https://github.com/RetroXR/godot), branch `retroxr-4.7.2`) at the
commit pinned in `Tools/engine/ENGINE_COMMIT`, on every platform: CI builds it.

Locally, only the Quest needs it, because stock Godot hangs there: every Android export swaps
it in and refuses any other commit. No binary is committed, so build it once, and again when
the pin moves. The export looks for it in `~/godot` (or `RETROXR_GODOT_DIR`).

```bash
git clone https://github.com/RetroXR/godot ~/godot
git -C ~/godot checkout "$(cat Tools/engine/ENGINE_COMMIT)"
cd ~/godot   # ANDROID_HOME = the Android SDK folder here
scons platform=android arch=arm64 target=template_debug   generate_apk=no
scons platform=android arch=arm64 target=template_release generate_apk=no
```

A desktop export or the editor runs whichever Godot you start, so it is stock unless you
build from the same checkout:

```bash
scons platform=windows target=editor                       # run the project with bin/godot.windows.editor.x86_64.console.exe
scons platform=windows target=template_release production=yes   # or linuxbsd / macos (build arm64 and x86_64, then lipo)
```

Add `d3d12=no accesskit=no` if those SDKs are missing. Then set the preset's *Custom
Template → Release* to the built `bin/godot.<platform>.template_release.<arch>` (don't commit
that), or copy it over the stock one in Godot's `export_templates/4.7.2.stable/` folder, as
CI does. A patched export names the pin: `grep -a "$(head -c9 Tools/engine/ENGINE_COMMIT)"`
finds it in the binary, where stock says `4.7.2.stable.official`.

### Exporting and releasing

```bash
"$godot" --headless --path RetroXR --export-release "Quest" RetroXR.apk   # or "Windows Desktop", "Linux", "macOS"
```

Supply your own Android keystore (*Project → Export → Android*, or the
`GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables).

A `v*` tag runs `.github/workflows/release.yml`: it builds the engine and extensions for
every platform, exports and signs every build, publishes the release and updates SideQuest.
Bump `version/code` and `version/name` in `RetroXR/export_presets.cfg` first; the tag must
match the name. **Run workflow** from the Actions tab builds the same without publishing.

## Desktop controls

With no headset, RetroXR runs on mouse and keyboard (or a gamepad).

- **Move** `WASD`, look with the mouse, `Ctrl` crouch, `Caps Lock` walk, `[` / `]` height
- **Hands** left-click grabs (or fires a held light gun), `Shift`+left-click drops, scroll pushes
  and pulls, middle-drag rotates, `Tab` the spawn menu, `F11` fills the window with the TV or
  handheld you look at
- **Joypad** (a machine in focus) d-pad `WASD`; numpad `1` B, `2` A, `3` Y, `4` X; `Q`/`E` L/R,
  `Z`/`X` L2/R2, `C`/`V` L3/R3, `Shift` Select, `Enter` Start; sticks `TFGH` and `IJKL`

## Licensing

Copyright (C) 2026 Ryan McClelland.

RetroXR is **GPL-3.0** ([LICENSE](LICENSE)), with an additional permission
([LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md)) to link Meta's proprietary XR Audio SDK and the
Oculus-SDK-licensed parts of the godot-openxr-vendors Meta plugin, which stay under the
[Oculus SDK License Agreement](https://developers.meta.com/horizon/licenses/oculussdk/).
`libretro-godot` is a separate MIT submodule, begun as a fork of SKurdt's SK.Libretro.Godot.

Bundled libraries and assets keep their own licences (MIT, BSD, Apache-2.0, zlib, LGPL-2.1
libVLC, GPL-2.0+ VLC plugins, GPL FreeSurround, CC0, CC BY 4.0, CC BY-SA 4.0). Attribution is a
licence condition for the CC BY and CC BY-SA assets: the credits are in the app under
OPTIONS → ABOUT, and each asset directory carries its own `LICENSE-*` file. Controller models
in your hands come from the XR runtime, so no headset vendor's art ships here.
