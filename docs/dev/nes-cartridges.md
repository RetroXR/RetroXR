# §2y-nes — NES cartridges

### 2y-nes. The NES cartridge: the photographed, measured Game Pak, a UV-mapped sticker, grey or the Zelda gold

`RetroCartridge` builds an `nes` cartridge from
`imported-assets/carts/nes/nes_cart.glb` (`_CART_MODELS`). It is the debranded,
optimized close tier (LOD0, 2,766 triangles) of `codex-photos/nintendo/nes/cart`: a
parametric Blender model (`scripts/build_cartridge.py`) of a gray three-screw US
Game Pak (Maniac Mansion), built from the user's measurements and registered to the
photographs (`LICENSE-nes-cart.txt`). It replaced a CC BY 4.0 Sketchfab model
(Super Mario Bros 3 NES Cartridge by cloud), whose credit came off the About page
with it. It comes in through one script, which renames the nodes and materials,
swaps in the debranded textures and runs `fix_unmapped_uvs.py`:

    cd codex-photos/nintendo/nes/cart
    blender -b --factory-startup --python tools/export_retroxr.py

It reads `exports/nes_cartridge_v002.blend`, writes `exports/retroxr/nes_cart.glb`, then
`Tools/glb/fix_unmapped_uvs.py --tile 11.12` (the stipple's tile) and `--check`.
The GLB replaced the old one under the same `.import` file, so its UID stayed.

**Size.** 120 × 134 × 17 mm, measured (the narrow lower section is 106.5 mm
wide). The `CART_SIZES` row is now 134 mm tall (it was 133), so the cart loads at
scale 1. The NES tray's mouth is 34.2 mm against the cart's 17 mm (`nes_model.gd`).

**Shape.** The back half has a bevel 5.3 mm in from each side and down from the top,
4 mm deep. The front has the ribbed channel (20 bars and a stippled pad at its foot)
and the finger grip. The mouth is a 20 mm pocket: the first 3 mm of its walls are the
shell's smooth molding, and from there to its floor it is `NES_Shell_Interior`, unlit
black (glTF `KHR_materials_unlit`). Lit black plastic still reflects at the grazing
angle a player sees those walls at, and read grey. Above the pocket the shell is
solid. The board is 93.5 mm wide and 1.2 mm thick, with 36 contacts a side on the
2.5 mm pitch (NESdev's NES-EWROM-01 drawing), from 6.5 mm inside the mouth to its
floor.

**Parts** (node names): `Front_Shell`, `Rear_Shell`, `Label`, `Label_Fold`,
`Caution_Label`, `Connector_PCB`, `Connector_Contacts`, `Security_Screw_C`,
`Security_Screw_L`, `Security_Screw_R`. Connector on −Y, label on +Z; the screws
and the caution sticker are on the back. Materials: `NES_Shell_Plastic` (the
stippled front and back faces: a normal map plus a roughness map that makes each
pebble's top glossy and the gaps matte), `NES_Shell_Smooth` (the sides, top,
bottom, bevel, rib bars, grips, triangle), `NES_Plaque_Baked` (the rear plaque, its
PAT.PEND. MADE IN JAPAN lettering a normal map), `NES_Shell_Interior`,
`NES_Label`, `NES_Label_Fold`, `NES_Caution_Label`, `PCB fiberglass`,
`Gold edge contacts`, `Security screw steel`.

**The sticker.** The label is 55 × 97 mm with R1 corners: 90 mm down the front and
a 7 mm fold over the top. ScreenScraper's NES `support-texture` is a scan of the
FRONT only (365 × 600, 1.644; the front is 1.636), so `Label` is the front alone,
UV 0..1 with the art's top-left at the label's top-left, and `Label_Fold` is plain
paper, as on the Genesis and the Super NES. `nes` is in `_UV_LABELS`.

**Marks.** None of Nintendo's: the rear plaque's molded wordmark and the caution
sticker's (c)(M) Nintendo(R) line are left off, as the old model had no Nintendo
marks either. The sticker's text is redrawn in Arimo; no photo is cropped.

**Shells.** `NesCartShell` picks the shell per ROM, and the spawn menu's hold
sub-menu can force one (`_has_spawn_options`: grey, gold, or a mixed color with
or without metal flakes). The palette is `Resources/nes_cartridge_shells.tres`:
- `grey`, the standard: the model's own plastic, sRGB 0.555, which the Game Boy
  Advance palette's Classic NES Series grey matches (`gba_cart_tests` holds them
  equal).
- `gold`: The Legend of Zelda and Zelda II came in vacuum-metallized gold shells.
  It is a `METALLIZED` finish (`CartridgeShellPreset.Finish`, new with this cart).
  `CartridgeColor` keeps the StandardMaterial3D duplicate, makes it fully metallic
  in the preset's color, drops the metallic texture, and scales each molding's own
  roughness by the preset's (0.5). So the stipple's pebble tops glint and the smooth
  moldings stay near mirror. Painting a plastic preset afterwards restores the
  molding's own metalness and maps. Like any metal it needs a reflection probe or
  a sky to read as gold.

An iNES ROM has no internal title, so `NesCartShell` goes by name: the scraped
gamelist's name for the ROM, else the file name, lower-cased with bracketed tags
and punctuation dropped. Any name with the word "zelda" is gold, unless the market
(the scraped region, else the file name's region tag) is Japan. Japan's Zelda was
a Famicom Disk System game, and its later Famicom cartridge was grey. Later US
Classic Series reprints went back to grey too, but a ROM can't tell which print it
came from, so a Zelda ROM gets the gold.

**Metal.** `nes` is in `_AUTHORED_MATERIALS`: the contacts and screws are metal,
and the shell's plastic is authored at metallic 0.

**LOD** is Godot's own (`meshes/generate_lods`). The export's own LOD1/LOD2
(1,864 and 1,434 triangles) and its branded variants are not imported.

**Tests.** `nes_cart_tests` (41): the model, branding, UVs, the label, the shell
lookup, the gold paint and back, and spawned carts (scraped art, Zelda gold, a
forced preset beating the ROM's own, a mixed color).
