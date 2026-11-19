#!/usr/bin/env bash
# download_pdfium.sh — fetch prebuilt PDFium from bblanchon/pdfium-binaries into
# extensions/godot-pdfium/external/pdfium/, laid out the way extensions/godot-pdfium/SConscript expects.
#
#   Tools/download/download_pdfium.sh                          # all platform packages, latest release
#   Tools/download/download_pdfium.sh -p linux                 # just the Linux x86_64 lib
#   Tools/download/download_pdfium.sh -p mac                   # just the macOS arm64 lib
#   Tools/download/download_pdfium.sh -p linux --no-headers    # ...and leave include/ alone
#   Tools/download/download_pdfium.sh -r chromium/7988         # pin a release tag
#   Tools/download/download_pdfium.sh --dry-run                # show what would change
#
# Runs anywhere bash + curl + tar exist: Linux, WSL, macOS, Git Bash on Windows.
# Replaced Tools/download/download_pdfium.ps1, which only knew win-x64 and android-arm64.
#
# The libs are committed to the repo, so a fresh clone does NOT need this — it is
# for refreshing them or adding a platform.
#
# The `include/` headers are shared by every platform. Refreshing one
# platform's lib without its headers (--no-headers) is the safe, minimal move;
# refreshing the headers without every lib pairs new declarations with older
# binaries, so a header write from a partial run warns.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$REPO/extensions/godot-pdfium/external/pdfium"
GH_REPO="bblanchon/pdfium-binaries"

# key -> archive basename : destination lib subdir
ALL_PLATFORMS=(win-x64 android-arm64 linux-x64 mac-x64 mac-arm64)

release="latest"
platforms=()
want_headers=""   # "" = auto (yes), "no" = skip
dry_run=""

die() { printf '%s\n' "error: $*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

usage() {
    # the leading comment block, minus the shebang
    sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed -n 's/^# \{0,1\}//p'
    exit "${1:-0}"
}

# Accept the short aliases people actually type.
canon_platform() {
    case "$1" in
        win|win-x64|windows|windows-x64)          echo win-x64 ;;
        linux|linux-x64|linux-x86_64)             echo linux-x64 ;;
        mac|macos|mac-arm64|macos-arm64)          echo mac-arm64 ;;
        mac-x64|macos-x64|mac-x86_64|macos-x86_64) echo mac-x64 ;;
        android|android-arm64|android-arm64-v8a)  echo android-arm64 ;;
        *) die "unknown platform '$1' (want: win-x64, linux-x64, mac-x64, mac-arm64, android-arm64)" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            [[ $# -ge 2 ]] || die "$1 needs a value"
            IFS=', ' read -r -a _req <<< "$2"
            for _p in "${_req[@]}"; do
                [[ -n "$_p" ]] && platforms+=("$(canon_platform "$_p")")
            done
            shift 2 ;;
        -r|--release)
            [[ $# -ge 2 ]] || die "$1 needs a value"
            release="$2"; shift 2 ;;
        --headers)    want_headers="yes"; shift ;;
        --no-headers) want_headers="no";  shift ;;
        -n|--dry-run) dry_run="yes"; shift ;;
        -h|--help)    usage 0 ;;
        *) die "unexpected argument '$1' (try --help)" ;;
    esac
done

for tool in curl tar; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not on PATH"
done

