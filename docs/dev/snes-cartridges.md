# §2y-snes — Super NES cartridges

### 2y-snes. Super NES cartridges — two North American bodies, a moulded colour, a scraped sticker

`RetroCartridge` builds a `snes` cartridge from `imported-assets/carts/snes/`:
`snes_cart_type_a.glb` or `snes_cart_type_b.glb`, the debranded mobile tier of the
user's own model (codex-photos/snes-cart: `rebuild_from_user.py` →
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
| `TYPE_A` / `TYPE_B` (forced) | any | any | that body |
| empty (Auto) | `us` | before 1994, or unknown | Type A |
| empty | `us` | 1994 on | Type B |
| empty | `jp`, `eu`, `au`, unknown | | none: the procedural box |

The market is the scraper's region for the ROM (`gamelist.json`, read through
`N64CartShell.market_of_region`), else the internal header's destination byte
(+0x19: 0x01 and 0x0F Canada `us`, 0x00 `jp`, 0x02–0x0A `eu`, 0x11 `au`). The
Super Famicom and PAL cartridges are a different shape, so their ROMs keep the box
until that model arrives; the natural hook is another body here, by market.

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
when checksum and complement sum to 0xFFFF. `KILLER INSTINCT` is black (it shipped
in black plastic); everything else is grey, the model's own plastic.
`Resources/snes_cartridge_shells.tres`; black is a visual approximation.

**Painting.** `CartridgeColor.PALETTE_PATHS` has `snes`; `SNES_Shell_Plastic` and
`SNES_Smooth_Plastic` are in `EXTERIOR_PLASTIC` and `OWN_ROUGHNESS` (the grain and
roughness stay the mould's). The halves go by node name, the bezel by side. Label,
fold, sticker, board, contacts and screws are never painted, and `demetal` does not
run (`_AUTHORED_MATERIALS`: contacts and screws are metal). A flake mix borrows the
N64 gold's flakes; this palette has none.

**Forcing**: held, a `snes` ROM row opens `_show_cart_spawn_options` with a Body
row (Auto (by release date) / Type A (groove) / Type B (recess), into
`body_region`), the grey and black swatches, and Custom. A forced body is spawned
on any ROM, a Japanese one included.

**Re-export**: run the three Blender scripts in codex-photos/snes-cart, copy the
two GLBs over, then `python Tools/glb/fix_unmapped_uvs.py <glb>` and `--check` on
each: the bevel strips came out with zero-area UVs (the exporter re-projects the
grain on the final faces; the tool catches the remaining slivers).

`snes_cart_tests` (95 cases): resources, model, branding (the sticker's copyright
strip is blank, MODEL NO. printed), uv, surfaces, color, kept, lookup, cartridge,
forced. Mutation-tested: dropping the US-only market check, the bezel material from
`EXTERIOR_PLASTIC`, or `snes` from `_UV_LABELS` or `_AUTHORED_MATERIALS` each fail
their own cases. The cartridge group writes one label PNG into the REAL roms root's
`snes/media/label` (as gb_cart_tests does) and removes it, and any folder it had
to create.

```bash
"$godot" --headless --path RetroXR res://Tests/snes_cart_tests.tscn
"$godot" --path RetroXR --resolution 1600x900 --position 20,20 \
  res://Tools/models/snes_cart_render_probe.tscn -- --out=<dir> [--label=<front-face png>]
```
