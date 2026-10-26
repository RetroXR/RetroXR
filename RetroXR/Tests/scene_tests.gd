extends Node

## Scene management, room transitions and the save gates around them.
##
##   godot --headless --path RetroXR res://Tests/scene_tests.tscn
##   godot --headless --path RetroXR res://Tests/scene_tests.tscn -- --only=autosave
##
## Exits non-zero on failure, so it can gate a commit.
##
## What it deliberately does NOT do is drive a real transition. change_scene()
## loads MainScene.tscn, whose SubViewports render every frame, and a headless run
## has no GPU to service them — the run hangs rather than fails. So the transition
## cases drive the state machine (_transitioning, _pending_scene_id) and assert the
## decisions it makes; what a loaded room looks like is a question for a probe with
## a display.
##
## SceneManager is an autoload holding the player's real active slots, and
## set_active_slot() writes user://scenes/prefs.json. Both are snapshotted at the
## start and put back at the end, so a red run cannot cost anyone their room.

const GROUPS := ["slots", "boot", "ready", "transition", "autosave", "reload", "carry", "restart", "overlap", "curtain", "fixture", "switch", "power", "cords", "vlc", "manifest", "stack"]
## A room id no real room has, for the carry: its file lives in a folder of its
## own under user://scenes, deleted at the end, never the player's.
const CARRY_ROOM := "__scene_selftest_carry"
const SCENE_MANAGER := preload("res://Scripts/Data/scene_manager.gd")
## Scratch slot ids, in the arcade's real directory — slot_dir() is derived from
## the room id and cannot be pointed somewhere safer.
const SLOT_A := "__scene_selftest_a"
const SLOT_B := "__scene_selftest_b"
const MANIFEST_FILE := "user://scenes/arcade/manifest.json"
## Every room's root script, which turns XR rendering on.
const XR_INIT := "res://Scripts/XR/xr_init.gd"

var _fail := 0
var _ran := 0
var _only := ""

var _saved_slots: Dictionary = {}
var _saved_scene_id := ""
var _saved_last_room := ""
var _saved_prefs_json := ""
var _had_prefs := false
var _saved_manifest_json := ""
var _had_manifest := false



## The pad-scene allowlist gates a value that can arrive from another machine, so
## it must not drift: every shipped controller scene whose script is a
## RetroController has to be on it.
##
## Read statically rather than by instantiating each scene — building the real
## pads headless starts threads and leaks RIDs, and the question here is about
## the manifest, not about runtime behaviour.
func _test_controller_scene_allowlist() -> void:
	var dir := "res://Scenes/Objects/controllers/"
	var scenes: Array[String] = []
	var stack: Array[String] = [dir]
	while not stack.is_empty():
		var at: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(at):
			stack.append(at.path_join(sub))
		for f in DirAccess.get_files_at(at):
			if f.ends_with(".tscn"):
				scenes.append(at.path_join(f))
	_ok(scenes.size() > 5, "controllers/the controller scenes were found")

	for path in scenes:
		var script_path := _scene_script_path(path)
		if script_path.is_empty() or not _extends_retro_controller(script_path):
			continue
		_ok(ScenePersistence.is_known_controller_scene(path),
			"controllers/%s is on the allowlist" % path.get_file())

	for listed: String in ScenePersistence.CONTROLLER_SCENES:
		_ok(ResourceLoader.exists(listed),
			"controllers/listed scene %s exists" % listed.get_file())

	_ok(not ScenePersistence.is_known_controller_scene(
			"res://Scenes/Objects/system.tscn"),
		"controllers/an unlisted scene is refused")


## The script a .tscn attaches to its root, read out of the file.
func _scene_script_path(scene_path: String) -> String:
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	var re := RegEx.create_from_string(
		'\\[ext_resource type="Script"[^\\]]*path="([^"]+)"')
	var m := re.search(text)
	return m.get_string(1) if m != null else ""


## The script a .tscn attaches to its ROOT node. Not simply the first one it names:
## a room lists its props' scripts as well.
func _root_script_path(scene_path: String) -> String:
	var text := FileAccess.get_file_as_string(scene_path)
	var root := RegEx.create_from_string("(?s)\\n\\[node [^\\n]*\\]\\n(.*?)(?:\\n\\[|$)").search(text)
	if root == null:
		return ""
	var ref := RegEx.create_from_string('(?m)^script = ExtResource\\("([^"]+)"\\)').search(root.get_string(1))
	if ref == null:
		return ""
	var res := RegEx.create_from_string(
		'\\[ext_resource type="Script"[^\\]]*path="([^"]+)"[^\\]]*id="%s"\\]' % ref.get_string(1)).search(text)
	return res.get_string(1) if res != null else ""


## Whether `script_path` is `base_path` or extends it, however far down.
func _script_extends(script_path: String, base_path: String) -> bool:
	var at: Script = null if script_path.is_empty() else load(script_path) as Script
	while at != null:
		if at.resource_path == base_path:
			return true
		at = at.get_base_script()
	return false


## Walk `extends` up the chain to see whether a script is a RetroController.
func _extends_retro_controller(script_path: String) -> bool:
	var seen := 0
	var at := script_path
	while not at.is_empty() and seen < 8:
		seen += 1
		var f := FileAccess.open(at, FileAccess.READ)
		if f == null:
			return false
		var text := f.get_as_text()
		f.close()
		var m := RegEx.create_from_string("(?m)^extends\\s+(\\w+)").search(text)
		if m == null:
			return false
		var base := m.get_string(1)
		if base == "RetroController":
			return true
		# Resolve the base class by its file, which is named for it in snake_case.
		var guess := "res://Scripts/Objects/controllers/%s.gd" % base.to_snake_case()
		at = guess if FileAccess.file_exists(guess) else ""
	return false

func _ready() -> void:
	# Restore BEFORE quitting: this suite writes the player's real prefs, arcade
	# manifest and active slots, so dying on the watchdog without this leaves
	# their room pointing at a slot the test invented.
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[test] TIMEOUT")
		_restore()
		get_tree().quit(1))
	get_tree().current_scene = self

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=")

	_snapshot()
	if _want_group("controllers"):
		_test_controller_scene_allowlist()
	if _want_group("slots"):
		_test_slots()
	if _want_group("boot"):
		_test_boot()
	if _want_group("ready"):
		_test_ready()
	if _want_group("transition"):
		_test_transition()
	if _want_group("autosave"):
		await _test_autosave()
	if _want_group("reload"):
		await _test_reload()
	if _want_group("carry"):
		await _test_carry()
	if _want_group("restart"):
		_test_restart_args()
	if _want_group("overlap"):
		await _test_overlap()
	if _want_group("curtain"):
		await _test_curtain()
	if _want_group("fixture"):
		await _test_fixture()
	if _want_group("switch"):
		await _test_switch()
	if _want_group("power"):
		await _test_power()
	if _want_group("cords"):
		await _test_cords()
	if _want_group("storage"):
		await _test_storage()
	if _want_group("plug"):
		_test_plug()
	if _want_group("strip"):
		await _test_power_strip()
	if _want_group("multitap"):
		await _test_multitap()
	if _want_group("stack"):
		await _test_stack()
	if _want_group("spacer"):
		await _test_spacer()
	if _want_group("cartbody"):
		await _test_cart_body()
	if _want_group("vlc"):
		_test_vlc()
	if _want_group("manifest"):
		_test_manifest()
	if _want_group("registry"):
		_test_save_registry()
	_restore()

	print("[test] %d cases, %s" % [_ran,
		"PASS" if _fail == 0 else "%d FAILURE(S)" % _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ── Which rooms keep slots, and what the active one is ────────────────────────

func _test_slots() -> void:
	# The authored rooms must never keep slots: a slot there restores a handful of
	# spawned objects into a room that already has its own contents. The bedroom
	# was one of them until it was emptied — it ships as bare walls and is now a
	# room the player furnishes, so it keeps slots like the arcade does.
	_ok(SceneManager.room_has_slots("arcade"), "slots/arcade has slots")
	_ok(SceneManager.room_has_slots("passthrough"), "slots/passthrough has slots")
	_ok(SceneManager.room_has_slots("bedroom"), "slots/bedroom has slots")
	for room in ["den", "test"]:
		_ok(not SceneManager.room_has_slots(room), "slots/%s has none" % room)
	_ok(not SceneManager.room_has_slots("nonesuch"), "slots/unknown room has none")

	# A room nobody has given a slot reads as clean rather than as empty string.
	SceneManager.active_slots.erase("den")
	_eq(SceneManager.active_slot("den"), "clean", "slots/default is clean")

	# Per room: setting one must not move another.
	SceneManager.set_active_slot(SLOT_A, "arcade")
	SceneManager.set_active_slot(SLOT_B, "passthrough")
	_eq(SceneManager.active_slot("arcade"), SLOT_A, "slots/arcade kept its own")
	_eq(SceneManager.active_slot("passthrough"), SLOT_B, "slots/passthrough kept its own")

	# active_slot_id means "the room I am in".
	SceneManager.current_scene_id = "passthrough"
	_eq(SceneManager.active_slot_id, SLOT_B, "slots/active_slot_id follows the room")
	SceneManager.current_scene_id = "arcade"
	_eq(SceneManager.active_slot_id, SLOT_A, "slots/active_slot_id follows back")

	# Assigning the property must not persist — that is set_active_slot's job, and
	# it is what stops a probe leaving its scratch id in the player's prefs.
	var before := FileAccess.get_file_as_string(SceneManager.PREFS_FILE)
	SceneManager.active_slot_id = "__not_persisted"
	_eq(FileAccess.get_file_as_string(SceneManager.PREFS_FILE), before,
		"slots/property assignment does not write prefs")
	SceneManager.active_slots["arcade"] = SLOT_A

	# The prefs file round-trips, and the single-room legacy key still migrates.
	SceneManager.save_prefs()
	SceneManager.active_slots.clear()
	SceneManager.load_prefs()
	_eq(SceneManager.active_slot("arcade"), SLOT_A, "slots/round-trips through prefs")

	var f := FileAccess.open(SceneManager.PREFS_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"last_slot_id": "legacy_id"}))
	f = null
	SceneManager.active_slots.clear()
	SceneManager.load_prefs()
	_eq(SceneManager.active_slot("arcade"), "legacy_id", "slots/legacy key migrates to arcade")


# ── Which room a launch opens in ──────────────────────────────────────────────

