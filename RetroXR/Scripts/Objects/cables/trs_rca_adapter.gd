## A 3.5 mm stereo plug to two phono jacks: the molded black block every hi-fi
## shop sells, a TRS plug out of one end and the left (white) and right (red) RCA
## jacks out of the other. It conducts and nothing else. Into a handheld's or a
## deck's PHONES it puts that sound on a pair of phono leads (to an amplifier's
## AUDIO IN, a set's); into the speakers' line in it takes a pair of leads in.
##
## So it is a CompositeCable of ONE plug and no rope, as RfModulator is:
##   * PlugA0 IS the whole block (connector "trs_plug", the 3.5 mm leads' own). There is no PlugB0 and
##     no VerletRope; CompositeCable tolerates both.
##   * Its jacks are AdapterRcaPorts (PlugA0/RcaL, PlugA0/RcaR: AUDIO_L, AUDIO_R),
##     which answer get_device() with whatever the plug is seated in, so a pair of
##     phono leads from them is, to AvGraph and AvSource, a pair from that machine's
##     own sockets, with no new code in the routing.
##   * The jacks point the way the socket the plug is in points: in a PHONES or line
##     out (OUT) they are outputs; in a line in (IN) they are inputs, which is the
##     adapter's other everyday use. Loose, they keep the last direction.
##
## The model is RetroXR-models generic/trs-rca-adapter's 3.5 mm model ("mini";
## imported-assets/connectors/trs_rca_adapter), in the plug frame: the shaft along +Z
## from the block's front face (the origin), the jacks' mouths 27.7 mm behind it.
class_name TrsRcaAdapter
extends CompositeCable

@onready var _left: AdapterRcaPort = get_node_or_null("PlugA0/RcaL") as AdapterRcaPort
@onready var _right: AdapterRcaPort = get_node_or_null("PlugA0/RcaR") as AdapterRcaPort

## The phono plugs held in the jacks, kept clear of the block they are pushed into.
var _lead_bodies: Dictionary = {}


func _ready() -> void:
	super._ready()
	for jack: AdapterRcaPort in [_left, _right]:
		if jack == null:
			push_warning("[TrsRcaAdapter] %s: a jack is missing from the scene" % name)
			continue
		jack.has_picked_up.connect(_on_lead_seated.bind(jack))
		jack.has_dropped.connect(_on_lead_pulled.bind(jack))  # has_dropped carries nothing: jack is the one argument


## What the plug is seated in -- the machine the jacks speak for -- or null while
## the block hangs loose.
func host() -> Node3D:
	var port := _host_port()
	return port.get_device() if port != null else null


## The left and right jacks, for a probe or a test.
func jacks() -> Array[AdapterRcaPort]:
	return [_left, _right]


func _host_port() -> Port:
	var plug := _plug_at(0, 0)
	return plug.seated_port() if plug != null else null


## The block's own plug moving changes which machine the leads in its jacks belong
## to, and which way they carry. Those leads hold the routing (and their record of
## who they last told is how a machine left behind hears of it), so each is made
## to resolve again once this one has, as RfModulator does for RF OUT.
func _resolve() -> void:
	super._resolve()
	if not is_inside_tree():
		print("[TrsRcaAdapter] resolve skipped: block is out of the tree")
		return
	var port := _host_port() as RcaPort
	if port != null:
		for jack: AdapterRcaPort in [_left, _right]:
			if jack != null and jack.direction != port.direction:
				jack.direction = port.direction
		print("[TrsRcaAdapter] %s: seated in %s on %s, jacks %s" % [name, port.name,
			host().name if host() != null else "nothing",
			"OUT" if port.direction == RcaPort.Direction.OUT else "IN"])
	for jack: AdapterRcaPort in [_left, _right]:
		if not is_instance_valid(jack):
			continue
		var lead_plug := jack.seated_plug() as RcaPlug
		if lead_plug != null and is_instance_valid(lead_plug.cable) and lead_plug.cable != self:
			lead_plug.cable.on_plug_seating_changed()


## A seated phono plug's collider runs on into the jack, and so into the block: a
## frozen plug overlapping a loose block would shove it across the table.
func _on_lead_seated(what: Variant, jack: AdapterRcaPort) -> void:
	var plug := _plug_at(0, 0)
	var body := what as PhysicsBody3D
	if plug == null or body == null:
		return
	_on_lead_pulled(jack)
	plug.add_collision_exception_with(body)
	_lead_bodies[jack] = body


func _on_lead_pulled(jack: AdapterRcaPort) -> void:
	var plug := _plug_at(0, 0)
	var body: PhysicsBody3D = _lead_bodies.get(jack, null)
	if plug != null and is_instance_valid(body):
		plug.remove_collision_exception_with(body)
	_lead_bodies.erase(jack)
