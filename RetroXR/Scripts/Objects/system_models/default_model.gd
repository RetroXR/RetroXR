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
## A Jaguar's is its DSP port, where a JagLink lead goes.
const JAG_LINK_PORT_SCENE := preload("res://Scenes/Objects/cables/jag_link_port.tscn")
## A PlayStation 2's is its S400 i.LINK socket, where an i.LINK lead goes -- to
## another console or to an i.LINK hub.
const ILINK_PORT_SCENE := preload("res://Scenes/Objects/cables/ilink_port.tscn")
## A Game Gear's EXT connector: the two-ended handheld socket, keyed to the
## Gear-to-Gear cable's own plug family so no other handheld's lead seats in it.
const HANDHELD_LINK_PORT_SCENE := preload("res://Scenes/Objects/cables/link_port.tscn")

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
		if ExpansionCatalog.mount_of(id) == ExpansionCatalog.MOUNT_ABOVE \
				and ExpansionCatalog.socket_of(id).is_empty():
			card = card.max(ExpansionCatalog.size_of(id))
	_lid_bay.seat_rear_slot(socket as XRToolsSnapZone, card)


## A Saturn's Video CD Card goes in flat through the back panel, at the end away
## from the A/V row and the serial socket (x 0.045 and up), with the end of it left
## out as a handle. The real slot is behind the battery door; the box has none.
##
## So does a network adapter, for the same reason: the fat PS2's expansion bay and
## the GameCube's Serial Port 1 (which is really underneath) at the end of the back
## panel clear of the A/V row and the i.LINK socket, its RJ45 on the end left out.
## The base's back-centre would put the PS2's card across the i.LINK plate.
const _BACK_CARD_SOCKETS := ["mpeg_card", "expansion_bay", "serial_port_1"]


func configure_unit_socket(socket_id: String, socket: Node3D) -> void:
	if not _BACK_CARD_SOCKETS.has(socket_id) or not (socket is XRToolsSnapZone):
		super(socket_id, socket)
		return
	ProceduralDiscBay.seat_back_card_slot(socket as XRToolsSnapZone,
		ExpansionCatalog.socket_size(str(socket.get_parent().get("systemid")), socket_id))


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
	var scene: PackedScene = SERIAL_PORT_SCENE
	if systemid == "saturn":
		scene = SATURN_LINK_PORT_SCENE
	elif systemid == "atarijaguar":
		scene = JAG_LINK_PORT_SCENE
	elif systemid == "ps2":
		scene = ILINK_PORT_SCENE
	elif systemid == "gamegear":
		scene = HANDHELD_LINK_PORT_SCENE
	var port := scene.instantiate() as Node3D
	if port == null:
		return
	# Keyed to the Gear-to-Gear cable so no other handheld's lead seats. Before
	# add_child: the socket reads its family in _ready.
	if scene == HANDHELD_LINK_PORT_SCENE:
		(port as LinkPort).connector = "gg_link_plug"
	host.add_child(port)
	port.position = Vector3(0.045, 0.0, -0.126)
	port.rotation = Vector3(PI, 0.0, 0.0)
	# The handheld lead's plug is a 27 mm collider reaching 20 mm BEHIND its
	# origin. In a handheld's thin shell that is harmless; against this solid box
	# it buried the plug 20 mm inside the console's own body, and physics shoved
	# it out again and again -- the cable joined and parted every few frames and
	# never held a bus. So the socket stands 20 mm further out, where the plug's
	# collider just clears the panel.
	if scene == HANDHELD_LINK_PORT_SCENE:
		port.position.z -= 0.020


func get_controller_port_count() -> int:
	return 4


## Sockets rather than a captive lead, the same three the decks wear: this box
## stands in for console hardware, and console hardware has A/V out on the back.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO, RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]


## Platforms whose picture leaves by Nintendo's AV Multi Out, so the box wears that
## socket in place of the phono row and takes the console's own lead, the
## Stereo AV Cable. The Super NES is where Nintendo started using it; the N64's
## model already wears the same socket.
const _MULTI_OUT_PLATFORMS: Array[String] = ["snes"]
const _MULTI_OUT_SCENE := "res://Scenes/Objects/system_models/nintendo_64/n64_av_port.tscn"


## The same three signals either way; only the number of holes differs.
func av_ports_are_multi_way() -> bool:
	return _MULTI_OUT_PLATFORMS.has(_systemid())


func av_multi_port_scene() -> String:
	return _MULTI_OUT_SCENE if av_ports_are_multi_way() else ""


## The cabinet this box dresses, which knows what it is standing in for.
func _systemid() -> String:
	var host := get_parent()
	return str(host.get("systemid")) if host != null else ""


## Lay them across the back panel of the 0.3 x 0.1 x 0.25 box, on 18 mm centres —
## the spacing the NES moulds and the decks now use.
##
## Local, not global: this model has no meshes to measure against (that is what
## makes it the primitive one), and the ports are already children of the system.
## Turned 180 degrees about X so each socket's local +Z points out of the back,
## which is where a plug arrives from.
##
## A Multi Out goes where the middle phono jack would, turned about Y rather than
## X, as the N64 seats it, so its key stays on top. Its zone is the plug's shroud
## face, 2 mm proud of the panel (n64_av_port.tscn), and the panel is at z -0.125.
func configure_av_ports(ports: Array) -> void:
	if av_ports_are_multi_way():
		if not ports.is_empty():
			(ports[0] as Node3D).transform = Transform3D(Basis(Vector3.UP, PI),
				Vector3(0.1, 0.0, -0.127))
		return
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
