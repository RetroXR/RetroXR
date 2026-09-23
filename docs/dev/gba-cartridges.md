# §2y — Game Boy Advance cartridges

### 2y. Game Boy Advance cartridges — one tintable body, solid or clear plastic

`RetroCartridge` builds a `gba` cartridge from
`imported-assets/carts/game_boy_advance/gba_cart.glb` (`GbaCartShell.BODY`): the
no-logos `gba_cartridge_tintable.glb` from the Codex GBA cart work
(`codex-photos/gba-cart/build_tintable.py`), 2,595 triangles, 60 × 35 × 9 mm. Four
meshes: `Front_Shell` and `Rear_Shell` (materials `Tintable_Front_Plastic` /
`Tintable_Rear_Plastic`, colour factor + normal + ORM, no colour texture),
`Opaque_Internal_Details` (board, contacts, screw, rear marking panel; atlas) and
`Label` (white placeholder the scraped art is laid over, as before; not UV-mapped).

**The export's shell is 82 % opaque and alpha-blended.** The copy in RetroXR is
patched to solid (`alphaMode` removed, `baseColorFactor` alpha 1 on the two
`Tintable_*` materials) so a cartridge is only clear when a preset makes it so,
and `reset_to_default` gives a solid cart. Do the same to any re-export. The
imported grey is sRGB `(0.4614, 0.4731, 0.4845)` — glTF's linear 0.18/0.19/0.20.

**The shell** is chosen by `GbaCartShell` from the ROM header (0xC0 bytes, never
hashed), from `Resources/gba_cartridge_shells.tres`. Maker code `01` at 0xB0 and the
first three letters of the game code at 0xAC (the fourth is the language, so every
market matches):

| Game code | Game | Shell |
| --- | --- | --- |
| `AXV_` | Ruby | `ruby`, clear red |
| `AXP_` | Sapphire | `sapphire`, clear blue |
| `BPE_` | Emerald | `emerald`, clear green |
| `BPR_` | FireRed | `fire_red`, clear orange-red |
| `BPG_` | LeafGreen | `leaf_green`, clear leaf green |
| anything else, or not maker `01` | | `grey`, solid: the model's own plastic |

FireRed/LeafGreen codes and maker are pret's `pokefirered/config.mk`. Every colour
and opacity is a visual approximation (Ruby's red was matched by eye to a photo).
Assumption open: the Japanese releases are clear too.

**Clear plastic.** `CartridgeShellPreset.opacity` (default 1). Below 1 — or
`apply_color` with a colour whose alpha is below 1 — `CartridgeColor` puts the
surface on `cartridge_clear_plastic.gdshader` with
`cartridge_clear_plastic_surface.gdshader` as its next pass, NOT an alpha blend:

- the filter pass (`blend_mul`, unshaded) multiplies what is already drawn behind
  by the dye: the tint scaled until its strongest channel is 1 (a dye passes its
  own colour whole), raised to `density / facing`, so the silhouette reads thicker.
  `density` = opacity × `CLEAR_DENSITY`.
- the surface pass (`blend_add`, lit) adds the gloss at full strength with the
  half's normal map, and `haze` = opacity × `CLEAR_HAZE` of lit dye colour.
  Roughness is the preset's (0.35; a plain colour gets `CLEAR_ROUGHNESS`).

Multiply and add commute and neither writes depth, so the two halves and stacked
carts need no sorting and have no overlap artefacts. What an alpha blend got wrong,
and why this replaced it: it washed the background toward the shell colour
instead of filtering it (a grey, milky look), faded the reflections with the
body, and depended on draw order. No screen texture is read, so it costs a Quest
two cheap passes. At 1 the plain `StandardMaterial3D` path is untouched. Metal
flake ignores opacity. 0.6 was picked from renders. The two shell materials are in
`EXTERIOR_PLASTIC` and `OWN_ROUGHNESS` (the solid path keeps the ORM map's
roughness). `demetal` skips them: they carry a metallic map.

**The black rectangle on the back** is `Rear_Marking_Panel` (the "MODEL NO.
AGB-002" plate), 50 triangles inside `Opaque_Internal_Details` with the dark colour
baked from the photographed grey cart. On a real clear cart that is embossed shell
plastic. OPEN: move it into `Rear_Shell` so it tints. The board inside is only the
80-triangle contact strip (`Connector_PCB`); a full board (AGB-E05-01 photos in
`codex-photos/gba-cart/pcb`) is also OPEN.

**Forcing a shell**: `_has_spawn_options` includes `gba`, so a held ROM row opens
`_show_cart_spawn_options` with the GBA swatches, as for GB.

`gba_cart_tests` (57 cases): resources, model, surfaces, color, clear, kept,
lookup, cartridge, forced. Mutation-tested: sending clear shells down the solid path fails 11
cases, dropping the maker check fails `lookup/a Pokemon game code from another maker`.
