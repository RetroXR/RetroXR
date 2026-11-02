## Bakes a panel-mount 9-pin mini-DIN SOCKET, the Genesis Model 2's A/V OUT, to
## Scenes/Objects/system_models/genesis/genesis_av_jack.res.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_genesis_av_jack.gd
##
## For a surface that moulds no socket of its own: the primitive box standing in for a
## Genesis (RetroSystemModelDefault) and a 32X wearing its plain box. The Genesis's
## shell and the 32X's scanned one draw their own, so on them this stays hidden (the
## socket scene's PanelJack, MultiAvPort.draw_jack).
##
## Sized as the 32X's socket is (RetroXR-models sega/32x/console prep_scan.py), which
## gen_genesis_av.gd's real-size plug (an 8.95 mm shield, an 11.5 mm head) fits:
##   * chrome flange 12.4 mm across, which the plug's head stops on with a ring of
##     metal showing round it, as on the real socket
##   * a dark 9.7 mm mouth inside it, the metal shell's opening, where the shield goes
##   * the insert in the middle of the mouth, 7.7 mm across, with nine dark contact
##     holes on the plug's nine pins
##
## FLAT, and all of it in front of the panel. Both surfaces it is for are SOLID: a
## first bake with a real bore 7 mm deep drew its mouth, insert and floor behind the
## box's back face, which hid every bit of them, and the socket read as a chrome ring
## round a patch of box. So the three are stepped faces 0.2-0.4 mm proud instead
## (the insert above the mouth, the flange above both), each a ring the others do not
## overlap, and the plug's head -- 0.5 mm out, 7.2 mm across -- covers all but the
## flange's rim once it is in.
##
## Authored socket-on-+Z with the origin on the PANEL face, so it drops onto a port node
## whose local +Z points out of the cabinet, pushed back by however far the port stands
## proud (0.5 mm: genesis_av_port.tscn puts the jack there).
##
## The port is turned 180 degrees about X from the console (+Y down, as
## genesis_model.gd's configure_av_ports turns it), so a point in the console's frame
## is (x, -y) in this one. The plug's pins are given in the console's frame
## (gen_genesis_av.gd PIN_LAYOUT), hence the minus below.
##
## One surface on the shared connector material (Shaders/connector.gdshader), the part
## in vertex colour. Winding as gen_rca_jack.gd's: an outer wall written with z
## increasing faces out, a flat ring written outer radius to inner faces +Z, a bore
## written with z decreasing faces the axis.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")

const OUT_PATH := "res://Scenes/Objects/system_models/genesis/genesis_av_jack.res"

const RING := 24
const PIN_RING := 8

const FLANGE_R := 0.0062
const BORE_R := 0.00485
const INSERT_R := 0.00386
const HOLE_R := 0.00045

const Z_PANEL := 0.0
## The flange's face, the insert's and the mouth's: stepped, all under the plug's head
## face at 0.5 mm.
const Z_FACE := 0.0004
const Z_INSERT := 0.0003
const Z_MOUTH := 0.0002

## gen_genesis_av.gd's PIN_LAYOUT, in the CONSOLE's frame (metres).
const PIN_LAYOUT := [
	Vector2(-0.002225, 0.001513), Vector2(0.000445, 0.001513), Vector2(0.002225, 0.001513),
	Vector2(-0.002670, -0.000481), Vector2(-0.000890, -0.000481),
	Vector2(0.000890, -0.000481), Vector2(0.002670, -0.000481),
	Vector2(-0.000890, -0.002474), Vector2(0.000890, -0.002474),
]

const INSERT_BLACK := Color(0.085, 0.085, 0.090)


func _init() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	# The metal shell: flange edge, flange face, and its lip down to the mouth.
	st.set_color(PlugMats.chrome_vertex())
	_lathe(st, PackedVector2Array([
		Vector2(Z_PANEL, FLANGE_R),
		Vector2(Z_FACE, FLANGE_R),
		Vector2(Z_FACE, BORE_R),
		Vector2(Z_MOUTH, BORE_R),
	]), Vector2.ZERO)

	# The mouth round the insert, where the plug's shield goes: dark by material, as
	# gen_rca_jack.gd's socket is, since these rooms shadow nothing for being deep.
	st.set_color(PlugMats.socket_vertex())
	_lathe(st, PackedVector2Array([
		Vector2(Z_MOUTH, BORE_R),
		Vector2(Z_MOUTH, INSERT_R),
	]), Vector2.ZERO)

	# The insert: its edge up from the mouth, and its face.
	st.set_color(PlugMats.matte_vertex(INSERT_BLACK))
	_lathe(st, PackedVector2Array([
		Vector2(Z_MOUTH, INSERT_R),
		Vector2(Z_INSERT, INSERT_R),
		Vector2(Z_INSERT, 0.0),
	]), Vector2.ZERO)

	# Nine contact holes, a hair in front of the insert's face.
	st.set_color(PlugMats.socket_vertex())
	for pin: Vector2 in PIN_LAYOUT:
		var at := Vector2(pin.x, -pin.y)
		_lathe(st, PackedVector2Array([
			Vector2(Z_INSERT + 0.00003, HOLE_R),
			Vector2(Z_INSERT + 0.00003, 0.0),
		]), at, PIN_RING)

	st.generate_normals()
	var mesh := ArrayMesh.new()
	var mat := PlugMats.connector()
	st.set_material(mat)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	mesh.surface_set_material(0, mat)
	_check_and_save(mesh)
	quit()


## Revolve a (z, radius) profile about the Z axis through `centre`.
func _lathe(st: SurfaceTool, profile: PackedVector2Array, centre: Vector2, ring := RING) -> void:
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


## Refuse a bake whose flange face does not face out of the panel (a jack wound inside
## out is see-through from where anyone looks at it), or that reaches behind the panel
## (where a solid face hides it) or past the plug's head face (which must cover it).
func _check_and_save(mesh: ArrayMesh) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Per triangle: one lying wholly in the flange face's plane is the face.
	var face := 0
	var out := 0
	for i in range(0, verts.size(), 3):
		if absf(verts[i].z - Z_FACE) < 1e-6 and absf(verts[i + 1].z - Z_FACE) < 1e-6 \
				and absf(verts[i + 2].z - Z_FACE) < 1e-6:
			face += 1
			# generate_normals() reads facing off the winding (Godot's front faces are
			# clockwise), so the normal it wrote is the facing to check.
			if normals[i].z > 0.9:
				out += 1
	print("[gen] flange face triangles facing +Z: %d of %d" % [out, face])
	var ab := mesh.get_aabb()
	if face == 0 or out * 2 <= face or ab.position.z < -0.00001 or ab.end.z >= 0.0005:
		push_error("[gen] %s REFUSING: wound inside out, or not between the panel and the plug's head" % OUT_PATH)
		return
	var err := ResourceSaver.save(mesh, OUT_PATH)
	print("[gen] %s err=%d  %.4f x %.4f x %.4f m  z %.4f..%.4f  tris %d" % [
		OUT_PATH, err, ab.size.x, ab.size.y, ab.size.z, ab.position.z, ab.end.z, verts.size() / 3])
