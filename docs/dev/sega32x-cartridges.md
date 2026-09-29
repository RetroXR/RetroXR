# §2y-32x — Sega 32X cartridges

### 2y-32x. The 32X cartridge — the photographed cart, no marks, a UV-mapped sticker

`RetroCartridge` builds a `sega32x` cartridge from
`imported-assets/carts/sega_32x/sega32x_cart.glb` (`_CART_MODELS`). It is the
no-branding optimized close tier (`03_Mobile_Clean`, 6,168 triangles) of
`codex-photos/sega-32x-cart/asset`: a parametric Blender model
(`build_cartridge.py`) registered to the user's photographs of a US Virtua
Fighter cart, its size and recess outlines measured on a 1:1 reference shell
(CC BY-NC, used for measurement only; `LICENSE-sega32x-cart.txt`). It comes in
through one script, which renames the nodes and materials to RetroXR's and runs
`fix_unmapped_uvs.py`:

    cd codex-photos/sega-32x-cart/asset
    blender -b --factory-startup --python scripts/export_retroxr.py

It reads `sega_32x_cartridge_v01.blend`, writes `retroxr/sega32x_cart.glb`, then
`Tools/glb/fix_unmapped_uvs.py --tile 5.56` (the plastic grain's own tile) and
`--check`. The boolean cuts leave one sliver on the rear shell with no UV area.

**Size.** 112.8 × 73 × 17 mm, the shell's true bounds. The `CART_SIZES` row
matches, so the cart loads at scale 1; the old 110 × 70 × 17 row would have
squashed it by 2.5 % across and 4 % in height. The 32X's slot (`CartFloor`, §2j′)
is 114.0 × 18.5 mm at its narrowest, 5 mm above the floor: 0.6 mm clear each side.
`genesis` keeps its 110 × 70 × 17 row and the box: the 32X's `connector` is the
middle of a 70 mm Genesis cart on `PlugSeat`, and the spacer's 21.7 mm drop is
measured against that seat, so a Genesis body is its own change.

**Parts** (node names): `Front_Shell`, `Rear_Shell`, `Label`, `Connector_PCB`,
`Connector_Contacts`, `Security_Screw_L`, `Security_Screw_R`. Connector on −Y,
label on +Z, in the upper half above the grip slots; the Gamebit screws are on
the back. Materials: `S32X_Shell_Plastic` (black ABS, the grain normal map),
`S32X_Label`, `PCB solder mask`, `PCB fiberglass`, `Gold edge contacts`,
`Gamebit screw nickel`. None is a `CartridgeColor` name, so nothing tints them;
every 32X cart is black.

**The sticker.** `Label` is in `_LABEL_MESHES`, and `sega32x` is in `_UV_LABELS`:
the scraped art is PAINTED onto the 75 × 43 mm sticker, with the image's top-left
at the label's top-left seen from the front. ScreenScraper's `support-texture` for
a US 32X cart is the sticker cropped to its bounds (Virtua Fighter: 600 × 356,
1.69, against the sticker's 1.74), so it is stretched onto it, not fitted inside
it. The label stands 0.25 mm proud of its pocket, clear of z-fighting at a
distance.

**Metal.** `sega32x` is in `_AUTHORED_MATERIALS`: the contacts and screws are
metallic and `demetal` would flatten them.

**LOD** is Godot's own (`meshes/generate_lods`, import settings identical to the
DS card's), as for every cart. The export's baked distant tiers (`_lod1`, `_lod2`,
seams and grooves in normal and occlusion maps) are not imported.

**Marks.** The moulded SEGA logo and its TM, and the moulded CAUTION text on the
back (it names the Genesis 32X), are left off; their recessed plaques stay blank.

`sega32x_cart_tests` (20 cases): resources, model (parts, `CART_SIZES`, connector
−Y, label +Z and in the upper half, screws on the back), branding (no logo or
lettering mesh or material, no normal map but the grain), uv, label (the art's
top-left and bottom-right corners, the 75 × 43 mm sticker, one surface), cartridge
(a spawned cart paints the scraped art, the blank sticker and title without it,
metal contacts and screws, scale 1). Mutation-tested: dropping `sega32x` from
`_UV_LABELS` fails 2 cases, and the old 110 × 70 row fails 2.

**Re-exporting.** Rebuild with `build_cartridge.py`, then run
`export_retroxr.py` (never copy `32x_mobile_clean.glb` straight over: its node and
material names are the build's), copy `retroxr/sega32x_cart.glb` here,
reimport, and run `sega32x_cart_tests` and `sega32x_probe`.
