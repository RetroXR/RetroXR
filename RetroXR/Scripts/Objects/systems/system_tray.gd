## SystemTray — a machine's disc drive: the loader it has (a hinged lid, a
## front-sliding tray or a slot), whether that stands open, the disc spinning in
## it, and the core's disk-control mirror the lid reports to.
##
## A child of the RetroSystem it serves, made in _init like the other components,
## so a bare RetroSystem.new() in a suite answers every question here with "no
## drive". Lifted out of system.gd whole. What it needs of the machine -- the
## model, the Libretro node, rom_path, power -- it asks for publicly; the scene
## nodes it drives (the OPEN/EJECT button, the cartridge slot, the procedural
## body) are handed to build().
##
## The machine keeps forwarders under the names other code reaches it by:
## request_tray_state, lid_reports_open, net_set_tray_open, press_eject, and the
## `_tray_open` / `_tray` / `_slot` properties the model packs' probes read.
## Everything else holds this node: RetroSystem.disc_tray().
class_name SystemTray
extends Node

const DISC_SPIN_MAX := 25.0    # rad/s (~240 RPM) — seated disc at full speed
const DISC_SPIN_UP := 18.0     # rad/s² ramp-up (power on / tray closed)
const DISC_SPIN_DOWN := 10.0   # rad/s² ramp-down (power off / tray opened)
## Slot-load: how far inside the console a disc rides, unless the model says.
const SLOT_INSET := 0.10

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null
## The scene nodes build() was handed. Null until then, and on a machine that
## never entered the tree.
var _eject_button: VRButton = null
var _cartridge_slot: XRToolsSnapZone = null

## How this system loads discs (MediaDimensions.LOADER_*), set by build().
var loader := MediaDimensions.LOADER_NONE
## LOADER_TRAY: whether the lid (or shelf) stands open. Starts shut.
var open := false
## LOADER_SLOT front-loading bay (insert ride / eject / grab hand-off /
## collision), owned by the shared MediaSlot. Null on every other loader.
var media_slot: MediaSlot = null
## LOADER_TRAY lid bay (well seating / lid gating / disc spin / grab hand-off /
## collision), owned by the shared MediaTray. Null on every other loader.
var media_tray: MediaTray = null
## Front-sliding tray shelf (LOADER_TRAY + MediaDimensions.has_front_tray) on the
## procedural box; false on a hinged lid. The seated disc rides it out.
var front_tray := false
## The mechanism the model drew on the placeholder box — the spring lid or the
## sliding shelf. Null on a bespoke shell, which brings its own. The hinge owns
## the lid's angle: MediaTray is NOT given a lid_pivot to tween, or the two would
## fight over it, and a hand-close comes back through request_state.
var disc_bay: ProceduralDiscBay = null
## Current disc angular speed (rad/s).
var spin := 0.0

## The disc left the drive while its core kept running it, so rom_path still
## names that image; the next power-on must not boot it.
var left_running := false
## This run started with no content, so its core has no disc list to swap into.
var started_without_content := false
## This run is the BIOS with no disc in it; a disc shut into it restarts the
## machine.
var bios_run := false

# --- Disk control (multi-disc games: FF7 "insert disc 2") ---
# Mirrors the core's libretro disk-control state (disk_control_ready signal).
# When the running core owns the interface, pulling the disc hot-ejects
# (game keeps running) and inserting the next disc swaps it in live.
var has_disk_control := false
var disc_index := 0
var disc_ejected := false


func setup(host: RetroSystem) -> void:
	_host = host


