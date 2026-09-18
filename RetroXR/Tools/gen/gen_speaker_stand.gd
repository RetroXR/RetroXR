## Bakes the surround speaker stands — a tall one and a short one — to
## Scenes/Objects/appliances/speaker_stand_120.res and speaker_stand_100.res.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_speaker_stand.gd
##
## FRAME. Origin at the BASE CENTRE, so a .tscn stands one on the floor by putting
## the node on the floor. The height in each name is to the TOP SURFACE of the top
## plate — which is where a cabinet's own origin lands, so a satellite on the 1.2 m
## stand really does have its base at 1.2 m.
##
## TWO SURFACES, and both are closed solids, so both are judged by _check_outward.
## That is the difference from gen_speaker.gd, where the driver is an open funnel and
## needs an oracle of its own.
##
## WINDING. Godot's front face is CLOCKWISE. _loft and _cap_ring are taken verbatim
## from gen_speaker.gd and pair with COUNTER-clockwise rings, so every ring here is
## reversed into that order before it is returned. Traced the other way the whole
## stand bakes inside out, which reads as missing geometry rather than as a winding
## error — see the cone that shipped that way.
##
## Every ring carries RING_SEG vertices, so a rounded rect can be lofted onto a
## circle.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")

const TALL_PATH := "res://Scenes/Objects/appliances/speaker_stand_120.res"
const SHORT_PATH := "res://Scenes/Objects/appliances/speaker_stand_100.res"

## To the top plate's upper face. The pair a surround rig wants: ear height seated
## for the fronts, and a metre for a rear that stands behind a sofa.
const TALL_H := 1.200
const SHORT_H := 1.000

## Vertices per closed ring. Four corners of eight, so a rounded rect and a circle
## can be lofted onto each other.
const RING_SEG := 32

## Cast base. Wide and heavy-looking, because a 1.2 m column on a small foot reads
## as something that would fall over.
const BASE_HX := 0.1100
const BASE_H := 0.0140
const BASE_CORNER := 0.0120

## The plate a cabinet sits on. 130 mm square clears the satellite's 95 x 117 mm
## footprint with a margin all round.
const TOP_HX := 0.0650
const TOP_H := 0.0100
const TOP_CORNER := 0.0060

## The column, tapering slightly up its length so the silhouette is not a pipe.
const COL_R_LO := 0.0250
const COL_R_HI := 0.0200

## Spigots sunk into each plate so the column does not end on the plate's own face —
## two coplanar faces pointing the same way interleave and draw as a flickering
## pinwheel, which is the defect n64_vru_tests' faces/ group exists to catch.
const SPIGOT := 0.0030


func _init() -> void:
	var err := _bake(TALL_PATH, TALL_H)
	if err == OK:
		err = _bake(SHORT_PATH, SHORT_H)
	quit(err)


func _bake(path: String, height: float) -> int:
	var plates := SurfaceTool.new()
	var column := SurfaceTool.new()
	for st: SurfaceTool in [plates, column]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_slab(plates, BASE_HX, BASE_H, 0.0, BASE_CORNER)
	_slab(plates, TOP_HX, TOP_H, height - TOP_H, TOP_CORNER)
	# Overlapping both plates by SPIGOT, so no face of the column is coplanar with
	# a face of a plate.
	_column(column, BASE_H - SPIGOT, height - TOP_H + SPIGOT)

	plates.generate_normals()
	column.generate_normals()

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plates.commit_to_arrays())
	mesh.surface_set_material(0, PlugMats.matte(Color(0.115, 0.115, 0.126), 0.80))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, column.commit_to_arrays())
	# Smoother than the cast plates: the column reads as a drawn metal tube.
	mesh.surface_set_material(1, PlugMats.matte(Color(0.088, 0.088, 0.097), 0.42))

	var verdicts := PackedStringArray()
	for s in mesh.get_surface_count():
		verdicts.append("%d:%s" % [s, _check_outward(mesh, s)])
	var tris := 0
	for s in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for v in verdicts:
		if not v.ends_with("outward"):
			print("[gen] %s NOT SAVED: %s" % [path, ", ".join(verdicts)])
			return FAILED

	var err := ResourceSaver.save(mesh, path)
	print("[gen] %s err=%d size=%s tris=%d %s"
		% [path, err, mesh.get_aabb().size, tris, ", ".join(verdicts)])
	return err


