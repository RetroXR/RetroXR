## FloatingObjectPanel3D — a 2D options panel that hangs in the air above the
## thing it belongs to and turns to face the player.
##
## Ten panels had grown their own copy of the same twelve lines: top_level on,
## hidden until asked for, and a _process that parks the panel over its object
## and aims it at the camera. Nine were identical in _ready and hide_panel, six
## in _process too.
##
## Two hooks rather than one shared member, so no panel has to rename anything:
## _target_node() hands back whatever that panel already calls its subject
## (_dvd, _vcr, _card...), and _float_height() how far above it to sit. A panel
## whose placement is not "straight up from the origin" — the television, which
## measures the set's own top, the poster, which steps off the surface it is
## stuck to, and the core panel, which clears the tower — overrides _anchor()
## instead and ignores both.
##
## The double flip in _process is not redundant: look_at points the node's -Z at
## the target, and a Viewport2Din3D's face is +Z, so without the half turn every
## panel would present its back to the player.
class_name FloatingObjectPanel3D
extends Node3D

## Default distance above the subject's origin. Overridden per panel, because it
## depends on how tall the thing underneath is.
const DEFAULT_FLOAT_HEIGHT := 0.3

## The head this panel turns towards. Handed in by show_for; a panel with no
## camera still parks correctly and simply does not rotate.
var _camera: Node3D = null

## Set once the panel's 2D UI has been found and its signals wired. The lookup
## has to be deferred — the SubViewport's child does not exist on the frame the
## panel is added — so this guards against wiring the same signals twice.
var _ui_connected := false


func _ready() -> void:
	# top_level: the panel is positioned in world space every frame, so it must
	# not inherit the transform of whatever it happens to be parented under.
	top_level = true
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	var target := _target_node()
	if is_instance_valid(target):
		global_position = _anchor()
	_ensure_lock_row()
	if is_instance_valid(_camera):
		look_at(_camera.global_position, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)
	_update_resize_drag()


func hide_panel() -> void:
	resize_end()
	visible = false


# ── Hooks ─────────────────────────────────────────────────────────────────────

## The object this panel belongs to, or null when it is not showing for anything.
func _target_node() -> Node3D:
	return null


## How far above the subject's origin to sit.
func _float_height() -> float:
	return DEFAULT_FLOAT_HEIGHT


## Where the panel should be this frame. Override for a subject whose top is not
## a fixed distance from its origin.
func _anchor() -> Vector3:
	var target := _target_node()
	if target == null or not is_instance_valid(target):
		return global_position
	return target.global_position + Vector3(0, _float_height(), 0)


# ── Lock in place ─────────────────────────────────────────────────────────────
#
# One row, added here rather than ten times over, because it is the same row on
# every panel and reads from nothing the panel knows: its subject is already
# _target_node(), and whether it can be locked is a property of the object, not
# of the menu in front of it. Panels whose subject is not pickable never grow it.
#
# The row is appended to the 2D UI's outermost box, and the viewport is grown by
# exactly its height so nothing that was already laid out is pushed out of view.

const LOCK_ROW_PX := 52
const _COLOR_ROW := Color(0.75, 0.75, 0.88)
const _COLOR_ON := Color(1.0, 0.80, 0.35)

var _lock_btn: Button = null
var _lock_grown := false


## Build the row if the 2D UI is up and the subject can be locked; keep it in
## step with the object's state while it is showing. Called every visible frame:
## a panel that rebuilds its own UI (the cartridge menu does) drops the row with
## it, and this puts it back.
func _ensure_lock_row() -> void:
	if is_instance_valid(_lock_btn) and _lock_btn.is_inside_tree():
		_refresh_lock_row()
		return
	var target := _target_node()
	if not ObjectLock.can_lock(target):
		return
	var box := _lock_box()
	if box == null:
		return

	# The button carries its own label, so the row has no separate one: the
	# narrowest of these panels is 340 px, and a "Placement" caption beside it
	# pushed the button's text out past the panel edge.
	var row := HBoxContainer.new()
	row.name = "LockRow"
	row.add_theme_constant_override("separation", 8)
	_lock_btn = Button.new()
	_lock_btn.toggle_mode = true
	_lock_btn.custom_minimum_size = Vector2(0, 40)
	_lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock_btn.add_theme_font_override("font", MenuIcons.symbols())
	_lock_btn.toggled.connect(_on_lock_toggled)
	row.add_child(_lock_btn)
	box.add_child(row)

	_grow_for_lock_row()
	_refresh_lock_row()


func _on_lock_toggled(pressed: bool) -> void:
	var target := _target_node()
	if target == null or not is_instance_valid(target):
		return
	ObjectLock.set_locked(target, pressed)
	_refresh_lock_row()


func _refresh_lock_row() -> void:
	if _lock_btn == null or not is_instance_valid(_lock_btn):
		return
	var locked := ObjectLock.is_locked(_target_node())
	_lock_btn.set_pressed_no_signal(locked)
	_lock_btn.text = "%s  %s" % [
		String.chr(MenuIcons.LOCK if locked else MenuIcons.LOCK_OPEN),
		"Locked in place" if locked else "Lock in place"]
	_lock_btn.add_theme_color_override("font_color",
		_COLOR_ON if locked else _COLOR_ROW)


