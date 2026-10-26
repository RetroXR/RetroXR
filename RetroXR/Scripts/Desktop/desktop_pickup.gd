## DesktopPickup — mouse-driven object pickup for desktop (non-VR) mode.
##
## Attach to XRCamera3D.  When XR is not active:
##   Left-click             — pick up the XRToolsPickable under the cursor.
##   Shift + Left-click     — on an FPS-snap object (light gun, Wii Remote): pick it
##                       up to LOOK AT, held on the ray like anything else, not
##                       raised to aim (see FPS-snap mode).
##   Shift + Left-click     — drop the currently held object.
##   Scroll up/down    — push/pull the held object along the camera ray.
##                       Pulled all the way in, one more notch CATCHES it into the
##                       hand (a comfortable pose in front of you; a handheld faces
##                       you screen-on); scroll up sends it back out on the ray.
##                       (Disabled for FPS-snap objects.)
##   Left click, held — the object is let go when the button comes back UP, and not
##                       when it goes down, so a press on one of its own controls (a
##                       console's power switch) works it instead of dropping it.
##   Middle-mouse drag — rotate the held object in place, the REVERSE of aircraft
##                       controls (the player found those wrong): mouse right
##                       yaws the far side LEFT, mouse up pitches the far side
##                       DOWN. Shift + horizontal drag rolls it (right =
##                       counter-clockwise). (Disabled for FPS-snap objects.)
##
## FPS-snap mode:
##   Objects with a truthy "desktop_fps_snap" property (e.g. the LightGun) are
##   locked to a fixed lower-right offset from the camera instead of floating
##   freely on the ray.  This gives an FPS-style weapon view.  The hand pivot's
##   orientation matches the camera so the weapon always aims where you look.
##
##   Picked up with Shift held, it is not raised to aim but INSPECTED: held as any
##   other object is (on the ray, scrolled along it, turned, caught into the hand,
##   and dropped by a plain click), and it does not play — the object reads
##   DesktopPickup.inspecting(self) and leaves the game's input alone.
##
##   An FPS-snap object may also name a COMPANION — a second object it arrives
##   with, which gets the mirrored lower-LEFT slot, i.e. the player's other hand.
##   The Wiimote's Nunchuk is the case this exists for: it is a separate pickable
##   on a cord, so without a slot of its own it hung off the remote and dragged
##   along the floor.  Declared by a desktop_companion() method returning the
##   pickable or null, and re-read every frame — plug the cord in mid-hold and it
##   comes to hand, pull it out and it drops.
##
## Objects must have collision on layer 3 ("Pickable") to be grabbable.
##
## The "fake hand" (_hand_pivot, group "desktop_hand") is an invisible Node3D
## child that acts as the grabber.  XRToolsGrabDriver follows its
## global_transform, so moving/rotating the pivot moves/rotates the held object.
class_name DesktopPickup
extends Node3D

const InteractionTargetType := preload("res://Scripts/Interaction/interaction_target.gd")

## Scroll step in metres
const SCROLL_STEP := 0.075
const MIN_DIST    := 0.15
const MAX_DIST    := 5.0

## Mouse sensitivity for rotation (radians per pixel)
const ROT_SENSITIVITY := 0.008

## Pointer travel (pixels) that turns a click into a drag.
const CLICK_DRAG_PX := 6.0

## Where a caught object rides, in camera space: right, down, forward. Low and near, as a
## console is held to be played.
const HAND_LOCAL := Vector3(0.0, -0.10, -0.40)
## How far (degrees) you may look away from where the hand holds it before it follows: a little
## give, so a small look does not drag it, but it stays in front of you. It used to be 24/18 and
## widened with the object's size (to 60) so the crosshair could sweep across a console to a switch
## on its edge; the object then sat well off to the side, trailing, and the player did not want
## that (2026-10-22). A control on an edge is reached by tipping the object towards you instead.
const HAND_DEADZONE_YAW := 6.0
const HAND_DEADZONE_PITCH := 5.0
## How fast the hand catches up once it has to (1 / seconds).
const HAND_FOLLOW_RATE := 12.0
## Anything bigger than this (its reach from the held point, metres) is held further off, in
## proportion, so it does not fill the view or pass through the camera.
const HAND_ROOM_REACH := 0.25
## Something with no screen and smaller than that comes in until it fills this much of the
## view's width (object_distance), no nearer than HAND_FOCUS_MIN: it used to sit at HAND_LOCAL,
## 40 cm out, whatever its size, so a small thing was as far off as a pad.
const HAND_OBJECT_FRACTION := 0.40
## A handheld is held by its SCREEN: that point sits at the crosshair, `HAND_SCREEN_FRACTION`
## of the view's width wide, as near as HAND_FOCUS_MIN and no further than HAND_FOCUS_MAX.
const HAND_SCREEN_FRACTION := 0.30
const HAND_FOCUS_MIN := 0.14
const HAND_FOCUS_MAX := 0.40
## How fast a caught object settles into the hand (1 / seconds).
const HAND_BLEND_RATE := 6.0

## FPS-snap local offset from camera: right, down, forward.
## Applied as a Transform3D in camera-local space so the weapon is always
## in the same screen-space corner regardless of where the player looks.
const FPS_SNAP_LOCAL := Transform3D(Basis.IDENTITY, Vector3(0.20, -0.22, -0.45))

