## VRDoor — a door that opens: a leaf on a vertical hinge (DoorHinge, a VRHinge)
## held shut by its latch until its knob (DoorKnob, a VRKnob) is turned.
##
## ONE node is the whole door. Put it at the bottom middle of the doorway, its +Y up,
## X across the opening and Z through it, and say which side the hinges are on and
## which face the door swings toward; it builds the rest in _ready. The leaf comes
## from, in this order:
##   • a door MODEL under this node that is one mesh (door.glb is): name its leaf and
##     knob surfaces (`leaf_surfaces`, `knob_surfaces`) and DoorModelSplit takes them
##     out of it; the leaf's own bounds then size everything, the exports below that
##     describe the leaf are ignored, and the knob sits where the model has it;
##   • authored children named `Leaf` and `Knob` (any Node3D, placed in this node's
##     frame with the door shut), sized by `width`/`height`/`thickness`;
##   • nothing: a plain box leaf and a round knob from those same exports — a working
##     door for a room or a mod from properties alone.
##
## How it works in a hand: the trigger at the knob takes the knob, which turns with
## the wrist either way; turned past `unlatch_turn` the latch lets go and the SAME
## hand is handed on to the leaf (VRHinge.grab_with), so one pull turns and swings
## it. Let go near shut and it latches; anywhere else it stays. An unlatched leaf
## can also be taken anywhere (trigger, or the grip at its edge) or pushed with a
## fingertip. At a desk, or with a laser, a press on the knob swings it open or shut.
##
## Saved and synced: a door in a ROOM (not inside a spawned object) is recorded in the
## slot beside the light switches (ScenePersistence "doors") and announced in netplay
## (NetEvents.EV_DOOR, and a late joiner's room state). A door inside a spawned
## object or a mod prop needs none of that: its hinge and knob are articulated
## controls the object's own entry already saves and syncs.
##
## The rig, by fixed names (saves and netplay key on paths):
##   HingeFrame            on the hinge line, local X = the hinge axis
##     HingePivot          the leaf, turned about HingeFrame's X (DoorHinge's target)
##       <leaf meshes>
##       LeafBody          AnimatableBody3D, the leaf's collision (layer 1)
##       DoorHinge         the grab box over the leaf
##       DoorKnob          the knob's reach; its KnobPivot carries the knob meshes
class_name VRDoor
extends Node3D

signal door_changed(degrees: float, latched: bool)
signal unlatched
signal latched

enum HingeSide { POSITIVE_X, NEGATIVE_X }
enum Swing { TOWARD_POSITIVE_Z, TOWARD_NEGATIVE_Z }
## What lets the latch go: a knob turned by the wrist, a crash bar pushed in, or
## nothing at all (a push plate: the leaf itself is pushed; use with latching off).
enum Opener { KNOB, PUSH_BAR, NONE }

## Every VRDoor, for the scene save and netplay's room state.
const GROUP := &"vr_door"
## Netplay: degrees a second a remote door is eased toward the angle it was sent.
const REMOTE_SPEED_DEG := 360.0
## Netplay: at most one report this often while a door swings (and one when it stops).
const REPORT_INTERVAL_MS := 125
const REPORT_MIN_DEG := 0.5

@export var hinge_side: HingeSide = HingeSide.POSITIVE_X
@export var swing: Swing = Swing.TOWARD_POSITIVE_Z
## How far it opens, in degrees from shut.
@export_range(10.0, 180.0) var open_deg: float = 100.0
## Shut and latched when the room loads (a save overrides it).
@export var latched_at_start: bool = true
## How far the knob must turn from rest, 0..1, before the latch lets go.
@export_range(0.05, 1.0) var unlatch_turn: float = 0.6
## KNOB: turned either way, then pulled or pushed. PUSH_BAR: a crash bar across the
## face OPPOSITE the swing (the side the door is pushed from), pushed in to open.
@export var opener: Opener = Opener.KNOB
## Off: a PUSH door with no latch at all (a shop's front door): a push on its bar or
## its face always swings it, and its closer brings it back without latching.
@export var latching: bool = true
## A door closer: let go anywhere, it eases shut and latches (an exit door's).
@export var self_closing: bool = false
@export var closer_speed_deg: float = 12.0
## A press on the knob from a pointer swings the door this far.
@export var desktop_open_deg: float = 80.0
@export var swing_seconds: float = 0.6
## The leaf blocks the player and objects as it swings.
@export var leaf_collision: bool = true
## Names the door in the log ("[Door] closet ...").
@export var log_name: String = ""

