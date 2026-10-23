## Bakes one wall plate per mains region: the US duplex, a Schuko pair, a UK
## twin, and the rest of MainsRegions.REGIONS.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_wall_outlet.gd
##
## Like gen_light_switch.gd, each mesh is authored at real scale with +X across
## the wall, +Y up, and +Z out of the wall, the origin on the wall surface.
##
## Where a receptacle is and what it takes are not written here. MainsRegions
## places each one (the port a plug seats at) and names its socket, and
## MainsSpecs.SOCKETS gives that socket's holes, well and studs -- the numbers the
## fit test seats plugs against. This file only dresses them: the plate's size,
## colour and thickness, the face round each receptacle, rocker switches and
## screws. A flush receptacle's face is drawn at its port; a recessed one's well
## runs from the plate face down to its port, so the plate this bakes is the one
## the plugs are seated in.
extends SceneTree

const PlugMats := preload("res://Tools/gen/plug_materials.gd")
const Specs := preload("res://Tools/gen/mains_specs.gd")

const BEVEL := 0.0025
const SEG := 6

const IVORY := Color(0.62, 0.60, 0.55)
const WHITE := Color(0.80, 0.80, 0.78)

## The plates, in millimetres. "thick" is the plate face's height off the wall:
## a recessed socket's well must reach it from its port (checked below), which is
## why those plates stand proud like surface boxes. "face" dresses each flush
## receptacle: "oval" (the US islands), "module" (a raised rectangle of
## "face_size", turned with the socket), "round" (a raised disc) or "flat".
## "switches" and "screws" are where those go on the plate.
const PLATES := {
	# Standard plate 2-3/4 x 4-1/2 in, openings 28.6 x 34.1 (Kyle Switch Plates).
	"na": {"size": Vector2(69.85, 114.3), "radius": 6.0, "thick": 7.0, "tone": IVORY,
		"face": "oval", "face_size": Vector2(28.6, 34.1), "screws": [Vector2.ZERO]},
	# Panasonic WTF7003W plate 70 x 120 x 8.8; the receptacle modules stand 8.8.
	"jp": {"size": Vector2(70, 120), "radius": 3.0, "thick": 7.5, "tone": WHITE,
		"face": "module", "face_size": Vector2(26.0, 18.0)},
	# Gira surface-mount double, 151.9 x 80.8 (it is 61 deep; the plate here stops
	# where the wells do).
	"eu": {"size": Vector2(151.9, 80.8), "radius": 9.0, "thick": 22.0, "tone": WHITE,
		"face": "flat"},
	# Legrand Dooxie 2-gang, 158 x 87.
	"fr": {"size": Vector2(158, 87), "radius": 9.0, "thick": 20.0, "tone": WHITE,
		"face": "flat"},
	# MK K2747, 146 x 86, fixings 120.6 apart; rockers inboard, 13 x 25.5.
	"uk": {"size": Vector2(146, 86), "radius": 3.0, "thick": 9.0, "tone": WHITE,
		"face": "flat", "switches": [Vector2(-8.7, 17.7), Vector2(8.7, 17.7)],
		"switch_size": Vector2(13.0, 25.5),
		"screws": [Vector2(-60.3, 0), Vector2(60.3, 0)]},
	# Clipsal C2025, 116 x 76; a switch above each socket, a little outboard.
	"au": {"size": Vector2(116, 76), "radius": 4.0, "thick": 9.0, "tone": WHITE,
		"face": "flat", "switches": [Vector2(-26.0, 20.0), Vector2(26.0, 20.0)],
		"switch_size": Vector2(10.0, 14.0)},
	# 86-type, 86 x 86.
	"cn": {"size": Vector2(86, 86), "radius": 4.0, "thick": 9.0, "tone": WHITE,
		"face": "flat"},
	# Hager kallysto is 92 x 92 for three; two side by side here (EST).
	"ch": {"size": Vector2(92, 60), "radius": 6.0, "thick": 16.0, "tone": WHITE,
		"face": "flat"},
	# Vimar Plana 3-module, 120 x 80; a bipasso module's face 22.3 x 49 (the
	# socket's own frame: the pins run along its 49).
	"it": {"size": Vector2(120, 80), "radius": 5.0, "thick": 7.5, "tone": WHITE,
		"face": "module", "face_size": Vector2(49.0, 22.3)},
	# LK FUGA frame, 113 x 90 (a retailer's figure).
	"dk": {"size": Vector2(113, 90), "radius": 3.0, "thick": 7.5, "tone": WHITE,
		"face": "module", "face_size": Vector2(45.0, 50.0)},
	# Crabtree 4x4, 100 x 100; where the two sit on it is EST.
	"za": {"size": Vector2(100, 100), "radius": 3.0, "thick": 12.0, "tone": WHITE,
		"face": "flat"},
	# Size and layout EST: no source gave either.
	"in": {"size": Vector2(146, 86), "radius": 4.0, "thick": 7.5, "tone": WHITE,
		"face": "round", "face_size": Vector2(48.0, 48.0)},
	# Size and layout EST, an Italian-style modular plate.
	"il": {"size": Vector2(120, 80), "radius": 5.0, "thick": 7.5, "tone": WHITE,
		"face": "module", "face_size": Vector2(45.0, 45.0)},
	# Pial Plus 4x2, 82 x 121.
	"br": {"size": Vector2(82, 121), "radius": 4.0, "thick": 12.0, "tone": WHITE,
		"face": "flat"},
}


