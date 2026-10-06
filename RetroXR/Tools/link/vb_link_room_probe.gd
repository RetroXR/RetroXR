## A link cable between two Virtual Boys, seated the way a hand seats it.
##
##     "$godot" --headless --path RetroXR res://Tools/link/vb_link_room_probe.tscn \
##         [-- --roms=<library> | --rom=<path>]
##
## vb_link_game_probe joins two cores with LinkConnect and drives real games over
## the result. This drives the path a PLAYER uses: two Virtual Boys built by the
## room, a lead from the spawn catalog, plugs pushed into each unit's EXT. socket.
## The lead goes in before either unit is switched on, and Mario's Tennis with
## M.K.'s multiplayer patch is the traffic: START on ONE unit's title screen
## calls the other, which answers, and both open the two-player menu. It needs
## the retroXR build of mednafen_vb; the stock core has no port at all.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CORE := "mednafen_vb"
const GAME := "Mario's Tennis (Japan, USA) (Multiplayer Hack v1).vb"
const START := 1 << 3

var _pass := 0
var _fail := 0
var _systems: Array[RetroSystem] = []
var _lead: Node3D = null


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[vb-room] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	var rom := _find_rom()
	if rom.is_empty():
		print("[vb-room] SKIP  no %s; pass --roms=<library> or --rom=<path>" % GAME)
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[vb-room] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	for i in range(2):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "virtualboy"
		sys.core_name = CORE
		sys.name = "VB%d" % i
		add_child(sys)
		sys.global_position = Vector3(0.4 * i, 1.0, 0.0)
		_systems.append(sys)
	await _settle(4)

	var ports: Array[LinkPort] = []
	for sys in _systems:
		ports.append(sys.find_child("LinkPort", true, false) as LinkPort)
	_ok("the Virtual Boy model carries an EXT. socket", ports.count(null) == 0)
	if ports.count(null) > 0:
		return _finish()

	# +Z out of the shell, the convention every socket follows. The socket is on
	# the underside of the visor, so it is measured from the visor, not from the
	# foot of the stand the model's origin sits at.
	var port := ports[0]
	var visor := _systems[0].find_child("Visor", true, false) as Node3D
	var out := port.global_transform.basis.z
	var from_centre := port.global_position - visor.global_position
	_ok("the socket faces out of the visor", out.dot(from_centre) > 0.0,
		"basis.z %s, offset %s" % [out, from_centre])
	_ok("and straight down", out.y < -0.99, "basis.z %s" % out)

	var entry := {}
	for item in SpawnCatalog.items_for("virtualboy"):
		if str(item.get("label", "")) == "Link Cable":
			entry = item
	_ok("the spawn menu offers a Link Cable", not entry.is_empty())
	var scene := ScenePersistence.LEAD_SCENES.get(str(entry.get("spawn", ""))) as PackedScene
	_ok("and it names a lead scene", scene != null, str(entry.get("spawn", "")))
	if scene == null:
		return _finish()
	_lead = scene.instantiate() as Node3D
	add_child(_lead)
	_lead.global_position = Vector3(0.2, 1.0, 0.1)
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
	await _emulated(150)
	_eq("both plugs in leaves unit 0 on a bus of two", _peers(0), 2)
	_eq("and unit 1 with it", _peers(1), 2)

	# The warning, the logo, the automatic-pause question and the intro, on both.
	for press in range(4):
		for i in range(2):
			await _press(i, START)
		await _emulated(140)
	var before0 := _traffic(0)
	var before1 := _traffic(1)
	# The title screen, on ONE unit: two units pressed on the same frame both
	# call, neither is listening, and each opens the one-player menu.
	await _press(0, START)
	await _emulated(260)
	var got0 := _traffic(0) - before0
	var got1 := _traffic(1) - before1
	print("[vb-room] delivered %d / %d after the title press" % [got0, got1])
	var a := _libretro(1).GetVideoImage()
	if a != null and not a.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out/vb"))
		a.save_png(ProjectSettings.globalize_path("res://probe_out/vb/room_unit1.png"))
	# A hundred: the call, the answer and the menu traffic that follows, not the
	# COMCNT state each end announces when the lead goes in.
	_ok("the title-screen call crosses the seated lead both ways", got0 >= 100 and got1 >= 100,
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
		if arg.begins_with("--rom="):
			return arg.substr(6) if FileAccess.file_exists(arg.substr(6)) else ""
		if arg.begins_with("--roms="):
			roots.append(arg.substr(7))
	for root in roots:
		var path := root.path_join("virtualboy").path_join(GAME)
		if FileAccess.file_exists(path):
			return path
	return ""


## A press long enough for the game to see it, with whatever sends the unit's
## idle pad every frame held still so it cannot wipe the press out.
func _press(index: int, mask: int) -> void:
	var lib := _libretro(index)
	var input := _input_node(_systems[index])
	if input != null:
		input.set_process(false)
	lib.SetJoypadState(0, mask, 0, 0, 0, 0)
	await _emulated(6)
	lib.SetJoypadState(0, 0, 0, 0, 0, 0)
	await _emulated(4)
	if input != null:
		input.set_process(true)


func _input_node(node: Node) -> Node:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("handheld_input.gd"):
			return child
		var found := _input_node(child)
		if found != null:
			return found
	return null


## Frames the cores have run, not frames the room has drawn: headless, with the
## physics of a room to step, the two can be far apart.
func _emulated(n: int) -> void:
	var lib := _libretro(0)
	var target: int = lib.GetFrameCount() + n
	var guard := n * 60 + 200
	while lib.GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


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
		print("[vb-room] PASS  %s" % name)
	else:
		_fail += 1
		print("[vb-room] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	if is_instance_valid(_lead):
		_lead.queue_free()
	for sys in _systems:
		if is_instance_valid(sys):
			sys.power_off()
	await _settle(90)
	print("[vb-room] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
