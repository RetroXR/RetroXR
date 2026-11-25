## CaseHinge — the hand's grip on a game case's lid, flip tray or flipper.
##
## VRHinge's grab, poke and pointer plumbing with nothing of its own motion: while a hand has it, GameCase hands the
## angle it reads here to CaseHingeSim; let go, the sim swings the panel and writes the angle back through
## set_angle_quiet(). `gate` (a Callable returning bool) says whether a hand may take it now: a flip tray under a
## shut lid may not, and of a hinge's two handles (the lid's, and the base's for a case held by its lid) only the
## one on the half that is free to move.
class_name CaseHinge
extends VRHinge

var gate: Callable
## Where this panel is NOT a hand's to work (a world point -> bool): over the manual lying in a lid the grip and
## the fingertip are for the manual, over a disc on a hanging base they are for the disc. No trigger latch, no
## open-hand icon, no fingertip push and no pointer press begins there; everywhere else on the panel they all do.
var quiet_at: Callable
## Where a FINGERTIP pushes nothing, when that is not all of quiet_at (a world point -> bool): a finger on the
## booklet lying in a lid presses the lid, though the trigger there is the manual's. Unset: quiet_at.
var push_quiet_at: Callable
## Where the TRIGGER is another panel's (a world point -> bool): a tray lying on the open lid is what a hand at it
## means to turn, not the lid under it. The fingertip and the pointer still work the panel there.
var cede_at: Callable
## Besides the ball round its handle, the trigger takes this panel anywhere within this (m) of its own slab (its
## PokePanel): a flip tray is turned by whatever part of it a hand is at. 0: the ball alone.
var panel_reach := 0.0
## Which faces a fingertip may push now (a face -> bool): a shut lid's inside is no finger's (GameCase).
var face_gate: Callable
## The angle speed (deg/s) of the last frames a hand held it, for the sim on release.
var release_speed_deg := 0.0
var _prev_deg := 0.0


func is_held() -> bool:
	return _trigger_ctrl != null or _pointer_held or _poke_ctrl != null


## Write the sim's angle without emitting (the hand is not moving it) and without the base class's momentum.
func set_angle_quiet(deg: float) -> void:
	_release_angular_velocity_deg = 0.0
	if target != null:
		target.rotation.x = deg_to_rad(clampf(deg, min_deg, max_deg))
	_prev_deg = deg


## Let go of whatever has it (a trigger latch, a fingertip, the pointer): its gate has shut under the hand. A gate
## only stops a hold from beginning.
func drop_hold() -> void:
	if _poke_ctrl != null:
		_end_poke(true)
	_trigger_ctrl = null
	_pointer_held = false


func _process(delta: float) -> void:
	super(delta)
	var now := get_rotation_deg()
	if is_held() and delta > 0.0:
		release_speed_deg = lerpf(release_speed_deg, (now - _prev_deg) / delta, 0.5)
	_prev_deg = now


func _can_engage() -> bool:
	return gate.call() if gate.is_valid() else true


func _quiet(at: Vector3) -> bool:
	return quiet_at.is_valid() and bool(quiet_at.call(at))


## The trigger's reach and the open-hand icon's (VRHinge asks this for both).
func _tip_in_activation_region(tip: Vector3) -> bool:
	if _quiet(tip) or (cede_at.is_valid() and bool(cede_at.call(tip))):
		return false
	return super(tip) or by_panel(tip)


## Whether a point is within `panel_reach` of the panel's own slab.
func by_panel(at: Vector3) -> bool:
	var panel := get_node_or_null("PokePanel") as CollisionShape3D
	if panel_reach <= 0.0 or panel == null or not panel.shape is BoxShape3D:
		return false
	var half := (panel.shape as BoxShape3D).size * 0.5 + Vector3.ONE * panel_reach
	var p := panel.global_transform.affine_inverse() * at
	return absf(p.x) <= half.x and absf(p.y) <= half.y and absf(p.z) <= half.z


func _poke_can_begin(ctrl: XRController3D) -> bool:
	return super(ctrl) and not push_quiet(PokeTip.tip_of(ctrl))


## Whether a fingertip at this point pushes nothing.
func push_quiet(at: Vector3) -> bool:
	return bool(push_quiet_at.call(at)) if push_quiet_at.is_valid() else _quiet(at)


func _poke_face_allowed(_shape: CollisionShape3D, face: int) -> bool:
	return not face_gate.is_valid() or bool(face_gate.call(face))


## The desktop ray and the laser: InteractionResolver asks a control whether it covers the point it was met at.
func accepts_pointer_at(at: Vector3) -> bool:
	return not _quiet(at)


## Hold the angle the hand left: no spring, no latch of the base class's (the sim does both).
func _on_released() -> void:
	pass


func _open_toward_max() -> bool:
	return true
