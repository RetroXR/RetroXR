## A PlayStation link cable — the SCPH-1040.
##
## A grey cord with an identical connector at each end, joining the serial
## sockets on the back of two consoles. Wipeout, Doom, Destruction Derby and
## Formula 1 all take one; the second console needs its own copy of the disc.
##
## Two consoles and no more. That is the difference from the Game Boy Advance
## lead and it is what makes this a separate class rather than a LinkCable with a
## different plug on it. A GBA lead carries an inline junction so a third and
## fourth player can chain onto the same wire, and most of LinkCable is about
## walking those chains and deciding who is player one. A PlayStation link cable
## is a null modem between peers: transmit crossed to receive, DTR to DSR, RTS to
## CTS, both ways. Neither console owns the clock, there is no seat to assign,
## and there is nothing in the middle to walk through. So this is the GameCube
## lead's shape — a plain CompositeCable that resolves a pair — with the ends
## symmetric instead of asymmetric.
##
## What it resolves into is one call: the two cores are told they share a wire.
## Everything after that is theirs. Whether the running core can carry a link at
## all is not this cable's business either: a core that never joins the bus
## leaves the lead sitting there doing nothing, which is also what happens when
## the console on the other end is switched off.
class_name PsxLinkCable
extends CompositeCable

## Frames to wait before saying the wire again after a machine comes back. Long
## enough that a console powering up does not get a stream of them while its core
## is still starting.
const RESTATE_COOLDOWN := 20

## The pair currently joined, as {a, b, machine_a, machine_b, port_a, port_b}, so
## a pull can be undone against the same machines even if one of them has since
## been switched off.
var _linked: Dictionary = {}

## Whether each end's machine was powered on last frame, keyed the same way.
## A machine switched off takes the wire with it, and only the edge back on is
## worth reacting to.
var _powered: Dictionary = {}

var _restate_wait := 0


func _resolve() -> void:
	if not is_inside_tree():
		return

	var a := _console_end(End.A)
	var b := _console_end(End.B)
	if netplay_took_bus(linked_machines(), held_machines()):
		if a.is_empty() or b.is_empty() or a["libretro"] == b["libretro"]:
			_linked = {}
			_powered = {}
		else:
			_linked = {
				"a": a["libretro"], "b": b["libretro"],
				"machine_a": a["machine"], "machine_b": b["machine"],
				"port_a": a["port"], "port_b": b["port"],
			}
			_powered = {
				"machine_a": bool(a["machine"].is_powered_on),
				"machine_b": bool(b["machine"].is_powered_on),
			}
		_restate_wait = RESTATE_COOLDOWN
	elif a.is_empty() or b.is_empty() or a["libretro"] == b["libretro"]:
		_disconnect()
	else:
		_join(a, b)

	_report_seating_changes()
	topology_changed.emit()


## The bus this lead makes, as [{machine, port}]. End A first, arbitrarily but
## consistently: neither console owns the clock on a null modem, so the order
## only has to be the same answer every time it is asked.
func linked_machines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := _console_end(End.A)
	var b := _console_end(End.B)
	if a.is_empty() or b.is_empty() or a["libretro"] == b["libretro"]:
		return out
	if a.get("machine") == null or b.get("machine") == null:
		return out
	out.append({"machine": a["machine"], "port": int(a["port"])})
	out.append({"machine": b["machine"], "port": int(b["port"])})
	return out


## The pair this lead is still holding, for a pull.
func held_machines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _linked.is_empty():
		return out
	var ma: Object = _linked.get("machine_a")
	var mb: Object = _linked.get("machine_b")
	if ma == null or mb == null:
		return out
	out.append({"machine": ma, "port": int(_linked.get("port_a", 0))})
	out.append({"machine": mb, "port": int(_linked.get("port_b", 0))})
	return out


## The console this end is plugged into, as {libretro, machine, port}, or {}.
func _console_end(e: int) -> Dictionary:
	var plugs := _end_plugs(e)
	if plugs.is_empty():
		return {}
	var plug := plugs[0] as RcaPlug
	if plug == null:
		return {}
	var port := plug.seated_port() as PsxLinkPort
	if port == null:
		return {}
	var lib := port.get_libretro()
	if lib == null:
		return {}
	return {"libretro": lib, "machine": port.get_machine(), "port": port.link_port}


