## RetroExpansion — a console expansion as a physical unit you can pick up.
##
## The 64DD, the Famicom Disk System, the Mega-CD, the 32X. Each is its own box
## with its own media bay and its own connector, and each does nothing at all
## until a console is actually bolted to it. Spawn one, spawn the console, stand
## the two together, put a cartridge in one and a disk in the other, press power.
##
## It knows nothing about cores. What it knows is which console it fits, which
## way up it goes, and what its own bay is holding — RetroSystem asks it those
## three things at power-on and ExpansionCatalog turns the answers into a launch.
##
## Geometry
## --------
## Where the connector goes follows entirely from ExpansionCatalog's `mount`:
##   MOUNT_BELOW  the console stands on this unit, so the unit wears the SOCKET
##                on its roof and its media bay moves to the FRONT face, which is
##                where it has to be with a console sitting on top of it.
##   MOUNT_ABOVE  this unit stands on the console, so it wears the FOOT on its
##                underside and its bay sits on TOP, where nothing covers it.
## Both cases are the same two ExpansionPort calls with the arguments swapped.
class_name RetroExpansion
extends XRToolsPickable

const MEDIA_GROUP := "cartridge"
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## Which expansion this is — a key in ExpansionCatalog.ROWS. Set by the spawner
## before the unit enters the tree, the same way RetroSystem.systemid is.
@export var expansion_id: String = ""

## The ROM this unit carries in itself, for a cartridge-shaped unit that contains
## one. Empty on every unit that is only an enclosure.
##
## The BS-X cartridge is the case that needs it: the shell lives on the cartridge,
## and a pack in its bay is the CONTENT that shell loads. So the machine boots the
## pack when there is one and this ROM when the bay is empty, which is what the
## hardware does -- an empty BS-X cart still boots the town.
@export var rom_path: String = ""

## The card family this unit keeps its own saves in, or "" -- see
## ExpansionCatalog.memory_of. Read from the row in _ready.
var family: String = ""

## Identity of that memory, and literally its image's filename, the way a memory
## card's is. A restore sets it before the unit enters the tree; otherwise it is
## minted in _ready. Empty on a unit that keeps no memory.
@export var card_id: String = ""
@export var card_label: String = ""

## True only for memory this session invented -- see MemoryCard.minted. Only such
## memory may have its image created.
var minted := false

const SAVES_PANEL_SCENE_PATH := "res://Scenes/UI/memory_card_panel.tscn"
var _saves_panel: MemoryCardPanel = null

## Emitted when a console is bolted on or taken off, with the console (or null).
## The room's persistence and any future cable art listen to these rather than
## polling the socket.
signal host_changed(host: RetroSystem)

## A card completed a pass through this unit's groove. `strip` indexes the card's
## own strips, or -1 when the edge presented carries no dotcode.
signal card_swiped(card: Node3D, edge: String, strip: int)
## A pass was started and not finished.
signal card_swipe_aborted(card: Node3D)


## The console currently joined to this unit, whichever side the socket is on.
var _host: RetroSystem = null
## The socket, on a MOUNT_BELOW unit. Null on one that stands on a console — its
## opposite number lives on the console instead.
var _socket: XRToolsSnapZone = null
## The foot, on a MOUNT_ABOVE unit.
var _foot: XRToolsGrabPointSnap = null
## The connector tongue, on a unit that mounts AS a cartridge. Its length is set
## against whichever console is asking -- see _aim_connector.
var _connector: XRToolsGrabPointSnap = null
## This unit's own media bays, and what is in each. Almost always one; a Sufami
## Turbo has two. Indexed rather than given a second named field, so every
## accessor is `slot := 0` and the ~10 existing callers keep working untouched --
## the same shape RetroSystem uses for its two memory-card sockets.
var _bays: Array[XRToolsSnapZone] = []
var _slot: MediaSlot = null
var _slit: CardSwipeSlit = null
var _tray: MediaTray = null
## The drawer mechanism on a tray unit that has no lid -- the mouth in the front
## face and the shelf that runs out of it. Null on a lidded unit and on every
## other kind of bay.
var _disc_bay: ProceduralDiscBay = null
var _media: Array[Node3D] = []

var _body: MeshInstance3D = null
var _label: Label3D = null
## The GLB a row's `shell` names, worn instead of the box. Null on a plain unit.
var _shell: Node3D = null
var _led_mat: BaseMaterial3D = null
var _led_on := false
var _watched_host: RetroSystem = null

## The glyph height expansion.tscn was authored at (font_size x pixel_size =
## 20 x 0.001). _fit_label never exceeds it, so it is also the ceiling.
const _LABEL_MAX_GLYPH := 0.02

## The top plate a row's cap_color paints — see _build_cap.
const _CAP_THICKNESS := 0.003
const _CAP_PROUD := 0.0002
## Where a seated disk's trailing edge sits against a shelled drive's face:
## negative is inside the mouth.
const _SHELL_DISK_PROUD := -0.008
## How far the shell's own eject cap travels; the modelled cap is small and
## already recessed, so the widget's default 8 mm pushed it through the case.
const _SHELL_EJECT_TRAVEL := 0.004

func _ready() -> void:
	super._ready()
	add_to_group(ExpansionPort.GROUP_EXPANSION)
	if not ExpansionCatalog.has(expansion_id):
		push_warning("[RetroExpansion] unknown expansion_id '%s'" % expansion_id)
		return
	_init_memory()
	_build_body()
	_build_connector()
	_build_media_bay()
	_build_accessory_mount()
	_build_ethernet_port()
	_build_link_relay()
	_update_label()
	_build_panel()


# ── its own memory ────────────────────────────────────────────────────────────


## Give a unit that keeps memory its identity. Unique against the images on disk
## and against every unit in the room, because two units spawned before either has
## an image would otherwise both be handed the same free name.
func _init_memory() -> void:
	family = ExpansionCatalog.memory_of(expansion_id)
	if family.is_empty():
		return
	if card_id.is_empty():
		var taken := {}
		for unit: Node in get_tree().get_nodes_in_group(ExpansionPort.GROUP_EXPANSION):
			if unit != self:
				taken[str(unit.get("card_id"))] = true
		var base := "%s MEMORY" % ExpansionCatalog.label_of(expansion_id).to_upper()
		var id := SramPaths.unique_card_id(base)
		var n := 1
		while taken.has(id):
			n += 1
			id = SramPaths.unique_card_id("%s %d" % [base, n])
		card_id = id
		minted = true
	if card_label.is_empty():
		card_label = card_id


## The menu verb. A unit that IS memory -- a Backup RAM Cartridge, with no bay of
## its own -- opens its card panel, as a memory card in the hand does. Every other
## unit keeps the generic panel it always had; a Sega CD's own memory is on its
## console's Saves tab rather than on a panel of the unit's.
func toggle_options_ui(camera: Node3D) -> void:
	if family.is_empty() or not ExpansionCatalog.media_of(expansion_id).is_empty():
		ObjectOptionsPanel.toggle_for(self, camera)
		return
	var panel := ensure_saves_panel()
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(self, camera)


## The panel that manages this unit's memory: the console menu's Saves tab drives
## it, and a Backup RAM Cartridge also opens it in the room. Null on a unit that
## keeps no memory.
func ensure_saves_panel() -> MemoryCardPanel:
	if family.is_empty():
		return null
	if _saves_panel == null:
		_saves_panel = (load(SAVES_PANEL_SCENE_PATH) as PackedScene).instantiate()
		add_child(_saves_panel)
	return _saves_panel


