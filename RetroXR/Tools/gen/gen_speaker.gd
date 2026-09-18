## Bakes the surround loudspeakers — a satellite and a subwoofer — to
## Scenes/Objects/appliances/speaker_satellite.res and speaker_sub.res.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_speaker.gd
##
## FRAME. Both are authored with the origin at the BASE CENTRE and the baffle
## facing +Z, so a .tscn stands one on a shelf by putting the node on the surface
## rather than solving an offset. The cone marker a source walks its voice onto is
## a Marker3D in the .tscn, not baked.
##
## The cabinet TAPERS in X — the baffle is narrower than the back — so the side
## panels are non-parallel. That is what stops the silhouette reading as a box.
##
## No two faces share a plane and a facing. The grille rim stands 3 mm proud of
## the baffle and the driver is sunk behind it; a rim flush with the baffle
## interleaves its triangles with the baffle's and draws as a flickering pinwheel.
## The baffle is built as a rect-to-circle annulus so the driver has a real hole to
## sit in rather than being hidden behind a solid front.
##
## The port bore is dark by MATERIAL, not by depth: these rooms light with a flat
## ambient and no radiance map, so a recess given the cabinet's own material
## renders exactly as bright as the panel around it.
##
## WINDING. Godot's front face is CLOCKWISE, so a front normal is (c-a) x (b-a),
## the negative of the usual right-hand cross product. _loft and _cap_ring are
## taken verbatim from gen_wall_outlet.gd and pair with COUNTER-clockwise rings, so
## every ring here is reversed into that order before it is returned. Traced
## clockwise instead, the whole cabinet bakes inside out: backface culling then
## shows the far interior walls and the background through any hole, which looks
## like missing geometry rather than a winding error.
##
## Every ring carries RING_SEG vertices, so a rounded rect can be lofted straight
## onto a circle.
##
## No lettering is baked — that would put a font dependency in the bake. The
## SURROUND and LFE IN legends are Label3Ds in the .tscn.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")

const SAT_PATH := "res://Scenes/Objects/appliances/speaker_satellite.res"
const SUB_PATH := "res://Scenes/Objects/appliances/speaker_sub.res"

## Vertices per closed ring. Four corners of eight, so a rounded rect and a circle
## can be lofted onto each other.
const RING_SEG := 32

# ── Satellite: 95 x 165 x 110 mm over a 12 mm plinth ──────────────────────────
const SAT_BACK_HX := 0.0475
const SAT_FRONT_HX := 0.0430
const SAT_HZ := 0.0550
const SAT_PLINTH_H := 0.0120
const SAT_TOP := 0.1650
const SAT_CORNER := 0.0060

## Driver and tweeter centres up the baffle. The driver sits low so the tweeter
## lands near ear height on a shelf.
const SAT_DRIVER_CY := 0.0620
const SAT_DRIVER_R := 0.0375
const SAT_CONE_R := 0.0300
const SAT_CAP_R := 0.0100
const SAT_TWEET_CY := 0.1280
const SAT_TWEET_R := 0.0100
const SAT_TWEET_FLANGE := 0.0145

## The proud frame around the baffle.
const SAT_RIM_PROUD := 0.0030
const SAT_RIM_INSET := 0.0050

## Rear bass port.
const SAT_PORT_R := 0.0120
const SAT_PORT_CY := 0.1380
const SAT_PORT_DEPTH := 0.0140

# ── Subwoofer: 260 x 300 x 280 mm on 14 mm feet ───────────────────────────────
const SUB_BACK_HX := 0.1300
const SUB_FRONT_HX := 0.1230
const SUB_HZ := 0.1400
const SUB_FOOT_H := 0.0140
const SUB_FOOT_R := 0.0140
const SUB_FOOT_INSET := 0.0280
const SUB_TOP := 0.3000
const SUB_CORNER := 0.0100

const SUB_DRIVER_CY := 0.1900
const SUB_DRIVER_R := 0.0825
const SUB_CONE_R := 0.0660
const SUB_CAP_R := 0.0230
const SUB_PORT_R := 0.0350
const SUB_PORT_CY := 0.0750
const SUB_PORT_DEPTH := 0.0300
const SUB_RIM_PROUD := 0.0040
const SUB_RIM_INSET := 0.0080


func _init() -> void:
	var err := _bake_satellite()
	if err == OK:
		err = _bake_sub()
	quit(err)


