## SystemPower — what a machine runs on, and what happens when its supply comes or
## goes (docs/dev/power.md).
##
## A child of the RetroSystem it serves, made in _init beside the other components.
## Once the model is built (build()), the machine's PowerInput is made and handed
## its supply: a mains inlet or DC jack the model already has (the PC tower's C14,
## a handheld's DC IN), or one built here from PowerProfiles on the back of the body
## -- a C8 for a console with a power supply inside, a DC jack for one on an AC
## adapter. A handheld whose pack is built in takes none: its jack only charges.
## Cells are counted by PowerInput itself, off the machine's CellSlots.
##
## The gate is RetroSystem's: power_on() and toggle_power() ask allows_power_on()
## before anything starts, and say why through the machine's notice card when it
## says no. What this adds is the other direction: a supply lost under a running
## machine switches it off, as pulling the plug does; a supply arriving under a
## power SLIDE left at ON switches it on, as putting cells into a Game Boy with its
## switch up does. A push button is not latched and stays off.
##
## Only the authority acts: off a session, this machine; in one, the host. A client
## sends its press to the host (toggle_power), whose own view of the cords decides.
class_name SystemPower
extends Node

const C8_PORT := preload("res://Scenes/Objects/cables/iec_c8_port.tscn")
const C8P_PORT := preload("res://Scenes/Objects/cables/iec_c8_polarized_port.tscn")
const C14_PORT := preload("res://Scenes/Objects/cables/iec_c14_port.tscn")
const DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")
## The name of an inlet built here. A save names the socket a cord is in by it, so
## it is never renamed.
const INLET_NAME := "PowerInlet"
## How far in from the body's side, and up from its floor, a built inlet stands.
const INLET_INSET := 0.035
const INLET_LIFT := 0.022

## The machine's intake, made by build().
var input: PowerInput = null

var _host: RetroSystem = null
var _inlet: Node3D = null
var _inlets: Array[Node] = []

## The empty a detailed model marks the mouth of its own power inlet with. Its name
## differs by model in RetroXR-models (the Saturn's ACIn, the PlayStation's ACInPort,
## the Dreamcast's AcInAnchor, the GameCube's and Wii's DCIn, the Jaguar's and PSone's
## DCInPort, the Game Boy's DCPort, the Game Gear's DcInAnchor, the Super Famicom's
## PowerInPort, the NES's AcAdapterAnchor); none is a Port of the game's.
const MODEL_INLETS: Array[String] = ["ACIn", "ACInPort", "AcInAnchor", "DCIn", "DCInPort", "DCPort",
	"DcInAnchor", "PowerInPort", "AcAdapterAnchor", "PsuSeat"]
## A mouth whose face is not the body's nearest: the N64's PsuSeat is the power input
## on the face at the front of its rear bay, which looks straight back (-Z) from well
## inside the shell's outline. Every other mouth faces out of the nearest face.
const MOUTH_OUT := {"PsuSeat": Vector3.FORWARD}
## The mouths that are a mains inlet; every other is a DC jack. A mains socket never
## goes in a DC jack's mouth, nor a barrel jack in a mains inlet's: the machine's
## profile is wrong for that model, and a cord that does not fit the real one would.
const AC_MOUTHS: Array[String] = ["ACIn", "ACInPort", "AcInAnchor"]
## A socket already this close to the model's mouth was put there (a mod's own).
const AT_MOUTH := 0.005


func setup(host: RetroSystem) -> void:
	_host = host


