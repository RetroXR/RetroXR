## RetroSystemModelGenesis — the Sega Genesis / Mega Drive, Model 2 (MK-1631).
##
## Drives Zerescas's Sketchfab shell (see LICENSE-genesis-console.txt), prepared by
## Tools/glb/prepare_genesis.py: the GENESIS badge and both SEGA marks are painted
## out, the two caps on the front control strip are split off as ButtonPower (the
## player's left) and ButtonReset, and the slot's two dust flaps carry their hinge
## as their origin.
##
## Wires POWER and RESET, the two front pad ports, the top cartridge slot and the
## A/V lead. Both buttons are push caps on the Model 2, not slides: POWER latches
## in, RESET is momentary. The rear A/V OUT is Sega's own 9-pin socket, which no
## lead in the room fits yet, so this console keeps the captive lead the Genesis
## has always had here — it now leaves from that socket.
##
## No eject: a Genesis cart pulls straight up out of the slot.
class_name RetroSystemModelGenesis
extends RetroSystemModel

const _MODEL_PATH := "res://imported-assets/consoles/genesis/genesis_console.glb"
const BUTTON_DEPRESS_DEPTH := 0.0018

var _glb: Node3D = null
var _power_button: VRButton = null


func _ready() -> void:
	var baked := get_node_or_null("Shell") as Node3D
	if baked != null:
		_glb = baked
	else:
		if not ResourceLoader.exists(_MODEL_PATH):
			push_warning("GenesisModel: %s missing — using placeholder box" % _MODEL_PATH)
			var host := get_parent()
			if host:
				var body := host.get_node_or_null("SystemBody") as MeshInstance3D
				if body:
					body.show()
			return
		var scene := load(_MODEL_PATH) as PackedScene
		if scene == null:
			push_warning("GenesisModel: failed to load %s" % _MODEL_PATH)
			return
		_glb = scene.instantiate() as Node3D
		# MUST be "Shell" — has_baked_shell() looks for it, and it is what keeps a
		# SystemNameLabel off a console that carries its own moulding.
		_glb.name = "Shell"
		add_child(_glb)
	# prepare_genesis.py exports the shell centred on its footprint and resting on
	# y = 0, so every constant below is in the GLB's own frame and no re-centre runs.


func _shell_mesh(mesh_name: String) -> MeshInstance3D:
	return _glb.find_child(mesh_name, true, false) as MeshInstance3D if _glb != null else null


func _mesh_center(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.get_aabb().get_center()


func get_controller_port_count() -> int:
	return 2


func card_slot_count() -> int:
	return 0


# --- buttons ----------------------------------------------------------------------

## Both caps are pressed straight down into the control strip, which is level
## where they sit (the shell's top is 31.6 mm either side of both, measured).
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	if eject_btn != null:
		eject_btn.set_active(false)
	_power_button = power_btn
	var down: Vector3 = -global_transform.basis.y.normalized()
	for pair: Array in [[power_btn, "ButtonPower"], [reset_btn, "ButtonReset"]]:
		var btn: VRButton = pair[0]
		if btn == null:
			continue
		btn.depress_depth = BUTTON_DEPRESS_DEPTH
		btn.set_latched_pressed(false)
		var cap := _shell_mesh(pair[1])
		if cap != null:
			btn.set_button_mesh(cap)   # also hides the placeholder box
			btn.global_position = _mesh_center(cap)
			btn.set_depress_axis_world(down)
		var lbl := btn.get_node_or_null("ButtonLabel") as Label3D
		if lbl != null:
			lbl.hide()


func on_power_on() -> void:
	super()
	if _power_button != null:
		_power_button.set_latched_pressed(true)


func on_power_off() -> void:
	super()
	if _power_button != null:
		_power_button.set_latched_pressed(false)


# --- cartridge --------------------------------------------------------------------

## The slot, measured off the shell: the two flaps close a 109 x 18 mm mouth at
## z = -41 .. -23 mm whose top sits 36.5 mm up; the edge connector under them
## tops out at 28 mm. A cart stands on the connector with its label to the front,
## so its bottom edge is 2 mm above that and the rest stands out of the slot.
const _SLOT_CENTRE_Z := -0.0319
const _CART_BOTTOM_Y := 0.030

## How far each flap swings down, in degrees, once a cart is in. The pair meet in
## the middle of the mouth and fold into the slot about their outer edges, so the
## front one turns about -X and the rear one about +X.
const _FLAP_OPEN_DEG := 80.0
const _FLAP_SWING_SEC := 0.12

var _flap_tween: Tween = null


func cart_seat_transform() -> Transform3D:
	var h: float = MediaDimensions.cart_size("genesis").y
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _CART_BOTTOM_Y + h * 0.5, _SLOT_CENTRE_Z))


