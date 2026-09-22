## Rollback netplay over a PlayStation link cable, with the real core and WipEout.
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/psx_rollback_probe.tscn -- --leg=rb
##   "$godot" --headless --path RetroXR res://Tools/netplay/psx_rollback_probe.tscn -- --leg=ref
##   "$godot" --headless --path RetroXR res://Tools/netplay/psx_rollback_probe.tscn -- --leg=solo
##   "$godot" --headless --path RetroXR res://Tools/netplay/psx_rollback_probe.tscn -- --leg=compare
##
## lynx_rollback_probe's legs and oracle, driving two PlayStations through
## psx_link_probe's menu walk into a linked two-player race, so the rollbacks
## land while the cable is carrying the race. ONE leg per process, in that
## order. Options: --rom=<.cue> (default WipEout (USA)), --delay=N, --frames=N.
##
## A probe: it wants RetroXR's pcsx_rearmed (SIO1 in the savestate), a BIOS and
## the disc. The player's pcsx_rearmed.opt is pinned for the run (link cable on,
## dynarec on) and put back byte for byte.
##
##   rb    group rollback; machine 1's confirmations arrive --delay frames late.
##   ref   the timeline rb recorded, in plain lockstep: the truth.
##   solo  rollback with no group, each core rewinding alone: must NOT match.
##   compare  rb == ref at every checkpoint, rb rolled back, the cable carried
##         a race's worth of bytes, and solo != ref.
extends Node

const CORE := "pcsx_rearmed"
const OUT_DIR := "res://probe_out/psx/rollback"
const CRC_INTERVAL := 60
var _crc_interval := CRC_INTERVAL
const MAX_AHEAD := 8
## The second unit's power-on, and the frame the cable joins (see
## Wrapper::SetNetplayPowerOnFrame): identical units switched on together
## collide on every byte, so a session staggers them.
const POWER_ON_1 := 7
var _power1 := POWER_ON_1
## --nocable: the same group and inputs with the lead never joined, which
## separates the rewind itself from the wire.
var _nocable := false
## --interp: the interpreter instead of the dynarec.
var _interp := false
## --allremote: both pads predicted, confirmed --delay frames behind, as the
## single-core spike runs its one pad.
var _allremote := false
## --alllocal: both pads local, so nothing is ever mispredicted: the group
## stops at every edge and never rewinds.
var _alllocal := false
var _loc0 := {}
var _loc1 := {}
## The frame the cable joins. Past anything the group can run before the first
## confirmation (max_ahead from frame -1), so the change is scheduled before
## its frame can come round: a cable change that lands late lands on a
## different frame on every peer.
const JOIN := 12

var _leg := "rb"
var _rom := OS.get_environment("USERPROFILE").replace("\\", "/") + "/retroxr/roms/psx/WipEout (USA).cue"
var _delay := 5
var _end := 7900
var _m: Array[Libretro] = []
var _crcs := [{}, {}]
## frame -> [m0 buttons, m1 buttons], the timeline every frame actually ran with.
var _timeline := {}
var _local := {}
var _posted := 0
var _opt_path := ""
var _opt_bytes := PackedByteArray()
var _opt_existed := false
var _joined := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			_leg = arg.substr(6)
		elif arg.begins_with("--rom="):
			_rom = arg.substr(6)
		elif arg.begins_with("--delay="):
			_delay = maxi(1, int(arg.substr(8)))
		elif arg.begins_with("--crc="):
			_crc_interval = maxi(1, int(arg.substr(6)))
		elif arg == "--alllocal":
			_alllocal = true
		elif arg == "--allremote":
			_allremote = true
		elif arg == "--interp":
			_interp = true
		elif arg == "--nocable":
			_nocable = true
		elif arg.begins_with("--power1="):
			_power1 = maxi(0, int(arg.substr(9)))
		elif arg.begins_with("--frames="):
			_end = maxi(600, int(arg.substr(9)))
	get_tree().create_timer(3000.0).timeout.connect(_on_timeout)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if _leg == "compare":
		get_tree().quit(_compare())
		return
	await _run()


const B_CROSS := 1 << 0
const B_START := 1 << 3
const B_DOWN := 1 << 5
## psx_link_probe's walk, in frames: to the title, a START hold through the
## attract, taps, TWO PLAYER on each console in turn, then class/team/track.
const TITLE := 2760
var _presses: Array = []


