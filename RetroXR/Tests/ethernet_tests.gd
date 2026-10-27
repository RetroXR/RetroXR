## Ethernet LAN self-tests -- the network adapters, the cable and the hub, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/ethernet_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/ethernet_tests.tscn -- --only=hub
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## What is here is what the room decides without a core: which sockets take an
## RJ45 plug, that a GameCube's Broadband Adapter and a PlayStation 2's Network
## Adapter grow one and switch their core's adapter on, and which consoles
## EthernetBus puts on one LAN -- through hubs, across both machines, and off it
## again when a spoke or an adapter comes out. Whether frames cross is the cores'
## business and Tools/link/lan_probe's; see docs/dev/ethernet-lan.md.
##
## Two of these are the regression record for traps the adapter puts in the way.
## The socket is on the CARD, not the console, so a walk that stopped at the card
## would put nothing on the LAN; and a card pulled out of a console with its lead
## still in it moves no lead, so nothing re-walked the room and the console stayed
## on a LAN it had no adapter for.
##
## And the covers (`cover/`): a shell whose opening has a cover (xenu.gamecube's
## Serial Port 1, xenu.ps2's EXPANSION BAY) gives the card's socket a PortCover
## that has to come off before the card goes in, and cannot go back while it is in.
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")
const CABLE_SCENE := "res://Scenes/Objects/cables/ethernet_cable.tscn"
const HUB_SCENE := "res://Scenes/Objects/cables/ethernet_hub.tscn"
const ILINK_CABLE_SCENE := "res://Scenes/Objects/cables/ilink_cable.tscn"

const BBA := "gamecube_broadband_adapter"
const NETWORK_ADAPTER := "ps2_network_adapter"

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "eth"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[eth] TIMEOUT")
		get_tree().quit(1))
	if _want("gating"):
		_test_plug_gating()
	if _want("cable"):
		await _test_cable_scene()
	if _want("spawn"):
		_test_spawnable()
	if _want("catalog"):
		_test_catalog()
	if _want("options"):
		_test_forced_options()
	if _want("hub"):
		await _test_hub_scene()
	if _want("adapter"):
		await _test_adapter("gc", BBA, 4, "dolphin", "dolphin_gc_sp1", "15", "255")
		await _test_adapter("ps2", NETWORK_ADAPTER, 1, "pcsx2", "pcsx2_dev9_eth", "link", "disabled")
	if _want("slim"):
		await _test_built_in_socket()
	if _want("hub_lan"):
		await _test_lan_through_a_hub()
	if _want("mixed"):
		await _test_gamecubes_and_ps2s_share_a_hub()
	if _want("card_out"):
		await _test_card_out_takes_the_console_off()
	if _want("cover"):
		await _test_port_covers()
	if _want("jack"):
		await _test_shell_jack()
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ── fixtures ──────────────────────────────────────────────────────────────────


func _console(systemid: String, label := "") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	if not label.is_empty():
		sys.name = label
	sys.position = Vector3(_spawned.size() * 2.0, 1, 0)
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(30)
	return sys


func _unit(expansion_id: String) -> RetroExpansion:
	var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
	unit.expansion_id = expansion_id
	unit.position = Vector3(_spawned.size() * 2.0, 1, 0)
	unit.freeze = true
	add_child(unit)
	_spawned.append(unit)
	await _wait(10)
	return unit


## A console with its network adapter seated, as a player leaves one.
func _cabled_console(systemid: String, label: String) -> RetroSystem:
	var sys := await _console(systemid, label)
	var card := await _unit(ExpansionCatalog.network_adapter_for(systemid))
	sys.restore_expansion(card)
	await _wait(10)
	return sys


## The adapter's socket on a console, wherever the console's adapter is.
func _socket_of(sys: RetroSystem) -> EthernetPort:
	for unit: RetroExpansion in sys.get_expansions():
		if unit.get_ethernet_port() != null:
			return unit.get_ethernet_port()
	return null


func _lead(label: String) -> EthernetCable:
	var lead: EthernetCable = load(CABLE_SCENE).instantiate()
	lead.name = label
	add_child(lead)
	_spawned.append(lead)
	return lead


func _hub() -> EthernetHub:
	var hub: EthernetHub = load(HUB_SCENE).instantiate()
	hub.position = Vector3(0, 0.5, 1.5)
	add_child(hub)
	_spawned.append(hub)
	return hub


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(5)


