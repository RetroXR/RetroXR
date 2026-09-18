#!/usr/bin/env python3
"""Check the surround device output on a 3.1, 5.1 and 7.1 device.

The output is the road the six decoded channels take to a PC wired for more than
stereo (surround-godot's SurroundOutput): a bus of its own whose effect writes each
speaker pair. This machine's own device may well be stereo, and there is no way to
switch the AudioServer into 5.1 from a script, so the movie writer stands in for
the device: its speaker mode is what the dummy driver runs at.

That setting can only come from project settings, read before any script runs, so
this writes a temporary RetroXR/override.cfg (and refuses to touch one that is
already there), runs Tools/av/surround_output_probe.tscn under --write-movie, and
removes the file again whatever happens. The probe plays each decoded channel in
turn and reads the Master bus's peak meter on every speaker pair; the recording
itself is thrown away (see the probe for why it cannot be read).

With --rom it then runs Tools/av/surround_probe.tscn --held at 5.1 with a real
core: the machine decoding, its picture taken to the window, and the game expected
on the device's centre with the voices silent.

    python Tools/surround_output_check.py              # 3.1, 5.1 and 7.1
    python Tools/surround_output_check.py --mode 5.1
    python Tools/surround_output_check.py --mode 5.1 --rom ~/retroxr/roms/nes/<a game>.nes
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "RetroXR")
OVERRIDE = os.path.join(PROJECT, "override.cfg")
GODOT_WIN = r"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
GODOT_LINUX = os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64")

# Godot's AudioServer.SpeakerMode for each layout.
MODES = {"3.1": 1, "5.1": 2, "7.1": 3}


def godot_binary():
    path = GODOT_WIN if os.name == "nt" else GODOT_LINUX
    if not os.path.exists(path):
        raise SystemExit("Godot 4.7.2 not found at " + path)
    return path


def run(name, scene="res://Tools/av/surround_output_probe.tscn", user_args=(), tag="[probe]"):
    if os.path.exists(OVERRIDE):
        raise SystemExit("RetroXR/override.cfg already exists; not overwriting someone else's")
    workdir = tempfile.mkdtemp(prefix="surround-output-")
    print("=== %s %s ===" % (name, os.path.basename(scene)), flush=True)
    try:
        with open(OVERRIDE, "w") as handle:
            handle.write("[editor]\n\nmovie_writer/speaker_mode=%d\n" % MODES[name])
        cmd = [godot_binary(), "--path", PROJECT, "--resolution", "320x240",
               "--position", "20,20", "--log-file", os.path.join(workdir, "godot.log"),
               "--write-movie", os.path.join(workdir, "take.png"), scene]
        if user_args:
            cmd += ["--"] + list(user_args)
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    finally:
        if os.path.exists(OVERRIDE):
            os.remove(OVERRIDE)
        shutil.rmtree(workdir, ignore_errors=True)
    for line in (done.stdout or "").splitlines():
        if tag in line:
            print("    " + line.replace(tag + " ", ""))
    return done.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=sorted(MODES), help="one speaker layout only")
    ap.add_argument("--rom", help="also run the real-core probe, held, at 5.1")
    ap.add_argument("--root", default=os.path.expanduser("~/retroxr/libretro"), help="libretro root")
    ap.add_argument("--core", default="fceumm")
    args = ap.parse_args()
    failed = [name for name in ([args.mode] if args.mode else ["3.1", "5.1", "7.1"])
              if not run(name)]
    if args.rom:
        held = ["--root=" + args.root, "--core=" + args.core, "--rom=" + args.rom, "--held"]
        if not run("5.1", "res://Tools/av/surround_probe.tscn", held, "[surround]"):
            failed.append("5.1 held with " + args.core)
    if failed:
        print("\nFAILED: " + ", ".join(failed))
        return 1
    print("\nevery channel on its own speaker at its own level, and nowhere else")
    return 0


if __name__ == "__main__":
    sys.exit(main())