# ── the box ───────────────────────────────────────────────────────────────────


func size() -> Vector3:
	return ExpansionCatalog.size_of(_shell_id())


## The id this unit's shell is read by: its own, or the one of its variant's shell
## where a mod's shell has a molding for that market (ExpansionCatalog.shell_key).
## Set before the unit enters the room, as its variant is.
func _shell_id() -> String:
	return ExpansionCatalog.shell_key(expansion_id, SystemModelRegistry.variant_of(self))


func _build_body() -> void:
	var s := size()
	_body = $Body as MeshInstance3D
	var mesh := BoxMesh.new()
	mesh.size = s
	_body.mesh = mesh
	var mat := StandardMaterial3D.new()
	# A shade darker than the console box so a stack reads as two machines from
	# across the room rather than one tall one.
	mat.albedo_color = Color(0.38, 0.38, 0.40)
	mat.roughness = 0.7
	_body.set_surface_override_material(0, mat)
	_build_cap(s)
	_build_shell(s)

	var shape := $CollisionShape3D as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = s
	shape.shape = box

	var pointer_shape := $PointerArea/CollisionShape3D as CollisionShape3D
	var ptr := BoxShape3D.new()
	# The case's own size: grown, it took beams meant for whatever stood beside
	# the unit or on it.
	ptr.size = s
	pointer_shape.shape = ptr

	_label = $NameLabel as Label3D
	# Above the slit on a front-loading unit and below the join on a top-mounting
	# one, so the name never lands on the mouth the media goes into (it did: the
	# 64DD's plate sat across its own slit) and never on the console it stands on.
	# High too on a unit that stands in a slot (label_top), which the foot of its
	# face is inside.
	var mount := ExpansionCatalog.mount_of(expansion_id)
	var front_loading := mount == ExpansionCatalog.MOUNT_BELOW
	var label_y := (s.y * 0.5 - 0.014) \
		if front_loading or ExpansionCatalog.label_top_of(expansion_id) else (-s.y * 0.5 + 0.010)
	# A unit that stands in the room is read from +Z, but a unit that IS a
	# cartridge is swallowed by a console and read from the other side: the
	# console's slot seats it facing away, so a name on +Z is the face nobody can
	# see, printed backwards through the shell.
	# A row can say otherwise (label_front).
	var cartridge := mount == ExpansionCatalog.MOUNT_CARTRIDGE \
		and not ExpansionCatalog.label_front_of(expansion_id)
	var label_z := (-s.z * 0.5 - 0.001) if cartridge else (s.z * 0.5 + 0.001)
	_label.position = Vector3(0.0, label_y, label_z)
	_label.rotation = Vector3(0.0, PI, 0.0) if cartridge else Vector3.ZERO
	# A real shell carries its own markings.
	_label.visible = _shell == null


## The GLB a row names, scaled per axis to the catalog size and centred on the
## box it replaces, so every socket, mouth and button placed from `size` still
## lands on it.
func _build_shell(s: Vector3) -> void:
	var path := ExpansionCatalog.shell_of(_shell_id())
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var shell := packed.instantiate() as Node3D
	shell.name = "Shell"
	add_child(shell)
	var ab := _mesh_bounds(shell)
	if ab.size.x <= 0.0001 or ab.size.y <= 0.0001 or ab.size.z <= 0.0001:
		shell.queue_free()
		return
	var k := Vector3(s.x / ab.size.x, s.y / ab.size.y, s.z / ab.size.z)
	shell.scale = k
	shell.position = -(ab.position + ab.size * 0.5) * k + ExpansionCatalog.shell_offset_of(_shell_id())
	_shell = shell
	_body.visible = false
	_build_shell_lods(shell)
	var albedo := ExpansionCatalog.shell_albedo_of(_shell_id())
	if not albedo.is_empty():
		ModelMaterialFix.retexture(shell, "shell", albedo)

	var led := shell.find_child("AccessLed", true, false) as MeshInstance3D
	if led != null and led.get_active_material(0) is BaseMaterial3D:
		_led_mat = (led.get_active_material(0) as BaseMaterial3D).duplicate()
		_led_mat.emission_enabled = false
		_led_mat.emission = Color(1.0, 0.12, 0.05)
		_led_mat.emission_energy_multiplier = 2.5
		led.set_surface_override_material(0, _led_mat)
		host_changed.connect(_watch_access_led)


## How far past a level's switch distance the camera has to go before the other
## level takes over, in metres. With fading off, a visibility range's margin is
## hysteresis, so a unit held near a switch distance does not flicker between two.
const LOD_HYSTERESIS := 0.1


## The shell's lower levels of detail, each given the shell's own scale and offset
## and shown only in its band of camera distance. The levels share the shell's
## bounds, which is what lets its numbers carry over. Markers (SocketMarker,
## AccessLed, ...) are only ever read off the full shell.
func _build_shell_lods(shell: Node3D) -> void:
	var lods := ExpansionCatalog.shell_lods_of(_shell_id())
	if lods.is_empty():
		return
	var levels: Array[Node3D] = [shell]
	var starts: Array[float] = [0.0]
	for entry: Array in lods:
		var path := str(entry[0])
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var level := packed.instantiate() as Node3D
		level.name = "ShellLOD%d" % levels.size()
		level.scale = shell.scale
		level.position = shell.position
		add_child(level)
		levels.append(level)
		starts.append(float(entry[1]))
	for i in levels.size():
		var begin: float = starts[i]
		var end: float = starts[i + 1] if i + 1 < levels.size() else 0.0
		for n in levels[i].find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			g.visibility_range_begin = begin
			g.visibility_range_begin_margin = LOD_HYSTERESIS if begin > 0.0 else 0.0
			g.visibility_range_end = end
			g.visibility_range_end_margin = LOD_HYSTERESIS if end > 0.0 else 0.0


## Bounds of every mesh under `root`, in `root`'s own space.
static func _mesh_bounds(root: Node3D) -> AABB:
	var to_root := root.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = (to_root * mi.global_transform) * mi.get_aabb()
		acc = ab if first else acc.merge(ab)
		first = false
	return acc


## A named node of the shell, or null on a plain unit.
func _shell_node(node_name: String) -> Node3D:
	if _shell == null:
		return null
	return _shell.find_child(node_name, true, false) as Node3D


## The ACCESS lamp is the drive's, so it follows the core's LED interface
## through the console standing on the unit, as the Satellaview's does.
const CORE_LED_ACCESS := 0


func _watch_access_led(sys: RetroSystem) -> void:
	if is_instance_valid(_watched_host):
		var old: Libretro = _watched_host.get_libretro_node()
		if old != null and old.led_state.is_connected(_on_core_led):
			old.led_state.disconnect(_on_core_led)
	_watched_host = sys
	_set_led(false)
	if sys == null:
		return
	var node: Libretro = sys.get_libretro_node()
	if node != null and not node.led_state.is_connected(_on_core_led):
		node.led_state.connect(_on_core_led)


func _on_core_led(led: int, on: bool) -> void:
	if led == CORE_LED_ACCESS:
		_set_led(on)


func _set_led(on: bool) -> void:
	if on == _led_on or _led_mat == null:
		return
	_led_on = on
	_led_mat.emission_enabled = on


