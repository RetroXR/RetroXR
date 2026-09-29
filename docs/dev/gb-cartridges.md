# §2x — Game Boy cartridges

### 2x. Game Boy cartridges — one body, a moulded colour, a scraped sticker

`RetroCartridge` builds a `gb` cartridge (`.gb` and `.gbc`), and a `gbc` one the same
way (`GbCartShell.is_shell`; Game Boy Color is a secondary platform of the Game Boy
cores with its own tile and `roms/gbc/` folder, not an alias of `gb`), from
`imported-assets/carts/game_boy/gb_cart.glb`: the unbranded Quest
close export of the Codex Kirby's Block Ball model, 14,386 triangles, 57 × 65 × 7.5 mm,
connector on −Y and label on +Z, so it drops into the frame with no turn. The LODs are
Godot's own (`meshes/generate_lods`), not Codex's `_lod1` file. `MediaDimensions`' `gb`
size is the model's own, so it is not stretched.

**The shell** is chosen by `GbCartShell` from the ROM header (0x150 bytes, never
hashed), from `Resources/gb_cartridge_shells.tres`:

| Header | Shell |
| --- | --- |
| title `POKEMON_GLD` / `POKEMON_SLV`, Nintendo | gold / silver (metal flake), every market |
| title `DONKEYKONGLAND…` / `SUPERDONKEYKONG`, Nintendo | yellow: Donkey Kong Land, 2 and III, and Japan's Super Donkey Kong GB and Donkey Kong Land (its Land 2), every market |
| title `POKEMON RED` / `POKEMON BLUE` / `POKEMON YEL…`, Nintendo, destination 0x14A ≠ 0 | red / blue / yellow |
| same, destination 0x14A = 0 (Japan) | grey: the Japanese Red, Green, Blue and Pikachu were standard grey |
| CGB flag 0x143 = 0x80 (runs on both machines) | black |
| CGB flag 0xC0 (Game Boy Color only) | not this shell: the clear Game Boy Color one (below); grey if forced into this one |
| anything else | grey |

The titles are one per game across languages: every European Red is `POKEMON RED`,
every Gold `POKEMON_GLD` + a game code. Measured 2026-09-22 on every Pokemon ROM in
a No-Intro `gb`/`gbc` set: destination is 0 on every Japanese release and 1 elsewhere,
Korea included. Every value in the palette is a visual approximation; grey is the model's
own imported plastic, so the default is the model as authored.

The Land games use the old 16-byte title, so 0x143 is a title letter, not a CGB
flag: `DONKEYKONGLAND95`, `DONKEYKONGLAND 2`, `DONKEYKONGLAND 3`. A beta with a
garbled licensee stays grey.

Assumptions still open: Japanese Gold/Silver are coloured (the source checked says
nothing); the Japanese Land carts are yellow (sources name the series, not
the Japanese run); Japanese Pikachu is grey
like Japan's other first-generation carts.

**Painting.** `CartridgeColor` takes a system id (`apply_preset(cart, &"red", "gb")`);
N64 is the default and keeps its palette. The GB moulding is four materials:
`Gray_ABS_Textured` (front), `Rear_ABS_Rough`, `Gray_ABS_Smooth` (rails and bowl, one
mesh across both halves) and `Shell_Seam_Shadow` (the rim round the sticker).
`SHADE` keeps the model's own ratios to the front, 1.03 and 0.65, so the rim stays
darker than the shell in any colour and grey reproduces the model; `OWN_ROUGHNESS`
keeps each one's roughness. PCB, contacts, screw, cavity and label are never painted,
and `demetal` does not run (contacts and screw are metal).

**Forcing a shell**: held for a second, a `gb` or `gbc` ROM row opens
`_show_cart_spawn_options`, the N64's sub-menu with a Body row of the two shells
(Auto, Game Boy, Game Boy Color), then the swatches of the Game Boy palette and the
Game Boy Color one. The id lands in `RetroCartridge.shell_preset` (saved by
`scene_persistence`) and brings the body whose palette holds it (below); an id
neither palette holds, an N64 one included, is ignored and the ROM's own shell is
used. The sub-menu's Custom
colour (`shell_color`, `shell_flake`; see n64-cartridges.md) keeps the rim's 0.65
and the rails' 1.03 shade of it, and a flake mix takes the GB gold's flakes.

**The sticker**: the scraped `media/label/<rom>.png` is painted onto the UV-mapped
`Label` mesh (`_UV_LABELS`), which covers 0–1 with the image's top left at the
label's top left; the embedded 4 × 4 white is only a placeholder.

**The export leaves the rear shell unmapped** (876 triangles at one UV), the same
Blender bug as the N64 front shell: run `Tools/glb/fix_unmapped_uvs.py` on any
re-export. `gb_cart_tests` `uv/` fails otherwise.

`gb_cart_tests` (71 cases): resources, model, branding, uv, surfaces, color, flake,
kept, lookup, cartridge, forced. Mutation-tested: dropping the destination check, the rim
shade, or `gb` from `_UV_LABELS` each fail their own cases.

