## Where a slot restore's time goes, READ-ONLY (nothing is written): the slot's objects are
## replayed one at a time the way instantiate_objects_async does, each timed, then the
## connection pass, then the frames that follow (deferred _ready work lands there).
## Prints a per-type table, slowest first. Run WINDOWED: headless loads no shell threaded
## and draws nothing, so it measures a different restore.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/perf/restore_perf_probe.tscn -- --file=/path/slot.json [--room=<scene path>]
##
##   --noprefetch  the control: no ScenePersistence.prefetch_assets, each entry's models
##                 requested only when the loop reaches it (the restore before 2026-11-10)
##   --boot        start the boot's shell warm alongside, as SceneManager._warm_models does
##   --roomload=sync|thread|sub --room-id=<id>
##                 only time loading a room's scene: load() as BootScene does, a threaded
##                 request, or one with use_sub_threads (dependencies loaded in parallel)
##   --twice       restore again once everything is cached: what is left is node building
extends Node3D

var _file := ""
var _room := ""
var _twice := false
var _prefetch := true
var _boot := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			_file = a.substr(7)
		elif a.begins_with("--room="):
			_room = a.substr(7)
		elif a == "--noprefetch":
			_prefetch = false
		elif a == "--boot":
			_boot = true
		elif a == "--twice":
			_twice = true
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roomload="):
			await _time_room_load(a.substr(11))
			get_tree().quit(0)
			return
	var root: Node = self
	if not _room.is_empty():
		var t := Time.get_ticks_usec()
		var packed := load(_room) as PackedScene
		var t_load := Time.get_ticks_usec()
		var inst := packed.instantiate()
		var t_inst := Time.get_ticks_usec()
		add_child(inst)
		print("[probe] room load %.1f ms, instantiate %.1f ms, enter tree %.1f ms" % [
			(t_load - t) / 1000.0, (t_inst - t_load) / 1000.0, (Time.get_ticks_usec() - t_inst) / 1000.0])
		root = inst
	for i in 10:
		await get_tree().process_frame
	var sp := ScenePersistence.new("probe_readonly")
	var t_read := Time.get_ticks_usec()
	var objects: Variant = sp._read_objects(_file)
	if not objects is Array:
		print("[probe] could not read ", _file)
		get_tree().quit(1)
		return
	print("[probe] read+parse %.1f ms, %d objects" % [(Time.get_ticks_usec() - t_read) / 1000.0, (objects as Array).size()])
	var by_type: Dictionary = {}
	var spawned: Dictionary = {}
	var entries: Dictionary = {}
	var held: Dictionary = {}
	var t_all := Time.get_ticks_usec()
	if _boot:
		# What SceneManager._warm_models starts a few frames into a real boot.
		ModelWarmer.request_shells()
		ModelWarmer.skip_stand_ins()
		ModelWarmer.warm_shells(self)
	if _prefetch:
		sp.prefetch_assets(objects as Array)
	print("[probe] leg prefetch=%s boot=%s" % [_prefetch, _boot])
	var acquire_total := 0
	var spawn_total := 0
	for entry: Variant in objects:
		var type := str((entry as Dictionary).get("type", "?")) if entry is Dictionary else "?"
		if type == "system":
			type = "system:" + str((entry as Dictionary).get("model_id", (entry as Dictionary).get("systemid", "")))
		var t0 := Time.get_ticks_usec()
		await sp._acquire_entry_assets(entry)
		var t1 := Time.get_ticks_usec()
		sp._spawn_entry(root, entry, spawned, entries, held)
		var t2 := Time.get_ticks_usec()
		acquire_total += t1 - t0
		spawn_total += t2 - t1
		var row: Dictionary = by_type.get(type, {"n": 0, "spawn": 0, "max": 0, "acquire": 0})
		row["n"] += 1
		row["spawn"] += t2 - t1
		row["max"] = maxi(row["max"], t2 - t1)
		row["acquire"] += t1 - t0
		by_type[type] = row
	var t_spawned := Time.get_ticks_usec()
	sp._hold_still_group(root, held)
	var t_c := Time.get_ticks_usec()
	for id: int in spawned:
		sp._restore_entry(root, id, spawned, entries)
	var t_c2 := Time.get_ticks_usec()
	for id: int in spawned:
		sp._restore_rope_layouts(spawned[id], entries[id])
	var t_r := Time.get_ticks_usec()
	sp._let_go(held)
	print("[probe] pass 1 %.1f ms (spawn %.1f, acquire wait %.1f)  connections %.1f ms  rope layouts %.1f ms" % [
		(t_spawned - t_all) / 1000.0, spawn_total / 1000.0, acquire_total / 1000.0,
		(t_c2 - t_c) / 1000.0, (t_r - t_c2) / 1000.0])
	var keys := by_type.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return by_type[a]["spawn"] > by_type[b]["spawn"])
	for k: Variant in keys:
		var r: Dictionary = by_type[k]
		print("[probe]   %-40s n=%3d  spawn %8.1f ms  max %7.1f  acquire %7.1f" % [
			k, r["n"], r["spawn"] / 1000.0, r["max"] / 1000.0, r["acquire"] / 1000.0])
	# The frames after: deferred builds (captive cables, shells) land here.
	var pso0 := _pso_counts()
	var tex0: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var frames: Array = []
	var last := Time.get_ticks_usec()
	for i in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(now - last)
		last = now
		if i == 0 or i == 119:
			var pso := _pso_counts()
			print("[probe] after frame %d: pipelines compiled %s (before %s), texture +%.1f MiB" % [i,
				str(pso), str(pso0), (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) - tex0) / 1048576.0])
	var after := 0
	for f: int in frames:
		after += f
	var sorted := frames.duplicate()
	sorted.sort()
	sorted.reverse()
	print("[probe] next 120 frames %.1f ms total; worst %s ms" % [after / 1000.0,
		str(sorted.slice(0, 8).map(func(x: int) -> float: return snappedf(x / 1000.0, 0.1)))])
	print("[probe] first 10 frames %s ms" % str(frames.slice(0, 10).map(func(x: int) -> float: return snappedf(x / 1000.0, 0.1))))
	print("[probe] TOTAL restore-to-settled %.1f ms" % ((Time.get_ticks_usec() - t_all) / 1000.0))
	if OS.get_cmdline_user_args().has("--runtime-textures"):
		_runtime_texture_census()
	if _twice:
		# Everything cached now: what is left is building nodes on the main thread.
		for node: Node in get_tree().get_nodes_in_group("spawned"):
			node.queue_free()
		for i in 30:
			await get_tree().process_frame
		var spawned2: Dictionary = {}
		var entries2: Dictionary = {}
		var held2: Dictionary = {}
		var by2: Dictionary = {}
		var s0 := Time.get_ticks_usec()
		for entry: Variant in objects:
			var type := str((entry as Dictionary).get("type", "?")) if entry is Dictionary else "?"
			var a0 := Time.get_ticks_usec()
			await sp._acquire_entry_assets(entry)
			var a1 := Time.get_ticks_usec()
			sp._spawn_entry(root, entry, spawned2, entries2, held2)
			by2[type] = by2.get(type, 0) + Time.get_ticks_usec() - a1
		print("[probe] SECOND pass 1 %.1f ms" % ((Time.get_ticks_usec() - s0) / 1000.0))
		var k2 := by2.keys()
		k2.sort_custom(func(a: Variant, b: Variant) -> bool: return by2[a] > by2[b])
		for k: Variant in k2.slice(0, 15):
			print("[probe]   2nd %-36s spawn %8.1f ms" % [k, by2[k] / 1000.0])
		sp._let_go(held2)
		# The same frames as after the first pass, with every texture already on the GPU:
		# what is left of the slow first frame is not uploads.
		var f2: Array = []
		var l2 := Time.get_ticks_usec()
		for i in 10:
			await get_tree().process_frame
			var n2 := Time.get_ticks_usec()
			f2.append(snappedf((n2 - l2) / 1000.0, 0.1))
			l2 = n2
		print("[probe] SECOND first 10 frames %s ms" % str(f2))
	get_tree().quit(0)