## The 2D UI's outermost box — panel_root gives every menu here a
## PanelContainer > MarginContainer > box, so descend through the single-child
## chain and stop at the first box. A panel laid out some other way simply gets
## no row rather than a row in the wrong place.
func _lock_box() -> BoxContainer:
	var v := _viewport_2d()
	if v == null:
		return null
	var sv := v.get_node_or_null("Viewport") as SubViewport
	if sv == null or sv.get_child_count() == 0:
		return null
	var node: Node = sv.get_child(0)
	while node != null:
		if node is BoxContainer:
			return node as BoxContainer
		if node.get_child_count() != 1:
			return null
		node = node.get_child(0)
	return null


func _viewport_2d() -> XRToolsViewport2DIn3D:
	for c in get_children():
		if c is XRToolsViewport2DIn3D:
			return c as XRToolsViewport2DIn3D
	return null


## Make room for the row rather than squeezing the menu that was already there.
##
## The quad and the collision box come out of the packed scene SHARED between
## every panel instance, so they are made unique first — writing screen_size
## without that resizes every other open menu's screen too.
func _grow_for_lock_row() -> void:
	if _lock_grown:
		return
	_lock_grown = true
	var v := _viewport_2d()
	if v == null:
		return
	var screen := v.get_node_or_null("Screen") as MeshInstance3D
	if screen == null or not (screen.mesh is QuadMesh):
		return
	_own_screen_resources(v)
	var vp: Vector2 = v.viewport_size
	if vp.y <= 0.0:
		return
	var grown := vp.y + LOCK_ROW_PX
	v.screen_size = Vector2(v.screen_size.x, v.screen_size.y * grown / vp.y)
	v.viewport_size = Vector2(vp.x, grown)
	_resize_place_grip()


## The quad and the collision box come out of the packed scene SHARED between
## every panel instance, so they are made unique before anything writes a size.
## Writing screen_size without that resizes every other open menu's screen too.
func _own_screen_resources(v: XRToolsViewport2DIn3D) -> void:
	if _screen_owned:
		return
	_screen_owned = true
	var screen := v.get_node_or_null("Screen") as MeshInstance3D
	if screen != null and screen.mesh != null:
		screen.mesh = screen.mesh.duplicate()
	var shape := v.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape != null:
		shape.shape = shape.shape.duplicate()


# ── Resize grip ───────────────────────────────────────────────────────────────
#
# Opt-in, through enable_resize_grip(), for a panel whose list outgrows the size
# it was authored at. The spawn menu's grip belongs to CurvedPanel and assumes
# its arc and its 1600 px floor, so a small flat panel gets this one. Both use
# PanelResizeGrip as the collider, which calls resize_begin and resize_end on
# whatever it was created for.
#
# It resizes the PAGE, not the magnification. Pixels and metres grow together at
# a fixed density, so the text keeps its size and the extra pixels become more
# rows in the list.
#
# The mark sits on the TOP-right corner, and the bottom edge stays where it is.
# A floating panel hangs just above the thing it belongs to, so growing about its
# centre would lower that edge into the object. With the bottom pinned the top
# edge follows the pointer, and the right edge follows it too, because the width
# grows about the centre by twice what the pointer moved.

## Arm length of the corner mark, its bar thickness, and its hit box.
const RESIZE_GRIP_ARM := 0.03
const RESIZE_GRIP_BAR := 0.006
const RESIZE_GRIP_HIT := 0.04
## How far past the corner the mark sits: its bar plus a hair, so it traces the
## outside of the corner rather than covering the page.
const RESIZE_GRIP_OUT := RESIZE_GRIP_BAR + 0.003
## The largest page, as a multiple of the size it had when first resized.
const RESIZE_MAX_SCALE := 2.5
## Every size change reallocates the SubViewport's render target, so a drag is
## quantised to this rather than doing it every frame.
const RESIZE_STEP_PX := 16.0
const _COLOR_GRIP_IDLE := Color(0.42, 0.45, 0.55)
const _COLOR_GRIP_DRAG := Color(1.0, 0.78, 0.30)

var _screen_owned := false
var _resize_grip: PanelResizeGrip = null
var _resize_grip_mat: StandardMaterial3D = null
## The smallest page, taken the first time it is resized: the authored size plus
## any lock row, which is as small as the layout inside was made to go.
var _resize_min_px := Vector2.ZERO
## How far the page has been raised to keep its bottom edge still.
var _resize_lift := 0.0
var _resize_rest_y := 0.0
var _resize_pointer: Node3D = null
var _resize_from := Vector3.ZERO
var _resize_from_screen := Vector2.ZERO


