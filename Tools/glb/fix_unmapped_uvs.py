"""Give UVs to the triangles of a normal-mapped surface that have none.

A triangle whose three UVs coincide has no area in texture space, so no tangent
can be derived for it. Godot falls back to a tangent along +X, and on a face whose
normal is also along X the two are parallel: orthogonalising them leaves nothing,
the normal-mapped normal is garbage, and the face takes ambient light only. On the
N64 cartridge that was a 2.4 mm dark band down both sides of the front shell.

Each such triangle is box-projected along the dominant axis of its own face
normal, at --tile millimetres per UV unit. A vertex shared by faces projected
along different axes is split, so no triangle is stretched between two
projections. Geometry, normals, names, materials and every other primitive are
left as they were; only the affected primitives' vertex and index data grow.

    python Tools/glb/fix_unmapped_uvs.py <in.glb> [--out <out.glb>] [--tile 12]
    python Tools/glb/fix_unmapped_uvs.py <in.glb> --check

--check rewrites nothing and exits 1 when an unmapped triangle is found.
"""

import argparse
import json
import struct
import sys

import numpy as np

COMPONENT = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
UV_EPS = 1e-12
GEO_EPS = 1e-15


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        sys.exit("%s is not a glTF 2.0 binary" % path)
    json_len, _ = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20:20 + json_len])
    bin_at = 20 + json_len
    bin_len, _ = struct.unpack_from("<II", data, bin_at)
    return doc, data[bin_at + 8:bin_at + 8 + bin_len]


def write_glb(path, doc, views):
    blob = bytearray()
    for view, payload in zip(doc["bufferViews"], views):
        while len(blob) % 4:
            blob.append(0)
        view["byteOffset"] = len(blob)
        view["byteLength"] = len(payload)
        view.pop("byteStride", None)
        blob += payload
    while len(blob) % 4:
        blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A))
        f.write(text)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)


def accessor_array(doc, views, index):
    a = doc["accessors"][index]
    width = WIDTH[a["type"]]
    raw = np.frombuffer(views[a["bufferView"]], dtype=COMPONENT[a["componentType"]],
                        count=a["count"] * width, offset=a.get("byteOffset", 0))
    return raw.reshape(a["count"], width).copy() if width > 1 else raw.copy()


def unmapped(positions, uvs, tris):
    p, t = positions[tris].astype(np.float64), uvs[tris].astype(np.float64)
    uv_area = 0.5 * np.abs((t[:, 1, 0] - t[:, 0, 0]) * (t[:, 2, 1] - t[:, 0, 1])
                           - (t[:, 2, 0] - t[:, 0, 0]) * (t[:, 1, 1] - t[:, 0, 1]))
    face = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    return (uv_area < UV_EPS) & (np.linalg.norm(face, axis=1) > GEO_EPS), face


def fix_primitive(doc, views, prim, tile_m):
    attrs = prim["attributes"]
    arrays = {name: accessor_array(doc, views, i) for name, i in attrs.items()}
    tris = accessor_array(doc, views, prim["indices"]).astype(np.int64).reshape(-1, 3)
    bad, face = unmapped(arrays["POSITION"], arrays["TEXCOORD_0"], tris)
    if not bad.any():
        return 0
    # The two axes a face is flattened onto, by the axis its normal runs along.
    planes = {0: (1, 2), 1: (0, 2), 2: (0, 1)}
    axes = np.abs(face).argmax(axis=1)
    count = len(arrays["POSITION"])
    # A vertex keeps its slot for the first projection that claims it, provided no
    # mapped triangle uses it; every other (vertex, axis) pair gets a copy.
    taken = {int(v): None for v in np.unique(tris[~bad])}
    remap = {}
    extra = []
    uvs = arrays["TEXCOORD_0"].astype(np.float32)
    new_uvs = []
    for t in np.nonzero(bad)[0]:
        axis = int(axes[t])
        for corner in range(3):
            v = int(tris[t, corner])
            key = (v, axis)
            if key not in remap:
                u, w = planes[axis]
                uv = arrays["POSITION"][v][[u, w]].astype(np.float64) / tile_m
                if v not in taken:
                    taken[v] = axis
                    remap[key] = v
                    uvs[v] = uv
                else:
                    remap[key] = count + len(extra)
                    extra.append(v)
                    new_uvs.append(uv)
            tris[t, corner] = remap[key]
    if extra:
        for name in arrays:
            arrays[name] = np.concatenate([arrays[name], arrays[name][extra]])
        uvs = np.concatenate([uvs, np.asarray(new_uvs, dtype=np.float32)])
    arrays["TEXCOORD_0"] = uvs
    for name, index in attrs.items():
        a = doc["accessors"][index]
        out = arrays[name].astype(COMPONENT[a["componentType"]])
        a["count"] = len(out)
        a.pop("byteOffset", None)
        if name == "POSITION":
            a["min"], a["max"] = out.min(axis=0).tolist(), out.max(axis=0).tolist()
        doc["bufferViews"].append({"buffer": 0, "target": 34962})
        views.append(out.tobytes())
        a["bufferView"] = len(views) - 1
    ia = doc["accessors"][prim["indices"]]
    ia["componentType"] = 5125 if tris.max() > 65535 else ia["componentType"]
    ia["count"] = tris.size
    ia.pop("byteOffset", None)
    doc["bufferViews"].append({"buffer": 0, "target": 34963})
    views.append(tris.reshape(-1).astype(COMPONENT[ia["componentType"]]).tobytes())
    ia["bufferView"] = len(views) - 1
    return int(bad.sum())


def drop_unused_views(doc, views):
    used = sorted({a["bufferView"] for a in doc["accessors"] if "bufferView" in a}
                  | {i["bufferView"] for i in doc.get("images", []) if "bufferView" in i})
    index = {old: new for new, old in enumerate(used)}
    for a in doc["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = index[a["bufferView"]]
    for i in doc.get("images", []):
        if "bufferView" in i:
            i["bufferView"] = index[i["bufferView"]]
    doc["bufferViews"] = [doc["bufferViews"][old] for old in used]
    return [views[old] for old in used]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("glb")
    parser.add_argument("--out", help="default: rewrite the input")
    parser.add_argument("--tile", type=float, default=12.0, help="millimetres per UV unit")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    doc, blob = read_glb(args.glb)
    views = [bytes(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
             for v in doc["bufferViews"]]
    shared = set()
    total = 0
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            material = doc["materials"][prim["material"]] if "material" in prim else {}
            if "normalTexture" not in material or "TEXCOORD_0" not in prim["attributes"]:
                continue
            key = (prim["indices"], tuple(sorted(prim["attributes"].items())))
            if key in shared:
                continue
            shared.add(key)
            if args.check:
                pos = accessor_array(doc, views, prim["attributes"]["POSITION"])
                uv = accessor_array(doc, views, prim["attributes"]["TEXCOORD_0"])
                tris = accessor_array(doc, views, prim["indices"]).astype(np.int64).reshape(-1, 3)
                found = int(unmapped(pos, uv, tris)[0].sum())
            else:
                found = fix_primitive(doc, views, prim, args.tile / 1000.0)
            if found:
                print("%-28s %5d unmapped triangles%s" % (mesh["name"], found, "" if args.check else " given UVs"))
            total += found
    if args.check:
        print("%d unmapped triangles on normal-mapped surfaces" % total)
        sys.exit(1 if total else 0)
    if total:
        views = drop_unused_views(doc, views)
        write_glb(args.out or args.glb, doc, views)
    print("%d triangles fixed in %s" % (total, args.out or args.glb))


if __name__ == "__main__":
    main()
