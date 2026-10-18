## RetroSystemModelArcadeCabinet — the Generic Arcade Cabinet.
##
## One piece: a screen, coin doors, a control panel per player, front sockets for
## extra controllers and light guns, and a bay behind a lower door where the board (a
## MAME/FBNeo ROM drawn as a JAMMA board) is plugged in. Nothing here is specific to
## one cabinet shape: the model collects the ArcadeModules in its scene by TYPE
## (Scripts/Objects/arcade/, contract version ArcadeProfiles.CONTRACT_VERSION) and
## wires them to the RetroSystem. A different cabinet is a different scene (or a mod's
## row in the registry) honouring the same modules; a new kind of control or bay is a
## new module, not a change to this class. docs/dev/arcade.md has the contract.
##
## In code the cabinet is the machine and the board is its media, the way a handheld
## is its own machine and a cartridge its media: pulling the board powers it off.
class_name RetroSystemModelArcadeCabinet
extends RetroSystemModel

## The cabinet's outer box: width x height x depth to the control panel's front, with
## the origin on the floor at the centre of the base.
const SIZE := Vector3(0.66, 1.80, 0.87)
const SIZE_CENTER := Vector3(0.0, 0.90, 0.035)

var _modules: Array[ArcadeModule] = []
var _screen: ArcadeScreenModule = null
var _bay: ArcadeBayModule = null
var _sockets: ArcadeSocketModule = null
var _controls: Array[ArcadeControlModule] = []
var _coins: Array[ArcadeCoinModule] = []
var _input: ArcadeInput = null
var _marquee_mat: StandardMaterial3D = null
## The pointer slab behind a shut door: off while the door is open.
var _pointer_door: CollisionShape3D = null


func _ready() -> void:
	_modules.clear()
	for n in find_children("*", "ArcadeModule", true, false):
		_modules.append(n as ArcadeModule)
	_controls.clear()
	_coins.clear()
	for m in _modules:
		m.attach(self)
		match m.kind:
			ArcadeProfiles.KIND_SCREEN:
				_screen = m as ArcadeScreenModule
			ArcadeProfiles.KIND_BAY:
				_bay = m as ArcadeBayModule
			ArcadeProfiles.KIND_SOCKETS:
				_sockets = m as ArcadeSocketModule
			ArcadeProfiles.KIND_STICK_BUTTONS:
				_controls.append(m as ArcadeControlModule)
			ArcadeProfiles.KIND_COIN:
				_coins.append(m as ArcadeCoinModule)
	_controls.sort_custom(func(a: ArcadeControlModule, b: ArcadeControlModule) -> bool: return a.player < b.player)
	var marquee := find_child("Marquee", true, false) as MeshInstance3D
	if marquee != null and marquee.mesh != null and marquee.mesh.material is StandardMaterial3D:
		_marquee_mat = marquee.mesh.material as StandardMaterial3D


func _process(delta: float) -> void:
	for m in _modules:
		m.tick(delta)


## The modules of one kind (ArcadeProfiles.KIND_*), for the probe and the tests.
func modules_of_kind(kind: StringName) -> Array[ArcadeModule]:
	var out: Array[ArcadeModule] = []
	for m in _modules:
		if m.kind == kind:
			out.append(m)
	return out


func arcade_input() -> ArcadeInput:
	return _input


# ── what this hardware is ───────────────────────────────────────────────────

func brings_own_body() -> bool:
	return true


func spawns_on_floor() -> bool:
	return true


## Notices float in front of the monitor, PARALLEL to it (the tube is tilted back, so is the
## notice), half a metre off the glass and clear of the cabinet, so none of it is inside the
## geometry. Taken from the screen's own transform, so it follows the model if the monitor moves.
const TOAST_DISTANCE := 0.5


func toast_anchor() -> Variant:
	var screen := _screen.get_screen() if _screen != null else null
	if screen == null:
		return Vector3(0.0, 1.30, 0.85)
	var xf: Transform3D = global_transform.affine_inverse() * screen.global_transform
	var basis := xf.basis.orthonormalized()
	return Transform3D(basis, xf.origin + basis.z * TOAST_DISTANCE)


## The options panel stands to the cabinet's RIGHT at eye height, readable from the front,
## instead of floating above a 1.8 m box where nobody can see it.
func options_panel_anchor(panel_size: Vector2) -> Variant:
	return Vector3(SIZE.x * 0.5 + 0.12 + panel_size.x * 0.5, 1.2, 0.25)


