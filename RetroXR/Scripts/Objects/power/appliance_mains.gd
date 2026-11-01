## ApplianceMains — give an appliance its mains: a PowerInput, and the cord of its
## own leaving from its model's PowerCordExit (docs/dev/power.md).
##
## The TV, the decks, the amplifier and the arcade cabinet all call hook_up() from
## their _ready. The cord leaves from the RETRO XR model's own PowerCordExit (its
## contract: the strain relief on the back, the cord along local -Z); a shell without
## one gets an exit on the back of its drawn bounds, low and in the middle.
##
## A deck built into a combo set (TvDecks) runs off the set: follow() points its
## PowerInput at the set's and frees its own cord.
class_name ApplianceMains
extends RefCounted

const EXIT_NAME := "PowerCordExit"
## Other names a model's cord exit goes by (see _exit).
const EXIT_ALIASES: Array[String] = ["CableAnchor"]


## The appliance's PowerInput, with its own cord. `search` is where its model's
## PowerCordExit is looked for (the host itself if null). `grounded` asks for the
## region's three-pin plug (an arcade cabinet) rather than an appliance's two-pin one.
static func hook_up(host: Node3D, search: Node = null, grounded := false) -> PowerInput:
	var input := PowerInput.on(host)
	if input.captive != null and is_instance_valid(input.captive):
		return input
	var exit := _exit(host, search if search != null else host)
	input.captive = CaptiveMainsCord.attach(host, exit, grounded)
	print("[Power] %s: its own mains cord, from %s" % [host.name,
		"its model's %s" % EXIT_NAME if exit.get_meta(&"from_model", false) else "the back of its bounds"])
	return input


## The cord's exit: the model's, or one made on the drawn back of a model that has
## none (a mod's set): low and toward the right seen from the front, on the surface the
## model really has there (back_surface: a CRT's back tapers, so the bounds' back is the
## tube's hump and a cord from it hung in the air).
static func _exit(host: Node3D, search: Node) -> Node3D:
	var found := search.find_child(EXIT_NAME, true, false) as Node3D
	# A model built before the PowerCordExit contract names its cord's boot otherwise:
	# the Panasonic CT-20D10B's CableAnchor ("where the power cord leaves its boot",
	# the cord along -Z). Looked for only under a model of its own, never the host's.
	if found == null and search != host:
		for alias: String in EXIT_ALIASES:
			found = search.find_child(alias, true, false) as Node3D
			if found != null:
				break
	if found != null:
		found.set_meta(&"from_model", true)
		return found
	var box := ApplianceModel.node_bounds(host, host)
	var exit := Node3D.new()
	exit.name = EXIT_NAME
	host.add_child(exit)
	if box.size == Vector3.ZERO:
		exit.position = Vector3(0, 0.02, -0.1)
	else:
		var x := box.end.x - minf(0.05, box.size.x * 0.25)
		var y := box.position.y + box.size.y * 0.25
		var spot := back_surface(host, search, Vector2(x, y), box)
		# Identity basis: the cord leaves along -Z, out of the back, from just outside it.
		exit.position = spot - Vector3(0, 0, 0.002)
	return exit


const C8_PORT := preload("res://Scenes/Objects/cables/iec_c8_port.tscn")
const C14_PORT := preload("res://Scenes/Objects/cables/iec_c14_port.tscn")
## The name of an appliance's inlet. A save names the socket a cord is in by it, so
## it is never renamed.
const INLET_NAME := "PowerInlet"


## The appliance's PowerInput, with an INLET a separate cord goes into: a C8
## (figure-eight, `kind` "c8") or a C14 (kettle lead, "c14"). It stands where the
## model's cord would leave (PowerCordExit, turned so the socket faces out of the
## back), else on the back of the host's drawn bounds. A set and an arcade cabinet
## take theirs this way; the spawnable Power Cord goes in.
static func hook_up_inlet(host: Node3D, search: Node = null, kind := "c8") -> PowerInput:
	var input := PowerInput.on(host)
	var existing := host.get_node_or_null(INLET_NAME) as PowerPort
	if existing != null:
		input.add_inlet(existing)
		return input
	var port := (C14_PORT if kind == "c14" else C8_PORT).instantiate() as PowerPort
	port.name = INLET_NAME
	host.add_child(port)
	place_inlet(host, port, search if search != null else host)
	input.add_inlet(port)
	print("[Power] %s: a %s inlet on its back (%s)" % [host.name, kind.to_upper(),
		port.connector])
	return input