@export_group("Leaf (no model)")
@export var width: float = 0.9
@export var height: float = 2.03
@export var thickness: float = 0.035
## Gap under the leaf.
@export var bottom_gap: float = 0.01
## Door-frame z of the leaf's middle.
@export var leaf_center_z: float = 0.0
## The knob's x and y in this node's frame. Zero: 6 cm in from the latch edge, 0.9 m up.
@export var knob_position: Vector2 = Vector2.ZERO

@export_group("Push bar (no model)")
## The bar's middle above the floor.
@export var bar_height: float = 1.0
## Its length. Zero: the leaf's width less 16 cm.
@export var bar_length: float = 0.0
## Its section: how tall, and how deep (out from the leaf).
@export var bar_section: Vector2 = Vector2(0.06, 0.035)
## From the push face to the bar's middle.
@export var bar_standoff: float = 0.05
## How far it goes in.
@export var bar_travel: float = 0.025

@export_group("Model")
## The door model's MeshInstance3D. Empty: the first one under this node.
@export var model: NodePath
@export var leaf_surfaces: PackedStringArray = PackedStringArray()
@export var knob_surfaces: PackedStringArray = PackedStringArray()
## PUSH_BAR: the bar's surfaces, taken whole.
@export var bar_surfaces: PackedStringArray = PackedStringArray()

## Test seam: when set, called with the EV_DOOR arguments instead of NetworkManager.
var report_to: Callable = Callable()
var hinge: DoorHinge = null
var knob: DoorKnob = null
var bar: DoorPushBar = null
var _bar_box := AABB()           # the bar, door frame, out
var _placeholder_leaf: Node3D = null
var _placeholder_opener: Node3D = null
# The latch bolt, when the model has one: it slides into the leaf's edge as the knob
# turns (or the bar goes in), all the way at the point the latch lets go.
var _bolt: Node3D = null
var _bolt_rest := Transform3D()
var _bolt_dir := Vector3.ZERO       # door frame until the rig is built, then HingePivot's
var _bolt_travel := 0.0
var _bolt_in := -1.0
var _frame: Node3D = null
var _pivot: Node3D = null
var _leaf_box := AABB()          # the leaf, door frame, shut
var _knob_at := Vector3.ZERO     # the knob's axle origin, door frame
var _knob_held_prev := false
var _tween: Tween = null
var _remote_target := NAN
var _remote_latched := true
var _last_deg := NAN
var _last_latched := true
var _rep_deg := NAN
var _rep_latched := true
var _rep_at_ms := 0


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	var leaf_meshes: Array[Node3D] = []
	var knob_meshes: Array[Node3D] = []
	if not _split_model(leaf_meshes, knob_meshes):
		_adopt_or_build(leaf_meshes, knob_meshes)
	_build_rig(leaf_meshes, knob_meshes)
	_last_deg = hinge.get_rotation_deg()
	_last_latched = hinge.is_latched_closed()
	_sync_reported()
	print("[Door] %s ready: leaf %.3f x %.3f x %.3f m, hinge %s, swings %s, %s" % [
		_name(), _leaf_box.size.x, _leaf_box.size.y, _leaf_box.size.z,
		"+X" if hinge_side == HingeSide.POSITIVE_X else "-X",
		"+Z" if swing == Swing.TOWARD_POSITIVE_Z else "-Z",
		"latched" if _last_latched else "open"])


# --- public API ------------------------------------------------------------------

func get_angle_deg() -> float:
	return hinge.get_rotation_deg() if hinge != null else 0.0


func is_latched() -> bool:
	return hinge != null and hinge.is_latched_closed()


func is_open() -> bool:
	return hinge != null and not hinge.is_latched_closed() \
		and hinge.get_rotation_deg() > hinge.close_latch_deg


## Swing it open to `degrees` (the latch let go first), animated or at once.
func open_to(degrees: float, animate: bool = true) -> void:
	if hinge == null:
		return
	degrees = clampf(degrees, 0.0, open_deg)
	_remote_target = NAN
	if hinge.is_latched_closed():
		hinge.open()
		if knob != null:
			knob.set_value_no_signal(1.0)   # the knob turns as it lets go; it springs back
		if bar != null:
			bar.set_value_no_signal(1.0)    # so does the bar
	_swing_to(degrees, false, animate)
	if animate and hinge.self_closing:
		hinge.hold_closer(swing_seconds + 2.0)   # stand open a moment before the closer takes it


