#!/usr/bin/env bash
# download_vlc_macos.sh — fetch libVLC for macOS from VideoLAN into
# RetroXR/vlc-godot/macos/, laid out the way vlc-godot/SConscript and
# vlc_godot.gdextension expect:
#
#   RetroXR/vlc-godot/macos/libvlc.dylib
#   RetroXR/vlc-godot/macos/libvlccore.dylib
#   RetroXR/vlc-godot/macos/plugins/<category>/*.dylib
#   RetroXR/vlc-godot/macos/VERSION
#
#   Tools/download_vlc_macos.sh            # the pinned release
#   Tools/download_vlc_macos.sh --force    # fetch again over what is there
#
# macOS only (hdiutil, otool, install_name_tool, codesign). The tree is not
# committed: CI runs this before building the extension, and a Mac developer
# runs it once before opening the project.
#
# VideoLAN ships libVLC inside the ordinary VLC.app rather than as an SDK, so
# this mounts the universal .dmg and takes the two libraries and the plugin
# categories the Windows tree keeps (RetroXR/vlc-godot/plugins/README.md). It is
# the same VLC release as the vendored Windows and header files, so one bump
# moves all three.
#
# The libraries are made to find each other by @rpath, and the extension and the
# game carry the rpaths: in the exported .app all of it sits in
# Contents/Frameworks, next to the extension, and in the editor in this folder.
# Anything rewritten is signed again, ad hoc, since an arm64 Mac refuses to load
# a library whose signature no longer matches.

set -euo pipefail

VLC_VERSION="3.0.23"
DMG="vlc-$VLC_VERSION-universal.dmg"
DMG_SHA256="56ee657c3aaf5c71b4ab7d6e4f4a77f6eca54633e0bf42a93b8116eb1d1f6ec9"
URL="https://download.videolan.org/pub/videolan/vlc/$VLC_VERSION/macosx/$DMG"

# The categories the Windows tree keeps: what the VCR, the DVD player and the
# audio decks decode with, and nothing of VLC's own interface, Lua or streaming.
CATEGORIES=(access audio_filter audio_output codec demux misc packetizer
            stream_filter video_chroma video_filter video_output)

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO/RetroXR/vlc-godot/macos"

die() { printf '%s\n' "error: $*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

force=""
case "${1:-}" in
    "") ;;
    --force) force="yes" ;;
    -h|--help) sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed -n 's/^# \{0,1\}//p'; exit 0 ;;
    *) die "unexpected argument '$1' (try --help)" ;;
esac

[[ "$(uname -s)" == "Darwin" ]] || die "this needs macOS (hdiutil, otool, install_name_tool)"
for tool in curl hdiutil otool install_name_tool codesign shasum; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not on PATH"
done

if [[ -z "$force" && -f "$DEST/VERSION" && "$(cat "$DEST/VERSION")" == "$VLC_VERSION" ]]; then
    note "vlc-macos: $VLC_VERSION already in ${DEST#"$REPO/"} (--force to fetch again)"
    exit 0
fi

tmp="$(mktemp -d)"
mnt="$tmp/mnt"
cleanup() {
    [[ -d "$mnt" ]] && hdiutil detach -quiet "$mnt" >/dev/null 2>&1 || true
    rm -rf "$tmp"
}
trap cleanup EXIT

note "vlc-macos: GET $URL"
curl -fL --silent --show-error --retry 5 --retry-delay 15 -o "$tmp/$DMG" "$URL" \
    || die "download failed: $URL"
got="$(shasum -a 256 "$tmp/$DMG" | cut -d' ' -f1)"
[[ "$got" == "$DMG_SHA256" ]] || die "$DMG has sha256 $got, expected $DMG_SHA256"

