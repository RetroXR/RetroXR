## A real netplay SESSION over a Saturn Link Cable: two players, two Saturns each.
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/saturn_session_probe.tscn -- \
##       [--mode=rollback|lockstep] [--rom=<.chd>] [--frames=N]
##
## A probe, not a test: real mednafen_saturn cores (RetroXR's fork past v2, in
## the player's core root), the BIOS and Steeldom. One process, never two at
## once: it listens on a fixed loopback port.
##
## saturn_rollback_probe proves the ENGINE with the inputs fed by hand. This is
## everything around it, the way players reach it: two NetworkManagers over real
## loopback ENet, each peer with its own room -- two Saturns built from
## system.tscn and the Saturn Link Cable pushed into their sockets -- and the
## host starting a session on one of them. The session decides the strategy,
## pins the options, forms the group, joins the cable on its scheduled frame,
## and carries every press between the peers. The host's player has unit 0, the
## client's unit 1; each presses only their own, through Steeldom's walk into
## LINK MODE.
##
## What must hold: the session runs in the mode asked for, every core runs to
## the end, the far player's presses really are rolled back (rollback mode), the
## cable carries a conversation, NO desync is reported, and the two peers' CRCs
## of both machines agree at every checkpoint -- which is the session's own
## cross-peer check, read directly.
extends Node

const NM_SCRIPT := preload("res://Scripts/Net/network_manager.gd")
const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CORE := "mednafen_saturn"
const PORT := 42979
const B_START := 1 << 3
const B_DOWN := 1 << 5
const B_RIGHT := 1 << 7

var _mode := "rollback"
var _rom := "Z:/roms/saturn/Koutetsu Reiiki - Steeldom (Japan) (2M).chd"
var _end := 4500
var _fail := 0
var _desyncs := 0
## [branch][machine] -> {frame: crc}
var _crcs := [[{}, {}], [{}, {}]]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.substr(7)
		elif arg.begins_with("--rom="):
			_rom = arg.substr(6)
		elif arg.begins_with("--frames="):
			_end = maxi(300, int(arg.substr(9)))
	get_tree().create_timer(1500.0).timeout.connect(func() -> void:
		print("[satnp] TIMEOUT")
		get_tree().quit(1))
	await _run()


## saturn_link_probe's Steeldom walk (emulated seconds x 60, 12-frame presses):
## both off the title, unit 0 picks LINK MODE, then unit 1, whose RIGHT presses
## change player 2's pilot on both screens; then both keep nudging.
func _press(machine: int, frame: int) -> int:
	var presses: Array = [
		[0, 2316, B_START], [1, 2316, B_START], [0, 2778, B_START], [1, 2778, B_START],
		[0, 2952, B_DOWN], [0, 3012, B_START], [1, 3126, B_DOWN], [1, 3186, B_START],
		[1, 3474, B_RIGHT], [1, 3588, B_RIGHT],
	]
	var t := 3720
	while t < 20000:
		presses.append([1, t, B_RIGHT])
		presses.append([0, t + 97, B_RIGHT])
		t += 211
	for p: Array in presses:
		if int(p[0]) == machine and frame >= int(p[1]) and frame < int(p[1]) + 12:
			return int(p[2])
	return 0


