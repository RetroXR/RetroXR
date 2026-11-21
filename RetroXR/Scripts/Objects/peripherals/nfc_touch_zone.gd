## NfcTouchZone — an NFC reader's touchpoint (the Wii U GamePad's). An amiibo set
## on it, or held to it, is handed to the machine's core as its tag; taken away,
## the tag is lifted. Set it down again and it is touched again: Cemu forgets a
## touch after about 2 s, so a game that asks later is answered by a new touch.
##
## Frame: +Y out of the face it is printed on, the origin on that face at the
## mark's middle. The machine is `host` (a RetroSystem, or anything with its
## is_powered_on and get_libretro_node), set while the reader is wired to one.
class_name NfcTouchZone
extends Area3D

## How far the tag may be from the mark: off the face, and across it.
const REACH_UP := 0.02
const REACH_ACROSS := 0.03
## A touch is a short tick, like a card read.
const TICK_MAGNITUDE := 0.25
const TICK_MS := 18

## The printed mark, as the primitive draws it (11 x 7.5 mm).
const MARK := Vector2(0.011, 0.0075)

var host: Node = null
var _tag: ToyFigure = null
## The core the tag was handed to: a new one (the console turned off and on) is touched again.
var _tag_lib: Node = null
## A dump the reader turned down, not offered again until it is taken away.
var _refused: ToyFigure = null


func _init() -> void:
	name = "NfcZone"
	monitorable = false
	# Media rests on layer 3 and XRToolsPickable moves it to DEFAULT_LAYER while
	# held, so the reader watches both, as a snap zone does.
	collision_layer = 0
	collision_mask = 0b0000_0000_0000_0001_0000_0000_0000_0100
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(REACH_ACROSS * 2.0, REACH_UP * 2.0, REACH_ACROSS * 2.0)
	shape.shape = box
	add_child(shape)
	var mark := MeshInstance3D.new()
	mark.name = "Mark"
	var quad := QuadMesh.new()
	quad.size = MARK
	mark.mesh = quad
	mark.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.0003, 0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.76)
	mat.roughness = 0.3
	mark.material_override = mat
	add_child(mark)


## The core's reader, or null when there is none to touch.
func _reader() -> Node:
	if host == null or not is_instance_valid(host) or not bool(host.get("is_powered_on")):
		return null
	var lib: Node = host.call("get_libretro_node")
	return lib if is_instance_valid(lib) and lib.has_method("SetNfcTag") else null


func _physics_process(_delta: float) -> void:
	if _tag != null and _reader() != _tag_lib:
		_tag = null
	var best := _nearest()
	if best != _refused:
		_refused = null
	if best == _tag or (best != null and best == _refused):
		return
	_lift()
	if best != null:
		_touch(best)


## The amiibo whose tag is on the mark, the nearest of them.
func _nearest() -> ToyFigure:
	if host == null:
		return null
	var best: ToyFigure = null
	var best_d := INF
	var inv := global_transform.affine_inverse()
	for body: Node3D in get_overlapping_bodies():
		# An amiibo: a Skylander or a toy tag is its own base's.
		var fig := body as ToyFigure
		if fig == null or fig.systemid != FigureShelves.AMIIBO:
			continue
		var at := inv * fig.nfc_point()
		var across := Vector2(at.x, at.z).length()
		if at.y < -0.005 or at.y > REACH_UP or across > REACH_ACROSS:
			continue
		var d := across + at.y
		if d < best_d:
			best_d = d
			best = fig
	return best


func _touch(fig: ToyFigure) -> void:
	var lib := _reader()
	# Local only for now: a tag is not sent to the other machines of a netplay session.
	if lib == null or fig.rom_path.is_empty() or NetworkManager.is_active():
		return
	var path := ProjectSettings.globalize_path(fig.rom_path)
	if not bool(lib.call("SetNfcTag", path)):
		push_warning("[NFC] the reader refused %s" % path)
		_refused = fig
		return
	_tag = fig
	_tag_lib = lib
	print("[NFC] touched %s" % fig.label())
	Haptics.pulse(fig.get_picked_up_by_controller() if fig.is_picked_up() else null,
		TICK_MAGNITUDE, TICK_MS, &"nfc")


func _lift() -> void:
	if _tag == null:
		return
	_tag = null
	var lib := _reader()
	if lib != null and lib == _tag_lib:
		lib.call("ClearNfcTag")
	print("[NFC] lifted")


## Wired to a machine, or (null) unwired: a tag on the mark is lifted either way.
func set_host(system: Node) -> void:
	if system == host:
		return
	_lift()
	host = system


func is_touching() -> bool:
	return _tag != null