## Build whatever this console loads a disc through, or nothing.
##
## Three shapes: a hinged lid, a front-sliding tray, and a true slot that
## draws the disc in. The first two are one loader with different geometry
## and different wording on the button; the third is MediaSlot instead of
## MediaTray. Cartridge hardware takes none of it and hides the button.
##
## `bespoke` is passed rather than re-derived: a shell that brings its own
## body also brings its own tray mechanism, so several of the procedural
## decisions below do not apply to it. `on_inserted` / `on_removed` are the
## machine's emulation-side insert and remove, which a loader fires in place of
## the slot's raw signals.
func build(bespoke: bool, eject_button: VRButton, cartridge_slot: XRToolsSnapZone,
		system_body: Node3D, on_inserted: Callable, on_removed: Callable) -> void:
	_eject_button = eject_button
	_cartridge_slot = cartridge_slot
	var model := _host.get_model()
	var systemid := _host.systemid
	# Disc loader: tray consoles (PS1/GameCube…) get an OPEN button gating a
	# closed-by-default tray; slot loaders (PS2) get an always-open slot with
	# an EJECT button. Cartridge systems hide the button entirely.
	loader = MediaDimensions.disc_loader(systemid)
	var has_loader := loader != MediaDimensions.LOADER_NONE
	# A shell that models its own release control (the PSP's sprung OPEN latch)
	# opts out — it drives request_tray_state directly.
	var want_eject := has_loader and model.has_eject_button()
	_eject_button.set_active(want_eject)
	# A front-sliding tray is a property of the PROCEDURAL box. A bespoke shell
	# brings its own mechanism — the PS2 Slim's hinged cover is a lid whatever the
	# platform row says the family does — so it keeps the lid wording and geometry.
	front_tray = loader == MediaDimensions.LOADER_TRAY \
		and MediaDimensions.has_front_tray(systemid) and not bespoke
	if not has_loader:
		return
	print("[RetroSystem] %s: disc loader %d (%s)" % [systemid, loader,
		"front tray" if front_tray else ("lid" if loader == MediaDimensions.LOADER_TRAY else "slot")])
	var eject_label := _eject_button.get_node_or_null("ButtonLabel") as Label3D
	if eject_label:
		# A sliding tray EJECTS, like the drive it imitates; only a hinged lid
		# is something you OPEN.
		var is_lid: bool = loader == MediaDimensions.LOADER_TRAY and not front_tray
		eject_label.text = "OPEN" if is_lid else "EJECT"
	# The cartridge recess would look wrong on disc hardware — the disc
	# tray/slit is the visual instead.
	var cart_recess := system_body.get_node_or_null("CartSlotMouth") as MeshInstance3D
	if cart_recess:
		cart_recess.visible = false
	# The snap ghost is cartridge-shaped — reshape it into this system's
	# disc so the blue "goes here" shadow reads correctly.
	var ghost := _cartridge_slot.get_node_or_null("SnapHighlight/HighlightMesh") as MeshInstance3D
	if ghost:
		var ghost_mesh := CylinderMesh.new()
		ghost_mesh.top_radius = MediaDimensions.disc_diameter(systemid) / 2.0
		ghost_mesh.bottom_radius = ghost_mesh.top_radius
		ghost_mesh.height = 0.004
		ghost.mesh = ghost_mesh
	# The model draws its own mechanism: the placeholder box builds a pod or a
	# sliding shelf to match itself, a bespoke shell already has one.
	if loader == MediaDimensions.LOADER_TRAY:
		_cartridge_slot.enabled = false   # tray starts closed
		disc_bay = model.build_disc_bay(_host, _cartridge_slot, systemid,
			front_tray, on_lid_swung)
		# Lid tray: hand the well seating / lid gating / spin / grab / collision to the
		# shared MediaTray (bespoke models animate their own lid via play_open/close;
		# a procedural lid pivot, if any, is animated by MediaTray). The zone's raw
		# insert/remove signals are replaced by MediaTray's, which fire the same
		# insert/remove for the emulation-side work.
		_cartridge_slot.has_picked_up.disconnect(on_inserted)
		_cartridge_slot.has_dropped.disconnect(on_removed)
		media_tray = MediaTray.new()
		media_tray.host = _host
		media_tray.slot = _cartridge_slot
		# No lid_pivot: a bespoke model swings its own lid from play_open/close,
		# and the procedural one is driven by its own spring hinge.
		# A flip-open tray assembly (the PSP's UMD door) carries its disc with
		# it — unlike a spindle console, where the disc stays fixed and only
		# the lid mesh swings. The cartridge slot's pose (already set by
		# configure_cartridge_slot) is where the disc should visually rest
		# with the pivot at its baked rest orientation; re-express it as a
		# LOCAL offset from that pivot so MediaTray can reparent the disc
		# under it and have it swing rigidly with the door.
		# The procedural slide when we built one, else whatever moving part the
		# model nominates (the PC tower's authored shelf, the PSP's UMD door).
		var disc_pivot: Node3D = disc_bay.slide_pivot if disc_bay != null else null
		if disc_pivot == null and model != null:
			disc_pivot = model.get_disc_lid_pivot()
		if disc_pivot != null:
			media_tray.disc_lid_pivot = disc_pivot
			var rel := disc_pivot.global_transform.affine_inverse() * _cartridge_slot.global_transform
			media_tray.media_local_basis = rel.basis
			media_tray.seat_offset = rel.origin
		_host.add_child(media_tray)
		media_tray.loaded.connect(on_inserted)
		media_tray.unloaded.connect(on_removed)
	# Slot loaders take the disc through a slit in the FRONT face: move the
	# snap zone to the slit mouth and add the slit visual there.
	if loader == MediaDimensions.LOADER_SLOT and not bespoke:
		_cartridge_slot.position = Vector3(0, 0.03, 0.125)
		model.build_disc_slit(_host, systemid)
	# Front-loading disc bay: hand the physical ride/eject/grab/collision to the
	# shared MediaSlot (bespoke models place their own slit but still slot-load).
	# The zone's raw insert/remove signals are replaced by MediaSlot's, which
	# fire the same insert/remove for the emulation-side work.
	if loader == MediaDimensions.LOADER_SLOT:
		_cartridge_slot.has_picked_up.disconnect(on_inserted)
		_cartridge_slot.has_dropped.disconnect(on_removed)
		media_slot = MediaSlot.new()
		media_slot.host = _host
		media_slot.slot = _cartridge_slot
		# A model whose case is too shallow for the cabinet's default says so;
		# 0 means "no opinion". See RetroSystemModel.slot_insert_depth.
		var slot_depth: float = model.slot_insert_depth()
		media_slot.insert_depth = slot_depth if slot_depth > 0.0 else SLOT_INSET
		_host.add_child(media_slot)
		media_slot.inserted.connect(on_inserted)
		media_slot.removed.connect(on_removed)


