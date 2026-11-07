## The RETRO XR AV selector (AvSwitch): four composite inputs, one TO TV, a four-position slide and four backlit labels.
##
##   godot --headless --path RetroXR res://Tests/av_switch_tests.tscn [-- --only=<group>]
##
## Real leads, a real set, a real VCR on INPUT 1 and a real Genesis on INPUT 3 through its own A/V Cable. A suite has
## no core, so a Genesis "switched on" is its `is_powered_on` flipped by hand: the switch reads exactly that.
## Groups: routing/ labels/ unplug/ chain/ save/ power/ ray/ debug/ panel/.
extends "res://Tests/test_suite.gd"

const SWITCH_SCENE := preload("res://Scenes/Objects/appliances/av_switch.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const GENESIS_AV_CABLE := preload("res://Scenes/Objects/system_models/genesis/genesis_av_cable.tscn")
const OUTLET := preload("res://Scenes/Objects/room/wall_outlet.tscn")

var _case := ""
var _failed_cases := {}
var _spawned: Array[Node] = []
var _grabber: Node3D


func _ready() -> void:
	suite_tag = "avswitch"
	quiet_passes = true
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[avswitch] TIMEOUT during '%s'" % _case)
		get_tree().quit(1))
	get_tree().current_scene = self
	_grabber = Node3D.new()
	add_child(_grabber)
	_run()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.split("=")[1]
	var cases: Array = [
		["routing/each slide position puts its input on the set", _routing],
		["labels/a source switched off is dark and lit once on; the selected one is brightest", _labels],
		["unplug/pulling a lead re-resolves at once, and seating it again brings it back", _unplug_case],
		["chain/two switches in a row carry the first one's source to the set", _chain],
		["chain/two switches cabled into each other are refused safely", _loop],
		["save/the slide is saved and restored", _save],
		["power/power simulation on with no DC: labels dark, the slide still routes", _power],
		["ray/the desktop ray takes the tab, and its box is the tab exactly", _ray],
		["debug/the Debug tab's rows follow a plug, an unplug and the slide", _debug],
		["panel/the menu's INPUT buttons move the slide", _panel],
	]
	print("[avswitch] running %d cases%s" % [cases.size(), "" if only.is_empty() else " matching '%s'" % only])
	for c: Array in cases:
		var name: String = c[0]
		if not only.is_empty() and not name.contains(only):
			continue
		_case = name
		var before := _case_count()
		await (c[1] as Callable).call()
		await _teardown()
		if _case_count() == before:
			_ok(false, "%s made no assertions — it aborted part way" % name)
		elif not _failed_cases.has(name):
			print("[avswitch] PASS  %s" % name)
	print("[avswitch] %d case(s) failed" % _failed_cases.size())
	_finish()


func _on_fail(_what: String) -> void:
	_failed_cases[_case] = true
	print("[avswitch]         in case %s" % _case)


# ── building a room ──────────────────────────────────────────────────────────

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _teardown() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)


func _put(node: Node3D, at: Vector3) -> Node3D:
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	node.position = at
	add_child(node)
	node.add_to_group("spawned")
	_spawned.append(node)
	return node


func _switch(at := Vector3(0, 1, 0)) -> AvSwitch:
	var node := SWITCH_SCENE.instantiate() as Node3D
	node.name = "AvSwitch%d" % (get_tree().get_nodes_in_group(AvSwitch.GROUP).size() + 1)
	var sw := _put(node, at) as AvSwitch
	await _wait(10)
	return sw


func _tv() -> RetroTV:
	var tv := _put(TV_SCENE.instantiate() as Node3D, Vector3(0, 1, -3)) as RetroTV
	await _wait(20)
	return tv


func _deck(at: Vector3) -> VCRPlayer:
	var deck := _put(VCR_SCENE.instantiate() as Node3D, at) as VCRPlayer
	await _wait(10)
	return deck


