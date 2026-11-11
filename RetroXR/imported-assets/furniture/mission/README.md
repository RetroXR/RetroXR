# Mission bedroom pair (nightstand and six-drawer chest)

Built in RetroXR-models `generic/mission-bedroom` (`python build_all.py`, Blender 5.3) from the owner's photos; sizes
estimated until measured. Copy the six `*_mobile*.glb` and both `*_contract.json` here; never edit a GLB. The GLBs'
own LODs stay off and the extracted stain imports VRAM Compressed with mipmaps (`texture_import_tests`).

`DrawerFurniture` (`Scripts/Objects/furniture/drawer_furniture.gd`) reads each contract at run time (a `.json` is a
JSON resource and ships with the export, as `vcr_contract.json` does) and builds the case collision and one sliding
`VRDrawer` per drawer from it.

Our own model; the wood is ambientCG's Wood066 (CC0).
