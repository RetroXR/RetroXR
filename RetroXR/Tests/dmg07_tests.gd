## The DMG-07 4 Player Adapter in the room (Dmg07Adapter) -- headless, no core
## runs (auto_power is off; wants_power() is asked instead).
##
##     "$godot" --headless --path RetroXR res://Tests/dmg07_tests.tscn
##
## Groups:
##   scene/  three DMG sockets for players 2-4 on link ports 1-3, each facing out
##           of its own face (by sign) and toward the end the photograph has it;
##           player 1's port 0 in the back holds the captive DMG-04 lead, whose
##           plug cannot be taken and which is not a "spawned" object of its own;
##           the adapter is a machine its sockets belong to
##   bus/    four original Game Boys: player 1's lead and three DMG-04s make four
##           wires of two, each a Game Boy's port 0 and the adapter's port k; its
##           power is player 1's plug in a Game Boy
##   save/   an entry naming where player 1's lead is, which validates, and a new
##           adapter put back there; a lead in a socket saved by that lead
##   spawn/  the Game Boy and Game Boy Color cards offer it
extends "res://Tests/test_suite.gd"

const ADAPTER_SCENE := preload("res://Scenes/Objects/peripherals/dmg07_adapter.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const DMG_LEAD_SCENE := preload("res://Scenes/Objects/cables/dmg_link_cable.tscn")

var _spawned: Array[Node] = []
## What each adapter's lead_made reported: adapter -> lead.
var _made := {}


func _ready() -> void:
	suite_tag = "dmg07"
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[dmg07] TIMED OUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	await _group_scene()
	await _group_bus_and_save()
	_group_spawn()
	_finish()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)


func _adapter(at: Vector3) -> Dmg07Adapter:
	var a := ADAPTER_SCENE.instantiate() as Dmg07Adapter
	a.auto_power = false
	a.position = at
	a.freeze = true
	a.lead_made.connect(func(l: LinkCable) -> void: _made[a] = l)
	add_child(a)
	_spawned.append(a)
	return a


func _game_boy(at: Vector3, n: int) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gb"
	sys.name = "GameBoy%d" % n
	sys.position = at
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	return sys


# -- scene ---------------------------------------------------------------------------

func _group_scene() -> void:
	var a := _adapter(Vector3(0, 1, 0))
	await _wait(6)
	var socks := a.sockets()
	_eq(socks.size(), 3, "scene/three sockets, players 2-4")
	if socks.size() != 3:
		await _clear()
		return
	_eq(socks.map(func(p: LinkPort) -> int: return p.link_port), [1, 2, 3], "scene/on link ports 1-3")
	_ok(socks.all(func(p: LinkPort) -> bool: return p.connector == "dmg_link_plug"),
		"scene/each the original Game Boy's large socket")
	_ok(socks.all(func(p: LinkPort) -> bool: return p.get_machine() == a), "scene/each belongs to the adapter")
	_ok(MachineLookup.is_machine(a), "scene/the adapter is a machine (it keeps a core of its own)")
	# By sign: a socket's +Z is out of its face (the way a plug arrives from).
	var p2 := socks[0].transform
	var p3 := socks[1].transform
	var p4 := socks[2].transform
	_ok(p2.basis.z.x < -0.9 and p2.origin.x < -0.04, "scene/player 2 faces out of the left side", str(p2.basis.z))
	_ok(p3.basis.z.z > 0.9 and p3.origin.z > 0.04, "scene/player 3 out of the front", str(p3.basis.z))
	_ok(p4.basis.z.x > 0.9 and p4.origin.x > 0.04, "scene/player 4 out of the right side", str(p4.basis.z))
	_ok(absf(p2.origin.z) < 0.001 and absf(p3.origin.x) < 0.001 and absf(p4.origin.z) < 0.001,
		"scene/each in the middle of its face, as the photographs have them",
		"%.4f %.4f %.4f" % [p2.origin.z, p3.origin.x, p4.origin.z])
	var cord := a.get_node_or_null("Player1Port") as LinkPort
	_ok(cord != null and cord.link_port == 0 and cord.transform.origin.z < -0.04 and cord.transform.basis.z.z < -0.9,
		"scene/player 1's port 0 is in the back, facing out of it")
	_ok(cord != null and absf(cord.transform.origin.x) < 0.001, "scene/in the middle of the back")
	var lead := a.lead()
	_ok(is_instance_valid(lead), "scene/player 1's lead is made")
	if is_instance_valid(lead):
		var plug_a := lead.get_node("PlugA0") as XRToolsPickable
		_ok(cord != null and cord.picked_up_object == plug_a, "scene/its end is seated in port 0")
		_ok(not plug_a.enabled, "scene/and cannot be taken out")
		_ok(not lead.is_in_group("spawned"), "scene/the lead is the adapter's, not an object of its own")
		_eq((lead.get_node("PlugB0") as RcaPlug).connector, "dmg_link_plug", "scene/its free end is the large plug")
		# Not the DMG-04's scene: a mod that dresses DMG-04 leads by scene path
		# (xenu.gblink) must leave it to the adapter's own (xenu.dmg07).
		_eq(lead.scene_file_path, "res://Scenes/Objects/cables/dmg07_lead.tscn", "scene/the lead is a scene of its own")
		_ok(_made.get(a) == lead, "scene/and lead_made said so, with the lead")
	await _clear()
	_ok(not is_instance_valid(lead), "scene/and goes with the adapter")