func _build_script() -> void:
	var t := TITLE
	_presses.append([0, t, 240, B_START]); _presses.append([1, t, 240, B_START])
	t += 420
	for i in range(8):
		_presses.append([0, t, 6, B_START]); _presses.append([1, t, 6, B_START])
		t += 30
	t += 600
	_presses.append([0, t, 10, B_DOWN]); _presses.append([1, t + 50, 10, B_DOWN])
	t += 100
	_presses.append([0, t, 10, B_CROSS]); _presses.append([1, t + 130, 10, B_CROSS])
	t += 260
	for i in range(9):
		_presses.append([0, t, 8, B_CROSS]); _presses.append([1, t + 38, 8, B_CROSS])
		t += 316


func _script(machine: int, frame: int) -> int:
	if _presses.is_empty():
		_build_script()
	var btn := 0
	for p: Array in _presses:
		if int(p[0]) == machine and frame >= int(p[1]) and frame < int(p[1]) + int(p[2]):
			btn |= int(p[3])
	return btn


func _run() -> void:
	if not FileAccess.file_exists(_rom):
		print("[psxrb] SKIP no ROM at %s" % _rom)
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	_pin_options(root)
	for i in range(2):
		var lib := Libretro.new()
		add_child(lib)
		_m.append(lib)
		lib.netplay_crc.connect(func(frame: int, crc: int) -> void: _crcs[i][str(frame)] = crc)
	var rollback := _leg != "ref"
	for i in range(2):
		var lib := _m[i]
		lib.SetNetplayRollback(rollback, 1 if (rollback and (_alllocal or (i == 0 and not _allremote))) else 0, MAX_AHEAD)
		lib.SetNetplayCrcInterval(_crc_interval)
		lib.SetNetplayPowerOnFrame(0 if i == 0 else _power1)
		lib.SetNetplayMode(true, 1, 0)
	if _leg == "rb":
		print("[psxrb] group: %s" % _m[0].SetNetplayRollbackGroup([_m[1]], PackedInt32Array([0, 0])))
	if _leg == "ref":
		_load_timeline()
	for lib in _m:
		lib.StartContent(root, CORE, _rom)
	# A core refuses a scheduled cable change until it has loaded, which happens
	# on its own thread; nothing is confirmed until then, so no frame near JOIN
	# can have run yet.
	while _m[0].GetCoreIdentity().is_empty() or _m[1].GetCoreIdentity().is_empty():
		await get_tree().process_frame
	# A bare probe plugs no pad in (system.gd does, for a real machine), and
	# nothing polls the pads for seconds of BIOS yet, so the frame this lands on
	# cannot matter.
	for lib in _m:
		lib.SetControllerPortDevice(0, 1)
	if _leg == "rb" and not _nocable:
		# The group lands it at the frame edge, with every member stopped there.
		_m[0].ScheduleLinkOp(JOIN, 1, [_m[1]], PackedInt32Array([0, 0]))

	var last := -1
	var still := 0
	while true:
		await get_tree().process_frame
		if _leg == "ref":
			_drive_ref()
		else:
			_drive_rollback()
		var f := mini(_m[0].GetFrameCount(), _m[1].GetFrameCount())
		if f >= _end:
			break
		still = still + 1 if f == last else 0
		last = f
		if still > 2000:
			print("[psxrb] WEDGED at frame %d/%d" % [_m[0].GetFrameCount(), _m[1].GetFrameCount()])
			_finish(true)
			return
	# Let the confirmations for the tail land so every CRC up to the end is out.
	for _i in range(120):
		if _leg != "ref":
			_drive_rollback()
		await get_tree().process_frame
	_finish(false)


## Lockstep: post the next frames, holding at the power-on frame until both
## machines are there, and join the cable from here while both are stopped --
## what NetplaySession._land_link_ops does.
func _drive_ref() -> void:
	var front := mini(_m[0].GetFrameCount(), _m[1].GetFrameCount())
	if not _joined and not _nocable:
		if front < JOIN:
			while _posted < JOIN:
				_post_both(_posted)
				_posted += 1
			return
		if _m[0].GetFrameCount() != JOIN or _m[1].GetFrameCount() != JOIN:
			return
		print("[psxrb] cable joined @%d: %s" % [JOIN, _m[0].LinkConnectGroup([_m[1]], PackedInt32Array([0, 0]))])
		_joined = true
	while _posted < front + 4 and _posted < _end + 2:
		_post_both(_posted)
		_posted += 1


func _post_both(frame: int) -> void:
	var row: Array = _timeline.get(frame, [0, 0])
	for i in range(2):
		_m[i].PostNetplayInputs(frame, _frame(int(row[i])))


