#!/usr/bin/env python3
"""Encode one of the welcome page's clips from a probe's frames.

    python Tools/art/encode_welcome_clip.py <frames dir> [--name menu_clip|hookup_clip]
        [--width 880] [--mp4 preview.mp4]

Reads <frames dir>/f_00000.png (or .jpg) ... at 30 fps and writes
RetroXR/Textures/welcome/<name>.ogv: Ogg Theora, no sound, which Godot plays with
its own VideoStreamPlayer on every platform, the Quest's patched engine included
(both carry the theora module). --width scales it (height follows, even); the
default keeps the frames' size. --mp4 also writes an H.264 copy, to look at
outside Godot.

    menu_clip    Tools/room/welcome_clip_probe   the menu being used, 880 x 720
    hookup_clip  Tools/room/nes_hookup_probe      an NES hooked up, 960 x 540

Uses the ffmpeg imageio-ffmpeg bundles (Tools/requirements.txt), which has
libtheora; a system ffmpeg may not.
"""

import argparse
import os
import subprocess
import sys

import imageio_ffmpeg

FPS = 30
# Theora's quality, 0-10. The menu is flat colour and text, the room is not: 7
# keeps the menu's text edges clean, 6 keeps the room clip a few MB.
QUALITY = {"menu_clip": 7, "hookup_clip": 6}
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "RetroXR", "Textures", "welcome")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("--name", default="menu_clip")
    ap.add_argument("--width", type=int, default=0)
    ap.add_argument("--mp4", default="")
    args = ap.parse_args()
    pattern = ""
    for ext in ("png", "jpg"):
        candidate = os.path.join(args.frames, "f_%05d." + ext)
        if os.path.exists(candidate % 0):
            pattern = candidate
    if not pattern:
        print(f"no frames f_00000.png/.jpg in {args.frames}", file=sys.stderr)
        return 1
    scale = ["-vf", f"scale={args.width}:-2"] if args.width > 0 else []
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    out = os.path.normpath(os.path.join(OUT_DIR, args.name + ".ogv"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", pattern, *scale,
                    "-c:v", "libtheora", "-q:v", str(QUALITY.get(args.name, 7)), "-pix_fmt", "yuv420p",
                    "-an", out], check=True)
    print(f"  {out}  {os.path.getsize(out) // 1024} KiB")
    if args.mp4:
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", pattern, *scale,
                        "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", "-an", args.mp4],
                       check=True)
        print(f"  {args.mp4}  {os.path.getsize(args.mp4) // 1024} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
