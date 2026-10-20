## Super Game Boy rollback probe: netplay_spike.gd for bsnes running a Game Boy
## game through the adapter, with up to four players on the Super Multitap.
##
## Same legs and oracle as netplay_spike (phase A, savestate, reload, replay;
## --spike-rollback posts confirmations LAGGED so every input change is first
## mispredicted, then rewound). Diff the [crc] lines of two runs to compare
## processes. Added over the spike:
##   --spike-sgb=<SGB1.sfc|SGB2.sfc>  load through the 'sgb' subsystem, Game Boy ROM first
##   --spike-ports=<mask>             netplay port mask, decimal (15 = all four)
##   --spike-device=<port>:<id>       SetControllerPortDevice BEFORE StartContent, so the
##                                    core has it from frame 0 (257 = bsnes's Multitap)
##   --spike-script=bomberman-battle[:seed]   Bomberman GB (USA, Europe): title, BATTLE,
##                                    all four players ON (DOWN on each pad), then every
##                                    pad wanders and drops bombs from frame 1900. Rounds
##                                    cycle by themselves, so the battle runs as long as asked.
##   --spike-seq=<file>               the same timeline from a file:
##                                    "press <start> <len> <port> <BTN+BTN>", "play <start> <mask> <seed>"
##   --spike-shots=<dir> --spike-shot-every=<n>   PNG every n frames in phase A
##   --spike-phase-a-only             stop at --spike-end without the reload leg
##   --spike-dump-at=<f> --spike-dump-out=<path>  (and --spike-dump-b-*) whole state to a file
##
##   godot --headless --path RetroXR res://Tools/netplay/sgb_rollback_probe.tscn -- \
##     "--spike-rom=$HOME/retroxr/roms/gb/Bomberman GB (USA, Europe) (SGB Enhanced).gb" \
##     "--spike-sgb=$HOME/retroxr/libretro/system/bsnes/SGB1.sfc" \
##     --spike-ports=15 --spike-device=0:1 --spike-device=1:257 \
##     --spike-script=bomberman-battle --spike-phase-a-only --spike-end=4800 \
##     --spike-crc-interval=10 --spike-timeout=400 \
##     --spike-option=bsnes_entropy=None --spike-option=bsnes_netplay_deterministic=enabled \
##     [--spike-rollback --spike-lag=3]
##
## THE ORACLE NEEDS RetroXR's bsnes FORK (~/libretro-cores-retroxr/bsnes-libretro,
## branch retroxr). Stock bsnes publishes no memory, so the only checksum is
## --spike-crc-from-state, and two processes never agree on a state: Random is
## seeded from clock() and SameBoy stamps time(NULL) into its RTC block. With
## bsnes_netplay_deterministic the fork publishes a memory map (SNES WRAM plus the
## Game Boy's RAM) and the default RAM checksum works across processes.
##
## Run against a scratch --spike-root (cores/, system/bsnes/SGB*.sfc, core_options/):
## the core writes its whole option set back to core_options/bsnes.opt at shutdown.
## A rollback run that stops advancing with no error is usually an assert() inside
## the core, parked on a message box nobody can see; attach gdb to read it.
extends Node3D

static var _home := OS.get_environment("HOME") if OS.get_name() == "Linux" \
		else OS.get_environment("USERPROFILE").replace("\\", "/")

## The menu walk to a four-player battle, then wandering from 1900. Frames are
## from a cold start on SGB1 (the adapter's logo, then the game's border at ~660).
const BOMBERMAN_BATTLE := """
press 800 6 0 START
press 950 4 0 DOWN
press 970 4 0 DOWN
press 990 4 0 DOWN
press 1020 6 0 START
press 1250 8 1 DOWN
press 1300 8 2 DOWN
press 1350 8 3 DOWN
press 1420 6 0 START
press 1600 6 0 START
press 1800 6 0 START
play 1900 15 {seed}
"""

const BTN := {"B": 0, "Y": 1, "SELECT": 2, "START": 3, "UP": 4, "DOWN": 5,
	"LEFT": 6, "RIGHT": 7, "A": 8, "X": 9, "L": 10, "R": 11}

