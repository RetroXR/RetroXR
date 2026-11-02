## ExpansionAv — a unit the console's picture and sound pass THROUGH (the 32X).
##
## The 32X has an A/V IN and an A/V OUT on its back, the Genesis Model 2's 9-pin
## mini-DIN both. Sega packed a short lead with mini-DINs at both ends, the Video Link
## Cable (600-6411, sega32x_video_link_cable.tscn): it goes from the Genesis's A/V OUT
## into the 32X's A/V IN, the 32X lays its own picture over the console's, and the set
## is cabled to the 32X's A/V OUT (Sega's Conversion Cable, 600-6412, did the same for
## a Model 1's 8-pin DIN; RetroXR has only the Model 2).
##
## The row says so (ExpansionCatalog `av_socket`, `av_in`, `av_out`). The two sockets
## are the console's own socket scene, so the console's own leads fit them: the A/V IN
## is built as an input (MultiAvPort.input) and the A/V OUT stays an output. The unit is
## their device (RetroExpansion answers on_av_topology_changed), so a save and a
## netplay seat event name a plug in them against the unit, as its ADAPTOR jack does.
##
## What passes is AvGraph's business: a machine whose output reaches the A/V IN is
## given the A/V OUT's links as its own, so the set it reaches files that machine on its
## input and the machine sends it picture and sound, with no code in either. The unit
## only has to tell the machine when to look again: a cord moved on one of its sockets
## (the set's lead on the A/V OUT is not the console's lead, so the console is never
## told by it), or its supply came or went.
##
## A unit passes only while it has a supply (PowerInput, the 32X's own MK-2103): the
## real one lays its picture over the console's, and with no power its A/V OUT is
## dead. With power simulation off everything has a supply.
##
## The core draws the 32X's picture and the Mega Drive's as ONE frame, so the
## console's own A/V OUT keeps carrying the whole of it with a 32X fitted -- a set
## cabled straight to the Genesis still shows a 32X game. On the real hardware that
## lead shows the Mega Drive's layer alone; the core has no way to give it.
class_name ExpansionAv
extends RefCounted

## The sockets' names. A save names the socket a plug is in by it: never renamed.
const IN_NAME := "AvIn"
const OUT_NAME := "AvOut"
## A shell's own empties for them, which win over the row's points.
const IN_MARKER := "AvInPort"
const OUT_MARKER := "AvOutPort"
## How far a socket on the plain box stands off its face: the plug's head stops there,
## and the drawn jack (genesis_av_port.tscn's PanelJack) sits that far behind the zone.
const BOX_PROUD := 0.0005

## The devices told last time, so one that has just been cabled away still hears.
const _META_TOLD := &"av_through_told"
## The plug seated in a socket, so its release can undo the exemption its seating made.
const _META_PLUG := &"av_through_plug"
## What the log last said about the unit's wiring.
const _META_SAID := &"av_through_said"

## Units forwarding a change right now: two 32Xs cabled into each other's A/V IN would
## otherwise tell each other for ever.
static var _busy := {}


## Give `unit` its A/V IN and A/V OUT if its row has them.
static func build(unit: RetroExpansion) -> void:
	var path := ExpansionCatalog.av_socket_of(unit.expansion_id)
	if path.is_empty():
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[ExpansionAv] %s: socket scene '%s' did not load -- no A/V IN or OUT"
			% [unit.expansion_id, path])
		return
	var placed := PackedStringArray()
	for which: String in ["av_in", "av_out"]:
		var port := packed.instantiate() as MultiAvPort
		if port == null:
			push_warning("[ExpansionAv] %s: '%s' is not a MultiAvPort scene" % [unit.expansion_id, path])
			return
		port.name = IN_NAME if which == "av_in" else OUT_NAME
		port.input = which == "av_in"
		unit.add_child(port)
		placed.append("%s %s" % [port.name, place(unit, port, which)])
		port.has_picked_up.connect(func(what: Node3D) -> void: _on_plug_in(unit, port, what))
		port.has_dropped.connect(func() -> void: _on_plug_out(unit, port))
	# A supply arriving or going changes whether anything passes.
	var supply := PowerInput.of(unit)
	if supply != null:
		supply.power_changed.connect(func(_live: bool) -> void: on_topology(unit))
	print("[ExpansionAv] %s: %s" % [unit.expansion_id, "; ".join(placed)])