func _run() -> void:
	if not FileAccess.file_exists(_rom):
		print("[satnp] SKIP no ROM at %s" % _rom)
		get_tree().quit(0)
		return
	var host := _branch("Host", Vector3(5.0, 0.0, 0.0))
	var client := _branch("Client", Vector3(-5.0, 0.0, 0.0))
	await _settle(4)
	var hnm: Node = host["nm"]
	var cnm: Node = client["nm"]
	hnm.host_game(PORT)
	cnm.join_game("::1", PORT)
	if not await _until(func() -> bool: return hnm.peers.size() == 2 and cnm.peers.size() == 2, 600):
		return _finish("the two peers never connected")
	await _settle(30)
	# Leads are seated once the players share a room: joining replaces a
	# client's own spawned objects with the host's.
	for b: Dictionary in [host, client]:
		await _cable(b)
	await _settle(30)
	var client_id := -1
	for id: int in hnm.peers:
		if id != 1:
			client_id = id
	for b: Dictionary in [host, client]:
		var np: NetplaySession = b["nm"]._netplay
		np.systems_override = {0: b["units"][0], 1: b["units"][1]}
		np.system_override = b["units"][0]
		np.desync_detected.connect(func(_peer: int, frame: int) -> void:
			_desyncs += 1
			print("[satnp] DESYNC reported by %s @frame %d" % [b["name"], frame]))
	var md5 := FileAccess.get_md5(_rom)
	var ok: bool = hnm.netplay_start_host(host["units"][0], CORE, md5,
		{0: 1, 4: client_id}, 3, 1 if _mode == "rollback" else 0)
	_check("the host starts a session on the cabled pair", ok)
	var hnp: NetplaySession = hnm._netplay
	var cnp: NetplaySession = cnm._netplay
	if not await _until(func() -> bool: return hnp.is_running() and cnp.is_running(), 30000):
		return _finish("the session never ran on both peers")
	_check("both peers run it as a group of two", hnp.group_size() == 2 and cnp.group_size() == 2)
	_check("in %s" % _mode, hnp._rollback == (_mode == "rollback") and cnp._rollback == (_mode == "rollback"))
	if _mode == "rollback":
		_check("the cabled units roll back together", hnp._group_rollback and cnp._group_rollback)
	for bi in range(2):
		var b: Dictionary = [host, client][bi]
		for mi in range(2):
			var lib: Object = b["units"][mi].get_libretro_node()
			var store: Dictionary = _crcs[bi][mi]
			lib.netplay_crc.connect(func(frame: int, crc: int) -> void: store[frame] = crc)

	var last := -1
	var still := 0
	while true:
		await get_tree().process_frame
		_drive(host, 0)
		_drive(client, 1)
		var f := _min_frame([host, client])
		if f >= _end or not (hnp.is_running() and cnp.is_running()):
			break
		still = still + 1 if f == last else 0
		last = f
		if still > 3000:
			for b: Dictionary in [host, client]:
				for unit: RetroSystem in b["units"]:
					var lib: Object = unit.get_libretro_node()
					print("[satnp] wedge %s %s: frame %d identity %s stats %s" % [b["name"], unit.name,
						lib.GetFrameCount(), lib.GetCoreIdentity().get("library_name", "-"),
						lib.GetNetplayRollbackStats()])
			return _finish("WEDGED at frame %d" % f)
	_check("the session is still running at frame %d" % _end, hnp.is_running() and cnp.is_running())
	for _i in range(60):
		_drive(host, 0)
		_drive(client, 1)
		await get_tree().process_frame

	var rollbacks := 0
	for b: Dictionary in [host, client]:
		for unit: RetroSystem in b["units"]:
			var lib: Object = unit.get_libretro_node()
			rollbacks += int(lib.GetNetplayRollbackCount())
			print("[satnp] %s %s: frame %d, rollbacks %d, sent %d, heard %d, peers %d" % [
				b["name"], unit.name, lib.GetFrameCount(), lib.GetNetplayRollbackCount(),
				lib.LinkSent(0), lib.LinkTraffic(0), lib.LinkPeerCount(0)])
			_check("%s %s talks on the cable" % [b["name"], unit.name], lib.LinkSent(0) > 100)
	if _mode == "rollback":
		_check("the far players' presses were rolled back", rollbacks >= 4, "%d rewinds" % rollbacks)
	_check("no desync was reported", _desyncs == 0, "%d" % _desyncs)
	var same := 0
	var differ := 0
	for mi in range(2):
		for frame: int in _crcs[0][mi]:
			if _crcs[1][mi].has(frame):
				if _crcs[0][mi][frame] == _crcs[1][mi][frame]:
					same += 1
				else:
					differ += 1
	_check("both peers' machines agree at every checkpoint", differ == 0 and same > 2 * (_end / 60) - 6,
		"%d equal, %d differ" % [same, differ])
	_shot(host, client)
	hnm.netplay_stop()
	await _settle(10)
	_finish("")


## Press this player's unit through the session's input seam, as a controller
## does: under rollback the seam hands a local port back to the core directly.
func _drive(b: Dictionary, machine: int) -> void:
	var unit: RetroSystem = b["units"][machine]
	var np: NetplaySession = b["nm"]._netplay
	var lib: Object = unit.get_libretro_node()
	var mask := _press(machine, int(lib.GetFrameCount()))
	if not np.route(unit, 0, {"btn": mask}):
		lib.SetJoypadState(0, mask, 0, 0, 0, 0)


