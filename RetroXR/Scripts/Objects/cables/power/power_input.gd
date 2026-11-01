## PowerInput — what a device runs on, and whether any of it has power right now.
##
## One per powered object, a child named NODE_NAME, made by on(). The object says
## what it takes as it builds itself: an inlet a lead goes into (`add_inlet`: a mains
## inlet, a DC jack, an adapter's dock), a cord of its own (`captive`), a battery it
## carries inside (`internal_battery`). Cells are read off the object's CellSlots,
## whatever built them. It has power when ANY of those does -- or when the room
## powers everything (MainsPower.everything_powered: power simulation is off,
## or there is no wall outlet in the room).
##
## A device that takes nothing at all (a mod's console with no inlet modelled yet) is
## always powered, and says so once: refusing it would leave a machine nobody can
## ever switch on.
##
## The answer is re-asked on MainsPower.changed() and power_changed is emitted only
## when it moves. The words describe() and why_not() return are the ones the device's
## menu and its "No power" card show, so both say the same thing.
class_name PowerInput
extends Node

## The supply came or went. `live` is the new answer.
signal power_changed(live: bool)

const NODE_NAME := "PowerInput"

## What the logs call the device.
var label := ""
## A rechargeable pack built in (a GBA SP, a DS, a PSP): always charged, as no charge
## is modelled. Its DC jack only charges it, so it is not added as an inlet.
var internal_battery := false
## The device's own mains cord (CaptiveMainsCord), or null. Duck-typed: `wall_plug`
## and `hidden`.
var captive: Node = null
## The PowerInput this device runs off instead of a supply of its own: a deck built
## into a combo set has power while the set does (ApplianceMains.follow).
var follow: PowerInput = null
## A supply that reaches the device through something it is joined to, which can
## change: the Virtual Boy's comes up its controller's cord, the controller's from
## the unit clipped on its back. Returns that thing's PowerInput, or null while
## nothing is there. `through_noun` names it in the supply line ("Controller"),
## `through_missing` says what is missing ("No controller plugged in").
var through: Callable = Callable()
var through_missing := ""
## What this device is called in another's supply line ("battery pack"); its
## label when empty.
var noun := ""

var _inlets: Array[Node] = []
var _live := false
var _asked := false
var _said_nothing := false


## The PowerInput of `host`, made on first use.
static func on(host: Node) -> PowerInput:
	var input := of(host)
	if input == null and host != null:
		input = PowerInput.new()
		input.name = NODE_NAME
		host.add_child(input)
	return input


## The PowerInput of `host`, or null for something that consumes nothing.
static func of(host: Node) -> PowerInput:
	return host.get_node_or_null(NODE_NAME) as PowerInput if host != null else null


## A socket on the device that a supply's plug goes into: a mains inlet, a DC jack.
func add_inlet(port: Node) -> void:
	if port != null and not _inlets.has(port):
		_inlets.append(port)
		MainsPower.changed(get_tree() if is_inside_tree() else null)


func inlets() -> Array[Node]:
	var out: Array[Node] = []
	for port: Node in _inlets:
		if is_instance_valid(port):
			out.append(port)
	return out


func _ready() -> void:
	add_to_group(MainsPower.CONSUMER_GROUP)
	if label.is_empty():
		label = _host_label()
	on_mains_changed.call_deferred()


## The answer as last announced (power_changed). Before the first announcement it is
## asked now.
func is_live() -> bool:
	if not _asked:
		return bool(evaluate()["live"])
	return _live


## Whether this device's own supply reaches it, the room's leniency aside: what the
## menu's status line and the toast talk about.
func supplied() -> bool:
	return bool(evaluate()["supplied"])


## MainsPower's call: ask again, and announce a change.
func on_mains_changed() -> void:
	if not is_inside_tree():
		return
	var answer := evaluate()
	var live := bool(answer["live"])
	if _asked and live == _live:
		return
	var first := not _asked
	_asked = true
	_live = live
	print("[Power] %s: %s -- %s" % [label, "has power" if live else "NO power",
		str(answer["supply"])])
	if not first or not live:
		power_changed.emit(live)


## What powers the device, as its menu says it: {live, supplied, supply}.
## `supplied` is whether its own supply is live (a cord in a live socket, cells in
## every bay); `live` adds the room's leniency.
func evaluate() -> Dictionary:
	var own := own_supply()
	var supply := str(own["supply"])
	if bool(own["supplied"]):
		return _answer(true, true, supply)
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if not AppPrefs.power_simulation:
		return _answer(true, false, "Power simulation off (Options) -- %s" % supply)
	if tree != null and not MainsPower.room_has_mains(tree):
		return _answer(true, false, "No outlets in this room: powered without a cord -- %s" % supply)
	return _answer(false, false, supply)


