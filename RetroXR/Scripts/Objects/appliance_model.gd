## ApplianceModel — a RETRO XR appliance's three mobile levels (RetroXR-models' generic/vcr, dvd-player,
## surround-receiver, turntable), one shown at a time by camera distance, every level animated together.
##
## The scene keeps its own nodes (buttons, slots, ports, knobs) and asks this node to dress them:
## adopt_button() copies a key's mesh into the scene's VRButton (the key presses with the button, and survives a
## combo TV hiding the housing); attach_part() hangs a moving part of EVERY level under a scene node the script
## already turns (a platter, a knob pivot); play()/seek() run the GLB's own animations on every level.
## LOD0 keeps each key its own mesh; LOD1/LOD2 carry the keys inside one Body, so a copied key is drawn only as
## far as LOD0 is.
class_name ApplianceModel
extends Node3D

## The three levels, close to far (the GLBs under res://imported-assets/appliances/<item>/).
@export var level_scenes: Array[PackedScene] = []
## LOD0 -> LOD1 (m).
@export var switch_distance: float = 1.5
## LOD1 -> LOD2 (m).
@export var far_distance: float = 3.5
@export var hysteresis: float = 0.15

var levels: Array[Node3D] = []
var players: Array[AnimationPlayer] = []


func _ready() -> void:
	_build()


func _build() -> void:
	if not levels.is_empty():
		return
	for scene in level_scenes:
		if scene == null:
			push_warning("[Appliance] %s: a level scene is missing" % get_path())
			continue
		var level := scene.instantiate() as Node3D
		add_child(level)
		levels.append(level)
		players.append(level.find_child("AnimationPlayer", true, false) as AnimationPlayer)
	_apply_ranges()
	print("[Appliance] %s: %d levels, switches at %.2f / %.2f m" % [name, levels.size(), switch_distance, far_distance])


func _apply_ranges() -> void:
	for i in levels.size():
		for n in levels[i].find_children("*", "GeometryInstance3D", true, false):
			_range(n as GeometryInstance3D, i)


func _range(g: GeometryInstance3D, i: int) -> void:
	var begin := 0.0 if i == 0 else (switch_distance if i == 1 else far_distance)
	var end := switch_distance if i == 0 else (far_distance if i == 1 else 0.0)
	g.visibility_range_begin = begin
	g.visibility_range_end = end
	g.visibility_range_begin_margin = hysteresis if i > 0 else 0.0
	g.visibility_range_end_margin = hysteresis if i < levels.size() - 1 else 0.0
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## The named node of a level (0 = close).
func part(part_name: String, level: int = 0) -> Node3D:
	_build()
	if level >= levels.size():
		return null
	return levels[level].find_child(part_name, true, false) as Node3D


## The named node on every level that has it.
func parts(part_name: String) -> Array[Node3D]:
	_build()
	var out: Array[Node3D] = []
	for i in levels.size():
		var p := part(part_name, i)
		if p:
			out.append(p)
	return out


## A part's transform in the space of `space` (default: this node's parent, i.e. the appliance's root).
func part_transform(part_name: String, space: Node3D = null) -> Transform3D:
	var p := part(part_name)
	if p == null:
		push_warning("[Appliance] %s: no part %s" % [name, part_name])
		return Transform3D.IDENTITY
	var base := space if space else get_parent() as Node3D
	return base.global_transform.affine_inverse() * p.global_transform


## Hide a part on every level (the engine draws it some other way).
func hide_part(part_name: String) -> void:
	for p in parts(part_name):
		p.visible = false


