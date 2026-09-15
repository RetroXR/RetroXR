"""Build the Nintendo 64 controller diagram for the CONTROLS tab and print its anchors.

Source: MilkToastRat Pack, SVG/n64.svg (CC0-1.0),
https://github.com/milktoastrat/milktoastrat-pack

The wordmark's lettering is removed from the badge at the top of the shell (the
badge outline stays) and the viewBox is cropped to the drawing. Nothing else is
changed.

Anchors come from the source geometry: each button is a circle or an ellipse and
the d-pad is one path. The shoulders and Z are placed by hand.

The leads are laid out as ConsolePadDiagram._relayout_columns lays them out over
a sweep of panel sizes, and the script exits non-zero if two cross, or one runs
through another control's dot or across another control's button.

    python Tools/art/gen_n64_pad_art.py --in <n64.svg> \\
        --out RetroXR/Textures/Controllers/n64_pad.svg
    python Tools/art/gen_n64_pad_art.py --in <n64.svg> --search
"""

from __future__ import annotations

import argparse
import collections
import io
import itertools
import math
import os
import re
import sys

# The drawing's alpha spans x 21..979, y 47..961 of the source's 1000 square.
VIEWBOX = (13.0, 39.0, 974.0, 930.0)

# How far inside a d-pad arm's tip the dot sits, as a fraction of the arm.
ARM_INSET = 0.18

# Centroids of the shoulder grey left visible above the face, off a 1000 px
# render. The shoulder paths continue behind the face, so their extent cannot
# be used.
SHOULDERS = {"l": (198.1, 136.1), "r": (803.0, 136.8)}

YELLOW = "#f5c93c"  # C buttons
BLUE = "#3567b2"  # A
GREEN = "#12ab7e"  # B
RED = "#e34048"  # Start
STICK_CAP = "#cccccb"
DARK_GREY = "#6d6d6d"  # d-pad cross, stick gate
SHELL = "#d0d3db"

DPAD = ("up", "down", "left", "right")

# Mirrored from ConsolePadDiagram.
MAX_W = 1520.0
ROW_H = 50.0
STUB = 18.0
COL_W = 210.0
COL_GAP = 16.0
EDGE_PAD = 24.0
DOT_RADIUS = 5.0
LEAD_WIDTH = 2.0

# A lead may touch a button's rim; it must not enter this fraction of its radius.
CAP_CORE = 0.8

# ControlsBindingEditor._CONSOLE_DIAGRAM_H, the shortest panel a diagram gets.
MIN_PANEL_H = 470.0

SIZES = [(w, h) for w in range(900, 1701, 100)
         for h in sorted(set(list(range(480, 721, 40)) + [470, 620]))]
COARSE = [(w, h) for w in (900, 1200, 1600) for h in (470, 620, 720)]

# ConsolePadArt keys: RetroPad targets, plus the fixed labels "c" and "stick".
# "" is a blank slot.
LEFT = ["l", "up", "left", "right", "down", "start", "l2"]
RIGHT = ["r", "c", "", "y", "b", "stick"]

NUM = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?")
_ARITY = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2}


def path_points(d: str) -> list[tuple[float, float]]:
    """Every on-curve point of a path, in absolute coordinates."""
    pts = []
    x = y = sx = sy = 0.0
    for cmd, args in re.findall(r"([MmLlHhVvCcSsQqTtZz])([^MmLlHhVvCcSsQqTtZz]*)", d):
        if cmd in "Zz":
            x, y = sx, sy
            continue
        n = [float(v) for v in NUM.findall(args)]
        step = _ARITY[cmd.upper()]
        rel = cmd.islower()
        for i in range(0, len(n), step):
            a = n[i:i + step]
            if cmd in "Hh":
                x = x + a[0] if rel else a[0]
            elif cmd in "Vv":
                y = y + a[0] if rel else a[0]
            else:
                x, y = (x + a[-2], y + a[-1]) if rel else (a[-2], a[-1])
            if cmd in "Mm" and i == 0:
                sx, sy = x, y
            pts.append((x, y))
    return pts


def fills(svg: str) -> dict[str, str]:
    return {m.group(1): m.group(2).lower()
            for m in re.finditer(r"\.(cls-\d+)\s*\{\s*fill:\s*(#[0-9a-fA-F]{6})", svg)}