## Pull a plug and keep it pulled -- link_tests' `_pull`, for its reason: a hub's
## sockets are close enough that a plug let go of snaps into the next one.
## Re-enable it before seating it anywhere again.
func _pull(port: XRToolsSnapZone) -> void:
	var plug := port.picked_up_object as XRToolsPickable
	port.drop_object()
	if plug != null:
		plug.enabled = false
		plug.freeze = true


func _ports_of(bus: Array) -> Dictionary:
	var out := {}
	for entry: Dictionary in bus:
		out[(entry["machine"] as Node).name] = int(entry["port"])
	return out


# ── what goes in what ─────────────────────────────────────────────────────────


func _test_plug_gating() -> void:
	var port := EthernetPort.new()
	add_child(port)
	var plug := LinkPlug.new()
	plug.connector = "ethernet_plug"
	add_child(plug)
	var ilink_port := ILinkPort.new()
	add_child(ilink_port)
	var ilink_plug := LinkPlug.new()
	ilink_plug.connector = "ilink_plug"
	add_child(ilink_plug)

	_eq(port.connector, plug.connector, "gating/ the RJ45 socket and plug name the same group")
	_eq(port.connector, "ethernet_plug", "gating/ the group is ethernet_plug")
	_eq(port.snap_require, port.connector, "gating/ the socket requires that group to snap")
	# Both directions: EthernetPort extends PsxLinkPort, as ILinkPort does, so a
	# scene that lost its connector would take the PlayStation's plug instead.
	_ok(port.connector != ilink_plug.connector, "gating/ an RJ45 socket does not take an i.LINK plug")
	_ok(ilink_port.connector != plug.connector, "gating/ nor an i.LINK socket an RJ45 plug")
	_ok(port.connector != PsxLinkPort.new().connector, "gating/ nor is it a PlayStation serial socket")
	_ok(plug.is_in_group(LinkPlug.ANY_GROUP), "gating/ an RJ45 plug is one netplay's lead sweep can see")

	for n: Node in [port, plug, ilink_port, ilink_plug]:
		n.queue_free()


func _test_cable_scene() -> void:
	var lead := _lead("GatingLead")
	await get_tree().process_frame
	for end: String in ["PlugA0", "PlugB0"]:
		var plug := lead.get_node(end) as LinkPlug
		_ok(plug != null, "cable/ %s is a link plug" % end)
		if plug == null:
			continue
		_eq(plug.connector, "ethernet_plug", "cable/ %s is an RJ45 plug" % end)
		_ok(plug.is_in_group(LinkPlug.ANY_GROUP), "cable/ %s is in the link-lead sweep group" % end)
		_eq(plug.cable, lead, "cable/ %s knows its lead" % end)
	_ok(lead.is_in_group(EthernetBus.CABLE_GROUP), "cable/ the lead is one EthernetBus walks")
	_eq(lead.links().size(), 0, "cable/ it carries no A/V links")
	_ok((lead.linked_machines() as Array).is_empty(), "cable/ unseated, it joins nothing")
	_ok((lead.held_machines() as Array).is_empty(), "cable/ and holds nothing")
	_ok(not lead.netplay_took_bus([], []), "cable/ and acts alone with no game running")
	await _clear()


func _test_spawnable() -> void:
	for sys: String in ["gc", "ps2"]:
		var lead := false
		var hub := false
		for item: Dictionary in SpawnCatalog.items_for(sys):
			var spawn := str(item.get("spawn", ""))
			lead = lead or spawn == "ethernet_cable"
			hub = hub or spawn == "ethernet_hub"
		_ok(lead, "spawn/ an Ethernet cable is offered under %s" % sys)
		_ok(hub, "spawn/ and so is a hub")
	# The Wii's LAN adapter is a USB one, and none of the others had a network.
	for sys: String in ["psx", "wii", "n64", "saturn"]:
		var stray := false
		for item: Dictionary in SpawnCatalog.items_for(sys):
			var spawn := str(item.get("spawn", ""))
			stray = stray or spawn == "ethernet_cable" or spawn == "ethernet_hub"
		_ok(not stray, "spawn/ neither under %s" % sys)
	_ok(ScenePersistence.LEAD_SCENES.has("ethernet_cable"), "spawn/ a saved room can rebuild the lead")
	_ok(ScenePersistence.PLAIN_SCENES.has("ethernet_hub"), "spawn/ and the hub")