func _genesis(at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "genesis"
	sys.model_id = "genesis"
	_put(sys, at)
	await _wait(60)
	return sys


func _trio(dev: Node3D, names: Array) -> Array[RcaPort]:
	var out: Array[RcaPort] = []
	for n: String in names:
		out.append(dev.get_node_or_null(n) as RcaPort)
	return out


func _in(sw: AvSwitch, i: int) -> Array[RcaPort]:
	return _trio(sw, ["Input%dVideo" % i, "Input%dAudioL" % i, "Input%dAudioR" % i])


func _out(dev: Node3D) -> Array[RcaPort]:
	return _trio(dev, ["VideoOut", "AudioLOut", "AudioROut"])


func _tv_in(tv: RetroTV) -> Array[RcaPort]:
	return _trio(tv, ["CompositePort4", "AudioLIn4", "AudioRIn4"])


## A composite lead with its three cords from `from` (out sockets) to `to` (in sockets).
func _lead(from: Array, to: Array) -> CompositeCable:
	var cable := CABLE_SCENE.instantiate() as CompositeCable
	cable.position = Vector3(_spawned.size() * 0.5, 2, 1)
	add_child(cable)
	_spawned.append(cable)
	await _wait(20)
	for c in 3:
		(from[c] as RcaPort).pick_up_object(cable.get_node("PlugA%d" % c) as RcaPlug)
		(to[c] as RcaPort).pick_up_object(cable.get_node("PlugB%d" % c) as RcaPlug)
		await _wait(4)
	await _wait(20)
	return cable


## The Genesis's own A/V Cable, its mini-DIN in the console and its three phono plugs in `to`.
func _genesis_lead(md: RetroSystem, to: Array) -> Node3D:
	var lead := GENESIS_AV_CABLE.instantiate() as Node3D
	lead.position = md.position + Vector3(0.3, 0.3, 0.3)
	add_child(lead)
	_spawned.append(lead)
	await _wait(20)
	(md.find_child("AvMultiOut", true, false) as RcaPort).pick_up_object(lead.get_node("PlugA0") as RcaPlug)
	await _wait(4)
	for c in 3:
		(to[c] as RcaPort).pick_up_object(lead.get_node("PlugB%d" % c) as RcaPlug)
		await _wait(4)
	await _wait(20)
	return lead


## Out of its socket and kept out (av_tests._unplug: every socket shut for the move, the plug frozen up high).
func _unplug(plug: RcaPlug) -> void:
	var shut: Array[RcaPort] = []
	for node in get_tree().get_nodes_in_group(RcaPort.GROUP):
		var port := node as RcaPort
		if port != null and port.enabled:
			port.enabled = false
			shut.append(port)
	var seated := plug.seated_port()
	if seated != null:
		seated.drop_object()
	await _wait(4)
	plug.freeze = true
	plug.global_position += Vector3(0.0, 3.0, 0.0)
	PhysicsServer3D.body_set_state(plug.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, plug.global_transform)
	await _wait(10)
	for port in shut:
		if is_instance_valid(port):
			port.enabled = true
	await _wait(10)


func _filed(tv: RetroTV, dev: Node3D) -> bool:
	return (tv.panel()._connected_systems as Array).has(dev)


## The usual room: a set on TO TV, a VCR on INPUT 1, a Genesis (off) on INPUT 3.
func _room() -> Dictionary:
	var sw := await _switch()
	var tv := await _tv()
	var deck := await _deck(Vector3(-0.6, 1, 0.8))
	var md := await _genesis(Vector3(0.6, 1, 0.8))
	await _lead(_out(sw), _tv_in(tv))
	await _lead(_out(deck), _in(sw, 1))
	await _genesis_lead(md, _in(sw, 3))
	return {"sw": sw, "tv": tv, "deck": deck, "md": md}


func _label_energy(sw: AvSwitch, i: int) -> float:
	var m: StandardMaterial3D = sw._windows[i]
	return m.emission_energy_multiplier if m.emission_enabled else 0.0


func _row(sw: AvSwitch, section: String, label: String) -> String:
	for s: Array in sw.debug_state():
		if str(s[0]) != section:
			continue
		for r: Array in s[1]:
			if str(r[0]) == label:
				return str(r[1])
	return "<no row>"


# ── cases ────────────────────────────────────────────────────────────────────

func _routing() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var tv: RetroTV = r["tv"]
	var deck: VCRPlayer = r["deck"]
	var md: RetroSystem = r["md"]
	_eq(sw.selected, 0, "a new switch stands on INPUT 1")
	_ok(_filed(tv, deck) and deck.connected_tv == tv, "slide on 1: the set files the VCR and the VCR feeds it")
	_ok(not _filed(tv, md), "slide on 1: the Genesis on INPUT 3 is not on the set")
	var route: Dictionary = {"left": deck._feed_left, "right": deck._feed_right}
	_ok(route["left"] == 0 and route["right"] == 1, "slide on 1: the VCR's left and right reach the set's left and right",
		str(route))
	sw.select(1)
	await _wait(5)
	_ok(not _filed(tv, deck) and not _filed(tv, md) and deck.connected_tv != tv,
		"slide on 2 (nothing there): neither machine is on the set")
	sw.select(2)
	await _wait(5)
	_ok(_filed(tv, md) and md.connected_tv == tv, "slide on 3: the set files the Genesis, as if cabled directly")
	_ok(not _filed(tv, deck), "slide on 3: and not the VCR")
	sw.select(3)
	await _wait(5)
	_ok(not _filed(tv, deck) and not _filed(tv, md), "slide on 4 (nothing there): nothing on the set")
	sw.select(0)
	await _wait(5)
	_ok(_filed(tv, deck) and not _filed(tv, md), "back on 1: the VCR again")
	_ok(AvGraph.source_of(sw.get_node("VideoOut") as RcaPort).get_device() == deck,
		"AvGraph follows TO TV back to the VCR's own output")


func _labels() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var md: RetroSystem = r["md"]
	sw._refresh_labels(true)
	_eq(sw.label_state(0), AvSwitch.LabelState.SELECTED, "INPUT 1, a VCR with its supply, selected: brightest")
	_eq(sw.label_state(1), AvSwitch.LabelState.DARK, "INPUT 2, nothing on it: dark")
	_eq(sw.label_state(2), AvSwitch.LabelState.DARK, "INPUT 3, a Genesis switched OFF: dark")
	_ok(not sw.input_live(2) and not md.is_powered_on, "the Genesis is cabled but sends no picture")
	_ok(_label_energy(sw, 2) == 0.0, "the window drawn dark (no emission)")
	md.is_powered_on = true
	await get_tree().create_timer(AvSwitch.LABEL_POLL_S * 2.5).timeout
	_eq(sw.label_state(2), AvSwitch.LabelState.LIT, "the Genesis switched on: INPUT 3 lights (not selected)")
	_ok(_label_energy(sw, 2) > 0.0, "and the window is drawn lit, by the poll, with nothing else moved")
	sw.select(2)
	await _wait(3)
	_eq(sw.label_state(2), AvSwitch.LabelState.SELECTED, "the slide on 3: INPUT 3 is the selected one")
	_eq(sw.label_state(0), AvSwitch.LabelState.LIT, "and INPUT 1 drops to lit")
	_ok(_label_energy(sw, 2) > _label_energy(sw, 0) and _label_energy(sw, 0) > 0.0,
		"the selected window is brightest", "%.2f vs %.2f" % [_label_energy(sw, 2), _label_energy(sw, 0)])
	md.is_powered_on = false
	await get_tree().create_timer(AvSwitch.LABEL_POLL_S * 2.5).timeout
	_eq(sw.label_state(2), AvSwitch.LabelState.DARK, "switched off again: dark, even selected")
	_ok(_label_energy(sw, 2) == 0.0, "and drawn dark")


func _unplug_case() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var tv: RetroTV = r["tv"]
	var deck: VCRPlayer = r["deck"]
	_ok(_filed(tv, deck), "control: the VCR is on the set")
	var plug := _in(sw, 1)[0].seated_plug() as RcaPlug
	await _unplug(plug)
	_ok(not _filed(tv, deck) or deck._feed_video == false, "the VCR's video cord out of INPUT 1: no picture from it")
	_eq(sw.source_device(0), deck, "its audio cords still say the VCR is on INPUT 1")
	var lead := plug.cable as CompositeCable
	for c in [1, 2]:
		await _unplug(lead.get_node("PlugB%d" % c) as RcaPlug)
	_ok(not _filed(tv, deck) and deck.connected_tv != tv, "all three out: the set loses the VCR at once")
	_eq(sw.source_device(0), null, "and INPUT 1 has nothing")
	_eq(sw.label_state(0), AvSwitch.LabelState.DARK, "its label goes dark")
	for c in 3:
		_in(sw, 1)[c].pick_up_object(lead.get_node("PlugB%d" % c) as RcaPlug)
		await _wait(4)
	await _wait(20)
	_ok(_filed(tv, deck) and deck.connected_tv == tv, "seated again: the VCR is back on the set")
	await _unplug(_out(sw)[0].seated_plug() as RcaPlug)
	_ok(not _filed(tv, deck) or not deck._feed_video, "TO TV's video cord out: the set loses the picture")


func _chain() -> void:
	var sw1 := await _switch(Vector3(0, 1, 0))
	var sw2 := await _switch(Vector3(0, 1, 1.0))
	var tv := await _tv()
	var deck := await _deck(Vector3(-0.8, 1, 1.6))
	await _lead(_out(sw1), _tv_in(tv))
	await _lead(_out(sw2), _in(sw1, 2))
	await _lead(_out(deck), _in(sw2, 4))
	sw1.select(1)
	sw2.select(3)
	await _wait(5)
	_ok(_filed(tv, deck) and deck.connected_tv == tv, "VCR -> switch 2 INPUT 4 -> switch 1 INPUT 2 -> set: the set files the VCR")
	_eq(sw1.source_device(1), deck, "switch 1 sees the VCR on its INPUT 2, through switch 2")
	_eq(sw1.label_state(1), AvSwitch.LabelState.SELECTED, "and lights INPUT 2 for it")
	sw2.select(0)
	await _wait(5)
	_ok(not _filed(tv, deck), "switch 2 moved off INPUT 4: the set loses the VCR")
	_eq(sw1.label_state(1), AvSwitch.LabelState.DARK, "and switch 1's INPUT 2 goes dark (nothing live reaches it)")
	_ok(not sw1.loop_refused() and _row(sw1, "Chain", "Loop") == "none",
		"switch 2 on an empty input is a dead end, not a loop", _row(sw1, "Chain", "Loop"))
	_ok(_row(sw1, "Chain", "Fed by a switch").contains(String(sw2.name)), "switch 1's Debug tab says switch 2 feeds it",
		_row(sw1, "Chain", "Fed by a switch"))
	_ok(_row(sw2, "Chain", "Feeds a switch").contains(String(sw1.name)), "switch 2's says it feeds switch 1",
		_row(sw2, "Chain", "Feeds a switch"))


func _loop() -> void:
	var sw1 := await _switch(Vector3(0, 1, 0))
	var sw2 := await _switch(Vector3(0, 1, 1.0))
	var deck := await _deck(Vector3(-0.8, 1, 1.6))
	await _lead(_out(sw1), _in(sw2, 1))
	await _lead(_out(sw2), _in(sw1, 1))
	await _lead(_out(deck), _in(sw1, 2))
	sw1.select(0)
	sw2.select(0)
	await _wait(5)
	# Reaching here at all is half the check: a walk that loops never returns.
	_ok(sw1.loop_refused() and sw2.loop_refused(), "each switch's selected input is its own output: a loop, refused")
	_eq(sw1.source_device(0), null, "no machine on a looped input")
	_eq(sw1.label_state(0), AvSwitch.LabelState.DARK, "and its label is dark")
	_ok(_row(sw1, "Chain", "Loop").begins_with("REFUSED"), "the Debug tab says so", _row(sw1, "Chain", "Loop"))
	sw1.select(1)
	await _wait(5)
	_ok(not sw1.loop_refused(), "switch 1 onto INPUT 2: no loop")
	_eq(sw2.source_device(0), deck, "and switch 2 sees the VCR on INPUT 1, through switch 1")


func _save() -> void:
	var sw := await _switch()
	sw.select(2)
	await _wait(3)
	var persistence := ScenePersistence.new()
	var records: Array = persistence._serialize_articulated_controls(sw)
	var found := false
	for rec: Dictionary in records:
		if str(rec.get("path", "")) == "Selector" and is_equal_approx(float(rec.get("value", -1.0)), 2.0 / 3.0):
			found = true
	_ok(found, "the slide is saved as the Selector's value", str(records))
	var sw2 := await _switch(Vector3(0, 1, 1))
	_eq(sw2.selected, 0, "control: a fresh switch is on INPUT 1")
	persistence._restore_articulated_controls(sw2, records)
	await _wait(3)
	_eq(sw2.selected, 2, "restored: the slide is on INPUT 3")
	_ok(ScenePersistence.PLAIN_SCENES.has("av_switch") and ScenePersistence.saved_kind_types().has("av_switch"),
		"the switch spawns and saves as av_switch")


func _power() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var tv: RetroTV = r["tv"]
	var deck: VCRPlayer = r["deck"]
	_ok(sw.powered(), "power simulation off: the switch has a supply")
	_ok(sw.get_node_or_null(AvSwitch.INLET_NAME) is DcPort, "it has a DC IN")
	_eq((sw.get_node(AvSwitch.INLET_NAME) as DcPort).connector, "barrel_5_5x2_1", "a 5.5 x 2.1 barrel jack")
	_ok(PowerBrickCatalog.for_machine("av_switch", "").has("retroxr_av_adapter"), "its adapter is in the catalogue")
	# A source that stays live whatever the mains do (a console "on" is is_powered_on), so a dark label below is
	# the SWITCH's missing supply and not its source's: the VCR loses its own supply with the option on too.
	var md: RetroSystem = r["md"]
	md.is_powered_on = true
	sw._refresh_labels(true)
	_eq(sw.label_state(2), AvSwitch.LabelState.LIT, "control: the Genesis switched on lights INPUT 3")
	var sim := AppPrefs.power_simulation
	var outlet := OUTLET.instantiate() as Node3D
	_put(outlet, Vector3(2, 1, 2))
	AppPrefs.power_simulation = true
	MainsPower.changed(get_tree())
	await _wait(10)
	# The option cut the Genesis's own supply too (MainsPower powers it off): "on" again by hand, after that.
	md.is_powered_on = true
	sw._refresh_labels(true)
	_ok(not sw.powered(), "power simulation on, an outlet in the room, nothing in DC IN: no supply")
	var dark := true
	for i in AvSwitch.INPUTS:
		dark = dark and sw.label_state(i) == AvSwitch.LabelState.DARK and _label_energy(sw, i) == 0.0
	_ok(dark, "every label is dark, the switched-on Genesis's too")
	_ok(sw.input_live(2), "though the Genesis on INPUT 3 is still sending")
	_ok(_filed(tv, deck), "the slide is passive: the VCR is still on the set")
	sw.select(2)
	await _wait(5)
	_ok(not _filed(tv, deck), "and it still routes when moved")
	_eq(_row(sw, "Power", "Supply"), "dead", "the Debug tab says the supply is dead")
	AppPrefs.power_simulation = sim
	MainsPower.changed(get_tree())
	await _wait(10)
	sw.select(0)
	await _wait(3)
	_ok(sw.powered() and sw.label_state(0) == AvSwitch.LabelState.SELECTED, "power simulation off: lit again")
	md.is_powered_on = false


func _ray() -> void:
	var sw := await _switch()
	await _wait(10)
	var slider := sw.get_node("Selector") as VRSlider
	var shape := slider.get_node("CollisionShape3D") as CollisionShape3D
	var tab := sw.get_node("Model").call("part", "SlideTab") as MeshInstance3D
	for k in AvSwitch.INPUTS:
		sw.select(k)
		await _wait(2)
		var shown := tab.global_transform * tab.get_aabb()
		var box := shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
		_ok((box.position - shown.position).length() < 0.0001 and (box.size - shown.size).length() < 0.0001,
			"position %d: the slide's box is the tab, no margin" % (k + 1), "box %s / tab %s" % [box, shown])
		var mid := shown.get_center()
		var space := sw.get_world_3d().direct_space_state
		var t := InteractionResolver.resolve_desktop(space, mid + Vector3.BACK * 0.6, mid - Vector3.BACK * 0.05, _grabber)
		_ok(t != null and (t.action_node == slider or t.highlight_node == slider),
			"position %d: the desktop ray from the front takes the tab" % (k + 1),
			"took %s" % (str(t.action_node.name) if t != null and t.action_node != null else "-"))
	var gap := (tab.global_transform * tab.get_aabb()).get_center() + Vector3.LEFT * 0.016
	var t2 := InteractionResolver.resolve_desktop(sw.get_world_3d().direct_space_state, gap + Vector3.BACK * 0.6,
		gap - Vector3.BACK * 0.05, _grabber)
	_ok(t2 == null or t2.action_node != slider, "a ray into the slot beside the tab does not take it")


func _debug() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var tv: RetroTV = r["tv"]
	var deck: VCRPlayer = r["deck"]
	_ok(_row(sw, "Input 1", "Yellow (video) jack").begins_with("lead seated, from %s" % deck.name),
		"Input 1's yellow jack row names the VCR", _row(sw, "Input 1", "Yellow (video) jack"))
	_ok(_row(sw, "Input 1", "Source").begins_with(String(deck.name)), "its Source row is the VCR")
	_eq(_row(sw, "Input 1", "Label"), "selected", "its Label row")
	_eq(_row(sw, "Input 2", "Source"), "nothing", "Input 2's Source row")
	_eq(_row(sw, "Input 3", "Sending"), "no (switched off)", "the Genesis's Sending row")
	_ok(_row(sw, "Output", "VideoOut ->").contains(String(tv.name)), "the Output section names the set",
		_row(sw, "Output", "VideoOut ->"))
	_ok(_row(sw, "Output", "Resolves to").begins_with(String(deck.name)), "and what it resolves to")
	_eq(_row(sw, "Slide", "Position"), "1", "the slide row")
	_eq(_row(sw, "Netplay", "Role"), "not in a session", "the netplay row")
	_eq(_row(sw, "Netplay", "Last slide move"), "local", "a hand's move is local")
	_eq(_row(sw, "Power", "Power simulation"), "off" if not AppPrefs.power_simulation else "on", "the simulation row")
	sw.select(2)
	await _wait(3)
	_eq(_row(sw, "Slide", "Position"), "3", "the slide moved: its row follows")
	_eq(_row(sw, "Input 1", "Label"), "lit", "and Input 1's label row")
	await _unplug(_in(sw, 1)[0].seated_plug() as RcaPlug)
	_eq(_row(sw, "Input 1", "Yellow (video) jack"), "empty", "the yellow lead out: its row says empty")
	_ok(sw.describe_wiring().contains("selected 3"), "the log line says the same", sw.describe_wiring())


func _panel() -> void:
	var r := await _room()
	var sw: AvSwitch = r["sw"]
	var panel := sw.get_node("AvSwitchOptionsPanel") as AvSwitchOptionsPanel
	panel.show_for(sw, null)
	await _wait(10)
	var ui := panel.ui_2d()
	_ok(ui != null, "the menu has its 2D page")
	if ui == null:
		return
	ui.input_selected.emit(3)
	await _wait(3)
	_eq(sw.selected, 3, "INPUT 4 in the menu puts the slide on 4")
	_ok(is_equal_approx((sw.get_node("Selector") as VRSlider).value, 1.0), "the slide itself moved")
	ui.show_debug_tab()
	await _wait(2)
	_ok(ui.is_debug_tab_shown(), "the Debug tab can be shown")
	_ok(ui.find_child("PowerRows", true, false) != null, "the menu has the Power rows")
	panel.hide_panel()