## Picked up by HOLDING the grab on it for one second, ring filling: a cabinet is not
## something to carry off with a stray squeeze or click.
func grab_hold_seconds() -> float:
	return HoldToGrab.DEFAULT_SECONDS


func get_builtin_screen() -> MeshInstance3D:
	return _screen.get_screen() if _screen != null else null


func channel_screens() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _screen != null and _screen.get_screen() != null:
		out.append(_screen.get_screen())
	return out


## The cabinet says how many sockets it has; SystemInfo's native_ports is the
## console's and does not get a vote.
func get_controller_port_count() -> int:
	return _sockets.seat_count() if _sockets != null else 0


func port_count_is_fixed() -> bool:
	return true


func configure_controller_ports(port_zones: Array) -> void:
	if _sockets != null:
		_sockets.seat_zones(port_zones)
	hide_port_placeholders(port_zones)


func configure_cartridge_slot(slot: Node3D) -> void:
	if _bay != null:
		_bay.configure_slot(slot)


func configure_cable_attach(attach_point: Node3D) -> void:
	# A cabinet has no video-out cord: its monitor is part of it.
	attach_point.visible = false


## The generic power button goes inside the bay, beside the board, where the switch
## is on a real cabinet. Reset and open have nothing to do here.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	reset_btn.set_active(false)
	reset_btn.hide()
	eject_btn.set_active(false)
	eject_btn.hide()
	var seat: Node3D = _bay.power_switch_seat() if _bay != null else null
	if seat != null:
		power_btn.global_transform = seat.global_transform
	var lbl := power_btn.get_node_or_null("ButtonLabel") as Label3D
	if lbl != null:
		lbl.hide()


## One box per solid part, leaving the bay open so a board can be carried into it.
## A single box would have kept every hand and board out of the cabinet it plugs into.
func configure_collision(host: Node3D) -> void:
	var boxes: Array[AABB] = [
		AABB(Vector3(-0.33, 0.00, -0.40), Vector3(0.66, 0.10, 0.80)),      # base
		AABB(Vector3(-0.33, 0.10, -0.40), Vector3(0.02, 0.40, 0.80)),      # left of the bay
		AABB(Vector3(0.31, 0.10, -0.40), Vector3(0.02, 0.40, 0.80)),       # right of the bay
		AABB(Vector3(-0.33, 0.10, -0.40), Vector3(0.66, 0.40, 0.02)),      # behind the bay
		AABB(Vector3(-0.33, 0.50, -0.40), Vector3(0.66, 1.30, 0.80)),      # everything above it
		AABB(Vector3(-0.33, 0.78, 0.40), Vector3(0.66, 0.14, 0.07)),       # control panel overhang
	]
	var first := host.get_node_or_null("CollisionShape3D") as CollisionShape3D
	for i in boxes.size():
		var col: CollisionShape3D = first if i == 0 else CollisionShape3D.new()
		if col == null:
			continue
		var shape := BoxShape3D.new()
		shape.size = boxes[i].size
		col.shape = shape
		col.position = boxes[i].get_center()
		if i > 0:
			col.name = "CabinetBox%d" % i
			host.add_child(col)
	_build_pointer_shapes(host)


