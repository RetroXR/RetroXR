## RetroSystemModelNeoGeoConsole — the Neo Geo MVS, consolized.
##
## A rectangular box that takes the MVS arcade cassettes (the same cartridges the MVS cabinet takes)
## and has what a home console has: two controller ports and POWER and RESET on the front, and the
## picture and sound out of the back on three phono jacks, like the SNES. No SNK ever sold one: it is
## what the community builds round an MVS board (kits such as the Orthros MCS-01), and its shape is
## no standard, so this is a plausible one: dark, 340 x 220 x 60 mm, the cassette standing in a slot
## on the roof. The official home machine was the AES, which takes a different cartridge.
##
## Everything is authored in the scene (Tools/gen/gen_neogeo_console.gd): the seats the ports, the
## buttons, the jacks and the cartridge slot go on are markers, and this model puts the system's
## own parts on them, as the N64's does. Origin on the floor at the centre of the base, front +Z.
class_name RetroSystemModelNeoGeoConsole
extends RetroSystemModel

## The case: width x height x depth.
const SIZE := Vector3(0.34, 0.06, 0.22)


## The case is drawn here, so the cabinet drops its own 0.3 x 0.1 x 0.25 box.
func brings_own_body() -> bool:
	return true


func get_controller_port_count() -> int:
	return 2


func port_count_is_fixed() -> bool:
	return true


## With the box hidden, its collision has to be this case's or a hand grabs 300 x 100 x 250 mm of air.
func configure_collision(host: Node3D) -> void:
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		col.shape = col.shape.duplicate()
		(col.shape as BoxShape3D).size = SIZE
		col.position = Vector3(0.0, SIZE.y * 0.5, 0.0)


func configure_controller_ports(port_zones: Array) -> void:
	for i in port_zones.size():
		var zone := port_zones[i] as Node3D
		var seat := get_node_or_null("Front/PortSeat%d" % (i + 1)) as Node3D
		if zone != null and seat != null:
			zone.global_transform = seat.global_transform
	hide_port_placeholders(port_zones.slice(get_controller_port_count()))


func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	super(power_btn, reset_btn, eject_btn)
	_seat_button(power_btn, "Front/PowerSeat")
	_seat_button(reset_btn, "Front/ResetSeat")


func _seat_button(btn: Node3D, seat_path: String) -> void:
	var seat := get_node_or_null(seat_path) as Node3D
	if btn == null or seat == null:
		return
	btn.global_transform = seat.global_transform
	btn.scale = Vector3(0.45, 0.45, 0.45)


## Picture and stereo sound on three phono jacks, which is what the generic lead fits.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO, RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]


## The jacks go on the markers the scene authored, each turned so its +Z points out of the back.
func configure_av_ports(ports: Array) -> void:
	for i in ports.size():
		var port := ports[i] as Node3D
		var seat := get_node_or_null("Rear/AvSeat%d" % (i + 1)) as Node3D
		if port != null and seat != null:
			port.global_transform = seat.global_transform


## The cassette stands in the slot on the roof, label to the front.
func configure_cartridge_slot(slot: Node3D) -> void:
	var seat := get_node_or_null("CartSeat") as Node3D
	if seat != null:
		slot.global_transform = seat.global_transform
	var v := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if v != null:
		v.visible = false


## Under the ports on the front, clear of the numbers above them.
func name_label_placement() -> Dictionary:
	return {"upright": true, "v_center": 0.085, "h_frac": 0.10}