### 2x-gbc. The Game Boy Color-only cartridge — clear smoke, and Pokemon Crystal's clear blue glitter

A game that runs only on a Game Boy Color (CGB flag 0x143 = 0xC0) came in the clear
CGB-002 shell, not the Game Boy's: its own shape, with a raised head at the top of the
front and the board showing through. `GbcCartShell` gives such a ROM, `gb` or `gbc`,
one of two bodies in `imported-assets/carts/game_boy_color/`, both codex-photos/gbc-cart's
**debranded mobile LOD0** (own work, `LICENSE-gbc-cart.txt`):

| Body | Board | Picked for | Triangles |
| --- | --- | --- | ---: |
| `gbc_cart_large.glb` | DMG-KGDU-10, coin cell (the board inside Crystal) | a battery in the cartridge type at 0x147 (a game that saves) | 15,882 |
| `gbc_cart_small.glb` | DMG-A09-10, MBC5 only | everything else | 14,114 |

Real saving boards vary (only the MBC3 ones carry a clock crystal): the board is the
nearer of two, not the game's own. Both are 57 × 65 mm, 9 mm over the head and 7.2 mm
at the body, connector on −Y, label on +Z; `MediaDimensions.CART_SIZE_GBC` is that
size and `cart_size()` returns it for either body, so neither is stretched (the `gb`
and `gbc` rows stay the Game Boy shell's, which dual-mode games still spawn in).
Seated, the body's AABB centre is on the seat like any cart, so the flat body sits
0.9 mm off it, away from the head; in the detailed GBA's slot that leaves 0.30 mm to
the front wall and 0.35 mm to the back one (measured against codex-photos/gba's
slot numbers, not probed), and the head starts 3.3 mm above the back wall.

The GBC-only Korean Pokemon Gold and Silver keep the Game Boy's shell in gold and
silver: a CGB-only ROM takes this body only when `GbCartShell` has no title shell
for it.

**The shell** (`Resources/gbc_cartridge_shells.tres`, palette id `gbc`):

| Header | Preset |
| --- | --- |
| title `PM_CRYSTAL`, Nintendo (new licensee `01`), every market | `crystal`: clear blue with metal glitter |
| any other | `smoke`: the standard clear smoke |

Assumption open: the Japanese Crystal (`BXTJ`) is the same clear blue.

**Clear glitter.** Crystal is a `METAL_FLAKE` preset with opacity below 1, which
`CartridgeColor` now paints as clear plastic with flakes in it, not as the solid flake
shader: both clear passes include `cartridge_clear_flake.gdshaderinc`, placing the
flakes exactly as `cartridge_flake_plastic.gdshader` does. The filter pass blacks out
what is behind a flake (it is metal); the surface pass lights it as a tilted mirror,
fading to its average once a flake is under a pixel. `flake_amount` 0 is plain clear
plastic, so every other clear shell renders as before. A mixed metal-flake colour
borrows Crystal's flakes but is always solid (`flake_finish` sets opacity 1). A solid
metal-flake preset (the gold and silver) still goes to the solid flake shader.

**The export** (`codex-photos/gbc-cart-work/export_retroxr.py`, from the saved .blend)
makes the shell solid, one smoke colour and no frost texture, so the preset does all
the clear work; the four moulding materials are `GBC_Shell_Front`, `GBC_Shell_Rear`
(stipple normal map, 10 mm per UV) and `GBC_Shell_Smooth` / `GBC_Shell_Edge` (the
polished lettering and ridges, which keep their own roughness when solid). Board parts
are renamed `Interior_*` so frost blurs them; `Contacts_32` stays sharp at the open
mouth. The front shell leaves 44 triangles unmapped per body: run
`Tools/glb/fix_unmapped_uvs.py --tile 10` on any re-export.

**The colours are fitted**, as the GBA's are: `Tools/models/gbc_cart_render_probe`
(`--fit`, windowed) lays each preset on the large board, label up, on white under flat
light, ortho from above at 10 px/mm (near/far 0.1-0.3 m), wearing the scraped label of
the cartridge photographed, and takes the per-channel linear median of the shell
outside the recess divided by the median of the label's pale side strips (the exposure
and white-balance reference; a red label's median is not). Targets from the same frame
of each photo: smoke `(0.268, 0.299, 0.220)` from codex-photos/gbc-cart IMG_1634 (an
Oracle of Seasons, whose ScreenScraper label the fit wears), Crystal
`(0.598, 1.067, 1.331)` from ScreenScraper's CGB-BYTE-USA photo. Fitted within 1 % on
every channel: smoke `#7d8584` opacity 0.75, Crystal `#a7c7db` opacity 0.9. Opacity and
frost (0.45 both, so the glitter is not lost in cloud) are set from the photos, then
the colour is fitted. Re-fit rather than retune by eye.

`gbc_cart_tests` (101 cases): resources, model, branding, uv, surfaces, clear,
glitter, kept, lookup, size, cartridge, forced, menu. Mutation-tested: dropping the
CGB-only rule fails 12 cases, clear presets losing their glitter
fail 4, and dropping the Korean Gold/Silver exception fails 2.
