"""Swap RetroXR's patched Godot engine into the Android build template's AAR.

The release workflow installs Godot's stock 4.7.2 Android build template and
exports with it, so an engine patch only ships if its libgodot_android.so
replaces the stock one inside godot-lib.template_<target>.aar first. The
library is built from the `retroxr-4.7.2` branch of the engine (4.7.2-stable
plus docs/godot-4.7.2-*.patch) at the commit pinned in Tools/engine/ENGINE_COMMIT,
and it must name that commit: a library from any other commit is refused.

Nothing is committed to this repo. CI builds the library in release.yml's
`engine` job and passes it with --so. A local export takes it from the engine
checkout's own build output, $RETROXR_GODOT_DIR or ~/godot:
platform/android/java/lib/libs/<target>/arm64-v8a/libgodot_android.so
(build it there with the recipe in docs/dev/engine-patches.md).

    python Tools/place_engine.py --target release --so <lib>   # CI, before --export-release
    python Tools/place_engine.py --target debug        # local Quest exports
    python Tools/place_engine.py --target debug --check
    python Tools/place_engine.py --target debug --restore

The stock AAR is kept beside the patched one as .aar.orig; --restore puts it
back. Only arm64-v8a is replaced, which is the only ABI the Quest preset builds.

Placing is a no-op when the AAR already carries the library, and the
retroxr_build_stamp export plugin runs it before every Android export. The
template is shared by every export from this checkout, so it has to STAY
patched: a --restore once used to tidy up after a probe build left it stock,
and every local Quest build after that hung on the loading screen.
"""
import argparse, os, shutil, sys, zipfile, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENTRY = "jni/arm64-v8a/libgodot_android.so"


def _crc32(path: str) -> int:
    crc = 0
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            crc = zlib.crc32(chunk, crc)
    return crc


## True when the AAR's engine library is byte-for-byte `so`. The zip records
## each entry's CRC and size, so this reads the .so but never inflates the AAR.
def _carries(aar: str, so: str) -> bool:
    with zipfile.ZipFile(aar) as z:
        try:
            info = z.getinfo(ENTRY)
        except KeyError:
            return False
    return info.file_size == os.path.getsize(so) and info.CRC == _crc32(so)


## The full engine commit every platform ships, from Tools/engine/ENGINE_COMMIT.
def _pinned_commit() -> str:
    with open(os.path.join(ROOT, "Tools", "engine", "ENGINE_COMMIT")) as f:
        return f.read().strip()


## The engine checkout's own build of `target`: $RETROXR_GODOT_DIR, else ~/godot.
def _default_so(target: str) -> str:
    godot = os.environ.get("RETROXR_GODOT_DIR") or os.path.join(os.path.expanduser("~"), "godot")
    return os.path.join(godot, "platform", "android", "java", "lib", "libs", target, "arm64-v8a", "libgodot_android.so")


## True when the library's version banner (4.7.2.stable.custom_build.<hash>)
## names `short`, the pinned commit's first nine characters, as release.yml
## checks every desktop binary.
def _names_commit(so: str, short: str) -> bool:
    needle = short.encode()
    tail = b""
    with open(so, "rb") as f:
        while chunk := f.read(1 << 20):
            if needle in tail + chunk:
                return True
            tail = chunk[-len(needle):]
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=("debug", "release"), required=True)
    ap.add_argument("--so", default=None, help="library to place; default the engine checkout's build, "
                    "$RETROXR_GODOT_DIR or ~/godot: platform/android/java/lib/libs/<target>/arm64-v8a/libgodot_android.so")
    ap.add_argument("--check", action="store_true", help="exit 0 if the AAR already carries the library, 1 if not; changes nothing")
    ap.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    aar = os.path.join(ROOT, "RetroXR", "android", "build", "libs", a.target, f"godot-lib.template_{a.target}.aar")
    bak = aar + ".orig"
    if not os.path.exists(aar):
        print(f"no build template AAR at {aar}", file=sys.stderr)
        return 1
    if a.restore:
        if not os.path.exists(bak):
            print("nothing to restore", file=sys.stderr)
            return 1
        os.replace(bak, aar)
        print("restored stock AAR", os.path.getsize(aar))
        print("WARNING: exports from this template run STOCK Godot, which deadlocks at boot on a Quest."
              " The next Android export re-places the patched engine unless RETROXR_STOCK_ENGINE=1.", file=sys.stderr)
        return 0
    so = a.so or _default_so(a.target)
    pin = _pinned_commit()
    if not os.path.exists(so) or os.path.getsize(so) < 1_000_000:
        print(f"no engine library at {so}: build target={'template_' + a.target} of RetroXR/godot at"
              f" {pin[:9]} there (docs/dev/engine-patches.md), set RETROXR_GODOT_DIR to its checkout, or pass --so",
              file=sys.stderr)
        return 1
    if not _names_commit(so, pin[:9]):
        print(f"{so} is not engine {pin[:9]} (Tools/engine/ENGINE_COMMIT): check out that commit in the engine"
              f" tree and rebuild template_{a.target}, or move the pin", file=sys.stderr)
        return 1
    if _carries(aar, so):
        print(f"{os.path.relpath(aar, ROOT)} already carries {os.path.basename(so)}")
        return 0
    if a.check:
        print(f"{os.path.relpath(aar, ROOT)} does NOT carry {os.path.basename(so)} (stock, or an older build)", file=sys.stderr)
        return 1
    if not os.path.exists(bak):
        shutil.copyfile(aar, bak)
    tmp = aar + ".tmp"
    replaced = False
    with zipfile.ZipFile(bak) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == ENTRY:
                zout.write(so, item.filename)
                replaced = True
            else:
                zout.writestr(item, zin.read(item.filename))
    if not replaced:
        os.remove(tmp)
        print(f"{ENTRY} not found in {aar}", file=sys.stderr)
        return 1
    os.replace(tmp, aar)
    print(f"placed {os.path.basename(so)} ({os.path.getsize(so)} bytes) into {os.path.relpath(aar, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
