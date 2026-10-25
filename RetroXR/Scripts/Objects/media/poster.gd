## Poster — a user image hung on a wall or stuck to an object.
##
## The image comes from ~/retroxr/posters/ (RomLibrary.scan_posters). Spawned from
## the menu, carried, and stuck to whatever surface it is released against; a stuck
## poster rides the object it is stuck to.
##
## PNG alpha is supported, so a die-cut sticker is as valid as a rectangle. The
## material for one is TRANSPARENCY_ALPHA_SCISSOR rather than ALPHA: scissor renders
## in the OPAQUE pass and keeps writing depth, and a poster that stops writing depth
## sorts per-triangle against the wall behind it and against the next poster along.
## That is the same trap paper.gdshader documents. An image with no alpha at all is
## left fully opaque — alpha testing costs early-Z on a tile GPU, so the cheap case
## must stay cheap.
class_name Poster
extends XRToolsPickable

## How the sheet is fitted to the surface it is stuck to. FLAT is always the
## default: a mode that picks itself reads as a bug, and a wall — where most
## posters go — is flat anyway.
enum FitMode { FLAT, CONFORM, DECAL }

## Longest edge, in metres, at size_scale 1.0. The short edge follows the image's
## own aspect, so a poster is never stretched.
const BASE_LONG_EDGE := 0.5
## Decoded texture cap. A runtime image gets no ETC2/ASTC, so it is resident at
## full RGBA: 2048 square is 16 MB, and a phone-camera JPEG would be far worse.
const MAX_PX_DESKTOP := 2048
const MAX_PX_QUEST := 1024
## Print has no light of its own; this is the trace the room's own posters carry.
## 0.30 was measured too hot — see BedroomScene.tscn.
const EMISSION_ENERGY := 0.1

@export var image_path: String = "":
	set(value):
		image_path = value
		if is_inside_tree():
			_load_image()

@export_range(0.05, 3.0) var size_scale: float = 1.0:
	set(value):
		size_scale = clampf(value, SIZE_MIN, SIZE_MAX)
		if is_inside_tree():
			_apply_dimensions()

@export var fit_mode: FitMode = FitMode.FLAT

## In-plane spin on the surface, in degrees. Sticking squares a sheet up to
## world-up, which is the right first guess and a poor only option — a poster
## hung at a slant is a deliberate look, not a mistake.
@export_range(-180.0, 180.0) var roll_degrees: float = 0.0:
	set(value):
		roll_degrees = wrapf(value, -180.0, 180.0)
		if _stick != null:
			_stick.roll = deg_to_rad(roll_degrees)
			_stick.reapply_roll()
			# A conformed sheet was sampled through the old frame, so its wrap and
			# its UVs are both stale once it turns.
			if is_inside_tree() and fit_mode == FitMode.CONFORM:
				apply_fit()

## Whether letting go sticks it to the surface it is against. Off, it is a loose
## sheet that drops where it is let go — for a poster leant on a shelf or laid on a
## desk, which sticking would otherwise take off to the nearest wall. Default on:
## a wall is where most posters go.
@export var sticks: bool = true:
	set(value):
		sticks = value
		if _stick != null:
			_stick.enabled = value
		if not value:
			_end_preview()

@onready var _surface: Node3D = $Surface
@onready var _flat_mesh: MeshInstance3D = $Surface/FlatMesh
@onready var _body_shape: CollisionShape3D = $CollisionShape3D
@onready var _pointer_shape: CollisionShape3D = $PointerArea/CollisionShape3D
@onready var _ray: RayCast3D = $SurfaceRay
@onready var _options_panel: PosterOptionsPanel = $PosterOptionsPanel

var _stick: SurfaceStick = null
## Set from a save before _ready, so a restored poster re-parks itself instead of
## dropping off the wall while the room finishes loading.
var stuck_from_save := false
## A print torn off the Game Boy Printer: loose, it bends as paper
## (GbPrintoutFlop). Set before the tree, as a save or the printer does.
var printout := false
## Something drawing the hover rim itself (GbPrintoutFlop: a print bent as
## paper, which the flat rim behind it covered instead of outlined): told when
## to show it through show_outline(on), the flat rim staying hidden.
var outline_drawn_by: Object = null
## Set while a ray-held resize is in progress, so the sheet can be re-fitted once.
var _resized_while_held := false
var _conform_mesh: MeshInstance3D = null
var _conform_arraymesh: ArrayMesh = null