def attrs(tag: str) -> dict[str, str]:
    return dict(re.findall(r'([\w-]+)="([^"]*)"', tag))


def group(svg: str, gid: str) -> str:
    m = re.search(r'<g id="%s">(.*?)</g>' % gid, svg, re.S)
    if m is None:
        raise SystemExit('no <g id="%s"> in the source' % gid)
    return m.group(1)


def round_shapes(body: str, fill_of: dict[str, str], colour: str) -> list[tuple[float, float, float]]:
    """(cx, cy, r) of every circle or ellipse in `body` filled with `colour`."""
    out = []
    for tag in re.findall(r"<(?:circle|ellipse)\b[^>]*>", body):
        a = attrs(tag)
        if fill_of.get(a.get("class", "")) == colour:
            out.append((float(a["cx"]), float(a["cy"]), float(a.get("r", a.get("ry", "0")))))
    return out


def paths(body: str, fill_of: dict[str, str], colour: str) -> list[str]:
    return [attrs(tag)["d"] for tag in re.findall(r"<path\b[^>]*>", body)
            if fill_of.get(attrs(tag).get("class", "")) == colour]


def one(items: list, what: str):
    if len(items) != 1:
        raise SystemExit("expected one %s, found %d" % (what, len(items)))
    return items[0]


def drop_wordmark(svg: str) -> str:
    m = re.search(r'<g id="TEXT">\s*<rect[^>]*/>(\s*<g>.*?</g>)\s*</g>', svg, re.S)
    if m is None:
        raise SystemExit("no wordmark group in the source")
    letters = len(re.findall(r"<path\b", m.group(1)))
    if letters != 8:
        raise SystemExit("expected the wordmark's 8 letters, found %d" % letters)
    return svg[:m.start(1)] + svg[m.end(1):]


def z_anchor(body: str, fill_of: dict[str, str]) -> tuple[float, float]:
    """Z is on the back of the centre prong; the dot sits on the prong a third of
    the way from the stick's gate to the tip."""
    gate = one(round_shapes(body, fill_of, DARK_GREY), "stick gate")
    tip = max(p[1] for p in path_points(one(paths(body, fill_of, SHELL), "shell")))
    top = gate[1] + gate[2]
    return gate[0], top + (tip - top) / 3.0


def read_source(svg: str):
    """(anchors, buttons) in source units. A button is (owners, cx, cy, r): a
    lead for a key not in `owners` must not cross it."""
    fill_of = fills(svg)
    body = group(svg, "Body")
    buttons = group(svg, "Buttons")

    c = round_shapes(buttons, fill_of, YELLOW)
    if len(c) != 4:
        raise SystemExit("expected 4 C buttons, found %d" % len(c))

    cross = path_points(one(paths(buttons, fill_of, DARK_GREY), "d-pad"))
    x0, x1 = min(p[0] for p in cross), max(p[0] for p in cross)
    y0, y1 = min(p[1] for p in cross), max(p[1] for p in cross)
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    hx, hy = (x1 - x0) * 0.5 * (1.0 - ARM_INSET), (y1 - y0) * 0.5 * (1.0 - ARM_INSET)

    a = one(round_shapes(buttons, fill_of, BLUE), "A button")
    b = one(round_shapes(buttons, fill_of, GREEN), "B button")
    start = one(round_shapes(buttons, fill_of, RED), "Start button")
    stick = one(round_shapes(buttons, fill_of, STICK_CAP), "stick cap")

    # mupen64plus-next and parallel-n64 with Independent C-button Controls off:
    # N64 A is RetroPad B, N64 B is RetroPad Y, Z is L2.
    anchors = {
        "l": SHOULDERS["l"],
        "r": SHOULDERS["r"],
        "up": (cx, cy - hy),
        "down": (cx, cy + hy),
        "left": (cx - hx, cy),
        "right": (cx + hx, cy),
        "start": start[:2],
        "b": a[:2],
        "y": b[:2],
        "l2": z_anchor(body, fill_of),
        "c": (sum(p[0] for p in c) / 4.0, sum(p[1] for p in c) / 4.0),
        "stick": stick[:2],
    }
    caps = [(("c",),) + p for p in c] + [
        (("b",),) + a,
        (("y",),) + b,
        (("start",),) + start,
        (("stick",),) + stick,
        (DPAD, cx, cy, (x1 - x0) * 0.5),
    ]
    return anchors, caps


