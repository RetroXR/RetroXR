# Vendored libVLC plugin tree

**Upstream release: VLC 3.0.23 (win64).** 158 `.dll` plugins plus `plugins.dat`,
about 43 MB. `libvlc.dll` and `libvlccore.dll` sit one directory up and are from
the same build.

`VlcPlayer` points libVLC at this directory at startup (`VlcPlayer.cpp`, which
globalizes `res://vlc-godot/plugins` and sets the plugin path before creating the
instance), so the set here is exactly what the DVD player and the VCR can decode.

## Why this file exists

The tree is 159 committed binaries with no version recorded anywhere, which
meant there was no way to tell which VLC it came from or how to rebuild it when
libVLC is bumped — the problem `Tools/download_pdfium.sh` and its per-platform
`VERSION` stamps already solve for PDFium.

## Verifying what is here

The version is readable from the shipped binaries themselves, so this file can
always be checked rather than trusted:

```powershell
(Get-Item RetroXR/vlc-godot/libvlc.dll).VersionInfo.FileVersion   # 3.0.23
```

and the vendored headers agree — `vlc-godot/external/include/vlc/libvlc_version.h`
declares MAJOR 3, MINOR 0, REVISION 23.

## Regenerating it

Not scripted, unlike PDFium: VideoLAN ships the plugins inside the ordinary
Windows build rather than as a separate download, so there is no URL to fetch a
plugin tree from.

1. Install or unzip the official VLC **win64** build of the target release.
2. Copy its `plugins/` directory here, keeping the subdirectory layout.
3. Keep only the categories present in this tree: `access`, `audio_filter`,
   `audio_output`, `codec`, `demux`, `misc`, `packetizer`, `stream_filter`,
   `video_chroma`, `video_filter`, `video_output`. The rest of VLC's set covers
   things this app never asks for — interfaces, visualisations, streaming output,
   services discovery.
4. Regenerate `plugins.dat` by running the app once; libVLC rebuilds the cache
   when it does not match the tree.
5. Bump the version at the top of this file, and refresh the headers in
   `vlc-godot/external/include/vlc/` from the same release.

The exact prune above is inferred from what the committed tree contains — the
original copy was not scripted and left no record — so treat step 3 as a
description of the current set rather than as the command that produced it. If a
bump needs a category that is not listed, add it here with the reason.

## Exports

An export carries this tree as `plugins\` beside `RetroXR.exe`, next to
`libvlccore.dll`: it is one of the Windows dependencies in
`../vlc_godot.gdextension`, and `VlcPlayer` falls back to it when
`res://vlc-godot/plugins` is not a folder on disk. v0.11.1 and earlier shipped
without it and played nothing. `Tools/av/vlc_export_probe.tscn` checks that an
export plays.

## macOS

Not this folder. `Tools/download_vlc_macos.sh` takes `libvlc.dylib`,
`libvlccore.dylib` and the same plugin categories from VideoLAN's universal
VLC.app (the same release, pinned by its sha256) into `../macos/`, which is not
committed. `Tools/build.py macos` runs it when that is missing, and an export puts
all of it in `Contents/Frameworks`.

## Licence

libVLC is **LGPL v2.1 or later**; individual plugins are a mix of LGPL v2.1+ and
**GPL v2+**. Both are compatible with this app's GPLv3 licensing. The Windows
binaries are redistributed unmodified; on macOS `Tools/download_vlc_macos.sh` may
rewrite install names to `@rpath` and sign again what it rewrote, which the LGPL
allows. See https://www.videolan.org/legal.html.
