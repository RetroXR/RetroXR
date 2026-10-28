extends "res://Tests/test_suite.gd"

## The mains region: MainsRegions' table, the WallOutlet and PowerStrip that follow
## it, the AppPrefs setting, and a save restored under another region.
##
## A test region with two-slot receptacles stands in for a foreign plate, so the
## cases hold whatever regions ship: a grounded US plug has nowhere to go in it,
## a two-prong one still does.

const TEST_REGION := "zz_two_slot"
const SPECS := preload("res://Tools/gen/mains_specs.gd")


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
	_test_fit_matrix()
	await _test_plug_meshes()
	_test_locale()
	await _test_outlet()
	await _test_outlet_switch_live()
	await _test_strip()
	await _test_adapter()
	_test_prefs()

	MainsRegions.extra = extra_before
	AppPrefs.mains_region = region_before
	if prefs_existed:
		var f := FileAccess.open(AppPrefs.PREFS_PATH, FileAccess.WRITE)
		f.store_buffer(prefs_before)
		f.close()
	elif FileAccess.file_exists(AppPrefs.PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AppPrefs.PREFS_PATH))

	_finish()


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


## The fit table and the geometry agree: every plug in every socket, by the pins
## and faces in Tools/gen/mains_specs.gd, goes in exactly when Connectors says so.
func _test_fit_matrix() -> void:
	for socket: String in SPECS.SOCKETS:
		for plug: String in SPECS.PLUGS:
			var fits: bool = SPECS.fits(plug, socket)
			var said := Connectors.groups_of(plug).has(socket)
			_ok(fits == said, "fit/%s %s %s (geometry: %s)" % [plug,
				"in" if said else "not in", socket, SPECS.why_not(plug, socket)
				if not fits else "goes in"])
	for id: String in MainsRegions.REGIONS:
		var spec: Dictionary = MainsRegions.REGIONS[id]
		for socket: Dictionary in spec["sockets"]:
			_ok(SPECS.SOCKETS.has(str(socket["connector"])),
				"fit/%s %s has a spec" % [id, socket["name"]])
		_ok(SPECS.SOCKETS.has(str(spec["strip"]["socket"])), "fit/%s strip has a spec" % id)
		# A region whose own plugs fit none of its sockets would ship a dead wall.
		var own := 0
		for token: String in spec.get("cords", []):
			if token == "power_strip":
				continue
			var plug := _cord_plug(token)
			for socket: Dictionary in spec["sockets"]:
				if Connectors.groups_of(plug).has(str(socket["connector"])):
					own += 1
		_ok(own > 0, "fit/%s's cords go into its plate" % id)
	for token: String in MainsRegions.CORDS:
		_ok(ScenePersistence.LEAD_SCENES.has(token), "fit/%s spawns and restores" % token)


## Every cord's wall plug as baked, seated through its own grab point in a socket
## it fits: whatever of it stands in front of its face lands inside the socket's
## holes. Catches a mesh mirrored the wrong way, a pin on the wrong side, or a
## spec edited without rebaking.
func _test_plug_meshes() -> void:
	var room := Node3D.new()
	add_child(room)
	for token: String in MainsRegions.CORDS:
		var cord := (ScenePersistence.LEAD_SCENES[token] as PackedScene).instantiate() as PowerCord
		room.add_child(cord)
		var plug := cord.wall_plug as PowerPlug
		var socket_id := ""
		for s: String in SPECS.SOCKETS:
			if Connectors.groups_of(plug.connector).has(s):
				socket_id = s
				break
		var port := preload("res://Scenes/Objects/cables/power_port.tscn").instantiate() as PowerPort
		port.connector = socket_id
		room.add_child(port)
		await get_tree().process_frame
		var seat := port.global_transform.affine_inverse() * port.snap_pose_for(plug)
		var tip := plug.get_node("PlugTip") as MeshInstance3D
		var stray := 0
		var checked := 0
		var holes: Array = SPECS.SOCKETS[socket_id]["holes"]
		for v: Vector3 in tip.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if v.z <= 0.0005:
				continue
			var at := seat * (tip.transform * v)
			checked += 1
			if not _in_holes(Vector2(at.x, at.y) * 1000.0, holes):
				stray += 1
		_ok(checked > 0 and stray == 0, "mesh/%s's pins land in %s's holes (%d of %d out)"
			% [token, socket_id, stray, checked])
		port.queue_free()
		cord.queue_free()
	await get_tree().process_frame
	room.queue_free()
	await get_tree().process_frame


