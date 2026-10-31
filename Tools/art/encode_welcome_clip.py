#!/usr/bin/env python3
"""Encode the welcome page's menu clip from welcome_clip_probe's frames.

    python Tools/art/encode_welcome_clip.py <frames dir> [--mp4 preview.mp4]

Reads <frames dir>/f_00000.png ... (30 fps, 880 x 720) and writes
RetroXR/Textures/welcome/menu_clip.ogv: Ogg Theora, no sound, which Godot plays
with its own VideoStreamPlayer on every platform, the Quest's patched engine
included (both carry the theora module). --mp4 also writes an H.264 copy, to
look at outside Godot.

Uses the ffmpeg imageio-ffmpeg bundles (Tools/requirements.txt), which has
libtheora; a system ffmpeg may not.
"""

import argparse
import os
import subprocess
import sys

import imageio_ffmpeg

FPS = 30
# Theora's quality, 0-10. The menu is flat colour and text: 7 keeps the text
# edges clean at about 1 MB a minute of mostly still UI.
QUALITY = 7
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "RetroXR", "Textures", "welcome",
                   "menu_clip.ogv")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("--mp4", default="")
    args = ap.parse_args()
    pattern = os.path.join(args.frames, "f_%05d.png")
    if not os.path.exists(pattern % 0):
        print(f"no frames at {pattern}", file=sys.stderr)
        return 1
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", pattern,
                    "-c:v", "libtheora", "-q:v", str(QUALITY), "-pix_fmt", "yuv420p", "-an",
                    os.path.normpath(OUT)], check=True)
    print(f"  {os.path.normpath(OUT)}  {os.path.getsize(OUT) // 1024} KiB")
    if args.mp4:
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", pattern,
                        "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", "-an", args.mp4],
                       check=True)
        print(f"  {args.mp4}  {os.path.getsize(args.mp4) // 1024} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