func _test_boot() -> void:
	var platform_default := "arcade" if OS.has_feature("android") else "bedroom"
	SceneManager.last_room_id = ""
	_eq(SceneManager.boot_room(), platform_default, "boot/nothing remembered opens the platform default")
	SceneManager.last_room_id = "den"
	_eq(SceneManager.boot_room(), "den", "boot/the remembered room opens")
	SceneManager.last_room_id = "nonesuch"
	_eq(SceneManager.boot_room(), platform_default, "boot/an unknown room opens the default")
	SceneManager.last_room_id = "passthrough"
	_eq(SceneManager.boot_room(),
		"passthrough" if SceneManager.is_passthrough_supported() else platform_default,
		"boot/passthrough opens only where it is supported")

	# Any room can be the one a launch opens in, and nothing before it marks the
	# viewport use_xr: the room's XRInit root does. Passthrough's root was a plain
	# Node3D that counted on the arcade having done it, so a launch remembered in
	# passthrough drew nothing at all in the headset (2026-10-21, on a Quest 3).
	for id in RoomCatalog.ids():
		_ok(_script_extends(_root_script_path(RoomCatalog.path_of(id)), XR_INIT),
			"boot/%s's root is an XRInit" % id)

	# Remembered when a room a transition installed stands with its contents in
	# place, not when it is asked for.
	SceneManager.last_room_id = "arcade"
	SceneManager.current_scene_id = "den"
	SceneManager._content_ready_scene_id = ""
	SceneManager._installed_room_id = ""
	SceneManager.notify_scene_content_ready("den")
	_eq(SceneManager.last_room_id, "arcade", "boot/a room run directly is not remembered")
	SceneManager._installed_room_id = "den"
	SceneManager._transitioning = true
	SceneManager.notify_scene_content_ready("den")
	_eq(SceneManager.last_room_id, "arcade", "boot/a room still arriving is not remembered")
	SceneManager._transitioning = false
	SceneManager.notify_scene_content_ready("den")
	_eq(SceneManager.last_room_id, "den", "boot/an arrived room is remembered")

	# Room and slots share prefs.json; writing either keeps the other.
	SceneManager.set_active_slot(SLOT_A, "arcade")
	SceneManager.active_slots.clear()
	SceneManager.last_room_id = ""
	SceneManager.load_prefs()
	_eq(SceneManager.last_room_id, "den", "boot/writing a slot keeps the room")
	SceneManager.current_scene_id = "bedroom"
	SceneManager._installed_room_id = "bedroom"
	SceneManager.notify_scene_content_ready("bedroom")
	SceneManager.active_slots.clear()
	SceneManager.last_room_id = ""
	SceneManager.load_prefs()
	_eq(SceneManager.last_room_id, "bedroom", "boot/the arrived room is persisted")
	_eq(SceneManager.active_slot("arcade"), SLOT_A, "boot/remembering a room keeps the slots")

	var f := FileAccess.open(SceneManager.PREFS_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"slots": {"arcade": SLOT_A}}))
	f = null
	SceneManager.last_room_id = "den"
	SceneManager.load_prefs()
	_eq(SceneManager.boot_room(), platform_default, "boot/prefs without a room open the default")


# ── The readiness gates every save is hung on ─────────────────────────────────

func _test_ready() -> void:
	SceneManager.current_scene_id = "arcade"
	SceneManager._transitioning = false
	SceneManager._content_ready_scene_id = ""

	_ok(SceneManager.is_room_ready("arcade"), "ready/current room with a scene is ready")
	_ok(not SceneManager.is_room_ready("den"), "ready/another room is not")

	# current_scene_id names the DESTINATION the moment a transition is claimed,
	# while the old room is still standing — so the id alone is not readiness.
	SceneManager._transitioning = true
	_ok(not SceneManager.is_room_ready("arcade"), "ready/not while transitioning")
	SceneManager._transitioning = false

	# Content readiness is the later boundary: the room is up AND its slot restored.
	_ok(not SceneManager.is_scene_content_ready("arcade"),
		"ready/content not ready before the restore finishes")
	SceneManager.notify_scene_content_ready("arcade")
	_ok(SceneManager.is_scene_content_ready("arcade"), "ready/content ready after notify")

	# A restore that yielded while the player left must not mark the room it
	# finished in. This is the 24-object-arcade-saved-as-1 bug.
	SceneManager.notify_scene_content_ready("den")
	_eq(SceneManager._content_ready_scene_id, "arcade",
		"ready/stale notify from another room is ignored")

	# And claiming a transition drops content readiness immediately.
	SceneManager._transitioning = true
	_ok(not SceneManager.is_scene_content_ready("arcade"),
		"ready/content readiness lost while transitioning")
	SceneManager._transitioning = false


# ── The transition state machine ──────────────────────────────────────────────

func _test_transition() -> void:
	SceneManager.current_scene_id = "arcade"
	SceneManager._transitioning = false
	SceneManager._pending_scene_id = ""
	SceneManager._last_load_failed = false

	# An unknown room is refused outright rather than claiming a transition.
	SceneManager.change_scene("nonesuch")
	_eq(SceneManager.current_scene_id, "arcade", "transition/unknown id is refused")
	_ok(not SceneManager._transitioning, "transition/unknown id claims nothing")

	# Passthrough needs the headset to support it; headless has no OpenXR at all.
	if not SceneManager.is_passthrough_supported():
		SceneManager.change_scene("passthrough")
		_eq(SceneManager.current_scene_id, "arcade",
			"transition/passthrough refused without support")

	# Asking for the room you are already in is a no-op, and cancels anything
	# queued behind it — a double-tap must not leave a stale destination armed.
	SceneManager._transitioning = true
	SceneManager._pending_scene_id = "den"
	SceneManager.change_scene("arcade")
	_eq(SceneManager._pending_scene_id, "", "transition/same room cancels the queue")
	_ok(SceneManager._same_scene_request_is_noop("arcade"),
		"transition/live same room is a no-op")
	SceneManager._last_load_failed = true
	_ok(not SceneManager._same_scene_request_is_noop("arcade"),
		"transition/failed destination can be retried")
	SceneManager._last_load_failed = false

	# While one is in flight, the newest request wins rather than stacking.
	SceneManager.change_scene("den")
	_eq(SceneManager._pending_scene_id, "den", "transition/request queues while busy")
	SceneManager.change_scene("bedroom")
	_eq(SceneManager._pending_scene_id, "bedroom", "transition/last intent wins")
	_eq(SceneManager.current_scene_id, "arcade", "transition/queued request does not move the id")

	# With no outgoing scene after a failure, the next attempt must recover the
	# parked player rather than allowing the incoming room to keep a second one.
	var parked := PlayerRig.new()
	SceneManager._parked_player = parked
	_ok(SceneManager._player_for_transition(null) == parked,
		"transition/failed load recovers parked player")
	SceneManager._parked_player = null
	parked.free()

	SceneManager._transitioning = false
	SceneManager._pending_scene_id = ""
	SceneManager._last_load_failed = false
	SceneManager._parked_player = null
	SceneManager._failed_loading_rig = null


# ── Periodic autosave ─────────────────────────────────────────────────────────

func _test_autosave() -> void:
	var sp := ScenePersistence.new("arcade")
	var path := "user://scenes/arcade/%s.json" % SLOT_A
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	sp.instantiate_objects(self, [
		{"id": 0, "type": "system", "systemid": "nes",
			"position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "system", "systemid": "gb",
			"position": [1, 0, 0], "rotation": [0, 0, 0]},
	])
	for i in range(40):
		await get_tree().physics_frame

	# Clean Room is readonly. An autosave aimed at it must refuse rather than
	# quietly writing a file named "clean".
	_ok(not sp.autosave_slot(self, "clean"), "autosave/refuses the clean slot")
	_ok(not FileAccess.file_exists("user://scenes/arcade/clean.json"),
		"autosave/wrote no clean.json")

	# The deferred write really lands, and costs the main thread only the walk.
	# Time the call and nothing else: _ok() prints, and a print into a piped
	# console costs ~15 ms, which is what this number was measuring at first.
	var t := Time.get_ticks_usec()
	var dispatched := sp.autosave_slot(self, SLOT_A)
	var main_us := Time.get_ticks_usec() - t
	_ok(dispatched, "autosave/first save dispatches")
	ScenePersistence.flush_pending_writes()
	_ok(FileAccess.file_exists(path), "autosave/deferred write landed")
	print("[test] autosave main-thread cost %.3f ms (walk only; encode+write deferred)"
		% (main_us / 1000.0))

	var first := FileAccess.get_file_as_string(path)
	_ok(first.length() > 0, "autosave/file is not empty")

	# An untouched room re-encodes to the identical bytes every interval. Writing
	# them again is pure flash wear, so it must be skipped.
	_ok(not sp.autosave_slot(self, SLOT_A), "autosave/unchanged room is skipped")

	# But a room that changed must not be.
	var sys: Node3D = null
	for n in get_children():
		if n is RetroSystem:
			sys = n
			break
	sys.global_position += Vector3(0, 0, 3.5)
	_ok(sp.autosave_slot(self, SLOT_A), "autosave/changed room is written")
	ScenePersistence.flush_pending_writes()
	_ok(FileAccess.get_file_as_string(path) != first, "autosave/file contents changed")

	# What landed has to be a loadable slot, not just different bytes.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_ok(parsed is Dictionary and (parsed as Dictionary).get("version", 0) == ScenePersistence.VERSION,
		"autosave/wrote a current-version slot")
	_eq(((parsed as Dictionary).get("objects", []) as Array).size(), 2,
		"autosave/wrote both objects")

	# A deleted slot file must be rewritten even though the digest still matches:
	# the digest describes what we last wrote, not what is on disk now.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(sp.autosave_slot(self, SLOT_A), "autosave/rewrites a slot deleted underneath it")
	ScenePersistence.flush_pending_writes()
	_ok(FileAccess.file_exists(path), "autosave/the rewrite landed")

	# clear_scene, not a hand-rolled queue_free of the systems: a system also puts
	# its captive cable in "spawned", and freeing only the systems left that cable
	# standing in the next group's room.
	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ── Clearing and reloading the room you are standing in ───────────────────────

## Loading the "clean" slot IS the clear-room action, and loading any other slot
## while already in the room clears it first. Both run against a live room, and
## clear_scene has to leave nothing behind — a survivor is a node still in the
## "spawned" group, which the next save then writes back out.
func _test_reload() -> void:
	var sp := ScenePersistence.new("arcade")
	var entries := [
		{"id": 0, "type": "system", "systemid": "nes",
			"position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "system", "systemid": "gb",
			"position": [1, 0, 0], "rotation": [0, 0, 0]},
	]
	sp.instantiate_objects(self, entries)
	for i in range(30):
		await get_tree().physics_frame
	# A system registers its captive cable in "spawned" too, so the group is bigger
	# than the entry list. The invariant is that a reload reproduces this exact
	# population — measure it rather than hardcoding a count that quietly tracks
	# how many cables a console happens to ship with.
	var baseline := get_tree().get_nodes_in_group("spawned").size()
	_ok(baseline >= 2, "reload/room furnished (%d spawned nodes)" % baseline)
	_eq(_systems(), 2, "reload/two systems furnished")

	sp.clear_scene(self)
	for i in range(30):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "reload/clear_scene leaves nothing")

	# And clearing an already-empty room is not an error.
	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "reload/clearing twice is safe")

	# Reload in place: save, then load the same slot back over a live room.
	sp.instantiate_objects(self, entries)
	for i in range(30):
		await get_tree().physics_frame
	_ok(sp.save_slot(self, SLOT_A), "reload/saved the furnished room")
	await sp.load_slot_async(self, SLOT_A)
	for i in range(30):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), baseline,
		"reload/in-place reload restores exactly one room's worth")
	_eq(_systems(), 2, "reload/in-place reload restores two systems")

	# Loading "clean" over it is the clear-room action.
	var clean_ok: bool = await sp.load_slot_async(self, "clean")
	_ok(clean_ok, "reload/clean slot loads")
	for i in range(20):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "reload/clean slot empties the room")

	# A slot that does not exist must fail WITHOUT clearing: a failed load is not
	# an implicit clear-room, or a typo costs the player their furniture.
	sp.instantiate_objects(self, entries)
	for i in range(30):
		await get_tree().physics_frame
	var missing_ok: bool = await sp.load_slot_async(self, "__no_such_slot")
	_ok(not missing_ok, "reload/missing slot fails")
	_eq(get_tree().get_nodes_in_group("spawned").size(), baseline,
		"reload/failed load left the room standing")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame


# ── The carry: a room across a reload or a restart ────────────────────────────

## Applying a mod rebuilds the room, and some changes restart the app. Neither is
## the player leaving it, so the room is written as it stands and the next restore
## of THAT room brings it back -- once -- in place of its slot.
func _test_carry() -> void:
	SceneManager._carry_room_id = ""
	SceneManager._transitioning = false
	SceneManager.current_scene_id = CARRY_ROOM
	SceneManager._content_ready_scene_id = ""
	_ok(not SceneManager.carry_room(), "carry/refused before the room has settled")
	_ok(not SceneManager.reload_room().is_empty(), "carry/as is a reload")
	_eq(SceneManager._carry_room_id, "", "carry/and nothing is marked")
	SceneManager._content_ready_scene_id = CARRY_ROOM

	var sp := ScenePersistence.new(CARRY_ROOM)
	var entries := [
		{"id": 0, "type": "system", "systemid": "nes",
			"position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "system", "systemid": "gb",
			"position": [1, 0, 0], "rotation": [0, 0, 0]},
	]
	sp.instantiate_objects(self, entries)
	for i in range(30):
		await get_tree().physics_frame
	var baseline := get_tree().get_nodes_in_group("spawned").size()
	var carry_file := ProjectSettings.globalize_path(
		"user://scenes/%s/%s.json" % [CARRY_ROOM, ScenePersistence.CARRY_SLOT])

	_ok(SceneManager.carry_room(), "carry/written for a settled room")
	_ok(FileAccess.file_exists(carry_file), "carry/the file is beside the slots")
	# Kept in the prefs, so a restart finds it.
	SceneManager._carry_room_id = ""
	SceneManager.load_prefs()
	_eq(SceneManager._carry_room_id, CARRY_ROOM, "carry/the mark survives a restart")
	_ok(SceneManager.take_carry(CARRY_ROOM), "carry/the room's next restore takes it")
	_ok(not SceneManager.take_carry(CARRY_ROOM), "carry/and only that one")
	SceneManager.load_prefs()
	_eq(SceneManager._carry_room_id, "", "carry/taken, it is gone from the prefs as well")

	sp.clear_scene(self)
	for i in range(30):
		await get_tree().physics_frame
	_eq(_systems(), 0, "carry/the room is torn down")
	var restored: bool = await sp.load_carry_async(self)
	_ok(restored, "carry/restores")
	for i in range(30):
		await get_tree().physics_frame
	_eq(_systems(), 2, "carry/the room comes back with what was in it")
	_eq(get_tree().get_nodes_in_group("spawned").size(), baseline,
		"carry/exactly one room's worth")
	_ok(not FileAccess.file_exists(carry_file), "carry/deleted once restored")
	var again: bool = await sp.load_carry_async(self)
	_ok(not again, "carry/a second restore finds none")
	_eq(_systems(), 2, "carry/and leaves the room standing")

	# Marked for one room and restored into another (a restart that came back
	# somewhere else): dropped, not kept for a later visit, by when it is stale.
	_ok(SceneManager.carry_room(), "carry/written again")
	_ok(not SceneManager.take_carry("arcade"), "carry/another room's restore does not take it")
	_ok(not FileAccess.file_exists(carry_file), "carry/and the file is deleted, not kept")
	_eq(SceneManager._carry_room_id, "", "carry/nor the mark")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	SceneManager.current_scene_id = _saved_scene_id
	SceneManager._content_ready_scene_id = ""


## The command line a restart starts the new process with. Static, so it is
## asked here without quitting anything.
func _test_restart_args() -> void:
	var none := PackedStringArray()
	_eq(SCENE_MANAGER.restart_args(true, true, PackedStringArray(["--x"]),
		PackedStringArray(["--y"]), "C:/p"), none,
		"restart/Android passes nothing: the activity adds its own")
	_eq(SCENE_MANAGER.restart_args(false, true, PackedStringArray(["--fullscreen"]), none, "C:/p"),
		PackedStringArray(["--fullscreen"]), "restart/an export keeps what the engine left it")
	_eq(SCENE_MANAGER.restart_args(false, true, none, PackedStringArray(["--only=x"]), "C:/p"),
		PackedStringArray(["--", "--only=x"]), "restart/our own arguments go after --")
	_eq(SCENE_MANAGER.restart_args(false, false, none, none, "C:/p"),
		PackedStringArray(["--path", "C:/p"]), "restart/an editor binary is told the project")
	_eq(SCENE_MANAGER.restart_args(false, false, PackedStringArray(["--path", "D:/q"]), none, "C:/p"),
		PackedStringArray(["--path", "D:/q"]), "restart/and not twice")

	# The waiter that launches the new process once this one has gone. It does
	# not trust a clean shutdown to do it (scene_manager.gd, restart_app).
	_eq(SCENE_MANAGER.relaunch_command("Android", 42, "x", none), [],
		"restart/Android starts no waiter: the activity relaunches itself")
	var sh: Array = SCENE_MANAGER.relaunch_command("Linux", 42, "/opt/retro xr/RetroXR",
		PackedStringArray(["--path", "/p q"]))
	_eq(sh[0], "/bin/sh", "restart/Linux waits in sh")
	_eq((sh[1] as PackedStringArray).slice(2), PackedStringArray(
		["sh", "42", "/opt/retro xr/RetroXR", "--path", "/p q"]),
		"restart/for that pid, then the program and its arguments, each one argument")
	var ps: Array = SCENE_MANAGER.relaunch_command("Windows", 42,
		"C:/Program Files/Bob's/RetroXR.exe", PackedStringArray(["--path", "C:/my games/p"]))
	var command := str((ps[1] as PackedStringArray)[-1])
	_eq(ps[0], "powershell.exe", "restart/Windows waits in PowerShell")
	_ok(command.begins_with("Wait-Process -Id 42 "), "restart/for that pid")
	_ok(command.contains("-FilePath 'C:/Program Files/Bob''s/RetroXR.exe'"),
		"restart/the program quoted, its apostrophe doubled")
	_ok(command.ends_with("-ArgumentList '\"--path\" \"C:/my games/p\"'"),
		"restart/each argument in double quotes, so a space does not split it")
	_ok(not str(SCENE_MANAGER.relaunch_command("Windows", 7, "C:/r.exe", none)[1][-1]).contains("-ArgumentList"),
		"restart/and no empty argument list")


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## Two restores into one room. The second bumps _restore_generation, and the
## first must notice after its next yield and stand down — otherwise both build
## into the same room while each clear_scene()s what the other spawned, leaving
## live systems holding freed cable plugs (scene_persistence.gd:49-54).
func _test_overlap() -> void:
	var sp := ScenePersistence.new("arcade")
	sp.instantiate_objects(self, [
		{"id": 0, "type": "system", "systemid": "nes",
			"position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "system", "systemid": "gb",
			"position": [1, 0, 0], "rotation": [0, 0, 0]},
	])
	for i in range(30):
		await get_tree().physics_frame
	sp.save_slot(self, SLOT_A)

	# Both started before either is awaited: the race the guard exists for.
	# call_deferred, because GDScript will not let a coroutine be called any other
	# way without awaiting it — a bare call is a parse error and Callable.call is a
	# runtime one — and awaiting the first would serialise the overlap under test.
	# Held in locals so the two instances outlive the deferred dispatch.
	var runner_a := ScenePersistence.new("arcade")
	var runner_b := ScenePersistence.new("arcade")
	runner_a.call_deferred("load_slot_async", self, SLOT_A)
	runner_b.call_deferred("load_slot_async", self, SLOT_A)
	for i in range(40):
		await get_tree().physics_frame

	# One room's worth, not two, and nothing freed still in the group.
	_eq(_systems(), 2, "overlap/two concurrent restores leave one room's systems")
	var alive := 0
	for n in get_tree().get_nodes_in_group("spawned"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			alive += 1
	_eq(alive, get_tree().get_nodes_in_group("spawned").size(),
		"overlap/every survivor is a live node")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame

	# _let_go hands the room back to physics after a restore. A body freed while it
	# was held — which is precisely what an overlapping restore does — must not stop
	# it weighting the rest: everything after the freed one stayed weightless and
	# asleep, permanently, because the typed local threw before is_instance_valid
	# could be consulted. Freed entry FIRST, so a throw abandons the live one.
	var doomed := RigidBody3D.new()
	add_child(doomed)
	var live := RigidBody3D.new()
	live.gravity_scale = 0.0
	add_child(live)
	var held := {
		0: {"body": doomed, "gravity": 1.0},
		1: {"body": live, "gravity": 1.0},
	}
	doomed.free()
	sp._let_go(held)
	_eq(live.gravity_scale, 1.0, "overlap/_let_go weights bodies after a freed one")
	live.queue_free()


# ── The loading screen over a slot loaded where you stand ─────────────────────

signal _load_pressed(slot_id: String, room_id: String)

## A slot loaded into the room the player is already in has no room change in
## front of it, so nothing put the loading screen up: the room was emptied and
## rebuilt in plain view. The handler is SpawnMenuController's, and it is driven
## here the way the menu drives it — by signal, which is also the only way to
## start a coroutine without waiting for it.
##
## The script goes onto a node ALREADY in the tree, so its _ready never runs. A
## whole controller looks for the rig, builds the menu's SubViewport (which hangs
## a headless run) and restores the player's own room; none of that is the
## question here, and the handler needs only the viewport it asks for the menu.
func _test_curtain() -> void:
	var sp := ScenePersistence.new("arcade")
	sp.instantiate_objects(self, [
		{"id": 0, "type": "system", "systemid": "nes",
			"position": [0, 0, 0], "rotation": [0, 0, 0]},
		{"id": 1, "type": "system", "systemid": "gb",
			"position": [1, 0, 0], "rotation": [0, 0, 0]},
		{"id": 2, "type": "system", "systemid": "snes",
			"position": [2, 0, 0], "rotation": [0, 0, 0]},
	])
	for i in range(30):
		await get_tree().physics_frame
	var baseline := get_tree().get_nodes_in_group("spawned").size()
	_ok(sp.save_slot(self, SLOT_A), "curtain/saved a furnished room")

	SceneManager.current_scene_id = "arcade"
	SceneManager._transitioning = false
	SceneManager.active_slots["arcade"] = "clean"
	var ctl := Node3D.new()
	add_child(ctl)
	ctl.set_script(load("res://Scripts/UI/spawn_menu/spawn_menu_controller.gd"))
	var viewport := XRToolsViewport2DIn3D.new()
	ctl.set("_viewport_node", viewport)
	_load_pressed.connect(Callable(ctl, "_on_slot_load"))

	# SceneManager claims the boot curtain in its own _ready, and on a machine whose
	# boot room has a slot that owner is never ended by a run of this suite.
	await _curtain_down()
	var shows := [0]
	var returned := [0]
	# Whether the screen still had its owner as each load handed back.
	var owned_at_return: Array[bool] = []
	var count_show := func() -> void: shows[0] += 1
	var count_return := func(_slot: String) -> void:
		returned[0] += 1
		owned_at_return.append(LoadingOverlay.owners().has(&"slot_load"))
	LoadingOverlay.overlay_shown.connect(count_show)
	SceneManager.active_slot_changed.connect(count_return)

	# The load itself. active_slot_changed is the handler's last act on a load that
	# worked, so until it fires the room is still being built and must be covered.
	_load_pressed.emit(SLOT_A, "arcade")
	_eq(shows[0], 1, "curtain/an in-place load puts the loading screen up")
	var panel: Node = LoadingOverlay._panel
	_ok(panel != null and str(panel.get_node("Screen/TitleLabel").text) == "LOADING  ARCADE ROOM",
		"curtain/titled for the room, as a room change is")
	_ok(panel != null and str(panel.get_node("Screen/StatusLabel").text).begins_with("RESTORING OBJECTS  "),
		"curtain/saying what it is waiting on")
	var covered := await _covered_until(returned, 1)
	_ok(covered[1] > 0, "curtain/the restore spans frames, so there is a room to hide")
	_eq(covered[0], 0, "curtain/it stays up for as long as the room is being built")
	_eq(returned[0], 1, "curtain/the load finished")
	_ok(not LoadingOverlay.is_active(), "curtain/and comes down when the room is whole")
	_eq(SceneManager.active_slot("arcade"), SLOT_A, "curtain/the loaded slot is the active one")
	_eq(get_tree().get_nodes_in_group("spawned").size(), baseline,
		"curtain/one room's worth was restored under it")
	await _curtain_down()
	_ok(LoadingOverlay._panel == null, "curtain/the panel is gone once it is down")

	# Two presses, the second over the first. The first restore stands down at its
	# next yield and returns at once; the screen belongs to the one still building.
	# Asked at the moment the first hands back, not on the frames either side: the
	# second load's next progress report would put a dropped owner straight back.
	shows[0] = 0
	returned[0] = 0
	owned_at_return.clear()
	_load_pressed.emit(SLOT_A, "arcade")
	_load_pressed.emit(SLOT_A, "arcade")
	covered = await _covered_until(returned, 2)
	_eq(shows[0], 1, "curtain/two loads at once share one screen")
	_eq(returned[0], 2, "curtain/both loads finished")
	_eq(owned_at_return, [true, false] as Array[bool],
		"curtain/the first load returning does not uncover the second")
	_eq(covered[0], 0, "curtain/nor does any frame between them")
	_eq(_systems(), 3, "curtain/and left one room's systems")
	await _curtain_down()

	# Clean Room only clears, and a slot that will not read leaves the room as it
	# was. Neither has anything to wait for, so neither may flash a loading screen.
	shows[0] = 0
	_load_pressed.emit("__no_such_slot", "arcade")
	_eq(shows[0], 0, "curtain/a load that fails raises nothing")
	_eq(_systems(), 3, "curtain/and leaves the room standing")
	_load_pressed.emit("clean", "arcade")
	_eq(shows[0], 0, "curtain/clearing the room raises nothing")
	_ok(not LoadingOverlay.is_active(), "curtain/and leaves no owner behind")
	for i in range(20):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "curtain/the clean slot emptied the room")

	LoadingOverlay.overlay_shown.disconnect(count_show)
	SceneManager.active_slot_changed.disconnect(count_return)
	_load_pressed.disconnect(Callable(ctl, "_on_slot_load"))
	viewport.free()
	ctl.queue_free()
	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame


## Frames run until `returned` reaches `want`, and how many of them found the room
## uncovered: [uncovered, frames].
func _covered_until(returned: Array, want: int) -> Array:
	var uncovered := 0
	var frames := 0
	while returned[0] < want and frames < 1200:
		if not LoadingOverlay.owners().has(&"slot_load"):
			uncovered += 1
		frames += 1
		await get_tree().process_frame
	return [uncovered, frames]


## Nobody waiting and the hide grace run out, so the next show is a new one.
func _curtain_down() -> void:
	for owner: Variant in LoadingOverlay.owners():
		LoadingOverlay.end(owner)
	await get_tree().create_timer(LoadingOverlay.HOLD_S + 0.15).timeout


# ── The room's own movable furniture ──────────────────────────────────────────

## The arcade's television is instanced by the room, so it is not in "spawned" and
## the object walk never saw it — it is an XRToolsPickable, so the player could
## carry it anywhere and the position was lost on every load. It is recorded by
## path instead, and must NOT be swept into "spawned", which clear_scene frees.
func _test_fixture() -> void:
	var sp := ScenePersistence.new("arcade")
	var tv := Node3D.new()
	tv.name = "TV"
	add_child(tv)
	tv.add_to_group("fixture")
	tv.global_position = Vector3(1.5, 0.95, -2.25)
	tv.global_rotation_degrees = Vector3(0, 37, 0)

	var snap := sp._snapshot(self)
	_ok(snap.has("fixtures"), "fixture/a room with fixtures writes the section")
	var fx: Array = snap.get("fixtures", [])
	_eq(fx.size(), 1, "fixture/exactly one fixture recorded")
	_eq(str((fx[0] as Dictionary).get("path", "")), "TV", "fixture/recorded by path")

	# It must never be treated as a spawned object, or clear_scene deletes the
	# room's own television and nothing in the file can rebuild it.
	_ok(not tv.is_in_group("spawned"), "fixture/a fixture is not spawned")
	sp.clear_scene(self)
	await get_tree().process_frame
	_ok(is_instance_valid(tv) and not tv.is_queued_for_deletion(),
		"fixture/clear_scene leaves the fixture standing")

	# Move it, then restore: it goes back rather than staying where it was left.
	tv.global_position = Vector3(-9.0, 0.0, 9.0)
	tv.global_rotation_degrees = Vector3(0, -120, 0)
	sp._restore_fixtures(self, fx)
	_ok(tv.global_position.distance_to(Vector3(1.5, 0.95, -2.25)) < 0.001,
		"fixture/position restored (%s)" % tv.global_position)
	_ok(absf(tv.global_rotation_degrees.y - 37.0) < 0.01,
		"fixture/rotation restored (%.2f)" % tv.global_rotation_degrees.y)

	# A slot written before fixtures existed carries no section at all, and must
	# leave the room's furniture exactly where the .tscn authored it.
	tv.global_position = Vector3(4.0, 1.0, 4.0)
	sp._restore_fixtures(self, [])
	_ok(tv.global_position.is_equal_approx(Vector3(4.0, 1.0, 4.0)),
		"fixture/an old slot moves nothing")
	# And a fixture the room no longer has is skipped, not an error.
	sp._restore_fixtures(self, [{"path": "NoSuchNode", "position": [0, 0, 0]}])
	_ok(true, "fixture/a missing fixture is skipped")

	# A television is the one fixture with state of its own. A spawned set carries
	# its whole control state in its object entry; a fixture has no entry, so the
	# arcade's own set used to come back on Composite 1 however it was left.
	var set_tv := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	set_tv.name = "FixtureTV"
	set_tv.freeze = true
	add_child(set_tv)
	set_tv.add_to_group("fixture")
	set_tv.set_source(RetroTV.Source.COMPOSITE_3)
	var tv_fx: Array = sp._snapshot(self).get("fixtures", [])
	var set_rec := {}
	for entry: Variant in tv_fx:
		if str((entry as Dictionary).get("path", "")) == "FixtureTV":
			set_rec = entry as Dictionary
	_eq(int(set_rec.get("source", -1)), int(RetroTV.Source.COMPOSITE_3),
		"fixture/a set records the input it is on")
	set_tv.set_source(RetroTV.Source.COMPOSITE_1)
	sp._restore_fixtures(self, [set_rec])
	_eq(set_tv.current_source, int(RetroTV.Source.COMPOSITE_3),
		"fixture/a set goes back to the input it was on")
	# A slot written before this, and a fixture that is furniture rather than a
	# set: neither carries the key, and neither may be touched by the restore.
	sp._restore_fixtures(self, [{"path": "FixtureTV", "position": [0, 0, 0]}])
	_eq(set_tv.current_source, int(RetroTV.Source.COMPOSITE_3),
		"fixture/an old slot leaves the input alone")
	# The saved input can be one this cabinet does not carry — a set the player has
	# since re-shelled. set_source falls back rather than blanking the glass.
	# 99 clamps to VGA, which the stock body does not carry (only the monitor shell
	# seats that socket), so the fallback has something to do here.
	set_tv.set_source(RetroTV.Source.COMPOSITE_3)
	sp._restore_fixtures(self, [{"path": "FixtureTV", "source": 99}])
	_eq(set_tv.current_source, int(RetroTV.Source.COMPOSITE_1),
		"fixture/an input this cabinet lacks falls back")
	set_tv.remove_from_group("fixture")
	set_tv.queue_free()

	# A room with no fixtures writes no section, so those slots are byte-identical
	# to what this build wrote before fixtures existed.
	tv.remove_from_group("fixture")
	_ok(not sp._snapshot(self).has("fixtures"),
		"fixture/a room without fixtures writes no section")
	tv.queue_free()

	# The arcade ships with no television: a set is spawned from the menu and
	# carried by the slot like anything else the player put down, so nothing in
	# the room is a fixture any more. Read from the .tscn because the room cannot
	# be loaded here: its SubViewports would hang a headless run.
	var scene_src := FileAccess.get_file_as_string("res://Scenes/MainScene.tscn")
	var tv_line := ""
	for line in scene_src.split("\n"):
		if line.begins_with("[node name=\"TV\"") and line.contains("instance="):
			tv_line = line
	_ok(tv_line.is_empty(), "fixture/the arcade authors no TV of its own")


# -- The room's wall switches -------------------------------------------------

