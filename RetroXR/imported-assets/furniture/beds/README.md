# RETRO XR beds (captain's, white-and-brass and waterbed queens; wooden and race-car twins)

Our own models, built in RetroXR-models `generic/beds` (`python build_all.py`, Blender 5.3) from the concept sheets
the owner chose; the mattresses are standard US sizes, the frames estimated (that folder's MEASUREMENTS.md). Copy the
`*_mobile.glb`, `*_mobile_lod1.glb`, `*_mobile_lod2.glb` and `*_contract.json` of each bed here; never edit a GLB. The
GLBs' own LODs stay off and the extracted textures import VRAM Compressed with mipmaps, the normal maps as normal maps
(`texture_import_tests`).

`ContractSeat` (`Scripts/Objects/room/contract_seat.gd`) reads each contract at run time: the collision, a place to
sit on the edge and one to lie on the pillow, the stand points, and the captain's bed's three and the waterbed's two
drawers (FurnitureDrawers, sliding out of the bed's side; docs/dev/seats.md, furniture.md).

Textures: the wood is ambientCG's Wood066 (CC0 1.0), tinted golden oak and dark walnut; every bedding pattern (plaid,
florals, stripes, quilting) is drawn procedurally in RetroXR-models' `tools/prep_textures.py`, nothing photographed.
