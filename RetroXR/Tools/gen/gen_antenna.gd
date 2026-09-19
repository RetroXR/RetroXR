## Bakes the RXR-004 set-top aerial's body to
## Scenes/Objects/appliances/antenna_body.res.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_antenna.gd
##
## Rabbit ears: a weighted black base, a hub, two three-section telescoping rods
## splayed out of it, and a UHF loop standing in front of them. Origin at the centre
## of the BASE — not of the whole silhouette — so the pickable's collision box needs
## no offset and the thing stands on a set the way the RF switch lies on a desk.
##
## Two surfaces, for the reason the connector bakes split theirs: surface 0 is the
## moulded plastic (base and hub), surface 1 is everything plated (rods, tips, loop).
##
## Everything round is built by _tube, which is gen_rf_switch's loft turned to run
## along an arbitrary axis. The winding rule is carried over unchanged, and it only
## holds while (u, dir, w) is a RIGHT-HANDED frame standing in for (x, y, z): a ring
## is traced (cos a * u - sin a * w), and stepping to the ring further along `dir`
## faces outward. Build the frame the other way round and every rod renders inside
## out, which at 3 mm across reads as the rod simply not being there.
##
## The rods are FIXED at their splay. They do not telescope or swing: the pose is
## the one in every photograph of one of these, and a rod that moved would want a
## reception model behind it that this room does not have.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")

const OUT_PATH := "res://Scenes/Objects/appliances/antenna_body.res"

# The base: 150 x 32 x 100 mm.
const HX := 0.075
const HY := 0.016
const HZ := 0.050
const CORNER_R := 0.014
const CORNER_SEG := 5

# (y, inset). A generous fillet on top, a tight one underneath: it is a moulding
# that sits on furniture, heavy at the bottom.
const LEVELS := [
	[-0.0160, 0.0012],
	[-0.0148, 0.0000],
	[ 0.0100, 0.0000],
	[ 0.0140, 0.0022],
	[ 0.0160, 0.0070],
]

const HUB_R := 0.020
const HUB_H := 0.014

const ROD_SPLAY_DEG := 32.0
const ROD_PIVOT_X := 0.010
## Three sections, thickest at the hub: (length, radius).
const ROD_SECTIONS := [
	[0.150, 0.0030],
	[0.140, 0.0023],
	[0.130, 0.0016],
]
const ROD_TIP_R := 0.0034
const ROD_SIDES := 8

const LOOP_R := 0.085
const LOOP_WIRE_R := 0.0022
const LOOP_SEG := 40
const LOOP_SIDES := 6
const LOOP_Z := 0.022
const LOOP_STALK := 0.012


func _init() -> void:
	var plastic := SurfaceTool.new()
	plastic.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plated := SurfaceTool.new()
	plated.begin(Mesh.PRIMITIVE_TRIANGLES)
	var group := 0

	# ── base ──
	var rings: Array = []
	for lv: Array in LEVELS:
		rings.append(_outline(float(lv[0]), float(lv[1])))
	for i in range(rings.size() - 1):
		plastic.set_smooth_group(group)
		group += 1
		_loft(plastic, rings[i], rings[i + 1])
	plastic.set_smooth_group(group)
	group += 1
	_cap(plastic, rings[0], Vector3(0.0, -HY, 0.0), false)
	plastic.set_smooth_group(group)
	group += 1
	_cap(plastic, rings[rings.size() - 1], Vector3(0.0, HY, 0.0), true)

	# ── hub ──
	var hub_top := Vector3(0.0, HY + HUB_H, 0.0)
	group = _tube(plastic, group, Vector3(0.0, HY, 0.0), hub_top, HUB_R, HUB_R * 0.86, 16, true)

	# ── rods ──
	for side: float in [-1.0, 1.0]:
		var a := deg_to_rad(ROD_SPLAY_DEG) * side
		var dir := Vector3(sin(a), cos(a), 0.0)
		var at := Vector3(ROD_PIVOT_X * side, HY + HUB_H * 0.6, 0.0)
		for sec: Array in ROD_SECTIONS:
			var to: Vector3 = at + dir * float(sec[0])
			group = _tube(plated, group, at, to, float(sec[1]), float(sec[1]), ROD_SIDES, true)
			at = to
		# The safety tip: a bead, so the end of a 1.6 mm rod is something you can see.
		group = _tube(plated, group, at, at + dir * (ROD_TIP_R * 2.0),
			ROD_TIP_R, ROD_TIP_R * 0.7, ROD_SIDES, true)

	# ── UHF loop ──
	var centre := Vector3(0.0, HY + LOOP_STALK + LOOP_R, LOOP_Z)
	group = _tube(plated, group, Vector3(0.0, HY - 0.001, LOOP_Z),
		Vector3(0.0, HY + LOOP_STALK + LOOP_WIRE_R, LOOP_Z), LOOP_WIRE_R * 1.6,
		LOOP_WIRE_R * 1.6, LOOP_SIDES, false)
	plated.set_smooth_group(group)
	group += 1
	var prev := _loop_ring(centre, 0)
	for k in range(1, LOOP_SEG + 1):
		var next := _loop_ring(centre, k % LOOP_SEG)
		_loft(plated, prev, next)
		prev = next

	plastic.generate_normals()
	plated.generate_normals()
	# Satin black, not gloss: PlugMats.plastic's clearcoat reads as wet, and this is
	# the dull moulding of a thing that lives on top of a warm television.
	var plastic_mat := PlugMats.matte(Color(0.045, 0.045, 0.05), 0.62)
	var plated_mat := PlugMats.chrome()

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plastic.commit_to_arrays())
	mesh.surface_set_material(0, plastic_mat)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plated.commit_to_arrays())
	mesh.surface_set_material(1, plated_mat)

	var err := ResourceSaver.save(mesh, OUT_PATH)
	var ab: AABB = mesh.get_aabb()
	var tris := 0
	for i in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("[gen] %s err=%d  %.4f x %.4f x %.4f m  origin-to-top %.4f  tris %d" % [
		OUT_PATH, err, ab.size.x, ab.size.y, ab.size.z, ab.end.y, tris])
	quit()


## One closed rounded-rectangle ring at height `y`, brought in by `inset`. Traced in
## the order gen_rf_switch traces its own: from +X, turning toward -Z.
func _outline(y: float, inset: float) -> PackedVector3Array:
	var hx: float = HX - inset
	var hz: float = HZ - inset
	var r: float = minf(CORNER_R, minf(hx, hz))
	var cx: float = hx - r
	var cz: float = hz - r
	var centres := [
		Vector2(cx, -cz),
		Vector2(-cx, -cz),
		Vector2(-cx, cz),
		Vector2(cx, cz),
	]
	var out := PackedVector3Array()
	for k in 4:
		var c: Vector2 = centres[k]
		for s in range(CORNER_SEG):
			var a: float = deg_to_rad(float(k) * 90.0 + float(s) * 90.0 / float(CORNER_SEG))
			out.append(Vector3(c.x + cos(a) * r, y, c.y - sin(a) * r))
	return out


## A ring of `sides` points about `at`, in the frame (u, dir, w) — see the header.
func _ring(at: Vector3, dir: Vector3, r: float, sides: int) -> PackedVector3Array:
	var u := dir.cross(Vector3.FORWARD)
	if u.length() < 0.01:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := u.cross(dir).normalized()
	var out := PackedVector3Array()
	for j in sides:
		var a := TAU * float(j) / float(sides)
		out.append(at + (u * cos(a) - w * sin(a)) * r)
	return out


## The loop's cross-section at step `k`. Its own frame rather than _ring's, because
## the radial direction has to turn WITH the loop or the tube twists once per lap:
## u is radial, dir the tangent, and u x dir comes out +Z all the way round.
func _loop_ring(centre: Vector3, k: int) -> PackedVector3Array:
	var t := TAU * float(k) / float(LOOP_SEG)
	var u := Vector3(cos(t), sin(t), 0.0)
	var w := Vector3(0.0, 0.0, 1.0)
	var at := centre + u * LOOP_R
	var out := PackedVector3Array()
	for j in LOOP_SIDES:
		var a := TAU * float(j) / float(LOOP_SIDES)
		out.append(at + (u * cos(a) - w * sin(a)) * LOOP_WIRE_R)
	return out


## A straight round bar from `from` to `to`, optionally capped. Returns the next free
## smooth group: the wall is one group and each cap its own, so a cap does not bleed
## into the wall under it.
func _tube(st: SurfaceTool, group: int, from: Vector3, to: Vector3, r0: float, r1: float,
		sides: int, capped: bool) -> int:
	var dir := (to - from).normalized()
	var lo := _ring(from, dir, r0, sides)
	var hi := _ring(to, dir, r1, sides)
	st.set_smooth_group(group)
	_loft(st, lo, hi)
	group += 1
	if capped:
		st.set_smooth_group(group)
		_cap(st, lo, from, false)
		group += 1
		st.set_smooth_group(group)
		_cap(st, hi, to, true)
		group += 1
	return group


## Wall band between two rings; `lo` is the one further back along the axis.
func _loft(st: SurfaceTool, lo: PackedVector3Array, hi: PackedVector3Array) -> void:
	var n := lo.size()
	for j in n:
		var j1 := (j + 1) % n
		st.add_vertex(lo[j]); st.add_vertex(hi[j]); st.add_vertex(hi[j1])
		st.add_vertex(lo[j]); st.add_vertex(hi[j1]); st.add_vertex(lo[j1])


## Close a ring onto `centre`. `up` faces along the axis; otherwise back down it.
func _cap(st: SurfaceTool, ring: PackedVector3Array, centre: Vector3, up: bool) -> void:
	var n := ring.size()
	for j in n:
		var j1 := (j + 1) % n
		if up:
			st.add_vertex(ring[j]); st.add_vertex(centre); st.add_vertex(ring[j1])
		else:
			st.add_vertex(centre); st.add_vertex(ring[j]); st.add_vertex(ring[j1])
