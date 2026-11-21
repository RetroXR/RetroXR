## RetroSystemModelWiiU — the Wii U (WUP-001), lying flat: 172 wide x 46 high x
## 268.5 deep on 2 mm feet, built in code in RetroXR-models' frame
## (nintendo/wiiu/console: x across the front, y up from the underside, z out of the
## front), so the detailed model can take its place later with the same marker names.
##
## What it draws is a stand-in: the white case, the disc slot's dark mouth, POWER,
## EJECT and SYNC on the front with their lamps, the flap over the SD and USB bay,
## and on the back the sockets that do something here -- HDMI OUT (HdmiPort, picture
## and sound), AV MULTI OUT (the Wii's lead: the Wii U kept the connector), SENSOR
## BAR and the AC ADAPTER's DC IN (DCIn, a mouth SystemPower seats the jack in). The
## USB sockets are drawn, not wired.
##
## Two pictures leave this console, the TV's and the GamePad's. Cemu packs them
## into one frame and says where each is (RETRO_ENVIRONMENT_SET_VIDEO_VIEWS):
## live_video_rect() hands the TV its window, gamepad_rect() the GamePad its own.
## Pairing, the ports and the remotes' ids are WiiLink's (wii_link.gd).
class_name RetroSystemModelWiiU
extends RetroSystemModelDefault

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## The case, metres: 172 x 46 x 268.5, standing on 2 mm feet.
const BODY := Vector3(0.172, 0.046, 0.2685)
const FEET := 0.002
const FRONT_Z := 0.13425
const BACK_Z := -0.13425

const WHITE := Color(0.93, 0.93, 0.915)
const DARK := Color(0.05, 0.05, 0.055)
const FLAP := Color(0.86, 0.86, 0.85)
const SYNC_RED := Color(0.45, 0.06, 0.08)
const LED_STANDBY := Color(0.80, 0.12, 0.10)
const LED_RUNNING := Color(0.20, 0.55, 0.95)
const LEGEND := Color(0.55, 0.55, 0.54)

## The views Cemu packs: screen 0 the TV, screen 1 the GamePad.
const SCREEN_TV := 0
const SCREEN_GAMEPAD := 1

## As the Wii's: a Multi Out seats 2 mm proud, the sensor bar plug 1.5.
const AV_MULTI_PROUD := 0.002
const SENSOR_PROUD := 0.0015

## The front flap over the SD slot and the two front USB sockets: hinged along its
## bottom edge, it folds down; past FLAP_OPEN_AT the sockets behind it take a plug.
const FLAP_OPEN_DEG := 80.0
const FLAP_OPEN_AT := 30.0
## The four USB-A sockets (Connectors.USB_PORTS), in order: the two on the back, upper
## first, then the two behind the flap, left first. Markers of these names, a socket's
## +Z out of its panel.
const USB_MARKERS := ["UsbRear1Anchor", "UsbRear2Anchor", "UsbFront1Anchor", "UsbFront2Anchor"]

var _power_cap: MeshInstance3D = null
var _power_led: MeshInstance3D = null
var _disc_led: MeshInstance3D = null
var _eject_cap: MeshInstance3D = null
var _sync_cap: MeshInstance3D = null
var _reset_cap: MeshInstance3D = null
var _disc_seat: Marker3D = null
var _av_seat: Marker3D = null
var _sensor_seat: Marker3D = null
var _hdmi_seat: Marker3D = null
var _hdmi_port: HdmiPort = null
var _sensor_bar_port: XRToolsSnapZone = null
var _led_mat: StandardMaterial3D = null
var _flap_hinge: VRHinge = null
var _flap_open := false
## The sockets behind the flap, which take a plug only while it is open.
var _front_usb: Array = []

## The views last read, and the geometry serial they were read at.
var _views: Array = []
var _views_serial := -1


func _init() -> void:
	name = "WiiUModel"
	_build_case()
	_build_front()
	_build_back()


func _ready() -> void:
	_build_sensor_bar_port()
	_set_power_led(false)
	_build_flap_hinge()