## Stand a socket in its mouth on the shell. Returns where it went, for the log.
##
## The socket's +Z points out of the panel (a plug arrives along it) and its +Y DOWN,
## as the Genesis's own A/V OUT is turned (genesis_model.gd configure_av_ports): the
## plug's snap grab point carries a half turn about X, and the two compose to a plug
## standing upright, its keyway on top.
static func place(unit: RetroExpansion, port: Node3D, which: String) -> String:
	var s := unit.size()
	var box := AABB(-s * 0.5, s)
	var shell := unit.get_node_or_null("Shell") as Node3D
	var mouth := Vector3.ZERO
	var from := ""
	if shell != null:
		var marker := shell.find_child(IN_MARKER if which == "av_in" else OUT_MARKER, true, false) as Node3D
		if marker != null and not marker is Port:
			mouth = (unit.global_transform.affine_inverse() * marker.global_transform).origin \
				if marker.is_inside_tree() else shell.transform * marker.position
			from = "the shell's %s" % marker.name
		else:
			var point: Variant = ExpansionCatalog.av_jack_of(unit.expansion_id, which)
			if point is Vector3:
				mouth = shell.transform * (point as Vector3)
				from = "the shell's socket (row %s)" % which
	var on_box := from.is_empty()
	if on_box:
		# The plain box: side by side on its back, low, the IN on the right seen from
		# behind as on the 32X.
		mouth = Vector3(-0.012 if which == "av_in" else 0.012,
			box.position.y + minf(0.03, s.y * 0.4), box.position.z)
		from = "the back of its box"
	var out := SystemPower._outward(mouth, box)
	var down := Vector3.DOWN if absf(out.y) < 0.9 else Vector3.FORWARD
	var x := down.cross(out).normalized()
	port.transform = Transform3D(Basis(x, out.cross(x), out), mouth)
	if on_box:
		# A box moulds no socket: the zone stands 0.5 mm proud, where the plug's head
		# stops, and the socket draws its own jack on the face behind it.
		port.position += out * BOX_PROUD
		if port is MultiAvPort and not (port as MultiAvPort).draw_jack(true):
			push_warning("[ExpansionAv] %s: socket scene draws no jack; %s is an empty patch of box"
				% [unit.expansion_id, port.name])
	return "at %s, facing %s" % [from, str(out)]


## Whether the unit passes what comes in now: while it has a supply.
static func passes(unit: RetroExpansion) -> bool:
	var supply := PowerInput.of(unit)
	return supply == null or supply.is_live()


## A cord moved on one of the unit's sockets, or its supply came or went: tell every
## device cabled to it -- the machine feeding the A/V IN, which works out again where
## its picture and sound go, and whatever the A/V OUT reaches, which reads its source
## again (an arcade cabinet's VIDEO IN does) -- and any that was cabled to it last time.
static func on_topology(unit: RetroExpansion) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree() or _busy.has(unit):
		return
	if unit.av_through_in() == null:
		return
	_busy[unit] = true
	var now: Array = []
	var feeds := ""
	var reaches := PackedStringArray()
	for link: Dictionary in AvGraph.own_links(unit):
		for end: String in ["out", "in"]:
			var dev := (link[end] as RcaPort).get_device()
			if dev == null or dev == unit or now.has(dev):
				continue
			now.append(dev)
			if end == "out":
				feeds = String(dev.name)
			else:
				reaches.append(String(dev.name))
	var said := "A/V IN <- %s, A/V OUT -> %s, %s" % [
		"<none>" if feeds.is_empty() else feeds,
		"<none>" if reaches.is_empty() else ", ".join(reaches),
		"passing" if passes(unit) else "NOT passing (no supply)"]
	if said != str(unit.get_meta(_META_SAID, "")):
		unit.set_meta(_META_SAID, said)
		print("[ExpansionAv] %s (%s): %s" % [unit.expansion_id, unit.name, said])
	var told: Array = []
	for dev: Variant in (unit.get_meta(_META_TOLD, []) as Array) + now:
		# Checked before any cast: one cabled here last time may have been freed since.
		if not is_instance_valid(dev) or told.has(dev):
			continue
		if not (dev as Object).has_method("on_av_topology_changed"):
			continue
		told.append(dev)
		(dev as Object).call("on_av_topology_changed", [])
	unit.set_meta(_META_TOLD, now)
	_busy.erase(unit)


## Let go of the leads in both sockets before the unit goes, or they are left
## pointing at freed snap zones (RetroExpansion.drop_and_free).
static func drop_plugs(unit: RetroExpansion) -> void:
	for port_name: String in [IN_NAME, OUT_NAME]:
		var port := unit.get_node_or_null(port_name) as XRToolsSnapZone
		if port != null and port.picked_up_object != null:
			port.drop_object()


## A seated plug's head is frozen in the unit's back panel, so left colliding it would
## shove a loose unit across the table -- the Ethernet socket's reason.
static func _on_plug_in(unit: RetroExpansion, port: Node, what: Node3D) -> void:
	var body := what as PhysicsBody3D
	if body == null or not is_instance_valid(unit):
		return
	unit.add_collision_exception_with(body)
	port.set_meta(_META_PLUG, body)


static func _on_plug_out(unit: RetroExpansion, port: Node) -> void:
	if not port.has_meta(_META_PLUG):
		return
	var body: Variant = port.get_meta(_META_PLUG)
	port.remove_meta(_META_PLUG)
	if is_instance_valid(unit) and is_instance_valid(body):
		unit.remove_collision_exception_with(body as PhysicsBody3D)
