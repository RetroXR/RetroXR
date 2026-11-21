## ToyBase — a toys-to-life base on its USB lead, as a primitive: the Skylanders
## Portal of Power, the Disney Infinity Base or the Lego Dimensions Toy Pad. Its
## plug goes in one of the Wii U's USB sockets, and a figure (ToyFigure) of its
## own line set on one of its spots is put on the core's base (Cemu's emulated
## nsyshid devices, through the accessory interface: one reader per position).
##
##   Portal of Power   one round top, up to 16 figures at once
##   Infinity Base     the hexagon in the middle (a Play Set or Power Disc, and two
##                     more discs), player one's round pad on the left, player
##                     two's on the right (a figure, and two ability discs, each)
##   Toy Pad           three pads: the round centre one (one figure), the square
##                     left and right ones (three each)
##
## The core attaches a base when the title starts, so plugging one in reaches
## the game at its next start: RetroSystem pins cemu_emulate_* to the bases its
## sockets hold (ForcedCoreOptions.toy_bases). Its ring lights while the core has
## its spots. Local only: inert in a netplay session.
##
## Frame: +Y up, the origin under the middle of the base, the lead leaving the
## back (-Z).
class_name ToyBase
extends XRToolsPickable

const GROUP := &"toy_base"
const CABLE_SCENE := preload("res://Scenes/Objects/peripherals/toy_base_cable.tscn")

const PORTAL := "skylanders_portal"
const INFINITY := "infinity_base"
const TOY_PAD := "dimensions_toypad"

## Each base: its figures' shelf, its body, and its spots. A spot is a pad on
## the top: where it is, its reach across, and which of the base's readers (in
## the core's order for its kind) its figures go on, in the order they arrive.
const BASES := {
	PORTAL: {
		"label": "Portal of Power", "shelf": FigureShelves.SKYLANDERS,
		"body": "round", "size": Vector3(0.205, 0.045, 0.205), "color": Color(0.18, 0.2, 0.24),
		"spots": [{"at": Vector2(0, 0), "reach": 0.085, "readers": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]}],
	},
	INFINITY: {
		"label": "Infinity Base", "shelf": FigureShelves.INFINITY,
		"body": "box", "size": Vector3(0.25, 0.028, 0.1), "color": Color(0.9, 0.91, 0.93),
		"spots": [
			{"at": Vector2(-0.085, 0), "reach": 0.03, "readers": [3, 4, 5], "shape": "round", "label": "1"},
			{"at": Vector2(0, 0), "reach": 0.035, "readers": [0, 1, 2], "shape": "hex"},
			{"at": Vector2(0.085, 0), "reach": 0.03, "readers": [6, 7, 8], "shape": "round", "label": "2"},
		],
	},
	TOY_PAD: {
		"label": "Toy Pad", "shelf": FigureShelves.DIMENSIONS,
		"body": "box", "size": Vector3(0.27, 0.022, 0.16), "color": Color(0.32, 0.33, 0.35),
		"spots": [
			{"at": Vector2(-0.085, 0.01), "reach": 0.045, "readers": [0, 3, 4], "shape": "square"},
			{"at": Vector2(0, -0.01), "reach": 0.035, "readers": [1], "shape": "round"},
			{"at": Vector2(0.085, 0.01), "reach": 0.045, "readers": [2, 5, 6], "shape": "square"},
		],
	},
}

## How far over a pad a figure's tag may be and still be read.
const REACH_UP := 0.025
const RING_OFF := Color(0.1, 0.1, 0.12)
const RING_ON := Color(0.25, 0.65, 1.0)

@export var type_id: String = PORTAL
@export var base_kind: String = PORTAL
## What its lead's plug fits, which the plug copies (ControllerPlug.set_controller):
## a Wii U USB socket (SystemPorts.accepts_usb_plug).
var connector := Connectors.USB_A

var _cable: Node3D = null
var _plug: ControllerPlug = null
var _rope: VerletRope = null
var _attach: Marker3D = null
var _ring_mat: StandardMaterial3D = null
var _pads: Array[Area3D] = []

