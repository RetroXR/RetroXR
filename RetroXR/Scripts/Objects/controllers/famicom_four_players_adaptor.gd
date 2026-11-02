## FamicomFourPlayersAdaptor — Hori's 4 Players Adaptor for the Famicom (model
## HJ-17), a primitive stand-in. What is the hardware's and was looked up (NESdev
## "Four player adapters", MAME hori.cpp, shop photographs and the box's back;
## docs/dev/four-player-adapters.md):
##
##   * A flat light grey half-disc: a straight back edge, a curved front with a
##     notch for each socket.
##   * Four DA-15 sockets round the curve for the Famicom's expansion-port pads,
##     numbered in red: 1 on the left flank, 2 front-left, 3 front-right, 4 on the
##     right flank. 2 and 3 face forward, 1 and 4 out at a slant.
##   * One black cord from the back edge to a 15-pin plug for the Famicom's front
##     expansion port (Connectors.FAMICOM_EXPANSION, the console's accessory
##     connector), not a plug on the body.
##   * A sideways slide on top near the back, "2" on the left and "4" on the right.
##
## On the wire: at 2 sockets 1 and 2 are the "simple" Famicom expansion pads --
## players 3 and 4, read on bit 1 of $4016 and $4017 beside the console's own two
## hardwired pads -- and 3 and 4 are off. At 4 the unit speaks its own protocol on
## bit 1 (two pads a line and a signature, the Four Score's arrangement), which
## the games that know it read as four players; and sockets 1 and 2 still read as
## simple players 3 and 4, since their eight bits come first.
##
## Which of that the cores here do: fceumm ("4-Player Adapter") and Mesen ("Four
## Player Adapter") both implement the SIMPLE mode only, on their fifth port with
## players 3 and 4 on libretro ports 2 and 3. Neither has Hori's own protocol. So
## sockets 1 and 2 are players 3 and 4 in either position of the switch, and
## sockets 3 and 4 reach no player at all: there is nothing in any core to hear
## them. The switch still moves and is saved.
##
## Sizes are estimates (no measurement was found): a half-disc 170 mm across.
class_name FamicomFourPlayersAdaptor
extends FourPlayerAdapter


const RADIUS := 0.085
const HEIGHT := 0.03
## The straight back edge's z; the curve bulges toward +Z from it.
const BACK_Z := -0.035
## Each socket's place round the curve (degrees from straight ahead, +X right) and
## the way its face looks: 2 and 3 forward, 1 and 4 out at a slant.
const SOCKET_AT := [-67.5, -22.5, 22.5, 67.5]
const SOCKET_FACING := [-55.0, 0.0, 0.0, 55.0]
## Each socket's notch: how far in from the rim its flat floor is, and how wide.
const NOTCH_DEPTH := 0.007
const NOTCH_WIDTH := 0.040
## What the lead's plug names itself in a core's list for its fifth port.
const ADAPTER_NAMES: Array[String] = ["4-player adapter", "four player adapter"]

const GREY := Color(0.74, 0.74, 0.72)
const PRINT_RED := Color(0.72, 0.09, 0.09)
const BLACK := Color(0.06, 0.06, 0.06)


func _init() -> void:
	connector = Connectors.FAMICOM_EXPANSION
	device_names = PackedStringArray(ADAPTER_NAMES)


func save_type() -> String:
	return "famicom_four_players_adaptor"


func _tag() -> String:
	return "HoriAdaptor"


# ── Routing ───────────────────────────────────────────────────────────────────

## Whether the lead is in a console's accessory connector.
func _in_console() -> bool:
	return is_instance_valid(_system) and _cable_plug != null \
		and _system.cabinet_port_of_plug(_cable_plug) == RetroSystem.ACCESSORY_SLOT


## Sockets 1 and 2 are players 3 and 4 (libretro ports 2 and 3) in both positions;
## 3 and 4 reach nothing (see the class note).
func _routes() -> Array[int]:
	var out: Array[int] = [-1, -1, -1, -1]
	if _in_console():
		out[0] = 2
		out[1] = 3
	return out


func _owned_ports() -> Array[int]:
	var out: Array[int] = []
	if _in_console():
		out.append(2)
		out.append(3)
	return out


## Players 3 and 4 are the core's named Gamepad, with or without a pad in the
## socket: fceumm reads them into the expansion port only off a port announced so.
func port_device(_machine: Node, _port: int) -> Dictionary:
	return {"type": RETRO_DEVICE_JOYPAD, "names": PackedStringArray(GAMEPAD_NAMES)}


func _dead_reason(i: int) -> String:
	if i < 2:
		return ": the lead is in no console"
	if mode != MODE_4P:
		return ": sockets 3 and 4 are off at 2"
	return ": at 4 they speak Hori's own protocol, which no core here emulates"


# ── Body ──────────────────────────────────────────────────────────────────────

func _centre() -> Vector3:
	return Vector3(0.0, 0.0, BACK_Z)


