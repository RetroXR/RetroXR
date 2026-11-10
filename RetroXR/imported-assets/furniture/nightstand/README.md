# RETRO XR mid-century nightstand

Built in RetroXR-models `generic/nightstand` (`python build_all.py`, Blender 5.3). Copy the three `*_mobile*.glb` and
`nightstand_contract.json` here; never edit a GLB. The GLBs' own LODs stay off (`meshes/generate_lods=false`), and the
extracted wood textures import VRAM Compressed with mipmaps (the normal map as a normal map): `texture_import_tests`.

`Scripts/Objects/furniture/nightstand.gd` copies the contract's collision boxes and markers into consts (JSON is not
exported); `nightstand_tests` checks they still match this file.

Our own model; the wood is ambientCG's Wood066 (CC0).