func _test_catalog() -> void:
	_eq(ExpansionCatalog.ethernet_port_of(BBA), 4, "catalog/ the Broadband Adapter is link port 4, past the four pads")
	_eq(ExpansionCatalog.ethernet_port_of(NETWORK_ADAPTER), 1, "catalog/ the Network Adapter is link port 1, beside i.LINK's 0")
	_eq(ExpansionCatalog.ethernet_port_of("sega_saturn_vcd_card"), -1, "catalog/ a unit with no RJ45 has no port")
	_eq(ExpansionCatalog.network_adapter_for("gc"), BBA, "catalog/ a GameCube's adapter is the Broadband Adapter")
	_eq(ExpansionCatalog.network_adapter_for("ps2"), NETWORK_ADAPTER, "catalog/ a PlayStation 2's is the Network Adapter")
	_eq(ExpansionCatalog.network_adapter_for("psx"), "", "catalog/ a PlayStation takes none")
	_eq(ExpansionCatalog.socket_of(BBA), "serial_port_1", "catalog/ the Broadband Adapter goes in Serial Port 1")
	_eq(ExpansionCatalog.socket_of(NETWORK_ADAPTER), "expansion_bay", "catalog/ the Network Adapter in the expansion bay")
	_ok(ExpansionCatalog.unit_sockets_for_host("gc").has("serial_port_1"), "catalog/ so a GameCube grows that socket")
	_ok(ExpansionCatalog.unit_sockets_for_host("ps2").has("expansion_bay"), "catalog/ and a PlayStation 2 that one")
	# A network card changes no core: the one the console already runs has it.
	_eq(str(ExpansionCatalog.boot_for("gc", [BBA]).get("core", "")), "", "catalog/ the Broadband Adapter picks no core")
	_eq(str(ExpansionCatalog.boot_for("ps2", [NETWORK_ADAPTER]).get("core", "")), "", "catalog/ nor the Network Adapter")


func _test_forced_options() -> void:
	_eq(ForcedCoreOptions.ethernet_adapter("dolphin", "gc", []), {"dolphin_gc_sp1": "255"},
		"options/ a GameCube with no adapter has nothing in Serial Port 1")
	_eq(ForcedCoreOptions.ethernet_adapter("dolphin", "gc", [BBA]), {"dolphin_gc_sp1": "15"},
		"options/ with one, SP1 is the Ethernet Link Cable")
	# The Wii shares dolphin.opt; a GameCube's "15" must not carry over to it.
	_eq(ForcedCoreOptions.ethernet_adapter("dolphin", "wii", [BBA]), {"dolphin_gc_sp1": "255"},
		"options/ and a Wii never inherits it")
	_eq(ForcedCoreOptions.ethernet_adapter("pcsx2", "ps2", []), {"pcsx2_dev9_eth": "disabled"},
		"options/ a PlayStation 2 with no adapter has no network")
	_eq(ForcedCoreOptions.ethernet_adapter("pcsx2", "ps2", [NETWORK_ADAPTER]), {"pcsx2_dev9_eth": "link"},
		"options/ with one, its network is the cable, not the host's")
	_eq(ForcedCoreOptions.ethernet_adapter("pcsx2", "ps2", [BBA]), {"pcsx2_dev9_eth": "disabled"},
		"options/ another console's card does nothing")
	_ok(ForcedCoreOptions.ethernet_adapter("mednafen_psx_hw", "psx", [NETWORK_ADAPTER]).is_empty()
		and ForcedCoreOptions.ethernet_adapter("play", "ps2", [NETWORK_ADAPTER]).is_empty(),
		"options/ and a core with no cable is told nothing")


# ── the hub ───────────────────────────────────────────────────────────────────


