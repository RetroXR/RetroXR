## XboxStorage — what an Xbox under xemu needs from the room: only one of it
## running, its game's saves backed up once it stops, and the Memory Units in its
## controllers carried to and from the files the core keeps them in.
##
## ONE AT A TIME. xemu is QEMU, and QEMU builds its machine once per process:
## every copy of the library the frontend loads forwards to the first, so a
## second console's load is refused by the core ("only one Xbox can run at a
## time") — and before the core learned to refuse it, two machines opened one
## hard disk image for writing. The room says no first, in its own words, the way
## it does for a second Sega CD.
##
## THE BACKUP. An Xbox game saves to the console's hard disk, which under xemu is
## one qcow2 every game shares, written by the core and never handed over: no
## SAVE_RAM, so no sram_flushed, so nothing RommSaveSync ever hears about. What
## this does instead is what a memory card does — lift the ONE game's saves out
## of the shared image and push them under that game, upload-only
## (XboxHddSaves says why). The game is known because it is the disc that was
## running; its folder on the disk is known from that disc's title id.
##
## It waits for the stop, and then a little longer. retro_unload_game is where
## xemu pauses the machine and flushes the image, and StopContent returns before
## the emulation thread has got that far. The disk is read only after that, off
## the main thread, and everything read is checked (FatxVolume) — a lift that
## fails uploads nothing, so a torn read can cost a backup and never replace one.
##
## MEMORY UNITS. A unit goes in a controller, two to a pad (the console calls
## them 1A and 1B for port 1), and xemu takes no path for one: each is a fixed
## file in the core's own save folder, switched on by an option of its own.
##
##     <root>/save/xemu/xemu/memory_unit_port<N>.img     xemu_memory_unit_port<N>    top, "A"
##     <root>/save/xemu/xemu/memory_unit_port<N>b.img    xemu_memory_unit_port<N>b   bottom, "B"
##
## So a seated unit's own image (save/memcards/xbox_mu/<card_id>.xmu) is STAGED
## into that file and the option switched on, and what the console writes is
## DRAINED back — every few seconds while it runs, for a while after it stops,
## and once more after a unit is pulled. It is flycast's VMU arrangement
## (VmuStorage) with one difference that matters: **xemu reads these options
## live**, so a unit pushed in or pulled out mid-game is a unit the console sees
## arrive or leave. Nothing waits for the next power-on.
##
## Three rules carried over from the cards that came before:
##   - a drain goes to the unit that FILLED the file, not to whatever is seated
##     now, which is why _units remembers the card id per slot;
##   - a file that does not check out as a Memory Unit is never copied back — a
##     torn read must not replace a good image;
##   - an empty slot's file is left alone, not deleted. The option says the slot
##     is empty, and a file the core is not reading harms nothing.
##
## A core build from before slot B existed declares no option for it. That is
## detected from what the core declares, and said out loud, rather than leaving
## a unit in the lower slot looking seated and doing nothing.
class_name XboxStorage
extends Node

const CORE_PREFIX := XboxHddSaves.CORE

## StopContent returns at once; the core's unload, which flushes the disk, runs
## after it and may block for 5 s of its own.
const SETTLE_AFTER_OFF_SEC := 8.0

const UNIT_FAMILY := XboxMuCardFormat.FAMILY
const UNIT_PORTS := 4
## Per SLOT of a pad, top first: the core's option key and file, by 1-based port.
const UNIT_SLOTS: Array[Dictionary] = [
	{"key": "xemu_memory_unit_port%d", "file": "memory_unit_port%d.img", "name": "A"},
	{"key": "xemu_memory_unit_port%db", "file": "memory_unit_port%db.img", "name": "B"},
]
const UNIT_ON := "enabled"
const UNIT_OFF := "disabled"

