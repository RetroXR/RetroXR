class_name MediaLabelLoader
extends Node
## Decodes the pictures a medium (tape, cassette, record) wears. The medium says
## which picture it wants in each named slot and the loader decodes them off the
## main thread, one pool task per slot, announcing each as it lands. It is a
## child of the medium, so it dies with it, and one freed while a decode is
## running waits for the pool thread, which writes into the loader's own job.

## `texture` is null when the slot's picture is gone or would not decode.
signal art_ready(slot: StringName, texture: Texture2D)

## Cut each picture to its middle square (the record's round label).
var square := false

var _slots: Dictionary = {}   # StringName -> Slot


class Slot extends RefCounted:
	var path := ""
	var task := -1
	var job: Dictionary = {}


func _ready() -> void:
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for slot: Slot in _slots.values():
			if slot.task != -1:
				WorkerThreadPool.wait_for_task_completion(slot.task)


## Say which picture each slot wants now: slot -> path, "" for none. A slot whose
## path has not changed is left alone, and one that changes while its decode runs
## only changes what is wanted; _process starts the next decode when it lands.
func request(wanted: Dictionary) -> void:
	for key: StringName in wanted:
		var slot := _slots.get(key) as Slot
		if slot == null:
			slot = Slot.new()
			_slots[key] = slot
		var path := str(wanted[key])
		if path == slot.path:
			continue
		slot.path = path
		if slot.task == -1:
			_step(key, slot)


func _step(key: StringName, slot: Slot) -> void:
	if slot.path.is_empty():
		art_ready.emit(key, null)
		return
	slot.job = {"path": slot.path, "square": square}
	slot.task = WorkerThreadPool.add_task(MediaLabelArt.decode_into.bind(slot.job))
	set_process(true)


func _process(_delta: float) -> void:
	var busy := false
	for key: StringName in _slots.keys():
		var slot := _slots[key] as Slot
		if slot.task == -1:
			continue
		if not WorkerThreadPool.is_task_completed(slot.task):
			busy = true
			continue
		WorkerThreadPool.wait_for_task_completion(slot.task)
		slot.task = -1
		if str(slot.job.get("path", "")) != slot.path:
			_step(key, slot)
			busy = busy or slot.task != -1
			continue
		art_ready.emit(key, MediaLabelArt.texture_from(slot.job.get("image") as Image))
	set_process(busy)