## Make the machine's PowerInput and give it its supply. Called once the model and
## its sockets exist.
func build(model_id: String) -> void:
	input = PowerInput.on(_host)
	var profile := PowerProfiles.for_machine(model_id, _host.systemid)
	input.internal_battery = bool(profile.get("internal", false))
	# The Virtual Boy's: up the cord of the controller in its port.
	if str(profile.get("through", "")) == "controller":
		input.through = _controller_supply
		input.through_missing = "No controller plugged in (its battery pack or AC adapter tap goes on the controller)"
	_build_bay(profile)
	# An arcade cabinet takes a kettle lead in a C14 inlet on its back.
	if _host._is_cabinet_model() and str(profile.get("inlet", "")).is_empty():
		profile = {"inlet": "c14"}
	var inlets: Array[Node] = []
	for node: Node in _host.find_children("*", "Port", true, false):
		if (node is PowerPort or node is DcPort) and CoverSlots.host_of(node) == _host:
			inlets.append(node)
	# A mod's shell in place of a handheld's stand-in has no DC IN of its own: the
	# stand-in's jack is built and goes in the model's inlet (seat_on_model_inlet).
	var jack_scene := str(profile.get("dc_jack", ""))
	if inlets.is_empty() and not jack_scene.is_empty() and not input.internal_battery 			and ResourceLoader.exists(jack_scene):
		var jack := (load(jack_scene) as PackedScene).instantiate() as DcPort
		jack.name = "DcInPort"
		_host.add_child(jack)
		inlets.append(jack)
		# In the model's inlet when it has one (seat_on_model_inlet, below), else on
		# the back as a built inlet is.
		_inlet = jack
		place_inlet()
		place_inlet.call_deferred()
		print("[Power] %s: its shell has no DC IN of its own; a %s jack is built for it"
			% [_host.systemid, jack.connector])
	if inlets.is_empty():
		var made := _make_inlet(profile)
		if made != null:
			inlets.append(made)
	# A cabinet that changes its form changes its back: the inlet follows.
	if _host._model != null and _host._model.has_signal("form_changed"):
		_host._model.connect("form_changed", func() -> void: place_inlet.call_deferred())
	if input.internal_battery:
		# The jack charges the pack; the pack runs the machine.
		inlets.clear()
	for port: Node in inlets:
		input.add_inlet(port)
	_inlets = inlets.duplicate()
	# A detailed model has an inlet of its own: the socket goes there. Again once its
	# shell is in (a mod's can arrive a frame later).
	seat_on_model_inlet()
	seat_on_model_inlet.call_deferred()
	input.power_changed.connect(_on_power_changed)
	var names: Array[String] = []
	for port: Node in inlets:
		names.append("%s (%s)" % [port.name, (port as Port).connector])
	print("[Power] %s (%s): %s%s" % [_host.systemid, model_id if not model_id.is_empty() else "default",
		"inlets " + ", ".join(names) if not names.is_empty() else "no inlet",
		", built-in battery" if input.internal_battery else ""])


