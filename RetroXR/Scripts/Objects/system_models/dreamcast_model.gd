## RetroSystemModelDreamcast — the white Sega Dreamcast (HKT-3000).
##
## Wires POWER and OPEN, the orange power lens, the sprung disc lid, the disc seat
## on the spindle, the four controller ports and the AV OUT socket. The Dreamcast
## has no RESET button and no console memory card slot — saves live on the VMU in
## the pad — so the cabinet's reset widget is hidden and no card slot is offered.
##
## Every position is READ OFF THE SHELL. Tools/glb/prepare_dreamcast.py splits the
## artist's single Buttons mesh into PowerButton / OpenButton, origins the Lid on
## its hinge, and exports empty markers at each connector mouth — ControllerPort1..4
## on the front plate and AvOut on the back — so nothing here is a hand-measured
## constant that rots when the asset is re-exported. It is also where the port
## plate was centred on the case's front opening; see its header.
##
## The lid follows playstation_model.gd exactly: its node's origin IS the hinge and
## it opens on NEGATIVE local X, so the spring hinge turns a hidden driver frame and
## the angle is mirrored onto the lid. Read that file's _setup_lid note before
## changing anything here — the driver's origin and yaw are both load-bearing.
class_name RetroSystemModelDreamcast
extends RetroSystemModel

const _MODEL_PATH := "res://imported-assets/consoles/dreamcast/dreamcast_console.glb"
const _AV_PORT_SCENE := "res://Scenes/Objects/system_models/dreamcast/dc_av_port.tscn"

## The artist's own lid swings up 70 degrees on its hinge arms before the gear
## tops out against the case; measured on the asset, not taken from a photograph.
const _LID_OPEN_DEG := 70.0
const _LID_ANIM_TIME := 0.38

## The caps are domes sitting in wells; 1.5 mm reads as a press and stays clear of
## the well floor.
const BUTTON_DEPRESS_DEPTH := 0.0015

## Orange, the colour of the real lens when the machine is on. The shell's own
## PowerLED material is a dark amber: the same lens, unlit.
const LED_COLOR := Color(1.0, 0.45, 0.08)
const LED_ENERGY := 0.0000288

var _glb: Node3D = null
var _power_button: VRButton = null
var _lid: Node3D = null
var _lid_driver: Node3D = null
var _lid_hinge: VRSpringLatchedHinge = null
var _lid_amount: float = 0.0
var _lid_tween: Tween = null
var _disc_slot: Node3D = null


func _ready() -> void:
	var baked := get_node_or_null("Shell") as Node3D
	if baked != null:
		_glb = baked
	else:
		if not ResourceLoader.exists(_MODEL_PATH):
			push_warning("DreamcastModel: %s missing — using placeholder box" % _MODEL_PATH)
			var host := get_parent()
			if host:
				var body := host.get_node_or_null("SystemBody") as MeshInstance3D
				if body:
					body.show()
			return
		var scene := load(_MODEL_PATH) as PackedScene
		if scene == null:
			push_warning("DreamcastModel: failed to load %s" % _MODEL_PATH)
			return
		_glb = scene.instantiate() as Node3D
		# MUST be "Shell" — see playstation_model.gd and has_baked_shell().
		_glb.name = "Shell"
		add_child(_glb)

	_hide_seat_previews()

	_lid = _glb.find_child("Lid", true, false) as Node3D
	if _lid != null:
		_setup_lid()

	_power_light_mesh = _glb.find_child("PowerLED", true, false) as MeshInstance3D
	if _power_light_mesh != null:
		prep_power_light(LED_COLOR, LED_COLOR, LED_ENERGY, 1.0)
		set_power_light(false)


func _mesh(part_name: String) -> MeshInstance3D:
	return _glb.find_child(part_name, true, false) as MeshInstance3D if _glb != null else null


func _marker(marker_name: String) -> Node3D:
	return _glb.find_child(marker_name, true, false) as Node3D if _glb != null else null


func _mesh_center(mesh_name: String) -> Vector3:
	var m := _mesh(mesh_name)
	return (m.global_transform * m.get_aabb().get_center()) if m != null else global_position


func get_controller_port_count() -> int:
	return 4


## Saves are on the VMU, which goes in the PAD (VmuPort). The console has no slot,
## and saying 0 rather than -1 is what stops the descriptor offering one.
func card_slot_count() -> int:
	return 0


## OPEN is modelled and a widget is mounted on it, as on the PlayStation.
func has_eject_button() -> bool:
	return true


