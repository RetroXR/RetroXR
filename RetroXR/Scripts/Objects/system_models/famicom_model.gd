## RetroSystemModelFamicom — a primitive stand-in for the HVC-001 at the figures
## Nintendo published for it: 220 x 150 mm on the table, 60 mm to the top of the
## deck. A dark red base the full width, a cream deck 114 mm wide standing on the
## middle of it with the cartridge mouth through it, and the two 53 mm strips of
## base left either side as the controller wells.
##
## What makes this a separate platform from the NES rather than a second shell
## for it is one thing: Controller II carries a microphone, and the NES has none.
## Everything else about the two machines is the same core running the same ROMs.
##
## The pads are HARDWIRED, as they are on the machine: both cords leave the back
## through a grommet at each rear corner and there is no socket to unplug. The
## port snap zones still exist and still carry the input -- RetroSystem seats each
## pad in one and then locks it -- so nothing about bindings, netplay or the core
## changes; what changes is that a hand cannot pull a lead the console has no
## socket for.
class_name RetroSystemModelFamicom
extends RetroSystemModelDefault


## The case is drawn in famicom_primitive.tscn, so the cabinet drops its own
## 0.3 x 0.1 x 0.25 box.
func brings_own_body() -> bool:
	return true


## Two boxes, not one, and for the same reason the N64 needs two: the machine is
## STEPPED. A single box spanning the full 60 mm would stand 30 mm of solid
## collision over both controller wells, so a hand reaching for a pad lying in one
## would get the console instead.
const _BASE_BOX := Vector3(0.220, 0.030, 0.150)
const _BASE_POS := Vector3(0.0, 0.015, 0.0)
const _DECK_BOX := Vector3(0.114, 0.030, 0.150)
const _DECK_POS := Vector3(0.0, 0.045, 0.0)


func configure_collision(host: Node3D) -> void:
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		col.shape = col.shape.duplicate()
		(col.shape as BoxShape3D).size = _BASE_BOX
		col.position = _BASE_POS
		_add_deck_box(col.get_parent() as CollisionObject3D)


## Named, so a rebuild does not stack a second deck box on the one already there.
func _add_deck_box(body: CollisionObject3D) -> void:
	if body == null or body.has_node("DeckCollisionShape3D"):
		return
	var deck := CollisionShape3D.new()
	deck.name = "DeckCollisionShape3D"
	var box := BoxShape3D.new()
	box.size = _DECK_BOX
	deck.shape = box
	body.add_child(deck)
	deck.position = _DECK_POS


## The cabinet authors its ports at z 0.125, which is 50 mm off the front of this
## case. Both hooks below put its furniture back onto real faces.
##
## On the REAR, at the grommets, because that is where a Famicom's cords come out.
func configure_controller_ports(port_zones: Array) -> void:
	for i in port_zones.size():
		var zone := port_zones[i] as Node3D
		if zone == null:
			continue
		var seat := get_node_or_null("Rear/PortSeat%d" % (i + 1)) as Node3D
		if seat != null:
			zone.global_transform = seat.global_transform


const _PADS := "res://Scenes/Objects/controllers/famicom/"


## Controller I in port 1, Controller II -- the one with the microphone -- in
## port 2. The order is the hardware's and it is load-bearing: the core reads the
## microphone off joy[1] alone, so a Controller II built into player one's port
## would have no microphone at all.
func captive_controllers() -> Array[String]:
	return [_PADS + "famicom_controller_i.tscn", _PADS + "famicom_controller_ii.tscn"]


## Lying in the two wells, face up and turned lengthways: a pad is 118 mm long
## and a well 53 mm wide, so it only fits the long way round. R_y(90) sends the
## pad's own +Z out along the console's +X. 41 mm is the well floor at 30 mm plus
## half the pad's 22 mm thickness.
func captive_controller_rests() -> Array[Transform3D]:
	var turned := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	return [
		Transform3D(turned, Vector3(-0.0835, 0.041, 0.0)),
		Transform3D(turned, Vector3(0.0835, 0.041, 0.0)),
	]


## POWER on the left, RESET on the right, on the front of the deck's top face.
## Also shrinks them: the cabinet's caps are scaled for a 300 mm box and would
## cover most of a 114 mm deck.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	super(power_btn, reset_btn, eject_btn)
	_seat_button(power_btn, "Top/PowerSeat")
	_seat_button(reset_btn, "Top/ResetSeat")


func _seat_button(btn: Node3D, seat_path: String) -> void:
	if btn == null:
		return
	var seat := get_node_or_null(seat_path) as Node3D
	if seat == null:
		return
	btn.global_transform = seat.global_transform
	btn.scale = Vector3(0.4, 0.4, 0.4)


## A cartridge drops straight down into the mouth and stands up out of the deck.
func configure_cartridge_slot(slot: Node3D) -> void:
	var seat := get_node_or_null("CartSeat") as Node3D
	if seat != null:
		slot.global_transform = seat.global_transform
	var v := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if v != null:
		v.visible = false


func get_cartridge_insert_direction() -> Vector3:
	return Vector3.DOWN


## ONE socket, and it is not composite: an HVC-001's rear panel carries AC
## ADAPTER, TV/GAME, CH1/CH2 and RF SWITCH, and nothing else. Everything the
## machine puts out goes down that one coax to the RXR-003 switch box and into
## the set's aerial socket.
##
## Declared as VIDEO because that is the channel an RF feed resolves as
## throughout the room -- the NES's own RF OUT says the same thing, and what a
## television treats it as is decided by the SOCKET the far end lands in. Listing
## a channel at all is also what stops the cabinet spawning a captive composite
## lead, which this machine has none of.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO]


## Seated on the marker the scene authors, which carries its basis as well as its
## place, and renamed: a save records a cord by the socket's NAME, and this hole
## is the RF out rather than a composite video jack. The NES calls its own the
## same thing, so a lead reads the same on either machine.
func configure_av_ports(ports: Array) -> void:
	if ports.is_empty():
		return
	var port := ports[0] as Node3D
	var seat := get_node_or_null("Rear/RfSeat") as Node3D
	if port == null or seat == null:
		return
	port.name = "RfOut"
	# The machine's whole output: an HVC-001 has no audio socket, so without this
	# it would be silent however it was wired.
	(port as RcaPort).rf_feed = true
	port.global_transform = seat.global_transform


## No derived plate. It reads "AV OUT" over a jack it calls "VIDEO", and this
## machine has neither: there is no composite socket to be a VIDEO one, and what
## leaves here is an RF feed. The scene prints "RF OUT" on the panel's own black
## strip instead, above the socket, where the real one is silk-screened.
func configure_av_legend(legend: AvLegend) -> void:
	if legend != null:
		legend.hide()


## The scene prints FAMILY COMPUTER on the front of the deck, so the cabinet's
## own nameplate would sit on top of it.
func prints_own_name() -> bool:
	return true


## A cartridge system: the save is on the cartridge, and this shell has no card
## slot whatever a descriptor might say.
func card_slot_count() -> int:
	return 0
