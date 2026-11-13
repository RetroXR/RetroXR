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
##   --no-replay   with --room=: do NOT replay --file; a room whose root restores its own slot (xr_init's
##                 scene_id) has already done it, and replaying on top doubled every object (bodies inside
##                 bodies, cords whipping). Run under a scratch APPDATA so that restore reads a COPY.
##   --gpu-census  what the player's camera draws, object by object: each top-level object is hidden in turn
##                 and the primitives / draw calls that go with it are counted (LODs as this window picks them,
##                 so run it at a headset-like size, e.g. --resolution 1600x1600)
##   --rope-census after the settle: every AWAKE cord, how far each of its end nodes moves a physics tick
##                 over 30 ticks, and what that node is (class, parent, frozen, sleeping, speed)
##   --settle=N    keep the restored room running N seconds after the 120 frames, printing each second's
##                 mean / worst frame (with XENU_ROPE_DIAG=1 / XENU_ROPE_FRAMETIME=1: why cords stay awake)
extends Node3D

var _file := ""
var _room := ""
var _twice := false
var _prefetch := true
var _boot := false
var _settle := 0.0


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
		elif a.begins_with("--settle="):
			_settle = float(a.substr(9))
	get_tree().create_timer(240.0 + _settle).timeout.connect(func() -> void:
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
	if OS.get_cmdline_user_args().has("--no-replay"):
		print("[probe] no replay: the room restored itself")
		for i in 120:
			await get_tree().process_frame
		if _settle > 0.0:
			await _run_settled(_settle)
		if OS.get_cmdline_user_args().has("--rope-census"):
			await _rope_census()
		if OS.get_cmdline_user_args().has("--gpu-census"):
			await _gpu_census()
		if OS.get_cmdline_user_args().has("--set-census"):
			_set_census()
		get_tree().quit(0)
		return
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
	if _settle > 0.0:
		await _run_settled(_settle)
	if OS.get_cmdline_user_args().has("--rope-census"):
		await _rope_census()
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


## The room left running: one line a second, so a cost that never settles (cords that stay awake) shows.
func _run_settled(seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1e6)
	var second := Time.get_ticks_usec()
	var last := second
	var n := 0
	var worst := 0
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		n += 1
		if now - second >= 1000000:
			print("[probe] settle %5.1f s: %3d frames, mean %.2f ms, worst %.1f ms" % [
				(end - now) / -1e6 + seconds, n, (now - second) / 1000.0 / n, worst / 1000.0])
			second = now
			n = 0
			worst = 0


func _rope_census() -> void:
	var ropes: Array[Node] = []
	for n: Node in get_tree().root.find_children("*", "VerletRope", true, false):
		ropes.append(n)
	var awake: Array[Node] = ropes.filter(func(r: Node) -> bool: return not r.call("is_sleeping"))
	print("[probe] ropes %d, awake %d" % [ropes.size(), awake.size()])
	var ends: Array = []  # [rope, which, node, last pos, max step, sum step]
	for r: Node in awake:
		for which: String in ["start", "end"]:
			var n := r.call("get_%s_node" % which) as Node3D
			if n != null:
				ends.append([r, which, n, n.global_position, 0.0, 0.0])
	for t in 30:
		await get_tree().physics_frame
		for e: Array in ends:
			var n: Node3D = e[2]
			if not is_instance_valid(n):
				continue
			var d := n.global_position.distance_to(e[3])
			e[3] = n.global_position
			e[4] = maxf(e[4], d)
			e[5] += d
	ends.sort_custom(func(a: Array, b: Array) -> bool: return a[5] > b[5])
	var kinds: Dictionary = {}
	for e: Array in ends:
		var n: Node3D = e[2]
		if not is_instance_valid(n):
			continue
		var desc := n.get_class()
		var body := n as RigidBody3D
		if body == null and n.get_parent() is RigidBody3D:
			body = n.get_parent()
		if body != null:
			desc += " body=%s frozen=%s mode=%d sleeping=%s v=%.3f w=%.3f" % [body.name, body.freeze, body.freeze_mode,
				body.sleeping, body.linear_velocity.length(), body.angular_velocity.length()]
		var moving: bool = e[5] > 0.0005
		var key := "%s %s" % ["MOVING" if moving else "still ", n.get_class() if body == null else "RigidBody3D frozen=%s sleeping=%s" % [body.freeze, body.sleeping]]
		kinds[key] = int(kinds.get(key, 0)) + 1
		if moving:
			print("[probe] end %-5s moved %7.2f mm (max %6.2f/tick)  %s <- %s  [%s]" % [e[1], e[5] * 1000.0, e[4] * 1000.0,
				n.name, str(n.get_parent().get_path()).replace("/root/RestorePerfProbe/", ""), desc])
	for k: String in kinds:
		print("[probe] ends %3d  %s" % [kinds[k], k])
	# Every unfrozen body in the room that is moving: what it is, where, how fast.
	var movers: Array = []
	for b: Node in get_tree().root.find_children("*", "RigidBody3D", true, false):
		var rb := b as RigidBody3D
		if not rb.freeze and not rb.sleeping and (rb.linear_velocity.length() > 0.05 or rb.angular_velocity.length() > 0.2):
			movers.append(rb)
	movers.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return a.linear_velocity.length() > b.linear_velocity.length())
	print("[probe] moving unfrozen bodies: %d" % movers.size())
	for rb: RigidBody3D in movers.slice(0, 40):
		if rb.has_method("get_libretro_node") or "systemid" in rb:
			var cords: Array = []
			for r: Node in get_tree().root.find_children("*", "VerletRope", true, false):
				for which: String in ["start", "end"]:
					var n := r.call("get_%s_node" % which) as Node3D
					if n != null and (n == rb or rb.is_ancestor_of(n)):
						var other := r.call("get_%s_node" % ("end" if which == "start" else "start")) as Node3D
						cords.append("%s/%s:%s->%s(%s)" % [r.get_parent().name, r.name, n.name,
							"-" if other == null else other.name, "-" if other == null else str(other.get_parent().name)])
			print("[probe] system %s systemid=%s model=%s gravity=%.1f mass=%.2f freeze=%s held_by=%s cords=%s" % [rb.name,
				str(rb.get("systemid")), str(rb.get("model_id")), rb.gravity_scale, rb.mass, rb.freeze,
				str(rb.get_meta("held_by", "")), str(cords)])
		var top: Node = rb
		while top.get_parent() != null and top.get_parent().name not in ["RestorePerfProbe", "StarlightArcade"]:
			top = top.get_parent()
		var scr: Script = rb.get_script()
		print("[probe] mover v=%6.2f w=%6.2f at %s  %s  scene=%s script=%s top=%s(%s) layer=%d mask=%d" % [rb.linear_velocity.length(),
			rb.angular_velocity.length(), str(rb.global_position.snapped(Vector3.ONE * 0.01)), rb.name, rb.scene_file_path.get_file(),
			"" if scr == null else scr.resource_path.get_file(), top.name, top.scene_file_path.get_file(), rb.collision_layer, rb.collision_mask])


