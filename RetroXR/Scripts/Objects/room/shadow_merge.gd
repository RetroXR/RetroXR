## ShadowMerge — one shadow draw per object instead of one per part.
##
## A part costs a draw in the main pass and another in the shadow pass of EVERY shadow-casting light
## that reaches it. Measured in the Starlight Arcade autosave (222 objects, 17 shadowed lights, RTX 5070
## laptop, 2026-11-14): 8,100 draws a frame, 6,100 of them shadow passes, and the render thread was the
## frame (10 ms; the GPU 5). The objects' 3,100 surfaces are already about one per material, so merging
## what they SHOW buys little; a shadow has no material, so every part that never moves on its body can
## cast through ONE mesh. Letting each object cast from its largest part only took the frame 9.0 -> 6.0 ms.
##
## What it does, per spawned object, a few objects a frame:
##   • every MeshInstance3D that casts, stays put on its physics body and draws opaque triangles is
##     merged, in the body's own space, into a shadows-only MeshInstance3D child of that body ("ShadowMerge");
##     the parts keep drawing exactly as before, with `cast_shadow` OFF (the old mode in META_PART);
##   • a body with fewer than two such parts is left alone;
##   • parts with a detail range (LOD levels) merge per range, and the proxy carries that range, so the
##     levels still swap exactly as they did;
##   • a moving part under SMALL_MOVER (a button cap, a wheel, a switch) merges too: it moves a millimeter
##     or two, which no shadow shows, and the watchdog leaves it be;
##   • a flat see-through part (a label or logo decal lying on the shell, thinner than DECAL_THICK) casts
##     nothing: the shell under it already casts that shadow.
##
## What it leaves casting on its own: bigger parts under a hinge, a pivot, a button, a stick, a lid, a
## door ... (by node name or script, see MOVER_WORDS) or under an animated track; see-through surfaces
## with depth and alpha-cut ones; skinned and blend-shape meshes; ropes (a VerletRope rebuilds its mesh
## every frame) and everything under one; parts already OFF or SHADOWS_ONLY. Another spawned object
## inside this one (a seated cartridge) is its own object.
##
## Kept honest at run time: a part that is added, removed, hidden, shown or given another mesh re-merges
## its object; a part found to have MOVED on its body (a watchdog visits each object about once a second)
## is marked a mover for good and re-merged out. The proxy is in the `outline_exclude` group and carries a
## material override, so the highlight's outline copies and PropLighting pass it by.
##
## Desktop Forward+ only (QualityManager adds it): the Quest's props are on a baked volume and cast nothing.
class_name ShadowMerge
extends Node

## On a part whose shadow this silenced: the cast mode it had (survives a duplicate of the object).
const META_PART := &"_shadow_merge_cast"
## On a proxy this made.
const META_PROXY := &"_shadow_merge_proxy"
const PROXY_NAME := "ShadowMerge"

## Node names and script paths that mean "this moves on its body" (lower case, substring match).
const MOVER_WORDS: Array[String] = [
	"pivot", "hinge", "button", "btn", "stick", "lid", "door", "dial", "switch", "knob", "trigger",
	"slider", "lever", "tray", "wheel", "reel", "flap", "latch", "spindle", "crank", "needle", "tonearm",
]

## A moving part whose largest side is under this (meters) merges anyway, and is not watched.
const SMALL_MOVER := 0.04
## A see-through part whose smallest side is under this (meters) is a decal: it stops casting.
const DECAL_THICK := 0.0015

## A changed object waits this long for more changes before it is merged again (models attach over frames).
const QUIET_MSEC := 400
## How often the spawned group is swept for new objects.
const SCAN_MSEC := 1000
## Main-thread time a frame may spend merging (an object is never split; one may overrun).
const BUDGET_USEC := 2500
## Watchdog: each object about once this often.
const WATCH_PERIOD_MSEC := 1000