func _bake_satellite() -> int:
	var shell := SurfaceTool.new()
	var cone := SurfaceTool.new()
	var dark := SurfaceTool.new()
	for st: SurfaceTool in [shell, cone, dark]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base := SAT_PLINTH_H
	var cy := (base + SAT_TOP) * 0.5
	var hy := (SAT_TOP - base) * 0.5
	var front := SAT_HZ

	_plinth(shell, SAT_BACK_HX, SAT_HZ, SAT_PLINTH_H, SAT_CORNER)
	_box_tapered(shell, SAT_BACK_HX, SAT_FRONT_HX, cy, hy, SAT_HZ, SAT_CORNER)

	# Baffle with the driver's hole in it, then the proud rim around the outside.
	_baffle(shell, SAT_FRONT_HX, cy, hy, SAT_CORNER, front,
		SAT_DRIVER_CY, SAT_DRIVER_R)
	_rim(shell, SAT_FRONT_HX, cy, hy, SAT_CORNER, front, SAT_RIM_INSET, SAT_RIM_PROUD)

	_driver(cone, dark, SAT_DRIVER_CY, front, SAT_DRIVER_R, SAT_CONE_R, SAT_CAP_R, 0.0165)
	_tweeter(cone, shell, SAT_TWEET_CY, front, SAT_TWEET_R, SAT_TWEET_FLANGE)
	_port(dark, SAT_PORT_CY, -SAT_HZ, SAT_PORT_R, SAT_PORT_DEPTH)

	return _commit(SAT_PATH, shell, cone, dark)


func _bake_sub() -> int:
	var shell := SurfaceTool.new()
	var cone := SurfaceTool.new()
	var dark := SurfaceTool.new()
	for st: SurfaceTool in [shell, cone, dark]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base := SUB_FOOT_H
	var cy := (base + SUB_TOP) * 0.5
	var hy := (SUB_TOP - base) * 0.5
	var front := SUB_HZ

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_foot(shell, Vector3((SUB_BACK_HX - SUB_FOOT_INSET) * sx, 0.0,
				(SUB_HZ - SUB_FOOT_INSET) * sz), SUB_FOOT_R, SUB_FOOT_H)
	_box_tapered(shell, SUB_BACK_HX, SUB_FRONT_HX, cy, hy, SUB_HZ, SUB_CORNER)

	_baffle(shell, SUB_FRONT_HX, cy, hy, SUB_CORNER, front, SUB_DRIVER_CY, SUB_DRIVER_R)
	_rim(shell, SUB_FRONT_HX, cy, hy, SUB_CORNER, front, SUB_RIM_INSET, SUB_RIM_PROUD)

	_driver(cone, dark, SUB_DRIVER_CY, front, SUB_DRIVER_R, SUB_CONE_R, SUB_CAP_R, 0.0340)
	# Front-firing port, which is what a sealed-back sub in a room corner wants.
	_port(dark, SUB_PORT_CY, front, SUB_PORT_R, SUB_PORT_DEPTH)

	return _commit(SUB_PATH, shell, cone, dark)


func _commit(path: String, shell: SurfaceTool, cone: SurfaceTool, dark: SurfaceTool) -> int:
	shell.generate_normals()
	cone.generate_normals()
	dark.generate_normals()

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shell.commit_to_arrays())
	mesh.surface_set_material(0, PlugMats.matte(Color(0.145, 0.145, 0.158), 0.74))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cone.commit_to_arrays())
	mesh.surface_set_material(1, PlugMats.matte(Color(0.052, 0.052, 0.058), 0.66))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, dark.commit_to_arrays())
	mesh.surface_set_material(2, PlugMats.matte(Color(0.022, 0.022, 0.026), 0.92))

	# Two oracles, because the two surfaces are different shapes. Surface 0 is the
	# closed solid, judged by whether its extreme vertex on each axis faces that
	# way. Surface 1 is an open funnel, which reads -1 on an axis it is edge-on to
	# whichever way it is wound — so it is judged by the one thing that IS true of
	# a driver: no part of it may face backwards. Refuse to save either way round
	# rather than leave it to a render.
	var verdict := _check_outward(mesh, 0)
	var driver := _check_forward(mesh, 1)
	var tris := 0
	for s in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	if verdict != "outward":
		print("[gen] %s NOT SAVED: shell %s" % [path, verdict])
		return FAILED
	if driver.begins_with("<--"):
		print("[gen] %s NOT SAVED: driver %s" % [path, driver])
		return FAILED
	var err := ResourceSaver.save(mesh, path)
	print("[gen] %s err=%d size=%s tris=%d shell=%s driver=%s"
		% [path, err, mesh.get_aabb().size, tris, verdict, driver])
	return err