func _join(a: Dictionary, b: Dictionary) -> void:
	if _linked.get("a") == a["libretro"] and _linked.get("b") == b["libretro"] \
			and _linked.get("port_a") == a["port"] and _linked.get("port_b") == b["port"]:
		return          # already joined to exactly this pair

	_disconnect()

	var lib: Libretro = a["libretro"]
	if lib.LinkConnect(b["libretro"], a["port"], b["port"]):
		_linked = {
			"a": a["libretro"], "b": b["libretro"],
			"machine_a": a["machine"], "machine_b": b["machine"],
			"port_a": a["port"], "port_b": b["port"],
		}
		_powered = {}
		_restate_wait = RESTATE_COOLDOWN
		_log("joined")


func _disconnect() -> void:
	var was := _linked
	_linked = {}
	_powered = {}
	if was.is_empty():
		return
	# Cleared first, and read out of the dictionary rather than through a typed
	# variable: binding a freed object to one faults before is_instance_valid can
	# answer, and a machine really can go away between joining and pulling.
	if is_instance_valid(was["a"]):
		was["a"].LinkDisconnect(was["port_a"])
	if is_instance_valid(was["b"]):
		was["b"].LinkDisconnect(was["port_b"])
	_log_ends("parted", was)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_watch()


## A seated lead can stop meaning anything without a plug moving, and the room
## cannot see it happen.
##
## The bus keys a wire on the CORE, and switching a console off destroys that
## core. The lead is then still in both sockets and joined to nothing, and
## powering back on does not undo it: the new core attaches to a bus that no
## longer has this wire on it. Left alone, the player's only repair is to unplug
## and replug a cable that never moved, for a fault they were never shown.
##
## So the edge back ON is what this watches for. Not the peer count: a console
## running a core that cannot carry a link never reaches two, and re-stating the
## wire at it forever would be a busy way of achieving nothing.
func _watch() -> void:
	if _linked.is_empty():
		return

	if not is_instance_valid(_linked["a"]) or not is_instance_valid(_linked["b"]):
		_disconnect()
		return

	if _restate_wait > 0:
		_restate_wait -= 1
		return

	var came_back := false
	for key in ["machine_a", "machine_b"]:
		var machine: Node = _linked[key]
		if machine == null or not is_instance_valid(machine):
			continue
		var on: bool = machine.is_powered_on
		if on and not bool(_powered.get(key, true)):
			came_back = true
		_powered[key] = on

	if not came_back:
		return

	var lib: Libretro = _linked["a"]
	lib.LinkConnect(_linked["b"], _linked["port_a"], _linked["port_b"])
	_restate_wait = RESTATE_COOLDOWN
	_log("re-stated")


func _log(verb: String) -> void:
	_log_ends(verb, _linked)


func _log_ends(verb: String, ends: Dictionary) -> void:
	# Worth saying out loud for the reason the other leads say it: two consoles
	# that are cabled and not talking look exactly like two consoles that are not
	# cabled, and the peer count is the only thing that tells them apart, because
	# it comes back from the cores rather than from the room.
	if ends.is_empty():
		return
	# Checked BEFORE they are bound to typed variables. Binding a freed object to
	# one faults on the assignment, before is_instance_valid gets to answer, and
	# this runs from the disconnect path -- which is exactly where a machine has
	# just gone away.
	var a_peers := 0
	var b_peers := 0
	if is_instance_valid(ends["a"]):
		var a: Libretro = ends["a"]
		a_peers = a.LinkPeerCount(ends["port_a"])
	if is_instance_valid(ends["b"]):
		var b: Libretro = ends["b"]
		b_peers = b.LinkPeerCount(ends["port_b"])
	print("[PsxLinkCable] %s %s  (%d and %d peers)" % [name, verb, a_peers, b_peers])


## Deliberately empty. This lead carries no picture and no sound, and AvGraph
## duck-types on this method, so an empty list is how it says "not mine".
func links() -> Array[Dictionary]:
	return []


## Left alone. CompositeCable tints each plug with its cord's colour so the wires
## of a multi-cord lead can be told apart; this lead has one cord and two ends
## that are deliberately identical, because either end goes in either console.
func _tint_plug(_plug: RcaPlug, _col: Color) -> void:
	pass


func _exit_tree() -> void:
	# Carried out of the room, or a scene change. Leaving the cores joined would
	# hold each other up over a lead that no longer exists.
	_disconnect()
