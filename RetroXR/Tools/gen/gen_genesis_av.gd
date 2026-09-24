## Bakes the Genesis Model 2 A/V lead's console end to
## Scenes/Objects/system_models/genesis/genesis_av_plug.res.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_genesis_av.gd
##
## The MK-1647-style lead: a round 9-pin mini-DIN at the console, three phonos at the
## set. Only the plug is baked here. The socket is moulded into the console shell
## (genesis_console.glb's A/V OUT), so there is no jack mesh to keep in step with it —
## and one drawn over the shell's own would z-fight it.
##
## ── Dimensions ───────────────────────────────────────────────────────────────
## Sized to the SHELL, not to the connector standard. A real mini-DIN shield is
## 9.5 mm across; the A/V OUT moulded into this model opens to 6.2 mm (measured by
## raycasting the GLB's rear panel: the mouth recesses 1.5 mm behind a panel face at
## z = -0.1043, and a ray 3.5 mm off centre already lands on the case). A 9.5 mm shield
## would stand on the case beside the hole it is meant to be in, so the shield here is
## 5.6 mm and the moulded head in proportion to it.
##
##   shield       5.6 dia, standing 6.5 proud of the head (it goes into the socket)
##   head         7.2 dia x 9 long, black, a thin collar round the shield
##   boot         ribbed, 11 mm to the cord
##
## ── Contracts ────────────────────────────────────────────────────────────────
## gen_wii_av.gd's: connector on +Z, cable trailing -Z (VerletRope's plug_exit_axis),
## origin on the HEAD's front face. That face is what stops on the panel, so a seated
## plug's origin is the panel plane and genesis_model.gd places the port there.
##
## One surface on the shared connector material (Shaders/connector.gdshader), the part
## carried in vertex colour: matte black moulding, chrome shield and pins, black insert.
## The console end of a three-cord lead has no cord colour, so nothing is tinted.
##
## Winding: every lathe profile runs with z INCREASING along an outer wall (faces out);
## a flat ring written from outer radius to inner faces +Z. generate_normals() derives
## facing from vertex order alone.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")

const OUT_PLUG := "res://Scenes/Objects/system_models/genesis/genesis_av_plug.res"

const SHIELD_R := 0.0028
const SHIELD_WALL := 0.0003
const Z_SHIELD := 0.0065         # the shield's front edge
const Z_INSERT := 0.0053         # the black insert's face, recessed inside the shield
## ── The mating face ──────────────────────────────────────────────────────────
## Sega's is NOT the generic mini-DIN-9 the pinout sites draw (allpinouts.org's
## conn_minidin9m.svg: an even 3 over 4 over 2, top row centred). A first bake from that
## drawing was wrong, and a photo of a Model 2's own A/V OUT shows why: its top row is
## UNEVEN — two holes toward one side, one out at the other, and a gap between.
##
## The console model's own A/V OUT moulds exactly that pattern, so the pins are placed
## on ITS nine contacts rather than on the photo's proportions — the thing the plug has
## to meet is that socket. A plug laid out off the photo alone had the right shape and
## the wrong size: its pins were spread wider and sat a row high, and the bottom two
## landed between contacts.
##
## Measured by genesis_render_probe --insert: the socket shot face-on through an
## ORTHOGRAPHIC camera (15.35 um a pixel whatever the depth — a perspective lens put
## the contacts 2.5% wide), the nine gold contacts found by colour and centred.
## Offsets from the socket's centre, in the CONSOLE's frame, in millimetres. A seated
## plug's axes ARE the console's (+X to +X, +Y up; the probe prints it), so these are
## the plug's own pin positions with no mirroring — the pattern already comes out as a
## plug's should, the socket's mirror image:
##
##   plug, face on:     Red    .  AudL  AudR        y = +0.55   x = -1.69, +0.42, +1.67
##                     Green Comp CSync Mono        y = -0.54   x = -1.88, -0.63, +0.62, +1.86
##                           Blue  +5V              y = -1.65   x = -0.61, +0.64
##
## Centred 0.55 mm BELOW the shield's axis, as the socket's contact block is. Which pin
## is which only matters for reading the layout; the room routes by cord, not pin.
##
## The keyway is still a notch in the top of the insert, as on any mini-DIN: 26.1 wide
## at the insert's rim, 18.2 at its floor, reaching in to r = 36.4, on the generic
## drawing's scale (shield r = 58.5, insert 52).
const DRAWING_SHIELD_R := 58.5
## Metres, off the console model's socket (see above).
const PIN_LAYOUT := [
	Vector2(-0.001685, 0.00055), Vector2(0.000419, 0.00055), Vector2(0.001668, 0.00055),
	Vector2(-0.001877, -0.00054), Vector2(-0.000629, -0.00054),
	Vector2(0.000618, -0.00054), Vector2(0.001860, -0.00054),
	Vector2(-0.000611, -0.00165), Vector2(0.000637, -0.00165),
]
## Pin diameter over shield diameter on real hardware (about 1 mm on 9.5 mm).
const PIN_TO_SHIELD := 0.105
const DRAWING_INSERT_R := 52.0
const DRAWING_KEY_RIM_HALF := 13.03
const DRAWING_KEY_FLOOR_HALF := 9.08
const DRAWING_KEY_FLOOR_R := 36.4
const PIN_PROUD := 0.0008
## How far the keyway sinks into the insert.
const KEY_DEPTH := 0.0012

