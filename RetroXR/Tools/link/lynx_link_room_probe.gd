## ComLynx between Lynxes, seated the way a hand seats it.
##
##     "$godot" --headless --path RetroXR res://Tools/link/lynx_link_room_probe.tscn [-- --roms=Z:/roms]
##
## lynx_link_probe joins cores with LinkConnect and drives real games. This drives
## the path a PLAYER uses: Lynxes built by the room, a ComLynx Cable from the spawn
## catalog, plugs pushed into each unit's socket, then a second lead from the first
## one's junction to a third unit, as the real cable chains. The units are switched
## on one after another, as people do -- identical units powered on in the same
## instant collide on every byte (docs/dev/lynx-link.md). Slime World counts the
## units on the wire from its title screen, which is the traffic that proves the
## seated leads carry something. It needs the retroXR build of mednafen_lynx and
## the Lynx BIOS.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CORE := "mednafen_lynx"
const GAME := "Todd's Adventures in Slime World (USA, Europe).lnx"

var _pass := 0
var _fail := 0
var _systems: Array[RetroSystem] = []
var _leads: Array[Node3D] = []


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[lynx-room] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	var rom := _find_rom()
	if rom.is_empty():
		print("[lynx-room] SKIP  no %s; pass --roms=<library>" % GAME)
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[lynx-room] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	# A table to lie on: with nothing under them the units fall and stack.
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.1, 4.0)
	shape.shape = box
	table.add_child(shape)
	var top := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = box.size
	top.mesh = slab
	table.add_child(top)
	add_child(table)
	table.global_position = Vector3(5.4, 0.9, 0.0)
	for i in range(3):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "atarilynx"
		sys.core_name = CORE
		sys.name = "Lynx%d" % i
		add_child(sys)
		sys.global_position = Vector3(5.0 + 0.4 * i, 1.0, 0.0)
		_systems.append(sys)
	await _settle(4)

	var ports: Array[LinkPort] = []
	for sys in _systems:
		ports.append(sys.find_child("LinkPort", true, false) as LinkPort)
	_ok("the Lynx model carries a ComLynx socket", ports.count(null) == 0)
	if ports.count(null) > 0:
		return _finish()

	# +Z out of the shell, the convention every socket follows.
	var out := ports[0].global_transform.basis.z
	var from_centre := ports[0].global_position - _systems[0].global_position
	_ok("the socket faces out of the shell", out.dot(from_centre) > 0.0,
		"basis.z %s, offset %s" % [out, from_centre])

	var entry := {}
	for item in SpawnCatalog.items_for("atarilynx"):
		if str(item.get("label", "")) == "ComLynx Cable":
			entry = item
	_ok("the spawn menu offers a ComLynx Cable", not entry.is_empty())
	var scene := ScenePersistence.LEAD_SCENES.get(str(entry.get("spawn", ""))) as PackedScene
	_ok("and it names a lead scene", scene != null, str(entry.get("spawn", "")))
	if scene == null:
		return _finish()
	for i in range(2):
		var lead := scene.instantiate() as Node3D
		add_child(lead)
		lead.global_position = Vector3(5.2 + 0.4 * i, 1.0, 0.15)
		_leads.append(lead)
	await _settle(2)

	# Lead 0 joins units 0 and 1.
	(ports[0] as XRToolsSnapZone).pick_up_object(_leads[0].get_node("PlugA0"))
	await _settle(6)
	(ports[1] as XRToolsSnapZone).pick_up_object(_leads[0].get_node("PlugB0"))
	await _settle(6)

	for i in range(2):
		_systems[i].rom_path = rom
		_systems[i].power_on()
		await _settle(23)   # never in the same instant
	await _settle(30)
	for i in range(2):
		_ok("unit %d powered on" % i, _systems[i].is_powered_on)
	await _emulated(0, 900)
	print("[lynx-room] frames %d / %d" % [_libretro(0).GetFrameCount(), _libretro(1).GetFrameCount()])
	_eq("one lead leaves unit 0 on a bus of two", _peers(0), 2)
	_eq("and unit 1 with it", _peers(1), 2)
	var sent0 := _sent(0)
	var sent1 := _sent(1)
	_ok("Slime World talks across the seated lead both ways", sent0 > 0 and sent1 > 0,
		"sent %d / %d" % [sent0, sent1])
	_ok("and each unit hears more than itself", _traffic(0) > 0 and _traffic(1) > 0,
		"heard %d / %d" % [_traffic(0), _traffic(1)])
	if OS.get_cmdline_user_args().has("--shot"):
		await _photograph()

	# Lead 1 from lead 0's junction to unit 2, switched on third.
	var junction := _leads[0].get_node("Junction/LinkPort") as XRToolsSnapZone
	junction.pick_up_object(_leads[1].get_node("PlugA0"))
	await _settle(6)
	(ports[2] as XRToolsSnapZone).pick_up_object(_leads[1].get_node("PlugB0"))
	await _settle(6)
	_systems[2].rom_path = rom
	_systems[2].power_on()
	await _settle(30)
	await _emulated(2, 700)
	for i in range(3):
		_eq("the chained lead puts unit %d on a bus of three" % i, _peers(i), 3)
	var before := _sent(2)
	await _emulated(2, 150)
	_ok("and the third unit talks on it", _sent(2) > before and before > 0,
		"sent %d then %d" % [before, _sent(2)])

	await _pull(_leads[1].get_node("PlugB0") as RcaPlug)
	_eq("pulling the third unit's plug drops it", _peers(2), 0)
	_eq("and leaves the first two on a bus of two", _peers(0), 2)

	await _pull(_leads[0].get_node("PlugB0") as RcaPlug)
	_eq("pulling unit 1's plug drops unit 0", _peers(0), 0)
	_eq("and unit 1", _peers(1), 0)

	(ports[1] as XRToolsSnapZone).pick_up_object(_leads[0].get_node("PlugB0"))
	await _settle(60)
	_eq("pushing it back in joins them again", _peers(0), 2)
	_finish()


