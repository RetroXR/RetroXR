## ControllerPlug — the grabbable plug at the end of a retro controller's cable.
## In the "controller_plug" group, which every controller port requires, and fits
## the ports whose connector is its own (Connectors.of; SystemPorts.accepts_plug).
##
## It names no console or controller class in code, only in comments: a cable
## scene holds this script, and naming RetroSystem compiled system.gd, whose
## preloads reach expansion.tscn -> wiimote.tscn -> nunchuk_cable.tscn and so this
## script again while it was still loading. When early class compiles walked into
## that loop at boot, every pad's cable scene loaded empty and no controller had
## its cord. scene_tests' plug/ group holds this.
class_name ControllerPlug
extends XRToolsPickable


## The controller (RetroController or LightGun) that owns this plug.
var _controller: Node3D = null
var _plugged_in := false

## Device type exposed so system.gd can read it without knowing the controller type.
var device_type: int = 1  # RETRO_DEVICE_JOYPAD
## What the controller on the other end calls itself in a core's device list
## (a gun's "zapper", "guncon"), copied with its device type. Empty for most.
## See RetroSystem.core_device_id.
var device_names: PackedStringArray = PackedStringArray()
## Systemid of the controller on the other end.
var systemid: String = ""
## What this plug is, copied off its controller (Connectors.of): its console's
## controller port, unless the controller says otherwise; "" fits any port.
var connector: String = ""

## Local point the cable leaves this plug at, fed to VerletRope.end_anchor_offset.
## The generic plug reads its own CordExit marker (the end of the strain-relief
## boot); a bespoke connector brings its own, since its origin is the SEATING
## reference buried in the shell rather than anywhere a cord could emerge.
var cable_anchor: Vector3 = Vector3.ZERO

## Which way the cord leaves, in this plug's frame. Fed to VerletRope's
## plug_exit_axis so an angled connector can say so in its asset. Vector3.BACK
## (-Z) for every straight plug, which is what the rope assumed globally before.
var cable_exit_axis: Vector3 = Vector3.BACK

## The generic plug's own exit, read from its CordExit marker at _ready and kept
## so removing a bespoke connector can put it back.
var _generic_exit := Transform3D.IDENTITY


func _ready() -> void:
	super._ready()
	add_to_group("controller_plug")
	_generic_exit = PlugExit.of_node(self)
	cable_anchor = _generic_exit.origin
	cable_exit_axis = -_generic_exit.basis.z.normalized()
	# Aimed at by what it draws: the generic molding, the connector a pad hands it
	# (set_plug_mesh), or a model a mod has put on it.
	PointerFit.watch(self)
	picked_up.connect(func(_p: Variant) -> void: PlugAim.aim(self))


## How far this plug may stray, as {anchor: Vector3, length: float}, or {} when
## the cable isn't built yet. Read by function_pickup so a ray grab reels the
## plug along the beam only as far as the cord actually reaches.
##
## Derived from the sibling rope rather than the owning controller, for the same
## reason CablePlug.get_tether is: every owner already sets `start_node` and
## sizes the rope, and there are several of them.
func get_tether() -> Dictionary:
	var rope := get_parent().get_node_or_null("VerletRope")
	if rope == null or not is_instance_valid(rope.start_node):
		return {}
	return {
		"anchor": (rope.start_node as Node3D).global_position,
		"length": float(rope.segment_count) * rope.segment_length,
	}


## Returns the owning controller (RetroController or LightGun).
func get_controller() -> Node3D:
	return _controller


## Swap the generic cylinder plug for a device-accurate connector — the PS/2 plugs
## on the keyboard and mouse, the NES pad's 7-pin, the Atari DE-9. The asset is
## authored in this node's own frame (connector on +Z, cable trailing -Z), so it
## needs no transform here.
##
## Takes a PackedScene carrying the shell plus a CordExit marker, or a bare Mesh
## for a connector not converted yet — PlugExit reads either and derives the old
## centre-of-the-back-face answer for the ones that cannot say.
##
## Re-entrant, and it has to be. Every pad sets this once when its cable spawns,
## because a pad is born knowing its console. A PadReceiver is universal and
## learns its connector only when it seats, so it calls this again on every plug
## and unplug — an empty path putting the generic moulding back, which is also
## what an unlisted console gets rather than keeping the last one's connector.
func set_plug_mesh(path: String) -> void:
	var previous := get_node_or_null("PlugModel")
	# Explicitly typed, not inferred: a ternary over Mesh/null infers Variant, and
	# inferring from Variant is an error in this project.
	var mesh: Mesh = null
	var exit := Transform3D.IDENTITY
	if not path.is_empty() and ResourceLoader.exists(path):
		var res: Resource = load(path)
		mesh = PlugExit.mesh_of(res)
		exit = PlugExit.of_resource(res)
	if previous == null and mesh == null:
		return          # nothing to swap in and nothing to swap out
	# The pointer target follows the connector. The fit waits for the end of the
	# frame, so it measures what this puts on, and anything a caller then does to
	# it (a mod turning it half round, or setting it back on the plug).
	PointerFit.watch(self)
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	for generic in ["PlugTip", "StrainRelief"]:
		var g := get_node_or_null(generic) as MeshInstance3D
		if g != null:
			g.visible = mesh == null
	if mesh == null:
		# Back to the generic moulding, and back to ITS exit — not to zero, which
		# is the middle of the bare grey barrel.
		cable_anchor = _generic_exit.origin
		cable_exit_axis = -_generic_exit.basis.z.normalized()
		return
	var mi := MeshInstance3D.new()
	mi.name = "PlugModel"
	mi.mesh = mesh
	add_child(mi)
	cable_anchor = exit.origin
	# -Z of the marker's own frame: the direction the cord leaves along. A straight
	# plug lands on Vector3.BACK, which is what every connector said implicitly
	# before any of them could say otherwise.
	cable_exit_axis = -exit.basis.z.normalized()


## Called by the owning controller when the cable is spawned.
func set_controller(controller: Node3D) -> void:
	_controller = controller
	if "device_type" in controller:
		device_type = controller.device_type
	# What RetroSystem.device_names_of reads, read here (see the class note).
	var names: Variant = controller.get("device_names") if "device_names" in controller else null
	device_names = names if names is PackedStringArray else PackedStringArray()
	# What this plug fits. The port zone's snap filter reads it off the plug
	# rather than chasing the cable back to the controller.
	if "systemid" in controller:
		systemid = str(controller.get("systemid"))
	connector = Connectors.of(controller)


## Called by system.gd when this plug snaps into a port. `system` is the RetroSystem,
## untyped here (see the class note).
func on_plugged_in(system: Node3D, port_index: int) -> void:
	_plugged_in = true
	if is_instance_valid(_controller) and _controller.has_method("on_plugged_in"):
		_controller.on_plugged_in(system, port_index)


## Called by system.gd when this plug is removed from a port.
func on_unplugged() -> void:
	_plugged_in = false
	if is_instance_valid(_controller) and _controller.has_method("on_unplugged"):
		_controller.on_unplugged()


func is_plugged_in() -> bool:
	return _plugged_in
