## SystemCaptivePads — the pads a console is wired to rather than socketed for
## (a Famicom's Controller I and II), and the wells they lie in.
##
## A child of the RetroSystem it serves, made in _init like the other components;
## spawn() runs once the model has said which pads it has. Lifted out of system.gd whole: it owns both of its fields,
## and what it needs of the machine -- the model, the cabinet's port zones, the
## room to hang the pads on -- it is handed or asks for publicly.
class_name SystemCaptivePads
extends Node

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null

## Pads this console is wired to, built by spawn().
var _captive_controllers: Array = []
## The recesses those pads lie in, one per pad -- a Famicom's two wells.
var _controller_wells: Array = []


func setup(host: RetroSystem) -> void:
	_host = host


## Pads this hardware is wired to rather than socketed for, built with the
## machine and seated at once.
##
## They are deliberately NOT in the "spawned" group, so nothing saves them and
## nothing syncs them as objects: the console rebuilds them every time it is
## built, the way it rebuilds its captive A/V lead, and _exit_tree takes them
## away again. A captive pad that persistence could see would come back as a
## second pad on every load.
##
## The port is locked afterwards, and its recess and number hidden. A hand that
## could pull the plug would be pulling out a lead the machine has no socket for,
## leaving a pad with a cord running into a console that cannot take it.
func spawn(port_zones: Array) -> void:
	var paths: Array = _host.get_model().captive_controllers()
	if paths.is_empty():
		return
	var rests: Array = _host.get_model().captive_controller_rests()
	var mounts: Array = _host.get_model().captive_gun_mounts() \
		if _host.get_model().has_method("captive_gun_mounts") else []
	var parent: Node = _host.get_tree().current_scene
	if parent == null:
		parent = _host.get_parent()
	for i in paths.size():
		if i >= port_zones.size():
			break
		var scene: PackedScene = load(str(paths[i]))
		if scene == null:
			push_warning("[RetroSystem] captive controller scene missing: %s" % str(paths[i]))
			continue
		var pad: Node3D = scene.instantiate()
		pad.set("captive", true)
		parent.add_child(pad)
		if i < rests.size():
			pad.global_transform = _host.global_transform * (rests[i] as Transform3D)
		# The route is authored in the model's frame and the rope lives in world
		# space, so it is carried over here. Asked for per pad rather than once,
		# because it is spent against that pad's own cord length.
		var routes: Array = _host.get_model().captive_cord_routes(_captive_cord_length(pad))
		if i < routes.size():
			var route: PackedVector3Array = routes[i]
			var world: PackedVector3Array = PackedVector3Array()
			for point in route:
				world.append(_host.global_transform * point)
			pad.set("captive_cord_route", world)
		_captive_controllers.append(pad)
		# The cord is built one deferred call later, so this may be a pending
		# restore rather than a seat; either way the pad ends up in the port.
		pad.restore_port_connection(_host, i)
		port_zones[i].enabled = false
		for hidden in ["PortRecess", "PortLabel"]:
			var node := port_zones[i].get_node_or_null(hidden) as Node3D
			if node != null:
				node.hide()
		var mount: Dictionary = mounts[i] if i < mounts.size() else {}
		if not mount.is_empty() and pad is LightGun:
			# A gun on a swivel mount is fixed to the cabinet: it turns about its pivot and never leaves, so it
			# has no well to be taken out of and put back in.
			(pad as LightGun).fix_to_mount(mount["pivot"] as Node3D, mount["local"] as Vector3, bool(mount["lever"]))
		elif i < rests.size():
			_build_controller_well(i, rests[i] as Transform3D, pad)


## The rest length of a captive pad's cord. `cable_length` 0 means the pad keeps
## whatever controller_cable.tscn ships, which is 1.80 m.
func _captive_cord_length(pad: Node3D) -> float:
	var declared := float(pad.get("cable_length"))
	return declared if declared > 0.0 else 1.8


## How far from a holster's seat a hand still takes the gun out of it, in metres.
const GUN_WELL_REACH := 0.13


## The recess a captive pad lies in, as a snap zone, so it can be put back where
## it came from. Its transform IS the rest: a pad carries no snap grab point, so
## a zone seats one at its own basis (measured, not assumed).
##
## It takes this console's own captive pads and nothing else. The group alone
## would offer the well to every hand-held device in the room, and `snap_require`
## cannot be left empty or the zone never lights a ghost and no ray grab can
## reach it.
func _build_controller_well(index: int, rest: Transform3D, pad: Node3D) -> void:
	var well: XRToolsSnapZone = RetroSystem.SNAP_ZONE_SCENE.instantiate()
	well.name = "ControllerWell%d" % (index + 1)
	well.snap_require = "hand_held_device"
	well.snap_filter = _accepts_captive_pad.bind(index)
	# A gun is taken from the hand's reach at its grip, not by hunting for the one point the zone
	# sits on: 6 cm made a holster feel magnetic, the hand had to be pulled right onto it.
	well.grab_distance = GUN_WELL_REACH if pad is LightGun else 0.06
	# A cabinet's gun follows the holster rule (no preview, back only when let go there). A console's wired pad (a Famicom's) keeps its well's preview: it is not a holster.
	if pad is LightGun:
		Holster.prepare_seat(well)
	_host.add_child(well)
	well.transform = rest
	_controller_wells.append(well)
	# A gun goes back in its holster when let go (LightGun._return_to_well).
	if "captive_well" in pad:
		pad.set("captive_well", well)
	well.pick_up_object(pad)


## A well's gate: the ONE pad that came out of it. A captive pad is moulded onto
## a cord out of the back of this console, and its cord reaches its own rear
## corner and no other -- so Controller II in Controller I's well is not a tidier
## arrangement, it is a cord across the cartridge deck.
##
## Read through the array into a Variant rather than comparing against a captured
## node: a well outlives its pad by a frame during teardown.
func _accepts_captive_pad(obj: Node3D, index: int) -> bool:
	if obj == null or index < 0 or index >= _captive_controllers.size():
		return false
	var pad: Variant = _captive_controllers[index]
	return is_instance_valid(pad) and obj == pad


## The pads built by spawn(), in port order.
func pads() -> Array:
	return _captive_controllers


func free_pads() -> void:
	# Let the wells go first. A snap zone never clears picked_up_object when what
	# it holds is freed, and these outlive the pads by a frame.
	for held: Variant in _controller_wells:
		var well := held as XRToolsSnapZone
		if is_instance_valid(well):
			well.enabled = false
			well.queue_free()
	_controller_wells.clear()
	for entry: Variant in _captive_controllers:
		var pad := entry as Node
		if not is_instance_valid(pad):
			continue
		# The cord is a sibling rather than a child -- a rope between two bodies
		# cannot be parented to either -- so freeing the pad alone would leave it
		# standing in the room. storage_box does the same pair.
		if pad.has_method("cable_instance"):
			var cord: Node = pad.cable_instance()
			if is_instance_valid(cord):
				cord.queue_free()
		pad.queue_free()
	_captive_controllers.clear()