# --- buttons ----------------------------------------------------------------

## POWER latches in, OPEN is momentary. Both caps sit on the top face and press
## straight down, so the depress axis is the model's own -Y.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	_power_button = power_btn
	# No reset on a Dreamcast, and the shell models none: hide the cabinet's rather
	# than leave a grey box and a floating label on the case.
	if reset_btn != null:
		reset_btn.visible = false
		reset_btn.set_deferred("monitoring", false)
	if _glb == null:
		return
	var into_face: Vector3 = -global_transform.basis.y.normalized()
	for pair: Array in [[power_btn, "PowerButton"], [eject_btn, "OpenButton"]]:
		var btn: VRButton = pair[0]
		if btn == null:
			continue
		btn.depress_depth = BUTTON_DEPRESS_DEPTH
		btn.set_latched_pressed(false)
		var cap := _mesh(String(pair[1]))
		if cap == null:
			push_warning("DreamcastModel: %s missing from the shell" % pair[1])
			continue
		btn.set_button_mesh(cap)
		btn.global_position = _mesh_center(String(pair[1]))
		btn.set_depress_axis_world(into_face)
		var lbl := btn.get_node_or_null("ButtonLabel") as Label3D
		if lbl != null:
			lbl.hide()


func on_power_on() -> void:
	super()
	if _power_button != null:
		_power_button.set_latched_pressed(true)
	set_power_light(true)


func on_power_off() -> void:
	super()
	if _power_button != null:
		_power_button.set_latched_pressed(false)
	set_power_light(false)


# --- disc lid ---------------------------------------------------------------

## See playstation_model.gd _setup_lid: a hidden driver frame at the hinge, yawed
## half a turn, is what the spring hinge turns; its angle is mirrored onto the lid.
func _setup_lid() -> void:
	_lid_driver = Node3D.new()
	_lid_driver.name = "LidDriver"
	add_child(_lid_driver)
	_lid_driver.transform = Transform3D(Basis(Vector3.UP, PI), to_local(_lid.global_position))

	var hinge := VRSpringLatchedHinge.new()
	hinge.name = "LidHinge"
	hinge.target = _lid_driver
	hinge.min_deg = 0.0
	hinge.max_deg = _LID_OPEN_DEG
	hinge.start_closed = true
	hinge.grip_engages = true
	hinge.collision_layer = 1 | (1 << 20)

	var ab: AABB = _lid_aabb()
	hinge.engage_radius = clampf(maxf(ab.size.x, ab.size.z) * 0.35, 0.03, 0.09)
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# The free, front half of the lid only, so a reach for it is not also the hinge.
	box.size = Vector3(ab.size.x * 0.8, maxf(ab.size.y, 0.012) + 0.012, ab.size.z * 0.5)
	col.shape = box
	hinge.add_child(col)
	_lid.add_child(hinge)
	hinge.global_position = Vector3(ab.get_center().x,
		ab.position.y + ab.size.y, ab.position.z + ab.size.z * 0.75)
	hinge.place_hint(Vector3(0.0, 0.02, 0.0))
	hinge.rotation_changed.connect(_on_lid_swung)
	_lid_hinge = hinge


func _lid_aabb() -> AABB:
	var acc := AABB()
	var first := true
	for n in [_lid] + _lid.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.visible:
			var ab: AABB = mi.global_transform * mi.get_aabb()
			acc = ab if first else acc.merge(ab)
			first = false
	return acc


func _set_lid(amount: float) -> void:
	_lid_amount = clampf(amount, 0.0, 1.0)
	if _lid != null:
		_lid.rotation.x = deg_to_rad(-_LID_OPEN_DEG * _lid_amount)


