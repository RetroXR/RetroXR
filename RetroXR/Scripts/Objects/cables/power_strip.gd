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

@onready var _body: RigidBody3D = $Body
@onready var _attach: Node3D = $Body/Shell/PowerStrip/CordAnchor
@onready var rope: VerletRope = $VerletRope
@onready var wall_plug: PowerPlug = $WallPlug

var _reach := 0.0
var _rope_built := false


func _ready() -> void:
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
		var away: Vector3 = to - from
		var d: float = away.length()
		if d > _reach and d > 0.0001:
			var hit := wall_plug.move_and_collide(away * ((_reach - d) / d))
			if hit != null:
				wall_plug.move_and_collide(hit.get_remainder().slide(hit.get_normal()))
		return
	if _body.freeze:
		return
	var back := CableHaul.haul(_body, from, to, _reach)
	if back != Vector3.ZERO:
		_body.global_position += back


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
		if port != null:
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
