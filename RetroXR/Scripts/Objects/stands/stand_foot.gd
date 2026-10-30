## StandFoot — the point a console is held by when it is mounted in a stand.
##
## ExpansionFoot's arrangement (expansion_port.gd build_foot), for a console that
## may lie on any face: one point per face some stand rests this console on, at
## that face's middle, +Y into the console (StandCatalog.foot_transform). It
## answers only a StandMount of its own face's group, so a stand that stands a
## PS2 on its side cannot take it by its underside, and no other zone ever sees it.
##
## It outranks any other point the console carries for that zone: the pose IS
## the stand's, and a plain grab point that happened to be nearer would seat the
## console at a pose no stand was drawn for.
class_name StandFoot
extends XRToolsGrabPointSnap

## Which face of the console this is.
var face := "bottom"


func can_grab(grabber: Node3D, current: XRToolsGrabPoint) -> float:
	return super.can_grab(grabber, current) * 1000.0


## Build the feet `sys` needs, once each, and register them with it. False when
## the console cannot be measured yet (its model has not loaded) and a foot it
## needs is still missing -- the caller tries again later.
##
## Registered by hand, as ExpansionFoot is: XRToolsPickable collects its grab
## points in its own _ready, long before the model is measured.
static func build_for(sys: RetroSystem) -> bool:
	var faces := StandCatalog.faces_for(sys.systemid, resolved_model_id(sys))
	if faces.is_empty():
		return true
	var missing := faces.filter(func(f: String) -> bool: return find(sys, f) == null)
	if missing.is_empty():
		return true
	var box := sys.body_aabb()
	if box.size.x <= 0.0:
		return false
	for f: String in missing:
		var point := StandFoot.new()
		point.name = "StandFoot_" + f
		point.face = f
		point.require_group = StandCatalog.zone_group(f)
		sys.add_child(point)
		point.transform = StandCatalog.foot_transform(f, box)
		sys._grab_points.push_back(point)
		print("[ConsoleStand] %s grew a foot on its %s face at %s (box %s)"
			% [sys.name, f, point.position, box.size])
	return true


## The foot for `face` on `sys`, or null.
static func find(sys: Node, face: String) -> StandFoot:
	return sys.get_node_or_null("StandFoot_" + face) as StandFoot


## The model row a console actually wears: model_id "" means its platform's
## default, and a stand names models by their real id.
static func resolved_model_id(sys: RetroSystem) -> String:
	return str(SystemModelRegistry.resolve(sys.model_id, sys.systemid).get("id", ""))