func _pso_counts() -> Array:
	return [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)]



func _time_room_load(mode: String) -> void:
	var room_id := "bedroom"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room-id="):
			room_id = a.substr(10)
	var path := RoomCatalog.path_of(room_id)
	for i in 5:
		await get_tree().process_frame
	var t := Time.get_ticks_usec()
	var frames := 0
	var longest := 0
	var packed: PackedScene = null
	if mode == "sync":
		packed = load(path) as PackedScene
	else:
		ResourceLoader.load_threaded_request(path, "", mode == "sub")
		var last := Time.get_ticks_usec()
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			longest = maxi(longest, now - last)
			last = now
			frames += 1
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	var t_load := Time.get_ticks_usec()
	var inst := packed.instantiate() if packed != null else null
	var t_inst := Time.get_ticks_usec()
	print("[probe] room '%s' %s: load %.1f ms (%d frames, longest %.1f ms), instantiate %.1f ms" % [room_id, mode,
		(t_load - t) / 1000.0, frames, longest / 1000.0, (t_inst - t_load) / 1000.0])
	if inst != null:
		inst.free()


## Textures made at RUN time (not an imported .ctex): every SubViewport in the tree, and every
## texture on a material that has no res:// file of its own, by what owns it. Estimated GPU bytes:
## an image texture by its format (no mipmaps counted: asking would read each one back from the GPU), a viewport as RGBA8 (RGBA16F when HDR) plus 4-byte depth, times
## its MSAA samples. Imported textures are Tools/perf/texture_census.py's (from a --verbose log).
func _runtime_texture_census() -> void:
	var rows: Array = []
	for n: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		var sv := n as SubViewport
		var px := sv.size.x * sv.size.y
		var color := 8 if sv.use_hdr_2d else 4
		var samples: int = [1, 2, 4, 8][clampi(sv.msaa_3d, 0, 3)] if not sv.disable_3d else 1
		var bytes: int = px * (color + (0 if sv.disable_3d else 4)) * samples
		rows.append([bytes, "viewport %dx%d msaa%d hdr=%s upd=%d" % [sv.size.x, sv.size.y, samples, sv.use_hdr_2d, sv.render_target_update_mode],
			_owner_label(sv)])
	var seen: Dictionary = {}
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mats: Array = [gi.material_override, gi.material_overlay]
		var mi := gi as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_active_material(i))
		for mat: Variant in mats:
			_collect_textures(mat, gi, seen, rows, 0)
	var by: Dictionary = {}
	var total := 0
	for r: Array in rows:
		total += int(r[0])
		var key := str(r[1]).get_slice(" ", 0) + " / " + str(r[2])
		by[key] = int(by.get(key, 0)) + int(r[0])
	print("[probe] runtime textures: %d, est. %.1f MiB" % [rows.size(), total / 1048576.0])
	var keys := by.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return by[a] > by[b])
	for k: Variant in keys.slice(0, 20):
		print("[probe]   %8.1f MiB  %s" % [by[k] / 1048576.0, k])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r: Array in rows.slice(0, 20):
		print("[probe]   %7.1f MiB  %s  (%s)" % [r[0] / 1048576.0, r[1], r[2]])


