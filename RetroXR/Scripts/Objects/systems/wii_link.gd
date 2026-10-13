## WiiLink — everything a Wii cabinet does that no other console does.
##
## Added as a child of the RetroSystem by system.gd when the console is a Wii
## (the same shape as HandheldInput), so every other machine leaves it null and
## reads none of this. Three jobs, all of them consequences of one fact: Dolphin
## exposes Wii Remotes and GameCube pads through the SAME four libretro ports.
##
##   • PAIRING — a remote has no cable, so it claims a port by handshake instead
##     of by plug: SYNC on the console opens a window, SYNC on the remote takes
##     the lowest free slot.
##   • ARBITRATION — each slot is one device or the other. The core enforces that
##     itself (announcing a remote drops the slot's GC pad and vice versa), so
##     retroXR has to make sure it never asks for both. A wired pad's cabinet
##     socket is fixed; a remote is wireless, so the remote is what moves.
##   • MODE — a Wii plays GameCube discs, and the core follows the DISC, not the
##     console. Which device id a wired pad is announced with depends on it.
##
## Four slots total across both kinds, which is every Wii game's player cap.
##
## It also owns the SENSOR BAR: which one is plugged into this console. The jack
## itself is hardware, so RetroSystemModelWii builds it; what happens when
## something goes into it is policy, so it happens here. Whether the bar sits
## above or below the screen is the player's to set in Dolphin's options, the
## same as on the real machine — nothing here pins that option.
class_name WiiLink
extends Node

## Dolphin's "GameCube controller plugged into a Wii" device id, (6 << 8) | JOYPAD.
const RETRO_DEVICE_GC_ON_WII := 1537
const RETRO_DEVICE_JOYPAD := 1

## Slots shared between remotes and wired pads.
const SLOTS := 4

## Seconds the console listens after its SYNC is pressed. Longer than the real
## Wii's ~15 s because here it is a walk across a room.
const PAIRING_WINDOW := 30.0

## Group a listening console's link joins. Remotes look for the nearest member.
const PAIRING_GROUP := &"pairing_wii"

const SYNC_IDLE := Color(0.85, 0.85, 0.88)
const SYNC_LIT := Color(0.4, 0.7, 1.0)
const BLINK_PERIOD := 0.4

## The cabinet this belongs to. Public because a remote choosing between two
## listening consoles needs somewhere to measure the distance to.
var host: RetroSystem = null

var _sync_button: VRButton = null

var _sensor_bar_port: XRToolsSnapZone = null
## What is in that port. Held rather than read back off the zone for the same
## reason system.gd holds _port_plugs: has_dropped says the socket is empty, not
## what left it, so the thing that was there has to be remembered.
var _sensor_bar: SensorBar = null


## Whether a given console gets one of these at all.
static func handles(systemid: String) -> bool:
	return systemid == "wii"


func setup(system: RetroSystem, sync_button: VRButton) -> void:
	host = system
	_sync_button = sync_button
	_sync_button.button_pressed.connect(open_pairing)
	_bind_sensor_bar_port()


func _exit_tree() -> void:
	# A console carried off mid-window would otherwise stay in the group and keep
	# answering remotes it is no longer near.
	if is_in_group(PAIRING_GROUP):
		remove_from_group(PAIRING_GROUP)


# ── Sensor bar ────────────────────────────────────────────────────────────────

func _bind_sensor_bar_port() -> void:
	# Asked of whatever model the console wears, by method and not by class: a
	# shell a mod brings is not RetroSystemModelWii and has the jack all the same.
	# Cast to that class, such a console's jack was built and never listened to.
	var model := host.get_model()
	if model == null or not model.has_method("get_sensor_bar_port"):
		return
	_sensor_bar_port = model.call("get_sensor_bar_port") as XRToolsSnapZone
	if _sensor_bar_port == null:
		return
	_sensor_bar_port.has_picked_up.connect(_on_sensor_bar_seated)
	# No argument, by design — see system.gd's port zones for the same shape.
	_sensor_bar_port.has_dropped.connect(_on_sensor_bar_removed)


func _on_sensor_bar_seated(plug: Node3D) -> void:
	var owner_node: Node3D = plug.get_controller() if plug.has_method("get_controller") else plug
	_sensor_bar = owner_node as SensorBar
	if _sensor_bar == null:
		return
	_sensor_bar.set_system(host)


func _on_sensor_bar_removed() -> void:
	if _sensor_bar == null:
		return
	_sensor_bar.set_system(null)
	_sensor_bar = null


## The bar plugged into THIS console, or null.
##
## Deliberately not what a remote reads for its aim — a camera cannot tell whose
## lights it is looking at, so wiimote.gd sweeps every lit bar in the room. This
## answers the narrower question of what this particular console has in its jack.
func get_sensor_bar() -> SensorBar:
	return _sensor_bar


## The jack itself, for a save restore putting a plug back into it.
func get_sensor_bar_port() -> XRToolsSnapZone:
	return _sensor_bar_port


# ── Mode ──────────────────────────────────────────────────────────────────────

