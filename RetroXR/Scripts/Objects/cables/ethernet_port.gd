## The RJ45 socket -- on a GameCube's Broadband Adapter, a PlayStation 2's
## network adapter (or a slim PS2's own back panel), and each of the eight on an
## Ethernet hub.
##
## ILinkPort's shape for a different plug: find the machine that owns the socket
## and the core inside it, or say which hub it is moulded into, and let
## EthernetBus walk the rest.
##
## The difference is that on a console the socket is usually not the console's.
## It is on an ADAPTER -- an expansion unit seated in the GameCube's Serial Port 1
## or the fat PS2's expansion bay -- so the machine behind it is whatever that
## unit is seated on, and nothing at all while the unit sits on the table. An
## adapter cabled to a hub but in no console is a lead going nowhere.
##
## `link_port` is which of the machine's link-bus ports the adapter's core
## attaches: 1 on a PlayStation 2 (beside i.LINK's 0), 4 on a GameCube (beside
## its four controller sockets). The adapter row sets it.
class_name EthernetPort
extends PsxLinkPort

## Lit while a plug is in, as every RJ45 jack's link light is.
var _led: MeshInstance3D = null


func _init() -> void:
	connector = "ethernet_plug"


## What an export's scene conversion can undo of _init (Port._own_connector).
func _own_connector() -> String:
	return "ethernet_plug"


func _ready() -> void:
	super()
	has_picked_up.connect(func(_what: Node) -> void: _light(true))
	has_dropped.connect(func() -> void: _light(false))


## The machine behind this socket: the console an adapter is seated on, a slim
## PS2's own panel, or null -- an adapter on the table, or a hub.
func get_machine() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("get_libretro_node"):
			return n as Node3D
		if n is RetroExpansion:
			return (n as RetroExpansion).get_host()
		n = n.get_parent()
	return null


## The hub this socket is moulded into, or null.
func get_hub() -> EthernetHub:
	var n: Node = get_parent()
	while n != null:
		if n is EthernetHub:
			return n as EthernetHub
		n = n.get_parent()
	return null


## What a save and a netplay plug event name this socket against.
##
## Port.get_device walks for an A/V device, and an adapter is not one: the walk would go
## past the unit into the room and come back empty, so a lead seated in an
## adapter would be saved loose and its seating never sent to peers. The unit is
## a spawned, saved object in its own right, so it is the device.
func get_device() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n is RetroExpansion or n.has_method("on_av_topology_changed"):
			return n as Node3D
		n = n.get_parent()
	return null


func _light(on: bool) -> void:
	if _led == null:
		_led = MeshInstance3D.new()
		_led.name = "LinkLed"
		var box := BoxMesh.new()
		box.size = Vector3(0.002, 0.0015, 0.0005)
		_led.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.9, 0.2)
		mat.emission_energy_multiplier = 1.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_led.material_override = mat
		add_child(_led)
		# Above the mouth's top-right corner, on the plate.
		_led.position = Vector3(0.0055, 0.0055, 0.0003)
	_led.visible = on
