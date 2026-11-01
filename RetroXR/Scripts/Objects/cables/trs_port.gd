## One 3.5 mm TRS socket on a device — the tower's line out, the speakers' line in.
##
## An RcaPort with a different mouth. Everything the A/V topology needs is already
## there: Port.ANY_GROUP membership so a plug can find the socket holding it,
## get_device() so a link resolves to the machine that owns the socket, and the
## OUT/IN direction that decides which way a cord carries.
##
## The `channel` export is inherited but not a choice here. A TRS connector carries
## BOTH channels down one plug, which is what Channel.AUDIO_STEREO exists to say, so
## it is pinned in _ready rather than left for a scene to get wrong. There is no
## crossed-channel case to model either — unlike a pair of phono cords, a stereo
## plug cannot be put in half way round.
##
## The jack visual is a child named TrsJack, so RcaPort's _tint_jack, which looks for
## a child named RcaJack, finds nothing and no-ops. That is deliberate: the green
## collar is baked into the mesh, and PC99's colour code is a property of the
## socket's function, not something a scene picks. show_jack DOES reach it
## (_jack_node): a detailed handheld shell moulds its own PHONES mouth, and the
## collar drawn over that read as a second socket (SystemAvPorts.build_phones).
class_name TrsPort
extends RcaPort


func _init() -> void:
	connector = "trs_plug"


## What an export's scene conversion can undo of _init (Port._own_connector).
func _own_connector() -> String:
	return "trs_plug"


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.AUDIO_STEREO


## The mouth show_jack shows or hides.
func _jack_node() -> Node3D:
	return get_node_or_null("TrsJack") as Node3D
