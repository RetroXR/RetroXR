## Nintendo's PAL RF switch (SNSP-003): no TV lead at all -- the box itself plugs
## straight onto the set's aerial socket.
##
## Routed exactly as RfSwitch: the console lead's phono plug (PlugA0) into a
## machine's RF OUT (an NES's, or an N64's RF Modulator), the TV end into the set's
## aerial socket, and an aerial's plug in the box's own socket on its far end. What
## differs is the GEOMETRY, and only that is overridden here:
##
##   * PlugB0 IS the box. It is the rigid, grabbable thing (connector "coax_plug",
##     so the set's existing F socket takes it; the real one is an IEC plug, and the
##     game has only F), the way RfModulator's PlugA0 is its whole block. There is
##     no Body and no TvRope.
##   * The aerial socket rides on it, PlugB0/AntPort, and the console lead leaves
##     from PlugB0/DeckLeadAttach, on the box's side.
##   * One rope, not two: the console lead, from DeckLeadAttach to PlugA0. The
##     tether is RfSwitch's rule for that one lead, with the box (PlugB0) as the
##     thing hauled when the console plug is held and the box is not.
##   * The box is saved as a PLUG (its pose and its seat), so there is no separate
##     body pose: carried_body_pose is empty.
##
## RfSwitch.aerial(), reached_set() and drop_and_free() work unchanged through
## ant_port() below; AntPort's get_device() walks up past PlugB0 to this root.
class_name PalRfSwitch
extends RfSwitch


## The box, which is PlugB0.
var _box: RcaPlug = null
## The aerial plug AntPort holds, kept clear of the box it is pushed into.
var _aerial_body: PhysicsBody3D = null


func _ready() -> void:
	# Before super: RfSwitch reads _deck_attach when the deferred _build_rope runs,
	# and its own lookup (Body/DeckLeadAttach) finds nothing in this scene.
	_box = get_node_or_null("PlugB0") as RcaPlug
	_deck_attach = get_node_or_null("PlugB0/DeckLeadAttach") as Node3D
	super._ready()
	var lead := _plug_at(End.A, 0)
	if lead != null and _box != null:
		# The dangling console plug must not shove its own box about.
		lead.add_collision_exception_with(_box)
	var port := ant_port()
	if port != null:
		# The box is an F plug and its own aerial socket is a few centimeters from
		# its own collider: without this it can be taken into itself.
		port.snap_filter = _accepts_aerial
		port.has_picked_up.connect(_on_aerial_seated)
		port.has_dropped.connect(_on_aerial_pulled)


## The aerial socket, on the box's far end.
func ant_port() -> RcaPort:
	return get_node_or_null("PlugB0/AntPort") as RcaPort


## The box is what the spawn menu hands over: the console plug is on a 3 m lead.
func spawn_hold_target() -> XRToolsPickable:
	return _box if _box != null else super.spawn_hold_target()


func _accepts_aerial(what: Node3D) -> bool:
	var plug := what as RcaPlug
	return plug == null or plug.cable != self


## A seated F plug's collider runs on into the socket, and so into the box.
func _on_aerial_seated(what: Variant) -> void:
	var body := what as PhysicsBody3D
	if _box == null or body == null:
		return
	_on_aerial_pulled()
	_box.add_collision_exception_with(body)
	_aerial_body = body


func _on_aerial_pulled() -> void:
	if _box != null and is_instance_valid(_aerial_body):
		_box.remove_collision_exception_with(_aerial_body)
	_aerial_body = null


## One lead: the console's, from the box's side to the phono plug.
func _build_rope() -> void:
	if not is_inside_tree():
		return          # a netplay client's local copy is freed before we get here
	var plug := _plug_at(End.A, 0)
	if _deck_rope == null or _deck_attach == null or plug == null:
		return
	_wire(_deck_rope, _deck_attach, plug)
	_deck_reach = float(_deck_rope.segment_count) * _deck_rope.segment_length
	_rope_built = true


## RfSwitch's tether for the one lead, with the box as the hauled body.
func _physics_process(_delta: float) -> void:
	if not _rope_built or _plugs.is_empty() or not is_instance_valid(_box):
		return
	var plug := _plug_at(End.A, 0)
	if not is_instance_valid(plug) or not is_instance_valid(_deck_attach):
		return
	var from: Vector3 = _deck_attach.global_position
	var to: Vector3 = plug.global_transform * plug.cable_anchor
	if not plug.is_held():
		PlugTether.reel_in(plug, to, from, _deck_reach)
		return
	if _box.is_held():
		return                  # both ends owned; the reach is the hands' problem
	var back := CableHaul.haul(_box, from, to, _deck_reach)
	if back != Vector3.ZERO:
		_box.global_position += back


func _body_is_held() -> bool:
	return is_instance_valid(_box) and _box.is_held()


## Nothing to add: the box is PlugB0 and is saved with the plugs, pose and seat.
func carried_body_pose() -> Dictionary:
	return {}


func restore_carried_body(_data: Dictionary) -> void:
	# The rope was laid around wherever the plugs stood a frame ago.
	call_deferred("_build_rope")