## Stand `port` where the model's cord leaves, its +Z out of the back (the exit's -Z),
## else on the back of the host's drawn model, low and to the right seen from the
## front. Either way set in so the inlet's face is flush with the surface it is in
## (inlet_proud): a C8's body stands 6 mm out of its socket point, and on the surface
## it read as a block stuck on the back.
static func place_inlet(host: Node3D, port: Node3D, search: Node) -> void:
	var exit := search.find_child(EXIT_NAME, true, false) as Node3D
	# R_y(180): a socket's +Z is out of its face, a cord's exit points the cord along -Z.
	var turn := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	var inset := inlet_proud(port)
	if exit != null:
		var at := host.global_transform.affine_inverse() * exit.global_transform
		var basis := at.basis.orthonormalized() * turn
		port.transform = Transform3D(basis, at.origin - basis.z * inset)
		return
	var box := ApplianceModel.node_bounds(host, host, [String(port.name)])
	if box.size == Vector3.ZERO:
		port.transform = Transform3D(turn, Vector3(0, 0.03, -0.1))
		return
	var x := box.end.x - minf(0.05, box.size.x * 0.25)
	# A quarter of the way up: lower is a stand or a foot, and a set's jack plates.
	var y := box.position.y + box.size.y * 0.25
	var spot := back_surface(host, search, Vector2(x, y), box)
	port.transform = Transform3D(turn, Vector3(spot.x, spot.y, spot.z + inset))
	print("[Power] %s: inlet on the back of its model at %s (no %s)" % [host.name, str(spot), EXIT_NAME])


## How far a socket's drawn inlet stands out of its socket point along its +Z (its
## "Inlet" mesh's front), so it can be set in flush; 0 for one with none.
static func inlet_proud(port: Node3D) -> float:
	var inlet := port.get_node_or_null("Inlet") as MeshInstance3D
	if inlet == null or inlet.mesh == null:
		return 0.0
	# Half a millimetre short of flush: a face coplanar with the cabinet's z-fights it.
	return maxf(0.0, (inlet.transform * inlet.get_aabb()).end.z - FACE_PROUD)


## How square to the ray (|normal.z|) the nearest face must be to take an inlet: a
## tapered back passes, a stand's rim or a cabinet's underside does not.
const SQUARE_TO_RAY := 0.5
## How far an inlet's face stands out of the surface it is set into.
const FACE_PROUD := 0.0005


## Where a ray along the host's +Z, from behind its bounds `box` at `xy`, first meets
## the drawn model under `search` (its own triangles: a CRT's back tapers, so the
## bounds' back is the tube's hump, far behind the corner an inlet goes in). Where the
## nearest face is steep to the ray (the rim of a stand, a sloping underside) or
## nothing is met, it tries again a quarter of the way toward the middle, up to four
## times; with nothing, the bounds' back.
static func back_surface(host: Node3D, search: Node, xy: Vector2, box: AABB) -> Vector3:
	var to_host := host.global_transform.affine_inverse()
	var meshes: Array[MeshInstance3D] = []
	for n: Node in search.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and not _in_port(mi, search):
			meshes.append(mi)
	var mid := Vector2(box.get_center().x, box.get_center().y)
	var at := xy
	for attempt in 5:
		var start := Vector3(at.x, at.y, box.position.z - 0.01)
		var best := INF
		var square := 0.0
		for mi: MeshInstance3D in meshes:
			var xf := to_host * mi.global_transform
			var bb := xf * mi.get_aabb()
			if at.x < bb.position.x or at.x > bb.end.x or at.y < bb.position.y or at.y > bb.end.y:
				continue
			var faces := mi.mesh.get_faces()
			for i in range(0, faces.size(), 3):
				var a := xf * faces[i]
				var b := xf * faces[i + 1]
				var c := xf * faces[i + 2]
				var hit: Variant = Geometry3D.ray_intersects_triangle(start, Vector3.BACK, a, b, c)
				if hit is Vector3 and (hit as Vector3).z < best:
					best = (hit as Vector3).z
					square = absf((b - a).cross(c - a).normalized().z)
		if best < INF and square >= SQUARE_TO_RAY:
			return Vector3(at.x, at.y, best)
		at = at.lerp(mid, 0.25)
	return Vector3(xy.x, xy.y, box.position.z)


static func _in_port(node: Node, stop: Node) -> bool:
	var n := node.get_parent()
	while n != null and n != stop:
		if n is Port:
			return true
		n = n.get_parent()
	return false


## A built-in deck: it has power while `owner_input` (the set's) does, and no cord.
static func follow(host: Node3D, owner_input: PowerInput) -> void:
	var input := PowerInput.on(host)
	if input.captive != null and is_instance_valid(input.captive):
		(input.captive as CaptiveMainsCord).drop_and_free()
	input.captive = null
	input.follow = owner_input
	MainsPower.changed(host.get_tree() if host.is_inside_tree() else null)
	print("[Power] %s: built in; runs off %s" % [host.name, owner_input.label if owner_input != null else "nothing"])