func _tween_lid(to: float) -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.tween_method(_set_lid, _lid_amount, to, _LID_ANIM_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The hand swung the lid. Reports both directions to the host, gated on the latch —
## see playstation_model.gd _on_lid_swung for why OPEN goes dead otherwise.
func _on_lid_swung(deg: float) -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_set_lid(deg / _LID_OPEN_DEG)
	if _disc_slot != null:
		_disc_slot.enabled = _lid_amount > 0.5
	if _lid_hinge != null:
		var host := get_parent()
		if host != null and host.has_method("lid_reports_open"):
			host.lid_reports_open(not _lid_hinge.is_latched_closed(), _lid_hinge)


func has_spring_latched_lid() -> bool:
	return _lid_hinge != null


## OPEN pressed: release the latch and let the spring take the lid up.
func play_open() -> void:
	if _lid_hinge != null:
		_lid_hinge.open()
	_tween_lid(1.0)
	if _disc_slot != null:
		_disc_slot.enabled = true


func play_close() -> void:
	if _lid_hinge != null:
		_lid_hinge.latch_closed()
	_tween_lid(0.0)
	if _disc_slot != null:
		_disc_slot.enabled = false


func get_lid_angle_deg() -> float:
	return _lid_amount * _LID_OPEN_DEG


func set_lid_angle_deg(open_deg: float) -> void:
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	var amount := clampf(open_deg / _LID_OPEN_DEG, 0.0, 1.0)
	_set_lid(amount)
	if _lid_hinge != null:
		_lid_hinge.set_state_remote(_LID_OPEN_DEG * amount, amount <= 0.5, false)
	if _disc_slot != null:
		_disc_slot.enabled = amount > 0.5


func is_lid_open() -> bool:
	return _lid_amount > 0.5


# --- disc -------------------------------------------------------------------

## The disc rests on the SpindlePlate's top face, centred on its axis; the asset
## origins the plate there, so its position is the axis.
func configure_cartridge_slot(slot: Node3D) -> void:
	_disc_slot = slot
	var seat := _seat_marker("DiscSeat")
	if seat != null:
		slot.global_transform = seat.global_transform
	else:
		var plate := _mesh("SpindlePlate")
		if plate != null:
			var ab: AABB = plate.global_transform * plate.get_aabb()
			var axis := plate.global_position
			slot.global_position = Vector3(axis.x, ab.position.y + ab.size.y, axis.z)
			slot.global_basis = global_transform.basis.orthonormalized()
	var slot_visual := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if slot_visual != null:
		slot_visual.hide()
	slot.enabled = _lid_amount > 0.5


func get_cartridge_insert_direction() -> Vector3:
	return -global_transform.basis.y.normalized()


## The hub stands in the disc's centre hole, so it turns with the platter. Both
## parts are origined on the spin axis by prepare_dreamcast.py.
func spin_disc_mechanism(radians: float) -> void:
	for part_name in ["Spindle", "SpindlePlate"]:
		var m := _mesh(part_name)
		if m != null:
			m.rotate_object_local(Vector3.UP, radians)


# --- controller ports -------------------------------------------------------

## Seated on the ControllerPort markers — each at its socket's mouth on the plate
## face, which is where a plug's mating face belongs. Rolled 180 about Z, not
## yawed, for the SnapGrabPoint flip playstation_model.gd explains.
func configure_controller_ports(port_zones: Array) -> void:
	for i in range(port_zones.size()):
		var zone: Node3D = port_zones[i]
		var mouth := _marker("ControllerPort%d" % (i + 1))
		if mouth == null:
			continue
		zone.position = to_local(mouth.global_position)
		zone.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	hide_port_placeholders(port_zones)


# --- A/V --------------------------------------------------------------------

## One socket, Sega's own AV OUT, carrying picture and both audio channels.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO, RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]


func av_ports_are_multi_way() -> bool:
	return true


func av_multi_port_scene() -> String:
	return _AV_PORT_SCENE


## Seated on the AvOut marker, basis and all. The marker is the N64 AvSeat's turn
## (R_y 180: +Z out of the back face, +Y up), which is what keeps a KEYED tongue
## the right way up — R_x 180 would also point out of the back and roll the key.
func configure_av_ports(ports: Array) -> void:
	var mouth := _marker("AvOut")
	if ports.is_empty() or mouth == null:
		return
	(ports[0] as Node3D).global_transform = mouth.global_transform


func configure_cable_attach(attach_point: Node3D) -> void:
	var mouth := _marker("AvOut")
	if mouth != null:
		attach_point.global_position = mouth.global_position
	# The back panel faces -Z and a rope leaves along its own -Z: identity trails it
	# straight out of the back.
	attach_point.rotation = Vector3.ZERO


# --- placement ---------------------------------------------------------------

## The measured shell: 190.1 x 80.2 x 195.2 mm.
func configure_collision(host: Node3D) -> void:
	var box := Vector3(0.190, 0.080, 0.195)
	var pos := Vector3(0.0, 0.040, 0.0)
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col != null and col.shape is BoxShape3D:
			col.shape = col.shape.duplicate()
			(col.shape as BoxShape3D).size = box
			col.position = pos
