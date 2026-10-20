## PointerFit — what a pointer can hit on a small object is what it draws.
##
## Plugs and memory cards used to carry pointer targets padded well past their
## shells: a 110 mm sphere round a 14 mm phono plug, a box 11 mm clear of a 38 mm
## card at each side, so that a ray from across the room would find them. What
## that bought was a desktop laser that stopped in the air beside the thing and
## took it, or its neighbor, instead of what was aimed at, which is what cf0d16c4
## took off discs and cartridges (2026-10-07).
##
## The target is measured rather than written down, because what is drawn changes
## while the game runs. A pad hands its plug its console's connector
## (ControllerPlug.set_plug_mesh), a receiver swaps it on every seat, and mods hang
## their own shells on plugs and cards and hide the stand-ins. So the fit is taken
## from the meshes actually drawn, in the object's own frame, at the end of the
## frame in which its children last changed: after whatever dressed it is done.
##
## Two things the desktop ray can stop on are fitted (it queries 3:Pickable as well
## as 21:XRPointer, see InteractionResolver.QUERY_MASK):
##   * PointerArea/CollisionShape3D becomes a box of what is drawn;
##   * the body's own boxes are cut back to what is drawn wherever they stand proud
##     of it, and are never grown. Only the boxes the object's scene authored, which
##     were sized for its stand-in: a box set at run time was fitted by whoever set
##     it (a mod sizes a card's body for the cap riding on it), and is left alone.
##
## Not measured: a hand pose waiting for a hand, the highlight's outline hulls,
## anything top-level (a hint, a panel), another pickable or a snap zone riding on
## this one, a shadow-only proxy, and the cord, which is the plug's sibling rather
## than a part of it. A node in EXCLUDE_GROUP is left out with everything under it.
class_name PointerFit
extends RefCounted

## A node in this group, and everything under it, is not part of what is drawn.
const EXCLUDE_GROUP := &"pointer_fit_exclude"

## A body face standing this far or less proud of the drawing is left where it is:
## a box sized to a shell to the nearest millimeter, not padding. A PlayStation 2
## card's body stands 0.7 mm over the real card's shell (xenu.ps2card), and that
## mod's probe holds the body to at least the shell's thickness.
const BODY_SLACK := 0.0008

## The thinnest box a fit makes, so that a flat model still gets a solid target.
const MIN_EXTENT := 0.0005

## The hand poses a held object shows. Hidden until a hand has it, and far bigger
## than the thing in it.
const HAND_NODES: Array[StringName] = [&"HandLeft", &"HandRight"]

## What the desktop ray stops on: InteractionResolver.QUERY_MASK, which the tests
## hold this to. Spelled out, as the classes below are named rather than referred
## to, because every plug and card script loads this one: a class named here is
## loaded with it, and the Nunchuk's cord scene, loading its plug's script, came
## back round to itself through one of them ("Parse Error: Busy").
const QUERY_MASK := (1 << 0) | (1 << 2) | (1 << 20) | (1 << 22)

## Helpers that hang off an object and are not part of it: the outline's hulls,
## and the hint that floats over a held thing.
const LEFT_OUT_CLASSES: Array[StringName] = [&"PickableHighlight", &"HeldHint"]

const _WATCH_META := &"_pointer_fit"
const _BODY_META := &"_pointer_fit_authored"

var _object: WeakRef = null
var _pending := false


## Fit `object` at the end of this frame, and again whenever a child of it comes,
## goes, or is shown or hidden. Called from the object's own _ready, which is after
## a mod's dressing hook has run (that runs as the object enters the tree) but may
## be before a model set a moment later has arrived; the watch catches that one.
static func watch(object: CollisionObject3D) -> void:
	if object == null:
		return
	# has_meta first: get_meta with a null default still reports a missing key.
	var watcher: PointerFit = null
	if object.has_meta(_WATCH_META):
		watcher = object.get_meta(_WATCH_META) as PointerFit
	if watcher == null:
		watcher = PointerFit.new()
		watcher._object = weakref(object)
		# Kept by the object, and so for exactly as long as it is.
		object.set_meta(_WATCH_META, watcher)
		object.child_entered_tree.connect(watcher._on_child_entered)
		object.child_exiting_tree.connect(watcher._on_child_exiting)
		for child: Node in object.get_children():
			watcher._follow(child)
	watcher.request()


