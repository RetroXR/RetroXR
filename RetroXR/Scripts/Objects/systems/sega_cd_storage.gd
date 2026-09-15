## SegaCdStorage — puts a Sega CD's backup memory, and a Backup RAM Cartridge's,
## where genesis_plus_gx reads them, and brings back what it wrote.
##
## The core keeps both memories in files of its own in the save directory it is
## handed (<root>/save/<core>). It reads them in retro_load_game and writes them
## only in retro_unload_game: never while the game runs, never through SAVE_RAM.
## Their names are fixed by three options, pinned for the run:
##
##     genesis_plus_gx_system_bram "per bios"  ->  scd_U.brm / scd_E.brm / scd_J.brm
##     genesis_plus_gx_cart_bram   "per cart"  ->  <size>_cart.brm
##     genesis_plus_gx_cart_size   the seated cartridge's size, or "disabled"
##
## So a unit's image is STAGED into all three region files before content starts
## (which one the core reads is the disc's region, unknown until it has read the
## disc) and the file the core rewrote is drained back after it stops. The folder
## is shared by every machine on this core, which is why one Sega CD may run at a
## time, and why a manifest on disk records which image filled which file: a crash
## between staging and draining must still put the saves back where they belong.
##
## Files found there that no manifest accounts for are saves from before a unit
## kept its own. They are moved into legacy/ rather than written over, and a new
## unit or cartridge with no image yet starts from the most recent one that fits.
class_name SegaCdStorage
extends Node

const CORE_PREFIX := "genesis_plus_gx"
const MEMORY_FAMILY := "sega_cd_memory"
const CART_FAMILY := "sega_cd_ram_cart"
const REGION_FILES := ["scd_U.brm", "scd_E.brm", "scd_J.brm"]
## A cartridge image's size, as the core's cart_size value and the file it names.
const CART_SIZES := {
	0x4000: ["128k", "128Kbit_cart.brm"],
	0x8000: ["256k", "256Kbit_cart.brm"],
	0x10000: ["512k", "512Kbit_cart.brm"],
	0x20000: ["1meg", "1Mbit_cart.brm"],
	0x40000: ["2meg", "2Mbit_cart.brm"],
	0x80000: ["4meg", "4Mbit_cart.brm"],
}
const MANIFEST := ".retroxr_sega_cd.json"
const LEGACY_DIR := "legacy"
## Options whose change mid-game makes the core rebuild the machine, which zeroes
## both memories in RAM and never reads them back. Held while it runs.
const REINIT_KEYS := ["genesis_plus_gx_system_hw", "genesis_plus_gx_bios",
	"genesis_plus_gx_region_detect", "genesis_plus_gx_vdp_mode"]

## The core's write lands on the emulation thread after StopContent returns, so
## draining keeps looking for a while: MemoryCardController's number.
const DRAIN_AFTER_OFF_SEC := 12.0
const DRAIN_POLL_SEC := 1.0

var _host: RetroSystem = null
## One entry per file staged this run: {file, image, card_id, bytes}.
var _staged: Array[Dictionary] = []
var _save_dir := ""
var _timer: Timer = null
var _drain_until := 0.0


func setup(host: RetroSystem) -> void:
	_host = host


func _exit_tree() -> void:
	# Written back if the core has already written, but the files and manifest
	# stay: a write still to come is recovered at the next start.
	drain()


# --- What the core is told ----------------------------------------------------

## The attached memories, as {memory, cart}; either may be null.
static func memory_units(expansions: Array) -> Dictionary:
	var out := {"memory": null, "cart": null}
	for held: Variant in expansions:
		if not is_instance_valid(held) or not (held is RetroExpansion):
			continue
		var unit := held as RetroExpansion
		if unit.family == MEMORY_FAMILY and out["memory"] == null:
			out["memory"] = unit
		elif unit.family == CART_FAMILY and out["cart"] == null:
			out["cart"] = unit
	return out


## Where the core finds the memories, and how big a cartridge is seated.
## `cart_size` is the cartridge image's size, 0 for none. Empty on another core
## or with no Sega CD memory attached.
static func forced_options(core: String, has_memory: bool, cart_size: int) -> Dictionary:
	if not core.begins_with(CORE_PREFIX) or not has_memory:
		return {}
	return {
		"genesis_plus_gx_system_bram": "per bios",
		"genesis_plus_gx_cart_bram": "per cart",
		"genesis_plus_gx_cart_size":
			str(CART_SIZES[cart_size][0]) if CART_SIZES.has(cart_size) else "disabled",
	}


## The options held at their current values while a Sega CD runs.
static func held_while_running(core: String, has_memory: bool, values: Dictionary) -> Dictionary:
	var out := {}
	if not core.begins_with(CORE_PREFIX) or not has_memory:
		return out
	for key: String in REINIT_KEYS:
		if values.has(key):
			out[key] = str(values[key])
	return out


