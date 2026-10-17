## An F-type aerial socket: the coax hole on the back of a television, and the ANT
## pass-through on an RF switch.
##
## Pinned to Channel.VIDEO rather than given a channel of its own, and that is a
## decision worth stating. An RF feed is not composite video, but nothing in the
## routing needs to know the difference: what a television does with the signal is
## decided by WHICH SOCKET it arrived in — RetroTV._input_for_device returns the
## port's input index — and the picture then resolves through the VIDEO arm that
## already exists. A Channel.RF would have bought a nicer log line in exchange for
## a new arm in RetroSystem.on_av_topology_changed and a new tint in _tint_jack.
##
## The consequence is honest about the hardware, too: a console's RF OUT is a plain
## phono jack, so a composite cord fits it and carries the picture. That is the real
## connector, and it is the philosophy RcaPort already states — nothing here
## enforces a "correct" cable.
##
## What is NOT modelled: RF carries mono sound down the same wire, so a set fed this
## way shows a picture and stays silent. The upgrade is data rather than surgery —
## a channel_for(cord) table here (the MultiAvPort shape) plus a second shared cord on
## the lead, and the existing machinery routes the audio with no new code.
##
## The jack visual is a child named CoaxJack, so RcaPort's _tint_jack and show_jack
## both look for "RcaJack", find nothing and no-op. Wanted: an F connector has no
## colour code.
class_name CoaxPort
extends RcaPort


func _init() -> void:
	connector = "coax_plug"


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
