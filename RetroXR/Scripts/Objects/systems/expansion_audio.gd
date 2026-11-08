## ExpansionAudio — a unit with a LINE OUT of its console's sound, and a MIXING input
## (the Sega CD Model 2).
##
## Sega's Model 2 manual: a stereo receiver takes "the two Audio Line Out jacks on the
## back of the Sega CD". With a Genesis Model 2 on it, nothing else is needed -- the
## console's sound reaches the drive through the expansion connector. An ORIGINAL
## Genesis (Model 1) does not send it that way: "Connect one end of the sound mixing
## cable, supplied with your Sega CD, to the Mixing jack on the back of the Sega CD.
## Connect the other end ... to the Stereo Headphone jack on the front of the Genesis."
##
## So the row's `line_out` builds LEFT and RIGHT phono OUTs (HostLineOut) at the shell's
## LineOutLAnchor / LineOutRAnchor, and `mixing` a 3.5 mm stereo IN (a TrsPort) at its
## MixingAnchor. The line out's device is the console on the unit while that console's
## sound reaches it (carrier): always for a console with no PHONES jack (a Model 2), and
## for one with a jack (a Model 1, its jack built by SystemAvPorts.build_phones) only
## while a lead runs from that jack into MIXING. Then the console's own AvSource sees the
## line out among its sockets, and a set or an amplifier cabled to it plays the console.
##
## The core gives ONE mixed stereo stream, so this is coarser than the hardware: a real
## Model 1 with no mixing lead still puts the CD's own audio (CD-DA, PCM) on the line
## out and its FM/PSG on the console's A/V OUT. Here the line out carries the whole
## machine or nothing, and the console's A/V OUT carries the whole machine either way.
## A machine plays through ONE sink (AvSource: the first found), so with the A/V OUT on a
## set and the line out on an amplifier, one of the two is heard.
class_name ExpansionAudio
extends RefCounted

## The sockets' names. A save names the socket a plug is in by it: never renamed.
const LEFT_NAME := "LineOutL"
const RIGHT_NAME := "LineOutR"
const MIXING_NAME := "MixingIn"
## The shell's empties for them.
const LEFT_MARKER := "LineOutLAnchor"
const RIGHT_MARKER := "LineOutRAnchor"
const MIXING_MARKER := "MixingAnchor"

const _LINE_OUT := preload("res://Scenes/Objects/cables/host_line_out.tscn")
const _TRS_PORT := preload("res://Scenes/Objects/cables/trs_port.tscn")

## How far each socket's zone stands off the face its mouth is in, where a seated plug's
## origin stops: a phono socket's jack sits 10 mm behind its zone (rca_port.tscn), a
## 3.5 mm one's 2 mm (trs_port.tscn).
const _PHONO_PROUD := 0.010
const _TRS_PROUD := 0.002

## The console whose sound the line out carried last, so a change tells both.
const _META_CARRIER := &"line_out_carrier"
## A refresh is queued for the end of the frame, after the seat that caused it settles.
const _META_PENDING := &"line_out_pending"
## The plug seated in a socket, so its release undoes the exemption its seating made.
const _META_PLUG := &"line_out_plug"


## Give `unit` its LINE OUT and MIXING if its row has them.
static func build(unit: RetroExpansion) -> void:
	var id := unit.expansion_id
	if not ExpansionCatalog.line_out_of(id) and not ExpansionCatalog.mixing_of(id):
		return
	var built: Array[String] = []
	if ExpansionCatalog.line_out_of(id):
		for spec: Array in [[LEFT_NAME, LEFT_MARKER, RcaPort.Channel.AUDIO_L],
				[RIGHT_NAME, RIGHT_MARKER, RcaPort.Channel.AUDIO_R]]:
			var port := _LINE_OUT.instantiate() as HostLineOut
			port.name = spec[0]
			port.direction = RcaPort.Direction.OUT
			port.channel = spec[2]
			unit.add_child(port)
			built.append("%s %s" % [spec[0], _place(unit, port, spec[1], _PHONO_PROUD)])
			_watch(unit, port)
	if ExpansionCatalog.mixing_of(id):
		var mix := _TRS_PORT.instantiate() as TrsPort
		mix.name = MIXING_NAME
		mix.direction = RcaPort.Direction.IN
		unit.add_child(mix)
		built.append("%s %s" % [MIXING_NAME, _place(unit, mix, MIXING_MARKER, _TRS_PROUD)])
		_watch(unit, mix)
	unit.host_changed.connect(func(_sys: RetroSystem) -> void: refresh(unit))
	print("[ExpansionAudio] %s: %s" % [id, "; ".join(built)])


