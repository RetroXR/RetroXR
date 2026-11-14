# Connectors

Plug models the game's own leads wear, from RetroXR-models (the user's own repository, so the project's
licence and no third-party credit). Copied in unchanged: never edit a GLB here; rebuild there and copy. Each is in
RetroXR's plug frame (connector +Z, origin on the mating face, an empty `CordExit` where the cord leaves along -Z).
After a re-import, put the GLBs back to `generate_lods=false` and any extracted texture back to VRAM Compressed
(normal maps as normal maps; `texture_import_tests`).

| folder | source | worn by |
|---|---|---|
| `usb_a_plug/usb_a_plug.glb` | `generic/usb-a-plug/exports/usb_a_plug_mobile.glb` (14db39fe3) | `jvs_cable.tscn` End A; the GunCon 2 mod by path |
| `rj45_plug/rj45_plug.glb` | `generic/rj45-plug/exports/blue/rj45_plug_blue_mobile_clean.glb` (31693eed2) | both ends of `ethernet_cable.tscn` |

Both were mods (`xenu.usba`, `xenu.rj45`) until 2026-11-14. An old `xenu.rj45` still installed changes nothing: it
skips a plug that already has a `Shell`, and lays the same cord colour and thickness the scene now has.
