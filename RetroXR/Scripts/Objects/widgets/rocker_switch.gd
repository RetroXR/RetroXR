## RockerSwitch — a two-position rocker power switch (I / O): a VRLever that only rests at its two ends.
##
## A real snap-in rocker has a spring detent: pushed past its middle it flips to the other end, let go short of it it
## falls back. So everything VRLever already does (a fingertip pushing either half about the pivot, the trigger taking
## hold of it, the laser) moves the cap, and the moment nothing holds it (_on_released, _on_idle) it snaps to the end it
## is nearer. A desktop click or a laser press TOGGLES it: a rocker is pressed, not dragged.
##
## The angle is the state: value 1 is ON (max_deg, the I half pressed in), 0 is OFF. Being a VRLever, it is saved and
## synced by the generic control walk (ScenePersistence "lever", ObjectSync's lever binding) with no code of its own.
##
## The cap's pivot is `target` (its local X the rocker's axis); this Area3D hangs under it so its box tilts with the
## cap. The face a finger pushes is the box's local `poke_torque_faces`.
class_name RockerSwitch
extends VRLever

## Emitted when the switch changes between ON and OFF (not while a finger is still rocking it), with what moved it.
signal toggled(on: bool)

## Half the throw: the cap rests at -throw_deg (OFF) or +throw_deg (ON).
@export var throw_deg: float = 9.0
## Tag for the log lines ("[Subwoofer]").
@export var log_tag: String = "Rocker"

var _on: Variant = null
## Which half a fingertip is pushing: +1 the I (top) half, -1 the O half, 0 none.
var _pushing := 0


func _ready() -> void:
	min_deg = -throw_deg
	max_deg = throw_deg
	value_at_min = 0.0
	value_at_max = 1.0
	value_changed.connect(_on_value)
	super()


## Whether the switch is ON (the I half in).
func is_on() -> bool:
	return get_value() >= 0.5


## Throw the switch to an end. `emit` false for a restore or a seed: no toggled signal, nothing sent.
func set_on(on: bool, emit := true) -> void:
	if emit:
		set_value(1.0 if on else 0.0)
	else:
		set_value_no_signal(1.0 if on else 0.0)
		_on = on


func toggle() -> void:
	set_on(not is_on())


## A press toggles; the hover still shows the hint icon.
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hover_pointers[event.pointer] = true
		XRToolsPointerEvent.Type.PRESSED:
			if _can_engage():
				toggle()
				print("[%s] %s: switched %s by the pointer" % [log_tag, _owner_name(), "ON" if is_on() else "OFF"])
		XRToolsPointerEvent.Type.EXITED:
			_hover_pointers.erase(event.pointer)
	_update_icon()


## A finger only PUSHES a rocker: the half it came down on goes in, and drawing the finger back does not pull it out
## again (VRHinge's torque poke follows the finger both ways, which turned the switch straight back off).
func _on_poke_started(tip: Vector3, _outward_normal: Vector3, _mode: int) -> void:
	var parent := target.get_parent() as Node3D if target != null else null
	if parent == null:
		_pushing = 0
		return
	var rest := Basis.from_euler(Vector3(0.0, target.rotation.y, target.rotation.z))
	var rel: Vector3 = rest.inverse() * (parent.to_local(tip) - target.position)
	_pushing = 1 if rel.y >= 0.0 else -1


func _on_poke_ended() -> void:
	_pushing = 0


func _on_poke_motion(world_pos: Vector3, _mode: int) -> void:
	var wanted := _poke_wanted_deg(world_pos, true)
	if is_nan(wanted) or target == null:
		return
	var cur := rad_to_deg(target.rotation.x)
	if (_pushing > 0 and wanted > cur) or (_pushing < 0 and wanted < cur):
		_apply(wanted, true)


func _on_released() -> void:
	super()
	_snap("let go")


func _on_idle(_delta: float) -> void:
	_snap("")


## To the nearer end, if it is between them.
func _snap(why: String) -> void:
	if target == null:
		return
	var v := get_value()
	var want := 1.0 if v >= 0.5 else 0.0
	if absf(v - want) > 0.0005:
		set_value(want)
		if not why.is_empty():
			print("[%s] %s: %s at %.2f, it snaps %s" % [log_tag, _owner_name(), why, v, "ON" if want > 0.5 else "OFF"])


func _on_value(v: float) -> void:
	# Mid-throw values are a finger still rocking it: the state is the end it rests at.
	if v > 0.0005 and v < 0.9995:
		return
	var on := v >= 0.5
	if on == _on:
		return
	_on = on
	toggled.emit(on)


func _owner_name() -> String:
	var n: Node = self
	while n != null and not n is RigidBody3D:
		n = n.get_parent()
	return String(n.name) if n != null else String(name)