## What a pointer (the desktop reticle, a laser) hits when it is aimed at the cabinet
## itself. One box over the whole cabinet would hit FIRST, and hide behind its front face
## every door, button and coin slot on it: a ray stops at the nearest thing, and the
## widgets are on the same layer. So these boxes stand BEHIND everything that can be
## operated: the lower block behind the door's back face, the apron behind the sockets,
## the deck and monitor behind the deck's back edge. Pointing at plain panel still
## reaches the cabinet, and pointing at a control reaches the control.
func _build_pointer_shapes(host: Node3D) -> void:
	var area := host.get_node_or_null("PointerArea") as Node3D
	if area == null:
		return
	var first := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var boxes: Array[AABB] = [
		AABB(Vector3(-0.33, 0.00, -0.40), Vector3(0.66, 0.10, 0.77)),   # base, under the bay
		AABB(Vector3(-0.33, 0.10, -0.40), Vector3(0.03, 0.40, 0.77)),   # left of the bay
		AABB(Vector3(0.30, 0.10, -0.40), Vector3(0.03, 0.40, 0.77)),    # right of the bay
		AABB(Vector3(-0.33, 0.10, -0.40), Vector3(0.66, 0.40, 0.03)),   # behind the bay
		AABB(Vector3(-0.33, 0.50, -0.40), Vector3(0.66, 0.28, 0.77)),   # coin area, behind the plates
		AABB(Vector3(-0.33, 0.78, -0.40), Vector3(0.66, 0.14, 0.84)),   # apron, behind the sockets
		AABB(Vector3(-0.33, 0.92, -0.40), Vector3(0.66, 0.54, 0.67)),   # deck and monitor
		AABB(Vector3(-0.33, 1.46, -0.40), Vector3(0.66, 0.34, 0.74)),   # marquee
	]
	for i in boxes.size():
		var col: CollisionShape3D = first if i == 0 else CollisionShape3D.new()
		if col == null:
			continue
		var shape := BoxShape3D.new()
		shape.size = boxes[i].size
		col.shape = shape
		col.position = boxes[i].get_center()
		if i > 0:
			col.name = "PointerBox%d" % i
			area.add_child(col)
	# A slab behind the SHUT door, so a pointer aimed at it finds the cabinet (to pick it
	# up) and not the board standing in the bay behind it. Out of the way once it is open.
	_pointer_door = CollisionShape3D.new()
	_pointer_door.name = "PointerDoor"
	var slab := BoxShape3D.new()
	slab.size = Vector3(0.60, 0.40, 0.04)
	_pointer_door.shape = slab
	_pointer_door.position = Vector3(0.0, 0.30, 0.35)
	_pointer_door.disabled = is_lid_open()
	area.add_child(_pointer_door)
	if _bay != null:
		_bay.door_changed.connect(func(open: bool) -> void: _pointer_door.disabled = open)


## Called by RetroSystem once the cabinet is parented and built: the input node lives
## on the system (the model cannot add a sibling of itself from its own _ready), and
## the cabinet stays where it was put once it comes to rest.
func attach_to_host(host: Node3D) -> void:
	# The console's floating name tag has nowhere sensible to hang on a 1.8 m cabinet;
	# the marquee is where a cabinet says what it is.
	var tag := host.get_node_or_null("SystemNameLabel") as Node3D
	if tag != null:
		tag.hide()
	_input = ArcadeInput.new()
	_input.name = "ArcadeInput"
	host.add_child(_input)
	var coins: Array = []
	for c in _coins:
		coins.append(c)
	var controls: Array = []
	for c in _controls:
		controls.append(c)
	_input.setup(host, self, controls, coins)
	# While it is in a hand it turns see-through, so the player can see the room behind a
	# 1.8 m box they are carrying. Per-instance dithered transparency, not a transparent
	# material: no sorting, no blending of a huge surface, and no material to swap and restore.
	if host.has_signal("grabbed"):
		host.connect("grabbed", _on_host_grabbed)
		host.connect("dropped", _on_host_dropped)
	# A cabinet is meant to be MOVED: it can be picked up and carried like any machine. It
	# stays upright, though: only yaw is free, so one set down off-level does not tip over
	# onto its marquee. (The lock in the object's options still pins it where it stands.)
	if host is RigidBody3D:
		var body := host as RigidBody3D
		body.axis_lock_angular_x = true
		body.axis_lock_angular_z = true


## How see-through the cabinet is while carried: 0 solid, 1 invisible.
const HELD_TRANSPARENCY := 0.65


func _on_host_grabbed(_pickable: Variant = null, _by: Variant = null) -> void:
	_set_transparency(HELD_TRANSPARENCY)


func _on_host_dropped(_pickable: Variant = null) -> void:
	_set_transparency(0.0)


func _set_transparency(amount: float) -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = amount


## The transparency the cabinet's body is at, for the tests.
func held_transparency() -> float:
	var body := find_child("SideL", true, false) as GeometryInstance3D
	return body.transparency if body != null else 0.0


# ── door, saved as the lid angle ────────────────────────────────────────────

func get_lid_angle_deg() -> float:
	return _bay.get_open_deg() if _bay != null else -1.0


func set_lid_angle_deg(open_deg: float) -> void:
	if _bay != null:
		_bay.set_open_deg(open_deg)


func is_lid_open() -> bool:
	return _bay != null and _bay.is_open()


# ── power ───────────────────────────────────────────────────────────────────

func on_power_on() -> void:
	_light_marquee(true)


func on_power_off() -> void:
	_light_marquee(false)


func _light_marquee(on: bool) -> void:
	if _marquee_mat == null:
		return
	_marquee_mat.emission_enabled = on
	_marquee_mat.emission_energy_multiplier = 0.9 if on else 0.0
