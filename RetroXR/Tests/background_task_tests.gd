## BackgroundTask self-tests -- a fire-and-forget WorkerThreadPool task is claimed once it has run.
##
##     "$godot" --headless --path RetroXR res://Tests/background_task_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## An unclaimed task keeps its lambda and captures in the pool until engine teardown, after GDScript has finished,
## where freeing it crashed the Quest on quit (tombstone 2026-11-09). The engine patch covers teardown; this covers
## the session: nothing started through BackgroundTask is left behind once its job has returned.
extends "res://Tests/test_suite.gd"


func _ready() -> void:
	suite_tag = "background_task"
	var before := BackgroundTask.pending()
	var ran: Array[int] = []
	var lock := Mutex.new()
	var big := PackedByteArray()
	big.resize(1 << 20)
	var ids: Array[int] = []
	for i in 8:
		ids.append(BackgroundTask.start(func() -> void:
			lock.lock()
			ran.append(big.size())
			lock.unlock(), false, "background_task_tests %d" % i))
	_ok(BackgroundTask.pending() == before + 8, "claim/eight jobs started are eight tasks open", str(BackgroundTask.pending()))
	var deadline := Time.get_ticks_msec() + 5000
	while BackgroundTask.pending() > before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok(ran.size() == 8, "claim/every job ran on the pool", str(ran.size()))
	_ok(BackgroundTask.pending() == before, "claim/every task is claimed once its job has returned (none left in the pool)", str(BackgroundTask.pending()))
	# A claimed id is gone from the pool: Godot answers an unknown id with an error and `true`; is_task_completed on a
	# claimed one would only be meaningful before the claim, so the check is the counter above. The ids were distinct.
	var distinct := {}
	for id in ids:
		distinct[id] = true
	_ok(distinct.size() == 8, "claim/each job is its own task", str(distinct.size()))
	_finish()
