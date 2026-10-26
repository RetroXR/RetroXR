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
	# Every object's menu takes the corner grip the spawn menu has, so any of them
	# can be dragged bigger. It was opt-in, and only the two with long lists (a
	# memory card's saves, a BS-X pack's) had opted in. A panel whose page is not a
	# direct child gets none, and says so, rather than a grip on the wrong node.
	enable_resize_grip()
	if _resize_grip == null:
		push_warning("[Panel] %s: no Viewport2DIn3D child, so no resize grip" % name)
	visibility_changed.connect(func() -> void: _subject_measured = false)


# ── Keeping clear of the object ───────────────────────────────────────────────
#
# A menu hangs above the thing it belongs to, and a page dragged bigger grows DOWN
# from its top edge (the grip is on the bottom-right), so a tall page would sink
# into the object under it. Every frame, after the panel is placed, its page's box
# is tested against the object's own box and the whole panel is raised just enough
# to clear it. 3D boxes, not "below the object's top": the poster's menu stands in
# FRONT of the poster at its own height, overlapping nothing, and must stay there.

## Gap kept between the bottom of the page and the top of the object.
const SUBJECT_CLEARANCE := 0.03
## How often the object is re-measured while the menu is open (it can be moved or
## resized under it). Measuring walks its meshes, so not every frame.
const SUBJECT_MEASURE_S := 1.0

## The object's visible bounds, world-axis, relative to its origin.
var _subject_box := AABB()
var _subject_measured := false
var _subject_measure_t := 0.0
## The mesh that set the object's top at the last measurement, for the log.
var _subject_top_mesh := NodePath()
## The lift last logged, so the log speaks on a change and not every frame.
var _logged_lift := 0.0


func _keep_clear_of(target: Node3D, delta: float) -> void:
	_subject_measure_t -= delta
	if not _subject_measured or _subject_measure_t <= 0.0:
		_measure_subject(target)
	var v := _viewport_2d()
	if not _subject_measured or v == null:
		return
	var box := _subject_box
	box.position += target.global_position
	var lift := clearance_lift(_page_corners(v), box, SUBJECT_CLEARANCE)
	if lift > 0.0:
		global_position.y += lift
	# Said when it changes by a few centimetres, never per frame: a menu that opens
	# in the wrong place is diagnosed from this line (which mesh set the top).
	if absf(lift - _logged_lift) > 0.05:
		_logged_lift = lift
		print("[Panel] %s: raised %.0f cm clear of %s (its top is %s, at %.3f m)" % [
			name, lift * 100.0, target.name, _subject_top_mesh, box.end.y])


## How far up a page must go to clear `subject` by `clearance`, or 0 when it does
## not overlap it at all. `page` is the page's four corners in world space.
## Static and pure, so the rule is checked without a scene (state_tests resize/).
static func clearance_lift(page: PackedVector3Array, subject: AABB, clearance: float) -> float:
	if page.is_empty() or subject.size == Vector3.ZERO:
		return 0.0
	var pbox := AABB(page[0], Vector3.ZERO)
	for p in page:
		pbox = pbox.expand(p)
	var bottom := pbox.position.y
	# A page is flat; give it a millimetre of depth so a box test can see it (the
	# lift is still measured from its real bottom edge).
	pbox = pbox.grow(0.001)
	# The clearance counts only above the object: a page close in FRONT of it (the
	# poster's) is not touching it.
	var above := AABB(subject.position, subject.size + Vector3(0.0, clearance, 0.0))
	if not pbox.intersects(above):
		return 0.0
	return maxf(0.0, subject.end.y + clearance - bottom)


func _page_corners(v: XRToolsViewport2DIn3D) -> PackedVector3Array:
	var h := v.screen_size * 0.5
	var c := v.position
	var out := PackedVector3Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(global_transform * (c + Vector3(h.x * s.x, h.y * s.y, 0.0)))
	return out


