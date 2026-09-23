"""Erase the SEGA and "Compatible with Windows CE" marks from the Dreamcast case sheets.

    python Tools/glb/scrub_dreamcast_textures.py --in ~/Downloads/sega_dreamcast --out <dir>

Run BEFORE prepare_dreamcast.py, which takes <dir> as its --textures. Plain Python
(numpy, scipy, pillow), not Blender: the inpaint wants scipy's filters.

The marks are PRINTED into Case_baseColor and EMBOSSED into Case_normal, on the same
sheet as the functional legends (POWER, OPEN, the port letters, the rear connector
names), so they cannot be deleted as geometry. Each is found inside a search rect as
the pixels that differ from the local plastic -- dark ink in the colour, relief in the
normal -- dilated, and filled by normalized-convolution inpainting from the plastic
around it, with a nearby clean patch's fine grain added back so the fill does not read
as a smooth smear. The rects are in 4096 px sheet space and hold nothing but the mark.

Three marks, not two: the sheet carries a second SEGA on an interior wall behind the
front panel. It cannot be seen on an opaque shell, but it ships in the texture, so it
goes too.
"""
import argparse
import os

import numpy as np
from PIL import Image
from scipy import ndimage

## (x0, y0, x1, y1) search rect, and the (dx, dy) of a clean donor patch of the same
## surface for the grain.
REGIONS = {
    "sega_front": ((2330, 1520, 2480, 1740), (0, 260)),
    "windows_ce": ((2490, 2120, 2610, 2380), (-120, 0)),
    "sega_inner": ((2190, 3810, 2340, 3890), (0, -110)),
}


def mask_for(base, normal, box):
    x0, y0, x1, y1 = box
    lum = base[y0:y1, x0:x1, :3].astype(np.float32).mean(axis=2)
    bg = np.median(lum)
    n = normal[y0:y1, x0:x1, :3].astype(np.float32)
    ndev = np.abs(n - np.median(n.reshape(-1, 3), axis=0)).max(axis=2)
    m = (lum < bg - 18) | (ndev > 14)
    m = ndimage.binary_opening(m, iterations=1) | (lum < bg - 40)
    return ndimage.binary_dilation(m, iterations=7)


def fill(img, mask, donor):
    """Inpaint img (float HxWxC) where mask, then add the donor's high-frequency grain."""
    known = (~mask).astype(np.float32)
    out = img.copy()
    for sigma in (2, 4, 8, 16, 32, 64):
        num = np.stack([ndimage.gaussian_filter(img[..., c] * known, sigma)
                        for c in range(img.shape[2])], -1)
        den = ndimage.gaussian_filter(known, sigma)[..., None]
        out[mask] = (num / np.maximum(den, 1e-6))[mask]
        if den[mask].min() > 0.05:
            break
    grain = donor - np.stack([ndimage.gaussian_filter(donor[..., c], 6)
                              for c in range(donor.shape[2])], -1)
    soft = ndimage.gaussian_filter(mask.astype(np.float32), 2)[..., None]
    return img * (1 - soft) + (out + grain) * soft


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True, help="the Sketchfab download folder")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    tex = os.path.join(os.path.expanduser(a.src), "textures")
    os.makedirs(a.out, exist_ok=True)
    base = np.array(Image.open(os.path.join(tex, "Case_baseColor.png")).convert("RGBA"))
    normal = np.array(Image.open(os.path.join(tex, "Case_normal.png")).convert("RGB"))
    for name, (box, (dx, dy)) in REGIONS.items():
        x0, y0, x1, y1 = box
        m = mask_for(base, normal, box)
        for arr in (base, normal):
            reg = arr[y0:y1, x0:x1, :3].astype(np.float32)
            don = arr[y0 + dy:y1 + dy, x0 + dx:x1 + dx, :3].astype(np.float32)
            reg = fill(reg, m, don)
            if arr is normal:  # keep tangent-space normals unit length
                v = reg / 127.5 - 1
                reg = (v / np.linalg.norm(v, axis=2, keepdims=True).clip(1e-6) + 1) * 127.5
            arr[y0:y1, x0:x1, :3] = np.clip(reg, 0, 255).astype(np.uint8)
        print("erased", name, "-", int(m.sum()), "px")
    Image.fromarray(base, "RGBA").save(os.path.join(a.out, "Case_baseColor.png"), optimize=True)
    Image.fromarray(normal, "RGB").save(os.path.join(a.out, "Case_normal.png"), optimize=True)


if __name__ == "__main__":
    main()
