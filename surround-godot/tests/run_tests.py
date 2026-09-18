#!/usr/bin/env python3
"""Build and run surround-godot's standalone C++ tests.

These need no Godot, no core and no audio device: each test compiles against the
vendored decoder directly, which is what lets the matrix cases assert that a
synthesised Dolby Surround encode comes back out where it went in.

    python tests/run_tests.py
    python tests/run_tests.py --only matrix
"""

import argparse
import glob
import os
import platform
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VENDOR = os.path.join(ROOT, "external", "freesurround")

# test source -> extra sources it needs
TESTS = {
    "discrete_ring_test.cpp": [],
    "matrix_decode_test.cpp": sorted(glob.glob(os.path.join(VENDOR, "source", "*.cpp"))),
}

INCLUDES = [os.path.join(VENDOR, "include"), os.path.join(ROOT, "src")]


def find_vcvars():
    """Newest vcvars64.bat, so the Windows SDK headers are reachable."""
    roots = [
        r"C:\Program Files\Microsoft Visual Studio",
        r"C:\Program Files (x86)\Microsoft Visual Studio",
    ]
    found = []
    for root in roots:
        found += glob.glob(os.path.join(root, "*", "*", "VC", "Auxiliary", "Build", "vcvars64.bat"))
    return sorted(found)[-1] if found else None


def build_windows(test_src, extra, out_exe, workdir):
    vcvars = find_vcvars()
    if not vcvars:
        raise SystemExit("no vcvars64.bat found; install the MSVC build tools")
    incs = " ".join('/I"%s"' % i for i in INCLUDES)
    vendored = " ".join('"%s"' % s for s in extra)
    # Driven through a batch file rather than cmd.exe /c: a command line that
    # begins with a quoted path gets its quotes eaten by cmd's own parsing and
    # exits 1 with nothing on either stream.
    #
    # The vendored decoder is compiled at /W0 and ours at /W4, so third-party
    # noise cannot hide a warning in the test itself.
    script = os.path.join(workdir, "build.bat")
    # A test with no vendored sources compiles alone: cl refuses an empty /c,
    # and *.obj would link in whatever an earlier test left in the directory.
    lines = [
        "@echo off",
        'call "%s" >nul 2>&1 || exit /b 1' % vcvars,
    ]
    if extra:
        lines.append('cl /nologo /EHsc /std:c++17 /W0 /c %s %s || exit /b 1' % (incs, vendored))
    lines.append('cl /nologo /EHsc /std:c++17 /W4 %s "%s" %s /Fe:"%s" || exit /b 1'
                 % (incs, test_src, "*.obj" if extra else "", out_exe))
    with open(script, "w") as handle:
        handle.write(chr(10).join(lines) + chr(10))
    return subprocess.run([script], capture_output=True, text=True, cwd=workdir)


def build_posix(test_src, extra, out_exe, workdir):
    cxx = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
    if not cxx:
        raise SystemExit("no C++ compiler found; set CXX")
    incs = []
    for i in INCLUDES:
        incs += ["-I", i]
    objs = []
    for src in extra:
        obj = os.path.join(workdir, os.path.basename(src) + ".o")
        done = subprocess.run([cxx, "-std=c++17", "-O1", "-w", "-c"] + incs + [src, "-o", obj],
                              capture_output=True, text=True)
        if done.returncode != 0:
            return done
        objs.append(obj)
    return subprocess.run([cxx, "-std=c++17", "-O1", "-g", "-Wall", "-Wextra", "-Werror"]
                          + incs + [test_src] + objs + ["-o", out_exe, "-lm"],
                          capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repeat", type=int, default=1, help="run each test N times")
    ap.add_argument("--only", help="run just the tests whose source name contains this")
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="surround-godot-tests-")
    windows = platform.system() == "Windows"
    failures = []

    try:
        for src, extra in sorted(TESTS.items()):
            if args.only and args.only not in src:
                continue
            name = os.path.splitext(src)[0]
            test_src = os.path.join(HERE, src)
            # A directory each: cl leaves every object beside the build, and the
            # link takes *.obj, so a second test would link the first one's main.
            test_dir = os.path.join(workdir, name)
            os.makedirs(test_dir)
            out_exe = os.path.join(test_dir, name + (".exe" if windows else ""))

            print("=== %s ===" % name, flush=True)
            build = build_windows(test_src, extra, out_exe, test_dir) if windows \
                else build_posix(test_src, extra, out_exe, test_dir)
            if build.returncode != 0:
                sys.stdout.write(build.stdout or "")
                sys.stdout.write(build.stderr or "")
                print("  build failed (exit %d)" % build.returncode)
                failures.append(name + " (build)")
                continue

            for run in range(args.repeat):
                result = subprocess.run([out_exe], capture_output=True, text=True)
                if result.returncode != 0:
                    print(result.stdout)
                    failures.append("%s (run %d)" % (name, run + 1))
                    break
                if run == 0:
                    print(result.stdout, end="")
            else:
                if args.repeat > 1:
                    print("  %d runs, all clean" % args.repeat)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    if failures:
        print("\nFAILED: " + ", ".join(failures))
        return 1
    print("\nall tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