func _init() -> void:
	var regions: Dictionary = (load("res://Scripts/Data/mains_regions.gd") as GDScript) \
		.get_script_constant_map()["REGIONS"]
	var failed := 0
	for id: String in regions:
		if not PLATES.has(id):
			print("[gen] %s: no plate in PLATES" % id)
			failed += 1
			continue
		if not _bake(id, regions[id]):
			failed += 1
		var strip: Dictionary = regions[id].get("strip", {})
		if strip.has("deck") and not _bake("strip_" + id, _deck_region(strip)):
			failed += 1
	quit(1 if failed > 0 else 0)


## The power strip's sockets along its top, at the US body's six positions (the
## scene's Socket1..6), as a plate region: its "deck" covers them, its sockets are
## the region's, turned so their up runs along the strip (power_strip.tscn), and
## only every other one where the strip says so.
const STRIP_X := [-0.110, -0.074, -0.038, -0.002, 0.034, 0.070]
const DECK_X := -0.0215


func _deck_region(strip: Dictionary) -> Dictionary:
	var sockets := []
	var every := maxi(1, int(strip.get("every", 1)))
	for i in STRIP_X.size():
		if i % every != 0:
			continue
		sockets.append({"name": "Socket%d" % (i + 1), "connector": strip["socket"],
			"position": Vector3(float(STRIP_X[i]) - DECK_X, 0, float(strip["port"]) * 0.001),
			"rotation": Vector3(0, 0, -90)})
	return {"sockets": sockets, "mesh": strip["deck"]}


func _bake(id: String, region: Dictionary) -> bool:
	var plate: Dictionary = PLATES[id] if PLATES.has(id) else _deck_plate(id)
	var thick := float(plate["thick"]) * 0.001
	var size: Vector2 = plate["size"] * 0.0005
	var radius := float(plate["radius"]) * 0.001
	var ok := true

	var body := SurfaceTool.new(); body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new(); dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := SurfaceTool.new(); metal.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The wells cut through the face, as outlines on the plate.
	var wells: Array[PackedVector2Array] = []
	for socket: Dictionary in region["sockets"]:
		var spec: Dictionary = Specs.SOCKETS[str(socket["connector"])]
		var pos: Vector3 = socket["position"]
		if spec.has("recess"):
			var depth := float(spec["recess"]["depth"]) * 0.001
			if absf(pos.z + depth - thick) > 0.0002:
				print("[gen] %s %s: the well (%.1f deep from z %.1f) does not reach the face at %.1f mm"
					% [id, socket["name"], depth * 1000, pos.z * 1000, thick * 1000])
				ok = false
			wells.append(_place(Specs.outline(spec["recess"]), socket))
		elif pos.z < thick - 0.0001:
			print("[gen] %s %s: the receptacle at z %.1f is under the face at %.1f mm"
				% [id, socket["name"], pos.z * 1000, thick * 1000])
			ok = false

	# Cover: vertical side, a bevel, then the face with the wells cut out of it.
	var back := _rounded(size, radius, 0.0)
	var shoulder := _rounded(size, radius, thick - BEVEL)
	var face_ring := _rounded(size - Vector2(BEVEL, BEVEL), radius - BEVEL * 0.5, thick)
	_loft(body, back, shoulder, 0)
	_loft(body, shoulder, face_ring, 1)
	if not _face(body, face_ring, wells, thick):
		print("[gen] %s: the face did not triangulate" % id)
		ok = false

	for socket: Dictionary in region["sockets"]:
		_dress_socket(id, plate, socket, body, dark, metal, thick)

	var rocker: Vector2 = plate.get("switch_size", Vector2(11.0, 17.0)) * 0.001
	for at: Vector2 in plate.get("switches", []):
		var c := Vector3(at.x, at.y, 0) * 0.001
		_box(body, c + Vector3(0, 0, thick + 0.0010), Vector3(rocker.x, rocker.y, 0.0020))
		# The red "on" flash on the rocker's lower half.
		_box(dark, c + Vector3(0, -rocker.y * 0.25, thick + 0.0021),
			Vector3(rocker.x * 0.7, rocker.y * 0.3, 0.0002))
	for at: Vector2 in plate.get("screws", []):
		var c := Vector3(at.x, at.y, 0) * 0.001
		_disc(body, c + Vector3(0, 0, thick + 0.0004), 0.0030, 0.0008)
		_box(dark, c + Vector3(0, 0, thick + 0.00085), Vector3(0.0047, 0.0008, 0.0001))

	var mesh := ArrayMesh.new()
	var mats := [PlugMats.matte(plate["tone"], 0.80),
		PlugMats.matte(Color(0.075, 0.070, 0.064), 0.94),
		PlugMats.matte(Color(0.70, 0.68, 0.62), 0.35)]
	var tris := 0
	for i in 3:
		var st: SurfaceTool = [body, dark, metal][i]
		var arrays := st.commit_to_arrays()
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		st.generate_normals()
		arrays = st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
		tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var path := str(region["mesh"])
	var err := ResourceSaver.save(mesh, path)
	print("[gen] %s err=%d size=%s tris=%d%s" % [path, err, mesh.get_aabb().size, tris,
		"" if ok else "  <-- CHECK FAILED"])
	return ok and err == OK


