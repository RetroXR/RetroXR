## CurvedPanel — lets an XRToolsViewport2DIn3D wrap toward the viewer, with a
## flat/curved toggle sitting just outside its lower-right corner and a trash bin
## (MenuTrashBin) outside its lower-left one.
##
## The spawn menu is 1.1 m wide at 0.9 m, so it subtends ~63 deg and its corners
## sit ~17% further from the eye than its centre. Wrapping it onto a cylinder
## takes that out.
##
## Added as a CHILD of the Viewport2DIn3D rather than as a script on it — the
## panel already carries the addon's own script, which owns the viewport and the
## embedded scene — and rather than as an inherited scene, so neither the addon
## nor player_rig has to be restructured.
## Three things have to stay in agreement:
##
##  1. the Screen mesh — a cylindrical arc with UVs linear in ARC LENGTH, so the
##     picture neither stretches nor compresses toward the edges;
##  2. the collision — a BoxShape3D cannot bend, so it becomes a
##     ConcavePolygonShape3D built from the same arc;
##  3. where a hit lands in the viewport — viewport_2d_in_3d_body.global_to_viewport
##     maps a hit with two planar lines. Rather than subclass it, this intercepts
##     its pointer_event and rewrites the hit to the equivalent point on the flat
##     plane, so the addon's own maths still produces the right pixel.
##
## Skipping (3) is the tempting shortcut and it does not work: an arc maps angle
## as x = R*theta while a flat plane maps it as x = R*tan(theta), which at this
## panel's edge is ~14% out — far enough to press the wrong control.
class_name CurvedPanel
extends Node3D

## Emitted whenever the geometry is rebuilt — a curve step, or a resize. Anything
## parented to the panel that has to ride the arc listens to this and re-places
## itself; a DropdownPanel popout also re-curves to stay concentric.
signal curve_changed

## Cylinder radius at full curve, in metres. Not the 0.9 m spawn distance: the
## panel is grabbable between 0.3 m and 2.5 m, so a curve tuned to one distance
## looks wrong at every other. This reads as a gentle wrap across that range.
@export var curve_radius: float = 1.4
## Segments across the arc. 24 is smooth at this width and still a trivial mesh.
@export var segments: int = 24
@export var animate_seconds: float = 0.22
## Start curved. AppPrefs.menu_curved overrides this at runtime — the export is
## only the fallback for a panel built outside the app (probes, tests).
@export var curved: bool = true
## Build the flat/curved toggle and the resize grip. Off for a panel that is not
## the one the player is steering — a dropdown popout curves to match its host
## and must not offer a second set of controls.
@export var show_controls: bool = true
## Take the initial state from AppPrefs. Off for a panel driven by another one.
@export var follow_prefs: bool = true

## 0 = flat, 1 = fully wrapped. Animated between the two.
var _curve: float = 0.0
var _tween: Tween = null

var _screen: MeshInstance3D = null
var _body: StaticBody3D = null
var _collision: CollisionShape3D = null
var _screen_size := Vector2(1.1, 0.75)

var _btn_flat: VRButton = null
var _btn_curved: VRButton = null

var _trash_bin: MenuTrashBin = null

var _grip: PanelResizeGrip = null
var _grip_mesh: MeshInstance3D = null
## Set while a resize drag is live: the pointer that started it, the panel-local
## point it grabbed, and the size at that moment.
var _drag_pointer: Node3D = null
var _drag_from := Vector3.ZERO
var _drag_size := Vector2.ZERO
## Viewport pixels per metre at the moment the drag began.
var _drag_density := Vector2(2000.0, 2000.0)
## Scratch resources so the addon's setter has something it can write to.
var _scratch_mesh := QuadMesh.new()
var _scratch_shape := BoxShape3D.new()
## The real geometry, reused across rebuilds. A curve step runs every frame of
## the tween, and allocating a fresh ArrayMesh and re-cooking a trimesh each time
## is what made the toggle stutter.
var _arc_mesh := ArrayMesh.new()
var _arc_shape := ConcavePolygonShape3D.new()

## Arc length past the screen edge, and the spacing between the two buttons.
const BTN_GAP := 0.035
const BTN_PITCH := 0.055

