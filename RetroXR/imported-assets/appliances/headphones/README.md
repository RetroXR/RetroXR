# RETRO XR portable headphones

From RetroXR-models `generic/headphones-portable` (an invented product, the user's approved concept 2): the three
mobile levels, the 3.5 mm plug and the contract, copied in unchanged. Never edit a GLB here; rebuild there and copy.
After a re-import, put the extracted textures back to VRAM Compressed (High Quality on the ORM and print atlases) and
the GLBs to `generate_lods=false` (texture_import_tests).

Frame: glTF meters, +Y over the head, the cups at +-X, the wearer looking along -Z; the origin between the ear canals.
Moving nodes (`YokeL/R`, `CupL/R`, origins on the pivots) and `CordExit` (a child of `CupL`, -Z the way the cord
leaves) are in `headphones_contract.json`. Michroma (OFL) is already credited in the About panel.