func _test_hub_scene() -> void:
	var hub := _hub()
	var ilink: Node3D = load(ILINK_CABLE_SCENE).instantiate()
	add_child(ilink)
	_spawned.append(ilink)
	var lead := _lead("HubLead")
	await get_tree().process_frame

	var ports := hub.sockets()
	_eq(ports.size(), EthernetHub.PORT_COUNT, "hub/ a hub has eight sockets")
	_eq(EthernetHub.PORT_COUNT, 8, "hub/ eight, Double Dash!!'s most on one LAN")
	_ok(hub.is_in_group("spawned"), "hub/ a hub is saved with the room")
	var names := {}
	for port in ports:
		names[port.name] = true
		_eq(port.get_machine(), null, "hub/ %s belongs to no machine" % port.name)
		_eq(port.get_hub(), hub, "hub/ %s belongs to the hub" % port.name)
		_eq(port.get_device(), hub, "hub/ %s is saved against the hub" % port.name)
		_eq(CompositeCable.port_named(hub, port.name), port, "hub/ and found again by its name")
		_ok(port.can_preview(lead.get_node("PlugA0")), "hub/ %s takes an RJ45 plug" % port.name)
		_ok(not port.can_preview(ilink.get_node("PlugA0")), "hub/ %s refuses an i.LINK plug" % port.name)
		# A socket's +Z is where a plug arrives FROM, which has to be out of the box.
		var out_of_box: float = hub.to_local(port.global_position + port.global_basis.z).z \
			- hub.to_local(port.global_position).z
		_ok(out_of_box > 0.9, "hub/ %s faces out of the hub" % port.name, "local +Z step %.3f" % out_of_box)
	_eq(names.size(), ports.size(), "hub/ every socket has its own name, which a save keys on")

	var plug := lead.get_node("PlugA0") as RigidBody3D
	ports[0].pick_up_object(plug)
	await get_tree().physics_frame
	await get_tree().process_frame
	var shell := plug.get_node("PlugTip") as Node3D
	var face := hub.to_local(ports[0].global_position).z
	var shell_z := hub.to_local(shell.global_position).z
	_ok(shell_z > face, "hub/ a seated plug's boot stands outside the hub", "boot at z %.4f, face at %.4f" % [shell_z, face])
	_ok(hub.get_collision_exceptions().has(plug), "hub/ and does not shove the hub it is in")
	ports[0].drop_object()
	await get_tree().process_frame
	_ok(not hub.get_collision_exceptions().has(plug), "hub/ pulled, it collides with the hub again")
	await _clear()


# ── the adapters ──────────────────────────────────────────────────────────────


func _test_adapter(systemid: String, unit_id: String, link_port: int, core: String,
		option: String, on: String, off: String) -> void:
	var tag := "adapter/%s/ " % systemid
	var card := await _unit(unit_id)
	var port := card.get_ethernet_port()
	_ok(port != null, tag + "the card grows an RJ45 socket")
	if port == null:
		await _clear()
		return
	_eq(port.link_port, link_port, tag + "on the link port its core attaches")
	_eq(port.get_machine(), null, tag + "on the table, it belongs to no console")
	_eq(port.get_hub(), null, tag + "and to no hub")
	_eq(port.get_device(), card, tag + "a lead in it is saved against the card")
	_eq(CompositeCable.port_named(card, port.name), port, tag + "and finds the socket again on load")
	var s := card.size()
	var jack: Variant = ExpansionCatalog.ethernet_jack_of(unit_id)
	_ok(jack is Transform3D and port.transform.is_equal_approx(jack),
		tag + "on the table, in the real card's jack (the row's)", "%s, row %s" % [port.transform, jack])
	if jack is Transform3D:
		var at_jack := (jack as Transform3D).origin.abs()
		_ok(at_jack.x >= s.x * 0.5 or at_jack.y >= s.y * 0.5 or at_jack.z >= s.z * 0.5,
			tag + "its mouth on the box's face, not inside it", "at %s, size %s" % [(jack as Transform3D).origin, s])
	_ok(port.show_recess, tag + "the plain box draws no mouth, so the socket keeps its own")

	var sys := await _console(systemid)
	_eq(sys.all_forced_options(core).get(option), off, tag + "a bare console has its adapter off")
	sys.restore_expansion(card)
	await _wait(10)
	_eq(card.get_host(), sys, tag + "the card seats")
	# The stand-in console takes the card end-on through its back panel: only its +Y
	# end is left showing, and the socket moves there.
	var out := card.to_local(port.global_position + port.global_basis.z) - card.to_local(port.global_position)
	_ok(not sys.get_model() is RetroSystemModelDefault
		or (out.y > 0.9 and card.to_local(port.global_position).y >= s.y * 0.5),
		tag + "in the stand-in console, on the end of the card left showing, facing out of it",
		"at %s, +Z %s" % [card.to_local(port.global_position), out])
	_eq(port.get_machine(), sys, tag + "and then the socket on it is the console's")
	_eq(sys.all_forced_options(core).get(option), on, tag + "with the core's adapter on")
	_ok(sys.expansion_ids().has(unit_id), tag + "and the card is named among what is seated")

	# Out of the console, measured in its frame: what a player has to reach.
	var body: AABB = sys.body_aabb()
	var at := sys.to_local(port.global_position)
	var dir := sys.to_local(port.global_position + port.global_basis.z) - at
	var away := at - body.get_center()
	away.y = 0.0
	_ok(not body.grow(-0.003).has_point(at), tag + "the socket is not buried in the console",
		"at %s, body %s" % [at, body])
	_ok(dir.dot(away.normalized()) > 0.5, tag + "and faces away from it", "+Z %s, away %s" % [dir, away])

	var slot := sys._unit_socket(ExpansionCatalog.socket_of(unit_id))
	_ok(slot != null and slot.picked_up_object == card, tag + "in its own slot")
	if slot != null:
		slot.forget_object(card)
		slot.drop_object()
		await _wait(5)
	_eq(card.get_host(), null, tag + "taken out, the card is loose")
	_eq(port.get_machine(), null, tag + "and its socket is nobody's")
	_eq(sys.all_forced_options(core).get(option), off, tag + "and the core's adapter is off again")
	await _clear()


