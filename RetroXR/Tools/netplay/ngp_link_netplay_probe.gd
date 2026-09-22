## Can a CABLED pair of Neo Geo Pockets be put back where it was?
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/ngp_link_netplay_probe.tscn -- \
##       "--rom=Z:/roms/ngpc/SNK Gals' Fighters (USA, Europe).ngc" \
##       [--mode=sweep|trace] [--from=400] [--to=1400] [--step=25] [--depth=12] \
##       [--nocable] [--trace-out=user://ngp_trace_a.txt]
##
## A probe: it wants RetroXR's mednafen_ngp (the link driver) and a real ROM.
##
## A session never ROLLS BACK a cabled machine (netplay_session.gd demotes a
## linked group to lockstep), but it still has to put a cabled pair back: a late
## join and a desync resync capture both cores plus the bus mid-conversation and
## restore them — bus first, then the cores. This does exactly that, both
## machines gated as the session gates them, at an anchor every --step frames:
## pause both at A, capture, run --depth frames, pause, restore, replay, compare
## BOTH machines' per-frame CRCs and what crossed the wire.
##
## --mode=trace just runs cold to --to and writes every CRC of both machines to
## --trace-out. Run it twice and diff the files: that is two peers each running
## the pair from a cold start, which is all lockstep needs.
##
## --nocable is the control leg: the same sweep with no lead, so a failure that
## only appears cabled is the link's and not the core's.
extends Node

static var _home := OS.get_environment("HOME") if OS.get_name() == "Linux" \
		else OS.get_environment("USERPROFILE").replace("\\", "/")

var core := "mednafen_ngp"
var rom2 := ""
## beetle-ngp: RetroPad B is the NGP's A (confirm), D-pad down is bit 5.
const A := 1 << 0
const DOWN := 1 << 5

var root_dir := _home + "/retroxr/libretro"
var rom := ""
var mode := "sweep"
var from_frame := 400
var to_frame := 1400
var step := 25
var depth := 12
var cable := true
var trace_out := "user://ngp_trace.txt"

var _m: Array = []
var _feed := [0, 0]
var _limit := 0
var _crc := [{}, {}]
var _pass1 := [{}, {}]
var _traffic1 := [0, 0]
var _recording := 0             # 0 off, 1 first pass, 2 replay
var _bad := 0
var _anchors := 0
var _quiet := false
var _skipped := 0
var _opts: Dictionary = {}
var _live := 0                  # anchors whose window carried bytes


## Gals' Fighters, Mode Select -> 2P VS, pressed APART (docs/dev/ngp-link.md).
## A pure function of the frame, so a replay is fed what the first pass was.
func _pad(machine: int, f: int) -> int:
	var presses := [[430, 0, A], [485, 0, A], [577, 1, A], [632, 1, A],
		[847, 0, DOWN], [847, 1, DOWN], [902, 0, A], [947, 1, A]]
	for p: Array in presses:
		if int(p[1]) == machine and f >= int(p[0]) and f < int(p[0]) + 3:
			return int(p[2])
	return 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--rom="): rom = a.trim_prefix("--rom=")
		elif a.begins_with("--mode="): mode = a.trim_prefix("--mode=")
		elif a.begins_with("--from="): from_frame = int(a.trim_prefix("--from="))
		elif a.begins_with("--to="): to_frame = int(a.trim_prefix("--to="))
		elif a.begins_with("--step="): step = int(a.trim_prefix("--step="))
		elif a.begins_with("--depth="): depth = int(a.trim_prefix("--depth="))
		elif a.begins_with("--trace-out="): trace_out = a.trim_prefix("--trace-out=")
		elif a == "--nocable": cable = false
		elif a.begins_with("--root="): root_dir = a.trim_prefix("--root=")
		elif a.begins_with("--opt="):
			var kv := a.trim_prefix("--opt=")
			_opts[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
		elif a.begins_with("--core="): core = a.trim_prefix("--core=")
		elif a.begins_with("--rom2="): rom2 = a.trim_prefix("--rom2=")
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[ngpnet] TIMEOUT")
		get_tree().quit(2))
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[ngpnet] RESULT=FAIL (pass --rom)")
		get_tree().quit(1)
		return
	await _run()


