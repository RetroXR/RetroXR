# crt_tv

Original RetroXR asset: built from scratch in the RetroXR-models repository (`generic/crt-tv`, `python build_all.py`),
so it has the project's own licence and needs no third-party credit. Rebuild there and copy the three mobile levels
(`tv_mobile*.glb`) and `tv_contract.json` here; never edit the GLBs.

LOD0 / LOD1 / LOD2 are the item's own levels (`meshes/generate_lods` stays off): LOD0 keeps the keys separate so they
press, LOD1 and LOD2 are one Body + one atlas; Screen, PowerLed and KeyDoor stay their own nodes on every level. The GLB
carries the RetroTVShell markers (ScreenSeat, PortSeat, SpeakerOutSeat, VgaPortSeat, AmbilightSeat) and an empty at
every socket's mouth; `Scenes/Objects/tv_models/retroxr_crt.tscn` wears it. The model's Screen is hidden: the set's own
tube (ScreenMesh, the CRT shader) is seated on ScreenSeat and draws the picture.
