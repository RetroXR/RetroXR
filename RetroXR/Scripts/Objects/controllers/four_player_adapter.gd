## FourPlayerAdapter — what the NES Four Score and the Famicom 4 Players Adaptor
## have in common: one captive lead into the console, four controller sockets on
## the body, and a 2/4 switch. Each pad in a socket is bound to the libretro port
## its socket reaches (attach_expanded_controller, so it drives the core as a pad
## in a console port does), and the adapter DECIDES what each of those ports is to
## the core (RetroSystem.own_port_device), because a pad alone cannot say it: the
## plain joypad id is fceumm's "Auto", which reads players 3 and 4 only for the
## games in its own list, so ports 2 and 3 are announced as the core's named
## Gamepad, with or without a pad in the socket.
##
## What differs between the two is where the lead goes and which socket reaches
## which port: _routes(), _owned_ports() and port_device() are the subclass's. The
## body, the sockets and the switches are built in code by each (a primitive
## stand-in at estimated sizes; see docs/dev/four-player-adapters.md for what was
## measured and what was not).
##
## The lead is the adapter's, made a frame after it spawns as every pad's cord is,
## and seated by a hand or by restore_port_connection(). The console tells the
## adapter through the lead's ControllerPlug (on_plugged_in / on_unplugged, once
## per port it fills); the adapter then re-reads where its lead is from the
## console (_resync), which is what keeps the Four Score's two-plug block, told
## twice, from needing to know which call was which.
class_name FourPlayerAdapter
extends XRToolsPickable


const CONTROLLER_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")
const SOCKETS := 4
const MODE_2P := 2
const MODE_4P := 4
const RETRO_DEVICE_NONE := 0
const RETRO_DEVICE_JOYPAD := 1
## What a core lists a plain pad as on its third and fourth ports, in order of
## preference: fceumm and Nestopia "Gamepad", Mesen "Standard Controller". Matched
## by RetroSystem.core_device_id; a core with neither gets the plain joypad.
const GAMEPAD_NAMES: Array[String] = ["gamepad", "standard controller"]

## The 2/4 switch. 4 by default: an adapter is spawned to add players.
@export var mode: int = MODE_4P

## How long the lead is, in metres. Neither adapter's cord has a published length
## (a reseller says "a few feet" of the Four Score's); a metre is an estimate.
@export var cable_length: float = 1.0

## What the lead is to the socket it seats in, copied by ControllerPlug.set_controller.
var device_type: int = RETRO_DEVICE_JOYPAD
var device_names := PackedStringArray()
## The lead's plug (Connectors.of): set by the subclass before the cord is made.
var connector: String = ""

var _cable_instance: Node3D = null
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length := 0.0
var _pending_port_restore: Dictionary = {}

## The console the lead is in, or null.
var _system: RetroSystem = null
## Ports whose device this adapter is deciding on _system, and the ones it puts
## its input filter on (the Four Score's TURBO).
var _owned: Array[int] = []
var _filtered: Array[int] = []

var _sub_zones: Array = []
var _sub_plugs: Array = [null, null, null, null]
## The libretro port each socket's pad is bound to now, -1 where none.
var _bound: Array[int] = [-1, -1, -1, -1]
var _labels: Array = []
var _mode_switch: VRSlider = null

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _ports_root: Node3D = $Ports


func _ready() -> void:
	super._ready()
	press_to_hold = false
	add_to_group("spawned")
	_build_body()
	_build_ports()
	_mode_switch = _build_mode_switch()
	_build_extra_controls()
	_update_labels()
	_spawn_cable()


# ── What the subclass says ────────────────────────────────────────────────────

## The libretro port socket `i` reaches now, or -1: from where the lead is
## (_system, _cable_plug) and the switch.
func _routes() -> Array[int]:
	var out: Array[int] = [-1, -1, -1, -1]
	return out


## The ports whose device this adapter decides while its lead is in _system.
func _owned_ports() -> Array[int]:
	var out: Array[int] = []
	return out


## The ports whose pads' input goes through filter_port_input.
func _filter_ports() -> Array[int]:
	var out: Array[int] = []
	return out


## What port `port` of `_machine` is to the core, while this adapter owns it:
## {type: RETRO_DEVICE_*, names: PackedStringArray}. See SystemPorts.port_owners.
func port_device(_machine: Node, _port: int) -> Dictionary:
	return {"type": RETRO_DEVICE_NONE, "names": PackedStringArray()}


