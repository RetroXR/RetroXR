## VbController — stand-in Virtual Boy controller.
##
## The real VB pad is unusual, and the model follows it: a butterfly of two
## rounded wings over two grips, with a D-pad on EACH wing, SELECT and START
## inboard of the left one, B and A inboard of the right one, L and R on the
## underside where the index fingers sit, and no analog sticks at all.
##
## It also carries the console's POWER switch and the battery pack on its back,
## because the head unit has neither. Sliding the switch powers the console it is
## plugged into, so the Virtual Boy is operated the way the hardware actually is.
##
## The pack is a thing of its own (VbPowerUnit, docs/dev/power.md): it clips onto
## the PackMount on the block's back, and so does the AC adapter tap in its place.
## The console's supply comes up this controller's cord from whichever is on it, so
## its PowerInput reads this one's (`through`), and this one's reads the unit's. The
## switch latches: left ON, the console comes on when the supply arrives.
## A fresh controller comes with its pack on, empty, as one did out of the box.
##
## A proper model exists in the wild but isn't in our library yet, so this is
## authored from primitives.
class_name VbController
extends AnimatedController

## Fraction of travel past which the switch counts as ON.
const _ON_AT := 0.5

# Node path (from the pad root) -> RETRO_JOYPAD bit.
const VB_FACE: Dictionary = {
	"Model/WingR/ButtonB": ControllerBindings.JOYPAD_B,
	"Model/WingR/ButtonA": ControllerBindings.JOYPAD_A,
	"Model/WingL/Select":  ControllerBindings.JOYPAD_SELECT,
	"Model/WingL/Start":   ControllerBindings.JOYPAD_START,
}
const VB_SHOULDERS: Dictionary = {
	"Model/ShoulderL": ControllerBindings.JOYPAD_L,
	"Model/ShoulderR": ControllerBindings.JOYPAD_R,
}

## L and R are moulded into the pad's underside, so they travel UP into it.
const SHOULDER_DIR := Vector3.UP

## Bits the RIGHT D-pad rocks on, as [up, down, left, right]. The VB's fourteen
## controls outnumber the RetroPad bits its other controls already claim, so the
## second D-pad borrows the four left over. Cores differ on which they pick, and
## these bindings are user-remappable, so the rocker also follows the right
## analog stick — the other convention cores use for it.
const RIGHT_DPAD_BITS := [ControllerBindings.JOYPAD_X, ControllerBindings.JOYPAD_L2,
	ControllerBindings.JOYPAD_Y, ControllerBindings.JOYPAD_R2]

const DPAD_PIVOT_DROP: float = 0.003

## The same controls by NAME, for a shell that is not the stand-in (a mod's model,
## xenu.vbpad): its own parts, found anywhere under Model. RetroXR-models' controller
## names them so, each under a "<name>Pivot" node at the point it moves about.
const _BY_NAME := {
	"Model/WingR/ButtonB": "ButtonB", "Model/WingR/ButtonA": "ButtonA",
	"Model/WingL/Select": "Select", "Model/WingL/Start": "Start",
	"Model/ShoulderL": "ShoulderL", "Model/ShoulderR": "ShoulderR",
	"Model/WingL/DPad": "DPadL", "Model/WingR/DPad": "DPadR",
}

## Where the pack's middle sits on the block's back (VbPowerUnit's frame is this
## one): its front face on the block's back face, 27 mm under the pads' plane on
## this stand-in, and 5.8 mm in from the block's cord edge as on the model
## (MEASUREMENTS.md `pack`), so it runs on past the block toward the grips.
const PACK_MOUNT_AT := Vector3(0.0, -0.0441, 0.0248)
const _PACK_SCENE := preload("res://Scenes/Objects/power/vb_battery_pack.tscn")

var _slider: VRSlider = null
var _was_on := false
var _mount: XRToolsSnapZone = null
var _unit: VbPowerUnit = null
var _input: PowerInput = null
var _seeded := false


func _ready() -> void:
	super._ready()
	_slider = get_node_or_null("PowerSlider") as VRSlider
	if _slider != null:
		_slider.value_changed.connect(_on_power_slider)
	_build_pack_mount()


func _cache_meshes() -> void:
	_anim.buttons.clear()
	for path: String in VB_FACE:
		_add_button(path, int(VB_FACE[path]), FACE_PRESS, PRESS_DIR)
	for path: String in VB_SHOULDERS:
		_add_button(path, int(VB_SHOULDERS[path]), TRIGGER_PRESS, SHOULDER_DIR)
	_anim.dpad = _rocker("Model/WingL/DPad")
	_anim.dpad2 = _rocker("Model/WingR/DPad")
	if not _anim.dpad2.is_empty():
		_anim.dpad2["bits"] = RIGHT_DPAD_BITS
		_anim.dpad2["axis"] = "right"


## The D-pads' UP arms point -Z, the edge the cable leaves by.
func _dpad_pitch_sign() -> float:
	return -1.0


## A control by the stand-in's path, else by its name under Model.
func _control(path: String) -> MeshInstance3D:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null and _BY_NAME.has(path):
		var model := get_node_or_null("Model")
		if model != null:
			m = model.find_child(str(_BY_NAME[path]), true, false) as MeshInstance3D
	return m


