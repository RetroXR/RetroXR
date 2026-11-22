extends "res://Tests/test_suite.gd"

## ExtensionCable: power through it, its length, a region change, a save, and the
## Power tab row (its mark, its hold-to-pick length, MAKE DEFAULT).

const OUTLET := preload("res://Scenes/Objects/room/wall_outlet.tscn")
const EXT := preload("res://Scenes/Objects/appliances/extension_cable.tscn")
const STRIP := preload("res://Scenes/Objects/appliances/power_strip.tscn")
const C7_CORD := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn")

const KEY := "power|extension_cable"

var _only := ""
var _room: Node3D = null


func _ready() -> void:
	suite_tag = "extension"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[extension] TIMEOUT")
		get_tree().quit(1))
	var region_before := AppPrefs.mains_region
	var sim_before := AppPrefs.power_simulation
	var default_before := AppPrefs.spawn_default(KEY)
	AppPrefs.mains_region = MainsRegions.DEFAULT
	AppPrefs.power_simulation = true
	if _want("heads"):
		await _test_heads()
	if _want("graph"):
		await _test_graph()
	if _want("length"):
		await _test_length()
	if _want("region"):
		await _test_region()
	if _want("save"):
		await _test_save()
	if _want("token"):
		_test_token()
	if _want("menu"):
		await _test_menu()
	AppPrefs.set_spawn_default(KEY, default_before)
	AppPrefs.mains_region = region_before
	AppPrefs.power_simulation = sim_before
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _new_room() -> WallOutlet:
	_room = Node3D.new()
	# A save names the outlet by path, so the room is the same one each time.
	_room.name = "ExtRoom"
	add_child(_room)
	var plate := OUTLET.instantiate() as WallOutlet
	plate.name = "WallOutlet"
	plate.position = Vector3(0, 0.3, -1)
	_room.add_child(plate)
	return plate


func _ext(metres := ExtensionCable.SHIPPED_LENGTH) -> ExtensionCable:
	var ext := EXT.instantiate() as ExtensionCable
	ext.cord_length = metres
	_room.add_child(ext)
	return ext


func _clear() -> void:
	if is_instance_valid(_room):
		for n in _room.get_children():
			if n.has_method("drop_and_free"):
				n.call("drop_and_free")
		_room.queue_free()
	_room = null
	await _wait(4)


func _test_heads() -> void:
	for id: String in MainsRegions.REGIONS:
		var head := ExtensionCable.head_of(id)
		var strip: Dictionary = MainsRegions.REGIONS[id]["strip"]
		var mesh: Mesh = load(str(head["mesh"])) if ResourceLoader.exists(str(head["mesh"])) else null
		_ok(mesh != null and mesh.has_meta("head_length"), "heads/%s has a baked head" % id)
		_ok(MainsRegions.fits(str(strip["plug"]), str(head["connector"])),
			"heads/%s: its head takes its own region's plug" % id)
		_ok(not ExtensionCable.outlet_type(id).is_empty(), "heads/%s names its outlet" % id)
	# Inline: the socket faces away from the cord, on the head's end face.
	_new_room()
	var ext := _ext()
	await _wait(2)
	var s := ext.sockets()[0]
	var out := s.global_basis.z
	var anchor := ext.get_node("Body/CordAnchor") as Node3D
	var away := (s.global_position - anchor.global_position).normalized()
	_ok(out.dot(away) > 0.99, "heads/the socket faces away from the cord, inline with it",
		"out %s away %s" % [out, away])
	_ok(absf(out.y) < 0.01, "heads/and lies level")
	await _clear()


