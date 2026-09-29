"""Turn the debranded Sega 32X from codex-photos into sega32x.glb for RetroXR.

The model is built from a laser scan of a real 32X in the codex-photos repo
(sega-32x/, build_32x.py). Its `sega32x_unbranded_lod1.glb` is already at real
size in metres, facing +Z, centred on its footprint, with y = 0 on the plane it
rests on (the plug hangs below that), and carries no trademark: the front badge
is left off and the scan has no moulded marks. So this only tidies it:

    python Tools/glb/prepare_sega32x.py \
        --in         <codex-photos>/sega-32x/sega32x_asset/sega32x_unbranded_lod1.glb \
        --out        RetroXR/imported-assets/consoles/sega_32x/sega32x.glb \
        --spacer     <codex-photos>/sega-32x/sega32x_asset/sega32x_model2_spacer.glb \
        --spacer-out RetroXR/imported-assets/consoles/sega_32x/sega32x_spacer.glb

  * strips the "_LOD1" suffix from every node, mesh, material and image name,
    names the root Sega32X and the two texture sheets normal / ao (Godot
    extracts them as sega32x_normal.png / sega32x_ao.png);
  * adds two empty markers under the root, both read off the geometry:
      PlugSeat   the bottom edge of the board in the plug, on its mid-plane --
                 the point that goes where a cartridge's bottom edge goes when
                 the unit is put into a console's cartridge slot;
      CartFloor  the dark plate at the bottom of the unit's own slot funnel,
                 centred on the slot -- where a cartridge put into the 32X
                 comes to rest;
  * copies the Genesis Model 2 spacer (codex-photos build_spacer.py) beside it
    as sega32x_spacer.glb, the accessory's own model. Sega packed it with the
    32X because on a Model 2 -- the only Mega Drive RetroXR has -- the plug
    bottoms out with the unit standing ~13 mm clear of the console; the spacer
    clips under the 32X and fills that gap. It shares the 32X's frame (y = 0 on
    the 32X's resting plane, front +Z), so clipped on it sits at identity in the
    32X shell's frame.

Pure JSON surgery on the GLB: the binary chunk is copied through untouched.
"""
import argparse
import json
import struct

import numpy as np


def read_glb(path):
    b = open(path, "rb").read()
    magic, version, _ = struct.unpack("<III", b[:12])
    assert magic == 0x46546C67 and version == 2, "not a glTF 2.0 binary"
    n = struct.unpack("<I", b[12:16])[0]
    gltf = json.loads(b[20:20 + n])
    off = 20 + n
    bn, bt = struct.unpack("<II", b[off:off + 8])
    assert bt == 0x004E4942, "no BIN chunk"
    return gltf, b[off + 8:off + 8 + bn]


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def positions(gltf, binary, node):
    """World-space vertex positions of a mesh node (every primitive)."""
    t = np.array(node.get("translation", [0.0, 0.0, 0.0]))
    assert "rotation" not in node and "scale" not in node, "marker maths assumes translation only"
    out = []
    for prim in gltf["meshes"][node["mesh"]]["primitives"]:
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        view = gltf["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", 12)
        raw = np.frombuffer(binary, np.uint8, count=acc["count"] * stride, offset=start)
        out.append(raw.reshape(-1, stride)[:, :12].copy().view(np.float32).reshape(-1, 3))
    return np.vstack(out) + t


def strip(name):
    return name[:-5] if name.lower().endswith("_lod1") else name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--spacer", required=True)
    ap.add_argument("--spacer-out", required=True)
    a = ap.parse_args()
    gltf, binary = read_glb(a.src)

    for group in ("nodes", "meshes", "materials", "images"):
        for item in gltf.get(group, []):
            if "name" in item:
                item["name"] = strip(item["name"])
    by_name = {n["name"]: n for n in gltf["nodes"]}
    root = next(n for n in gltf["nodes"] if "children" in n)
    root["name"] = "Sega32X"
    for img in gltf.get("images", []):
        img["name"] = img["name"].replace("housing_", "")   # Godot prefixes the GLB name

    # PlugSeat: the board's bottom edge, on its mid-plane
    pcb = positions(gltf, binary, by_name["Plug_PCB"])
    lo, hi = pcb.min(0), pcb.max(0)
    plug_seat = [float((lo[0] + hi[0]) / 2), float(lo[1]), float((lo[2] + hi[2]) / 2)]

    # CartFloor: Slot_Floor is two quads -- the plate under the slot funnel and a
    # cap over the base's plug opening, far below it. The higher one is the floor.
    sf = positions(gltf, binary, by_name["Slot_Floor"])
    top = sf[sf[:, 1] > sf[:, 1].max() - 0.002]
    cart_floor = [float((top[:, 0].min() + top[:, 0].max()) / 2), float(top[:, 1].max()),
                  float((top[:, 2].min() + top[:, 2].max()) / 2)]

    for name, t in (("PlugSeat", plug_seat), ("CartFloor", cart_floor)):
        gltf["nodes"].append({"name": name, "translation": [round(v, 5) for v in t]})
        root["children"].append(len(gltf["nodes"]) - 1)
        print("%-10s at (%.4f, %.4f, %.4f) m" % (name, *t))

    write_glb(a.out, gltf, binary)
    print("wrote", a.out)

    spacer, spacer_bin = read_glb(a.spacer)
    assert [n["name"] for n in spacer["nodes"]] == ["Model2_Spacer"], "unexpected spacer GLB"
    write_glb(a.spacer_out, spacer, spacer_bin)
    print("wrote", a.spacer_out)


if __name__ == "__main__":
    main()
