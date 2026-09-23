"""Prepare the Sketchfab "Sega Dreamcast" (Zerescas, CC-BY-4.0) as RetroXR's console GLB.

    python Tools/glb/scrub_dreamcast_textures.py --in ~/Downloads/sega_dreamcast --out <tex>
    blender --background --python Tools/glb/prepare_dreamcast.py -- \
        --in ~/Downloads/sega_dreamcast --textures <tex> \
        --out RetroXR/imported-assets/consoles/dreamcast
    python Tools/glb/fix_unmapped_uvs.py RetroXR/imported-assets/consoles/dreamcast/dreamcast_console.glb --check

The download is a glTF scene: the console, a disc, three area lights and a camera, under
an FBX-style hierarchy whose nodes carry scales of 100, 0.84 and 0.08. What this does:

  * FLATTENS it. Every kept mesh has its world transform baked in, at 0.071 m per source
    unit, which lands the console at 190.1 x 80.2 x 195.2 mm against a real HKT-3000's
    190 x 78 x 195.8. Centred on its footprint, feet on y = 0. The disc, lights and camera
    are dropped; RetroDisc builds the disc from MediaDimensions at runtime.
  * MAKES THE SHELL SOLID. The artist gave the case material full KHR transmission with
    alpha blending and a 0.18 base-colour factor, so it renders as smoked glass in Godot.
    Transmission and alpha are unlinked and the factor goes back to the texture's own grey.
  * DELETES THE LID LOGO. The Dreamcast swirl and wordmark are a raised sticker -- three
    loose parts sitting on the lid -- and the lid surface beneath them is intact.
    SEGA and "Compatible with Windows CE" are printed into the case sheet instead, and
    scrub_dreamcast_textures.py erases those.
  * SEATS THE CONTROLLER PANEL. The source panel is a 122.4 x 31.5 mm plate laid ON the
    front face over a 109.7 x 18.9 mm opening, with its four socket wells 1.3 mm low and
    0.17 mm left of it: the bottom of every well ran into the opening's lower lip, and the
    plate hung 4 mm down over the base's curved underside. The wells are moved into the
    middle of the opening, the plate stays centred on the console, and the blank strip
    under the sockets is drawn up so the plate's lower edge lands on the flat face.
  * SPLITS the single Buttons mesh into PowerButton (left) and OpenButton (right), each
    re-origined at the base of its cap, and joins the lid with its hinge arms into Lid,
    origined ON the hinge axis (the artist's Door Axis node) so 0 is shut and a rotation
    about local -X lifts the front.
  * MARKS THE CONNECTORS. ControllerPort1..4 sit at each socket mouth on the plate face,
    AvOut at the AV OUT tunnel mouth on the back face. Each marker's +Z points OUT of the
    console. The AV OUT connector was already centred in its tunnel (0.005 mm) and is
    only checked, not moved.

Node names carry no dots: Godot strips them on import.
"""
import bpy
import bmesh
import math
import os
import sys

import mathutils

SCALE = 0.071
MM = 0.001
TEXTURE_SIZE = 2048

KEEP = {
    "Case_Case_0": "Case",
    "Bottom_Case_0": "Bottom",
    "Buttons_Case_0": "Buttons",
    "Laser_Case_0": "DiscLaser",
    "Disc Reader_Case_0": "DiscReader",
    "Disc Reader Top_Case_0": "DiscReaderTop",
    "Cylinder.003_Case_0": "Spindle",
    "Cylinder.004_Case_0": "SpindlePlate",
    "Triange on front_Case_0": "PowerLED",
    "Gamepads Ports Panel_Door and ports_0": "ControllerPorts",
    "Back ports_Door and ports_0": "BackPorts",
    "Door_Door and ports_0": "Lid",
    "Cube.005_Door and ports_0": "LidHinge",
}


def argv():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {}
    for i in range(0, len(a) - 1, 2):
        opts[a[i].lstrip("-")] = os.path.expanduser(a[i + 1])
    return opts


