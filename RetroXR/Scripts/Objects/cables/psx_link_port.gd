## The serial socket on the back of a PlayStation -- SIO1, the one a link cable
## goes in.
##
## Not the controller bus. That is SIO0, it is on the front, and it carries pads
## and memory cards; the two share a register layout and a name and nothing else.
##
## Subclassed off LinkPort rather than off RcaPort directly, because everything
## this socket needs it already has: finding the machine that owns it by walking
## up the tree, and the core running inside that machine. What differs is the one
## string that decides which plugs fit, and a PlayStation has exactly one of
## these sockets so link_port stays at its default 0.
##
## get_cable() is inherited and always answers null here, which is correct rather
## than merely harmless: it exists so a GBA lead's inline junction can be told
## apart from a socket on a machine, and a PlayStation link cable has no
## junction. Two consoles, one wire, nothing in the middle.
class_name PsxLinkPort
extends LinkPort


## Whether to draw the silk-screened plate and the SERIAL I/O lettering.
##
## On the primitive body it is the only thing naming the socket, so it defaults
## on. A console with a shell of its own has the legend MOULDED INTO the back
## panel already, and the plate then lands as a black rectangle pasted over the
## console's own print -- so RetroSystemModelPlayStation turns this off, the same
## way it turns off RcaPort.show_jack for sockets the shell already draws.
@export var show_legend: bool = true:
	set(value):
		show_legend = value
		_apply_legend()


## Whether to draw the dark recess.
##
## Same story one layer down. On the primitive body there is no socket until this
## draws one. A console with a shell of its own has the socket MOULDED, and a box
## laid over it is a black cube stuck on the back panel -- which is what it looked
## like, because that is what it was. On such a shell this port is a SNAP ZONE and
## nothing else: it contributes no geometry and only says where a plug goes.
@export var show_recess: bool = true:
	set(value):
		show_recess = value
		_apply_recess()


func _ready() -> void:
	super()
	_apply_legend()
	_apply_recess()


func _apply_legend() -> void:
	var legend := get_node_or_null("Legend") as Node3D
	if legend != null:
		legend.visible = show_legend


func _apply_recess() -> void:
	var jack := get_node_or_null("PsxLinkJack") as Node3D
	if jack != null:
		jack.visible = show_recess


func _init() -> void:
	connector = "psx_link_plug"