## Resize limits, in VIEWPORT PIXELS — the grip resizes the page, not the
## magnification. The horizontal floor is the binding one: the menu's tab strip
## needs roughly 1100 logical pixels to keep its labels on two rows, and
## ui_scale halves whatever is set here.
const MIN_VIEWPORT := Vector2(1600, 1100)
const MAX_VIEWPORT := Vector2(4000, 2600)
## Every size change reallocates the SubViewport's render target, so a drag is
## quantised to this rather than doing it every frame.
const VIEWPORT_STEP := 32.0
## Arm length of the "_|" corner mark, its bar thickness, and its hit box.
const GRIP_ARM := 0.045
const GRIP_BAR := 0.008
const GRIP_HIT := 0.055
## How far past the corner the mark sits, out along the surface and down.
##
## Only the bar thickness plus a hair, so the "_|" traces the outside of the
## corner it marks. Its two arms run back along the edges from its origin — the
## horizontal one under the bottom edge, the vertical one beside the right edge
## — and each has to clear only the edge it is parallel to, not both. Offsetting
## by a whole arm length (the first attempt) clears both and leaves the mark
## floating in the diagonal, attached to nothing.
const GRIP_OUT := GRIP_BAR + 0.003
## Gap between the grip and the column of curve toggles beside it.
const ROW_GAP := 0.008

const HL_ON := Color(1.0, 0.78, 0.30)
const HL_OFF := Color(0.42, 0.45, 0.55)


var _panel: Node3D = null


func _ready() -> void:
	_panel = get_parent() as Node3D
	if _panel == null:
		push_warning("CurvedPanel: must be a child of an XRToolsViewport2DIn3D")
		return
	_screen = _panel.get_node_or_null("Screen") as MeshInstance3D
	_body = _panel.get_node_or_null("StaticBody3D") as StaticBody3D
	if _body:
		_collision = _body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _screen == null or _body == null or _collision == null:
		push_warning("CurvedPanel: expected Screen/StaticBody3D/CollisionShape3D — panel left flat")
		return

	var size: Variant = _panel.get("screen_size")
	if size is Vector2:
		_screen_size = size

	# All deferred on purpose. Children _ready BEFORE their parent, so at this
	# point the panel has not run its own _ready yet — which wires the body's
	# pointer handler and calls _update_screen_size(), resetting the mesh to a
	# QuadMesh and the shape to a box. Deferring puts this after both.
	call_deferred("_intercept_pointer")
	if show_controls:
		call_deferred("_build_toggle")
		call_deferred("_build_grip")
		call_deferred("_build_trash_bin")
	if follow_prefs:
		curved = AppPrefs.menu_curved
	_curve = 1.0 if curved else 0.0
	call_deferred("_rebuild")


# ── Geometry ──────────────────────────────────────────────────────────────────

## Local-space point for an arc parameter. `s` is arc length from the centre
## (-w/2 .. w/2), so UVs stay linear and the picture does not stretch.
func _arc_point(s: float, y: float) -> Vector3:
	if _curve <= 0.001:
		return Vector3(s, y, 0.0)
	var r := curve_radius / _curve
	var theta := s / r
	return Vector3(r * sin(theta), y, r * (1.0 - cos(theta)))


## `update_collision` off skips re-cooking the trimesh — the expensive half. Used
## for the frames of the curve tween, where nothing can be clicked anyway; the
## tween's finished callback does one full rebuild to put the collider back in
## step with the mesh.
func _rebuild(update_collision := true) -> void:
	if _screen == null:
		return
	var hw := _screen_size.x * 0.5
	var hh := _screen_size.y * 0.5

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var tris := PackedVector3Array()

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var s: float = lerp(-hw, hw, t)
		var top := _arc_point(s, hh)
		var bot := _arc_point(s, -hh)
		verts.append(top)
		verts.append(bot)
		uvs.append(Vector2(t, 0.0))
		uvs.append(Vector2(t, 1.0))
		# Outward normal: FROM the surface TOWARD the centre of curvature at +Z,
		# i.e. back at the viewer. The other way round leaves the screen's lit
		# material shaded from behind (cull_mode is disabled, so it still draws —
		# the error shows only as wrong shading).
		var n := Vector3(0, 0, 1)
		if _curve > 0.001:
			var r := curve_radius / _curve
			n = (Vector3(0.0, 0.0, r) - Vector3(top.x, 0.0, top.z)).normalized()
		normals.append(n)
		normals.append(n)

	var idx := PackedInt32Array()
	for i in range(segments):
		var a := i * 2
		var b := a + 1
		var c := a + 2
		var d := a + 3
		idx.append_array([a, c, b, c, d, b])
		tris.append_array([verts[a], verts[c], verts[b], verts[c], verts[d], verts[b]])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx

	# Refill the same ArrayMesh rather than making a new one: the material
	# override and the MeshInstance's own RID then survive untouched, so a curve
	# step costs a buffer upload instead of a resource swap.
	var mat := _screen.get_surface_override_material(0)
	if mat == null and _screen.mesh != null and _screen.mesh != _arc_mesh:
		mat = _screen.mesh.surface_get_material(0)
	_arc_mesh.clear_surfaces()
	_arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _screen.mesh != _arc_mesh:
		_screen.mesh = _arc_mesh
	if mat:
		_screen.set_surface_override_material(0, mat)

	if update_collision:
		_arc_shape.set_faces(tris)
		# A trimesh is single-sided by default, so a ray from the wrong side
		# passes straight through and the panel silently stops taking clicks —
		# exactly what happened when this replaced the BoxShape. The winding above
		# is correct now, but this makes a future slip cosmetic, not fatal.
		_arc_shape.backface_collision = true
		if _collision.shape != _arc_shape:
			_collision.shape = _arc_shape

	_place_buttons()
	_place_grip()
	_place_trash_bin()
	curve_changed.emit()