## A primitive handheld's battery compartment, from its profile's `bay` (BatteryBay),
## cut into the body box its scene draws. A model with no such box, or whose object
## already has seats (a mod's shell), keeps what it has.
func _build_bay(profile: Dictionary) -> void:
	var bay: Dictionary = profile.get("bay", {})
	var model: RetroSystemModel = _host._model
	if bay.is_empty() or model == null:
		return
	var body := model.find_child("HandheldBody", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		print("[Power] %s: no primitive body to put a battery bay on" % _host.systemid)
		return
	# In the model's frame: the stand-in's shell is a subtree of it.
	var box := (model.global_transform.affine_inverse() * body.global_transform) * body.get_aabb()
	# The bay's walls in the shell's own colour.
	var shell := Color(0.62, 0.62, 0.6)
	var mat := body.get_active_material(0) as StandardMaterial3D
	if mat != null:
		shell = mat.albedo_color
	var seats := BatteryBay.build(model, box, bay, "%s_battery_cover" % _host.systemid, shell, body)
	print("[Power] %s: battery bay built, %d %s seats" % [_host.systemid, seats, str(bay.get("size", "AA"))])


## The machine's own label for the logs, once its name is known.
func refresh_label(text: String) -> void:
	if input != null:
		input.label = text


## Whether the machine may start: it has power, or the room powers everything. Says
## why on the machine's notice card when it may not.
func allows_power_on() -> bool:
	if input == null or input.is_live():
		return true
	var why := input.why_not()
	print("[Power] %s: will not switch on -- %s" % [input.label, why])
	var toast := _host._machine_toast()
	if toast != null:
		toast.show_notice(_host._display_name(), "No power", _remedy(why),
			AchievementToast.ACCENT_NOTICE)
	return false


## What the card says: the supply, and what to do about it.
func _remedy(why: String) -> String:
	var profile := PowerProfiles.for_machine(_host.model_id, _host.systemid)
	if why.begins_with("Not plugged in") and not str(profile.get("brick", "")).is_empty():
		return "%s. Its AC adapter is on its card in the spawn menu." % why
	if why.begins_with("Not plugged in"):
		return "%s. A power cord is on the spawn menu's Power tab." % why
	return why


## The inlet a profile names, on the back of the body, or null for one that names
## none this can build (cells only, a dock, the C14 the PC tower's scene has).
func _make_inlet(profile: Dictionary) -> Node3D:
	var port: Node3D = null
	match str(profile.get("inlet", "")):
		"c8":
			port = C8_PORT.instantiate() as Node3D
		"c8p":
			port = C8P_PORT.instantiate() as Node3D
		"c14":
			port = C14_PORT.instantiate() as Node3D
		"dc", "dock":
			# A barrel jack, or the N64's rear bay the NUS-002 docks into (its whole
			# body is the plug, PowerBrick "dock"): a socket taking the profile's plug.
			var dc := DC_PORT.instantiate() as DcPort
			dc.connector = str(profile.get("plug", ""))
			port = dc
	if port == null:
		return null
	port.name = INLET_NAME
	_host.add_child(port)
	_inlet = port
	place_inlet()
	# Once more when the shell's meshes are all in: a primitive's are built in its
	# own _ready, a detailed one's can arrive a frame later.
	place_inlet.call_deferred()
	return port


## Stand a built inlet on the back of the body: low, toward the right as the machine
## is seen from the front (its back face is local -Z), the socket's +Z out of it. A
## model can say where its real one is (power_inlet_transform, in the machine's frame).
func place_inlet() -> void:
	if not is_instance_valid(_inlet) or not is_instance_valid(_host):
		return
	if _model_mouth() != null:
		seat_on_model_inlet()
		return
	var model: RetroSystemModel = _host._model
	if model != null and model.has_method("power_inlet_transform"):
		_inlet.transform = model.call("power_inlet_transform")
		return
	var body := _host.body_aabb()
	if body.size == Vector3.ZERO:
		return
	var x := body.end.x - minf(INLET_INSET, body.size.x * 0.25)
	var y := body.position.y + minf(INLET_LIFT, body.size.y * 0.35)
	# On the drawn back where it is (a shell's back is not always the bounds'), set in
	# so the inlet's face is flush with it.
	var spot := Vector3(x, y, body.position.z)
	if model != null:
		spot = ApplianceMains.back_surface(_host, model, Vector2(x, y), body)
	var at := Vector3(spot.x, spot.y, spot.z + ApplianceMains.inlet_proud(_inlet))
	# R_y(180): +Z of the socket out of the back.
	_inlet.transform = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), at)


## The mouth of the model's own inlet (MODEL_INLETS), or null for a stand-in.
func _model_mouth() -> Node3D:
	var model: RetroSystemModel = _host._model if is_instance_valid(_host) else null
	if model == null:
		return null
	for mouth_name: String in MODEL_INLETS:
		var found := model.find_child(mouth_name, true, false) as Node3D
		if found != null and not found is Port and found.is_inside_tree():
			return found
	return null


