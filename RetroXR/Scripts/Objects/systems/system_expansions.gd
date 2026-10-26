## SystemExpansions — the hardware half of what is bolted to a console: the
## sockets a unit mounts in, the covers over them, and the list of units the
## machine is currently assembled from.
##
## A child of the RetroSystem it serves, created unconditionally in _init (a bare
## RetroSystem.new() in a suite still answers expansion_ids()), in the same shape
## as SaveStateController, MemoryCardController and ExpansionLaunch.
##
## A console and the unit bolted to it are two separate physical objects that
## together behave as one machine. Which one wears the socket depends on which
## way the pair stacks -- a 64DD is a base the N64 stands on, a 32X sits on top
## of a Mega Drive -- and ExpansionCatalog is the only thing that knows. The
## console side is deliberately thin: it keeps the list, answers what the stack
## is, and hands the launch path one path to boot from (ExpansionLaunch).
##
## Lifted out of system.gd whole. What stays on RetroSystem is the surface other
## code calls BY NAME -- RetroExpansion (attach/detach, port covers),
## ScenePersistence (covers, restore_expansion), the mods' probes -- as one-line
## forwarders, plus the parts that are really about the console's own slot and
## drive: a unit that mounts AS a cartridge (restore_expansion), a dotcode card
## swiped through a unit (a disk op), and roof_above_cartridge_slot.
##
## The FOOT is built here but registered there: XRToolsPickable collects grab
## points in its own _ready, so the host pushes it onto its own list (see
## RetroSystem._build_expansion_hardware).
class_name SystemExpansions
extends Node

# The generic expansion-unit scene — see _seed_default_occupant.
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")
# The lid over an expansion bay — see _seed_expansion_cover.
const EXPANSION_COVER_SCENE := preload("res://Scenes/Objects/expansion_cover.tscn")
# The cover over a unit's own socket -- see seed_port_covers.
const PORT_COVER_SCENE := preload("res://Scenes/Objects/port_cover.tscn")

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null

## Everything currently bolted to this console. Order is the catalog's, not the
## order they were attached in, so a stack reads the same however it was built.
var _units: Array[RetroExpansion] = []


func setup(host: RetroSystem) -> void:
	_host = host


# --- Building the sockets -----------------------------------------------------

## The socket on top, the unit sockets, the cover sockets, and the foot
## underneath, built from the model's own box. Returns the foot when one was
## built this call (for the host to register), else null.
##
## Only what the catalog says this console has: a machine nothing mounts above
## must NOT grow a socket, because an empty one still lights a snap ghost and
## offers a join that does not exist. Idempotent: each part is built only if it
## is not there yet, so a restore may call this before the deferred one from
## _ready and the deferred one then does nothing.
func build_hardware() -> XRToolsGrabPointSnap:
	var sysid := _host.systemid
	if sysid.is_empty():
		return null
	var aabb := _host.body_aabb()
	if aabb.size.x <= 0.0:
		return null          # no meshes yet; nothing to measure against
	var span := Vector2(aabb.size.x, aabb.size.z)
	var model := _host.get_model()
	var restoring := _host.is_restoring_from_save()

	if ExpansionCatalog.host_takes_top_unit(sysid) \
			and _host.get_node_or_null("ExpansionSocket") == null:
		var socket := ExpansionPort.build_socket(_host, aabb.end.y, span,
			ExpansionPort.GROUP_EXPANSION, _accepts_expansion)
		socket.has_picked_up.connect(_on_expansion_seated)
		socket.has_dropped.connect(_on_expansion_lifted)
		# Roof-top-centred is only right for a unit that genuinely stacks
		# externally — nothing ships yet. The N64's Expansion Pak/Jumper Pak
		# port is inside the body, so its model relocates the socket behind a
		# cover; every other model's override is a no-op and leaves it here.
		model.configure_expansion_socket(socket)
		if not restoring:
			# Pak first, then the cover over it — the order the factory used.
			_seed_default_occupant(socket)
			_seed_expansion_cover()

	_build_unit_sockets(aabb, span)
	_build_cover_sockets()

	if ExpansionCatalog.host_stands_on_unit(sysid) \
			and _host.get_node_or_null("ExpansionFoot") == null:
		return ExpansionPort.build_foot(_host, aabb.position.y, span,
			not model.brings_own_body())
	return null