partial=""
if [[ ${#platforms[@]} -eq 0 ]]; then
    platforms=("${ALL_PLATFORMS[@]}")
else
    # de-duplicate while keeping the canonical order
    _uniq=()
    for p in "${ALL_PLATFORMS[@]}"; do
        for q in "${platforms[@]}"; do
            [[ "$p" == "$q" ]] && { _uniq+=("$p"); break; }
        done
    done
    platforms=("${_uniq[@]}")
    [[ ${#platforms[@]} -lt ${#ALL_PLATFORMS[@]} ]] && partial="yes"
fi

# Headers default to on for a full run, off for a partial one: a partial run that
# rewrote include/ would leave the platforms it skipped on stale binaries.
if [[ -z "$want_headers" ]]; then
    want_headers=$([[ -n "$partial" ]] && echo no || echo yes)
fi

if [[ "$release" == "latest" ]]; then
    base_url="https://github.com/$GH_REPO/releases/latest/download"
else
    base_url="https://github.com/$GH_REPO/releases/download/$release"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

note "pdfium: $GH_REPO @ $release"
note "  platforms: ${platforms[*]}"
note "  headers:   $want_headers"
note "  dest:      $DEST"
[[ -n "$dry_run" ]] && note "  (dry run — nothing will be written)"

# What the tree holds right now. Each lib dir carries its own VERSION because the
# platforms can legitimately sit on different releases; the top-level one belongs
# to include/, which is shared.
for _p in "" "${ALL_PLATFORMS[@]}"; do
    _vf="$DEST${_p:+/lib/$_p}/VERSION"
    if [[ -f "$_vf" ]]; then
        printf '  have: %-14s %s\n' "${_p:-include/}" "$(cat "$_vf")"
    fi
done

headers_done=""
fetched_version=""

for plat in "${platforms[@]}"; do
    archive="pdfium-$plat.tgz"
    url="$base_url/$archive"
    work="$tmp/$plat"
    mkdir -p "$work"

    note ""
    note "=== $plat ==="
    note "  GET $url"
    curl -fL --silent --show-error --retry 3 --retry-delay 2 -o "$tmp/$archive" "$url" \
        || die "download failed: $url"
    tar -xzf "$tmp/$archive" -C "$work"

    if [[ -f "$work/VERSION" ]]; then
        v="$(tr '\n' ' ' < "$work/VERSION" | sed 's/  *$//')"
        note "  version: $v"
        if [[ -n "$fetched_version" && "$fetched_version" != "$v" ]]; then
            die "release '$release' resolved to different versions per platform" \
                "($fetched_version vs $v) — pin an explicit tag with --release"
        fi
        fetched_version="$v"
    fi

    if [[ -n "$dry_run" ]]; then
        note "  would install into lib/$plat/:"
        for src in "$work/lib" "$work/bin"; do
            [[ -d "$src" ]] || continue
            find "$src" -maxdepth 1 -type f | sed "s|$work/|    |"
        done
        continue
    fi

    # Headers are identical across platforms, so only the first pass writes them.
    # fpdfview.h.orig is an upstream packaging artefact, not a header we compile.
    if [[ "$want_headers" == "yes" && -z "$headers_done" && -d "$work/include" ]]; then
        note "  headers -> $DEST/include/"
        find "$work/include" -name '*.orig' -delete
        # Replaced wholesale, not merged: include/ is a vendored copy, and a
        # header upstream deleted must not survive here as a stale declaration.
        rm -rf "$DEST/include"
        mkdir -p "$DEST/include"
        cp -R "$work/include/." "$DEST/include/"
        headers_done="yes"
        # The top-level stamp describes include/, which is what this block wrote.
        if [[ -n "$fetched_version" ]]; then
            printf '%s\n' "$fetched_version" > "$DEST/VERSION"
        fi
        if [[ -n "$partial" ]]; then
            note "  WARNING: headers refreshed from a partial run — the platforms"
            note "           you skipped still carry libs from an older release."
        fi
    fi

    libdir="$DEST/lib/$plat"
    mkdir -p "$libdir"
    for src in "$work/lib" "$work/bin"; do
        [[ -d "$src" ]] || continue
        while IFS= read -r f; do
            note "  $(basename "$f") -> ${libdir#"$REPO/"}/"
            cp -f "$f" "$libdir/"
        done < <(find "$src" -maxdepth 1 -type f)
    done

    # Stamp the release this platform's binary came from. Platforms are refreshed
    # independently, so this lives per lib dir rather than once at the top.
    if [[ -n "$fetched_version" ]]; then
        printf '%s\n' "$fetched_version" > "$libdir/VERSION"
    fi

    # Licence text travels with the binary we redistribute.
    for lic in LICENSE licenses; do
        if [[ -e "$work/$lic" ]]; then cp -R "$work/$lic" "$DEST/"; fi
    done
done

note ""
note "=== done ==="
find "$DEST/lib" -type f ! -name VERSION | sed "s|$REPO/|  |" | sort
for _p in "" "${ALL_PLATFORMS[@]}"; do
    _vf="$DEST${_p:+/lib/$_p}/VERSION"
    if [[ -f "$_vf" ]]; then
        printf '  %-14s %s\n' "${_p:-include/}" "$(cat "$_vf")"
    fi
done
note ""
note "Next: build the extension —"
note "  python Tools/build.py <windows|linux|macos|android> --only godot-pdfium"
