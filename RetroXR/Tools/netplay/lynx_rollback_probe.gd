## Rollback netplay over a ComLynx cable, with the real core and a real game.
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/lynx_rollback_probe.tscn -- --leg=rb
##   "$godot" --headless --path RetroXR res://Tools/netplay/lynx_rollback_probe.tscn -- --leg=ref
##   "$godot" --headless --path RetroXR res://Tools/netplay/lynx_rollback_probe.tscn -- --leg=solo
##   "$godot" --headless --path RetroXR res://Tools/netplay/lynx_rollback_probe.tscn -- --leg=compare
##
## ONE leg per process, in that order (ref replays what rb recorded), and never
## two at once. Options: --rom=<.lnx> (default Warbirds), --delay=N frames of
## confirmation latency for the far player (default 5), --frames=N.
##
## A probe, not a test: it wants mednafen_lynx (RetroXR's fork, which carries
## ComLynx and lynx_fixed_frames), the Lynx BIOS and a commercial ROM.
##
## WHAT IT PROVES. Two Lynxes on one cable, as a netplay session runs them:
## fixed-length frames on, the second unit switched on seven frames after the
## first and the cable joined five frames later, CRCs of both machines' RAM every
## 30 frames.
##
##   rb    group rollback (Wrapper::NetplayGroupIteration). Machine 0's pad is
##         this player's, sampled live; machine 1's is the far player's and its
##         confirmations arrive --delay frames late, so every press and release
##         on it is first mispredicted and then rolled back -- with the cable
##         carrying bytes the whole time. Records the exact inputs every frame
##         ran with.
##   ref   the same timeline in plain lockstep: every frame run once, with the
##         right inputs, nothing ever rewound. The truth.
##   solo  rollback WITHOUT the group, each core rewinding on its own, as it
##         would with the cable ignored. The control: it must NOT match ref (or
##         must wedge), or the check below cannot tell a group from no group.
##   compare  rb == ref at every checkpoint, rb actually rolled back, the cable
##         actually carried traffic, and solo != ref.
extends Node

const CORE := "mednafen_lynx"
const OUT_DIR := "res://probe_out/lynx/rollback"
const CRC_INTERVAL := 30
var _crc_interval := CRC_INTERVAL
const MAX_AHEAD := 8
## The second unit's power-on, and the frame the cable joins (see
## Wrapper::SetNetplayPowerOnFrame): identical units switched on together
## collide on every byte, so a session staggers them.
const POWER_ON_1 := 7
## The frame the cable joins. Past anything the group can run before the first
## confirmation (max_ahead from frame -1), so the change is scheduled before
## its frame can come round: a cable change that lands late lands on a
## different frame on every peer.
const JOIN := 12
const BUTTON_B := 1 << 0

var _leg := "rb"
var _rom := "Z:/roms/atarilynx/Warbirds (USA, Europe).lnx"
var _delay := 5
var _end := 2800
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
		elif arg.begins_with("--frames="):
			_end = maxi(200, int(arg.substr(9)))
	get_tree().create_timer(240.0).timeout.connect(_on_timeout)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if _leg == "compare":
		get_tree().quit(_compare())
		return
	await _run()


## Warbirds' two-player start, the sequence docs/dev/lynx-link.md gives, in
## flight by about frame 2725.
## Machine 0's presses come from here too, fed live on the rollback leg.
func _script(machine: int, frame: int) -> int:
	var presses: Array = [
		[0, 1537], [1, 1759], [0, 2081], [1, 2403],
	]
	for p: Array in presses:
		if int(p[0]) == machine and frame >= int(p[1]) and frame < int(p[1]) + 10:
			return BUTTON_B
	return 0