## The numbers every other core-owned card here drains by (VmuStorage).
const UNIT_POLL_SEC := 5.0
const UNIT_DRAIN_AFTER_OFF_SEC := 12.0
## After a pull, how long the slot's file is still watched before it is let go:
## the console has to notice the unit left and finish writing to it.
const UNIT_DRAIN_AFTER_PULL_SEC := 6.0
## How long after a slot's option goes off before its file may be written: the
## core closes it within the retro_run that sees the change, so a few frames —
## half a second is thirty of them.
const UNIT_RELEASE_SEC := 0.5

var _host: RetroSystem = null
## "<port>:<slot>" -> {card_id, pulled_at}: which unit filled which file this
## run. pulled_at is 0 while seated, else the wall clock of the pull.
var _units: Dictionary = {}
var _unit_dir := ""
var _unit_timer: Timer = null
var _unit_drain_until := 0.0
## Said once a run, not once a tick.
var _warned_slot_b := false
## The run to back up once it stops: {rom_path, systemid, core, label}.
var _run: Dictionary = {}
var _timer: Timer = null
var _task := -1


func setup(host: RetroSystem) -> void:
	_host = host


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


static func is_xbox_core(core: String) -> bool:
	return core.begins_with(CORE_PREFIX)


# --- One at a time ------------------------------------------------------------

## Why this machine may not start, or "": another Xbox is running.
func busy_elsewhere(core: String) -> String:
	if not is_xbox_core(core) or not is_instance_valid(_host):
		return ""
	for sys: Node in _host.get_tree().get_nodes_in_group("retro_system"):
		if sys == _host or not sys.has_method("resolve_core_name"):
			continue
		if bool(sys.get("is_powered_on")) and is_xbox_core(str(sys.call("resolve_core_name"))):
			return "Another Xbox is running, and the emulator can only be one console at a time. Power it off first."
	return ""


# --- Memory Units -------------------------------------------------------------

## Where the core keeps one slot's unit. `port` and `slot` are 0-based.
static func unit_path(root: String, port: int, slot: int) -> String:
	return root.path_join("save").path_join(XboxHddSaves.CORE).path_join(XboxHddSaves.CORE) \
		.path_join(str(UNIT_SLOTS[slot]["file"]) % (port + 1))


static func unit_key(port: int, slot: int) -> String:
	return str(UNIT_SLOTS[slot]["key"]) % (port + 1)


## "1A", "3B": what the console itself calls a slot.
static func unit_name(port: int, slot: int) -> String:
	return "%d%s" % [port + 1, str(UNIT_SLOTS[slot]["name"])]


static func _slot_key(port: int, slot: int) -> String:
	return "%d:%d" % [port, slot]


## Every Memory Unit in this machine's controllers, as {port, slot, card}. Only
## units: the same sockets hold a Dreamcast's devices, which are not this
## console's business.
func seated_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(_host):
		return out
	var ports: Array = _host.get_port_controllers()
	for port: int in mini(ports.size(), UNIT_PORTS):
		var ctrl: Node = ports[port]
		if not is_instance_valid(ctrl) or not ctrl.has_method("get_vmu_device"):
			continue
		for slot: int in mini(int(ctrl.call("vmu_slot_count")), UNIT_SLOTS.size()):
			var device: Variant = ctrl.call("get_vmu_device", slot)
			if device is XboxMuCard:
				out.append({"port": port, "slot": slot, "card": device})
	return out


## Copy each seated unit into the file the core will read and switch its option
## on — and every other slot's OFF, because the options persist in the core's
## own .opt and one left on is a unit the console still sees after it was taken
## out of the room.
func stage_units_before_start(dir: String, core: String) -> void:
	_units.clear()
	_unit_dir = dir
	_warned_slot_b = false
	if not is_xbox_core(core):
		return
	var opts: Dictionary = {}
	for port: int in UNIT_PORTS:
		for slot: int in UNIT_SLOTS.size():
			opts[unit_key(port, slot)] = UNIT_OFF
	for entry: Dictionary in seated_units():
		if _stage(dir, int(entry["port"]), int(entry["slot"]), entry["card"]):
			opts[unit_key(int(entry["port"]), int(entry["slot"]))] = UNIT_ON
	if CoreOptionsStore.merge_values(dir, core, opts):
		print("[XboxStorage] Memory Unit slots pinned before boot: %s" % str(_units.keys()))