## True when a MediaSlot or MediaTray owns the media's seating and collision
## exception, rather than the machine's plain cartridge slot.
func has_loader_bay() -> bool:
	return media_slot != null or media_tray != null


## Carry a restored lid pose into the MACHINE, which is a separate thing from the
## shell the pose just moved.
##
## set_lid_angle_deg only moves the mesh and the model's own zone gate. A tray
## console's open state lives in two more places — `open` here and MediaTray's
## own — and both start shut, so a room saved with the lid up came back with the
## lid drawn open over a machine that believed it was closed. The PlayStation's
## well then took a disc (the model had enabled the zone) and MediaTray
## immediately sealed it in: ungrabbable, and the core never heard the tray
## cycle, so the game never saw the disc that was visibly sitting in it.
##
## Idempotent, and a no-op on anything but a tray console — which is why the
## NES's flap, whose own set_lid_angle_deg already gates its bay, passes through
## here unchanged.
func restore_open() -> void:
	var model := _host.get_model()
	if model == null or loader != MediaDimensions.LOADER_TRAY:
		return
	var lid_open: bool = model.is_lid_open()
	if lid_open != open:
		print("[RetroSystem] %s: restored lid is %s" % [_host.systemid, "open" if lid_open else "shut"])
		set_open(lid_open, true)


## The spin the seated disc is at, relative to the authored seat, in radians.
## Zero for a cartridge bay, an empty bay, or a disc seated as authored.
func seat_yaw() -> float:
	if media_slot != null:
		return media_slot.seat_yaw()
	if media_tray != null:
		return media_tray.seat_yaw()
	return 0.0


## Seat restored media through the drive (no ride, filter bypassed). False when
## this machine has no drive, and the cartridge slot has to take it instead.
func restore_media(cartridge: Node3D, yaw: float) -> bool:
	if media_slot != null:
		media_slot.restore(cartridge, yaw)
		return true
	if media_tray != null:
		media_tray.restore(cartridge, yaw)
		return true
	return false


# --- The disc spinning ---

