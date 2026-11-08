## PokeWake — the poke widgets in reach of a fingertip are awake; the rest sleep.
##
## Every VRButton, VRSlider and VRKnob used to ask PokeTip, every frame, whether a
## hand was near it: 137 buttons alone in the Starlight Arcade, each a script call
## and a pair of distance tests, for a room where at most a handful are ever in
## reach. The widgets are Area3Ds on the pointable layer, so the physics engine
## already keeps them in a spatial index that follows every console carried about.
## One sphere query a fingertip, a frame, finds the few in reach and wakes them;
## a widget that has been idle for SLEEP_AFTER frames switches its own _process off
## again (tick). The widget's code is unchanged while it runs: this only decides
## when it runs.
##
## Created on first use (ensure) as a child of the root, not an autoload: it
## serves widgets and needs nothing at boot.
class_name PokeWake
extends Node

## Frames a widget must be idle (no hand within PokeTip.WIDGET_NEAR, nothing held,
## hovered or selected) before it sleeps.
const SLEEP_AFTER := 30
## The query reaches past the widgets' own gate, so the edge cannot flap.
const WAKE_RADIUS := PokeTip.WIDGET_NEAR + 0.1
const MAX_RESULTS := 256
## Set on a widget something else has switched off (VRButton.set_interactive,
## focus mode): the scanner must not switch it back on.
const META_OFF := &"poke_wake_off"
const META_SUSPENDED := &"poke_wake_suspended"

## Off: nothing sleeps, every widget polls as it always did. A kill switch and
## the control leg of a measurement.
static var enabled := true
static var _instance: PokeWake = null

var _controllers: Array[XRController3D] = []
var _query := PhysicsShapeQueryParameters3D.new()
var _woken_total := 0


## Make sure the scanner exists. Called from each widget's _ready.
static func ensure(from: Node) -> void:
	if is_instance_valid(_instance) or not from.is_inside_tree():
		return
	_instance = PokeWake.new()
	_instance.name = "PokeWake"
	from.get_tree().root.add_child.call_deferred(_instance)


## Switch a sleeping widget back on, unless something else has it switched off.
static func wake(widget: Node) -> void:
	if widget.is_processing() or widget.has_meta(META_OFF) or widget.has_meta(META_SUSPENDED):
		return
	widget.set_process(true)


## A widget's last line of _process: `busy` is whether anything needed it this
## frame, `idle` its frame count so far. Returns the new count; puts the widget to
## sleep once it has been idle long enough AND the scanner could find it again.
static func tick(widget: Area3D, busy: bool, idle: int) -> int:
	if busy or not enabled:
		return 0
	idle += 1
	if idle < SLEEP_AFTER:
		return idle
	if can_sleep(widget):
		widget.set_process(false)
	return 0


## Whether the scanner would see `widget`: on the pointable layer, with a shape
## switched on, in the scanner's world. A widget it could not find must never
## sleep, or it is a button that ignores a finger.
static func can_sleep(widget: Area3D) -> bool:
	if not enabled or not is_instance_valid(_instance) or not _instance.is_inside_tree():
		return false
	if widget.collision_layer & VRButton.POINTABLE_LAYER == 0:
		return false
	if widget.get_world_3d() != _instance.get_viewport().get_world_3d():
		return false
	for owner_id in widget.get_shape_owners():
		if not widget.is_shape_owner_disabled(owner_id) \
				and widget.shape_owner_get_shape_count(owner_id) > 0:
			return true
	return false


static func is_poke_widget(node: Object) -> bool:
	return node is VRButton or node is VRSlider or node is VRKnob


func _ready() -> void:
	# Ahead of the widgets, so one woken this frame is in step from the next.
	process_priority = -1000
	var sphere := SphereShape3D.new()
	sphere.radius = WAKE_RADIUS
	_query.shape = sphere
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_query.collision_mask = VRButton.POINTABLE_LAYER
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)
	# A hand made after the widgets (a rig built late, a test's tracked finger)
	# must be scanned from its first frame, not on some later refresh.
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	print("[PokeWake] scanning for fingertips (%d controller(s)); widgets sleep after %d idle frames"
		% [_controllers.size(), SLEEP_AFTER])


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _on_node_added(node: Node) -> void:
	if node is XRController3D and not _controllers.has(node):
		_controllers.append(node as XRController3D)


func _on_node_removed(node: Node) -> void:
	if node is XRController3D:
		_controllers.erase(node)


func _process(_delta: float) -> void:
	if not enabled or _controllers.is_empty():
		return
	var space := get_viewport().get_world_3d().direct_space_state
	if space == null:
		return
	for ctrl in _controllers:
		if not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
			continue
		# Not gated on get_is_active(): neither is the widgets' own first test
		# (PokeTip.any_tip_within), and waking one that then finds no qualified
		# hand costs a frame of what it always did.
		_query.transform = Transform3D(Basis(), PokeTip.tip_of(ctrl))
		var hits := space.intersect_shape(_query, MAX_RESULTS)
		if hits.size() >= MAX_RESULTS:
			push_warning("[PokeWake] %d pointable areas round one fingertip: some may not wake" % hits.size())
		for hit: Dictionary in hits:
			var widget: Object = hit.get("collider")
			if is_poke_widget(widget) and not (widget as Node).is_processing():
				wake(widget as Node)
				_woken_total += 1


## How many wakes so far, for a probe or a test.
func woken_total() -> int:
	return _woken_total