## Whether a surface's STORED normals point away from the solid.
##
## The stored ones, because they are the only thing that differs: Godot's front
## face is the clockwise one, so generate_normals() returns the negative of the
## textbook (b-a) x (c-a), and an oracle that recomputes from vertex order reports
## an inside-out mesh as outward. Signed volume, the AABB and a manifold edge count
## cannot tell the two apart either. Shape of the check is gen_wiimote.gd's.
func _check_outward(mesh: ArrayMesh, surface: int) -> String:
	var arrays := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var axes := {"+X": Vector3.RIGHT, "-X": Vector3.LEFT, "+Y": Vector3.UP,
		"-Y": Vector3.DOWN, "+Z": Vector3.BACK, "-Z": Vector3.FORWARD}
	var bad := PackedStringArray()
	for label: String in axes:
		var axis: Vector3 = axes[label]
		var best := 0
		for i in v.size():
			if v[i].dot(axis) > v[best].dot(axis):
				best = i
		if n[best].dot(axis) < -0.0001:
			bad.append(label)
	return "outward" if bad.is_empty() else "<-- INSIDE OUT on %s" % ", ".join(bad)


## The driver surface is an open funnel, so _check_outward cannot judge it — a
## funnel reads -1 on an axis it is edge-on to whichever way it is wound, which is
## why surface 1 went unchecked and shipped inside out.
##
## What IS true of it: a cone, its surround and its dust cap are only ever seen from
## in FRONT of the baffle, so not one face of them may point backwards. An
## inside-out cone fails on nearly every face at once.
##
## The tolerance is for the tweeter dome, whose equator faces are edge-on at z = 0.
func _check_forward(mesh: ArrayMesh, surface: int) -> String:
	var arrays := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var worst := 0.0
	var backward := 0
	for i in v.size():
		if n[i].z < -0.001:
			backward += 1
			worst = minf(worst, n[i].z)
	if backward == 0:
		return "facing out of the baffle"
	return "<-- %d/%d vertices FACE BACKWARDS (worst z = %.3f)" % [backward,
		v.size(), worst]


# ── parts ─────────────────────────────────────────────────────────────────────

## A slab from y = 0 to y = h, inset nowhere: the cabinet sits on it.
func _plinth(st: SurfaceTool, hx: float, hz: float, h: float, corner: float) -> void:
	var lo := _rrect(hx, hz, 0.0, corner, 0.0)
	var hi := _rrect(hx, hz, 0.0, corner, h)
	# Traced in XZ and lifted, so the extrusion axis is Y. Rotate the ring into
	# place rather than swapping axes, which would mirror the facing.
	var lo_y := _xz_to_y(lo, 0.0)
	var hi_y := _xz_to_y(hi, h)
	_loft(st, lo_y, hi_y, 1)
	_cap_ring(st, hi_y, Vector3(0.0, h, 0.0), true, 2)
	_cap_ring(st, lo_y, Vector3(0.0, 0.0, 0.0), false, 2)


func _foot(st: SurfaceTool, at: Vector3, r: float, h: float) -> void:
	var lo := _circle_xz(r, at, 0.0)
	var hi := _circle_xz(r, at, h)
	_loft(st, lo, hi, 3)
	_cap_ring(st, hi, at + Vector3(0.0, h, 0.0), true, 4)
	_cap_ring(st, lo, at, false, 4)


## The cabinet: a rounded rect at the back lofted onto a narrower one at the front.
func _box_tapered(st: SurfaceTool, back_hx: float, front_hx: float, cy: float,
		hy: float, hz: float, corner: float) -> void:
	var back := _rrect(back_hx, hy, cy, corner, -hz)
	var front := _rrect(front_hx, hy, cy, corner, hz)
	_loft(st, back, front, 5)
	_cap_ring(st, back, Vector3(0.0, cy, -hz), false, 6)


## The front face, as an annulus from the cabinet outline onto the driver's rim,
## so the driver has a hole to sit in.
func _baffle(st: SurfaceTool, hx: float, cy: float, hy: float, corner: float,
		z: float, driver_cy: float, driver_r: float) -> void:
	var outer := _rrect(hx, hy, cy, corner, z)
	var hole := _circle(driver_r, Vector3(0.0, driver_cy, z))
	# Subdivided rather than one loft. The hole sits low on the baffle rather than
	# concentric with it, so a single rect-to-circle span makes triangles long
	# enough for their interpolated normals to read as a crease across the panel.
	_annulus(st, outer, hole, 4, -1)