def objs():
    return bpy.context.scene.objects


def bounds(verts):
    vs = list(verts)
    return (mathutils.Vector([min(v[i] for v in vs) for i in range(3)]),
            mathutils.Vector([max(v[i] for v in vs) for i in range(3)]))


def loose_parts(bm):
    seen = set()
    for v in bm.verts:
        if v in seen:
            continue
        stack, comp = [v], []
        seen.add(v)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        yield comp


def set_origin(o, p):
    o.data.transform(mathutils.Matrix.Translation(-p))
    o.location = p


def well_walls(panel):
    """The socket wells' walls where they cross the case's front plane.

    Not the whole well: its bevelled lip lies ON the plate face, proud of the case, and
    can overhang the opening harmlessly. What must fit inside the opening is the wall
    that passes through it (y -97.2..-96.6 mm, against a front face at -96.9)."""
    return [v.co for v in panel.data.vertices
            if -97.2 * MM < v.co.y < -96.6 * MM and abs(v.co.x) < 53 * MM and 17 * MM < v.co.z < 41 * MM]


def import_and_flatten(src):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src, "scene.gltf"))
    world = {o.name: o.matrix_world.copy() for o in objs()}
    hinge = mathutils.Matrix.Scale(SCALE, 4) @ world["Door Axis"]
    for o in list(objs()):
        if o.name not in KEEP:
            bpy.data.objects.remove(o)
    for o in list(objs()):
        o.parent = None
        o.data = o.data.copy()
        o.data.transform(mathutils.Matrix.Scale(SCALE, 4) @ world[o.name])
        o.matrix_world = mathutils.Matrix.Identity(4)
        o.name = o.data.name = KEEP[o.name]
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    mn, mx = bounds(v.co for o in objs() for v in o.data.vertices)
    shift = mathutils.Vector(((mn.x + mx.x) / -2, (mn.y + mx.y) / -2, -mn.z))
    for o in objs():
        o.data.transform(mathutils.Matrix.Translation(shift))
    print("size mm", [round((mx[i] - mn[i]) * 1000, 1) for i in range(3)])
    # The source hinge node's local Z runs along world X: the lid swings about X.
    return hinge.translation + shift


def principled(mat):
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def fix_materials(textures):
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        nt = mat.node_tree
        bsdf = principled(mat)
        for name, value in (("Transmission Weight", 0.0), ("Alpha", 1.0)):
            for l in list(bsdf.inputs[name].links):
                nt.links.remove(l)
            bsdf.inputs[name].default_value = value
        mat.surface_render_method = "DITHERED"
        link = bsdf.inputs["Base Color"].links[0] if bsdf.inputs["Base Color"].links else None
        if link and link.from_node.type != "TEX_IMAGE":
            tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and "baseColor" in n.image.name), None)
            if tex:
                nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # The scrubbed case sheets. Loaded as NEW images: the importer packs the originals,
    # so re-pointing their filepath would silently keep the marks.
    for stem in ("Case_baseColor", "Case_normal"):
        clean = bpy.data.images.load(os.path.join(textures, stem + ".png"))
        clean.colorspace_settings.name = "sRGB" if "baseColor" in stem else "Non-Color"
        swapped = 0
        for mat in bpy.data.materials:
            for n in (mat.node_tree.nodes if mat.node_tree else []):
                if n.type == "TEX_IMAGE" and n.image and n.image.name.startswith(stem) and n.image != clean:
                    n.image = clean
                    swapped += 1
        assert swapped, "no %s texture to replace" % stem
    # The lens gets a material of its own so the model can light it. It shared the case
    # sheet, reading a transparent hole in it.
    led = bpy.data.materials.new("PowerLED")
    led.use_nodes = True
    b = principled(led)
    b.inputs["Base Color"].default_value = (0.32, 0.13, 0.03, 1)
    b.inputs["Roughness"].default_value = 0.25
    o = bpy.data.objects["PowerLED"]
    o.data.materials.clear()
    o.data.materials.append(led)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
    for img in bpy.data.images:
        if img.size[0] > TEXTURE_SIZE:
            img.scale(TEXTURE_SIZE, TEXTURE_SIZE)
        img.pack()