## A pad's frame on its way to `port` (RetroSystem.filter_port_input).
func filter_port_input(_port: int, pad: Dictionary) -> Dictionary:
	return pad


## Where socket `i` is, in the Ports node's frame, its +Z out of the socket and its
## +Y the way a plug stands up in it.
func _socket_transform(_i: int) -> Transform3D:
	return Transform3D.IDENTITY


## Whether a plug fits socket `i`'s shape: the pads' connector, and the game's
## generic props (connector "") that stand in for any pad.
func _socket_fits(plug: Node3D) -> bool:
	var c := Connectors.of(plug)
	return c.is_empty()


## The housing, its collision and its printing.
func _build_body() -> void:
	pass


## The 2/4 switch, or null. set_mode is what it calls.
func _build_mode_switch() -> VRSlider:
	return null


## Anything else on the body that works (the Four Score's TURBO buttons).
func _build_extra_controls() -> void:
	pass


## The lead's end: its connector, its mesh, its collision. The plug exists and is
## in the room; its controller is set.
func _dress_plug(_plug: ControllerPlug) -> void:
	pass


## The type this adapter's save entry is written under (ScenePersistence).
func save_type() -> String:
	return ""


## A short name for log lines.
func _tag() -> String:
	return "FourPlayerAdapter"


## The end that sits in the console: the cord's plug, or (the NES Satellite) the
## receiver it is paired with. Null while there is none.
func _lead() -> Node3D:
	return _cable_plug


## Whether this adapter has a cord of its own to make (the Satellite has none).
func _has_cable() -> bool:
	return true


# ── Sockets ───────────────────────────────────────────────────────────────────

func _build_ports() -> void:
	for i in range(SOCKETS):
		var zone: XRToolsSnapZone = SNAP_ZONE_SCENE.instantiate()
		zone.name = "Socket%d" % (i + 1)
		zone.snap_require = "controller_plug"
		zone.snap_filter = _accepts_socket_plug
		zone.grab_distance = 0.03
		_ports_root.add_child(zone)
		zone.transform = _socket_transform(i)
		var idx := i
		zone.has_picked_up.connect(func(obj: Node3D) -> void: _on_sub_snapped(idx, obj))
		# has_dropped carries no argument (see RetroMultitap): _sub_plugs remembers.
		zone.has_dropped.connect(func() -> void: _on_sub_released(idx))
		_sub_zones.append(zone)


## A socket takes a pad's plug of its own shape -- never another adapter's lead,
## which would fit the shape and mean nothing on the wire.
func _accepts_socket_plug(obj: Node3D) -> bool:
	if obj == null or not _socket_fits(obj):
		return false
	var far: Variant = obj.call("get_controller") if obj.has_method("get_controller") else null
	if far is FourPlayerAdapter or far is RetroMultitap or far == self:
		return false
	return true


## Whether socket `i` reaches a port now.
func socket_live(i: int) -> bool:
	return i >= 0 and i < SOCKETS and _routes()[i] >= 0


func _on_sub_snapped(i: int, plug: Node3D) -> void:
	_sub_plugs[i] = plug
	if _system == null:
		print("[%s] socket %d seated; the lead is in no console" % [_tag(), i + 1])
		return
	_attach_socket(i, _routes())


func _on_sub_released(i: int) -> void:
	var plug: Node3D = _sub_plugs[i]
	_sub_plugs[i] = null
	var port := _bound[i]
	_bound[i] = -1
	if port < 0 or not is_instance_valid(_system):
		print("[%s] socket %d unplugged" % [_tag(), i + 1])
		return
	print("[%s] socket %d unplugged, libretro port %d released" % [_tag(), i + 1, port])
	if is_instance_valid(plug):
		_system.detach_expanded_controller(port, plug, false)
	_system.reannounce_port(port)


