## PanelResizeGrip — the "_|" corner mark on a CurvedPanel: press and drag to
## resize the panel in x and y.
##
## A separate collider for the same reason KeyboardKeyField is one:
## InteractionResolver tests `is XRToolsPickable` before has_method("pointer_event"),
## so anything hung off a pickable has to be its own node to be pointed at rather
## than grabbed. On POINTABLE_LAYER it classifies as KIND_POINTER, which also
## means can_grab = false — pressing the grip cannot drag the whole panel.
##
## A StaticBody3D, not an Area3D. The VR laser's RayCast has
## collide_with_areas = false, so an area is invisible to it — which is how this
## shipped unclickable in VR. Nothing was lost by the change: it had already
## turned monitoring and monitorable off, i.e. every Area3D feature there is.
## The desktop path is unaffected, keying off has_method("pointer_event").
##
## The drag deliberately does NOT follow pointer MOVED events. Those stop the
## moment the cursor leaves this little area, which for a resize handle is
## immediately — that is the whole point of the gesture. Instead PRESSED records
## which pointer started it, and from then on the panel projects that pointer's
## own ray onto its plane every frame until RELEASED.
class_name PanelResizeGrip
extends StaticBody3D

var _panel: Node = null


static func create(panel: Node, size: Vector3) -> PanelResizeGrip:
	var grip := PanelResizeGrip.new()
	grip.name = "ResizeGrip"
	grip._panel = panel
	grip.collision_layer = VRSlider.POINTABLE_LAYER
	grip.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	grip.add_child(shape)
	return grip


func pointer_event(event: XRToolsPointerEvent) -> void:
	if not is_instance_valid(_panel):
		return
	match event.event_type:
		XRToolsPointerEvent.Type.PRESSED:
			_panel.call("resize_begin", event.pointer)
		XRToolsPointerEvent.Type.RELEASED:
			_panel.call("resize_end")
		XRToolsPointerEvent.Type.ENTERED:
			# Lit under the pointer, so the mark reads as something to take hold of.
			if _panel.has_method("resize_hover"):
				_panel.call("resize_hover", true)
		XRToolsPointerEvent.Type.EXITED:
			# Do NOT end the drag here: leaving the grip is expected.
			if _panel.has_method("resize_hover"):
				_panel.call("resize_hover", false)