## Spin the seated disc: ramp up while powered with the tray shut, ramp down
## when the tray opens or the power goes off. Purely visual — each peer derives
## the same state from power + tray, so no sync is needed.
func update_spin(delta: float) -> void:
	var disc := _host.get_snapped_cartridge() as RetroDisc
	if not is_instance_valid(disc):
		spin = 0.0
		return
	# "Shut and seated": a tray disc spins only with the lid closed (MediaTray.can_spin
	# already means shut-over-a-disc); a slot disc has no lid but must have finished its
	# insert ride so the spin doesn't fight MediaSlot's ride tween.
	var shut := true
	if media_tray != null:
		shut = media_tray.can_spin()
	elif media_slot != null:
		shut = media_slot.is_media_seated()
	# ...and home. A front tray takes most of a second to travel and the disc is
	# bolted to it, so a spin keyed off the gates alone turned the disc in the open
	# air the whole way back into the machine.
	if shut and is_moving():
		shut = false
	var target := DISC_SPIN_MAX if (_host.is_powered_on and shut) else 0.0
	var rate := DISC_SPIN_UP if target > spin else DISC_SPIN_DOWN
	spin = move_toward(spin, target, rate * delta)
	# A disc being grabbed out keeps its pose (it's no longer frozen in the bay).
	if spin > 0.0 and disc.freeze and disc.can_visually_spin():
		disc.rotate_object_local(Vector3.UP, spin * delta)
	# The shell's own mechanism turns with the motor, NOT with the platter: a disc
	# lifted out mid-spin stops being rotated here, and a turntable that stopped
	# dead with it would be reporting the hand rather than the motor. Models
	# without a modelled mechanism ignore this.
	var model := _host.get_model()
	if spin > 0.0 and model != null:
		model.spin_disc_mechanism(spin * delta)


## True while the tray is still travelling between open and shut. The two things
## that can be moving it are the placeholder box's own shelf and a bespoke model's
## authored one; a spring-latched lid is not one of them, because a hand closes it
## and it reports only once it is home.
func is_moving() -> bool:
	if disc_bay != null and disc_bay.is_moving():
		return true
	var model := _host.get_model()
	return model != null and model.is_tray_moving()


# --- What the drive reads ---

## Whether a disc change can reach the core without rebooting it.
##
## The live answer arrives on disk_control_ready, which is async: it lands some
## frames after the core comes up, and a disc pulled before it did took the "no
## disk control" path and powered the machine off. The core's own .info file
## answers the same question before the core is even loaded, so ask that too.
func supports_disk_control() -> bool:
	if has_disk_control:
		return true
	var info := CoreInfoDatabase.shared().get_by_core_name(_host.resolve_core_name())
	return str(info.get("disk_control", "false")) == "true"


## True when this machine's media can leave while the program keeps running: a
## disc drive of either kind, or a floppy machine. A cartridge deck cannot — the
## program itself lives on the cart.
func media_survives_removal() -> bool:
	return loader != MediaDimensions.LOADER_NONE \
		or MediaDimensions.uses_floppy(_host.systemid)


## The path of the disc seated in this drive, whatever its lid is doing; "" with
## none.
func seated_disc_path() -> String:
	var seated := _host.get_snapped_cartridge()
	if seated == null or not seated.has_method("get_rom_path"):
		return ""
	return str(seated.get_rom_path())


## What a disc drive reads at power-on: nothing while its lid is open, else the
## disc seated in it. With none seated, rom_path stands only if the room did not
## put it there: a disc pulled out mid-game leaves the image the core was
## running, and a BIOS run leaves its blank one.
func boot_disc_path() -> String:
	var rom_path := _host.rom_path
	if loader == MediaDimensions.LOADER_NONE:
		return rom_path
	if loader == MediaDimensions.LOADER_TRAY and open:
		return ""
	var seated := seated_disc_path()
	if not seated.is_empty():
		return seated
	if left_running or BiosBoot.is_empty_media(rom_path):
		return ""
	return rom_path


## "lid" or "tray" when this drive stands open over a disc, which it will not
## read; "" otherwise.
func open_over_disc() -> String:
	if loader != MediaDimensions.LOADER_TRAY or not open \
			or seated_disc_path().is_empty():
		return ""
	return "tray" if front_tray else "lid"


## A disc shut into a BIOS run: switch the machine off and on, so it boots it.
func restart_on_disc() -> void:
	if not _host.is_powered_on or open:
		print("[RetroSystem] disc restart dropped: %s" % ("machine off" if not _host.is_powered_on else "lid open again"))
		return
	_host.power_off()
	_host.power_on()


## The core has gone: nothing it said about its drive holds any more.
func on_core_stopped() -> void:
	has_disk_control = false
	disc_index = 0
	disc_ejected = false
	started_without_content = false
	bios_run = false


