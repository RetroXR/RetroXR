## Once a second, what every running machine's second was made of, printed as
## a `[PaceTrace]` line: the room's measure of a lag or a crackle, where the
## probes measure it in a rig. Only when XENU_PACE_TRACE is set in the
## environment (QualityManager adds this node); nothing reads it otherwise.
##
## Per machine, over the last second:
##   f       frames finished, so its fps
##   run     ms inside retro_run, and the worst single call
##   sleep   ms asleep on the audio brake
##   parked  ms parked on a link bus waiting for a peer -- 0 unless
##           XENU_LINK_WAIT_DIAGNOSTICS is set too -- of `adv` advance calls,
##           `waits` of which parked at all
##   sink    the front voice's queue, floor..ceiling ms
## and for the room: its fps, the main thread's process ms, mixer underruns.
##
## A machine that is SLOW runs long and parks little; one that is WAITING on
## another runs long and parks for most of it (docs/dev/ps2-ilink.md).
##
## The lines also go to user://logs/pace_trace.log, flushed one by one, so the
## trace can be read while the session is still running: godot.log is written
## in blocks.
extends Node

const TRACE_PATH := "user://logs/pace_trace.log"

var _file: FileAccess = null
var _last_ms := 0
## instance id -> the counters as last read
var _prev: Dictionary = {}
var _lo: Dictionary = {}
var _hi: Dictionary = {}
var _mx: Object = null
var _underruns := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_ms = Time.get_ticks_msec()
	if Engine.has_singleton("MetaXRAudio"):
		_mx = Engine.get_singleton("MetaXRAudio")
		_underruns = int(_mx.call("get_underrun_count"))
	_file = FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	_emit("[PaceTrace] on %s%s" % [Time.get_datetime_string_from_system(),
		"" if OS.has_environment("XENU_LINK_WAIT_DIAGNOSTICS")
		else " (parked reads 0: XENU_LINK_WAIT_DIAGNOSTICS is not set)"])


func _emit(line: String) -> void:
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()


func _process(_delta: float) -> void:
	var systems := _running()
	if _mx != null:
		var rate := AudioServer.get_mix_rate()
		for sys: Node in systems:
			var ids: PackedInt32Array = (sys.call("get_libretro_node") as Libretro).GetAudioVoiceIds()
			if ids.is_empty():
				continue
			var ms := 1000.0 * float(_mx.call("voice_frames_available", ids[0])) / rate
			var key := sys.get_instance_id()
			_lo[key] = minf(float(_lo.get(key, INF)), ms)
			_hi[key] = maxf(float(_hi.get(key, 0.0)), ms)
	var now := Time.get_ticks_msec()
	var span := now - _last_ms
	if span < 1000:
		return
	_last_ms = now
	var line := "[PaceTrace] %s room %.0f fps proc %.1f ms" % [
		Time.get_time_string_from_system(), Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
	if _mx != null:
		var under := int(_mx.call("get_underrun_count"))
		line += " underruns +%d" % (under - _underruns)
		_underruns = under
	for sys: Node in systems:
		var lib := sys.call("get_libretro_node") as Libretro
		var key := sys.get_instance_id()
		var pacing: Dictionary = lib.GetPacingStats()
		var cost: Dictionary = lib.LinkCost(0)
		var cur := {
			"frames": int(lib.GetFrameCount()),
			"run": float(pacing.get("run_ms", 0.0)),
			"sleep": float(pacing.get("brake_sleep_ms", 0.0)),
			"parked": float(cost.get("blocked_ms", 0.0)),
			"adv": int(cost.get("advance_calls", 0)),
			"waits": int(cost.get("advance_waits", 0)),
		}
		var was: Dictionary = _prev.get(key, cur)
		_prev[key] = cur
		var scale := 1000.0 / float(span)
		line += " | %s f %.0f run %.0f (worst %.0f) sleep %.0f parked %.0f adv %d waits %d peers %d sink %.0f..%.0f" % [
			_label(sys), (cur["frames"] - was["frames"]) * scale,
			(cur["run"] - was["run"]) * scale, float(pacing.get("run_worst_ms", 0.0)),
			(cur["sleep"] - was["sleep"]) * scale, (cur["parked"] - was["parked"]) * scale,
			cur["adv"] - was["adv"], cur["waits"] - was["waits"], lib.LinkPeerCount(0),
			float(_lo.get(key, 0.0)) if _lo.has(key) else 0.0, float(_hi.get(key, 0.0))]
	_lo.clear()
	_hi.clear()
	_emit(line)


func _running() -> Array[Node]:
	var out: Array[Node] = []
	for sys: Node in get_tree().get_nodes_in_group("retro_system"):
		if not bool(sys.get("is_powered_on")):
			continue
		var lib := sys.call("get_libretro_node") as Libretro
		if lib != null:
			out.append(sys)
	return out


## The machine's own node name is a generated "@RigidBody3D@3738" in a restored
## room, so the system id rides along with the instance id it shares with the
## rest of the log.
func _label(sys: Node) -> String:
	return "%s#%d" % [str(sys.get("systemid")), sys.get_instance_id() % 10000]