## Swing it shut and latch it.
func close(animate: bool = true) -> void:
	if hinge == null or hinge.is_latched_closed():
		return
	_remote_target = NAN
	_swing_to(0.0, latching, animate)


## A press on the knob from a pointer: open a shut door, shut an open one.
func toggle() -> void:
	if is_open():
		close()
	else:
		open_to(desktop_open_deg)


## Restore (a save, a late joiner's room state): straight there, nothing reported.
func apply_state(degrees: float, p_latched: bool) -> void:
	if hinge == null:
		return
	_kill_tween()
	_remote_target = NAN
	p_latched = p_latched and latching
	hinge.set_state_remote(0.0 if p_latched else clampf(degrees, 0.0, open_deg),
		p_latched, false)
	_last_deg = hinge.get_rotation_deg()
	_last_latched = hinge.is_latched_closed()
	_sync_reported()


## Another player moved it: eased there rather than jumped, since it arrives a few
## times a second while they swing it.
func set_state_remote(degrees: float, p_latched: bool) -> void:
	if hinge == null:
		return
	if not is_inside_tree():
		apply_state(degrees, p_latched)
		return
	_kill_tween()
	p_latched = p_latched and latching
	_remote_latched = p_latched
	_remote_target = 0.0 if p_latched else clampf(degrees, 0.0, open_deg)
	if hinge.is_latched_closed() and _remote_target > 0.0:
		hinge.set_state_remote(hinge.get_rotation_deg(), false, false)


## Hang a model's leaf on the door after it is built: a mod whose door model loads
## late (a room GLB picked per quality tier) gives its own leaf mesh here. Placed as
## it stands in the world WITH THE DOOR SHUT, whatever the door is doing now; the
## plain leaf built in its place is hidden.
func dress_leaf(node: Node3D) -> void:
	if node == null or _pivot == null:
		return
	_adopt_at_rest(node, _pivot, Transform3D.IDENTITY)
	if _placeholder_leaf != null and _placeholder_leaf != node:
		_placeholder_leaf.hide()
	print("[Door] %s dressed with leaf '%s'" % [_name(), node.name])


## The same for the knob (any Node3D, turned with it) or the crash bar (a
## MeshInstance3D, which then slides in and out as the bar).
func dress_opener(node: Node3D) -> void:
	if node == null or _pivot == null:
		return
	if bar != null:
		var mi := node as MeshInstance3D
		if mi == null:
			push_warning("[Door] %s: a push bar is dressed with a MeshInstance3D, not '%s'"
				% [_name(), node.get_class()])
			return
		bar.set_value_no_signal(0.0)
		_adopt_at_rest(mi, _pivot, Transform3D.IDENTITY)
		bar.set_knob_mesh(mi)
	elif knob != null:
		knob.set_value_no_signal(0.5)
		var kp := knob.get_node(VRKnob.PIVOT_NAME) as Node3D
		_adopt_at_rest(node, kp, knob.transform * kp.transform)
	if _placeholder_opener != null and _placeholder_opener != node:
		_placeholder_opener.hide()
	print("[Door] %s dressed with opener '%s'" % [_name(), node.name])


## Move `node` under `parent` so that it sits where it stands now RELATIVE TO THE
## SHUT DOOR. `parent_in_pivot` is the parent's pose in HingePivot with the door shut.
func _adopt_at_rest(node: Node3D, parent: Node3D, parent_in_pivot: Transform3D) -> void:
	var world := node.global_transform
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node)
	node.transform = (global_transform * _frame.transform * parent_in_pivot).affine_inverse() * world


## Inside a spawned object, which saves and syncs this door's controls itself.
func is_room_door() -> bool:
	var p := get_parent()
	while p != null:
		if p.is_in_group("spawned"):
			return false
		p = p.get_parent()
	return true


# --- per frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	if hinge == null:
		return
	_drive_knob()
	_drive_bolt()
	if hinge.is_held() and _tween != null and _tween.is_valid():
		_kill_tween()   # a hand takes over from a desktop swing
	hinge.closer_hold = (_tween != null and _tween.is_valid()) or not is_nan(_remote_target)
	_drive_remote(delta)
	_watch_state()