func forced_options_for(core: String) -> Dictionary:
	if not is_instance_valid(_host):
		return {}
	var units := memory_units(_host.get_expansions())
	var has_memory: bool = units["memory"] != null
	var out := forced_options(core, has_memory, _cart_image_size(units["cart"]))
	if _host.is_powered_on:
		out.merge(held_while_running(core, has_memory, _host._options_values), true)
	return out


func _cart_image_size(cart: RetroExpansion) -> int:
	if cart == null:
		return 0
	var path := SramPaths.find_card(cart.card_id, CART_FAMILY)
	if path.is_empty():
		return SegaCdBram.CART_SIZE if cart.minted else 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var size := f.get_length()
	f.close()
	return size if CART_SIZES.has(size) else 0


## Why this machine may not start its Sega CD, or "": the folder is shared, and
## another machine is running one or has not finished writing its memory back.
func busy_elsewhere(core: String) -> String:
	if not core.begins_with(CORE_PREFIX) or not is_instance_valid(_host):
		return ""
	if memory_units(_host.get_expansions())["memory"] == null:
		return ""
	for sys: Node in _host.get_tree().get_nodes_in_group("retro_system"):
		if sys == _host or not sys.has_method("sega_cd_storage"):
			continue
		var other: SegaCdStorage = sys.call("sega_cd_storage")
		if other == null or not other.is_holding_files():
			continue
		if bool(sys.get("is_powered_on")):
			return "Another Sega CD is running. Power it off first."
		return "Another Sega CD is still saving. Try again in a few seconds."
	return ""


func is_holding_files() -> bool:
	return not _staged.is_empty()


# --- Before the core starts ---------------------------------------------------

## Put the attached memories where the core will read them. Called from the
## content-start path before forced options, which read the cartridge's size.
func stage_before_start(dir: String, core: String) -> void:
	_finish()
	if not core.begins_with(CORE_PREFIX) or not is_instance_valid(_host):
		return
	var units := memory_units(_host.get_expansions())
	var memory: RetroExpansion = units["memory"]
	if memory == null:
		return
	_save_dir = dir.path_join("save").path_join(core)
	DirAccess.make_dir_recursive_absolute(_save_dir)
	var recovered := recover(_save_dir)
	if recovered > 0:
		print("[SegaCdStorage] recovered %d memory image(s) a previous run left staged" % recovered)
	for moved: String in set_aside_unclaimed(_save_dir):
		print("[SegaCdStorage] kept unclaimed saves at %s" % moved)

	var memory_image := _image_for(memory, MEMORY_FAMILY)
	if not memory_image.is_empty():
		for name: String in REGION_FILES:
			_stage_file(name, memory_image, memory.card_id)
	var cart: RetroExpansion = units["cart"]
	if cart != null:
		var cart_image := _image_for(cart, CART_FAMILY)
		var size := FileAccess.get_file_as_bytes(cart_image).size() if not cart_image.is_empty() else 0
		if CART_SIZES.has(size):
			_stage_file(str(CART_SIZES[size][1]), cart_image, cart.card_id)
	_write_manifest()


## A unit's image path, making one only for memory this session invented, and
## starting that from unclaimed saves when there are any.
func _image_for(unit: RetroExpansion, family: String) -> String:
	var path := SramPaths.find_card(unit.card_id, family)
	if not path.is_empty():
		return path
	if not unit.minted:
		push_warning("[SegaCdStorage] '%s' has no image on disk - running without it rather than creating a blank" % unit.card_id)
		return ""
	var legacy := adopt_legacy(_save_dir, family)
	if legacy.is_empty():
		return SramPaths.ensure_card(family, unit.card_id)
	path = SramPaths.card_save_path(family, unit.card_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return path if _write(path, legacy) else ""


func _stage_file(name: String, image_path: String, card_id: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(image_path)
	if not SegaCdBram.is_card_image(bytes):
		push_warning("[SegaCdStorage] %s is not a Sega CD memory image; not staged" % image_path)
		return
	var file := _save_dir.path_join(name)
	if _write(file, bytes):
		_staged.append({"file": file, "image": image_path, "card_id": card_id, "bytes": bytes})


func _write_manifest() -> void:
	if _staged.is_empty():
		return
	var entries: Array = []
	for e: Dictionary in _staged:
		entries.append({"file": e["file"], "image": e["image"], "card_id": e["card_id"]})
	var f := FileAccess.open(_save_dir.path_join(MANIFEST), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"entries": entries}))
		f.close()


# --- After it stops -----------------------------------------------------------

## Write back what the core has written so far and keep looking until its final
## write has had time to land, then clear the folder.
func drain_after_stop() -> void:
	if _staged.is_empty():
		return
	drain()
	_drain_until = Time.get_unix_time_from_system() + DRAIN_AFTER_OFF_SEC
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "SegaCdDrainTimer"
		_timer.wait_time = DRAIN_POLL_SEC
		_timer.timeout.connect(_on_drain_tick)
		add_child(_timer)
	_timer.start()


func _on_drain_tick() -> void:
	drain()
	if Time.get_unix_time_from_system() >= _drain_until:
		_finish()


## Copy every staged file the core changed back to the image that filled it --
## never to whatever is seated now. Of the three region files only the disc's
## region changes. A file that does not parse is skipped, not copied.
func drain() -> int:
	var written := 0
	for e: Dictionary in _staged:
		var data := FileAccess.get_file_as_bytes(str(e["file"]))
		if data.is_empty() or data == e["bytes"] or not SegaCdBram.is_card_image(data):
			continue
		if _write(str(e["image"]), data):
			e["bytes"] = data
			written += 1
			print("[SegaCdStorage] %s -> %s (%d bytes)"
				% [str(e["file"]).get_file(), e["card_id"], data.size()])
	return written


func _finish() -> void:
	if _timer != null:
		_timer.stop()
	_drain_until = 0.0
	if _staged.is_empty():
		return
	drain()
	for e: Dictionary in _staged:
		DirAccess.remove_absolute(str(e["file"]))
	DirAccess.remove_absolute(_save_dir.path_join(MANIFEST))
	_staged.clear()


## Put back what a run that never finished draining left in the folder, by its
## manifest, and clear it. Returns how many images were written.
static func recover(save_dir: String) -> int:
	var manifest := save_dir.path_join(MANIFEST)
	if not FileAccess.file_exists(manifest):
		return 0
	var restored := 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if parsed is Dictionary:
		for entry: Variant in (parsed as Dictionary).get("entries", []):
			if not (entry is Dictionary):
				continue
			var file := str((entry as Dictionary).get("file", ""))
			var image := str((entry as Dictionary).get("image", ""))
			var data := FileAccess.get_file_as_bytes(file)
			if SegaCdBram.is_card_image(data) and not image.is_empty() \
					and FileAccess.get_file_as_bytes(image) != data:
				if _write(image, data):
					restored += 1
			DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(manifest)
	return restored


# --- Saves from before ----------------------------------------------------------

static func _core_file_names() -> Array[String]:
	var out: Array[String] = []
	for name: String in REGION_FILES:
		out.append(name)
	for size: int in CART_SIZES:
		out.append(str(CART_SIZES[size][1]))
	return out


## Move the core's memory files that no manifest claimed into legacy/, never over
## an earlier copy. Returns where each one went.
static func set_aside_unclaimed(save_dir: String) -> Array[String]:
	var moved: Array[String] = []
	var legacy := save_dir.path_join(LEGACY_DIR)
	for name: String in _core_file_names():
		var src := save_dir.path_join(name)
		if not FileAccess.file_exists(src):
			continue
		DirAccess.make_dir_recursive_absolute(legacy)
		var dst := legacy.path_join(name)
		var n := 2
		while FileAccess.file_exists(dst):
			dst = legacy.path_join("%s %d.%s" % [name.get_basename(), n, name.get_extension()])
			n += 1
		if DirAccess.rename_absolute(src, dst) == OK:
			moved.append(dst)
	return moved


## The most recent unclaimed memory that fits this family, consumed (renamed
## .imported) so a second new unit does not start from the same saves. Empty
## when there is none.
static func adopt_legacy(save_dir: String, family: String) -> PackedByteArray:
	var legacy := save_dir.path_join(LEGACY_DIR)
	if not DirAccess.dir_exists_absolute(legacy):
		return PackedByteArray()
	var best := ""
	var best_time := -1
	for name: String in DirAccess.get_files_at(legacy):
		if name.get_extension() != "brm":
			continue
		var is_cart := name.contains("_cart")
		if is_cart != (family == CART_FAMILY):
			continue
		var path := legacy.path_join(name)
		var data := FileAccess.get_file_as_bytes(path)
		if not SegaCdBram.is_card_image(data):
			continue
		if not is_cart and data.size() != SegaCdBram.INTERNAL_SIZE:
			continue
		var time := FileAccess.get_modified_time(path)
		if time > best_time:
			best = path
			best_time = time
	if best.is_empty():
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(best)
	DirAccess.rename_absolute(best, best + ".imported")
	print("[SegaCdStorage] a new memory starts from %s" % best)
	return bytes


static func _write(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[SegaCdStorage] cannot write %s" % path)
		return false
	f.store_buffer(data)
	f.close()
	return true