## A thin collar, not a knob: 7.2 mm round over a 5.6 mm shield, the proportion the real
## Genesis 2 plug has (its moulding hugs the shield). A first bake at 12 mm made the
## head more than twice the shield's width and read as a lump on the back of the console.
const HEAD_R := 0.0036
const HEAD_CHAMFER := 0.0004
## Short, as the real moulding is: 9 mm of head and 11 mm of ribbed relief behind the
## shield, 20 mm in all. A first bake ran 16 + 18 = 34 mm and stood out of the console
## like a stalk.
const Z_HEAD_BACK := -0.009
const Z_CORD := -0.020
const RELIEF_RIBS := 4
const RELIEF_RIB_AMP := 0.0004
const BOOT_R := 0.0036
## The ribbon of three 2.2 mm cords genesis_av_cable.tscn ships is 6.6 mm across; the
## boot has to end wider than what it grips. Change that scene's tube_radius and this
## together.
const CORD_R := 0.0034

const BLACK := Color(0.055, 0.055, 0.060)
## A shade lighter than the moulding, so the keyway cut into it reads as a cut.
const INSERT_BLACK := Color(0.085, 0.085, 0.090)

const RING := 24
const PIN_RING := 8


func _init() -> void:
	_build_plug()
	quit()


func _build_plug() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	# The moulding: cord, ribbed boot, head, then its front face in to the shield.
	st.set_color(PlugMats.matte_vertex(BLACK))
	var p := PackedVector2Array()
	p.append(Vector2(Z_CORD, 0.0))
	p.append(Vector2(Z_CORD, CORD_R))
	var steps := RELIEF_RIBS * 3
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var z: float = lerpf(Z_CORD, Z_HEAD_BACK, t)
		var base: float = lerpf(CORD_R, BOOT_R, t)
		var bump: float = 0.5 + 0.5 * sin(t * float(RELIEF_RIBS) * TAU - PI * 0.5)
		p.append(Vector2(z, base + RELIEF_RIB_AMP * bump))
	p.append(Vector2(Z_HEAD_BACK, HEAD_R - HEAD_CHAMFER))
	p.append(Vector2(Z_HEAD_BACK + HEAD_CHAMFER, HEAD_R))
	p.append(Vector2(-HEAD_CHAMFER, HEAD_R))
	p.append(Vector2(0.0, HEAD_R - HEAD_CHAMFER))
	p.append(Vector2(0.0, SHIELD_R))
	_lathe(st, p, Vector2.ZERO, RING)

	# The shield: outer wall, front rim, and the inside wall down to the insert.
	st.set_color(PlugMats.chrome_vertex())
	_lathe(st, PackedVector2Array([
		Vector2(0.0, SHIELD_R),
		Vector2(Z_SHIELD, SHIELD_R),
		Vector2(Z_SHIELD, SHIELD_R - SHIELD_WALL),
		Vector2(Z_INSERT, SHIELD_R - SHIELD_WALL),
	]), Vector2.ZERO, RING)

	# The insert's face, less the keyway sector at the top.
	var k := SHIELD_R / DRAWING_SHIELD_R
	var insert_r: float = SHIELD_R - SHIELD_WALL
	var key_floor_r: float = DRAWING_KEY_FLOOR_R * k
	# The keyway's side walls, as angles off +X. The drawing tapers them (26.1 at the
	# rim, 18.2 at the floor); both ends land within a degree of the same bearing, so
	# they are cut radially here, which is what lets the face be two plain sectors.
	var key_half: float = asin(DRAWING_KEY_RIM_HALF / DRAWING_INSERT_R)
	var key_a0: float = PI * 0.5 - key_half
	var key_a1: float = PI * 0.5 + key_half
	st.set_color(PlugMats.matte_vertex(INSERT_BLACK))
	_sector(st, 0.0, insert_r, key_a1, key_a0 + TAU, Z_INSERT, RING)   # the face around it
	_sector(st, 0.0, key_floor_r, key_a0, key_a1, Z_INSERT, 4)          # the face inside it

	# The keyway itself: its floor, the inner wall it stops at, and its two sides.
	var z_key: float = Z_INSERT - KEY_DEPTH
	st.set_color(PlugMats.socket_vertex())
	_sector(st, key_floor_r, insert_r, key_a0, key_a1, z_key, 4)
	_arc_wall(st, key_floor_r, key_a0, key_a1, z_key, Z_INSERT, 4)
	for a: float in [key_a0, key_a1]:
		var dir := Vector2(cos(a), sin(a))
		_quad_both(st,
			Vector3(dir.x * key_floor_r, dir.y * key_floor_r, z_key),
			Vector3(dir.x * insert_r, dir.y * insert_r, z_key),
			Vector3(dir.x * insert_r, dir.y * insert_r, Z_INSERT),
			Vector3(dir.x * key_floor_r, dir.y * key_floor_r, Z_INSERT))

	# Nine pins standing out of it, on the console socket's nine contacts.
	st.set_color(PlugMats.chrome_vertex())
	# Sized from hardware, not the drawing, which draws pins as labelled bubbles 2.4 mm
	# across on a 9.5 mm shell. A real contact is about 1 mm: 0.105 of the shield.
	var pin_r: float = SHIELD_R * PIN_TO_SHIELD
	for pin: Vector2 in PIN_LAYOUT:
		_lathe(st, PackedVector2Array([
			Vector2(Z_INSERT - 0.0002, pin_r),
			Vector2(Z_INSERT + PIN_PROUD, pin_r),
			Vector2(Z_INSERT + PIN_PROUD, 0.0),
		]), pin, PIN_RING)

	st.generate_normals()
	var mesh := ArrayMesh.new()
	var mat := PlugMats.connector()
	st.set_material(mat)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	mesh.surface_set_material(0, mat)
	_save(mesh, OUT_PLUG)


