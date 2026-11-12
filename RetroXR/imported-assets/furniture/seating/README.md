# RETRO XR seating (three sofas, two stools, a desk chair, a papasan chair, a pouf)

Our own models, built in RetroXR-models `generic/seating` (`python build_all.py`, Blender 5.3) from the concept sheet
the owner chose; sizes estimated (that folder's MEASUREMENTS.md). Copy the `*_mobile.glb`, `*_mobile_lod1.glb`,
`*_mobile_lod2.glb` and `*_contract.json` of each piece here; never edit a GLB. The GLBs' own LODs stay off and the
extracted textures import VRAM Compressed with mipmaps, the normal maps as normal maps (`texture_import_tests`).

`ContractSeat` (`Scripts/Objects/room/contract_seat.gd`) reads each contract at run time and builds the collision, the
places to sit (a sofa has three) and the stand points from it (docs/dev/seats.md).

Textures: CC0 1.0 from ambientCG, tinted in RetroXR-models: Wood066 (walnut, oak, pine, the dark feet), Fabric036 (the
upholstery), Fabric061 (the pouf's weave), Wicker013 (the papasan's rattan).