var root_dir := _home + "/retroxr/libretro"
var core := "bsnes"
var rom := ""
var sgb_rom := ""
var port_mask := 1
var devices: Dictionary = {}
var seq: Array = []
var play_from := -1
var play_mask := 0
var play_seed := 1
var shots_dir := ""
var shot_every := 0
var _next_shot := 0
var phase_a_only := false
var dump_at := -1
var dump_out := ""
var _dumping := false
var dump_b_at := -1
var dump_b_out := ""
var rollback := false
var crc_interval := 60
var timeout_s := 110.0
var options: Dictionary = {}
var rollback_lag := 3
const STARTUP_CONFIRMED := 8
var selfload := false
var crc_state := false
var crc_from_state := false
const ROLLBACK_MAX_AHEAD := 8

var save_at := 600
var END_AT := 1800

var _lib: Node = null
var _next_feed := 0
var _crc_a := {}
var _crc_b := {}
var _phase := "A"
var _state_data := PackedByteArray()
var _state_frame := -1
var _saved := false
var _done := false
var _selfloading := false
var _t0 := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		arg = arg.strip_edges()
		if arg.begins_with("--spike-core="):
			core = arg.trim_prefix("--spike-core=")
		elif arg.begins_with("--spike-rom="):
			rom = arg.trim_prefix("--spike-rom=")
		elif arg.begins_with("--spike-sgb="):
			sgb_rom = arg.trim_prefix("--spike-sgb=")
		elif arg.begins_with("--spike-ports="):
			port_mask = int(arg.trim_prefix("--spike-ports="))
		elif arg.begins_with("--spike-device="):
			var pd := arg.trim_prefix("--spike-device=").split(":")
			devices[int(pd[0])] = int(pd[1])
		elif arg.begins_with("--spike-seq="):
			_load_seq(arg.trim_prefix("--spike-seq="))
		elif arg.begins_with("--spike-script="):
			var spec := arg.trim_prefix("--spike-script=").split(":")
			if spec[0] == "bomberman-battle":
				_parse_seq(BOMBERMAN_BATTLE.replace("{seed}", spec[1] if spec.size() > 1 else "1"))
			else:
				print("[spike] unknown script %s" % spec[0])
		elif arg.begins_with("--spike-shots="):
			shots_dir = arg.trim_prefix("--spike-shots=")
		elif arg.begins_with("--spike-shot-every="):
			shot_every = int(arg.trim_prefix("--spike-shot-every="))
		elif arg.begins_with("--spike-dump-at="):
			dump_at = int(arg.trim_prefix("--spike-dump-at="))
		elif arg.begins_with("--spike-dump-out="):
			dump_out = arg.trim_prefix("--spike-dump-out=")
		elif arg.begins_with("--spike-dump-b-at="):
			dump_b_at = int(arg.trim_prefix("--spike-dump-b-at="))
		elif arg.begins_with("--spike-dump-b-out="):
			dump_b_out = arg.trim_prefix("--spike-dump-b-out=")
		elif arg == "--spike-phase-a-only":
			phase_a_only = true
		elif arg == "--spike-crc-state":
			crc_state = true
		elif arg.begins_with("--spike-root="):
			root_dir = arg.trim_prefix("--spike-root=")
		elif arg.begins_with("--spike-save-at="):
			save_at = int(arg.trim_prefix("--spike-save-at="))
		elif arg.begins_with("--spike-crc-interval="):
			crc_interval = int(arg.trim_prefix("--spike-crc-interval="))
		elif arg.begins_with("--spike-option="):
			var kv := arg.trim_prefix("--spike-option=").split("=", true, 1)
			if kv.size() == 2:
				options[kv[0]] = kv[1]
		elif arg.begins_with("--spike-timeout="):
			timeout_s = float(arg.trim_prefix("--spike-timeout="))
		elif arg == "--spike-rollback":
			rollback = true
		elif arg == "--spike-crc-from-state":
			crc_from_state = true
		elif arg.begins_with("--spike-end="):
			END_AT = int(arg.trim_prefix("--spike-end="))
		elif arg == "--spike-selfload":
			selfload = true
		elif arg.begins_with("--spike-lag="):
			rollback_lag = int(arg.trim_prefix("--spike-lag="))
	get_tree().create_timer(timeout_s).timeout.connect(func() -> void:
		var f: int = _lib.GetFrameCount() if _lib else -1
		print("[spike] TIMEOUT phase=%s frame=%d" % [_phase, f])
		get_tree().quit(1))
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	add_child(_lib)
	_lib.connect("netplay_crc", _on_crc)
	_lib.connect("savestate_ready", _on_state_ready)
	_lib.connect("savestate_loaded", _on_state_loaded)
	_lib.SetNetplayMode(true, port_mask, 0)
	if crc_state or crc_from_state:
		_lib.SetNetplayCrcFromState(true)
	_lib.SetNetplayCrcInterval(crc_interval)
	_lib.SetNetplayRollback(rollback, 0, ROLLBACK_MAX_AHEAD)
	for k: Variant in options:
		_lib.SetCoreOption(str(k), str(options[k]))
		print("[spike] option %s = %s" % [str(k), str(options[k])])
	for p: Variant in devices:
		_lib.SetControllerPortDevice(int(p), int(devices[p]))
		print("[spike] port %d device %d" % [int(p), int(devices[p])])
	_t0 = Time.get_ticks_msec()
	if sgb_rom.is_empty():
		_lib.StartContent(root_dir, core, rom)
	else:
		_lib.StartSubsystemContent(root_dir, core, rom, "sgb", PackedStringArray([rom, sgb_rom]))
	print("[spike] started %s / %s%s%s ports=%d" % [core, rom.get_file(),
		(" + " + sgb_rom.get_file()) if not sgb_rom.is_empty() else "",
		(" (ROLLBACK lag %d)" % rollback_lag) if rollback else " (LOCKSTEP)", port_mask])


