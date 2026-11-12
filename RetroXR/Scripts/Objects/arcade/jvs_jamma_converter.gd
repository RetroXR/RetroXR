## JvsJammaConverter — Sega's I/O BD JVS TO JAMMA (838-13683): what puts a NAOMI in a JAMMA cabinet.
##
## The cabinet's JAMMA harness goes on its edge (a JAMMA Cable between its `ConvJammaEdge` and the cabinet's
## `JammaPort`); the NAOMI's JVS socket is cabled to its USB-B (`ConvJvsIn`) and the NAOMI's VGA to its D-sub
## (`ConvVgaIn`). With those, the cabinet's panel and coins reach the NAOMI and its monitor shows the NAOMI's
## picture (NaomiHookup). A loose object: it lies on the cabinet's board base beside the NAOMI.
##
## The look is a stand-in drawn here (a green board on four spacers, its sockets as blocks); a mod's model of the
## real board replaces it (ModApi.override_arcade_bay_shell("jvs_jamma_converter", ...)), and moves the sockets
## onto its JammaEdgeAnchor, JvsInAnchor and VgaInAnchor. Frame: +Y up, the JAMMA edge toward +Z, the USB and the
## D-sub along the back (-Z) edge; origin on the floor at the board's middle.
class_name JvsJammaConverter
extends XRToolsPickable

const KIND := "jvs_jamma_converter"
## The board (838-13683-93): 163.5 x 71.5, the edge's tongue 7.8 more, on spacers 11 tall; the D-sub stands 19 up.
const SIZE := Vector3(0.1635, 0.031, 0.0793)
const BOARD_Y := 0.011

## The ScenePersistence PLAIN_SCENES key it is saved and spawned under.
@export var type_id: String = KIND


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(NaomiHookup.CONV_GROUP)
	_build_stand_in()
	ArcadeBayShells.dress(self, KIND, SIZE)
	_build_ports()


func _box(box_name: String, size: Vector3, at: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.5
	mi.material_override = mat
	add_child(mi)
	mi.position = at
	return mi


func _marker(marker_name: String, at: Vector3) -> void:
	if has_node(marker_name):
		return
	var m := Marker3D.new()
	m.name = marker_name
	add_child(m)
	m.position = at


## The stand-in: the board, its tongue toward +Z, four spacers, the sockets; the markers the sockets go on.
func _build_stand_in() -> void:
	var green := Color(0.13, 0.41, 0.24)
	var body_d := 0.0715
	var zc := -(SIZE.z - body_d) * 0.5          # the body's middle, the tongue's 7.8 in front of it
	_box("Pcb", Vector3(0.1635, 0.0016, body_d), Vector3(0, BOARD_Y + 0.0008, zc), green)
	_box("Tongue", Vector3(0.1148, 0.0016, 0.0078), Vector3(-0.0137, BOARD_Y + 0.0008, zc + body_d * 0.5 + 0.0039), green)
	_box("Contacts", Vector3(0.108, 0.0018, 0.007), Vector3(-0.0137, BOARD_Y + 0.0008, zc + body_d * 0.5 + 0.0042), Color(0.7, 0.7, 0.72), 0.8)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("Spacer", Vector3(0.006, BOARD_Y, 0.006), Vector3(sx * 0.0787, BOARD_Y * 0.5, zc + sz * 0.0328), Color(0.05, 0.05, 0.06))
	var top := BOARD_Y + 0.0016
	var back := zc - body_d * 0.5
	_box("UsbB", Vector3(0.012, 0.011, 0.016), Vector3(0.0233, top + 0.0055, back + 0.0062), Color(0.78, 0.78, 0.8), 0.8)
	_box("VgaBody", Vector3(0.033, 0.0125, 0.014), Vector3(0.0675, top + 0.0063, back + 0.0174), Color(0.78, 0.78, 0.8), 0.8)
	_box("Mcu", Vector3(0.060, 0.0045, 0.0213), Vector3(-0.0218, top + 0.0023, back + 0.0324), Color(0.05, 0.05, 0.06))
	_marker("JammaEdgeAnchor", Vector3(-0.0137, BOARD_Y + 0.0008, zc + body_d * 0.5 + 0.0078))
	_marker("JvsInAnchor", Vector3(0.0233, top + 0.0055, back - 0.003))
	_marker("VgaInAnchor", Vector3(0.0675, top + 0.0125 + 0.006, back + 0.0174))


## The sockets on the markers: the JAMMA edge (the harness's plug goes on along -Z), the USB-B (in along +Z, from
## behind), the D-sub (down, from above).
func _build_ports() -> void:
	var rows := [["JammaEdgeAnchor", NaomiHookup.CONV_EDGE, "res://Scripts/Objects/cables/jamma_port.gd", "jamma_plug", RcaPort.Direction.IN, -1, Basis.IDENTITY],
		["JvsInAnchor", NaomiHookup.CONV_JVS, "res://Scripts/Objects/cables/port.gd", NaomiHookup.USB_B, -1, -1, Basis(Vector3.UP, PI)],
		["VgaInAnchor", NaomiHookup.CONV_VGA, "res://Scripts/Objects/cables/vga_port.gd", "vga_plug", RcaPort.Direction.IN, RcaPort.Channel.VIDEO,
			Basis(Vector3.RIGHT, -PI * 0.5)]]
	for r: Array in rows:
		var at := find_child(str(r[0]), true, false) as Node3D
		if at == null or at.has_node(str(r[1])):
			continue
		var port := NaomiHookup.make_port(str(r[1]), str(r[2]), str(r[3]), int(r[4]), int(r[5]))
		if port is RcaPort:
			port.set("show_jack", false)
		at.add_child(port)
		port.basis = r[6] as Basis


## A device for the A/V graph (ports under it resolve to it); nothing to route.
func on_av_topology_changed(_links: Array = []) -> void:
	pass