mkdir -p "$mnt"
# Answer a licence prompt, should the image ever carry one, rather than hang.
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$tmp/$DMG" <<< "Y" >/dev/null
app="$(find "$mnt" -maxdepth 1 -name 'VLC.app' | head -1)"
[[ -n "$app" ]] || die "no VLC.app in $DMG"
src="$app/Contents/MacOS"
[[ -f "$src/lib/libvlc.dylib" && -f "$src/lib/libvlccore.dylib" ]] \
    || die "no lib/libvlc.dylib + lib/libvlccore.dylib in VLC.app"

rm -rf "$DEST"
mkdir -p "$DEST/plugins"
# -L: VLC.app links libvlc.dylib -> libvlc.5.dylib; the copy is the file itself.
cp -L "$src/lib/libvlc.dylib" "$src/lib/libvlccore.dylib" "$DEST/"
for cat in "${CATEGORIES[@]}"; do
    if [[ -d "$src/plugins/$cat" ]]; then
        cp -RL "$src/plugins/$cat" "$DEST/plugins/"
    else
        note "  (no $cat plugins in this VLC)"
    fi
done
# Older VLCs keep the plugins flat; fail loudly rather than ship an empty tree.
count="$(find "$DEST/plugins" -name '*.dylib' | wc -l | tr -d ' ')"
[[ "$count" -gt 50 ]] || die "only $count plugins found under $src/plugins"
# The plugin cache lists VLC.app's whole set by path and size, and libVLC
# rescans when it does not match; leaving it out costs one scan at startup.
rm -f "$DEST/plugins/plugins.dat"
hdiutil detach -quiet "$mnt"

# --- make the libraries find each other by @rpath ---------------------------

# The install name a Mach-O file gives itself, and the libvlc*/libvlccore* it loads.
own_id() { otool -D "$1" | sed -n '2p'; }
vlc_loads() { otool -L "$1" | sed -n '2,$p' | awk '{print $1}' | grep -E '/libvlc(core)?(\.[0-9]+)*\.dylib$' || true; }

changed=()
fix_file() {
    local f="$1" before after
    before="$(otool -L "$f")"
    case "$f" in
        */libvlc.dylib)     [[ "$(own_id "$f")" == "@rpath/libvlc.dylib" ]] \
                                || install_name_tool -id "@rpath/libvlc.dylib" "$f" 2>/dev/null ;;
        */libvlccore.dylib) [[ "$(own_id "$f")" == "@rpath/libvlccore.dylib" ]] \
                                || install_name_tool -id "@rpath/libvlccore.dylib" "$f" 2>/dev/null ;;
    esac
    local dep
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        local want="@rpath/libvlccore.dylib"
        [[ "$(basename "$dep")" == libvlc.* || "$(basename "$dep")" == libvlc.dylib ]] && want="@rpath/libvlc.dylib"
        [[ "$dep" == "$want" ]] || install_name_tool -change "$dep" "$want" "$f" 2>/dev/null
    done < <(vlc_loads "$f")
    after="$(otool -L "$f")"
    [[ "$before" == "$after" ]] || changed+=("$f")
}

note "vlc-macos: install names as shipped"
note "  libvlc.dylib     id $(own_id "$DEST/libvlc.dylib"); loads $(vlc_loads "$DEST/libvlc.dylib" | tr '\n' ' ')"
note "  libvlccore.dylib id $(own_id "$DEST/libvlccore.dylib")"
sample="$(find "$DEST/plugins/codec" -name '*.dylib' | head -1)"
note "  $(basename "$sample") loads $(vlc_loads "$sample" | tr '\n' ' ')"

while IFS= read -r f; do
    fix_file "$f"
done < <(find "$DEST" -name '*.dylib')

if [[ ${#changed[@]} -gt 0 ]]; then
    note "vlc-macos: rewrote ${#changed[@]} install names; signing them again (ad hoc)"
    for f in "${changed[@]}"; do
        codesign --force --sign - "$f" 2>/dev/null
    done
fi

printf '%s\n' "$VLC_VERSION" > "$DEST/VERSION"
note "vlc-macos: $VLC_VERSION -> ${DEST#"$REPO/"} ($count plugins)"
lipo -info "$DEST/libvlc.dylib"