func _collect_textures(mat: Variant, gi: Node, seen: Dictionary, rows: Array, depth: int) -> void:
	if not mat is Material or depth > 4:
		return
	var texs: Array = []
	if mat is BaseMaterial3D:
		for t: int in BaseMaterial3D.TEXTURE_MAX:
			texs.append((mat as BaseMaterial3D).get_texture(t))
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		for u: Dictionary in (mat as ShaderMaterial).shader.get_shader_uniform_list():
			texs.append((mat as ShaderMaterial).get_shader_parameter(u["name"]))
	for tex: Variant in texs:
		if not tex is Texture2D or seen.has((tex as Texture2D).get_rid()):
			continue
		var t := tex as Texture2D
		seen[t.get_rid()] = true
		if t is ViewportTexture or (t.resource_path.begins_with("res://") and not t.resource_path.contains("::")):
			continue
		var bytes := t.get_width() * t.get_height() * 4
		var what := "image"
		if t is ImageTexture:
			var fmt := (t as ImageTexture).get_format()
			var bpp := {Image.FORMAT_L8: 1, Image.FORMAT_LA8: 2, Image.FORMAT_R8: 1, Image.FORMAT_RG8: 2,
				Image.FORMAT_RGB8: 4, Image.FORMAT_RGBA8: 4, Image.FORMAT_RGBAH: 8, Image.FORMAT_RGBAF: 16}
			bytes = int(t.get_width() * t.get_height() * float(bpp.get(fmt, 1)))
			what = "image fmt%d" % fmt
		rows.append([bytes, "%s %dx%d %s" % [what, t.get_width(), t.get_height(), t.resource_path], _owner_label(gi)])
	_collect_textures((mat as Material).next_pass, gi, seen, rows, depth + 1)


## The restored object a node belongs to: its "spawned" ancestor's name and script.
func _owner_label(n: Node) -> String:
	var at := n
	while at != null and not at.is_in_group("spawned"):
		at = at.get_parent()
	if at == null:
		return "room/other"
	var sc := at.get_script() as Script
	return sc.get_global_name() if sc != null and sc.get_global_name() != &"" else at.name