## Dress a scene VRButton with the model's key `part_name`: the button moves to the key's face (the key's origin),
## its ButtonMesh takes the key's mesh, the box IS the key (no margin: the ray takes what is drawn and nothing
## beside it), the press travels `travel` along the key's -Z, and
## the model's own key is hidden on LOD0. The copied cap is drawn as far as LOD0 is (farther, the keys are in Body).
## `exact`: a key whose box would overlap its neighbours' (a four-way ring's arcs round an OK key) takes its own
## triangles as its shape instead, and a fingertip presses it only over its own face (footprint_gate).
func adopt_button(button: VRButton, part_name: String, travel: float = 0.0015, exact: bool = false) -> void:
	var key := part(part_name) as MeshInstance3D
	if key == null or button == null:
		push_warning("[Appliance] %s: cannot adopt %s onto %s" % [name, part_name, button])
		return
	var parent := button.get_parent() as Node3D
	button.transform = parent.global_transform.affine_inverse() * key.global_transform
	var cap := button.get_node_or_null("ButtonMesh") as MeshInstance3D
	if cap == null:
		cap = MeshInstance3D.new()
		cap.name = "ButtonMesh"
		button.add_child(cap)
	cap.mesh = key.mesh
	cap.material_override = null
	cap.transform = Transform3D.IDENTITY
	_range(cap, 0)
	for i in key.get_surface_override_material_count():
		cap.set_surface_override_material(i, key.get_surface_override_material(i))
	button.set_button_mesh(cap)
	cap.visible = true          # set_button_mesh hides any node named ButtonMesh: here that is the adopted cap
	button.depress_axis = Vector3(0, 0, -1)
	button.depress_depth = travel
	var shape := button.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape and exact:
		shape.shape = key.mesh.create_trimesh_shape()
		shape.transform = Transform3D.IDENTITY
		button.press_gate = footprint_gate(cap, 0.0)      # no reach: a ring's keys are 0.6 mm apart
	elif shape:
		var box := BoxShape3D.new()
		var ab := key.get_aabb()
		box.size = ab.size
		shape.shape = box
		shape.position = ab.get_center()
	var legend := button.get_node_or_null("ButtonLabel") as Node3D
	if legend:
		legend.visible = false        # the key carries its own icon
	key.visible = false


## The close level's drawn bounds in `space`'s frame: every visible mesh still under the model, less the parts named
## in `except`. A part attach_part hung elsewhere and a key adopt_button hid are not in it; nor is anything the
## scene draws itself (a display quad, a cap).
func bounds(space: Node3D, except: Array[String] = []) -> AABB:
	_build()
	if levels.is_empty():
		return AABB()
	return node_bounds(levels[0], space, except)


## What `root` and everything visible under it draws, in `space`'s frame (a part attach_part hung under a pivot).
static func node_bounds(root: Node, space: Node3D, except: Array[String] = []) -> AABB:
	var out := AABB()
	var first := true
	var to_space := space.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if except.has(String(n.name)):
			continue
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			var box: AABB = (to_space * g.global_transform) * g.get_aabb()
			if box.size != Vector3.ZERO:
				out = box if first else out.merge(box)
				first = false
		stack.append_array(n.get_children())
	return out


## Make `shape` exactly `box` (in the shape's parent's frame): a box, no margin. The shape is duplicated first —
## a scene's sub_resource is shared by every copy of the scene in the room.
static func fit_box(shape: CollisionShape3D, box: AABB) -> void:
	if shape == null or box.size == Vector3.ZERO:
		return
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	shape.transform = Transform3D(Basis.IDENTITY, box.get_center())


## `box` less `pocket`: up to six boxes that cover the rest of it (a control set deeper into the housing than the
## pointer's 5 mm ENCLOSURE_DEPTH is unreachable inside a single box).
static func carve(box: AABB, pocket: AABB) -> Array[AABB]:
	var hole := box.intersection(pocket)
	if hole.size == Vector3.ZERO or hole.size.x <= 0.0 or hole.size.y <= 0.0 or hole.size.z <= 0.0:
		return [box]
	var out: Array[AABB] = []
	var rest := box
	for axis in 3:
		var lo := rest.position[axis]
		var hi := rest.end[axis]
		if hole.position[axis] > lo:
			var a := rest
			a.size[axis] = hole.position[axis] - lo
			out.append(a)
		if hole.end[axis] < hi:
			var b := rest
			b.position[axis] = hole.end[axis]
			b.size[axis] = hi - hole.end[axis]
			out.append(b)
		rest.position[axis] = hole.position[axis]
		rest.size[axis] = hole.size[axis]
	return out