## Core options this console needs. The remote's aim is the sensor bar's lights
## seen by its camera, which Cemu takes on the pointer indices of its port; the
## GamePad's and the remotes' motion come from the room.
func get_forced_core_options() -> Dictionary:
	return {
		"cemu_wiimote_pointer": "ir",
		"cemu_wiimote_motion": "enabled",
		"cemu_gamepad_motion": "enabled",
		# The GamePad's motion is worked out from its tracked pose: no bias, no noise.
		# The fork's Real Sensors filter would throw slow turns away and learn them as bias.
		"cemu_gamepad_motion_filter": "exact",
	}


func brings_own_body() -> bool:
	return true


## No wired controller sockets: every pad on a Wii U is wireless (WiiLink).
func has_controller_sockets() -> bool:
	return false


func configure_collision(host: Node3D) -> void:
	var box := Vector3(BODY.x, BODY.y + FEET, BODY.z)
	var pos := Vector3(0.0, box.y * 0.5, 0.0)
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col != null and col.shape is BoxShape3D:
			col.shape = col.shape.duplicate()
			(col.shape as BoxShape3D).size = box
			col.position = pos


# --- the two pictures ---------------------------------------------------------

## The TV's window of the packed frame, or null for the whole frame (no views yet,
## or a frontend frame they do not fit).
func live_video_rect(channel: int) -> Variant:
	if channel != 0:
		return null
	return _view_rect(SCREEN_TV)


## The GamePad's window of the frame, or null while Cemu has sent no views.
func gamepad_rect() -> Variant:
	return _view_rect(SCREEN_GAMEPAD)


func _view_rect(screen: int) -> Variant:
	_refresh_views()
	for v: Variant in _views:
		var d := v as Dictionary
		if d != null and int(d.get("screen", -1)) == screen and int(d.get("eye", 0)) != 2:
			return d.get("rect")
	return null


## Read again only when the core says something changed (the views share the
## geometry's serial).
func _refresh_views() -> void:
	var host := get_parent() as RetroSystem
	if host == null:
		return
	var lib: Node = host.get_libretro_node()
	if not is_instance_valid(lib) or not lib.has_method("GetVideoViews"):
		if not _views.is_empty():
			_views = []
		return
	var serial := int(lib.call("GetVideoGeometrySerial"))
	if serial == _views_serial:
		return
	_views_serial = serial
	_views = lib.call("GetVideoViews")
	print("[WiiU] video views: %s" % [str(_views) if not _views.is_empty() else "none, the frame is shown whole"])


# --- the disc slot ------------------------------------------------------------

## Flat through the slot in the front, into the case along -Z.
func configure_cartridge_slot(slot: Node3D) -> void:
	slot.global_transform = _disc_seat.global_transform
	var v := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if v != null:
		v.visible = false


## Half the case's depth: a 120 mm disc ends up in the middle of the drive.
func slot_insert_depth() -> float:
	return BODY.z * 0.5


# --- buttons ------------------------------------------------------------------

## POWER and EJECT onto the front's keys. There is no RESET on a Wii U: that
## button is parked inside the case and switched off.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	_mount_cap(power_btn, _power_cap)
	_mount_cap(eject_btn, _eject_cap)
	if reset_btn != null:
		_mount_cap(reset_btn, _reset_cap)
		reset_btn.set_active(false)
		reset_btn.visible = false


## SYNC on the front, under the flap's left end, where the real one is: it is
## what a GamePad, a remote or a Pro Controller pairs through.
func configure_sync_button(sync_btn: VRButton) -> void:
	_mount_cap(sync_btn, _sync_cap)


func _mount_cap(btn: VRButton, cap: MeshInstance3D) -> void:
	if btn == null or cap == null:
		return
	btn.global_transform = Transform3D(cap.global_transform.basis, cap.global_position)
	btn.depress_depth = 0.0006
	btn.depress_axis = Vector3(0, 0, -1)
	btn.set_button_mesh(cap)
	var lbl := btn.get_node_or_null("ButtonLabel") as Label3D
	if lbl != null:
		lbl.hide()


func on_power_on() -> void:
	super.on_power_on()
	_set_power_led(true)


func on_power_off() -> void:
	super.on_power_off()
	_set_power_led(false)


func _set_power_led(on: bool) -> void:
	if _led_mat == null:
		return
	var c: Color = LED_RUNNING if on else LED_STANDBY
	_led_mat.albedo_color = c
	_led_mat.emission = c
	_led_mat.emission_energy_multiplier = 1.6 if on else 0.9


# --- the back panel -----------------------------------------------------------