## A frame standing `proud` of the baffle, inset from its edge.
func _rim(st: SurfaceTool, hx: float, cy: float, hy: float, corner: float,
		z: float, inset: float, proud: float) -> void:
	var out_lo := _rrect(hx, hy, cy, corner, z)
	var out_hi := _rrect(hx, hy, cy, corner, z + proud)
	var in_hi := _rrect(hx - inset, hy - inset, cy, maxf(corner - inset * 0.5, 0.001), z + proud)
	_loft(st, out_lo, out_hi, 8)
	_loft(st, out_hi, in_hi, -1)
	# The rim's inner wall drops back to the baffle, which is what makes it a
	# frame rather than a plate.
	var in_lo := _rrect(hx - inset, hy - inset, cy, maxf(corner - inset * 0.5, 0.001), z)
	_loft(st, in_hi, in_lo, 8)


## Roll surround, cone and dust cap. The surround bulges forward of the baffle and
## the cone falls back behind it.
func _driver(cone: SurfaceTool, dark: SurfaceTool, cy: float, z: float,
		rim_r: float, cone_r: float, cap_r: float, depth: float) -> void:
	var centre := Vector3(0.0, cy, z)
	var rim := _circle(rim_r, centre)
	var roll := _circle(cone_r, centre + Vector3(0.0, 0.0, 0.0020))
	var apex := _circle(cap_r, centre - Vector3(0.0, 0.0, depth))
	_loft(cone, rim, roll, 10)
	# Cone wall, and it takes the OPPOSITE order to the surround above even though
	# both run front-to-back. The surround is a convex bead, seen from outside; the
	# cone is a concave funnel, and what a player sees is its INSIDE. So its faces
	# must point back toward the axis, which is the reverse winding.
	_loft(cone, roll, apex, 11)
	_cap_ring(dark, apex, centre - Vector3(0.0, 0.0, depth - 0.0060), true, 12)


## A dome on a flange, sitting proud so it shares no plane with the baffle.
func _tweeter(cone: SurfaceTool, shell: SurfaceTool, cy: float, z: float,
		r: float, flange_r: float) -> void:
	# 1.5 mm proud: the flange sits over solid baffle, so the two overlap in XY and
	# a smaller standoff z-fights at a grazing angle.
	var centre := Vector3(0.0, cy, z + 0.0015)
	var flange := _circle(flange_r, centre)
	var base := _circle(r, centre)
	_loft(shell, _circle(flange_r, centre - Vector3(0.0, 0.0, 0.0015)), flange, 13)
	_loft(shell, flange, base, 13)
	_dome(cone, centre, r, 0.0055, 14)


## A bore `depth` deep with a dark floor. `z` is the face it is cut into; a
## negative face is the back, so the bore runs the other way.
func _port(st: SurfaceTool, cy: float, z: float, r: float, depth: float) -> void:
	var dir := signf(z)
	var centre := Vector3(0.0, cy, z)
	var floor_at := centre - Vector3(0.0, 0.0, dir * depth)
	var mouth := _circle(r, centre)
	var floor_ring := _circle(r * 0.94, floor_at)
	# A bore is seen from the inside, so its wall faces the axis. _loft faces
	# outward given the nearer ring first, so the rings go in reverse depth order.
	if dir > 0.0:
		_loft(st, mouth, floor_ring, 15)
	else:
		_loft(st, floor_ring, mouth, 15)
	# The floor looks back out of the hole, which is +Z for a bore in the baffle
	# and -Z for one in the back panel.
	_cap_ring(st, floor_ring, floor_at, dir > 0.0, 16)


func _dome(st: SurfaceTool, centre: Vector3, r: float, rise: float, group: int) -> void:
	const BANDS := 4
	var prev := _circle(r, centre)
	for b in range(1, BANDS + 1):
		var t := float(b) / float(BANDS)
		var ring_r := r * cos(t * PI * 0.5)
		var ring_z := rise * sin(t * PI * 0.5)
		if b == BANDS:
			_cap_ring(st, prev, centre + Vector3(0.0, 0.0, rise), true, group)
			break
		var ring := _circle(ring_r, centre + Vector3(0.0, 0.0, ring_z))
		_loft(st, prev, ring, group)
		prev = ring


# ── rings ─────────────────────────────────────────────────────────────────────