## The Wii U its plug is in, or null; the core node whose readers it has.
var host: Node = null
var _lib: Node = null
## The core's readers for this base's kind, in its order: absolute indices.
var _readers: Array[int] = []
## Per spot: figure -> the slot (an index into its "readers") it is on.
var _on: Array[Dictionary] = []
## Absolute readers the core has been handed a figure on, this publish.
var _sent: Dictionary = {}
var _poll := 0


func _init() -> void:
	add_to_group(GROUP)


func spec() -> Dictionary:
	return BASES.get(base_kind, BASES[PORTAL])


func shelf() -> String:
	return str(spec()["shelf"])


func label() -> String:
	return str(spec()["label"])


func _ready() -> void:
	_build()
	super._ready()
	add_to_group("spawned")
	_cable = CABLE_SCENE.instantiate()
	_add_cable.call_deferred()


# ── Body ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	var s: Dictionary = spec()
	var size: Vector3 = s["size"]
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var aim := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	var body_mat := _mat(s["color"], 0.45)
	var shape: Shape3D
	if str(s["body"]) == "round":
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		shape = cyl
		var mesh := CylinderMesh.new()
		mesh.top_radius = size.x * 0.46
		mesh.bottom_radius = size.x * 0.5
		mesh.height = size.y
		_mesh("Body", mesh, Vector3(0, size.y * 0.5, 0), body_mat)
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape = box
		var mesh := BoxMesh.new()
		mesh.size = size
		_mesh("Body", mesh, Vector3(0, size.y * 0.5, 0), body_mat)
	if col != null:
		col.shape = shape
		col.position = Vector3(0, size.y * 0.5, 0)
	if aim != null:
		var aimed := BoxShape3D.new()
		aimed.size = size + Vector3(0.006, 0.006, 0.006)
		aim.shape = aimed
		aim.position = Vector3(0, size.y * 0.5, 0)
	_ring_mat = _mat(RING_OFF, 0.2)
	_ring_mat.emission = RING_ON
	_ring_mat.emission_energy_multiplier = 1.4
	var spots: Array = s["spots"]
	for i in spots.size():
		var spot: Dictionary = spots[i]
		var at: Vector2 = spot["at"]
		var reach := float(spot["reach"])
		var top := Vector3(at.x, size.y, at.y)
		var pad_mesh: Mesh
		match str(spot.get("shape", "round")):
			"square":
				var b := BoxMesh.new()
				b.size = Vector3(reach * 1.8, 0.003, reach * 1.8)
				pad_mesh = b
			"hex":
				var h := CylinderMesh.new()
				h.radial_segments = 6
				h.top_radius = reach
				h.bottom_radius = reach
				h.height = 0.004
				pad_mesh = h
			_:
				var c := CylinderMesh.new()
				c.top_radius = reach * 0.96
				c.bottom_radius = reach
				c.height = 0.003
				pad_mesh = c
		_mesh("Pad%d" % (i + 1), pad_mesh, top + Vector3(0, 0.0015, 0), _ring_mat)
		if spot.has("label"):
			var mark := Label3D.new()
			mark.name = "PadLabel%d" % (i + 1)
			mark.text = str(spot["label"])
			mark.font_size = 64
			mark.pixel_size = 0.0002
			mark.outline_size = 0
			mark.modulate = Color(0.35, 0.36, 0.4)
			mark.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(at.x, size.y + 0.0002, at.y + reach + 0.008))
			add_child(mark)
		var zone := Area3D.new()
		zone.name = "Spot%d" % (i + 1)
		zone.monitorable = false
		zone.collision_layer = 0
		# Media rests on layer 3 and XRToolsPickable moves it to DEFAULT_LAYER
		# while held, so a spot watches both, as a snap zone does.
		zone.collision_mask = 0b0000_0000_0000_0001_0000_0000_0000_0100
		var zshape := CollisionShape3D.new()
		var zbox := BoxShape3D.new()
		zbox.size = Vector3(reach * 2.0, REACH_UP * 2.0, reach * 2.0)
		zshape.shape = zbox
		zone.add_child(zshape)
		zone.position = top
		add_child(zone)
		_pads.append(zone)
		_on.append({})
	_attach = Marker3D.new()
	_attach.name = "CableAttachPoint"
	# The lead leaves the back, along -Z.
	_attach.position = Vector3(0, size.y * 0.4, -size.z * 0.5)
	add_child(_attach)


