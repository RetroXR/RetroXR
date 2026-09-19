"""Frames from RetroXR/Tools/vr/book_flop_probe -> an mp4 and a contact sheet.

    python Tools/book_flop_video.py <frames dir> [--out book_flop]

Writes <out>.mp4 (libx264, crf 24, 30 fps) and <out>_sheet.jpg: the last frame of
every captioned segment, which is the settled pose -- the one to judge a hang by.
The mp4 is for the motion: the swing on the way there, and the shake.
"""
import argparse
import pathlib
import sys

import imageio.v2 as imageio
import numpy as np
from PIL import Image, ImageDraw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    src = pathlib.Path(args.frames)
    frames = sorted(src.glob("f_*.jpg"))
    if not frames:
        print(f"no frames in {src}", file=sys.stderr)
        return 1
    out = pathlib.Path(args.out) if args.out else src / "book_flop"

    captions = {}
    cap_file = src / "captions.txt"
    if cap_file.exists():
        for line in cap_file.read_text(encoding="utf-8").splitlines():
            idx, _, text = line.partition("\t")
            captions[int(idx)] = text

    def labelled(i: int, path: pathlib.Path) -> Image.Image:
        img = Image.open(path).convert("RGB")
        text = captions.get(i, "")
        if text:
            draw = ImageDraw.Draw(img)
            draw.rectangle([0, 0, img.width, 22], fill=(0, 0, 0))
            draw.text((8, 5), text, fill=(255, 255, 255))
        return img

    mp4 = out.with_suffix(".mp4")
    with imageio.get_writer(mp4, fps=30, codec="libx264", output_params=["-crf", "24"],
                            macro_block_size=8) as writer:
        for i, path in enumerate(frames):
            writer.append_data(np.asarray(labelled(i, path)))
    print(f"wrote {mp4} ({len(frames)} frames)")

    # Last frame of each segment.
    ends = []
    for i in range(len(frames)):
        if i + 1 == len(frames) or captions.get(i + 1) != captions.get(i):
            ends.append(i)
    thumbs = [labelled(i, frames[i]).resize((400, 300)) for i in ends]
    cols = 3
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 400, rows * 300), (20, 20, 24))
    for n, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((n % cols) * 400, (n // cols) * 300))
    sheet_path = out.parent / (out.name + "_sheet.jpg")
    sheet.save(sheet_path, quality=88)
    print(f"wrote {sheet_path} ({len(thumbs)} poses)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
