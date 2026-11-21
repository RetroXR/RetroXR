"""Bakes RetroXR/fonts/RetroXR-Sockets.ttf: outlet glyphs for the mains regions
Material Design Icons has none for (Type K, M, D, H), drawn on its power_socket
frame -- 1704-unit rounded square, 684-radius face, 128-radius holes -- so they
sit beside md-power_socket_* in the same label. MenuIcons loads it as a fallback.

    python Tools/art/gen_socket_glyphs.py      (needs fontTools, skia-pathops)
"""
import math
import os

import pathops
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "RetroXR", "fonts", "RetroXR-Sockets.ttf")
K = 0.5522847498  # cubic circle handle


def _circle(cx, cy, r):
    p = pathops.Path()
    pen = p.getPen()
    k = r * K
    pen.moveTo((cx + r, cy))
    pen.curveTo((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r))
    pen.curveTo((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy))
    pen.curveTo((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r))
    pen.curveTo((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy))
    pen.closePath()
    return p


def _poly(pts):
    p = pathops.Path()
    pen = p.getPen()
    pen.moveTo(pts[0])
    for q in pts[1:]:
        pen.lineTo(q)
    pen.closePath()
    return p


def _rounded_square(x0, y0, x1, y1, r):
    p = pathops.Path()
    pen = p.getPen()
    k = r * K
    pen.moveTo((x0 + r, y0))
    pen.lineTo((x1 - r, y0))
    pen.curveTo((x1 - r + k, y0), (x1, y0 + r - k), (x1, y0 + r))
    pen.lineTo((x1, y1 - r))
    pen.curveTo((x1, y1 - r + k), (x1 - r + k, y1), (x1 - r, y1))
    pen.lineTo((x0 + r, y1))
    pen.curveTo((x0 + r - k, y1), (x0, y1 - r + k), (x0, y1 - r))
    pen.lineTo((x0, y0 + r))
    pen.curveTo((x0, y0 + r - k), (x0 + r - k, y0), (x0 + r, y0))
    pen.closePath()
    return p


def _slot(cx, cy, ang, w, length):
    a = math.radians(ang)
    ux, uy, vx, vy = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    return _poly([(cx + sx * ux * length / 2 + sy * vx * w / 2, cy + sx * uy * length / 2 + sy * vy * w / 2)
        for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))])


def _d_hole(cx, cy, r):
    """Half disc, flat side up: Type K's earth."""
    return pathops.op(_circle(cx, cy, r), _poly([(cx - r - 1, cy), (cx + r + 1, cy),
        (cx + r + 1, cy + r + 1), (cx - r - 1, cy + r + 1)]), pathops.PathOp.DIFFERENCE)


def _union(paths):
    out = paths[0]
    for p in paths[1:]:
        out = pathops.op(out, p, pathops.PathOp.UNION)
    return out


def _socket(holes):
    """Plate minus face, plus the holes: black where MDI is black."""
    plate = pathops.op(_rounded_square(0, -238, 1704, 1466, 188), _circle(852, 614, 684),
        pathops.PathOp.DIFFERENCE)
    return _union([plate] + holes)


def _type_h():
    holes = []
    for cx, cy in ((600, 850), (1104, 850), (852, 300)):
        ang = math.degrees(math.atan2(cy - 614, cx - 852))
        # Slot and round together: SI 32 sockets take the old flat pins and the round.
        holes.append(_union([_slot(cx, cy, ang, 140, 330), _circle(cx, cy, 112)]))
    return holes


GLYPHS = [
    (0xF2000, "power_socket_dk", [_circle(512, 780, 128), _circle(1192, 780, 128), _d_hole(852, 330, 200)]),
    (0xF2001, "power_socket_za", [_circle(852, 980, 170), _circle(572, 380, 140), _circle(1132, 380, 140)]),
    (0xF2002, "power_socket_in", [_circle(852, 1010, 145), _circle(612, 340, 110), _circle(1092, 340, 110)]),
    (0xF2003, "power_socket_il", _type_h()),
]


def main():
    fb = FontBuilder(2048, isTTF=True)
    names = [".notdef"] + [n for _, n, _ in GLYPHS]
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({cp: n for cp, n, _ in GLYPHS})
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    for _, name, holes in GLYPHS:
        path = _socket(holes)
        path.simplify()
        tt = TTGlyphPen(None)
        path.draw(Cu2QuPen(tt, max_err=1.0, reverse_direction=True))
        glyphs[name] = tt.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (1704 if n != ".notdef" else 1024, 0) for n in names})
    # The Nerd Font's metrics, so a socket sits where an md-power_socket does.
    fb.setupHorizontalHeader(ascent=1638, descent=-410)
    fb.setupNameTable({"familyName": "RetroXR Sockets", "styleName": "Regular"})
    fb.setupOS2(sTypoAscender=1638, sTypoDescender=-410, sTypoLineGap=0,
        usWinAscent=1638, usWinDescent=410)
    fb.setupPost()
    fb.save(OUT)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
