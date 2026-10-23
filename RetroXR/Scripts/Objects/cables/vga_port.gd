## One DE-15 socket on a device — the tower's video out, the monitor's video in.
##
## An RcaPort with a different mouth. Everything the A/V topology needs is already
## there: RcaPort.GROUP membership so a plug can find the socket holding it,
## get_device() so the link resolves to the deck or the set, and the OUT/IN
## direction that decides which way a cord carries. CompositeCable._resolve reads
## RcaPort, and this is one.
##
## The `channel` export is inherited but not a choice here: VGA is a video-only
## connector, so it is pinned in _ready rather than left for a scene to get wrong.
## A player who wants sound out of the tower runs the RCA pair as well — which is
## what you did with a real PC, and which system.gd now handles because it merges
## every lead on a console rather than believing whichever reported last.
##
## The jack visual is a child named VgaJack, so RcaPort's own _tint_jack and
## show_jack — both of which look for a child named RcaJack — find nothing and no-op.
## That is deliberate: a VGA socket has no colour code to apply.
class_name VgaPort
extends RcaPort


func _init() -> void:
	connector = "vga_plug"


## What an export's scene conversion can undo of _init (RcaPort._own_connector).
func _own_connector() -> String:
	return "vga_plug"


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
