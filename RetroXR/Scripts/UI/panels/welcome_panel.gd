## WelcomePanel — the welcome popup: one page (Welcome2D) standing in front of the
## player when the room is ready, saying what to do and what not to.
##
## A Viewport2DIn3D like the menu's, so one panel serves the headset (the lasers)
## and the desktop (the crosshair) with nothing of either's own. Built when it is
## shown and freed when it is put away: it is up for a minute at the start of a
## launch, and a SubViewport left standing would hold a render target all session.
##
## It comes up at the start of EVERY launch while AppPrefs.show_welcome is on. Got
## it puts it away for this launch; "Don't Show Again" also switches that off, and
## OPTIONS > General switches it back on. Put away any other way (the menu opened
## over it, the room changed) changes nothing.
##
## SpawnMenuController decides when (once per launch, curtain down) and stands it
## where the menu would open. On the headset's page it also hands over the two
## controllers' art, and a ControllerDemo stands the player's own controllers in
## front of the page's stage, pressing each button the page talks about.
class_name WelcomePanel
extends Node3D

## Done or "Don't Show Again" pressed; the page is going away.
signal dismissed

const PAGE_SCENE := preload("res://Scenes/UI/welcome_2d.tscn")
const VIEWPORT_SCENE := preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")

## Metres, and the page's pixels: the menu's density (2000 px a metre). The page
## is built at this size and then made as tall as what is on it (_fit), between
## the two bounds: the headset's page carries the controllers' stage and the
## desktop's does not, a Quest's ROM folder wraps to more lines, and a fixed
## height left a band of nothing over its buttons.
const SCREEN_SIZE := Vector2(1.1, 0.75)
const VIEWPORT_SIZE := Vector2(2200, 1500)
const MIN_PX := 700.0
const MAX_PX := 2000.0
## How far off it stands, at the least: it is as wide as the menu and taller.
const MIN_DISTANCE := 1.1
## How far in front of the page the controllers stand, so they read as things
## and not a picture on it.
const DEMO_LIFT := 0.07
## Redraws a second. Throttled rather than every frame: the page only changes
## under a laser's hover, and a headset frame has better things to spend on.
const REDRAW_FPS := 30.0

var _viewport: XRToolsViewport2DIn3D = null
var _done := false
var _arts: Array = [null, null]
var _demo: ControllerDemo = null


## Whether the page comes up at the start of a launch.
static func due() -> bool:
	return AppPrefs.show_welcome


func _init() -> void:
	# Placed in the world, not carried with the controller it hangs under: that node
	# is moved to wherever the menu opens.
	top_level = true