func _drawn() -> Vector2i:
	var sum := Vector2i.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
		sum += Vector2i(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return sum / 3


func _gpu_census() -> void:
	var cam := get_viewport().get_camera_3d()
	print("[probe] gpu census from %s at %s looking %s" % ["-" if cam == null else str(cam.get_path()),
		"-" if cam == null else str(cam.global_position), "-" if cam == null else str(-cam.global_basis.z)])
	if OS.get_cmdline_user_args().has("--no-shadows"):
		# A Quest's room casts no shadows: count what is left without the shadow passes.
		for l: Node in get_tree().root.find_children("*", "Light3D", true, false):
			(l as Light3D).shadow_enabled = false
	var all := await _drawn()
	print("[probe] drawn: %d primitives, %d draw calls" % [all.x, all.y])
	var tops: Array[Node3D] = []
	for holder: Node in [self, get_tree().root.find_child("StarlightArcade", true, false)]:
		if holder == null:
			continue
		for c: Node in holder.get_children():
			if c is Node3D and (c as Node3D).visible and c.name != "PlayerRig":
				tops.append(c)
	var rows: Array = []
	for n: Node3D in tops:
		n.visible = false
		var without := await _drawn()
		n.visible = true
		var label := str(n.name)
		if "model_id" in n and str(n.get("model_id")) != "":
			label += " " + str(n.get("model_id"))
		elif n.scene_file_path != "":
			label += " " + n.scene_file_path.get_file()
		rows.append([all.x - without.x, all.y - without.y, label])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r: Array in rows.slice(0, 30):
		print("[probe] gpu %8d prims %5d draws  %s" % [r[0], r[1], r[2]])


static func _mesh_tris(mesh: Mesh) -> int:
	var t := 0
	if mesh == null:
		return 0
	for i in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		t += idx.size() / 3 if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


## The room's own scenery, grouped by mesh: what the set itself asks the GPU for.
func _set_census() -> void:
	var set_node := get_tree().root.find_child("Set", true, false)
	if set_node == null:
		print("[probe] no Set")
		return
	var groups: Dictionary = {}
	var lights := 0
	var shadow_lights := 0
	for n: Node in set_node.find_children("*", "", true, false):
		if n is Light3D and (n as Light3D).visible:
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadow_lights += 1
		var inst := 1
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
			inst = (n as MultiMeshInstance3D).multimesh.visible_instance_count
			if inst < 0:
				inst = (n as MultiMeshInstance3D).multimesh.instance_count
		else:
			continue
		if not (n as GeometryInstance3D).is_visible_in_tree() or mesh == null:
			continue
		var key := "%s|%s" % [n.name.rstrip("0123456789_"), mesh.resource_path.get_file() if mesh.resource_path != "" else mesh.get_class()]
		var g: Dictionary = groups.get(key, {"nodes": 0, "inst": 0, "tris": 0, "surf": 0, "shadow": 0})
		var tris := _mesh_tris(mesh)
		g["nodes"] += 1
		g["inst"] += inst
		g["tris"] += tris * inst
		g["surf"] += mesh.get_surface_count()
		if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g["shadow"] += 1
		groups[key] = g
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return groups[a]["tris"] > groups[b]["tris"])
	var tt := 0
	var ts := 0
	for k: String in keys:
		tt += groups[k]["tris"]
		ts += groups[k]["surf"]
	print("[probe] set: %d tris (LOD0), %d surfaces, %d groups, %d lights (%d with shadows)" % [tt, ts, keys.size(), lights, shadow_lights])
	for k: String in keys.slice(0, 30):
		var g: Dictionary = groups[k]
		print("[probe] set %9d tris %5d surf %4d nodes %5d inst %4d shadow  %s" % [g["tris"], g["surf"], g["nodes"], g["inst"], g["shadow"], k])