## Fit a body's (or a PointerArea's) collision to `boxes`, given in `shape`'s parent's frame: `shape` takes the
## first, and siblings named `<shape>Carve<n>` the rest (made, or dropped, as many as needed).
static func fit_collision(shape: CollisionShape3D, boxes: Array[AABB]) -> void:
	if shape == null or boxes.is_empty():
		return
	var parent := shape.get_parent()
	fit_box(shape, boxes[0])
	for i in range(1, maxi(boxes.size(), 8)):
		var extra := parent.get_node_or_null("%sCarve%d" % [shape.name, i]) as CollisionShape3D
		if i >= boxes.size():
			if extra:
				extra.queue_free()
			continue
		if extra == null:
			extra = CollisionShape3D.new()
			extra.name = "%sCarve%d" % [shape.name, i]
			parent.add_child(extra)
		extra.disabled = shape.disabled
		fit_box(extra, boxes[i])


## Fit every shape in `shapes` (the body's and the PointerArea's) to what the close level draws, less `except`,
## each in its own parent's frame. No margin: the desktop ray takes the object only where it is drawn, and a key
## standing on the face is never inside a shell padded out past it.
func fit_shapes(shapes: Array[CollisionShape3D], except: Array[String] = []) -> void:
	for shape in shapes:
		if shape == null:
			continue
		var box := bounds(shape.get_parent() as Node3D, except)
		fit_box(shape, box)
		print("[Appliance] %s: %s fitted to the model, %s mm" % [name, shape.get_path(), (box.size * 1000.0).snapped(Vector3.ONE * 0.1)])


## A fingertip presses a key only over its own face: inside the outline of the cap's front faces (its local +Z, the
## way it faces) grown `reach`, and no higher than `hover` over the face. VRButton's touch is a radius round the
## key's origin, which on a ring reaches the arcs either side and OK.
static func footprint_gate(cap: MeshInstance3D, reach: float = 0.001, hover: float = 0.003) -> Callable:
	var tris: Array[PackedVector2Array] = []
	var faces := cap.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if absf((b - a).cross(c - a).normalized().z) > 0.5:     # the face and its parallels: one outline
			tris.append(PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)]))
	var top := cap.mesh.get_aabb().end.z
	var bottom := cap.mesh.get_aabb().position.z
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(reach, 0), Vector2(-reach, 0), Vector2(0, reach),
		Vector2(0, -reach)]
	return func(tip: Vector3) -> bool:
		if not is_instance_valid(cap):
			return false
		var p := cap.global_transform.affine_inverse() * tip
		if p.z > top + hover or p.z < bottom:
			return false
		for o in offsets:
			var q := Vector2(p.x, p.y) + o
			for t in tris:
				if Geometry2D.is_point_in_polygon(q, t):
					return true
		return false


## Hang `part_name` of EVERY level under `under` (a node the scene script already turns), keeping where it is now.
## `under` should already sit on the part's pivot, so turning it turns the part about its own axis.
func attach_part(part_name: String, under: Node3D) -> void:
	for p in parts(part_name):
		var g := p.global_transform
		p.get_parent().remove_child(p)
		under.add_child(p)
		p.global_transform = g


func has_animation(anim: String) -> bool:
	return not players.is_empty() and players[0] != null and players[0].has_animation(anim)


func animation_length(anim: String) -> float:
	return players[0].get_animation(anim).length if has_animation(anim) else 0.0


## Run one of the GLB's animations on every level.
func play(anim: String, speed: float = 1.0) -> void:
	for p in players:
		if p:
			p.play(anim, -1.0, speed)


## Hold an animation at a time on every level (a hand-driven phase, or a restored state).
func seek(anim: String, t: float) -> void:
	for p in players:
		if p == null:
			continue
		if p.current_animation != anim:
			p.play(anim)
		p.pause()
		p.seek(t, true)


## Every mesh of every level (a highlight or an outline wants them).
func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for level in levels:
		for n in level.find_children("*", "MeshInstance3D", true, false):
			out.append(n as MeshInstance3D)
	return out
