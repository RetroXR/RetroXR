## An e-Reader card scanned under netplay, with the real core, BIOS and card.
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/ereader_rollback_probe.tscn -- --leg=ref
##   "$godot" --headless --path RetroXR res://Tools/netplay/ereader_rollback_probe.tscn -- --leg=rb
##   "$godot" --headless --path RetroXR res://Tools/netplay/ereader_rollback_probe.tscn -- --leg=join
##   "$godot" --headless --path RetroXR res://Tools/netplay/ereader_rollback_probe.tscn -- --leg=compare
##
## ONE leg per process, ref first (join loads the state ref took). Options:
## --core=<id> (default mgba), --tag=<name> to keep a second set of results
## apart (a control run on an older core), --roms=<data root roms dir>.
##
## A probe, not a test: it wants the e-Reader (USA) dump, its FLASH save and
## Air Hockey-e strip 1.
##
## WHAT IT PROVES. The card goes in the way a session puts it in: ScheduleDiscOp
## on one frame, while the reader is asking for a card, and the scan that follows
## runs for a few hundred frames. CRCs are taken of the whole SAVESTATE (so the
## scanner block is in them) every 30 frames.
##
##   ref   lockstep, every frame run once with the right inputs. The truth. It
##         also snapshots the machine mid-scan for `join`.
##   rb    rollback: the pad is the far player's, confirmed --delay frames late,
##         and it keeps changing through the scan, so the scan is rewound and
##         replayed over and over.
##   join  a late joiner: a fresh core handed ref's mid-scan snapshot, then run
##         on in lockstep. It has never seen the card.
##   compare  rb == ref and join == ref at every checkpoint, rb really rolled
##         back, and the scan really happened (the state after it differs from
##         a run with no card -- checked by the screenshot, which is the oracle
##         for "read", see ereader_scan_probe).
##
## THE CONTROL is the same rb and join legs on a core that does not serialize
## the scanner (--core=<old build> --tag=old): they must NOT match, or the
## comparison cannot tell a scanner in the state from one left out of it.
extends Node

const OUT_DIR := "res://probe_out/ereader_netplay"
const CRC_INTERVAL := 30
const MAX_AHEAD := 10
const CARD_FRAME := 600
## Mid-scan: the reader shows "Now Reading..." from about frame 640.
var SNAP_FRAME := 630
const BTN_A := 1 << 8
const BTN_L := 1 << 10

var _leg := "ref"
var _tag := "new"
var _core := "mgba"
var _roms := ""
var _delay := 6
var _end := 1260
var _lib: Libretro = null
var _crcs := {}
var _posted := 0
var _snap := PackedByteArray()
var _snap_frame := -1
var _loaded := false
var _crc_state := true
var _no_card := false
var _stalled := 0
var _noise_from := 560
var _noise_end := 1000
var _last_f := -1


func _ready() -> void:
	_roms = OS.get_environment("USERPROFILE").path_join("retroxr/roms")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			_leg = arg.substr(6)
		elif arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--core="):
			_core = arg.substr(7)
		elif arg.begins_with("--roms="):
			_roms = arg.substr(7)
		elif arg == "--crc=ram":
			_crc_state = false
		elif arg.begins_with("--noise="):
			var span := arg.substr(8).split("-")
			_noise_from = int(span[0])
			_noise_end = int(span[1])
		elif arg.begins_with("--snap="):
			SNAP_FRAME = int(arg.substr(7))
		elif arg == "--no-card":
			_no_card = true
		elif arg.begins_with("--delay="):
			_delay = clampi(int(arg.substr(8)), 1, MAX_AHEAD - 2)
	get_tree().create_timer(240.0).timeout.connect(_on_timeout)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if _leg == "compare":
		get_tree().quit(_compare())
		return
	await _run()


func _rom() -> String:
	return _roms.path_join("gba/e-Reader (USA).gba")


func _card() -> String:
	return _roms.path_join("ereader/Air Hockey-e - 00-B000 (USA) (Promo) (Strip 1).raw")


