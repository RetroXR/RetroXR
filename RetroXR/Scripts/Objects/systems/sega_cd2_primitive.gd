## SegaCd2Primitive -- the Sega CD / Mega-CD Model 2 (MK-4102), as a stand-in shell.
##
## Worn by the `sega_cd` unit as its `shell` (ExpansionCatalog), so RetroExpansion
## fits it to the row's `size` (1:1: these are its true bounds) and reads its parts by
## name. Built in code rather than authored because most of its faces are slopes, and a
## slope written as a .tscn basis is a row-ordered matrix that comes out inverted.
##
## Every figure is the RetroXR-models model's (sega/sega-cd/console-2 params.py, read off
## Sega's design patent USD351,385 at the published 220 mm depth, the service manual and
## photographs), in THAT model's frame: +X right, +Y up, +Z out of the front, y = 0 under
## the feet, x = 0 the middle of the plan. The markers carry the models' names, so the
## detailed model can replace this shell without a constant here moving:
##
##   LidPivot     the lid's hinge on its rear edge; MediaTray swings it 85 degrees up
##   DiscSeat     a seated disc's middle on the hub, under the lid
##   DCInPort     AC ADAPTOR (5.5 x 2.1, MK-1602), on the back; ExpansionPower reads it
##   MixingAnchor, LineOutLAnchor, LineOutRAnchor
##                MIXING (3.5 mm stereo) and LINE OUT LEFT / RIGHT, on the back
##   ExpansionAnchor
##                the receptacle's mouth on the drive's left wall, where the console's
##                expansion edge goes in along +X
##
## and the two the expansion code reads by its own names: EjectButton (the OPEN knob,
## pressed DOWN) and AccessLed (the ACCESS lamp, lit by the core's LED).
##
## Simplified, as a stand-in is: the base's corners are square (the real ones are rounded
## 8 and the front-right swept round 72), the drive's convex front is two planes (an 18
## degree fall from the top and a steep gray nose under it), the OPEN knob sits on that
## nose instead of on the swept corner, the rear jacks stand on the back face (the real
## ones are 7 mm into an inset), and the rails and hook windows are dark inlays rather
## than pockets. The receptacle, the well under the lid and the hub are there, because a
## console seats against the one and a disc lies on the others.
##
## 396 mm wide, Sega's published width (2026-11-08, the owner's choice over the patent's
## 381): the constants below are the patent's as the model's params.py reads them, and
## every x is stretched by WIDTH / W once the parts are built (_stretch), exactly as the
## model stretches its own. So the drive's wall is at x 23.39, a Genesis Model 2's
## origin at -86.61 and a Model 1's at -116.61.
class_name SegaCd2Primitive
extends Node3D

const MM := 0.001