def normalize(anchors, caps):
    vx, vy, vw, vh = VIEWBOX
    return ({k: ((x - vx) / vw, (y - vy) / vh) for k, (x, y) in anchors.items()},
            [(o, (x - vx) / vw, (y - vy) / vh, r / vw) for o, x, y, r in caps])


def _cross(o, p, q):
    return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])


def _seg_hit(p1, p2, p3, p4) -> bool:
    """Proper crossing; a shared end point does not count."""
    if len({p1, p2, p3, p4}) < 4:
        return False
    d1, d2 = _cross(p3, p4, p1), _cross(p3, p4, p2)
    d3, d4 = _cross(p1, p2, p3), _cross(p1, p2, p4)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


def _point_seg(p, a, b) -> float:
    ax, ay = b[0] - a[0], b[1] - a[1]
    t = ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / max(ax * ax + ay * ay, 1e-9)
    t = min(max(t, 0.0), 1.0)
    return math.hypot(p[0] - (a[0] + t * ax), p[1] - (a[1] + t * ay))


def _layout(anchors, aspect, left, right, w, h, rows):
    """([(key, edge, stub, anchor)], art rect), as ConsolePadDiagram places them."""
    band_w = min(w, MAX_W)
    band_x = (w - band_w) * 0.5
    rows_h = rows * ROW_H + (rows - 1) * COL_GAP
    rows_top = max((h - rows_h) * 0.5, 0.0)
    avail_w = band_w - 2.0 * (COL_W + EDGE_PAD)
    art_h = h - 20.0
    art_w = art_h * aspect
    if art_w > avail_w:
        art_w = avail_w
        art_h = art_w / aspect
    art = (band_x + (band_w - art_w) * 0.5, (h - art_h) * 0.5, art_w, art_h)

    out = []
    for side, order in ((0, left), (1, right)):
        col_x = band_x if side == 0 else band_x + band_w - COL_W
        for i, key in enumerate(order):
            if not key:
                continue
            row_y = rows_top + i * (ROW_H + COL_GAP)
            edge = (col_x + (COL_W if side == 0 else 0.0), row_y + ROW_H * 0.5)
            stub = (edge[0] + (STUB if side == 0 else -STUB), edge[1])
            ax, ay = anchors[key]
            out.append((key, edge, stub, (art[0] + ax * art_w, art[1] + ay * art_h)))
    return out, art


def measure(anchors, caps, aspect, left, right, sizes, rows=None, detail=None):
    """(crossings, leads through another control's dot, leads across another
    control's button, mean lead length)."""
    rows = rows or max(len(left), len(right))
    crossings = through = over = 0
    length = 0.0
    n = 0
    for w, h in sizes:
        leads, (art_x, art_y, art_w, art_h) = _layout(anchors, aspect, left, right, w, h, rows)
        segs = []
        for key, edge, stub, anchor in leads:
            segs.append((key, edge, stub))
            segs.append((key, stub, anchor))
            length += math.dist(stub, anchor)
            n += 1
        for i in range(len(segs)):
            for j in range(i + 1, len(segs)):
                if segs[i][0] != segs[j][0] and _seg_hit(segs[i][1], segs[i][2],
                                                         segs[j][1], segs[j][2]):
                    crossings += 1
                    if detail is not None:
                        detail["%s crosses %s" % (segs[i][0], segs[j][0])] += 1
        for key, _edge, stub, anchor in leads:
            for other, _e, _s, dot in leads:
                if other != key and _point_seg(dot, stub, anchor) < DOT_RADIUS + LEAD_WIDTH:
                    through += 1
                    if detail is not None:
                        detail["%s through %s's dot" % (key, other)] += 1
            for owners, bx, by, br in caps:
                centre = (art_x + bx * art_w, art_y + by * art_h)
                if key not in owners and _point_seg(centre, stub, anchor) < br * art_w * CAP_CORE:
                    over += 1
                    if detail is not None:
                        detail["%s over %s's button" % (key, owners[0])] += 1
    return crossings, through, over, length / max(n, 1)


