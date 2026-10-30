## DeckDrawer — the RETRO XR cassette deck's door and CD player's tray: a model's Open / Close animation that carries the
## media in and out on a seat the model marks (TapeSeat on the door, DiscSeat on the tray), as the DVD player's tray does.
##
## The host's MediaSlot hands its media over (MediaSlot.ride_driver): in on Close, out on Open, or `instant`, seated
## with the drawer shut (a save or a peer restoring it). The press of the host's open key comes here (press()): a
## drawer with media in it ejects it (or, parked out, takes it back); an empty one opens or shuts. The slot's zone sits
## where the open drawer offers its seat, so a medium let go there is taken, and it takes one only then: out, still
## and empty.
class_name DeckDrawer
extends Node

## The drawer has stopped, out (`open`) or in.
signal settled(open: bool)

## The deck that owns the drawer, its model, its slot and the slot's zone.
var host: Node3D
var model: ApplianceModel
var slot: MediaSlot
var zone: XRToolsSnapZone
## The model's seat on the moving part (a child of it, so it rides along).
var seat_part := ""
## Where a medium's center stands in the seat's frame (a disc's half thickness over the well's floor).
var seat_offset := Vector3.ZERO
## The log's tag.
var tag := "Deck"

var _open := false
var _anim := ""
var _t := 0.0
var _ride: Node3D = null


## Wire the slot to the drawer and put the zone where the open drawer offers the seat.
func setup() -> void:
	slot.ride_driver = _ride_media
	if model.has_animation("Open"):
		model.seek("Open", model.animation_length("Open"))
		zone.transform = _seat_local()        # the zone is the host's child
		model.seek("Close", model.animation_length("Close"))
	else:
		push_warning("[%s] %s: the model has no Open; the drawer does not move" % [tag, host.name])
	_sync()
	print("[%s] %s: drawer on %s, the zone at %s" % [tag, host.name, seat_part, zone.position])


## True while the drawer is out (or going out).
func is_open() -> bool:
	return _open if _anim == "" else _anim == "Open"


## True while it moves.
func is_moving() -> bool:
	return _anim != ""


## The animation it is running ("Open" / "Close"), or "".
func moving() -> String:
	return _anim


## The open key: media in the drawer goes out (or back in); an empty drawer opens or shuts.
func press() -> void:
	if _anim != "":
		print("[%s] %s: the open key while the drawer is moving; ignored" % [tag, host.name])
		return
	if slot.has_media():
		slot.toggle_eject()
		return
	start("Close" if _open else "Open", false)


## Open or shut at once (a restore, a test).
func set_open(open: bool) -> void:
	if is_open() == open and _anim == "":
		return
	start("Open" if open else "Close", true)


func _ride_media(media: Node3D, to_seat: bool, instant: bool) -> void:
	_ride = media
	start("Close" if to_seat else "Open", instant)


func start(anim: String, instant: bool) -> void:
	if not model.has_animation(anim):
		_open = anim == "Open"
		if _ride != null:
			_ride = null
			slot.end_ride()
		_sync()
		return
	_anim = anim
	_t = model.animation_length(anim) if instant else 0.0
	print("[%s] %s: drawer %s%s" % [tag, host.name, anim, " (at once)" if instant else ""])
	_sync()
	step(0.0)


func _process(delta: float) -> void:
	step(delta)


## Advance the drawer `delta` seconds, carrying the media on the seat.
func step(delta: float) -> void:
	if _anim == "":
		return
	var length := model.animation_length(_anim)
	_t = minf(_t + delta, length)
	model.seek(_anim, _t)
	if _ride != null:
		if is_instance_valid(_ride) and slot.get_media() == _ride:
			lay(_ride)
		else:
			_ride = null
			slot.end_ride()
	if _t < length:
		return
	_open = _anim == "Open"
	_anim = ""
	print("[%s] %s: drawer %s" % [tag, host.name, "out" if _open else "in"])
	if _ride != null:
		_ride = null
		slot.end_ride()
	_sync()
	settled.emit(_open)


## Lay the medium on the seat, at the spin it went in at.
func lay(media: Node3D) -> void:
	var seat := _seat_local()
	media.global_transform = host.global_transform * Transform3D(seat.basis * slot.seat_basis(),
		seat.origin + seat.basis * seat_offset)


func _seat_local() -> Transform3D:
	return model.part_transform(seat_part, host)


## A medium goes in only onto the drawer: out, still and empty.
func _sync() -> void:
	if zone:
		zone.enabled = _open and _anim == "" and not slot.has_media()
