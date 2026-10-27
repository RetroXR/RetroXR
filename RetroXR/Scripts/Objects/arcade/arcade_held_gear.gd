## ArcadeHeldGear — something an arcade cabinet is WIRED to and a player holds: a Taiko drummer's sticks.
##
## The rule the cabinet's guns follow (arcade.md "Guns are captive"), for a thing that is not a gun and plugs into no port: it is built with the cabinet (ArcadeGearRack) and freed with it, it stays
## out of the "spawned" group so nothing saves it and nothing syncs it as an object (the cabinet builds it again every time), it lies in a cradle of the cabinet (a snap zone the rack builds: `captive_well`)
## and comes out of it in a hand, it is held while the grip is held, and a cord ties it to the cabinet. What the thing DOES with the game is its own (ArcadeDrumstick).
##
## THE CORD is a VerletRope between this thing's `CableAttachPoint` and `cord_anchor`, a node of the cabinet where it goes in, laid on `cord_route` (CaptiveCord.hanging_route) so a stowed cord hangs
## down the front instead of packing into arches. It does not hold the thing back: a hand that takes it further than the cord reaches LETS GO (the stick falls and hangs), and a thing lying beyond
## the reach is reeled in (PlugTether, swept, as every cord's owner does).
##
## ON THE DESKTOP the player's hand is the mouse: a thing that declares `desktop_fps_snap` rides in the lower right of the view, and one that names a COMPANION (the other of its pair) brings it to the lower
## left (DesktopPickup), so a drummer has a stick in each hand. Which clicks do what is the subclass's.
class_name ArcadeHeldGear
extends XRToolsPickable

const CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
## How far above the thing its held hint floats.
const HINT_HEIGHT := 0.14
## A hand may take it this much further than the cord reaches before the thing is let go, and a thing is reeled in past the reach itself.
const LET_GO_SLACK := 0.10
## How far its reach to its cradle counts, on top of the cradle's own grab distance (XRToolsGrabDriver._get_preview_radius asks `preview_radius`). Not the length of the thing: a stick held by its
## grip reaches a quarter of a metre past the hand, and the cradle beside a drum would take it back, and show it in the cradle, wherever over the drum it was played.
const PREVIEW_RADIUS := 0.03
## A thing let go of is watched this many physics steps, and pushed down at this speed (m/s) if it hangs asleep with nothing under it (`_wake_if_hung`); "nothing under it" is this far down (m).
const HUNG_AFTER_STEPS := 4
const HUNG_PUSH := 0.3
const HUNG_SUPPORT := 0.04

## The cord's rest length (the rack sets it from the gear's table row).
var cord_length := 0.95
## Wired to the machine and kept out of "spawned": set BEFORE add_child, so the thing's own _ready never joins the group (the guns' rule).
var captive := false
## The cradle this thing came out of, a snap zone of the cabinet (ArcadeGearRack): let go over it and the zone takes the thing back.
var captive_well: XRToolsSnapZone = null
## The cord's lay at rest, in world space, from the thing to the cabinet's entry; and the cabinet's node it goes into.
var cord_route := PackedVector3Array()
var cord_anchor: Node3D = null
## Whose it is: the cabinet's player (its panel and its port), and the player's left (0) or right (1) one of a pair.
var player := 0
var side := 0
## What it is, by the table's name ("drumstick", "guitar").
var kind := ""
## The other of the pair, for the desktop's other hand.
var mate: ArcadeHeldGear = null
## The cabinet's model (RetroSystemModelArcadeCabinet) it belongs to, for the panel and the input it feeds.
var cabinet: Node3D = null
## Desktop: rides in the camera's lower right while held, and takes no mouse-look turn (DesktopPickup).
var desktop_fps_snap := true

## Physics steps left before a thing just let go of is looked at for hanging asleep in the air (0: not watched).
var _hung_watch := 0
var _cable: Node3D = null
var _rope: VerletRope = null
var _hint: HeldHint = null
## Held by the desktop's hand (either of its two pivots), and by which VR controller.
var _desktop_held := false

## Where the cord is tied on (a `CableAttachPoint` somewhere in the scene: a thing that moves in parts carries it with the part).
@onready var _cable_attach: Node3D = find_child("CableAttachPoint", true, false) as Node3D