## Give this panel a corner grip. Called from a subclass's _ready.
func enable_resize_grip() -> void:
	var v := _viewport_2d()
	if v == null or _resize_grip != null:
		return
	_resize_rest_y = v.position.y
	_resize_grip = PanelResizeGrip.create(self,
		Vector3(RESIZE_GRIP_HIT, RESIZE_GRIP_HIT, 0.02))
	var mark := MeshInstance3D.new()
	mark.name = "GripMesh"
	mark.mesh = _resize_grip_mesh()
	_resize_grip_mat = StandardMaterial3D.new()
	_resize_grip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_resize_grip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_resize_grip_mat.albedo_color = _COLOR_GRIP_IDLE
	mark.set_surface_override_material(0, _resize_grip_mat)
	_resize_grip.add_child(mark)
	# On the page rather than on the panel, so it rises with the page as it grows.
	v.add_child(_resize_grip)
	_resize_place_grip()
	visibility_changed.connect(_resize_sync_grip)
	_resize_sync_grip()


## Two bars meeting at the corner: one back along the top edge, one down the side.
func _resize_grip_mesh() -> ArrayMesh:
	var a := RESIZE_GRIP_ARM
	var b := RESIZE_GRIP_BAR
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Array in [[-a, -b], [-b, -a]]:
		# r = the far corner of one bar, as an offset from the mark's own corner.
		var x0: float = r[0]
		var y0: float = r[1]
		var n := verts.size()
		verts.append(Vector3(x0, y0, 0.0))
		verts.append(Vector3(0.0, y0, 0.0))
		verts.append(Vector3(0.0, 0.0, 0.0))
		verts.append(Vector3(x0, 0.0, 0.0))
		idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _resize_place_grip() -> void:
	var v := _viewport_2d()
	if _resize_grip == null or v == null:
		return
	_resize_grip.position = Vector3(v.screen_size.x * 0.5 + RESIZE_GRIP_OUT,
		v.screen_size.y * 0.5 + RESIZE_GRIP_OUT, 0.001)


## A hidden panel's grip must not catch the laser: visible governs drawing only.
func _resize_sync_grip() -> void:
	if _resize_grip == null:
		return
	var on := is_visible_in_tree()
	_resize_grip.collision_layer = VRSlider.POINTABLE_LAYER if on else 0
	for c in _resize_grip.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on
	if not on:
		resize_end()


## Called by the grip on PRESSED. Remembers which pointer owns the drag.
func resize_begin(pointer: Node3D) -> void:
	var v := _viewport_2d()
	if (v == null or not is_instance_valid(pointer)
			or v.screen_size.x <= 0.0 or v.screen_size.y <= 0.0):
		return
	if _resize_min_px == Vector2.ZERO:
		_resize_min_px = v.viewport_size
	_resize_pointer = pointer
	_resize_from = _resize_pointer_on_plane(pointer)
	_resize_from_screen = v.screen_size
	if _resize_grip_mat != null:
		_resize_grip_mat.albedo_color = _COLOR_GRIP_DRAG


func resize_end() -> void:
	_resize_pointer = null
	if _resize_grip_mat != null:
		_resize_grip_mat.albedo_color = _COLOR_GRIP_IDLE


## Follow the pointer that started the drag. Its own ray is projected onto the
## panel every frame, rather than following pointer MOVED events, which stop the
## moment the cursor leaves the little grip -- immediately, for a resize.
func _update_resize_drag() -> void:
	if _resize_pointer == null:
		return
	if not is_instance_valid(_resize_pointer):
		resize_end()
		return
	var v := _viewport_2d()
	if v == null or v.screen_size.x <= 0.0:
		return
	var d := _resize_pointer_on_plane(_resize_pointer) - _resize_from
	var density := v.viewport_size / v.screen_size
	resize_page(Vector2(_resize_from_screen.x + d.x * 2.0,
		_resize_from_screen.y + d.y) * density)


## Where a pointer is aiming, on the panel's own z = 0 plane, in panel space. The
## panel itself does not move as the page grows -- the page rises inside it --
## so this frame holds still for the whole drag.
func _resize_pointer_on_plane(pointer: Node3D) -> Vector3:
	var inv := global_transform.affine_inverse()
	var origin := inv * pointer.global_position
	var dir := (inv.basis * (-pointer.global_transform.basis.z)).normalized()
	if absf(dir.z) < 0.0001:
		return Vector3(origin.x, origin.y, 0.0)
	return origin + dir * (-origin.z / dir.z)


## Make the page this many viewport pixels, clamped and quantised, at the density
## it already has and with its bottom edge where it was.
func resize_page(want_px: Vector2) -> void:
	var v := _viewport_2d()
	if v == null or v.viewport_size.x <= 0.0 or v.screen_size.x <= 0.0:
		return
	if _resize_min_px == Vector2.ZERO:
		_resize_min_px = v.viewport_size
	var hi := _resize_min_px * RESIZE_MAX_SCALE
	var px := (want_px / RESIZE_STEP_PX).round() * RESIZE_STEP_PX
	px = px.clamp(_resize_min_px, hi)
	if px.is_equal_approx(v.viewport_size):
		return
	var density := v.viewport_size / v.screen_size
	var old_height := v.screen_size.y
	_own_screen_resources(v)
	var screen := px / density
	v.viewport_size = px
	v.screen_size = screen
	_resize_lift += (screen.y - old_height) * 0.5
	v.position.y = _resize_rest_y + _resize_lift
	_resize_place_grip()
