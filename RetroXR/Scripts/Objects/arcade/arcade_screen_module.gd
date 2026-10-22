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

var _screen: MeshInstance3D = null
var _material: ShaderMaterial = null
var _off_material: StandardMaterial3D = null

var _serial: int = -1
var _content_aspect: float = 0.0
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


func get_screen() -> MeshInstance3D:
	return _screen


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


func tick(_delta: float) -> void:
	if _screen == null or cabinet == null:
		return
	var tex: Texture2D = null if cabinet.host_picture_on_tv() else cabinet.host_picture()
	if tex == null:
		if _screen.get_surface_override_material(0) != _off_material:
			_screen.set_surface_override_material(0, _off_material)
		_serial = -1
		return
	if _material.get_shader_parameter("source_tex") != tex:
		_material.set_shader_parameter("source_tex", tex)
	if _screen.get_surface_override_material(0) != _material:
		_screen.set_surface_override_material(0, _material)
	var external := cabinet.has_method("external_picture_active") and bool(cabinet.call("external_picture_active"))
	var attract := cabinet.has_method("attract_picture_active") and bool(cabinet.call("attract_picture_active"))
	_refresh_geometry(tex, external, attract)


func _refresh_geometry(tex: Texture2D, external: bool = false, attract: bool = false) -> void:
	var lib: Object = _libretro()
	var aspect := 0.0
	if attract:
		# The game on show, not running: a video snap or a still, whose shape is its own.
		_serial = -1
		_content_aspect = float(tex.get_width()) / float(maxi(tex.get_height(), 1))
		_last_fit = fit_for(_content_aspect, glass_size)
		_material.set_shader_parameter("fit_scale", _last_fit)
		return
	if external:
		# A machine cabled to the bay: the board's geometry says nothing about this picture.
		_serial = -1
		_content_aspect = fallback_aspect(Vector2(tex.get_size()))
		_last_fit = fit_for(_content_aspect, glass_size)
		_material.set_shader_parameter("fit_scale", _last_fit)
		return
	if lib != null and lib.has_method("GetVideoGeometrySerial"):
		var serial: int = lib.GetVideoGeometrySerial()
		if serial == _serial and _content_aspect > 0.0:
			return
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
	_content_aspect = aspect
	_last_fit = fit_for(aspect, glass_size)
	_material.set_shader_parameter("fit_scale", _last_fit)


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
