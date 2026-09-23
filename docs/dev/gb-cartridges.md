# §2x — Game Boy cartridges

### 2x. Game Boy cartridges — one body, a moulded colour, a scraped sticker

`RetroCartridge` builds a `gb` cartridge (`.gb` and `.gbc`; the `gbc` folder is an
alias of `gb`) from `imported-assets/carts/game_boy/gb_cart.glb`: the unbranded Quest
close export of the Codex Kirby's Block Ball model, 14,386 triangles, 57 × 65 × 7.5 mm,
connector on −Y and label on +Z, so it drops into the frame with no turn. The LODs are
Godot's own (`meshes/generate_lods`), not Codex's `_lod1` file. `MediaDimensions`' `gb`
size is the model's own, so it is not stretched.

**The shell** is chosen by `GbCartShell` from the ROM header (0x150 bytes, never
hashed), from `Resources/gb_cartridge_shells.tres`:

| Header | Shell |
| --- | --- |
| title `POKEMON_GLD` / `POKEMON_SLV`, Nintendo | gold / silver (metal flake), every market |
| title `POKEMON RED` / `POKEMON BLUE` / `POKEMON YEL…`, Nintendo, destination 0x14A ≠ 0 | red / blue / yellow |
| same, destination 0x14A = 0 (Japan) | grey: the Japanese Red, Blue and Pikachu were standard grey |
| title `POKEMON GREEN`, Nintendo | green |
| CGB flag 0x143 = 0x80 (runs on both machines) | black |
| anything else, GBC-only 0xC0 included | grey |

The titles are one per game across languages: every European Red is `POKEMON RED`,
every Gold `POKEMON_GLD` + a game code. Measured 2026-09-22 on every Pokemon ROM in
a No-Intro `gb`/`gbc` set: destination is 0 on every Japanese release and 1 elsewhere,
Korea included. Every value in the palette is a visual approximation; grey is the model's
own imported plastic, so the default is the model as authored.

Assumptions still open: Japanese Gold/Silver are coloured (the source checked says
nothing); Green is green though some Midori shipped grey; Japanese Pikachu is grey
like Japan's other first-generation carts; GBC-only games (clear carts) stay grey
because no preset was asked for.

**Painting.** `CartridgeColor` takes a system id (`apply_preset(cart, &"red", "gb")`);
N64 is the default and keeps its palette. The GB moulding is four materials:
`Gray_ABS_Textured` (front), `Rear_ABS_Rough`, `Gray_ABS_Smooth` (rails and bowl, one
mesh across both halves) and `Shell_Seam_Shadow` (the rim round the sticker).
`SHADE` keeps the model's own ratios to the front, 1.03 and 0.65, so the rim stays
darker than the shell in any colour and grey reproduces the model; `OWN_ROUGHNESS`
keeps each one's roughness. PCB, contacts, screw, cavity and label are never painted,
and `demetal` does not run (contacts and screw are metal).

**Forcing a shell**: held for a second, a `gb` ROM row opens
`_show_cart_spawn_options`, the N64's sub-menu without the Body row, with the
swatches of the Game Boy palette. The id lands in `RetroCartridge.shell_preset`
(saved by `scene_persistence`); an id the GB palette does not hold, an N64 one
included, is ignored and the ROM's own shell is used.

**The sticker**: the scraped `media/label/<rom>.png` is painted onto the UV-mapped
`Label` mesh (`_UV_LABELS`), which covers 0–1 with the image's top left at the
label's top left; the embedded 4 × 4 white is only a placeholder.

**The export leaves the rear shell unmapped** (876 triangles at one UV), the same
Blender bug as the N64 front shell: run `Tools/glb/fix_unmapped_uvs.py` on any
re-export. `gb_cart_tests` `uv/` fails otherwise.

`gb_cart_tests` (68 cases): resources, model, branding, uv, surfaces, color, flake,
kept, lookup, cartridge, forced. Mutation-tested: dropping the destination check, the rim
shade, or `gb` from `_UV_LABELS` each fail their own cases.
