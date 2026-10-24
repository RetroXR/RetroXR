## TransferPak — the pak with a Game Boy cartridge slot in its roof.
##
## The only one of the three that is both a plug and a socket, which is the same
## shape MotionPlus takes: it seats in the controller's expansion port and
## carries a bay of its own so a Game Boy cartridge has somewhere to go.
##
## There is no second core behind it. mupen64plus emulates the cartridge's MAPPER
## only — MBC1/2/3 with its clock, MBC5, and the Pocket Camera — and the N64 game
## brings its own Game Boy emulator in its own ROM. So nothing here starts a core
## or joins a link bus; the cartridge is a FILE PATH handed to the port, and the
## N64 reads it the way the real pak reads silicon.
class_name TransferPak
extends N64Pak

const PLUG_SYSTEMID := "n64_transfer_pak"

## What this pak's own bay is for: Game Boy cartridges, the Color library's with
## them (GbCartShell.is_shell).
const MEDIA_SYSTEMID := "gb"

## The cartridge in the roof changed. The controller cannot watch this bay
## itself, being two objects away from it, so the change is announced upward and
## the port re-tells the core, exactly as the Wii Remote does for a chained
## Nunchuk.
signal cart_changed(cart: Node3D)

var _cart: Node3D = null

@onready var _bay: XRToolsSnapZone = $CartridgeBay


func _ready() -> void:
	systemid = PLUG_SYSTEMID
	super._ready()
	_bay.snap_filter = _accepts_cart
	_bay.has_picked_up.connect(_on_cart_seated)
	_bay.has_dropped.connect(_on_cart_removed)


func pak_option_value() -> String:
	return "transfer"


func pak_label() -> String:
	return "Transfer Pak"


# ── The cartridge bay ─────────────────────────────────────────────────────────

## Media with no systemid of its own is let through — a blank cartridge is
## whatever it is put into, which is how every other bay in this room treats one.
func _accepts_cart(obj: Node3D) -> bool:
	if obj == null or not ("systemid" in obj):
		return false
	var mid := str(obj.get("systemid"))
	# The Color library's cartridges fit too, as on the hardware: Pokemon Gold,
	# Silver and Crystal (Crystal is Color only) are what Pokemon Stadium 2 reads
	# through this pak.
	return mid.is_empty() or GbCartShell.is_shell(mid)


func _on_cart_seated(cart: Node3D) -> void:
	_cart = cart
	print("[TransferPak] %s: game in: %s" % [name, cart_rom_path()])
	add_collision_exception_with(cart)
	# The cartridge's box goes on the pak, and through it on to the pad.
	if cart is CollisionObject3D:
		SeatedCollision.lend(self, cart as CollisionObject3D, _bay)
	cart_changed.emit(_cart)


## XRToolsSnapZone.has_dropped carries no argument: it says the zone is empty,
## not what left. Which is enough — the bay holds one thing and _cart is it.
func _on_cart_removed() -> void:
	if is_instance_valid(_cart):
		print("[TransferPak] %s: game out: %s" % [name, cart_rom_path()])
		remove_collision_exception_with(_cart)
		if _cart is CollisionObject3D:
			SeatedCollision.withdraw(self, _cart as CollisionObject3D)
	_cart = null
	cart_changed.emit(null)


## The cartridge in the roof, or null.
func get_cart() -> Node3D:
	return _cart


## Put a cartridge back into the roof after a load.
func restore_cart(cart: Node3D) -> void:
	if not is_instance_valid(cart):
		return
	_bay.pick_up_object(cart)


## The Game Boy ROM the N64 should read through this pak, or "" for an empty pak.
func cart_rom_path() -> String:
	if not is_instance_valid(_cart) or not ("rom_path" in _cart):
		return ""
	return str(_cart.get("rom_path"))


## Where that cartridge's battery save belongs.
##
## Keyed off the CARTRIDGE, the same way the Super Game Boy's Game Boy cartridge
## is: the battery is in the cartridge, not in the pak, so a save follows the
## cartridge from pak to pak and does not follow the pak from game to game. Filed
## under the cartridge's own library (MEDIA_SYSTEMID for a blank one), so it is
## the same file a Game Boy or Game Boy Color playing that cartridge reads, as the
## Super Game Boy's is (SramPaths.media_systemid).
func cart_save_path(core_name: String) -> String:
	var rom := cart_rom_path()
	if rom.is_empty():
		return ""
	var save_id := str(_cart.get("save_id")) if "save_id" in _cart else ""
	if save_id.is_empty():
		save_id = rom.get_file().get_basename()
	return SramPaths.resolve_cart_save(SramPaths.media_systemid(_cart, MEDIA_SYSTEMID), core_name, rom, save_id)


## Where that cartridge's real-time clock is kept: beside its battery, and keyed
## by the N64 core, whose clock layout is its own.
func cart_rtc_path(core_name: String) -> String:
	return SramPaths.rtc_path(cart_save_path(core_name), core_name)