## Fit `object` now: its pointer target to what it draws, and its body's boxes back
## to it. Returns what was measured, in the object's frame, or an empty AABB when
## nothing is drawn, in which case nothing is changed.
static func fit(object: CollisionObject3D) -> AABB:
	var boxes: Array[AABB] = []
	_gather(object, object, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var drawn := _merged(boxes)
	_fit_pointer(object, drawn)
	if (object.collision_layer & QUERY_MASK) != 0:
		for child: Node in object.get_children():
			var col := child as CollisionShape3D
			if col != null:
				_trim_body(col, drawn)
	return drawn


## The bounds of what `object` draws, in its own frame; an empty AABB for nothing.
static func drawn_bounds(object: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_gather(object, object, Transform3D.IDENTITY, boxes)
	return AABB() if boxes.is_empty() else _merged(boxes)


## One fit at the end of this frame, however many ask for it.
func request() -> void:
	if _pending:
		return
	_pending = true
	_flush.call_deferred()


func _flush() -> void:
	_pending = false
	if _object == null:
		return
	var object := _object.get_ref() as CollisionObject3D
	if object == null or object.is_queued_for_deletion():
		return
	fit(object)


func _on_child_entered(child: Node) -> void:
	_follow(child)
	request()


func _on_child_exiting(child: Node) -> void:
	if child.has_signal(&"visibility_changed") and child.is_connected(&"visibility_changed", request):
		child.disconnect(&"visibility_changed", request)
	request()


## A child shown or hidden changes what is drawn: a mod hides the stand-in's parts
## under its shell, and may do it after the shell is on.
func _follow(child: Node) -> void:
	var spatial := child as Node3D
	if spatial == null or spatial is CollisionObject3D or _is_one_of(spatial, LEFT_OUT_CLASSES):
		return
	if not spatial.visibility_changed.is_connected(request):
		spatial.visibility_changed.connect(request)


static func _merged(boxes: Array[AABB]) -> AABB:
	var acc := boxes[0]
	for i in range(1, boxes.size()):
		acc = acc.merge(boxes[i])
	return acc


## Every drawn mesh under `node`, as a box in `object`'s frame. Transforms are
## walked by hand, so this answers for an object that is not in the tree as well.
static func _gather(node: Node, object: Node3D, frame: Transform3D, out: Array[AABB]) -> void:
	for child: Node in node.get_children():
		var spatial := child as Node3D
		# A Node3D under a plain Node is placed in the world, not in this object.
		if spatial == null or _left_out(spatial, object):
			continue
		var at := frame * spatial.transform
		var mi := spatial as MeshInstance3D
		if mi != null and mi.mesh != null \
				and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			out.append(at * mi.get_aabb())
		_gather(spatial, object, at, out)


static func _left_out(node: Node3D, object: Node3D) -> bool:
	if not node.visible or node.top_level or node.is_in_group(EXCLUDE_GROUP):
		return true
	if _is_one_of(node, LEFT_OUT_CLASSES):
		return true
	# Something else riding on it, in its own socket: its own target answers for it.
	if node is XRToolsPickable or node is XRToolsSnapZone:
		return true
	return node.get_parent() == object and HAND_NODES.has(node.name)


## Whether `node`'s script is, or extends, one of these global classes.
static func _is_one_of(node: Node, classes: Array[StringName]) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if classes.has(script.get_global_name()):
			return true
		script = script.get_base_script()
	return false


## `node`'s frame in `object`'s, walked by hand for the same reason as _gather.
static func _frame_in(node: Node, object: Node) -> Transform3D:
	var frame := Transform3D.IDENTITY
	while node != null and node != object:
		var spatial := node as Node3D
		if spatial != null:
			frame = spatial.transform * frame
		node = node.get_parent()
	return frame


## The pointer target: one box, the drawing's bounds, centered on them. A fresh
## shape: the scene's is shared by every plug of its kind in the room.
static func _fit_pointer(object: Node3D, drawn: AABB) -> void:
	var area := object.get_node_or_null(^"PointerArea") as Node3D
	if area == null:
		return
	var col := area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var local := _frame_in(area, object).affine_inverse() * drawn
	var size := local.size.max(Vector3.ONE * MIN_EXTENT)
	var at := Transform3D(Basis.IDENTITY, local.get_center())
	var box := col.shape as BoxShape3D
	if box != null and box.size.is_equal_approx(size) and col.transform.is_equal_approx(at):
		return
	var fitted := BoxShape3D.new()
	fitted.size = size
	col.shape = fitted
	col.transform = at


## A body box cut back to the drawing on every face that stands proud of it.
##
## Measured from the box the scene authored each time, and that box is put back
## once the drawing covers it again (a receiver's plug swaps connectors on every
## seat), so one fit never trims what a previous fit already trimmed.
static func _trim_body(col: CollisionShape3D, drawn: AABB) -> void:
	var record: Dictionary = col.get_meta(_BODY_META, {})
	var authored: BoxShape3D = null
	var authored_at := col.transform
	if record.is_empty():
		authored = col.shape as BoxShape3D
		# Set at run time: fitted by whoever set it.
		if authored == null or authored.resource_path.is_empty():
			return
	else:
		if col.shape != record["fitted"]:
			# Given another box since this one was cut: that one is theirs.
			col.remove_meta(_BODY_META)
			return
		authored = record["shape"] as BoxShape3D
		authored_at = record["at"]
	if not authored_at.basis.is_equal_approx(Basis.IDENTITY):
		return
	var whole := AABB(authored_at.origin - authored.size * 0.5, authored.size)
	var lo := whole.position
	var hi := whole.end
	for axis in 3:
		if lo[axis] < drawn.position[axis] - BODY_SLACK:
			lo[axis] = drawn.position[axis]
		if hi[axis] > drawn.end[axis] + BODY_SLACK:
			hi[axis] = drawn.end[axis]
		if hi[axis] - lo[axis] < MIN_EXTENT:
			return      # the drawing is nowhere near this box: not the fit's to judge
	var trimmed := AABB(lo, hi - lo)
	if trimmed.is_equal_approx(whole):
		if not record.is_empty():
			col.shape = authored
			col.transform = authored_at
			col.remove_meta(_BODY_META)
		return
	var current := col.shape as BoxShape3D
	if not record.is_empty() and current != null and current.size.is_equal_approx(trimmed.size) \
			and col.position.is_equal_approx(trimmed.get_center()):
		return
	var fitted := BoxShape3D.new()
	fitted.size = trimmed.size
	col.shape = fitted
	col.transform = Transform3D(Basis.IDENTITY, trimmed.get_center())
	col.set_meta(_BODY_META, {"shape": authored, "at": authored_at, "fitted": fitted})