## The plan and height (params `overall`; the dish on the lid is the highest point). W is
## the patent drawing's width every x below was read at; WIDTH is the unit's.
const W := 381.0
const WIDTH := 396.0
const SX := WIDTH / W
const D := 220.0
const H := 84.3
## The base (params `base`, `deck`): its top rim 45 up, the platform's deck 2 below the rim.
const BASE_BOTTOM := 3.0
const RIM_TOP := 45.0
const DECK_TOP := 43.0
const DECK_X := Vector2(-183.0, 14.0)
## The deck along the depth, in THIS frame (params y [-97.7, 86.8], +y back).
const DECK_Z := Vector2(-86.8, 97.7)
## The drive's housing (params `drive`): its left wall, 4 inside the base's outline.
const DRIVE_X := Vector2(22.5, 186.5)
const DRIVE_Z := Vector2(-106.0, 106.0)
const DRIVE_TOP := 82.8
## Where the flat top ends and the front begins to fall (62 back from the front), where
## the fall meets the nose, and how high the nose stands at the front edge.
const TOP_FRONT_Z := 44.0
const NOSE_TOP := Vector2(90.0, 68.0)    # (z, y)
const NOSE_FOOT := Vector2(106.0, 46.0)  # (z, y)
## The disc well under the lid (params `well`): centred at (106, z 8), 122 across, its
## floor 68 up; the hub 28 across to 72, the spindle 15 across to 74.
const WELL_C := Vector2(106.0, 8.0)      # (x, z)
const WELL_R := 61.0
const WELL_FLOOR := 68.0
const HUB := Vector2(14.0, 72.0)         # (radius, top)
const SPINDLE := Vector2(7.5, 74.0)
## The lid (params `lid`): x 38.4 to 174.5 less its 0.6 clearance, from its hinge at the
## back (z -70.9) to its front edge, 1.2 over the housing, 3.5 thick.
const LID_X := Vector2(39.0, 173.9)
const LID_BACK := -70.9
const LID_RISE := 1.2
const LID_T := 3.5
## The raised oval dish on the lid: 69 x 36 at (123.8, z 32.6), turned 50 degrees.
const DISH := Vector3(123.8, 32.6, -50.0)
const DISH_SIZE := Vector2(69.0, 36.0)
## The receptacle (params `connector`): a block on the drive's left wall, its slot 82.5
## long and 2.4 tall at 58.6 up.
const RECEPTACLE_X := Vector2(12.0, 22.8)
const RECEPTACLE_Z := Vector2(-61.5, 35.4)
const RECEPTACLE_Y := Vector2(44.0, 67.0)
const SLOT_Z := Vector2(-54.3, 28.2)
const SLOT_Y := 58.6
## The front (params `front`): the ACCESS lamp at x 62, 55 up; the OPEN knob, a 10 x 6
## lever pressed 2 down, here on the nose's right end.
const LED := Vector3(62.0, 55.0, 0.0)
const KNOB := Vector3(170.0, 57.0, 0.0)
## The back (params `rear`): all 24 up, AC ADAPTOR at x 10, MIXING -5, RIGHT -24, LEFT -36.
const JACK_Y := 24.0
const JACKS := {"DCInPort": 10.0, "MixingAnchor": -5.0, "LineOutRAnchor": -24.0, "LineOutLAnchor": -36.0}
const REAR_INSET := Vector4(-50.0, 20.0, 12.0, 34.0)  # x0, x1, y0, y1
## The platform's four rails (36 x 7, the Genesis's feet slide in them) and the four
## windows its joining plate hooks into, as (x, z) in THIS frame.
const RAILS := [Vector2(-24.6, -71.0), Vector2(-24.6, 76.0), Vector2(-154.9, -71.0), Vector2(-154.9, 76.0)]
const WINDOWS := [Vector2(-49.9, -50.7), Vector2(-53.5, 50.7), Vector2(-125.9, -47.0), Vector2(-125.9, 47.0)]
## Four rubber feet, 24 x 8, 3.3 tall.
const FEET := [Vector2(124.0, -74.0), Vector2(124.0, 74.0), Vector2(-140.0, -74.0), Vector2(-140.0, 74.0)]

## A hair proud of the face an inlay is drawn on, so the two are never coplanar.
const PROUD := 0.2

const SHELL_RGB := Color8(18, 18, 19)
const SKIRT_RGB := Color8(52, 53, 56)
const LID_RGB := Color8(16, 16, 17)
const DARK_RGB := Color8(6, 6, 7)

var _mats := {}


func _init() -> void:
	_build()


func _mat(key: String, rgb: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = rgb
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## A box from two corners in millimetres, under `parent`.
func _box(parent: Node3D, node_name: String, a: Vector3, b: Vector3, mat: Material) -> MeshInstance3D:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = (hi - lo) * MM
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = (lo + hi) * 0.5 * MM
	parent.add_child(mi)
	return mi


## A slab whose top face runs across the drive's width from `from` to `to` ((z, y) in
## mm, the top surface's line), `t` thick below it: a face of the drive's front.
func _slope(parent: Node3D, node_name: String, x: Vector2, from: Vector2, to: Vector2, t: float,
		mat: Material) -> MeshInstance3D:
	var along := Vector3(0.0, to.y - from.y, to.x - from.x)
	var length := along.length()
	var dir := along / length
	# The face's outward normal: the line turned a quarter toward +Y / +Z.
	var up := Vector3(0.0, dir.z, -dir.y)
	if up.y < 0.0:
		up = -up
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3((x.y - x.x), t, length) * MM
	mi.mesh = mesh
	mi.material_override = mat
	var mid := Vector3((x.x + x.y) * 0.5, (from.y + to.y) * 0.5, (from.x + to.x) * 0.5) - up * t * 0.5
	mi.transform = Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)), mid * MM)
	parent.add_child(mi)
	return mi