## The companion's slot: the same offset mirrored across the view, so the pair
## reads as one in each hand. Same depth and drop as the weapon slot on purpose —
## anything else and the two sit at visibly different distances.
const FPS_SNAP_COMPANION_LOCAL := Transform3D(Basis.IDENTITY, Vector3(-0.20, -0.22, -0.45))

var _held_object : XRToolsPickable = null
## The held FPS-snap object was picked up with Shift, to look at rather than to aim.
var _inspect : bool = false

## Set on an object while it is inspected, for its own script and its hint to read.
const INSPECT_META := &"desktop_inspect"
var _grab_dist   : float = 1.5

var _hand_pivot  : Node3D    = null
var _desktop_pointer : XRToolsDesktopFunctionPointer = null

var _companion_object : XRToolsPickable = null
var _companion_pivot  : Node3D = null

var _middle_held : bool = false
## Left held and dragged past CLICK_DRAG_PX with the object in hand: turning it, as the middle
## button does, and the release lets go of nothing.
var _left_turning : bool = false
## True from a left press that is on the held object (a click to drop it or a drag to turn it)
## until the button comes up: the look-around ignores the mouse meanwhile, or turning the object
## would turn the player too (MovementDesktopTurn asks, as it does about the middle button).
static var left_drag : bool = false
var _left_drag : float = 0.0
## True while the object is CAUGHT: in the hand, rather than floating on the ray.
var _hand_hold : bool = false
## 0 when it was just caught, 1 once it has settled; and the pose it was caught from.
var _hold_blend : float = 1.0
var _dimmed : PickableHighlight = null
## _held_highlight's answer, and the object it is for.
var _highlight : PickableHighlight = null
var _highlight_of : XRToolsPickable = null
var _catch_from : Transform3D = Transform3D.IDENTITY
## Notches of resistance given so far past the pull-in limit, how long since the last, and the
## shiver they set off (1 just after a notch, fading to 0).
## Which way the hand points, as yaw and pitch (radians): the frame the held object rides in.
## It trails the camera with a dead zone instead of being bolted to it, so looking over a
## held console moves the crosshair across it.
var _hand_yaw : float = 0.0
var _hand_pitch : float = 0.0
## The object's orientation in the hand, in THAT frame.
var _hand_cam_basis : Basis = Basis.IDENTITY
## The orientation it is caught in, which scrolling in again returns it to.
var _hand_default_basis : Basis = Basis.IDENTITY
## A handheld held by its screen: the screen's middle in the object's own space, and how wide it
## is. Width 0 means there is no such thing, and the object is held by its origin as before.
var _hand_focus_local : Vector3 = Vector3.ZERO
var _hand_focus_width : float = 0.0
## How far the held thing reaches from that point (metres): how far the gaze may stray from it
## before the hand has to follow, so that any part of it can be looked at.
var _hand_focus_radius : float = 0.0
## Left went down with something held and nothing of its own under the crosshair: the
## object is let go when the button comes back up.
var _drop_armed : bool = false
var _hovered_target : Node3D = null

## Left button down over something that answers to a click (a cart lying in a push
## tray). Held until the button comes back up — a release without travel is the
## click, travel first is a pull — so the grab has to wait for one or the other.
var _pending_click : Node3D = null
var _pending_grab  : Node3D = null
var _pending_inspect : bool = false
var _click_drag    : float = 0.0


func _ready() -> void:
	# Invisible pivot that the grabbed object follows.
	# Uses DesktopHandPivot script to satisfy XRToolsPickable's grabber interface
	# (picked_up_ranged property + drop_object() callback).
	# Placed in the "desktop_hand" group so light_gun.gd / retro_controller.gd
	# can detect desktop-grab in their _on_grabbed_signal handlers.
	var pivot_script := load("res://Scripts/Desktop/desktop_hand_pivot.gd")
	_hand_pivot = Node3D.new()
	_hand_pivot.set_script(pivot_script)
	_hand_pivot.name = "DesktopHand"
	_hand_pivot.add_to_group("desktop_hand")
	_hand_pivot._owner_pickup = weakref(self)
	add_child(_hand_pivot)

	# The other hand. Same shim and the same group — HeldHint reads "desktop_hand"
	# to decide which platform's hints an object shows, and a companion held by
	# something outside the group would advertise the VR drop combo.
	_companion_pivot = Node3D.new()
	_companion_pivot.set_script(pivot_script)
	_companion_pivot.name = "DesktopCompanionHand"
	_companion_pivot.add_to_group("desktop_hand")
	_companion_pivot._owner_pickup = weakref(self)
	_companion_pivot._drop_method = &"_on_companion_drop_object"
	add_child(_companion_pivot)

	_desktop_pointer = get_node_or_null("FunctionDesktopPointer") as XRToolsDesktopFunctionPointer