## The crash bar pushed past its threshold: the latch lets go, and the hand pushing
## it walks the leaf open (DoorHinge.push_with).
func _on_bar_through() -> void:
	_remote_target = NAN
	var ctrl := bar.pushing_ctrl()
	if hinge.is_latched_closed():
		print("[Door] %s unlatched by the push bar (%.2f in)" % [_name(), bar.value])
		hinge.open()
	if ctrl != null:
		hinge.push_with(ctrl)


## The bolt follows the knob or the bar: out at rest, flush in the edge at the point
## the latch lets go. It springs back out as they do, open or shut, as a real one.
func _drive_bolt() -> void:
	if _bolt == null:
		return
	var t := 0.0
	if knob != null:
		t = clampf(knob.turn() / maxf(unlatch_turn, 0.01), 0.0, 1.0)
	elif bar != null:
		t = clampf(bar.value / maxf(bar.active_threshold, 0.01), 0.0, 1.0)
	if is_equal_approx(t, _bolt_in):
		return
	_bolt_in = t
	_bolt.transform = Transform3D(_bolt_rest.basis, _bolt_rest.origin + _bolt_dir * _bolt_travel * t)


## How far in the bolt is, 0 (out) to 1 (flush); -1 with no bolt.
func bolt_in() -> float:
	return _bolt_in if _bolt != null else -1.0


## The knob decides the latch, and hands its hand on to the leaf.
func _drive_knob() -> void:
	if knob == null:
		return
	var ctrl := knob.holding_ctrl()
	if ctrl != null:
		_remote_target = NAN
		if hinge.is_latched_closed():
			if knob.turn() >= unlatch_turn:
				print("[Door] %s unlatched by the knob (turn %.2f >= %.2f)" % [
					_name(), knob.turn(), unlatch_turn])
				hinge.open()
				hinge.grab_with(ctrl)
		elif not hinge.is_held():
			hinge.grab_with(ctrl)
	elif _knob_held_prev and not hinge.is_latched_closed() and not hinge.is_held() \
			and hinge.get_rotation_deg() <= hinge.close_latch_deg:
		# Let go of the knob with the door still at the strike: the bolt goes back in.
		print("[Door] %s knob released at %.1f deg: latched again" % [
			_name(), hinge.get_rotation_deg()])
		hinge.latch_closed()
	_knob_held_prev = ctrl != null


func _drive_remote(delta: float) -> void:
	if is_nan(_remote_target):
		return
	if hinge.is_held() or (knob != null and knob.is_held()) or (bar != null and bar.is_pushed()):
		_remote_target = NAN   # a hand here wins
		return
	var cur := hinge.get_rotation_deg()
	var next := move_toward(cur, _remote_target, REMOTE_SPEED_DEG * delta)
	if is_equal_approx(next, _remote_target):
		hinge.set_state_remote(next, _remote_latched, false)
		_remote_target = NAN
	else:
		hinge.set_rotation_deg_no_signal(next)
	_last_deg = hinge.get_rotation_deg()
	_last_latched = hinge.is_latched_closed()
	_sync_reported()


## Emit on change, log a latch change, and tell the session.
func _watch_state() -> void:
	var deg := hinge.get_rotation_deg()
	var is_latched_now := hinge.is_latched_closed()
	var moved := not is_equal_approx(deg, _last_deg)
	if is_latched_now != _last_latched:
		print("[Door] %s %s at %.1f deg" % [_name(),
			"LATCHED" if is_latched_now else "UNLATCHED", deg])
		if is_latched_now:
			latched.emit()
		else:
			unlatched.emit()
	if moved or is_latched_now != _last_latched:
		door_changed.emit(deg, is_latched_now)
	_last_latched = is_latched_now
	_last_deg = deg
	var now := Time.get_ticks_msec()
	if is_latched_now != _rep_latched:
		_report(deg, is_latched_now)
	elif absf(deg - _rep_deg) >= REPORT_MIN_DEG \
			and (not moved or now - _rep_at_ms >= REPORT_INTERVAL_MS):
		_report(deg, is_latched_now)


func _report(deg: float, is_latched_now: bool) -> void:
	_rep_deg = deg
	_rep_latched = is_latched_now
	_rep_at_ms = Time.get_ticks_msec()
	if not is_room_door():
		return
	if report_to.is_valid():
		report_to.call({"door": self, "deg": deg, "latched": is_latched_now})
		return
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("report_event"):
		nm.report_event(NetEvents.Event.EV_DOOR,
			{"door": self, "deg": deg, "latched": is_latched_now})