func _run() -> void:
	if not FileAccess.file_exists(_rom):
		print("[lynxrb] SKIP no ROM at %s" % _rom)
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
		lib.SetNetplayRollback(rollback, 1 if (rollback and i == 0) else 0, MAX_AHEAD)
		lib.SetNetplayCrcInterval(_crc_interval)
		lib.SetNetplayPowerOnFrame(0 if i == 0 else POWER_ON_1)
		lib.SetNetplayMode(true, 1, 0)
	if _leg == "rb":
		print("[lynxrb] group: %s" % _m[0].SetNetplayRollbackGroup([_m[1]], PackedInt32Array([0, 0])))
	if _leg == "ref":
		_load_timeline()
	for lib in _m:
		lib.StartContent(root, CORE, _rom)
	# A core refuses a scheduled cable change until it has loaded, which happens
	# on its own thread; nothing is confirmed until then, so no frame near JOIN
	# can have run yet.
	while _m[0].GetCoreIdentity().is_empty() or _m[1].GetCoreIdentity().is_empty():
		await get_tree().process_frame
	if _leg == "rb":
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
			print("[lynxrb] WEDGED at frame %d/%d" % [_m[0].GetFrameCount(), _m[1].GetFrameCount()])
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
	if not _joined:
		if front < JOIN:
			while _posted < JOIN:
				_post_both(_posted)
				_posted += 1
			return
		if _m[0].GetFrameCount() != JOIN or _m[1].GetFrameCount() != JOIN:
			return
		print("[lynxrb] cable joined @%d: %s" % [JOIN, _m[0].LinkConnectGroup([_m[1]], PackedInt32Array([0, 0]))])
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
	if _leg == "solo" and not _joined and f0 >= JOIN and _m[1].GetFrameCount() >= JOIN:
		print("[lynxrb] cable joined: %s" % _m[0].LinkConnectGroup([_m[1]], PackedInt32Array([0, 0])))
		_joined = true
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
	print("[lynxrb] %s: frames %d/%d, crcs %d/%d, rollbacks %d/%d, traffic %s%s" % [
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
		print("[lynxrb] FAIL run --leg=rb first")
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


## lynx_fixed_frames on for this run only. The .opt file is the player's real
## one (StartContent reads nothing else), so it is put back byte for byte.
func _pin_options(root: String) -> void:
	_opt_path = CoreOptionsStore.opt_path(root, CORE)
	_opt_existed = FileAccess.file_exists(_opt_path)
	if _opt_existed:
		_opt_bytes = FileAccess.get_file_as_bytes(_opt_path)
	CoreOptionsStore.merge_values(root, CORE, {"lynx_fixed_frames": "enabled"})


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
	print("[lynxrb] TIMEOUT in leg %s at frames %s" % [_leg,
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
		print("[lynxrb] FAIL run --leg=rb and --leg=ref first")
		return 1
	var fail := 0
	var d := _diff(rb, ref)
	print("[lynxrb] rb vs ref: %d checkpoints equal, %d differ%s" % [d[0], d[1],
		"" if d[2] < 0 else " (first at frame %d)" % d[2]])
	if d[1] != 0 or d[0] < 2 * (int(ref["end"]) / CRC_INTERVAL) - 4:
		print("[lynxrb] FAIL rollback did not reproduce the lockstep timeline")
		fail = 1
	var rolls := int(rb["stats"][0].get("rollback_count", 0)) + int(rb["stats"][1].get("rollback_count", 0))
	print("[lynxrb] rb rolled back %d times (deepest %d frames)" % [rolls,
		maxi(int(rb["stats"][0].get("max_depth", 0)), int(rb["stats"][1].get("max_depth", 0)))])
	if rolls < 4:
		print("[lynxrb] FAIL too few rollbacks to have tested anything")
		fail = 1
	var t: Array = rb["traffic"]
	print("[lynxrb] cable: sent %s/%s received %s/%s" % [t[0][0], t[1][0], t[0][1], t[1][1]])
	if int(t[0][0]) < 100 or int(t[1][0]) < 100:
		print("[lynxrb] FAIL the cable carried no conversation")
		fail = 1
	if solo.is_empty():
		print("[lynxrb] NOTE no solo leg to compare")
	else:
		var s := _diff(solo, ref)
		print("[lynxrb] solo vs ref: %d equal, %d differ, wedged=%s" % [s[0], s[1], str(solo.get("wedged", false))])
		if s[1] == 0 and not bool(solo.get("wedged", false)):
			print("[lynxrb] FAIL the control matched: this check cannot tell a group from no group")
			fail = 1
	print("[lynxrb] %s" % ("PASS" if fail == 0 else "FAIL"))
	return fail
