## WiiUGamePadCradle — the Wii U GamePad Cradle (WUP-014) as a primitive.
##
## A black stand the GamePad drops into on its bottom edge, screen toward you and
## leaning back, its charging terminals on the cradle's two contacts and its two
## support slots over the cradle's tabs. The GamePad AC Adapter (WUP-011) plugs into
## its back (`PowerInlet`, a DcPort taking `wiiu_gamepad_dc_plug`), and a GamePad in
## it charges while that supply is live: its orange lamp lights (no charge is
## modelled). The detailed model (RetroXR-models, another session) replaces the
## geometry; the seat, the jack and the contacts keep these names.
##
## Sizes are ESTIMATES (no published size for the cradle alone): wide enough to
## hold the GamePad's support slots (x +-37 mm) with its 255.7 mm body overhanging.
class_name WiiUGamePadCradle
extends XRToolsPickable

const DC_PORT := preload("res://Scenes/Objects/cables/barrel_dc_port.tscn")
const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## The plug the WUP-011 ends in; the GamePad's own top port takes it too.
const PLUG := "wiiu_gamepad_dc_plug"
## The group a GamePad joins so the seat takes it and nothing else.
const PAD_GROUP := &"wiiu_gamepad"
## Never renamed: a save names the socket a plug is in by it.
const INLET_NAME := "PowerInlet"

const BASE := Vector3(0.11, 0.022, 0.07)
## How far the GamePad leans back from upright, degrees.
const LEAN_DEG := 15.0
const SHELL := Color(0.07, 0.07, 0.08)

var _seat: XRToolsSnapZone = null
var _input: PowerInput = null
var _pad: Node3D = null


func _init() -> void:
	_build()


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	_input = PowerInput.on(self)
	_input.label = "Wii U GamePad Cradle (%s)" % name
	_input.noun = "cradle"
	var jack := get_node_or_null(INLET_NAME)
	if jack != null:
		_input.add_inlet(jack)
	_input.power_changed.connect(_on_power_changed)
	_seat.has_picked_up.connect(_on_pad_seated)
	_seat.has_dropped.connect(_on_pad_lifted)


## The GamePad standing in it, or null.
func seated_pad() -> Node3D:
	return _pad if is_instance_valid(_pad) else null


## Whether a supply reaches the contacts: the adapter's plug in the back, and
## power by the room's rule (its own cord in a live socket with power simulation
## on; plugged is enough with it off). An empty jack charges nothing either way.
func is_powered() -> bool:
	var jack := get_node_or_null(INLET_NAME) as Port
	return jack != null and jack.seated_plug() != null and _input != null and _input.is_live()


func _on_pad_seated(pad: Node3D) -> void:
	_pad = pad
	print("[WiiU] cradle: %s seated (%s)" % [pad.name, "charging" if is_powered() else "no supply"])
	_tell_pad()


func _on_pad_lifted() -> void:
	var was := _pad
	_pad = null
	if is_instance_valid(was) and was.has_method("set_cradle"):
		was.call("set_cradle", null)
	print("[WiiU] cradle: GamePad lifted out")


func _on_power_changed(live: bool) -> void:
	print("[WiiU] cradle: supply %s" % ("live" if live else "gone"))
	_tell_pad()


func _tell_pad() -> void:
	if is_instance_valid(_pad) and _pad.has_method("set_cradle"):
		_pad.call("set_cradle", self)


# ── Building ────────────────────────────────────────────────────────────────

func _mat(c: Color, rough := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(node_name: String, size: Vector3, xform: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.transform = xform
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	return mi


func _build() -> void:
	var shell := _mat(SHELL)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-LEAN_DEG))
	# The base, origin on the table.
	_box("Base", BASE, Transform3D(Basis.IDENTITY, Vector3(0, BASE.y * 0.5, 0)), shell)
	# The back rest the GamePad leans on, and the lip in front of its bottom edge.
	_box("BackRest", Vector3(BASE.x, 0.05, 0.008),
		Transform3D(lean, Vector3(0, BASE.y + 0.02, -0.018)), shell)
	_box("Lip", Vector3(BASE.x, 0.008, 0.004), Transform3D(Basis.IDENTITY, Vector3(0, BASE.y + 0.004, 0.014)), shell)
	# The two tabs into the GamePad's support slots, and the two contacts under its
	# charging terminals (RetroXR-models gamepad MEASUREMENTS: x +-37 and +-10 mm).
	var metal := _mat(Color(0.75, 0.72, 0.6), 0.3)
	metal.metallic = 0.9
	for x: float in [-0.037, 0.037]:
		_box("Tab", Vector3(0.009, 0.004, 0.003), Transform3D(lean, Vector3(x, BASE.y + 0.002, -0.004)), shell)
	for x: float in [-0.010, 0.010]:
		_box("Contact", Vector3(0.0026, 0.002, 0.0026), Transform3D(lean, Vector3(x, BASE.y + 0.001, -0.004)), metal)

	# The seat: where the GamePad's origin goes. Its frame is the GamePad's lying
	# flat (screen +Y, top edge -Z) stood on its bottom edge and leaned back, so its
	# screen faces +Z and up a little.
	var stand := Basis(Vector3.RIGHT, deg_to_rad(90.0 - LEAN_DEG))
	var half_depth := 0.1339 * 0.5
	var bottom_edge := Vector3(0, BASE.y, -0.004)
	var seat_at := bottom_edge + stand * Vector3(0, 0, -half_depth)
	_seat = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	_seat.name = "PadSeat"
	_seat.snap_require = String(PAD_GROUP)
	_seat.grab_distance = 0.12
	_seat.transform = Transform3D(stand, seat_at)
	add_child(_seat)

	# The AC adapter's jack in the back, its +Z out of the back face.
	var jack := DC_PORT.instantiate() as DcPort
	jack.name = INLET_NAME
	jack.connector = PLUG
	jack.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, BASE.y * 0.5, -BASE.z * 0.5))
	add_child(jack)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(BASE.x, BASE.y + 0.03, BASE.z)
	col.shape = shape
	col.position = Vector3(0, (BASE.y + 0.03) * 0.5, 0)
	add_child(col)