func _sync_reported() -> void:
	_rep_deg = get_angle_deg()
	_rep_latched = is_latched()
	_rep_at_ms = Time.get_ticks_msec()


func _swing_to(degrees: float, then_latch: bool, animate: bool) -> void:
	_kill_tween()
	var from := hinge.get_rotation_deg()
	if not animate or not is_inside_tree() or is_equal_approx(from, degrees):
		hinge.drive_to(degrees)
		if then_latch and not hinge.is_latched_closed():
			hinge.latch_closed()
		return
	var seconds := swing_seconds * clampf(absf(degrees - from) / 90.0, 0.25, 1.5)
	_tween = create_tween()
	_tween.tween_method(hinge.drive_to, from, degrees, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if then_latch:
		_tween.tween_callback(func() -> void:
			if hinge != null and not hinge.is_latched_closed():
				hinge.latch_closed())


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _name() -> String:
	return log_name if not log_name.is_empty() else str(name)


# --- building ----------------------------------------------------------------------

## The model route: take the named surfaces out of a one-mesh door. False when this
## door names none, or the model is not there (logged).
func _split_model(leaf_out: Array[Node3D], knob_out: Array[Node3D]) -> bool:
	if leaf_surfaces.is_empty():
		return false
	var no_opener := opener == Opener.NONE
	var mi := get_node_or_null(model) as MeshInstance3D if not model.is_empty() else null
	if mi == null:
		for n in find_children("*", "MeshInstance3D", true, false):
			mi = n as MeshInstance3D
			break
	if mi == null or mi.mesh == null:
		push_warning("[Door] %s names leaf surfaces but has no model mesh: building a plain leaf"
			% _name())
		return false
	var mesh := mi.mesh
	var to_door := global_transform.affine_inverse() * mi.global_transform
	var missing := PackedStringArray()
	var leaf_ids := DoorModelSplit.find_surfaces(mesh, leaf_surfaces, missing)
	var push_bar := opener == Opener.PUSH_BAR
	var knob_ids := DoorModelSplit.find_surfaces(mesh,
		PackedStringArray() if no_opener else (bar_surfaces if push_bar else knob_surfaces), missing)
	if not missing.is_empty():
		push_warning("[Door] %s: the model has no surface %s (it has %s)" % [
			_name(), ", ".join(missing), ", ".join(_surface_names(mesh))])
	if leaf_ids.is_empty():
		return false
	_leaf_box = DoorModelSplit.bounds(mesh, leaf_ids, to_door)
	var leaf_mesh := ArrayMesh.new()
	var knob_mesh := ArrayMesh.new()
	var frame_mesh := ArrayMesh.new()
	var z_min := _leaf_box.position.z
	var z_max := _leaf_box.end.z
	var knob_box := AABB()
	var knob_first := true
	var lock_pieces: Array[Dictionary] = []
	# The latch edge: the leaf's side away from the hinges.
	var latch_neg := hinge_side == HingeSide.POSITIVE_X
	var latch_x := _leaf_box.position.x if latch_neg else _leaf_box.end.x
	for i in mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i)
		if leaf_ids.has(i):
			DoorModelSplit.append_surface(leaf_mesh, mesh, i, mat)
		elif knob_ids.has(i) and push_bar:
			# A bar is all bar: taken whole.
			DoorModelSplit.append_surface(knob_mesh, mesh, i, mat)
			var bar_ids: Array[int] = [i]
			var ab := DoorModelSplit.bounds(mesh, bar_ids, to_door)
			knob_box = ab if knob_first else knob_box.merge(ab)
			knob_first = false
		elif knob_ids.has(i):
			# By PIECE (a lockset is several parts in one material): one standing
			# wholly out of a face turns with the knob; the biggest one CROSSING the
			# latch edge (out of it and on into the bore) is the bolt; the rest (the
			# faceplate on the edge and its screws) stays on the leaf.
			for piece in DoorModelSplit.pieces(mesh, i, to_door):
				var box: AABB = piece["box"]
				piece["surface"] = i
				piece["material"] = mat
				if box.position.z >= z_max - 0.001 or box.end.z <= z_min + 0.001:
					piece["to"] = "knob"
					knob_box = box if knob_first else knob_box.merge(box)
					knob_first = false
				elif box.position.x < latch_x - 0.001 and box.end.x > latch_x + 0.001:
					piece["to"] = "edge"
				else:
					piece["to"] = "leaf"
				lock_pieces.append(piece)
		else:
			DoorModelSplit.append_surface(frame_mesh, mesh, i, mat)
	# The bolt: the biggest piece crossing the latch edge. The faceplate stands wholly
	# OUTSIDE it (door.glb's is a slab 7 mm proud with its screws) and stays put: the
	# first version took the biggest piece outside the edge and slid the plate.
	var bolt_piece: Dictionary = {}
	for piece in lock_pieces:
		if piece["to"] == "edge" and (bolt_piece.is_empty()
				or (piece["box"] as AABB).get_volume() > (bolt_piece["box"] as AABB).get_volume()):
			bolt_piece = piece
	var bolt_mesh := ArrayMesh.new()
	for piece in lock_pieces:
		var dst := knob_mesh if piece["to"] == "knob" else (bolt_mesh if piece == bolt_piece else leaf_mesh)
		DoorModelSplit.append_surface(dst, mesh, piece["surface"], piece["material"], piece["tris"])
	if not bolt_piece.is_empty():
		var bb: AABB = bolt_piece["box"]
		_bolt_travel = (latch_x - bb.position.x) if latch_neg else (bb.end.x - latch_x)
		_bolt_dir = Vector3(1.0 if latch_neg else -1.0, 0.0, 0.0)
		_bolt = MeshInstance3D.new()
		_bolt.name = "Bolt"
		(_bolt as MeshInstance3D).mesh = bolt_mesh
		add_child(_bolt)
		_bolt.global_transform = mi.global_transform
		print("[Door] %s: the latch bolt stands %.1f mm out of the edge" % [_name(), _bolt_travel * 1000.0])
	print("[Door] %s split '%s': %d leaf, %d knob, %d frame surfaces" % [_name(), mi.name,
		leaf_mesh.get_surface_count(), knob_mesh.get_surface_count(),
		frame_mesh.get_surface_count()])
	mi.mesh = frame_mesh if frame_mesh.get_surface_count() > 0 else null
	var leaf_mi := MeshInstance3D.new()
	leaf_mi.name = "Leaf"
	leaf_mi.mesh = leaf_mesh
	add_child(leaf_mi)
	leaf_mi.global_transform = mi.global_transform
	leaf_out.append(leaf_mi)
	if knob_mesh.get_surface_count() > 0:
		var knob_mi := MeshInstance3D.new()
		knob_mi.name = "Bar" if push_bar else "Knob"
		knob_mi.mesh = knob_mesh
		add_child(knob_mi)
		knob_mi.global_transform = mi.global_transform
		knob_out.append(knob_mi)
		_knob_at = Vector3(knob_box.get_center().x, knob_box.get_center().y,
			_leaf_box.get_center().z)
		_bar_box = knob_box
	else:
		_knob_at = _default_knob_at()
		_bar_box = _default_bar_box()
	return true