func configure_cartridge_slot(slot: Node3D) -> void:
	var seat := find_child("CartSeat", true, false) as Node3D
	if seat != null:
		slot.global_transform = seat.global_transform
	else:
		slot.transform = cart_seat_transform()
	var slot_visual := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if slot_visual:
		slot_visual.hide()


func get_cartridge_insert_direction() -> Vector3:
	return -global_transform.basis.y.normalized()


func play_cartridge_insert(_cartridge: Node3D, _slot: Node3D) -> void:
	_swing_flaps(1.0)


func play_cartridge_eject(_cartridge: Node3D, _slot: Node3D) -> void:
	_swing_flaps(0.0)


func _swing_flaps(open: float) -> void:
	var front := _shell_mesh("SlotFlapFront")
	var rear := _shell_mesh("SlotFlapRear")
	if front == null or rear == null:
		return
	if _flap_tween != null and _flap_tween.is_valid():
		_flap_tween.kill()
	var angle := deg_to_rad(_FLAP_OPEN_DEG) * open
	_flap_tween = create_tween().set_parallel(true)
	_flap_tween.tween_property(front, "rotation:x", -angle, _FLAP_SWING_SEC)
	_flap_tween.tween_property(rear, "rotation:x", angle, _FLAP_SWING_SEC)


# --- controller ports -------------------------------------------------------------

## The two DE-9 sockets on the front face, centred on their own pin rows (five
## over four, 12 mm across): port 1 on the player's left. Measured off the
## shell's pins at x = -/+15.9 mm, y = 15.7 mm; the socket mouth is the shell's
## front face at z = 104 mm, and the plug's pose sits 6 mm inside it like the NES.
const _PORT_POS := [
	Vector3(-0.0159, 0.0157, 0.0985),
	Vector3(0.0159, 0.0157, 0.0985),
]
## Offered at the mouth rather than already inside it.
const _PLUG_PROUD := 0.012


func configure_controller_ports(port_zones: Array) -> void:
	for i in range(port_zones.size()):
		var zone: Node3D = port_zones[i]
		var seat := find_child("PortSeat%d" % (i + 1), true, false) as Node3D
		if seat != null:
			zone.global_transform = seat.global_transform
		elif i < _PORT_POS.size():
			zone.position = _PORT_POS[i]
			# Front-facing: a ROLL of 180 about Z, as on the NES. The plug's
			# SnapGrabPoint carries its own 180 about X, and composed with it the
			# roll sends the connector into the shell with the plug upright.
			zone.rotation_degrees = Vector3(0, 0, 180)
		zone.preview_offset = Vector3(0, 0, _PLUG_PROUD)
	hide_port_placeholders(port_zones)


# --- A/V lead ---------------------------------------------------------------------

## The 9-pin A/V OUT on the rear panel, the round socket beside the DC jack
## (which is 9 mm further toward -X). Measured off its pin cluster.
const _AV_OUT := Vector3(-0.0398, 0.0166, -0.1040)


func configure_cable_attach(attach_point: Node3D) -> void:
	attach_point.position = _AV_OUT
	# The rear faces -Z and VerletRope leaves an attach point along its local -Z,
	# so identity trails the lead straight out of the back.
	attach_point.rotation = Vector3.ZERO


# --- placement --------------------------------------------------------------------

## The shell, measured: 0.220 x 0.043 x 0.210 m on y = 0. Its top is a dome
## (31–38 mm, the slot ring to 43 mm) except for the control strip across the
## front, where the caps stand 35.8 mm high over a 33 mm strip.
##
## Two boxes, as on the 2600: the body to 30 mm everywhere, and the deck above it
## only behind the strip. One box over the lot tops out above both caps and puts
## shell in front of them from every angle.
const BODY_SIZE := Vector3(0.220, 0.030, 0.2104)
const DECK_TOP_Y := 0.037
const DECK_FRONT_Z := 0.055


func configure_collision(host: Node3D) -> void:
	var back := -BODY_SIZE.z * 0.5
	var parts := [
		["", AABB(Vector3(-BODY_SIZE.x * 0.5, 0.0, back), BODY_SIZE)],
		["RearDeck", AABB(Vector3(-BODY_SIZE.x * 0.5, BODY_SIZE.y, back),
			Vector3(BODY_SIZE.x, DECK_TOP_Y - BODY_SIZE.y, DECK_FRONT_Z - back))],
	]
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col == null or not (col.shape is BoxShape3D):
			continue
		var parent := col.get_parent()
		for part in parts:
			var part_name: String = part[0]
			var a: AABB = part[1]
			var target := col
			if not part_name.is_empty():
				target = parent.get_node_or_null(NodePath(part_name)) as CollisionShape3D
				if target == null:
					target = CollisionShape3D.new()
					target.name = part_name
					parent.add_child(target)
			var shape := BoxShape3D.new()
			shape.size = a.size
			target.shape = shape
			target.position = a.get_center()
