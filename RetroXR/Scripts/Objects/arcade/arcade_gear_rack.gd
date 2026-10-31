## ArcadeGearRack — what a cabinet is wired to besides its guns: hand-held gear on a cord (a Taiko drummer's sticks), built with the machine and freed with it.
##
## The cabinet's form says what there is and where it lies (RetroSystemModelArcadeCabinet.captive_gear: one row per `GearRest` marker). This builds each one: a pickable of its own
## (ArcadeHeldGear) laid in a cradle of the cabinet (a snap zone, as a gun's holster is: let go of over it, it is taken back; pulled out of it by a hand, it comes), tied by a cord to the node
## the cabinet's form gives it, the cord laid hanging down the front the way a stowed gun's is (CaptiveCord.hanging_route). The pair of each player know each other (the desktop's two hands).
##
## They are kept OUT of the "spawned" group (`captive`): nothing saves them and nothing syncs them as objects; a room that is loaded builds the cabinet and the cabinet builds them. The machine builds
## them after its form (RetroSystem.after_cabinet_form) and takes them away before the next one and when it leaves (before_cabinet_form, _exit_tree).
class_name ArcadeGearRack
extends RefCounted

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")
## The group a cradle takes: anything wired to a cabinet.
const GROUP := "arcade_gear"

var _system: Node3D = null
var _items: Array[ArcadeHeldGear] = []
var _wells: Array[XRToolsSnapZone] = []


func _init(system: Node3D) -> void:
	_system = system


## The gear now built, for whoever asks what came with the machine.
func items() -> Array[ArcadeHeldGear]:
	var live: Array[ArcadeHeldGear] = []
	for item in _items:
		if is_instance_valid(item):
			live.append(item)
	return live


## Build the gear `rows` ask for (captive_gear), for the cabinet model `cabinet`. What was there is taken away first.
func spawn(rows: Array, cabinet: Node3D) -> void:
	free_all()
	if rows.is_empty():
		return
	if _system == null or not is_instance_valid(_system) or not _system.is_inside_tree():
		push_warning("[Arcade] %d piece(s) of gear not built: the system is not in the tree" % rows.size())
		return
	var tree := _system.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else _system.get_parent()
	var to_model := _system.global_transform.affine_inverse()
	for row: Dictionary in rows:
		var scene := load(str(row["scene"])) as PackedScene
		if scene == null:
			push_warning("[Arcade] gear scene missing: %s" % str(row["scene"]))
			continue
		var item := scene.instantiate() as ArcadeHeldGear
		if item == null:
			push_warning("[Arcade] %s is not a piece of gear" % str(row["scene"]))
			continue
		item.captive = true
		item.kind = str(row.get("kind", ""))
		item.player = int(row["player"])
		item.side = int(row["side"])
		item.cord_length = float(row["cord"])
		item.cabinet = cabinet
		item.cord_anchor = row["entry"] as Node3D
		parent.add_child(item)
		var rest: Transform3D = row["rest"]
		item.global_transform = _system.global_transform * rest
		# The cord leaves the gear where it is tied and goes in where the cabinet's form says, in the model's frame and then the world's.
		if is_instance_valid(item.cord_anchor):
			var boss := to_model * item.cord_boss()
			var entry := to_model * item.cord_anchor.global_position
			# The cord hangs down the face it goes into: the cabinet's front, unless the row says another (a form's marker names it).
			var route := CaptiveCord.hanging_route(boss, entry, item.cord_length, row.get("front", Vector3.BACK) as Vector3)
			var world := PackedVector3Array()
			for point in route:
				world.append(_system.global_transform * point)
			item.cord_route = world
		_build_well(item, rest)
		_items.append(item)
	_pair_up()
	var kinds := PackedStringArray()
	for item in _items:
		kinds.append("%s %d/%d" % [item.kind, item.player, item.side])
	print("[Arcade] gear built: %d of %d row(s) [%s]" % [_items.size(), rows.size(), ", ".join(kinds)])


## The two of a player are each other's mate, for the desktop's other hand.
func _pair_up() -> void:
	for a in _items:
		for b in _items:
			if a != b and a.player == b.player and a.side != b.side and a.scene_file_path == b.scene_file_path:
				a.mate = b


## The cradle: a snap zone at the gear's rest, taking this gear and no other (a stick belongs to its own cord).
func _build_well(item: ArcadeHeldGear, rest: Transform3D) -> void:
	var well := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	well.name = "GearWell%d" % (_wells.size() + 1)
	# `snap_require` cannot be left empty or the zone never lights a ghost and no ray grab can reach it.
	well.snap_require = GROUP
	well.snap_filter = _accepts.bind(item)
	well.grab_distance = item.well_reach()
	Holster.prepare_seat(well)
	_system.add_child(well)
	# A cradle seats a thing by its grab point (XRToolsSnapZone.snap_pose_for): the thing lies at the zone's transform TIMES the point's inverse. A stick's point is the identity; a guitar's is
	# where a hand holds it, so the zone stands where the hand would, and the guitar hangs at `rest`.
	var point := item._get_grab_point(well, null)
	well.transform = rest * point.transform if point != null else rest
	_wells.append(well)
	item.captive_well = well
	well.pick_up_object(item)


## A cradle's gate: the ONE piece of gear that came out of it. Read through a Variant: a cradle outlives its gear by a frame during teardown.
func _accepts(obj: Node3D, item: Variant) -> bool:
	return obj != null and is_instance_valid(item) and obj == item


## Everything built is taken away: the cradles first (a snap zone never clears what it holds when that is freed, and these outlive the gear by a frame), then the gear and its cords.
func free_all() -> void:
	for held: Variant in _wells:
		var well := held as XRToolsSnapZone
		if is_instance_valid(well):
			well.enabled = false
			well.queue_free()
	_wells.clear()
	for entry: Variant in _items:
		var item := entry as ArcadeHeldGear
		if not is_instance_valid(item):
			continue
		var cord := item.cable_instance()
		if is_instance_valid(cord):
			cord.queue_free()
		item.queue_free()
	_items.clear()
