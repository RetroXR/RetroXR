## FocusMode — VR: point the right hand at a TV or handheld and press the right
## stick; its picture moves to a FocusScreen and the room stops being drawn. The
## same gesture on the screen brings the room back.
##
## The room is hidden, not unloaded. Every direct child of the current scene except
## the player rig goes invisible and gets back the visibility it had. Kept drawn:
## whatever a hand has held since focus began, the focused handheld, every device and
## lead wired to the focused machine, and whatever is seated in a socket on any of
## those. Hidden things keep their bodies, so their pickables and poke widgets are
## switched off and the lasers see only the screen.
class_name FocusMode
extends Node3D

const BLOCK_OWNER := &"focus_mode"
## Seconds between keep sweeps. A hidden child that shows itself is re-hidden
## every frame.
const KEEP_INTERVAL := 0.1
const AMBIENT := Color(0.45, 0.45, 0.45)

var _camera: Camera3D = null
var _right_hand: Node3D = null
var _hands: Array[Node3D] = []
var _pointers: Array[Node] = []
var _pickups: Array[Node] = []
var _loco: LocomotionManager = null
var _menu_panel: Node3D = null

var _screen: FocusScreen = null
var _device: WeakRef = null
var _room: Node = null
var _rig_top: Node = null

## Hidden room child -> the visible it had.
var _prior_visible: Dictionary = {}
## Hidden room child -> {"pickables": {node: enabled}, "widgets": {node: processing}}.
var _suspended: Dictionary = {}
## Room children a hand has held since focus began.
var _held: Dictionary = {}
var _pointer_masks: Dictionary = {}
var _prior_env: Environment = null
var _prior_screen_lights := true
var _prior_blend := -1
var _prior_transparent_bg := false
var _light: DirectionalLight3D = null
var _menu_was_open := false
var _keep_clock := 0.0
var _refresh_queued := false
var _audio_held: WeakRef = null


func _ready() -> void:
	set_process(false)
	var rig := get_parent() as PlayerRig
	if rig == null:
		return
	# By path: a child is ready before its parent, so the rig's @onready vars are null.
	var origin := "Staging/XROrigin3D/"
	var hands: Array[Node3D] = []
	var pointers: Array[Node] = []
	var pickups: Array[Node] = []
	for hand_name: String in ["LeftController", "RightController"]:
		var hand := rig.get_node_or_null(origin + hand_name) as Node3D
		if hand == null:
			continue
		hands.append(hand)
		var pointer := hand.get_node_or_null("FunctionPointer")
		if pointer != null:
			pointers.append(pointer)
		var pickup := hand.get_node_or_null("FunctionPickup")
		if pickup != null:
			pickups.append(pickup)
	var right := rig.get_node_or_null(origin + "RightController") as XRController3D
	configure(rig.get_node_or_null(origin + "XRCamera3D") as Camera3D, right, hands,
		pointers, pickups, rig.get_node_or_null("LocomotionManager") as LocomotionManager,
		rig.get_node_or_null("SpawnMenuController/SpawnMenuViewport") as Node3D)
	if right != null:
		right.button_pressed.connect(_on_right_button)


func configure(camera: Camera3D, right_hand: Node3D, hands: Array[Node3D],
		pointers: Array[Node], pickups: Array[Node], loco: LocomotionManager,
		menu_panel: Node3D) -> void:
	_camera = camera
	_right_hand = right_hand
	_hands = hands
	_pointers = pointers
	_pickups = pickups
	_loco = loco
	_menu_panel = menu_panel


func is_active() -> bool:
	return _screen != null


func screen() -> FocusScreen:
	return _screen


func _on_right_button(action: String) -> void:
	if action != "primary_click" or not get_viewport().use_xr or _right_hand == null:
		return
	var pointer := _right_hand.get_node_or_null("FunctionPointer") as Node3D
	if pointer == null or not pointer.visible:
		return
	toggle_from(pointer.get("last_target"))


