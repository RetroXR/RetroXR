## ThreeDoStorage — puts a 3DO's NVRAM where Opera reads it, and brings back what
## it wrote.
##
## The NVRAM is the console's (ConsoleMemory), but Opera hands it over through no
## SAVE_RAM: it keeps the memory in a file of its own under the save directory it
## is handed (<root>/save/<core>), reads it in retro_load_game and writes it in
## retro_unload_game, on a reset, and before an ODE launch switches discs. Left to
## itself it keeps one per game ("per game", its default, under opera/per_game/),
## which is not how the machine works: every game on a 3DO saves to the same 32 KB.
## So the options are pinned for the run:
##
##     opera_nvram_storage  "shared"  ->  opera/shared/nvram.<version>.srm
##     opera_nvram_version  "0"
##
## and the console's image is STAGED into that file before content starts, then
## drained back while the game runs and for a while after it stops. The folder is
## shared by every machine on this core, which is why one 3DO may run at a time,
## and why a manifest on disk records which image filled the file: a crash between
## staging and draining must still put the saves back where they belong.
##
## The first NVRAM image ever made takes the saves Opera kept per game before the
## console kept them, which stay where they are. A shared file no manifest
## accounts for -- the player switched the option on, or an older Opera's
## 3DO.nvram -- is moved into legacy/ rather than written over, and a new console's
## NVRAM starts from the saves it holds.
class_name ThreeDoStorage
extends Node

const CORE_PREFIX := "opera"
const MEMORY_FAMILY := "3do_nvram"
const NVRAM_VERSION := "0"
## Under the save directory Opera is handed.
const NVRAM_FILE := "opera/shared/nvram.0.srm"
const PER_GAME_DIR := "opera/per_game"
const SHARED_DIR := "opera/shared"
## Where an Opera before the opera/ folder kept its shared memory, and still looks
## when there is no file in it.
const OLD_NVRAM_FILE := "3DO.nvram"
const MANIFEST := ".retroxr_3do.json"
const LEGACY_DIR := "legacy"

## The core's last write lands on the emulation thread after StopContent returns,
## so draining keeps looking for a while: MemoryCardController's number.
const DRAIN_AFTER_OFF_SEC := 12.0
const DRAIN_POLL_SEC := 2.0

var _host: RetroSystem = null
## The file staged this run: {file, image, card_id, bytes}. Empty when none is.
var _staged: Dictionary = {}
var _save_dir := ""
var _timer: Timer = null
var _drain_until := 0.0


func setup(host: RetroSystem) -> void:
	_host = host


func _exit_tree() -> void:
	# Written back if the core has already written, but the file and manifest stay:
	# a write still to come is recovered at the next start.
	drain()


# --- What the core is told ----------------------------------------------------

## Opera, on a console with NVRAM of its own.
func _keeps_memory(core: String) -> bool:
	return core.begins_with(CORE_PREFIX) and is_instance_valid(_host) \
		and _host.console_memory() != null \
		and _host.console_memory().family == MEMORY_FAMILY


## Empty on another core or a console without the memory.
static func forced_options(core: String, has_memory: bool) -> Dictionary:
	if not core.begins_with(CORE_PREFIX) or not has_memory:
		return {}
	return {"opera_nvram_storage": "shared", "opera_nvram_version": NVRAM_VERSION}


func forced_options_for(core: String) -> Dictionary:
	return forced_options(core, _keeps_memory(core))


## Why this machine may not start, or "": the file is shared, and another machine
## is running a 3DO or has not finished writing its NVRAM back.
func busy_elsewhere(core: String) -> String:
	if not _keeps_memory(core):
		return ""
	for sys: Node in _host.get_tree().get_nodes_in_group("retro_system"):
		if sys == _host or not sys.has_method("three_do_storage"):
			continue
		var other: ThreeDoStorage = sys.call("three_do_storage")
		if other == null or not other.is_holding_files():
			continue
		if bool(sys.get("is_powered_on")):
			return "Another 3DO is running. Power it off first."
		return "Another 3DO is still saving. Try again in a few seconds."
	return ""