## Where socket `i`'s face is (at mid height) and which way it looks, in the
## body's frame: on the flat floor of its notch, NOTCH_DEPTH in from the rim at
## SOCKET_AT[i], facing SOCKET_FACING[i].
func _socket_face(i: int) -> Array:
	var at := deg_to_rad(float(SOCKET_AT[i]))
	var facing := deg_to_rad(float(SOCKET_FACING[i]))
	var f := Vector3(sin(facing), 0.0, cos(facing))
	var rim := _centre() + Vector3(sin(at), 0.0, cos(at)) * RADIUS
	var p := rim - f * NOTCH_DEPTH
	return [Vector3(p.x, HEIGHT * 0.5, p.z), f]


## The outline (x, z): the half-disc's arc from the left end of the back edge to
## the right, stepping in at each socket to a flat NOTCH_WIDTH wide and back out
## to the arc. Star-shaped about its middle, so _extrude's fan holds; collision
## is the hull (the half-disc), which a hand cannot tell from it.
func _outline() -> PackedVector2Array:
	var c := Vector2(0.0, BACK_Z)
	var poly := PackedVector2Array()
	var current := -PI * 0.5
	for i in range(SOCKETS):
		var face: Array = _socket_face(i)
		var q3: Vector3 = face[0]
		var f3: Vector3 = face[1]
		var q := Vector2(q3.x, q3.z)
		var f := Vector2(f3.x, f3.z)
		var t := Vector2(f.y, -f.x)   # along the flat; the order is settled by angle below
		var e1 := q - t * NOTCH_WIDTH * 0.5
		var e2 := q + t * NOTCH_WIDTH * 0.5
		if _angle(e1, c) > _angle(e2, c):
			var swap := e1
			e1 = e2
			e2 = swap
		var a1 := _to_rim(e1, f, c)
		var a2 := _to_rim(e2, f, c)
		_arc(poly, c, current, _angle(a1, c))
		poly.append(a1)
		poly.append(e1)
		poly.append(e2)
		poly.append(a2)
		current = _angle(a2, c)
	_arc(poly, c, current, PI * 0.5)
	poly.append(c + Vector2(RADIUS, 0.0))
	return poly


## The arc's points strictly between angles `from` and `to` (about 4 degrees apart),
## then the end point at `to` when `to` is the back edge's.
func _arc(poly: PackedVector2Array, c: Vector2, from: float, to: float) -> void:
	if poly.is_empty():
		poly.append(c + Vector2(sin(from), cos(from)) * RADIUS)
	var steps := maxi(1, int(ceil((to - from) / deg_to_rad(4.0))))
	for k in range(1, steps):
		var a := from + (to - from) * float(k) / float(steps)
		poly.append(c + Vector2(sin(a), cos(a)) * RADIUS)


## A point's angle round the centre, 0 straight ahead (+Z), positive to +X.
static func _angle(p: Vector2, c: Vector2) -> float:
	return atan2(p.x - c.x, p.y - c.y)


## Where the line from `e` out along `f` meets the rim.
func _to_rim(e: Vector2, f: Vector2, c: Vector2) -> Vector2:
	var d := e - c
	var b := d.dot(f)
	var s := -b + sqrt(maxf(0.0, b * b - (d.length_squared() - RADIUS * RADIUS)))
	return e + f * s


func _build_body() -> void:
	var grey := _material(GREY, 0.55)
	var black := _material(BLACK, 0.7)
	var dark := _material(Color(0.02, 0.02, 0.02), 0.9)
	var metal := _material(Color(0.55, 0.55, 0.57), 0.35)
	metal.metallic = 0.6

	var outline := _outline()
	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.mesh = _extrude(outline, HEIGHT)
	body.material_override = grey
	add_child(body)
	var pts := PackedVector3Array()
	for p in outline:
		pts.append(Vector3(p.x, 0.0, p.y))
		pts.append(Vector3(p.x, HEIGHT, p.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.shape = shape
		col.transform = Transform3D.IDENTITY

	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in range(SOCKETS):
		var xf := _socket_transform(i)
		var face := Transform3D(xf.basis.orthonormalized(), xf.origin)
		# A female DA-15 on the facet: its metal shell, the D-shaped mouth dark in it.
		_add_box(_ports_root, Vector3(0.033, 0.0125, 0.0012), face.translated_local(Vector3(0, 0, 0.0006)), metal)
		_add_box(_ports_root, Vector3(0.025, 0.0075, 0.0014), face.translated_local(Vector3(0, 0, 0.0008)), dark)
		var sf: Array = _socket_face(i)
		var near: Vector3 = (sf[0] as Vector3) - (sf[1] as Vector3) * 0.013
		var lbl := _add_label(self, str(i + 1), Transform3D(flat, Vector3(near.x, HEIGHT + 0.0004, near.z)),
			PRINT_RED, 26)
		lbl.name = "SocketLabel%d" % (i + 1)
		_labels.append(lbl)

	# The 2/4 legend either end of the slide's slot.
	var sw := _switch_pos()
	_add_box(self, Vector3(0.016, 0.0006, 0.007), Transform3D(Basis.IDENTITY, sw - Vector3(0, 0.0017, 0)), dark)
	_add_label(self, "2", Transform3D(flat, sw + Vector3(-0.015, -0.0016, 0)), PRINT_RED, 22)
	_add_label(self, "4", Transform3D(flat, sw + Vector3(0.015, -0.0016, 0)), PRINT_RED, 22)
	_add_label(self, "4 PLAYERS ADAPTOR", Transform3D(flat, Vector3(0, HEIGHT + 0.0004, BACK_Z + 0.036)),
		PRINT_RED, 12)

	var boot := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0045
	cyl.bottom_radius = 0.006
	cyl.height = 0.012
	boot.mesh = cyl
	boot.material_override = black
	add_child(boot)
	boot.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), _cable_attach_point.position + Vector3(0, 0, 0.004))