## Bind socket `i`'s pad to the port it reaches, if it has one and reaches any.
## The port is this adapter's to announce (its device can depend on the pad).
func _attach_socket(i: int, routes: Array[int]) -> void:
	if _bound[i] >= 0 or not is_instance_valid(_sub_plugs[i]) or not is_instance_valid(_system):
		return
	var port := routes[i]
	if port < 0:
		print("[%s] socket %d holds a pad and reaches no port (%s%s)" % [_tag(), i + 1, _mode_text(), _dead_reason(i)])
		return
	print("[%s] socket %d -> libretro port %d" % [_tag(), i + 1, port])
	_system.attach_expanded_controller(port, _sub_plugs[i], false)
	_bound[i] = port
	_system.reannounce_port(port)


## The switch's position, for log lines.
func _mode_text() -> String:
	return "%dP" % mode


## Why socket `i` reaches nothing, for the log line. The subclass knows.
func _dead_reason(_i: int) -> String:
	return ""


# ── The lead and the switch ──────────────────────────────────────────────────

## Called by the lead's plug when it seats in a console port (once per port it
## fills). `port_index` is the libretro port; where the lead is, is re-read whole.
func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	if _system != null and _system != system:
		_teardown()
	_system = system
	print("[%s] lead seated (libretro port %d) at %dP" % [_tag(), port_index, mode])
	_resync()


## Called by the lead's plug when it leaves a console port. With the plug out of
## every socket the adapter lets go of the console; while it still fills one (the
## Four Score's block is told twice) it re-reads what is left.
func on_unplugged() -> void:
	if _system == null:
		return
	var lead := _lead()
	if lead != null and bool(lead.call("is_plugged_in")):
		_resync()
		return
	print("[%s] lead unplugged" % _tag())
	_teardown()
	_system = null
	_update_labels()


## Throw the 2/4 switch. With the lead in a console the ports are re-told what they
## are and the sockets re-routed on the spot, as the hardware does.
func set_mode(next: int) -> void:
	if next != MODE_2P and next != MODE_4P:
		return
	if next == mode:
		return
	var plugged := is_instance_valid(_system)
	if plugged:
		_teardown()
	mode = next
	if _mode_switch != null:
		var v := 1.0 if mode == MODE_4P else 0.0
		if _mode_switch.value != v:
			_mode_switch.set_value_no_signal(v)
	print("[%s] switch -> %dP" % [_tag(), mode])
	if plugged:
		_build_routes()
	_update_labels()


## Let go of every port and socket binding, then take them again from where the
## lead is now.
func _resync() -> void:
	_teardown()
	if is_instance_valid(_system):
		_build_routes()
	_update_labels()


func _teardown() -> void:
	if not is_instance_valid(_system):
		_owned.clear()
		_filtered.clear()
		_bound = [-1, -1, -1, -1]
		return
	for i in range(SOCKETS):
		if _bound[i] >= 0 and is_instance_valid(_sub_plugs[i]):
			_system.detach_expanded_controller(_bound[i], _sub_plugs[i], false)
		_bound[i] = -1
	for p: int in _filtered:
		_system.clear_input_filter(p, self)
	_filtered.clear()
	# Last: giving a port back announces what is left on it, and the pads are gone.
	for p: int in _owned:
		_system.disown_port_device(p, self)
	_owned.clear()


func _build_routes() -> void:
	var routes := _routes()
	_owned = _owned_ports()
	print("[%s] routes %s, deciding ports %s" % [_tag(), str(routes), str(_owned)])
	for p: int in _owned:
		_system.own_port_device(p, self)
	for i in range(SOCKETS):
		_attach_socket(i, routes)
	_filtered = _filter_ports()
	for p: int in _filtered:
		_system.set_input_filter(p, self)


## The pad seated in socket `i` as the console sees it (its plug), or null.
func socket_plug(i: int) -> Node3D:
	if i < 0 or i >= SOCKETS or not is_instance_valid(_sub_plugs[i]):
		return null
	return _sub_plugs[i]


## What the pad in socket `i` announces itself as -- its own device type and the
## names it goes by -- or {} when the socket is empty.
func socket_device(i: int) -> Dictionary:
	var plug := socket_plug(i)
	if plug == null:
		return {}
	var dev: int = plug.get("device_type") if "device_type" in plug else RETRO_DEVICE_JOYPAD
	return {"type": dev, "names": RetroSystem.device_names_of(plug)}


## Each socket's number is the player it is on the console it is in; a socket that
## reaches nothing is dimmed.
func _update_labels() -> void:
	var routes := _routes()
	for i in _labels.size():
		var lbl := _labels[i] as Label3D
		if lbl == null:
			continue
		lbl.modulate = Color(lbl.modulate, 1.0 if routes[i] >= 0 or _system == null else 0.35)


