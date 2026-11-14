## NaomiHookup — what a NAOMI in a cabinet is plugged into, and so what the cabinet gets from it
## (docs/dev/naomi-jvs.md, phases 3 and 4).
##
## On real hardware a NAOMI is a board on its own: the cabinet's supply powers it through a harness plug, its
## VGA goes to the monitor and its two phono jacks to the amplifier, and its JVS socket (a USB-A) is cabled to
## the cabinet's I/O board, which reads the panel and the coin switches. In a JAMMA cabinet a JVS-to-JAMMA
## converter stands between: the NAOMI's JVS and VGA go into the converter, and the cabinet's JAMMA harness
## goes on the converter's edge. Leave a cord out and that part of the cabinet stays dark, silent or dead.
##
## This reads it from the sockets: the board's (ArcadeBayUnit builds them on a NAOMI's markers) and the
## cabinet's (ArcadeCabinetFromModel builds them on the model's leads). A cabinet with none of the leads (the
## game's Morphing Arcade Cabinet) is not wired this way: it plays a NAOMI as it plays any board.
class_name NaomiHookup
extends RefCounted

## The board's sockets (children of its markers).
const BOARD_VGA := "VgaOut"
const BOARD_AUDIO_L := "AudioLOut"
const BOARD_AUDIO_R := "AudioROut"
const BOARD_JVS := "JvsOut"
const BOARD_POWER := "PowerIn"
## The cabinet's (at its leads).
const CAB_VGA := "NaomiVgaIn"
const CAB_AUDIO_L := "NaomiAudioLIn"
const CAB_AUDIO_R := "NaomiAudioRIn"
const CAB_JVS := "JvsIn"
const CAB_POWER := "BoardPowerIn"
const CAB_JAMMA := "JammaPort"
## The converter's.
const CONV_GROUP := "jvs_jamma_converter"
## On a cabinet socket that is the cabinet end of one of its own cords (ArcadeCabinetFromModel.captive_leads).
const CAPTIVE_META := &"captive_lead"
## How much longer than its run (the board's socket to the cabinet's) a cord the cabinet comes with is: a tray's travel (a
## NAOMI Universal's slides out 330 mm) and 3 cm. Cut to the run, it does not spill out of the bay in coils (it was 12 cm
## over the travel: the owner, 2026-11-14, "would it make sense to make some of those cables inside of there shorter").
const CORD_SPARE := 0.36
const CONV_EDGE := "ConvJammaEdge"
const CONV_JVS := "ConvJvsIn"
const CONV_VGA := "ConvVgaIn"

## The connector families: the NAOMI's JVS socket is a USB-A, an I/O board's or a converter's a USB-B; the
## board's power is a JST VL header.
const USB_B := "usb_b"
const NAOMI_POWER := "jst_vl8"


## The socket at the far end of whatever cord is in `port`, or null.
static func peer(port: Port) -> Port:
	if port == null or not is_instance_valid(port):
		return null
	var plug := port.seated_plug() as RcaPlug
	if plug == null or plug.cable == null:
		return null
	for n in plug.cable.get_children():
		var other := n as RcaPlug
		if other != null and other != plug and other.cord == plug.cord:
			return other.seated_port()
	return null


static func joined(a: Port, b: Port) -> bool:
	return a != null and b != null and peer(a) == b


static func _port(root: Node, port_name: String) -> Port:
	return root.find_child(port_name, true, false) as Port if root != null else null


## True when the cabinet is wired for a NAOMI (it has the leads); a cabinet without them is not gated.
static func wired(cabinet: Node) -> bool:
	return _port(cabinet, CAB_JVS) != null or _port(cabinet, CAB_POWER) != null or _port(cabinet, CAB_VGA) != null


