## DcPlugShape — the primitive an AC adapter's DC plug is drawn as when no model
## dresses it (PowerBrick._make_dc_plug): a plug, not a box.
##
## In the game's plug frame: origin on the face that stops against the jack, the
## part that goes IN along +Z, the body behind along -Z. Three kinds, by connector:
##   a barrel plug (every BARREL standard, the SNES's) -- a metal sleeve of the
##       standard's diameter and length with its dark pin hole, a round overmould
##       and a ribbed boot tapering to the cord;
##   an L plug (a row's plug_mm much taller than wide: the DMG-03's, the PSone's,
##       the PSP's) -- the same sleeve out of a head block, the boot turning down
##       under it, the cord leaving downward;
##   a keyed plug (the GameCube's, the Wii's, the DS/3DS's, the GBA SP's EXT.2) --
##       a rectangular tongue instead of a sleeve, a squared body and the boot.
## Sizes are the row's plug_mm (RetroXR-models' plug models' bounds) and the
## standards' barrel sizes (RetroXR-models common/powerkit.py BARREL). The cord's
## exit is a CordExit transform (PlugExit), so an L plug's cord leaves downward.
class_name DcPlugShape
extends RefCounted

## Barrel sleeve: outer diameter, pin hole, length out of the overmould, mm.
const BARRELS := {
	"barrel_3_5x1_35": [3.5, 1.35, 9.0],
	"barrel_5_5x2_1": [5.5, 2.1, 9.5],
	"barrel_5_5x2_5": [5.5, 2.5, 9.5],
	"eiaj_01": [2.35, 0.7, 9.5],
	"eiaj_02": [4.0, 1.7, 9.5],
	"eiaj_03": [4.75, 1.7, 9.5],
	# The SNS-002's own: a fat sleeve with a pin of its own in the hole.
	"snes_dc_plug": [6.9, 4.1, 9.5],
}
## Keyed plugs' tongues: width, height, length out of the body, mm (estimates from the
## connectors' photographs; only the look rests on them).
const TONGUES := {
	"gc_dc_plug": [11.0, 6.0, 7.0],
	"wii_dc_plug": [9.0, 11.0, 7.0],
	"dsi_dc_plug": [5.0, 2.6, 5.0],
	"ext2_plug": [11.0, 3.4, 5.5],
}
const METAL := Color(0.74, 0.72, 0.66)
const HOLE := Color(0.03, 0.03, 0.035)
## Rings round a boot, and how far each stands proud of it, mm.
const RIBS := 4
const RIB_PROUD := 0.35
const SEGMENTS := 20