## Surfaces read back from the GPU, at most this many a frame. One read is two or three FULL GPU stalls
## (RenderingDevice.buffer_get_data flushes and waits out every frame in flight, for the vertex, attribute and
## index buffers each) and the main thread waits through them on the render thread: the Starlight Arcade's
## ~2,900 surfaces read back as fast as the merge could take them were the room crawling after it opened
## (2026-11-17: 1,600 `mesh_get_surface ... synchronizations` warnings in one session).
const READS_PER_FRAME := 2

## Kill switch (a probe A/Bs it inside one process: launches differ by ~2 ms). Use set_enabled().
static var enabled: bool = true
## (A surface read back once is kept in memory and on disk by MeshArraysCache, so the next launch builds its proxies
## with no GPU read; the objects' own geometry reads share it.)

static var _instance: ShadowMerge

var _material: StandardMaterial3D
## object instance id -> record (see _record)
var _objects: Dictionary = {}
## object instance id -> msec it is due
var _queue: Dictionary = {}
var _next_scan := 0
var _watch_keys: Array = []
var _watch_i := 0
var _watch_carry := 0.0
## signature -> WeakRef(ArrayMesh): identical objects share one proxy mesh
var _proxy_meshes: Dictionary = {}
## GPU reads this frame may still make (READS_PER_FRAME).
var _reads_left := READS_PER_FRAME
## The counts as the queue last started filling (empty while it is empty): for _report_batch.
var _batch: Dictionary = {}


static func set_enabled(on: bool) -> void:
	enabled = on
	if is_instance_valid(_instance):
		_instance._apply_enabled()


## How many objects and proxies are live, and how many parts cast through them.
static func stats() -> Dictionary:
	var out := {"objects": 0, "proxies": 0, "parts": 0, "readbacks": 0, "disk_hits": 0, "disk_writes": 0}
	if not is_instance_valid(_instance):
		return out
	out.merge(MeshArraysCache.counts, true)
	for rec: Dictionary in _instance._objects.values():
		out["objects"] += 1
		out["proxies"] += (rec["proxies"] as Array).size()
		out["parts"] += (rec["parts"] as Array).size()
	return out


func _ready() -> void:
	_instance = self
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Parts are often single-sided shells; a two-sided caster cannot leak light through an open back.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.disconnect(_on_node_removed)
	for id: int in _objects.keys():
		_unmerge(id)
	_objects.clear()
	if _instance == self:
		_instance = null


func _apply_enabled() -> void:
	if enabled:
		_next_scan = 0
		return
	for id: int in _objects.keys():
		_unmerge(id)
	_objects.clear()
	_queue.clear()


func _process(delta: float) -> void:
	if not enabled:
		return
	_reads_left = READS_PER_FRAME
	var now := Time.get_ticks_msec()
	if now >= _next_scan:
		_next_scan = now + SCAN_MSEC
		for n: Node in get_tree().get_nodes_in_group("spawned"):
			var id := n.get_instance_id()
			if not _objects.has(id) and not _queue.has(id) and n is Node3D:
				_queue[id] = now + QUIET_MSEC
	if not _queue.is_empty():
		if _batch.is_empty():
			_batch = MeshArraysCache.counts.duplicate()
			_batch["at"] = now
			_batch["objects"] = _objects.size()
		var t0 := Time.get_ticks_usec()
		for id: int in _queue.keys():
			if int(_queue[id]) > now:
				continue
			_queue.erase(id)
			var obj := instance_from_id(id) as Node3D
			if obj == null or not obj.is_inside_tree():
				_forget(id)
				continue
			_merge(obj)
			# Out of GPU reads: the rest wait for the next frame (a walk that finds it cannot finish is waste).
			if _reads_left <= 0 or Time.get_ticks_usec() - t0 > BUDGET_USEC:
				break
		if _queue.is_empty():
			_report_batch(now)
	_watch(delta)


