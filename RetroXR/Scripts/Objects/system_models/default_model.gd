## RetroSystemModelDefault — placeholder model used when no system-specific GLB exists.
## Manages the placeholder visuals already in system.tscn (colored button boxes,
## slot cylinder, port recesses, etc.) so system.gd never needs to know about them.
class_name RetroSystemModelDefault
extends RetroSystemModel

## Loaded here rather than in build_serial_port so the cost is paid once per
## build of the script, not once per console spawned.
const SERIAL_PORT_SCENE := preload("res://Scenes/Objects/cables/psx_link_port.tscn")
## A Saturn's is its Communication Connector, which takes a Saturn lead and
## nothing else -- a different plug group, so a PlayStation lead cannot seat.
const SATURN_LINK_PORT_SCENE := preload("res://Scenes/Objects/cables/saturn_link_port.tscn")

var _power_btn: VRButton = null
var _reset_btn: VRButton = null
## The hinged disc well, on a console that has one.
var _lid_bay: ProceduralDiscBay = null


## Nothing here draws a console — this model dresses the box system.tscn already
## carries. So the cabinet keeps that box, and this model draws the disc
## mechanism to match it.
func brings_own_body() -> bool:
	return false


## The disc pod, shelf and slit are measurements of the placeholder box, so they
## are this model's geometry and not the cabinet's. Every dimension lives in
## ProceduralDiscBay.
func build_disc_bay(host: Node3D, slot: Node3D, systemid: String, front: bool,
		on_lid_swung: Callable) -> ProceduralDiscBay:
	var bay := ProceduralDiscBay.build_tray(host, slot, systemid, front, on_lid_swung)
	if not front:
		_lid_bay = bay
	return bay


## A lid over the middle of the roof leaves nowhere there to bolt a unit on, so
## the socket goes into the cartridge slot behind the lid, where a Sega Saturn
## takes its Backup RAM Cartridge. Sized to the largest unit that mounts there.
func configure_expansion_socket(socket: Node3D) -> void:
	if _lid_bay == null or not (socket is XRToolsSnapZone):
		return
	var card := Vector3.ZERO
	for id: String in ExpansionCatalog.ids_for_host(str(socket.get_parent().get("systemid"))):
		if ExpansionCatalog.mount_of(id) == ExpansionCatalog.MOUNT_ABOVE:
			card = card.max(ExpansionCatalog.size_of(id))
	_lid_bay.seat_rear_slot(socket as XRToolsSnapZone, card)


func build_disc_slit(host: Node3D, systemid: String) -> void:
	ProceduralDiscBay.build_slit(host, systemid)


## The serial socket, on the back panel beside the A/V row.
##
## Asked of SystemInfo rather than named here, so this is the same switch that
## shows the memory-card slot: a console either has the socket or it does not,
## and that is a fact about the hardware rather than about this box.
##
## Placed at x = 0.045 against the A/V row's 0.082 upward. The 37 mm gap is what
## the number is for: a 21 mm shell and a phono plug reached for at the same time
## should not be fighting over the same handful of panel.
##
## Not an attempt at the real console's panel order. This box is the stand-in
## every machine without a model of its own wears, and it is not a PlayStation
## shape to begin with; a shell that draws its own back panel puts the socket
## where the mould actually has it by overriding this.
##
## Same turn as configure_av_ports uses -- 180 degrees about X, so the socket's
## local +Z points out of the panel, which is where a plug arrives from -- but
## NOT the same z, and the difference is the whole of it. A port sits where the
## seated plug's ORIGIN belongs, and the two connectors put their origin in
## different places: a phono plug's is 10 mm out from the panel with its barrel
## reaching back to it, so rca_port pushes its jack back by that same 10 mm to
## land the flange on the panel. This connector's origin is its mating face,
## which stops about a millimetre proud. Copying the phono row's -0.135 left the
## socket hanging 10 mm off the back of the console with the plug's nose ending
## 3 mm short of it -- close enough to read as seated in a render, which is why
## it took a measurement rather than a look.
func build_serial_port(host: Node3D, systemid: String) -> void:
	var info := SystemInfo.for_system(systemid)
	if info == null or not info.serial_port:
		return
	var scene: PackedScene = SATURN_LINK_PORT_SCENE if systemid == "saturn" else SERIAL_PORT_SCENE
	var port := scene.instantiate() as Node3D
	if port == null:
		return
	host.add_child(port)
	port.position = Vector3(0.045, 0.0, -0.126)
	port.rotation = Vector3(PI, 0.0, 0.0)


func get_controller_port_count() -> int:
	return 4


## Sockets rather than a captive lead, the same three the decks wear: this box
## stands in for console hardware, and console hardware has A/V out on the back.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO, RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]


## Lay them across the back panel of the 0.3 x 0.1 x 0.25 box, on 18 mm centres —
## the spacing the NES moulds and the decks now use.
##
## Local, not global: this model has no meshes to measure against (that is what
## makes it the primitive one), and the ports are already children of the system.
## Turned 180 degrees about X so each socket's local +Z points out of the back,
## which is where a plug arrives from.
func configure_av_ports(ports: Array) -> void:
	for i in ports.size():
		var port: Node3D = ports[i]
		# Centred on x = 0.1, where the captive lead's attach point used to sit.
		port.position = Vector3(0.082 + 0.018 * float(i), 0.0, -0.135)
		port.rotation = Vector3(PI, 0.0, 0.0)


# START/STOP label + color toggling is owned by system.gd
# (_update_power_button_visual) so every model gets it, including bespoke ones
# that override on_power_on/off for their own visuals.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, _eject_btn: VRButton) -> void:
	_power_btn = power_btn
	_reset_btn = reset_btn
	_power_btn.set_color(Color(0.0, 1.0, 0.0))
