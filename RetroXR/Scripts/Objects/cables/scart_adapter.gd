## A SCART plug with three phono jacks on its back: the block Nintendo sold in Europe
## (the Euro Connector Plug, SNSP-015) for a set whose only input is SCART. A console's
## composite lead goes into its VIDEO, AUDIO (L) and AUDIO (R); the block goes into the
## set's SCART socket. It conducts and nothing else: the picture is composite.
##
## An AvAdapter with no cord: PlugA0 IS the block (connector "scart_plug"), no PlugB0
## and no rope. Its jacks are AdapterRcaPorts, direction IN, whose get_device() is the
## set the block is in, and whose host_socket() is that set's SCART IN, so TvPanel files
## them on SCART; signal_kind COMPOSITE says how the picture arrives (TvDisplay).
## AvAdapter._resolve makes the leads in them resolve again when the block moves.
##
## The model is RetroXR-models nintendo/snes/scart-adapter (its clean LOD0;
## imported-assets/connectors/scart_adapter), turned into the plug frame by Shell's
## transform: the shell along +Z from the collar's face (the origin), the lettering +Y.
class_name ScartAdapter
extends AvAdapter

## The phono plugs held in the jacks, kept clear of the block they are pushed into.
var _lead_bodies: Dictionary = {}


func _ready() -> void:
	super._ready()
	for jack: AdapterRcaPort in jacks():
		jack.has_picked_up.connect(_on_lead_seated.bind(jack))
		jack.has_dropped.connect(_on_lead_pulled.bind(jack))  # has_dropped carries nothing


## The three jacks, VIDEO, AUDIO (L), AUDIO (R), for a probe or a test.
func jacks() -> Array[AdapterRcaPort]:
	var out: Array[AdapterRcaPort] = []
	for n: String in ["PlugA0/RcaVideo", "PlugA0/RcaL", "PlugA0/RcaR"]:
		var jack := get_node_or_null(n) as AdapterRcaPort
		if jack != null:
			out.append(jack)
	return out


## A seated phono plug's collider runs on into the jack, and so into the block: a
## frozen plug overlapping a loose block would shove it across the table
## (TrsRcaAdapter's rule).
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