## Image aspect (width / height). 1.0 until an image loads.
var _aspect: float = 1.0
var _texture: Texture2D = null


func _ready() -> void:
	super._ready()
	add_to_group("poster")
	_stick = SurfaceStick.attach(self, _ray)
	_stick.roll = deg_to_rad(roll_degrees)
	_stick.enabled = sticks
	# Keep the exported angle in step when a landing adopts one, so the menu reads
	# right and the save records what is actually on the wall.
	_stick.roll_inherited.connect(func(deg: float) -> void: roll_degrees = deg)
	_stick.stuck_changed.connect(func(_t: Node3D) -> void:
		_end_preview()
		apply_fit())
	_find_vr_nodes.call_deferred()
	if GbPrintoutFlop.is_printout(self):
		GbPrintoutFlop.attach(self)
	_build_outline()
	_build_hint()
	highlight_updated.connect(_on_highlight)
	# A grab IS the peel: every hold restores `freeze` itself, so there is no
	# separate verb and nothing to teach.
	picked_up.connect(func(_p: Node3D) -> void: _stick.peel(true))
	if not image_path.is_empty():
		_load_image()
	else:
		_apply_dimensions()
	if stuck_from_save:
		# Deferred twice over: the body has not reached its restored pose at
		# _ready, and the restore's own _let_go hands gravity back to everything
		# it froze a pass later.
		_repark_after_restore.call_deferred()


## True while the sheet is committed to a surface.
func is_stuck() -> bool:
	return _stick != null and _stick.is_stuck()


func stick_target() -> Node3D:
	return _stick.target if _stick != null else null


## A restored poster comes back at its saved WORLD pose, parented to the room —
## not under the host it was riding, because the walk that saves it is over the
## "spawned" group and _base() records a global transform.
##
## So it re-probes rather than restoring a reference: the surface it was stuck to
## has been restored to its own saved pose too, and the sheet still sits 2 mm off
## it, so the same short ray that stuck it the first time finds it again. That also
## self-heals when the room changed underneath the save, where a stored reference
## would only be able to fail.
func _repark_after_restore() -> void:
	if _stick == null:
		return
	_stick.try_stick()


## Metres, as currently sized. Width first.
func get_sheet_size() -> Vector2:
	var long_edge := BASE_LONG_EDGE * size_scale
	if _aspect >= 1.0:
		return Vector2(long_edge, long_edge / _aspect)
	return Vector2(long_edge * _aspect, long_edge)


# ── Image ─────────────────────────────────────────────────────────────────────

## Decode the user's file and build the sheet's material.
##
## A file dropped in the posters folder never passes through Godot's import
## pipeline, so the three things an imported texture would have arrived with have
## to be done by hand here: a size cap, mipmaps, and an alpha-edge fix.
func _load_image() -> void:
	_texture = null
	if not image_path.is_empty():
		var img := Image.load_from_file(image_path)
		if img == null:
			push_warning("Poster: cannot read image '%s'" % image_path)
		else:
			var cap := MAX_PX_DESKTOP if QualityManager.is_desktop() else MAX_PX_QUEST
			_fit_within(img, cap)
			var alpha := img.detect_alpha()
			if alpha != Image.ALPHA_NONE:
				# Bleeds colour into fully transparent texels. Without it, mip
				# averaging pulls their (often black) RGB into the cut edge and the
				# sticker wears a dark fringe — and the emission pass would print
				# that fringe a second time.
				img.fix_alpha_edges()
			img.generate_mipmaps()
			_texture = ImageTexture.create_from_image(img)
			_aspect = float(img.get_width()) / maxf(1.0, float(img.get_height()))
			var mat := _build_material(_texture, alpha)
			if GbPrintoutFlop.is_printout(self):
				# A print is thermal paper, printed on its face only. Its margin is
				# bare paper (GbPrinterPaper.sheet), the color of the back.
				mat.cull_mode = BaseMaterial3D.CULL_BACK
				mat.next_pass = _bare_back(img.get_pixel(0, 0))
			_flat_mesh.set_surface_override_material(0, mat)
			if _outline != null:
				(_outline.material_override as ShaderMaterial).set_shader_parameter(
					"poster_tex", _texture)
	_apply_dimensions()