## Where something sitting `out` metres off the screen should go, for a point
## given in FLAT panel-local coordinates (x measured along the surface, y up).
## Anything parented to the panel that is not part of its texture — the toggle
## icons, the resize grip, a DropdownPanel popout — has to be placed through this
## or it ends up buried in the screen wherever the arc bows toward the viewer.
func surface_pose(flat_x: float, y: float, out: float) -> Transform3D:
	if _curve <= 0.001:
		return Transform3D(Basis.IDENTITY, Vector3(flat_x, y, out))
	var r := curve_radius / _curve
	var theta := flat_x / r
	# Outward normal at this point on the arc, i.e. back toward the viewer.
	var n := Vector3(-sin(theta), 0.0, cos(theta))
	var tilt := Basis(Vector3.UP, -theta)
	return Transform3D(tilt, _arc_point(flat_x, y) + n * out)


## True while the screen is bent enough for surface_pose to matter.
func is_curved() -> bool:
	return _curve > 0.001


## Distance from the cylinder axis out to the screen, in metres, or 0 when flat.
## A panel that wants to sit on the SAME cylinder — concentric, so the two read
## as one surface rather than two — takes this minus its own standoff.
func axis_radius() -> float:
	return 0.0 if _curve <= 0.001 else curve_radius / _curve


## Run `mutate` — anything that writes the panel's screen_size or viewport_size —
## with plain QuadMesh/BoxShape geometry in place, then restore the arc.
##
## Not optional. viewport_2d_in_3d._update_screen_size does, in order:
##     $Screen.mesh.size = screen_size
##     $StaticBody3D.screen_size = screen_size
##     $StaticBody3D/CollisionShape3D.shape.size = ...
## An ArrayMesh has no `size`, so against live geometry the first line raises
## "Invalid assignment of property 'size' ... on ArrayMesh" and GDScript abandons
## the function — leaving the body's screen_size stale, which is what the addon's
## hit mapping reads. The visible symptom is an error storm; the quiet one is a
## panel whose clicks land in the wrong place.
func with_flat_geometry(mutate: Callable) -> void:
	if _screen == null or _collision == null:
		mutate.call()
		return
	_screen.mesh = _scratch_mesh
	_collision.shape = _scratch_shape
	mutate.call()
	resync()


## Resize a Viewport2DIn3D from outside, curved or not. Anything that assigns
## screen_size must come through here or through with_flat_geometry on a panel it
## already holds — a plain assignment throws the moment the panel is curved, and
## the throw is silent until someone is actually dragging.
static func set_screen_size(panel: Node3D, size: Vector2) -> void:
	if panel == null:
		return
	# A rebuild re-cooks the trimesh, and a caller holding the stick against a
	# clamp asks for the same size every frame.
	var now: Variant = panel.get("screen_size")
	if now is Vector2 and (now as Vector2).is_equal_approx(size):
		return
	var curve := panel.get_node_or_null("CurvedPanel") as CurvedPanel
	if curve != null:
		curve.with_flat_geometry(func() -> void: panel.set("screen_size", size))
	else:
		panel.set("screen_size", size)