## Rounded rect in XY at depth z, centred at (0, cy). Starts at the TOP CENTRE and
## runs clockwise seen from +Z, sampled by ARC LENGTH.
##
## Both of those matter, and neither is cosmetic: a rect lofted onto a circle pairs
## vertex i with vertex i, so the two rings have to start in the same place and
## progress at the same rate or the annulus between them comes out as a fan of
## diagonal gashes.
func _rrect(hx: float, hy: float, cy: float, radius: float, z: float) -> PackedVector3Array:
	var r := minf(radius, minf(hx, hy))
	var sx := hx - r
	var sy := hy - r
	# A FIXED vertex budget per segment, not arc length. Two rounded rects of
	# different sizes then agree vertex for vertex, which is what a loft between
	# them needs — the cabinet's taper and the grille rim are both such a loft, and
	# under arc-length sampling the differing straight-to-arc ratio pairs mismatched
	# points and shears the face into diagonal gashes.
	var per := RING_SEG / 8
	var out := PackedVector3Array()
	for seg in 8:
		for k in per:
			var f := float(k) / float(per)
			var p := Vector2.ZERO
			match seg:
				0: p = Vector2(sx, sy) + _arc(90.0, f * PI * 0.5, r)      # top-right
				1: p = Vector2(hx, sy - f * 2.0 * sy)                     # right
				2: p = Vector2(sx, -sy) + _arc(0.0, f * PI * 0.5, r)      # bottom-right
				3: p = Vector2(sx - f * 2.0 * sx, -hy)                    # bottom
				4: p = Vector2(-sx, -sy) + _arc(-90.0, f * PI * 0.5, r)   # bottom-left
				5: p = Vector2(-hx, -sy + f * 2.0 * sy)                   # left
				6: p = Vector2(-sx, sy) + _arc(-180.0, f * PI * 0.5, r)   # top-left
				_: p = Vector2(-sx + f * 2.0 * sx, hy)                    # top
			out.append(Vector3(p.x, cy + p.y, z))
	out.reverse()
	return out


## A point `sweep` radians clockwise from `start_deg` on a circle of radius r.
func _arc(start_deg: float, sweep: float, r: float) -> Vector2:
	var a := deg_to_rad(start_deg) - sweep
	return Vector2(cos(a), sin(a)) * r


## Circle in XY about `centre`, clockwise seen from +Z and starting where _rrect
## does — at the top-right corner, i.e. 45 degrees — so a rect can be lofted onto
## it without a rotational twist.
func _circle(r: float, centre: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in RING_SEG:
		var a := deg_to_rad(45.0) - TAU * float(i) / float(RING_SEG)
		out.append(centre + Vector3(cos(a) * r, sin(a) * r, 0.0))
	out.reverse()
	return out


## Circle in the XZ plane about `centre`, for the parts extruded along Y.
func _circle_xz(r: float, centre: Vector3, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in RING_SEG:
		var a := TAU * float(i) / float(RING_SEG)
		out.append(Vector3(centre.x + cos(a) * r, y, centre.z + sin(a) * r))
	out.reverse()
	return out


## Take a ring traced in XY and stand it in XZ at height y. Rx(-90): (x, y, z) ->
## (x, z, -y), which is a rotation and so preserves the facing.
func _xz_to_y(ring: PackedVector3Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in ring:
		out.append(Vector3(p.x, y, -p.y))
	return out


## A flat annulus between two corresponding rings, in `steps` bands.
func _annulus(st: SurfaceTool, outer: PackedVector3Array, inner: PackedVector3Array,
		steps: int, group: int) -> void:
	var prev := outer
	for s in range(1, steps + 1):
		var f := float(s) / float(steps)
		var ring := PackedVector3Array()
		for i in outer.size():
			ring.append(outer[i].lerp(inner[i], f))
		_loft(st, prev, ring, group)
		prev = ring


func _loft(st: SurfaceTool, lo: PackedVector3Array, hi: PackedVector3Array, group: int) -> void:
	st.set_smooth_group(group)
	for i in lo.size():
		var j := (i + 1) % lo.size()
		st.add_vertex(lo[i]); st.add_vertex(hi[i]); st.add_vertex(hi[j])
		st.add_vertex(lo[i]); st.add_vertex(hi[j]); st.add_vertex(lo[j])


func _cap_ring(st: SurfaceTool, ring: PackedVector3Array, centre: Vector3,
		front: bool, group: int) -> void:
	st.set_smooth_group(group)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		if front:
			st.add_vertex(ring[i]); st.add_vertex(centre); st.add_vertex(ring[j])
		else:
			st.add_vertex(centre); st.add_vertex(ring[i]); st.add_vertex(ring[j])