# -- bus and save ------------------------------------------------------------------------

func _port_of(sys: RetroSystem) -> LinkPort:
	return sys.find_child("LinkPort", true, false) as LinkPort


func _group_bus_and_save() -> void:
	var a := _adapter(Vector3(0, 1, 0))
	var gbs: Array[RetroSystem] = []
	for i in 4:
		gbs.append(_game_boy(Vector3(-0.6 + 0.4 * i, 1, 0.6), i + 1))
	var leads: Array[LinkCable] = []
	for i in 3:
		var l := DMG_LEAD_SCENE.instantiate() as LinkCable
		add_child(l)
		_spawned.append(l)
		leads.append(l)
	await _wait(6)
	if not gbs.all(func(g: RetroSystem) -> bool: return _port_of(g) != null) or not is_instance_valid(a.lead()):
		_ok(false, "bus/four Game Boys with link sockets and the adapter's lead")
		await _clear()
		return
	_ok(not a.wants_power(), "bus/with player 1's plug loose, the adapter is off")
	_port_of(gbs[0]).pick_up_object(a.lead().get_node("PlugB0"))
	for i in 3:
		_port_of(gbs[i + 1]).pick_up_object(leads[i].get_node("PlugA0"))
		a.sockets()[i].pick_up_object(leads[i].get_node("PlugB0"))
	await _wait(4)
	_ok(a.wants_power(), "bus/player 1's plug in a Game Boy powers it")
	# Its Libretro node, as a powered adapter has, without starting a core: the
	# walk joins only machines that have one (an off Game Boy keeps its own).
	_ok(a.get_libretro_node() == null, "bus/an unpowered adapter has no core to join")
	a.call("_ensure_lib")
	for c: LinkCable in [a.lead()] + leads:
		c._resolve()

	var all: Array[LinkCable] = [a.lead()]
	all.append_array(leads)
	for k in 4:
		var bus: Array = all[k].linked_machines()
		var has_gb := bus.any(func(e: Dictionary) -> bool: return e.get("machine") == gbs[k] and int(e.get("port", -1)) == 0)
		var has_ad := bus.any(func(e: Dictionary) -> bool: return e.get("machine") == a and int(e.get("port", -1)) == k)
		_ok(bus.size() == 2 and has_gb and has_ad,
			"bus/player %d's wire is two: Game Boy %d's port 0 and the adapter's port %d" % [k + 1, k + 1, k],
			str(bus.map(func(e: Dictionary) -> String: return "%s:%d" % [(e.get("machine") as Node).name, int(e.get("port", -1))])))

	# Saved: where player 1's lead is, and each socket's lead names the adapter.
	var sp := ScenePersistence.new()
	var ids := {a: 1, gbs[0]: 2, gbs[1]: 3, gbs[2]: 4, gbs[3]: 5}
	var rec: Dictionary = sp.serialize_node(a, 1, ids)
	_eq(str(rec.get("type", "")), "dmg07_adapter", "save/it has an entry of its own")
	var lead_rec: Dictionary = rec.get("lead", {})
	_ok(lead_rec.get("device") == 2 and str(lead_rec.get("port", "")) == str(_port_of(gbs[0]).name),
		"save/naming the Game Boy and socket player 1's lead is in", str(lead_rec))
	var l2: Dictionary = sp.serialize_node(leads[0], 10, ids)
	var b_end: Array = (l2.get("plugs", []) as Array).filter(func(p: Dictionary) -> bool: return int(p.get("end", -1)) == 1)
	_ok(b_end.size() == 1 and b_end[0].get("device") == 1 and str(b_end[0].get("port", "")) == "Player2Port",
		"save/a lead in player 2's socket is saved by the lead, naming the adapter and Player2Port", str(b_end))
	_eq(ScenePersistence._objects_validation_error([rec]), "", "save/the entry validates")

	# Pull player 1's plug: off.
	_port_of(gbs[0]).drop_object()
	await _wait(3)
	_ok(not a.wants_power(), "bus/pulled, it is off again")

	# A new adapter put back where the save says.
	var b := _adapter(Vector3(0.5, 1.2, -0.4))
	b.restore_lead(gbs[0], str(lead_rec.get("port", "")))
	await _wait(8)
	_ok(is_instance_valid(b.lead()) and _port_of(gbs[0]).picked_up_object == b.lead().get_node("PlugB0"),
		"save/a restored adapter's lead goes back into that Game Boy")
	_ok(b.wants_power(), "save/and powers it")
	await _clear()


# -- spawn ---------------------------------------------------------------------------------

func _group_spawn() -> void:
	for sid: String in ["gb", "gbc"]:
		_ok(SpawnCatalog.items_for(sid).any(func(i: Dictionary) -> bool: return str(i.get("spawn", "")) == "dmg07_adapter"),
			"spawn/the %s card offers it" % sid)
	_ok(ScenePersistence.PLAIN_SCENES.has("dmg07_adapter"), "spawn/a saved room can rebuild it")