## Re-read the panel's screen_size and rebuild. Needed after anything that goes
## through the addon's own screen_size setter, which replaces the arc mesh with a
## QuadMesh and the trimesh with a BoxShape as a side effect of its bookkeeping.
func resync() -> void:
	if _screen == null or _panel == null:
		return
	var size: Variant = _panel.get("screen_size")
	if size is Vector2:
		_screen_size = size
	_rebuild()


# ── Pointer remap ─────────────────────────────────────────────────────────────

func _intercept_pointer() -> void:
	if _body == null or not _body.has_signal("pointer_event"):
		return
	if _body.has_method("_on_pointer_event") \
			and _body.pointer_event.is_connected(_body._on_pointer_event):
		_body.pointer_event.disconnect(_body._on_pointer_event)
	if not _body.pointer_event.is_connected(_on_pointer_event):
		_body.pointer_event.connect(_on_pointer_event)


## Flatten the hit, then hand it to the addon's planar handler unchanged.
func _on_pointer_event(event: XRToolsPointerEvent) -> void:
	if _curve > 0.001:
		event.position = _flatten(event.position)
		event.last_position = _flatten(event.last_position)
	if _body.has_method("_on_pointer_event"):
		_body._on_pointer_event(event)


## Curved-surface hit -> the point on the flat plane that maps to the same pixel.
## theta = atan2(x, R - z) recovers the angle about the centre of curvature, and
## arc length R*theta is exactly the flat-plane x the addon expects.
func _flatten(at: Vector3) -> Vector3:
	var t := _collision.global_transform
	var local := t.affine_inverse() * at
	var r := curve_radius / _curve
	var theta := atan2(local.x, r - local.z)
	return t * Vector3(r * theta, local.y, 0.0)


# ── Flat / curved toggle ──────────────────────────────────────────────────────

## A press: apply it and remember it. Kept apart from set_curved so nothing
## internal can write the prefs file as a side effect.
func _choose(on: bool) -> void:
	set_curved(on)
	AppPrefs.menu_curved = on
	AppPrefs.save_prefs()


func set_curved(on: bool, animate := true) -> void:
	curved = on
	_refresh_buttons()
	var target := 1.0 if on else 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	if not animate or animate_seconds <= 0.0:
		_curve = target
		_rebuild()
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_curve_step, _curve, target, animate_seconds)
	_tween.finished.connect(_rebuild.bind(true))


func _set_curve_step(v: float) -> void:
	_curve = v
	_rebuild(false)


func _refresh_buttons() -> void:
	if _btn_flat:
		_btn_flat.set_latched_pressed(not curved)
		_btn_flat.set_color(HL_OFF if curved else HL_ON)
	if _btn_curved:
		_btn_curved.set_latched_pressed(curved)
		_btn_curved.set_color(HL_ON if curved else HL_OFF)


## Two buttons just outside the lower-right corner. The icons are the shapes
## themselves — a straight bar and an arced one — so they need no legend.
func _build_toggle() -> void:
	_btn_flat = _make_button("CurveToggleFlat", false)
	_btn_curved = _make_button("CurveToggleCurved", true)
	_btn_flat.button_pressed.connect(func() -> void: _choose(false))
	_btn_curved.button_pressed.connect(func() -> void: _choose(true))
	_place_buttons()
	_refresh_buttons()


## The corner furniture sits just outside the panel's lower-right corner: the
## resize grip hugging the corner itself, and the curve toggles stacked in a
## column immediately to its right, curved above flat. This is the line they
## start from.
func _corner_baseline() -> float:
	return -_screen_size.y * 0.5 - GRIP_OUT


## Yaw that keeps a piece of furniture facing along the arc at arc-length `s`.
## Left at zero they read as flat tabs stuck on a curved panel.
func _yaw_at(s: float) -> float:
	return 0.0 if _curve <= 0.001 else -s / (curve_radius / _curve)


