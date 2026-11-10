## What made a room restore fast, kept that way (Tools/perf/restore_perf_probe measures it; this
## checks the behaviour each speed-up rests on still gives the answers the slow way gave):
##   controllers/  XrControllers.all() is what the whole-tree find_children it replaced said
##   hooks/        ModHooks' cached class matching agrees with _matches, and follows new watchers
##   outline/      a highlight traces its outline the first time it SHOWS, not when it is built
##   prefetch/     a restore asks for a system's model scene with its GLBs, before any spawn
##   godot --headless --path RetroXR res://Tests/restore_speed_tests.tscn
extends "res://Tests/test_suite.gd"


func _ready() -> void:
	suite_tag = "restore_speed"
	if _wanted("controllers/"):
		await _controllers()
	if _wanted("hooks/"):
		_hooks()
	if _wanted("outline/"):
		await _outline()
	if _wanted("prefetch/"):
		_prefetch()
	_finish()


func _walk() -> Array[Node]:
	return get_tree().root.find_children("*", "XRController3D", true, false)


func _controllers() -> void:
	_ok(XrControllers.all(get_tree()) == _walk(), "controllers/at the start: the same list as a tree walk")
	var origin := XROrigin3D.new()
	add_child(origin)
	var a := XRController3D.new()
	origin.add_child(a)
	_ok(XrControllers.all(get_tree()).has(a) and XrControllers.all(get_tree()) == _walk(),
		"controllers/a controller added is in the next answer")
	var b := XRController3D.new()
	origin.add_child(b)
	var listed := XrControllers.all(get_tree())
	_ok(listed == _walk() and listed.find(a) < listed.find(b), "controllers/two, in tree order")
	listed.clear()
	_ok(XrControllers.all(get_tree()).size() == _walk().size(), "controllers/the answer is a copy: clearing it changes nothing")
	origin.remove_child(a)
	_ok(not XrControllers.all(get_tree()).has(a) and XrControllers.all(get_tree()) == _walk(),
		"controllers/one taken out of the tree (not freed) is gone from the answer")
	a.free()
	b.queue_free()
	await get_tree().process_frame
	_ok(XrControllers.all(get_tree()) == _walk(), "controllers/one freed is gone too")
	# Moved while it stays in the tree: nothing to invalidate, and the order is still the walk's.
	var c := XRController3D.new()
	origin.add_child(c)
	var d := XRController3D.new()
	add_child(d)
	_ok(XrControllers.all(get_tree()) == _walk(), "controllers/controllers under different parents, as the walk orders them")
	origin.queue_free()
	d.queue_free()
	await get_tree().process_frame


func _script_with_connector(connector: String) -> GDScript:
	var gd := GDScript.new()
	gd.source_code = "extends Node3D\nvar connector := \"%s\"\n" % connector
	gd.reload()
	return gd


func _hooks() -> void:
	var hooks := ModHooks.new(null)
	var noop := func(_n: Node) -> void: pass
	var watched: Array[StringName] = [&"Node3D", &"MeshInstance3D", &"VRButton", &"Area3D", &"n64_av_plug", &"RetroTV"]
	for cls: StringName in watched:
		hooks.watch_nodes("test", cls, noop)
	var plugged := Node3D.new()
	plugged.set_script(_script_with_connector("n64_av_plug"))
	var other_plug := Node3D.new()
	other_plug.set_script(_script_with_connector("snes_plug"))
	var nodes: Array[Node] = [Node.new(), Node3D.new(), MeshInstance3D.new(), VRButton.new(), Area3D.new(),
		plugged, other_plug, Control.new()]
	var agree := true
	var bad := ""
	# Twice: the second pass is answered from the caches the first filled.
	for round_i in 2:
		for node: Node in nodes:
			var hits: Dictionary = hooks._classes_of(node)
			for cls: StringName in watched:
				if hits.has(cls) != ModHooks._matches(node, cls):
					agree = false
					bad = "%s/%s" % [node.get_class(), cls]
	_ok(agree, "hooks/cached matches agree with _matches for every node and watched class", bad)
	_ok(hooks._classes_of(plugged).has(&"n64_av_plug") and not hooks._classes_of(other_plug).has(&"n64_av_plug"),
		"hooks/a connector is matched by its value, per node, though the two share a script shape")
	_ok(hooks._classes_of(nodes[3]).has(&"VRButton") and hooks._classes_of(nodes[3]).has(&"Area3D"),
		"hooks/a script class and its native base both match")
	# A watcher added once the caches are full must be seen.
	hooks.watch_nodes("late", &"Node", noop)
	_ok(hooks._classes_of(nodes[0]).has(&"Node"), "hooks/a class watched later matches a node class already cached")
	hooks.drop_owner("late")
	_ok(not hooks._classes_of(nodes[0]).has(&"Node"), "hooks/and is forgotten when its owner is dropped")
	for node: Node in nodes:
		node.free()


