# audio_cassette

Original RetroXR asset: built from scratch in the RetroXR-models repository (`generic/audio-cassette`,
`python build_all.py`), so it has the project's own licence and needs no third-party credit. Rebuild there and
copy the three mobile levels (`cassette_mobile*.glb`) and `tape_contract.json` here; never edit the GLBs.

The game's AudioCassette wears it (`CompactCassette`, `Scripts/Objects/media/compact_cassette.gd`) unless a mod
dresses the cassette (`AudioCassette/shell`). LOD0 / LOD1 / LOD2 are the model's own levels
(`meshes/generate_lods` stays off). The packs are blend shapes the script drives from the tape's position;
`tape_contract.json` holds the hub, roller and pack geometry the script's constants repeat.