## A shell that says it has the socket built in, as a slim PS2's model does.
class _SlimShell extends RetroSystemModel:
	func builtin_ethernet_port() -> int:
		return 1


func _test_built_in_socket() -> void:
	var fat := await _console("ps2", "FatPS2")
	_eq(fat.get_node_or_null("EthernetPort"), null, "slim/ a fat PlayStation 2 has no socket of its own")
	_eq(fat.all_forced_options("pcsx2").get("pcsx2_dev9_eth"), "disabled", "slim/ and no network without the card")

	var slim := await _console("ps2", "SlimPS2")
	var shell := _SlimShell.new()
	var was: RetroSystemModel = slim.get_model()
	slim._model = shell
	slim._build_builtin_ethernet_port()
	var port := slim.get_node_or_null("EthernetPort") as EthernetPort
	_ok(port != null, "slim/ a shell with the socket built in grows it on the console")
	if port != null:
		_eq(port.link_port, 1, "slim/ on the network adapter's link port")
		_eq(port.get_machine(), slim, "slim/ and it is the console's")
		_eq(port.get_device(), slim, "slim/ a lead in it is saved against the console")
		_eq(CompositeCable.port_named(slim, port.name), port, "slim/ and finds it again on load")
		slim._build_builtin_ethernet_port()
		_eq(slim.get_children().filter(func(n: Node) -> bool: return n is EthernetPort).size(), 1,
			"slim/ asking twice builds one socket")
	_eq(slim.all_forced_options("pcsx2").get("pcsx2_dev9_eth"), "link", "slim/ the core's adapter is on")
	_ok(not slim.expansion_ids().has(NETWORK_ADAPTER), "slim/ without a card being named as seated")
	var card := await _unit(NETWORK_ADAPTER)
	_ok(not slim.expansion_hardware().accepts_unit(card, ExpansionCatalog.socket_of(NETWORK_ADAPTER)),
		"slim/ and it takes no Network Adapter card: it has no bay")
	_ok(fat.expansion_hardware().accepts_unit(card, ExpansionCatalog.socket_of(NETWORK_ADAPTER)),
		"slim/ where a fat one does")
	slim._model = was
	shell.free()
	await _clear()


# ── the LAN ───────────────────────────────────────────────────────────────────