## The far player's pad. Two A presses walk the reader to its card-read screen
## (the timings ereader_scan_probe uses); the L taps after it do nothing to the
## reader and exist to be MISPREDICTED -- each one is a rollback through the scan.
func _script(frame: int) -> int:
	if (frame >= 360 and frame < 372) or (frame >= 450 and frame < 462):
		return BTN_A
	if frame >= _noise_from and frame < _noise_end and (frame % 23) < 4:
		return BTN_L
	return 0


func _run() -> void:
	for path in [_rom(), _card()]:
		if not FileAccess.file_exists(path):
			print("[erdnp] SKIP missing %s" % path)
			get_tree().quit(0)
			return
	var root := CoreDownloadManager.default_core_root()
	_lib = Libretro.new()
	add_child(_lib)
	_lib.netplay_crc.connect(func(frame: int, crc: int) -> void: _crcs[str(frame)] = crc)
	_lib.savestate_ready.connect(_on_snap)
	_lib.savestate_loaded.connect(func(ok: bool) -> void:
		_loaded = ok
		print("[erdnp] snapshot loaded: %s" % ok))
	_lib.SetSramPath(_roms.path_join("gba/e-Reader (USA).sav").replace(".sav", ".erdnp.sav"))
	_copy_sram()
	_lib.SetCoreOption("mgba_use_bios", "ON")
	_lib.SetCoreOption("mgba_skip_bios", "OFF")
	_lib.SetNetplayRollback(_leg == "rb", 0, MAX_AHEAD)
	_lib.SetNetplayCrcInterval(CRC_INTERVAL)
	_lib.SetNetplayCrcFromState(_crc_state)
	_lib.SetNetplayMode(true, 1, 0)
	_lib.StartContent(root, _core, _rom())
	while _lib.GetCoreIdentity().is_empty():
		await get_tree().process_frame

	if _leg == "join":
		if not await _join():
			return
	elif not _no_card:
		# Before frame 0 is even posted, so the op cannot land late.
		_lib.ScheduleDiscOp(CARD_FRAME, 1, 0, _card())

	var last := -1
	var still := 0
	while _lib.GetFrameCount() < _end:
		await get_tree().process_frame
		_drive()
		if _leg in ["ref", "reload"] and _snap.is_empty() and _snap_frame < 0 and _lib.GetFrameCount() >= SNAP_FRAME:
			_snap_frame = 0
			_lib.RequestSaveState()
		var f := _lib.GetFrameCount()
		still = still + 1 if f == last else 0
		last = f
		if still > 2000:
			print("[erdnp] WEDGED at frame %d" % f)
			break
	for _i in range(60):
		_drive()
		await get_tree().process_frame
	_finish()


## Lockstep keeps a few frames posted ahead; rollback confirms each frame only
## once the core has speculated `_delay` frames past it.
func _drive() -> void:
	var f := _lib.GetFrameCount()
	var upto := f + 4 if _leg != "rb" else f - _delay + 1
	# A core holding at a scheduled disc frame waits for THAT frame to be
	# confirmed, which a network would get round to; so confirm on.
	_stalled = _stalled + 1 if f == _last_f else 0
	_last_f = f
	if _stalled > 3:
		upto = maxi(upto, f + 1)
	while _posted < upto and _posted < _end + 64:
		_lib.PostNetplayInputs(_posted, _frame(_script(_posted)))
		_posted += 1


