## Plays a real four-player game through the Four Score on a real fceumm: pads in
## the unit's sockets, each pressed through its OWN delivery path on a script of
## frames, and the game's screen saved where the script asks, so what the GAME
## made of the players is read off its own screens.
##
##     "$godot" --headless --path RetroXR res://Tools/input/four_score_game_probe.tscn -- \
##         --root=<scratch libretro root holding cores/fceumm_libretro.dll> \
##         --rom="<a Four Score game>.nes" --leg=4p --out=<dir> \
##         --steps="300-306:1:start,420-426:1:down" --shots=280,400,520
##
## ONE LEG PER PROCESS:
##   --leg=4p    the Four Score at 4, a pad in each of its four sockets
##   --leg=2p    the same at 2 (the unit's own control: no signature)
##   --leg=none  two pads straight in the NES's ports, nothing else
##   --leg=sat   the NES Satellite: receiver in the ports, transmitter 1.4 m away,
##               switched on, a pad in each socket
##   --leg=satoff the same never switched on (the control: no input reaches it)
##
## --steps: comma-separated `from-to:player:buttons`, buttons joined by `+` from
## a b select start up down left right; a player's buttons are held over the
## frames from..to (the core's own frames) and released after.
## --shots: the core frames to save as <out>/<leg>_<frame>.png.
##
## Bomberman II (USA) is what this was first run against (docs/dev/four-player-
## adapters.md has the script and what each leg showed).
extends Node

const BITS := {"b": 0, "select": 2, "start": 3, "up": 4, "down": 5, "left": 6,
	"right": 7, "a": 8}

var root_dir := ""
var rom_path := ""
var leg := "4p"
var out_dir := ""
var _steps: Array = []        # [{from, to, player, mask}]
var _shots: Array[int] = []
var _pads: Array = []
var _lib: Object = null
var _sent: Array[int] = [-1, -1, -1, -1]
var _tx: NesSatellite = null


func _ready() -> void:
	var steps_arg := ""
	var shots_arg := ""
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a.begins_with("--steps="):
			steps_arg = a.trim_prefix("--steps=")
		elif a.begins_with("--shots="):
			shots_arg = a.trim_prefix("--shots=")
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[fourgame] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/fceumm_libretro.dll")) \
			or not FileAccess.file_exists(rom_path) or out_dir.is_empty():
		print("[fourgame] need --root=, --rom= and --out=")
		get_tree().quit(1)
		return
	for s in steps_arg.split(",", false):
		var parts := s.split(":")
		var span := parts[0].split("-")
		var mask := 0
		for b in parts[2].split("+", false):
			mask |= 1 << int(BITS.get(b, 0))
		_steps.append({"from": int(span[0]), "to": int(span[1]), "player": int(parts[1]) - 1, "mask": mask})
	for f in shots_arg.split(",", false):
		_shots.append(int(f))
	await _run()


func _spawn(path: String, at: Vector3) -> Node3D:
	var obj := (load(path) as PackedScene).instantiate() as Node3D
	add_child(obj)
	obj.global_position = at
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	return obj


func _run() -> void:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "nes"
	sys.core_directory = root_dir
	sys.core_name = "fceumm"
	add_child(sys)
	sys.freeze = true
	for i in 10:
		await get_tree().physics_frame
	for i in 4:
		_pads.append(_spawn("res://Scenes/Objects/controllers/nes/nes_controller.tscn", Vector3(-0.3 + 0.2 * i, 0, 0.6)))
	for i in 6:
		await get_tree().physics_frame
	if leg == "none":
		for i in 2:
			sys.restore_controller_plug(i, _pads[i].call("get_plug"))
	elif leg == "sat" or leg == "satoff":
		# The Satellite: its receiver in the ports, the transmitter 1.4 m out with
		# its lens toward the console, pads in its four sockets. "satoff" never
		# presses its power switch: the control.
		var rx := _spawn("res://Scenes/Objects/controllers/nes/nes_satellite_receiver.tscn", Vector3(0.4, 0, 0.4)) as NesSatelliteReceiver
		_tx = _spawn("res://Scenes/Objects/controllers/nes/nes_satellite.tscn", Vector3(0, 0, 1.4)) as NesSatellite
		await get_tree().physics_frame
		await get_tree().physics_frame
		sys.restore_controller_plug(0, rx)
		for i in 4:
			_tx.restore_socket(i, _pads[i])
		if leg == "sat":
			_tx.press_power()
	else:
		var fs := _spawn("res://Scenes/Objects/controllers/nes/nes_four_score.tscn", Vector3(0, 0, 0.3)) as NesFourScore
		await get_tree().physics_frame
		await get_tree().physics_frame
		if leg == "2p":
			fs.set_mode(FourPlayerAdapter.MODE_2P)
		sys.restore_controller_plug(0, fs.get_plug())
		for i in 4:
			fs.restore_socket(i, _pads[i])
	for i in 12:
		await get_tree().physics_frame
	for p: Variant in _pads:
		(p as Node).set_physics_process(false)
		(p as Node).set_process(false)
	if _tx != null:
		print("[fourgame] satellite: powered %s, link %s" % [_tx.is_powered(), _tx.link_up()])
	print("[fourgame] %s: players on libretro ports %s" % [leg, str(_pads.map(
		func(p: Variant) -> int: return int((p as Node).call("get_port_index"))))])

	sys.rom_path = rom_path
	sys.toggle_power()
	_lib = sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 60000
	while (_lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if (_lib.GetCoreIdentity() as Dictionary).is_empty():
		print("[fourgame] the core never came up")
		get_tree().quit(1)
		return
	var last := 0
	for f: int in _shots:
		last = maxi(last, f)
	for st: Dictionary in _steps:
		last = maxi(last, int(st["to"]) + 1)
	var shot_i := 0
	var sorted_shots := _shots.duplicate()
	sorted_shots.sort()
	var told := false
	while true:
		var frame := int(_lib.GetFrameCount())
		if not told and frame > 60:
			told = true
			var ids: Array = []
			for e: Dictionary in sys.controller_ports().controller_info:
				ids.append("%d:%d" % [int(e.get("port", -1)), int(e.get("current_id", -1))])
			print("[fourgame] the core was told %s" % ", ".join(ids))
		_drive(frame)
		while shot_i < sorted_shots.size() and frame >= sorted_shots[shot_i]:
			_shot(sorted_shots[shot_i])
			shot_i += 1
		if frame > last:
			break
		await get_tree().process_frame
	sys.toggle_power()
	for i in 60:
		await get_tree().process_frame
	print("[fourgame] done")
	get_tree().quit(0)


## Each player's buttons for this frame, sent only on a change, through the pad.
func _drive(frame: int) -> void:
	for player in 4:
		var mask := 0
		for st: Dictionary in _steps:
			if int(st["player"]) == player and frame >= int(st["from"]) and frame <= int(st["to"]):
				mask |= int(st["mask"])
		if mask == _sent[player]:
			continue
		_sent[player] = mask
		var pad: Node = _pads[player]
		if int(pad.call("get_port_index")) < 0:
			continue
		pad.call("_deliver_joypad", {"btn": mask, "alx": 0, "aly": 0, "arx": 0, "ary": 0})


func _shot(frame: int) -> void:
	var img: Image = _lib.call("GetVideoImage")
	if img == null or img.is_empty():
		print("[fourgame] frame %d: no image" % frame)
		return
	var path := out_dir.path_join("%s_%05d.png" % [leg, frame])
	img.save_png(path)
	print("[fourgame] frame %d -> %s" % [frame, path])
