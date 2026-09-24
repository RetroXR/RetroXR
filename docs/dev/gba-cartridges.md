# §2y — Game Boy Advance cartridges

### 2y. Game Boy Advance cartridges — one tintable body, solid or clear plastic

`RetroCartridge` builds a `gba` cartridge from
`imported-assets/carts/game_boy_advance/gba_cart.glb` (`GbaCartShell.BODY`): the
no-logos `gba_cartridge_tintable.glb` from `codex-photos/gba-cart`
(`build_tintable.py`), 60 × 35 × 9 mm, copied in unchanged. Nine meshes:

- `Front_Shell`, `Rear_Shell` (materials `Tintable_Front_Plastic` /
  `Tintable_Rear_Plastic`: colour factor + normal + ORM, no colour texture). The
  rear marking panel ("MODEL NO. AGB-002") is part of `Rear_Shell`, so it tints
  and goes clear with it. It used to be an opaque plate baked dark from the grey
  cart photographed: the black rectangle on the back of a clear cart.
- `Interior_PCB` (component side, trace side, green edge), `Interior_ROM_Chip`,
  `Interior_RTC_Chip`, `Interior_Save_Battery`: the AGB-E05-01 board Ruby and
  Sapphire use, from FexCollects' photos (gbhwdb, CC BY-SA 4.0, credited in the
  About panel and `LICENSE-gba-cart.txt`), 1024 × 650, "Nintendo" silkscreen
  removed, and the photographed background beyond the board filled with board
  green (no white fringe, no mipmap halo). It continues from z = −9.45 to +15 mm;
  the component side faces the label, as the scanned contact strip's gold does.
  Board size, notch (3.3 mm) and part heights are fitted to the photos, not
  measured.
- `Connector_PCB`: the scanned contact strip (its geometry is the part fitted to
  the slot), now wearing the same two photos at the same scale, so the
  silkscreen and the photographed gold contacts run on across the join.
- `Opaque_Internal_Details`: the tri-wing screw.
- `Label`: the sticker, 43.0 × 22.0 mm (the front recess reshaped to match; it was
  45.4 × 22.8), a white placeholder the scraped art is laid over, fitted inside
  without stretching (not UV-mapped).

**Frost: foggy plastic.** Real moulded clear plastic scatters a little, so what is
inside looks out of focus and flat, and the plastic itself is patchy and satin
rather than glassy. `CartridgeShellPreset.frost` (0 glass, 1 fully frosted; the
clear three 0.40–0.45, FireRed and LeafGreen 0.85) drives three cheap effects, no
screen copy:

- the inside (`FROSTED_PARTS`: `Interior_*`, `Connector_PCB`) goes onto
  `cartridge_frosted_interior.gdshader` while the shell is clear: its texture
  sampled `frost × FROST_BLUR` (6) mip levels down, and `frost × FROST_FLATTEN`
  (0.55) of the way to its own average colour. Only ever seen through the shell,
  so blurring the parts is the whole effect. A solid shell or a reset puts every
  part back on exactly its own material.
- both clear passes share `cartridge_clear_cloud.gdshaderinc`: patches about
  1.8 mm across (three octaves) vary the filter's density and the surface's
  scatter by `min(frost × FROST_CLOUD, 1)` (FROST_CLOUD 1.6), matching the fine
  blotchy look of a real Ruby.
- the surface's roughness gets the moulded finish: a 0.3 mm grain of ±
  `CLEAR_GRAIN` (0.2), fading to the preset's roughness once a grain is under a
  pixel, and milkier patches a little more matte. The model's own ORM roughness
  is a flat 0.42, so the grain is procedural. FireRed and LeafGreen are
  roughness 0.55, the clear three 0.35.

A plain translucent colour (`apply_color` with alpha) does not frost.

**The rear marking panel** is one surface of `Rear_Shell`, joined to the recess wall
by a narrow rim under its edge (no floor under it, which tinted twice and read as a
darker rectangle; and no gap, which once let the board show round it as a green
line even on a solid cart). Checked by casting 12,444 rays from behind across all
four edges: none reaches the interior. Where the rim sits under the edge, a clear
shell tints twice, which reads as the thin darker outline of a moulded recess.

**The shells export solid** (`OPAQUE`, alpha 1): a cartridge is clear only when a
preset makes it so. An earlier export was 82 % opaque and blended by default; if
one ever is again, make it solid before it goes in. The imported grey is sRGB
`(0.4614, 0.4731, 0.4845)` — glTF's linear 0.18/0.19/0.20.

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

FireRed/LeafGreen codes and maker are pret's `pokefirered/config.mk`.

**The colours are fitted, not picked.** A probe (re-run whenever the model's interior changes) rendered each preset lying on a
white surface under flat front light (ortho camera, near/far 0.1–0.3 m: the
default 4 km far plane lets the recess floor, 0.47 mm behind the label, win the
depth test and tint the label), took the per-channel median colour of the shell outside the
label (the board showing through, as it does on the real cart), and scaled the
preset colour until that median met the photo's: Ruby `#653634`, measured the
same way from a flat scan; Sapphire `#2c3aa6`, Emerald `#2cbf3c`, FireRed `#e45a4c`,
LeafGreen `#4d9a5c`, read off photos the user supplied. Opacity is from the same photos: Ruby 0.65,
Sapphire 0.6 and Emerald 0.55 are clear; FireRed and LeafGreen are FROSTED, 0.9,
milkier and hiding more of the inside. Re-fit rather than retune by eye.
Assumption open: the Japanese releases are clear too.

**Clear plastic.** `CartridgeShellPreset.opacity` (default 1). Below 1 — or
`apply_color` with a colour whose alpha is below 1 — `CartridgeColor` puts the
surface on `cartridge_clear_plastic.gdshader` with
`cartridge_clear_plastic_surface.gdshader` as its next pass, NOT an alpha blend:

- the filter pass (`blend_mul`, unshaded) multiplies what is already drawn behind
  by the preset colour raised to `density / facing`, so the silhouette reads
  thicker. `density` = opacity × `CLEAR_DENSITY`. The colour is used as the wall's
  real transmittance: normalising it so the dye's own channel passed whole (tried)
  made every red shell a bright fire-engine red, far off the real Ruby.
- the surface pass (`blend_add`, lit) adds the gloss at full strength with the
  half's normal map, and `haze` = opacity × `CLEAR_HAZE` of lit dye colour.
  Roughness is the preset's (0.35; a plain colour gets `CLEAR_ROUGHNESS`).

Multiply and add commute and neither writes depth, so the two halves and stacked
carts need no sorting and have no overlap artefacts. What an alpha blend got wrong,
and why this replaced it: it washed the background toward the shell colour
instead of filtering it (a grey, milky look), faded the reflections with the
body, and depended on draw order. No screen texture is read, so it costs a Quest
two cheap passes. At 1 the plain `StandardMaterial3D` path is untouched. Metal
flake ignores opacity. The two shell materials are in
`EXTERIOR_PLASTIC` and `OWN_ROUGHNESS` (the solid path keeps the ORM map's
roughness). `demetal` skips them: they carry a metallic map.

**Forcing a shell**: `_has_spawn_options` includes `gba`, so a held ROM row opens
`_show_cart_spawn_options` with the GBA swatches, as for GB.

`gba_cart_tests` (69 cases): resources, model, surfaces, color, clear, kept,
lookup, cartridge, forced. Mutation-tested: sending clear shells down the solid path fails 11
cases, dropping the maker check fails `lookup/a Pokemon game code from another maker`.