func _frame(buttons: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(20)
	a[0] = buttons
	return a


func _on_snap(data: PackedByteArray, frame: int) -> void:
	_snap = data
	_snap_frame = frame
	if _leg == "reload":
		# The same bytes straight back into the machine they came from: what a
		# rollback does to a running core, with no rewind at all.
		_lib.RequestLoadState(data, frame)
		_posted = frame
		print("[erdnp] reloaded own snapshot @frame %d" % frame)
		return
	var fa := FileAccess.open(OUT_DIR + "/snap_%s.bin" % _tag, FileAccess.WRITE)
	fa.store_buffer(data)
	fa.close()
	print("[erdnp] snapshot %d bytes @frame %d" % [data.size(), frame])


func _join() -> bool:
	var meta: Dictionary = _read("ref")
	var data := FileAccess.get_file_as_bytes(OUT_DIR + "/snap_%s.bin" % _tag)
	if data.is_empty() or meta.is_empty():
		print("[erdnp] FAIL run --leg=ref --tag=%s first" % _tag)
		get_tree().quit(1)
		return false
	var frame := int(meta.get("snap_frame", -1))
	_lib.RequestLoadState(data, frame)
	for _i in range(600):
		await get_tree().process_frame
		if _loaded:
			break
	if not _loaded:
		print("[erdnp] FAIL the snapshot did not load")
		get_tree().quit(1)
		return false
	_posted = frame
	return true


## The e-Reader writes its FLASH as it runs, so each leg starts from its own
## copy of the player's save and never touches the real one.
func _copy_sram() -> void:
	var src := _roms.path_join("gba/e-Reader (USA).sav")
	var dst := src.replace(".sav", ".erdnp.sav")
	if FileAccess.file_exists(src):
		var fa := FileAccess.open(dst, FileAccess.WRITE)
		fa.store_buffer(FileAccess.get_file_as_bytes(src))
		fa.close()


func _finish() -> void:
	var stats: Dictionary = _lib.GetNetplayRollbackStats()
	var img := _lib.GetVideoImage()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		img.save_png(OUT_DIR + "/%s_%s.png" % [_leg, _tag])
	var out := {
		"leg": _leg, "tag": _tag, "core": _core, "end": _end, "crcs": _crcs,
		"stats": stats, "snap_frame": _snap_frame,
	}
	var fa := FileAccess.open(OUT_DIR + "/%s_%s.json" % [_leg, _tag], FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("[erdnp] %s/%s: frame %d, crcs %d, rollbacks %d (deepest %d)" % [
		_leg, _tag, _lib.GetFrameCount(), _crcs.size(),
		int(stats.get("rollback_count", 0)), int(stats.get("max_depth", 0))])
	_lib.StopContent()
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.remove_absolute(_roms.path_join("gba/e-Reader (USA).erdnp.sav"))
	get_tree().quit(0)


func _on_timeout() -> void:
	print("[erdnp] TIMEOUT in leg %s at frame %d" % [_leg, _lib.GetFrameCount() if _lib else -1])
	get_tree().quit(1)


func _read(leg: String) -> Dictionary:
	var path := OUT_DIR + "/%s_%s.json" % [leg, _tag]
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}


## [equal, differ, first differing frame] over the checkpoints both have.
func _diff(a: Dictionary, b: Dictionary, from := 0) -> Array:
	var same := 0
	var differ := 0
	var first := -1
	for key: String in a["crcs"]:
		if int(key) < from or not b["crcs"].has(key):
			continue
		if int(a["crcs"][key]) == int(b["crcs"][key]):
			same += 1
		else:
			differ += 1
			if first < 0 or int(key) < first:
				first = int(key)
	return [same, differ, first]


func _compare() -> int:
	var ref := _read("ref")
	var rb := _read("rb")
	var join := _read("join")
	if ref.is_empty() or rb.is_empty() or join.is_empty():
		print("[erdnp] FAIL run ref, rb and join with --tag=%s first" % _tag)
		return 1
	var fail := 0
	var d := _diff(rb, ref)
	var after := _diff(rb, ref, CARD_FRAME)
	print("[erdnp] %s rb vs ref: %d equal, %d differ%s; %d checkpoints after the card" % [
		_tag, d[0], d[1], "" if d[2] < 0 else " (first at frame %d)" % d[2], after[0] + after[1]])
	if d[1] != 0 or after[0] < 15:
		fail = 1
	var rolls := int(rb["stats"].get("rollback_count", 0))
	print("[erdnp] %s rb rolled back %d times (deepest %d)" % [_tag, rolls,
		int(rb["stats"].get("max_depth", 0))])
	if rolls < 10:
		print("[erdnp] FAIL too few rollbacks to have tested anything")
		fail = 1
	var j := _diff(join, ref, int(join.get("snap_frame", 0)) if int(ref.get("snap_frame", 0)) <= 0 else int(ref["snap_frame"]))
	print("[erdnp] %s join vs ref: %d equal, %d differ%s" % [_tag, j[0], j[1],
		"" if j[2] < 0 else " (first at frame %d)" % j[2]])
	if j[1] != 0 or j[0] < 15:
		fail = 1
	print("[erdnp] %s %s" % [_tag, "PASS" if fail == 0 else "FAIL"])
	return fail