## Authored `Leaf` / `Knob` children, else a plain box and ball.
func _adopt_or_build(leaf_out: Array[Node3D], knob_out: Array[Node3D]) -> void:
	_leaf_box = AABB(Vector3(-width * 0.5, bottom_gap, leaf_center_z - thickness * 0.5),
		Vector3(width, height, thickness))
	_knob_at = _default_knob_at()
	var leaf := get_node_or_null("Leaf") as Node3D
	if leaf == null:
		var mi := MeshInstance3D.new()
		mi.name = "Leaf"
		var box := BoxMesh.new()
		box.size = _leaf_box.size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.93, 0.91, 0.86)
		mat.roughness = 0.6
		box.material = mat
		mi.mesh = box
		add_child(mi)
		mi.position = _leaf_box.get_center()
		leaf = mi
	leaf_out.append(leaf)
	_placeholder_leaf = leaf
	if opener == Opener.NONE:
		return
	if opener == Opener.PUSH_BAR:
		_bar_box = _default_bar_box()
		var bar_node := get_node_or_null("Bar") as Node3D
		if bar_node == null:
			bar_node = _build_bar_mesh()
		_placeholder_opener = bar_node
		knob_out.append(bar_node)
		return
	var knob_node := get_node_or_null("Knob") as Node3D
	if knob_node == null:
		knob_node = _build_knob_mesh()
	_placeholder_opener = knob_node
	knob_out.append(knob_node)


