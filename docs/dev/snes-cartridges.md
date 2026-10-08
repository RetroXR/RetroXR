# §2y-snes — Super NES cartridges

### 2y-snes. Super NES cartridges — two North American bodies, the Super Famicom / PAL one, a moulded colour, a scraped sticker

`RetroCartridge` builds a `snes` cartridge from `imported-assets/carts/snes/`:
`snes_cart_type_a.glb` or `snes_cart_type_b.glb`, the debranded mobile tier of the
user's own model (codex-photos/nintendo/snes/cart: `rebuild_from_user.py` →
`package_revision2.py` → `export_retroxr.py`), 17,285 and 18,377 triangles,
135.5 × 87 × 20.15 mm (the 0.15 is the bezel round the rear sticker), connector on
−Y and label on +Z, so it drops into the frame with no turn. The LODs are Godot's
own. `MediaDimensions`' `snes` size is the model's own, so it is not stretched.

The two bodies are the NTSC-U shell and differ only at the front latch: Type A, the
deep locking notch (Super Mario World's), and Type B, the sloped recess (Bubsy II's).
They share one rear shell. Parts:

- `Front_Shell`, `Rear_Shell` (material `SNES_Shell_Plastic`: colour, the grain
  normal map on UV0, roughness 0.62) and `Label_Bezel` (`SNES_Smooth_Plastic`, the
  smooth frame round the rear sticker).
- `Label`: the front face of the sticker, UV 0–1 with the art's top left at the
  label's top left. Scraped labels are front-face scans, so `Label_Fold` (the 7 mm
  that wraps over the top) keeps its white.
- `Rear_Sticker`: the recreated warning sticker without its
  "Rd. (M) (C)1991 NINTENDO" line; MODEL NO. SNS-006, SNS-USA and MADE IN JAPAN
  stay. Alpha scissor for the rounded corners.
- `Connector_PCB` (bare brownish FR4 up to 0.5 mm above the fingers, green solder
  mask above), `Connector_Contacts`, `Security_Screw_L/R` (Gamebit heads: nickel
  on Type A, brass on Type B, as the two cartridges photographed are).

**The body** is chosen by `SnesCartShell.body_model_for_rom`:

| `body_region` | market | first release | body |
| --- | --- | --- | --- |
| `TYPE_A` / `TYPE_B` / `SFC` (forced) | any | any | that body |
| empty (Auto) | `us` | before 1994, or unknown | Type A |
| empty | `us` | 1994 on | Type B |
| empty | `jp`, `eu`, `au` (`SFC_MARKETS`) | any | Super Famicom |
| empty | unknown | | none: the procedural box |

The market (`SnesCartShell.market`) is the scraper's region for the ROM
(`gamelist.json`, read through `N64CartShell.market_of_region`), else the file
name's region tag (`filename_market`: No-Intro's `(USA)`, `(Europe)`, `(Japan, USA)`,
or GoodTools' `(U)`, `(JU)`; a tag naming North America among others is `us`), else
the internal header's destination byte (+0x19: 0x01 and 0x0F Canada `us`, 0x00
`jp`, 0x02–0x0A `eu`, 0x11 `au`). Korea (0x0D) and the other codes have no market,
so they keep the box. The tag outranks the header because the header is sometimes
wrong: on a 3,057-ROM retail No-Intro set, 12 carry a destination their tag
contradicts (Pinocchio and Flashback USA say Japan, An American Tail 0xFF, FIFA 98
Europe says USA), and 9 have no valid header at all (test and PowerFest carts).