func _stage(dir: String, port: int, slot: int, card: XboxMuCard) -> bool:
	var image := _unit_image(card)
	if image.is_empty():
		return false
	var path := unit_path(dir, port, slot)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[XboxStorage] cannot stage Memory Unit %s into %s (err %d)"
			% [card.card_id, path, FileAccess.get_open_error()])
		return false
	f.store_buffer(image)
	f.close()
	_units[_slot_key(port, slot)] = {"card_id": card.card_id, "pulled_at": 0.0}
	print("[XboxStorage] Memory Unit '%s' staged into slot %s" % [card.card_id, unit_name(port, slot)])
	return true


## One unit's image, made only for a unit this session invented. One restored
## from a saved room whose file has gone runs unbacked rather than being handed
## a blank: a fresh empty unit reads exactly like the saves were wiped.
func _unit_image(card: XboxMuCard) -> PackedByteArray:
	if card.card_id.is_empty():
		return PackedByteArray()
	var path := SramPaths.find_card(card.card_id, UNIT_FAMILY)
	if path.is_empty():
		if not card.minted:
			push_warning("[XboxStorage] Memory Unit '%s' has no image on disk - running without it rather than creating a blank" % card.card_id)
			return PackedByteArray()
		path = SramPaths.ensure_card(UNIT_FAMILY, card.card_id)
	return FileAccess.get_file_as_bytes(path)