## Rollback: machine 0 live, machine 1 confirmed `_delay` frames behind.
func _drive_rollback() -> void:
	var f0 := _m[0].GetFrameCount()
	# A lone rollback applies no scheduled cable change, so the control joins
	# the lead from here once both are past power-on, as a room would.
	if _leg == "solo" and not _nocable and not _joined and f0 >= JOIN and _m[1].GetFrameCount() >= JOIN:
		print("[psxrb] cable joined: %s" % _m[0].LinkConnectGroup([_m[1]], PackedInt32Array([0, 0])))
		_joined = true
	if _alllocal:
		var g0 := _m[0].GetFrameCount()
		var g1 := _m[1].GetFrameCount()
		_m[0].SetJoypadState(0, _script(0, g0), 0, 0, 0, 0)
		_m[1].SetJoypadState(0, _script(1, g1), 0, 0, 0, 0)
		var r0: PackedInt32Array = _m[0].TakeNetplayLocalRecords()
		var r1: PackedInt32Array = _m[1].TakeNetplayLocalRecords()
		for k in range(0, r0.size() - 6, 7):
			_loc0[r0[k]] = r0[k + 2]
		for k in range(0, r1.size() - 6, 7):
			_loc1[r1[k]] = r1[k + 2]
		while _loc0.has(_posted) and _loc1.has(_posted) and _posted < _end + 2:
			var r := [int(_loc0[_posted]), int(_loc1[_posted])]
			_timeline[_posted] = r
			_m[0].PostNetplayInputs(_posted, _frame(r[0]))
			_m[1].PostNetplayInputs(_posted, _frame(r[1]))
			_posted += 1
		return
	if _allremote:
		var fr := mini(f0, _m[1].GetFrameCount())
		while _posted <= fr - _delay and _posted < _end + 2:
			var r := [_script(0, _posted), _script(1, _posted)]
			_timeline[_posted] = r
			_m[0].PostNetplayInputs(_posted, _frame(r[0]))
			_m[1].PostNetplayInputs(_posted, _frame(r[1]))
			_posted += 1
		return
	_m[0].SetJoypadState(0, _script(0, f0), 0, 0, 0, 0)
	var rec: PackedInt32Array = _m[0].TakeNetplayLocalRecords()
	var now := Time.get_ticks_msec()
	for k in range(0, rec.size() - 6, 7):
		_local[rec[k]] = [rec[k + 2], now]
	# Latency on a CLOCK, as a network has it: a frame's confirmation arrives
	# `_delay` frames' worth of time after this player pressed it, whether or
	# not the machines have moved meanwhile.
	var latency := int(_delay * 1000.0 / 75.0)
	while _local.has(_posted) and now - int(_local[_posted][1]) >= latency and _posted < _end + 2:
		var row := [int(_local[_posted][0]), _script(1, _posted)]
		_timeline[_posted] = row
		_m[0].PostNetplayInputs(_posted, _frame(row[0]))
		_m[1].PostNetplayInputs(_posted, _frame(row[1]))
		_posted += 1


