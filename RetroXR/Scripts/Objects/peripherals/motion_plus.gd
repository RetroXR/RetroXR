## MotionPlus, the dongle that clips onto the foot of a Wii Remote and gives it
## a gyroscope.
##
## The only accessory in this room that is both a PLUG and a SOCKET. It seats in
## the remote's expansion port the way a Nunchuk's connector does, and carries a
## port of its own on its far end so the Nunchuk still has somewhere to go. That
## pass-through is the whole shape of the real accessory, and it is why the core's
## device ids DOUBLE rather than gaining one: every extension can still be fitted,
## into the dongle instead of into the remote.
##
## It sends nothing to libretro itself. The remote owns the slot and derives the
## rotation from its own tracked motion, so all this has to do is be somewhere:
## seated, the remote announces a device id ending _MP and Dolphin attaches the
## emulated dongle; pulled, it announces the plain one and the emulated remote
## loses its gyroscope, which is what bare hardware does, and why Wii Sports
## Resort will not play without one.
class_name MotionPlus
extends XRToolsPickable



## Height of the drop hint above the dongle, in metres. Lower than the Nunchuk's:
## this is a 46 mm block and a hint at its height would float clear of it.
const HINT_HEIGHT := 0.08

## Retries for the deferred re-seat on load. Bounded rather than "until it works",
## for the reason Wiimote._reseat_nunchuk gives: a Nunchuk freed mid-load would
## otherwise reschedule this every idle frame for the life of the session.
const RESEAT_RETRIES := 8


## The Nunchuk in the pass-through changed. The remote cannot watch this zone
## itself, being two objects away from it, so the chain is announced upward and
## the remote re-announces its libretro slot on the strength of it.
signal nunchuk_changed(nunchuk: Nunchuk)
## The same for an extension the game has no class for (a mod's Classic
## Controller; see Wiimote._brought_extension), which goes in this socket as it
## goes in the remote's.
signal extension_changed(extension: Node3D)


## What this is to any socket it is offered to: an extension plug, which the
## remote's expansion port takes and no console port does.
var connector: String = Connectors.WII_EXTENSION

var _nunchuk: Nunchuk = null
var _extension: Node3D = null
var _hint: HeldHint = null

@onready var _expansion_port: XRToolsSnapZone = $ExpansionPort


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The remote's expansion port requires this group, the same one every cable
	# plug joins. Being in it is what makes a cable-less dongle seatable at all;
	# the systemid above is what then narrows the socket to this one thing.
	add_to_group("controller_plug")
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	_expansion_port.snap_filter = _accepts_nunchuk
	_expansion_port.has_picked_up.connect(_on_nunchuk_seated)
	_expansion_port.has_dropped.connect(_on_nunchuk_removed)


# ── The pass-through port ─────────────────────────────────────────────────────

## The dongle's OWN port: an extension plug, but not another dongle -- the
## pass-through is a Wii expansion port, not somewhere to stack more of them.
func _accepts_nunchuk(obj: Node3D) -> bool:
	if obj is MotionPlus:
		return false
	if Connectors.of(obj) == Connectors.WII_EXTENSION:
		return true
	# What the remote's own socket takes of a mod's making, this one does.
	return Wiimote._brought_extension(obj) != null


func _on_nunchuk_seated(plug: Node3D) -> void:
	var owner_node: Node3D = plug.get_controller() if plug.has_method("get_controller") else plug
	_nunchuk = owner_node as Nunchuk
	if _nunchuk == null:
		_extension = Wiimote._brought_extension(plug)
		extension_changed.emit(_extension)
		return
	nunchuk_changed.emit(_nunchuk)


## XRToolsSnapZone.has_dropped carries no argument: it says the zone is empty,
## not what left. Which is enough: the zone holds one thing, and it is _nunchuk
## or _extension.
func _on_nunchuk_removed() -> void:
	if _extension != null:
		_extension = null
		extension_changed.emit(null)
	_nunchuk = null
	nunchuk_changed.emit(null)


## The extension of a mod's making plugged into the pass-through, or null.
func get_extension() -> Node3D:
	return _extension if is_instance_valid(_extension) else null


## The Nunchuk plugged into the pass-through, or null. The remote reads its stick
## and buttons through this rather than holding a reference of its own, so there
## is one answer to "what is on the end of this remote" however deep the chain is.
func get_nunchuk() -> Nunchuk:
	return _nunchuk


## Re-seat a Nunchuk after a load. Deferred for the reason the remote's own
## version is: the Nunchuk spawns its cord on a deferred call, so its plug does
## not exist on the frame the scene is rebuilt and there is nothing to snap yet.
func restore_nunchuk(nc: Nunchuk) -> void:
	if not is_instance_valid(nc):
		return
	_reseat_nunchuk.call_deferred(nc, RESEAT_RETRIES)


func _reseat_nunchuk(nc: Nunchuk, tries_left: int) -> void:
	if not is_instance_valid(nc):
		return
	var plug := nc.get_plug()
	if plug != null:
		_expansion_port.pick_up_object(plug)
		return
	if tries_left <= 0:
		push_warning("[MotionPlus] nunchuk cord never appeared; left unseated")
		return
	_reseat_nunchuk.call_deferred(nc, tries_left - 1)


## Seat a plug in the pass-through: what a load does for an extension of a mod's
## making once its cord has been made (Wiimote.restore_extension, which does the
## waiting).
func seat_plug(plug: Node3D) -> void:
	if is_instance_valid(plug):
		_expansion_port.pick_up_object(plug)