## Put the machine's inlet in the model's own: the socket's face at the empty that
## marks its mouth, its +Z out of the nearest face of the body, and the stand-in's
## drawing of it hidden (the model draws the real one). A socket already there (a
## mod's own) is left alone. Only the first inlet: a machine has one.
func seat_on_model_inlet() -> void:
	var mouth := _model_mouth()
	if mouth == null or _inlets.is_empty() or not is_instance_valid(_inlets[0]):
		return
	var port := _inlets[0] as Node3D
	var mains_mouth := AC_MOUTHS.has(str(mouth.name))
	if (port is DcPort) == mains_mouth:
		if not port.has_meta(&"inlet_mismatch"):
			port.set_meta(&"inlet_mismatch", true)
			push_warning("[Power] %s: its model's inlet %s is %s, but its profile gives it a %s (%s); left where it was"
				% [_host.systemid, mouth.name, "a mains inlet" if mains_mouth else "a DC jack",
				"DC jack" if port is DcPort else "mains inlet", (port as Port).connector])
		return
	if not port.has_meta(&"on_model_inlet") and port.global_position.distance_to(mouth.global_position) < AT_MOUTH:
		print("[Power] %s: %s is already at the model's inlet (%s)" % [_host.systemid, port.name, mouth.name])
		return
	var to_host := _host.global_transform.affine_inverse()
	var at := (to_host * mouth.global_transform).origin
	var out: Vector3 = MOUTH_OUT.get(str(mouth.name), _outward(at, _host.body_aabb()))
	var up := Vector3.UP if absf(out.y) < 0.9 else Vector3.BACK
	var x := up.cross(out).normalized()
	var basis := Basis(x, out.cross(x), out)
	# The socket point is as far in from the mouth as the stand-in's inlet is deep
	# in front of it, so a plug goes in to the same depth as into the stand-in.
	var inlet := port.get_node_or_null("Inlet") as MeshInstance3D
	var depth := (inlet.transform * inlet.get_aabb()).end.z if inlet != null and inlet.mesh != null else 0.0
	port.global_transform = _host.global_transform * Transform3D(basis, at - out * depth)
	for drawn: String in ["Inlet", "DcMouth", "DcPin"]:
		var part := port.get_node_or_null(drawn) as Node3D
		if part != null:
			part.visible = false
	var first := not port.has_meta(&"on_model_inlet")
	port.set_meta(&"on_model_inlet", true)
	if first:
		print("[Power] %s: %s in the model's own inlet (%s), facing %s" % [_host.systemid, port.name,
			mouth.name, str(out)])


## The face of `box` nearest `p`, as its outward normal.
static func _outward(p: Vector3, box: AABB) -> Vector3:
	var gaps := [p.x - box.position.x, box.end.x - p.x, p.y - box.position.y, box.end.y - p.y,
		p.z - box.position.z, box.end.z - p.z]
	var normals := [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	var best := 0
	for i in gaps.size():
		if absf(float(gaps[i])) < absf(float(gaps[best])):
			best = i
	return normals[best]


## The supply came or went under the machine.
func _on_power_changed(live: bool) -> void:
	if not is_instance_valid(_host) or NetworkManager.is_client():
		return
	var running := _host.is_powered_on or _host.attracting
	if not live and running:
		var latched := _slide_on()
		print("[Power] %s lost its supply while on -- switching off (%s)" % [input.label, input.why_not()])
		if NetworkManager.netplay_running() and NetworkManager.netplay_covers(_host):
			NetworkManager.netplay_stop("unplugged")
		else:
			_host.power_off()
			if NetworkManager.is_active() and NetworkManager.is_host():
				NetworkManager.report_event(NetEvents.Event.EV_SYS_POWER_STATE,
					{"sys": _host, "on": false})
		# The slide stays where the hand left it: the machine comes back with the supply.
		if latched:
			_set_slide(true)
	elif live and not running and _slide_on():
		print("[Power] %s: supply arrived with its power switch ON -- switching on" % input.label)
		_host.toggle_power()


## Whether the machine's power switch latches and stands at ON. A push button
## never does.
func _slide_on() -> bool:
	var slide := _latch()
	return slide != null and slide.value > 0.5


func _set_slide(on: bool) -> void:
	var slide := _latch()
	if slide != null:
		slide.set_value_no_signal(1.0 if on else 0.0)


## The machine's latching power switch: its model's, else the one on a controller in
## its ports (the Virtual Boy's is on its controller, VbController), else null.
func _latch() -> VRSlider:
	var model: RetroSystemModel = _host._model
	var slide: VRSlider = model.latching_power_switch() if model != null else null
	if slide != null:
		return slide
	for pad: Variant in _host.get_port_controllers():
		if is_instance_valid(pad) and pad is Node and (pad as Node).has_method("latching_power_switch"):
			return (pad as Node).call("latching_power_switch") as VRSlider
	return null


## What a machine powered up its controller's cord reads: the intake of the first
## controller in its ports that has one (VbController.power_input), or null.
func _controller_supply() -> PowerInput:
	for pad: Variant in _host.get_port_controllers():
		if is_instance_valid(pad) and pad is Node and (pad as Node).has_method("power_input"):
			return (pad as Node).call("power_input") as PowerInput
	return null