def delete_lid_logo():
    lid = bpy.data.objects["Lid"]
    bm = bmesh.new(); bm.from_mesh(lid.data)
    kill = []
    for comp in loose_parts(bm):
        mn, mx = bounds(v.co for v in comp)
        if mn.x > -17 * MM and mx.x < 17 * MM and mn.y > 18 * MM and mx.y < 41.5 * MM:
            kill += comp
    assert kill, "lid logo sticker not found"
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(lid.data); bm.free()


def join_lid(pivot):
    lid, hinge = bpy.data.objects["Lid"], bpy.data.objects["LidHinge"]
    with bpy.context.temp_override(active_object=lid, selected_editable_objects=[lid, hinge]):
        bpy.ops.object.join()
    set_origin(lid, pivot)


def seat_controller_panel():
    case = bpy.data.objects["Case"]
    panel = bpy.data.objects["ControllerPorts"]
    bm = bmesh.new(); bm.from_mesh(case.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    rim = [v.co.copy() for e in bm.edges if e.is_boundary for v in e.verts
           if v.co.y < -96.0 * MM and abs(v.co.x) < 57 * MM and 15 * MM < v.co.z < 42 * MM]
    bm.free()
    omn, omx = bounds(rim)
    wmn, wmx = bounds(well_walls(panel))
    d = mathutils.Vector((((omn.x + omx.x) - (wmn.x + wmx.x)) / 2, 0,
                          ((omn.z + omx.z) - (wmn.z + wmx.z)) / 2))
    bm = bmesh.new(); bm.from_mesh(panel.data)
    for comp in loose_parts(bm):
        mn, mx = bounds(v.co for v in comp)
        plate = mx.x - mn.x > 100 * MM or abs(mn.x + mx.x) / 2 > 60 * MM
        for v in comp:
            v.co += mathutils.Vector((0 if plate else d.x, 0, d.z))
    bm.to_mesh(panel.data); bm.free()
    # The case front is vertical from z 17.5 mm up and curves under below it.
    flat_bottom = 18.2 * MM
    z_lo = min(v.co.z for v in panel.data.vertices)
    z_keep = wmn.z + d.z - 1.5 * MM
    for v in panel.data.vertices:
        if v.co.z < z_keep:
            t = (v.co.z - z_lo) / (z_keep - z_lo)
            v.co.z = flat_bottom + t * (z_keep - flat_bottom)
    print("controller sockets moved mm", [round(c * 1000, 3) for c in d])
    return omn, omx


def split_buttons():
    btn = bpy.data.objects["Buttons"]
    open_btn = btn.copy(); open_btn.data = btn.data.copy()
    bpy.context.scene.collection.objects.link(open_btn)
    for o, right in ((btn, False), (open_btn, True)):
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if (v.co.x > 0) != right], context="VERTS")
        bm.to_mesh(o.data); bm.free()
        o.name = o.data.name = "OpenButton" if right else "PowerButton"
        mn, mx = bounds(v.co for v in o.data.vertices)
        set_origin(o, mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z)))


def origin_turntable():
    """Spindle and platter origined on their own axis, so the model can spin them in place."""
    for name in ("Spindle", "SpindlePlate"):
        o = bpy.data.objects[name]
        mn, mx = bounds(v.co for v in o.data.vertices)
        set_origin(o, mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z)))