## A strip deck's plate: the top of the US body it sits on, 227 x 52, as tall as
## its wells need.
func _deck_plate(id: String) -> Dictionary:
	var regions: Dictionary = (load("res://Scripts/Data/mains_regions.gd") as GDScript) \
		.get_script_constant_map()["REGIONS"]
	var strip: Dictionary = regions[id.trim_prefix("strip_")]["strip"]
	return {"size": Vector2(227, 50), "radius": 3.0, "thick": float(strip["height"]),
		"tone": WHITE, "face": "flat"}


## One receptacle: its face (or well), the dark apertures of its holes, and any
## stud or earth clips, all from its MainsSpecs socket.
func _dress_socket(id: String, plate: Dictionary, socket: Dictionary, body: SurfaceTool,
		dark: SurfaceTool, metal: SurfaceTool, thick: float) -> void:
	var spec: Dictionary = Specs.SOCKETS[str(socket["connector"])]
	var pos: Vector3 = socket["position"]
	var floor_z := pos.z
	if spec.has("recess"):
		# Walls facing in, and the well's floor at the port.
		var outline := _place(Specs.outline(spec["recess"]), socket)
		var top := PackedVector3Array()
		var bottom := PackedVector3Array()
		for p in outline:
			top.append(Vector3(p.x, p.y, thick)); bottom.append(Vector3(p.x, p.y, floor_z))
		_loft(body, top, bottom, 50)
		_fan(body, bottom, floor_z, true)
		if str(socket["connector"]) == "cee_7_3_socket":
			# The two earthing clips, top and bottom of the well.
			var r := float(spec["recess"]["body_size"].x) * 0.0005
			for y: float in [r - 0.0006, -r + 0.0006]:
				var c := _place_point(Vector2(0, y * 1000.0), socket)
				_box(metal, Vector3(c.x, c.y, floor_z + 0.0060), Vector3(0.0060, 0.0012, 0.0110))
	else:
		var style := str(plate.get("face", "flat"))
		var fs: Vector2 = plate.get("face_size", Vector2.ZERO) * 0.0005
		# A raised face sits round the socket's holes, not its port: a BS 546
		# earth is 28.6 above the pins the port is level with.
		var c := Vector2.ZERO
		var n := 0
		for hole: Array in spec.get("holes", []):
			for part: Dictionary in hole:
				c += _place_point(part["at"], socket)
				n += 1
		c = c / n if n > 0 else Vector2(pos.x, pos.y)
		if pos.z > thick + 0.0001 or style != "flat":
			var ring := PackedVector3Array()
			var ring_top := PackedVector3Array()
			var lift := maxf(pos.z, thick + 0.0010) if style != "flat" else pos.z
			floor_z = lift
			var pts: PackedVector2Array
			match style:
				"oval": pts = _ellipse(fs.x, fs.y, 32)
				"round": pts = _ellipse(fs.x, fs.y, 32)
				_: pts = _rect_pts(fs, deg_to_rad(float((socket.get("rotation", Vector3.ZERO) as Vector3).z)))
			for p in pts:
				ring.append(Vector3(c.x + p.x, c.y + p.y, thick - 0.0002))
				ring_top.append(Vector3(c.x + p.x * 0.96, c.y + p.y * 0.96, lift))
			_loft(body, ring, ring_top, 60)
			_fan(body, ring_top, lift, true)
	# The apertures, a hair above the face they are in.
	for hole: Array in spec.get("holes", []):
		for part: Dictionary in hole:
			var pts: PackedVector2Array
			if str(part["shape"]) == "round":
				pts = Specs._circle(part["at"], float(part["d"]) * 0.5)
			else:
				pts = Specs._rect(part["at"], part["size"], float(part.get("angle", 0.0)))
			var placed := _place(pts, socket)
			var ring := PackedVector3Array()
			for p in placed: ring.append(Vector3(p.x, p.y, floor_z + 0.00008))
			_fan(dark, ring, floor_z + 0.00008, true)
	for stud: Dictionary in spec.get("studs", []):
		var c := _place_point(stud["at"], socket)
		var length := float(stud.get("len", 10.0)) * 0.001
		_disc(metal, Vector3(c.x, c.y, floor_z + length * 0.5), float(stud["d"]) * 0.0005, length)