func av_ports_are_multi_way() -> bool:
	return true


## The Wii's AV Multi Out: the Wii U kept it, and the Wii's lead fits.
func av_multi_port_scene() -> String:
	return "res://Scenes/Objects/system_models/wii/wii_av_port.tscn"


func configure_av_ports(ports: Array) -> void:
	if ports.is_empty():
		return
	var t: Transform3D = _av_seat.global_transform
	(ports[0] as Node3D).global_transform = Transform3D(
		t.basis, t.origin + t.basis.z.normalized() * AV_MULTI_PROUD)
	_build_hdmi_out()


## HDMI OUT, beside the AV MULTI OUT: a video socket whose sound rides the same plug
## (rf_feed: the set gets the machine's sound unless an audio cord already took it).
## Built here, as the NES builds its RF OUT: the cabinet's A/V row has no slot for a
## second video socket.
func _build_hdmi_out() -> void:
	if _hdmi_port != null:
		return
	_hdmi_port = (load("res://Scenes/Objects/cables/hdmi_port.tscn") as PackedScene).instantiate() as HdmiPort
	_hdmi_port.name = "HdmiOut"
	_hdmi_port.direction = RcaPort.Direction.OUT
	_hdmi_port.rf_feed = true
	add_child(_hdmi_port)
	var t: Transform3D = _hdmi_seat.transform
	# The zone 0.8 mm out of the panel, where a seated plug's overmold face stops
	# (hdmi_port.tscn); its +Z is the marker's, out of the back.
	_hdmi_port.transform = Transform3D(t.basis, t.origin + t.basis.z.normalized() * 0.0008)
	print("[WiiU] HDMI OUT built (picture and sound on one plug)")


## The flap's mount and pivot at `hinge` (its bottom edge, on the front face), the
## pivot returned for the flap's mesh to hang from. VRHinge turns its target about
## the target's PARENT frame's X, so the mount carries the frame and the pivot stays
## at identity (as the Wii's SD door, wii_model.gd).
func _flap_pivot(hinge: Vector3) -> Node3D:
	var mount := Node3D.new()
	mount.name = "FlapMount"
	mount.position = hinge
	add_child(mount)
	var pivot := Node3D.new()
	pivot.name = "FlapPivot"
	mount.add_child(pivot)
	return pivot


## The flap's hinge: a grip on its free (top) edge folds it down, out of the case.
func _build_flap_hinge() -> void:
	var pivot := get_node_or_null("FlapMount/FlapPivot") as Node3D
	if pivot == null or _flap_hinge != null:
		return
	_flap_hinge = VRHinge.new()
	_flap_hinge.name = "FlapGrab"
	_flap_hinge.target = pivot
	_flap_hinge.min_deg = 0.0
	_flap_hinge.max_deg = FLAP_OPEN_DEG
	_flap_hinge.grip_engages = true
	_flap_hinge.engage_radius = 0.04
	pivot.add_child(_flap_hinge)
	_flap_hinge.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, 0.003))
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.008, 0.01)
	col.shape = box
	_flap_hinge.add_child(col)
	_flap_hinge.place_hint(Vector3(0.0, 0.016, 0.004))
	_flap_hinge.rotation_changed.connect(_on_flap_moved)


func _on_flap_moved(deg: float) -> void:
	var open := deg > FLAP_OPEN_AT
	if open == _flap_open:
		return
	_flap_open = open
	print("[WiiU] front flap %s" % ("open" if open else "shut"))
	for zone: XRToolsSnapZone in _front_usb:
		# A socket holding a plug stays live: the flap cannot shut over it.
		if is_instance_valid(zone) and not is_instance_valid(zone.picked_up_object):
			zone.enabled = open


## The four USB-A sockets onto their markers, rolled half round as a front socket is
## (the PS2's), so a plug goes in contacts the same way up; the two behind the flap
## live only while it is open.
func configure_usb_ports(usb_zones: Array) -> void:
	_front_usb.clear()
	for k in mini(usb_zones.size(), USB_MARKERS.size()):
		var zone := usb_zones[k] as XRToolsSnapZone
		var mark := get_node_or_null(str(USB_MARKERS[k])) as Node3D
		if zone == null or mark == null:
			continue
		zone.global_transform = mark.global_transform * Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3.ZERO)
		var recess := zone.get_node_or_null("UsbRecess") as Node3D
		if recess != null:
			recess.hide()
		if str(USB_MARKERS[k]).begins_with("UsbFront"):
			_front_usb.append(zone)
			zone.enabled = _flap_open


