class_name PowerStrip
extends Node3D

## A six-outlet US power strip: a body the player carries, six NEMA 5-15R sockets on
## top of it, and a captive 3 ft cord ending in a grounded wall plug.
##
## Shaped like the Antenna — a lead with a body on one END — but a mains lead, so it
## speaks PowerCord's persistence API (plug_at / seating / restore_*) rather than
## CompositeCable's. Not a PowerCord subclass: that resolves $AppliancePlug in an
## @onready, and this lead's appliance end is the strip itself.
##
## Nothing stops the strip's own plug going into one of its own sockets. Nothing
## should: that is what a real one lets you do too.

## PowerCord's numbering, so a save's "end" means the same thing for both.
const END_WALL := PowerCord.End.WALL

## Every strip in the tree, so a change of mains region reaches them.
const GROUP := "power_strip"

## The body's top face, and the US sockets' height in it.
const TOP := 0.038
const US_SOCKET_Y := 0.036
## Where a region's deck sits: centred over the six sockets, clear of the switch.
## The deck mesh is authored as a wall plate (+Z up out of it), so it is turned
## to lie on the strip: plate X along the strip, plate Y toward -Z, plate Z up.
const DECK_AT := Transform3D(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0),
	Vector3(-0.0215, TOP, 0))

@onready var _body: RigidBody3D = $Body
@onready var _attach: Node3D = $Body/Shell/PowerStrip/CordAnchor
@onready var rope: VerletRope = $VerletRope
@onready var wall_plug: PowerPlug = $WallPlug

var _reach := 0.0
var _rope_built := false

## The region the strip was last made as; "" before _ready.
var region := ""


func _ready() -> void:
	add_to_group(GROUP)
	set_region(AppPrefs.mains_region)
	wall_plug.cable = self
	# A dangling plug must not shove its own strip across the floor.
	wall_plug.add_collision_exception_with(_body)
	call_deferred("_build_rope")


## One rope, from the switch end of the strip to the plug.
func _build_rope() -> void:
	if not is_inside_tree():
		return
	rope.start_node = _attach
	rope.end_node = wall_plug
	rope.end_anchor_offset = wall_plug.cable_anchor
	rope._init_points()
	_reach = float(rope.segment_count) * rope.segment_length
	_rope_built = true


## Keep the cord within its reach, moving whichever end is NOT owned — the Antenna's
## rule. A seated plug counts as owned (a snap zone freezes what it holds), so a strip
## plugged into the wall is hauled back toward the outlet when it is let go of.
func _physics_process(_delta: float) -> void:
	if not _rope_built or not is_instance_valid(_body) or not is_instance_valid(wall_plug):
		return
	var from: Vector3 = _attach.global_position
	var to: Vector3 = wall_plug.global_transform * wall_plug.cable_anchor
	if not wall_plug.is_held():
		PlugTether.reel_in(wall_plug, to, from, _reach)
		return
	if _body.freeze:
		return
	var back := CableHaul.haul(_body, from, to, _reach)
	if back != Vector3.ZERO:
		_body.global_position += back


## Make the strip `id`'s: its sockets and its own plug become that region's, as
## a strip bought there would be (MainsRegions' "strip" entry; a region with none
## keeps the scene's US one). Plugs that stop fitting fall out, its own included.
func set_region(id: String) -> void:
	var want := MainsRegions.resolve(id)
	if want == region:
		return
	region = want
	var spec: Dictionary = MainsRegions.of(want).get("strip", {})
	if spec.is_empty():
		spec = MainsRegions.of(MainsRegions.DEFAULT).get("strip", {})
	var deck_path := str(spec.get("deck", ""))
	var deck := _body.get_node_or_null("RegionDeck") as MeshInstance3D
	if deck_path.is_empty():
		if deck != null:
			deck.queue_free()
	else:
		if deck == null:
			deck = MeshInstance3D.new()
			deck.name = "RegionDeck"
			deck.transform = DECK_AT
			_body.add_child(deck)
		deck.mesh = load(deck_path) as Mesh
	var y := TOP + float(spec.get("port", 0.0)) * 0.001 if not deck_path.is_empty() else US_SOCKET_Y
	var every := maxi(1, int(spec.get("every", 1)))
	var i := 0
	for s in sockets():
		s.set_connector(str(spec.get("socket", s.connector)))
		s.position.y = y
		# A socket the region's plugs are too wide to use next to another is not
		# on this strip at all.
		var used := i % every == 0
		if not used and s.picked_up_object != null:
			s.drop_object()
		s.enabled = used
		s.visible = used
		i += 1
	wall_plug.set_connector(str(spec.get("plug", wall_plug.connector)))
	var tip := wall_plug.get_node_or_null("PlugTip") as MeshInstance3D
	var mesh_path := str(spec.get("plug_mesh", ""))
	if tip != null and not mesh_path.is_empty():
		tip.mesh = load(mesh_path) as Mesh
	var holder := PowerCord.socket_holding(wall_plug)
	if holder != null and not wall_plug.is_in_group(holder.snap_require):
		holder.drop_object()


