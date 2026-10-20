## The JAMMA harness socket: on a cabinet's back, and on a bay's.
##
## A cabinet and its bay were one object; now a bay can stand apart, and this socket is how the two
## are joined across the room. It is an RcaPort with a connector of its own, so a JAMMA lead goes
## in it and nothing else does, and it only says which end of the join it is: a cabinet's socket
## answers `get_cabinet()`, a bay's answers `get_bay()`. JammaCable reads those two.
##
## It carries neither picture nor sound as a socket: the picture is the cabinet's own, and the
## lead's meaning is "this bay's board is the one that cabinet plays", which is JammaCable's.
class_name JammaPort
extends RcaPort


func _init() -> void:
	connector = "jamma_plug"


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
	show_jack = false


## The cabinet (the machine that runs a core) this socket is on, or null on a bay.
func get_cabinet() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("link_bay"):
			return n as Node3D
		n = n.get_parent()
	return null


## The bay this socket is on, or null on a cabinet.
func get_bay() -> ArcadeBayUnit:
	var n: Node = get_parent()
	while n != null:
		if n is ArcadeBayUnit:
			return n as ArcadeBayUnit
		n = n.get_parent()
	return null