## Stand the page `distance` in front of `camera` along `forward` (level, unit),
## facing it, a touch below eye height as the menu is. `left_art` / `right_art`
## are the hands' ControllerArt, shown on the headset's page (either may be null).
func show_in_front_of(camera: Node3D, forward: Vector3, distance: float,
		left_art: ControllerArt = null, right_art: ControllerArt = null) -> void:
	_arts = [left_art, right_art]
	distance = maxf(distance, MIN_DISTANCE)
	_build()
	global_position = camera.global_position + forward * distance + Vector3(0, -0.05, 0)
	# look_at turns -Z to the camera; the viewport's face is +Z, so half a turn more.
	look_at(camera.global_position, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	reset_physics_interpolation()
	visible = true
	print("[Welcome] shown (%s, %.2f m)" % ["vr" if MenuStyle.is_vr_mode() else "desktop", distance])


## Put away without Done: not marked seen, so it comes back next launch.
func put_away(reason: String) -> void:
	if _done:
		return
	_done = true
	print("[Welcome] put away unread (%s); it shows again next launch" % reason)
	queue_free()


func _build() -> void:
	if _viewport != null:
		return
	# Instanced from the addon scene, not .new(): the SubViewport, mesh and
	# collision body are scene children.
	_viewport = VIEWPORT_SCENE.instantiate() as XRToolsViewport2DIn3D
	_viewport.name = "WelcomeViewport"
	_viewport.screen_size = SCREEN_SIZE
	_viewport.viewport_size = VIEWPORT_SIZE
	_viewport.update_mode = XRToolsViewport2DIn3D.UpdateMode.UPDATE_THROTTLED
	_viewport.throttle_fps = REDRAW_FPS
	# SCISSOR, not TRANSPARENT: alpha-blended, the page was drawn in the
	# transparent pass and the bedroom window's string lights, two metres behind
	# it, came through the text (measured in welcome_probe). Scissored it is drawn
	# opaque and still keeps its rounded corners.
	_viewport.transparent = XRToolsViewport2DIn3D.TransparancyMode.SCISSOR
	_viewport.unshaded = true
	add_child(_viewport)
	_viewport.scene = PAGE_SCENE
	var page := _viewport.get_scene_instance() as Welcome2D
	if page == null:
		push_warning("[Welcome] the page did not instantiate; nothing to press")
		return
	page.dismissed.connect(_on_page_dismissed)
	page.page_changed.connect(_on_page_changed.bind(page))
	# Out of sight until it is the right size, so it never shows at the wrong one.
	_viewport.visible = false
	_fit.call_deferred(page)


## Make the quad as tall as the page's content once that has been laid out.
func _fit(page: Welcome2D) -> void:
	for i in 2:
		await get_tree().process_frame
	if _done or not is_instance_valid(page) or not is_instance_valid(_viewport):
		return
	var want := page.content_height()
	var px := ceilf(clampf(want, MIN_PX, MAX_PX))
	if want > MAX_PX:
		push_warning("[Welcome] the page wants %d px, cut to %d: shorten the copy" % [want, MAX_PX])
	_viewport.viewport_size = Vector2(VIEWPORT_SIZE.x, px)
	_viewport.screen_size = Vector2(SCREEN_SIZE.x, SCREEN_SIZE.x * px / VIEWPORT_SIZE.x)
	_viewport.visible = true
	print("[Welcome] page fitted: %d px, %.2f x %.2f m" % [px, _viewport.screen_size.x,
		_viewport.screen_size.y])
	if page.page_index() == 0 and page.stage_rect().has_area():
		# Laid out again at the new height a frame later; the stage moves with it.
		await get_tree().process_frame
		if _done or not is_instance_valid(page):
			return
		if _demo == null:
			_stand_demo(page)
		else:
			_demo.position = _stage_point(page)


## Next or Back: the page is another height, and the controllers belong to the
## first page's stage only.
func _on_page_changed(index: int, page: Welcome2D) -> void:
	if _demo != null:
		_demo.visible = index == 0
	_fit(page)


## Where the page's stage is, in the panel's space, just in front of the quad.
func _stage_point(page: Welcome2D) -> Vector3:
	var rect := page.stage_rect()
	var vs := _viewport.viewport_size
	var ss := _viewport.screen_size
	return Vector3((rect.get_center().x / vs.x - 0.5) * ss.x,
		(0.5 - rect.get_center().y / vs.y) * ss.y, DEMO_LIFT)


## The player's controllers, in front of the page's stage, telling it which step
## they are on.
func _stand_demo(page: Welcome2D) -> void:
	var at := _stage_point(page)
	_demo = ControllerDemo.new()
	_demo.name = "ControllerDemo"
	_demo.position = at
	_demo.step_changed.connect(page.set_step)
	add_child(_demo)
	_demo.setup(_arts[0] as ControllerArt, _arts[1] as ControllerArt)
	print("[Welcome] controller demo at the stage (%.2f, %.2f) m: left %s, right %s" % [
		at.x, at.y, _demo.source_of("left"), _demo.source_of("right")])


## The controller demo, once it stands; for probes.
func demo() -> ControllerDemo:
	return _demo


## The page, once built; for probes.
func page() -> Welcome2D:
	return _viewport.get_scene_instance() as Welcome2D if _viewport != null else null


## `for_good`: "Don't Show Again", which switches the page off at start as well.
func _on_page_dismissed(for_good: bool) -> void:
	# A click through a Viewport2DIn3D can arrive twice; the second finds it done.
	if _done:
		return
	_done = true
	print("[Welcome] dismissed%s" % (", and not shown at start again" if for_good else ""))
	if for_good and not AppPrefs.set_show_welcome(false):
		push_warning("[Welcome] could not save Don't Show Again; it shows at the next start")
	dismissed.emit()
	queue_free()
