#!/usr/bin/env python3
"""Runs arcade_scale_probe over a matrix of configurations, one Godot process each (a core
is never looped inside a process), and prints one table.

    python RetroXR/Tools/perf/run_arcade_matrix.py --godot ~/Godot/Godot_v4.7.2-stable_linux.x86_64 \
        --rom ~/retroxr/roms/mame/dino.zip --phase all --out /tmp/arcade_matrix

--phase scene   cabinets only, nothing powered: N = 0 1 2 4, then at N=4 the A/B switches
                (shadows off, interior hidden, glass off, camera turned away)
--phase core    a core running dino in N cabinets, MAME and FinalBurn Neo, paced and
                XENU_UNTHROTTLED (what the core costs), then the A/B switches at N=4
--phase all     both

--wrap "flatpak-spawn --host"   for a shell inside a sandbox whose libc is older than the one
                the extensions were built against (and that has no display).

The cores write options and saves under <root>; core_options/ and the dino save files are
snapshotted before the first run and put back byte for byte after the last.
Every run's RESULT json lands in --out/<name>.json.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def configs(phase: str, quick: bool) -> list[dict]:
    out: list[dict] = []
    ns = [0, 1, 4] if quick else [0, 1, 2, 4]
    if phase in ("scene", "all"):
        for n in ns:
            out.append({"name": f"scene_n{n}", "args": {"n": n, "state": "off"}})
        for tag, extra in (("noshadow", {"shadows": "off"}), ("nointerior", {"interior": "hidden"}),
                           ("noglass", {"glass": "off"}), ("away", {"view": "away"}),
                           ("minlights", {"lights": "min"})):
            out.append({"name": f"scene_n4_{tag}", "args": {"n": 4, "state": "off", **extra}})
    if phase in ("core", "all"):
        cores = ["fbneo", "mame"]
        for core in cores:
            for n in ([1, 4] if quick else [1, 2, 4]):
                out.append({"name": f"{core}_n{n}", "core": core, "args": {"n": n, "state": "on", "core": core}})
            for n in (1, 4):
                out.append({"name": f"{core}_n{n}_unthrottled", "core": core, "unthrottled": True,
                            "args": {"n": n, "state": "on", "core": core}})
        for tag, extra in (("noshadow", {"shadows": "off"}), ("away", {"view": "away"}),
                           ("nointerior", {"interior": "hidden"})):
            out.append({"name": f"fbneo_n4_{tag}", "core": "fbneo",
                        "args": {"n": 4, "state": "on", "core": "fbneo", **extra}})
    return out


def snapshot(root: Path, store: Path) -> None:
    store.mkdir(parents=True, exist_ok=True)
    for sub in ("core_options", "save/fbneo/fbneo", "save/mame/mame"):
        src = root / sub
        if src.is_dir():
            dst = store / sub
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)


def restore(root: Path, store: Path) -> None:
    for sub in ("core_options", "save/fbneo/fbneo", "save/mame/mame"):
        src = store / sub
        dst = root / sub
        if src.is_dir():
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
        elif dst.exists() and not src.exists():
            # the run created a directory that was not there: leave the player's tree as it was
            shutil.rmtree(dst)


def run_one(cfg: dict, a: argparse.Namespace, out: Path) -> dict | None:
    probe_args = [f"--{k}={v}" for k, v in cfg["args"].items()]
    probe_args += [f"--seconds={a.seconds}", f"--windows={a.windows}", f"--warmup={a.warmup}",
                   f"--size={a.size}", f"--rom={a.rom}"]
    godot = [a.godot, "--path", str(REPO / "RetroXR")]
    if a.display_driver:
        godot += ["--display-driver", a.display_driver]
    godot += ["--disable-vsync", "--resolution", "640x360", "--position", "20,20",
              "res://Tools/perf/arcade_scale_probe.tscn", "--", *probe_args]
    env_pairs = {"DISPLAY": os.environ.get("DISPLAY") or ":0", "WAYLAND_DISPLAY": os.environ.get("WAYLAND_DISPLAY", "wayland-0")}
    if cfg.get("unthrottled"):
        env_pairs["XENU_UNTHROTTLED"] = "1"
    if a.wrap:
        cmd = shlex.split(a.wrap) + [f"--directory={REPO}", "env", *[f"{k}={v}" for k, v in env_pairs.items()], *godot]
        env = None
    else:
        cmd = godot
        env = {**os.environ, **env_pairs}
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=a.timeout)
        text = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        text = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        print(f"  TIMEOUT after {a.timeout}s", file=sys.stderr)
    result = None
    for line in text.splitlines():
        if "[arcade_perf] RESULT " in line:
            try:
                result = json.loads(line.split("RESULT ", 1)[1])
            except json.JSONDecodeError:
                pass
    # A probe that hangs in teardown after its RESULT keeps drawing and eats the next run's GPU: reap it.
    stray = (shlex.split(a.wrap) if a.wrap else []) + ["pkill", "-f", "[r]es://Tools/perf/arcade_"]
    subprocess.run(stray, capture_output=True)
    (out / f"{cfg['name']}.log").write_text(text)
    if result is not None:
        (out / f"{cfg['name']}.json").write_text(json.dumps(result, indent=1))
    print(f"  {cfg['name']:<26} {time.time() - t0:5.0f}s  {'ok' if result and not result.get('failed') else 'FAILED'}", flush=True)
    return result


def _med(vals: list[float]) -> float:
    vals = sorted(vals)
    return vals[len(vals) // 2] if vals else 0.0


def row(name: str, runs: list[dict]) -> str:
    """One row for a configuration: the MEDIAN over its repeats, with the fps spread beside it."""
    runs = [r for r in runs if r and "engine" in r]
    if not runs:
        return f"| {name} | (no result) |||||||||||||"
    r = runs[-1]
    e = r["engine"]
    machines = r.get("machines", [])
    core_fps = "/".join(f"{_med([x['machines'][i]['fps'] for x in runs]):.0f}" for i in range(len(machines))) or "-"
    run_ms = "/".join(f"{_med([x['machines'][i]['run_ms_per_frame'] for x in runs]):.1f}" for i in range(len(machines))) or "-"
    worst = max([m["run_worst_ms"] for x in runs for m in x.get("machines", [])], default=0.0)
    fps = [x["fps"] for x in runs]
    return (f"| {name} | {_med(fps):.0f} ({min(fps):.0f}-{max(fps):.0f}) | {_med([x['gpu_ms'] for x in runs]):.1f} | "
            f"{_med([x.get('gpu_mhz_avg', 0) for x in runs]):.0f} | {_med([x.get('gpu_mcycles', 0) for x in runs]):.1f} | "
            f"{_med([x.get('main_cpu_ms_per_frame', 0) for x in runs]):.1f} | {_med([x.get('own_cores_busy', 0) for x in runs]):.2f} | "
            f"{_med([x.get('other_cores_busy', 0) for x in runs]):.1f} | {e['draw_calls']} | {e['primitives'] // 1000}k | {e['nodes']} | "
            f"{core_fps} | {run_ms} | {worst:.0f} | {_med([x['texture_update_ms_per_s'] for x in runs]):.1f} | "
            f"{_med([x['memory']['rss_mb'] for x in runs]):.0f} |")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--rom", required=True, help="the dino.zip to run (MAME needs qsound.zip beside it)")
    ap.add_argument("--phase", default="all", choices=["scene", "core", "all"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--root", default=str(Path.home() / "retroxr/libretro"))
    ap.add_argument("--wrap", default="")
    ap.add_argument("--display-driver", default="x11", dest="display_driver")
    ap.add_argument("--seconds", type=float, default=8)
    ap.add_argument("--windows", type=int, default=3)
    ap.add_argument("--warmup", type=float, default=6)
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--timeout", type=int, default=420)
    ap.add_argument("--only", default="", help="substring filter on the config name")
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--repeat", type=int, default=1, help="whole matrix N times, interleaved (A B C A B C): a machine "
                    "that is busy with something else moves every number, so a result is a median of repeats")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    root = Path(a.root)
    store = out / "snapshot"
    snapshot(root, store)
    grouped: dict[str, list[dict]] = {}
    order: list[str] = []
    failed = False
    try:
        for k in range(a.repeat):
            for cfg in configs(a.phase, a.quick):
                if a.only and a.only not in cfg["name"]:
                    continue
                run_cfg = {**cfg, "name": cfg["name"] if a.repeat == 1 else f"{cfg['name']}.r{k}"}
                r = run_one(run_cfg, a, out)
                if cfg["name"] not in grouped:
                    grouped[cfg["name"]] = []
                    order.append(cfg["name"])
                if r is None:
                    failed = True
                else:
                    grouped[cfg["name"]].append(r)
    finally:
        restore(root, store)
    head = ("| run | fps (min-max) | gpu ms | gpu MHz | gpu Mcycles/frame | main cpu ms/frame | own cores busy | OTHER cores busy | draws | prims | nodes | core fps "
            "| retro_run ms/frame | worst call ms | tex upload ms/s | rss MB |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    table = head + "\n" + "\n".join(row(n, grouped[n]) for n in order)
    (out / "table.md").write_text(table + "\n")
    print("\n" + table)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
