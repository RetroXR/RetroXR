"""Measure the shading rate a Quest really used, from a capture of the foveation pattern.

    adb exec-out screencap -p > cap.png      # with vrsprobe.cfg {"fov_pattern": true, ...} live
    python Tools/perf/fov_pattern_map.py cap.png [--focus 0.2425,0.1932] [--cell 48]

The pattern (QualityManager._probe_foveation_pattern) gives every FRAGMENT its own random
colour, so a fragment shaded for a k x k block of pixels is a k x k block of one colour. Each
cell's rate is its pixel count over its count of colour changes, across and down. Prints a
grid per eye (1 = full rate, 2 = one fragment for two pixels a side, ...; 9 = 9 or coarser),
then how far from the lens centre each rate begins toward the four edges, as a fraction of
the way to that edge: an even ring reads the same four numbers. --focus is the LEFT eye's
(NDC, y up; the right eye mirrors x), default the buffer's middle.
"""
import argparse
import numpy as np
from PIL import Image


def rate(cell):
    """Mean block size (px) across and down in one cell, or 0 where the pattern is absent."""
    c = cell.astype(np.int32)
    across = (np.abs(np.diff(c, axis=1)).sum(axis=2) > 24).sum()
    down = (np.abs(np.diff(c, axis=0)).sum(axis=2) > 24).sum()
    h, w = c.shape[:2]
    if across < h or down < w:          # under one change a row: not the pattern (lens mask)
        return 0.0, 0.0
    return h * (w - 1) / across, w * (h - 1) / down


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--focus", default="0,0")
    ap.add_argument("--cell", type=int, default=48)
    args = ap.parse_args()
    fx, fy = (float(v) for v in args.focus.split(","))
    im = np.asarray(Image.open(args.capture).convert("RGB"))
    half = im.shape[1] // 2
    cell = args.cell
    for name, x0, focus_x in (("LEFT", 0, fx), ("RIGHT", half, -fx)):
        eye = im[:, x0:x0 + half]
        rows, cols = eye.shape[0] // cell, eye.shape[1] // cell
        grid = np.zeros((rows, cols, 2))
        for r in range(rows):
            for c in range(cols):
                grid[r, c] = rate(eye[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell])
        print("%s eye, %dx%d px, cell %d px: block size across (left) and down (right)"
              % (name, eye.shape[1], eye.shape[0], cell))
        for r in range(rows):
            line = lambda k: "".join(" " if v == 0 else str(min(9, int(round(v)))) for v in grid[r, :, k])
            print("  " + line(0) + "    " + line(1))
        # Walk from the lens centre toward each edge and report where each rate begins.
        cx = (focus_x + 1.0) * 0.5 * cols
        cy = (1.0 - fy) * 0.5 * rows
        mean = grid.mean(axis=2)
        print("  lens centre at cell (%.1f, %.1f); rate there %.2f" % (cx, cy, mean[int(cy), int(cx)]))
        walks = {"up": (0, -1, cy), "down": (0, 1, rows - cy), "left": (-1, 0, cx), "right": (1, 0, cols - cx)}
        for side, (dx, dy, reach) in walks.items():
            marks = []
            seen = 1.0
            for step in range(int(reach)):
                x, y = int(cx + dx * step), int(cy + dy * step)
                if not (0 <= x < cols and 0 <= y < rows) or mean[y, x] == 0:
                    marks.append("mask at %.2f" % (step / reach))
                    break
                if mean[y, x] >= seen * 1.5:
                    seen = mean[y, x]
                    marks.append("%.1fx at %.2f" % (seen, step / reach))
            print("  %-5s %s" % (side, ", ".join(marks) if marks else "full rate to the edge"))
        print()


if __name__ == "__main__":
    main()