## Where the bar goes with no model to say: across the push face (the one the door
## swings AWAY from), centred on the leaf.
func _default_bar_box() -> AABB:
	var sz := 1.0 if swing == Swing.TOWARD_POSITIVE_Z else -1.0
	var push_face := _leaf_box.position.z if sz > 0.0 else _leaf_box.end.z
	var length := bar_length if bar_length > 0.0 else maxf(_leaf_box.size.x - 0.16, 0.2)
	var centre := Vector3(_leaf_box.get_center().x, bar_height, push_face - sz * bar_standoff)
	var size := Vector3(length, bar_section.x, bar_section.y)
	return AABB(centre - size * 0.5, size)


## A plain aluminium bar.
func _build_bar_mesh() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "Bar"
	var box := BoxMesh.new()
	box.size = _bar_box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.79, 0.8)
	mat.metallic = 0.8
	mat.roughness = 0.35
	box.material = mat
	mi.mesh = box
	add_child(mi)
	mi.position = _bar_box.get_center()
	return mi


func _default_knob_at() -> Vector3:
	if knob_position != Vector2.ZERO:
		return Vector3(knob_position.x, knob_position.y, _leaf_box.get_center().z)
	var latch_x := _leaf_box.position.x + 0.06 if hinge_side == HingeSide.POSITIVE_X \
		else _leaf_box.end.x - 0.06
	return Vector3(latch_x, 0.9, _leaf_box.get_center().z)


## A round brass knob each side of the leaf on one spindle, placed at the knob.
func _build_knob_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "Knob"
	add_child(root)
	root.position = _knob_at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.62, 0.32)
	mat.metallic = 0.9
	mat.roughness = 0.3
	var half := _leaf_box.size.z * 0.5
	var spindle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.009
	cyl.bottom_radius = 0.009
	cyl.height = _leaf_box.size.z + 0.11
	cyl.material = mat
	spindle.mesh = cyl
	spindle.rotation.x = PI * 0.5
	root.add_child(spindle)
	for side in [-1.0, 1.0]:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.028
		sphere.height = 0.05
		sphere.material = mat
		ball.mesh = sphere
		ball.position = Vector3(0.0, 0.0, side * (half + 0.055))
		root.add_child(ball)
	return root