## What a right-stick click on `target` does: leave when it is the screen, enter
## when it belongs to a TV or handheld.
func toggle_from(target: Object) -> void:
	if is_active():
		if _screen.owns(target):
			leave()
		return
	if is_instance_valid(target) and target is Node:
		enter(TvFullscreen.device_from_node(target as Node))


## Move `device`'s picture to a screen in front of the player and hide the room.
## False when it has no picture to move.
func enter(device: Node3D) -> bool:
	if is_active() or device == null or _camera == null or not is_inside_tree():
		return false
	var room := get_tree().current_scene
	if room == null or not room.is_ancestor_of(device) or not room.is_ancestor_of(self):
		return false
	var panels := TvFullscreen.panels_for(device)
	if panels.is_empty():
		return false
	_room = room
	_rig_top = _top_level(self)
	_device = weakref(device)
	_screen = FocusScreen.new()
	_screen.name = "FocusScreen"
	add_child(_screen)
	_screen.setup(panels, _camera, _hands)
	_screen.place_in_front(_camera)
	_menu_was_open = is_instance_valid(_menu_panel) and _menu_panel.visible
	_take_view()
	_take_controls()
	_refresh_room()
	_room.child_entered_tree.connect(_on_room_child)
	_room.tree_exiting.connect(leave)
	_keep_clock = 0.0
	set_process(true)
	return true


## Put the room back as it was.
func leave() -> void:
	if _screen == null:
		return
	set_process(false)
	if is_instance_valid(_room):
		if _room.child_entered_tree.is_connected(_on_room_child):
			_room.child_entered_tree.disconnect(_on_room_child)
		if _room.tree_exiting.is_connected(leave):
			_room.tree_exiting.disconnect(leave)
	_release_audio()
	for child: Variant in _prior_visible.keys():
		if is_instance_valid(child):
			_show_child(child as Node3D)
	_prior_visible.clear()
	_suspended.clear()
	_held.clear()
	_release_view()
	_release_controls()
	_screen.free()
	_screen = null
	_device = null
	_room = null
	_rig_top = null


func _process(delta: float) -> void:
	var device: Variant = _device.get_ref() if _device != null else null
	if not is_instance_valid(device):
		leave()
		return
	var menu_open := is_instance_valid(_menu_panel) and _menu_panel.visible
	if menu_open and not _menu_was_open:
		leave()
		return
	_menu_was_open = menu_open
	_keep_clock += delta
	if _keep_clock >= KEEP_INTERVAL:
		_keep_clock = 0.0
		_refresh_room()
	else:
		_rehide()
	_hold_audio()


# ── The room ──────────────────────────────────────────────────────────────────

func _refresh_room() -> void:
	for child: Variant in _prior_visible.keys():
		if not is_instance_valid(child):
			_prior_visible.erase(child)
			_suspended.erase(child)
	var keep := _keep_set()
	for child: Node in _room.get_children():
		if child == _rig_top or not (child is Node3D):
			continue
		if keep.has(child):
			_show_child(child as Node3D)
		else:
			_hide_child(child as Node3D)


func _rehide() -> void:
	for child: Variant in _prior_visible:
		if is_instance_valid(child) and (child as Node3D).visible:
			(child as Node3D).visible = false


## Hidden after the frame it arrived in, once its _ready has run.
func _on_room_child(_node: Node) -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_queued_refresh.call_deferred()


func _queued_refresh() -> void:
	_refresh_queued = false
	if is_active():
		_refresh_room()


func _hide_child(child: Node3D) -> void:
	if _prior_visible.has(child):
		if child.visible:
			child.visible = false
		return
	_prior_visible[child] = child.visible
	child.visible = false
	_suspend(child)


func _show_child(child: Node3D) -> void:
	if not _prior_visible.has(child):
		return
	child.visible = _prior_visible[child]
	_prior_visible.erase(child)
	_resume(child)


