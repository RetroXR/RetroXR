## ArcadeScreenModule — the cabinet's monitor.
##
## Paints the quad it finds (`CabinetScreen`) with the core's picture, fitted INSIDE
## the glass by the shape the core reports. The fit comes from the libretro bridge's
## video geometry (Libretro.GetVideoGeometry), never from the texture's size:
## arcade pixels are not square (CPS1 is 384x224 on a 4:3 tube) and a vertical game
## arrives as a portrait frame, which a fixed-aspect screen would stretch.
##
## A build of the extension that has no GetVideoGeometry (a platform not rebuilt yet)
## falls back to the orientation of the frame and the monitor's own shape, which is
## right for every arcade tube that was ever made, and says so once.
class_name ArcadeScreenModule
extends ArcadeModule

const SHADER := preload("res://Shaders/arcade_screen.gdshader")

## The visible glass in metres, width x height as the quad is seen from the front.
@export var glass_size: Vector2 = Vector2(0.38, 0.285)
## Scanline strength handed to the shader; 0 turns them off.
@export_range(0.0, 1.0) var scanlines: float = 0.22
## A game whose second screen is the scope's (Silent Scope, `ArcadeCabinetSpecs.scope_of`): the part of the core's frame the MONITOR shows and the
## part the scope's lens does, as fractions of it, y down, and the frame's shape the table expects. Empty = the whole frame on the monitor and no
## lens. The cut is made only while the core's frame really is that shape (a different layout, the player's own artwork, would put other things there).
@export var main_part: Rect2 = Rect2()
@export var scope_part: Rect2 = Rect2()
@export var scope_frame_aspect: float = 0.0
## A rifle game of ONE screen (Golgo 13, Silent Scope EX) has no second screen to put in the scope: its scope is DIGITAL (> 1: how many times it magnifies).
## The monitor shows the whole frame, and the lens the part of it the rifle points at, magnified: the aim is the gun's own (`last_aim`, -0x7fff..0x7fff, y down),
## so the picture in the eyepiece is where the barrel is. 0 = no digital scope.
@export var scope_zoom: float = 0.0
## For the tests and the probe: the frame's shape as if the core had reported it (> 0), instead of asking the core.
var aspect_override: float = 0.0

var _screen: MeshInstance3D = null
var _material: ShaderMaterial = null
var _off_material: StandardMaterial3D = null

var _serial: int = -1
var _geometry_aspect: float = 0.0
var _content_aspect: float = 0.0
## The lens in the rifle's scope (the rifle's `ScopeScreen` quad), found by name among the machine's guns, its materials, and whether the cut is
## being made now.
var _lens: MeshInstance3D = null
var _lens_material: ShaderMaterial = null
var _lens_off: StandardMaterial3D = null
var _lens_search := 0.0
var _cut := false
var _applied_aspect := -1.0
var _applied_part := Rect2()
## The game's own bezel round the picture (set_bezel), or null.
var _bezel: MeshInstance3D = null
var _warned_fallback: bool = false
var _last_fit: Vector2 = Vector2.ONE


func _init() -> void:
	kind = ArcadeProfiles.KIND_SCREEN


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_screen = find_child("CabinetScreen", true, false) as MeshInstance3D
	_off_material = StandardMaterial3D.new()
	_off_material.albedo_color = Color(0.015, 0.017, 0.02)
	_off_material.roughness = 0.12
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("scanlines", scanlines)
	if _screen != null:
		_screen.set_surface_override_material(0, _off_material)
	_lens_off = _off_material.duplicate() as StandardMaterial3D
	_lens_material = ShaderMaterial.new()
	_lens_material.shader = SHADER
	_lens_material.set_shader_parameter("scanlines", 0.0)


func get_screen() -> MeshInstance3D:
	return _screen


# ── the game's bezel ────────────────────────────────────────────────────────

## How far behind the glass the bezel hangs: in front of the tube, behind the pane.
const BEZEL_Z := -0.010
const FRAME_PARTS: Array[String] = ["FrameSideL", "FrameSideR", "FrameTop", "FrameBottom"]


