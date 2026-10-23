extends Node

## The mains region: MainsRegions' table, the WallOutlet and PowerStrip that follow
## it, the AppPrefs setting, and a save restored under another region.
##
## A test region with two-slot receptacles stands in for a foreign plate, so the
## cases hold whatever regions ship: a grounded US plug has nowhere to go in it,
## a two-prong one still does.

const TEST_REGION := "zz_two_slot"

var _failed := 0
var _ran := 0


func _ready() -> void:
	var prefs_before := FileAccess.get_file_as_bytes(AppPrefs.PREFS_PATH)
	var prefs_existed := FileAccess.file_exists(AppPrefs.PREFS_PATH)
	var region_before := AppPrefs.mains_region
	var extra_before := MainsRegions.extra.duplicate(true)
	AppPrefs.mains_region = MainsRegions.DEFAULT
	MainsRegions.extra[TEST_REGION] = {
		"label": "Test", "types": "two-slot",
		"mesh": "res://Scenes/Objects/room/wall_outlet_duplex.res",
		"sockets": [
			{"name": "TopPort", "position": Vector3(0, 0.02, 0.008),
				"connector": "nema_1_15_plug"},
			{"name": "BottomPort", "position": Vector3(0, -0.02, 0.008),
				"connector": "nema_1_15_plug"},
		],
		"cords": ["nema_1_15_to_c7_cord"],
		"strip": {"socket": "nema_1_15_plug", "plug": "nema_1_15_plug"},
	}

	_test_table()
	_test_locale()
	await _test_outlet()
	await _test_strip()
	_test_prefs()

	MainsRegions.extra = extra_before
	AppPrefs.mains_region = region_before
	if prefs_existed:
		var f := FileAccess.open(AppPrefs.PREFS_PATH, FileAccess.WRITE)
		f.store_buffer(prefs_before)
		f.close()
	elif FileAccess.file_exists(AppPrefs.PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppPrefs.PREFS_PATH))

	print("[test] %d cases, %s" % [_ran,
		"PASS" if _failed == 0 else "%d FAILURE(S)" % _failed])
	get_tree().quit(0 if _failed == 0 else 1)


## Every shipped region is whole: a plate that loads, the two named receptacles,
## connectors spelled as connectors, and a strip.
func _test_table() -> void:
	for id: String in MainsRegions.REGIONS:
		var spec: Dictionary = MainsRegions.REGIONS[id]
		_ok(load(str(spec.get("mesh", ""))) is Mesh, "table/%s has a plate mesh" % id)
		var names := []
		for socket: Dictionary in spec.get("sockets", []):
			names.append(str(socket.get("name", "")))
			_eq(Connectors.problem(str(socket.get("connector", ""))), "",
				"table/%s %s names a connector" % [id, socket.get("name", "")])
		_eq(names, ["TopPort", "BottomPort"], "table/%s keeps the saved socket names" % id)
		_ok(not (spec.get("cords", []) as Array).is_empty(), "table/%s lists its cords" % id)
		var strip: Dictionary = spec.get("strip", {})
		_eq(Connectors.problem(str(strip.get("socket", ""))), "", "table/%s strip socket" % id)
		_eq(Connectors.problem(str(strip.get("plug", ""))), "", "table/%s strip plug" % id)
		_ok(not MainsRegions.label_of(id).is_empty(), "table/%s has a label" % id)
	_eq(MainsRegions.resolve("no_such_region"), MainsRegions.DEFAULT,
		"table/an unknown region resolves to the default")
	_ok(MainsRegions.ids().has(TEST_REGION), "table/a mod's region is listed")


func _test_locale() -> void:
	_eq(MainsRegions.for_locale("en_US"), "na", "locale/en_US is North America")
	_eq(MainsRegions.for_locale("xx_ZZ"), MainsRegions.DEFAULT,
		"locale/an unknown locale is the default")
	_eq(MainsRegions.for_locale(""), MainsRegions.DEFAULT, "locale/an empty one too")