## The object's OWN body, as HeldHint.visual_top measures it: its visible meshes,
## less everything that hangs off it without being it. Counting those made a menu
## open high and drop a second later (when the next measurement no longer saw
## them): a console's cords are VerletRopes, which ARE MeshInstance3Ds, and a cord
## lifting or settling as the machine is touched stretched the "console" upward.
## Left out:
##   * anything under another physics body below the object — plugs, controllers,
##     a seated cartridge or disc: separate objects with their own extent;
##   * VerletRope meshes (the cords themselves);
##   * anything drawn inside a SubViewport (a screen's scene; the Game Boy Camera's
##     backdrop has a box 2 km wide);
##   * menus and highlight overlays.
func _measure_subject(target: Node3D) -> void:
	_subject_measure_t = SUBJECT_MEASURE_S
	var box := AABB()
	var found := false
	var top_mesh: MeshInstance3D = null
	for node: Node in target.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.is_class("VerletRope") or mi.get_viewport() != target.get_viewport():
			continue
		if _not_the_object(mi, target):
			continue
		var wb: AABB = mi.global_transform * mi.get_aabb()
		if not found or wb.end.y > box.end.y:
			top_mesh = mi
		box = wb if not found else box.merge(wb)
		found = true
	_subject_measured = found
	if found:
		box.position -= target.global_position
		_subject_box = box
		_subject_top_mesh = target.get_path_to(top_mesh) if top_mesh else NodePath()


