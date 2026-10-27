## TestSuite — the harness every suite in RetroXR/Tests extends.
##
## One place for the three things every suite used to write for itself: the
## `_ok` / `_eq` checks, the pass/fail tally, and the closing summary line plus
## exit code. `Tools/run_tests.py` reads that ONE line,
##
##     [<tag>] RESULT <passed> passed, <failed> failed: PASS|FAIL
##
## and compares passed + failed with `Tools/test_baseline.json`, so the count a
## suite reports cannot drift with how it happens to word its summary.
##
## Suites extend it BY PATH (`extends "res://Tests/test_suite.gd"`), not by
## class name: a headless run reads class names from the editor's cache, and a
## suite must not depend on that cache being fresh to run at all.
##
## This file has no scene beside it, so the runner never mistakes it for a suite.
class_name TestSuite
extends Node

## The bracket tag on every line this suite prints ("[av] FAIL ...").
var suite_tag := "test"
## A passing check prints nothing. For suites whose thousands of PASS lines
## would bury the one FAIL worth reading.
var quiet_passes := false
## A passing check prints its detail too, for suites whose detail is a
## measurement worth reading even when it is in range (rope_tests).
var show_pass_detail := false

var _pass_count := 0
var _fail_count := 0


## One case. `detail` says how it went wrong and is printed on failure.
func _ok(cond: bool, what: String, detail: String = "") -> void:
	if not _wanted(what):
		return
	if cond:
		_pass_count += 1
		if not quiet_passes:
			var note := "  (%s)" % detail if show_pass_detail and not detail.is_empty() else ""
			print("[%s] PASS  %s%s" % [suite_tag, what, note])
		return
	_fail_count += 1
	print("[%s] FAIL  %s%s" % [suite_tag, what, "" if detail.is_empty() else "  -- " + detail])
	_on_fail(what)


## One case: `got == want`, with both printed on failure.
func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [str(got), str(want)])


## Cases recorded so far, passed and failed. The number the baseline guards.
func _case_count() -> int:
	return _pass_count + _fail_count


## Override to skip (and not count) a check, for suites that filter by the
## check's own name rather than by which group runs.
func _wanted(_what: String) -> bool:
	return true


## Override to note a failure somewhere of the suite's own (the case it was in).
func _on_fail(_what: String) -> void:
	pass


## Poll `condition` once a frame until it holds or `timeout_s` of real time has
## passed, and say whether it held. For a wait on something asynchronous (a
## shrink-and-free, a retry on a timer, an audio device draining), in place of a
## fixed timer: one is too short on a loaded CI runner, wasted on a fast box, and
## either way the case then asserts on how long the machine took. The timeout is
## a generous upper bound, not the expected time.
func _wait_until(condition: Callable, timeout_s: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not bool(condition.call()):
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## The bytes of a file the suite is about to overwrite -- the player's real
## user:// state, whose paths cannot be pointed elsewhere -- or null when there
## is none. Hand the result to _restore_file when done.
func _snapshot_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.get_file_as_bytes(path)


## Put a file back byte for byte as _snapshot_file found it, or remove it when
## there was none. A JSON round trip would not do: it turns ints into floats.
func _restore_file(path: String, saved: Variant) -> void:
	if saved == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[%s] could not restore %s: %s" % [suite_tag, path,
			error_string(FileAccess.get_open_error())])
		return
	f.store_buffer(saved as PackedByteArray)
	f.close()


## What a fresh AppPrefs reads back after the live one saved `values` ({pref:
## value}), as {pref: value read, or null when the save did not land}. Saves
## through the real save_prefs() and loads through the real loader, on an
## instance outside the tree so nothing is applied to the room; the live prefs
## and the player's file are put back as found. Save values that differ from
## the defaults, or a pref the save or the load dropped reads back unchanged.
func _app_prefs_round_trip(values: Dictionary) -> Dictionary:
	var prefs := get_node("/root/AppPrefs")
	var path: String = prefs.PREFS_PATH
	var saved_file: Variant = _snapshot_file(path)
	var live := {}
	for key: String in values:
		live[key] = prefs.get(key)
		prefs.set(key, values[key])
	var wrote: bool = prefs.save_prefs()
	for key: String in live:
		prefs.set(key, live[key])
	# Not added to the tree: AppPrefs loads in _ready, and entering the tree
	# would also apply the prefs to the running room.
	var fresh := (prefs.get_script() as GDScript).new() as Node
	fresh.load_prefs()
	var out := {}
	for key: String in values:
		out[key] = fresh.get(key) if wrote else null
	fresh.free()
	_restore_file(path, saved_file)
	return out


## A pref's value on a fresh install: an AppPrefs that has loaded nothing.
func _app_prefs_default(key: String) -> Variant:
	var fresh := (get_node("/root/AppPrefs").get_script() as GDScript).new() as Node
	var value: Variant = fresh.get(key)
	fresh.free()
	return value


## Print the summary line and quit, non-zero when anything failed. Code after
## this call still runs to the end of the frame, as it did after quit().
func _finish() -> void:
	print("[%s] RESULT %d passed, %d failed: %s" % [suite_tag, _pass_count, _fail_count,
		"PASS" if _fail_count == 0 else "FAIL"])
	get_tree().quit(0 if _fail_count == 0 else 1)