## Three PlayStation 2s, a hub, three leads: one LAN of three, every console on
## its network adapter's port.
func _test_lan_through_a_hub() -> void:
	var consoles: Array[RetroSystem] = []
	for k in range(3):
		consoles.append(await _cabled_console("ps2", "LanPS2_%d" % k))
	var hub := _hub()
	var leads: Array[EthernetCable] = []
	for k in range(3):
		leads.append(_lead("LanLead_%d" % k))
	await get_tree().process_frame

	var hub_ports := hub.sockets()
	for k in range(3):
		var socket := _socket_of(consoles[k])
		_ok(socket != null, "hub_lan/ %s has its adapter's socket" % consoles[k].name)
		if socket == null:
			await _clear()
			return
		socket.pick_up_object(leads[k].get_node("PlugA0"))
		hub_ports[k].pick_up_object(leads[k].get_node("PlugB0"))
	await get_tree().process_frame
	for lead in leads:
		lead._resolve()

	for k in range(3):
		_eq((leads[k].linked_machines() as Array).size(), 3,
			"hub_lan/ lead %d states the whole three-console LAN, not its own spoke" % k)
	_eq(_ports_of(leads[0].linked_machines()).values(), [1, 1, 1],
		"hub_lan/ each console on its network adapter's port")
	var bus: Array = consoles[2].net_link_bus()
	_eq(bus.size(), 3, "hub_lan/ netplay's sweep finds the whole LAN from any console")
	_eq((leads[0].held_machines() as Array).size(), 3, "hub_lan/ and the LAN is joined, not just described")
	var heads := PackedStringArray()
	for lead in leads:
		heads.append(String((lead.linked_machines()[0] as Dictionary)["machine"].name))
	_ok(heads[0] == heads[1] and heads[1] == heads[2], "hub_lan/ every lead names the same head", ", ".join(heads))

	var before := EthernetBus.joins
	consoles[0].net_refresh_link_cables()
	_eq(EthernetBus.joins - before, 1, "hub_lan/ a console restarting rejoins its LAN once, not per spoke")
	_eq((leads[2].held_machines() as Array).size(), 3, "hub_lan/ and the LAN is whole after it")

	_pull(hub_ports[1])
	await get_tree().process_frame
	leads[1]._resolve()
	_eq((leads[0].linked_machines() as Array).size(), 2, "hub_lan/ pulling one spoke leaves a LAN of two")
	_eq((leads[1].held_machines() as Array).size(), 0, "hub_lan/ and the pulled lead holds nothing")
	_eq(consoles[1].net_link_bus().size(), 0, "hub_lan/ the unplugged console is on no LAN")

	_pull(hub_ports[2])
	await get_tree().process_frame
	leads[2]._resolve()
	_eq((leads[0].linked_machines() as Array).size(), 0, "hub_lan/ one console on a hub is on no LAN")
	_eq((leads[0].held_machines() as Array).size(), 0, "hub_lan/ and holds none")
	await _clear()


## A real hub did not care what was on the other end of a lead, and neither does
## this one: two GameCubes and a PlayStation 2 are one LAN, each console on its
## own adapter's port. They hear each other's broadcasts and ignore them. Chained
## hubs are one LAN too.
func _test_gamecubes_and_ps2s_share_a_hub() -> void:
	var gc_a := await _cabled_console("gc", "MixGC_A")
	var gc_b := await _cabled_console("gc", "MixGC_B")
	var ps2 := await _cabled_console("ps2", "MixPS2")
	var hub_a := _hub()
	var hub_b := _hub()
	hub_b.position.x += 0.5
	var leads: Array[EthernetCable] = []
	for k in range(4):
		leads.append(_lead("MixLead_%d" % k))
	await get_tree().process_frame

	_socket_of(gc_a).pick_up_object(leads[0].get_node("PlugA0"))
	hub_a.sockets()[0].pick_up_object(leads[0].get_node("PlugB0"))
	_socket_of(gc_b).pick_up_object(leads[1].get_node("PlugA0"))
	hub_a.sockets()[1].pick_up_object(leads[1].get_node("PlugB0"))
	_socket_of(ps2).pick_up_object(leads[2].get_node("PlugA0"))
	hub_b.sockets()[0].pick_up_object(leads[2].get_node("PlugB0"))
	hub_a.sockets()[7].pick_up_object(leads[3].get_node("PlugA0"))
	hub_b.sockets()[7].pick_up_object(leads[3].get_node("PlugB0"))
	await get_tree().process_frame
	for lead in leads:
		lead._resolve()

	var bus: Array = leads[3].linked_machines()
	_eq(bus.size(), 3, "mixed/ two hubs chained are one LAN of three")
	_eq(_ports_of(bus), {"MixGC_A": 4, "MixGC_B": 4, "MixPS2": 1},
		"mixed/ each console attached on its own adapter's port")
	_eq((leads[0].held_machines() as Array).size(), 3, "mixed/ and it is joined")
	_eq(gc_a.net_link_bus().size(), 3, "mixed/ netplay groups the GameCubes with the PlayStation 2")
	await _clear()