## Copy what the console has written back into the units the files came from.
func drain_units() -> void:
	for key: String in _units:
		var bits := key.split(":")
		var data := FileAccess.get_file_as_bytes(unit_path(_unit_dir, int(bits[0]), int(bits[1])))
		# The whole tree has to walk, not only the root: this may be read while
		# the console is half way through writing a save.
		if data.is_empty() or not XboxMemoryUnit.is_consistent(data):
			continue
		var card_path := SramPaths.card_save_path(UNIT_FAMILY, str(_units[key]["card_id"]))
		if card_path.is_empty() or FileAccess.get_file_as_bytes(card_path) == data:
			continue
		var f := FileAccess.open(card_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
			print("[XboxStorage] Memory Unit '%s' written back from slot %s"
				% [_units[key]["card_id"], unit_name(int(bits[0]), int(bits[1]))])


func start_draining_units() -> void:
	if _unit_dir.is_empty() or not is_instance_valid(_host) \
			or not is_xbox_core(_host.resolve_core_name()):
		return
	_unit_drain_until = 0.0
	if _unit_timer == null:
		_unit_timer = Timer.new()
		_unit_timer.name = "XboxUnitDrainTimer"
		_unit_timer.wait_time = UNIT_POLL_SEC
		_unit_timer.timeout.connect(_on_unit_tick)
		add_child(_unit_timer)
	_unit_timer.start()
	_warn_if_slot_b_is_deaf()


func stop_draining_units_soon() -> void:
	if _unit_timer == null or _unit_timer.is_stopped():
		return
	_unit_drain_until = Time.get_unix_time_from_system() + UNIT_DRAIN_AFTER_OFF_SEC


func _on_unit_tick() -> void:
	drain_units()
	var now := Time.get_unix_time_from_system()
	# A pulled unit's slot is let go once the console has had time to finish.
	for key: String in _units.keys():
		var pulled := float(_units[key]["pulled_at"])
		if pulled > 0.0 and now - pulled >= UNIT_DRAIN_AFTER_PULL_SEC:
			_units.erase(key)
	if _unit_drain_until > 0.0 and now >= _unit_drain_until:
		_unit_timer.stop()
		_unit_drain_until = 0.0
		_units.clear()


## A unit was pushed into or pulled out of a pad's slot. Live: xemu re-reads its
## Memory Unit options every time one changes, so the console sees the unit
## arrive or leave. With the machine off there is nothing to do — the next
## power-on stages whatever is seated then.
func reapply(_ctrl: Node) -> void:
	if not is_instance_valid(_host) or not _host.is_powered_on \
			or not is_xbox_core(_host.resolve_core_name()) or _unit_dir.is_empty():
		return
	var lib: Node = _host.get_libretro_node()
	if lib == null:
		return
	var now_seated: Dictionary = {}
	for entry: Dictionary in seated_units():
		now_seated[_slot_key(int(entry["port"]), int(entry["slot"]))] = entry

	# Pulled: switch the slot off, and keep watching its file for a while.
	for key: String in _units:
		var was: Dictionary = _units[key]
		var still := now_seated.has(key) \
			and str((now_seated[key]["card"] as XboxMuCard).card_id) == str(was["card_id"])
		if still or float(was["pulled_at"]) > 0.0:
			continue
		var bits := key.split(":")
		lib.SetCoreOption(unit_key(int(bits[0]), int(bits[1])), UNIT_OFF)
		was["pulled_at"] = Time.get_unix_time_from_system()
		print("[XboxStorage] Memory Unit '%s' pulled from slot %s"
			% [was["card_id"], unit_name(int(bits[0]), int(bits[1]))])

	# Seated: whatever was in that slot goes home first, then this one goes in.
	for key: String in now_seated:
		var entry: Dictionary = now_seated[key]
		var card := entry["card"] as XboxMuCard
		if _units.has(key) and float(_units[key]["pulled_at"]) == 0.0 \
				and str(_units[key]["card_id"]) == card.card_id:
			continue
		var port := int(entry["port"])
		var slot := int(entry["slot"])
		if _units.has(key):
			# The slot's file is, or was a moment ago, open in the core, and a
			# file must never be overwritten while its option is on: the console
			# may hold the unit's FAT in memory. Off first; the core unplugs the
			# unit, which flushes and CLOSES the file, before the retro_run that
			# sees the change returns. So the old unit goes home and the new one
			# goes in a few frames later, not now.
			lib.SetCoreOption(unit_key(port, slot), UNIT_OFF)
			_seat_once_released(port, slot, card)
			continue
		if _stage(_unit_dir, port, slot, card):
			lib.SetCoreOption(unit_key(port, slot), UNIT_ON)
	start_draining_units()


## Stage `card` into a slot the core has just been told to let go of.
func _seat_once_released(port: int, slot: int, card: XboxMuCard) -> void:
	await get_tree().create_timer(UNIT_RELEASE_SEC).timeout
	if not is_instance_valid(card) or not is_instance_valid(_host) or not _host.is_powered_on:
		return
	# Still in that slot? A hand can change its mind inside half a second.
	var still := false
	for entry: Dictionary in seated_units():
		if entry["card"] == card and int(entry["port"]) == port and int(entry["slot"]) == slot:
			still = true
	if not still:
		return
	drain_units()
	var lib: Node = _host.get_libretro_node()
	if lib != null and _stage(_unit_dir, port, slot, card):
		lib.SetCoreOption(unit_key(port, slot), UNIT_ON)


func _warn_if_slot_b_is_deaf() -> void:
	if _warned_slot_b or not _host.core_options_known():
		return
	for key: String in _units:
		var bits := key.split(":")
		if int(bits[1]) == 0 or _host.core_declares_option(unit_key(int(bits[0]), int(bits[1]))):
			continue
		_warned_slot_b = true
		push_warning("[XboxStorage] this build of xemu has no option for the lower Memory Unit slot: the unit in %s is not seen by the console"
			% unit_name(int(bits[0]), int(bits[1])))
		var toast := _host.machine_toast()
		if toast != null:
			toast.show_notice(_host.display_name_for_toast(), "Lower slot not supported",
				"This build of the Xbox core only reads a controller's top Memory Unit slot. Move the unit up, or update the core.",
				Color(1.0, 0.72, 0.2))
		return


# --- The backup ---------------------------------------------------------------

## Called as content starts. Records WHICH disc, because by the time the machine
## stops its tray may hold another, or nothing.
func note_started(core: String) -> void:
	_run.clear()
	if not is_xbox_core(core) or not is_instance_valid(_host) or _host.rom_path.is_empty():
		return
	_run = {
		"rom_path": _host.rom_path,
		"systemid": _host.resolve_systemid(),
		"core": core,
		"label": _host.content_label(),
	}


func backup_after_stop() -> void:
	if _run.is_empty() or not SaveSync.is_available():
		return
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_backup_now)
		add_child(_timer)
	_timer.start(SETTLE_AFTER_OFF_SEC)


