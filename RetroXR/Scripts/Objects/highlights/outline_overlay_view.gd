## OutlineOverlayView — draws the hover / held / widget outlines AFTER the 3D view, while a temporal upscaler
## (DLSS, NVIDIA's engine fork) runs.
##
## A temporal upscaler rebuilds each frame partly from the last ones, and finds where a pixel was through its
## motion vector. An outline writes none (x-ray, depth test off), so the upscaler reprojected its old pixels
## with whatever was behind them and the outline trailed and faded behind the object as the player moved.
## Telling it to trust the current frame where the outline IS (DLSS's bias mask) cannot clear where it WAS.
## So the outline is kept out of that frame altogether: every outline overlay renders on LAYER only, the main
## camera stops drawing LAYER while this view is up, and a small raster view of the same world, its camera
## copied from the main one each frame, draws LAYER alone and is laid over the screen.
##
## The outline is self-contained in its overlay mesh (stencil mask + outline, chained, depth test off), so it
## needs nothing of the scene's depth to come out right here. QualityManager puts one up only while DLSS runs;
## everywhere else a camera sees every layer, LAYER included, exactly as before.
class_name OutlineOverlayView
extends CanvasLayer

## Render layer 20: no other visual uses it (19 is the Game Boy Camera's lens, 18 the arcade shell's shadows).
const LAYER := 1 << 19

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _rect: TextureRect = null
var _main: Camera3D = null
var _main_mask := 0


func _init() -> void:
	name = "OutlineOverlayView"
	# Under the HUD's layers (the crosshair, prompts) and over the 3D view.
	layer = -1


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = false
	_viewport.world_3d = get_viewport().world_3d
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# NVIDIA's fork: this view rasterises (a per-viewport switch the stock engine does not have).
	if &"use_pathtracing" in _viewport:
		_viewport.set(&"use_pathtracing", false)
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.cull_mask = LAYER
	# It copies the main camera's pose every frame, already interpolated; interpolating it again warned
	# ("Interpolated Camera3D triggered from outside physics process") and would lag a tick.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera)
	_camera.current = true
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture = _viewport.get_texture()
	add_child(_rect)
	print("[Outline] drawn after the 3D view (a temporal upscaler is on)")


func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main != _main:
		_release_main()
		_main = main
		if _main:
			_main_mask = _main.cull_mask
	if _main == null:
		return
	# Every frame: a camera can be handed its mask back by whatever owns it.
	_main.cull_mask = _main_mask & ~LAYER
	var size := get_viewport().get_visible_rect().size
	if Vector2i(size) != _viewport.size:
		_viewport.size = Vector2i(size)
	_camera.global_transform = _main.global_transform
	_camera.projection = _main.projection
	_camera.fov = _main.fov
	_camera.size = _main.size
	_camera.near = _main.near
	_camera.far = _main.far
	_camera.keep_aspect = _main.keep_aspect
	_camera.h_offset = _main.h_offset
	_camera.v_offset = _main.v_offset


func _exit_tree() -> void:
	_release_main()
	print("[Outline] back in the 3D view")


func _release_main() -> void:
	if is_instance_valid(_main):
		_main.cull_mask = _main_mask
	_main = null