## The coloured plate across a unit's top face, for a row that names one. The
## Expansion Pak's red top is the only one so far, and it earns its keep: in a
## bay where it and the Jumper Pak are the same size and the same shape, colour
## is the only thing that says which of the two is currently installed.
##
## Sunk so its top finishes level with the shell rather than standing proud of
## it -- the pak lives in a 24 mm well with a lid 5 mm above it, and a plate
## that added height would foul the lid. The fifth of a millimetre it does
## stand is the same trick ExpansionPort uses on its connector: two coplanar
## faces have no depth order and shimmer, and 0.2 mm is far too small to read.
func _build_cap(s: Vector3) -> void:
	var cap := _body.get_node_or_null("CapPlate") as MeshInstance3D
	var colour := ExpansionCatalog.cap_color_of(expansion_id)
	if colour.a <= 0.0:
		if cap != null:
			cap.queue_free()
		return
	if cap == null:
		cap = MeshInstance3D.new()
		cap.name = "CapPlate"
		_body.add_child(cap)
	var mesh := BoxMesh.new()
	# Inset a hair on both spans so the sides never land in the shell's own
	# planes either.
	mesh.size = Vector3(s.x * 0.98, _CAP_THICKNESS, s.z * 0.98)
	cap.mesh = mesh
	cap.position = Vector3(0.0, s.y * 0.5 - _CAP_THICKNESS * 0.5 + _CAP_PROUD, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.55
	cap.set_surface_override_material(0, mat)


## The front face some units wear -- the Satellaview's POWER and ACCESS lamps are
## the only one so far. The scene is named by the catalog row rather than by an
## id test here, the same way every other per-unit fact in this file is, and the
## panel finds this unit's console through host_changed on its own.
func _build_panel() -> void:
	var scene_path := ExpansionCatalog.panel_of(expansion_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("[RetroExpansion] '%s' names a panel that will not load: %s"
			% [expansion_id, scene_path])
		return
	add_child(packed.instantiate())


## The unit's own name, from the catalog. It does not name the console bolted to
## it -- a stack is read from the console's plate, which carries both halves.
func _update_label() -> void:
	if _label == null:
		return
	_label.text = ExpansionCatalog.display_label_of(expansion_id)
	_fit_label()


## Shrink the plate until it fits the case it is printed on.
##
## The authored pixel_size gives a fixed ~20 mm of glyph height whatever the
## unit is, which is right for the boxes this file was written for -- a 64DD is
## 300 mm wide -- and absurd on a 75 mm Jumper Pak, where "Expansion Pak" came
## out wider than the whole module and read as a floating banner beside the
## console rather than a name printed on it.
##
## Both bounds only ever REDUCE the authored size (the min against
## _LABEL_MAX_GLYPH), so every unit that already looked right is untouched and
## only the small ones move.
func _fit_label() -> void:
	var s := size()
	if s.x <= 0.0 or _label.font_size <= 0:
		return
	var chars := maxi(_label.text.length(), 1)
	# ~0.55 em per character is close enough for a proportional face; this only
	# has to stop the text overrunning the case, not typeset it.
	var by_width := (s.x * 0.9) / (float(chars) * 0.55)
	var glyph := minf(_LABEL_MAX_GLYPH, minf(by_width, s.y * 0.45))
	_label.pixel_size = glyph / float(_label.font_size)


# ── the connector ─────────────────────────────────────────────────────────────


func _build_connector() -> void:
	var s := size()
	var span := Vector2(s.x, s.z)
	if ExpansionCatalog.mount_of(expansion_id) == ExpansionCatalog.MOUNT_CARTRIDGE:
		# We ARE the cartridge -- the console's own slot takes us, and joining the
		# group that slot accepts is most of it.
		add_to_group(MEDIA_GROUP)
		# But not all of it. A snap zone seats an object by its grab point, and
		# with none the object's ORIGIN lands on the zone -- which for a cartridge
		# slot is where a cartridge's MIDDLE sits, well inside the console. A
		# cartridge is meant to be mostly swallowed; a whole machine is not, and
		# the Jaguar CD sank into the Jaguar far enough to bury its own OPEN
		# button.
		#
		# What actually goes into the slot is this unit's connector, so that is
		# what the grab point marks: a tongue hanging below the unit, long enough
		# that the unit's underside comes to rest ON the console's roof with only
		# the connector inside it.
		#
		# How long that tongue is cannot be decided here. It is the distance from
		# the console's cartridge slot up to its top face, which is a different
		# figure on every shell -- so the point is placed when a slot actually
		# asks for it, in _get_grab_point, against the machine asking. Derived
		# from the CARTRIDGE's height instead, the 32X and the Jaguar CD floated
		# well above their consoles.
		_connector = XRToolsGrabPointSnap.new()
		_connector.name = "CartridgeConnector"
		_connector.require_group = ExpansionPort.GROUP_CART_SLOT
		add_child(_connector)
		_aim_connector(null)
		# By hand, for the same reason the foot is: XRToolsPickable collects its
		# grab points in _ready, which has already run by the time we get here.
		_grab_points.push_back(_connector)
		return

	if ExpansionCatalog.mount_of(expansion_id) == ExpansionCatalog.MOUNT_BELOW:
		# The console stands on us: we hold the socket, and only the console this
		# unit was made for is allowed into it.
		var seat_y := ExpansionCatalog.seat_y_of(_shell_id())
		_socket = ExpansionPort.build_socket(self, s.y * 0.5 if is_nan(seat_y) else seat_y, span,
			ExpansionPort.GROUP_SYSTEM, _accepts_host, _shell == null)
		_socket.has_picked_up.connect(_on_host_seated)
		_socket.has_dropped.connect(_on_host_lifted)
	else:
		# We stand on the console: we wear the foot, and the console's own socket
		# is what takes us. Registered by hand because XRToolsPickable collects
		# grab points in its _ready, which has already run by the time we get here.
		# A shell molds its own connector: the plate is for the primitive box,
		# and under a Jumper Pak's shell it hung below it as a block.
		_foot = ExpansionPort.build_foot(self, -s.y * 0.5, span, _shell == null)
		_grab_points.push_back(_foot)


## Aim the connector at `zone`'s machine before handing it over.
##
## snap_pose_for asks for the grab point every time it ranks or previews a zone,
## and the answer decides where this unit lands, so setting it here makes the
## ghost and the seat agree by construction -- they are the same query.
##
## A null zone (or one that belongs to no console) leaves the tongue at zero, so
## the unit seats on the slot itself. That is where a preview sits for the few
## frames before a console's model has meshes to measure, and it is never cached.
func _get_grab_point(grabber: Node3D, current: XRToolsGrabPoint) -> XRToolsGrabPoint:
	var point := super(grabber, current)
	if point != null and point == _connector:
		_aim_connector(grabber as XRToolsSnapZone)
	return point


func _aim_connector(zone: XRToolsSnapZone) -> void:
	if _connector == null:
		return
	# The seat composes this point's whole transform, so turning it turns the unit
	# in the slot (snap_pose_for). The e-Reader goes in facing the other way from a
	# cartridge's label.
	_connector.basis = Basis(Vector3.UP, deg_to_rad(ExpansionCatalog.seat_yaw_of(_shell_id())))
	# A unit whose modelled tongue goes INTO the slot, the way a cartridge's does
	# (the e-Reader), names the point the seat takes: where a cartridge's middle
	# would be if the tongue were one. Every console's slot already seats a
	# cartridge there, so no console needs measuring.
	var fixed: Variant = ExpansionCatalog.connector_of(_shell_id())
	if fixed is Vector3:
		_connector.position = fixed
		return
	var lift := 0.0
	if zone != null:
		var n: Node = zone.get_parent()
		while n != null:
			if n is RetroSystem:
				lift = (n as RetroSystem).roof_above_cartridge_slot()
				break
			n = n.get_parent()
	_connector.position = Vector3(0.0, -(size().y * 0.5 + lift), 0.0)


## Socket gate: is this the console this unit bolts to? A Mega-CD takes a Mega
## Drive and refuses everything else, silently, the way every snap zone here does.
func _accepts_host(obj: Node3D) -> bool:
	var sys := obj as RetroSystem
	if sys == null:
		return false
	# The opening our plug goes up into is shut while its cover is on, as on the
	# real console: the cover has to come off before the console stands on us.
	if sys.port_cover_on(ExpansionCatalog.cover_socket_of(expansion_id)):
		return false
	return sys.systemid == ExpansionCatalog.host_of(expansion_id)


func _on_host_seated(obj: Node3D) -> void:
	var sys := obj as RetroSystem
	if sys == null:
		return
	_bind_host(sys)
	# The console standing on us is frozen while it does: we carry its box.
	SeatedCollision.lend(self, sys, _socket)


func _on_host_lifted() -> void:
	SeatedCollision.withdraw_zone(self, _socket)
	_unbind_host()


## Called from either side of the join: by our own socket when we took a console,
## and by the console's socket when IT took us.
func _bind_host(sys: RetroSystem) -> void:
	if _host == sys:
		return
	_unbind_host()
	_host = sys
	print("[RetroExpansion] %s: on %s (%s)" % [expansion_id, sys.name, sys.systemid])
	# The seated machine is frozen and rides us through the scene graph; without
	# this the two boxes fight at the face they are pressed together at.
	add_collision_exception_with(sys)
	_except_accessory_from(sys, true)
	sys.attach_expansion(self)
	# Our plug fills the opening its cover came off: the cover cannot go back
	# while the console stands on us.
	sys.block_port_cover(ExpansionCatalog.cover_socket_of(expansion_id), true)
	# Seated in one of the console's sockets (a Super Game Boy or a 32X in the
	# cartridge slot), this unit is frozen and stands well out of it: the console
	# carries its box, and through it whatever is in this unit's own bay.
	var zone := _holding_zone()
	if zone != null:
		SeatedCollision.lend(sys, self, zone)
	_update_label()
	host_changed.emit(sys)


func _unbind_host() -> void:
	if _host == null:
		return
	var was := _host
	_host = null
	if is_instance_valid(was):
		print("[RetroExpansion] %s: off %s (%s)" % [expansion_id, was.name, was.systemid])
		SeatedCollision.withdraw(was, self)
		remove_collision_exception_with(was)
		_except_accessory_from(was, false)
		was.detach_expansion(self)
		was.block_port_cover(ExpansionCatalog.cover_socket_of(expansion_id), false)
	_update_label()
	host_changed.emit(null)


## The console's socket holding this unit, or null for a unit the console stands on.
func _holding_zone() -> Node3D:
	if ExpansionCatalog.mount_of(expansion_id) == ExpansionCatalog.MOUNT_BELOW:
		return null
	var driver: Variant = VrHold.grab_driver(self)
	if driver == null or not is_instance_valid(driver.primary):
		return null
	return driver.primary.by as XRToolsSnapZone


## The console this unit is joined to, or null.
func get_host() -> RetroSystem:
	return _host if is_instance_valid(_host) else null


## Bolt to `sys` from the console's side. Only meaningful on a MOUNT_ABOVE unit;
## a MOUNT_BELOW unit is bound by its own socket instead.
func bind_to_host(sys: RetroSystem) -> void:
	_bind_host(sys)


func unbind_from_host() -> void:
	_unbind_host()


# ── the media bay ─────────────────────────────────────────────────────────────


## Where the bay goes follows the mount: a unit with a console standing on it
## loads through the FRONT (a slit, like a 64DD or a front-loading Mega-CD), and
## one that stands on a console loads from the TOP, where nothing covers it.
func _build_media_bay() -> void:
	var media := ExpansionCatalog.media_of(expansion_id)
	if media.is_empty():
		return
	# Some units have no mouth. The Satellaview is a tuner and a modem that clips
	# under the console; the cartridge goes into the SUPER FAMICOM's slot, on top,
	# and this unit builds nothing for it. Without this the bay landed on the
	# unit's roof -- which is the face the console is standing on -- and the
	# cartridge vanished into the join between the two machines.
	if ExpansionCatalog.media_in_host(expansion_id):
		return
	var s := size()
	# A slit in the front is for media that SLIDES IN: a 64DD disk, an FDS disk.
	# Which way the unit stacks does not decide that -- a Satellaview sits under
	# a Super NES and takes a memory pack pushed into the top of it, and a
	# Mega-CD sits under a Mega Drive and opens a lid. Deciding by mount buried
	# the Satellaview's pack 92 mm inside the box, out of sight and out of reach,
	# because it rode the slot travel meant for something a third of its length.
	var loader := ExpansionCatalog.loader_of(expansion_id)
	# A swiped medium is never held, so this unit gets a groove and NO bay. The
	# snap zones below are built before the loader is branched on, and one of them
	# would capture the card part-way through the swipe.
	if loader == MediaDimensions.LOADER_SWIPE:
		_build_swipe_slit(size(), media)
		return
	var front_loading := loader == MediaDimensions.LOADER_SLOT

	var count := ExpansionCatalog.bays_of(expansion_id)
	_media.resize(count)

	for i in count:
		var bay := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
		# "MediaBay", then "MediaBay2" -- the numbering RetroSystem's memory-card
		# sockets already use, so the first bay's node name is unchanged and every
		# scene, test and save file that names it keeps resolving.
		bay.name = "MediaBay" if i == 0 else "MediaBay%d" % (i + 1)
		bay.snap_require = MEDIA_GROUP
		bay.snap_filter = _accepts_media
		# 70 mm of capture radius is right for a unit with one mouth and far too
		# much for a unit whose mouths are 65 mm apart: two spheres that size
		# overlap almost completely, and every reach lights up both previews.
		bay.grab_distance = 0.07 if count == 1 else 0.03
		add_child(bay)
		_bays.append(bay)

	if front_loading:
		_build_slot_bay(s, media)
	elif loader == MediaDimensions.LOADER_TRAY:
		_build_tray_bay(s, media, loader)
	else:
		_build_well_bay(s, media, loader)


## Media that SLIDES IN through a slit in the front face: a 64DD disk, an FDS
## disk. MediaSlot runs the ride in and out.
func _build_slot_bay(s: Vector3, media: String) -> void:
	# At the mouth of the slit, a third of the way up the front face -- or where
	# the shell's socket marker says a seated disk sits.
	_bays[0].position = Vector3(0.0, -s.y * 0.2, s.z * 0.5)
	var socket := _shell_node("SocketMarker")
	var seated := Vector3.ZERO
	if socket != null:
		seated = to_local(socket.global_position)
		_bays[0].position = Vector3(seated.x, seated.y, s.z * 0.5)
	if _shell == null:
		ExpansionShell.build_slit(_body, s, media)
	# The ride in and out, the grab hand-off and the collision exception, all
	# from the same component the slot-loading consoles use. Its `host` is
	# typed PhysicsBody3D rather than RetroSystem precisely so a second kind
	# of machine can own one.
	_slot = MediaSlot.new()
	_slot.host = self
	_slot.slot = _bays[0]
	# How far it rides in. The consoles' slot inset is a disc figure and a
	# 64DD disk is shorter, so taken flat it would vanish inside the drive;
	# measured from the media itself, roughly two thirds swallowed, the head
	# stays out in the room where a hand can reach it -- which is what a
	# loaded 64DD looks like.
	var media_size := MediaDimensions.cart_size(media)
	# A flat disk goes in the way you hold it: LABEL UP, shutter first.
	# The media is modelled with its label on +Z and its shutter at +Y,
	# so a quarter turn back about X lays the label upward and points the
	# shutter into the machine. Set on the SLOT rather than the bay: the
	# slot rides its media along its own -Z, and turning the bay would
	# have turned that axis too, sending the disk down through the floor
	# of the drive instead of into it.
	_slot.media_local_basis = Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))
	# A cartridge goes in another way round (the Game Boy Player's, label down and
	# contacts first): the row says how.
	var turn: Variant = ExpansionCatalog.slot_basis_of(expansion_id)
	if turn is Basis:
		_slot.media_local_basis = turn as Basis
	# insert_depth places the disk's CENTRE, not its trailing edge, so
	# the disc figure would bury a 64DD disk completely: at 0.66 of its
	# length the whole thing sits inside the drive. A fifth of the
	# length leaves about a third of the disk out in the room, which is
	# what a loaded 64DD looks like and what a hand needs to pull it
	# back out.
	_slot.insert_depth = media_size.y * 0.2
	# A real drive swallows the disk to a lip; the eject button is what brings
	# it back within reach.
	if socket != null:
		_slot.insert_depth = media_size.y * 0.5 - _SHELL_DISK_PROUD
		# Or to the marker itself, for media whose end stays out of the mouth: the
		# marker is where its middle comes to rest.
		if ExpansionCatalog.slot_marker_depth_of(expansion_id):
			_slot.insert_depth = s.z * 0.5 - seated.z
	add_child(_slot)
	_slot.inserted.connect(_on_media_in)
	_slot.removed.connect(_on_media_out)
	# A slot bay swallows its media and MediaSlot makes it neither grabbable nor
	# pointable while it is in there, so without this button a 64DD disk went in
	# and could not come back out.
	_build_eject_button(s, media)