func is_holding_files() -> bool:
	return not _staged.is_empty()


# --- Before the core starts ---------------------------------------------------

## Put the console's NVRAM where the core will read it.
func stage_before_start(dir: String, core: String) -> void:
	_finish()
	if not _keeps_memory(core):
		return
	_save_dir = dir.path_join("save").path_join(core)
	DirAccess.make_dir_recursive_absolute(_save_dir.path_join(SHARED_DIR))
	if recover(_save_dir):
		print("[ThreeDoStorage] recovered the NVRAM a previous run left staged")
	for moved: String in set_aside_unclaimed(_save_dir):
		print("[ThreeDoStorage] kept unclaimed NVRAM at %s" % moved)

	var own := _host.console_memory()
	var image := _image_for(own)
	var bytes := FileAccess.get_file_as_bytes(image) if not image.is_empty() else PackedByteArray()
	if not ThreeDoNvram.is_card_image(bytes):
		push_warning("[ThreeDoStorage] %s is not a 3DO NVRAM image; not staged" % image)
		return
	var file := _save_dir.path_join(NVRAM_FILE)
	if not _write(file, bytes):
		return
	_staged = {"file": file, "image": image, "card_id": own.card_id, "bytes": bytes}
	var f := FileAccess.open(_save_dir.path_join(MANIFEST), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"file": file, "image": image, "card_id": own.card_id}))
		f.close()
	_start_timer()