## Within 0.1 mm of one of the holes' parts.
func _in_holes(p: Vector2, holes: Array) -> bool:
	for hole: Array in holes:
		for part: Dictionary in hole:
			var poly: PackedVector2Array
			if str(part["shape"]) == "round":
				poly = SPECS._circle(part["at"], float(part["d"]) * 0.5 + 0.1)
			else:
				poly = SPECS._rect(part["at"], part["size"] + Vector2(0.2, 0.2),
					float(part.get("angle", 0.0)))
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
	return false


## The connector at a cord's wall end, from its scene.
func _cord_plug(token: String) -> String:
	var cord := (ScenePersistence.LEAD_SCENES[token] as PackedScene).instantiate()
	var plug := str(cord.get_node("WallPlug").get("connector"))
	cord.free()
	return plug


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


## The region changed with plugs in the wall, as a player does it: physics running
## between the seating, the change and what follows. A plug that no longer fits
## comes out, and nothing is left saying it is held by a receptacle that has been
## freed -- the pointer asks every plug it passes over who holds it, and casting
## the freed one threw "Trying to cast a freed object" in the resolver.
func _test_outlet_switch_live() -> void:
	var room := Node3D.new()
	add_child(room)
	var plate := preload("res://Scenes/Objects/room/wall_outlet.tscn").instantiate() as WallOutlet
	room.add_child(plate)
	plate.position = Vector3(0, 1, 0)
	var grounded := preload("res://Scenes/Objects/cables/power_cord.tscn").instantiate() as PowerCord
	room.add_child(grounded)
	var two_prong := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn") 		.instantiate() as PowerCord
	room.add_child(two_prong)
	await get_tree().process_frame
	# One plug, in the top receptacle: the empty one below it is watching its
	# grab sphere, and the plug is in it.
	plate.ports()[0].pick_up_object(grounded.wall_plug)
	two_prong.wall_plug.global_position = plate.global_position + Vector3(0.5, 0, 0.3)
	for i in 10:
		await get_tree().physics_frame
	plate.set_region("eu")
	for i in 10:
		await get_tree().physics_frame
	await get_tree().process_frame
	for plug: PowerPlug in [grounded.wall_plug as PowerPlug, two_prong.wall_plug as PowerPlug]:
		_ok(not plug.is_picked_up(),
			"live switch/%s is not left held, by a freed receptacle or any" % plug.connector)
		_ok(PowerCord.socket_holding(plug) == null, "live switch/%s does not fit a Schuko plate: it is out" % plug.connector)
		_ok(InteractionResolver._snap_zone_holding(plug) == null,
			"live switch/the pointer asking who holds %s gets nothing, and no error" % plug.connector)
	plate.set_region(MainsRegions.DEFAULT)
	for i in 5:
		await get_tree().physics_frame
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
	_ok(strip.get_node_or_null("Body/RegionBody") == null,
		"strip/a test region's strip keeps the US body")

	# A UK strip is the four-gang sold there: its own body, as long as the table
	# says, four UK sockets on it, and the cord out of its end.
	strip.set_region("uk")
	var uk: Dictionary = MainsRegions.REGIONS["uk"]["strip"]
	var body := strip.get_node_or_null("Body/RegionBody") as MeshInstance3D
	_ok(body != null and body.mesh != null, "strip/a UK strip wears its own body")
	_ok(not (strip.get_node("Body/Shell") as Node3D).visible, "strip/and not the US one")
	if body != null and body.mesh != null:
		_ok(absf(body.mesh.get_aabb().size.x - (uk["size"] as Vector3).x * 0.001) < 0.001,
			"strip/its body is the table's length")
	var live := 0
	for s in strip.sockets():
		if s.enabled:
			live += 1
			_eq(s.snap_require, "bs_1363_plug", "strip/a UK socket takes a UK plug")
			_ok(s.global_basis.z.dot(Vector3.UP) > 0.99, "strip/%s faces up" % s.name)
	_eq(live, MainsRegions.strip_outlets("uk"), "strip/a UK strip has its four")
	var attach := strip.get_node("Body/Shell/PowerStrip/CordAnchor") as Node3D
	var along := attach.global_position.x - (strip.get_node("Body") as Node3D).global_position.x
	_ok(absf(along - (uk["size"] as Vector3).x * 0.0005) < 0.001,
		"strip/its cord leaves the end of the UK body")
	# China's: a two-slot and a three-slot opening at each of four positions,
	# more sockets than the scene has.
	strip.set_region("cn")
	live = 0
	for s in strip.sockets():
		live += 1 if s.enabled else 0
	_eq(live, 8, "strip/a Chinese strip opens both halves of four five-hole positions")
	strip.set_region(MainsRegions.DEFAULT)
	live = 0
	for s in strip.sockets():
		live += 1 if s.enabled else 0
	_eq(live, 6, "strip/a US strip all six again")
	_eq(strip.sockets().size(), 6, "strip/and the sockets it made are gone")
	_ok((strip.get_node("Body/Shell") as Node3D).visible, "strip/the US body is back")
	await _clear(room)