func _min_frame(branches: Array) -> int:
	var out := 1 << 30
	for b: Dictionary in branches:
		for unit: RetroSystem in b["units"]:
			out = mini(out, int(unit.get_libretro_node().GetFrameCount()))
	return out


## One player's world: a NetworkManager under its own SceneMultiplayer, a table,
## two Saturns on it.
func _branch(bname: String, at: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = bname
	add_child(root)
	var api := SceneMultiplayer.new()
	get_tree().set_multiplayer(api, root.get_path())
	var nm := NM_SCRIPT.new()
	nm.name = "NetworkManager"
	nm.world_root = root
	nm.pose_source = func() -> PackedFloat32Array: return PackedFloat32Array()
	root.add_child(nm)
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.1, 3.0)
	shape.shape = box
	table.add_child(shape)
	root.add_child(table)
	table.global_position = at + Vector3(0.2, 0.9, 0.0)
	var units: Array[RetroSystem] = []
	for i in range(2):
		var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
		sys.systemid = "saturn"
		sys.core_name = CORE
		sys.name = "Saturn%d" % i
		sys.rom_path = _rom
		nm.add_child(sys)
		sys.global_position = at + Vector3(0.4 * i, 1.0, 0.0)
		# A console needs a display or the session will not start its core
		# (_has_display). The real set is a SubViewport, which hangs a headless
		# run, so a stand-in fills channel 0's `tv` the way surround_probe does.
		if sys._channels.is_empty():
			sys._channels.append(RetroSystem.VideoChannel.new())
		sys._channels[0].tv = Node.new()
		units.append(sys)
	return {"name": bname, "nm": nm, "root": root, "units": units}


## The Saturn Link Cable, pushed into both units' sockets.
func _cable(b: Dictionary) -> void:
	var scene := ScenePersistence.LEAD_SCENES.get("saturn_link_cable") as PackedScene
	if scene == null:
		_check("ScenePersistence knows saturn_link_cable", false)
		return
	var lead := scene.instantiate() as Node3D
	# In the game the lead asks the NetworkManager autoload; here each player's
	# room has its own manager, and the lead must ask that one.
	lead.set("netplay_manager_override", b["nm"])
	(b["root"] as Node).add_child(lead)
	var units: Array = b["units"]
	lead.global_position = (units[0] as Node3D).global_position + Vector3(0.2, 0.0, 0.15)
	await _settle(2)
	var ports: Array = []
	for unit: RetroSystem in units:
		ports.append(unit.find_child("SaturnLinkPort", true, false))
	(ports[0] as XRToolsSnapZone).pick_up_object(lead.get_node("PlugA0"))
	await _settle(6)
	(ports[1] as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB0"))
	await _settle(6)
	print("[satnp] debug %s: lead sees %d machines, ports %s, plugs in groups %s" % [b["name"],
		(lead.call("linked_machines") as Array).size(), str(ports),
		str(lead.get_node("PlugA0").get_groups())])
	var bus: Array = (units[0] as RetroSystem).net_link_buses()
	_check("%s: the lead joins the two units" % b["name"], bus.size() == 1 and (bus[0] as Array).size() == 2)


func _shot(host: Dictionary, client: Dictionary) -> void:
	var imgs: Array[Image] = []
	for b: Dictionary in [host, client]:
		for unit: RetroSystem in b["units"]:
			var img: Image = unit.get_libretro_node().GetVideoImage()
			if img == null or img.is_empty():
				return
			imgs.append(img)
	var fmt := imgs[0].get_format()
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var out := Image.create_empty(w * 4 + 24, h, false, fmt)
	out.fill(Color(0.1, 0.1, 0.12))
	for i in range(4):
		imgs[i].convert(fmt)
		out.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(i * (w + 8), 0))
	out.resize(out.get_width() * 2, out.get_height() * 2, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out/saturn/session"))
	out.save_png("res://probe_out/saturn/session/%s.png" % _mode)


func _check(what: String, ok: bool, detail := "") -> void:
	print("[satnp] %s  %s%s" % ["ok  " if ok else "FAIL", what, "" if detail.is_empty() else " (" + detail + ")"])
	if not ok:
		_fail += 1


func _finish(why: String) -> void:
	if not why.is_empty():
		_check(why, false)
	print("[satnp] %s (%s)" % ["PASS" if _fail == 0 else "FAIL %d" % _fail, _mode])
	get_tree().quit(0 if _fail == 0 else 1)


func _until(cond: Callable, frames: int) -> bool:
	for _i in range(frames):
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame
