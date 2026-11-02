## NesFourScore — Nintendo's NES Four Score (NES-034, 1990; a Hori board inside), a
## primitive stand-in. What is the hardware's and was looked up (NESdev "Four
## Score", Wikipedia, photographs; docs/dev/four-player-adapters.md):
##
##   * A light grey wedge, thicker at the back, its top sloping toward the player.
##   * Four NES controller sockets in one row across that top, numbered 1 2 3 4 left
##     to right in red above each.
##   * ONE black cord from the rear edge, right of centre, ending in ONE moulded
##     block that carries two NES plugs side by side at the console's own port
##     pitch -- not two cords. So the block fills both of an NES's ports at once,
##     its left plug in port 1 (ControllerPlug.socket_span = 2): the left plug
##     carries players 1 and 3, the right one players 2 and 4.
##   * The 2/4 switch at the left end of the top: a slide in a front-to-back slot,
##     "2" at the rear end and "4" at the front.
##   * Two TURBO push buttons at the right end, B then A, oval caps that LATCH: the
##     board under them has two square six-pin self-locking push switches. Each is
##     for every pad in both modes, masking its button to 0 on a fixed clock of
##     about two frames each way.
##   * The sockets stand portrait (an NES plug is 16 mm by 25), in black bezels, in
##     a band of controls set toward the back of the top.
##
## What is NOT known, and is a choice here: every size (no measurement was
## found; the body is a guess from photographs at about eight socket pitches
## wide) and the cord's length.
##
## On the wire (NESdev): at 4 each of the two console lines carries two pads --
## $4016 players 1 then 3, $4017 players 2 then 4 -- then a signature byte; at 2
## the unit is two extension cords and sockets 3 and 4 are dead. To the cores that
## is libretro ports 0-3: fceumm turns its Four Score on when port 2 or 3 is its
## "Gamepad" and off when both are nothing, Mesen when either is not None, and
## Nestopia reads its third and fourth "Gamepad" through whichever adapter its
## nestopia_select_adapter option (auto, from its database, unless the player set
## it) puts in.
class_name NesFourScore
extends FourPlayerAdapter


## Sizes, in metres. ESTIMATES (see the class note).
const WIDTH := 0.205
const DEPTH := 0.105
const BACK_HEIGHT := 0.045
const FRONT_HEIGHT := 0.022
## Socket centre to centre across the top: the bezels nearly touch in the
## photographs.
const SOCKET_PITCH := 0.0225
## The band of controls across the top, in the top's frame: its middle (toward the
## back of the slope; the photographs' front strip carries only the name) and its
## depth.
const CONTROL_Z := -0.006
const CONTROL_DEPTH := 0.042
## The 2/4 slide's place on the left end.
const MODE_X := -WIDTH * 0.5 + 0.018
## How far a latched TURBO cap sits below one that is up.
const TURBO_LATCH_DEPTH := 0.0025
## The block's two plugs, centre to centre: the NES's own port pitch, which is
## what makes them a pair that can only go in one way. nes_model.gd _PORT_X
## (64.5 and 82.4 mm), checked against the console by system_tests.
const PLUG_PITCH := 0.0179

const _NES_PLUG := "res://imported-assets/controllers/nes/nes_controller_plug.res"

const GREY := Color(0.73, 0.73, 0.71)
const PRINT_RED := Color(0.72, 0.09, 0.09)
const BLACK := Color(0.06, 0.06, 0.06)
const PANEL_GREY := Color(0.66, 0.66, 0.64)
const CAP_GREY := Color(0.78, 0.78, 0.76)

## The TURBO buttons, latched down = on.
@export var turbo_a: bool = false
@export var turbo_b: bool = false
## Frames the TURBO mask holds each way (NESdev: "approximately 2 frames").
const TURBO_HALF_PERIOD := 2

var _turbo_a_button: VRButton = null
var _turbo_b_button: VRButton = null
var _top: Node3D = null


func _init() -> void:
	connector = Connectors.controller_port_of("nes")


func save_type() -> String:
	return "nes_four_score"


func _tag() -> String:
	return "FourScore"


## The slope of the top, toward the player.
static func _slope() -> float:
	return atan2(BACK_HEIGHT - FRONT_HEIGHT, DEPTH)


## The top face's frame: origin on the surface over the middle, +Y its normal, +Z
## down the slope toward the front.
static func _top_xform() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, _slope()),
		Vector3(0.0, (BACK_HEIGHT + FRONT_HEIGHT) * 0.5, 0.0))


# ── Routing ───────────────────────────────────────────────────────────────────

## The libretro port of each of the block's two plugs, -1 where it is in none.
## Read off the console: the block is told it seated once per socket it fills.
func _lead_ports() -> Array[int]:
	var out: Array[int] = [-1, -1]
	if not is_instance_valid(_system) or _cable_plug == null:
		return out
	var sockets := _system.cabinet_ports_of_plug(_cable_plug)
	for k in mini(sockets.size(), 2):
		out[k] = sockets[k]
	return out


## Sockets 1 and 3 ride the left plug's line, 2 and 4 the right one's; the second
## pad on a line is two ports on (players 3 and 4 are libretro ports 2 and 3). At
## 2 the back row is dead.
func _routes() -> Array[int]:
	var lines := _lead_ports()
	var out: Array[int] = [-1, -1, -1, -1]
	for i in range(SOCKETS):
		var line := lines[i % 2]
		var row := i / 2
		if line < 0 or (row == 1 and mode != MODE_4P):
			continue
		out[i] = line + 2 * row
	return out


func _owned_ports() -> Array[int]:
	var out: Array[int] = []
	for line: int in _lead_ports():
		if line >= 0:
			out.append(line)
			out.append(line + 2)
	return out


func _filter_ports() -> Array[int]:
	return _owned_ports()


## A line's own port is the pad in its first socket, as itself (the unit passes
## it through), or nothing. Its second port is the Four Score at 4 -- the core's
## named Gamepad whether or not a pad is in that socket, which is what makes
## fceumm read it and the game find the adapter -- and nothing at 2.
func port_device(_machine: Node, port: int) -> Dictionary:
	var lines := _lead_ports()
	for k in 2:
		var line := lines[k]
		if line < 0:
			continue
		if port == line:
			var dev := socket_device(k)
			return dev if not dev.is_empty() \
				else {"type": RETRO_DEVICE_NONE, "names": PackedStringArray()}
		if port == line + 2:
			if mode == MODE_4P:
				return {"type": RETRO_DEVICE_JOYPAD, "names": PackedStringArray(GAMEPAD_NAMES)}
			return {"type": RETRO_DEVICE_NONE, "names": PackedStringArray()}
	return {"type": RETRO_DEVICE_NONE, "names": PackedStringArray()}


func _dead_reason(i: int) -> String:
	if i >= 2 and mode != MODE_4P:
		return ": sockets 3 and 4 are off at 2"
	return ": its plug is in no port"


## TURBO: while a button is on, its bit is masked to 0 on alternate stretches of
## TURBO_HALF_PERIOD frames, for every pad the unit carries. Counted on the core's
## own frames, so the mask lines up with what the game reads.
func filter_port_input(_port: int, pad: Dictionary) -> Dictionary:
	return turbo_frame(pad, _core_frame())


## `pad` as the unit passes it on `frame`: the A and B bits of a slide that is on,
## masked to 0 on the off half of the turbo clock.
func turbo_frame(pad: Dictionary, frame: int) -> Dictionary:
	if not (turbo_a or turbo_b):
		return pad
	if (frame / TURBO_HALF_PERIOD) % 2 == 0:
		return pad
	var btn := int(pad.get("btn", 0))
	if turbo_a:
		btn &= ~(1 << ControllerBindings.JOYPAD_A)
	if turbo_b:
		btn &= ~(1 << ControllerBindings.JOYPAD_B)
	var out := pad.duplicate()
	out["btn"] = btn
	return out


## The core's own frame while one runs; the physics tick otherwise (a stopped
## core counts nothing, and the mask would then never move).
func _core_frame() -> int:
	if is_instance_valid(_system) and _system.is_powered_on:
		var lib: Node = _system.get_libretro_node()
		if is_instance_valid(lib) and lib.has_method("GetFrameCount"):
			return int(lib.call("GetFrameCount"))
	return Engine.get_physics_frames()


func set_turbo(button: String, on: bool) -> void:
	match button:
		"a":
			turbo_a = on
			if _turbo_a_button != null:
				_turbo_a_button.set_latched_pressed(on)
		"b":
			turbo_b = on
			if _turbo_b_button != null:
				_turbo_b_button.set_latched_pressed(on)
		_:
			return
	print("[FourScore] TURBO %s %s" % [button.to_upper(), "on" if on else "off"])


## A press on a TURBO button: it latches down (on) or comes back up (off).
func _press_turbo(button: String) -> void:
	set_turbo(button, not (turbo_a if button == "a" else turbo_b))


# ── Body ──────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	var grey := _material(GREY, 0.55)
	var panel := _material(PANEL_GREY, 0.6)
	var black := _material(BLACK, 0.7)
	var socket_dark := _material(Color(0.02, 0.02, 0.02), 0.9)

	var hw := WIDTH * 0.5
	var hd := DEPTH * 0.5
	# The wedge: four corners on the floor, the top two at the back higher than
	# the front two.
	var pts := PackedVector3Array([
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd),
		Vector3(-hw, BACK_HEIGHT, -hd), Vector3(hw, BACK_HEIGHT, -hd),
		Vector3(hw, FRONT_HEIGHT, hd), Vector3(-hw, FRONT_HEIGHT, hd),
	])
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.mesh = _wedge_mesh(pts)
	body.material_override = grey
	add_child(body)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.shape = shape
		col.transform = Transform3D.IDENTITY

	_top = Node3D.new()
	_top.name = "Top"
	add_child(_top)
	_top.transform = _top_xform()
	_ports_root.transform = _top_xform()

	# The band the controls sit in, and the two side panels set into it: the 2/4
	# switch's on the left, the TURBO buttons' on the right (the shell's grey on the
	# band's darker one, as the photographs' recessed panels read).
	var band_w := WIDTH - 0.012
	_add_box(_top, Vector3(band_w, 0.0004, CONTROL_DEPTH), Transform3D(Basis.IDENTITY,
		Vector3(0.0, 0.0002, CONTROL_Z)), panel, "ControlBand")
	_add_box(_top, Vector3(0.026, 0.0006, CONTROL_DEPTH - 0.004), Transform3D(Basis.IDENTITY,
		Vector3(MODE_X, 0.0003, CONTROL_Z)), grey, "ModePanel")
	_add_box(_top, Vector3(0.040, 0.0006, CONTROL_DEPTH - 0.004), Transform3D(Basis.IDENTITY,
		Vector3((_turbo_x("a") + _turbo_x("b")) * 0.5, 0.0003, CONTROL_Z)), grey, "TurboPanel")

	var flat := Basis(Vector3.RIGHT, -PI * 0.5)   # a label lying on the top, reading from the front
	for i in range(SOCKETS):
		var x := _socket_x(i)
		# A black bezel standing proud of the top, the socket's portrait mouth in it
		# (the plug stands 16 mm across and 25 front to back).
		_add_box(_top, Vector3(0.021, 0.0016, 0.030), Transform3D(Basis.IDENTITY, Vector3(x, 0.0008, CONTROL_Z)), black)
		_add_box(_top, Vector3(0.0165, 0.0012, 0.025), Transform3D(Basis.IDENTITY, Vector3(x, 0.0017, CONTROL_Z)), socket_dark)
		var lbl := _add_label(_top, str(i + 1), Transform3D(flat, Vector3(x, 0.0008, CONTROL_Z - 0.0195)), PRINT_RED, 22)
		lbl.name = "SocketLabel%d" % (i + 1)
		_labels.append(lbl)

	# The legends: "2" behind the slide's slot and "4" in front of it, B and A over
	# their buttons, TURBO under both. The slot itself is dark.
	_add_box(_top, Vector3(0.012, 0.0008, 0.026), Transform3D(Basis.IDENTITY, Vector3(MODE_X, 0.0005, CONTROL_Z)), socket_dark)
	_add_label(_top, "2", Transform3D(flat, Vector3(MODE_X, 0.0008, CONTROL_Z - 0.0175)), PRINT_RED, 18)
	_add_label(_top, "4", Transform3D(flat, Vector3(MODE_X, 0.0008, CONTROL_Z + 0.0175)), PRINT_RED, 18)
	for t: Array in [["B", _turbo_x("b")], ["A", _turbo_x("a")]]:
		_add_label(_top, str(t[0]), Transform3D(flat, Vector3(float(t[1]), 0.0008, CONTROL_Z - 0.0155)), PRINT_RED, 18)
	_add_label(_top, "TURBO", Transform3D(flat, Vector3((_turbo_x("a") + _turbo_x("b")) * 0.5, 0.0008,
		CONTROL_Z + 0.0155)), PRINT_RED, 12)

	# The cord's ribbed strain relief, on the rear edge right of centre.
	var boot := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0045
	cyl.bottom_radius = 0.006
	cyl.height = 0.012
	boot.mesh = cyl
	boot.material_override = black
	add_child(boot)
	boot.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), _cable_attach_point.position + Vector3(0, 0, 0.004))


static func _socket_x(i: int) -> float:
	return (float(i) - 1.5) * SOCKET_PITCH


static func _turbo_x(button: String) -> float:
	var right := WIDTH * 0.5 - 0.024
	return right if button == "a" else right - 0.016


## An oval cap, as the photographs' 2/4 slide and TURBO buttons are: a short
## cylinder stretched front to back. [mesh, scale].
static func _oval_cap(across: float, along: float, height: float) -> Array:
	var cyl := CylinderMesh.new()
	cyl.top_radius = across * 0.5
	cyl.bottom_radius = across * 0.5
	cyl.height = height
	cyl.radial_segments = 24
	return [cyl, Vector3(1.0, 1.0, along / across)]


## Six flat faces off the eight corners, each wound so its normal points out.
static func _wedge_mesh(p: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[0, 1, 2, 3],   # floor
		[4, 7, 6, 5],   # top
		[3, 2, 6, 7],   # front
		[1, 0, 4, 5],   # back
		[0, 3, 7, 4],   # left
		[2, 1, 5, 6],   # right
	]
	var centre := Vector3.ZERO
	for v in p:
		centre += v
	centre /= float(p.size())
	for f: Array in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var n := (b - a).cross(c - a).normalized()
		var flip := n.dot((a + c) * 0.5 - centre) < 0.0
		if flip:
			n = -n
		var tri: Array = [a, c, b, a, d, c] if not flip else [a, b, c, a, c, d]
		for v: Vector3 in tri:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


## The sockets on the sloped top, in its frame (the Ports node wears it): +Z out
## of the socket, the plug standing with its +Y toward the back -- its 25 mm side,
## which is why the mouths are portrait -- and the same roll about Z the NES's own
## front ports take (nes_model.gd) so the plug's grab point, turned half round
## about X, seats it connector-in and upright.
func _socket_transform(i: int) -> Transform3D:
	var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.BACK, PI)
	return Transform3D(b, Vector3(_socket_x(i), 0.0016, CONTROL_Z))


func _socket_fits(plug: Node3D) -> bool:
	var c := Connectors.of(plug)
	return c.is_empty() or c == connector


## The 2/4 slide: an oval cap in a front-to-back slot, "2" at the rear.
func _build_mode_switch() -> VRSlider:
	var cap: Array = _oval_cap(0.010, 0.016, 0.005)
	var s := _add_slide(_top, "ModeSwitch", Vector3(MODE_X, 0.0028, CONTROL_Z),
		Vector3(0, 0, 1), 0.008, 1.0 if mode == MODE_4P else 0.0, _material(CAP_GREY, 0.5),
		cap[0], cap[1])
	s.value_changed.connect(func(v: float) -> void: set_mode(MODE_4P if v >= 0.5 else MODE_2P))
	return s


## TURBO B and A: oval push buttons that LATCH. The board under them carries two
## square six-pin push switches (C V G on both sides), the self-locking kind: a
## press holds the switch down and turbo on, the next lets it back up. So the cap
## stays down while its turbo is on (VRButton.set_latched_pressed).
func _build_extra_controls() -> void:
	_turbo_b_button = _build_turbo_button("TurboB", _turbo_x("b"), "b")
	_turbo_a_button = _build_turbo_button("TurboA", _turbo_x("a"), "a")
	# As loaded (a save's), quietly: nothing was switched.
	_turbo_a_button.set_latched_pressed(turbo_a)
	_turbo_b_button.set_latched_pressed(turbo_b)


func _build_turbo_button(node_name: String, x: float, button: String) -> VRButton:
	var b := VRButton.new()
	b.name = node_name
	# Its own grey: state_tint would repaint the cap in the hover colours.
	b.state_tint = false
	b.depress_depth = TURBO_LATCH_DEPTH
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.013, 0.010, 0.021)
	shape.shape = box
	b.add_child(shape)
	# Named ButtonMesh and in place BEFORE the button enters the tree, so its own
	# @onready finds it (ExpansionShell.build_eject_button's note).
	var cap: Array = _oval_cap(0.0115, 0.019, 0.006)
	var mesh := MeshInstance3D.new()
	mesh.name = "ButtonMesh"
	mesh.mesh = cap[0]
	mesh.scale = cap[1]
	mesh.material_override = _material(CAP_GREY, 0.5)
	b.add_child(mesh)
	_top.add_child(b)
	b.position = Vector3(x, 0.003, CONTROL_Z)
	b.button_pressed.connect(func() -> void: _press_turbo(button))
	return b


## The block: two NES plugs at the console's pitch in one black moulding, the cord
## leaving its back between them. Seated, the plug's +X is the console's -X (the
## NES's port roll composed with the grab point), so port 2's plug is at -X.
func _dress_plug(plug: ControllerPlug) -> void:
	plug.socket_span = 2
	plug.set_plug_mesh(_NES_PLUG)
	var mesh: Mesh = null
	var exit := Transform3D.IDENTITY
	if ResourceLoader.exists(_NES_PLUG):
		var res: Resource = load(_NES_PLUG)
		mesh = PlugExit.mesh_of(res)
		exit = PlugExit.of_resource(res)
	var ab: AABB = mesh.get_aabb() if mesh != null \
		else AABB(Vector3(-0.009, -0.006, -0.03), Vector3(0.018, 0.012, 0.04))
	if mesh != null:
		var second := MeshInstance3D.new()
		second.name = "PlugModel2"
		second.mesh = mesh
		plug.add_child(second)
		second.position = Vector3(-PLUG_PITCH, 0.0, 0.0)
	# The moulding over both boots: the back third of the plug, both plugs wide.
	var boot_len := maxf(0.008, ab.size.z * 0.4)
	var block := MeshInstance3D.new()
	block.name = "PlugBlock"
	var box := BoxMesh.new()
	box.size = Vector3(ab.size.x + PLUG_PITCH + 0.002, ab.size.y + 0.002, boot_len)
	block.mesh = box
	block.material_override = _material(BLACK, 0.7)
	plug.add_child(block)
	block.position = Vector3(ab.get_center().x - PLUG_PITCH * 0.5, ab.get_center().y,
		ab.position.z + boot_len * 0.5)
	plug.cable_anchor = Vector3(exit.origin.x - PLUG_PITCH * 0.5, exit.origin.y, ab.position.z)
	plug.cable_exit_axis = Vector3.BACK
	var col := plug.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var fit := (col.shape as BoxShape3D).duplicate() as BoxShape3D
		fit.size = Vector3(fit.size.x + PLUG_PITCH, fit.size.y, fit.size.z)
		col.shape = fit
		col.position = Vector3(col.position.x - PLUG_PITCH * 0.5, col.position.y, col.position.z)
	PointerFit.watch(plug)
