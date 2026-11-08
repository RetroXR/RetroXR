## TvKeyDoor — the RETRO XR television's key door: the flap over the five keys in the bezel's bottom right, hinged
## on its bottom edge and held shut by a push-push catch, as the front doors of CRT sets were (a press on the shut
## door lets its catch go and a spring swings it out; pushed back up until it clicks, the catch takes it again;
## docs/dev/av-suite.md "The key door").
##
##   - SHUT and LATCHED (it boots so): a fingertip pushed into its face drives it in a couple of millimetres
##     (push_push_unlatch_depth, the visible overtravel), then the catch lets go and it falls open. A pointer (the
##     desktop crosshair, a laser) or a hand's trigger on it does the same at once.
##   - OPEN: a hinged flap. A fingertip pushes it up by its outer face, a hand's trigger or a laser drags it, and on
##     the desktop it is pressed and DRAGGED WITH THE MOUSE (its free edge follows the mouse as it lies on screen;
##     the view does not turn, VRSlider.mouse_drag's arrangement). Reaching shut, it latches; let go of part-way, it
##     falls open again.
##
## The door's angle and its latch are saved and synced as every VRSpringLatchedHinge's are (ScenePersistence's
## articulated controls, ObjectSync), found through ScenePersistence.CONTROL_GROUP, which VRHinge joins in _init.
class_name TvKeyDoor
extends VRSpringLatchedHinge

## How far it swings (the model's DoorOpen ends here).
const OPEN_DEG := 100.0
## Within this much of shut, a door being pushed or dragged is home: the catch takes it.
const HOME_DEG := 0.5
## A door taken while latched must first leave home by this much before it can be pushed home again (a trigger that
## unlatches it holds it AT home, which must not count as pushing it shut).
const AWAY_DEG := 5.0
## Desktop drag: the fewest mouse pixels the whole swing takes (VRSlider.MOUSE_TRAVEL_MIN_PX).
const MOUSE_TRAVEL_MIN_PX := 360.0
## The fall: eased toward open at this rate per second of what is left (a damped spring), never slower than
## FALL_MIN_DEG a second, so it settles in about two thirds of a second.
const FALL_RATE := 7.0
const FALL_MIN_DEG := 25.0

## Where on the door the mouse drags it: its free edge's middle, in the pivot's (target's) frame. The shell sets it.
var edge_local := Vector3(0, 0.035, 0)

var _mouse_held := false
var _away := false
var _open_logged := true
var _pushed_by := ""


func _ready() -> void:
	super._ready()
	# A push-push door is reached while latched: its box stays live shut too.
	_set_interactive(true)
	_away = not is_latched_closed()
	print("[TV] key door: %s at %.1f deg" % ["latched" if is_latched_closed() else "open", get_rotation_deg()])


func _vr() -> bool:
	return is_inside_tree() and get_viewport().use_xr


## Whether the mouse is dragging the door now.
func is_mouse_held() -> bool:
	return _mouse_held


func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.PRESSED:
			if is_latched_closed():
				# The press is the push on the shut door: its catch lets go and it falls open. Nothing is held, so
				# the release does not ask the catch again.
				_unlatch("pointer")
				_update_icon()
				return
			if not _vr():
				_release_angular_velocity_deg = 0.0
				_pointer_held = true
				_mouse_held = true
				print("[TV] key door: held by the mouse at %.1f deg (%.0f px end to end)" % [get_rotation_deg(),
					_px_per_deg() * (max_deg - min_deg)])
				_update_icon()
				return
		XRToolsPointerEvent.Type.RELEASED:
			_mouse_held = false
	super.pointer_event(event)


## Desktop: the held door follows the mouse along the way its free edge moves on screen, and the view is left alone
## (handled here, before MovementDesktopTurn's _unhandled_input). The button coming up ends it even if the pointer
## never says RELEASED.
func _input(event: InputEvent) -> void:
	if not _mouse_held:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_mouse_held = false
		_pointer_held = false
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	get_viewport().set_input_as_handled()
	drag_by_pixels(mm.relative)


## Move a mouse-held door by a mouse motion (also the tests' way in): the motion's part along the free edge's own
## on-screen path, at that path's length but never under MOUSE_TRAVEL_MIN_PX for the swing.
func drag_by_pixels(relative: Vector2) -> void:
	if target == null:
		return
	var path := _edge_on_screen()
	if path.is_empty():
		return
	var per_deg: float = maxf(float(path["px"]), MOUSE_TRAVEL_MIN_PX / maxf(max_deg - min_deg, 1.0))
	_apply(get_rotation_deg() + relative.dot(path["dir"]) / per_deg, true)
	_away = _away or get_rotation_deg() > min_deg + AWAY_DEG


## Which way, and how many pixels a degree, the door's free edge moves on screen as it opens: {dir, px}, or {} with
## no camera.
func _edge_on_screen() -> Dictionary:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var parent := target.get_parent() as Node3D if target != null else null
	if cam == null or parent == null:
		return {}
	var a := cam.unproject_position(_edge_at(get_rotation_deg()))
	var b := cam.unproject_position(_edge_at(get_rotation_deg() + 1.0))
	if (b - a).length() < 0.001:
		return {}
	return {"dir": (b - a).normalized(), "px": (b - a).length()}