# ── Saving (ScenePersistence) ─────────────────────────────────────────────────

## The console this adapter's lead is in, or null.
func get_connected_system() -> RetroSystem:
	return _system


## The console socket the lead is in (the first, for the Four Score's block; the
## accessory connector's RetroSystem.ACCESSORY_SLOT for the Famicom's), or -1.
func get_cabinet_port() -> int:
	if not is_instance_valid(_system) or _lead() == null:
		return -1
	return _system.cabinet_port_of_plug(_lead())


## The device in each socket (the pad, not its plug), null where empty.
func socket_peripherals() -> Array:
	var out: Array = []
	for plug: Variant in _sub_plugs:
		var ctrl: Node = null
		if is_instance_valid(plug):
			var p := plug as Node
			ctrl = p.get_controller() if p.has_method("get_controller") else p
		out.append(ctrl)
	return out


## Which socket holds `peripheral`, or -1. A pad in a socket is the adapter's to
## put back: the console files it under a port that is also one of its own.
func socket_of(peripheral: Node) -> int:
	var held := socket_peripherals()
	for i in held.size():
		if held[i] != null and held[i] == peripheral:
			return i
	return -1


## Seat `peripheral` back in socket `i`, once its cord exists (it is made a frame
## after the pad spawns).
func restore_socket(i: int, peripheral: Node) -> void:
	if i < 0 or i >= SOCKETS or not is_instance_valid(peripheral):
		return
	_reseat_socket.call_deferred(i, peripheral, RESEAT_RETRIES)


const RESEAT_RETRIES := 8


func _reseat_socket(i: int, peripheral: Node, tries_left: int) -> void:
	if not is_instance_valid(peripheral) or i >= _sub_zones.size():
		return
	var cable: Node = peripheral.call("cable_instance") \
		if peripheral.has_method("cable_instance") else null
	var plug := cable.get_node_or_null("ControllerPlug") as Node3D \
		if is_instance_valid(cable) else null
	if plug != null and plug.is_inside_tree():
		var zone: XRToolsSnapZone = _sub_zones[i]
		if is_instance_valid(zone.picked_up_object):
			push_warning("[%s] socket %d already holds a plug; %s left out" % [_tag(), i + 1, RetroMultitap._describe(peripheral)])
			return
		print("[%s] restoring %s into socket %d" % [_tag(), RetroMultitap._describe(peripheral), i + 1])
		zone.pick_up_object(plug)
		return
	if tries_left <= 0:
		push_warning("[%s] socket %d: the pad's cord never appeared; left out" % [_tag(), i + 1])
		return
	_reseat_socket.call_deferred(i, peripheral, tries_left - 1)


## Seat the lead back where a save says it was, now or once the cord exists.
func restore_port_connection(system: RetroSystem, port_index: int) -> void:
	# A shared room replays the block's bind once per socket it fills: the second
	# finds the lead already in.
	if _cable_plug != null and _cable_plug.is_plugged_in() and _system == system:
		print("[%s] lead already in that console; socket %d needs nothing" % [_tag(), port_index])
		return
	if _cable_plug != null:
		print("[%s] restoring the lead into console socket %d" % [_tag(), port_index])
		system.restore_controller_plug(port_index, _cable_plug)
		if _system != system:
			push_warning("[%s] console socket %d did not take the lead back" % [_tag(), port_index])
	else:
		print("[%s] restoring the lead into console socket %d once the cord is made" % [_tag(), port_index])
		_pending_port_restore = {"system": system, "port_index": port_index}


# ── Cable (as RetroMultitap) ──────────────────────────────────────────────────

## The captive cable, parented to the scene root, so the storage box can unplug
## and free it with the adapter.
func cable_instance() -> Node3D:
	return _cable_instance


## The lead's plug, or null until the cord is made.
func get_plug() -> ControllerPlug:
	return _cable_plug


func _spawn_cable() -> void:
	if not _has_cable():
		return
	_cable_instance = CONTROLLER_CABLE_SCENE.instantiate()
	call_deferred("_add_cable_to_scene")