## One line when the queue runs dry: how long it took and where its surfaces came from. A room opened on a warm
## cache reads back nothing; a run of readbacks there means meshes the disk cache cannot name (MeshArraysCache._disk_key).
func _report_batch(now: int) -> void:
	var reads := int(MeshArraysCache.counts["readbacks"]) - int(_batch["readbacks"])
	var hits := int(MeshArraysCache.counts["disk_hits"]) - int(_batch["disk_hits"])
	if reads > 0 or hits > 0:
		print("[ShadowMerge] %d objects merged in %d ms: %d surfaces read back from the GPU, %d from the disk cache" % [
			_objects.size() - int(_batch["objects"]), now - int(_batch["at"]), reads, hits])
	_batch = {}


# ── events ─────────────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if not enabled or not (node is MeshInstance3D) or node.has_meta(META_PROXY):
		return
	var obj := _owner_object(node)
	if obj != null:
		_touch(obj.get_instance_id())


func _on_node_removed(node: Node) -> void:
	if node.has_meta(META_PART):
		# Wherever it goes next, it casts as it did; its object re-merges without it.
		var mi := node as GeometryInstance3D
		if mi != null:
			mi.cast_shadow = int(mi.get_meta(META_PART)) as GeometryInstance3D.ShadowCastingSetting
		node.remove_meta(META_PART)
		var obj := _owner_object(node)
		if obj != null:
			_touch(obj.get_instance_id())
		return
	var id := node.get_instance_id()
	if _objects.has(id):
		_forget(id)


func _on_part_visibility(id: int) -> void:
	_touch(id)


## Re-merge an object we know (or are about to) once it has been quiet for QUIET_MSEC.
func _touch(id: int) -> void:
	if _objects.has(id) or _queue.has(id):
		_queue[id] = Time.get_ticks_msec() + QUIET_MSEC