## Media that is SWIPED rather than loaded: a groove across the roof, and no bay.
##
## The card stays in the hand for the whole pass, so there is nothing to seat and
## nothing to eject. CardSwipeSlit constrains the pose and reports a completed
## pass; this unit only forwards it.
func _build_swipe_slit(s: Vector3, media: String) -> void:
	var card := MediaDimensions.cart_size(media)
	# A shell with a card channel of its own says where it is, and which way a
	# card lies in it; anything else gets a groove cut in its roof.
	var frame: Variant = ExpansionCatalog.swipe_slit_of(_shell_id())
	var place := Transform3D.IDENTITY
	if frame is Transform3D:
		place = frame
	else:
		place.origin = ExpansionShell.build_through_slot(_body, s, card)

	_slit = CardSwipeSlit.new()
	_slit.name = "SwipeSlit"
	_slit.card_group = MEDIA_GROUP
	_slit.card_filter = _accepts_media
	# The same mask a snap zone carries, and for the same reason: media rests on
	# layer 3 and XRToolsPickable moves it to DEFAULT_LAYER while a hand has it,
	# so a groove watching only one of the two never sees a card being carried
	# through it -- which is the only way a card ever arrives.
	_slit.collision_mask = 0b0000_0000_0000_0001_0000_0000_0000_0100
	# The groove runs the width of the case, and a pass has to clear both ends.
	_slit.travel = s.x
	add_child(_slit)
	_slit.transform = place

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The volume that WATCHES for a card, and it is deliberately generous.
	#
	# It was cut to the card's own thickness, 6.8 mm deep, so a card had to be
	# lined up to within 3.4 mm of the groove plane before the groove would so
	# much as notice it -- while being 22 mm forgiving in height. That is an
	# invisible tolerance a hand cannot find, and it reads as the slot ignoring
	# the card.
	#
	# It could not be any bigger while ENTRY was also the decision, since a pose
	# sampled anywhere in here decided the whole pass. It is not any more:
	# CardSwipeSlit.is_presenting arms on the card's own pose, so this box only
	# has to answer "there is a card near the slot", and the sloppier it is the
	# sooner a hand gets picked up. Wider than the case as well, because a pass
	# has to clear both ends and can start beyond one.
	box.size = Vector3(s.x + 0.03, card.y, 0.05)
	shape.shape = box
	_slit.add_child(shape)

	_slit.swiped.connect(_on_card_swiped)
	_slit.aborted.connect(_on_card_swipe_aborted)