## Seats the console's default-occupant expansion (a Jumper Pak) the moment a
## FRESH socket is built for it -- never on a restore, which is why the caller
## already checked is_restoring_from_save(). A restored console's own
## "expansions" list (scene_persistence -> restore_expansion) is the whole
## truth about what is bolted on there, whether that is this same unit, a real
## Expansion Pak the player installed, or nothing; seeding on top of that would
## leave a second Jumper Pak with nowhere to go, since the socket holds one
## object and the save's own restore_expansion call would simply evict this one
## un-tracked.
func _seed_default_occupant(socket: XRToolsSnapZone) -> void:
	var default_id := ExpansionCatalog.default_occupant_for(_host.systemid)
	if default_id.is_empty():
		return
	var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
	unit.expansion_id = default_id
	_host.get_tree().current_scene.add_child(unit)
	unit.add_to_group("spawned")
	unit.global_position = _host.global_position
	socket.pick_up_object(unit)


## Puts the lid on a fresh console's expansion bay, for a model that has one.
## Same restore rule as the pak underneath it: never on a restore, where the
## save's own record — lid on the console, or lid left on a table across the
## room — is the whole truth. A player who lost theirs stays without one.
func _seed_expansion_cover() -> void:
	var model := _host.get_model()
	var zone := model.expansion_cover_slot() if model != null else null
	if zone == null or zone.has_snapped_object():
		return
	var cover := EXPANSION_COVER_SCENE.instantiate() as ExpansionCover
	_host.get_tree().current_scene.add_child(cover)
	cover.add_to_group("spawned")
	cover.global_position = _host.global_position
	zone.pick_up_object(cover)


## The sockets of their own some units go into -- a Saturn's Video CD Card slot in
## its back -- built as the shared one is and placed by the model. Named after the
## row's `socket`: "mpeg_card" is MpegCardSocket.
func _build_unit_sockets(aabb: AABB, span: Vector2) -> void:
	for socket_id: String in ExpansionCatalog.unit_sockets_for_host(_host.systemid):
		if unit_socket(socket_id) != null:
			continue
		var socket := ExpansionPort.build_socket(_host, aabb.end.y, span,
			ExpansionPort.GROUP_EXPANSION, accepts_unit.bind(socket_id))
		socket.name = unit_socket_name(socket_id)
		socket.has_picked_up.connect(_on_expansion_seated)
		socket.has_dropped.connect(_on_expansion_lifted)
		_host.get_model().configure_unit_socket(socket_id, socket)
		# A NEW socket only: building again after the player took the cover off
		# must not put a fresh one back. A restore's covers are the save's.
		if not _host.is_restoring_from_save():
			_seed_port_cover(socket_id)


## The covered openings in the console's floor that a unit it stands on fills
## (ExpansionCatalog's `cover_socket`: the N64's EXT, a Super NES's EXT). The
## model builds the cover's slot where its shell has the cover; a model with none
## builds nothing, and the console stands on the unit as it always did.
func _build_cover_sockets() -> void:
	var model := _host.get_model()
	for socket_id: String in ExpansionCatalog.cover_sockets_for_host(_host.systemid):
		if model.port_cover_slot(socket_id) != null:
			continue
		model.configure_cover_socket(socket_id)
		if model.port_cover_slot(socket_id) != null and not _host.is_restoring_from_save():
			_seed_port_cover(socket_id)


## The socket a MOUNT_ABOVE unit naming `socket_id` goes into, or null. A child
## of the host, found by name, so it is the same answer however it was built.
func unit_socket(socket_id: String) -> XRToolsSnapZone:
	if socket_id.is_empty():
		return _host.get_node_or_null("ExpansionSocket") as XRToolsSnapZone
	return _host.get_node_or_null(unit_socket_name(socket_id)) as XRToolsSnapZone


static func unit_socket_name(socket_id: String) -> String:
	return socket_id.to_pascal_case() + "Socket"


# --- Gates ----------------------------------------------------------------------

## Roof-socket gate: is this a unit that mounts on THIS console?
func _accepts_expansion(obj: Node3D) -> bool:
	return accepts_unit(obj, "")