## The spawned object a node belongs to: its nearest ancestor (or itself) in the "spawned" group.
func _owner_object(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n.is_in_group("spawned"):
			return n as Node3D
		n = n.get_parent()
	return null


# ── merge / unmerge ────────────────────────────────────────────────────────────

func _record(obj: Node3D) -> Dictionary:
	var id := obj.get_instance_id()
	if not _objects.has(id):
		_objects[id] = {"obj": weakref(obj), "proxies": [], "parts": [], "movers": {}, "watched": []}
	return _objects[id]


## Put every part of the object back as it was and drop its proxies. Keeps the record (its movers).
func _unmerge(id: int) -> void:
	var rec: Dictionary = _objects.get(id, {})
	if rec.is_empty():
		return
	for p: Array in rec["parts"]:
		var mi := (p[0] as WeakRef).get_ref() as GeometryInstance3D
		if is_instance_valid(mi) and mi.has_meta(META_PART):
			mi.cast_shadow = int(mi.get_meta(META_PART)) as GeometryInstance3D.ShadowCastingSetting
			mi.remove_meta(META_PART)
	rec["parts"] = []
	for w: WeakRef in rec["proxies"]:
		var proxy := w.get_ref() as Node
		if is_instance_valid(proxy):
			proxy.get_parent().remove_child(proxy)
			proxy.free()
	rec["proxies"] = []
	for pair: Array in rec["watched"]:
		var node := (pair[0] as WeakRef).get_ref() as Node3D
		if is_instance_valid(node) and node.visibility_changed.is_connected(pair[1]):
			node.visibility_changed.disconnect(pair[1])
	rec["watched"] = []


func _forget(id: int) -> void:
	_unmerge(id)
	_objects.erase(id)
	_queue.erase(id)


func _merge(obj: Node3D) -> void:
	var id := obj.get_instance_id()
	var rec := _record(obj)
	_unmerge(id)
	var movers: Dictionary = rec["movers"]
	var animated := _animated_nodes(obj)
	var vis_cb := _on_part_visibility.bind(id)
	# group key "body id|layers" -> {"body": Node3D, "layers": int, "parts": Array[MeshInstance3D]}
	var groups: Dictionary = {}
	# [node, shown (relative to the object), mover, body]
	var stack: Array = [[obj, true, false, obj]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var node: Node = top[0]
		var shown: bool = top[1]
		var mover: bool = top[2]
		var body: Node3D = top[3]
		if node != obj:
			if node.is_in_group("spawned") or node.has_meta(META_PROXY) or node.is_class("VerletRope"):
				continue
			if node is PhysicsBody3D:
				body = node as Node3D
				mover = false
			elif not mover:
				mover = animated.has(node) or _is_mover_node(node)
		if node is Node3D and node != obj:
			shown = shown and (node as Node3D).visible
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# Hidden parts are watched too: shown later, they must join (or leave) the merge.
			mi.visibility_changed.connect(vis_cb)
			rec["watched"].append([weakref(mi), vis_cb])
			# A stray copy from a duplicated object carries the original mode on its meta.
			if mi.has_meta(META_PART):
				mi.cast_shadow = int(mi.get_meta(META_PART)) as GeometryInstance3D.ShadowCastingSetting
				mi.remove_meta(META_PART)
			if shown:
				var kind := _eligible(mi)
				var sides := _sides(mi) if kind != KEEP else Vector2.ZERO
				var moving := mover or movers.has(mi.get_instance_id())
				if kind == DECAL and sides.y < DECAL_THICK:
					mi.set_meta(META_PART, int(mi.cast_shadow))
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					rec["parts"].append([weakref(mi), Transform3D(), mi.mesh, weakref(body), false])
				elif kind == MERGE and (not moving or sides.x < SMALL_MOVER):
					var range_key := "%s,%s,%s,%s,%d" % [mi.visibility_range_begin, mi.visibility_range_end,
						mi.visibility_range_begin_margin, mi.visibility_range_end_margin, int(mi.visibility_range_fade_mode)]
					var key := "%d|%d|%s" % [body.get_instance_id(), mi.layers, range_key]
					if not groups.has(key):
						groups[key] = {"body": body, "layers": mi.layers, "parts": [], "range_of": mi, "watch": []}
					(groups[key]["parts"] as Array).append(mi)
					(groups[key]["watch"] as Array).append(not moving)
		for child in node.get_children():
			stack.append([child, shown, mover, body])
	# [group, rels, signature, shared proxy mesh or null]; and every mesh a proxy still to be built needs.
	var plans: Array = []
	var needed: Array[Mesh] = []
	for g: Dictionary in groups.values():
		var parts: Array = g["parts"]
		if parts.size() < 2:
			continue
		var body: Node3D = g["body"]
		var to_body := body.global_transform.affine_inverse()
		var rels: Array[Transform3D] = []
		var sig := PackedStringArray([str(g["layers"])])
		for mi: MeshInstance3D in parts:
			var rel := to_body * mi.global_transform
			rels.append(rel)
			sig.append("%d:%s" % [mi.mesh.get_instance_id(), rel])
		var key := "|".join(sig)
		var shared: ArrayMesh = null
		if _proxy_meshes.has(key):
			shared = (_proxy_meshes[key] as WeakRef).get_ref() as ArrayMesh
		if shared == null:
			for mi: MeshInstance3D in parts:
				if not needed.has(mi.mesh):
					needed.append(mi.mesh)
		plans.append([g, rels, key, shared])
	if not _fetch(needed):
		# This frame's GPU reads are spent and some surface is still missing: build nothing yet and come back
		# next frame. Until then its parts cast as they always did (the decals' OFF is recorded and undone).
		_queue[id] = Time.get_ticks_msec()
		return
	for plan: Array in plans:
		var g: Dictionary = plan[0]
		var parts: Array = g["parts"]
		var body: Node3D = g["body"]
		var rels: Array[Transform3D] = plan[1]
		var key: String = plan[2]
		var mesh: ArrayMesh = plan[3]
		if mesh == null:
			mesh = _build_mesh(parts, rels)
			if mesh == null:
				continue
			_proxy_meshes[key] = weakref(mesh)
			if _proxy_meshes.size() > 4096:
				_prune_proxy_meshes()
		var proxy := MeshInstance3D.new()
		proxy.name = PROXY_NAME
		proxy.mesh = mesh
		proxy.material_override = _material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.layers = int(g["layers"])
		var like: MeshInstance3D = g["range_of"]
		proxy.visibility_range_begin = like.visibility_range_begin
		proxy.visibility_range_end = like.visibility_range_end
		proxy.visibility_range_begin_margin = like.visibility_range_begin_margin
		proxy.visibility_range_end_margin = like.visibility_range_end_margin
		proxy.visibility_range_fade_mode = like.visibility_range_fade_mode
		proxy.set_meta(META_PROXY, true)
		proxy.add_to_group("outline_exclude")
		body.add_child(proxy, false, Node.INTERNAL_MODE_BACK)
		rec["proxies"].append(weakref(proxy))
		for i in parts.size():
			var mi: MeshInstance3D = parts[i]
			mi.set_meta(META_PART, int(mi.cast_shadow))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rec["parts"].append([weakref(mi), rels[i], mi.mesh, weakref(body), bool((g["watch"] as Array)[i])])


func _is_mover_node(node: Node) -> bool:
	var name_l := String(node.name).to_lower()
	var script := node.get_script() as Script
	var path_l := script.resource_path.get_file().to_lower() if script != null else ""
	name_l = name_l.replace("sticker", "")
	for w in MOVER_WORDS:
		if name_l.contains(w) or (not path_l.is_empty() and path_l.contains(w)):
			return true
	return false


## Every node an AnimationPlayer under `obj` has a track on.
func _animated_nodes(obj: Node) -> Dictionary:
	var hit := {}
	for n: Node in obj.find_children("*", "AnimationPlayer", true, false):
		var player := n as AnimationPlayer
		var base := player.get_node_or_null(player.root_node)
		if base == null:
			continue
		for lib_name in player.get_animation_library_list():
			var lib := player.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				for t in anim.get_track_count():
					var target := base.get_node_or_null(NodePath(String(anim.track_get_path(t)).get_slice(":", 0)))
					if target != null:
						hit[target] = true
	return hit


const MERGE := 0
const DECAL := 1
const KEEP := 2


## MERGE (opaque triangles that can cast through the proxy), DECAL (see-through, alpha-blended: casts
## nothing if it is flat), or KEEP (leave it as it is).
func _eligible(mi: MeshInstance3D) -> int:
	if mi.mesh == null or mi.skin != null:
		return KEEP
	var mode := mi.cast_shadow
	if mode != GeometryInstance3D.SHADOW_CASTING_SETTING_ON and mode != GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
		return KEEP
	var mesh := mi.mesh
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		if am.get_blend_shape_count() > 0:
			return KEEP
		for s in am.get_surface_count():
			if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return KEEP
			if am.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES:
				return KEEP
	elif not (mesh is PrimitiveMesh) or mesh is PointMesh or mesh is RibbonTrailMesh or mesh is TubeTrailMesh:
		return KEEP
	var see_through := mi.transparency > 0.0
	for s in mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat is BaseMaterial3D:
			match (mat as BaseMaterial3D).transparency:
				BaseMaterial3D.TRANSPARENCY_DISABLED:
					pass
				BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
					see_through = true
				_:
					return KEEP
	return DECAL if see_through else MERGE


## Largest side of a part as it stands in the world, and its thinnest side in its own frame (a tilted
## label's world box is not thin), in meters.
func _sides(mi: MeshInstance3D) -> Vector2:
	var size := (mi.global_transform * mi.get_aabb()).size
	var big := maxf(size.x, maxf(size.y, size.z))
	var local := mi.get_aabb().size * mi.global_transform.basis.get_scale().abs()
	return Vector2(big, minf(local.x, minf(local.y, local.z)))


## Have every surface of these meshes in hand, reading back from the GPU only what memory and the disk cache
## (MeshArraysCache) cannot give, and no more than this frame's READS_PER_FRAME. False while any is still missing.
func _fetch(meshes: Array[Mesh]) -> bool:
	var whole := true
	for mesh in meshes:
		for s in mesh.get_surface_count():
			if not MeshArraysCache.known(mesh, s).is_empty():
				continue
			if _reads_left <= 0:
				whole = false
				continue
			_reads_left -= 1
			MeshArraysCache.read_back(mesh, s)
	return whole


## Positions, normals and indices of one surface; read back if nothing else has it (_fetch has, by now).
func _surface(mesh: Mesh, s: int) -> Array:
	return MeshArraysCache.surface(mesh, s)


func _prune_proxy_meshes() -> void:
	for key: String in _proxy_meshes.keys():
		if (_proxy_meshes[key] as WeakRef).get_ref() == null:
			_proxy_meshes.erase(key)


func _build_mesh(parts: Array, rels: Array[Transform3D]) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in parts.size():
		var mi: MeshInstance3D = parts[i]
		var rel: Transform3D = rels[i]
		var nrel := Transform3D(rel.basis.inverse().transposed(), Vector3.ZERO)
		for s in mi.mesh.get_surface_count():
			var surf := _surface(mi.mesh, s)
			var base := verts.size()
			verts.append_array(rel * (surf[1] as PackedVector3Array))
			normals.append_array(nrel * (surf[2] as PackedVector3Array))
			var src: PackedInt32Array = surf[3]
			var at := indices.size()
			indices.resize(at + src.size())
			for k in src.size():
				indices[at + k] = src[k] + base
	if verts.is_empty() or indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── watchdog ───────────────────────────────────────────────────────────────────

## Visit each merged object about once a WATCH_PERIOD: a part that moved on its body, changed mesh or
## went away re-merges its object (a mover for good).
func _watch(delta: float) -> void:
	if _objects.is_empty():
		return
	if _watch_i >= _watch_keys.size():
		_watch_keys = _objects.keys()
		_watch_i = 0
	_watch_carry += float(_watch_keys.size()) * delta * 1000.0 / float(WATCH_PERIOD_MSEC)
	while _watch_carry >= 1.0 and _watch_i < _watch_keys.size():
		_watch_carry -= 1.0
		var id: int = _watch_keys[_watch_i]
		_watch_i += 1
		if _queue.has(id):
			continue
		var rec: Dictionary = _objects.get(id, {})
		if rec.is_empty():
			continue
		for p: Array in rec["parts"]:
			var mi := (p[0] as WeakRef).get_ref() as MeshInstance3D
			var body := (p[3] as WeakRef).get_ref() as Node3D
			if not is_instance_valid(mi) or not is_instance_valid(body) or mi.mesh != p[2]:
				_queue[id] = Time.get_ticks_msec()
				break
			if not bool(p[4]):
				continue
			var rel := body.global_transform.affine_inverse() * mi.global_transform
			var was: Transform3D = p[1]
			if rel.origin.distance_squared_to(was.origin) > 1e-8 or not _basis_close(rel.basis, was.basis):
				(rec["movers"] as Dictionary)[mi.get_instance_id()] = true
				_queue[id] = Time.get_ticks_msec()
				break
	if _watch_carry > float(_watch_keys.size()):
		_watch_carry = 0.0


func _basis_close(a: Basis, b: Basis) -> bool:
	return (a.x - b.x).length_squared() < 1e-6 and (a.y - b.y).length_squared() < 1e-6 \
		and (a.z - b.z).length_squared() < 1e-6