func _add_button(path: String, bit: int, depth: float, dir: Vector3) -> void:
	var m := _control(path)
	if m == null:
		push_warning("[VbController] control mesh not found: " + path)
		return
	_anim.buttons.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth, "dir": dir})


func _rocker(path: String) -> Dictionary:
	var m := _control(path)
	if m == null:
		push_warning("[VbController] control mesh not found: " + path)
		return {}
	# A model's D-pad hangs under the node it rocks about; the stand-in's cross rocks
	# about a point under itself.
	if str(m.get_parent().name).ends_with("Pivot"):
		return {"node": m, "rest": m.transform, "pivot": Vector3.ZERO}
	return {"node": m, "rest": m.transform, "pivot": m.position - Vector3(0.0, DPAD_PIVOT_DROP, 0.0)}


## Drive the plugged-in console's power from the slider, latching on the
## crossing so a jittery hand doesn't toggle it repeatedly mid-slide.
func _on_power_slider(v: float) -> void:
	var on := v >= _ON_AT
	if on == _was_on:
		return
	_was_on = on
	# ObjectSync moves this cap on the other peers, but the authoritative power
	# intent travels separately. Do not turn their cores on/off from the visual
	# replay or the same physical move is applied twice.
	if NetworkManager.is_event_applying():
		return
	var sys := _connected_system
	if sys == null:
		return
	if on != sys.is_powered_on:
		sys.toggle_power()


## Reflect the console's state if it was powered some other way (the cabinet
## START button, a save restore), so the switch never sits at odds with it.
func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	# The console's supply comes up this cord.
	MainsPower.changed(get_tree())
	if _slider == null or system == null:
		return
	_was_on = system.is_powered_on
	_slider.set_value_no_signal(1.0 if _was_on else 0.0)


func on_unplugged() -> void:
	super.on_unplugged()
	MainsPower.changed(get_tree())


## The POWER switch: a slide that stays where it is put (SystemPower turns a
## console on when its supply arrives under a switch left ON).
func latching_power_switch() -> VRSlider:
	return _slider


# ── its power: the pack or the tap on its back ───────────────────────────────

func _build_pack_mount() -> void:
	_mount = CoverSlots.make_zone("PackMount", VbPowerUnit.GROUP, 0.04, self)
	_mount.position = PACK_MOUNT_AT
	_mount.has_picked_up.connect(_on_unit_in)
	_mount.has_dropped.connect(_on_unit_out)
	_input = PowerInput.on(self)
	_input.noun = "controller"
	_input.through = get_power_unit_input
	_input.through_missing = "Nothing on its back (it takes the battery pack or the AC adapter tap)"
	# A restored controller is told by its save (restore_power_unit).
	if not has_meta(CoverSlots.RESTORING):
		_seed_pack.call_deferred()


## The battery pack or AC adapter tap on its back, or null.
func get_power_unit() -> VbPowerUnit:
	return _unit if is_instance_valid(_unit) else null


## What the console reads through this controller: the unit's intake, or null with
## nothing on its back.
func get_power_unit_input() -> PowerInput:
	var unit := get_power_unit()
	return unit.input if unit != null else null


## This controller's own intake (what is on its back), for the console's.
func power_input() -> PowerInput:
	return _input


## Put a save's unit back on. `named` is whether the save said anything at all: a
## save from before the pack was a thing of its own names nothing, and that
## controller gets the fresh pack it was always drawn with.
func restore_power_unit(unit: VbPowerUnit, named: bool) -> void:
	if _mount == null:
		return
	if is_instance_valid(unit):
		if not _mount.has_snapped_object():
			_mount.pick_up_object(unit)
		return
	if not named:
		print("[Power] %s: saved before its pack was its own -- a fresh one goes on" % name)
		_seed_pack()


func _seed_pack() -> void:
	if _seeded or _mount == null or not is_inside_tree() or _mount.has_snapped_object():
		return
	_seeded = true
	var pack := _PACK_SCENE.instantiate() as VbPowerUnit
	get_tree().current_scene.add_child(pack)
	pack.global_transform = _mount.global_transform
	_mount.pick_up_object(pack)
	print("[Power] %s: came with its battery pack, empty, lid shut" % name)


func _on_unit_in(what: Node3D) -> void:
	_unit = what as VbPowerUnit
	if _unit == null:
		return
	add_collision_exception_with(_unit)
	# Seated, the unit is frozen and collides with nothing; the controller carries
	# its shape, or a pad laid on its back sinks the pack into the table.
	SeatedCollision.lend(self, _unit, _mount)
	print("[Power] %s: %s on" % [name, _unit.unit_label()])
	MainsPower.changed(get_tree())


func _on_unit_out() -> void:
	if is_instance_valid(_unit):
		remove_collision_exception_with(_unit)
		SeatedCollision.withdraw(self, _unit)
		print("[Power] %s: %s off" % [name, _unit.unit_label()])
	_unit = null
	MainsPower.changed(get_tree())