func _mesh(node_name: String, mesh: Mesh, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	add_child(mi)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


# ── The lead ─────────────────────────────────────────────────────────────────

func _add_cable() -> void:
	if not is_inside_tree():
		return
	get_tree().current_scene.add_child(_cable)
	_cable.add_to_group("spawned")
	_plug = _cable.get_node("ControllerPlug") as ControllerPlug
	_rope = _cable.get_node("VerletRope") as VerletRope
	_plug.set_controller(self)
	_plug.add_collision_exception_with(self)
	_plug.global_position = _attach.global_position - _attach.global_transform.basis.z * 0.1
	_rope.start_node = _attach
	_rope.end_node = _plug
	_rope._init_points()


func get_plug() -> ControllerPlug:
	return _plug


## The lead, parented to the scene root, so the storage box frees it with the base.
func cable_instance() -> Node3D:
	return _cable


func _exit_tree() -> void:
	if is_instance_valid(_cable):
		_cable.queue_free()
	super._exit_tree()


## The USB socket its plug is in (a snap zone on a RetroSystem), or null.
func _socket() -> XRToolsSnapZone:
	if not is_instance_valid(_plug):
		return null
	return _plug.get_picked_up_by() as XRToolsSnapZone


## The socket's name on its console ("UsbPort2"), or "" when it is not in one.
func socket_name() -> String:
	var z := _socket()
	return str(z.name) if z != null else ""


## Put the plug back in `system`'s socket after a save restore; retried, as the
## sensor bar's is, since the lead is built a frame after the base exists.
func restore_connection(system: Node, socket: String, tries_left: int = 8) -> void:
	if not is_instance_valid(system) or socket.is_empty() or not is_instance_valid(self):
		return
	var zone := system.get_node_or_null(socket) as XRToolsSnapZone
	if zone != null and is_instance_valid(_plug):
		zone.pick_up_object(_plug)
		return
	if tries_left > 0:
		restore_connection.call_deferred(system, socket, tries_left - 1)
	else:
		push_warning("[ToyBase] %s: socket %s or the lead never appeared; left unplugged" % [label(), socket])


# ── The core ─────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_poll -= 1
	if _poll <= 0:
		_poll = 10
		_follow_host()
	if _readers.is_empty():
		return
	for i in _pads.size():
		_update_spot(i)


## Which Wii U the plug is in, and that console's running core.
func _follow_host() -> void:
	var z := _socket()
	var sys: Node = z.get_parent() if z != null else null
	if sys != null and str(sys.get("systemid")) != "wiiu":
		sys = null
	if sys != host:
		var was := host
		host = sys
		print("[ToyBase] %s %s" % [label(), "plugged into %s" % sys.name if sys != null else "unplugged"])
		for s: Node in [was, sys]:
			if is_instance_valid(s) and s.has_method("refresh_toy_base_option"):
				s.call("refresh_toy_base_option")
	var lib: Node = null
	if is_instance_valid(host) and bool(host.get("is_powered_on")) and not NetworkManager.is_active():
		lib = host.call("get_libretro_node")
		if not is_instance_valid(lib) or not lib.has_method("InsertAccessoryMedia"):
			lib = null
	if lib == _lib:
		return
	if is_instance_valid(_lib) and _lib.is_connected("accessory_readers_changed", _on_readers):
		_lib.disconnect("accessory_readers_changed", _on_readers)
	_lib = lib
	_set_readers([])
	if _lib != null:
		_lib.connect("accessory_readers_changed", _on_readers)
		_lib.call("RequestAccessoryReaders")


## The core's readers, published at a start and again after every insert or
## remove. A new set is a new base: every figure is handed over afresh. The same
## set again is a check: a figure the core no longer has on its spot (a reset
## emptied the base) is handed over again, and nothing else is.
func _on_readers(readers: Array) -> void:
	var mine: Array[int] = []
	var present: Dictionary = {}
	var kind := FigureShelves.kind_of(shelf())
	for r: Variant in readers:
		if r is Dictionary and int((r as Dictionary).get("kind", -1)) == kind:
			var index := int((r as Dictionary)["index"])
			mine.append(index)
			if bool((r as Dictionary).get("present", false)):
				present[index] = true
	if mine != _readers:
		_set_readers(mine)
		return
	var spots: Array = spec()["spots"]
	for i in _on.size():
		var slots: Array = spots[i]["readers"]
		for fig: Variant in (_on[i] as Dictionary).keys():
			var reader := _readers[int(slots[int(_on[i][fig])])]
			if _sent.has(reader) and not present.has(reader):
				_sent.erase(reader)
				(_on[i] as Dictionary).erase(fig)


## A new set of readers (a start, another base switched on): every figure on the
## base is handed over afresh, since the core's base starts empty.
func _set_readers(readers: Array[int]) -> void:
	_readers = readers
	_sent.clear()
	for d: Dictionary in _on:
		d.clear()
	if _ring_mat != null:
		_ring_mat.emission_enabled = not readers.is_empty()
		_ring_mat.albedo_color = RING_ON.darkened(0.35) if not readers.is_empty() else RING_OFF
	print("[ToyBase] %s: %s" % [label(), "%d spot(s) live" % readers.size() if not readers.is_empty()
		else "no spots (the core has no %s: plug it in before the game starts)" % label()])


func is_live() -> bool:
	return not _readers.is_empty()


## The figures of this base's line whose tag is over spot `i`.
func figures_on(i: int) -> Array[ToyFigure]:
	var out: Array[ToyFigure] = []
	var zone := _pads[i]
	var inv := zone.global_transform.affine_inverse()
	var reach := float((spec()["spots"] as Array)[i]["reach"])
	for body: Node3D in zone.get_overlapping_bodies():
		var fig := body as ToyFigure
		if fig == null or fig.systemid != shelf() or fig.rom_path.is_empty():
			continue
		var at := inv * fig.nfc_point()
		if at.y < -0.005 or at.y > REACH_UP or Vector2(at.x, at.z).length() > reach:
			continue
		out.append(fig)
	return out


func _update_spot(i: int) -> void:
	var on: Dictionary = _on[i]
	var slots: Array = (spec()["spots"] as Array)[i]["readers"]
	var here := figures_on(i)
	# Taken off: off the core's base too.
	for fig: Variant in on.keys():
		if not is_instance_valid(fig) or not (fig in here):
			_take_off(int(slots[int(on[fig])]))
			on.erase(fig)
	# Set down: on the spot's first free position.
	for fig: ToyFigure in here:
		if on.has(fig):
			continue
		var free := -1
		for n in slots.size():
			if not (n in on.values()):
				free = n
				break
		if free < 0:
			continue
		on[fig] = free
		_put_on(int(slots[free]), fig)


func _put_on(slot: int, fig: ToyFigure) -> void:
	if slot >= _readers.size() or not is_instance_valid(_lib):
		return
	var reader := _readers[slot]
	_lib.call("InsertAccessoryMedia", reader, ProjectSettings.globalize_path(fig.rom_path))
	_sent[reader] = true
	print("[ToyBase] %s on the %s (reader %d)" % [fig.label(), label(), reader])
	Haptics.pulse(fig.get_picked_up_by_controller() if fig.is_picked_up() else null, 0.25, 18, &"toy_base")


func _take_off(slot: int) -> void:
	if slot >= _readers.size() or not is_instance_valid(_lib):
		return
	var reader := _readers[slot]
	if _sent.erase(reader):
		_lib.call("RemoveAccessoryMedia", reader)
		print("[ToyBase] a figure off the %s (reader %d)" % [label(), reader])


## The kinds of base (BASES keys) plugged into `system`'s sockets.
static func kinds_on(system: Node) -> Array[String]:
	var out: Array[String] = []
	if system == null or not system.is_inside_tree():
		return out
	for b: Node in system.get_tree().get_nodes_in_group(GROUP):
		var base := b as ToyBase
		if base != null and base.host == system and base.base_kind not in out:
			out.append(base.base_kind)
	return out