func _load_seq(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("[spike] cannot read seq %s" % path)
		return
	_parse_seq(f.get_as_text())


func _parse_seq(text: String) -> void:
	for line: String in text.split("\n", false):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var w := line.split(" ", false)
		if w[0] == "press" and w.size() >= 5:
			var bits := 0
			for b: String in w[4].split("+"):
				bits |= 1 << int(BTN[b])
			seq.append([int(w[1]), int(w[2]), int(w[3]), bits])
		elif w[0] == "play" and w.size() >= 4:
			play_from = int(w[1])
			play_mask = int(w[2])
			play_seed = int(w[3])
	print("[spike] seq: %d presses, play from %d mask %d seed %d" % [seq.size(), play_from, play_mask, play_seed])


## The game's spike's default timeline (used when no --spike-seq is given).
func _input_for_frame(f: int) -> int:
	var btn := 0
	if (f >= 180 and f < 195) or (f >= 300 and f < 320):
		btn |= 1 << 3
	if f >= 400:
		btn |= 1 << 7
		if (f % 90) < 25:
			btn |= 1 << 8
		if (f % 51) < 10:
			btn |= 1 << 0
	return btn


## Deterministic wandering for one player: a new direction every 20-ish frames
## (offset per port so the players never change on the same frame), a bomb now
## and then. Each change is a misprediction under rollback.
func _play(f: int, port: int) -> int:
	var t := f - play_from + port * 7
	var seg := t / 20
	var h := (seg * 73856093) ^ ((port + 1) * 19349663) ^ (play_seed * 83492791)
	h = (h ^ (h >> 13)) & 0x7fffffff
	var btn := 0
	match h % 5:
		1: btn |= 1 << BTN["UP"]
		2: btn |= 1 << BTN["DOWN"]
		3: btn |= 1 << BTN["LEFT"]
		4: btn |= 1 << BTN["RIGHT"]
	if ((t + port * 13) % 67) < 4:
		btn |= 1 << BTN["A"]
	return btn


func _input_for_port(f: int, port: int) -> int:
	if seq.is_empty() and play_from < 0:
		return _input_for_frame(f) if port == 0 else 0
	var btn := 0
	for s: Array in seq:
		if port == s[2] and f >= s[0] and f < s[0] + s[1]:
			btn |= int(s[3])
	if play_from >= 0 and f >= play_from and (play_mask & (1 << port)):
		btn |= _play(f, port)
	return btn


func _flat(f: int) -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.resize(20)
	for p in 4:
		if port_mask & (1 << p):
			arr[p * 5] = _input_for_port(f, p)
	return arr


func _process(_delta: float) -> void:
	if _done or _lib == null or _phase == "B_LOADING":
		return
	var cur: int = _lib.GetFrameCount()
	if rollback:
		var confirm_to: int = cur if cur < STARTUP_CONFIRMED else cur - rollback_lag
		while _next_feed <= confirm_to:
			_lib.PostNetplayInputs(_next_feed, _flat(_next_feed))
			_next_feed += 1
	else:
		var cap := dump_at if dump_at >= 0 else 1 << 30
		while _next_feed < mini(cur + 90, cap):
			_lib.PostNetplayInputs(_next_feed, _flat(_next_feed))
			_next_feed += 1
	if _phase == "A" and not shots_dir.is_empty() and shot_every > 0 and cur >= _next_shot:
		_next_shot = cur - cur % shot_every + shot_every
		var img: Image = _lib.GetVideoImage()
		if img != null and not img.is_empty():
			var c: Image = img.duplicate()
			c.convert(Image.FORMAT_RGB8)
			c.save_png(shots_dir.path_join("f%05d.png" % cur))
	if dump_at >= 0 and not _dumping and cur == dump_at:
		_dumping = true
		_lib.RequestSaveState()
	if _phase == "A" and not _saved and cur >= save_at and not phase_a_only:
		_saved = true
		_lib.RequestSaveState()
	elif _phase == "B" and cur >= END_AT + 30:
		_finish()


func _on_crc(frame: int, crc: int) -> void:
	if _phase == "A":
		print("[crc] %d %08x" % [frame, crc])
		_crc_a[frame] = crc
		if frame >= END_AT and phase_a_only:
			_finish_a()
		elif frame >= END_AT and _state_frame >= 0:
			_phase = "B_LOADING"
			print("[spike] phase A done (%d checkpoints) -- loading state @%d" % [_crc_a.size(), _state_frame])
			_lib.RequestLoadState(_state_data, _state_frame)
	elif _phase == "B":
		_crc_b[frame] = crc
		print("[crcB] %d %08x" % [frame, crc])


func _on_state_ready(data: PackedByteArray, frame: int) -> void:
	if _dumping and dump_at >= 0:
		var fa := FileAccess.open(dump_out, FileAccess.WRITE)
		fa.store_buffer(data)
		fa.close()
		print("[spike] dumped %d bytes at frame %d to %s" % [data.size(), frame, dump_out])
		dump_at = -1
		return
	print("[spike] savestate captured: %d bytes at frame %d" % [data.size(), frame])
	if data.is_empty():
		print("[spike] RESULT=FAIL (core has no savestate support)")
		get_tree().quit(1)
		return
	_state_data = data
	_state_frame = frame
	if selfload and _phase == "A":
		_selfloading = true
		_lib.RequestLoadState(data, frame)


func _on_state_loaded(ok: bool) -> void:
	if _selfloading:
		_selfloading = false
		print("[spike] self-load at %d ok=%s -- carrying on in phase A" % [_state_frame, ok])
		_next_feed = _state_frame
		return
	print("[spike] state loaded ok=%s -- replaying from %d" % [ok, _state_frame])
	if not ok:
		print("[spike] RESULT=FAIL (unserialize failed)")
		get_tree().quit(1)
		return
	_next_feed = _state_frame
	if dump_b_at >= 0:
		dump_at = dump_b_at
		dump_out = dump_b_out
		_dumping = false
	_phase = "B"


func _report_rollbacks() -> bool:
	if not rollback:
		return true
	var rb: int = _lib.GetNetplayRollbackCount()
	print("[spike] rollbacks performed: %d" % rb)
	return rb > 0 or rollback_lag == 0


func _finish_a() -> void:
	_done = true
	var ok := _report_rollbacks()
	print("[spike] phase A only: %d checkpoints to frame %d in %.1f s" % [_crc_a.size(), END_AT,
		(Time.get_ticks_msec() - _t0) / 1000.0])
	print("[spike] RESULT=%s" % ("PASS" if ok else "FAIL"))
	_lib.StopContent()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)


func _finish() -> void:
	_done = true
	var mismatches := 0
	var compared := 0
	for f: int in _crc_b:
		if f <= _state_frame or f > END_AT:
			continue
		if _crc_a.has(f):
			compared += 1
			if int(_crc_a[f]) != int(_crc_b[f]):
				mismatches += 1
				if mismatches <= 10:
					print("[spike] MISMATCH frame %d: ref=%08x here=%08x"
						% [f, int(_crc_a[f]), int(_crc_b[f])])
	var ok := compared >= 15 and mismatches == 0
	print("[spike] compared %d CRC checkpoints after reload, %d mismatches" % [compared, mismatches])
	if not _report_rollbacks():
		ok = false
	print("[spike] RESULT=%s" % ("PASS" if ok else "FAIL"))
	_lib.StopContent()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)