func _outline() -> void:
	var body := XRToolsPickable.new()
	var src := MeshInstance3D.new()
	src.mesh = BoxMesh.new()
	body.add_child(src)
	var hl := PickableHighlight.new()
	body.add_child(hl)
	add_child(body)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := hl.overlay_of(src)
	_ok(overlay != null, "outline/a pickable's mesh gets an overlay when it is built")
	_ok(overlay != null and overlay.mesh == null, "outline/...with no outline traced yet")
	body.highlight_updated.emit(body, true)
	_ok(overlay != null and overlay.mesh != null and overlay.visible, "outline/hovered, it is traced and shown")
	_ok(overlay != null and overlay.mesh == PickableHighlight._get_outline_mesh(src.mesh),
		"outline/...from the per-mesh cache")
	body.highlight_updated.emit(body, false)
	_ok(overlay != null and not overlay.visible, "outline/and hidden again when the hover ends")
	# A control's outline: the same, through WidgetOutline.
	var cap := MeshInstance3D.new()
	cap.mesh = BoxMesh.new()
	add_child(cap)
	var holder := Node3D.new()
	add_child(holder)
	var wo := WidgetOutline.attach(holder)
	wo.set_source(cap)
	_ok(wo.mesh == null, "outline/a widget outline is not traced when it is given its source")
	wo.sync(false)
	_ok(wo.mesh == null and not wo.visible, "outline/...nor while it stays hidden")
	wo.sync(true)
	_ok(wo.mesh != null and wo.visible, "outline/...and is traced the first time it shows")
	body.queue_free()
	cap.queue_free()
	holder.queue_free()
	await get_tree().process_frame


func _prefetch() -> void:
	var picked := ""
	var scene := ""
	for id: Variant in SystemModelRegistry.all_ids():
		var row := SystemModelRegistry.row_for(str(id))
		var path := str(row.get("scene", ""))
		if SystemModelRegistry.is_available(str(id)) and not path.is_empty() and ResourceLoader.exists(path):
			picked = str(id)
			scene = path
			break
	_ok(not picked.is_empty(), "prefetch/the registry has a model with a scene to test with")
	if picked.is_empty():
		return
	var sp := ScenePersistence.new("restore_speed_tests")
	var row := SystemModelRegistry.row_for(picked)
	var paths: Array = sp._entry_asset_paths({"type": "system", "model_id": picked})
	_ok(paths.has(scene), "prefetch/a system entry asks for its model's scene (%s)" % picked)
	var all_required := true
	for p: String in row.get("requires", []):
		all_required = all_required and paths.has(p)
	_ok(all_required, "prefetch/...and every GLB its row requires")
	_ok(sp._entry_asset_paths({"type": "battery_aa"}).is_empty() and sp._entry_asset_paths(42).is_empty(),
		"prefetch/an entry with no external model asks for nothing")
	var objects: Array = [{"type": "system", "model_id": picked}, {"type": "system", "model_id": picked}]
	_eq(sp.prefetch_assets(objects), paths.size(), "prefetch/two of the same model ask for its assets once")
