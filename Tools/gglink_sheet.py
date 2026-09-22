"""Contact sheet of a gg_link_probe game run: top row machine A, bottom B.

    python Tools/gglink_sheet.py TAG      # -> RetroXR/probe_out/sheet_TAG.png
"""
import glob, os, sys
from PIL import Image

tag = sys.argv[1]
d = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "RetroXR", "probe_out")
A = sorted(glob.glob(os.path.join(d, f"gg_link_{tag}_game_a_*.png")))
B = sorted(glob.glob(os.path.join(d, f"gg_link_{tag}_game_b_*.png")))
W, H = 160, 144
sheet = Image.new("RGB", (max(1, len(A)) * (W + 4), 2 * (H + 4)), "white")
for i, (a, b) in enumerate(zip(A, B)):
    sheet.paste(Image.open(a).convert("RGB").resize((W, H)), (i * (W + 4), 0))
    sheet.paste(Image.open(b).convert("RGB").resize((W, H)), (i * (W + 4), H + 4))
out = os.path.join(d, f"sheet_{tag}.png")
sheet.save(out)
print(out)