## True while the title this cabinet would run is a WII title, not a GameCube one.
##
## This cannot be read off the console: a Wii plays GameCube discs, and with a
## GameCube title booted the core's IsWii() goes false — it then has no Wii
## Remotes at all and rejects the Wii device ids outright. So the machine is a
## Wii; the MODE is whatever is in the tray. An empty tray reads as Wii mode,
## which is what the hardware boots into on its own.
func is_wii_mode() -> bool:
	var media: Node3D = host.get_snapped_cartridge()
	if is_instance_valid(media) and "systemid" in media:
		var id := str(media.get("systemid"))
		if not id.is_empty():
			return id == "wii"
	return true


## The device id a WIRED pad should be announced with. In Wii mode a plain joypad
## is not enough: the core needs GC_ON_WII to route the port to the Wii's
## GameCube socket and to drop any remote holding the slot.
##
## This deliberately is not folded into RetroSystem.set_controller_port_device,
## because that funnel cannot tell the two apart — the core #defines
## RETRO_DEVICE_WIIMOTE to RETRO_DEVICE_JOYPAD, so a remote and a pad both arrive
## as 1. Only the caller knows which it has, and a cabinet socket is by
## definition the wired one.
func cabinet_device_id(device_type: int) -> int:
	if device_type == RETRO_DEVICE_JOYPAD and is_wii_mode():
		return RETRO_DEVICE_GC_ON_WII
	return device_type


# ── Pairing ───────────────────────────────────────────────────────────────────

## The console's SYNC button. Joining the group is what a remote looks for.
func open_pairing() -> void:
	if not is_wii_mode():
		print("[WiiLink] SYNC ignored — a GameCube disc is in, and that mode has no remotes")
		return
	if is_in_group(PAIRING_GROUP):
		return   # already listening; a second press is not a second window
	print("[WiiLink] pairing window open for %.0fs" % PAIRING_WINDOW)
	add_to_group(PAIRING_GROUP)
	_blink_sync_button()
	get_tree().create_timer(PAIRING_WINDOW).timeout.connect(close_pairing)


func close_pairing() -> void:
	if not is_in_group(PAIRING_GROUP):
		return
	remove_from_group(PAIRING_GROUP)
	if is_instance_valid(_sync_button):
		_sync_button.set_color(SYNC_IDLE)
	print("[WiiLink] pairing window closed")


## Pulse the cap while the window is open, so the console visibly says it is
## listening from wherever the player is standing with the remote.
func _blink_sync_button() -> void:
	var lit := false
	while is_in_group(PAIRING_GROUP) and is_inside_tree():
		lit = not lit
		if is_instance_valid(_sync_button):
			_sync_button.set_color(SYNC_LIT if lit else SYNC_IDLE)
		await get_tree().create_timer(BLINK_PERIOD).timeout


## Claim the lowest free slot for `remote`, which must carry a `device_type` and
## may implement on_plugged_in/on_unplugged. Returns the slot, or -1 when the
## console is full. Closes the window on success: one press of the console's
## button pairs one remote, as on real hardware.
func pair(remote: Node3D) -> int:
	# Checked here and not only at open_pairing, because the window outlives the
	# press that opened it: a GameCube disc can go in while it is still counting
	# down, and that mode has no remotes at all. This is the check that protects
	# the core; the blinking light is only an invitation.
	if not is_wii_mode():
		print("[WiiLink] pairing refused — a GameCube disc went in while the window was open")
		close_pairing()
		return -1
	var slot := free_slot()
	if slot < 0:
		# The window deliberately stays open: freeing a slot and pressing again
		# within it should work without another trip to the console.
		print("[WiiLink] pairing refused — all %d slots in use" % SLOTS)
		return -1
	host.attach_expanded_controller(slot, remote)
	close_pairing()
	return slot


## Release whatever slot `remote` holds. Safe to call on an unpaired remote.
func unpair(remote: Node3D) -> void:
	for i in range(SLOTS):
		if host.port_holder(i) == remote:
			host.detach_expanded_controller(i, remote)
			return


## Lowest slot nothing holds, or -1 when all four are taken. Remotes and wired
## pads share one set of ports, so this sees both.
##
## `except` excludes a slot that is free only because it is mid-handover — see
## evict_remote_from, which has to let go of a slot before it can look for
## another, and must not be handed back the one being taken.
func free_slot(except: int = -1) -> int:
	for i in range(SLOTS):
		if i != except and host.port_holder(i) == null:
			return i
	return -1


## A wired pad is taking `port`. Cabinet socket k is hard-wired to slot k so the
## pad cannot move — but the remote sitting there can, and being wireless it
## should. Bump it to the lowest free slot, or unpair it if there is none.
##
## Runs BEFORE the pad is recorded, which means letting go of `port` leaves it
## reading as free even though it is spoken for. Hence the `except` — without it
## the remote is handed straight back the slot it was just evicted from, and the
## pad then overwrites it, stranding a remote that still believes it is paired.
func evict_remote_from(port: int) -> void:
	var held := host.port_holder(port)
	# The marker method is what separates a remote (wireless, movable) from a
	# wired pad, which must not be shuffled out from under its own cable.
	if held == null or not held.has_method("on_wireless_rehomed"):
		return
	host.detach_expanded_controller(port, held)
	var slot := free_slot(port)
	if slot < 0:
		print("[WiiLink] slot %d taken by a wired pad; nowhere free, remote unpaired" % port)
		return
	print("[WiiLink] slot %d taken by a wired pad; remote rehomed to %d" % [port, slot])
	host.attach_expanded_controller(slot, held)
