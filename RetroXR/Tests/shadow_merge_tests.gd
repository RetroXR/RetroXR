## ShadowMerge self-tests -- one shadow-only mesh per object body instead of a shadow draw per part.
##
##     "$godot" --headless --path RetroXR res://Tests/shadow_merge_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## The dummy renderer keeps mesh surfaces, so the merge runs for real here: which parts join the proxy and
## which keep their own shadow, the proxy's own settings, the kill switch putting every part back, the
## watchdog taking out a part that moved, and a duplicate of a merged object. How the shadows LOOK is a
## windowed A/B of the real room (performance.md, "Shadow draws merged per object").
extends "res://Tests/test_suite.gd"

var _merge: ShadowMerge


func _ready() -> void:
	suite_tag = "shadow_merge"
	ShadowMerge.enabled = true
	_merge = ShadowMerge.new()
	add_child(_merge)
	await _run()
	_finish()


func _box(parent: Node, name: String, size: float, at := Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = Vector3(size, size, size)
	mi.mesh = box
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _pivot(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n


func _see_through() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _proxies(body: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for i in body.get_child_count(true):
		var c := body.get_child(i, true)
		if c.has_meta(ShadowMerge.META_PROXY):
			out.append(c as MeshInstance3D)
	return out


func _verts(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _main_proxy(body: Node) -> MeshInstance3D:
	for p in _proxies(body):
		if p.visibility_range_end == 0.0:
			return p
	return null


func _make_object() -> RigidBody3D:
	var obj := RigidBody3D.new()
	obj.name = "Console"
	obj.freeze = true
	_box(obj, "Shell", 0.30)
	_box(obj, "Base", 0.25, Vector3(0, -0.2, 0))
	_box(_pivot(obj, "ButtonPivot"), "Cap", 0.012, Vector3(0, 0.16, 0))
	_box(_pivot(obj, "LidPivot"), "Lid", 0.20, Vector3(0, 0.3, 0))
	var label := MeshInstance3D.new()
	label.name = "Label"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.05)
	label.mesh = quad
	label.material_override = _see_through()
	label.position = Vector3(0, 0, 0.151)
	obj.add_child(label)
	_box(obj, "Glass", 0.08, Vector3(0.1, 0.1, 0.1), _see_through())
	var off := _box(obj, "NoShadow", 0.1, Vector3(-0.1, 0, 0))
	off.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 2:
		var far := _box(obj, "Far%d" % i, 0.05, Vector3(0.2 * i, 0.4, 0))
		far.visibility_range_end = 5.0
	var plug := RigidBody3D.new()
	plug.name = "Plug"
	plug.freeze = true
	obj.add_child(plug)
	_box(plug, "PlugShell", 0.04)
	_box(plug, "PlugTip", 0.02, Vector3(0, 0.03, 0))
	var cart := Node3D.new()
	cart.name = "Cart"
	obj.add_child(cart)
	_box(cart, "CartShell", 0.1, Vector3(0, 0.25, 0))
	_box(cart, "CartBoard", 0.05, Vector3(0, 0.25, 0))
	cart.add_to_group("spawned")
	obj.add_to_group("spawned")
	return obj


func _merged(obj: Node) -> bool:
	return _main_proxy(obj) != null


func _run() -> void:
	var obj := _make_object()
	add_child(obj)
	var ok := await _wait_until(func() -> bool: return _merged(obj) and _merged(obj.get_node("Plug")) \
		and not _proxies(obj.get_node("Cart")).is_empty(), 6.0)
	_ok(ok, "merge/a spawned object gets its shadow proxy within a few seconds", str(ShadowMerge.stats()))
	if not ok:
		obj.queue_free()
		return
	var proxy := _main_proxy(obj)
	var shell := obj.get_node("Shell") as MeshInstance3D
	var base := obj.get_node("Base") as MeshInstance3D
	var cap := obj.get_node("ButtonPivot/Cap") as MeshInstance3D
	var lid := obj.get_node("LidPivot/Lid") as MeshInstance3D
	_ok(proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"proxy/the proxy draws shadows only")
	_ok(proxy.is_in_group("outline_exclude") and proxy.material_override != null,
		"proxy/the highlight outline and PropLighting pass it by (outline_exclude, a material override)")
	_ok(not obj.get_children().has(proxy), "proxy/it is an INTERNAL child: walkers and duplicate() never see it")
	_eq(_verts(proxy.mesh), _verts(shell.mesh) + _verts(base.mesh) + _verts(cap.mesh),
		"proxy/it holds the shell, the base and the small button cap, nothing else")
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ok(shell.cast_shadow == off and base.cast_shadow == off and cap.cast_shadow == off,
		"parts/merged parts cast nothing themselves")
	_eq(int(shell.get_meta(ShadowMerge.META_PART, -1)), GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"parts/a merged part remembers the mode it had")
	_ok(lid.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"movers/a part under a pivot bigger than SMALL_MOVER keeps its own shadow")
	_ok((obj.get_node("Label") as MeshInstance3D).cast_shadow == off,
		"decals/a flat see-through label casts nothing (the shell under it does)")
	_ok((obj.get_node("Glass") as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"decals/a see-through part with depth keeps its own shadow")
	_ok(not (obj.get_node("NoShadow") as MeshInstance3D).has_meta(ShadowMerge.META_PART),
		"parts/a part that cast nothing is left alone")
	var far_proxy: MeshInstance3D = null
	for p in _proxies(obj):
		if p.visibility_range_end == 5.0:
			far_proxy = p
	_ok(far_proxy != null and _verts(far_proxy.mesh) == 2 * _verts((obj.get_node("Far0") as MeshInstance3D).mesh),
		"ranges/parts with a detail range merge apart, and their proxy carries the range")
	_ok(_main_proxy(obj.get_node("Plug")) != null and _verts(proxy.mesh) < 4 * _verts(shell.mesh),
		"bodies/a physics body inside the object (a plug) gets its own proxy, out of the object's")
	_ok(not _proxies(obj.get_node("Cart")).is_empty(),
		"objects/another spawned object inside this one (a seated cart) is merged on its own")

	# The kill switch puts every part back and takes every proxy away; on again rebuilds.
	ShadowMerge.set_enabled(false)
	_ok(_proxies(obj).is_empty() and shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and (obj.get_node("Label") as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and not shell.has_meta(ShadowMerge.META_PART), "switch/off restores every part and drops the proxies")
	ShadowMerge.set_enabled(true)
	ok = await _wait_until(func() -> bool: return _merged(obj), 6.0)
	_ok(ok, "switch/on again merges again")
	proxy = _main_proxy(obj)

	# Hiding a part re-merges without it.
	var proxy_id := proxy.get_instance_id()
	base.visible = false
	ok = await _wait_until(func() -> bool: return _merged(obj) and _main_proxy(obj).get_instance_id() != proxy_id, 4.0)
	_ok(ok and _verts(_main_proxy(obj).mesh) == _verts(shell.mesh) + _verts(cap.mesh),
		"visibility/a part hidden on its object leaves the merge")
	base.visible = true
	await _wait_until(func() -> bool: return _merged(obj) and _verts(_main_proxy(obj).mesh) > _verts(shell.mesh) + _verts(cap.mesh), 4.0)

	# A duplicate: its parts carry the original mode on their meta, and it shares the proxy mesh.
	var dup := obj.duplicate() as RigidBody3D
	dup.position = Vector3(2, 0, 0)
	add_child(dup)
	ok = await _wait_until(func() -> bool: return _merged(dup), 6.0)
	_ok(ok and int((dup.get_node("Shell") as Node).get_meta(ShadowMerge.META_PART, -1)) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"duplicate/a copy of a merged object merges with its parts' real modes")
	_ok(ok and _main_proxy(dup).mesh == _main_proxy(obj).mesh, "duplicate/identical objects share one proxy mesh")
	_eq(_proxies(dup).size(), _proxies(obj).size(), "duplicate/the copy has no stray proxy of the original's")
	dup.queue_free()

	# The watchdog: a part found to have moved on its body leaves the merge and casts its own shadow again.
	shell.position += Vector3(0, 0.05, 0)
	ok = await _wait_until(func() -> bool: return shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and _merged(obj), 5.0)
	_ok(ok and _verts(_main_proxy(obj).mesh) == _verts(base.mesh) + _verts(cap.mesh),
		"watchdog/a part that moved on its body is a mover from then on")

	# Taken out of the tree: every part casts as it did.
	remove_child(obj)
	_ok(base.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not base.has_meta(ShadowMerge.META_PART),
		"removal/an object leaving the tree gets its parts' shadows back")
	obj.free()
