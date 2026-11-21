# Connectors

Plug models the game's own leads wear, from RetroXR-models (the user's own repository, so the project's
licence and no third-party credit). Copied in unchanged: never edit a GLB here; rebuild there and copy. Each is in
RetroXR's plug frame (connector +Z, origin on the mating face, an empty `CordExit` where the cord leaves along -Z).
After a re-import, put the GLBs back to `generate_lods=false` and any extracted texture back to VRAM Compressed
(normal maps as normal maps; `texture_import_tests`).

| folder | source | worn by |
|---|---|---|
| `usb_a_plug/usb_a_plug.glb` | `generic/usb-a-plug/exports/usb_a_plug_mobile.glb` (14db39fe3) | `jvs_cable.tscn` End A; the GunCon 2 mod by path |
| `usb_b_plug/usb_b_plug.glb` | `generic/usb-b-plug/exports/usb_b_plug_mobile.glb` (ba75cddd1) | `jvs_cable.tscn` End B (`PlugB0/Shell`, rolled half round about Z and 3.12 mm back: the scene says why) |
| `rj45_plug/rj45_plug.glb` | `generic/rj45-plug/exports/blue/rj45_plug_blue_mobile_clean.glb` (31693eed2) | both ends of `ethernet_cable.tscn` |
| `jst_vl_plug/jst_vl_plug.glb` | `generic/jst-vl-plug/exports/naomi/jst_vl_plug_naomi_mobile_clean.glb` | both ends of `naomi_power_cable.tscn` |
| `vga_plug/vga_plug.glb` | `generic/vga-plug/exports/blue/vga_plug_blue_mobile_clean.glb` | both ends of `vga_cable.tscn` |
| `hdmi_plug/hdmi_plug.glb` | `generic/hdmi-plug/exports/hdmi_plug_mobile_clean.glb` (856207fb9; the WUP-008's shape without its oval) | both ends of `hdmi_cable.tscn` |
| `svideo_plug/svideo_plug.glb` | `generic/svideo-plug/exports/black/svideo_plug_black_mobile_clean.glb` (ba1dfd960; a molded 4-pin mini-DIN on `common/minidin.py`, no marks) | `PlugB0` of `n64_svideo_cable.tscn` and `ps2_svideo_cable.tscn` |
| `svideo_port/svideo_socket.glb` | `generic/svideo-socket/exports/black/svideo_socket_black_mobile_clean.glb` (b6693259b: a round collar, a nickel lip, a lit gray insert) | `svideo_port.tscn` (`SvideoSocket`, its mouth AT the zone: the plug's nose stops there, the collar 1.2 mm behind on the panel) |
| `scart_plug/scart_plug.glb` | `generic/scart-plug/exports/black/scart_plug_black_mobile_clean.glb` (ff14cd476; `common/scart.py`'s face) | `PlugB0` of the five `*_scart_cable.tscn` |
| `scart_port/scart_socket.glb` | `generic/scart-socket/exports/black/scart_socket_black_mobile_clean.glb` (ff14cd476) | `scart_port.tscn` (`ScartSocket`, its mouth AT the zone, the bezel's back 3.2 mm behind on the panel) |
| `hdmi_port/hdmi_socket.glb` | `generic/hdmi-socket/exports/hdmi_socket.glb` (096cc328c; a short Blender script, not cartkit) | `hdmi_port.tscn` (`HdmiSocket`, 0.8 mm behind the zone: the plug stops on its surround) |
| `hpdb50_plug/hpdb50_plug.glb` | `generic/hpdb50-plug/exports/naomi/hpdb50_plug_naomi_mobile_clean.glb` | both ends of `gd_cable.tscn` |
| `jamma_plug/jamma_plug.glb` | `generic/jamma-plug/exports/keyed/jamma_plug_keyed_mobile_clean.glb` (the keyed model, d5aebc2ac) | both ends of `jamma_cable.tscn` (`Shell` turned half round about Z; its harness leaves along the plug's -Y, which the rope's exit axes say) |
| `ps2_plug/ps2_plug_purple.glb` | `generic/ps2-plug/exports/purple/ps2_plug_purple_mobile_clean.glb` | the PC keyboard's lead (`RetroKeyboard.PLUG_MESH`, through `ControllerPlug.set_plug_mesh`) |
| `ps2_plug/ps2_plug_green.glb` | `generic/ps2-plug/exports/green/ps2_plug_green_mobile_clean.glb` | the PC mouse's lead (`RetroMouse.PLUG_MESH`) |
| `trs_plug/trs_plug.glb` | `generic/trs-plug/exports/lime/trs_plug_lime_mobile_clean.glb` | both ends of `trs_cable.tscn` |
| `trs_plug/trs_plug_black.glb` | `generic/trs-plug/exports/black/trs_plug_black_mobile_clean.glb` | the headphones' plug (`HeadphonesPlug.PLUG_GLB`, its mesh and CordExit taken in `_ready`) and both ends of `sega_cd_mixing_cable.tscn` |
| `trs_rca_adapter/trs_rca_adapter.glb` | `generic/trs-rca-adapter/exports/mini/trs_rca_adapter_mini_mobile_clean.glb` (the 3.5 mm model) | the whole block of `trs_rca_adapter.tscn` (`PlugA0/Shell`; its `RcaJackL`/`RcaJackR` mouths are where the jacks' zones stand) |
| `scart_adapter/scart_adapter.glb` | `nintendo/snes/scart-adapter/exports/snsp015/scart_adapter_snsp015_mobile_clean.glb` (8bd0b3a6d; Nintendo's SNSP-015, no marks but its jacks' names) | the whole block of `scart_adapter.tscn` (`PlugA0/Shell`, **turned a quarter about X**: the model's own frame has the shell along -Y and the lettering +Z; its `RcaJack*` mouths are where the jacks' zones stand) |
| `barrel_plug/barrel_plug_<key>.glb`, `barrel_plug_<key>_l.glb` | `generic/barrel-plug/exports/<key>[_l]/barrel_plug_<key>[_l]_mobile_clean.glb`, keys `5521`, `5525`, `3513`, `eiaj01`, `eiaj02`, `eiaj03` | an AC adapter's DC plug when its row names no `plug_model` (`DcPlugShape.model_path`: the L one where `plug_mm` is much taller than wide); `PowerBrick` tints `BPLUG_Body` to the row's `cord`. Keyed plugs keep `DcPlugShape`'s primitive |

The PS/2 and 3.5 mm plugs replaced `DevTools/gen/gen_ps2.gd`'s and `gen_trs.gd`'s baked plugs (2026-11-15); the sockets
are still those generators' `.res`, and the old plug `.res` files stay for them. Both were mods (`xenu.usba`, `xenu.rj45`) until 2026-11-14. An old `xenu.rj45` still installed changes nothing: it
skips a plug that already has a `Shell`, and lays the same cord colour and thickness the scene now has.