func _add_cable_to_scene() -> void:
	if not is_inside_tree():
		return
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_cable_plug = _cable_instance.get_node("ControllerPlug") as ControllerPlug
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_plug.set_controller(self)
	_dress_plug(_cable_plug)
	_cable_plug.add_collision_exception_with(self)
	# The cord leaves the body along the attach point's -Z.
	_cable_plug.global_position = _cable_attach_point.global_position \
		- _cable_attach_point.global_basis.z * 0.12
	_cable_rope.start_node = _cable_attach_point
	_cable_rope.end_node = _cable_plug
	_cable_rope.end_anchor_offset = _cable_plug.cable_anchor
	# Resized and laid in the same frame, as every pad's cord is: a live rope
	# given more segments without a re-lay writes past its points (CLAUDE.md).
	CaptiveCord.resize(_cable_rope, cable_length)
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length

	if not _pending_port_restore.is_empty():
		var sys: RetroSystem = _pending_port_restore.get("system")
		var idx: int = _pending_port_restore.get("port_index", -1)
		_pending_port_restore = {}
		if is_instance_valid(sys) and idx >= 0:
			print("[%s] cord made; restoring the lead into console socket %d" % [_tag(), idx])
			sys.restore_controller_plug(idx, _cable_plug)
			if _system != sys:
				push_warning("[%s] console socket %d did not take the lead back" % [_tag(), idx])


## The cable is not a child, so a despawn would otherwise leave it in the room.
func _exit_tree() -> void:
	if is_instance_valid(_system):
		_teardown()
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	super._exit_tree()


func _physics_process(_delta: float) -> void:
	if _cable_plug != null and _cable_attach_point != null and _max_rope_length > 0.0 \
			and not _cable_plug.is_picked_up() and _system == null:
		PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
				_cable_attach_point.global_position, _max_rope_length)


# ── Drawing helpers for the primitives ───────────────────────────────────────

static func _material(color: Color, roughness := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _add_box(parent: Node3D, size: Vector3, xform: Transform3D, mat: Material,
		node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	if not node_name.is_empty():
		mi.name = node_name
	parent.add_child(mi)
	mi.transform = xform
	return mi


func _add_label(parent: Node3D, text: String, xform: Transform3D, color: Color,
		font_size := 12, pixel := 0.0008) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = pixel
	lbl.font_size = font_size
	lbl.modulate = color
	lbl.outline_size = 0
	lbl.double_sided = false
	parent.add_child(lbl)
	lbl.transform = xform
	return lbl


## A two-position slide in a slot: the knob travels along `axis` (the parent's
## frame) by `travel`, its value 0 at the -axis end and 1 at the +axis end. The
## cap is a small box unless `cap_mesh` (scaled by `cap_scale`) is given.
func _add_slide(parent: Node3D, node_name: String, at: Vector3, axis: Vector3,
		travel: float, value: float, knob_mat: Material,
		cap_mesh: Mesh = null, cap_scale := Vector3.ONE) -> VRSlider:
	var knob := MeshInstance3D.new()
	knob.name = node_name + "Knob"
	var along := axis.abs()
	if cap_mesh != null:
		knob.mesh = cap_mesh
		knob.scale = cap_scale
	else:
		var box_cap := BoxMesh.new()
		box_cap.size = along * 0.006 + (Vector3.ONE - along) * 0.005
		box_cap.size.y = 0.004
		knob.mesh = box_cap
	knob.material_override = knob_mat
	parent.add_child(knob)
	knob.position = at + axis * travel * (value - 0.5)
	var slider := VRSlider.new()
	slider.name = node_name
	slider.axis_local = axis
	slider.travel = travel
	slider.steps = 2
	slider.value = value
	slider.collision_layer = 1 | (1 << 20)
	slider.engage_radius = 0.016
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The box rides with the cap (VRSlider._update_knob), so it is the cap's size
	# and a little: at least the slot's length for a small cap.
	var cap_box := knob.mesh.get_aabb().size * knob.scale + Vector3(0.003, 0.0, 0.003)
	box.size = (along * maxf(travel + 0.008, cap_box.dot(along))
		+ (Vector3.ONE - along) * maxf(0.012, cap_box.dot(Vector3.ONE - along - Vector3.UP)))
	box.size.y = 0.008
	col.shape = box
	slider.add_child(col)
	parent.add_child(slider)
	slider.position = at
	slider.set_knob_mesh(knob)
	return slider
