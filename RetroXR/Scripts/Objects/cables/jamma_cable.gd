## A JAMMA harness lead: the cabinet's socket to a bay's.
##
## One cord with the same plug at both ends. What a seated pair MEANS is the one thing this
## overrides: a cabinet in one socket and a bay in the other, and the cabinet plays that bay's board.
## The join is local geometry (what is plugged in what), which every peer reproduces from the plug
## events the base class already reports, so nothing here goes on a wire of its own.
##
## A bay that is clipped into a cabinet's mount is joined by that, and a lead to it is ignored; a
## cabinet that already has a bay takes a second one only after the first is out.
class_name JammaCable
extends PsxLinkCable

## The pair this lead has joined, [cabinet, bay], or [] when it joins nothing.
var _bound: Array = []


func _resolve() -> void:
	if not is_inside_tree():
		return
	var cabinet: Node3D = null
	var bay: ArcadeBayUnit = null
	for e: int in [End.A, End.B]:
		var port := _port_at(e)
		if port == null:
			continue
		if cabinet == null and port.get_cabinet() != null:
			cabinet = port.get_cabinet()
		elif bay == null and port.get_bay() != null:
			bay = port.get_bay()
	var other: Node3D = null if cabinet == null else cabinet.call("get_bay")
	if cabinet != null and bay != null and not bay.is_docked() and (other == null or other == bay):
		_link(cabinet, bay)
	else:
		_disconnect()
	_report_seating_changes()
	topology_changed.emit()


## The JAMMA socket this end sits in, or null.
func _port_at(e: int) -> JammaPort:
	var plugs := _end_plugs(e)
	if plugs.is_empty():
		return null
	var plug := plugs[0] as RcaPlug
	return plug.seated_port() as JammaPort if plug != null else null


func _link(cabinet: Node3D, bay: ArcadeBayUnit) -> void:
	if _bound.size() == 2 and _bound[0] == cabinet and _bound[1] == bay:
		return
	_disconnect()
	if bool(cabinet.call("link_bay", bay, ArcadeBayUnit.CABLE)):
		_bound = [cabinet, bay]


func _disconnect() -> void:
	var was := _bound
	_bound = []
	if was.size() != 2:
		return
	# Read out of the array, not through typed variables: either can have been freed since.
	if is_instance_valid(was[0]) and is_instance_valid(was[1]):
		var cabinet: Node3D = was[0]
		if cabinet.call("get_bay") == was[1] and cabinet.call("bay_link_kind") == ArcadeBayUnit.CABLE:
			cabinet.call("unlink_bay", was[1])


## A lead that joins a bay to a cabinet puts no two cores on a wire.
func linked_machines() -> Array[Dictionary]:
	return []


func held_machines() -> Array[Dictionary]:
	return []


func _watch() -> void:
	pass
