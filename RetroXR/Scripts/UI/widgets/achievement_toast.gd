## AchievementToast — the RetroAchievements unlock popup, on the cabinet.
##
## The spawn menu's toast stack is parented to the menu panel, so it is invisible
## while somebody is actually playing — which is exactly when an unlock happens.
## This is its own quad, anchored to the machine that earned it, so with two
## cabinets running you can see which one popped.
##
## Built the way ToastPanel builds its quad, and it inherits two settings from
## there that were expensive to learn: SCISSOR rather than alpha blending (a
## blended Viewport2DIn3D quad measured 57 drawn pixels against 14787 with
## blending off), and a scale that makes an 18 pt line readable across the room
## rather than 9 mm tall.
class_name AchievementToast
extends Node3D

## Seconds a badge stays up. Long enough to read the title and look at the badge.
const DWELL := 6.0
## Metres above the screen's top edge.
const ABOVE_SCREEN := 0.06
## Metres above the hardware's crown, for a card anchored to the machine itself.
## Wider than ABOVE_SCREEN because what sticks up off a console is unpredictable —
## an NES flap standing open, a cartridge half out of the slot.
const ABOVE_MACHINE := 0.10
## Pixels per metre. ToastPanel's 1.7x over page scale, for the same reason.
const PIXELS_PER_METRE := 1400.0

const PANEL_W := 520.0
const PANEL_H := 132.0
## The tallest a card grows for a long message (a refused game names the core's own words, the files
## it wants and where they go). Past this the text is cut, which is a card taller than a person.
const PANEL_H_MAX := 900.0

## Trim colour per kind of card: gold for an unlock, red for a fault the player
## cannot fix from where they stand, orange for one they can (nothing in the
## slot) — the machine is fine, it is just waiting for something.
const ACCENT_UNLOCK := Color(1.0, 0.78, 0.24)
const ACCENT_NOTICE := Color(1.0, 0.42, 0.36)
const ACCENT_WAITING := Color(1.0, 0.60, 0.18)

var _viewport: XRToolsViewport2DIn3D = null
var _root: Control = null
var _queue: Array[Dictionary] = []
var _showing := false

## The screen this toast belongs to. Held rather than read from get_parent(),
## because the node is top_level and its parent is only a lifetime owner.
var _anchor: MeshInstance3D = null
## The machine this toast belongs to, when it hangs over the hardware instead of
## over a picture. Set by attach_to_machine; exclusive with _anchor. Typed Node3D
## rather than RetroSystem so this widget does not name a game object back.
var _machine: Node3D = null
## Placement is stale for one frame after a show; physics interpolation would
## otherwise lerp the quad in from wherever it last sat.
var _needs_interpolation_reset := false

## The card's height now: PANEL_H, or taller when the message needs it (see _fit_height).
var _panel_h := PANEL_H


## Attach a toast host to a cabinet. `screen` is the screen mesh it floats above,
## so the popup tracks a handheld picked up and carried.
static func attach(screen: MeshInstance3D) -> AchievementToast:
	if screen == null:
		return null
	var toast := AchievementToast.new()
	toast.name = "AchievementToast"
	toast._anchor = screen
	# Parented to the screen for lifetime — it should die with the machine — but
	# top_level, so none of the screen's transform reaches it. See _place().
	screen.add_child(toast)
	toast._build()
	return toast


## Attach a toast host to the hardware itself, floating over its crown.
##
## For anything the machine is waiting on rather than showing: the player who
## just pressed the power button is standing at the console, and a console cabled
## to a set on the other side of the room puts its picture where they are not.
## `machine` needs a `body_top_y()` (RetroSystem has one) or the card sits at its
## origin.
static func attach_to_machine(machine: Node3D) -> AchievementToast:
	if machine == null:
		return null
	var toast := AchievementToast.new()
	toast.name = "MachineToast"
	toast._machine = machine
	machine.add_child(toast)
	toast._build()
	return toast


func _build() -> void:
	# Instanced from the addon scene, not .new(): the SubViewport, mesh and
	# collision body are scene children.
	_viewport = load("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn") \
		.instantiate() as XRToolsViewport2DIn3D
	_viewport.name = "AchievementViewport"
	_viewport.update_mode = XRToolsViewport2DIn3D.UpdateMode.UPDATE_ALWAYS
	_viewport.transparent = XRToolsViewport2DIn3D.TransparancyMode.SCISSOR
	_viewport.unshaded = true
	# Nothing here is clickable, and a pointer-layer body floating in front of a
	# cabinet would block the controls behind it.
	_viewport.collision_layer = 0
	_viewport.viewport_size = Vector2(PANEL_W, PANEL_H)
	_viewport.screen_size = Vector2(PANEL_W, PANEL_H) / PIXELS_PER_METRE
	add_child(_viewport)

	# The screen mesh is not a safe transform to inherit. Its scale is what a
	# shell uses to size its tube (tv.gd:231), and tv.gd:445 tweens scale.y from
	# 0.02 to 1 as the CRT warms up — a child rides both, so the toast would be
	# sized by whatever cabinet it landed on and squashed during power-on.
	# top_level ignores the parent transform entirely; _place() then rebuilds the
	# world transform from the anchor with the scale stripped out.
	top_level = true
	set_process(false)
	visible = false