## A socket-frame outline in millimetres, turned and moved onto the plate (metres).
func _place(pts: PackedVector2Array, socket: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_place_point(p, socket))
	return out


func _place_point(p: Vector2, socket: Dictionary) -> Vector2:
	var pos: Vector3 = socket["position"]
	var turn := deg_to_rad(float((socket.get("rotation", Vector3.ZERO) as Vector3).z))
	return (p * 0.001).rotated(turn) + Vector2(pos.x, pos.y)


## The plate face: the ring's outline less every well, triangulated as one polygon
## with a bridge cut to each well. A well bridges up to the top edge unless
## another well is above it, then down to the bottom one.
func _face(st: SurfaceTool, ring: PackedVector3Array, wells: Array[PackedVector2Array],
		z: float) -> bool:
	var outer := PackedVector2Array()
	for p in ring: outer.append(Vector2(p.x, p.y))
	if Geometry2D.is_polygon_clockwise(outer):
		outer.reverse()
	var top := -INF
	var bottom := INF
	for p in outer:
		top = maxf(top, p.y); bottom = minf(bottom, p.y)
	for w in wells:
		var hole := w.duplicate()
		if not Geometry2D.is_polygon_clockwise(hole):
			hole.reverse()
		var centre := Vector2.ZERO
		for p in hole: centre += p
		centre /= hole.size()
		var up := true
		for other in wells:
			if other == w:
				continue
			var oc := Vector2.ZERO
			for p in other: oc += p
			oc /= other.size()
			if oc.y > centre.y and absf(oc.x - centre.x) < 0.02:
				up = false
		# The hole's vertex nearest the edge it bridges to; of a flat edge's
		# vertices, the one nearest the middle, so the cut never leaves a corner.
		var k := 0
		var best := -INF
		for i in hole.size():
			var score := (hole[i].y if up else -hole[i].y) - 0.01 * absf(hole[i].x - centre.x)
			if score > best:
				best = score; k = i
		var from := hole[k]
		var to := Vector2(from.x, top if up else bottom)
		outer = _bridge(outer, hole, k, to)
		if outer.is_empty():
			return false
	var idx := Geometry2D.triangulate_polygon(outer)
	if idx.is_empty():
		return false
	st.set_smooth_group(2)
	for i in range(0, idx.size(), 3):
		var a := outer[idx[i]]
		var b := outer[idx[i + 1]]
		var c := outer[idx[i + 2]]
		# Front faces are the clockwise ones seen from +Z.
		if (b - a).cross(c - a) > 0.0:
			var t := b; b = c; c = t
		for p: Vector2 in [a, b, c]:
			st.add_vertex(Vector3(p.x, p.y, z))
	return true