func _switch_pos() -> Vector3:
	return Vector3(0.0, HEIGHT + 0.002, BACK_Z + 0.014)


## A flat outline (x, z) extruded from y 0 to `h`. Each face is wound CLOCKWISE seen
## from outside, which is Godot's front face (counter-clockwise drew the body from
## the inside, dark).
static func _extrude(outline: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	var c := Vector2.ZERO
	for p in outline:
		c += p
	c /= float(n)
	var c3 := Vector3(c.x, 0.0, c.y)
	var up := Vector3.UP
	for k in range(n):
		var a := outline[k]
		var b := outline[(k + 1) % n]
		var a3 := Vector3(a.x, 0.0, a.y)
		var b3 := Vector3(b.x, 0.0, b.y)
		_emit(st, [c3 + up * h, a3 + up * h, b3 + up * h], up)
		_emit(st, [c3, a3, b3], Vector3.DOWN)
		var out := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		if out.dot((a3 + b3) * 0.5 - c3) < 0.0:
			out = -out
		_emit(st, [a3, b3, b3 + up * h], out)
		_emit(st, [a3, b3 + up * h, a3 + up * h], out)
	return st.commit()


## One triangle facing `normal`, wound clockwise seen from that side.
static func _emit(st: SurfaceTool, tri: Array, normal: Vector3) -> void:
	var v0: Vector3 = tri[0]
	var v1: Vector3 = tri[1]
	var v2: Vector3 = tri[2]
	if (v1 - v0).cross(v2 - v0).dot(normal) > 0.0:
		var t := v1
		v1 = v2
		v2 = t
	for v: Vector3 in [v0, v1, v2]:
		st.set_normal(normal)
		st.add_vertex(v)


## A socket on its facet: +Z out of it, a plug standing upright in it, and the
## same roll about Z the console's front sockets take (the plug's grab point is
## turned half round about X).
func _socket_transform(i: int) -> Transform3D:
	var face: Array = _socket_face(i)
	var f: Vector3 = face[1]
	var facing := Basis(Vector3.UP, atan2(f.x, f.z))
	return Transform3D(facing * Basis(Vector3.BACK, PI), face[0])


func _socket_fits(plug: Node3D) -> bool:
	var c := Connectors.of(plug)
	return c.is_empty() or c == Connectors.FAMICOM_EXPANSION


func _build_mode_switch() -> VRSlider:
	var knob := _material(Color(0.2, 0.2, 0.2), 0.6)
	var s := _add_slide(self, "ModeSwitch", _switch_pos(), Vector3(1, 0, 0), 0.008,
		1.0 if mode == MODE_4P else 0.0, knob)
	s.value_changed.connect(func(v: float) -> void: set_mode(MODE_4P if v >= 0.5 else MODE_2P))
	return s


## A male DA-15 on a black moulded hood: the D-shell forward (+Z, into the
## console), the hood behind, the cord out of its back.
func _dress_plug(plug: ControllerPlug) -> void:
	for generic: String in ["PlugTip", "StrainRelief"]:
		var g := plug.get_node_or_null(generic) as Node3D
		if g != null:
			g.visible = false
	var model := Node3D.new()
	model.name = "PlugModel"
	plug.add_child(model)
	var black := _material(BLACK, 0.7)
	var metal := _material(Color(0.62, 0.62, 0.64), 0.3)
	metal.metallic = 0.8
	_add_box(model, Vector3(0.025, 0.0075, 0.006), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)), metal, "DShell")
	_add_box(model, Vector3(0.039, 0.0125, 0.001), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0005)), metal, "Flange")
	_add_box(model, Vector3(0.045, 0.016, 0.02), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.01)), black, "Hood")
	plug.cable_anchor = Vector3(0, 0, -0.02)
	plug.cable_exit_axis = Vector3.BACK
	var col := plug.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		var fit := BoxShape3D.new()
		fit.size = Vector3(0.045, 0.016, 0.027)
		col.shape = fit
		col.position = Vector3(0, 0, -0.0065)
	PointerFit.watch(plug)