## A disc went into a powered drive that has no lid, while the core holds its
## tray open: swap it in live (multi-disc games — FF7 "insert disc 2").
##
## A lidded drive reports nothing here. Its lid is the sensor, so the swap
## reaches the core when the lid shuts (sync_core) — a disc laid in an open tray
## has not been read by anything yet.
func hot_swap_in() -> void:
	if media_tray != null or not _host.is_powered_on or not supports_disk_control() \
			or not disc_ejected or _host.rom_path.is_empty() \
			or NetworkManager.is_event_applying():
		return
	# disc_index is the core's internal image-list SLOT (get_image_index),
	# not a disc number — without .m3u the list has one slot (0) and the
	# swap overwrites the file in it (replace_image_index).
	print("[RetroSystem] Hot swap: image slot %d -> %s" % [disc_index, _host.rom_path])
	request_disk_op(RetroSystem.DISK_OP_CLOSE, _host.rom_path)
	_host.protect_active_rom()


## The disc left a powered drive whose program keeps running. A lidded drive
## tells the core nothing yet: the lid is the sensor, and the core hears about
## it when the lid shuts. A slot drive has no lid, so the disc leaving IS the
## event. rom_path stays mounted either way — that image is still what the core
## is running.
func media_left_running() -> void:
	print("[RetroSystem] Media out: game keeps running (%s)" % _host.rom_path)
	left_running = true
	if media_tray == null and supports_disk_control() \
			and not NetworkManager.is_event_applying():
		request_disk_op(RetroSystem.DISK_OP_EJECT, "")


## Cached disk-control state from the emulation thread (async signal).
func on_disk_control_ready(has_control: bool, count: int, current_index: int,
		ejected: bool) -> void:
	# Log state changes (not every echo) — the boot answer and each op's result.
	if has_control != has_disk_control or current_index != disc_index \
			or ejected != disc_ejected:
		print("[RetroSystem] Disk control: has=%s images=%d index=%d ejected=%s" %
			[has_control, count, current_index, ejected])
	has_disk_control = has_control
	disc_index = current_index
	disc_ejected = ejected


## Perform a disc op — RetroSystem.DISK_OP_EJECT (open the core's tray) or
## DISK_OP_CLOSE (replace the current image with `path` and close the tray).
## Offline: straight to the core. Netplay: frame-scheduled so every lockstep peer
## swaps on the same frame (host schedules; clients send intent via EV_DISK_OP).
func request_disk_op(op: int, path: String) -> void:
	if NetworkManager.netplay_running() and NetworkManager.netplay_covers(_host):
		var md5 := "" if path.is_empty() else NetFileTransfer.hash_of(path)
		if NetworkManager.is_host():
			NetworkManager.netplay_schedule_disk(_host, op, md5, disc_index)
		else:
			print("[RetroSystem] Disc op %d intent -> host (md5 %s…)" % [op, md5.left(8)])
			NetworkManager.report_event(NetEvents.Event.EV_DISK_OP,
				{"sys": _host, "op": op, "md5": md5, "index": disc_index})
		# The core-side state flips on the scheduled frame; the mirror updates
		# via disk_control_ready then.
		return
	var lib := _host.get_libretro_node()
	if op == RetroSystem.DISK_OP_EJECT:
		lib.SetDiskEjectState(true)
		disc_ejected = true
	else:
		lib.ReplaceDiskImage(disc_index, path)
		lib.SetDiskEjectState(false)
		disc_ejected = false
	# Read the drive back rather than trusting what we just wrote. The mirror is
	# what the next decision is made from, and it drifts: the answer to a
	# RequestDiskInfo issued at power-on drains AFTER an early lid press and
	# reports the state from before it, quietly overwriting the truth.
	lib.RequestDiskInfo()


# --- The lid ---

## OPEN (tray consoles): toggles the lid, gating insert/remove and the spin.
## EJECT (slot consoles): slides the seated disc out so it can be grabbed.
func on_eject_pressed() -> void:
	match loader:
		MediaDimensions.LOADER_TRAY:
			# A spring-latched lid (PSone/PSX/Saturn/Dreamcast/PS2) is closed BY HAND —
			# the button is only a latch release, so pressing it while the lid is already
			# up does nothing. Pressing it used to snap the lid shut, which is not what
			# the real hardware does.
			if has_spring_lid():
				if not open:
					request_open(true)
				else:
					print("[RetroSystem] OPEN pressed on a lid already up: it closes by hand")
			else:
				request_open(not open)
		MediaDimensions.LOADER_SLOT:
			if media_slot:
				# Pressed again with the disc still resting at the slot mouth, it
				# takes the disc back — a slot drive has no open tray to leave it on.
				media_slot.toggle_eject()


