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
## The pads are DETACHABLE here and hardwired on the hardware. That concession is
## what lets the existing controller-port snap zones serve, and it is why the two
## ports are on the front face under the wells -- where the real cords emerge --
## rather than being no ports at all.
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
func configure_controller_ports(port_zones: Array) -> void:
	for i in port_zones.size():
		var zone := port_zones[i] as Node3D
		if zone == null:
			continue
		var seat := get_node_or_null("Front/PortSeat%d" % (i + 1)) as Node3D
		if seat != null:
			zone.global_transform = seat.global_transform


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


## No A/V sockets at all, which is the difference from the NES beside it: an
## HVC-001's picture and sound leave on a hardwired RF pigtail. Returning nothing
## is what makes the cabinet keep its captive lead AND keep that lead's plug
## visual shown, since there is no jack for it to be blocking.
##
## The lead the cabinet gives is a composite one and the real pigtail ends in an
## RF plug that goes to a modulator box. That is not modelled: what is being said
## here is that this machine has no socket a player could plug anything into.
func av_port_channels() -> Array:
	return []


## Out of the back, on the left. The cord leaves an attach point stiffly along
## its local -Z, so the rear normal is what aims it.
func configure_cable_attach(attach_point: Node3D) -> void:
	var seat := get_node_or_null("Rear/CableSeat") as Node3D
	if seat != null:
		attach_point.global_position = seat.global_position
	aim_cable_exit(attach_point, Vector3(0, 0, -1))


## The scene prints FAMILY COMPUTER on the front of the deck, so the cabinet's
## own nameplate would sit on top of it.
func prints_own_name() -> bool:
	return true


## A cartridge system: the save is on the cartridge, and this shell has no card
## slot whatever a descriptor might say.
func card_slot_count() -> int:
	return 0