def _orders(keys, slots):
    """Every order of `keys` over `slots` rows, blanks filling the rest, with
    trailing blanks dropped."""
    seen = set()
    for perm in itertools.permutations(keys):
        for blanks in itertools.combinations(range(slots), slots - len(keys)):
            it = iter(perm)
            out = ["" if i in blanks else next(it) for i in range(slots)]
            while out and not out[-1]:
                out.pop()
            if tuple(out) not in seen:
                seen.add(tuple(out))
                yield out


def search(anchors, caps, aspect) -> None:
    """Centre controls may take either column. Every order of each column, blank
    slots included, is scored alone on COARSE; the best few pairs are scored
    together on SIZES. Ranked by faults, then blanks, then lead length."""
    centre = [k for k, (x, _y) in anchors.items() if abs(x - 0.5) < 0.05]
    left0 = [k for k, (x, _y) in anchors.items() if k not in centre and x < 0.5]
    right0 = [k for k, (x, _y) in anchors.items() if k not in centre and x >= 0.5]
    max_rows = int((MIN_PANEL_H + COL_GAP) // (ROW_H + COL_GAP))
    results = []
    for mask in range(1 << len(centre)):
        left = left0 + [k for i, k in enumerate(centre) if not mask & (1 << i)]
        right = right0 + [k for i, k in enumerate(centre) if mask & (1 << i)]
        if max(len(left), len(right)) > max_rows:
            continue
        best = []
        for side, keys in ((0, left), (1, right)):
            scored = []
            for order in _orders(keys, max_rows):
                lo, ro = (order, []) if side == 0 else ([], order)
                cr, th, ov, ln = measure(anchors, caps, aspect, lo, ro, COARSE, max_rows)
                scored.append(((cr + th + ov, order.count(""), ln), order))
            scored.sort(key=lambda s: s[0])
            best.append([o for _s, o in scored[:8]])
        for lo in best[0]:
            for ro in best[1]:
                cr, th, ov, ln = measure(anchors, caps, aspect, lo, ro, SIZES)
                results.append(((cr + th + ov, (lo + ro).count(""), ln), (cr, th, ov, ln), lo, ro))
    results.sort(key=lambda r: r[0])
    for _rank, (cr, th, ov, ln), lo, ro in results[:6]:
        print("crossings %d  through a dot %d  across a button %d  mean lead %.0f px"
              % (cr, th, ov, ln))
        print("  left  %s" % lo)
        print("  right %s" % ro)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True, help="MilkToastRat n64.svg")
    ap.add_argument("--out", help="destination .svg")
    ap.add_argument("--search", action="store_true", help="look for column orders")
    args = ap.parse_args()

    src = io.open(args.src, encoding="utf-8").read()
    anchors, caps = normalize(*read_source(src))
    aspect = VIEWBOX[2] / VIEWBOX[3]

    if args.search:
        search(anchors, caps, aspect)
        return

    keys = [k for k in LEFT + RIGHT if k]
    if sorted(keys) != sorted(anchors):
        raise SystemExit("LEFT + RIGHT must list every anchor exactly once")

    if args.out:
        out = re.sub(r'viewBox="[^"]*"', 'viewBox="%g %g %g %g"' % VIEWBOX,
                     drop_wordmark(src), count=1)
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        io.open(args.out, "w", encoding="utf-8", newline="\n").write(out)
        print("wrote %s" % args.out)

    print('\n\t\t"anchors": {')
    for k in keys:
        print('\t\t\t"%s": Vector2(%.4f, %.4f),' % (k, anchors[k][0], anchors[k][1]))
    print("\t\t},")
    print('\t\t"left": %s,' % str(LEFT).replace("'", '"'))
    print('\t\t"right": %s,' % str(RIGHT).replace("'", '"'))

    detail = collections.Counter()
    cr, th, ov, _ln = measure(anchors, caps, aspect, LEFT, RIGHT, SIZES, detail=detail)
    print("\nleader-line crossings over the size sweep: %d" % cr)
    print("leads through another control's dot: %d" % th)
    print("leads across another control's button: %d" % ov)
    for what, count in detail.most_common():
        print("  %s: %d" % (what, count))
    if cr or th or ov:
        sys.exit(1)


if __name__ == "__main__":
    main()