## What the menu's OPEN/EJECT row says, or "" for a machine without the button.
## Worded by the drive: a lid on a spring only OPENS (it is shut by hand), a
## motorised tray goes both ways, a slot hands the disc back.
func eject_label() -> String:
	if _eject_button == null or not _eject_button.visible:
		return ""
	match loader:
		MediaDimensions.LOADER_TRAY:
			if has_spring_lid():
				return "Close the lid by hand" if open else "Open lid"
			return "Close tray" if open else "Open tray"
		MediaDimensions.LOADER_SLOT:
			return "Eject disc"
	return "Eject"


## The OPEN/EJECT button, pressed from the menu: only where the machine shows it.
func press_eject() -> void:
	if _eject_button != null and _eject_button.visible:
		on_eject_pressed()


## True when the model's lid is spring-loaded + hand-closed (see
## RetroSystemModel.has_spring_latched_lid).
func has_spring_lid() -> bool:
	if disc_bay != null and disc_bay.lid_hinge != null:
		return true          # the procedural box's own lid
	var model := _host.get_model()
	return model != null and model.has_spring_latched_lid()


## A model's own hand-driven lid (e.g. the PSone's VRHinge) reporting the state
## the player physically put it in. Idempotent, so a drag can report freely.
func request_state(want_open: bool) -> void:
	if loader == MediaDimensions.LOADER_TRAY and want_open != open:
		request_open(want_open)


## Local intent (OPEN button or pushing the lid shut): apply + replicate.
func request_open(want_open: bool) -> void:
	set_open(want_open)
	NetworkManager.report_event(NetEvents.Event.EV_TRAY,
		{"sys": _host, "open": open})


## Apply a tray state: the snap zone only hover-accepts discs while open, and a
## seated disc can only be grabbed out while open (no reaching through the lid).
## The spin ramp follows via update_spin. Netplay applies remote toggles through
## net_set_open below.
##
## `restoring` is a load re-entering a state the room was already in: the shell
## has just been posed by set_lid_angle_deg, so nothing animates and the model is
## not asked to play the swing again — but every gate is applied exactly as a
## press would, which is the whole reason a restore comes through here at all.
func set_open(want_open: bool, restoring: bool = false) -> void:
	open = want_open
	# MediaTray gates the well (accepts a disc only while open + empty), makes a
	# seated disc grabbable only while open, and swings the procedural lid pivot.
	if media_tray:
		media_tray.set_open(want_open, not restoring)
	# Latch the OPEN button down to show "tray open" — except on a spring lid, whose
	# button is a momentary latch release (holding it down would advertise a second
	# press that deliberately does nothing).
	if _eject_button != null:
		_eject_button.set_latched_pressed(want_open and not has_spring_lid())
	# The procedural spring lid: unlatch so it pops up, or snap it shut. A remote
	# peer's toggle arrives here too, so both ends stay in the same physical state.
	if disc_bay != null:
		if disc_bay.lid_hinge != null:
			if want_open:
				disc_bay.lid_hinge.open()
			else:
				disc_bay.lid_hinge.latch_closed()
		disc_bay.slide(want_open)
	# Bespoke GLB tray models animate their own lid here. Skipped on a restore,
	# where set_lid_angle_deg has already put the shell exactly where the save
	# says it was — playing the swing would tween it there from wherever it is.
	if not restoring:
		var model := _host.get_model()
		if want_open:
			model.play_open()
		else:
			model.play_close()
	sync_core()