## Stand a socket at the shell's marker, its +Z out of the face (where a plug arrives
## from), the zone `proud` off it. With no marker (a mod's shell without one), low on
## the back of the unit's box. Returns where it went, for the log.
static func _place(unit: RetroExpansion, port: Node3D, marker_name: String, proud: float) -> String:
	var s := unit.size()
	var box := AABB(-s * 0.5, s)
	var shell := unit.get_node_or_null("Shell") as Node3D
	var marker := shell.find_child(marker_name, true, false) as Node3D if shell != null else null
	var mouth := Vector3(0.0, box.position.y + s.y * 0.3, box.position.z)
	var from := "the back of its box"
	if marker != null:
		mouth = unit.to_local(marker.global_position) if marker.is_inside_tree() \
			else shell.transform * marker.position
		from = "the shell's %s" % marker_name
	else:
		push_warning("[ExpansionAudio] %s: its shell has no %s; %s goes on the back of its box"
			% [unit.expansion_id, marker_name, port.name])
	var out := SystemPower._outward(mouth, box)
	var up := Vector3.UP if absf(out.y) < 0.9 else Vector3.BACK
	var x := up.cross(out).normalized()
	port.transform = Transform3D(Basis(x, out.cross(x), out), mouth + out * proud)
	return "at %s" % from


## A plug in one of the sockets: exempt from the unit (it rides in the socket), and a
## lead into MIXING may change whose sound the line out carries.
static func _watch(unit: RetroExpansion, port: Port) -> void:
	port.has_picked_up.connect(func(what: Node3D) -> void:
		var body := what as PhysicsBody3D
		if body != null:
			unit.add_collision_exception_with(body)
			port.set_meta(_META_PLUG, body)
		refresh(unit))
	port.has_dropped.connect(func() -> void:
		var body: Variant = port.get_meta(_META_PLUG) if port.has_meta(_META_PLUG) else null
		if is_instance_valid(body):
			unit.remove_collision_exception_with(body as PhysicsBody3D)
		port.remove_meta(_META_PLUG)
		refresh(unit))


## The console whose sound reaches `unit`'s line out now, or null.
##
## Read off the MIXING socket's own lead, never through AvGraph: AvGraph asks every
## socket for its device, the line out's own included, which is this question.
static func carrier(unit: RetroExpansion) -> RetroSystem:
	if unit == null or not is_instance_valid(unit):
		return null
	var host := unit.get_host()
	if host == null:
		return null
	var phones := host.get_node_or_null("PhonesOut") as Port
	if phones == null:
		# No PHONES jack (a Genesis Model 2): its sound comes through the connector.
		return host
	return host if mixing_from(unit) == phones else null


## The socket the far end of the lead in `unit`'s MIXING is seated in, or null.
static func mixing_from(unit: RetroExpansion) -> Port:
	var mix := unit.get_node_or_null(MIXING_NAME) as Port
	var plug := mix.seated_plug() as RcaPlug if mix != null else null
	if plug == null or not is_instance_valid(plug.cable):
		return null
	for child in plug.cable.get_children():
		var other := child as RcaPlug
		if other != null and other != plug:
			var at := other.seated_port()
			if at != null:
				return at
	return null


## Whose sound the line out carries may have changed: once the frame's seats settle,
## the console that carried it before and the one that carries it now each resolve
## their wiring again, and the leads in the line out re-tell their far ends.
static func refresh(unit: RetroExpansion) -> void:
	if not is_instance_valid(unit) or bool(unit.get_meta(_META_PENDING, false)):
		return
	unit.set_meta(_META_PENDING, true)
	# On the unit, so a unit freed before the frame ends drops the call.
	unit.call_deferred("settle_line_out")


static func settle(unit: RetroExpansion) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	unit.set_meta(_META_PENDING, false)
	var was: Variant = unit.get_meta(_META_CARRIER) if unit.has_meta(_META_CARRIER) else null
	var now := carrier(unit)
	if was != now:
		unit.set_meta(_META_CARRIER, now)
		var why := "none"
		if now != null:
			why = "its connector" if now.get_node_or_null("PhonesOut") == null else "the mixing lead from its PHONES"
		print("[ExpansionAudio] %s: LINE OUT carries %s (%s)"
			% [unit.expansion_id, now.name if now != null else "nothing", why])
	for name: String in [LEFT_NAME, RIGHT_NAME]:
		var port := unit.get_node_or_null(name) as Port
		var plug := port.seated_plug() as RcaPlug if port != null else null
		if plug != null and is_instance_valid(plug.cable) and plug.cable.has_method("on_plug_seating_changed"):
			plug.cable.on_plug_seating_changed()
	for dev: Variant in [was, now]:
		if is_instance_valid(dev) and (dev as Node).has_method("on_av_topology_changed"):
			(dev as Node).on_av_topology_changed([])


## Let go of every lead in the unit's sockets before it goes, or each is left pointing
## at a freed snap zone.
static func drop_plugs(unit: RetroExpansion) -> void:
	for name: String in [LEFT_NAME, RIGHT_NAME, MIXING_NAME]:
		var port := unit.get_node_or_null(name) as Port
		if port != null and port.seated_plug() != null:
			port.drop_object()
