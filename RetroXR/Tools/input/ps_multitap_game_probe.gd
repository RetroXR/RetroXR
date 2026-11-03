## Plays a real multitap game through the PlayStation Multitap on a real
## pcsx_rearmed: pads in the tap's sockets, each pressed through its OWN delivery
## path on a script of frames, and the game's screen saved where the script asks,
## so what the GAME made of the players is read off its own screens. The core's
## multitap option is the room's (ForcedCoreOptions.ps_multitap), not set here.
##
##     "$godot" --headless --path RetroXR res://Tools/input/ps_multitap_game_probe.tscn -- \
##         --root=<scratch libretro root holding cores/pcsx_rearmed_libretro.dll> \
##         --rom="<a multitap game>.chd" --leg=tap --out=<dir> \
##         --steps="900-906:1:start,1200-1206:3:cross" --shots=880,1180,1400
##
## --system=ps2 plays a PS2 game instead, on the PlayStation 2 Multitap and
## `--core=` (pcsx2 by default: RetroXR's LRPS2 v7+, or pcee2), the root holding
## cores/<core>_libretro.dll and system/pcsx2.
##
## ONE LEG PER PROCESS:
##   --leg=tap   a Multitap in port 1, a pad in each of its sockets A-D
##   --leg=none  the control: two pads straight in the console's ports
##
## --steps: comma-separated `from-to:player:buttons`, buttons joined by `+` from
## cross circle square triangle start select up down left right l1 r1 l2 r2; held
## over the core's frames from..to and released after. --every=N also saves a
## frame every N frames (finding a menu's timing).
##
## Crash Team Racing (USA) is what this was first run against
## (docs/dev/four-player-adapters.md has the script and what each leg showed).
extends Node

const BITS := {"cross": 0, "square": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "circle": 8, "triangle": 9, "l1": 10, "r1": 11, "l2": 12, "r2": 13}

var root_dir := ""
var rom_path := ""
var leg := "tap"
var out_dir := ""
var every := 0
var systemid := "psx"
var core := ""
var _steps: Array = []
var _shots: Array[int] = []
var _pads: Array = []
var _lib: Object = null
var _sent: Array[int] = [-1, -1, -1, -1]


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
		elif a.begins_with("--every="):
			every = int(a.trim_prefix("--every="))
		elif a.begins_with("--system="):
			systemid = a.trim_prefix("--system=")
		elif a.begins_with("--core="):
			core = a.trim_prefix("--core=")
	if core.is_empty():
		core = "pcsx2" if systemid == "ps2" else "pcsx_rearmed"
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[psmtgame] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/%s_libretro.dll" % core)) \
			or not FileAccess.file_exists(rom_path) or out_dir.is_empty():
		print("[psmtgame] need --root=, --rom= and --out=")
		get_tree().quit(1)
		return
	for s in steps_arg.split(",", false):
		var parts := s.split(":")
		var span := parts[0].split("-")
		var mask := 0
		for b in parts[2].split("+", false):
			if not BITS.has(b):
				print("[psmtgame] unknown button %s" % b)
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
	sys.systemid = systemid
	sys.core_directory = root_dir
	sys.core_name = core
	add_child(sys)
	sys.freeze = true
	for i in 10:
		await get_tree().physics_frame
	for i in 4:
		_pads.append(_spawn("res://Scenes/Objects/controllers/playstation/ps1_controller.tscn", Vector3(-0.3 + 0.2 * i, 0, 0.6)))
	for i in 6:
		await get_tree().physics_frame
	if leg == "none":
		for i in 2:
			sys.restore_controller_plug(i, _pads[i].call("get_plug"))
	else:
		var tap_scene := "ps2_multitap" if systemid == "ps2" else "ps_multitap"
		var tap := _spawn("res://Scenes/Objects/controllers/playstation/%s.tscn" % tap_scene, Vector3(0, 0, 0.3)) as PsMultitap
		await get_tree().physics_frame
		await get_tree().physics_frame
		sys.restore_controller_plug(0, tap.get_plug())
		for i in 4:
			tap.restore_socket(i, _pads[i])
	for i in 12:
		await get_tree().physics_frame
	for p: Variant in _pads:
		(p as Node).set_physics_process(false)
		(p as Node).set_process(false)
	print("[psmtgame] %s: players on libretro ports %s" % [leg, str(_pads.map(
		func(p: Variant) -> int: return int((p as Node).call("get_port_index"))))])
	print("[psmtgame] forced %s" % str(ForcedCoreOptions.ps_multitap(core, systemid,
		sys.controller_ports().ps_multitap_sockets(ForcedCoreOptions.multitap_group(systemid)))))

	sys.rom_path = rom_path
	sys.toggle_power()
	_lib = sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 60000
	while (_lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if (_lib.GetCoreIdentity() as Dictionary).is_empty():
		print("[psmtgame] the core never came up")
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
	var next_every := every
	while true:
		var frame := int(_lib.GetFrameCount())
		if not told and frame > 60:
			told = true
			var ids: Array = []
			for e: Dictionary in sys.controller_ports().controller_info:
				ids.append("%d:%d" % [int(e.get("port", -1)), int(e.get("current_id", -1))])
			print("[psmtgame] the core was told %s" % ", ".join(ids))
		_drive(frame)
		while shot_i < sorted_shots.size() and frame >= sorted_shots[shot_i]:
			_shot(sorted_shots[shot_i])
			shot_i += 1
		if every > 0 and frame >= next_every:
			_shot(frame)
			next_every += every
		if frame > last:
			break
		await get_tree().process_frame
	sys.toggle_power()
	for i in 60:
		await get_tree().process_frame
	print("[psmtgame] done")
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
		print("[psmtgame] frame %d: no image" % frame)
		return
	var path := out_dir.path_join("%s_%05d.png" % [leg, frame])
	img.save_png(path)
	print("[psmtgame] frame %d -> %s" % [frame, path])