## Revolve a (z, radius) profile about the Z axis through `centre`.
func _lathe(st: SurfaceTool, profile: PackedVector2Array, centre: Vector2, ring: int) -> void:
	for s in range(profile.size() - 1):
		var z0: float = profile[s].x
		var r0: float = profile[s].y
		var z1: float = profile[s + 1].x
		var r1: float = profile[s + 1].y
		if is_equal_approx(z0, z1) and is_equal_approx(r0, r1):
			continue
		for i in ring:
			var a0: float = TAU * float(i) / float(ring)
			var a1: float = TAU * float(i + 1) / float(ring)
			var p00 := Vector3(centre.x + cos(a0) * r0, centre.y + sin(a0) * r0, z0)
			var p10 := Vector3(centre.x + cos(a1) * r0, centre.y + sin(a1) * r0, z0)
			var p01 := Vector3(centre.x + cos(a0) * r1, centre.y + sin(a0) * r1, z1)
			var p11 := Vector3(centre.x + cos(a1) * r1, centre.y + sin(a1) * r1, z1)
			if is_zero_approx(r0):
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			elif is_zero_approx(r1):
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p10)
			else:
				st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
				st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)


## A flat annular sector at `z` facing +Z, from angle a0 anticlockwise to a1. r0 = 0
## makes it a fan. Winding as gen_wii_av.gd's _band.
func _sector(st: SurfaceTool, r0: float, r1: float, a0: float, a1: float, z: float,
		steps: int) -> void:
	for i in steps:
		var t0: float = lerpf(a0, a1, float(i) / float(steps))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(steps))
		var i0 := Vector3(cos(t0) * r0, sin(t0) * r0, z)
		var i1 := Vector3(cos(t1) * r0, sin(t1) * r0, z)
		var o0 := Vector3(cos(t0) * r1, sin(t0) * r1, z)
		var o1 := Vector3(cos(t1) * r1, sin(t1) * r1, z)
		st.add_vertex(i0); st.add_vertex(o1); st.add_vertex(o0)
		if r0 > 0.0:
			st.add_vertex(i0); st.add_vertex(i1); st.add_vertex(o1)