## The console's image path, made when it has none: a console's memory has nowhere
## else to be (ConsoleMemory.minted), so a missing one is memory whose battery ran
## out, and the console runs with a formatted one. A new image starts from any
## unclaimed shared memory, and the first of the family ever from the saves Opera
## kept per game as well.
func _image_for(own: ConsoleMemory) -> String:
	var path := SramPaths.find_card(own.card_id, MEMORY_FAMILY)
	if not path.is_empty():
		return path
	var image := adopt_legacy(_save_dir, ThreeDoNvram.blank_image())
	if SramPaths.list_cards(MEMORY_FAMILY).is_empty():
		image = adopt_per_game(_save_dir, image)
	path = SramPaths.card_save_path(MEMORY_FAMILY, own.card_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return path if _write(path, image) else ""


# --- While it runs, and after it stops ----------------------------------------

func _start_timer() -> void:
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "ThreeDoDrainTimer"
		_timer.wait_time = DRAIN_POLL_SEC
		_timer.timeout.connect(_on_drain_tick)
		add_child(_timer)
	_timer.start()


## Write back what the core has written so far and keep looking until its final
## write has had time to land, then clear the folder.
func drain_after_stop() -> void:
	if _staged.is_empty():
		return
	drain()
	_drain_until = Time.get_unix_time_from_system() + DRAIN_AFTER_OFF_SEC
	_start_timer()


func _on_drain_tick() -> void:
	drain()
	if _drain_until > 0.0 and Time.get_unix_time_from_system() >= _drain_until:
		_finish()


## Copy the staged file back to the image that filled it, when the core has
## changed it -- never to whatever console is asking now. A file that does not
## parse is skipped, not copied.
func drain() -> bool:
	if _staged.is_empty():
		return false
	var data := FileAccess.get_file_as_bytes(str(_staged["file"]))
	if data.is_empty() or data == _staged["bytes"] or not ThreeDoNvram.is_card_image(data):
		return false
	if not _write(str(_staged["image"]), data):
		return false
	_staged["bytes"] = data
	print("[ThreeDoStorage] %s -> %s (%d files)"
		% [NVRAM_FILE.get_file(), _staged["card_id"], ThreeDoNvram.list_files(data).size()])
	return true


func _finish() -> void:
	if _timer != null:
		_timer.stop()
	_drain_until = 0.0
	if _staged.is_empty():
		return
	drain()
	DirAccess.remove_absolute(str(_staged["file"]))
	DirAccess.remove_absolute(_save_dir.path_join(MANIFEST))
	_staged.clear()


## Put back what a run that never finished draining left in the folder, by its
## manifest, and clear it. True when an image was written.
static func recover(save_dir: String) -> bool:
	var manifest := save_dir.path_join(MANIFEST)
	if not FileAccess.file_exists(manifest):
		return false
	var restored := false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if parsed is Dictionary:
		var file := str((parsed as Dictionary).get("file", ""))
		var image := str((parsed as Dictionary).get("image", ""))
		var data := FileAccess.get_file_as_bytes(file)
		if ThreeDoNvram.is_card_image(data) and not image.is_empty() \
				and FileAccess.get_file_as_bytes(image) != data:
			restored = _write(image, data)
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(manifest)
	return restored


# --- Saves from before ----------------------------------------------------------

## Move every shared NVRAM file no manifest claimed into legacy/, never over an
## earlier copy, so the core cannot read one in place of the console's. Returns
## where each one went.
static func set_aside_unclaimed(save_dir: String) -> Array[String]:
	var found: Array[String] = []
	var shared := save_dir.path_join(SHARED_DIR)
	if DirAccess.dir_exists_absolute(shared):
		for name: String in DirAccess.get_files_at(shared):
			if name.get_extension().to_lower() == "srm":
				found.append(shared.path_join(name))
	if FileAccess.file_exists(save_dir.path_join(OLD_NVRAM_FILE)):
		found.append(save_dir.path_join(OLD_NVRAM_FILE))
	var moved: Array[String] = []
	var legacy := save_dir.path_join(LEGACY_DIR)
	for src: String in found:
		DirAccess.make_dir_recursive_absolute(legacy)
		var name := src.get_file()
		var dst := legacy.path_join(name)
		var n := 2
		while FileAccess.file_exists(dst):
			dst = legacy.path_join("%s %d.%s" % [name.get_basename(), n, name.get_extension()])
			n += 1
		if DirAccess.rename_absolute(src, dst) == OK:
			moved.append(dst)
	return moved


## `image` with the files from every unclaimed NVRAM in legacy/, newest first, as
## far as they fit. Each one used is renamed .imported, so a second new console
## does not start from the same saves.
static func adopt_legacy(save_dir: String, image: PackedByteArray) -> PackedByteArray:
	var legacy := save_dir.path_join(LEGACY_DIR)
	var found := _images_in(legacy, ["srm", "nvram"])
	var out := image
	for e: Dictionary in found:
		out = ThreeDoNvram.merge(out, e["data"])
		DirAccess.rename_absolute(str(e["path"]), str(e["path"]) + ".imported")
		print("[ThreeDoStorage] a new NVRAM takes the saves in %s" % str(e["path"]))
	return out


## `image` with the files from every NVRAM Opera kept per game, newest first, as
## far as they fit. The files stay where they are: nothing here reads them again,
## and they are the player's.
static func adopt_per_game(save_dir: String, image: PackedByteArray) -> PackedByteArray:
	var out := image
	for e: Dictionary in _images_in(save_dir.path_join(PER_GAME_DIR), ["srm"]):
		out = ThreeDoNvram.merge(out, e["data"])
		print("[ThreeDoStorage] the first NVRAM takes the saves in %s" % str(e["path"]))
	return out


## Every NVRAM image in `dir` holding a file, newest first: {path, data}.
static func _images_in(dir: String, extensions: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for name: String in DirAccess.get_files_at(dir):
		if not extensions.has(name.get_extension().to_lower()):
			continue
		var path := dir.path_join(name)
		var data := FileAccess.get_file_as_bytes(path)
		if not ThreeDoNvram.list_files(data).is_empty():
			found.append({"path": path, "data": data, "time": FileAccess.get_modified_time(path)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["time"]) > int(b["time"]))
	return found


static func _write(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[ThreeDoStorage] cannot write %s" % path)
		return false
	f.store_buffer(data)
	f.close()
	return true
