## SaturnStorage — tells Beetle Saturn where a Sega Saturn's memories are, and
## carries a Backup RAM Cartridge's in and out of the file the core keeps it in.
##
## The System Memory needs no carrying: in its "libretro" save method the core
## hands it over through SAVE_RAM, and ConsoleMemory is the file. A cartridge's
## memory the core keeps itself, in the save directory it is handed
## (<root>/save/<core>), named after the disc unless shared_ext is on; it reads
## it at load and flushes it about three seconds after a game writes and again as
## it unloads. So the options are pinned for the run:
##
##     beetle_saturn_save_method  "libretro"
##     beetle_saturn_shared_ext   "enabled"  ->  mednafen_saturn_libretro_shared.bcr
##     beetle_saturn_cart         "Backup Memory" with a cartridge seated, "None" without
##
## and a seated cartridge's image is STAGED into that file before content starts,
## then drained back while the game runs and for a while after it stops. The
## folder is shared by every machine on this core, which is why one Saturn with a
## cartridge may run at a time, and why a manifest on disk records which image
## filled the file: a crash between staging and draining must still put the saves
## back where they belong.
##
## Cartridge files found there that no manifest accounts for -- one per disc, from
## before a cartridge was a thing in the room -- are moved into legacy/ rather
## than written over, and a new cartridge starts from the saves they hold.
class_name SaturnStorage
extends Node

const CORE_PREFIX := ConsoleMemory.SAVE_RAM_CORE
const CART_FAMILY := "sega_saturn_ram_cart"
const CART_FILE := "mednafen_saturn_libretro_shared.bcr"
const MANIFEST := ".retroxr_saturn_cart.json"
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

## The Backup RAM Cartridge among these units, or null.
static func cart_of(expansions: Array) -> RetroExpansion:
	for held: Variant in expansions:
		if is_instance_valid(held) and held is RetroExpansion \
				and (held as RetroExpansion).family == CART_FAMILY:
			return held
	return null


## Empty on another core.
static func forced_options(core: String, has_cart: bool) -> Dictionary:
	if not core.begins_with(CORE_PREFIX):
		return {}
	return {
		"beetle_saturn_save_method": "libretro",
		"beetle_saturn_shared_ext": "enabled",
		"beetle_saturn_cart": "Backup Memory" if has_cart else "None",
	}


func forced_options_for(core: String) -> Dictionary:
	if not is_instance_valid(_host):
		return {}
	return forced_options(core, cart_of(_host.get_expansions()) != null)


## Why this machine may not start with its cartridge, or "": the folder is shared,
## and another machine is running one or has not finished writing it back.
func busy_elsewhere(core: String) -> String:
	if not core.begins_with(CORE_PREFIX) or not is_instance_valid(_host):
		return ""
	if cart_of(_host.get_expansions()) == null:
		return ""
	for sys: Node in _host.get_tree().get_nodes_in_group("retro_system"):
		if sys == _host or not sys.has_method("saturn_storage"):
			continue
		var other: SaturnStorage = sys.call("saturn_storage")
		if other == null or not other.is_holding_files():
			continue
		if bool(sys.get("is_powered_on")):
			return "Another Saturn with a Backup RAM Cartridge is running. Power it off first."
		return "Another Saturn is still saving its cartridge. Try again in a few seconds."
	return ""


func is_holding_files() -> bool:
	return not _staged.is_empty()


# --- Before the core starts ---------------------------------------------------

## Put a seated cartridge where the core will read it. Touches nothing when none
## is seated: the core is told there is no cartridge, and the folder may be
## another Saturn's.
func stage_before_start(dir: String, core: String) -> void:
	_finish()
	if not core.begins_with(CORE_PREFIX) or not is_instance_valid(_host):
		return
	var cart := cart_of(_host.get_expansions())
	if cart == null:
		return
	_save_dir = dir.path_join("save").path_join(core)
	DirAccess.make_dir_recursive_absolute(_save_dir)
	if recover(_save_dir):
		print("[SaturnStorage] recovered the cartridge a previous run left staged")
	for moved: String in set_aside_unclaimed(_save_dir):
		print("[SaturnStorage] kept unclaimed cartridge saves at %s" % moved)

	var image := _image_for(cart)
	var bytes := FileAccess.get_file_as_bytes(image) if not image.is_empty() else PackedByteArray()
	if bytes.size() != SaturnBram.CART_SIZE or not SaturnBram.is_card_image(bytes):
		push_warning("[SaturnStorage] %s is not a Backup RAM Cartridge image; not staged" % image)
		return
	var file := _save_dir.path_join(CART_FILE)
	if not _write(file, bytes):
		return
	_staged = {"file": file, "image": image, "card_id": cart.card_id, "bytes": bytes}
	var f := FileAccess.open(_save_dir.path_join(MANIFEST), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"file": file, "image": image, "card_id": cart.card_id}))
		f.close()
	_start_timer()