## A switch never moves, so it is not a fixture and the object walk never sees it:
## the bedroom came back lit however it was left. Its state is recorded by path,
## the same key object_sync uses when it ships the room to a late joiner.
func _test_switch() -> void:
	var sp := ScenePersistence.new("bedroom")
	var sw := LightSwitch.new()
	sw.name = "Ceiling"
	add_child(sw)
	sw.set_lights_on(false)

	var snap := sp._snapshot(self)
	_ok(snap.has("switches"), "switch/a room with switches writes the section")
	var recs: Array = snap.get("switches", [])
	_eq(recs.size(), 1, "switch/exactly one switch recorded")
	var rec := recs[0] as Dictionary
	_eq(str(rec.get("path", "")), "Ceiling", "switch/recorded by path")
	_ok(not bool(rec.get("on", true)), "switch/records the state it was left in")

	# The load path must actually move the switch, not just read it back.
	sw.set_lights_on(true)
	sp._restore_switches(self, recs)
	_ok(not sw.lights_on, "switch/a saved-off switch comes back off")
	sp._restore_switches(self, [{"path": "Ceiling", "on": true}])
	_ok(sw.lights_on, "switch/a saved-on switch comes back on")

	# A slot written before switches existed carries no section, and must leave the
	# room on the state its .tscn authored.
	sp._restore_switches(self, [])
	_ok(sw.lights_on, "switch/an old slot changes nothing")
	# And a switch the room no longer has is skipped, not an error.
	sp._restore_switches(self, [{"path": "NoSuchNode", "on": false}])
	_ok(true, "switch/a missing switch is skipped")

	sw.queue_free()
	await get_tree().process_frame
	_ok(not sp._snapshot(self).has("switches"),
		"switch/a room without switches writes no section")

	# Worth nothing unless the bedroom still authors switches. Read from the .tscn
	# because the room cannot be loaded here.
	var src := FileAccess.get_file_as_string("res://Scenes/BedroomScene.tscn")
	_ok(src.contains("light_switch.gd"),
		"switch/the bedroom still authors a light switch")


# ── A machine's core must not outlive the machine ─────────────────────────────

## Leaving the tree has to stop the core. clear_scene was the only path that
## powered machines off, so a trash-canned console, a bare queue_free or a room
## torn down around one skipped the whole GDScript release — the achievements
## session stayed claimed and a rumbling pad kept rumbling. The emulation thread
## itself was always stopped by the C++ Libretro::_exit_tree, which is exactly why
## nobody noticed.
func _test_power() -> void:
	var sys: Node = preload("res://Scenes/Objects/system.tscn").instantiate()
	add_child(sys)
	await get_tree().process_frame

	# No core is started here — there is no ROM and no installed core in a headless
	# run — so the flag is set directly. What is under test is the teardown branch,
	# not what powering on does.
	sys.is_powered_on = true
	remove_child(sys)
	_ok(not sys.is_powered_on, "power/leaving the tree stops the core")
	sys.free()

	# And the teardown path must not go through the power BUTTON's verb, which
	# answers to the netplay session and can return without stopping anything.
	var src := FileAccess.get_file_as_string("res://Scripts/Data/scene_persistence.gd")
	_ok(src.contains(".power_off()") and not src.contains(".toggle_power()"),
		"power/clear_scene powers off locally rather than toggling")

	# A power switch is not a pose, and it is the one slider that is not. Power is
	# not in the file at all, so every machine restores OFF — and a saved switch
	# position brought a handheld back with its cap up and nothing running behind
	# it, having fired value_changed straight into toggle_power on the way.
	var gb: RetroSystem = preload("res://Scenes/Objects/system.tscn").instantiate()
	gb.systemid = "gb"
	add_child(gb)
	await get_tree().process_frame
	var sw := gb.find_child("PowerSwitch", true, false) as VRSlider
	var vol := gb.find_child("VolumeSlider", true, false) as VRSlider
	_ok(sw != null and vol != null,
		"power/the handheld carries both a power switch and a volume slider")
	sw.set_value_no_signal(1.0)
	vol.set_value_no_signal(0.75)
	var sp := ScenePersistence.new("arcade")
	var paths: Array = []
	for rec: Variant in sp._serialize_articulated_controls(gb):
		paths.append(str((rec as Dictionary).get("path", "")))
	_ok(not paths.has(str(gb.get_path_to(sw))),
		"power/a running machine does not save its power switch")
	# The other half: the walk itself still works, so the case above is measuring
	# the skip rather than an empty record list.
	_ok(paths.has(str(gb.get_path_to(vol))),
		"power/the volume slider is saved as before")

	# The Game Boy Advance's thumbwheel is a knob on its own axle: the system menu's
	# slider and a hand on the wheel set the same level, and the GLB's wheel turns.
	var gba: RetroSystem = preload("res://Scenes/Objects/system.tscn").instantiate()
	gba.systemid = "gba"
	add_child(gba)
	await get_tree().process_frame
	await get_tree().process_frame
	var wheel_knob := gba.find_child("VolumeSlider", true, false) as VRKnob
	var gba_model := gba.get_model()
	_ok(wheel_knob != null and gba_model != null and gba_model.has_method("set_volume"),
		"volume/the Game Boy Advance's volume is a wheel on its axle")
	if wheel_knob != null and gba_model != null:
		var wheel := gba_model.find_child("VolumeWheel", true, false) as Node3D
		var rest := wheel.transform if wheel != null else Transform3D()
		# Turned about the wheel's own axle, the same way round (a hand turns it as
		# the wheel turns), its touch box out on the rim at the bottom edge (+Z).
		var to_model := gba_model.global_transform.affine_inverse()
		var touch := wheel_knob.get_node_or_null("CollisionShape3D") as Node3D
		_ok(wheel != null and touch != null
			and wheel_knob.global_basis.z.normalized().dot((wheel.get_parent() as Node3D).global_basis.z.normalized()) > 0.999
			and (to_model * touch.global_position).z > (to_model * wheel_knob.global_position).z + 0.003,
			"volume/the knob turns about the wheel's own axle, its box out on the rim")
		gba_model.call("set_volume", 0.25)
		await get_tree().process_frame
		_ok(is_equal_approx(float(gba_model.call("get_volume")), 0.25) and is_equal_approx(wheel_knob.value, 0.25),
			"volume/the menu's level is the wheel's")
		_ok(wheel != null and not wheel.transform.basis.is_equal_approx(rest.basis),
			"volume/and the wheel turns to it")
		# A slot written while the wheel was a slider still lands on it.
		ScenePersistence.new("arcade")._restore_articulated_controls(gba,
			[{"path": str(gba.get_path_to(wheel_knob)), "kind": "slider", "value": 0.6}])
		_ok(is_equal_approx(wheel_knob.value, 0.6), "volume/an older slot's slider record turns the wheel")
	gba.queue_free()
	# The System tab's Volume row, both ways.
	var opts := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	add_child(opts)
	await get_tree().process_frame
	opts.populate_system(false, true, false, "", 0, 0.4)
	_ok(opts._volume_box.visible and is_equal_approx(opts._volume_slider.value, 40.0),
		"volume/the System tab shows the handheld's level")
	var heard := [-1.0]
	opts.volume_changed.connect(func(v: float) -> void: heard[0] = v)
	opts._volume_slider.value = 70.0
	_ok(is_equal_approx(heard[0], 0.7), "volume/and moving its slider asks for that level")
	opts.show_volume(0.2)
	_ok(is_equal_approx(opts._volume_slider.value, 20.0) and is_equal_approx(heard[0], 0.7),
		"volume/a turned wheel moves it without asking back")
	opts.populate_system(false, false, false)
	_ok(not opts._volume_box.visible, "volume/a machine without its own control has no row")
	opts.queue_free()

	# Every slot written before this carries the switch, so the restore has to
	# refuse it too — applying it would lift the cap AND toggle the machine.
	sw.set_value_no_signal(0.0)
	# The toggle is reached through value_changed, and a machine with no ROM
	# refuses to start — so is_powered_on would read false either way and only the
	# signal tells the two outcomes apart.
	var emitted := [0]
	sw.value_changed.connect(func(_v: float) -> void: emitted[0] += 1)
	sp._restore_articulated_controls(gb, [{
		"path": str(gb.get_path_to(sw)), "kind": "slider", "value": 1.0,
	}])
	_ok(is_zero_approx(sw.value), "power/an old slot's ON switch is not applied")
	_eq(emitted[0], 0, "power/and never reaches the machine's power toggle")
	remove_child(gb)
	gb.free()


# ── The video decks' teardown contract ────────────────────────────────────────

## The decks call _vlc.shutdown() from _exit_tree, which is a GDExtension method:
## if it ever stops being exported, every room change starts logging an invalid
## call and silently goes back to the unbounded destructor teardown.
## A room saved with a machine assembled must come back assembled.
##
## The whole point of ExpansionCatalog is that a stack is real hardware rather
## than a made-up systemid, and a stack that evaporates on reload is worse than
## one that was never buildable: the player loses work. Nothing wrote or read an
## expansion at all until this, so a Mega Drive standing on a Mega-CD with a disc
## in the drive came back as a bare console on the floor.
##
## Built through the same restore_* calls a hand's release ends in, then saved,
## cleared and loaded, so what is asserted is the real round trip and not a
## hand-written entry list agreeing with itself.
func _test_stack() -> void:
	var sp := ScenePersistence.new("arcade")
	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame

	var unit := (load("res://Scenes/Objects/expansion.tscn") as PackedScene) 		.instantiate() as RetroExpansion
	unit.expansion_id = "sega_cd"
	unit.add_to_group("spawned")
	add_child(unit)
	unit.freeze = true
	unit.global_position = Vector3(0.0, 1.0, 0.0)

	var console := (load("res://Scenes/Objects/system.tscn") as PackedScene) 		.instantiate() as RetroSystem
	console.systemid = "genesis"
	console.add_to_group("spawned")
	add_child(console)
	console.freeze = true
	console.global_position = Vector3(0.4, 1.0, 0.0)

	var disc := (load("res://Scenes/Objects/media/disc.tscn") as PackedScene) 		.instantiate() as RetroDisc
	disc.systemid = "segacd"
	disc.rom_path = "Z:/roms/segacd/selftest.cue"
	disc.add_to_group("spawned")
	add_child(disc)
	disc.freeze = true
	for i in range(60):
		await get_tree().physics_frame

	console.restore_expansion(unit)
	unit.restore_media_in_slot(disc)
	for i in range(20):
		await get_tree().physics_frame
	_eq(console.expansion_ids().size(), 1, "stack/built: the console carries its unit")
	_eq(unit.get_media_path(), "Z:/roms/segacd/selftest.cue",
		"stack/built: the drive holds its disc")

	_ok(sp.save_slot(self, SLOT_A), "stack/saved the assembled room")
	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "stack/cleared")

	var loaded: bool = await sp.load_slot_async(self, SLOT_A)
	_ok(loaded, "stack/loaded it back")
	for i in range(40):
		await get_tree().physics_frame

	var back_console: RetroSystem = null
	var back_unit: RetroExpansion = null
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is RetroSystem:
			back_console = n as RetroSystem
		elif n is RetroExpansion:
			back_unit = n as RetroExpansion
	_ok(back_console != null, "stack/the console came back")
	_ok(back_unit != null, "stack/the unit came back at all")
	if back_unit != null:
		_eq(back_unit.expansion_id, "sega_cd", "stack/and it is the same unit")
	if back_console != null and back_unit != null:
		_eq(back_console.expansion_ids().size(), 1,
			"stack/still bolted together after the reload")
		_ok(back_unit.get_host() == back_console,
			"stack/and the unit knows which console it is under")
		_eq(back_unit.get_media_path(), "Z:/roms/segacd/selftest.cue",
			"stack/the disc is still in the drive")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame


## The 32X's Model 2 spacer is its own object clipped under the unit, and the unit
## is in the console's slot: a reload has to bring back all three, still joined.
## The spacer's entry is only a pose -- the 32X's entry names it ("accessory").
func _test_spacer() -> void:
	var sp := ScenePersistence.new("arcade")
	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame

	var unit := (load("res://Scenes/Objects/expansion.tscn") as PackedScene) \
		.instantiate() as RetroExpansion
	unit.expansion_id = "sega_32x"
	unit.add_to_group("spawned")
	add_child(unit)
	unit.freeze = true
	unit.global_position = Vector3(0.0, 1.0, 0.0)

	var console := (load("res://Scenes/Objects/system.tscn") as PackedScene) \
		.instantiate() as RetroSystem
	console.systemid = "genesis"
	console.add_to_group("spawned")
	add_child(console)
	console.freeze = true
	console.global_position = Vector3(0.4, 1.0, 0.0)

	var spacer := ScenePersistence.instantiate("sega32x_spacer") as Sega32xSpacer
	add_child(spacer)
	spacer.freeze = true
	spacer.global_position = Vector3(-0.4, 1.0, 0.0)
	for i in range(60):
		await get_tree().physics_frame

	unit.restore_accessory(spacer)
	console.restore_cartridge(unit)
	for i in range(20):
		await get_tree().physics_frame
	_ok(unit.get_accessory() == spacer, "spacer/built: the spacer is clipped under the 32X")
	_ok(unit.get_host() == console, "spacer/built: and the 32X is in the slot")

	_ok(sp.save_slot(self, SLOT_A), "spacer/saved the assembled room")
	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	_eq(get_tree().get_nodes_in_group("spawned").size(), 0, "spacer/cleared")

	var loaded: bool = await sp.load_slot_async(self, SLOT_A)
	_ok(loaded, "spacer/loaded it back")
	for i in range(40):
		await get_tree().physics_frame

	var back_console: RetroSystem = null
	var back_unit: RetroExpansion = null
	var back_spacer: Sega32xSpacer = null
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is RetroSystem:
			back_console = n as RetroSystem
		elif n is RetroExpansion:
			back_unit = n as RetroExpansion
		elif n is Sega32xSpacer:
			back_spacer = n as Sega32xSpacer
	_ok(back_spacer != null, "spacer/the spacer came back")
	_ok(back_unit != null and back_spacer != null and back_unit.get_accessory() == back_spacer,
		"spacer/still clipped to the 32X after the reload")
	_ok(back_unit != null and back_unit.get_host() == back_console,
		"spacer/and the 32X is still in the slot")
	if back_unit != null and back_spacer != null:
		var shell := back_unit.get_node_or_null("Shell") as Node3D
		_ok(shell != null and back_spacer.global_position.distance_to(shell.global_position) < 0.001,
			"spacer/back exactly under the unit, where it was modelled")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame


## A restored cartridge's body GLB comes in on the loader threads BEFORE the
## cartridge is built (ModelWarmer.acquire). RetroCartridge loads it
## synchronously in _ready: free once it is cached, and a 625 ms frozen frame on
## a Quest (an N64 cart in the arcade restore) when it was not.
func _test_cart_body() -> void:
	var sp := ScenePersistence.new("arcade")
	sp.clear_scene(self)
	var cart := (load("res://Scenes/Objects/media/cartridge.tscn") as PackedScene) \
		.instantiate() as RetroCartridge
	cart.systemid = "n64"
	cart.add_to_group("spawned")
	add_child(cart)
	cart.freeze = true
	var body := cart._body_model()
	_ok(not body.is_empty() and cart.has_node("CartModel"), "cartbody/an N64 cartridge wears its body")
	_ok(sp.save_slot(self, SLOT_A), "cartbody/saved it")
	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame

	ModelWarmer._held.erase(body)
	var loaded: bool = await sp.load_slot_async(self, SLOT_A)
	_ok(loaded and ModelWarmer._held.has(body),
		"cartbody/the restore fetched the body through ModelWarmer before building the cartridge")
	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame


func _test_vlc() -> void:
	if not ClassDB.class_exists("VlcPlayer"):
		print("[test] skip vlc/ — VlcPlayer extension not loaded")
		return
	var player: Object = ClassDB.instantiate("VlcPlayer")
	_ok(player.has_method("shutdown"), "vlc/VlcPlayer exports shutdown()")

	# With no media open there is nothing to stop, so it must return at once
	# rather than spending its budget.
	var t := Time.get_ticks_usec()
	player.shutdown()
	var us := Time.get_ticks_usec() - t
	_ok(us < 500000, "vlc/shutdown with no media returns immediately (%.1f ms)" % (us / 1000.0))

	# Idempotent: a deck freed after an explicit stop must not tear down twice.
	player.shutdown()
	_ok(true, "vlc/shutdown is idempotent")

	# And the decks actually call it, which is the half a C++ method cannot assert.
	# Both decks tear down through MediaTransport now, so that is the file the
	# call lives in; the tuner still owns its own.
	for path in ["res://Scripts/Objects/media/media_transport.gd",
			"res://Scripts/Objects/tv/tv_tuner.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_ok(src.contains("func _exit_tree") and src.contains("shutdown()"),
			"vlc/%s stops libVLC on teardown" % path.get_file())

	# Reading the base's source only proves the deck tears down if the deck
	# actually inherits it, so check the chain rather than assuming it. Grepping
	# the two deck files used to cover both halves at once; after the extraction
	# it would have passed while proving nothing.
	for path in ["res://Scripts/Objects/media/dvd_player.gd",
			"res://Scripts/Objects/media/vcr_player.gd"]:
		var scr := load(path) as GDScript
		var base := scr.get_base_script() as GDScript
		_ok(base != null and base.resource_path.ends_with("media_transport.gd"),
			"vlc/%s inherits that teardown (base is %s)"
				% [path.get_file(), "none" if base == null else base.resource_path.get_file()])


# ── Slot manifest CRUD ────────────────────────────────────────────────────────

func _test_manifest() -> void:
	var sp := ScenePersistence.new("arcade")
	var before := sp.get_slots().size()

	# "clean" is synthesised, never stored, and always first.
	_eq(str(sp.get_slots()[0].get("id", "")), "clean", "manifest/clean is first")
	_ok(bool(sp.get_slots()[0].get("readonly", false)), "manifest/clean is readonly")

	var id := sp.create_new_slot(self, "Self Test")
	_ok(not id.is_empty(), "manifest/create returns an id")
	_eq(sp.get_slots().size(), before + 1, "manifest/create appends one slot")

	_ok(sp.rename_slot(id, "Renamed"), "manifest/rename succeeds")
	var found := ""
	for s in sp.get_slots():
		if str(s.get("id", "")) == id:
			found = str(s.get("name", ""))
	_eq(found, "Renamed", "manifest/rename took")

	# The readonly slot refuses every mutation.
	_ok(not sp.rename_slot("clean", "Nope"), "manifest/clean cannot be renamed")
	_ok(not sp.delete_slot("clean"), "manifest/clean cannot be deleted")
	_ok(not sp.save_slot(self, "clean"), "manifest/clean cannot be saved over")

	_ok(sp.delete_slot(id), "manifest/delete succeeds")
	_eq(sp.get_slots().size(), before, "manifest/delete removes the slot")
	_ok(not FileAccess.file_exists("user://scenes/arcade/%s.json" % id),
		"manifest/delete removed the file")


# ── The save side's type table (ScenePersistence._save_kind_rows) ─────────────

## PLAIN_SCENES types whose save row picks the type at save time (a peripheral,
## an audio deck, a battery, a cabinet or a stand by its scene), or that are an
## old name read back only ("ray_gun").
const _BUILT_TYPES := ["light_gun", "ray_gun", "retro_keyboard", "wiimote",
	"cd_player", "cassette_player", "record_player", "battery_aa", "battery_aaa",
	"loudspeaker", "subwoofer", "speaker_stand_120", "speaker_stand_100"]


## PLAIN_SCENES is read only when LOADING; a type with no save row is never
## written, which shipped for the Nunchuk, the table and the i.LINK hub. And the
## table is walked first-match-wins, so a row below one of its own base classes
## could never be reached (RetroDisc under RetroCartridge saved every disc as a
## cartridge).
func _test_save_registry() -> void:
	var written := ScenePersistence.saved_kind_types()
	for type: String in ScenePersistence.PLAIN_SCENES:
		_ok(type in written or type in _BUILT_TYPES, "registry/%s is written by a save row" % type)
	for type: String in written:
		_ok(ScenePersistence._is_known_type(type), "registry/%s can be loaded back" % type)
	var sp := ScenePersistence.new()
	var rows := ScenePersistence._save_kind_rows()
	for j in rows.size():
		var row: Array = rows[j]
		if row.size() > 2:
			_ok(sp.has_method(row[2] as StringName), "registry/hook %s exists" % row[2])
		for i in j:
			var earlier := (rows[i] as Array)[0] as Script
			var base := (row[0] as Script)
			var shadowed := false
			while base != null:
				if base == earlier:
					shadowed = true
				base = base.get_base_script()
			if shadowed:
				_ok(false, "registry/row %d (%s) is below its base class's row %d"
					% [j, (row[0] as Script).get_global_name(), i])
	_ok(rows.size() > 40, "registry/the table is populated (%d rows)" % rows.size())


# ── Harness ───────────────────────────────────────────────────────────────────

## Systems currently in the room. The stable half of the "spawned" population —
## cables come and go with what a console brings.
func _systems() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("spawned"):
		if node is RetroSystem:
			n += 1
	return n


func _want_group(name: String) -> bool:
	return _only.is_empty() or _only == name


func _snapshot() -> void:
	_saved_slots = SceneManager.active_slots.duplicate(true)
	_saved_scene_id = SceneManager.current_scene_id
	_saved_last_room = SceneManager.last_room_id
	_had_prefs = FileAccess.file_exists(SceneManager.PREFS_FILE)
	if _had_prefs:
		_saved_prefs_json = FileAccess.get_file_as_string(SceneManager.PREFS_FILE)
	# The manifest group creates and deletes a slot in the player's real manifest.
	# Deleting the test's own entry is not enough to leave the file as it was: the
	# rewrite round-trips every value through JSON, which turns the version int
	# into 1.0. Harmless, but the suite should leave no fingerprints at all.
	_had_manifest = FileAccess.file_exists(MANIFEST_FILE)
	if _had_manifest:
		_saved_manifest_json = FileAccess.get_file_as_string(MANIFEST_FILE)


func _restore() -> void:
	ScenePersistence.flush_pending_writes()
	SceneManager.active_slots = _saved_slots
	SceneManager.current_scene_id = _saved_scene_id
	SceneManager.last_room_id = _saved_last_room
	SceneManager._installed_room_id = ""
	SceneManager._transitioning = false
	SceneManager._pending_scene_id = ""
	SceneManager._content_ready_scene_id = ""
	SceneManager._carry_room_id = ""
	_remove_dir(ProjectSettings.globalize_path("user://scenes/" + CARRY_ROOM))
	for slot in [SLOT_A, SLOT_B]:
		var p := ProjectSettings.globalize_path("user://scenes/arcade/%s.json" % slot)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if _had_prefs:
		var f := FileAccess.open(SceneManager.PREFS_FILE, FileAccess.WRITE)
		if f:
			f.store_string(_saved_prefs_json)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SceneManager.PREFS_FILE))
	if _had_manifest:
		var mf := FileAccess.open(MANIFEST_FILE, FileAccess.WRITE)
		if mf:
			mf.store_string(_saved_manifest_json)