func _build_rig(leaf_meshes: Array[Node3D], knob_meshes: Array[Node3D]) -> void:
	var hx := 1.0 if hinge_side == HingeSide.POSITIVE_X else -1.0
	var sz := 1.0 if swing == Swing.TOWARD_POSITIVE_Z else -1.0
	# The hinge line: the leaf's hinge edge, on the face it swings toward (a butt
	# hinge's knuckle is on that face, which is what lets the leaf clear its frame).
	var hinge_at := Vector3(_leaf_box.end.x if hx > 0.0 else _leaf_box.position.x, 0.0,
		_leaf_box.end.z if sz > 0.0 else _leaf_box.position.z)
	# VRHinge: at 0 the leaf points along the pivot's -Z and opens toward its +Y about
	# its X. So -Z runs from the hinge to the latch edge (-hx along the door's X), +Y
	# is the face it swings toward, and X = Y x Z comes out vertical, up or down as
	# those two require.
	var y_axis := Vector3(0.0, 0.0, sz)
	var z_axis := Vector3(hx, 0.0, 0.0)
	var frame_basis := Basis(y_axis.cross(z_axis), y_axis, z_axis)
	_frame = Node3D.new()
	_frame.name = "HingeFrame"
	add_child(_frame)
	_frame.transform = Transform3D(frame_basis, hinge_at)
	_pivot = Node3D.new()
	_pivot.name = "HingePivot"
	_frame.add_child(_pivot)
	for m in leaf_meshes:
		m.reparent(_pivot, true)
	var to_pivot := _frame.transform.affine_inverse()   # door frame -> pivot, shut
	if _bolt != null:
		_bolt.reparent(_pivot, true)
		_bolt_rest = _bolt.transform
		_bolt_dir = (to_pivot.basis * _bolt_dir).normalized()
	var leaf_pivot := to_pivot * _leaf_box
	# The leaf's collision, which the player and loose objects meet as it swings.
	if leaf_collision:
		var body := AnimatableBody3D.new()
		body.name = "LeafBody"
		body.collision_layer = 1
		body.collision_mask = 0
		# Off: with sync_to_physics an AnimatableBody3D follows only its OWN local
		# transform, and this one is carried by its parent (HingePivot) turning, so it
		# stayed where the shut leaf was, an invisible wall across the open doorway.
		body.sync_to_physics = false
		_pivot.add_child(body)
		body.position = leaf_pivot.get_center()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = leaf_pivot.size
		cs.shape = shape
		body.add_child(cs)
	# The grab box over the leaf, a little proud of both faces (the pivot's Y).
	hinge = DoorHinge.new()
	hinge.name = "DoorHinge"
	hinge.target = _pivot
	hinge.min_deg = 0.0
	hinge.max_deg = open_deg
	hinge.start_closed = latched_at_start and latching
	hinge.has_latch = latching
	hinge.position = leaf_pivot.get_center()
	var grab := CollisionShape3D.new()
	grab.name = "CollisionShape3D"
	var grab_box := BoxShape3D.new()
	grab_box.size = leaf_pivot.size + Vector3(0.0, 0.03, 0.0)
	grab.shape = grab_box
	hinge.add_child(grab)
	_pivot.add_child(hinge)
	hinge.opener = null
	hinge.leaf_width = _leaf_box.size.x
	hinge.self_closing = self_closing
	hinge.closer_speed_deg = closer_speed_deg
	if opener == Opener.PUSH_BAR or opener == Opener.NONE:
		if opener == Opener.PUSH_BAR:
			_build_bar(knob_meshes, to_pivot, sz)
		if not hinge.start_closed:
			hinge.set_state_remote(0.0, false, false)
		return
	# The hint on the latch side, at the knob's height.
	hinge.place_hint(to_pivot * _knob_at - hinge.position + Vector3(0.0, 0.06, 0.0))
	# The knob: its axle through the leaf (the door's Z), at the knob.
	knob = DoorKnob.new()
	knob.name = "DoorKnob"
	var reach := _leaf_box.size.z * 0.5 + 0.075
	knob.reach = reach
	var knob_cs := CollisionShape3D.new()
	var knob_shape := BoxShape3D.new()
	knob_shape.size = Vector3(0.075, 0.075, reach * 2.0)
	knob_cs.shape = knob_shape
	knob.add_child(knob_cs)
	var knob_pivot := Node3D.new()
	knob_pivot.name = VRKnob.PIVOT_NAME
	knob.add_child(knob_pivot)
	_pivot.add_child(knob)
	knob.transform = to_pivot * Transform3D(Basis(), _knob_at)
	for m in knob_meshes:
		m.reparent(knob_pivot, true)
	knob.pointer_pressed.connect(toggle)
	hinge.opener = knob
	if not hinge.start_closed:
		hinge.set_state_remote(0.0, false, false)


## The crash bar: a DoorPushBar at the bar's middle, its +Z into the door (the way
## it is pushed, which is the way the door swings), riding the leaf.
func _build_bar(bar_meshes: Array[Node3D], to_pivot: Transform3D, sz: float) -> void:
	bar = DoorPushBar.new()
	bar.name = "DoorPushBar"
	bar.travel = bar_travel
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _bar_box.size
	cs.shape = shape
	bar.add_child(cs)
	var face := Basis.IDENTITY if sz > 0.0 else Basis(Vector3.UP, PI)
	_pivot.add_child(bar)
	bar.transform = to_pivot * Transform3D(face, _bar_box.get_center())
	for m in bar_meshes:
		var mi := m as MeshInstance3D
		if mi == null:
			for n in m.find_children("*", "MeshInstance3D", true, false):
				mi = n as MeshInstance3D
				break
		if mi == null:
			push_warning("[Door] %s: the bar '%s' has no mesh to slide; it stays put" % [_name(), m.name])
			m.reparent(_pivot, true)
			continue
		mi.reparent(_pivot, true)
		bar.set_knob_mesh(mi)
	bar.toggle_requested.connect(_on_bar_through)
	bar.pointer_pressed.connect(toggle)
	hinge.opener = bar
	hinge.place_hint(to_pivot * _bar_box.get_center() - hinge.position
		+ (to_pivot.basis * Vector3(0.0, 0.0, -sz)) * 0.06)


func _surface_names(mesh: Mesh) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		out.append((mesh as ArrayMesh).surface_get_name(i) if mesh is ArrayMesh
			else (mat.resource_name if mat != null else str(i)))
	return out