## A cartridge's image path, made when it has none. Unlike SegaCdStorage this makes
## one for a restored cartridge too: the core is told a cartridge is seated either
## way, and what it wrote to a file nobody staged would never come home.
func _image_for(cart: RetroExpansion) -> String:
	var path := SramPaths.find_card(cart.card_id, CART_FAMILY)
	if not path.is_empty():
		return path
	var legacy := adopt_legacy(_save_dir)
	if legacy.is_empty():
		return SramPaths.ensure_card(CART_FAMILY, cart.card_id)
	path = SramPaths.card_save_path(CART_FAMILY, cart.card_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return path if _write(path, legacy) else ""


# --- While it runs, and after it stops ----------------------------------------

func _start_timer() -> void:
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "SaturnCartDrainTimer"
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
## changed it -- never to whatever is seated now. A file that does not parse is
## skipped, not copied.
func drain() -> bool:
	if _staged.is_empty():
		return false
	var data := FileAccess.get_file_as_bytes(str(_staged["file"]))
	if data.is_empty() or data == _staged["bytes"] or not SaturnBram.is_card_image(data):
		return false
	if not _write(str(_staged["image"]), data):
		return false
	_staged["bytes"] = data
	print("[SaturnStorage] %s -> %s (%d bytes)" % [CART_FILE, _staged["card_id"], data.size()])
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
		if SaturnBram.is_card_image(data) and not image.is_empty() \
				and FileAccess.get_file_as_bytes(image) != data:
			restored = _write(image, data)
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(manifest)
	return restored


# --- Saves from before ----------------------------------------------------------

## Move the core's cartridge files no manifest claimed into legacy/, never over an
## earlier copy. Returns where each one went.
static func set_aside_unclaimed(save_dir: String) -> Array[String]:
	var moved: Array[String] = []
	var legacy := save_dir.path_join(LEGACY_DIR)
	for name: String in DirAccess.get_files_at(save_dir):
		if name.get_extension().to_lower() != "bcr":
			continue
		DirAccess.make_dir_recursive_absolute(legacy)
		var dst := legacy.path_join(name)
		var n := 2
		while FileAccess.file_exists(dst):
			dst = legacy.path_join("%s %d.bcr" % [name.get_basename(), n])
			n += 1
		if DirAccess.rename_absolute(save_dir.path_join(name), dst) == OK:
			moved.append(dst)
	return moved


## A new cartridge's image, from every unclaimed cartridge file holding saves,
## newest first, as far as they fit. Each one used is renamed .imported so a second
## new cartridge does not start from the same saves. Empty when none held any.
static func adopt_legacy(save_dir: String) -> PackedByteArray:
	var legacy := save_dir.path_join(LEGACY_DIR)
	if not DirAccess.dir_exists_absolute(legacy):
		return PackedByteArray()
	var found: Array[Dictionary] = []
	for name: String in DirAccess.get_files_at(legacy):
		if name.get_extension().to_lower() != "bcr":
			continue
		var path := legacy.path_join(name)
		var data := FileAccess.get_file_as_bytes(path)
		if data.size() == SaturnBram.CART_SIZE and not SaturnBram.list_files(data).is_empty():
			found.append({"path": path, "data": data, "time": FileAccess.get_modified_time(path)})
	if found.is_empty():
		return PackedByteArray()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["time"]) > int(b["time"]))
	var image := SaturnBram.blank_image(SaturnBram.CART_SIZE)
	for e: Dictionary in found:
		image = SaturnBram.merge(image, e["data"])
		DirAccess.rename_absolute(str(e["path"]), str(e["path"]) + ".imported")
		print("[SaturnStorage] a new cartridge takes the saves in %s" % str(e["path"]))
	return image


static func _write(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[SaturnStorage] cannot write %s" % path)
		return false
	f.store_buffer(data)
	f.close()
	return true