func _test_outlet() -> void:
	var room := Node3D.new()
	add_child(room)
	var plate := preload("res://Scenes/Objects/room/wall_outlet.tscn").instantiate() as WallOutlet
	plate.name = "WallOutlet"
	room.add_child(plate)
	var two_prong := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(two_prong)
	var grounded := preload("res://Scenes/Objects/cables/power_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(grounded)
	await get_tree().process_frame

	_eq(plate.region, MainsRegions.DEFAULT, "outlet/built as the setting's region")
	var ports := plate.ports()
	_eq(ports.size(), 2, "outlet/two receptacles")
	_eq(ports[0].name, &"TopPort", "outlet/top first")
	_eq(ports[0].snap_require, "nema_5_15_plug", "outlet/a US plate takes a 5-15P")
	_ok((plate.get_node("Plate") as MeshInstance3D).mesh != null, "outlet/the plate shows")
	_ok(ports[0].can_preview(grounded.wall_plug), "outlet/a 5-15P goes into a US plate")

	ports[0].pick_up_object(grounded.wall_plug)
	ports[1].pick_up_object(two_prong.wall_plug)
	await get_tree().process_frame

	plate.set_region(TEST_REGION)
	await get_tree().process_frame
	ports = plate.ports()
	_eq(ports.size(), 2, "switch/still two receptacles")
	_eq(ports[0].snap_require, "nema_1_15_plug", "switch/the plate is the new region's")
	_ok(PowerCord.socket_holding(grounded.wall_plug) == null,
		"switch/a grounded plug falls out of a two-slot plate")
	_ok(PowerCord.socket_holding(two_prong.wall_plug) == plate.get_node("BottomPort"),
		"switch/a two-prong plug stays in its receptacle")
	_ok(not ports[0].can_preview(grounded.wall_plug),
		"switch/and a grounded plug is refused from then on")
	_ok(ports[0].can_preview(two_prong.wall_plug), "switch/a two-prong plug still fits")

	WallOutlet.apply_region(get_tree(), MainsRegions.DEFAULT)
	await get_tree().process_frame
	_eq(plate.region, MainsRegions.DEFAULT, "switch/apply_region reaches every plate")
	_eq(plate.ports()[0].snap_require, "nema_5_15_plug", "switch/and back again")

	var pinned := preload("res://Scenes/Objects/room/wall_outlet.tscn").instantiate() as WallOutlet
	pinned.region_override = TEST_REGION
	room.add_child(pinned)
	await get_tree().process_frame
	_eq(pinned.region, TEST_REGION, "override/a pinned plate ignores the setting")
	WallOutlet.apply_region(get_tree(), MainsRegions.DEFAULT)
	_eq(pinned.region, TEST_REGION, "override/and a change of it")

	# A save from the US plate, restored after the region changed: the socket of
	# that name is there, the plug just no longer fits it.
	var top := plate.get_node("TopPort") as PowerPort
	top.pick_up_object(grounded.wall_plug)
	await get_tree().process_frame
	var seats := grounded.seating()
	for seat: Dictionary in seats:
		var p := (seat["plug"] as Node3D).global_position
		var r := (seat["plug"] as Node3D).global_rotation_degrees
		seat["position"] = [p.x, p.y, p.z]
		seat["rotation"] = [r.x, r.y, r.z]
	top.drop_object()
	plate.set_region(TEST_REGION)
	grounded._apply_seating(seats)
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(grounded.wall_plug) == null,
		"restore/a saved plug that no longer fits comes back loose")
	plate.set_region(MainsRegions.DEFAULT)
	grounded._apply_seating(seats)
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(grounded.wall_plug) == plate.get_node("TopPort"),
		"restore/and one that fits is seated")

	await _clear(room)


func _test_strip() -> void:
	var room := Node3D.new()
	add_child(room)
	var plate := preload("res://Scenes/Objects/room/wall_outlet.tscn").instantiate() as WallOutlet
	room.add_child(plate)
	var strip := preload("res://Scenes/Objects/appliances/power_strip.tscn") \
		.instantiate() as PowerStrip
	room.add_child(strip)
	var grounded := preload("res://Scenes/Objects/cables/power_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(grounded)
	await get_tree().process_frame

	_eq(strip.sockets()[0].snap_require, "nema_5_15_plug", "strip/a US strip takes a 5-15P")
	_ok(strip.wall_plug.is_in_group("nema_5_15_plug"), "strip/and wears one")
	(plate.get_node("TopPort") as PowerPort).pick_up_object(strip.wall_plug)
	strip.sockets()[0].pick_up_object(grounded.wall_plug)
	await get_tree().process_frame

	PowerStrip.apply_region(get_tree(), TEST_REGION)
	WallOutlet.apply_region(get_tree(), TEST_REGION)
	await get_tree().process_frame
	_eq(strip.sockets()[5].snap_require, "nema_1_15_plug", "strip/every socket follows the region")
	_ok(strip.wall_plug.is_in_group("nema_1_15_plug"), "strip/its plug becomes the region's")
	_ok(not strip.wall_plug.is_in_group("nema_5_15_plug") or \
			Connectors.groups_of("nema_1_15_plug").has("nema_5_15_plug"),
		"strip/and leaves the old plug's groups")
	_ok(PowerCord.socket_holding(grounded.wall_plug) == null,
		"strip/a grounded plug falls out of its two-slot sockets")
	_ok(PowerCord.socket_holding(strip.wall_plug) == plate.get_node("TopPort"),
		"strip/its own plug stays in the wall that still takes it")

	PowerStrip.apply_region(get_tree(), MainsRegions.DEFAULT)
	_ok(strip.wall_plug.is_in_group("nema_5_15_plug") \
			and not strip.wall_plug.is_in_group("nema_1_15_plug"),
		"strip/and back to a grounded plug")
	await _clear(room)


## Let every plug go and wait out the drop's deferred work before freeing the
## room: a socket freed while it holds a plug drops it into a body already queued.
func _clear(room: Node) -> void:
	for node in get_tree().get_nodes_in_group(PowerPort.GROUP):
		var port := node as PowerPort
		if room.is_ancestor_of(port) and port.picked_up_object != null:
			port.drop_object()
	await get_tree().physics_frame
	await get_tree().process_frame
	room.queue_free()
	await get_tree().process_frame


func _test_prefs() -> void:
	var heard := []
	var listen := func(region: String) -> void: heard.append(region)
	AppPrefs.mains_region_changed.connect(listen)
	AppPrefs.set_mains_region(TEST_REGION)
	AppPrefs.set_mains_region(TEST_REGION)
	AppPrefs.mains_region_changed.disconnect(listen)
	_eq(heard, [TEST_REGION], "prefs/a change is announced once")
	var saved := JsonStore.read_dict(AppPrefs.PREFS_PATH, "test")
	_eq(str(saved.get("mains_region", "")), TEST_REGION, "prefs/and saved")
	AppPrefs.mains_region = ""
	AppPrefs._load_prefs()
	_eq(AppPrefs.mains_region, TEST_REGION, "prefs/and loaded back")


func _ok(ok: bool, label: String) -> void:
	_ran += 1
	if ok:
		print("[test] ok   %s" % label)
	else:
		_failed += 1
		print("[test] FAIL %s" % label)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	_ok(actual == expected, "%s (%s == %s)" % [label, actual, expected])
