# §2y-gen — Sega Genesis cartridges

### 2y-gen. The Genesis cartridge — the photographed, caliper-measured cart, a UV-mapped sticker

`RetroCartridge` builds a `genesis` cartridge from
`imported-assets/carts/genesis/genesis_cart.glb` (`_CART_MODELS`). It is the
optimized close tier (LOD0, 2,072 triangles) of `codex-photos/sega/genesis/cart`:
a parametric Blender model (`scripts/build_cartridge.py`) of a US Champions World
Class Soccer cart in Acclaim's "Assembled in Mexico" shell, built from the user's
caliper numbers and registered to the photographs (`LICENSE-genesis-cart.txt`).
It comes in through one script, which renames the nodes and materials and runs
`fix_unmapped_uvs.py`:

    cd codex-photos/sega/genesis/cart
    blender -b --factory-startup --python scripts/export_retroxr.py

It reads `delivery/genesis_cartridge_v002.blend`, writes `retroxr/genesis_cart.glb`,
then `Tools/glb/fix_unmapped_uvs.py --tile 5.56` (the plastic grain's tile) and
`--check`. The build welds the boolean cuts before exporting, so there is no sliver
left for it to fix; the step stays as the guard.

**Size.** 108 × 67 × 17 mm, measured. The `CART_SIZES` row matches, so the cart
loads at scale 1; the old 110 × 70 × 17 box row would stretch it 1.9 % across and
4.5 % in height. The Genesis's slot (`genesis_model.gd`) is a 109 × 18 mm mouth, so
it clears by 0.5 mm a side. The seat stands a cart's bottom edge 2 mm above the
connector and centres it at half its height, and the 32X's `connector` is derived
from the same row (§2j′), so a change here moves neither.

**Shape** (all measured unless marked): the front shoulders are a superellipse
11.4 mm across and 8.3 mm deep (the end-on photos); the parting line is 6.4 mm in
from the back; each back corner has a hard-edged notch 7 mm into the side, 4 mm in
from the back and 40 mm up from the mouth, leaving the rear half's 2 mm lip flush
with the side; the mouth edges carry a 1 mm, 45° chamfer; the board is 83 mm wide
and 1.7 mm thick and stands 1 mm inside the mouth, with 32 contacts a side on the
2.54 mm pitch. The back's grip, blank plaque, caution recess and screws were
placed through a solved camera of the back photo.

**Parts** (node names): `Front_Shell`, `Rear_Shell`, `Label`, `Label_Fold`,
`Caution_Plate`, `Connector_PCB`, `Connector_Contacts`, `Security_Screw_L`,
`Security_Screw_R`. Connector on −Y, label on +Z; the screws and the caution plate
are on the back. Materials: `Genesis_Shell_Plastic` (black ABS, the grain normal
map), `Genesis_Label`, `Genesis_Label_Fold`, `Genesis_Caution_Plate` (its lettering
normal map), `PCB fiberglass`, `Gold edge contacts`, `Security screw steel`. None is
a `CartridgeColor` name, so nothing tints them; every Genesis cart is black.

**The sticker.** The label is 74 × 67 mm with R2 corners: 60 mm down the front and a
7 mm fold over the top. ScreenScraper's `support-texture` for a Genesis cart is a
scan of the FRONT only (Champions World Class Soccer 600 × 500, Sonic 600 × 490;
the front is 1.23), so `Label` is the front alone, UV 0..1 with the art's top-left
at the label's top-left, and `Label_Fold` is plain paper that stays white, as on the
Super NES. `genesis` is in `_UV_LABELS`, and `CartridgeLabel.find_label` finds
`Label`, never the fold.

**Metal.** `genesis` is in `_AUTHORED_MATERIALS`: the contacts and screws are metal.

**LOD** is Godot's own (`meshes/generate_lods`, the 32X cart's import settings). The
export's own LOD1/LOD2 (1,076 and 636 triangles, a three-level switch in the
codex-photos Godot scene) are not imported.

**Marks.** The Acclaim plaque on the back is modelled blank (the user's call); the
raised CAUTION lettering names nobody, so it stays, set in Cutive (OFL) and baked
into the plate's normal map.

`genesis_cart_tests` (26 cases): resources, model (parts, `CART_SIZES` and its
measured value, connector −Y, label +Z, the board 1 mm inside the mouth, screws and
plate on the back, the notch 7 mm deep up to 40 mm with the lip left), branding (no
logo mesh or material; the only normal maps are the grain and the lettering), uv,
label (the art's corners, the 74 × 60 mm front, one surface, the fold over the top,
`find_label` paints the front), cartridge (a spawned cart paints the scraped art and
leaves the fold plain, the blank sticker and title without art, metal contacts and
screws, scale 1). Mutation-tested: dropping `genesis` from `_UV_LABELS` fails 2
cases, and the old 110 × 70 row fails 3.

**Re-exporting.** Rebuild with `build_cartridge.py`, then run `export_retroxr.py`
(never copy `genesis_mobile.glb` straight over: its node and material names are the
build's), copy `retroxr/genesis_cart.glb` here, reimport, and run
`genesis_cart_tests`.