func _on_card_swiped(card: Node3D, edge: String, strip: int) -> void:
	card_swiped.emit(card, edge, strip)


func _on_card_swipe_aborted(card: Node3D) -> void:
	card_swipe_aborted.emit(card)


## A CD unit -- a lid in the roof, or a drawer out of the front.
##
## Every one of these loads from the top on the real hardware, and the disc
## consoles already have the pair that models it: a MediaTray for the lid and
## the seating, and a button that opens it. Reusing them means a Mega-CD
## behaves like every other disc machine in the room rather than like a slot
## that swallows a disc whole.
func _build_tray_bay(s: Vector3, media: String, loader: int) -> void:
	_tray = MediaTray.new()
	_tray.host = self
	_tray.slot = _bays[0]
	if ExpansionCatalog.lid_of(expansion_id):
		# A LID. The disc lies in a well in the roof and the lid swings up off
		# it, the way a PlayStation or a GameCube opens.
		_bays[0].position = Vector3(0.0, s.y * 0.5, 0.0)
		ExpansionShell.build_well(_body, s, media, loader)
		_tray.lid_pivot = ExpansionShell.build_lid(self, s)
		add_child(_tray)
	else:
		# A DRAWER, and the same one a PlayStation 2 runs: a mouth in the front
		# face and a shelf that carries the disc out through it. Pressing OPEN
		# used to change nothing anybody could see -- MediaTray only animates a
		# lid pivot, and a tray unit with no lid had none, so the button
		# toggled a state with no mechanism attached to it.
		#
		# ProceduralDiscBay is the console's own mechanism, handed this unit's
		# box instead of the placeholder console's so the mouth lands on THIS
		# machine's front face. disc_lid_pivot is what makes the snap zone ride
		# the shelf, so a disc laid on the tray travels in with it -- and it has
		# to be set before the tray enters the tree, because MediaTray measures
		# the zone against the pivot in its _ready.
		# Below the middle of the face, not above it. The unit wears its
		# nameplate high on the front (_build_body puts it at s.y * 0.5 -
		# 14 mm on a MOUNT_BELOW unit), and a deck placed like a console's
		# ran the mouth -- and the disc riding out of it -- straight across
		# the lettering.
		_disc_bay = ProceduralDiscBay.build_tray(self, _bays[0], media, true,
			Callable(), s, ExpansionShell.deck_y(s))
		_tray.disc_lid_pivot = _disc_bay.slide_pivot
		# Where the disc actually LIES on that shelf, and it is not the
		# shelf pivot's own origin. build_tray puts the snap zone 2.5 mm up
		# from the pivot, which is what clears the 3 mm well cylinder drawn
		# around it; seated at the pivot instead, the disc sat INSIDE that
		# well with the well's opaque top face over it, so it snapped to the
		# right place and then vanished into the tray.
		#
		# Read off the two nodes rather than written as a number, and it is
		# the same line RetroSystem uses for its own tray -- the offset is a
		# property of how ProceduralDiscBay lays the shelf out, so asking it
		# cannot drift the way a copied constant would.
		var pivot_inv := _disc_bay.slide_pivot.global_transform.affine_inverse()
		var rel := pivot_inv * _bays[0].global_transform
		_tray.media_local_basis = rel.basis
		_tray.seat_offset = rel.origin
		add_child(_tray)
		_tray.opened.connect(func() -> void: _disc_bay.slide(true))
		_tray.closed.connect(func() -> void: _disc_bay.slide(false))
	_tray.loaded.connect(_on_media_in)
	_tray.unloaded.connect(_on_media_out)
	_build_eject_button(s, media)