## Seat the buttons ON the arc, continuing it past the screen's edge, and turn
## them to face along it. Left at z = 0 they would sit ~11 cm behind the edge
## once the panel wrapped, floating off the corner they belong to.
func _place_buttons() -> void:
	if _btn_flat == null or _btn_curved == null:
		return
	# One column just past the grip's outer edge, curved above flat. They sit
	# right of the panel's edge, so starting on the corner's line does not
	# overlap it.
	var s := _screen_size.x * 0.5 + GRIP_OUT + ROW_GAP + BTN_PITCH * 0.5
	var y := _corner_baseline()
	var yaw := _yaw_at(s)
	for i in 2:
		var btn: VRButton = [_btn_flat, _btn_curved][i]
		btn.position = _arc_point(s, y + BTN_PITCH * i)
		btn.rotation = Vector3(0.0, yaw, 0.0)


func _make_button(node_name: String, arced: bool) -> VRButton:
	var btn := VRButton.new()
	btn.name = node_name
	btn.depress_axis = Vector3(0, 0, -1)
	btn.depress_depth = 0.004

	var hit := Vector3(0.044, 0.044, 0.012)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hit
	shape.shape = box
	btn.add_child(shape)

	# VRButton is an Area3D and the laser ignores areas, so these would only ever
	# respond to a fingertip — and they sit at the edge of a panel that floats
	# out of reach. The proxy opts these two in without making every VRButton in
	# the project pressable from across the room.
	PointerProxy.wrap(btn, hit)

	# Named ButtonMesh and parented BEFORE the button enters the tree:
	# VRButton._ready resolves `@onready _mesh = $ButtonMesh` and immediately
	# reads _mesh.position, so a later add_child would have it dereference null.
	var mi := MeshInstance3D.new()
	mi.name = "ButtonMesh"
	mi.mesh = _icon_mesh(arced)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Flat ribbons with no back to speak of — without this the winding decides
	# whether you can see them at all.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = HL_OFF
	mi.set_surface_override_material(0, mat)
	btn.add_child(mi)

	add_child(btn)
	return btn


## A pictogram, not a miniature: a straight ribbon for flat, an arched one for
## curved. The bow runs in Y — in the plane facing the player — because a bow in
## Z is exactly edge-on from where they stand and reads as a plain rectangle.
func _icon_mesh(arced: bool) -> ArrayMesh:
	var half := 0.018
	var thick := 0.0035
	var bow: float = 0.010 if arced else 0.0
	var steps := 12

	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x: float = lerp(-half, half, t)
		# Parabolic arch — indistinguishable from a true arc at this size.
		var mid: float = bow * (1.0 - pow(x / half, 2.0))
		verts.append(Vector3(x, mid + thick, 0.0))
		verts.append(Vector3(x, mid - thick, 0.0))
	for i in range(steps):
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── Resize ────────────────────────────────────────────────────────────────────

## The "_|" mark at the panel's lower-right corner.
func _build_grip() -> void:
	_grip = PanelResizeGrip.create(self, Vector3(GRIP_HIT, GRIP_HIT, 0.02))
	_grip_mesh = MeshInstance3D.new()
	_grip_mesh.name = "GripMesh"
	_grip_mesh.mesh = _grip_corner_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = HL_OFF
	_grip_mesh.set_surface_override_material(0, mat)
	_grip.add_child(_grip_mesh)
	add_child(_grip)
	_place_grip()


## Two bars meeting at the bottom-right: one along the bottom, one up the right.
func _grip_corner_mesh() -> ArrayMesh:
	var a := GRIP_ARM
	var b := GRIP_BAR
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Array in [[-a, 0.0, 0.0, b], [-b, 0.0, 0.0, a]]:
		# r = [x0, y0, x1, y1] as offsets from the corner at (0, 0).
		var x0: float = r[0]
		var y0: float = r[1]
		var x1: float = r[2]
		var y1: float = r[3]
		var n := verts.size()
		verts.append(Vector3(x0, y0, 0.0))
		verts.append(Vector3(x1, y0, 0.0))
		verts.append(Vector3(x1, y1, 0.0))
		verts.append(Vector3(x0, y1, 0.0))
		idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## On the arc at the lower-right corner, facing along it — same reasoning as the
## toggle buttons, which were left behind the edge when it was pinned to z = 0.
func _place_grip() -> void:
	if _grip == null:
		return
	# Just past the corner, out along the arc and below the bottom — clear of
	# the screen in both axes rather than sitting under the corner it marks.
	# First in the row; the curve toggles follow to its right.
	var s := _screen_size.x * 0.5 + GRIP_OUT
	_grip.position = _arc_point(s, _corner_baseline())
	_grip.rotation = Vector3(0.0, _yaw_at(s), 0.0)


# ── Trash bin ─────────────────────────────────────────────────────────────────