## What the cabinet gets from the board in its bay: {power, video, audio_l, audio_r, input, missing: [what is
## not plugged, in words]}. Everything true when the bay holds no NAOMI or the cabinet is not wired.
static func state(cabinet: Node, bay: Node) -> Dictionary:
	var all := {"power": true, "video": true, "audio_l": true, "audio_r": true, "input": true, "missing": []}
	if bay == null or not ArcadeProfiles.is_naomi_bay(str(bay.get("bay_kind"))) or not wired(cabinet):
		return all
	var missing: Array[String] = []
	var harness := _converter_on_harness(cabinet)
	var conv := harness[0] as Node
	var power := joined(_port(bay, BOARD_POWER), _port(cabinet, CAB_POWER))
	if not power:
		missing.append("the NAOMI's power lead")
	var vga := _port(bay, BOARD_VGA)
	var video := joined(vga, _port(cabinet, CAB_VGA)) or (conv != null and joined(vga, _port(conv, CONV_VGA)))
	if not video:
		missing.append("the VGA cable to the monitor" + (" or the converter" if _port(cabinet, CAB_JAMMA) != null else ""))
	var al := joined(_port(bay, BOARD_AUDIO_L), _port(cabinet, CAB_AUDIO_L))
	var ar := joined(_port(bay, BOARD_AUDIO_R), _port(cabinet, CAB_AUDIO_R))
	if not al or not ar:
		missing.append("the audio cable")
	var jvs := _port(bay, BOARD_JVS)
	var input := joined(jvs, _port(cabinet, CAB_JVS)) or (conv != null and joined(jvs, _port(conv, CONV_JVS)))
	if not input:
		missing.append("the JVS cable to the I/O board" + (" or the converter" if _port(cabinet, CAB_JAMMA) != null else ""))
	return {"power": power, "video": power and video, "audio_l": power and al, "audio_r": power and ar, "input": power and input,
		"missing": missing}


## [the converter whose edge the cabinet's JAMMA harness is on, or null].
static func _converter_on_harness(cabinet: Node) -> Array:
	var harness := _port(cabinet, CAB_JAMMA)
	if harness == null:
		return [null]
	var other := peer(harness)
	if other == null:
		return [null]
	var n: Node = other
	while n != null:
		if n.is_in_group(CONV_GROUP):
			return [n]
		n = n.get_parent()
	return [null]


## A fresh cabinet's NAOMI comes wired, as a cabinet leaves the factory: the power harness, the VGA cable, the
## two phono leads and the JVS cable, each plugged into the board and the cabinet's lead. Only on a cabinet
## that has the leads, and only on a fresh one (a restored room has its own cords, where they were left). In a
## JAMMA cabinet (it has a JAMMA harness) the JVS goes to the I/O board the cabinet does not have, so it is left
## for the player to run through a converter.
static func seed_cords(cabinet: Node, bay: Node, home: Node) -> void:
	if cabinet == null or bay == null or home == null or not wired(cabinet):
		return
	# A JAMMA cabinet: a converter beside the board, the harness on its edge, the NAOMI's JVS into it.
	var harness := _port(cabinet, CAB_JAMMA)
	if harness != null and _port(cabinet, CAB_JVS) == null:
		var conv := (load("res://Scenes/Objects/peripherals/jvs_jamma_converter.tscn") as PackedScene).instantiate() as Node3D
		home.add_child(conv)
		conv.global_transform = _converter_seat(cabinet, bay as Node3D)
		if conv is RigidBody3D:
			(conv as RigidBody3D).freeze = true
			# Frozen on the cabinet's floor, inside its boxes: without this it threw the cabinet off itself.
			var machine: Node = cabinet
			while machine != null and not machine is RigidBody3D:
				machine = machine.get_parent()
			if machine != null:
				(conv as RigidBody3D).add_collision_exception_with(machine)
		var jc := (load("res://Scenes/Objects/cables/jamma_cable.tscn") as PackedScene).instantiate() as Node3D
		home.add_child(jc)
		jc.global_position = conv.global_position + Vector3(0, 0.1, 0)
		(_port(conv, CONV_EDGE)).pick_up_object(jc.get_node("PlugA0"))
		harness.pick_up_object(jc.get_node("PlugB0"))
		var jv := (load("res://Scenes/Objects/cables/jvs_cable.tscn") as PackedScene).instantiate() as Node3D
		home.add_child(jv)
		jv.global_position = conv.global_position + Vector3(0, 0.1, 0)
		_port(bay, BOARD_JVS).pick_up_object(jv.get_node("PlugA0"))
		_port(conv, CONV_JVS).pick_up_object(jv.get_node("PlugB0"))
	var runs := [["naomi_power_cable", [["PlugA0", bay, BOARD_POWER], ["PlugB0", cabinet, CAB_POWER]]],
		["vga_cable", [["PlugA0", bay, BOARD_VGA], ["PlugB0", cabinet, CAB_VGA]]],
		["stereo_rca_cable", [["PlugA0", bay, BOARD_AUDIO_L], ["PlugB0", cabinet, CAB_AUDIO_L],
			["PlugA1", bay, BOARD_AUDIO_R], ["PlugB1", cabinet, CAB_AUDIO_R]]],
		["jvs_cable", [["PlugA0", bay, BOARD_JVS], ["PlugB0", cabinet, CAB_JVS]]]]
	for run: Array in runs:
		var seats: Array = run[1]
		var ports: Array = []
		for seat: Array in seats:
			ports.append(_port(seat[1], str(seat[2])))
		if ports.has(null):
			continue
		var cable := (load("res://Scenes/Objects/cables/%s.tscn" % str(run[0])) as PackedScene).instantiate() as Node3D
		# Cut to its run: the longest board-to-cabinet pair it joins, and CORD_SPARE.
		var reach := 0.0
		for i in range(0, ports.size() - 1, 2):
			reach = maxf(reach, (ports[i] as Node3D).global_position.distance_to((ports[i + 1] as Node3D).global_position))
		for rope in cable.find_children("*", "VerletRope", true, false):
			CaptiveCord.resize(rope as VerletRope, reach + CORD_SPARE)
		home.add_child(cable)
		cable.global_position = (bay as Node3D).global_position + Vector3(0, 0.1, 0)
		for i in seats.size():
			var plug := cable.get_node_or_null(str(seats[i][0])) as Node3D
			if plug != null:
				(ports[i] as Port).pick_up_object(plug)


## Where a fresh JAMMA cabinet's converter stands: on the floor under the board, found by a ray down the cabinet's own
## mesh (a cabinet from a model is aimed at by it); the board's shelf is in the air, and the converter was laid on top of
## the board or off the shelf's edge. A cabinet without that mesh: on top of the board, as before.
static func _converter_seat(cabinet: Node, bay: Node3D) -> Transform3D:
	var on_board := bay.global_transform.translated_local(Vector3(0.0, 0.08, 0.0))
	var world := bay.get_world_3d()
	if world == null:
		return on_board
	# From under the shelf the board stands on (a few centimetres of plate), down.
	var from := bay.global_transform * Vector3(0.0, -0.03, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.6, 1 << 20)
	q.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(q)
	# The cabinet's own mesh is its machine's pointer area (the system the cabinet model is in).
	var machine := (cabinet as Node).get_parent()
	if hit.is_empty() or machine == null or not machine.is_ancestor_of(hit["collider"] as Node):
		return on_board
	return Transform3D(bay.global_basis, hit["position"] as Vector3 + Vector3.UP * 0.001)


## A socket made in code: the snap zone with a script and its plug family set before it is in the tree.
static func make_port(port_name: String, script_path: String, connector: String, direction: int = -1, channel: int = -1) -> Port:
	var zone := (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate()
	zone.set_script(load(script_path))
	var port := zone as Port
	port.name = port_name
	port.grab_distance = 0.06
	if not connector.is_empty():
		port.connector = connector
	if direction >= 0:
		port.set("direction", direction)
	if channel >= 0:
		port.set("channel", channel)
	return port