## Splice `hole` (clockwise) into `outer` (anticlockwise) through a cut from the
## edge point `to` straight to the hole's vertex k: out along one side of the cut,
## round the hole, and back along the other.
func _bridge(outer: PackedVector2Array, hole: PackedVector2Array, k: int,
		to: Vector2) -> PackedVector2Array:
	# The outline's edge the cut meets.
	var best := -1
	var best_d := INF
	for i in outer.size():
		var a := outer[i]
		var b := outer[(i + 1) % outer.size()]
		var q := Geometry2D.get_closest_point_to_segment(to, a, b)
		var d := q.distance_to(to)
		if d < best_d:
			best_d = d; best = i
	var a := outer[best]
	var b := outer[(best + 1) % outer.size()]
	var hit := Geometry2D.get_closest_point_to_segment(to, a, b)
	var eps := (b - a).normalized() * 0.00002
	var out := PackedVector2Array()
	for i in best + 1:
		out.append(outer[i])
	out.append(hit - eps)
	# Each side of the cut keeps to its own side of it, at the edge and at the
	# hole alike, or the two sides cross and nothing triangulates.
	for j in hole.size() + 1:
		out.append(hole[(k + j) % hole.size()] + (-eps if j == 0 else
			eps if j == hole.size() else Vector2.ZERO))
	out.append(hit + eps)
	for i in range(best + 1, outer.size()):
		out.append(outer[i])
	return out


func _rounded(half: Vector2, radius: float, z: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var r := minf(radius, minf(half.x, half.y))
	var centres := [Vector2(half.x - r, half.y - r), Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r), Vector2(half.x - r, -half.y + r)]
	for corner in 4:
		for sample in SEG:
			var a := deg_to_rad(float(corner) * 90.0 + float(sample) * 90.0 / SEG)
			var p: Vector2 = centres[corner] + Vector2(cos(a), sin(a)) * r
			out.append(Vector3(p.x, p.y, z))
	return out


func _ellipse(rx: float, ry: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _rect_pts(half: Vector2, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := minf(0.0015, minf(half.x, half.y))
	for c: Vector2 in [Vector2(half.x, half.y), Vector2(-half.x, half.y),
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]:
		out.append(c.rotated(turn))
	return out


## Walls between two rings of the same count, facing out of the lower one.
func _loft(st: SurfaceTool, lo: PackedVector3Array, hi: PackedVector3Array, group: int) -> void:
	st.set_smooth_group(group)
	for i in lo.size():
		var j := (i + 1) % lo.size()
		st.add_vertex(lo[i]); st.add_vertex(hi[i]); st.add_vertex(hi[j])
		st.add_vertex(lo[i]); st.add_vertex(hi[j]); st.add_vertex(lo[j])


## A flat polygon at z, facing +Z when `front`.
func _fan(st: SurfaceTool, ring: PackedVector3Array, z: float, front: bool) -> void:
	var centre := Vector3.ZERO
	for p in ring: centre += p
	centre /= ring.size()
	centre.z = z
	var ccw := not Geometry2D.is_polygon_clockwise(_flat(ring))
	st.set_smooth_group(-1)
	for i in ring.size():
		var j := (i + 1) % ring.size()
		var a := ring[i]
		var b := ring[j]
		if ccw != front:
			var t := a; a = b; b = t
		st.add_vertex(a); st.add_vertex(centre); st.add_vertex(b)


func _flat(ring: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ring: out.append(Vector2(p.x, p.y))
	return out


## A short cylinder standing on the wall's normal: a stud, a screw head.
func _disc(st: SurfaceTool, c: Vector3, r: float, length: float) -> void:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		lo.append(c + Vector3(cos(a) * r, sin(a) * r, -length * 0.5))
		hi.append(c + Vector3(cos(a) * r, sin(a) * r, length * 0.5))
	_loft(st, lo, hi, 70)
	_fan(st, hi, c.z + length * 0.5, true)


func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var v := [c+Vector3(-h.x,-h.y,-h.z),c+Vector3(h.x,-h.y,-h.z),c+Vector3(h.x,h.y,-h.z),c+Vector3(-h.x,h.y,-h.z),c+Vector3(-h.x,-h.y,h.z),c+Vector3(h.x,-h.y,h.z),c+Vector3(h.x,h.y,h.z),c+Vector3(-h.x,h.y,h.z)]
	st.set_smooth_group(-1)
	for f in [[0,1,2],[0,2,3],[4,6,5],[4,7,6],[0,7,4],[0,3,7],[1,6,2],[1,5,6],[0,5,1],[0,4,5],[3,6,7],[3,2,6]]:
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[1]]); st.add_vertex(v[f[2]])
