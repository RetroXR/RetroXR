class_name BackgroundTask
extends RefCounted
## A WorkerThreadPool task that nobody has to wait for.
##
## Godot keeps every task it is given until `wait_for_task_completion` claims it, and a task nobody claims stays in
## the pool -- lambda, captures and all -- for the rest of the session, and is only freed when the engine tears the
## pool down, AFTER the script languages have finished. A GDScript lambda freed then crashed the Quest on quit
## (`GDScript::cancel_pending_functions` under `WorkerThreadPool::finish`, tombstone 2026-11-09). The engine now lets
## go of those itself (docs/godot-4.7.2-worker-pool-shutdown.patch), but a fire-and-forget job should still not leak
## until then: `start` claims the task on the main thread as soon as the job has returned.
##
## Use it wherever the task id would otherwise be thrown away. A caller that keeps the id and waits on it does not
## need this.

## Tasks started here and not yet claimed. Read by `pending()` (a suite), written on the main thread only.
static var _open := {}


## Run `job` on the worker pool; the task is claimed once it has run. Returns the task id.
static func start(job: Callable, high_priority := false, description := "") -> int:
	var box := [-1]
	var id := WorkerThreadPool.add_task(func() -> void:
		job.call()
		BackgroundTask._claim.call_deferred(box), high_priority, description)
	box[0] = id
	_open[id] = description
	return id


## How many tasks started here are still unclaimed.
static func pending() -> int:
	return _open.size()


static func _claim(box: Array) -> void:
	var id := int(box[0])
	if id < 0:
		push_warning("[BackgroundTask] a task finished before its id was known; it is not claimed")
		return
	# The job has returned; at most the wrapper's last line is still running, so this does not block.
	WorkerThreadPool.wait_for_task_completion(id)
	_open.erase(id)