func _backup_now() -> void:
	# Powered on again inside the wait: the core holds the disk open for writing
	# and this run's stop will come round. Reading now would be reading live.
	if _run.is_empty() or _task >= 0 \
			or (is_instance_valid(_host) and _host.is_powered_on):
		return
	var run := _run.duplicate()
	_run.clear()
	var rom_id := SaveSync.rom_id_for(str(run["systemid"]), str(run["rom_path"]))
	if rom_id <= 0:
		return
	run["rom_id"] = rom_id
	run["hdd"] = XboxHddSaves.hdd_path()
	_task = WorkerThreadPool.add_task(_lift.bind(run), false, "Xbox save backup")


## Off the main thread: a disc image is opened, and a disk read through two
## levels of table.
func _lift(run: Dictionary) -> void:
	var archive := archive_for(str(run["rom_path"]), str(run["hdd"]))
	_lifted.call_deferred(run, archive)


func _lifted(run: Dictionary, archive: Dictionary) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if not bool(archive["ok"]):
		push_warning("[XboxStorage] no backup of %s: %s" % [run["label"], archive["error"]])
		return
	var bytes: PackedByteArray = archive["bytes"]
	if bytes.is_empty():
		return
	var title_id := str(archive["title_id"])
	var key := RommSaveSync.card_save_key(str(run["hdd"]), title_id)
	# Recorded either way, as a card save's owner is: it is what lets a save
	# opted in later be uploaded without the game having to run again.
	SaveSync.note_card_save_owner(key, int(run["rom_id"]))
	if not SaveSync.is_key_enabled(key):
		return
	SaveSync.push_card_save(key, int(run["rom_id"]), str(run["core"]), title_id,
		str(run["label"]), bytes, XboxHddSaves.ARCHIVE_EXT)


## The archive of what the game on `rom_path` keeps on the disk at `hdd`:
## {ok, error, title_id, bytes}. `bytes` is empty, with ok true, for a game that
## has saved nothing — nothing to upload, and not a failure. Static and free of
## the room so a suite can drive it over a disc and a disk it built itself.
static func archive_for(rom_path: String, hdd: String) -> Dictionary:
	var title := XboxDisc.title_of(rom_path)
	if title.is_empty():
		return {"ok": false, "error": "cannot read a title id off the disc",
			"title_id": "", "bytes": PackedByteArray()}
	var title_id := str(title["title_id"])
	var lifted := XboxHddSaves.lift(hdd, title_id)
	if not bool(lifted["ok"]):
		return {"ok": false, "error": str(lifted["error"]),
			"title_id": title_id, "bytes": PackedByteArray()}
	var files: Dictionary = lifted["files"]
	return {"ok": true, "error": "", "title_id": title_id,
		"bytes": XboxHddSaves.pack(files) if not files.is_empty() else PackedByteArray()}