## Remake every strip in `tree` as `id`'s. Before WallOutlet.apply_region, so a
## strip's plug left in the wall is already the new region's when the plate asks
## whether it still fits.
static func apply_region(tree: SceneTree, id: String) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as PowerStrip).set_region(id)


func on_plug_seating_changed() -> void:
	pass


## The six sockets, in order along the strip.
func sockets() -> Array[PowerPort]:
	var out: Array[PowerPort] = []
	for n in _body.get_children():
		if n is PowerPort:
			out.append(n as PowerPort)
	return out


## Unseat everything this strip touches, then free it: its own plug from whatever
## holds it, and every other plug out of its six sockets. A socket freed while it
## holds someone else's plug leaves that cord pointing at a dead pickable.
func drop_and_free() -> void:
	var port := PowerCord.socket_holding(wall_plug)
	if port != null:
		port.drop_object()
	for s in sockets():
		if s.picked_up_object != null:
			s.drop_object()
	queue_free()


# ── Persistence: PowerCord's API, one end ────────────────────────────────────────

func cord_count() -> int:
	return 1


func plug_at(end: int) -> PowerPlug:
	return wall_plug if end == END_WALL else null


func seating() -> Array[Dictionary]:
	var socket := PowerCord.socket_holding(wall_plug)
	return [{
		"plug": wall_plug,
		"end": int(END_WALL),
		"cord": 0,
		"device": socket.get_device() if socket != null else null,
		"port": String(socket.name) if socket != null else "",
	}]


func restore_plug_poses(seats: Array) -> void:
	for seat: Dictionary in seats:
		if int(seat.get("end", 0)) != END_WALL:
			continue
		var pos: Array = seat.get("position", [])
		var rot: Array = seat.get("rotation", [])
		if pos.size() == 3:
			wall_plug.global_position = Vector3(pos[0], pos[1], pos[2])
		if rot.size() == 3:
			wall_plug.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])


## Deferred for PowerCord's reason, and because the socket may be one of this strip's
## OWN, which restore_carried_body has only just moved.
func restore_seating(seats: Array) -> void:
	call_deferred("_apply_seating", seats)


func _apply_seating(seats: Array) -> void:
	restore_plug_poses(seats)
	for seat: Dictionary in seats:
		var device: Node3D = seat.get("device")
		var port_name := str(seat.get("port", ""))
		if int(seat.get("end", 0)) != END_WALL or device == null \
				or not is_instance_valid(device) or port_name.is_empty():
			continue
		var port := CompositeCable.port_named(device, port_name)
		if port != null and wall_plug.is_in_group(port.snap_require):
			port.pick_up_object(wall_plug)


## The strip's pose: the root never moves, the player carries the Body — see
## Antenna.carried_body_pose.
func carried_body_pose() -> Dictionary:
	if not is_instance_valid(_body):
		return {}
	var p := _body.global_position
	var r := _body.global_rotation_degrees
	return {"position": [p.x, p.y, p.z], "rotation": [r.x, r.y, r.z]}


func restore_carried_body(data: Dictionary) -> void:
	if not is_instance_valid(_body) or data.is_empty():
		return
	var p: Array = data.get("position", [])
	var r: Array = data.get("rotation", [])
	if p.size() == 3:
		_body.global_position = Vector3(p[0], p[1], p[2])
	if r.size() == 3:
		_body.global_rotation_degrees = Vector3(r[0], r[1], r[2])
	call_deferred("_build_rope")