func _unhandled_input(event: InputEvent) -> void:
	# Only active in desktop mode
	if get_viewport().use_xr:
		return

	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_LEFT:
				if not mbe.pressed:
					left_drag = false
				if mbe.pressed:
					if is_turning():
						# A click mid-turn is neither a drop nor a press on whatever the turn
						# has brought under the crosshair.
						get_viewport().set_input_as_handled()
					elif _held_object:
						# The click drops what is held -- but on the way UP, so that a press
						# on one of the object's own controls (a console's power switch) is
						# THAT control's: it is lit under the crosshair and the pointer works
						# it, and the object stays in the hand.
						# Shift+click drops any held object; a plain click also drops
						# non-FPS-snap objects (books, controllers, etc.).
						# FPS-snap objects (light gun) require Shift+click to drop because
						# plain left-click is the shoot/trigger action while the gun is held.
						# Objects with desktop_shift_drop (mouse) do too — plain click is
						# their own LEFT button while held.
						if _crosshair_on_control():
							_drop_armed = false
							_log_click_kept()
						elif mbe.shift_pressed or not (_is_fps_snap() or _needs_shift_drop()):
							_drop_armed = true
							_left_drag = 0.0
							left_drag = true
							get_viewport().set_input_as_handled()
					else:
						_try_grab(mbe.shift_pressed)
				elif _left_turning:
					# The drag that turned it ends; nothing is dropped.
					_left_turning = false
					get_viewport().set_input_as_handled()
				elif _drop_armed:
					_drop_armed = false
					if _held_object:
						_drop()
					get_viewport().set_input_as_handled()
				elif _pending_click != null:
					# Came back up without travelling: it was a click.
					var clicked := _pending_click
					_pending_click = null
					_pending_grab = null
					if is_instance_valid(clicked):
						clicked.desktop_click_action()
					get_viewport().set_input_as_handled()

			MOUSE_BUTTON_MIDDLE:
				_middle_held = mbe.pressed

			# Wheel DOWN brings the held object toward you, wheel UP sends it away. Pulled all
			# the way in, one more notch down catches it into the hand; wheel UP lets it
			# back out onto the ray.
			MOUSE_BUTTON_WHEEL_UP:
				if _held_object and not _is_fps_snap():
					if _hand_hold:
						_release_to_ray()
					else:
						_grab_dist = clampf(_grab_dist + SCROLL_STEP, MIN_DIST, MAX_DIST)
					get_viewport().set_input_as_handled()

			MOUSE_BUTTON_WHEEL_DOWN:
				if _held_object and not _is_fps_snap():
					if _hand_hold:
						# Scrolling in again, already in the hand, puts it back the way it was
						# caught: screen to you, in front of you. For a thing turned to show a
						# switch on its edge that is the way back.
						_reset_hand_pose()
					elif _grab_dist <= MIN_DIST + 0.0005:
						_catch()
					else:
						_grab_dist = clampf(_grab_dist - SCROLL_STEP, MIN_DIST, MAX_DIST)
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _pending_click != null:
		# Travelled while held: the player is pulling it out, not pressing it.
		_click_drag += (event as InputEventMouseMotion).relative.length()
		if _click_drag >= CLICK_DRAG_PX:
			var target := _pending_grab
			_pending_click = null
			_pending_grab = null
			if is_instance_valid(target):
				_grab_target(target, _pending_inspect)

	elif event is InputEventMouseMotion and _drop_armed and _held_object != null \
			and not _is_fps_snap() and not _needs_shift_drop():
		# Left held on the object and dragged: not a click to drop it but a turn, the same
		# as the middle button's. Short of CLICK_DRAG_PX it is still a click.
		_left_drag += (event as InputEventMouseMotion).relative.length()
		if _left_drag >= CLICK_DRAG_PX:
			_drop_armed = false
			_left_turning = true
		if _left_turning:
			_turn_held(event as InputEventMouseMotion)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _left_turning and _held_object != null:
		_turn_held(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _middle_held:
		_turn_held(event as InputEventMouseMotion)
		# Always consume mouse motion while MMB is held so MovementDesktopTurn
		# doesn't also rotate the player.
		get_viewport().set_input_as_handled()


## Turn the held object by this mouse motion: yaw and pitch, roll instead of yaw with Shift.
## Made by the middle button's drag and by the left button's.
func _turn_held(motion: InputEventMouseMotion) -> void:
	if _held_object and not _is_fps_snap() and _hand_hold:
		# In the hand the turn is made in the hand's own frame, on the pose it is held in (a
		# handheld starts screen to you, and can be tipped to show a switch on its edge).
		var hdelta := motion.relative
		if motion.shift_pressed:
			_hand_cam_basis = Basis(Vector3.FORWARD, -hdelta.x * ROT_SENSITIVITY) * _hand_cam_basis
		else:
			_hand_cam_basis = Basis(Vector3.UP, hdelta.x * ROT_SENSITIVITY) * _hand_cam_basis
		_hand_cam_basis = (Basis(Vector3.RIGHT, hdelta.y * ROT_SENSITIVITY) * _hand_cam_basis).orthonormalized()
	elif _held_object and not _is_fps_snap():
		var delta := motion.relative
		# The reverse of aircraft semantics (nose = far side, pointing away from the
		# camera), at the player's request: mouse right -> nose yaws left, mouse up ->
		# nose pitches down. Shift+drag horizontal -> roll, right = counter-clockwise.
		# Axes are built in world space and premultiplied onto the pivot's
		# global basis — Node3D.rotate() expects parent-space axes, so feeding
		# it world-space camera axes skewed the rotation whenever the camera
		# was turned.
		var pitch_axis := global_transform.basis.x.normalized()
		var roll_axis := (-global_transform.basis.z).normalized()
		var flat_fwd := -global_transform.basis.z
		flat_fwd.y = 0.0
		if flat_fwd.length_squared() > 0.0001:
			roll_axis = flat_fwd.normalized()
			pitch_axis = roll_axis.cross(Vector3.UP).normalized()
		var pivot_basis := _hand_pivot.global_basis
		if motion.shift_pressed:
			pivot_basis = Basis(roll_axis, -delta.x * ROT_SENSITIVITY) * pivot_basis
		else:
			pivot_basis = Basis(Vector3.UP, delta.x * ROT_SENSITIVITY) * pivot_basis
		pivot_basis = Basis(pitch_axis, delta.y * ROT_SENSITIVITY) * pivot_basis
		_hand_pivot.global_basis = pivot_basis.orthonormalized()


func _physics_process(delta: float) -> void:
	_clear_stale_left()
	_update_reticle_highlight()

	if not _held_object:
		return
	if get_viewport().use_xr:
		_drop()
		return

	if _is_fps_snap():
		# Lock weapon to camera-local FPS slot — orientation tracks camera exactly
		# so the barrel always points straight ahead.
		_hand_pivot.global_transform = global_transform * FPS_SNAP_LOCAL
		_sync_companion()
	elif _hand_hold:
		_hold_blend = minf(_hold_blend + delta * HAND_BLEND_RATE, 1.0)
		_follow_gaze(delta)
		_hand_pivot.global_transform = _hand_pose(_hold_blend)
		_release_companion()
	else:
		# Standard ray-hold: slide along camera forward at the stored distance
		var fwd := -global_transform.basis.z.normalized()
		_hand_pivot.global_position = global_position + fwd * _grab_dist
		_release_companion()


## True while the desktop hand is holding something (spawn-into-hand gate).
func is_holding() -> bool:
	return _held_object != null


## True while the held object is being turned (the middle drag, or the left one past
## CLICK_DRAG_PX). The pointer aims at nothing meanwhile: left live, a control the turn swung
## under the crosshair lit up and took the next click.
func is_turning() -> bool:
	return _held_object != null and not _is_fps_snap() and (_middle_held or _left_turning)


## True while the held object floats out on the ray rather than being caught in the hand. Its own
## controls are out of reach meanwhile: the angle it hung at decided which switch the crosshair
## met, and a click meant to drop it worked that switch. Caught, they are aimed at on purpose.
func on_ray() -> bool:
	return _held_object != null and not _is_fps_snap() and not _hand_hold


## What the desktop hand is holding, or null.
func held_object() -> XRToolsPickable:
	return _held_object if is_instance_valid(_held_object) else null


## Grab a freshly spawned pickable into the desktop hand (spawn-into-hand).
func grab_spawned(pickable: XRToolsPickable) -> void:
	if _held_object or not is_instance_valid(pickable):
		return
	_grab_target(pickable)


## Cast ray and grab the first XRToolsPickable hit. `inspect` (Shift held): an FPS-snap
## object is held to look at, not to aim.
func _try_grab(inspect := false) -> void:
	if _held_object:
		_drop()
		return

	var interaction := _resolve_interaction_target(true)
	if not interaction.can_grab or not is_instance_valid(interaction.action_node):
		return
	# The resolver now runs down the POINTER's ray, which reaches twice as far as
	# the pickup ray it replaced. Out of arm's reach is out of reach.
	if interaction.distance > MAX_DIST:
		return

	# Something that answers to a click takes the press instead of the grab, and
	# only gives it up if the pointer then travels.
	var clickable := _click_action_node(interaction.action_node)
	if clickable != null:
		_pending_click = clickable
		_pending_grab = interaction.action_node
		_pending_inspect = inspect
		_click_drag = 0.0
		return

	_grab_target(interaction.action_node, inspect)


## The object under the pointer that wants the click for itself, or null. A snap
## zone is asked about what it is HOLDING: the resolver hands back the socket, but
## it is the cart in the tray that knows a click means "push me home".
##
## The object is asked whether the click is claimable RIGHT NOW, not whether it owns
## the method at all — a cartridge carries one wherever it is, and a class-level
## test made every loose cart in the room wait for a drag before it could be picked
## up, with a plain click doing nothing.
func _click_action_node(target: Node3D) -> Node3D:
	var zone := target as XRToolsSnapZone
	var obj: Node3D = InteractionResolver.held_pickable(zone) if zone != null else target
	if obj != null and obj.has_method("desktop_click_available") \
			and obj.desktop_click_available() and obj.has_method("desktop_click_action"):
		return obj
	return null


## Park the companion slot and reconcile who is standing in it.
##
## The pivot is moved FIRST so a companion picked up on this frame lands in the
## corner immediately rather than snapping there next frame from wherever the
## cord had swung it.
func _sync_companion() -> void:
	_companion_pivot.global_transform = global_transform * FPS_SNAP_COMPANION_LOCAL

	var want := _companion_wanted()
	if want == _companion_object:
		return
	_release_companion()
	if not is_instance_valid(want) or not want.can_pick_up(_companion_pivot):
		return
	want.pick_up(_companion_pivot)
	_companion_object = want

	# A companion was not grabbed, it arrived, so its hint panel is answering a
	# question nobody asked — and answering it wrongly: the rotate rows
	# HeldObjectPhysics adds to every desktop grab are dead in an FPS slot, and
	# there is no gesture that puts this one down by itself. Both grab handlers
	# have already run and built the panel by the time pick_up returns, so this
	# takes it back down rather than preventing it. Looked up rather than
	# for_node()'d: a companion with no hint should not be given one.
	var hint := want.get_node_or_null("HeldHint") as HeldHint
	if hint != null:
		hint.hide_now()


## What the held object says should ride the companion slot, if anything.
func _companion_wanted() -> XRToolsPickable:
	if _held_object == null or not _held_object.has_method("desktop_companion"):
		return null
	return _held_object.call("desktop_companion") as XRToolsPickable


func _release_companion() -> void:
	if _companion_object == null:
		return
	var obj := _companion_object
	_companion_object = null
	if is_instance_valid(obj) and obj.is_picked_up() \
			and obj.get_picked_up_by() == _companion_pivot:
		obj.let_go(_companion_pivot, Vector3.ZERO, Vector3.ZERO)
		obj.sleeping = false


## Called by DesktopCompanionHand.drop_object() when the companion is released
## from the far end — a snap zone taking it, or its own script calling drop().
func _on_companion_drop_object() -> void:
	_release_companion()


## Take the held object into the hand. It keeps its place until the blend has carried it to
## the hand pose, so it settles rather than jumps. A handheld takes the orientation it asks for
## (screen toward you, top edge up); anything else keeps the one it has.
func _catch() -> void:
	if _held_object == null:
		return
	_hand_hold = true
	_hold_blend = 0.0
	_catch_from = _hand_pivot.global_transform
	_middle_held = false
	var gaze := global_basis.get_euler(EULER_ORDER_YXZ)
	_hand_pitch = gaze.x
	_hand_yaw = gaze.y
	_hand_focus_local = Vector3.ZERO
	_hand_focus_width = 0.0
	_hand_focus_radius = 0.0
	# Held by its screen(s), found the way F11 finds them: a handheld, a DS's two, a VMU's LCD,
	# a mod's -- anything with a picture surface, with nothing to implement for the hand.
	var facing := screen_hold(_held_object, screens_of(_held_object))
	if not facing.is_empty():
		_hand_focus_local = facing["center"]
		_hand_focus_width = float(facing["width"])
		var seen_all := visual_bounds(_held_object)
		for i in 8:
			_hand_focus_radius = maxf(_hand_focus_radius,
				(seen_all.get_endpoint(i) - _hand_focus_local).length())
	if _hand_focus_width <= 0.0:
		# Nothing with a screen (a cable's plug, a pad, a cartridge): held by the middle of what can
		# be SEEN of it, a little below the centre of the view, so that a plug at the end of a cord is
		# not carried by a corner and turns about itself.
		var seen := visual_bounds(_held_object)
		if seen.size != Vector3.ZERO:
			_hand_focus_local = seen.get_center()
			_hand_focus_radius = seen.size.length() * 0.5
	if not facing.is_empty():
		_hand_cam_basis = screen_hold_basis(_hand_point(), facing["normal"], facing["up"])
	else:
		_hand_cam_basis = _hand_frame().inverse() * _hand_pivot.global_basis
	_hand_default_basis = _hand_cam_basis
	HeldHint.note_on(_held_object, &"hand_hold_desktop")


## Put a caught object back as it was caught: orientation as first held, hand turned to where you
## look now. Eased from where it is, like the catch itself.
func _reset_hand_pose() -> void:
	_catch_from = _hand_pivot.global_transform
	_hold_blend = 0.0
	var gaze := global_basis.get_euler(EULER_ORDER_YXZ)
	_hand_pitch = gaze.x
	_hand_yaw = gaze.y
	_hand_cam_basis = _hand_default_basis


## Send a caught object back out to float on the ray, where the hand had it.
## Back out onto the ray at the pull-in limit, where it was caught: one notch out leaves the hand
## and one notch in catches it again. It used to resume 45 cm out, four notches further than the
## player expected (2026-10-22).
func _release_to_ray() -> void:
	_hand_hold = false
	_grab_dist = MIN_DIST


## The screens `obj` has, as TvFullscreen finds them for F11, lit or not. One query for every
## device with a picture; the hand used to ask RetroSystem for methods of its own, so only a
## console's screen counted and a VMU's LCD did not.
static func screens_of(obj: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var device := TvFullscreen.device_from_node(obj)
	if device == null:
		return out
	for panel: Dictionary in TvFullscreen.panels_for(device, true):
		var mesh := panel.get("mesh") as MeshInstance3D
		if is_instance_valid(mesh) and mesh.mesh != null and not out.has(mesh):
			out.append(mesh)
	return out


## How `root` is held by `screens`, in root's own space: {center, width, normal, up}, or {} for
## no screen. center: the middle of them all (a DS by both). width: the widest one across its
## own face. normal / up: the face and top edge of the one lying flattest on the body (+Y up),
## so a clamshell is held by its base with its lid leaning back. Read off each screen's own
## transform and mesh, never assumed: a handheld's faces the body's +Y, a VMU's +Z. Pure.
static func screen_hold(root: Node3D, screens: Array[MeshInstance3D]) -> Dictionary:
	if screens.is_empty():
		return {}
	var to_root := root.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var width := 0.0
	var best := -INF
	var normal := Vector3.UP
	var up := Vector3.FORWARD
	for screen: MeshInstance3D in screens:
		var xf := to_root * screen.global_transform
		var axes := _screen_axes(screen.mesh)
		var n := (xf.basis * axes[0]).normalized()
		var u := (xf.basis * axes[1]).normalized()
		var right := u.cross(n).normalized()
		var box := screen.mesh.get_aabb()
		var a := INF
		var b := -INF
		for i in 8:
			var p := xf * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
			a = minf(a, p.dot(right))
			b = maxf(b, p.dot(right))
		width = maxf(width, b - a)
		if n.dot(Vector3.UP) > best:
			best = n.dot(Vector3.UP)
			normal = n
			up = u
	return {"center": (lo + hi) * 0.5, "width": width, "normal": normal, "up": up}


## A screen mesh's face and top edge in its own space. A QuadMesh or PlaneMesh says by its
## `orientation` (a QuadMesh faces +Z with its top at +Y; a PlaneMesh faces +Y, top at -Z);
## any other mesh is taken as a QuadMesh would be.
static func _screen_axes(mesh: Mesh) -> Array[Vector3]:
	if mesh is PlaneMesh:
		match (mesh as PlaneMesh).orientation:
			PlaneMesh.FACE_X:
				return [Vector3.RIGHT, Vector3.UP]
			PlaneMesh.FACE_Y:
				return [Vector3.UP, Vector3.FORWARD]
	return [Vector3.BACK, Vector3.UP]


## The orientation, as a basis in the hand's frame, that turns a screen facing `normal` with its
## top toward `up` (both in the thing's own space) toward the eye, top as near straight up as
## that allows, for a thing whose middle is at `at` in the hand's frame. Pure.
static func screen_hold_basis(at: Vector3, normal: Vector3, up: Vector3) -> Basis:
	var eye := (-at).normalized()
	var upright := Vector3.UP - eye * Vector3.UP.dot(eye)
	if upright.length_squared() < 0.0001:
		upright = Vector3.BACK
	upright = upright.normalized()
	var n := normal.normalized()
	var u := (up - n * up.dot(n)).normalized()
	var own := Basis(u.cross(n), u, n)
	var want := Basis(upright.cross(eye), upright, eye)
	return want * own.inverse()


## screen_hold_basis for a screen on the +Y face with its top edge at -Z: how every handheld
## shell is built. Kept because the facing tests hold the general case to these numbers.
static func screen_facing_basis(at: Vector3) -> Basis:
	return screen_hold_basis(at, Vector3.UP, Vector3.FORWARD)


## The box around everything of `root` that can be seen, in root's own space: its visible
## meshes, corners and all, so a turned or scaled part counts as it is. Zero size when there is
## nothing to see. Pure, so a test can hand it a tree.
static func visual_bounds(root: Node3D) -> AABB:
	var to_root := root.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var found := false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or node.get_parent() is HeldHint:
			continue
		var box := mesh.get_aabb()
		var mesh_to_root := to_root * mesh.global_transform
		for i in 8:
			var p := mesh_to_root * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
			found = true
	return AABB(lo, hi - lo) if found else AABB()


## One axis of the hand trailing the gaze: `current` stays put while `target` is within `dead` of
## it, and otherwise moves `weight` (0..1) of the way to the edge of that zone nearest the
## target -- so it never snaps, and never ends further behind than the zone allows.
static func follow_toward(current: float, target: float, dead: float, weight: float) -> float:
	var d := angle_difference(current, target)
	if absf(d) <= dead:
		return current
	return current + (d - signf(d) * dead) * clampf(weight, 0.0, 1.0)


## The frame the hand holds things in: yaw and pitch, no roll.
func _hand_frame() -> Basis:
	return Basis.from_euler(Vector3(_hand_pitch, _hand_yaw, 0.0), EULER_ORDER_YXZ)


## Let the hand come round after the gaze, but only once the gaze has left the small dead zone
## around it: the nearer edge of the zone is where the hand ends up, so it never snaps.
func _follow_gaze(delta: float) -> void:
	var gaze := global_basis.get_euler(EULER_ORDER_YXZ)
	var weight := 1.0 - exp(-HAND_FOLLOW_RATE * delta)
	_hand_yaw = follow_toward(_hand_yaw, gaze.y, deg_to_rad(HAND_DEADZONE_YAW), weight)
	_hand_pitch = follow_toward(_hand_pitch, gaze.x, deg_to_rad(HAND_DEADZONE_PITCH), weight)


## How far ahead a screen of this width must stand to fill `fraction` of the view's width, for a
## camera of this vertical field of view and aspect, kept between the near and far limits.
## How far ahead something with no screen and `size` across stands so that it fills
## HAND_OBJECT_FRACTION of the view's width: no nearer than HAND_FOCUS_MIN, no further than
## HAND_LOCAL's 40 cm, where everything used to sit.
static func object_distance(size: float, vfov_degrees: float, aspect: float) -> float:
	var view := 2.0 * tan(deg_to_rad(clampf(vfov_degrees, 5.0, 170.0)) * 0.5) * maxf(aspect, 0.1)
	return clampf(size / (HAND_OBJECT_FRACTION * view), HAND_FOCUS_MIN, -HAND_LOCAL.z)


static func focus_distance(width: float, vfov_degrees: float, aspect: float) -> float:
	var view := 2.0 * tan(deg_to_rad(clampf(vfov_degrees, 5.0, 170.0)) * 0.5) * maxf(aspect, 0.1)
	return clampf(width / (HAND_SCREEN_FRACTION * view), HAND_FOCUS_MIN, HAND_FOCUS_MAX)


## Where the held point sits, in the hand's frame: straight ahead at the crosshair for a handheld
## held by its screen, the usual spot below it for anything else.
func _hand_point() -> Vector3:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var cam := get_viewport().get_camera_3d()
	var fov := cam.fov if cam != null else 75.0
	if _hand_focus_width <= 0.0:
		# A little below the line of sight: further for something big, nearer for something
		# small, so either way it is in the view at a size you can see.
		if _hand_focus_radius > HAND_ROOM_REACH:
			return HAND_LOCAL * (_hand_focus_radius / HAND_ROOM_REACH)
		return HAND_LOCAL * (object_distance(_hand_focus_radius * 2.0, fov, aspect) / -HAND_LOCAL.z)
	return Vector3(0.0, 0.0, -focus_distance(_hand_focus_width, fov, aspect))


## Where the pivot is while the object is in the hand, `t` of the way from where it was caught.
## What is carried to the hand is the held POINT (the screen's middle, or the origin), so that
## turning the thing in the hand turns it about that point.
func _hand_pose(t: float) -> Transform3D:
	var k := ease_in_out(t)
	var frame := _hand_frame()
	var target_basis := frame * _hand_cam_basis
	var basis_now := _catch_from.basis.slerp(target_basis, k).orthonormalized()
	var from_point := _catch_from.origin + _catch_from.basis * _hand_focus_local
	var to_point := global_position + frame * _hand_point()
	var point_now := from_point.lerp(to_point, k)
	return Transform3D(basis_now, point_now - basis_now * _hand_focus_local)


## The left press's state ends with its release, but the release reaches _unhandled_input only if
## nothing took it first: a menu opened mid-press, a 2D panel under the crosshair. Left set, every
## later plain mouse motion would turn the held object instead of the player, and MovementDesktopTurn
## would ignore the mouse for good. So it is also ended whenever the button is simply not down.
func _clear_stale_left() -> void:
	if not (left_drag or _drop_armed or _left_turning):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	left_drag = false
	_drop_armed = false
	_left_turning = false


## A gentle start and stop for the blend.
static func ease_in_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## True when the crosshair is on one of the held thing's controls, or any control: a switch,
## a slider, a button the pointer would work. The same question the pointer asks every frame,
## asked fresh, so a press is judged against exactly what is lit.
func _crosshair_on_control() -> bool:
	var t := _resolve_interaction_target(true)
	return t != null and t.is_valid() and t.can_activate \
		and is_instance_valid(t.pointer_event_target)


## The click went to a control under the crosshair, so what the hand holds stays
## in it: said in the log, because from the chair it looks like a socket refusing
## a plug. Shift+click is the control's too; looking off it drops.
func _log_click_kept() -> void:
	var t := _resolve_interaction_target(true)
	var control := "?"
	if t != null and is_instance_valid(t.pointer_event_target):
		control = str(t.pointer_event_target.name)
		var owner_node := t.pointer_event_target.get_parent()
		if owner_node != null:
			control = "%s/%s" % [owner_node.name, control]
	print("[Desktop] the click went to %s under the crosshair, so %s stays in the hand (look off the control to drop it)" % [
		control, str(_held_object.name) if _held_object else "?"])


## Drop the currently held object.
func _drop() -> void:
	_release_companion()
	_end_inspect()
	if _held_object:
		# Only when the modifier was actually required — a plain-click drop taught
		# the player nothing.
		if _is_fps_snap() or _needs_shift_drop():
			HeldHint.note_on(_held_object, &"drop_desktop")
		var obj := _held_object
		_held_object = null
		if obj.is_picked_up() and obj.get_picked_up_by() == _hand_pivot:
			obj.let_go(_hand_pivot, Vector3.ZERO, Vector3.ZERO)
			obj.sleeping = false
	_middle_held = false
	_hand_hold = false
	_drop_armed = false
	_left_turning = false
	left_drag = false


## Called by DesktopHandPivot.drop_object() when pickable.gd notifies the
## grabber of a drop (e.g. from a snap zone or external pickable.drop() call).
func _on_pivot_drop_object() -> void:
	_release_companion()
	_end_inspect()
	if _held_object and _held_object.is_picked_up() and _held_object.get_picked_up_by() == _hand_pivot:
		var obj := _held_object
		_held_object = null
		obj.let_go(_hand_pivot, Vector3.ZERO, Vector3.ZERO)
		obj.sleeping = false
		_middle_held = false
		_hand_hold = false
		_drop_armed = false
		_left_turning = false
		left_drag = false
		return
	_held_object = null
	_middle_held = false
	_hand_hold = false
	_drop_armed = false
	_left_turning = false
	left_drag = false


## Returns true when the held object wants FPS-snap positioning, and was not picked up to
## look at.
func _is_fps_snap() -> bool:
	return _held_object != null and not _inspect and _held_object.get("desktop_fps_snap")


## True while `obj` is held on desktop to look at (picked up with Shift), not to play: an
## FPS-snap device asks in its grab handler, and does not take the game's input.
static func inspecting(obj: Node) -> bool:
	return is_instance_valid(obj) and obj.get_meta(INSPECT_META, false) == true


## The inspect hold ends with the hold, whichever way it ends.
func _end_inspect() -> void:
	if is_instance_valid(_held_object) and _held_object.has_meta(INSPECT_META):
		_held_object.remove_meta(INSPECT_META)
	_inspect = false


## True when the held object claims plain left-click as its own input
## (RetroMouse) — dropping then needs Shift+click, like the light gun.
func _needs_shift_drop() -> bool:
	return _held_object != null and _held_object.get("desktop_shift_drop") == true


func _update_reticle_highlight() -> void:
	_dim_held_outline()
	if get_viewport().use_xr or _held_object:
		_set_hovered_target(null)
		return

	var interaction := _resolve_interaction_target(false)
	if not interaction.can_grab or not is_instance_valid(interaction.highlight_node):
		_set_hovered_target(null)
		return

	_set_hovered_target(interaction.highlight_node)


## While the crosshair is on one of the held object's controls, its own outline is switched off so
## that the control (which lights itself) is what reads as aimed at.
func _dim_held_outline() -> void:
	var want: PickableHighlight = null
	if _held_object != null and not get_viewport().use_xr:
		var t := _resolve_interaction_target(false)
		if t != null and t.is_valid() and t.can_activate and is_instance_valid(t.pointer_event_target):
			want = _held_highlight()
	if want == _dimmed:
		return
	if is_instance_valid(_dimmed):
		_dimmed.set_suppressed(false)
	_dimmed = want
	if _dimmed != null:
		_dimmed.set_suppressed(true)


## Looked up once for each object held (this is asked every physics frame the crosshair is on one
## of its controls), and again only if the one found has gone.
func _held_highlight() -> PickableHighlight:
	if _highlight_of != _held_object or not is_instance_valid(_highlight):
		_highlight_of = _held_object
		var found := _held_object.find_children("*", "PickableHighlight", true, false)
		_highlight = found[0] as PickableHighlight if not found.is_empty() else null
	return _highlight


func _set_hovered_target(target: Node3D) -> void:
	if target == _hovered_target:
		return

	if _hovered_target and _hovered_target.has_method("request_highlight"):
		_hovered_target.request_highlight(self, false)

	_hovered_target = target

	if _hovered_target and _hovered_target.has_method("request_highlight"):
		_hovered_target.request_highlight(self, true)


func _grab_target(target: Node3D, inspect := false) -> void:
	var pickable: XRToolsPickable = null
	var snap_zone := target as XRToolsSnapZone
	if snap_zone:
		pickable = InteractionResolver.held_pickable(snap_zone)
	else:
		pickable = target as XRToolsPickable

	if not pickable:
		return
	# Asked BEFORE the zone lets go, and only about the rules that do not depend on
	# the zone holding it — can_pick_up() answers "already held" while it does. A
	# refusal taken after the drop leaves the object released by the socket and
	# picked up by nobody, which is how a clamped cart falls out of a console.
	if not pickable.enabled \
			or (pickable.has_method("is_clamped") and pickable.is_clamped()):
		return
	if snap_zone:
		snap_zone.drop_object()
	if not pickable.can_pick_up(_hand_pivot):
		return

	# Position the pivot at the object's origin so the grab offset is ~zero,
	# giving clean behaviour for both ray-hold and FPS-snap modes.
	_grab_dist = clampf(
		global_position.distance_to(pickable.global_position),
		MIN_DIST, MAX_DIST)
	_hand_pivot.global_transform = pickable.global_transform

	_set_hovered_target(null)
	_hand_hold = false
	_drop_armed = false
	_left_turning = false
	left_drag = false
	# Before pick_up: the object's grab handler asks whether it is being inspected.
	_inspect = inspect and pickable.get("desktop_fps_snap") == true
	if _inspect:
		pickable.set_meta(INSPECT_META, true)
	pickable.pick_up(_hand_pivot)
	_held_object = pickable


## What the crosshair is on right now, freshly cast.
func aimed_target() -> InteractionTarget:
	return _resolve_interaction_target(true)


func _resolve_interaction_target(refresh: bool) -> InteractionTarget:
	if not is_instance_valid(_desktop_pointer):
		return InteractionTargetType.none()

	if refresh:
		return _desktop_pointer.resolve_interaction_target()
	return _desktop_pointer.get_resolved_target()