func get_sensor_bar_port() -> XRToolsSnapZone:
	return _sensor_bar_port


## The SENSOR BAR socket, the Wii's connector (WiiLink reads what is in it).
func _build_sensor_bar_port() -> void:
	if _sensor_bar_port != null:
		return
	_sensor_bar_port = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	_sensor_bar_port.name = "SensorBarPort"
	_sensor_bar_port.grab_distance = 0.03
	_sensor_bar_port.snap_require = String(SensorBar.PLUG_GROUP)
	add_child(_sensor_bar_port)
	_sensor_bar_port.transform = Transform3D(_sensor_seat.transform.basis,
		_sensor_seat.position + _sensor_seat.transform.basis.z.normalized() * SENSOR_PROUD)
	var jack := MeshInstance3D.new()
	jack.name = "WiiSensorJack"
	jack.mesh = load("res://Scenes/Objects/system_models/wii/wii_sensor_jack.res")
	jack.position = Vector3(0.0, 0.0, -SENSOR_PROUD)
	_sensor_bar_port.add_child(jack)


# --- geometry -------------------------------------------------------------------

func _mat(c: Color, rough := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(node_name: String, size: Vector3, at: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


## A round key or lamp facing out of the front (+Z): a cylinder turned onto its side.
func _disc(node_name: String, diameter: float, depth: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter * 0.5
	mesh.bottom_radius = diameter * 0.5
	mesh.height = depth
	mesh.radial_segments = 20
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	return mi


func _legend(text: String, at: Vector3, back := false) -> void:
	var l := Label3D.new()
	l.name = "Legend_" + text.replace(" ", "")
	l.text = text
	l.font_size = 32
	l.pixel_size = 0.00005
	l.modulate = LEGEND
	l.outline_size = 0
	l.double_sided = false
	l.add_to_group(&"printed_label")
	l.transform = Transform3D(Basis(Vector3.UP, PI) if back else Basis.IDENTITY, at)
	add_child(l)


func _marker(node_name: String, xform: Transform3D) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.transform = xform
	add_child(m)
	return m


func _build_case() -> void:
	var white := _mat(WHITE, 0.25)
	_box("Body", BODY, Vector3(0.0, FEET + BODY.y * 0.5, 0.0), white)
	var foot_mat := _mat(Color(0.75, 0.75, 0.74), 0.6)
	for fx: float in [-0.065, 0.065]:
		for fz: float in [-0.11, 0.11]:
			_box("Foot", Vector3(0.012, FEET, 0.012), Vector3(fx, FEET * 0.5, fz), foot_mat)
	# The parting line round the sides, 26 mm up.
	var seam := _mat(Color(0.82, 0.82, 0.81), 0.5)
	_box("Seam", Vector3(BODY.x + 0.0004, 0.0006, BODY.z + 0.0004), Vector3(0.0, 0.026, 0.0), seam)


func _build_front() -> void:
	var z := FRONT_Z + 0.0003
	var dark := _mat(DARK, 0.8)
	# The disc slot: 130.3 wide, its middle 33.9 up.
	_box("DiscSlot", Vector3(0.1303, 0.0055, 0.0008), Vector3(0.00625, 0.0339, z), dark)
	_disc_seat = _marker("DiscSlotAnchor", Transform3D(Basis.IDENTITY, Vector3(0.00625, 0.0339, FRONT_Z)))
	# The flap over the SD card and the two USB sockets, on its hinge along its bottom
	# edge (_build_flap_hinge): FlapMount at the hinge, FlapPivot turned by it.
	var pivot := _flap_pivot(Vector3(0.01345, 0.0051, FRONT_Z))
	_box("Flap", Vector3(0.0835, 0.0143, 0.0008), Vector3(0.0, 0.00715, 0.0003), _mat(FLAP, 0.3), pivot)
	_marker("UsbFront1Anchor", Transform3D(Basis.IDENTITY, Vector3(0.0219, 0.0141, 0.1273)))
	_marker("UsbFront2Anchor", Transform3D(Basis.IDENTITY, Vector3(0.0422, 0.0141, 0.1273)))
	# POWER: a 9.8 mm disc at x -73.1, 11.2 up, its lamp 8 mm above it.
	_power_cap = _disc("PowerCap", 0.0098, 0.0012, Vector3(-0.0731, 0.0112, FRONT_Z + 0.0006), _mat(WHITE, 0.2))
	_led_mat = StandardMaterial3D.new()
	_led_mat.emission_enabled = true
	_power_led = _disc("PowerLed", 0.0012, 0.0006, Vector3(-0.0731, 0.0192, z), _led_mat)
	# EJECT: a 10 x 4.2 pill, 34 up, the DISC lamp above it.
	_eject_cap = _box("EjectCap", Vector3(0.010, 0.0042, 0.0012), Vector3(-0.0732, 0.034, FRONT_Z + 0.0006), _mat(WHITE, 0.2))
	_disc_led = _disc("DiscLed", 0.0009, 0.0006, Vector3(-0.0732, 0.0416, z), _mat(Color(0.3, 0.55, 0.9), 0.4))
	# SYNC: a maroon dome 3 mm across at x -38.2, 11.4 up.
	_sync_cap = _disc("SyncCap", 0.003, 0.001, Vector3(-0.0382, 0.0114, FRONT_Z + 0.0005), _mat(SYNC_RED, 0.15))
	# Where the cabinet's RESET goes to sleep: inside the case.
	_reset_cap = _box("ResetCap", Vector3(0.002, 0.002, 0.002), Vector3(0.0, 0.02, 0.0), dark)
	_reset_cap.visible = false
	_legend("POWER", Vector3(-0.0731, 0.0044, z))
	_legend("EJECT", Vector3(-0.0734, 0.0286, z))
	_legend("SYNC", Vector3(-0.0380, 0.0044, z))


func _build_back() -> void:
	var z := BACK_Z - 0.0003
	var dark := _mat(DARK, 0.8)
	# Out of the back is -Z: a socket's +Z looks out of its panel.
	var out := Basis(Vector3.UP, PI)
	_av_seat = _marker("AvMultiOutAnchor", Transform3D(out, Vector3(0.0372, 0.0169, BACK_Z)))
	_sensor_seat = _marker("SensorBarAnchor", Transform3D(out, Vector3(0.0374, 0.0301, BACK_Z)))
	# The AC ADAPTER inlet: SystemPower seats the DC jack in this mouth.
	_marker("DCIn", Transform3D(out, Vector3(0.063, 0.0159, BACK_Z)))
	_box("AcInletHousing", Vector3(0.0141, 0.0099, 0.0008), Vector3(0.063, 0.0159, z), _mat(Color(0.95, 0.8, 0.15), 0.4))
	# HDMI OUT and the two USB sockets, drawn only.
	# HDMI OUT (configure_av_ports builds the socket on this marker): its window.
	_hdmi_seat = _marker("HdmiAnchor", Transform3D(out, Vector3(0.0109, 0.0149, BACK_Z)))
	_box("HdmiWindow", Vector3(0.0186, 0.0083, 0.0004), Vector3(0.0109, 0.0149, BACK_Z - 0.0001), dark)
	_box("UsbRear1", Vector3(0.0135, 0.0055, 0.0008), Vector3(-0.059, 0.02375, z), dark)
	_box("UsbRear2", Vector3(0.0135, 0.0055, 0.0008), Vector3(-0.059, 0.01535, z), dark)
	_marker("UsbRear1Anchor", Transform3D(out, Vector3(-0.059, 0.02375, BACK_Z)))
	_marker("UsbRear2Anchor", Transform3D(out, Vector3(-0.059, 0.01535, BACK_Z)))
	# The exhaust grille: three columns of seven slots.
	var grille := _mat(Color(0.7, 0.7, 0.69), 0.6)
	for cx: float in [-0.0099, -0.0233, -0.0367]:
		for r in 7:
			_box("Grille", Vector3(0.0116, 0.0036, 0.0006), Vector3(cx, 0.0424 - 0.0056 * r, z), grille)
	_legend("AC ADAPTER", Vector3(0.064, 0.023, z), true)
	_legend("SENSOR BAR", Vector3(0.0356, 0.0358, z), true)
	_legend("AV MULTI OUT", Vector3(0.042, 0.0255, z), true)
	_legend("HDMI OUT", Vector3(0.0108, 0.0213, z), true)
