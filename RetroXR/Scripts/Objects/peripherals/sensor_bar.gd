## SensorBar — the Wii's sensor bar, which senses nothing.
##
## It is two clusters of infrared LEDs on a stick. The camera in the nose of the
## Wii Remote is what does the looking, and everything about where the pointer
## lands comes from where these two lights are in the room. That is the reason
## this is an object you can pick up and put somewhere rather than a position
## computed off the television: with `dolphin_ir_passthrough` on, the frontend
## hands Dolphin the camera's real view of these LEDs, so moving the bar moves the
## aim — the same way it does at home when someone knocks it off the set.
##
## It talks to no core. WiiLink owns the console end (which console this bar
## belongs to, and which way up it is sitting relative to the screen), and
## wiimote.gd reads `led_positions()` once a frame. This file is the object.
class_name SensorBar
extends XRToolsPickable


const CABLE_SCENE := preload("res://Scenes/Objects/system_models/wii/sensor_bar_cable.tscn")

## Group the plug joins so the console's SensorBarPort accepts it and nothing
## else does. A cabinet controller socket filters on "controller_plug", which
## this deliberately is NOT in — a sensor bar is not a player.
const PLUG_GROUP := &"wii_sensorbar_plug"

## Group the bar itself joins, so a remote can find it without either of them
## knowing about the other's scene.
const BAR_GROUP := &"wii_sensor_bar"

## Height of the drop hint above the bar, in metres.
const HINT_HEIGHT := 0.07

## How brightly the windows glow when the bar is powered. Real IR is invisible;
## this is the only thing that tells a player the bar is live and which face is
## the front.
const GLOW_ENERGY := 1.6

var _cable_instance: Node3D = null
var _cable_plug: ControllerPlug = null
var _cable_rope: VerletRope = null
var _max_rope_length: float = 0.0

## The console this bar is plugged into, or null. Set by WiiLink when the plug
## seats, cleared when it comes out.
var _system: RetroSystem = null

var _hint: HeldHint = null
var _led_material: StandardMaterial3D = null

@onready var _led_left: MeshInstance3D = $LedLeft
@onready var _led_right: MeshInstance3D = $LedRight
@onready var _cable_attach_point: Node3D = $CableAttachPoint


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(BAR_GROUP)
	grabbed.connect(_on_grabbed_signal)
	dropped.connect(_on_dropped_signal)
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	# One material driven for both windows: they are the same two lights and are
	# never lit apart. Made unique because the scene's copy is shared by every bar
	# spawned from it, and a second console would otherwise dim the first's.
	_led_material = (_led_left.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_led_left.set_surface_override_material(0, _led_material)
	_led_right.set_surface_override_material(0, _led_material)
	_spawn_cable()


# ── Cable (mirrors Nunchuk) ───────────────────────────────────────────────────

func _spawn_cable() -> void:
	_cable_instance = CABLE_SCENE.instantiate()
	call_deferred("_add_cable_to_scene")


func _add_cable_to_scene() -> void:
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_cable_plug = _cable_instance.get_node("ControllerPlug") as ControllerPlug
	_cable_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_cable_plug.set_controller(self)
	_cable_plug.add_collision_exception_with(self)
	# The console's SensorBarPort filters on this, and only this. Note the plug
	# stays in "controller_plug" too (ControllerPlug._ready puts it there), which
	# is harmless: a cabinet port also checks _accepts_plug, and this plug carries
	# no device_type a console would announce.
	_cable_plug.add_to_group(PLUG_GROUP)
	# Laid out along the boss's own axis, so the cord continues the direction the
	# moulding points instead of kinking at the join.
	#
	# -Z, not the Nunchuk's -Y. That is not a style choice: VerletRope takes the
	# anchor's exit direction from plug_exit_axis, which is (0,0,-1), so -Z is the
	# way the cord actually leaves. Spawning along a different axis than the rope
	# pulls along puts the plug in one place and the wire in another, which reads
	# as a lead coming out of the wrong face.
	_cable_plug.global_position = _cable_attach_point.global_position \
		- _cable_attach_point.global_transform.basis.z * 0.1
	_cable_rope.start_node = _cable_attach_point
	_cable_rope.end_node = _cable_plug
	_cable_rope._init_points()
	_max_rope_length = _cable_rope.segment_count * _cable_rope.segment_length


func get_plug() -> ControllerPlug:
	return _cable_plug


func _physics_process(_delta: float) -> void:
	if _cable_plug == null or _cable_attach_point == null or _max_rope_length <= 0.0:
		return
	if _cable_plug.is_picked_up():
		return
	PlugTether.reel_in(_cable_plug, _cable_plug.global_position,
			_cable_attach_point.global_position, _max_rope_length)


# ── Hold ──────────────────────────────────────────────────────────────────────

func _on_grabbed_signal(_pickable: Node3D, by: Node3D) -> void:
	if _hint:
		_hint.on_grabbed(by)


func _on_dropped_signal(_pickable: Node3D) -> void:
	if _hint:
		_hint.on_dropped()


# ── Power ─────────────────────────────────────────────────────────────────────

## Called by WiiLink when the plug seats in (or leaves) a console's sensor bar
## jack. Also called on a save restore, once the plug has been put back.
func set_system(system: RetroSystem) -> void:
	_system = system
	print("[SensorBar] %s" % ("plugged into %s" % system.name if system != null else "unplugged"))


func get_system() -> RetroSystem:
	return _system


## Put the plug back in `system`'s jack after a save restore. Deferred and
## retried, for the same reason the Nunchuk's reseat is: the cable is built a
## frame after the bar exists, and there is nothing to snap until it does.
func restore_connection(system: RetroSystem) -> void:
	if not is_instance_valid(system):
		return
	_reseat_plug.call_deferred(system, RESEAT_RETRIES)


## Bounded, not "until it works": a bar freed mid-load would otherwise reschedule
## this every idle frame for the life of the session.
const RESEAT_RETRIES := 8

func _reseat_plug(system: RetroSystem, tries_left: int) -> void:
	if not is_instance_valid(system) or not is_instance_valid(self):
		return
	var link: WiiLink = system.get_wii_link()
	var port: XRToolsSnapZone = link.get_sensor_bar_port() if link != null else null
	if port != null and _cable_plug != null:
		port.pick_up_object(_cable_plug)
		return
	if tries_left <= 0:
		push_warning("[SensorBar] jack or cord never appeared; left unplugged")
		return
	_reseat_plug.call_deferred(system, tries_left - 1)


## Lit means the LEDs are on, which means the remote can see them. A real bar
## draws its power from the console, so an unplugged one — or one on a console
## nobody has switched on — is just a black stick.
func is_lit() -> bool:
	return is_instance_valid(_system) and _system.is_powered_on


## The two LED clusters in world space, left first. Empty while the bar is dark,
## which is what tells wiimote.gd there is nothing to see rather than something at
## the origin.
func led_positions() -> Array[Vector3]:
	if not is_lit():
		return []
	var out: Array[Vector3] = [_led_left.global_position, _led_right.global_position]
	return out


func _process(_delta: float) -> void:
	var energy := GLOW_ENERGY if is_lit() else 0.0
	if not is_equal_approx(_led_material.emission_energy_multiplier, energy):
		_led_material.emission_energy_multiplier = energy
