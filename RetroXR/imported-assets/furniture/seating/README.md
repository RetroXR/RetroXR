# RETRO XR seating (three sofas, two stools, a desk chair, a papasan chair, a pouf, six floor seats)

Our own models, built in RetroXR-models `generic/seating` (`python build_all.py`, Blender 5.3) from the concept sheet
the owner chose; sizes estimated (that folder's MEASUREMENTS.md). Copy the `*_mobile.glb`, `*_mobile_lod1.glb`,
`*_mobile_lod2.glb` and `*_contract.json` of each piece here; never edit a GLB. The GLBs' own LODs stay off and the
extracted textures import VRAM Compressed with mipmaps, the normal maps as normal maps (`texture_import_tests`).

`ContractSeat` (`Scripts/Objects/room/contract_seat.gd`) reads each contract at run time and builds the collision, the
places to sit (a sofa has three) and the stand points from it (docs/dev/seats.md). The six FLOOR seats (floor_cushion_square,
floor_cushion_round, zabuton, flip_chair, floor_pillow, floor_rocker) have tops under 0.3 m and a floor-sitter's eyes.

Textures: CC0 1.0 from ambientCG, tinted in RetroXR-models: Wood066 (walnut, oak, pine, the dark feet), Fabric036 (the
upholstery), Fabric061 (the pouf's weave), Wicker013 (the papasan's rattan), Leather037 (the floor rocker's black and
red vinyl). The round cushion's corduroy wales and the flip chair's geometric print are drawn procedurally in
RetroXR-models' `tools/prep_textures.py`, nothing photographed.