func _px_per_deg() -> float:
	var path := _edge_on_screen()
	return MOUSE_TRAVEL_MIN_PX / (max_deg - min_deg) if path.is_empty() \
		else maxf(float(path["px"]), MOUSE_TRAVEL_MIN_PX / (max_deg - min_deg))


func _edge_at(deg: float) -> Vector3:
	var parent := target.get_parent() as Node3D
	var turned := Transform3D(Basis.from_euler(Vector3(deg_to_rad(deg), target.rotation.y, target.rotation.z))
		* Basis.from_scale(target.scale), target.position)
	return parent.global_transform * turned * edge_local


func _process(delta: float) -> void:
	super._process(delta)
	var deg := get_rotation_deg()
	if not is_latched_closed():
		_away = _away or deg > min_deg + AWAY_DEG
		# Pushed or dragged home by a hand, a laser or the mouse: the catch takes it there and then. (A fingertip's
		# push is VRSpringLatchedHinge's own: it latches at its overtravel, in _on_poke_motion.)
		var by := "the mouse" if _mouse_held else "a laser" if _pointer_held else "a hand" if _trigger_ctrl != null else ""
		if _away and not by.is_empty() and deg <= min_deg + HOME_DEG:
			_pushed_by = by
			_mouse_held = false
			_skip_next_release = true
			latch_closed()
		elif not _open_logged and is_equal_approx(deg, max_deg):
			_open_logged = true
			print("[TV] key door: open (%.0f deg)" % max_deg)


func _unlatch(by: String) -> void:
	print("[TV] key door: unlatched by %s" % by)
	open()


func open() -> void:
	var was := is_latched_closed()
	super.open()
	_open_logged = false
	if was:
		_away = false
		# The fingertip's and the trigger's ways in come through here from VRSpringLatchedHinge; the pointer's says
		# so itself first (_unlatch).
		if _poke_ctrl != null:
			print("[TV] key door: unlatched by a fingertip (pushed %.1f mm in)" % (push_push_unlatch_depth * 1000.0))
		elif _trigger_ctrl != null:
			print("[TV] key door: unlatched by a hand")


func latch_closed(rebound_from_overtravel: bool = false, preserve_poke: bool = false) -> void:
	if rebound_from_overtravel and _pushed_by.is_empty():
		_pushed_by = "a fingertip"
	if not _pushed_by.is_empty():
		print("[TV] key door: pushed shut by %s" % _pushed_by)
	_pushed_by = ""
	super.latch_closed(rebound_from_overtravel, preserve_poke)
	_mouse_held = false
	_away = false
	print("[TV] key door: latched")


func set_state_remote(degrees: float, latched: bool, emit: bool = true) -> void:
	super.set_state_remote(degrees, latched, emit)
	_mouse_held = false
	_away = not latched
	_open_logged = latched or is_equal_approx(degrees, max_deg)
	print("[TV] key door: set %s at %.1f deg (a restore or a peer)" % ["latched" if latched else "unlatched", degrees])


## Let go of part-way: home within close_latch_deg latches (VRSpringLatchedHinge), anywhere else it falls open.
func _on_released() -> void:
	_mouse_held = false
	var deg := get_rotation_deg()
	if absf(deg - min_deg) <= close_latch_deg:
		_pushed_by = "a release at home"
		super._on_released()
		return
	print("[TV] key door: fell open (let go at %.1f deg)" % deg)


## A fingertip on the shut door: how far it has pushed in is measured from the door's FACE, not from wherever it
## came within poke_face_margin of it, or the catch let go before the finger touched the door.
func _on_poke_started(tip: Vector3, outward_normal: Vector3, mode: int) -> void:
	super._on_poke_started(tip, outward_normal, mode)
	if not _poke_overtravel or _poke_shape == null or not (_poke_shape.shape is BoxShape3D):
		return
	var local := Vector3.ZERO
	var axis := _face_axis(_poke_face)
	local[axis] = _face_sign(_poke_face) * (_poke_shape.shape as BoxShape3D).size[axis] * 0.5
	var face := _poke_shape.global_transform * local
	_poke_start_tip = tip - outward_normal * (tip - face).dot(outward_normal)


func _on_poke_ended() -> void:
	if _poke_latching and not is_latched_closed():
		print("[TV] key door: fell open (the fingertip left it at %.1f deg)" % get_rotation_deg())
	super._on_poke_ended()


## The fall is damped: quick away from the catch, slowing into its stop.
func _step_spring_open(delta: float) -> void:
	if target == null:
		return
	var cur := get_rotation_deg()
	if is_equal_approx(cur, max_deg):
		return
	var step := maxf((max_deg - cur) * (1.0 - exp(-FALL_RATE * delta)), FALL_MIN_DEG * delta)
	_apply(move_toward(cur, max_deg, step), false)