func _build_material(tex: Texture2D, alpha: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.9
	# A sheet has no back worth culling, and a poster on a pillar is read from both
	# sides of the doorway.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if alpha != Image.ALPHA_NONE:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = EMISSION_ENERGY
	return mat


## A print's back: the bare paper, a shade darker as the strip's back is on the
## printer (gb_printer_paper.gdshader). It draws the faces the picture culls.
static func _bare_back(paper: Color) -> StandardMaterial3D:
	var back := StandardMaterial3D.new()
	back.cull_mode = BaseMaterial3D.CULL_FRONT
	back.albedo_color = Color(paper.r * 0.93, paper.g * 0.93, paper.b * 0.93)
	back.roughness = 0.9
	back.emission_enabled = true
	back.emission = back.albedo_color
	back.emission_energy_multiplier = EMISSION_ENERGY
	return back


## Aspect-preserving downscale to a square bound. One scalar in, both edges out —
## which is also why size_scale cannot stretch a poster.
static func _fit_within(img: Image, cap: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or (w <= cap and h <= cap):
		return
	var factor: float = minf(float(cap) / float(w), float(cap) / float(h))
	img.resize(maxi(1, int(round(w * factor))), maxi(1, int(round(h * factor))),
		Image.INTERPOLATE_LANCZOS)


# ── Dimensions ────────────────────────────────────────────────────────────────

## The one place the sheet's size is written. Everything that has to agree with it
## — the quad, the body's collider and the pointer target — is set from the same
## two numbers, so none of them can drift apart.
func _apply_dimensions() -> void:
	if _flat_mesh == null:
		return
	var size := get_sheet_size()
	var quad := _flat_mesh.mesh as QuadMesh
	if quad != null:
		quad.size = size
	# 2 mm of thickness: enough for a grab and for the pointer to find, thin enough
	# that a poster flat against a wall does not read as a board.
	var box := _body_shape.shape as BoxShape3D
	if box != null:
		box.size = Vector3(size.x, size.y, 0.002)
	if _outline != null:
		(_outline.mesh as QuadMesh).size = size * OUTLINE_GROW
	var ptr := _pointer_shape.shape as BoxShape3D
	if ptr != null:
		# Slightly proud of the sheet so aiming at a poster is not a pixel hunt.
		ptr.size = Vector3(size.x + 0.02, size.y + 0.02, 0.02)


# ── Resizing while ray-held ───────────────────────────────────────────────────
#
# While a poster is held at the end of a laser, the OPPOSITE controller already
# rotates it — xr-tools reads that hand's stick for yaw/pitch and its grip for roll
# (XRToolsFunctionPickup._compute_ray_grab_rotation). Size goes on the same hand's
# face buttons, A/X to grow and B/Y to shrink.
#
# Buttons rather than an axis, deliberately: that hand's stick is spoken for by the
# rotation, and the HOLDING hand's stick drives locomotion. Using neither means a
# poster needs no locomotion block at all — and so cannot hit the ordering trap
# where a menu-spawned object is handed to the grabber before its deferred node
# lookup has resolved the locomotion manager, and the block is silently dropped.

## Full size range, in multiples of BASE_LONG_EDGE. A postcard to a door.
## 0.05 is a 25 mm sticker on the 0.5 m sheet — small enough to badge a console
## rather than cover it.
const SIZE_MIN := 0.05
const SIZE_MAX := 3.0
## Multiples per second while a button is held.
const RESIZE_SPEED := 0.6

var _left_ctrl: XRController3D = null
var _right_ctrl: XRController3D = null
var _ctrls_found := false


func _process(delta: float) -> void:
	var holder := _ray_holder() if _ctrls_found else null
	# Remember where the beam is pointing for as long as it holds the sheet. The
	# release itself is silent on this path (no `dropped`), and by the time the
	# stick runs the grab is already over — so the aim has to be kept, not asked
	# for afterwards.
	if holder != null and _stick != null:
		set_aim_direction(-holder.global_transform.basis.z)
		# A beam grab emits nothing on the pickable — no `picked_up`, no
		# `dropped` — so a stuck poster has to notice the beam itself, or it
		# stays parented to the wall while the laser drags it around.
		if is_stuck():
			_stick.peel(true)
	# Preview whenever something is HOLDING it and it is not already stuck.
	# `freeze` is the predicate every hold sets — hand, snap zone and beam alike —
	# so this shows the landing for a hand placement too, and it does not depend
	# on a controller being found.
	_update_preview(delta, sticks and freeze and not is_stuck())
	_desktop_resize(delta)
	_refresh_outline()
	var rotator := _rotating_controller_for(holder)
	if rotator == null:
		return
	var step := 0.0
	if rotator.is_button_pressed("ax_button"):
		step += RESIZE_SPEED * delta
	if rotator.is_button_pressed("by_button"):
		step -= RESIZE_SPEED * delta
	if is_zero_approx(step):
		return
	var before := size_scale
	size_scale = clampf(size_scale + step, SIZE_MIN, SIZE_MAX)
	if is_equal_approx(before, size_scale):
		return
	_resized_while_held = true


## The hand that is NOT holding this poster on its laser, or null when no laser
## holds it. That is the hand xr-tools already gives the rotation to, so size and
## rotation stay on one controller and the other simply aims.
func _rotating_controller_for(holder: XRController3D) -> XRController3D:
	if holder == null:
		return null
	return _right_ctrl if holder == _left_ctrl else _left_ctrl


func _ray_holder() -> XRController3D:
	for ctrl: XRController3D in [_left_ctrl, _right_ctrl]:
		if not is_instance_valid(ctrl):
			continue
		for child in ctrl.get_children():
			if child.has_method("is_ray_grabbing_target") \
					and child.call("is_ray_grabbing_target", self):
				return ctrl
	return null


func _find_vr_nodes() -> void:
	for node: Node in get_tree().root.find_children("*", "XRController3D", true, false):
		var ctrl := node as XRController3D
		if ctrl == null:
			continue
		if ctrl.tracker == &"left_hand":
			_left_ctrl = ctrl
		elif ctrl.tracker == &"right_hand":
			_right_ctrl = ctrl
	_ctrls_found = true


# ── Fit modes ─────────────────────────────────────────────────────────────────
#
# The stored mode and the displayed geometry are deliberately separate. A poster
# in a hand, or lying on the floor, always renders FLAT however fit_mode is set;
# the wrapped mesh is only built once the sheet is committed to a surface. That
# one rule removes conforming to nothing and conforming to a moving hand.

## Refit the sheet for the mode it is in and the surface it is on. Safe to call
## when nothing is stuck: it just puts the flat quad back.
func apply_fit() -> void:
	if not is_stuck() or fit_mode == FitMode.FLAT:
		_show_flat()
		return
	if fit_mode == FitMode.CONFORM:
		_build_conform()


func set_sticks(on: bool) -> void:
	if on == sticks:
		return
	sticks = on
	print("[Poster] %s: sticking %s%s" % [name, "on" if on else "off",
		" (stays where it is until picked up)" if is_stuck() and not on else ""])


func set_fit_mode(mode: FitMode) -> void:
	if mode == fit_mode:
		return
	fit_mode = mode
	apply_fit()


func _show_flat() -> void:
	if _conform_mesh != null:
		_conform_mesh.queue_free()
		_conform_mesh = null
	_flat_mesh.visible = true


## Sample the host and swap the quad for the wrapped sheet.
##
## Once per stick — not per frame. The cook plus a few hundred rays plus a mesh
## upload is affordable as a one-shot and is a hitch every frame otherwise, and a
## hitch in VR is a comfort problem rather than a frame-rate one.
func _build_conform() -> void:
	var host := stick_target()
	if host == null:
		_show_flat()
		return
	var built: Dictionary = await PosterConform.build(
		host, global_transform, get_sheet_size(), get_tree(), self)
	if not is_instance_valid(self):
		return
	if built.is_empty():
		# No usable surface — a wall, a crude collider, or too much of the sheet
		# hanging off the edge. Flat is the honest answer, not a mangled mesh.
		_show_flat()
		return
	if _conform_mesh == null:
		_conform_mesh = MeshInstance3D.new()
		_conform_mesh.name = "ConformMesh"
		_surface.add_child(_conform_mesh)
	if _conform_arraymesh == null:
		_conform_arraymesh = ArrayMesh.new()
	# Refilled in place rather than replaced, so the material override and the
	# MeshInstance's own RID survive a refit.
	_conform_arraymesh.clear_surfaces()
	_conform_arraymesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, built["arrays"] as Array)
	_conform_mesh.mesh = _conform_arraymesh
	_conform_mesh.set_surface_override_material(
		0, _flat_mesh.get_surface_override_material(0))
	_flat_mesh.visible = false
## The contextual options menu. The controller detects a host by type and then
## calls this unconditionally, so a poster registered in those chains MUST have it.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


## Take it off the surface without picking it up — the menu's own verb, for a
## poster that is out of reach.
func peel() -> void:
	if _stick != null:
		_stick.peel()
	_show_flat()


## Where the holder is aiming, for the laser placement path. A print is placed
## only when brought to the surface (SurfaceStick.aim_reach).
func set_aim_direction(dir: Vector3) -> void:
	if _stick != null:
		_stick.aim_direction = dir
		_stick.aim_reach = SurfaceStick.REACH if printout else SurfaceStick.AIM_REACH


# ── Hover outline ─────────────────────────────────────────────────────────────
#
# A border quad rather than PickableHighlight's inverted hull. Two reasons: that
# highlight only walks its parent's DIRECT children and the sheet lives one level
# down under Surface, and inflating a single-sided sheet along its normals gives a
# doubled ghost instead of a rim. A flat border is what a sheet's outline IS.

const OUTLINE_COLOR := Color(1.0, 0.85, 0.30)
## How far the rim stands proud, as a FRACTION of the sheet rather than a fixed
## number of millimetres. Absolute was wrong once posters could go down to 0.05x:
## 45 mm of margin on a 25 mm sticker is a rim wider than the art it outlines.
const OUTLINE_GROW := 1.025

var _outline: MeshInstance3D = null
var _highlight_requested := false


const OUTLINE_SHADER := preload("res://Shaders/poster_outline.gdshader")


func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.name = "HoverOutline"
	_outline.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("rim_color", OUTLINE_COLOR)
	mat.set_shader_parameter("cutoff", 0.5)
	_outline.material_override = mat
	# A hair behind the sheet, so the enlarged silhouette shows as a rim around it
	# rather than a panel over the art.
	_outline.position = Vector3(0, 0, -0.0015)
	_outline.visible = false
	_surface.add_child(_outline)


func _on_highlight(_p: Node3D, on: bool) -> void:
	_highlight_requested = on
	_refresh_outline()


## The rim shows while something is pointing at the sheet — and while something is
## HOLDING it, which is the same thing from the player's side and is not covered
## by the highlight alone: both the hand and the beam explicitly drop the
## highlight at pick-up ("the object transitions from highlighted to held"), so a
## poster went dark exactly while it was the thing being aimed and moved.
##
## Deliberately not gated on being stuck: a loose poster in the air is the case
## where knowing what you have hold of matters most.
func _refresh_outline() -> void:
	if _outline == null:
		return
	var want := _highlight_requested or (freeze and not is_stuck())
	if outline_drawn_by != null and is_instance_valid(outline_drawn_by):
		_outline.visible = false
		outline_drawn_by.call("show_outline", want)
		return
	_outline.visible = want


# ── Placement preview ─────────────────────────────────────────────────────────
#
# While a beam holds the sheet and a surface is in reach, the ARTWORK slides to
# where it would land and a sticker glyph shows above it. The body itself is left
# alone: the ray grab writes its transform every frame and a preview that fought
# that would stutter. Detaching the visual instead is the same trick RetroMouse
# uses to lie its shell on a desk while the body follows the hand.

## Metres per second the preview closes the gap. Fast enough to feel attached to
## the aim, slow enough to read as a move rather than a jump.
const PREVIEW_LERP := 14.0
const HINT_GLYPH_M := 0.10
const HINT_RASTER := 48

var _hint: Label3D = null
var _previewing := false


func _build_hint() -> void:
	_hint = Label3D.new()
	_hint.name = "StickHint"
	_hint.font = TransportGlyphs.font()
	_hint.font_size = HINT_RASTER
	_hint.pixel_size = HINT_GLYPH_M / float(HINT_RASTER)
	_hint.text = TransportGlyphs.glyph("sticker")
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.modulate = OUTLINE_COLOR
	_hint.visible = false
	add_child(_hint)


## Show — or stop showing — where this would land if let go now.
func _update_preview(delta: float, active: bool) -> void:
	var hit: Dictionary = _stick.predict() if (active and _stick != null) else {}
	if hit.is_empty():
		_end_preview()
		return
	var pose: Transform3D = _stick.pose_for(hit)
	if not _previewing:
		_previewing = true
		# top_level so the sheet stops inheriting the body the beam is dragging.
		_surface.top_level = true
		_surface.global_transform = global_transform
	var t: float = clampf(delta * PREVIEW_LERP, 0.0, 1.0)
	_surface.global_transform = _surface.global_transform.interpolate_with(pose, t)
	_hint.visible = true
	_hint.global_position = pose.origin + pose.basis.z.normalized() * 0.06 \
		+ Vector3.UP * (get_sheet_size().y * 0.5 + 0.05)


func _end_preview() -> void:
	if _previewing:
		_previewing = false
		_surface.top_level = false
		_surface.transform = Transform3D.IDENTITY
	if _hint != null:
		_hint.visible = false


## Whether the sheet is drawn at its landing now rather than in the hand. A
## print's flop shows the flat sheet while this holds, since the preview is the
## sticker on the wall and not the paper being carried.
func is_previewing() -> bool:
	return _previewing


## Where this would land if let go now, and the pose it would take there. The
## preview draws from these, so anything checking the preview checks the commit.
func predict_stick() -> Dictionary:
	return _stick.predict() if _stick != null else {}


func pose_for_stick(hit: Dictionary) -> Transform3D:
	return _stick.pose_for(hit) if _stick != null else Transform3D.IDENTITY


# ── Resizing on desktop ───────────────────────────────────────────────────────
#
# Q shrinks, E grows, while the poster is held. The VR gesture is the face buttons
# on the rotating hand (see above); a desk has no second controller, and the mouse
# wheel is already the reticle's own scroll.

const KEY_GROW := KEY_E
const KEY_SHRINK := KEY_Q


func _desktop_resize(delta: float) -> void:
	if not freeze or is_stuck():
		return
	# Not while a text field has focus, or naming a save slot resizes whatever is
	# in your hand. The typing guard suspends scroll and movement for the same
	# reason; a focused LineEdit is the same question asked directly.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var step := 0.0
	if Input.is_physical_key_pressed(KEY_GROW):
		step += RESIZE_SPEED * delta
	if Input.is_physical_key_pressed(KEY_SHRINK):
		step -= RESIZE_SPEED * delta
	if is_zero_approx(step):
		return
	size_scale = clampf(size_scale + step, SIZE_MIN, SIZE_MAX)


## Turn the sheet in the plane of whatever it is on. The menu's two arrows.
const ROLL_STEP := 15.0


func rotate_cw() -> void:
	roll_degrees += ROLL_STEP


func rotate_ccw() -> void:
	roll_degrees -= ROLL_STEP
