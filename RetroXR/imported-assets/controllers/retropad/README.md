# RETRO XR controller plug

RetroXR's own generic controller plug: the connector a pad's cable shows until its console names one of its own
(`Scenes/Objects/cables/controller_cable.tscn`, `PlugTip`). An original design (the approved concept's option A: an
octagonal nickel nose with three gold pins, a red ring, a black boot with finger flats, a ribbed strain relief); it
copies no console's connector. Made for this project, no third-party content, so nothing to credit in About.

- Source: RetroXR-models `generic/retropad/build_plug.py` (Blender 5.3, `--background --factory-startup`).
- `plug_mobile.glb` is that export copied in unchanged; `plug_contract.json` its frame and bounds.
- `retropad_plug_mesh.res` is baked from it by `Tools/gen/extract_retropad_plug.gd`, which refuses a mesh that no
  longer sits connector-on-+Z or no longer fits ControllerPlug's collision box (x +-10, y +-9.8, z -40 .. +18 mm).

Frame: glTF/Godot metres, connector in along +Z, the cord leaving at z -0.040 along -Z (the scene's `CordExit`).
2068 triangles, one mesh, five materials (boot, ring, metal, gold, face), no textures.

To change it: edit build_plug.py, run it, copy `exports/plug_mobile.glb` + `plug_contract.json` here, run
`--editor --quit`, then the extract script.
