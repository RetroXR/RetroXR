# tv_remote

Original RetroXR asset: built from scratch in the RetroXR-models repository (`generic/tv-remote`,
`python build_all.py`), so it has the project's own licence and needs no third-party credit. Rebuild there and
copy the three mobile levels (`*_mobile*.glb`) and the `*_contract.json` here; never edit the GLBs.

LOD0 / LOD1 / LOD2 are the item's own levels (`meshes/generate_lods` stays off): LOD0 keeps the 26 keys separate
(tv_remote.gd adopts each key into a VRButton, so it presses), LOD1 and LOD2 are one Body + one atlas, and every
level keeps `BatteryCover` its own mesh (tv_remote.gd makes it a CoverSlots cover). The contract JSON holds each
key's face center, IrTip, the cover and the two AAA markers (`BatteryAAA1/2`, CellSlots seats).