## Hang the game's bezel (ArcadeBezel) round the tube, or take it down (`tex` null). `hole` is where the screen
## is in the picture (0..1, y down): the picture is scaled so the hole holds the whole tube, centred on it, and
## cut to the monitor's opening (what the cabinet shows between its sides, the glass's slanted edge). The black
## frame round the glass makes way for it while it hangs.
func set_bezel(tex: Texture2D, hole: Rect2) -> void:
	if _bezel != null:
		_bezel.queue_free()
		_bezel = null
	var hang := tex != null and _screen != null and hole.size.x > 0.0 and hole.size.y > 0.0
	for n in FRAME_PARTS:
		var part := find_child(n, false, false) as Node3D
		if part != null:
			part.visible = not hang
	if not hang:
		return
	var tube := (_screen.mesh as QuadMesh).size
	var rect := bezel_rect(Vector2(tex.get_size()), hole, tube, Vector2(_screen.position.x, _screen.position.y))
	var shown := rect.intersection(opening())
	if shown.size.x <= 0.0 or shown.size.y <= 0.0:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# The part of the picture the opening shows (the plane's y runs up, the picture's down).
	var u0 := (shown.position.x - rect.position.x) / rect.size.x
	var u1 := (shown.end.x - rect.position.x) / rect.size.x
	var v0 := 1.0 - (shown.end.y - rect.position.y) / rect.size.y
	var v1 := 1.0 - (shown.position.y - rect.position.y) / rect.size.y
	m.uv1_scale = Vector3(u1 - u0, v1 - v0, 1.0)
	m.uv1_offset = Vector3(u0, v0, 0.0)
	_bezel = MeshInstance3D.new()
	_bezel.name = "GameBezel"
	var quad := QuadMesh.new()
	quad.size = shown.size
	_bezel.mesh = quad
	_bezel.material_override = m
	_bezel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bezel)
	_bezel.position = Vector3(shown.get_center().x, shown.get_center().y, BEZEL_Z)


## The game's bezel hanging now, or null (the tests, the probe).
func bezel() -> MeshInstance3D:
	return _bezel


## Where a bezel picture of `image_size` pixels stands in the monitor's plane when its `hole` (0..1, y down) holds
## the whole tube (`tube` metres, its middle at `tube_center`): scaled alike on both axes, so a hole of another
## shape than the tube shows a margin rather than covering the picture. Pure, for the tests.
static func bezel_rect(image_size: Vector2, hole: Rect2, tube: Vector2, tube_center: Vector2) -> Rect2:
	var hole_px := hole.size * image_size
	var k := maxf(tube.x / hole_px.x, tube.y / hole_px.y)
	var full := image_size * k
	var hole_mid := (hole.position + hole.size * 0.5) * image_size
	# The picture's middle from the hole's, in metres, y up.
	var off := Vector2((image_size.x * 0.5 - hole_mid.x) * k, -(image_size.y * 0.5 - hole_mid.y) * k)
	return Rect2(tube_center + off - full * 0.5, full)


## The monitor's opening in its own plane: the board behind the tube, as wide as the cabinet between its sides and
## as tall as the glass's slanted edge.
func opening() -> Rect2:
	var board := find_child("Bezel", false, false) as MeshInstance3D
	if board != null and board.mesh is BoxMesh:
		var size := (board.mesh as BoxMesh).size
		return Rect2(Vector2(board.position.x, board.position.y) - Vector2(size.x, size.y) * 0.5, Vector2(size.x, size.y))
	return Rect2(-glass_size * 0.75, glass_size * 1.5)


## How much of the glass a picture of `content_aspect` (width / height of what is to
## be SEEN) covers on each axis; (1, 1) fills it. Whatever is left is black bar:
## pillars for a picture narrower than the glass, bars above and below for wider.
## Zero or less means "not known": fill the glass.
static func fit_for(content_aspect: float, glass: Vector2) -> Vector2:
	if not (content_aspect > 0.0) or glass.x <= 0.0 or glass.y <= 0.0:
		return Vector2.ONE
	var glass_aspect := glass.x / glass.y
	if is_equal_approx(content_aspect, glass_aspect):
		return Vector2.ONE
	if content_aspect > glass_aspect:
		return Vector2(1.0, glass_aspect / content_aspect)
	return Vector2(content_aspect / glass_aspect, 1.0)