func _run() -> void:
	for i in range(2):
		var obj: Object = ClassDB.instantiate("Libretro")
		var lib: Node = obj as Node
		add_child(lib)
		lib.connect("netplay_crc", _on_crc.bind(i))
		lib.SetNetplayMode(true, 0x1, 0)
		lib.SetNetplayCrcInterval(1)
		for k: Variant in _opts:
			lib.SetCoreOption(str(k), str(_opts[k]))
		lib.StartContent(root_dir, core, rom if i == 0 or rom2.is_empty() else rom2)
		_m.append(lib)
	for _i in range(600):
		await get_tree().process_frame
		if not (_m[0].GetCoreIdentity() as Dictionary).is_empty() \
				and not (_m[1].GetCoreIdentity() as Dictionary).is_empty():
			break
	if cable:
		_m[0].LinkConnectGroup([_m[1]], PackedInt32Array([0, 0]))
	print("[ngpnet] %s %s, %s, peers %d" % [mode, rom.get_file(),
		"cabled" if cable else "NO CABLE", int(_m[0].LinkPeerCount(0))])

	if mode == "trace":
		_recording = 1
		await _run_to(to_frame)
		var f := FileAccess.open(trace_out, FileAccess.WRITE)
		for fr in range(1, to_frame + 1):
			f.store_line("%d %08x %08x" % [fr, int(_crc[0].get(fr, -1)), int(_crc[1].get(fr, -1))])
		f.store_line("traffic %d %d" % [int(_m[0].LinkTraffic(0)), int(_m[1].LinkTraffic(0))])
		f.close()
		print("[ngpnet] trace -> %s, traffic %d/%d" % [ProjectSettings.globalize_path(trace_out),
			int(_m[0].LinkTraffic(0)), int(_m[1].LinkTraffic(0))])
		await _finish()
		return

	if mode == "pause":
		var wedged := 0
		var tries := 0
		for target in range(from_frame, to_frame, step):
			_quiet = true
			await _run_to(target)
			_quiet = false
			tries += 1
			var fc := [int(_m[0].GetFrameCount()), int(_m[1].GetFrameCount())]
			if fc[0] != target or fc[1] != target:
				wedged += 1
				if wedged <= 12:
					print("[ngpnet] pause at %d: machines rest at %d / %d" % [target, fc[0], fc[1]])
		print("[ngpnet] pause: %d of %d boundaries unreachable by both, traffic %d/%d" % [wedged, tries,
			int(_m[0].LinkTraffic(0)), int(_m[1].LinkTraffic(0))])
		_bad = wedged
		print("[ngpnet] RESULT=%s" % ("PASS" if _bad == 0 else "FAIL"))
		await _finish()
		return

	await _run_to(from_frame)
	var anchor := from_frame
	while anchor + depth <= to_frame:
		await _check_anchor(anchor)
		anchor += step
	print("[ngpnet] %d anchors, %d with bytes on the wire, %d bad, %d skipped (pair not at rest)"
		% [_anchors, _live, _bad, _skipped])
	print("[ngpnet] RESULT=%s" % ("PASS" if _bad == 0 else "FAIL"))
	await _finish()