func _test_graph() -> void:
	var plate := _new_room()
	var ext := _ext()
	var cord := C7_CORD.instantiate() as PowerCord
	_room.add_child(cord)
	var strip := STRIP.instantiate() as PowerStrip
	_room.add_child(strip)
	await _wait(3)
	var top := plate.get_node("TopPort") as PowerPort
	var socket := ext.sockets()[0]
	_eq(ext.sockets().size(), 1, "graph/one socket on the head")
	socket.pick_up_object(cord.wall_plug)
	await _wait(2)
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/a cord in a loose extension is dead")
	top.pick_up_object(ext.wall_plug)
	await _wait(2)
	_ok(MainsPower.socket_live(socket), "graph/an extension in the wall makes its head live")
	_ok(MainsPower.plug_live(cord.appliance_plug), "graph/and the cord in it")
	top.drop_object()
	await _wait(2)
	_ok(not MainsPower.plug_live(cord.appliance_plug), "graph/pulled from the wall, dead again")
	# Wall -> strip -> extension -> cord.
	top.pick_up_object(strip.wall_plug)
	strip.sockets()[0].pick_up_object(ext.wall_plug)
	await _wait(2)
	_ok(MainsPower.plug_live(cord.appliance_plug), "graph/through a strip, then the extension")
	strip.sockets()[0].drop_object()
	await _wait(2)
	_eq(PowerInput.describe_wall_plug(cord.wall_plug).contains("extension cable"), true,
		"graph/a cord in it says it is in an extension cable")
	await _clear()


func _test_length() -> void:
	_new_room()
	var made := {}
	for row: Array in ExtensionCable.SPAWN_LENGTHS:
		made[row[0]] = _ext(float(row[0]))
	await _wait(3)
	for m: float in made:
		var ext: ExtensionCable = made[m]
		var got := float(ext.rope.segment_count) * ext.rope.segment_length
		_ok(absf(got - m) < 0.01, "length/a %s m cable's cord is %s m" % [m, m], "got %.3f" % got)
		_ok(ext.rope.segment_count <= 150, "length/never more segments than the scene authors")
	await _clear()


func _test_region() -> void:
	var plate := _new_room()
	var ext := _ext()
	var cord := C7_CORD.instantiate() as PowerCord
	_room.add_child(cord)
	await _wait(3)
	(plate.get_node("TopPort") as PowerPort).pick_up_object(ext.wall_plug)
	ext.sockets()[0].pick_up_object(cord.wall_plug)
	await _wait(2)
	MainsSplice.change_region(get_tree(), "uk")
	await _wait(3)
	_eq(ext.region, "uk", "region/the cable follows the room to the UK")
	_eq(ext.wall_plug.connector, "bs_1363_plug", "region/with a UK plug")
	_eq(ext.sockets()[0].connector, "bs_1363_plug", "region/and a UK socket on its head")
	_ok(PowerCord.socket_holding(ext.wall_plug) == plate.get_node("TopPort"),
		"region/its own plug stays in the wall")
	var holder := PowerCord.socket_holding(cord.wall_plug)
	_ok(holder != null, "region/the US cord in its head is kept plugged in (an adapter)")
	_ok(MainsPower.plug_live(cord.appliance_plug), "region/and still live")
	MainsSplice.change_region(get_tree(), MainsRegions.DEFAULT)
	await _wait(3)
	await _clear()


func _test_save() -> void:
	var plate := _new_room()
	var ext := _ext(1.5)
	await _wait(3)
	(plate.get_node("BottomPort") as PowerPort).pick_up_object(ext.wall_plug)
	await _wait(2)
	var sp := ScenePersistence.new("arcade")
	var entry := sp.serialize_node(ext, 0, {ext: 0})
	_eq(str(entry.get("kind", "")), "extension_cable", "save/saved as an extension cable")
	_eq(float(entry.get("cord_length", 0.0)), 1.5, "save/with its length")
	_eq(ScenePersistence._entry_validation_error(entry, {0: true}), "", "save/the entry validates")
	await _clear()
	var room_plate := _new_room()
	await _wait(3)
	var spawned := sp.instantiate_objects(_room, [entry])
	await _wait(12)
	var back := spawned.get(0) as ExtensionCable
	_ok(back != null, "save/it came back")
	if back != null:
		_ok(absf(float(back.rope.segment_count) * back.rope.segment_length - 1.5) < 0.01,
			"save/still 1.5 m")
		_ok(PowerCord.socket_holding(back.wall_plug) == room_plate.get_node("BottomPort"),
			"save/and back in the wall")
	await _clear()


