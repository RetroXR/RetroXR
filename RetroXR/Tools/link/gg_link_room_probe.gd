## A Gear-to-Gear Cable between two Game Gears, seated the way a hand seats it.
##
##     "$godot" --headless --path RetroXR res://Tools/link/gg_link_room_probe.tscn [-- --roms=Z:/roms]
##
## gg_link_probe joins two cores with LinkConnect and drives real games over the
## result. This drives the path a PLAYER uses: two Game Gears built by the room,
## a lead from the spawn catalog, plugs pushed into each unit's EXT socket. The
## lead goes in before either unit is switched on, and Mean Bean Machine's boot
## -- it polls the far end from the moment it starts -- is the traffic that
## proves the seated lead carries something. It needs the retroXR build of
## genesis_plus_gx; the stock core never puts anything on the wire.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CORE := "genesis_plus_gx"
const GAME := "Dr. Robotnik's Mean Bean Machine (USA, Europe).gg"

var _pass := 0
var _fail := 0
var _systems: Array[RetroSystem] = []
var _lead: Node3D = null


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[gg-room] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	var rom := _find_rom()
	if rom.is_empty():
		print("[gg-room] SKIP  no %s; pass --roms=<library>" % GAME)
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[gg-room] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	for i in range(2):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "gamegear"
		sys.core_name = CORE
		sys.name = "GG%d" % i
		add_child(sys)
		sys.global_position = Vector3(0.3 * i, 1.0, 0.0)
		_systems.append(sys)
	await _settle(4)

	var ports: Array[LinkPort] = []
	for sys in _systems:
		ports.append(sys.find_child("LinkPort", true, false) as LinkPort)
	_ok("the Game Gear carries an EXT socket", ports.count(null) == 0)
	if ports.count(null) > 0:
		return _finish()

	# +Z out of the shell, the convention every socket follows: from the body's
	# centre the socket sits on the side its +Z points to.
	var port := ports[0]
	var out := port.global_transform.basis.z
	var from_centre := port.global_position - _systems[0].global_position
	_ok("the socket faces out of the shell", out.dot(from_centre) > 0.0,
		"basis.z %s, offset %s" % [out, from_centre])

	var entry := {}
	for item in SpawnCatalog.items_for("gamegear"):
		if str(item.get("label", "")) == "Gear-to-Gear Cable":
			entry = item
	_ok("the spawn menu offers a Gear-to-Gear Cable", not entry.is_empty())
	var scene := ScenePersistence.LEAD_SCENES.get(str(entry.get("spawn", ""))) as PackedScene
	_ok("and it names a lead scene", scene != null, str(entry.get("spawn", "")))
	if scene == null:
		return _finish()
	_lead = scene.instantiate() as Node3D
	add_child(_lead)
	_lead.global_position = Vector3(0.15, 1.0, 0.1)
	await _settle(2)

	(ports[0] as XRToolsSnapZone).pick_up_object(_lead.get_node("PlugA0"))
	await _settle(6)
	(ports[1] as XRToolsSnapZone).pick_up_object(_lead.get_node("PlugB0"))
	await _settle(6)

	for i in range(2):
		_systems[i].rom_path = rom
		_systems[i].power_on()
	await _settle(30)
	for i in range(2):
		_ok("unit %d powered on" % i, _systems[i].is_powered_on)
	await _settle(300)
	_eq("both plugs in leaves unit 0 on a bus of two", _peers(0), 2)
	_eq("and unit 1 with it", _peers(1), 2)
	var got0 := _traffic(0)
	var got1 := _traffic(1)
	print("[gg-room] delivered %d / %d" % [got0, got1])
	_ok("the boot traffic crosses the seated lead both ways", got0 > 0 and got1 > 0,
		"delivered %d / %d" % [got0, got1])

	await _pull(_lead.get_node("PlugB0") as RcaPlug)
	_eq("pulling one end drops unit 0", _peers(0), 0)
	_eq("and unit 1", _peers(1), 0)

	(ports[1] as XRToolsSnapZone).pick_up_object(_lead.get_node("PlugB0"))
	await _settle(60)
	_eq("pushing it back in joins them again", _peers(0), 2)
	_finish()


func _find_rom() -> String:
	var roots: PackedStringArray = [RomLibrary.default_roms_root()]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roms="):
			roots.append(arg.substr(7))
	for root in roots:
		var path := root.path_join("gamegear").path_join(GAME)
		if FileAccess.file_exists(path):
			return path
	return ""


func _libretro(index: int) -> Libretro:
	return _systems[index].find_child("Libretro", true, false) as Libretro


func _peers(index: int) -> int:
	var lib := _libretro(index)
	return lib.LinkPeerCount(0) if lib != null else -1


func _traffic(index: int) -> int:
	var lib := _libretro(index)
	return lib.LinkTraffic(0) if lib != null else -1


## Pull a plug out and get it clear; a dropped plug falls straight back in, so
## every socket is shut for the move (the GB room probe's helper, for the same reason).
func _pull(plug: RcaPlug) -> void:
	var shut: Array[RcaPort] = []
	for node in get_tree().get_nodes_in_group(RcaPort.GROUP):
		var p := node as RcaPort
		if p != null and p.enabled:
			p.enabled = false
			shut.append(p)
	var seated := plug.seated_port()
	if seated != null:
		seated.drop_object()
	await _settle(4)
	plug.freeze = true
	plug.global_position += Vector3(0.0, 3.0, 0.0)
	PhysicsServer3D.body_set_state(plug.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM, plug.global_transform)
	await _settle(6)
	for p in shut:
		if is_instance_valid(p):
			p.enabled = true
	plug.freeze = false
	await _settle(6)


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gg-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[gg-room] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	if is_instance_valid(_lead):
		_lead.queue_free()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.power_off()
	await _settle(90)
	print("[gg-room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
