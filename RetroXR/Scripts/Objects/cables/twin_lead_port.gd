## TwinLeadPort — a US set's 300-ohm VHF antenna terminals: two screws a twin-lead's
## spade lugs go under.
##
## Another way into the set's RF input, beside the F-type: the NES era's RF switch
## and every rabbit-ears aerial ended in twin-lead, and a set took it here. To the
## routing it is the same VIDEO socket on the same input (TvInputKinds "rf" with
## "twinlead"). The pair of lugs is one "plug" (connector twinlead_spade): the 75 to
## 300 ohm balun's, which an F-type lead goes into.
##
## The block is RetroXR-models generic/twinlead-terminals.
class_name TwinLeadPort
extends RcaPort

const CONNECTOR := "twinlead_spade"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
