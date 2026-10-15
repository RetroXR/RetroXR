## Two real PlayStation 2s on one i.LINK lead, switched on one after the other:
## the order a player meets, and the one that froze a console on 2026-10-15.
##
##     USERPROFILE=<a scratch home holding retroxr/probe_home.txt> \
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/link/ilink_power_on_probe.tscn -- "--rom=<image>" \
##       [--rom2=<image for B>] [--delay=20] [--seconds=60] [--nocable]
##
## A is switched on, B `--delay` seconds later (B is OFF on the wire meanwhile,
## as in the room). Every second both frame counters are printed with what the
## bus says; a console that is on and has not finished a frame for 5 s is
## reported FROZEN and the run exits 1. `--nocable` is the control leg.
## `--rom2` gives B a game of its own: one that never starts an i.LINK driver
## is the case that held the first console for good.
##
## Windowed: pcsx2 renders on the GPU. The data root's memory cards and core
## files are written, so this refuses to run without probe_home.txt there.
##
## Every line also goes to --out (flushed one at a time: a run killed by a
## timeout loses Godot's buffered stdout), and a watchdog thread writes there
## when the MAIN thread stops turning frames, which a call into a wedged link
## coordinator would do.
extends Node

const MARKER := "probe_home.txt"
const NAMES := ["A", "B"]
const STUCK_MS := 5000

var _rom := ""
var _rom2 := ""
var _delay := 20.0
var _seconds := 60.0
var _nocable := false
var _sys: Array[Node3D] = []
var _out_path := "user://ilink_power_on_probe.txt"
var _out: FileAccess = null
var _out_lock := Mutex.new()
var _frames_seen := 0
var _watching := true
var _watchdog: Thread = null


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		_say("[probe] TIMEOUT")
		get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--rom="):
			_rom = s.substr(6)
		elif s.begins_with("--rom2="):
			_rom2 = s.substr(7)
		elif s.begins_with("--delay="):
			_delay = float(s.substr(8))
		elif s.begins_with("--seconds="):
			_seconds = float(s.substr(10))
		elif s == "--nocable":
			_nocable = true
		elif s.begins_with("--out="):
			_out_path = s.substr(6)
	_out = FileAccess.open(_out_path, FileAccess.WRITE)
	_watchdog = Thread.new()
	_watchdog.start(_watch)
	if not FileAccess.file_exists(DataPaths.media_root(MARKER)):
		_say("[probe] refusing: %s holds no %s" % [DataPaths.media_root(), MARKER])
		get_tree().quit(2)
		return
	if not FileAccess.file_exists(_rom):
		_say("[probe] need --rom=<PS2 image>")
		get_tree().quit(2)
		return
	var code: int = await _run()
	_watching = false
	_watchdog.wait_to_finish()
	get_tree().quit(code)


func _process(_delta: float) -> void:
	_frames_seen += 1


func _say(line: String) -> void:
	print(line)
	_out_lock.lock()
	if _out != null:
		_out.store_line("%s %s" % [Time.get_time_string_from_system(), line])
		_out.flush()
	_out_lock.unlock()


## On its own thread: a main thread that has stopped turning frames cannot say so.
func _watch() -> void:
	var last := -1
	var still := 0
	while _watching:
		OS.delay_msec(1000)
		var now := _frames_seen
		still = still + 1 if now == last else 0
		last = now
		if still == 3 or (still > 0 and still % 15 == 0):
			_say("[probe] MAIN THREAD STUCK for %d s at room frame %d" % [still, now])


func _run() -> int:
	for k in range(2):
		var sys := (preload("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as Node3D
		sys.set("systemid", "ps2")
		sys.set("core_name", "pcsx2")
		sys.name = "PS2_" + NAMES[k]
		sys.position = Vector3(-0.3 + 0.6 * k, 0, 0)
		add_child(sys)
		_sys.append(sys)
	var lead: ILinkCable = (preload("res://Scenes/Objects/cables/ilink_cable.tscn") as PackedScene).instantiate()
	add_child(lead)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _nocable:
		(_sys[0].find_child("ILinkPort", true, false) as ILinkPort).pick_up_object(lead.get_node("PlugA0"))
		(_sys[1].find_child("ILinkPort", true, false) as ILinkPort).pick_up_object(lead.get_node("PlugB0"))
		await get_tree().process_frame
		lead._resolve()
	_say("[probe] lead joins %d console(s)%s" % [(lead.linked_machines() as Array).size(),
		" (control: no lead)" if _nocable else ""])

	var on_at: Array[int] = [-1, -1]
	var last_frame: Array[int] = [-1, -1]
	var moved_at: Array[int] = [0, 0]
	var start := Time.get_ticks_msec()
	var next_log := 0
	var frozen := false
	while Time.get_ticks_msec() - start < int((_delay + _seconds) * 1000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_msec() - start
		for k in range(2):
			if on_at[k] < 0 and now >= int(_delay * 1000.0) * k:
				_sys[k].set("rom_path", _rom2 if k == 1 and _rom2 != "" else _rom)
				_sys[k].call("power_on")
				on_at[k] = now
				moved_at[k] = now
				_say("[probe] %s power_on at %.1f s" % [NAMES[k], now / 1000.0])
		var frames: Array[int] = [0, 0]
		for k in range(2):
			if on_at[k] < 0:
				continue
			frames[k] = int(_lib(k).GetFrameCount())
			if frames[k] != last_frame[k]:
				last_frame[k] = frames[k]
				moved_at[k] = now
			# A core still booting has no frames yet; give it the same grace.
			if now - moved_at[k] > STUCK_MS and not frozen:
				frozen = true
				_say("[probe] FROZEN %s at frame %d, %.1f s after its last frame (%.1f s in)" % [
					NAMES[k], frames[k], (now - moved_at[k]) / 1000.0, now / 1000.0])
				_report()
		if now >= next_log:
			next_log += 1000
			var line := "[probe] t=%5.1f" % (now / 1000.0)
			for k in range(2):
				if on_at[k] < 0:
					line += "  %s off" % NAMES[k]
					continue
				var c: Dictionary = _lib(k).LinkCost(0)
				line += "  %s f=%d peers=%d adv=%d parked=%d" % [NAMES[k], frames[k],
					_lib(k).LinkPeerCount(0), int(c.get("advance_calls", 0)),
					int(c.get("advance_waits", 0))]
			_say(line)
		if frozen and now - start > 0 and now > moved_at.max() + STUCK_MS * 2:
			break
	_report()
	for k in range(2):
		if on_at[k] >= 0:
			_sys[k].call("power_off")
	for i in range(120):
		await get_tree().process_frame
	_say("[probe] RESULT=%s" % ("FROZEN" if frozen else "BOTH RAN"))
	return 1 if frozen else 0


func _report() -> void:
	for k in range(2):
		var lib := _lib(k)
		if lib == null:
			continue
		_say("[probe]   %s frames %d identity %s cost %s pacing %s" % [NAMES[k],
			int(lib.GetFrameCount()), str(lib.GetCoreIdentity().get("version", "")),
			str(lib.LinkCost(0)), str(lib.GetPacingStats())])


func _lib(k: int) -> Libretro:
	return _sys[k].call("get_libretro_node") as Libretro
