## A GameCube-to-Game Boy Advance lead.
##
## The DOL-011: a purple cord with a wide grey plug for a console's controller
## socket at one end and a grey barrel for a handheld's EXT port at the other.
## Four Swords Adventures gives every player one, and the handheld becomes their
## controller and their second screen.
##
## What it resolves into differs from a link cable in two ways, and both come
## from the machines not being peers.
##
## The console ASKS and the handheld ANSWERS. That is a different conversation
## from two handhelds trading a word each, so it carries a different protocol id
## on the bus, and the bus refuses to join one to the other. Physically a Game
## Boy Advance has one EXT socket and what is in it decides who it talks to, so
## the handheld keeps two bus ports and the CABLE picks which one it means.
##
## And the console has to be told what is on the port. A handheld on a GameCube
## lead is a controller as far as the machine is concerned, so seating the plug
## announces its device type the way any pad's would -- there is no separate step
## and nothing else to configure. Pulling it out puts the port back.
class_name GcGbaCable
extends CompositeCable

## The bus port the handheld keeps for a GameCube lead, beside the one its link
## cable uses. Two ports on one socket, told apart by which cable is in it.
const GBA_JOY_PORT := 1

## The pair currently joined, as {console, gba, port}, so a pull can be undone
## against the same machines even if one of them has since been switched off.
var _linked: Dictionary = {}


func _resolve() -> void:
	if not is_inside_tree():
		return

	var console := _console_end()
	var handheld := _handheld_end()
	if netplay_took_bus(linked_machines(), held_machines()):
		if console.is_empty() or handheld == null:
			_linked = {}
		else:
			_linked = {"libretro": console["libretro"], "gba": handheld,
				"port": console["port"], "machine": console.get("machine"),
				"gba_machine": _machine_of(handheld)}
	elif console.is_empty() or handheld == null:
		_disconnect()
	else:
		_join(console, handheld)

	_report_seating_changes()
	topology_changed.emit()


## The bus this lead makes, as [{machine, port}], console first.
##
## Console first because that end is the one handed to LinkConnect, the same
## rule the handheld lead follows for its purple end. The two ports are not the
## same number and never were: one counts sockets on a console, the other says
## which of a handheld's two conversations this cable is.
func linked_machines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var console := _console_end()
	var handheld := _handheld_end()
	if console.is_empty() or handheld == null:
		return out
	var console_machine: Object = console.get("machine")
	var handheld_machine: Object = _machine_of(handheld)
	if console_machine == null or handheld_machine == null:
		return out
	out.append({"machine": console_machine, "port": int(console["port"])})
	out.append({"machine": handheld_machine, "port": GBA_JOY_PORT})
	return out


## The machine owning a Libretro node, by walking back up out of it.
func _machine_of(lib: Node) -> Object:
	return MachineLookup.owning_machine(lib)


## The pair this lead is still holding, console first, for a pull.
func held_machines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _linked.is_empty():
		return out
	var console: Object = _linked.get("machine")
	var gba: Object = _linked.get("gba_machine")
	if console == null or gba == null:
		return out
	out.append({"machine": console, "port": int(_linked.get("port", 0))})
	out.append({"machine": gba, "port": GBA_JOY_PORT})
	return out


## The console this lead's wide end is in, and which of its ports, or {}.
func _console_end() -> Dictionary:
	for e in [End.A, End.B]:
		var plugs := _end_plugs(e)
		if plugs.is_empty():
			continue
		var plug := plugs[0] as GcLinkPlug
		if plug == null or plug.seated_system == null:
			continue
		if not is_instance_valid(plug.seated_system):
			continue
		var lib: Libretro = plug.seated_system.get_libretro_node()
		if lib == null:
			continue
		return {"libretro": lib, "port": plug.seated_port_index,
			"machine": plug.seated_system}
	return {}


## The handheld this lead's barrel end is in, or null.
func _handheld_end() -> Libretro:
	for e in [End.A, End.B]:
		var plugs := _end_plugs(e)
		if plugs.is_empty():
			continue
		var plug := plugs[0] as RcaPlug
		if plug == null or plug is GcLinkPlug:
			continue
		var port := plug.seated_port() as LinkPort
		if port == null:
			continue
		return port.get_libretro()
	return null


func _join(console: Dictionary, handheld: Libretro) -> void:
	if _linked.get("libretro") == console["libretro"] \
			and _linked.get("gba") == handheld \
			and _linked.get("port") == console["port"]:
		return          # already joined to exactly this pair

	_disconnect()

	var lib: Libretro = console["libretro"]
	var port: int = console["port"]
	if port < 0:
		return
	# The console's port index and the handheld's GameCube port, which are not the
	# same number and never were: one counts sockets on a console, the other says
	# which of a handheld's two conversations this cable is.
	if lib.LinkConnect(handheld, port, GBA_JOY_PORT):
		_linked = {"libretro": lib, "gba": handheld, "port": port,
			"machine": console.get("machine"), "gba_machine": _machine_of(handheld)}
		_log("joined")


func _disconnect() -> void:
	var was := _linked
	_linked = {}
	if was.is_empty():
		return
	# Cleared first, and read out of the dictionary rather than through a typed
	# variable: binding a freed object to one faults before is_instance_valid can
	# answer, and a machine really can go away between joining and pulling.
	if is_instance_valid(was["libretro"]):
		was["libretro"].LinkDisconnect(was["port"])
	if is_instance_valid(was["gba"]):
		was["gba"].LinkDisconnect(GBA_JOY_PORT)
	_log_ends("parted", was)


func _log(verb: String) -> void:
	_log_ends(verb, _linked)


func _log_ends(verb: String, ends: Dictionary) -> void:
	# Worth saying out loud for the same reason the link cable says it: a console
	# and a handheld that are cabled and not talking look exactly like a console
	# and a handheld that are not cabled, and the peer count is the only thing
	# that tells them apart, because it comes back from the cores.
	if ends.is_empty():
		return
	# Checked BEFORE they are bound to typed variables. Binding a freed object to
	# one faults on the assignment, before is_instance_valid gets to answer, and
	# this runs from the disconnect path -- which is exactly where a machine has
	# just gone away.
	var gc_peers := 0
	var gba_peers := 0
	if is_instance_valid(ends["libretro"]):
		var lib: Libretro = ends["libretro"]
		gc_peers = lib.LinkPeerCount(ends["port"])
	if is_instance_valid(ends["gba"]):
		var gba: Libretro = ends["gba"]
		gba_peers = gba.LinkPeerCount(GBA_JOY_PORT)
	print("[GcGbaCable] %s %s port %d <-> handheld  (%d and %d peers)" % [
		name, verb, ends["port"], gc_peers, gba_peers])


## Deliberately empty. This lead carries no picture and no sound, and AvGraph
## duck-types on this method, so an empty list is how it says "not mine".
func links() -> Array[Dictionary]:
	return []


## Left alone. CompositeCable tints each plug with its cord's colour so the wires
## of a multi-cord lead can be told apart; this lead has one cord and two ends
## that differ by SHAPE rather than by wire, which is the whole point of it.
func _tint_plug(_plug: RcaPlug, _col: Color) -> void:
	pass


func _exit_tree() -> void:
	# Carried out of the room, or a scene change. Leaving the cores joined would
	# hold each other up over a lead that no longer exists.
	_disconnect()