## A well in the roof. The cart stands proud of it, which is what a 32X
## cartridge does and what makes it obvious the unit is loaded.
## Several wells are spread along X, evenly about the centre, so a two-bay unit
## reads as a pair of mouths side by side rather than one mouth off to a side.
## The offsets are computed rather than written down: the catalog owns both the
## box and the cartridge, and a hand-placed constant would go stale the moment
## either is tuned.
##
## The mesh takes the SAME offset as the zone. They are placed independently, and
## moving only the zone gives a unit that catches a cartridge where no hole is
## drawn -- see ExpansionShell.build_well.
func _build_well_bay(s: Vector3, media: String, loader: int) -> void:
	var n := _bays.size()
	var pitch := MediaDimensions.cart_size(media).x + 0.010
	# A shell that models its own slot (the 32X) marks where a cartridge in it comes
	# to rest -- the floor of its slot funnel, which is neither the box's roof nor
	# its middle -- and draws its own mouth, so no dark plate goes on top of it.
	var floor_marker := _shell_node("CartFloor")
	for i in n:
		var x: float = (float(i) - float(n - 1) * 0.5) * pitch
		if floor_marker != null and n == 1:
			_floor_seat = to_local(floor_marker.global_position)
			_seat_on_floor(media)
		else:
			_bays[i].position = Vector3(x, s.y * 0.5, 0.0)
			ExpansionShell.build_well(_body, s, media, loader, x)
		# Bound, so each zone reports the slot it IS. Without the bind both bays
		# write the same entry and the second cartridge is invisible.
		_bays[i].has_picked_up.connect(_on_media_in.bind(i))
		_bays[i].has_dropped.connect(_on_media_out.bind(i))


## The floor of a shell-modelled slot, in this unit's frame; null without one.
var _floor_seat: Variant = null


## Stand the one bay of a shell-modelled slot on its floor at the height of a
## `media` cartridge: the bay holds a cartridge by its middle, and a Genesis
## cartridge in a 32X is 6 mm shorter than the 32X's own.
func _seat_on_floor(media: String) -> void:
	if _floor_seat == null or _bays.size() != 1:
		return
	var h: float = MediaDimensions.cart_size(media).y
	_bays[0].position = (_floor_seat as Vector3) + Vector3(0.0, h * 0.5, 0.0)


## Bay gate: is this the media this unit takes? Media with no systemid of its own
## is let through — a blank cartridge is whatever machine it is put into, which
## is how RetroSystem treats one too.
func _accepts_media(obj: Node3D) -> bool:
	if obj == null or not ("systemid" in obj):
		return false
	var mid := str(obj.get("systemid"))
	var media := ExpansionCatalog.media_of(expansion_id)
	if mid.is_empty() or mid == media:
		return true
	# A cartridge the unit passes through to the console (a Genesis game in a 32X).
	if ExpansionCatalog.passes_of(expansion_id).has(mid):
		return true
	# A Game Boy bay (the Super Game Boys') takes the Color library's cartridges
	# as well, as the hardware does: the black dual-mode ones play, and a
	# Color-only game puts up its own "Game Boy Color only" screen.
	return media == GbCartShell.SYSTEMID and GbCartShell.is_shell(mid)


func _on_media_in(media: Node3D, slot := 0) -> void:
	if slot >= _media.size():
		return
	_media[slot] = media
	print("[RetroExpansion] %s: game in bay %d: %s" % [expansion_id, slot + 1, media.get("rom_path")])
	if _slot == null:
		add_collision_exception_with(media)
		# A cartridge standing out of the roof (a Game Boy's in a Super Game Boy)
		# rides frozen: this unit carries its box, and passes it on to the console.
		if media is CollisionObject3D:
			SeatedCollision.lend(self, media as CollisionObject3D, _bays[slot])
	# Back-fill, exactly as a console does: a disk put into a 64DD is a 64DD disk.
	if "systemid" in media and str(media.get("systemid")).is_empty():
		media.set("systemid", ExpansionCatalog.media_of(expansion_id))
	if "systemid" in media:
		_seat_on_floor(str(media.get("systemid")))
	_swing_flaps(true)
	_notify_host_media()


func _on_media_out(slot := 0) -> void:
	if slot >= _media.size():
		return
	var was: Node3D = _media[slot]
	if is_instance_valid(was):
		print("[RetroExpansion] %s: game out of bay %d: %s" % [expansion_id, slot + 1, was.get("rom_path")])
	if is_instance_valid(was) and _slot == null:
		remove_collision_exception_with(was)
		SeatedCollision.withdraw(self, was as CollisionObject3D)
	_media[slot] = null
	_seat_on_floor(ExpansionCatalog.media_of(expansion_id))
	_swing_flaps(false)
	_notify_host_media()


## How far a shell's slot flaps swing, and how fast -- the Mega Drive's own figures
## (genesis_model.gd), since the 32X's slot is the same pair of sprung flaps.
const _FLAP_OPEN_DEG := 80.0
const _FLAP_SWING_SEC := 0.12
var _flap_tween: Tween = null


## Open or close the dust flaps of a shell that has them (Flap_Front / Flap_Back,
## each origined on its hinge). They meet in the middle of the slot and fold down
## into it about their outer edges, so the front one turns about -X and the rear
## one about +X, as the console's do. A no-op on every unit without them.
func _swing_flaps(open: bool) -> void:
	var front := _shell_node("Flap_Front")
	var back := _shell_node("Flap_Back")
	if front == null or back == null:
		return
	if _flap_tween != null and _flap_tween.is_valid():
		_flap_tween.kill()
	var angle := deg_to_rad(_FLAP_OPEN_DEG) if open else 0.0
	_flap_tween = create_tween().set_parallel(true)
	_flap_tween.tween_property(front, "rotation:x", -angle, _FLAP_SWING_SEC)
	_flap_tween.tween_property(back, "rotation:x", angle, _FLAP_SWING_SEC)


## Tell the console its stack changed, if a console is bolted on.
func _notify_host_media() -> void:
	var h := get_host()
	if h != null:
		h.on_expansion_media_changed(self)


## How many cartridges this unit holds at once.
func get_bay_count() -> int:
	return _media.size()


## What is in one of this unit's bays, or null.
##
## Range-checked rather than indexed, because slot 1 is asked of every unit by
## code that does not know how many bays this one has -- and a single-bay unit
## answering "nothing in my second bay" is the correct answer, where a crash or a
## silent alias to bay 0 are both wrong. The alias is the more dangerous of the
## two: it reads as a cartridge that is not there.
func get_media(slot := 0) -> Node3D:
	if slot < 0 or slot >= _media.size():
		return null
	var m: Node3D = _media[slot]
	return m if is_instance_valid(m) else null


## The path of the disk/disc/cart in one of this unit's bays. Empty when the bay
## is empty or the media carries no ROM — which is the state a stack powers on in
## when the player has only put a game in the console.
func get_media_path(slot := 0) -> String:
	var m := get_media(slot)
	if m == null or not m.has_method("get_rom_path"):
		return ""
	return str(m.call("get_rom_path"))


## Is this unit's tray standing open? A disc lying in an open tray is not loaded.
func is_tray_open() -> bool:
	return _tray != null and _tray.is_open()


## The path of the media the drive would actually read: "" while its tray is
## open, whatever is lying in it. What a boot asks; saves and menus still want
## get_media_path.
func get_loaded_media_path(slot := 0) -> String:
	return "" if is_tray_open() else get_media_path(slot)


## Seat media after a save restore, bypassing the insert ride and its noise.
func restore_media_in_slot(media: Node3D, slot := 0) -> void:
	if _slot != null:
		_slot.restore(media)
	elif slot >= 0 and slot < _bays.size():
		_bays[slot].pick_up_object(media)


## The socket, for the console to release when it is pulled off from the far side.
func get_socket() -> XRToolsSnapZone:
	return _socket


# ── a clip-on accessory ───────────────────────────────────────────────────────

## The zone a clip-on accessory seats in -- the 32X's Model 2 spacer -- or null on
## a unit whose row names no `accessory_group`.
var _accessory_mount: XRToolsSnapZone = null
## What is clipped on, kept so its exemptions can be undone after it is gone.
var _accessory: PhysicsBody3D = null


## A small snap zone at the shell's own origin -- its resting plane, under the
## middle of the footprint -- taking the row's accessory group. The accessory's
## model shares the shell's frame and seats by an identity grab point, so it lands
## exactly where it was modelled. 30 mm of capture, as the paks' ports have: a
## zone that small is touched only when the accessory is offered to it, where a
## larger one would win grabs meant for the unit itself.
func _build_accessory_mount() -> void:
	var group := ExpansionCatalog.accessory_group_of(expansion_id)
	if group.is_empty() or _shell == null:
		return
	var zone := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	zone.name = "AccessoryMount"
	zone.snap_require = group
	zone.grab_distance = 0.03
	add_child(zone)
	zone.position = _shell.position
	zone.has_picked_up.connect(_on_accessory_in)
	zone.has_dropped.connect(_on_accessory_out)
	_accessory_mount = zone


# ── a network adapter's socket ────────────────────────────────────────────────

const _ETHERNET_PORT_SCENE := preload("res://Scenes/Objects/cables/ethernet_port.tscn")

## The RJ45 socket on a network adapter -- the row's `ethernet_port` -- or null.
var _ethernet_port: EthernetPort = null
## The plug in it, so a release can undo the exemption its seating made.
var _ethernet_plug: PhysicsBody3D = null


## Where the real card's jack is (the row's or a mod shell's `jack`), so on a
## modelled console the lead goes in where the real one does; with none, on the
## face left outside the console. Named, because a save records a seated plug by
## its socket's name (CompositeCable.port_named).
func _build_ethernet_port() -> void:
	var link_port := ExpansionCatalog.ethernet_port_of(expansion_id)
	if link_port < 0:
		return
	var port := _ETHERNET_PORT_SCENE.instantiate() as EthernetPort
	port.name = "EthernetPort"
	port.link_port = link_port
	add_child(port)
	# A mod's shell draws the jack's mouth and face; the socket's own would sit in
	# them. The plain box draws none, so there the socket keeps its own.
	if _shell != null and ExpansionCatalog.ethernet_jack_of(_shell_id()) is Transform3D:
		port.show_recess = false
		port.show_legend = false
	port.has_picked_up.connect(_on_ethernet_plug_in)
	port.has_dropped.connect(_on_ethernet_plug_out)
	host_changed.connect(_on_ethernet_host_changed)
	_ethernet_port = port
	_place_ethernet_port(null)


## The socket in the jack the row or the shell gives -- unless the plain box is
## in the stand-in console's back panel: ExpansionPort.seat_through_back turns a
## unit so its +Y runs out of the back panel and only that end is left showing,
## and a jack placed for the real card's face would be inside the console. There
## it is on the +Y end, turned for its +Z -- where a plug arrives from -- to point
## along it. A shell keeps its jack wherever it is seated: its mouth is molded.
func _place_ethernet_port(host: RetroSystem) -> void:
	var jack: Variant = ExpansionCatalog.ethernet_jack_of(_shell_id())
	var stand_in_console := host != null and host.get_model() is RetroSystemModelDefault
	if jack is Transform3D and not (stand_in_console and _shell == null):
		_ethernet_port.transform = jack
	else:
		var s := size()
		_ethernet_port.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
			Vector3(0.0, s.y * 0.5 + 0.0015, 0.0))


## The network adapter's socket, or null on any other unit.
func get_ethernet_port() -> EthernetPort:
	return _ethernet_port


## Seated in a console or taken out of one with a lead still in it: the walk from
## this socket now ends at a different machine, or none, so the LAN the lead is on
## is worked out again. Nothing else would ask -- the lead itself did not move.
func _on_ethernet_host_changed(sys: RetroSystem) -> void:
	_place_ethernet_port(sys)
	var plug := _ethernet_port.picked_up_object as RcaPlug
	if plug != null and is_instance_valid(plug.cable) and plug.cable.has_method("_resolve"):
		plug.cable.call("_resolve")


## A seated plug's body goes most of its length into this box and is frozen, so
## left colliding it would shove the unit out of its slot -- ILinkHub's reason.
func _on_ethernet_plug_in(what: Node) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	add_collision_exception_with(body)
	_ethernet_plug = body


func _on_ethernet_plug_out() -> void:
	if is_instance_valid(_ethernet_plug):
		remove_collision_exception_with(_ethernet_plug)
	_ethernet_plug = null


## Let go of a lead in the adapter's socket before going, or it is left pointing
## at a freed snap zone -- ILinkHub.drop_and_free.
func drop_and_free() -> void:
	if _ethernet_port != null and _ethernet_port.picked_up_object != null:
		_ethernet_port.drop_object()
	# The console's link port, and any lead in it, go back where they came from.
	_release_link_port()
	super.drop_and_free()


# ── the console's link port, carried through ──────────────────────────────────

## How far this unit's plug may land from the console's LinkPort and still be in
## it. The port's origin is 1 mm proud of its rim and the e-Reader's plug lands
## within 1.6 mm of the GBA's socket's middle; an SP's port is 96 mm away.
const _LINK_PLUG_REACH := 0.005

## Holds the console's LinkPort in this unit's socket while it is in it.
var _link_relay: RemoteTransform3D = null
## The console's LinkPort while it is in this unit's socket, and where it was.
var _link_port: LinkPort = null
var _link_port_home := Transform3D.IDENTITY
## The port's placeholder jack, hidden while a shell's molded mouth is round it.
var _link_jack: Node3D = null
## The lead's plug in it, so a release can undo the exemption its seating made.
var _link_plug: PhysicsBody3D = null