func _suspend(child: Node) -> void:
	var pickables := {}
	var widgets := {}
	var nodes: Array[Node] = [child]
	nodes.append_array(child.find_children("*", "", true, false))
	for node: Node in nodes:
		if node is XRToolsPickable:
			pickables[node] = (node as XRToolsPickable).enabled
			(node as XRToolsPickable).enabled = false
		elif _is_poke_widget(node):
			widgets[node] = node.is_processing()
			node.set_process(false)
	_suspended[child] = {"pickables": pickables, "widgets": widgets}


func _resume(child: Node) -> void:
	var record: Dictionary = _suspended.get(child, {})
	_suspended.erase(child)
	var pickables: Dictionary = record.get("pickables", {})
	for node: Variant in pickables:
		if is_instance_valid(node):
			(node as XRToolsPickable).enabled = pickables[node]
	var widgets: Dictionary = record.get("widgets", {})
	for node: Variant in widgets:
		if is_instance_valid(node):
			(node as Node).set_process(widgets[node])


## Widgets that poll PokeTip every frame, and so answer a hand they cannot be seen by.
static func _is_poke_widget(node: Node) -> bool:
	return node is VRButton or node is VRSlider or node is VRHinge or node is VRKnob \
		or node is TVTouchSurface or node is PageGrab


## The room children to keep drawn this sweep.
func _keep_set() -> Dictionary:
	for pickup: Node in _pickups:
		if not is_instance_valid(pickup):
			continue
		var held: Variant = pickup.get("picked_up_object")
		if is_instance_valid(held):
			_keep(_held, held)
	var keep := {}
	for node: Variant in _held.keys():
		if is_instance_valid(node):
			keep[node] = true
		else:
			_held.erase(node)
	var device: Variant = _device.get_ref() if _device != null else null
	if device is RetroSystem:
		_keep(keep, device)
	var machine := _focused_machine()
	if machine != null:
		_keep_wired(keep, machine)
	_keep_seated(keep)
	return keep


## The devices in `machine`'s ports, their cords, and every lead on its bus with the
## machine at the far end.
func _keep_wired(keep: Dictionary, machine: RetroSystem) -> void:
	var controllers := machine.get_port_controllers()
	for ctrl: Variant in controllers:
		if is_instance_valid(ctrl):
			_keep(keep, ctrl)
	var tree := get_tree()
	var plugs := tree.get_nodes_in_group("controller_plug") + tree.get_nodes_in_group("link_plug")
	for plug: Node in plugs:
		if plug.has_method("get_controller") and controllers.has(plug.call("get_controller")):
			_keep(keep, plug)
		var cable: Variant = plug.get("cable")
		if not is_instance_valid(cable) or not (cable as Object).has_method("linked_machines"):
			continue
		var bus: Array = (cable as Object).call("linked_machines")
		if not _bus_has(bus, machine):
			continue
		_keep(keep, cable)
		for entry: Dictionary in bus:
			_keep(keep, entry.get("machine"))


## Adds whatever sits in a socket on something kept, however deep: a VMU in a pad,
## a Transfer Pak and the cartridge in it. A snapped object is never reparented under
## its socket, so it is a room child of its own and the tree cannot say what holds it.
func _keep_seated(keep: Dictionary) -> void:
	var seats: Array[Array] = []
	for zone: XRToolsSnapZone in XRToolsSnapZone.live_zones():
		if is_instance_valid(zone) and is_instance_valid(zone.picked_up_object):
			seats.append([_top_level(zone), _top_level(zone.picked_up_object)])
	var grew := true
	while grew:
		grew = false
		for seat: Array in seats:
			if seat[1] != null and keep.has(seat[0]) and not keep.has(seat[1]):
				keep[seat[1]] = true
				grew = true


func _keep(into: Dictionary, node: Variant) -> void:
	if not is_instance_valid(node) or not (node is Node):
		return
	var top := _top_level(node as Node)
	if top != null:
		into[top] = true


