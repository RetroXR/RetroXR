# RETRO XR living room (six TV stands, five bookcases, four coffee tables)

Our own models, built in RetroXR-models `generic/living-room` (`python build_all.py`, Blender 5.3) from the concept
sheets the owner chose; sizes estimated (that folder's MEASUREMENTS.md). Copy the `*_mobile.glb`, `*_mobile_lod1.glb`,
`*_mobile_lod2.glb` and `*_contract.json` of each piece here; never edit a GLB. The GLBs' own LODs stay off and the
extracted textures import VRAM Compressed with mipmaps, the normal maps as normal maps (`texture_import_tests`).

`DrawerFurniture` (`Scripts/Objects/furniture/drawer_furniture.gd`) reads each contract at run time and builds the
case's collision, every drawer and SLIDING door (VRDrawers, `FurnitureDrawers`) and every HINGED door (a VRDoor with no
knob and no latch, its leaf the model's own `DoorN`) from it (docs/dev/furniture.md "The living-room set"). Tops,
shelves, cubbies and bays are case collision, so a set and its consoles stand on them.

The wall unit's two tower doors are CLEAR glass: `LIV_ClearGlass`, alpha-blended at 12%, the only transparency in the
set (two small panes, one per door, on a Quest).

Textures: CC0 1.0 from ambientCG, tinted in RetroXR-models: Wood066 (the oak, Mission, walnut and pine stains). The
lacquer, glass, brass and white laminate are plain materials.