## The device's own supply, the room's leniency left out: {supplied, supply}. What
## evaluate() starts from, and what a device powered THROUGH this one reads, so the
## leniency is said once, by the device asked.
func own_supply() -> Dictionary:
	var lines: Array[String] = []
	var any := false
	if follow != null and is_instance_valid(follow):
		var theirs := follow.own_supply()
		return _own(bool(theirs["supplied"]), "Built in: %s" % str(theirs["supply"]))
	# The device's own cord, hidden: plugged in somewhere out of sight.
	if captive != null and is_instance_valid(captive):
		any = true
		if bool(captive.get("hidden")):
			return _own(true, "Cord hidden (plugged in out of sight)")
		var plug := captive.get("wall_plug") as Node3D
		var place := describe_wall_plug(plug)
		if MainsPower.seated_live(plug, {}):
			return _own(true, "Built-in cord, in %s" % place)
		lines.append("Built-in cord -- %s" % _dead_place(place))
	# A supply that comes through something joined to it.
	if through.is_valid():
		any = true
		var src := through.call() as PowerInput
		if src == null or not is_instance_valid(src) or src == self:
			lines.append(through_missing if not through_missing.is_empty() else "Nothing connected")
		else:
			var theirs := src.own_supply()
			var named := _cap(src.noun if not src.noun.is_empty() else src.label)
			if bool(theirs["supplied"]):
				return _own(true, "%s: %s" % [named, str(theirs["supply"])])
			lines.append("%s: %s" % [named, str(theirs["supply"])])
	for port: Node in inlets():
		any = true
		var held := (port as XRToolsSnapZone).picked_up_object as Node3D \
			if port is XRToolsSnapZone else null
		if held == null or not is_instance_valid(held):
			lines.append("Not plugged in")
			continue
		var noun := _cap(lead_noun(held))
		var up := lead_wall_plug(held)
		if MainsPower.plug_live(held, {}):
			return _own(true, "%s, in %s" % [noun, describe_wall_plug(up)]
				if up != null else noun)
		lines.append("%s -- %s" % [noun,
			_dead_place(describe_wall_plug(up)) if up != null else "has no power"])
	var slots := CellSlots.of(get_parent())
	if slots != null and not slots.seats().is_empty():
		any = true
		var seats := slots.seats().size()
		var have := slots.cells().size()
		var size := CellSlots.size_of_seat(slots.seats()[0])
		if have >= seats:
			return _own(true, "Batteries (%d %s)" % [seats, size])
		lines.append("Batteries %d of %d %s -- needs %d more" % [have, seats, size, seats - have]
			if have > 0 else "No batteries (takes %d %s)" % [seats, size])
	if internal_battery:
		return _own(true, "Built-in battery")
	if not any:
		if not _said_nothing:
			_said_nothing = true
			print("[Power] %s takes no supply that is modelled yet: always on" % label)
		return _own(true, "No power supply modelled -- always on")
	return _own(false, "; ".join(lines))


## The reason the device cannot come on, for its "No power" card.
func why_not() -> String:
	return str(evaluate()["supply"])


## The supply line, as the menu shows it.
func describe() -> String:
	return str(evaluate()["supply"])


static func _cap(s: String) -> String:
	return s if s.is_empty() else s.substr(0, 1).to_upper() + s.substr(1)


static func _answer(live: bool, own: bool, supply: String) -> Dictionary:
	return {"live": live, "supplied": own, "supply": supply}


static func _own(supplied: bool, supply: String) -> Dictionary:
	return {"supplied": supplied, "supply": supply}


## Where a wall plug sits, in words: "a wall outlet", "a power strip", or "nothing"
## when it is loose.
static func describe_wall_plug(plug: Node3D) -> String:
	if plug == null or not is_instance_valid(plug):
		return "nothing"
	var holder := PowerCord.socket_holding(plug)
	if holder == null:
		return "nothing"
	if holder.get_parent() is WallOutlet:
		return "a wall outlet"
	var at: Node = holder.get_parent()
	while at != null:
		if at.has_method("mains_live_at"):
			var noun := str(at.call("mains_noun")) if at.has_method("mains_noun") else "a socket"
			var up: Node3D = at.call("mains_wall_plug") as Node3D if at.has_method("mains_wall_plug") \
				else null
			if MainsPower.socket_live(holder, {}):
				return "a %s" % noun
			var where := describe_wall_plug(up) if up != null else "nothing"
			return "a %s that is %s" % [noun, "not plugged in" if where == "nothing"
				else "in %s with no power" % where]
		at = at.get_parent()
	return "a socket with no power"


## The words for a plug's place when it has no power.
static func _dead_place(place: String) -> String:
	if place == "nothing":
		return "not plugged in"
	return "in %s" % place


## What the lead holding `plug` is called: "power cord", "AC adapter".
static func lead_noun(plug: Node3D) -> String:
	var end := plug as RcaPlug
	var lead: Node = end.cable if end != null and is_instance_valid(end.cable) else null
	if lead != null and lead.has_method("mains_noun"):
		return str(lead.call("mains_noun"))
	return "power cord"


## The wall plug of the lead `plug` is the appliance end of, or null.
static func lead_wall_plug(plug: Node3D) -> Node3D:
	var end := plug as RcaPlug
	var lead: Node = end.cable if end != null and is_instance_valid(end.cable) else null
	if lead != null and lead.has_method("mains_wall_plug"):
		return lead.call("mains_wall_plug") as Node3D
	return null


func _host_label() -> String:
	var host := get_parent()
	if host == null:
		return "<nothing>"
	var shown: Variant = host.get("display_name")
	if shown is String and not (shown as String).is_empty():
		return "%s (%s)" % [shown, host.name]
	return str(host.name)