## A disc (or an ellipse, scaled) standing on `y0` with its axis up.
func _disc(parent: Node3D, node_name: String, c: Vector2, r: float, y0: float, y1: float,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = r * MM
	mesh.bottom_radius = r * MM
	mesh.height = (y1 - y0) * MM
	mesh.radial_segments = 48
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(c.x, (y0 + y1) * 0.5, c.y) * MM
	parent.add_child(mi)
	return mi


func _marker(node_name: String, at_mm: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.position = at_mm * MM
	add_child(m)
	return m


func _build() -> void:
	var shell := _mat("shell", SHELL_RGB, 0.55)
	var skirt := _mat("skirt", SKIRT_RGB, 0.45)
	var lid_mat := _mat("lid", LID_RGB, 0.3)
	var dark := _mat("dark", DARK_RGB, 0.8)
	var feet_mat := _mat("feet", Color8(34, 34, 35), 0.9)
	var hx := W * 0.5
	var hz := D * 0.5

	# The base: the deck's level all over, then the rim round the deck to 45.
	_box(self, "Base", Vector3(-hx, BASE_BOTTOM, -hz), Vector3(hx, DECK_TOP, hz), shell)
	_box(self, "RimLeft", Vector3(-hx, DECK_TOP - 1.0, -hz), Vector3(DECK_X.x, RIM_TOP, hz), shell)
	_box(self, "RimRight", Vector3(DECK_X.y, DECK_TOP - 1.0, -hz), Vector3(hx, RIM_TOP, hz), shell)
	_box(self, "RimBack", Vector3(DECK_X.x, DECK_TOP - 1.0, -hz), Vector3(DECK_X.y, RIM_TOP, DECK_Z.x), shell)
	_box(self, "RimFront", Vector3(DECK_X.x, DECK_TOP - 1.0, DECK_Z.y), Vector3(DECK_X.y, RIM_TOP, hz), shell)
	for i in RAILS.size():
		var r: Vector2 = RAILS[i]
		_box(self, "Rail%d" % (i + 1), Vector3(r.x - 18.0, DECK_TOP - 0.5, r.y - 3.5),
			Vector3(r.x + 18.0, DECK_TOP + PROUD, r.y + 3.5), dark)
	for i in WINDOWS.size():
		var w: Vector2 = WINDOWS[i]
		_box(self, "HookWindow%d" % (i + 1), Vector3(w.x - 4.5, DECK_TOP - 0.5, w.y - 9.0),
			Vector3(w.x + 4.5, DECK_TOP + PROUD, w.y + 9.0), dark)
	for i in FEET.size():
		var f: Vector2 = FEET[i]
		_box(self, "Foot%d" % (i + 1), Vector3(f.x - 12.0, 0.0, f.y - 4.0), Vector3(f.x + 12.0, BASE_BOTTOM + 0.3, f.y + 4.0), feet_mat)

	# The drive's housing: up to the well's floor all over, the frame round the lid's
	# opening above that, the front's fall either side of the lid, and the gray nose.
	_box(self, "Housing", Vector3(DRIVE_X.x, RIM_TOP, DRIVE_Z.x), Vector3(DRIVE_X.y, WELL_FLOOR, NOSE_TOP.x), shell)
	_box(self, "HousingBack", Vector3(DRIVE_X.x, WELL_FLOOR - 1.0, DRIVE_Z.x), Vector3(DRIVE_X.y, DRIVE_TOP, LID_BACK), shell)
	for side: Array in [["Left", Vector2(DRIVE_X.x, LID_X.x - 0.6)], ["Right", Vector2(LID_X.y + 0.6, DRIVE_X.y)]]:
		var x: Vector2 = side[1]
		_box(self, "Housing%s" % side[0], Vector3(x.x, WELL_FLOOR - 1.0, LID_BACK), Vector3(x.y, DRIVE_TOP, TOP_FRONT_Z), shell)
		_slope(self, "Fall%s" % side[0], x, Vector2(TOP_FRONT_Z, DRIVE_TOP), NOSE_TOP, 14.0, shell)
	_slope(self, "Nose", DRIVE_X, NOSE_TOP, NOSE_FOOT, 20.0, skirt)

	# The well under the lid, the hub and spindle a disc lies on.
	_disc(self, "Well", WELL_C, WELL_R, WELL_FLOOR - 0.5, WELL_FLOOR + PROUD, dark)
	_disc(self, "Hub", WELL_C, HUB.x, WELL_FLOOR, HUB.y, _mat("metal", Color8(150, 150, 146), 0.35, 0.7))
	_disc(self, "Spindle", WELL_C, SPINDLE.x, HUB.y - 0.5, SPINDLE.y, _mat("metal", Color8(150, 150, 146), 0.35, 0.7))

	# The lid, on its hinge: the flat panel over the top and its front following the fall.
	var pivot := Node3D.new()
	pivot.name = "LidPivot"
	pivot.position = Vector3((LID_X.x + LID_X.y) * 0.5, DRIVE_TOP, LID_BACK) * MM
	add_child(pivot)
	var at := pivot.position / MM
	var top := DRIVE_TOP + LID_RISE
	_box(pivot, "Lid", Vector3(LID_X.x, top - LID_T, LID_BACK) - at, Vector3(LID_X.y, top, TOP_FRONT_Z) - at, lid_mat)
	_slope(pivot, "LidFront", Vector2(LID_X.x, LID_X.y) - Vector2(at.x, at.x),
		Vector2(TOP_FRONT_Z, top) - Vector2(at.z, at.y), NOSE_TOP + Vector2(0.0, LID_RISE) - Vector2(at.z, at.y),
		LID_T, lid_mat)
	# The dish: an oval pad standing to the shell's full height.
	var dish := _disc(pivot, "Dish", Vector2(DISH.x - at.x, DISH.y - at.z), 1.0, top - 0.5 - at.y, H - at.y,
		_mat("dish", Color8(26, 26, 28), 0.25))
	dish.scale = Vector3(DISH_SIZE.x * 0.5, 1.0, DISH_SIZE.y * 0.5)
	dish.rotation = Vector3(0.0, deg_to_rad(DISH.z), 0.0)

	# The receptacle on the drive's left wall, its slot facing the console.
	_box(self, "Receptacle", Vector3(RECEPTACLE_X.x, RECEPTACLE_Y.x, RECEPTACLE_Z.x),
		Vector3(RECEPTACLE_X.y, RECEPTACLE_Y.y, RECEPTACLE_Z.y), shell)
	_box(self, "ReceptacleSlot", Vector3(RECEPTACLE_X.x - 0.3, SLOT_Y - 1.2, SLOT_Z.x),
		Vector3(RECEPTACLE_X.x + 1.0, SLOT_Y + 1.2, SLOT_Z.y), dark)
	_marker("ExpansionAnchor", Vector3(RECEPTACLE_X.x, SLOT_Y, (SLOT_Z.x + SLOT_Z.y) * 0.5))

	# The front: the ACCESS lamp and the OPEN knob, both on the nose.
	var nose_at := func(y: float) -> float:
		return NOSE_FOOT.x - (y - NOSE_FOOT.y) / (NOSE_TOP.y - NOSE_FOOT.y) * (NOSE_FOOT.x - NOSE_TOP.x)
	var led := _slope(self, "AccessLed", Vector2(LED.x - 2.0, LED.x + 2.0),
		Vector2(nose_at.call(LED.y + 1.0), LED.y + 1.0), Vector2(nose_at.call(LED.y - 1.0), LED.y - 1.0), 0.6,
		null)
	# Lit by the core's LED (RetroExpansion._build_shell duplicates it); a surface
	# material, which is what that reads.
	led.material_override = null
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color8(70, 8, 6)
	lamp.roughness = 0.3
	led.set_surface_override_material(0, lamp)
	# Moved the 0.6 it is thick out of the nose, so it stands on it.
	led.position += led.basis.y * 0.6 * MM
	var knob_z: float = nose_at.call(KNOB.y)
	_box(self, "KnobRecess", Vector3(KNOB.x - 8.0, KNOB.y - 6.0, knob_z - 6.0),
		Vector3(KNOB.x + 8.0, KNOB.y - 2.5, knob_z + 2.0), dark)
	_box(self, "EjectButton", Vector3(KNOB.x - 5.0, KNOB.y - 2.5, knob_z - 4.0),
		Vector3(KNOB.x + 5.0, KNOB.y, knob_z + 2.0), _mat("knob", Color8(20, 20, 21), 0.5))

	# The back: the panel the jacks are in, a mouth drawn at AC ADAPTOR (ExpansionPower
	# hides its own on a shell), and the four markers on the back face.
	_box(self, "RearPanel", Vector3(REAR_INSET.x, REAR_INSET.z, -hz - PROUD), Vector3(REAR_INSET.y, REAR_INSET.w, -hz + 1.0), dark)
	# 0.6 thick, its face 0.4 behind the panel's: the shell's back is at -110.6, which
	# is why the row's depth is 220.6 rather than the base's 220.
	var dc := _disc(self, "DcMouth", Vector2(JACKS["DCInPort"], 0.0), 4.5, -0.3, 0.3, _mat("metal", Color8(150, 150, 146), 0.35, 0.7))
	dc.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	dc.position = Vector3(JACKS["DCInPort"], JACK_Y, -hz - 0.3) * MM
	for marker: String in JACKS:
		_marker(marker, Vector3(JACKS[marker], JACK_Y, -hz))
	_marker("DiscSeat", Vector3(WELL_C.x, HUB.y + 0.6, WELL_C.y))
	_stretch(self)
	_stretch(pivot)


## Every x of `parent`'s children times SX: their offsets and their own x extent. Every
## part turns about X only (the slopes) or Y (the dish), so the stretch is a left-hand
## scale along X; LidPivot keeps an identity basis, which MediaTray turns about X.
func _stretch(parent: Node3D) -> void:
	var sx := Basis.from_scale(Vector3(SX, 1.0, 1.0))
	for child in parent.get_children():
		var n := child as Node3D
		if n == null:
			continue
		if n.name == "LidPivot":
			n.position.x *= SX
			continue
		n.transform = Transform3D(sx * n.transform.basis, Vector3(n.position.x * SX, n.position.y, n.position.z))
