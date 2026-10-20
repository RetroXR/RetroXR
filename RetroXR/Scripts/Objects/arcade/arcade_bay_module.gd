## ArcadeBayModule — the bay behind the lower door, where the board plugs in.
##
## The kind is `bay`, and `bay_kind` says what it takes (ArcadeProfiles.BAY_KINDS):
## `jamma` today. The door is a drop-down panel on a hinge (`DoorPivot`, a VRHinge
## on `DoorGrab`); while it is shut the cabinet's cartridge slot is gated off, as the
## NES's flap gates its bay. Inside are the `CartSeat` the board stands on, the
## `JammaSocket` (the harness's female connector, where the comb goes) and the
## `PowerSwitch` seat.
##
## The door angle is the saved state (`lid_angle`, which ScenePersistence already
## stores and restores for any model) and its VRHinge is already synced in netplay.
class_name ArcadeBayModule
extends ArcadeModule

signal door_changed(open: bool)

@export var bay_kind: String = ArcadeProfiles.BAY_JAMMA
## How far the door swings, degrees from shut.
@export var open_deg: float = 90.0

var _pivot: Node3D = null
var _hinge: VRHinge = null
var _slot: Node3D = null
## True when the cabinet's scene has a `BayMount` marker: its bay is a separate object (ArcadeBayUnit)
## that clips into the mount, and this module is only the compartment, the door and the power switch.
var _detachable := false
## The slot of the bay in the compartment, gated by the door; null with none, or a cabled one.
var _gated: XRToolsSnapZone = null
var _open := false


func _init() -> void:
	kind = ArcadeProfiles.KIND_BAY


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_pivot = find_child("DoorPivot", true, false) as Node3D
	_hinge = find_child("DoorGrab", true, false) as VRHinge
	if _hinge != null and _pivot != null:
		_hinge.target = _pivot
		_hinge.min_deg = 0.0
		_hinge.max_deg = open_deg
		# The cabinet is never lifted by its door, so a squeeze may open it; the
		# hinge mutes that hand's pickup while it is on the door.
		_hinge.grip_engages = true
		_hinge.box_engages = true
		_hinge.rotation_changed.connect(_on_hinge)


## Seat the cabinet's cartridge slot on the board's seat and gate it by the door. A cabinet with a
## `BayMount` has no seat of its own: the slot is shut for good, and the bay brings one.
func configure_slot(slot: Node3D) -> void:
	_slot = slot
	var visual := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if visual != null:
		visual.hide()
	_detachable = find_child("BayMount", true, false) != null
	if _detachable:
		if "enabled" in slot:
			slot.enabled = false
		return
	var seat := find_child("CartSeat", true, false) as Node3D
	if seat != null:
		slot.global_transform = seat.global_transform
	_gate()


## Where a bay's origin goes when it is clipped in, or null on a cabinet whose bay is not separate.
func mount_marker() -> Node3D:
	return find_child("BayMount", true, false) as Node3D


## The slot of the bay now docked, which the door gates; null when it is gone or is not docked.
func set_gated_slot(zone: XRToolsSnapZone) -> void:
	_gated = zone
	_gate()


func power_switch_seat() -> Node3D:
	return find_child("PowerSwitch", true, false) as Node3D


func is_open() -> bool:
	return _open


## How far the door stands open, in degrees from shut.
func get_open_deg() -> float:
	return _pivot_deg()


## Pose the door at a saved angle with no animation: a restore is a state the room
## was already in, not something the player just did. Takes the slot gate and the
## grab hinge with it.
func set_open_deg(deg: float) -> void:
	var d := clampf(deg, 0.0, open_deg)
	if _pivot != null:
		_pivot.rotation.x = deg_to_rad(d)
	if _hinge != null:
		_hinge.set_rotation_deg_no_signal(d)
	_set_open(d > open_deg * 0.5)


func _on_hinge(_deg: float) -> void:
	_set_open(_pivot_deg() > open_deg * 0.5)


func _pivot_deg() -> float:
	return rad_to_deg(_pivot.rotation.x) if _pivot != null else 0.0


func _set_open(open: bool) -> void:
	if open == _open:
		_gate()
		return
	_open = open
	_gate()
	door_changed.emit(open)


func _gate() -> void:
	var target: Node3D = _gated if _detachable else _slot
	if target != null and "enabled" in target:
		target.enabled = _open