func _test_token() -> void:
	var plain := SpawnCatalog.parse_token("extension_cable")
	_eq(plain["kind"], SpawnCatalog.TokenKind.EXTENSION_CABLE, "token/the plain token")
	_eq(float(plain["length"]), ExtensionCable.SHIPPED_LENGTH, "token/is 3 m")
	_eq(float(SpawnCatalog.parse_token("extension_cable:4.5")["length"]), 4.5, "token/a length")
	_ok(ScenePersistence.LEAD_SCENES.has("extension_cable"), "token/its scene is a lead")


func _row(view: SpawnMenuSpawnView) -> Button:
	for c in view._power_vbox.get_children():
		var btn := c as Button
		if btn != null and btn.text.contains("Extension Cable"):
			return btn
	return null


func _hold(btn: Button, seconds: float) -> void:
	var hold := btn.get_node("HoldPress") as HoldPress
	btn.button_down.emit()
	hold.advance(seconds)
	btn.pressed.emit()
	btn.button_up.emit()


func _test_menu() -> void:
	AppPrefs.set_spawn_default(KEY, "")
	var holder := Control.new()
	add_child(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	# The Power tab alone; _build would scan the library for every other tab.
	var tabs := TabContainer.new()
	holder.add_child(tabs)
	view._power_vbox = view._add_spawn_tab(tabs, "Power", view._power_items())
	await _wait(2)
	var sent: Array[String] = []
	view.spawn_requested.connect(func(token: String) -> void: sent.append(token))
	var btn := _row(view)
	_ok(btn != null, "menu/the Power tab has an Extension Cable row")
	if btn == null:
		holder.queue_free()
		return
	var mark := btn.get_node_or_null("RegionMark") as Label
	_ok(mark != null and mark.text.contains("Type B") and mark.text.ends_with("3 m"),
		"menu/its right side shows the outlet and the length",
		mark.text if mark != null else "no mark")
	_hold(btn, 0.2)
	_eq(sent, ["extension_cable:3.0"] as Array[String], "menu/pressed, a 3 m cable")
	sent.clear()
	_hold(btn, HoldPress.HOLD_SECONDS + 0.1)
	var panel := view._spawn_options_panel
	_ok(panel != null and sent.is_empty(), "menu/held, the length picker opens")
	if panel == null:
		holder.queue_free()
		return
	var lengths := panel.find_child("Lengths", true, false)
	_eq(lengths.get_child_count() if lengths != null else 0, ExtensionCable.SPAWN_LENGTHS.size(),
		"menu/a button per length")
	(lengths.get_child(3) as Button).pressed.emit()
	(panel.find_child("MakeDefault", true, false) as Button).pressed.emit()
	_eq(AppPrefs.spawn_default(KEY), "6.0", "menu/MAKE DEFAULT keeps 6 m")
	(panel.find_child("SpawnVariant", true, false) as Button).pressed.emit()
	_eq(sent, ["extension_cable:6.0"] as Array[String], "menu/SPAWN asks for 6 m")
	await _wait(2)
	btn = _row(view)
	mark = btn.get_node_or_null("RegionMark") as Label if btn != null else null
	_ok(mark != null and mark.text.ends_with("6 m"), "menu/the row now shows 6 m",
		mark.text if mark != null else "no mark")
	AppPrefs.mains_region = "uk"
	view.refresh_power_tab()
	await _wait(1)
	btn = _row(view)
	mark = btn.get_node_or_null("RegionMark") as Label if btn != null else null
	_ok(mark != null and mark.text.contains("Type G"), "menu/in a UK room it shows Type G",
		mark.text if mark != null else "no mark")
	AppPrefs.mains_region = MainsRegions.DEFAULT
	holder.queue_free()
	await _wait(1)
