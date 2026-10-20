#!/usr/bin/env python3
"""The 64DD disk RetroXR ships: RetroXR-models' own (nintendo/n64/64dd-disk), its
debranded first mobile level (n64dd_disk_mobile_clean.glb), turned into the
floppy frame.

The models repo builds the disk in the cartridge frame: label +Z, the body
running +Y from the shutter's edge, which goes into a slot first along -Y. A
floppy here goes into its drive the other way: label +Z, shutter +Y (it goes in
first) and the index label toward -Y. So every position, normal and tangent is
turned half round about Z, (x, y, z) -> (-x, -y, z), and so are the empties.

Nothing else changes. Its nodes are Cartridge (both halves and the caution
label), Shutter, Label (the title label in the front recess) and LabelTop (the
index label on the trailing edge), each label plain white paper that
cartridge.gd lays the scraped art on. The textures stay embedded; Godot
extracts them beside the GLB on import, and their .import files are VRAM
Compressed with mipmaps (the two normal maps as normal maps, the caution label
High Quality).

    python Tools/glb/prepare_64dd_disk.py \
        [--src ~/RetroXR-models/nintendo/n64/64dd-disk/exports/n64dd_disk_mobile_clean.glb] [--verify]
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepare_n64_pad import read_glb, write_glb  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "RetroXR", "imported-assets", "carts", "nintendo_64dd", "n64dd_disk.glb")
SRC = os.path.join(os.path.expanduser("~"), "RetroXR-models", "nintendo", "n64", "64dd-disk", "exports",
                   "n64dd_disk_mobile_clean.glb")
NODES = {"N64DDDisk", "Cartridge", "Shutter", "Label", "LabelTop", "LabelAnchor", "LabelTopAnchor"}
HALF_TURN = np.diag([-1.0, -1.0, 1.0])


def vec_accessor(gltf: dict, blob: bytearray, ai: int, width: int) -> tuple[int, np.ndarray]:
    acc = gltf["accessors"][ai]
    if acc["componentType"] != 5126:
        raise SystemExit(f"accessor {ai}: not float32")
    bv = gltf["bufferViews"][acc["bufferView"]]
    if bv.get("byteStride", width * 4) != width * 4:
        raise SystemExit(f"accessor {ai}: interleaved; cannot turn it in place")
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return base, np.frombuffer(bytes(blob[base:base + acc["count"] * width * 4]), np.float32).reshape(-1, width).copy()


def half_turn(gltf: dict, blob: bytearray) -> None:
    """Positions, normals and tangents (xyz; w is unchanged by a proper rotation) and the nodes' translations."""
    done: set[int] = set()
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            for key, width in (("POSITION", 3), ("NORMAL", 3), ("TANGENT", 4)):
                ai = prim["attributes"].get(key)
                if ai is None or ai in done:
                    continue
                done.add(ai)
                base, v = vec_accessor(gltf, blob, ai, width)
                v[:, :3] = v[:, :3] @ HALF_TURN.T
                blob[base:base + v.size * 4] = v.astype(np.float32).tobytes()
                if key == "POSITION":
                    gltf["accessors"][ai]["min"] = [float(x) for x in v.min(0)]
                    gltf["accessors"][ai]["max"] = [float(x) for x in v.max(0)]
    for node in gltf["nodes"]:
        if node.get("rotation", [0, 0, 0, 1]) != [0, 0, 0, 1] or "matrix" in node:
            raise SystemExit(f"node {node.get('name')!r} carries a rotation; turn it too")
        if "translation" in node:
            node["translation"] = [float(x) for x in np.array(node["translation"]) @ HALF_TURN.T]


def verify(path: str) -> int:
    gltf, blob = read_glb(path)
    bad = 0
    names = {n.get("name") for n in gltf["nodes"]}
    if names != NODES:
        print(f"  FAIL: nodes {sorted(names)}, expected {sorted(NODES)}")
        bad += 1
    lo, hi = np.full(3, 1e9), np.full(3, -1e9)
    for node in gltf["nodes"]:
        if "mesh" not in node:
            print(f"  {node['name']:14s} marker t={[round(v * 1000, 2) for v in node.get('translation', [0, 0, 0])]} mm")
            continue
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            lo, hi = np.minimum(lo, acc["min"]), np.maximum(hi, acc["max"])
        print(f"  {node['name']:14s} {len(gltf['meshes'][node['mesh']]['primitives'])} primitives")
    print(f"  bounds {np.round(lo * 1000, 2)} .. {np.round(hi * 1000, 2)} mm")
    # The shutter's edge leads (+Y, at the body's top), the index label trails (-Y), the label faces +Z.
    shutter = next(n for n in gltf["nodes"] if n.get("name") == "Shutter")
    top = next(n for n in gltf["nodes"] if n.get("name") == "LabelTop")
    s_acc = gltf["accessors"][gltf["meshes"][shutter["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
    t_acc = gltf["accessors"][gltf["meshes"][top["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
    if not (s_acc["max"][1] > hi[1] - 0.001 and t_acc["min"][1] < lo[1] + 0.001):
        print("  FAIL: the shutter is not at +Y or the index label not at -Y")
        bad += 1
    print(f"  images {[im.get('name') for im in gltf.get('images', [])]}, glb {os.path.getsize(path) // 1024} KB")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=SRC, help="the models repo's n64dd_disk_mobile_clean.glb")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()
    gltf, blob = read_glb(a.src)
    blob = bytearray(blob)
    half_turn(gltf, blob)
    gltf.setdefault("asset", {})["extras"] = {"source": "RetroXR-models nintendo/n64/64dd-disk, n64dd_disk_mobile_clean.glb, "
                                                        "turned half round about Z into the floppy frame"}
    write_glb(a.out, gltf, bytes(blob))
    print(f"wrote {a.out}")
    return verify(a.out) if a.verify else 0


if __name__ == "__main__":
    sys.exit(main())