## The lid is the drive's sensor, so the core's tray follows the LID and not the
## disc. Opening tells the core the tray is open; shutting hands it whatever is
## in the well by then. In between the core hears nothing, which is what lets a
## disc be swapped — or an unrelated one shown to the drive and taken back out —
## without the program seeing anything but one tray cycle.
##
## A slot drive has no lid to read, so its insert and eject are the events; they
## stay where they are, in hot_swap_in / media_left_running.
func sync_core() -> void:
	if media_tray == null or not _host.is_powered_on:
		return
	# A remote peer's lid arrives through net_set_open; the machine's owner
	# schedules the op for everyone, so applying one here would double it.
	if NetworkManager.is_event_applying():
		return
	var disc := seated_disc_path()
	# A BIOS does not boot a disc swapped in under it (measured on pcsx_rearmed and
	# mednafen_saturn), so a disc shut into a BIOS run starts the machine again.
	if bios_run and not open and not disc.is_empty():
		print("[RetroSystem] Lid shut on %s over a BIOS run: restarting on it" % disc.get_file())
		restart_on_disc.call_deferred()
		return
	# No disc list to swap into, and flycast indexes that empty list when its
	# tray shuts.
	if started_without_content or not supports_disk_control():
		return
	var op := tray_op_for(open, disc_ejected, not disc.is_empty())
	# Logged either way. When a machine will not boot what is plainly sitting in
	# its bay, this line is the difference between the room and the core — and
	# the one thing that cannot be read off the screen.
	print("[RetroSystem] Lid %s: disc=%s core_ejected=%s -> %s"
		% ["open" if open else "shut", not disc.is_empty(), disc_ejected,
			["nothing", "eject", "close on " + disc.get_file()][op + 1]])
	if op == RetroSystem.DISK_OP_NONE:
		return
	if op == RetroSystem.DISK_OP_CLOSE:
		_host.rom_path = disc
	request_disk_op(op, disc if op == RetroSystem.DISK_OP_CLOSE else "")
	if op == RetroSystem.DISK_OP_CLOSE:
		_host.protect_active_rom()


## Pure lid-to-core decision: what the core needs to be told when the lid reaches
## `lid_open`, given what it currently believes (`core_ejected`) and whether there
## is a disc in the well to hand it.
##
## Shutting the lid over a disc always hands it over, even the one already
## mounted — a real drive re-reads what it finds. Shutting it over an empty well
## says nothing, so the core keeps waiting with its tray open rather than being
## told to close on nothing.
static func tray_op_for(lid_open: bool, core_ejected: bool, has_disc: bool) -> int:
	if lid_open:
		return RetroSystem.DISK_OP_NONE if core_ejected else RetroSystem.DISK_OP_EJECT
	return RetroSystem.DISK_OP_CLOSE if has_disc else RetroSystem.DISK_OP_NONE


## The lid moved under its own mechanism — mark the tray as wherever it now
## stands, as the PSP's UMD door does.
##
## BOTH directions, and that is the fix. This used to report only the latch
## clicking SHUT, because in play the only way a lid opens is the OPEN button,
## which reports for itself. A restore does not press that button:
## ScenePersistence reapplies the saved angle and latch straight onto the
## mechanism, so a room saved with the lid up came back with the lid standing
## open over a machine that still believed it was shut — and its bay refused
## every disc until the lid was pushed home and opened again.
##
## request_state is idempotent, so the echo from an OPEN press or from
## latch_closed() stops here rather than bouncing back into the hinge. While a
## remote update or a restore is being APPLIED the state is set without being
## reported, which is the rule sync_core already follows — a hook that
## re-reports what it was just told starts a round trip.
func on_lid_swung(_deg: float) -> void:
	if disc_bay == null or disc_bay.lid_hinge == null:
		return
	lid_reports_open(not disc_bay.lid_hinge.is_latched_closed(), disc_bay.lid_hinge)


## A lid mechanism reporting its own state. Public because a bespoke model owns
## its hinge and reports through here (via RetroSystem.lid_reports_open) rather
## than growing a second copy of the rule (see playstation_model._on_lid_swung).
func lid_reports_open(lid_open: bool, mechanism: Node) -> void:
	if loader != MediaDimensions.LOADER_TRAY or lid_open == open:
		return
	var applying: bool = NetworkManager.is_event_applying() \
		or (mechanism != null and mechanism.has_meta("net_restore_in_progress"))
	if applying:
		set_open(lid_open, true)
	else:
		request_open(lid_open)


## Netplay: another player toggled this console's tray.
func net_set_open(want_open: bool) -> void:
	if loader == MediaDimensions.LOADER_TRAY and want_open != open:
		set_open(want_open)
