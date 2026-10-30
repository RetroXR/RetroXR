# cassette_deck

Original RetroXR asset: built from scratch in the RetroXR-models repository (`generic/cassette-deck`,
`python build_all.py`), so it has the project's own licence and needs no third-party credit. Rebuild there and
copy the three mobile levels (`*_mobile*.glb`) and the `*_contract.json` here; never edit the GLBs.

LOD0 / LOD1 / LOD2 are the item's own levels (`meshes/generate_lods` stays off): LOD0 keeps the keys separate so
they press, LOD1 and LOD2 are one Body + one atlas. The contract JSON holds the animation timings, pivots and seats
the scene script reads (the door's Open / Close, its hinge and TapeSeat, the reel spindles). The display mesh ships black: the engine draws the vacuum fluorescent display.
