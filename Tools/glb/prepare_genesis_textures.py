"""Remove the GENESIS and SEGA marks from the Model 2 textures and resize for Quest.

    python Tools/glb/prepare_genesis_textures.py <download>/textures <work>/textures

Step one of two; prepare_genesis.py (in Blender) is the second.

The download carries three marks, all painted into textures rather than modelled:
the GENESIS badge beside the cartridge slot (Power__Cartridge), the SEGA plate on
the front control strip and the SEGA logo on the underside sticker (both Labels).
Each is a box (in the 0..1 UV space of its texture set) refilled on the
baseColor, normal and metallicRoughness maps by a Coons blend of the box's own
border, so the embossed relief goes with the print. The sticker's plain text is
left alone.

Every map is resized to 1024 from the download's 2048 and 4096.
"""
import os, sys
import numpy as np
from PIL import Image

SRC = sys.argv[1]
DST = sys.argv[2]
os.makedirs(DST, exist_ok=True)

# (set, x0, y0, x1, y1) in fractions of the texture, padded a little past the
# measured bright bbox so the anti-aliased and embossed edge goes too.
BOXES = [
    ("Power__Cartridge", 1108 / 2048, 1426 / 2048, 1683 / 2048, 1527 / 2048),  # GENESIS badge, top
    ("Labels", 582 / 1024, 231 / 1024, 693 / 1024, 552 / 1024),               # SEGA, top plate
    ("Labels", 399 / 1024, 336 / 1024, 467 / 1024, 572 / 1024),               # SEGA, bottom sticker
]
PAD = 0.008

SIZE = 1024


def coons(a, x0, y0, x1, y1):
    a = a.astype(np.float64)
    top, bot = a[y0 - 1, x0:x1], a[y1, x0:x1]
    lef, rig = a[y0:y1, x0 - 1], a[y0:y1, x1]
    h, w = y1 - y0, x1 - x0
    v = ((np.arange(h) + 1) / (h + 1))[:, None]
    u = ((np.arange(w) + 1) / (w + 1))[None, :]
    if a.ndim == 3:
        v, u = v[..., None], u[..., None]
    c00, c10 = a[y0 - 1, x0 - 1], a[y0 - 1, x1]
    c01, c11 = a[y1, x0 - 1], a[y1, x1]
    fill = ((1 - v) * top[None] + v * bot[None] + (1 - u) * lef[:, None] + u * rig[:, None]
            - ((1 - u) * (1 - v) * c00 + u * (1 - v) * c10 + (1 - u) * v * c01 + u * v * c11))
    a[y0:y1, x0:x1] = fill
    return a


for f in sorted(os.listdir(SRC)):
    if not f.endswith(".png"):
        continue
    tset = f.rsplit("_", 1)[0]
    im = Image.open(os.path.join(SRC, f))
    # Always RGB, never the grayscale several of these ship as. Godot samples a
    # one-channel albedo WITHOUT the sRGB decode an RGB one gets, so the shell's
    # 15/255 black rendered as a 6% grey — twelve times too light — while the
    # RGB underside beside it came out black.
    mode = "RGB"
    a = np.asarray(im.convert(mode))
    H, W = a.shape[:2]
    for bset, fx0, fy0, fx1, fy1 in BOXES:
        if bset != tset:
            continue
        x0, y0 = int((fx0 - PAD) * W), int((fy0 - PAD) * H)
        x1, y1 = int((fx1 + PAD) * W), int((fy1 + PAD) * H)
        a = coons(a, x0, y0, x1, y1)
        print("[clean]", f, (x0, y0, x1, y1))
    out = Image.fromarray(np.clip(np.rint(a), 0, 255).astype(np.uint8), mode)
    if out.size[0] > SIZE:
        out = out.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(os.path.join(DST, f), optimize=True)
    print("[out]", f, out.size, mode)