def add_markers():
    """Blender local -Y is Godot local +Z after export, so an identity empty on the front
    face already points out of it, and the rear one is turned half about Z."""
    panel = bpy.data.objects["ControllerPorts"]
    case = bpy.data.objects["Case"]
    plate_y = min(v.co.y for v in panel.data.vertices)
    mouths = [v.co for v in panel.data.vertices if -94.6 * MM < v.co.y < -94.4 * MM]
    xs = sorted(c.x for c in mouths)
    step = (xs[-1] - xs[0]) / 4
    for i in range(4):
        pts = [c for c in mouths if xs[0] + i * step <= c.x <= xs[0] + (i + 1) * step]
        mn, mx = bounds(pts)
        e = bpy.data.objects.new("ControllerPort%d" % (i + 1), None)
        bpy.context.scene.collection.objects.link(e)
        e.location = ((mn.x + mx.x) / 2, plate_y, (mn.z + mx.z) / 2)
    back = bpy.data.objects["BackPorts"]
    win = lambda c: -44 * MM < c.x < -22 * MM and 12 * MM < c.z < 20 * MM
    amn, amx = bounds(v.co for v in back.data.vertices if win(v.co) and 90 * MM < v.co.y < 97.5 * MM)
    e = bpy.data.objects.new("AvOut", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = ((amn.x + amx.x) / 2, max(v.co.y for v in case.data.vertices if win(v.co)), (amn.z + amx.z) / 2)
    e.rotation_euler = (0, 0, math.pi)


def check(opening):
    bpy.context.view_layer.update()
    omn, omx = opening
    ports = [bpy.data.objects["ControllerPort%d" % i].matrix_world.translation for i in range(1, 5)]
    pitch = [ports[i + 1].x - ports[i].x for i in range(3)]
    assert max(pitch) - min(pitch) < 1e-5, "uneven port pitch %s" % pitch
    assert max(p.z for p in ports) - min(p.z for p in ports) < 1e-6, "ports not level"
    assert abs(ports[0].x + ports[3].x) < 2e-5, "ports not centred"
    wmn, wmx = bounds(well_walls(bpy.data.objects["ControllerPorts"]))
    margins = [wmn.x - omn.x, omx.x - wmx.x, wmn.z - omn.z, omx.z - wmx.z]
    assert min(margins) > 0.5 * MM and abs(margins[2] - margins[3]) < 2e-5, "wells vs opening %s" % margins
    case, back = bpy.data.objects["Case"], bpy.data.objects["BackPorts"]
    win = lambda c: -47 * MM < c.x < -19 * MM and 10 * MM < c.z < 23 * MM
    tmn, tmx = bounds(v.co for v in case.data.vertices if win(v.co) and 85 * MM < v.co.y < 90 * MM)
    cmn, cmx = bounds(v.co for v in back.data.vertices if win(v.co) and 85 * MM < v.co.y < 100 * MM)
    off = ((cmn + cmx) - (tmn + tmx)) / 2
    assert abs(off.x) < 0.05 * MM and abs(off.z) < 0.05 * MM, "AV OUT off its tunnel %s" % off
    print("ports mm", [[round(c * 1000, 2) for c in p] for p in ports], "pitch", round(pitch[0] * 1000, 3))
    print("port wells inside opening, margins mm", [round(m * 1000, 2) for m in margins])
    print("AV OUT centred in tunnel, offset mm", round(off.x * 1000, 3), round(off.z * 1000, 3))


def main():
    a = argv()
    pivot = import_and_flatten(a["in"])
    fix_materials(a["textures"])
    delete_lid_logo()
    join_lid(pivot)
    opening = seat_controller_panel()
    split_buttons()
    origin_turntable()
    add_markers()
    root = bpy.data.objects.new("Dreamcast", None)
    bpy.context.scene.collection.objects.link(root)
    for o in list(objs()):
        if o is not root and o.parent is None:
            o.parent = root
    check(opening)
    os.makedirs(a["out"], exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(a["out"], "dreamcast_console.glb"),
                              export_format="GLB", export_yup=True, export_cameras=False,
                              export_lights=False, export_apply=True)


main()