## The travel adapter: its prongs the region's, any wall plug in its socket but
## itself, out of a wall the region change leaves it unable to use, and back
## from a save.
func _test_adapter() -> void:
	var room := Node3D.new()
	add_child(room)
	var plate := preload("res://Scenes/Objects/room/wall_outlet.tscn").instantiate() as WallOutlet
	room.add_child(plate)
	var scene := preload("res://Scenes/Objects/appliances/travel_adapter.tscn")
	var adapter := scene.instantiate() as TravelAdapter
	room.add_child(adapter)
	adapter.add_to_group("spawned")
	var uk := preload("res://Scenes/Objects/cables/bs_1363_cord.tscn").instantiate() as PowerCord
	room.add_child(uk)
	await get_tree().process_frame

	_ok(adapter.wall_plug.is_in_group("nema_5_15_plug"), "adapter/US prongs in a US room")
	var top := plate.get_node("TopPort") as PowerPort
	_ok(top.can_preview(adapter.wall_plug), "adapter/it goes into the US wall")
	_ok(not top.can_preview(uk.wall_plug), "adapter/a UK plug does not")
	for plug: String in SPECS.PLUGS:
		_ok(MainsRegions.fits(plug, adapter.socket.snap_require),
			"adapter/a %s goes into its socket" % plug)
	_ok(adapter.socket.can_preview(uk.wall_plug), "adapter/the UK plug goes into it")
	_ok(not adapter.socket.can_preview(adapter.wall_plug), "adapter/but not itself")
	var tip := adapter.wall_plug.get_node("PlugTip") as MeshInstance3D
	var back := adapter.wall_plug.to_local(adapter.socket.global_position)
	_ok(absf(back.z - tip.mesh.get_aabb().position.z) < 0.0005,
		"adapter/its socket is on the block's back")

	top.pick_up_object(adapter.wall_plug)
	adapter.socket.pick_up_object(uk.wall_plug)
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(uk.wall_plug) == adapter.socket,
		"adapter/the UK plug seats in it")
	_ok(uk.seating()[0].get("device") == adapter, "adapter/and names the adapter as its device")
	var sp := ScenePersistence.new("arcade")
	var entry := sp.serialize_node(adapter, 0, {adapter: 0})
	_eq(str(entry.get("kind", "")), "travel_adapter", "adapter/serializes by kind")

	# A region whose wall the US prongs do not fit: the prongs change, it comes
	# out of the wall, and the plug in it stays.
	TravelAdapter.apply_region(get_tree(), "uk")
	WallOutlet.apply_region(get_tree(), "uk")
	await get_tree().process_frame
	var british := adapter.wall_plug.is_in_group("bs_1363_plug")
	_ok(british and not adapter.wall_plug.is_in_group("nema_5_15_plug"),
		"adapter/UK prongs in a UK room")
	_ok(PowerCord.socket_holding(adapter.wall_plug) == null,
		"adapter/out of a socket that no longer takes it")
	_ok(PowerCord.socket_holding(uk.wall_plug) == adapter.socket,
		"adapter/and the plug in it stays")
	TravelAdapter.apply_region(get_tree(), MainsRegions.DEFAULT)
	WallOutlet.apply_region(get_tree(), MainsRegions.DEFAULT)
	await get_tree().process_frame

	adapter.drop_and_free()
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(uk.wall_plug) == null, "adapter/binning it lets go of the plug")
	var spawned := sp.instantiate_objects(room, [entry])
	for i in 3:
		await get_tree().process_frame
	_ok(spawned.get(0) is TravelAdapter, "adapter/is rebuilt from its entry")
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
	AppPrefs.load_prefs()
	_eq(AppPrefs.mains_region, TEST_REGION, "prefs/and loaded back")