## Whether a mesh under the object belongs to something else hanging off it: a
## menu, a highlight overlay, or another physics body (see _measure_subject).
static func _not_the_object(n: Node, stop: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != stop:
		if p is FloatingObjectPanel3D or p is PickableHighlight or p is WidgetOutline:
			return true
		if p is PhysicsBody3D:
			return true
		p = p.get_parent()
	return false


func _process(delta: float) -> void:
	if not visible:
		return
	var target := _target_node()
	if is_instance_valid(target):
		global_position = _anchor()
	_ensure_lock_row()
	_tick_delete_prompt(delta)
	if is_instance_valid(_camera):
		look_at(_camera.global_position, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)
	if is_instance_valid(target):
		_keep_clear_of(target, delta)
	_update_resize_drag()
	_while_shown(delta)


## Each frame the panel is shown, after it is placed: what a panel follows while it
## is open (the core panel's handheld volume). A panel overrides this rather than
## _process, which stays this one (state_tests' anchor/ group).
func _while_shown(_delta: float) -> void:
	pass


func hide_panel() -> void:
	resize_end()
	_delete_confirm = 0.0
	_set_delete_prompt(false)
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
## What _lock_btn last drew: 1 locked, 0 not, -1 nothing yet. The row is checked
## every frame the panel shows, and writing the text and the colour override on
## each of them re-laid the whole panel out whether or not anything had changed.
var _lock_drawn := -1


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
	# Delete goes in first, so it sits just above the lock.
	if Trash.can_delete(target):
		_build_delete_row(box)
	box.add_child(row)

	_grow_for_lock_row()
	_lock_drawn = -1
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
	if int(locked) == _lock_drawn:
		return
	_lock_drawn = int(locked)
	_lock_btn.set_pressed_no_signal(locked)
	_lock_btn.text = "%s  %s" % [
		String.chr(MenuIcons.LOCK if locked else MenuIcons.LOCK_OPEN),
		"Locked in place" if locked else "Lock in place"]
	_lock_btn.add_theme_color_override("font_color",
		_COLOR_ON if locked else _COLOR_ROW)


# ── Delete ────────────────────────────────────────────────────────────────────
#
# Above the lock, on every panel whose subject a bin could take (Trash.can_delete:
# spawned, and not a captive cable end). The same delete as the bins, so a
# controller goes with its console, a lead with both ends, and netplay and the
# saved room hear of it the same way.
#
# Two presses: the first turns the row into "Tap again to delete" for a few
# seconds, so a laser sweeping across the menu cannot bin a console. A locked
# object can still be deleted here; opening its menu and pressing twice is not
# an accident.

const DELETE_ROW_PX := 52
const DELETE_CONFIRM_SECONDS := 3.0
const _COLOR_DELETE := Color(0.95, 0.5, 0.47)
const _COLOR_DELETE_CONFIRM := Color(1.0, 0.22, 0.18)

var _delete_btn: Button = null
var _delete_grown := false
## Seconds left on "Tap again to delete"; 0 when the row is not asking.
var _delete_confirm := 0.0


func _build_delete_row(box: BoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "DeleteRow"
	_delete_btn = Button.new()
	_delete_btn.custom_minimum_size = Vector2(0, 40)
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_btn.add_theme_font_override("font", MenuIcons.symbols())
	_delete_btn.pressed.connect(_on_delete_pressed)
	row.add_child(_delete_btn)
	box.add_child(row)
	if not _delete_grown:
		_delete_grown = true
		_grow_page(DELETE_ROW_PX)
	_delete_confirm = 0.0
	_set_delete_prompt(false)


func _on_delete_pressed() -> void:
	var target := _target_node()
	if not Trash.can_delete(target):
		return
	if _delete_confirm <= 0.0:
		_delete_confirm = DELETE_CONFIRM_SECONDS
		_set_delete_prompt(true)
		return
	print("[ObjectMenu] deleting '%s'" % target.name)
	hide_panel()
	# Nothing was let go of, so nothing drops: it shrinks away where it stands.
	Vanish.shrink_in_place(Trash.delete_with_dependents.bind(target as XRToolsPickable))


func _tick_delete_prompt(delta: float) -> void:
	if _delete_confirm <= 0.0:
		return
	_delete_confirm -= delta
	if _delete_confirm <= 0.0:
		_delete_confirm = 0.0
		_set_delete_prompt(false)


func _set_delete_prompt(asking: bool) -> void:
	if _delete_btn == null or not is_instance_valid(_delete_btn):
		return
	_delete_btn.text = "%s  %s" % [String.chr(MenuIcons.DELETE),
		"Tap again to delete" if asking else "Delete"]
	_delete_btn.add_theme_color_override("font_color",
		_COLOR_DELETE_CONFIRM if asking else _COLOR_DELETE)


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
func _grow_for_lock_row() -> void:
	if _lock_grown:
		return
	_lock_grown = true
	_grow_page(LOCK_ROW_PX)


## Make the page `px` viewport pixels taller (less, for a negative `px`) at the
## density it already has, so the text keeps its size. False when it could not.
##
## The quad and the collision box come out of the packed scene SHARED between
## every panel instance, so they are made unique first — writing screen_size
## without that resizes every other open menu's screen too.
func _grow_page(px: float) -> bool:
	var v := _viewport_2d()
	if v == null:
		return false
	var screen := v.get_node_or_null("Screen") as MeshInstance3D
	if screen == null or not (screen.mesh is QuadMesh):
		return false
	_own_screen_resources(v)
	var vp: Vector2 = v.viewport_size
	if vp.y <= 0.0 or vp.y + px <= 0.0:
		return false
	var grown := vp.y + px
	v.screen_size = Vector2(v.screen_size.x, v.screen_size.y * grown / vp.y)
	v.viewport_size = Vector2(vp.x, grown)
	_resize_place_grip()
	return true


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
# The mark sits on the BOTTOM-right corner, where the spawn menu's is and where a
# player looks for one, and the TOP edge stays where it is: drag down and the page
# grows down under the pointer, and the right edge follows it too, because the
# width grows about the centre by twice what the pointer moved. (It was the
# top-right with the bottom pinned, which kept a tall page clear of the object
# under it, and nobody found the grip there.)

## Arm length of the corner mark, its bar thickness, and its hit box — the spawn
## menu's (CurvedPanel.GRIP_*), so the two marks are recognisably one control. At
## 30 × 6 mm in grey this one was there and not seen.
const RESIZE_GRIP_ARM := 0.045
const RESIZE_GRIP_BAR := 0.008
const RESIZE_GRIP_HIT := 0.055
## How far past the corner the mark sits: its bar plus a hair, so it traces the
## outside of the corner rather than covering the page.
const RESIZE_GRIP_OUT := RESIZE_GRIP_BAR + 0.003
## The largest page, as a multiple of the size it had when first resized.
const RESIZE_MAX_SCALE := 2.5
## Every size change reallocates the SubViewport's render target, so a drag is
## quantised to this rather than doing it every frame.
const RESIZE_STEP_PX := 16.0
## Brighter than the spawn menu's idle grey: this mark stands against the room,
## not beside a wide lit panel, and the grey disappeared into it.
const _COLOR_GRIP_IDLE := Color(0.72, 0.76, 0.88)
const _COLOR_GRIP_HOVER := Color(1.0, 0.9, 0.6)
const _COLOR_GRIP_DRAG := Color(1.0, 0.78, 0.30)

var _screen_owned := false
var _resize_grip: PanelResizeGrip = null
var _resize_grip_mat: StandardMaterial3D = null
var _resize_hovered := false
## The smallest page, taken the first time it is resized: the authored size plus
## any lock row, which is as small as the layout inside was made to go.
var _resize_min_px := Vector2.ZERO
## How far the page has been moved (down, as it grows) to keep its top edge still.
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
	# On the page rather than on the panel, so it moves with the page as it grows.
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
	# Bars running LEFT along the bottom edge and UP the right one, from the corner.
	for r: Array in [[-a, b], [-b, a]]:
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
	# Outside the lower-right corner, following the page as it moves inside the
	# panel (_resize_lift).
	_resize_grip.position = Vector3(v.screen_size.x * 0.5 + RESIZE_GRIP_OUT,
		-v.screen_size.y * 0.5 - RESIZE_GRIP_OUT, 0.001)


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
	# World, not panel space: keeping clear of the object can raise the panel
	# mid-drag, and a start point in panel space would then move with it, read as
	# the pointer going further down, grow the page more, raise it more...
	_resize_from = global_transform * _resize_pointer_on_plane(pointer)
	_resize_from_screen = v.screen_size
	if _resize_grip_mat != null:
		_resize_grip_mat.albedo_color = _COLOR_GRIP_DRAG


func resize_end() -> void:
	_resize_pointer = null
	if _resize_grip_mat != null:
		_resize_grip_mat.albedo_color = _COLOR_GRIP_HOVER if _resize_hovered else _COLOR_GRIP_IDLE


## The pointer came onto or left the grip. Lit while it is there; a drag in
## progress keeps its own colour until it ends.
func resize_hover(on: bool) -> void:
	_resize_hovered = on
	if _resize_grip_mat != null and _resize_pointer == null:
		_resize_grip_mat.albedo_color = _COLOR_GRIP_HOVER if on else _COLOR_GRIP_IDLE


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
	# The pointer's travel in world space, read along the panel's own axes.
	var moved := global_transform * _resize_pointer_on_plane(_resize_pointer) - _resize_from
	var d := Vector2(moved.dot(global_basis.x.normalized()), moved.dot(global_basis.y.normalized()))
	var density := v.viewport_size / v.screen_size
	# Down is bigger: the grip is on the bottom edge.
	resize_page(Vector2(_resize_from_screen.x + d.x * 2.0,
		_resize_from_screen.y - d.y) * density)


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
	# Lowered by half the growth, so the top edge stays put and the page grows down.
	_resize_lift -= (screen.y - old_height) * 0.5
	v.position.y = _resize_rest_y + _resize_lift
	_resize_place_grip()