## Whether a surface's STORED normals point away from the solid.
##
## The stored ones, because they are the only thing that differs: Godot's front face
## is the clockwise one, so generate_normals() returns the negative of the textbook
## (b-a) x (c-a), and an oracle that recomputes from vertex order reports an
## inside-out mesh as outward. Signed volume, the AABB and a manifold edge count
## cannot tell the two apart either.
func _check_outward(mesh: ArrayMesh, surface: int) -> String:
	var arrays := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var axes := {"+X": Vector3.RIGHT, "-X": Vector3.LEFT, "+Y": Vector3.UP,
		"-Y": Vector3.DOWN, "+Z": Vector3.BACK, "-Z": Vector3.FORWARD}
	var bad := PackedStringArray()
	for label: String in axes:
		var axis: Vector3 = axes[label]
		var reach := -INF
		for i in v.size():
			reach = maxf(reach, v[i].dot(axis))
		# EVERY vertex at the extreme, and the best-facing of them — not the first
		# one found, which gen_speaker.gd's copy of this takes. A tapered column
		# leans inward going up, so its side wall faces slightly UPWARD, and at the
		# bottom of the column that wall shares the extreme -Y with the end cap.
		# Picking it reported the column inside out at n.y = +0.004. Still a check
		# that can fail: wound the other way, every candidate faces backwards.
		var facing := -INF
		for i in v.size():
			if v[i].dot(axis) > reach - 0.000001:
				facing = maxf(facing, n[i].dot(axis))
		if facing < -0.0001:
			bad.append(label)
	return "outward" if bad.is_empty() else "INSIDE OUT on %s" % ", ".join(bad)


# ── parts ─────────────────────────────────────────────────────────────────────

## A rounded slab from y = base to y = base + h.
func _slab(st: SurfaceTool, hx: float, h: float, base: float, corner: float) -> void:
	# Traced in XZ and lifted, so the extrusion axis is Y. Rotate the ring into
	# place rather than swapping axes, which would mirror the facing.
	var lo := _xz_to_y(_rrect(hx, hx, 0.0, corner, 0.0), base)
	var hi := _xz_to_y(_rrect(hx, hx, 0.0, corner, 0.0), base + h)
	_loft(st, lo, hi, 1)
	_cap_ring(st, hi, Vector3(0.0, base + h, 0.0), true, 2)
	_cap_ring(st, lo, Vector3(0.0, base, 0.0), false, 2)


func _column(st: SurfaceTool, y_lo: float, y_hi: float) -> void:
	var lo := _circle_xz(COL_R_LO, y_lo)
	var hi := _circle_xz(COL_R_HI, y_hi)
	_loft(st, lo, hi, 3)
	# Capped at both ends even though both are buried in a plate: an unclosed tube
	# would show its own inside through the plate at a grazing angle.
	_cap_ring(st, hi, Vector3(0.0, y_hi, 0.0), true, 4)
	_cap_ring(st, lo, Vector3(0.0, y_lo, 0.0), false, 4)


# ── rings ─────────────────────────────────────────────────────────────────────

## Rounded rect in XY at depth z, centred at (0, cy). Starts at the TOP-RIGHT corner
## and runs clockwise seen from +Z, on a FIXED vertex budget per segment.
##
## The fixed budget is not cosmetic: two rounded rects of different sizes then agree
## vertex for vertex, which is what a loft between them needs. Under arc-length
## sampling the differing straight-to-arc ratio pairs mismatched points and shears
## the face into diagonal gashes.
func _rrect(hx: float, hy: float, cy: float, radius: float, z: float) -> PackedVector3Array:
	var r := minf(radius, minf(hx, hy))
	var sx := hx - r
	var sy := hy - r
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


## Circle in the XZ plane at height y, starting where _rrect does — at 45 degrees —
## so a rect can be lofted onto it without a rotational twist.
func _circle_xz(r: float, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in RING_SEG:
		var a := deg_to_rad(45.0) - TAU * float(i) / float(RING_SEG)
		out.append(Vector3(cos(a) * r, y, -sin(a) * r))
	out.reverse()
	return out


## Take a ring traced in XY and stand it in XZ at height y. Rx(-90): (x, y, z) ->
## (x, z, -y), which is a rotation and so preserves the facing.
func _xz_to_y(ring: PackedVector3Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in ring:
		out.append(Vector3(p.x, y, -p.y))
	return out


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