## The same gate for one socket: a unit mounts here when it is this console's and
## names this socket ("" for the shared ExpansionSocket). A network card does not
## go into a shell with the jack built in -- a slim PS2 has no bay to take one.
func accepts_unit(obj: Node3D, socket_id: String) -> bool:
	var unit := obj as RetroExpansion
	if unit == null:
		return false
	var model := _host.get_model()
	if model != null and model.builtin_ethernet_port() >= 0 \
			and ExpansionCatalog.ethernet_port_of(unit.expansion_id) >= 0:
		return false
	return ExpansionCatalog.host_of(unit.expansion_id) == _host.systemid \
		and ExpansionCatalog.mount_of(unit.expansion_id) == ExpansionCatalog.MOUNT_ABOVE \
		and ExpansionCatalog.socket_of(unit.expansion_id) == socket_id


# --- Covers -----------------------------------------------------------------------

## The lid seated on this console's expansion bay, or null when it is off —
## what a save records. Null on every console whose model has no such bay.
func expansion_cover() -> Node3D:
	var model := _host.get_model()
	var zone := model.expansion_cover_slot() if model != null else null
	if zone == null:
		return null
	return zone.picked_up_object as Node3D


## Put a saved lid back on. The host builds the bay first (restore_expansion_cover).
func restore_expansion_cover(cover: Node3D) -> void:
	var model := _host.get_model()
	var zone := model.expansion_cover_slot() if model != null else null
	if zone != null and cover != null:
		zone.pick_up_object(cover)


## True while the cover over `socket_id` is in its slot on this console. False
## for an opening this console's model does not cover.
func port_cover_on(socket_id: String) -> bool:
	var model := _host.get_model()
	if socket_id.is_empty() or model == null:
		return false
	var zone := model.port_cover_slot(socket_id)
	return zone != null and zone.has_snapped_object()


## Shut a floor opening's cover slot while this console stands on the unit that
## fills it, and open it again when the console is lifted off. A cover still in
## the slot when the console is joined -- a room saved before covers, whose
## restore seeded one under a console already standing on its drive -- is taken
## out and laid beside the console: on the real pair it could not be there.
func block_port_cover(socket_id: String, blocked: bool) -> void:
	var model := _host.get_model()
	if socket_id.is_empty() or model == null:
		return
	var zone := model.port_cover_slot(socket_id)
	if zone == null:
		return
	if blocked and zone.has_snapped_object():
		var cover := zone.picked_up_object as Node3D
		zone.drop_object()
		if is_instance_valid(cover):
			var aside := _host.body_aabb()
			cover.global_position = _host.global_transform * Vector3(
				aside.end.x + 0.04, aside.position.y + 0.01, aside.get_center().z)
	model.block_port_cover(socket_id, blocked)


## Puts the covers on a console's own unit sockets, for a model whose shell has
## them: every slot that is empty over a socket that is empty. The host builds
## the sockets first (seed_port_covers).
func seed_port_covers() -> void:
	var model := _host.get_model()
	if model == null:
		return
	for socket_id: String in model.port_cover_sockets():
		_seed_port_cover(socket_id)


## In the console's own color, given before it enters the room: that is when a
## mod's hook dresses it.
func _seed_port_cover(socket_id: String) -> void:
	var model := _host.get_model()
	var zone := model.port_cover_slot(socket_id) if model != null else null
	var socket := unit_socket(socket_id)
	if zone == null or zone.has_snapped_object() or (socket != null and socket.has_snapped_object()):
		return
	var cover := PORT_COVER_SCENE.instantiate() as PortCover
	cover.socket_id = socket_id
	cover.size = model.port_cover_size(socket_id)
	cover.model_variant = _host.model_variant
	_host.get_tree().current_scene.add_child(cover)
	cover.add_to_group("spawned")
	cover.global_transform = zone.global_transform
	zone.pick_up_object(cover)


## Each unit socket that has a cover slot, and the cover in it or null -- what a
## save records. Empty on a model with none.
func port_covers() -> Dictionary:
	var out := {}
	var model := _host.get_model()
	if model == null:
		return out
	for socket_id: String in model.port_cover_sockets():
		out[socket_id] = model.port_cover_slot(socket_id).picked_up_object as Node3D
	return out