func _ready() -> void:
	super._ready()
	# A cabinet's thing is held while the grip is held: let go and the hand lets go.
	press_to_hold = captive
	if not captive:
		add_to_group("spawned")
	add_to_group("arcade_gear")
	grabbed.connect(_on_grabbed_signal)
	dropped.connect(_on_dropped_signal)
	_hint = HeldHint.attach(self, true, hint_height())
	_spawn_cord()


func _exit_tree() -> void:
	# The cord is parented to the scene, not to the thing (a rope between two bodies cannot be parented to either): any way this goes (the cabinet morphing, a room torn down) takes it too.
	if is_instance_valid(_cable):
		_cable.queue_free()
	super._exit_tree()


## The cord, if there is a cabinet node for it to go into. Deferred: a thing is made while its parents are still being built.
func _spawn_cord() -> void:
	if cord_anchor == null:
		return
	_cable = CABLE_SCENE.instantiate()
	# The generic lead's plug is not wanted: the cord ends at the cabinet's own node, which is not a body anything can pull.
	var plug := _cable.get_node_or_null("ControllerPlug")
	if plug != null:
		_cable.remove_child(plug)
		plug.free()
	_add_cord_to_scene.call_deferred()


func _add_cord_to_scene() -> void:
	if not is_inside_tree() or _cable == null or not is_instance_valid(cord_anchor):
		return
	get_tree().current_scene.add_child(_cable)
	_rope = _cable.get_node("VerletRope") as VerletRope
	_rope.start_node = _cable_attach
	_rope.end_node = cord_anchor
	_rope.end_anchor_offset = Vector3.ZERO
	CaptiveCord.resize(_rope, cord_length)
	_rope._init_points()
	if cord_route.size() >= 2 and not CaptiveCord.lay(_rope, cord_route):
		push_warning("ArcadeHeldGear: the cord's route was refused by the rope")


## The cord (null before it exists, and for a thing with no cabinet).
func cord() -> VerletRope:
	return _rope


## How far from its seat in the cradle a hand still takes it out, and it is put back (the cradle's grab distance): a stick's grip is a hand's width, a guitar's body wider.
func well_reach() -> float:
	return 0.10


## The pad bits it holds down now, ORed into its player's state every frame (ArcadeInput._with_hands): a guitar's frets and wail. A thing that only taps a button (a drumstick: ArcadeInput.tap_pad_bit) holds none.
func held_pad_bits() -> int:
	return 0


## The thumbsticks it stands in for, [left, right] (x right, y up, as a controller reads them): a guitar's effect knob is the right stick's X.
func held_sticks() -> Array[Vector2]:
	return [Vector2.ZERO, Vector2.ZERO]


## How far above its origin the thing's held hint floats (a guitar is taller than a stick).
func hint_height() -> float:
	return HINT_HEIGHT


## What the grab driver and the pickup function ask for the preview of a socket (see PREVIEW_RADIUS).
func preview_radius() -> float:
	return PREVIEW_RADIUS


## Where the cord is tied on, in the world.
func cord_boss() -> Vector3:
	return _cable_attach.global_position if _cable_attach != null else global_position


func cable_instance() -> Node3D:
	return _cable


func _physics_process(delta: float) -> void:
	_tether()
	_tick(delta)
	if _hung_watch > 0:
		_hung_watch -= 1
		if _hung_watch == 0:
			_wake_if_hung()


## What the subclass does every physics frame (a hit, an animation).
func _tick(_delta: float) -> void:
	pass


## The cord's reach, as far as this thing may go from where it goes into the cabinet.
func reach() -> float:
	return cord_length


func _tether() -> void:
	if cord_anchor == null or not is_instance_valid(cord_anchor) or _cable_attach == null:
		return
	var from := cord_anchor.global_position
	var at := _cable_attach.global_position
	if is_picked_up():
		# A hand that walks off with it lets go, and it falls where it is.
		if at.distance_to(from) > reach() + LET_GO_SLACK:
			drop()
	else:
		PlugTether.reel_in(self, at, from, reach())


# ── held ─────────────────────────────────────────────────────────────────────