## Above the screen, centred on it, facing the same way, at a size that does not
## depend on the screen's scale.
##
## Everything is computed in WORLD space from the anchor. Two details matter:
## get_aabb() is the mesh resource's own extent and ignores node scale, so it has
## to be pushed through global_transform rather than multiplied by scale; and the
## basis is orthonormalized, which strips the scale so the quad keeps the physical
## size screen_size asked for.
func _place() -> void:
	# A machine whose hardware swallows a notice laid over it (a cabinet's tilted monitor and
	# marquee) names a spot of its own, detached in front of it.
	var spot: Variant = _detached_spot()
	if spot != null:
		_place_at(spot)
		return
	if _machine != null:
		_place_over_machine()
		return
	if not is_instance_valid(_anchor):
		return

	var xform := _anchor.global_transform
	var frame := xform.basis.orthonormalized()

	var top_centre := xform.origin
	if _anchor.mesh != null:
		var aabb := _anchor.get_aabb()
		# Top edge, centred on the mesh's own extent — a screen quad is not always
		# centred on its node origin.
		top_centre = xform * Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)

	# Clear of the bezel, then half the panel so the gap is to its bottom edge,
	# then a little proud of the screen plane so it never z-fights the picture.
	var offset := frame.y * (ABOVE_SCREEN + (_panel_h / PIXELS_PER_METRE) * 0.5) \
		+ frame.z * 0.01

	global_transform = Transform3D(frame, top_centre + offset)


## The machine's own spot for its notices, or null. Found by walking up from whatever this
## toast hangs on, so it works for both the screen toast and the machine toast.
func _detached_spot() -> Variant:
	var node: Node = _machine if _machine != null else _anchor
	while node != null:
		if node.has_method("toast_anchor_world"):
			return node.call("toast_anchor_world")
		node = node.get_parent()
	return null


## Float at `spot`: a Transform3D hangs exactly there (parallel to whatever it was taken from);
## a Vector3 is turned to face the player and kept level.
func _place_at(spot: Variant) -> void:
	# The spot is where a standard card's CENTRE goes: a taller card keeps its bottom edge there and
	# grows upward, so a long message does not sink into whatever the card floats in front of.
	var grow := (_panel_h - PANEL_H) * 0.5 / PIXELS_PER_METRE
	if spot is Transform3D:
		var xf := spot as Transform3D
		var frame := xf.basis.orthonormalized()
		global_transform = Transform3D(frame, xf.origin + frame.y * grow)
		return
	global_position = (spot as Vector3) + Vector3.UP * grow
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var flat := cam.global_position - global_position
	flat.y = 0.0
	if flat.length_squared() < 1e-6:
		return
	look_at(global_position + flat, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)


## Centred over the machine, its bottom edge clear of the hardware's crown, turned
## to face the player.
##
## A body has no picture plane to take a facing from, and a console can be sitting
## at any yaw in the room, so this billboards — the look_at-then-flip that puts the
## quad's +Z front toward the viewer, kept level rather than pitched at a headset
## looking down. The height comes from body_top_y() because the bodies differ by an
## order of magnitude: a PC tower is 0.42 m tall and a flat console around 0.07.
func _place_over_machine() -> void:
	if not is_instance_valid(_machine):
		return

	var top_y := _machine.global_position.y
	if _machine.has_method("body_top_y"):
		top_y = float(_machine.call("body_top_y"))
	var origin := _machine.global_position
	global_position = Vector3(origin.x,
		top_y + ABOVE_MACHINE + (_panel_h / PIXELS_PER_METRE) * 0.5,
		origin.z)

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var flat := cam.global_position - global_position
	flat.y = 0.0
	if flat.length_squared() < 1e-6:
		return
	look_at(global_position + flat, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)


## The screen this toast floats above. Callers compare it against their current
## screen target — plugging a video-out cable into a TV moves the picture, and a
## toast still hanging over the handheld's dark built-in panel is worse than none.
func anchor() -> MeshInstance3D:
	return _anchor if is_instance_valid(_anchor) else null


## Queue an unlock. Several can land close together (a boss kill often trips two
## or three), so they are shown one at a time rather than drawn over each other.
func show_unlock(title: String, description: String, points: int, badge: Texture2D) -> void:
	_queue.append({
		"heading": "Achievement unlocked  •  %d" % points,
		"accent": ACCENT_UNLOCK,
		"title": title,
		"description": description,
		"badge": badge,
	})
	if not _showing:
		_next()