## The plug for `connector` at `size` (m, the row's plug_mm): {mesh, body (its
## AABB, which the collision box takes), exit (the CordExit transform: origin where
## the cord leaves, -Z the way it goes)}.
static func build(connector: String, size: Vector3, body_color: Color) -> Dictionary:
	var parts := {"body": [], "metal": [], "hole": []}
	var body_box: AABB
	var exit: Transform3D
	var l_plug := size.y > size.x * 1.6 and not TONGUES.has(connector)
	var front := 0.0
	if TONGUES.has(connector):
		var t: Array = TONGUES[connector]
		var tw := minf(float(t[0]) * 0.001, size.x * 0.85)
		var th := minf(float(t[1]) * 0.001, size.y * 0.85)
		front = float(t[2]) * 0.001
		_box(parts["body"], Vector3(tw, th, front), Vector3(0, 0, front * 0.5))
		# Its contacts' slots, dark, on the tongue's face.
		_box(parts["hole"], Vector3(tw * 0.6, th * 0.35, 0.0006), Vector3(0, 0, front + 0.0002))
	else:
		var b: Array = BARRELS.get(connector, BARRELS["barrel_5_5x2_1"])
		var od := float(b[0]) * 0.001
		front = float(b[2]) * 0.001
		_tube(parts["metal"], od * 0.5, od * 0.5, front, 0.0)
		_disc(parts["hole"], float(b[1]) * 0.0005, front + 0.0002)
	var depth := maxf(size.z - front, size.z * 0.4)
	if l_plug:
		# A head as deep as the plug and as tall as it is wide-ish, the boot under it.
		var head := Vector3(size.x, minf(size.x * 1.25, size.y * 0.55), depth)
		_box(parts["body"], head, Vector3(0, 0, -depth * 0.5))
		var boot_len := size.y - head.y
		var boot_top := -head.y * 0.5
		var r := size.x * 0.42
		_tube_y(parts["body"], r, r * 0.62, boot_len, Vector3(0, boot_top - boot_len * 0.5, -depth * 0.5))
		for i in RIBS:
			var y := boot_top - boot_len * (0.25 + 0.6 * float(i) / RIBS)
			var rr := lerpf(r, r * 0.62, (boot_top - y) / boot_len) + RIB_PROUD * 0.001
			_tube_y(parts["body"], rr, rr, 0.0009, Vector3(0, y, -depth * 0.5))
		body_box = AABB(Vector3(-size.x * 0.5, boot_top - boot_len, -depth),
			Vector3(size.x, head.y * 0.5 - (boot_top - boot_len), depth))
		# The cord leaves the boot's end, downward: -Z of the exit is world down.
		exit = Transform3D(Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP),
			Vector3(0, boot_top - boot_len, -depth * 0.5))
	else:
		var w := size.x
		var h := size.y
		var mould := depth * 0.45
		var boot := depth - mould
		if TONGUES.has(connector):
			_box(parts["body"], Vector3(w, h, mould), Vector3(0, 0, -mould * 0.5))
		else:
			_tube(parts["body"], minf(w, h) * 0.5, minf(w, h) * 0.5, mould, -mould)
		var r := minf(w, h) * 0.5 * 0.82
		_tube(parts["body"], r, r * 0.55, boot, -depth)
		for i in RIBS:
			var z := -mould - boot * (0.2 + 0.65 * float(i) / RIBS)
			var rr := lerpf(r, r * 0.55, (-mould - z) / boot) + RIB_PROUD * 0.001
			_tube(parts["body"], rr, rr, 0.0009, z - 0.00045)
		body_box = AABB(Vector3(-w * 0.5, -h * 0.5, -depth), Vector3(w, h, depth))
		exit = Transform3D(Basis.IDENTITY, Vector3(0, 0, -depth))
	return {"mesh": _merge(parts, body_color), "body": body_box, "exit": exit}


## A cylinder along +Z from z0 to z0 + length, radius r0 at z0 and r1 at the far end.
static func _tube(out: Array, r1: float, r0: float, length: float, z0: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r0
	m.height = length
	m.radial_segments = SEGMENTS
	m.rings = 1
	# CylinderMesh stands along +Y, its top at +Y: R_x(+90) lays the top along +Z.
	out.append([m, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, z0 + length * 0.5))])


## A cylinder standing along Y, centred at `at`, top radius `r_top`.
static func _tube_y(out: Array, r_top: float, r_bottom: float, length: float, at: Vector3) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = length
	m.radial_segments = SEGMENTS
	m.rings = 1
	out.append([m, Transform3D(Basis.IDENTITY, at)])


static func _box(out: Array, size: Vector3, at: Vector3) -> void:
	var m := BoxMesh.new()
	m.size = size
	out.append([m, Transform3D(Basis.IDENTITY, at)])


## A flat disc facing +Z at z, radius r: the pin hole's dark mouth.
static func _disc(out: Array, r: float, z: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.0003
	m.radial_segments = SEGMENTS
	m.rings = 1
	out.append([m, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, z))])


## One mesh, a surface per material: the moulding, the metal, the hole.
static func _merge(parts: Dictionary, body_color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var mats := {"body": _mat(body_color, 0.7, 0.0), "metal": _mat(METAL, 0.3, 0.9), "hole": _mat(HOLE, 1.0, 0.0)}
	for key: String in ["body", "metal", "hole"]:
		var list: Array = parts[key]
		if list.is_empty():
			continue
		var st := SurfaceTool.new()
		for item: Array in list:
			var prim := item[0] as PrimitiveMesh
			st.append_from(prim, 0, item[1] as Transform3D)
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[key])
	return mesh


static func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color == HOLE:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