## The shape to show a frame in when the bridge gives no geometry: the monitor's own
## 4:3, turned on its side for a portrait frame. Not the frame's pixel ratio, which
## is wrong for arcade video.
static func fallback_aspect(frame_size: Vector2) -> float:
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return 0.0
	return 3.0 / 4.0 if frame_size.y > frame_size.x else 4.0 / 3.0


func tick(delta: float) -> void:
	if _screen == null or cabinet == null:
		return
	var tex: Texture2D = null if cabinet.host_picture_on_tv() else cabinet.host_picture()
	if tex == null:
		if _screen.get_surface_override_material(0) != _off_material:
			_screen.set_surface_override_material(0, _off_material)
		_serial = -1
		_cut = false
		_update_lens(null, delta)
		return
	var external := cabinet.has_method("external_picture_active") and bool(cabinet.call("external_picture_active"))
	var attract := cabinet.has_method("attract_picture_active") and bool(cabinet.call("attract_picture_active"))
	present(tex, external, attract, delta)


## Show a picture: bind it to the tube, fit it to the glass (cut out of the frame for a scope game) and feed the scope's lens with the other half.
## What `tick` does once it has a picture; the tests call it with one.
func present(tex: Texture2D, external: bool, attract: bool, delta: float) -> void:
	if _material.get_shader_parameter("source_tex") != tex:
		_material.set_shader_parameter("source_tex", tex)
	if _screen.get_surface_override_material(0) != _material:
		_screen.set_surface_override_material(0, _material)
	_refresh_geometry(tex, external, attract)
	# A digital scope shows the game running (not its video snap on show, nor a cord from another machine): a real frame.
	var digital := scope_zoom > 1.0 and not external and not attract
	_update_lens(tex if (_cut or digital) else null, delta)


func _refresh_geometry(tex: Texture2D, external: bool = false, attract: bool = false) -> void:
	var lib: Object = _libretro()
	var aspect := 0.0
	_cut = false
	if attract:
		# The game on show, not running: a video snap or a still, whose shape is its own.
		_serial = -1
		_content_aspect = float(tex.get_width()) / float(maxi(tex.get_height(), 1))
		_apply_fit(_content_aspect, Rect2(0.0, 0.0, 1.0, 1.0))
		return
	if external:
		# A machine cabled to the bay: the board's geometry says nothing about this picture.
		_serial = -1
		_content_aspect = fallback_aspect(Vector2(tex.get_size()))
		_apply_fit(_content_aspect, Rect2(0.0, 0.0, 1.0, 1.0))
		return
	if aspect_override > 0.0:
		aspect = aspect_override
	elif lib != null and lib.has_method("GetVideoGeometrySerial"):
		var serial: int = lib.GetVideoGeometrySerial()
		if serial == _serial and _geometry_aspect > 0.0:
			aspect = _geometry_aspect
		else:
			_serial = serial
			var geom: Dictionary = lib.GetVideoGeometry()
			aspect = float(geom.get("aspect", 0.0))
	else:
		if not _warned_fallback:
			_warned_fallback = true
			push_warning("[arcade] this libretro-godot build has no GetVideoGeometry; "
				+ "the monitor takes its shape from the frame's orientation")
	if not (aspect > 0.0):
		aspect = fallback_aspect(Vector2(tex.get_size()))
	_geometry_aspect = aspect
	# The monitor shows its screen cut out of the frame, while the frame is the shape the table says: then the scope has the other.
	_cut = crop_applies(aspect, scope_frame_aspect) and main_part.has_area() and scope_part.has_area()
	if _cut:
		_content_aspect = aspect * main_part.size.x / main_part.size.y
		_apply_fit(_content_aspect, main_part)
	else:
		_content_aspect = aspect
		_apply_fit(aspect, Rect2(0.0, 0.0, 1.0, 1.0))


func _apply_fit(aspect: float, part: Rect2) -> void:
	# Only when something changed: this runs every frame and a material parameter set is not free.
	if is_equal_approx(aspect, _applied_aspect) and part.is_equal_approx(_applied_part):
		return
	_applied_aspect = aspect
	_applied_part = part
	_last_fit = fit_for(aspect, glass_size)
	_material.set_shader_parameter("fit_scale", _last_fit)
	_material.set_shader_parameter("view_rect", Vector4(part.position.x, part.position.y, part.size.x, part.size.y))