## The MenuTrashBin, in the free corner: the lower-right one has the grip and
## the curve toggles.
func _build_trash_bin() -> void:
	_trash_bin = MenuTrashBin.new()
	_trash_bin.name = "TrashBin"
	add_child(_trash_bin)
	_place_trash_bin()


## Beside the left edge with its foot level with the bottom one, on the arc and
## facing along it like the rest of the corner furniture.
func _place_trash_bin() -> void:
	if _trash_bin == null:
		return
	var s := -(_screen_size.x * 0.5 + GRIP_OUT + MenuTrashBin.RADIUS)
	var y := -_screen_size.y * 0.5 + MenuTrashBin.HEIGHT * 0.5
	_trash_bin.position = _arc_point(s, y)
	_trash_bin.rotation = Vector3(0.0, _yaw_at(s), 0.0)


## Called by the grip on PRESSED. Remembers which pointer owns the drag.
func resize_begin(pointer: Node3D) -> void:
	if not is_instance_valid(pointer):
		return
	_drag_pointer = pointer
	_drag_size = _screen_size
	_drag_from = _pointer_on_plane(pointer)
	# Pixels per metre, fixed for the whole drag. Holding this constant is what
	# makes the grip add page rather than magnification: the text keeps its
	# physical size and the extra pixels become extra room.
	var vp: Variant = _panel.get("viewport_size")
	_drag_density = Vector2(2000.0, 2000.0)
	if vp is Vector2 and _drag_size.x > 0.0 and _drag_size.y > 0.0:
		_drag_density = (vp as Vector2) / _drag_size
	if is_instance_valid(_grip_mesh):
		(_grip_mesh.get_surface_override_material(0) as StandardMaterial3D).albedo_color = HL_ON


func resize_end() -> void:
	_drag_pointer = null
	if is_instance_valid(_grip_mesh):
		(_grip_mesh.get_surface_override_material(0) as StandardMaterial3D).albedo_color = HL_OFF


func _process(_delta: float) -> void:
	if not is_instance_valid(_drag_pointer):
		return
	var now := _pointer_on_plane(_drag_pointer)
	var d := now - _drag_from
	# The panel is centred on its origin, so a corner moved by d changes the
	# half-extent by d and the full size by twice that. Down is -y.
	_apply_page_size(Vector2(_drag_size.x + d.x * 2.0, _drag_size.y - d.y * 2.0)
		* _drag_density)


## Where this pointer is aiming, on the panel's z = 0 plane, in panel-local
## space. Following pointer MOVED events instead would end the drag the instant
## the cursor left the grip, which is immediately.
func _pointer_on_plane(pointer: Node3D) -> Vector3:
	var inv := _panel.global_transform.affine_inverse()
	var origin := inv * pointer.global_position
	var dir := (inv.basis * (-pointer.global_transform.basis.z)).normalized()
	if absf(dir.z) < 0.0001:
		return Vector3(origin.x, origin.y, 0.0)
	var t := -origin.z / dir.z
	return origin + dir * t


## Grow or shrink the PAGE: more viewport pixels, and the metres to draw them
## at, so text keeps its physical size and the extra pixels become extra room.
## Growing vertically therefore lands in the menu's content area, which is the
## only part of its layout that expands — the title and nav rows keep their
## natural height.
##
## This is the other half of a pair. The thumbstick (SpawnMenuController's
## grab-resize) writes screen_size alone, which is pure magnification: same
## pixels, larger metres, so everything just gets bigger. The grip writes both.
##
## Through with_flat_geometry because the screen_size half runs the addon's
## setter, which assigns mesh.size — a property the arc's ArrayMesh has not got.
func _apply_page_size(want_px: Vector2) -> void:
	if _panel == null:
		return
	var vp := Vector2(
		clampf(want_px.x, MIN_VIEWPORT.x, MAX_VIEWPORT.x),
		clampf(want_px.y, MIN_VIEWPORT.y, MAX_VIEWPORT.y))
	vp = (vp / VIEWPORT_STEP).round() * VIEWPORT_STEP
	var now: Variant = _panel.get("viewport_size")
	if now is Vector2 and (now as Vector2).is_equal_approx(vp):
		return
	var screen := vp / _drag_density
	with_flat_geometry(func() -> void:
		_panel.set("viewport_size", vp)
		_panel.set("screen_size", screen))
