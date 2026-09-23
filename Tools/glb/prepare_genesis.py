"""Turn Zerescas's Sega Genesis Model 2 (Sketchfab, CC-BY-4.0) into genesis_console.glb.

Run inside Blender, on a copy of the download whose textures/ folder has already
been through prepare_genesis_textures.py (which paints out the marks):

    python Tools/glb/prepare_genesis_textures.py <download>/textures <work>/textures
    cp <download>/scene.gltf <download>/scene.bin <work>/
    "/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
        --python Tools/glb/prepare_genesis.py -- --in <work>/scene.gltf --out <work>/raw.glb
    "/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
        --python Tools/glb/decimate_glb.py -- --in <work>/raw.glb \
        --out RetroXR/imported-assets/consoles/genesis/genesis_console.glb --target 30000

What this does to the scene:
  * drops the three Sketchfab studio lights, and the two unused UV sets;
  * bakes the Sketchfab / FBX / RootNode transforms into the vertices, so every
    part sits at the root with an identity-scaled transform;
  * splits "Power Control Panel" into its strip and the two caps it carries
    (ButtonPower on the player's left, ButtonReset on the right) so each can be
    pressed on its own;
  * renames the rest to what they are (the two "Cap" meshes are the cartridge
    slot's dust flaps, not buttons);
  * scales to real size, 220 mm wide (the source is 491.5 units; its depth then
    measures 210 mm, which is the hardware), front on -Y in Blender so the GLB
    faces +Z, centred on its footprint and resting on z = 0;
  * puts each flap's origin on its hinge — the flaps meet mid-slot and each
    swings down about its OUTER long edge — and each button's origin at its
    centre.
"""
import bpy
import bmesh
import sys
from mathutils import Matrix, Vector


def argv():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(args, flag, default=None):
    return args[args.index(flag) + 1] if flag in args else default


WIDTH_M = 0.220

RENAME = {
    "Case_Top Case_0": "ShellTop",
    "Case_Bottom Case_0": "ShellBottom",
    "Cartridge Reader Case_Power & Cartridge_0": "CartSlot",
    "Cap 1_Power & Cartridge_0": "SlotFlapRear",
    "Cap 2_Power & Cartridge_0": "SlotFlapFront",
    "Controller Ports_Ports & Inside_0": "PortsInside",
    "Model Label_Labels_0": "Labels",
    "Power Control Panel_Power & Cartridge_0": "ControlPanel",
}


def world_bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = -lo
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def set_origin(o, point):
    o.data.transform(Matrix.Translation(-point))
    o.matrix_world = Matrix.Translation(point) @ o.matrix_world


def main():
    args = argv()
    src, dst = opt(args, "--in"), opt(args, "--out")
    if not src or not dst:
        raise SystemExit("need --in and --out")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # Bake every parent transform into the mesh, then drop the empties and lights.
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    for o in meshes:
        o.name = RENAME.get(o.name, o.name)
        o.data.name = o.name
        # Every mesh carries three UV sets and only the first is textured. Godot
        # imports the other two as custom arrays in a format it then refuses
        # ("Invalid array format for surface"), once per mesh.
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])

    # Real-world size, centred on the footprint, resting on z = 0.
    lo, hi = world_bounds(meshes)
    s = WIDTH_M / (hi.x - lo.x)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    fit = Matrix.Scale(s, 4) @ Matrix.Translation(-centre)
    for o in meshes:
        o.data.transform(fit)
    lo, hi = world_bounds(meshes)
    print("[genesis] footprint %.4f x %.4f x %.4f m" % tuple(hi - lo))

    # Split the control strip into strip + two caps.
    panel = bpy.data.objects["ControlPanel"]
    bm = bmesh.new()
    bm.from_mesh(panel.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.to_mesh(panel.data)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    panel.select_set(True)
    bpy.context.view_layer.objects.active = panel
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.data.objects if o.name.startswith("ControlPanel")]
    if len(parts) != 3:
        raise SystemExit("expected ControlPanel to split into 3 parts, got %d" % len(parts))
    parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
    # Free the name first: separate() leaves it on whichever part it pleases.
    for i, o in enumerate(parts):
        o.name = o.data.name = "_part%d" % i
    strip, caps = parts[0], parts[1:]
    strip.name = strip.data.name = "ControlPanel"
    caps.sort(key=lambda o: world_bounds([o])[0].x)
    # Player's left is -X (the console faces -Y here, +Z once exported).
    for o, name in zip(caps, ["ButtonPower", "ButtonReset"]):
        o.name = o.data.name = name
        lo_c, hi_c = world_bounds([o])
        set_origin(o, (lo_c + hi_c) / 2)

    # Flaps hinge on their OUTER long edge, at the top face.
    for name, outer in [("SlotFlapFront", "min"), ("SlotFlapRear", "max")]:
        o = bpy.data.objects[name]
        lo_f, hi_f = world_bounds([o])
        y = lo_f.y if outer == "min" else hi_f.y
        set_origin(o, Vector(((lo_f.x + hi_f.x) / 2, y, hi_f.z)))

    for o in bpy.data.objects:
        lo_o, hi_o = world_bounds([o])
        print("[genesis] %-14s origin (%.4f %.4f %.4f) lo (%.4f %.4f %.4f) hi (%.4f %.4f %.4f) tris %d" % (
            o.name, *o.location, *lo_o, *hi_o, sum(len(p.vertices) - 2 for p in o.data.polygons)))

    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_yup=True,
                              export_lights=False, export_cameras=False)


main()