## Queue a plain notice on the same card — no badge, no points, red trim.
##
## It rides here rather than on the TV's OSD because the OSD belongs to the set,
## and the machine that cannot run a game is as often a handheld with no set
## connected. Anchoring to the screen covers both: a cabinet's TV, or the
## built-in panel of a Lynx being held at the time.
func show_notice(heading: String, title: String, description: String,
				 accent: Color = ACCENT_NOTICE) -> void:
	_queue.append({
		"heading": heading,
		"accent": accent,
		"title": title,
		"title_color": accent,
		"description": description,
		"badge": null,
	})
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		visible = false
		# top_level means nothing else moves this node, so tracking only has to
		# run while something is on screen.
		set_process(false)
		return

	_showing = true
	var entry: Dictionary = _queue.pop_front()
	_render(entry)
	_place()
	_needs_interpolation_reset = true
	visible = true
	set_process(true)

	# Long enough to READ what is on it: a card for a refused game carries a paragraph.
	var words := str(entry.get("title", "")).length() + str(entry.get("description", "")).length()
	await get_tree().create_timer(dwell_for(words)).timeout
	# The cabinet may have been powered off or freed while the toast was up.
	if not is_inside_tree():
		return
	_next()


## Seconds a card with this many characters stays up: DWELL, and a second more per 40 characters
## past the first hundred, to 20.
static func dwell_for(characters: int) -> float:
	return minf(20.0, DWELL + maxf(0.0, float(characters - 100)) / 40.0)


## How tall a card has to be for these lines, at the card's own width. The text is measured with the
## theme's font and wrapped as the labels wrap it; a little is added for the difference between this
## and what the labels settle on, and _refine_height takes it from there.
static func height_for(title: String, description: String, has_badge: bool) -> float:
	var font := ThemeDB.fallback_font
	var inner := PANEL_W - 24.0 - 6.0 - (110.0 if has_badge else 0.0)
	var h := font.get_height(15)
	if not title.is_empty():
		h += font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, inner, 22).y
	if not description.is_empty():
		h += font.get_multiline_string_size(description, HORIZONTAL_ALIGNMENT_LEFT, inner, 15).y
	return clampf(h * 1.08 + 24.0 + 6.0 + 8.0, PANEL_H, PANEL_H_MAX)


## Size the card, the viewport that draws it and the quad that shows it to `h` pixels tall.
func _fit_height(h: float) -> void:
	_panel_h = h
	_viewport.viewport_size = Vector2(PANEL_W, h)
	_viewport.screen_size = Vector2(PANEL_W, h) / PIXELS_PER_METRE
	if is_instance_valid(_root):
		_root.custom_minimum_size = Vector2(PANEL_W, h)


## One frame after the card is laid out, grow it if the labels came out taller than the estimate.
func _refine_height() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_root) or not is_instance_valid(_viewport):
		return
	var needed := clampf(_root.get_combined_minimum_size().y, PANEL_H, PANEL_H_MAX)
	# The minimum includes the size this card was already given: only a label that wants more shows.
	var wanted := 0.0
	for label in _root.find_children("*", "Label", true, false):
		wanted += (label as Label).get_minimum_size().y
	wanted = clampf(wanted + 24.0 + 6.0 + 8.0, PANEL_H, PANEL_H_MAX)
	if maxf(needed, wanted) > _panel_h + 1.0:
		_fit_height(maxf(needed, wanted))


## Follow the machine. A cabinet is furniture but a handheld gets picked up and
## carried, and a top_level node does not inherit that movement for free.
func _process(_delta: float) -> void:
	var host: Node3D = _machine if _machine != null else _anchor
	if not is_instance_valid(host):
		visible = false
		set_process(false)
		return

	_place()

	if _needs_interpolation_reset:
		# The node has been sitting somewhere stale (or nowhere) since the last
		# toast. Without this the first frame lerps in from that pose.
		_needs_interpolation_reset = false
		reset_physics_interpolation()


func _render(entry: Dictionary) -> void:
	if is_instance_valid(_root):
		_root.queue_free()

	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var accent: Color = entry.get("accent", ACCENT_UNLOCK)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 1.0)
	style.border_color = accent
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	_root.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)

	var badge: Texture2D = entry.get("badge")
	if badge != null:
		var icon := TextureRect.new()
		icon.texture = badge
		icon.custom_minimum_size = Vector2(96, 96)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var heading := Label.new()
	heading.text = str(entry.get("heading", ""))
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", accent)
	text.add_child(heading)

	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.add_theme_font_size_override("font_size", 22)
	# An unlock's title is white against its gold heading; a notice carries the
	# fault itself on this line, so it takes the accent and the heading below
	# drops to naming the machine.
	title.add_theme_color_override("font_color", entry.get("title_color", Color(1, 1, 1)))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)

	var desc := Label.new()
	desc.text = str(entry.get("description", ""))
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)

	# Into the addon's SubViewport child, which is what actually renders — the
	# node itself is the Node3D holding the quad. This is the same place
	# viewport_2d_in_3d.gd puts its own `scene` instance.
	var sub := _viewport.get_node_or_null("Viewport") as SubViewport
	if sub == null:
		push_warning("AchievementToast: Viewport2DIn3D has no Viewport child")
		return
	sub.add_child(_root)
	_fit_height(height_for(str(entry.get("title", "")), str(entry.get("description", "")), badge != null))
	_refine_height()