func _find_rom() -> String:
	var roots: PackedStringArray = [RomLibrary.default_roms_root()]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roms="):
			roots.append(arg.substr(7))
	for root in roots:
		var path := root.path_join("atarilynx").path_join(GAME)
		if FileAccess.file_exists(path):
			return path
	return ""


func _libretro(index: int) -> Libretro:
	return _systems[index].find_child("Libretro", true, false) as Libretro


func _peers(index: int) -> int:
	var lib := _libretro(index)
	return lib.LinkPeerCount(0) if lib != null else -1


func _sent(index: int) -> int:
	var lib := _libretro(index)
	return lib.LinkSent(0) if lib != null else -1


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


## --shot, windowed: the two cabled units from the front and from behind, to
## probe_out/lynx/room/. Headless renders a blank image of the right size.
func _photograph() -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-50, 30, 0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	cam.current = true
	var mid := (_systems[0].global_position + _systems[1].global_position) * 0.5
	var dir := ProjectSettings.globalize_path("res://probe_out/lynx/room")
	DirAccess.make_dir_recursive_absolute(dir)
	var views := {"above": Vector3(0.05, 0.7, 0.12), "behind": Vector3(0.0, 0.3, -0.55),
		"socket": Vector3(-0.2, 0.12, 0.06)}
	for view in views:
		var at: Vector3 = views[view]
		var target := mid if view != "socket" else ports_of(0).global_position
		cam.global_position = target + at
		cam.look_at(target, Vector3.UP)
		await _settle(12)
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, view])
		print("[lynx-room] shot %s/%s.png" % [dir, view])
	cam.queue_free()
	light.queue_free()


func ports_of(index: int) -> Node3D:
	return _systems[index].find_child("LinkPort", true, false) as Node3D


## Wait for machine `index` to run `n` emulated frames (a room's SubViewports make
## host frames and emulated ones differ).
func _emulated(index: int, n: int) -> void:
	var lib := _libretro(index)
	if lib == null:
		return
	var target := lib.GetFrameCount() + n
	var guard := n * 40 + 200
	while lib.GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[lynx-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[lynx-room] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	for lead in _leads:
		if is_instance_valid(lead):
			lead.queue_free()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.power_off()
	await _settle(90)
	print("[lynx-room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