## A unit whose row has a `link_socket` (the e-Reader USA and +) takes its
## console's link port up into that socket whenever it is seated.
func _build_link_relay() -> void:
	if ExpansionCatalog.link_socket_of(expansion_id) == null:
		return
	host_changed.connect(_on_link_host_changed)


func _on_link_host_changed(sys: RetroSystem) -> void:
	_release_link_port()
	if sys != null:
		_take_link_port(sys)


## The real reader's plug fills the console's EXT socket and its own socket on
## top is wired straight through, so the console's port MOVES here rather than a
## second one appearing: the lead still belongs to the console's port, the link
## bus walks from it to the same machine, and a save still names it LinkPort. A
## lead already in it rides along, as it stays connected on the hardware.
##
## Only where this unit's plug lands in that port. On an SP the reader seats in
## the slot but its plug meets the shell, and the SP's port stays where it is.
func _take_link_port(sys: RetroSystem) -> void:
	var socket: Variant = ExpansionCatalog.link_socket_of(_shell_id())
	var plug: Variant = ExpansionCatalog.link_plug_of(_shell_id())
	var zone := _holding_zone() as XRToolsSnapZone
	var model := sys.get_model()
	if not socket is Transform3D or not plug is Vector3 or zone == null or model == null:
		return
	var port := model.get_node_or_null("LinkPort") as LinkPort
	if port == null:
		return
	# The pose the seat gives this unit, not where it is now: a restore seats it in
	# the same call, before the grab driver has moved it anywhere.
	var seated := zone.snap_pose_for(self)
	if (seated * (plug as Vector3)).distance_to(port.global_position) > _LINK_PLUG_REACH:
		return
	_link_port = port
	_link_port_home = port.transform
	# The shell molds the socket's mouth, which the placeholder jack would sit in.
	var jack := port.get_node_or_null("LinkJack") as Node3D
	if _shell != null and jack != null and jack.visible:
		jack.visible = false
		_link_jack = jack
	_link_relay = RemoteTransform3D.new()
	_link_relay.name = "LinkSocket"
	_link_relay.update_scale = false
	add_child(_link_relay)
	_link_relay.transform = socket
	_link_relay.remote_path = _link_relay.get_path_to(port)
	port.has_picked_up.connect(_on_link_plug_in)
	port.has_dropped.connect(_on_link_plug_out)
	_on_link_plug_in(port.picked_up_object)


## Hand the console's port back to the console, where it was.
func _release_link_port() -> void:
	if _link_relay != null:
		_link_relay.remote_path = NodePath()
		_link_relay.queue_free()
		_link_relay = null
	_on_link_plug_out()
	if is_instance_valid(_link_port):
		_link_port.has_picked_up.disconnect(_on_link_plug_in)
		_link_port.has_dropped.disconnect(_on_link_plug_out)
		_link_port.transform = _link_port_home
	if is_instance_valid(_link_jack):
		_link_jack.visible = true
	_link_port = null
	_link_jack = null


## A seated plug's body goes 6 mm into this unit's box -- the Ethernet socket's
## reason for the exemption.
func _on_link_plug_in(what: Node) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	_on_link_plug_out()
	add_collision_exception_with(body)
	_link_plug = body


func _on_link_plug_out() -> void:
	if is_instance_valid(_link_plug):
		remove_collision_exception_with(_link_plug)
	_link_plug = null


## The console's LinkPort while it is carried up into this unit's socket, or null.
func get_link_port() -> LinkPort:
	return _link_port if is_instance_valid(_link_port) else null


## The accessory clipped to this unit, or null.
func get_accessory() -> Node3D:
	if _accessory_mount == null:
		return null
	var a := _accessory_mount.picked_up_object as Node3D
	return a if is_instance_valid(a) else null


## Clip `accessory` on after a save restore, bypassing the reach.
func restore_accessory(accessory: Node3D) -> void:
	if _accessory_mount != null and accessory != null:
		_accessory_mount.pick_up_object(accessory)


## The accessory rides inside this unit's box (the box runs down to the plug's
## tip, past the spacer's floor), and once the unit is seated the spacer's floor
## rests on the console's roof -- so it is exempt from both, or each pair fights
## at the faces they share. The console's exemption follows the unit's own: made
## in _bind_host, dropped in _unbind_host.
func _on_accessory_in(what: Node3D) -> void:
	_accessory = what as PhysicsBody3D
	if _accessory == null:
		return
	add_collision_exception_with(_accessory)
	if get_host() != null:
		get_host().add_collision_exception_with(_accessory)
	SeatedCollision.lend(self, _accessory, _accessory_mount)


func _on_accessory_out() -> void:
	SeatedCollision.withdraw_zone(self, _accessory_mount)
	if is_instance_valid(_accessory):
		remove_collision_exception_with(_accessory)
		if get_host() != null:
			get_host().remove_collision_exception_with(_accessory)
	_accessory = null


func _except_accessory_from(sys: RetroSystem, on: bool) -> void:
	if not is_instance_valid(_accessory):
		return
	if on:
		sys.add_collision_exception_with(_accessory)
	else:
		sys.remove_collision_exception_with(_accessory)


## The EJECT/OPEN button, placed against this unit's own box and wired to
## whichever bay this unit built.
func _build_eject_button(s: Vector3, media: String) -> void:
	var drawer := _disc_bay != null
	var mount := ExpansionCatalog.mount_of(expansion_id)
	var pos := Vector3(
		ExpansionShell.eject_x(s, mount, drawer, media),
		ExpansionShell.eject_y(s, mount, drawer),
		s.z * 0.5 + 0.004)
	var cap := _shell_node("EjectButton") as MeshInstance3D
	# A cap pushed some other way than into the front face (the Game Boy Player's
	# lever, in its right side): its hit box goes on the side face it is in.
	var axis: Variant = ExpansionCatalog.eject_axis_of(expansion_id)
	var side := 0.0
	if cap != null:
		# The hit box stays at the face plane, proud of the unit's own pointer
		# box, even though the modelled cap is recessed behind it; a box inside
		# that volume is never the first thing a beam reaches.
		var centre := to_local(cap.global_transform * cap.get_aabb().get_center())
		pos = Vector3(centre.x, centre.y, pos.z)
		if axis is Vector3 and absf(centre.x) / (s.x * 0.5) > absf(centre.z) / (s.z * 0.5):
			side = signf(centre.x)
			pos = Vector3(side * (s.x * 0.5 + 0.004), centre.y, centre.z)
	var eject := ExpansionShell.build_eject_button(self, pos, func() -> void:
		if _tray != null:
			_tray.toggle_open()
		elif _slot != null:
			_slot.toggle_eject(),
		"OPEN" if _tray != null else "EJECT")
	# The shell's own button is the cap; the built one and its legend go.
	if cap != null:
		if side != 0.0:
			eject.rotation = Vector3(0.0, side * PI * 0.5, 0.0)
		eject.set_button_mesh(cap)
		eject.set_depress_axis_world(
			(global_transform.basis * (axis as Vector3)).normalized() if axis is Vector3 else -global_transform.basis.z)
		var travel := ExpansionCatalog.eject_travel_of(expansion_id)
		eject.depress_depth = _SHELL_EJECT_TRAVEL if is_nan(travel) else travel
		for child in eject.get_children():
			if child is Label3D:
				child.visible = false