## A curved wall at radius r between two depths, facing away from the axis.
func _arc_wall(st: SurfaceTool, r: float, a0: float, a1: float, z0: float, z1: float,
		steps: int) -> void:
	for i in steps:
		var t0: float = lerpf(a0, a1, float(i) / float(steps))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(steps))
		var p00 := Vector3(cos(t0) * r, sin(t0) * r, z0)
		var p10 := Vector3(cos(t1) * r, sin(t1) * r, z0)
		var p01 := Vector3(cos(t0) * r, sin(t0) * r, z1)
		var p11 := Vector3(cos(t1) * r, sin(t1) * r, z1)
		st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)


## A quad wound both ways — the keyway's flat sides, seen from either side of the cut.
func _quad_both(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d], [a, c, b], [a, d, c]]:
		for v: Vector3 in tri:
			st.add_vertex(v)


## Save, refusing a bake whose frame is wrong or whose moulding faces inward — the two
## mistakes that show up three files away, as a plug seated backwards or see-through.
func _save(mesh: ArrayMesh, path: String) -> void:
	var ab: AABB = mesh.get_aabb()
	if ab.end.z <= 0.0 or ab.position.z >= 0.0:
		push_error("[gen] %s REFUSING: connector must sit on +Z and the cable trail -Z" % path)
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out := 0
	var total := 0
	for i in verts.size():
		# The side of the head and boot: radial, so outward means away from the axis.
		if verts[i].z < -0.001 and verts[i].z > Z_CORD + 0.001:
			var radial := Vector2(verts[i].x, verts[i].y)
			if radial.length() > CORD_R * 0.5:
				total += 1
				if Vector2(normals[i].x, normals[i].y).dot(radial) > 0.0:
					out += 1
	print("[gen] moulding faces outward: %d of %d" % [out, total])
	if total == 0 or out * 2 <= total:
		push_error("[gen] %s REFUSING: the moulding is wound inside out" % path)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(mesh, path)
	print("[gen] %s err=%d  %.4f x %.4f x %.4f m  z %.4f..%.4f  tris %d" % [
		path, err, ab.size.x, ab.size.y, ab.size.z, ab.position.z, ab.end.z,
		verts.size() / 3])
