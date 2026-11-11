#!/usr/bin/env python3
"""Build a RetroXR Linux AppImage (x86_64) from this checkout, in one command.

    python Tools/build_appimage.py
    python Tools/build_appimage.py --steps export,package      # skip the C++ and the import
    python Tools/build_appimage.py --godot ~/Godot/Godot_v4.7.2-stable_linux.x86_64
    python Tools/build_appimage.py --name RetroXR-arcade-test.AppImage --smoke

The same four steps `release.yml` runs for its Linux x86_64 job, so a local AppImage is
the one CI would make:

  build    the Linux GDExtensions, template_release (Tools/build.py)
  import   Godot imports the project and fails on any script or shader error
  export   the "Linux" preset -> build_out/RetroXR.x86_64 (pck embedded) + libSDL3
  package  an AppDir (hardlinks, so no second copy of a 400 MB binary) -> appimagetool

Output: build_out/RetroXR-linux-x86_64-<version>.AppImage (build_out/ is gitignored).

What it takes care of, because each one cost a build once:

  * Git LFS. Without it the GLBs are 130-byte pointer files and the build has no console
    or cartridge models. It checks, and pulls (--no-lfs to refuse instead).
  * Disk space. The export is ~400 MB, the AppImage ~180 MB, the import cache ~0.5 GB.
    It stops before starting if there is less than --min-free-gb (default 3) free.
  * libstdc++.a. A distro without the static libstdc++ (Fedora: libstdc++-static) cannot
    link with godot-cpp's default, so it is detected and `use_static_cpp=no` passed; the
    AppImage then uses the host's libstdc++.
  * libvlc.so. vlc-godot links the SYSTEM libvlc, which needs the development symlink
    (Fedora: vlc-devel). When only the runtime library is installed, a stub directory is
    made and vlc-godot/SConscript patched for the duration of the build, then RESTORED
    (--no-vlc-stub to refuse; installing vlc-devel is the real fix).

At run time the AppImage needs the host's libvlc (vlc-libs) and GL/Vulkan libraries; it
bundles libSDL3.so.0 from libretro-godot/external. FUSE is not required: appimagetool runs
with --appimage-extract-and-run, and so can the result (APPIMAGE_EXTRACT_AND_RUN=1).
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "RetroXR"
BUILD_OUT = REPO / "build_out"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "retroxr-appimage"
APPIMAGETOOL_URL = ("https://github.com/AppImage/AppImageKit/releases/download/"
                    "continuous/appimagetool-x86_64.AppImage")
BINARY_NAME = "RetroXR.x86_64"
STEPS = ("build", "import", "export", "package")

# What the import pass may print without it being our change: no OpenXR runtime, the
# GDExtension paths of other platforms, no .NET SDK, the XR staging shim.
IMPORT_NOISE = ("xrCreateInstance", ".NET Sdk", "xr_staging_shim")
IMPORT_ERRORS = re.compile(
    r"SCRIPT ERROR|Parse Error|SHADER ERROR|Failed to load|Failed to instantiate")

# A file known to be an LFS-tracked model: a pointer file (not smudged) starts with this.
LFS_PROBE = PROJECT / "imported-assets/consoles/nes/nes_console.glb"
LFS_MAGIC = b"version https://git-lfs"


def say(msg: str) -> None:
    print(f"[appimage] {msg}", flush=True)


def die(msg: str) -> "None":
    print(f"[appimage] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def run(cmd: list[str], *, cwd: Path = REPO, env: dict | None = None,
        log: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """Run a command, streaming to `log` when given (the import pass is very chatty)."""
    say("$ " + " ".join(str(c) for c in cmd))
    full_env = dict(os.environ, **(env or {}))
    # scons is installed with `pip install --user` / `uv tool install`, which put it in
    # ~/.local/bin: not always on PATH, and Tools/build.py wants it there.
    local_bin = str(Path.home() / ".local/bin")
    if local_bin not in full_env.get("PATH", "").split(os.pathsep):
        full_env["PATH"] = local_bin + os.pathsep + full_env.get("PATH", "")
    if log is not None:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("wb") as fh:
            proc = subprocess.run(cmd, cwd=cwd, env=full_env, stdout=fh,
                                  stderr=subprocess.STDOUT)
    else:
        proc = subprocess.run(cmd, cwd=cwd, env=full_env)
    if check and proc.returncode != 0:
        die(f"command failed (exit {proc.returncode}): {' '.join(str(c) for c in cmd)}"
            + (f"\n          log: {log}" if log else ""))
    return proc


# ── preconditions ───────────────────────────────────────────────────────────────

def check_platform() -> None:
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        die("this builds the x86_64 Linux AppImage and must run on Linux x86_64 "
            "(CI's linux-arm64 job makes a tarball, not an AppImage)")


def check_space(min_gb: float) -> None:
    for where in (REPO, CACHE.parent):
        free = shutil.disk_usage(where).free / 2**30
        if free < min_gb:
            die(f"only {free:.1f} GB free on the disk holding {where}; the build wants "
                f"{min_gb:g} GB (--min-free-gb to change it). Free some space first: a "
                f"disk that fills mid-export leaves a half-written package.")


def find_godot(explicit: str | None) -> str:
    if explicit:
        if not Path(explicit).exists():
            die(f"--godot: no such file: {explicit}")
        return explicit
    env = os.environ.get("GODOT")
    if env and Path(env).exists():
        return env
    home = Path.home()
    candidates: list[Path] = []
    for folder in (home / "Godot", home / "Applications", home / ".local/bin"):
        if folder.is_dir():
            candidates += sorted(folder.glob("Godot_v4.7*linux*x86_64"), reverse=True)
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        candidates.append(Path(found))
    for c in candidates:
        if c.is_file():
            return str(c)
    die("could not find Godot 4.7. Pass --godot <path> or set $GODOT.")


def check_templates() -> None:
    root = Path.home() / ".local/share/godot/export_templates"
    if not root.is_dir() or not any(root.glob("4.7*")):
        die(f"no Godot 4.7 export templates under {root}; install them from the editor "
            f"(Editor > Manage Export Templates) before exporting")


def ensure_lfs(allow_pull: bool) -> None:
    if not LFS_PROBE.exists():
        return
    if not LFS_PROBE.read_bytes()[:len(LFS_MAGIC)] == LFS_MAGIC:
        return
    if not allow_pull:
        die("the GLBs are Git LFS pointers (run `git lfs pull`): a build without them has "
            "no console or cartridge models")
    say("the GLBs are LFS pointers; pulling them (about 250 MB)")
    run(["git", "lfs", "pull"])
    if LFS_PROBE.read_bytes()[:len(LFS_MAGIC)] == LFS_MAGIC:
        die("git lfs pull ran but the GLBs are still pointers (is git-lfs installed?)")


# ── build ───────────────────────────────────────────────────────────────────────

def has_static_libstdcxx() -> bool:
    cxx = shutil.which("g++") or shutil.which("c++")
    if not cxx:
        return True
    out = subprocess.run([cxx, "-print-file-name=libstdc++.a"], capture_output=True,
                         text=True).stdout.strip()
    return os.path.isabs(out) and os.path.exists(out)


def libvlc_dev_present() -> bool:
    cc = shutil.which("gcc") or shutil.which("cc")
    if not cc:
        return True
    out = subprocess.run([cc, "-print-file-name=libvlc.so"], capture_output=True,
                         text=True).stdout.strip()
    return os.path.isabs(out) and os.path.exists(out)


def make_vlc_stub() -> Path | None:
    """A directory holding libvlc.so -> the runtime library, for linking only."""
    stub = CACHE / "vlcstub"
    found: dict[str, Path] = {}
    for libdir in ("/usr/lib64", "/usr/lib/x86_64-linux-gnu", "/usr/lib"):
        for name in ("libvlc", "libvlccore"):
            for cand in sorted(Path(libdir).glob(f"{name}.so.*")):
                found.setdefault(name, cand)
    if "libvlc" not in found:
        return None
    stub.mkdir(parents=True, exist_ok=True)
    for name, target in found.items():
        link = stub / f"{name}.so"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(target)
    return stub


class VlcLinkPatch:
    """Point vlc-godot's Linux link at `stub` for the duration of a build, then restore.

    A context manager so an interrupted build cannot leave the SConscript changed."""

    SCONSCRIPT = REPO / "vlc-godot" / "SConscript"
    NEEDLE = "    env.Append(LIBS=['vlc'])\n"

    def __init__(self, stub: Path) -> None:
        self.stub = stub
        self.original = ""

    def __enter__(self) -> "VlcLinkPatch":
        self.original = self.SCONSCRIPT.read_text()
        first = self.original.index(self.NEEDLE)
        patched = (self.original[:first] + self.NEEDLE
                   + f"    env.Append(LIBPATH=['{self.stub}'])\n"
                   + self.original[first + len(self.NEEDLE):])
        self.SCONSCRIPT.write_text(patched)
        say(f"vlc-godot linked against the runtime libvlc through {self.stub} "
            f"(SConscript patched for this build, restored after)")
        return self

    def __exit__(self, *exc: object) -> None:
        self.SCONSCRIPT.write_text(self.original)


def step_build(jobs: int, allow_vlc_stub: bool) -> None:
    extra: list[str] = []
    if not has_static_libstdcxx():
        say("no static libstdc++ here: linking dynamically (use_static_cpp=no)")
        extra.append("use_static_cpp=no")
    cmd = [sys.executable, str(REPO / "Tools/build.py"), "linux", "--target", "release",
           "--jobs", str(jobs)]
    if extra:
        cmd += ["--"] + extra
    if not libvlc_dev_present():
        stub = make_vlc_stub() if allow_vlc_stub else None
        if stub is None:
            say("WARNING: no libvlc development link (install vlc-devel); vlc-godot will "
                "fail to link and the video player will be missing")
            run(cmd, check=False)
            return
        with VlcLinkPatch(stub):
            run(cmd)
        return
    run(cmd)


# ── import / export ─────────────────────────────────────────────────────────────

def step_import(godot: str) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    base = [godot, "--headless", "--path", str(PROJECT)]
    # See release.yml: `--import` is the only mode that waits for the scan, and only the
    # last --editor pass is an oracle for script errors.
    run(base + ["--import"], log=CACHE / "import.log", check=False)
    run(base + ["--editor", "--quit"], log=CACHE / "editor1.log", check=False)
    run(base + ["--editor", "--quit"], log=CACHE / "editor2.log", check=False)
    text = (CACHE / "editor2.log").read_text(errors="replace")
    errors = [ln for ln in text.splitlines()
              if IMPORT_ERRORS.search(ln) and not any(n in ln for n in IMPORT_NOISE)]
    if errors:
        print("\n".join(errors[:25]))
        die(f"the import reported {len(errors)} script/shader error(s) "
            f"(full log: {CACHE / 'editor2.log'})")
    say("import clean")


def step_export(godot: str) -> None:
    BUILD_OUT.mkdir(exist_ok=True)
    target = BUILD_OUT / BINARY_NAME
    if target.exists():
        target.unlink()
    run([godot, "--headless", "--path", str(PROJECT), "--export-release", "Linux",
         str(target)], log=CACHE / "export.log")
    if not target.is_file() or target.stat().st_size < 50 * 2**20:
        die(f"the export did not produce a usable {target.name} (log: {CACHE / 'export.log'})")
    # The extension links SDL3 by soname with no rpath, and many distros package none:
    # $ORIGIN finds it beside the executable.
    sdl3 = REPO / "libretro-godot/external/SDL3/lib/linux-x64/libSDL3.so.0"
    if not sdl3.is_file():
        die(f"missing {sdl3}")
    shutil.copy2(sdl3, BUILD_OUT / sdl3.name)
    say(f"exported {target} ({target.stat().st_size / 2**20:.0f} MB)")


# ── package ─────────────────────────────────────────────────────────────────────

def fetch_appimagetool() -> Path:
    tool = CACHE / "appimagetool"
    if tool.is_file():
        return tool
    CACHE.mkdir(parents=True, exist_ok=True)
    say(f"downloading appimagetool to {tool}")
    urllib.request.urlretrieve(APPIMAGETOOL_URL, tool)
    tool.chmod(0o755)
    return tool


def project_icon() -> Path:
    icon = PROJECT / "Textures/app_icon.png"
    if icon.is_file():
        return icon
    for cand in sorted((PROJECT / "Textures").glob("app_icon*.png")):
        return cand
    die("no app icon found under RetroXR/Textures")


def link_or_copy(src: Path, dst: Path) -> None:
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def step_package(out_name: str) -> Path:
    exported = BUILD_OUT / BINARY_NAME
    if not exported.is_file():
        die(f"{exported} is missing: run the export step first")
    tool = fetch_appimagetool()
    appdir = CACHE / "AppDir"
    if appdir.exists():
        shutil.rmtree(appdir)
    bindir = appdir / "usr/bin"
    bindir.mkdir(parents=True)
    for f in BUILD_OUT.iterdir():
        if f.is_file() and f.suffix not in (".apk", ".AppImage"):
            link_or_copy(f, bindir / f.name)
    (appdir / "retroXR.desktop").write_text(
        "[Desktop Entry]\nName=RetroXR\nExec=AppRun\nType=Application\n"
        "Categories=Game;Emulator;\nIcon=retroXR\n")
    apprun = appdir / "AppRun"
    apprun.write_text(
        '#!/bin/bash\nHERE="$(dirname "$(readlink -f "$0")")"\ncd "$HERE/usr/bin"\n'
        f'exec "./{BINARY_NAME}" "$@"\n')
    apprun.chmod(0o755)
    shutil.copy2(project_icon(), appdir / "retroXR.png")
    out = BUILD_OUT / out_name
    if out.exists():
        out.unlink()
    run([str(tool), "--appimage-extract-and-run", str(appdir), str(out)],
        env={"ARCH": "x86_64"}, log=CACHE / "appimagetool.log")
    shutil.rmtree(appdir, ignore_errors=True)
    if not out.is_file():
        die(f"appimagetool produced no file (log: {CACHE / 'appimagetool.log'})")
    out.chmod(0o755)
    say(f"built {out} ({out.stat().st_size / 2**20:.0f} MB)")
    return out


def smoke(appimage: Path, seconds: int) -> None:
    """Start it headless for a few seconds: a binary that cannot load its extensions or
    its pck dies at once, which is the one thing this can see."""
    say(f"smoke test: {seconds} s headless")
    try:
        proc = subprocess.run([str(appimage), "--headless", "--quit-after", "30"],
                              env=dict(os.environ, APPIMAGE_EXTRACT_AND_RUN="1"),
                              capture_output=True, text=True, timeout=seconds)
        tail = (proc.stdout + proc.stderr).strip().splitlines()[-6:]
        say(f"exited {proc.returncode}")
        print("\n".join(tail))
    except subprocess.TimeoutExpired:
        say("still running after the timeout, so it started")


# ── main ────────────────────────────────────────────────────────────────────────

def version_name() -> str:
    version = "dev"
    text = (PROJECT / "project.godot").read_text()
    m = re.search(r'^config/version="([^"]+)"', text, re.MULTILINE)
    if m:
        version = m.group(1)
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                         capture_output=True, text=True).stdout.strip()
    return f"{version}-{sha}" if sha else version


def main() -> None:
    ap = argparse.ArgumentParser(description="Build a RetroXR Linux AppImage (x86_64).",
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split("\n\n", 1)[1])
    ap.add_argument("--steps", default=",".join(STEPS),
                    help=f"comma list of {', '.join(STEPS)} (default: all)")
    ap.add_argument("--godot", help="Godot 4.7 binary (default: $GODOT, then ~/Godot, "
                                    "~/Applications, PATH)")
    ap.add_argument("--name", help="output file name (default: "
                                   "RetroXR-linux-x86_64-<version>-<sha>.AppImage)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) // 2),
                    help="parallel compile jobs for the C++ (default: half the cores)")
    ap.add_argument("--min-free-gb", type=float, default=3.0)
    ap.add_argument("--no-lfs", action="store_true", help="refuse to `git lfs pull`")
    ap.add_argument("--no-vlc-stub", action="store_true",
                    help="do not patch vlc-godot's link when only libvlc's runtime is installed")
    ap.add_argument("--smoke", action="store_true", help="start the result headless for a moment")
    args = ap.parse_args()

    steps = [s.strip() for s in args.steps.split(",") if s.strip()]
    bad = [s for s in steps if s not in STEPS]
    if bad:
        die(f"unknown step(s): {', '.join(bad)} (known: {', '.join(STEPS)})")

    check_platform()
    check_space(args.min_free_gb)
    started = time.time()
    out_name = args.name or f"RetroXR-linux-x86_64-{version_name()}.AppImage"

    godot = ""
    if any(s in steps for s in ("import", "export")):
        godot = find_godot(args.godot)
        say(f"Godot: {godot}")
    if any(s in steps for s in ("import", "export")):
        ensure_lfs(not args.no_lfs)
    if "export" in steps:
        check_templates()

    if "build" in steps:
        step_build(args.jobs, not args.no_vlc_stub)
    if "import" in steps:
        step_import(godot)
    if "export" in steps:
        step_export(godot)
    result = None
    if "package" in steps:
        result = step_package(out_name)
    if args.smoke and result is not None:
        smoke(result, 90)
    say(f"done in {time.time() - started:.0f} s" + (f": {result}" if result else ""))


if __name__ == "__main__":
    main()