The release date is the gamelist ROM entry's `releasedate` (`date_digits` reads
both `1994-11-01` and `19941101T000000`). Why 1994 (`TYPE_B_FROM`): collectors date
the sloped front to "some point in 1993", and games printed after it, reprints of
older ones included (Players' Choice, Star Fox, F-Zero, Super Castlevania IV),
came in Type B. A 1993 first print could be either, so Auto keeps the whole of
1993 on Type A. Assumptions open: the changeover month, and that a ROM means its
FIRST print (a reprint's cartridge cannot be told from the ROM).

**The shell** is chosen by `SnesCartShell.preset_for_rom` from the internal header,
never hashed: the title at 0x7FC0 (LoROM) or 0xFFC0 (HiROM), after a 512-byte
copier header when the file's size is 512 past a multiple of 1024, accepted only
when checksum and complement sum to 0xFFFF. Three SNES games shipped in coloured
plastic, and `TITLE_SHELLS` lists each with the markets it did so in:

| Title | Game | Shell | Markets |
| --- | --- | --- | --- |
| `KILLER INSTINCT` | Killer Instinct | black | every one (no Japanese release) |
| `DOOM` | Doom | red | `us` only: the European and Japanese carts were grey |
| `MAXIMUM CARNAGE` | Spider-Man & Venom: Maximum Carnage | red | `us` only: the European cart was grey |

The titles were read off a 3,480-ROM No-Intro set, where no other game shares
them; Doom's and Maximum Carnage's ROMs keep one title across markets, which is
why the market matters. Everything else is grey, the model's own plastic.
`Resources/snes_cartridge_shells.tres`; black and red are visual approximations.
Assumption open: PAL Killer Instinct in black (European listings show black carts;
no source says so outright).

`Tools/models/snes_cart_rom_check.tscn -- --roms=<folder>` (headless) runs
market, body and shell over a real set and fails if a tagged file's market
disagrees with its tag or a coloured shell lands anywhere unexpected. On
Z:/roms/snes (3,480 ROMs): 1,002 `us`, 1,729 `jp`, 733 `eu`, 3 `au`, 13 of no
market; exactly Doom (USA) and Maximum Carnage (USA) red, the three Killer
Instinct dumps black.

**Painting.** `CartridgeColor.PALETTE_PATHS` has `snes`; `SNES_Shell_Plastic`,
`SNES_Smooth_Plastic` and the Super Famicom body's `SNES_Shell_Plastic_Ribbed` are
in `EXTERIOR_PLASTIC` and `OWN_ROUGHNESS` (the grain and roughness stay the
mould's). The halves go by node name, the bezel by side. Label,
fold, sticker, board, contacts and screws are never painted, and `demetal` does not
run (`_AUTHORED_MATERIALS`: contacts and screws are metal). A flake mix borrows the
N64 gold's flakes; this palette has none.

**Forcing**: held, a `snes` ROM row opens `_show_cart_spawn_options` with a Body
row (Auto (from the ROM) / Type A (groove) / Type B (recess) / Super Famicom / PAL,
into `body_region`), the grey, black and red swatches, and Custom. A forced body is
spawned on any ROM: a US shell on a Japanese ROM, or the Super Famicom shell on a
US one.

### The Super Famicom / PAL body

`imported-assets/carts/sfc/sfc_cart.glb` (`SnesCartShell.BODY_SFC`) is the shell
Japan, Europe and Australia shared: rounded top, the NTSC Type A-like grip slot
with a ridged floor, ribbed back, and the two notches cut into its top edge. It is
the debranded mobile LOD0 of the user's photographed and calipered Super Mario RPG
(SHVC-006), codex-photos/nintendo/snes/cart-sfc/cartridge_assets (`build_all.py` →
`export_retroxr.py`), 20,768 triangles, **128 × 87.5 × 20 mm** (20 over the rear
ribs), in the same frame as the US bodies. The LODs are Godot's own.

- **Its size is not the `snes` row.** `MediaDimensions.cart_size(systemid,
  rom_path, body_model)` returns `CART_SIZE_SFC` for this body, and
  `RetroCartridge._cart_size()` passes the body `_body_model()` resolved (cached
  per ROM and `body_region`, since the size passes run on every drop). Every size
  pass in cartridge.gd goes through it (the box, the body it rests on, the aim box,
  the seated stub and the model's scale), so it loads at scale 1. A new body of
  another size needs the same treatment, or the per-axis fit stretches it.
- Parts: `Front_Shell`, `Rear_Shell` (`SNES_Shell_Plastic`, and
  `SNES_Shell_Plastic_Ribbed` for the flat rear panels, whose ribbing is a baked
  normal + AO map on UV0), `Molded_Made_In_Japan` and `Cavity_Mold_ID`
  (`SNES_Smooth_Plastic`, raised lettering on the rear moulding, painted with it),
  `Label` (the front label only: this shell's label does not wrap over the top),
  `Rear_Sticker`, `Connector_PCB`, `Connector_Contacts`, `Grounding_Clip`, and
  brass `Security_Screw_L/R`.
- Debranded like the US bodies: no moulded Nintendo oval or ®; the recreated rear
  sticker drops "SUPER FAMICOM®" and the trademark notice line and keeps its
  warning text, CASSETTE, MODEL NO. SHVC-006 and serial. The moulded
  PAT. PEND. / MADE IN JAPAN and the mold ID stay.
- Its plastic is authored as the palette's grey, so the default `grey` preset
  leaves it as it is. The PAL cartridges use the same shell and, for now, the
  Japanese sticker; no PAL specimen has been photographed.

**Re-export**: `python source/build_all.py` in codex-photos/nintendo/snes/cart-sfc/cartridge_assets
writes `retroxr/sfc_cart.glb` and runs `fix_unmapped_uvs.py` on it, then `--check`
(three hairline slivers where the front shoulder channel meets the top rim always
need it). Copy that GLB over this one.

**Re-export**: run the three Blender scripts in codex-photos/nintendo/snes/cart, copy the
two GLBs over, then `python Tools/glb/fix_unmapped_uvs.py <glb>` and `--check` on
each: the bevel strips came out with zero-area UVs (the exporter re-projects the
grain on the final faces; the tool catches the remaining slivers).

`snes_cart_tests` (122 cases): resources, model, branding (the sticker's copyright
strip is blank, MODEL NO. printed), uv, surfaces, color, kept, lookup, cartridge,
forced. Mutation-tested: dropping the US-only market check, the bezel material from
`EXTERIOR_PLASTIC`, or `snes` from `_UV_LABELS` or `_AUTHORED_MATERIALS` each fail
their own cases. The cartridge group writes one label PNG into the REAL roms root's
`snes/media/label` (as gb_cart_tests does) and removes it, and any folder it had
to create.

`sfc_cart_tests` (72 cases): resources, model, branding (no SUPER FAMICOM mark or
trademark line on the sticker, MODEL NO. and serial printed, MADE IN JAPAN kept),
uv, surfaces (the ribbed panel is moulding, the lettering on the rear half), color,
kept, lookup (by market, forced, and from header fixtures 0x00/0x02/0x09/0x11/0x01),
size, cartridge (Japanese, PAL and forced carts spawn it unstretched and centred, at
the Super Famicom size; a US ROM still gets Type A). Mutation-tested: dropping
`SFC_MARKETS`, the forced `SFC`, the body from `_cart_size()`, or the ribbed
material from `EXTERIOR_PLASTIC` or `OWN_ROUGHNESS` each fail their own cases.

```bash
"$godot" --headless --path RetroXR res://Tests/snes_cart_tests.tscn
"$godot" --headless --path RetroXR res://Tests/sfc_cart_tests.tscn
"$godot" --path RetroXR --resolution 1600x900 --position 20,20 \
  res://Tools/models/snes_cart_render_probe.tscn -- --out=<dir> [--label=<front-face png>]
```