func _check_anchor(anchor: int) -> void:
	_quiet = true
	await _run_to(anchor)
	_quiet = false
	# A machine blocked inside its frame on the bus cannot take a state, and the
	# pair cannot always rest on one frame (docs/dev/netplay.md): skip those.
	if int(_m[0].GetFrameCount()) != anchor or int(_m[1].GetFrameCount()) != anchor:
		_skipped += 1
		return
	var states: Array = []
	for i in range(2):
		_m[i].RequestSaveState()
		var got: Array = await _m[i].savestate_ready
		states.append(got[0])
	var at := [int(_m[0].GetFrameCount()), int(_m[1].GetFrameCount())]
	var bus: Array = _m[0].LinkCaptureGroup([_m[1]], PackedInt32Array([0, 0])) if cable else []
	var t0 := [int(_m[0].LinkTraffic(0)), int(_m[1].LinkTraffic(0))]

	_pass1 = [{}, {}]
	_crc = [{}, {}]
	_recording = 1
	await _run_to(anchor + depth)
	await _settle()
	_pass1 = [_crc[0].duplicate(), _crc[1].duplicate()]
	_traffic1 = [int(_m[0].LinkTraffic(0)) - t0[0], int(_m[1].LinkTraffic(0)) - t0[1]]

	# Put it back the way a joiner does: the bus, then each core.
	if cable and not _m[0].LinkRestoreGroup([_m[1]], PackedInt32Array([0, 0]), bus):
		print("[ngpnet] anchor %d: LinkRestoreGroup FAILED" % anchor)
		_bad += 1
	for i in range(2):
		_m[i].RequestLoadState(states[i] as PackedByteArray, at[i])
		var ok: bool = await _m[i].savestate_loaded
		if not ok:
			print("[ngpnet] anchor %d: machine %d unserialize FAILED" % [anchor, i])
			_bad += 1
	_feed = at.duplicate()
	_crc = [{}, {}]
	_recording = 2
	var t1 := [int(_m[0].LinkTraffic(0)), int(_m[1].LinkTraffic(0))]
	await _run_to(anchor + depth)
	await _settle()
	_recording = 0
	var traffic2 := [int(_m[0].LinkTraffic(0)) - t1[0], int(_m[1].LinkTraffic(0)) - t1[1]]

	_anchors += 1
	var live: bool = _traffic1[0] + _traffic1[1] > 0
	if live:
		_live += 1
	var verdict := ""
	for i in range(2):
		for f in range(at[i] + 1, anchor + depth):
			if _pass1[i].get(f, -1) != _crc[i].get(f, -2):
				verdict += " m%d differs at %d (%08x vs %08x)" % [i, f,
					int(_pass1[i].get(f, -1)), int(_crc[i].get(f, -1))]
				break
	if _traffic1 != traffic2:
		verdict += " wire %s then %s" % [str(_traffic1), str(traffic2)]
	if not verdict.is_empty():
		_bad += 1
		print("[ngpnet] anchor %d%s:%s" % [anchor, " (bytes)" if live else "", verdict])


func _settle() -> void:
	for _i in range(5):
		await get_tree().process_frame


## Feed both gates up to (not including) `target` and wait until both are there,
## or until the pair stops: a cabled machine cannot always finish its last frame
## before the other has run past the bus horizon, so the two may rest a frame
## apart. Each is then anchored at its own frame.
func _run_to(target: int) -> void:
	_limit = target
	var still := 0
	var last := -1
	while (int(_m[0].GetFrameCount()) < target or int(_m[1].GetFrameCount()) < target) 			and still < (30 if _quiet else 120):
		await get_tree().process_frame
		var sum := int(_m[0].GetFrameCount()) + int(_m[1].GetFrameCount())
		still = still + 1 if sum == last else 0
		last = sum
	if not _quiet and mini(int(_m[0].GetFrameCount()), int(_m[1].GetFrameCount())) < target - 1:
		print("[ngpnet] stuck short of %d: fc %d/%d" % [target,
			int(_m[0].GetFrameCount()), int(_m[1].GetFrameCount())])
		_bad += 1


func _process(_d: float) -> void:
	for i in range(_m.size()):
		# A bounded lead, as the session keeps: the gate's input ring is finite.
		while _feed[i] < mini(_limit, int(_m[i].GetFrameCount()) + 60):
			var flat := PackedInt32Array()
			flat.resize(20 + 7 + 8)
			flat[0] = _pad(i, _feed[i])
			_m[i].PostNetplayInputs(_feed[i], flat)
			_feed[i] += 1


func _on_crc(frame: int, crc: int, machine: int) -> void:
	if _recording != 0:
		_crc[machine][frame] = crc


func _finish() -> void:
	for lib: Node in _m:
		lib.StopContent()
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(1 if _bad > 0 else 0)