# ── Mains leads: what fits where, and what a slot remembers ───────────────────

## A two-prong lead has to reach a modern outlet, and a saved room has to bring
## every mains lead back still plugged in.
##
## Both halves were missing. NEMA 1-15P answered only to its own group, so the
## two-wire cords could not enter the bedroom's 5-15R at all, which no real wall
## has been true of since the sixties. And ScenePersistence only ever serialized a
## lead that `is CompositeCable`, which a PowerCord is not, so a mains lead was
## not in the slot file at any point: it vanished on reload, taking the record of
## what had been plugged into what with it.
##
## Driven through the socket's own gate rather than pick_up_object, which is the
## RESTORE path and bypasses the filter on purpose. can_preview is what decides
## whether a released plug seats, so it is what a fit case has to ask.
func _test_cords() -> void:
	var room := Node3D.new()
	add_child(room)
	# Named and nested the way the bedroom authors it, because the socket's node
	# name and the fixture it hangs off are exactly what the slot writes down.
	var wall := Node3D.new()
	wall.name = "WallOutlet"
	room.add_child(wall)
	var outlet := preload("res://Scenes/Objects/cables/power_port.tscn").instantiate() as PowerPort
	outlet.name = "TopPort"
	wall.add_child(outlet)
	await get_tree().process_frame

	_eq(outlet.snap_require, "nema_5_15_plug", "cords/a bare wall socket is a 5-15R")

	var cord := preload("res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(cord)
	cord.add_to_group("spawned")
	var polarized := preload(
		"res://Scenes/Objects/cables/nema_1_15_polarized_to_c7_polarized_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(polarized)
	var grounded := preload("res://Scenes/Objects/cables/power_cord.tscn") \
		.instantiate() as PowerCord
	room.add_child(grounded)
	await get_tree().process_frame

	_ok(outlet.can_preview(cord.wall_plug), "cords/a plain 1-15P goes into a 5-15R")
	_ok(outlet.can_preview(polarized.wall_plug), "cords/a polarized 1-15P goes into a 5-15R")
	_ok(outlet.can_preview(grounded.wall_plug), "cords/a 5-15P still goes into a 5-15R")
	_ok(not outlet.can_preview(cord.appliance_plug), "cords/a C7 is still refused by a 5-15R")
	# The other direction, which is the half that makes the rule worth having: a
	# ground pin has nowhere to go in a two-slot outlet.
	var two_slot := preload("res://Scenes/Objects/cables/power_port.tscn").instantiate() as PowerPort
	two_slot.name = "BottomPort"
	two_slot.connector = "nema_1_15_plug"
	wall.add_child(two_slot)
	await get_tree().process_frame
	_ok(not two_slot.can_preview(grounded.wall_plug),
		"cords/a 5-15P is refused by a two-slot outlet")

	# Fitting is only half of going in: up has to stay up. A snap zone seats via
	# `zone * grab_point.inverse()`, so a SnapGrabPoint carrying R_x(180), which
	# flips Y as well as Z, puts the plug in inverted, earth pin above the blades
	# and the polarized lead's wide blade over the narrow slot. The grounded lead
	# was fixed for exactly that; the two-wire cords kept the old transform, where
	# it never showed because a 1-15P could not reach a wall outlet at all.
	for lead: Array in [[cord, "a 1-15P"], [polarized, "a polarized 1-15P"],
			[grounded, "a 5-15P"]]:
		var seated: Transform3D = outlet.snap_pose_for((lead[0] as PowerCord).wall_plug)
		_ok(seated.basis.y.dot(Vector3.UP) > 0.99,
			"cords/%s seats the right way up" % lead[1])

	# ── The round trip ──
	outlet.pick_up_object(cord.wall_plug)
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(cord.wall_plug) == outlet,
		"cords/the socket knows which plug it is holding")

	var sp := ScenePersistence.new("arcade")
	var entry := sp._serialize_node(cord, 0, {})
	_ok(not entry.is_empty(), "cords/a mains lead serializes to an entry at all")
	_eq(str(entry.get("kind", "")), "nema_1_15_to_c7_cord",
		"cords/and is named by the scene it was spawned from")
	var plugs: Array = entry.get("plugs", [])
	_eq(plugs.size(), 2, "cords/both ends are recorded")
	var wall_rec: Dictionary = plugs[0]
	_eq(str(wall_rec.get("port", "")), "TopPort", "cords/the wall end names its socket")
	_eq(str(wall_rec.get("device", "")), str(wall.get_path()),
		"cords/and the fixture that socket belongs to")
	_eq(str((plugs[1] as Dictionary).get("port", "")), "",
		"cords/the loose appliance end names no socket")

	# Out of the way before the restore: one socket holds one plug, so the saved
	# lead cannot come back into an outlet the original is still standing in.
	outlet.drop_object()
	room.remove_child(cord)
	cord.queue_free()
	await get_tree().process_frame
	_ok(outlet.picked_up_object == null, "cords/the outlet is empty again")

	var spawned := sp.instantiate_objects(room, [entry])
	# restore_seating defers a frame so the rope is built first, and the socket
	# takes the plug on the frame after that.
	await get_tree().process_frame
	await get_tree().process_frame
	var back := spawned.get(0) as PowerCord
	_ok(back != null, "cords/the lead is rebuilt from its entry")
	if back != null:
		_ok(PowerCord.socket_holding(back.wall_plug) == outlet,
			"cords/and comes back plugged into the same outlet")

	room.remove_child(polarized); polarized.queue_free()
	room.remove_child(grounded); grounded.queue_free()
	remove_child(room)
	room.queue_free()
	await get_tree().process_frame


## Every corded device takes its cord with it, binned or despawned. The cord is
## spawned at the scene root rather than under the device, so each device has to
## dispose of it itself; the light gun, mouse, keyboard, multitap, Nunchuk and
## sensor bar did not, and dropping one into the storage box shrank the device
## away and left its plug and rope standing in the room.
func _test_storage() -> void:
	get_tree().current_scene = self
	var box := preload("res://Scenes/Objects/appliances/storage_box.tscn") \
		.instantiate() as StorageBox
	add_child(box)
	var corded := {
		"pad": "res://Scenes/Objects/controllers/retro_controller.tscn",
		"light gun": "res://Scenes/Objects/peripherals/light_gun.tscn",
		"mouse": "res://Scenes/Objects/peripherals/retro_mouse.tscn",
		"keyboard": "res://Scenes/Objects/peripherals/retro_keyboard.tscn",
		"multitap": "res://Scenes/Objects/controllers/retro_multitap.tscn",
		"Nunchuk": "res://Scenes/Objects/controllers/wii/nunchuk.tscn",
		"sensor bar": "res://Scenes/Objects/system_models/wii/sensor_bar.tscn",
	}
	for how: String in ["binned", "despawned"]:
		var devices: Dictionary = {}
		for label: String in corded:
			var device := (load(corded[label]) as PackedScene).instantiate() as XRToolsPickable
			add_child(device)
			devices[label] = device
		# The cord joins the room on a deferred call after _ready.
		await get_tree().process_frame
		await get_tree().process_frame
		var cords: Dictionary = {}
		for label: String in devices:
			var device: XRToolsPickable = devices[label]
			# Read off the field, not the accessor, so a device without one is
			# still caught leaving its cord behind.
			var cord: Node3D = device.get("_cable_instance")
			_ok(is_instance_valid(cord) and cord.is_inside_tree(),
				"storage/a %s has its cord in the room" % label)
			# The box asks for it by this name to unplug it before it frees it.
			_ok(device.has_method("cable_instance") and device.call("cable_instance") == cord,
				"storage/and a %s answers for it" % label)
			cords[label] = cord
			if how == "binned":
				# What the box does on the release frame.
				box._delete_with_dependents(device)
			else:
				device.queue_free()
		# Past Vanish's shrink, which is what frees a binned device.
		await get_tree().create_timer(Vanish.DURATION + 0.2).timeout
		for label: String in devices:
			_ok(not is_instance_valid(devices[label]), "storage/a %s %s is gone" % [label, how])
			_ok(not is_instance_valid(cords[label]),
				"storage/and a %s %s takes its cord and plug with it" % [label, how])
	box.queue_free()
	await get_tree().process_frame


## The 6-outlet strip: a mains lead with a body on one end and six 5-15R sockets
## on that body — one of which its own plug can go into.
func _test_power_strip() -> void:
	var room := Node3D.new()
	add_child(room)
	var strip := preload("res://Scenes/Objects/appliances/power_strip.tscn") 		.instantiate() as PowerStrip
	room.add_child(strip)
	strip.add_to_group("spawned")
	var other := preload("res://Scenes/Objects/cables/power_cord.tscn") 		.instantiate() as PowerCord
	room.add_child(other)
	await get_tree().process_frame
	await get_tree().process_frame

	var sockets := strip.sockets()
	_eq(sockets.size(), 6, "strip/six sockets")
	var names: Array[String] = []
	for s in sockets:
		names.append(String(s.name))
	_eq(names, ["Socket1", "Socket2", "Socket3", "Socket4", "Socket5", "Socket6"],
		"strip/named Socket1..6, which a save writes down")
	var body := strip.get_node("Body") as Node3D
	for s in sockets:
		_eq(s.snap_require, "nema_5_15_plug", "strip/%s is a 5-15R" % s.name)
		# Out of the top, and "up" on the outlet face (away from the ground hole)
		# along the strip toward the switch end, +X.
		_ok(s.global_basis.z.dot(Vector3.UP) > 0.99, "strip/%s faces up" % s.name)
		_ok(s.global_basis.y.dot(body.global_basis.x) > 0.99,
			"strip/%s has its ground hole toward the far end" % s.name)
		_ok(s.get_device() == strip, "strip/%s names the strip as its device" % s.name)

	var own := sockets[2]
	_ok(own.can_preview(strip.wall_plug), "strip/it accepts its own plug")
	_ok(own.can_preview(other.wall_plug), "strip/and any other 5-15P")
	_ok(not own.can_preview(other.appliance_plug), "strip/but not a C13")
	var seated: Transform3D = own.snap_pose_for(strip.wall_plug)
	# The plug's up matches the socket's, and its prongs (the plug's +Z) point
	# down INTO the strip, against the socket's outward +Z.
	_ok(seated.basis.y.dot(own.global_basis.y) > 0.99,
		"strip/a plug seats with its earth pin toward the ground hole")
	_ok(seated.basis.z.dot(Vector3.DOWN) > 0.99, "strip/prongs down into the strip")

	# The cord leaves the SWITCH end (+X), out of the end face, and is 3 ft.
	var attach := strip.get_node("Body/Shell/PowerStrip/CordAnchor") as Node3D
	var switch := strip.get_node("Body/Shell/PowerStrip/Switch") as Node3D
	_ok(attach.global_position.x > 0.14 and switch.global_position.x > 0.0,
		"strip/the cord leaves the switch end")
	_ok((-attach.global_basis.z).dot(Vector3.RIGHT) > 0.99,
		"strip/out of the end face, not into the case")
	_ok(strip.rope.start_node == attach and strip.rope.end_node == strip.wall_plug,
		"strip/the rope runs from the case to the plug")
	_ok(absf(strip.rope.segment_count * strip.rope.segment_length - 0.9144) < 0.005,
		"strip/and is three feet long")

	# ── Its own plug in its own socket, saved and restored ──
	own.pick_up_object(strip.wall_plug)
	await get_tree().process_frame
	_ok(PowerCord.socket_holding(strip.wall_plug) == own,
		"strip/its own plug seats in its own socket")
	body.global_position = Vector3(0.3, 0.2, -0.4)
	await get_tree().process_frame
	# A live rigid body: it has fallen a little by now, so compare against where
	# it IS when saved.
	var saved_at := body.global_position
	var sp := ScenePersistence.new("arcade")
	var entry := sp._serialize_node(strip, 0, {strip: 0})
	_eq(str(entry.get("kind", "")), "power_strip", "strip/serializes by kind")
	var plugs: Array = entry.get("plugs", [])
	_eq(plugs.size(), 1, "strip/one plug recorded")
	if plugs.size() == 1:
		_eq(str((plugs[0] as Dictionary).get("port", "")), "Socket3",
			"strip/the plug names the socket")
		_eq((plugs[0] as Dictionary).get("device"), 0, "strip/on the strip itself")
	var bp: Array = (entry.get("body", {}) as Dictionary).get("position", [])
	_ok(bp.size() == 3 and Vector3(bp[0], bp[1], bp[2]).distance_to(saved_at) < 0.001,
		"strip/the case's pose is recorded")

	strip.drop_and_free()
	await get_tree().process_frame
	var spawned := sp.instantiate_objects(room, [entry])
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var back := spawned.get(0) as PowerStrip
	_ok(back != null, "strip/is rebuilt from its entry")
	if back != null:
		var back_body := back.get_node("Body") as Node3D
		_ok(back_body.global_position.distance_to(saved_at) < 0.01,
			"strip/where its case was")
		var holder := PowerCord.socket_holding(back.wall_plug)
		_ok(holder != null and holder.name == &"Socket3" and holder.get_device() == back,
			"strip/and comes back plugged into itself")

		# Binning a strip lets go of a plug that is somebody else's.
		back.sockets()[0].pick_up_object(other.wall_plug)
		await get_tree().process_frame
		back.drop_and_free()
		await get_tree().process_frame
		_ok(PowerCord.socket_holding(other.wall_plug) == null and not other.wall_plug.freeze,
			"strip/binning it lets go of another cord's plug")

	room.remove_child(other); other.queue_free()
	remove_child(room)
	room.queue_free()
	await get_tree().process_frame


## A multitap in a console's port, with pads in its sockets, saved and loaded.
## The tap was saved as nothing at all, so it vanished; and each pad in it was
## saved under the port the tap fans out to, which is also one of the console's
## own sockets, so the pad in the tap's first socket came back plugged straight
## into the console's second port.
func _test_multitap() -> void:
	var room := Node3D.new()
	add_child(room)
	var built := await _multitap_room(room)
	var sys := built[0] as RetroSystem
	var tap := built[1] as RetroMultitap
	var pad_a := built[2] as RetroController
	var pad_b := built[3] as RetroController
	if tap == null:
		remove_child(room)
		room.queue_free()
		return
	tap.restore_port_connection(sys, 1)
	tap.restore_socket(0, pad_a)
	tap.restore_socket(2, pad_b)
	await _frames(6)
	_ok(tap.get_connected_system() == sys and tap.get_cabinet_port() == 1,
		"multitap/the tap is in the console's second port")
	_ok(sys.port_holder(1) == pad_a and sys.port_holder(3) == pad_b,
		"multitap/and its first and third sockets are players 2 and 4")

	var sp := ScenePersistence.new("arcade")
	var objects: Array = sp._collect_objects(room)
	var mine: Array = []
	var by_type := {}
	# The ids are positions in the "spawned" group, so read them back by node.
	var nodes := get_tree().get_nodes_in_group("spawned")
	for o: Dictionary in objects:
		var node: Node = nodes[int(o["id"])]
		if node in [sys, tap, pad_a, pad_b]:
			mine.append(o)
			by_type[node] = o
	_eq(mine.size(), 4, "multitap/the console, the tap and both pads are saved")
	_eq(ScenePersistence._objects_validation_error(mine), "", "multitap/and the save validates")
	var tap_entry: Dictionary = by_type.get(tap, {})
	_eq(str(tap_entry.get("type", "")), "retro_multitap", "multitap/the tap has an entry of its own")
	_eq(tap_entry.get("system"), (by_type.get(sys, {}) as Dictionary).get("id"),
		"multitap/naming the console")
	_eq(int(tap_entry.get("port_index", -1)), 1, "multitap/and the port it is in")
	_eq(int(tap_entry.get("tap_mode", 0)), RetroMultitap.MODE_5P, "multitap/at 5P")
	var sockets: Array = tap_entry.get("sockets", [])
	_ok(sockets.size() == 4 and sockets[0] == (by_type.get(pad_a, {}) as Dictionary).get("id")
		and sockets[1] == null and sockets[2] == (by_type.get(pad_b, {}) as Dictionary).get("id")
		and sockets[3] == null, "multitap/with each socket's pad, null where empty (%s)" % [sockets])
	for pad: Node in [pad_a, pad_b]:
		var pe: Dictionary = by_type.get(pad, {})
		_ok(int(pe.get("port_index", -1)) == -1 and pe.get("system") == null,
			"multitap/a pad in it names no console port of its own (%s)" % pe.get("port_index"))

	# As a load clears the room it is about to fill.
	sp.clear_scene(room)
	await _frames(3)
	var spawned: Dictionary = sp.instantiate_objects(room, mine)
	for node: Variant in spawned.values():
		_freeze_all(node as Node)
	await _frames(8)
	var sys2: RetroSystem = null
	var tap2: RetroMultitap = null
	for entry: Dictionary in mine:
		var node: Node = spawned.get(int(entry["id"]))
		if node is RetroSystem:
			sys2 = node
		elif node is RetroMultitap:
			tap2 = node
	var pad_a2: Node = spawned.get(int((by_type[pad_a] as Dictionary)["id"]))
	var pad_b2: Node = spawned.get(int((by_type[pad_b] as Dictionary)["id"]))
	_ok(sys2 != null and tap2 != null and pad_a2 != null and pad_b2 != null,
		"multitap/the console, the tap and both pads come back")
	if sys2 != null and tap2 != null:
		_ok(tap2.get_connected_system() == sys2 and tap2.get_cabinet_port() == 1,
			"multitap/the tap is plugged back into the console's second port")
		_eq(tap2.mode, RetroMultitap.MODE_5P, "multitap/at 5P")
		_ok(tap2.socket_of(pad_a2) == 0 and tap2.socket_of(pad_b2) == 2,
			"multitap/each pad is back in its own socket")
		_ok(sys2.port_holder(1) == pad_a2 and sys2.port_holder(3) == pad_b2,
			"multitap/and they are players 2 and 4 again")
		_ok(sys2.port_holder(0) == null, "multitap/the console's first port is still empty")

	# The SELECT switch is the tap's before it is ready, so 2P comes back as 2P.
	var two := tap_entry.duplicate(true)
	two["tap_mode"] = RetroMultitap.MODE_2P
	var tap_2p := sp._deserialize_object(two) as RetroMultitap
	_ok(tap_2p != null and tap_2p.mode == RetroMultitap.MODE_2P, "multitap/a tap saved at 2P loads at 2P")
	if tap_2p != null:
		tap_2p.free()

	sp.clear_scene(room)
	await _frames(3)
	remove_child(room)
	room.queue_free()
	await _frames(3)


## A frozen SNES, a multitap and two pads in `room`, each with its cord made.
## [system, tap, pad, pad], or nulls when a cord never appears.
func _multitap_room(room: Node3D) -> Array:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "snes"
	sys.position = Vector3(0.0, 1.0, -1.0)
	room.add_child(sys)
	sys.add_to_group("spawned")
	var tap := preload("res://Scenes/Objects/controllers/retro_multitap.tscn").instantiate() as RetroMultitap
	tap.position = Vector3(0.0, 1.0, -0.6)
	room.add_child(tap)
	var pads: Array = []
	for x: float in [-0.2, 0.2]:
		var pad := preload("res://Scenes/Objects/controllers/retro_controller.tscn").instantiate() as RetroController
		pad.position = Vector3(x, 1.0, -0.3)
		room.add_child(pad)
		pad.add_to_group("spawned")
		pads.append(pad)
	await _frames(3)
	for node: Node in [sys, tap] + pads:
		_freeze_all(node)
	if tap.cable_instance() == null or not tap.cable_instance().is_inside_tree() \
			or (pads[0] as RetroController).cable_instance() == null:
		_ok(false, "multitap/the tap and pads make their cords")
		return [sys, null, null, null]
	return [sys, tap, pads[0], pads[1]]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Nothing here has a floor under it.
func _freeze_all(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for b: Node in node.find_children("*", "RigidBody3D", true, false) + [node]:
		if b is RigidBody3D:
			(b as RigidBody3D).freeze = true


## The controller plug names no console, controller or expansion class in its code.
## A cable scene holds controller_plug.gd, and naming RetroSystem compiled
## system.gd, whose preloads reach expansion.tscn -> wiimote.tscn ->
## nunchuk_cable.tscn and so the plug's script again while it was still loading:
## when early class compiles walked into that loop at boot, every pad's cable scene
## loaded empty and no controller had its cord. Read from the source, comments left
## out, as the vlc/ group reads its own.
func _test_plug() -> void:
	var src := FileAccess.get_file_as_string("res://Scripts/Objects/cables/controller_plug.gd")
	var code := PackedStringArray()
	for line in src.split("\n"):
		var at := line.find("#")
		code.append(line.substr(0, at) if at >= 0 else line)
	var body := "\n".join(code)
	_ok(body.contains("class_name ControllerPlug"), "plug/the plug's source reads")
	for cls: String in ["RetroSystem", "RetroController", "LightGun", "RetroExpansion", "Wiimote"]:
		_ok(RegEx.create_from_string("\\b%s\\b" % cls).search(body) == null, "plug/its code names no %s" % cls)
	# The scenes that hold it load whole, the Nunchuk's at the end of the old loop.
	for path: String in ["res://Scenes/Objects/cables/controller_cable.tscn",
			"res://Scenes/Objects/controllers/wii/nunchuk_cable.tscn",
			"res://Scenes/Objects/system_models/wii/sensor_bar_cable.tscn"]:
		var scene := load(path) as PackedScene
		_ok(scene != null and scene.get_state().get_node_count() > 0, "plug/%s loads with its nodes" % path.get_file())


func _ok(cond: bool, what: String) -> void:
	_ran += 1
	if cond:
		print("[test] ok   %s" % what)
	else:
		_fail += 1
		print("[test] FAIL %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, got, want])
