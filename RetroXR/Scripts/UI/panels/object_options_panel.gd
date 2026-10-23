## ObjectOptionsPanel — the menu an object gets when it has no menu of its own.
##
## Every other panel here belongs to one kind of thing and knows what to say
## about it. This one knows nothing except what it is floating over, which is
## the point: it is what a table, a trash can, a cable or a controller opens,
## and the only row on it is the one FloatingObjectPanel3D puts on every panel.
##
## Created on demand and kept as a child of its subject, so it dies with it and
## a second press finds the same instance rather than stacking a new one.
class_name ObjectOptionsPanel
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://Scenes/UI/object_options_panel.tscn")
const NODE_NAME := "ObjectOptionsPanel"

## Clear of the object's own geometry. Measured from the top of what it draws
## rather than from its origin, because these are anything from a memory card to
## a table and a fixed offset would open inside the tall ones.
const CLEARANCE := 0.18

var _object: Node3D = null
## The rows last handed to the UI, so a frame where nothing moved lays nothing out.
var _info_drawn: Array = []
## How much taller than it would otherwise be the page has been made, to hold
## those rows.
var _info_px := 0.0


## Open or close the generic menu for `obj`. Safe to call on anything: an object
## that cannot be locked gets an empty menu, which is still an honest answer to
## "what are this thing's options".
static func toggle_for(obj: Node3D, camera: Node3D) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var panel := obj.get_node_or_null(NODE_NAME) as ObjectOptionsPanel
	if panel == null:
		panel = PANEL_SCENE.instantiate() as ObjectOptionsPanel
		panel.name = NODE_NAME
		obj.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(obj, camera)


func show_for(obj: Node3D, camera: Node3D) -> void:
	_object = obj
	_camera = camera
	global_position = _anchor()
	visible = true
	_populate()


func _anchor() -> Vector3:
	if _object == null or not is_instance_valid(_object):
		return global_position
	return _object.global_position + Vector3(0, _top_offset() + CLEARANCE + _tuning_lift(), 0)


## Half the rope tuning section's height, in meters. The page is centered on the
## anchor and grows both ways, and that section is tall enough (half a meter) that
## the lower half went into the desk the cable lay on; lifting by half of it keeps
## the page's bottom where it was without the section.
func _tuning_lift() -> float:
	var vp := _ui_viewport()
	if vp == null or vp.get_child_count() == 0:
		return 0.0
	var ui := vp.get_child(0) as ObjectOptions2D
	var v := $ObjectOptionsViewport as XRToolsViewport2DIn3D
	if ui == null or v.viewport_size.y <= 0.0:
		return 0.0
	return 0.5 * ui.tuning_height() * v.screen_size.y / v.viewport_size.y


## How far above the object's origin its highest drawn point is. Zero for
## anything with no visible geometry, which puts the panel at the clearance and
## is as good a guess as any.
func _top_offset() -> float:
	var top := 0.0
	for vis: Node in _object.find_children("*", "VisualInstance3D", true, false):
		var v := vis as VisualInstance3D
		if v == self or is_ancestor_of(v):
			continue
		var aabb := v.global_transform * v.get_aabb()
		top = maxf(top, aabb.position.y + aabb.size.y - _object.global_position.y)
	return maxf(top, 0.0)


func _process(delta: float) -> void:
	super(delta)
	if visible:
		_refresh_info()


func _populate() -> void:
	var vp := _ui_viewport()
	if vp == null or vp.get_child_count() == 0:
		call_deferred("_populate")
		return
	var ui := vp.get_child(0) as ObjectOptions2D
	if ui == null:
		return
	if not _ui_connected:
		ui.close_requested.connect(hide_panel)
		_ui_connected = true
	ui.populate(_display_name())
	ui.set_tuning(RopeTuning.rope_of(_object) if RopeTuning.enabled else null)
	_info_drawn = []
	_refresh_info()


func _ui_viewport() -> SubViewport:
	return ($ObjectOptionsViewport as XRToolsViewport2DIn3D).get_node_or_null("Viewport") as SubViewport


## The object's own facts, from its `options_info()` ([caption, text] rows), for
## anything that has some. Asked again every frame the menu shows, because some
## of them move: a tape's place, if the menu is left up while the tape plays.
##
## The page is fitted only on a frame where the rows did not change. A wrapped
## label measures itself at the width it was last laid out at, and one just
## written has not been, so measuring at once can read a path a letter a line.
func _refresh_info() -> void:
	var vp := _ui_viewport()
	if vp == null or vp.get_child_count() == 0:
		return
	var ui := vp.get_child(0) as ObjectOptions2D
	if ui == null or _object == null or not is_instance_valid(_object):
		return
	var rows: Array = []
	if _object.has_method("options_info"):
		rows = _object.call("options_info")
	if rows != _info_drawn:
		_info_drawn = rows
		ui.set_info(rows)
		return
	_fit_page(ui)


## As tall as what is on it, and never shorter than the page would be without
## the info rows: the authored page has room for the title and the lock row, so
## a menu with nothing to tell keeps exactly the size it always had. Fitted
## rather than grown by a guess, so a measurement taken too early mends itself.
func _fit_page(ui: ObjectOptions2D) -> void:
	var v := $ObjectOptionsViewport as XRToolsViewport2DIn3D
	var base := v.viewport_size.y - _info_px
	var want := maxf(0.0, ceilf(ui.content_height() - base))
	if want != _info_px and _grow_page(want - _info_px):
		_info_px = want


## The object's own label when it has one, otherwise its node name with the
## spawn suffix Godot appends stripped off.
func _display_name() -> String:
	for prop: String in ["display_name", "game_label", "album_label", "video_label"]:
		if prop in _object:
			var s := str(_object.get(prop))
			if s != "":
				return s
	var n := str(_object.name)
	var at := n.find("@")
	return n.substr(0, at) if at > 0 else n


func _target_node() -> Node3D:
	return _object