func _frame(buttons: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(20)
	a[0] = buttons
	return a


func _finish(wedged: bool) -> void:
	var stats := []
	var traffic := []
	for lib in _m:
		stats.append(lib.GetNetplayRollbackStats())
		traffic.append([lib.LinkSent(0), lib.LinkTraffic(0), lib.LinkPeerCount(0)])
	_shot()
	var out := {
		"leg": _leg, "rom": _rom, "delay": _delay, "end": _end, "wedged": wedged,
		"crcs": _crcs, "stats": stats, "traffic": traffic,
	}
	if _leg == "rb":
		var tl := {}
		for f: int in _timeline:
			tl[str(f)] = _timeline[f]
		out["timeline"] = tl
	var fa := FileAccess.open(OUT_DIR + "/%s.json" % _leg, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("[psxrb] %s: frames %d/%d, crcs %d/%d, rollbacks %d/%d, traffic %s%s" % [
		_leg, _m[0].GetFrameCount(), _m[1].GetFrameCount(), _crcs[0].size(), _crcs[1].size(),
		int(stats[0].get("rollback_count", 0)), int(stats[1].get("rollback_count", 0)),
		str(traffic), " WEDGED" if wedged else ""])
	for lib in _m:
		lib.StopContent()
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_options()
	get_tree().quit(0)


func _load_timeline() -> void:
	var text := FileAccess.get_file_as_string(OUT_DIR + "/rb.json")
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("timeline"):
		print("[psxrb] FAIL run --leg=rb first")
		get_tree().quit(1)
		return
	for key: String in data["timeline"]:
		var row: Array = data["timeline"][key]
		_timeline[int(key)] = [int(row[0]), int(row[1])]
	_end = int(data.get("end", _end))


func _shot() -> void:
	var imgs: Array[Image] = []
	for lib in _m:
		var img := lib.GetVideoImage()
		if img == null or img.is_empty():
			return
		imgs.append(img)
	var fmt := imgs[0].get_format()
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var pair := Image.create_empty(w * 2 + 8, h, false, fmt)
	pair.fill(Color(0.1, 0.1, 0.12))
	for i in range(2):
		imgs[i].convert(fmt)
		pair.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(i * (w + 8), 0))
	pair.resize(pair.get_width() * 2, pair.get_height() * 2, Image.INTERPOLATE_NEAREST)
	pair.save_png(OUT_DIR + "/%s.png" % _leg)


## The link cable and the dynarec on for this run only. The .opt file is the player's real
## one (StartContent reads nothing else), so it is put back byte for byte.
func _pin_options(root: String) -> void:
	_opt_path = CoreOptionsStore.opt_path(root, CORE)
	_opt_existed = FileAccess.file_exists(_opt_path)
	if _opt_existed:
		_opt_bytes = FileAccess.get_file_as_bytes(_opt_path)
	CoreOptionsStore.merge_values(root, CORE, {"pcsx_rearmed_link_cable": "enabled",
		"pcsx_rearmed_drc": "disabled" if _interp else "enabled"})


func _restore_options() -> void:
	if _opt_path.is_empty():
		return
	if _opt_existed:
		var fa := FileAccess.open(_opt_path, FileAccess.WRITE)
		fa.store_buffer(_opt_bytes)
		fa.close()
	else:
		DirAccess.remove_absolute(_opt_path)
	_opt_path = ""


func _on_timeout() -> void:
	print("[psxrb] TIMEOUT in leg %s at frames %s" % [_leg,
		str(_m.map(func(l: Libretro) -> int: return l.GetFrameCount()))])
	_restore_options()
	get_tree().quit(1)


func _read(leg: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT_DIR + "/%s.json" % leg))
	return data if typeof(data) == TYPE_DICTIONARY else {}


## rb must equal ref at every checkpoint both have; solo must not.
func _diff(a: Dictionary, b: Dictionary) -> Array:
	var same := 0
	var differ := 0
	var first := -1
	for i in range(2):
		var ca: Dictionary = a["crcs"][i]
		var cb: Dictionary = b["crcs"][i]
		for key: String in ca:
			if not cb.has(key):
				continue
			if int(ca[key]) == int(cb[key]):
				same += 1
			else:
				differ += 1
				if first < 0 or int(key) < first:
					first = int(key)
	return [same, differ, first]


func _compare() -> int:
	var rb := _read("rb")
	var ref := _read("ref")
	var solo := _read("solo")
	if rb.is_empty() or ref.is_empty():
		print("[psxrb] FAIL run --leg=rb and --leg=ref first")
		return 1
	var fail := 0
	var d := _diff(rb, ref)
	print("[psxrb] rb vs ref: %d checkpoints equal, %d differ%s" % [d[0], d[1],
		"" if d[2] < 0 else " (first at frame %d)" % d[2]])
	if d[1] != 0 or d[0] < 2 * (int(ref["end"]) / CRC_INTERVAL) - 4:
		print("[psxrb] FAIL rollback did not reproduce the lockstep timeline")
		fail = 1
	var rolls := int(rb["stats"][0].get("rollback_count", 0)) + int(rb["stats"][1].get("rollback_count", 0))
	print("[psxrb] rb rolled back %d times (deepest %d frames)" % [rolls,
		maxi(int(rb["stats"][0].get("max_depth", 0)), int(rb["stats"][1].get("max_depth", 0)))])
	if rolls < 10:
		print("[psxrb] FAIL too few rollbacks to have tested anything")
		fail = 1
	var t: Array = rb["traffic"]
	print("[psxrb] cable: sent %s/%s received %s/%s" % [t[0][0], t[1][0], t[0][1], t[1][1]])
	if int(t[0][0]) < 500 or int(t[1][0]) < 500:
		print("[psxrb] FAIL the cable carried no conversation")
		fail = 1
	if solo.is_empty():
		print("[psxrb] NOTE no solo leg to compare")
	else:
		var s := _diff(solo, ref)
		print("[psxrb] solo vs ref: %d equal, %d differ, wedged=%s" % [s[0], s[1], str(solo.get("wedged", false))])
		if s[1] == 0 and not bool(solo.get("wedged", false)):
			print("[psxrb] FAIL the control matched: this check cannot tell a group from no group")
			fail = 1
	print("[psxrb] %s" % ("PASS" if fail == 0 else "FAIL"))
	return fail