## Whether a frame of the shape the core reports is the one the table's layout expects, within a few percent (the core rounds its aspect): the
## cut is only made then, so a layout the table did not foresee shows the whole frame on the monitor instead of the wrong part of it.
static func crop_applies(reported: float, expected: float) -> bool:
	return reported > 0.0 and expected > 0.0 and absf(reported - expected) <= expected * 0.04


# ── the scope's lens ────────────────────────────────────────────────────────

const LENS_NODE := "ScopeScreen"


## Show the scope's screen on the lens in the rifle's scope (`tex`: the core's frame), or put it out (null).
func _update_lens(tex: Texture2D, delta: float) -> void:
	if not scope_part.has_area() and not scope_zoom > 1.0:
		return
	if _lens == null or not is_instance_valid(_lens):
		_lens = null
		_lens_search -= delta
		if _lens_search > 0.0:
			return
		_lens_search = 1.0
		_lens = _find_lens()
		if _lens == null:
			return
	if tex == null:
		if _lens.get_surface_override_material(0) != _lens_off:
			_lens.set_surface_override_material(0, _lens_off)
		return
	if _lens_material.get_shader_parameter("source_tex") != tex:
		_lens_material.set_shader_parameter("source_tex", tex)
	var size := (_lens.mesh as QuadMesh).size
	var part := scope_part if scope_part.has_area() else follow_rect(scope_zoom, _aim_of_lens())
	_lens_material.set_shader_parameter("fit_scale", fit_for(_geometry_aspect * part.size.x / part.size.y, size))
	_lens_material.set_shader_parameter("view_rect", Vector4(part.position.x, part.position.y, part.size.x, part.size.y))
	if _lens.get_surface_override_material(0) != _lens_material:
		_lens.set_surface_override_material(0, _lens_material)


## The part of the picture a digital scope of `zoom` times shows when the rifle points at `aim` (the gun's own coordinates, -0x7fff..0x7fff, y down): a window
## 1/zoom of the picture on each axis (so the picture's own shape), centred on the aim and kept inside the picture. Pure, for the tests.
static func follow_rect(zoom: float, aim: Vector2i) -> Rect2:
	var size := 1.0 / maxf(zoom, 1.0)
	var at := Vector2((float(aim.x) + 32767.0) / 65534.0, (float(aim.y) + 32767.0) / 65534.0)
	var pos := (at - Vector2(size, size) * 0.5).clamp(Vector2.ZERO, Vector2(1.0 - size, 1.0 - size))
	return Rect2(pos, Vector2(size, size))


## Where the rifle that wears the lens points: its `last_aim`, or the middle of the picture when it has none.
func _aim_of_lens() -> Vector2i:
	var node: Node = _lens
	while node != null:
		if "last_aim" in node:
			return node.get("last_aim")
		node = node.get_parent()
	return Vector2i.ZERO


## The scope screen of the rifle this cabinet wears: the guns are built with the MACHINE and hang in the room, not in the cabinet's model, so they
## are asked of the machine (RetroSystem.captive_controllers).
func _find_lens() -> MeshInstance3D:
	var host := cabinet.get_parent() if cabinet != null else null
	if host == null or not host.has_method("captive_controllers"):
		return null
	for gun: Variant in host.call("captive_controllers"):
		if is_instance_valid(gun):
			var found := (gun as Node).find_child(LENS_NODE, true, false) as MeshInstance3D
			if found != null:
				return found
	return null


## The lens being fed now, for the tests and the probe.
func lens() -> MeshInstance3D:
	return _lens if is_instance_valid(_lens) else null


## Whether the monitor is showing one screen cut out of the frame now (a scope game whose frame is the shape the table expects).
func is_cut() -> bool:
	return _cut


## The fit last applied, for the probe and the tests.
func current_fit() -> Vector2:
	return _last_fit


func current_aspect() -> float:
	return _content_aspect


func _libretro() -> Object:
	var h := host()
	if h != null and h.has_method("get_libretro_node"):
		return h.get_libretro_node()
	return null
