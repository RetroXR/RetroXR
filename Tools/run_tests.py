#!/usr/bin/env python3
"""Run every self-checking suite in RetroXR/Tests, in one command.

    python Tools/run_tests.py
    python Tools/run_tests.py --only rope_tests
    python Tools/run_tests.py --only netplay_tests,scene_tests
    python Tools/run_tests.py --list
    python Tools/run_tests.py --only rope_tests -- --only=contact

Everything under RetroXR/Tests/ is a suite that checks itself, runs unattended
with no ROM, core, headset or device, and exits non-zero on failure. Every suite
extends RetroXR/Tests/test_suite.gd (TestSuite), whose _finish() prints ONE
summary line in one format,

    [<tag>] RESULT <passed> passed, <failed> failed: PASS|FAIL

and sets the exit code from the same tally. The exit code is the verdict; the
summary line is where the case count comes from, and that count is what the
baseline guard compares. A suite that exits 0 without the line did not finish
through the harness (it quit some other way), so its count is unknown and it is
reported NOSUMMARY rather than OK. One thing else is read from the output: a
SCRIPT ERROR in a suite that still exits 0 (see SCRIPT below).

By default suites run SEQUENTIALLY. Each one writes the player's real
`user://` state -- prefs.json, controller_bindings.json, the arcade manifest,
core_options/ -- and each snapshots and restores its own. Two at once in the
same `user://` would restore each other's snapshots and leave the player's
settings wherever the race landed.

`--jobs N` runs N at once by taking that shared state away instead: every suite
gets a fresh, empty scratch home -- `user://` (APPDATA / XDG_DATA_HOME), the
`~/retroxr` data root (USERPROFILE / HOME) and the temp folder -- deleted after
it, so no two suites see each other's files and none touches the player's (an
empty home is what CI's runner has anyway). Network ports cannot be redirected
that way, so every suite whose script may open a socket (`NET_HINT`) waits for
the one before it, in a lane of its own. The longest suites start first, by the
times of the last parallel run (`.godot/run_tests_times.json`).

Anything after a bare `--` is forwarded to every suite, which is how a suite's
own `--only=<group>` filter is reached. That is a different flag from this
script's `--only`, which picks whole suites.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock

REPO = Path(__file__).resolve().parent.parent
PROJECT = REPO / "RetroXR"
TESTS_DIR = PROJECT / "Tests"

# A failing suite's detail line is where the em dash lives ("FAIL name — why"),
# so a cp1252 console dies exactly when it is finally printing something worth
# reading. Force UTF-8 out rather than lose the one report that matters.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

# Longest measured run is rope_tests at ~2 min. The default leaves generous head
# room on a cold cache or a slower box; a suite that blows through it is hung,
# not slow, and is reported as TIMEOUT rather than silently waited on.
DEFAULT_TIMEOUT = 420

# Pre-existing headless noise, documented in CLAUDE.md as not-your-change: no
# OpenXR runtime, the template_debug GDExtension paths that only exist after a
# build, no .NET SDK, and the XR staging shim's placeholder instance. Filtered
# from the captured output so a real error is not buried in it.
NOISE = re.compile(
    r"xrCreateInstance failed"
    r"|libgodotopenxrvendors"
    r"|godot-pdfium|libpdfium"
    r"|libretro_godot|libvlc_godot|libverlet_rope|libarchive_godot|metaxr_audio"
    r"|\.NET Sdk not found|Unable to load .NET runtime"
    r"|xr_staging_shim\.gd"
    r"|is_xr_class"
    r"|placeholder instance"
    r"|GDExtension dynamic library not found"
    r"|Can't open dynamic library"
    # The desktop box has no headset, so OpenXR always fails to bring one up and
    # says so across six lines including a Windows Mixed Reality aside.
    r"|HMD was not detected"
    r"|Check logged errors in debugger"
    r"|Windows Mixed Reality"
    r"|Godot will start in normal mode"
    r"|initialize_openxr_module"
    r"|Unicode parsing error"
    r"|Failed to create XR instance"
    r"|OpenXR was requested but failed to start",
    re.IGNORECASE,
)

# A suite whose script matches this may listen on a fixed port (netplay's 42913,
# object_sync's 42917, the fake RomM / mod.io / update servers), so under --jobs
# these run one at a time. A false match costs only parallelism.
NET_HINT = re.compile(
    r"ENetMultiplayerPeer|create_server|create_client|TCPServer|UDPServer|PacketPeerUDP"
    r"|\.listen\(|NetworkManager|WebFileServer|NetplaySession|HTTPRequest")

TIMES = PROJECT / ".godot" / "run_tests_times.json"

# The one summary line TestSuite._finish() prints. Anchored on the RESULT word and
# the closing verdict, so a case's own description can never be read as it. Before
# the shared harness there were five shapes, scraped by three regexes and a
# per-case fallback, and a suite that re-worded its summary silently changed the
# count the baseline guard compared.
SUMMARY = re.compile(
    r"^\[[^\]\s]+\] RESULT (\d+) passed, (\d+) failed: (?:PASS|FAIL)\s*$", re.MULTILINE)


def find_godot(explicit: str | None) -> str:
    """Locate a Godot 4.7 binary, preferring the console build on Windows.

    The plain Windows .exe is a GUI launcher that detaches, so its stdout never
    reaches us and every suite would look like it produced no output at all.
    """
    if explicit:
        if not Path(explicit).exists():
            sys.exit(f"--godot: no such file: {explicit}")
        return explicit

    env = os.environ.get("GODOT")
    if env and Path(env).exists():
        return env

    candidates = [
        Path("C:/Program Files/Godot/Godot_v4.7.2-stable_win64.exe/"
             "Godot_v4.7.2-stable_win64_console.exe"),
        Path.home() / "Godot/Godot_v4.7.2-stable_linux.x86_64",
        Path("C:/Program Files/Godot/Godot_v4.7-stable_win64/"
             "Godot_v4.7-stable_win64_console.exe"),
        Path.home() / "Godot/Godot_v4.7-stable_linux.x86_64",
        Path("/Applications/Godot.app/Contents/MacOS/Godot"),
    ]
    for c in candidates:
        if c.exists():
            return str(c)

    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            return found

    sys.exit(
        "could not find Godot 4.7. Pass --godot <path> or set $GODOT.\n"
        "  Windows: C:/Program Files/Godot/Godot_v4.7.2-stable_win64.exe/"
        "Godot_v4.7-stable_win64_console.exe\n"
        "  Linux:   ~/Godot/Godot_v4.7.2-stable_linux.x86_64"
    )


def discover() -> list[str]:
    """Every Tests/*.tscn that has a script beside it, in a stable order."""
    if not TESTS_DIR.is_dir():
        sys.exit(f"no such directory: {TESTS_DIR}")
    names = sorted(
        p.stem for p in TESTS_DIR.glob("*.tscn") if (TESTS_DIR / f"{p.stem}.gd").exists()
    )
    if not names:
        sys.exit(f"no suites found in {TESTS_DIR}")
    return names


def scrape(text: str) -> tuple[int, int] | None:
    """(checks, failures) from the suite's summary line, or None without one.

    A crashing suite can lose whatever stdout was still buffered, so the line can
    be missing for exactly the runs you most want to read; the verdict is still
    the exit status. The LAST line wins, though a suite prints it once.
    """
    found = None
    for found in SUMMARY.finditer(text):
        pass
    if found is None:
        return None
    passed, failed = int(found.group(1)), int(found.group(2))
    return passed + failed, failed


BASELINE = Path(__file__).resolve().parent / "test_baseline.json"


def load_baseline() -> dict[str, int]:
    """Each suite's known case count, or an empty map when the file is absent."""
    if not BASELINE.exists():
        return {}
    try:
        raw = json.loads(BASELINE.read_text(encoding="utf-8")).get("suites", {})
        return {str(k): int(v) for k, v in raw.items()}
    except (ValueError, OSError) as exc:
        # A damaged baseline must not stop the suites from running: it is a
        # guard over them, not a precondition for them.
        print(f"[tests] ignoring unreadable {BASELINE.name}: {exc}")
        return {}


def write_baseline(counts: dict[str, int]) -> None:
    BASELINE.write_text(json.dumps({
        "_comment": "Case counts per suite. A DROP fails the run: a suite whose "
                    "group quietly stops running still passes every case it did "
                    "run and still exits 0, which is the one failure a green CI "
                    "cannot show you. Counts rise as cases are added -- rerun "
                    "with --update-baseline and commit this alongside them.",
        "suites": dict(sorted(counts.items())),
    }, indent=2) + "\n", encoding="utf-8")


def check_baseline(results: list[tuple[str, str, int, int, float]]) -> list[str]:
    """Suites whose count fell below the recorded baseline.

    Only a DROP is reported. A rise is how the suites are supposed to grow, and
    a suite absent from the file is new rather than broken — both pass, so
    adding cases never needs a second commit to keep the run green.
    """
    known = load_baseline()
    dropped = []
    for name, status, checks, _failures, _secs in results:
        if status != "OK" or name not in known:
            continue
        if checks < known[name]:
            dropped.append(f"{name}: {checks} checks, baseline {known[name]}")
    return dropped


# A script error aborts the function it happened in and nothing else: the suite goes on, finishes and
# exits 0, having skipped everything that function had left to check (link_tests lost four cases to a
# stale property that way, and av_tests and system_tests printed one each for months). The exit code
# cannot see it, so the output is read for it. Anything NOISE filters is already gone from `clean`.
SCRIPT_ERROR = re.compile(r"^SCRIPT ERROR", re.MULTILINE)


def script_errors(clean: str) -> int:
    return len(SCRIPT_ERROR.findall(clean))


def verdict(code: int, timed_out: bool) -> str:
    """OK / FAIL / CRASH / TIMEOUT (SCRIPT is decided by the caller, from the output).

    A suite can print a clean summary and still die on the way out --
    motion_tests has passed every case and then segfaulted during teardown. That is still a red run, but it needs a different fix from a failed
    assertion, so the table says which one it was instead of calling both FAIL.
    """
    if timed_out:
        return "TIMEOUT"
    if code == 0:
        return "OK"
    # Windows hands back the exception code itself (0xC0000005 and friends);
    # POSIX shells report 128+signal. Either way it is not an orderly exit(1).
    if code > 128 or code < 0:
        return "CRASH"
    return "FAIL"


# A suite that fails one of 105 cases should report that one case, not all 105.
# Engine-level errors are kept too: a suite can exit non-zero having printed no
# FAIL line at all -- a parse error, a crash, a timeout -- and the reason is then
# only in these.
TROUBLE = re.compile(
    r"\bFAIL\b|\bTIMEOUT\b"
    r"|SCRIPT ERROR|Parse Error|SHADER ERROR"
    r"|Failed to load|Failed to instantiate"
    r"|ERROR:|USER ERROR:|WARNING:|USER WARNING:",
)


def interesting(text: str) -> str:
    lines = [ln for ln in text.splitlines() if TROUBLE.search(ln)]
    if not lines:
        # Nothing matched, so the tail is the only clue about how it died.
        lines = text.strip().splitlines()[-15:]
    return "\n".join(lines[:60]).strip()


def scratch_env(home: Path) -> dict[str, str]:
    """An environment whose user://, data root and temp folder all live in `home`."""
    env = dict(os.environ)
    tmp = home / "tmp"
    for d in (home / "AppData" / "Roaming", home / "AppData" / "Local",
              home / ".local" / "share", tmp):
        d.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        env["APPDATA"] = str(home / "AppData" / "Roaming")
        env["LOCALAPPDATA"] = str(home / "AppData" / "Local")
        env["USERPROFILE"] = str(home)
    else:
        env["HOME"] = str(home)
        env["XDG_DATA_HOME"] = str(home / ".local" / "share")
    env["TEMP"] = env["TMP"] = env["TMPDIR"] = str(tmp)
    return env


def is_net_suite(name: str) -> bool:
    try:
        return bool(NET_HINT.search((TESTS_DIR / f"{name}.gd").read_text(encoding="utf-8")))
    except OSError:
        return True


def run_one(godot: str, name: str, timeout: int, extra: list[str],
            allow_script_errors: bool = False,
            isolate: bool = False) -> tuple[str, int, int, float, str]:
    cmd = [godot, "--headless", "--path", str(PROJECT), f"res://Tests/{name}.tscn"]
    if extra:
        cmd += ["--", *extra]

    home = Path(tempfile.mkdtemp(prefix=f"retroxr_{name}_")) if isolate else None
    if not isolate:
        print(f"=== {name}", flush=True)
    started = time.time()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            env=scratch_env(home) if home else None,
        )
        code, out = proc.returncode, (proc.stdout or "") + (proc.stderr or "")
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        code, timed_out = 124, True
        out = (exc.stdout or "") + (exc.stderr or "")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
    finally:
        if home:
            shutil.rmtree(home, ignore_errors=True)

    secs = time.time() - started
    clean = "\n".join(ln for ln in out.splitlines() if not NOISE.search(ln))
    summary = scrape(clean)
    checks, failures = summary if summary is not None else (0, 0)

    status = verdict(code, timed_out)
    # Exit 0 and no summary line: the suite quit without going through
    # TestSuite._finish(), so the count the baseline guards is unknown.
    if status == "OK" and summary is None:
        status = "NOSUMMARY"
    hidden = script_errors(clean) if status == "OK" else 0
    if hidden and not allow_script_errors:
        status = "SCRIPT"
    # In parallel the header waits for the result, or the lines interleave.
    head = f"=== {name}\n" if isolate else ""
    if timed_out:
        print(f"{head}    TIMEOUT after {timeout}s", flush=True)
    else:
        note = f"  <-- exit 0x{code:08X}" if status == "CRASH" else ""
        if hidden:
            note = f"  <-- {hidden} SCRIPT ERROR(s) in a suite that exited 0"
        print(f"{head}    {status}  {checks} checks, {failures} failed  {secs:.1f}s{note}", flush=True)

    return status, checks, failures, secs, clean


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Run the RetroXR self-checking test suites.",
        epilog="Anything after a bare -- is forwarded to every suite "
               "(e.g. -- --only=contact).",
    )
    ap.add_argument("--only", help="comma-separated suite names (see --list)")
    ap.add_argument("--list", action="store_true", help="list the suites and exit")
    ap.add_argument("--godot", help="path to the Godot 4.7 binary")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                    help=f"per-suite seconds (default {DEFAULT_TIMEOUT})")
    ap.add_argument("--jobs", "-j", type=int, default=1,
                    help="suites at once, each in its own scratch user:// and data root "
                         "(default 1: sequential, in the player's real user://)")
    ap.add_argument("--verbose", action="store_true",
                    help="print each suite's filtered output, not only failures'")
    ap.add_argument("--allow-script-errors", action="store_true",
                    help="report a SCRIPT ERROR in a suite that exits 0 but do not fail the run for it")
    ap.add_argument("--update-baseline", action="store_true",
                    help="rewrite Tools/test_baseline.json from this run's counts")
    ap.add_argument("forward", nargs="*", help=argparse.SUPPRESS)
    args = ap.parse_args()

    suites = discover()
    if args.list:
        for s in suites:
            print(s)
        return 0

    if args.only:
        wanted = [s.strip() for s in args.only.split(",") if s.strip()]
        unknown = [w for w in wanted if w not in suites]
        if unknown:
            sys.exit(f"unknown suite(s): {', '.join(unknown)}\n"
                     f"available: {', '.join(suites)}")
        suites = wanted

    godot = find_godot(args.godot)
    extra = list(args.forward)

    print(f"[tests] {godot}")
    jobs = max(1, args.jobs)
    mode = "sequential" if jobs == 1 else f"{jobs} at once, isolated"
    print(f"[tests] {len(suites)} suite(s), {mode}"
          + (f", forwarding {' '.join(extra)}" if extra else ""))
    print()

    results: list[tuple[str, str, int, int, float]] = []
    outputs: dict[str, str] = {}
    wall = time.time()
    if jobs == 1:
        for name in suites:
            status, checks, failures, secs, out = run_one(godot, name, args.timeout, extra, args.allow_script_errors)
            results.append((name, status, checks, failures, secs))
            outputs[name] = out
            if args.verbose:
                print(out)
    else:
        results = run_parallel(godot, suites, jobs, args, extra, outputs)
    wall = time.time() - wall

    print("\n" + "=" * 66)
    for name, status, checks, failures, secs in results:
        print(f"  {status:<7} {name:<22} "
              f"{checks:>5} checks {failures:>4} failed {secs:7.1f}s")

    if jobs > 1:
        print(f"  wall clock {wall:.0f}s for {sum(r[4] for r in results):.0f}s of suite time")

    bad = [(n, s) for n, s, _, _, _ in results if s != "OK"]
    total = sum(c for _, _, c, _, _ in results)
    elapsed = sum(s for _, _, _, _, s in results)

    if bad:
        # Without this the table says which suite broke and nothing about why,
        # and re-running it by hand is the only way to find out.
        if not args.verbose:
            for name, _ in bad:
                print(f"\n----- {name} -----")
                print(interesting(outputs[name]) or "(no output)")
            print("\n(--verbose for the full log of every suite)")
        # A crash after every case passed is a different problem from a failed
        # assertion, and a script error that left the exit code 0 from both, so
        # name the kind rather than lumping them together.
        print(f"\n{len(bad)} of {len(results)} suites not OK: "
              + ", ".join(f"{n} ({s})" for n, s in bad))
        return 1

    # A suite whose group stopped running still passes every case it did run,
    # so the exit status alone cannot see it. The recorded count can.
    #
    # Skipped for a filtered run -- --only, or a forwarded --only= group --
    # where a lower count is the whole point rather than a regression.
    partial = bool(args.only) or any(a.startswith("--only=") for a in extra)
    if args.update_baseline:
        if partial:
            print("\nrefusing to write a baseline from a filtered run")
            return 1
        write_baseline({n: c for n, _, c, _, _ in results})
        print(f"\nwrote {BASELINE.name} from this run")
    elif not partial and (dropped := check_baseline(results)):
        print("\ncase count fell below the recorded baseline:")
        for line in dropped:
            print(f"  {line}")
        print("\nA suite that quietly stops running a group still passes every\n"
              "case it did run. If the drop is deliberate, rerun with\n"
              "--update-baseline and commit Tools/test_baseline.json with it.")
        return 1

    print(f"\nall {len(results)} suites OK -- {total} checks in {elapsed:.0f}s"
          + (f" of suite time, {wall:.0f}s wall clock" if jobs > 1 else ""))
    return 0


def run_parallel(godot: str, suites: list[str], jobs: int, args, extra: list[str],
                 outputs: dict[str, str]) -> list[tuple[str, str, int, int, float]]:
    """Run `suites` `jobs` at once, the network ones one at a time among them.

    The network suites are fed to ONE worker of their own, in order, and the
    rest to the other `jobs - 1`, so no worker ever sits waiting on a lock.
    Both queues go longest first, by the last run's times.
    """
    try:
        times = json.loads(TIMES.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        times = {}
    longest_first = sorted(suites, key=lambda n: -float(times.get(n, 30.0)))
    net = [n for n in longest_first if is_net_suite(n)]
    rest = [n for n in longest_first if n not in net]
    found: dict[str, tuple[str, str, int, int, float]] = {}
    print_lock = Lock()

    def one(name: str):
        return name, run_one(godot, name, args.timeout, extra, args.allow_script_errors, isolate=True)

    def net_lane():
        return [one(n) for n in net]

    def collect(name, res):
        status, checks, failures, secs, out = res
        found[name] = (name, status, checks, failures, secs)
        outputs[name] = out
        times[name] = round(secs, 1)
        if args.verbose:
            with print_lock:
                print(f"----- {name} -----\n{out}")

    with ThreadPoolExecutor(max_workers=max(1, jobs - 1)) as pool, \
            ThreadPoolExecutor(max_workers=1) as lane:
        lane_future = lane.submit(net_lane)
        for fut in as_completed([pool.submit(one, n) for n in rest]):
            collect(*fut.result())
        for name, res in lane_future.result():
            collect(name, res)

    if not args.only:
        try:
            TIMES.parent.mkdir(parents=True, exist_ok=True)
            TIMES.write_text(json.dumps(times, indent=1, sort_keys=True), encoding="utf-8")
        except OSError:
            pass
    return [found[n] for n in suites]


if __name__ == "__main__":
    sys.exit(main())