## The rows the room teaches every desktop grab (HeldObjectPhysics: turn it in the air, hold it in the hand) say nothing true of a thing that rides in the view's corner.
const RAY_HOLD_ROWS: Array[StringName] = [&"rotate_yaw", &"rotate_roll", &"hand_hold_desktop"]


func _on_grabbed_signal(_pickable: Node3D, by: Node3D) -> void:
	_hung_watch = 0
	var pickup := by as XRToolsFunctionPickup
	_prepare_hint(by)
	# Only a HAND holding it shows how to put it down: a snap zone taking it (the cradle) is not a hold.
	if _hint != null and (pickup != null or by.is_in_group("desktop_hand")):
		if desktop_fps_snap and by.is_in_group("desktop_hand"):
			for id in RAY_HOLD_ROWS:
				_hint.remove_row(id)
		_hint.on_grabbed(by)
	_desktop_held = by.is_in_group("desktop_hand")
	if pickup != null and pickup.get_controller() != null:
		_on_taken_by_controller(pickup.get_controller())


func _on_dropped_signal(_pickable: Node3D) -> void:
	if _hint != null:
		_hint.on_dropped()
	_desktop_held = false
	_on_let_go()
	_hung_watch = HUNG_AFTER_STEPS


## The second of a pair let go of together with the first, in the air, was found dynamic, awake for one step and then asleep with gravity on it and nothing under it: it hung there until something
## touched it, and `sleeping = false` did not wake it, a velocity did (the open "controller that will not drop", quest-device.md: this is the case that reproduces it). A thing let go of is watched
## for a few steps (`_hung_watch`, counted in `_physics_process`: no coroutine to outlive it), and one that is asleep in the air is pushed down.
func _wake_if_hung() -> void:
	# The server's word, not only the node's: the node's flag is written when the body next reports, and a body asleep reports nothing.
	var asleep := sleeping or bool(PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING))
	if is_picked_up() or freeze or not asleep or gravity_scale <= 0.0:
		return
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * HUNG_SUPPORT, collision_mask)
	var own: Array[RID] = [get_rid()]
	for body: Node in find_children("*", "CollisionObject3D", true, false):
		own.append((body as CollisionObject3D).get_rid())
	query.exclude = own
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	linear_velocity = Vector3.DOWN * HUNG_PUSH


## A hand has arrived, before the hint is shown: a thing whose rows depend on how it is held (a guitar's two ends) declares them again here (`replace_rows`).
func _prepare_hint(_by: Node3D) -> void:
	pass


## A VR controller took hold: the subclass blocks what it must (a laser, a stick's locomotion).
func _on_taken_by_controller(_ctrl: XRController3D) -> void:
	pass


## Let go of, by a hand or a snap zone.
func _on_let_go() -> void:
	pass


## The VR controller holding this, or null (in its cradle, on the floor, or in the desktop's hand).
func holding_controller() -> XRController3D:
	return get_picked_up_by_controller() if is_picked_up() else null


## Whether the desktop's hand has it.
func held_by_desktop() -> bool:
	return _desktop_held and is_picked_up()


## The other of the pair, for the desktop's other hand (DesktopPickup reads this every frame while this is the thing in the hand). It is taken out of its own cradle for the hand: a thing a snap zone
## holds is not for the taking (can_pick_up), which left the second stick lying in its cradle with the first in the hand and the clicks all on one.
func desktop_companion() -> XRToolsPickable:
	if not is_instance_valid(mate) or mate == self:
		return null
	if held_by_desktop() and is_instance_valid(mate.captive_well) and mate.captive_well.picked_up_object == mate:
		mate.captive_well.drop_object()
	return mate


## Rows the cabinet adds to this thing's held hint: [id, platform, glyphs, caption] (HeldHint). The subclass says how to use it.
func set_rows(rows: Array) -> void:
	if _hint == null:
		return
	for row: Array in rows:
		_hint.add_row(row[0], row[1], row[2], row[3], HeldHint.WHEN_HELD)


## The same, replacing rows of those ids already declared (a hint is declared once and a row of an id already there is ignored).
func replace_rows(rows: Array) -> void:
	if _hint == null:
		return
	for row: Array in rows:
		_hint.remove_row(row[0])
	set_rows(rows)