## Put a saved cover back over `socket_id`. The host builds the sockets first
## (restore_port_cover).
func restore_port_cover(socket_id: String, cover: Node3D) -> void:
	var model := _host.get_model()
	var zone := model.port_cover_slot(socket_id) if model != null else null
	if zone != null and cover != null:
		zone.pick_up_object(cover)


# --- The units ------------------------------------------------------------------

func _on_expansion_seated(obj: Node3D) -> void:
	var unit := obj as RetroExpansion
	if unit != null:
		unit.bind_to_host(_host)


func _on_expansion_lifted() -> void:
	# The zone says it is empty, not what left it, so unbind whatever we hold
	# that a socket is no longer holding. ITS socket: a Saturn's Video CD Card stays
	# in its own while a cartridge comes out of the slot behind the lid.
	for unit in _units.duplicate():
		if not is_instance_valid(unit) \
				or ExpansionCatalog.mount_of(unit.expansion_id) != ExpansionCatalog.MOUNT_ABOVE:
			continue
		var socket := unit_socket(ExpansionCatalog.socket_of(unit.expansion_id))
		if socket == null or socket.picked_up_object != unit:
			unit.unbind_from_host()


## Add `unit` to the list. False when it was already on it (or null), which is
## the host's cue that there is nothing to rewire.
func attach(unit: RetroExpansion) -> bool:
	if unit == null or _units.has(unit):
		return false
	_units.append(unit)
	_notice_adapter_change(unit, true)
	return true


## Take `unit` off the list. False when it was not on it.
func detach(unit: RetroExpansion) -> bool:
	if unit == null or not _units.has(unit):
		return false
	_units.erase(unit)
	_notice_adapter_change(unit, false)
	return true


## A network adapter changes what the core is told at power-on and nothing while
## it runs -- both cores read their adapter option once, at load -- so a card put
## in or taken out of a running console says when it will count.
func _notice_adapter_change(unit: RetroExpansion, seated: bool) -> void:
	if not _host.is_powered_on or ExpansionCatalog.ethernet_port_of(unit.expansion_id) < 0:
		return
	print("[RetroSystem] %s %s while running: takes effect at the next power-on"
		% [unit.expansion_id, "in" if seated else "out"])
	_host.machine_toast().show_notice(_host.display_name_for_toast(),
		"%s %s" % [ExpansionCatalog.display_label_of(unit.expansion_id), "in" if seated else "out"],
		"Switch the console off and on again for it to count.",
		AchievementToast.ACCENT_WAITING)


## The ids bolted to this console, in catalog order.
func ids() -> Array[String]:
	var out: Array[String] = []
	for unit in _units:
		if is_instance_valid(unit) and not unit.expansion_id.is_empty():
			out.append(unit.expansion_id)
	return ExpansionCatalog.sorted_ids(out)


## What the hardware pins are worked out from: the units seated, and the network
## adapter a shell has built in (a slim PS2's) as if it were the card. Not ids()
## itself, which also names what is SEATED for boot recipes and saves, and a
## built-in socket is neither.
func hardware_ids() -> Array[String]:
	var out := ids()
	var model := _host.get_model()
	if model != null and model.builtin_ethernet_port() >= 0:
		var card := ExpansionCatalog.network_adapter_for(_host.systemid)
		if not card.is_empty() and not out.has(card):
			out.append(card)
	return out


## The units themselves, for whoever needs the objects rather than the names.
func units() -> Array[RetroExpansion]:
	var out: Array[RetroExpansion] = []
	for unit in _units:
		if is_instance_valid(unit):
			out.append(unit)
	return out


## Where a two-bay unit's SECOND cartridge keeps its battery (a Sufami Turbo's
## slot B), keyed to that cartridge, or "" when nothing is in a second bay.
func slot_b_save_path(core: String) -> String:
	if core.is_empty():
		return ""
	for unit in units():
		if unit.get_bay_count() < 2:
			continue
		var m := unit.get_media(1)
		if m == null or not ("save_id" in m):
			continue
		var save_id := str(m.get("save_id"))
		if save_id.is_empty():
			continue
		return SramPaths.resolve_cart_save(
			SramPaths.media_systemid(m, ExpansionCatalog.media_of(unit.expansion_id)),
			core, _host.rom_path, save_id)
	return ""