static func _bus_has(bus: Array, machine: Object) -> bool:
	for entry: Variant in bus:
		if entry is Dictionary and (entry as Dictionary).get("machine") == machine:
			return true
	return false


## The machine whose ports and leads count as wired: the device itself, or the
## source on a TV's selected input.
func _focused_machine() -> RetroSystem:
	var device: Variant = _device.get_ref() if _device != null else null
	if device is RetroSystem:
		return device as RetroSystem
	if device is RetroTV:
		return (device as RetroTV).panel().selected_system() as RetroSystem
	return null


## `node`'s ancestor that is a direct child of the room, or null outside it.
func _top_level(node: Node) -> Node:
	while is_instance_valid(node) and node.get_parent() != _room:
		node = node.get_parent()
	return node


# ── View and controls ─────────────────────────────────────────────────────────

func _take_view() -> void:
	var passthrough := false
	var xr := XRServer.primary_interface
	if AppPrefs.focus_passthrough and XrPassthrough.supported() and xr != null:
		_prior_blend = xr.environment_blend_mode
		_prior_transparent_bg = get_viewport().transparent_bg
		passthrough = XrPassthrough.enable(get_viewport())
		if not passthrough:
			_prior_blend = -1
	# The camera's own environment overrides the room's WorldEnvironment.
	_prior_env = _camera.environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if passthrough else Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	_camera.environment = env
	_light = DirectionalLight3D.new()
	_light.name = "FocusLight"
	_light.shadow_enabled = false
	_light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(_light)
	_prior_screen_lights = QualityManager.screen_lights_enabled
	QualityManager.screen_lights_enabled = false
	QualityManager.apply_screen_lights()


func _release_view() -> void:
	if is_instance_valid(_camera):
		_camera.environment = _prior_env
	_prior_env = null
	var xr := XRServer.primary_interface
	if _prior_blend >= 0 and xr != null:
		xr.environment_blend_mode = _prior_blend as XRInterface.EnvironmentBlendMode
		get_viewport().transparent_bg = _prior_transparent_bg
	_prior_blend = -1
	if is_instance_valid(_light):
		_light.free()
	_light = null
	QualityManager.screen_lights_enabled = _prior_screen_lights
	QualityManager.apply_screen_lights()


func _take_controls() -> void:
	for pointer: Node in _pointers:
		if is_instance_valid(pointer):
			_pointer_masks[pointer] = pointer.get("collision_mask")
			pointer.set("collision_mask", FocusScreen.LAYER)
	if _loco != null:
		_loco.set_block(BLOCK_OWNER, LocomotionManager.CHANNEL_ALL, true)


func _release_controls() -> void:
	for pointer: Variant in _pointer_masks:
		if is_instance_valid(pointer):
			(pointer as Node).set("collision_mask", _pointer_masks[pointer])
	_pointer_masks.clear()
	if _loco != null:
		_loco.set_block(BLOCK_OWNER, LocomotionManager.CHANNEL_ALL, false)


# ── Sound ─────────────────────────────────────────────────────────────────────

## The source behind the shown picture sounds from the screen's two edges.
func _hold_audio() -> void:
	var want := TvFullscreen.audio_source_for(_device.get_ref() if _device != null else null)
	var held: Variant = _audio_held.get_ref() if _audio_held != null else null
	if held != want:
		_release_audio()
		_audio_held = weakref(want) if want != null else null
	if want == null or not want.has_method("set_audio_head_lock"):
		return
	var at := _screen.speaker_positions()
	want.call("set_audio_head_lock", at[0], at[1])


func _release_audio() -> void:
	var held: Variant = _audio_held.get_ref() if _audio_held != null else null
	if is_instance_valid(held) and (held as Object).has_method("clear_audio_head_lock"):
		(held as Object).call("clear_audio_head_lock")
	_audio_held = null
