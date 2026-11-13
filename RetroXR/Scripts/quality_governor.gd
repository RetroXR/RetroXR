extends Node
## Holds a headset's room at the display rate by stepping quality down, one notch at a time, only when it has to.
##
## The Starlight Arcade (242 objects) ran 33 fps on a Quest 3 at the player's settings and 70-72 at eye buffer 0.8,
## MSAA off and parts culled from ~31 px (release build, 2026-11-13, performance.md); the bedroom holds 72 at full
## quality. One setting for every room would cost the light rooms their quality, so this measures instead: once a
## room has finished arriving it watches the frame rate, and while that stays under the display rate it takes the
## next step below, mildest first. Nothing is saved -- the player's own settings are untouched and every room
## starts again from them -- and it never steps back up within a room (a room only gets heavier as things move in).
##
## Headset only. `vrsprobe.cfg` "no_governor": true is the control arm.

## Mildest first. `cull` is QualityManager.detail_cull_k, `eye` a ceiling on the eye buffer, `msaa` 0 is off.
const STEPS: Array[Dictionary] = [
	{"cull": 80.0},
	{"eye": 0.9},
	{"cull": 60.0},
	{"eye": 0.8},
	{"msaa": 0},
	{"cull": 40.0},
]
## A room has arrived when it has existed this long and its spawned objects have stopped coming for SETTLED_SEC.
const MIN_ROOM_SEC := 20.0
const SETTLED_SEC := 10.0
## Each verdict is the mean frame rate over this long, and a step waits this long to take effect before the next.
const WINDOW_SEC := 4.0
const AFTER_STEP_SEC := 3.0
## Under this share of the display rate (70 of 72), a window counts against the room; two in a row take a step.
## 0.94 stopped the Starlight Arcade at step 5, 69-70 fps, one step short of the 72 that step 6 holds.
const SLOW_SHARE := 0.97

static var enabled: bool = true

## The level each room needed last time, so a heavy room starts there instead of rediscovering it over its first
## minutes (the steps wait for the room to finish arriving: ~1.5 min of 35-45 fps in the Starlight Arcade, seen in
## the headset 2026-11-13). Keyed by the room's scene_id. Only ever raised; a cache, not a setting.
const LEVELS_PATH := "user://quality_governor.json"
var _room_id := ""

var qm: Node
var _room_since := 0.0
var _spawned := -1
var _spawned_since := 0.0
var _level := 0
var _wait := 0.0
var _frames := 0
var _elapsed := 0.0
var _slow := 0
var _armed := false


## A new room: start again from the player's own settings.
func room_entered(room_id: String) -> void:
	if _level > 0:
		_restore()
		print("[QualityGovernor] %s: back to the player's settings" % room_id)
	_level = 0
	_room_id = room_id
	var remembered := int(JsonStore.read_dict(LEVELS_PATH, "QualityGovernor").get(room_id, 0))
	# Off (vrsprobe "no_governor") means off: a remembered level applied anyway made the control arm a copy of the
	# governed one.
	if remembered > 0 and enabled:
		_apply_remembered.call_deferred(mini(remembered, STEPS.size()))
	_room_since = Time.get_ticks_msec() / 1000.0
	_spawned = -1
	_armed = false
	_slow = 0
	_frames = 0
	_elapsed = 0.0


func _process(delta: float) -> void:
	if not enabled or qm == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _armed:
		var count := get_tree().get_nodes_in_group("spawned").size()
		if count != _spawned:
			_spawned = count
			_spawned_since = now
		if _room_since > 0.0 and now - _room_since >= MIN_ROOM_SEC and now - _spawned_since >= SETTLED_SEC:
			_armed = true
			print("[QualityGovernor] room settled (%d objects): watching the frame rate" % count)
		return
	if _level >= STEPS.size():
		return
	if _wait > 0.0:
		_wait -= delta
		return
	_frames += 1
	_elapsed += delta
	if _elapsed < WINDOW_SEC:
		return
	var fps := _frames / _elapsed
	_frames = 0
	_elapsed = 0.0
	var rate: float = qm.call("effective_display_rate")
	if rate <= 0.0 or fps >= rate * SLOW_SHARE:
		_slow = 0
		return
	_slow += 1
	if _slow < 2:
		return
	_slow = 0
	_step(fps, rate)
	_wait = AFTER_STEP_SEC


func _apply_remembered(level: int) -> void:
	for i in level:
		var s: Dictionary = STEPS[_level]
		_level += 1
		_apply(s)
	print("[QualityGovernor] %s: starting at step %d/%d, where it settled last time" % [_room_id, _level, STEPS.size()])


func _apply(s: Dictionary) -> void:
	if s.has("cull"):
		qm.call("set_runtime_detail_cull", float(s["cull"]))
	if s.has("eye"):
		qm.call("set_runtime_eye_ceiling", float(s["eye"]))
	if s.has("msaa"):
		get_tree().root.msaa_3d = int(s["msaa"]) as Viewport.MSAA


func _remember() -> void:
	if _room_id.is_empty():
		return
	var levels := JsonStore.read_dict(LEVELS_PATH, "QualityGovernor")
	if int(levels.get(_room_id, 0)) < _level:
		levels[_room_id] = _level
		JsonStore.write_dict(LEVELS_PATH, levels, "QualityGovernor")


func _step(fps: float, rate: float) -> void:
	var s: Dictionary = STEPS[_level]
	_level += 1
	_apply(s)
	_remember()
	print("[QualityGovernor] %.1f fps of %.0f: step %d/%d %s" % [fps, rate, _level, STEPS.size(), JSON.stringify(s)])


func _restore() -> void:
	qm.call("set_runtime_detail_cull", -1.0)
	qm.call("set_runtime_eye_ceiling", -1.0)
	qm.call("apply_msaa")
