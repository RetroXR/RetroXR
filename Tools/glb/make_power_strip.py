"""Generate a 6-outlet US power strip (NEMA 5-15R, grounded) with a lit rocker
switch. The cord, its strain relief and the plug are added in RetroXR.

    blender --background --python Tools/glb/make_power_strip.py -- [out.glb]

Units are metres. Blender frame: strip runs along X, outlets face +Z, the
cord leaves the +X (switch) end. `CordAnchor` sits on that end face; in
Godot its local -Z points out along the cord.
"""
import math
import sys

import bpy
import bmesh

OUT = "RetroXR/imported-assets/electrical/power_strip.glb"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if argv:
    OUT = argv[0]

L, W, H = 0.290, 0.052, 0.038      # body
R = 0.008                           # body corner bevel
PITCH = 0.036                       # outlet spacing along X
N = 6
FIRST_X = -L / 2 + 0.035            # first outlet centre (far end from the cord)

bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough=0.5, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 0.4
    return m


M_BODY = mat("Mat_body", (0.80, 0.79, 0.74), 0.45)
M_HOLE = mat("Mat_hole", (0.02, 0.02, 0.02), 0.9)
M_SWITCH = mat("Mat_switch", (0.80, 0.06, 0.01), 0.3, emit=(0.8, 0.06, 0.0))
M_RUBBER = mat("Mat_rubber", (0.05, 0.05, 0.05), 0.7)


def box(name, size, loc, m, bevel=0.0, segs=4):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    if bevel:
        bv = o.modifiers.new("bevel", "BEVEL")
        bv.width, bv.segments = bevel, segs
        bpy.ops.object.modifier_apply(modifier="bevel")
    return o


def attach(child, parent):
    """Parent without moving: the body's origin is at H/2, not the floor."""
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def ground_cutter(cx, cz, r=0.0024, flat=0.0022, depth=0.014, segs=16):
    """One prism for the ground hole: arched toward the blades (+X), flat away.
    Two overlapping cutters left a sliver the exact solver kept as a post."""
    outline = [(cx + r * math.cos(a), r * math.sin(a))
               for a in (math.pi / 2 - math.pi * k / segs for k in range(segs + 1))]
    outline += [(cx - flat, -r), (cx - flat, r)]
    me = bpy.data.meshes.new("g")
    n = len(outline)
    verts = [(px, py, cz - depth / 2) for px, py in outline] +             [(px, py, cz + depth / 2) for px, py in outline]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M_HOLE)
    o = bpy.data.objects.new("g", me)
    bpy.context.collection.objects.link(o)
    return o


def cut(target, cutter):
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation, mod.object, mod.solver = "DIFFERENCE", cutter, "EXACT"
    mod.material_mode = "TRANSFER"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cutter)


body = box("PowerStrip", (L, W, H), (0, 0, H / 2), M_BODY, R, 5)
top = H

# Outlets: a shallow face recess, two flat blades (neutral taller), round-topped ground.
for i in range(N):
    x = FIRST_X + i * PITCH
    face = box("f", (0.032, 0.036, 0.004), (x, 0, top), M_HOLE, 0.004, 3)
    face.data.materials[0] = M_BODY  # recess keeps body colour
    cut(body, face)
    fz = top - 0.002                 # recessed face height
    # Blades run along X, 12.7 mm apart across Y; ground toward -X. Seen from above
    # with the ground at the bottom, +Y is on the left: the longer neutral goes there.
    for dy, blade_len in ((+0.00635, 0.0087), (-0.00635, 0.0071)):
        s = box("s", (blade_len, 0.0020, 0.014), (x + 0.003, dy, fz), M_HOLE)
        cut(body, s)
    cut(body, ground_cutter(x - 0.0085, fz))

# Rocker switch at the far end, long side across the strip.
sx = L / 2 - 0.030
bezel = box("SwitchBezel", (0.026, 0.036, 0.004), (sx, 0, top + 0.001), M_HOLE, 0.0015, 2)
cut(bezel, box("sw_hole", (0.0186, 0.0286, 0.02), (sx, 0, top), M_HOLE))
attach(bezel, body)
switch = box("Switch", (0.018, 0.028, 0.008), (sx, 0, top - 0.001), M_SWITCH, 0.0025, 3)
switch.rotation_euler.x = math.radians(8)    # rocks across the strip; ON
attach(switch, body)

# The cord leaves the +X end face, beside the switch; RetroXR builds the cord and plug.
anchor = bpy.data.objects.new("CordAnchor", None)
bpy.context.collection.objects.link(anchor)
anchor.location = (L / 2, 0, H / 2)
anchor.rotation_euler.z = math.radians(-90)  # Blender +Y (= Godot -Z) -> +X
attach(anchor, body)

# Rubber feet.
for fx in (-L / 2 + 0.03, L / 2 - 0.03):
    for fy in (-W / 2 + 0.012, W / 2 - 0.012):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.005, depth=0.002, location=(fx, fy, -0.001))
        f = bpy.context.object
        f.name = "Foot"
        f.data.materials.append(M_RUBBER)
        attach(f, body)

body.data.polygons.foreach_set("use_smooth", [False] * len(body.data.polygons))
bpy.context.view_layer.objects.active = body
bpy.ops.object.shade_auto_smooth(angle=math.radians(35))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
print(f"[power_strip] wrote {OUT}")
