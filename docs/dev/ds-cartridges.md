# §2y-ds — Nintendo DS and 3DS Game Cards

### 2y-ds. DS and 3DS Game Cards — the photographed cards, no marks, a UV-mapped sticker

`RetroCartridge` builds an `nds` card from
`imported-assets/carts/nintendo_ds/ds_cart.glb` and an `n3ds` card from
`imported-assets/carts/nintendo_3ds/3ds_cart.glb` (`_CART_MODELS`). Both are the
no-branding optimized close exports, `ds_mobile_clean.glb` and
`3ds_mobile_clean.glb`, from `codex-photos/3ds-ds/cartridge_assets`
(`build_master.py` → `derive_export.py`; its README has the measurement table).
They were built from the user's photographs and caliper measurements and copied in
through one tool:

    python Tools/glb/fix_unmapped_uvs.py <export>.glb --out <asset>.glb --tile 34

The export projects the shells' UVs from the front, so the walls of the shells,
ribs and ledge (about 2,400 triangles a card) had none under the plastic-grain
normal map — the N64's dark-band defect. `--tile 34` box-projects them at the
front face's own scale (its UVs span the ~34 mm card), so the grain matches round
the edges.

**Sizes.** DS 33 × 35 × 3.8 mm; the 3DS card is the same body plus a 2 mm tab on
+X at the top, 35 × 35 × 3.8 mm. The `CART_SIZES` rows match the models, so a card
loads at scale 1: the old 33 × 35 × 4 rows would have squashed the 3DS tab into
the body (X ×0.943) and thickened both (Z ×1.053). Centring on the AABB puts the
3DS body 1 mm off the slot's centre line; the 3DS slot mouth is 38 mm wide. The
handhelds keep their own `cart_size` (`nds_model.gd`, `n3ds_model.gd`,
33 × 35 × 4 mm) for the slot pose, protrusion and seat preview; left as it was.

**Parts** (node names): `FrontShell`, `RearShell`, `RearMarkingPanel`,
`ManufacturingCode`, `ConnectorPCB`, `GoldContacts`, `ContactSeparators`,
`ConnectorBottomLedge`, `PCBMarkings`, `CartridgeLabel`. Connector on −Y, label on
+Z, root at the bottom centre of the 33 mm body. Materials are prefixed per card
(`ds_Shell`, `3ds_Gold`, …) — none is a `CartridgeColor` name, so nothing tints
them; a DS card is the grey it was moulded, a 3DS card the off-white.

**The sticker.** `CartridgeLabel` is in `_LABEL_MESHES` and in
`CartridgeLabel.LABEL_NAMES` (`find_label`), and both systems are in `_UV_LABELS`:
the scraped art is PAINTED onto the sticker, not laid over it on a quad. UV0 covers
the sticker's bounding rectangle with the image's top-left at the label's top-left
seen from the front; the rounded corners and the cut lower-left corner clip the
art. That is what ScreenScraper's `support-texture` is — a scan of the whole
sticker cropped to its bounding box (DS 541 × 600 ≈ 0.90, 3DS 308 × 335 ≈ 0.92,
against the sticker's 26.66 × 28.96 mm ≈ 0.92) — so the art is stretched onto it,
not fitted inside it.

**Metal.** Both systems are in `_AUTHORED_MATERIALS`: the gold contacts are
metallic 0.85 and `demetal` would flatten them.

**LOD** is Godot's own (`meshes/generate_lods`, import settings identical to the
GBA cart's), as for every cart. The export's separate `_lod` distant models are
not imported.

**Marks.** Neither card carries the moulded Nintendo logo or the
`NTR-005` / `CTR-005 PAT. PEND.` line (`LICENSE-*-cart.txt`). Two things stay from
the photographed cards: the printed lot code on the back (`AZEEN0J08`,
`AJREZ40342`) and the board silkscreen (`DA•A-1 C03-10`, `DS D-10 D01-10`). The lot
code's first four characters are the game code — Phantom Hourglass and Majora's
Mask 3D — so every card shows those. Open: draw it per ROM from the header's game
code (DS header 0x0C; the 3DS NCCH product code), or blank it.

`ds_cart_tests` (33 cases): resources, model (parts, `CART_SIZES`, connector −Y,
label +Z, the tab on +X only), branding, uv, label (the art's top-left and
bottom-right corners, one surface), cartridge (a spawned card paints the scraped
art, the blank sticker and title without it, metal contacts, scale 1).
Mutation-tested: dropping `CartridgeLabel` from `_LABEL_MESHES`, the two systems
from `_AUTHORED_MATERIALS`, and the 3DS row's width fails 8 cases.

**Re-exporting.** Copy the new `*_mobile_clean.glb` in through
`fix_unmapped_uvs.py --tile 34` (never straight over), reimport, and run
`ds_cart_tests`; its `uv` group fails on an unfixed copy.