## The trap the card puts in the way: taking a card out of a console moves no
## lead, so nothing else would walk the room again.
func _test_card_out_takes_the_console_off() -> void:
	var a := await _cabled_console("ps2", "CardPS2_A")
	var b := await _cabled_console("ps2", "CardPS2_B")
	var lead := _lead("CardLead")
	await get_tree().process_frame
	# Straight from one adapter to the other: a crossover, the two-console LAN.
	_socket_of(a).pick_up_object(lead.get_node("PlugA0"))
	_socket_of(b).pick_up_object(lead.get_node("PlugB0"))
	await get_tree().process_frame
	lead._resolve()
	_eq((lead.linked_machines() as Array).size(), 2, "card_out/ a lead between two adapters is a LAN of two")
	_eq((lead.held_machines() as Array).size(), 2, "card_out/ and it is joined")

	var card := b.get_expansions()[0]
	var slot := b._unit_socket(ExpansionCatalog.socket_of(card.expansion_id))
	slot.forget_object(card)
	slot.drop_object()
	await _wait(5)
	_eq(card.get_host(), null, "card_out/ the card is out of the console")
	_eq((lead.linked_machines() as Array).size(), 0, "card_out/ and the console behind it is off the LAN")
	_eq((lead.held_machines() as Array).size(), 0, "card_out/ the coordinator is told, not just the room")

	b.restore_expansion(card)
	await _wait(10)
	_eq((lead.linked_machines() as Array).size(), 2, "card_out/ put back with the lead still in it, the LAN is back")
	_eq((lead.held_machines() as Array).size(), 2, "card_out/ and joined")
	await _clear()


# ── the covers over a card's socket ───────────────────────────────────────────

const COVER_SOCKET := "serial_port_1"
const COVER_SIZE := Vector3(0.1, 0.02, 0.04)
## Any model will do for a shell that only has to exist and load.
const TEST_SHELL := "res://imported-assets/bedroom/exterior/house_a.glb"


## The stand-in box with a cover over its card socket, as a mod's shell has.
class _CoveredShell extends RetroSystemModelDefault:
	pass


func _covered_console(label: String) -> RetroSystem:
	var sys := await _console("gc", label)
	var socket := sys._unit_socket(COVER_SOCKET)
	var shell := _CoveredShell.new()
	sys.add_child(shell)
	shell.build_port_cover_slot(COVER_SOCKET, socket,
		Transform3D(Basis.IDENTITY, socket.position + Vector3(0.0, 0.05, 0.0)), COVER_SIZE)
	sys._model = shell
	return sys


func _test_port_covers() -> void:
	var sys := await _covered_console("CoveredGC")
	sys.model_variant = "spice"
	var socket := sys._unit_socket(COVER_SOCKET)
	var slot := sys.get_model().port_cover_slot(COVER_SOCKET)
	_ok(slot != null, "cover/ the shell builds a slot over the card's socket")
	if slot == null:
		await _clear()
		return
	_eq(slot.snap_require, PortCover.group_for(COVER_SOCKET), "cover/ which only a cover for that socket fits")
	_ok(socket.enabled and slot.enabled, "cover/ with both empty, both are open")

	sys.seed_port_covers()
	await _wait(5)
	var cover := slot.picked_up_object as PortCover
	_ok(cover != null, "cover/ the console is given its cover")
	if cover == null:
		await _clear()
		return
	_spawned.append(cover)
	_eq(cover.socket_id, COVER_SOCKET, "cover/ for that socket")
	_eq(cover.size, COVER_SIZE, "cover/ at the size the shell says")
	var shape := cover.get_node("CollisionShape3D") as CollisionShape3D
	_ok(shape.shape is BoxShape3D and (shape.shape as BoxShape3D).size == COVER_SIZE,
		"cover/ and collides at that size")
	_eq(cover.model_variant, "spice", "cover/ in the console's color")
	_ok(cover.is_in_group(PortCover.group_for(COVER_SOCKET))
		and not cover.is_in_group(PortCover.group_for("expansion_bay")),
		"cover/ it fits its own socket and not another console's")
	_ok(not cover.is_in_group(ExpansionCover.GROUP) and not ((cover as Object) is ExpansionCover),
		"cover/ and is no N64 lid, which a mod dressing lids would dress")
	_ok(not socket.enabled, "cover/ with the cover on, the socket takes no card")
	sys.seed_port_covers()
	await _wait(3)
	_eq(get_tree().get_nodes_in_group(PortCover.GROUP).size(), 1, "cover/ seeding again adds no second cover")
	_eq(sys.get_port_covers(), {COVER_SOCKET: cover}, "cover/ a save records it on")

	slot.drop_object()
	cover.freeze = true
	await _wait(3)
	_ok(socket.enabled, "cover/ the cover off, the socket is open")
	_ok(slot.enabled, "cover/ and so is the cover's slot")
	_eq(sys.get_port_covers(), {COVER_SOCKET: null}, "cover/ a save records it off")

	var card := await _unit(BBA)
	sys.restore_expansion(card)
	await _wait(5)
	_eq(card.get_host(), sys, "cover/ the card goes in where the cover was")
	_ok(not slot.enabled, "cover/ and while it is in, the cover cannot go back on")
	sys.seed_port_covers()
	await _wait(3)
	_ok(not slot.has_snapped_object(), "cover/ an old room given its covers leaves a seated card alone")
	socket.forget_object(card)
	socket.drop_object()
	await _wait(5)
	_ok(slot.enabled, "cover/ the card out, the cover can go back")
	sys.restore_port_cover(COVER_SOCKET, cover)
	await _wait(3)
	_eq(slot.picked_up_object, cover, "cover/ a saved cover goes back on")
	_ok(not socket.enabled, "cover/ and shuts the socket again")

	var sp := ScenePersistence.new()
	var rec: Dictionary = JSON.parse_string(JSON.stringify(sp.serialize_node(cover, 7, {})))
	_eq(rec.get("type"), "port_cover", "cover/ saved as a cover")
	_eq(rec.get("cover_socket"), COVER_SOCKET, "cover/ with its socket")
	_eq(rec.get("model_variant"), "spice", "cover/ and its color")
	var back := sp.deserialize_object(rec) as PortCover
	_ok(back != null and back.socket_id == COVER_SOCKET and back.size.is_equal_approx(COVER_SIZE)
		and back.model_variant == "spice", "cover/ and a load builds the same cover")
	if back != null:
		_ok(back.is_in_group(PortCover.group_for(COVER_SOCKET)), "cover/ that fits the same socket")
		back.free()
	var sys_rec: Dictionary = sp.serialize_node(sys, 1, {cover: 7})
	_eq(sys_rec.get("port_covers"), {COVER_SOCKET: 7}, "cover/ the console's record names its cover")
	var ids := {1: true, 7: true}
	var base := {"id": 1, "type": "system", "position": [0, 0, 0], "rotation": [0, 0, 0]}
	_eq(ScenePersistence._entry_validation_error(base.merged({"port_covers": {COVER_SOCKET: 7}}), ids), "",
		"cover/ a record naming its cover is valid")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"port_covers": [7]}), ids).is_empty(),
		"cover/ covers that are not by socket are refused")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"port_covers": {COVER_SOCKET: 9}}), ids).is_empty(),
		"cover/ and a cover that is not in the save")
	_ok(not ScenePersistence._entry_validation_error({"id": 7, "type": "port_cover",
		"position": [0, 0, 0], "rotation": [0, 0, 0], "cover_size": [0.1, 0.02]}, ids).is_empty(),
		"cover/ and a cover whose size is not three numbers")
	var plain := await _console("gc", "PlainGC")
	_ok(not sp.serialize_node(plain, 2, {}).has("port_covers"),
		"cover/ a console whose shell has no covers saves as it did")
	await _clear()


## A mod's shell says where its jack is, and the socket goes there, drawn by the
## shell rather than by itself.
func _test_shell_jack() -> void:
	var size := Vector3(0.1093, 0.0486, 0.02215)
	var jack := Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)),
		Vector3(-0.05415, 0.0, -0.002825))
	_ok(not ExpansionCatalog.register_mod_shell(BBA,
		{"shell": TEST_SHELL, "size": size, "jack": Vector3.ZERO}, "ethernet_tests").is_empty(),
		"jack/ a shell's jack is a transform and nothing else")
	_eq(ExpansionCatalog.register_mod_shell(BBA,
		{"shell": TEST_SHELL, "size": size, "jack": jack}, "ethernet_tests"), "",
		"jack/ a mod's shell may say where its jack is")
	var card := await _unit(BBA)
	var port := card.get_ethernet_port()
	_ok(port != null and port.transform.is_equal_approx(jack), "jack/ and the socket is in it",
		str(port.transform if port != null else null))
	_ok(port != null and not port.show_recess and not port.show_legend,
		"jack/ with the shell drawing the jack's mouth, not the socket")
	ExpansionCatalog._mod_shells.erase(BBA)
	var plain := await _unit(BBA)
	var plain_port := plain.get_ethernet_port()
	var row_jack: Variant = ExpansionCatalog.ethernet_jack_of(BBA)
	_ok(plain_port != null and plain_port.show_recess and row_jack is Transform3D
		and plain_port.transform.is_equal_approx(row_jack),
		"jack/ without a shell, the plain box has the socket in the row's jack, its recess its own")
	await _clear()
