## ShadowDirtyProbe — what keeps throwing away the room's cached shadow maps.
##
## Godot keeps a spot or omni light's shadow map until a shadow caster in its range changes: a transform that is
## not EXACTLY the last one (RendererSceneCull::instance_set_transform's early out is `==`), an AABB (a skeleton
## posing a skinned mesh), entering or leaving the range, appearing, disappearing, a layer change
## (renderer_scene_cull.cpp, make_shadow_dirty). Then the light redraws EVERY caster it reaches. The directional
## light redraws every frame regardless and is left out here.
##
## `XENU_SHADOW_DIRTY_PROBE=<seconds>` in the environment (QualityManager adds this; 45 when empty) waits that long
## for the room to settle, then watches FRAMES frames and prints `[ShadowDirty]` lines: per shadowed light, the
## share of frames something dirtied it; per caster, how many frames it changed, how, and how many lights it hit.
## With physics interpolation on, what the renderer is given is the interpolated transform, so that is compared.
##
## Further steps, each also set in the environment (any value):
##   XENU_SHADOW_DIRTY_FREEZE  freeze the dynamic bodies that never stopped moving, then time the room as each further
##                             thing is silenced: skinned meshes, TIME-shader casters, ropes, the directional light,
##                             every light (the floor);
##   XENU_SHADOW_DIRTY_BISECT  (with FREEZE) each spot/omni light alone, and the casters keeping one dirty, bisected;
##   XENU_SHADOW_DIRTY_ATLAS   (with BISECT) the atlas check: the stuck-slot redraw on the atlas as set and a uniform one.
## Findings of 2026-11-17 in performance.md, "What redraws the shadows".
extends Node

const FRAMES := 600
const TIME_FRAMES := 300
const WAKE_TICKS := 240
const TRACK_SECONDS := 8
const TOP := 25

var _wait := 45.0
var _frame := -1
var _lights: Array[Light3D] = []
## caster instance id -> [transform, layers, mesh id, skeleton pose hash]
var _last: Dictionary = {}
## caster instance id -> {"path", "frames", "how": {kind: n}, "lights": {light id: true}}
var _hits: Dictionary = {}
## light instance id -> frames dirtied
var _light_dirty: Dictionary = {}
## top-level object instance id -> motion record (see _motion)
var _tops: Dictionary = {}
## The bodies the A/B froze (nudged by the atlas check to dirty the lights around them).
var _frozen: Array[RigidBody3D] = []
var _draws := 0.0
var _fps := 0.0


func _ready() -> void:
	var v := OS.get_environment("XENU_SHADOW_DIRTY_PROBE")
	if v.is_valid_float():
		_wait = float(v)
	_run()


## Time, watch; with `XENU_SHADOW_DIRTY_FREEZE` set, freeze the dynamic bodies that never stopped moving, and
## time and watch again: the A/B that says whether they are what keeps the shadows redrawing.
func _run() -> void:
	await get_tree().create_timer(_wait).timeout
	_collect_lights()
	await _time("as found")
	await _watch()
	if OS.has_environment("XENU_SHADOW_DIRTY_WAKE"):
		await _wake_check()
		return
	if OS.has_environment("XENU_SHADOW_DIRTY_TRACK"):
		await _track()
		return
	if not OS.has_environment("XENU_SHADOW_DIRTY_FREEZE"):
		return
	var frozen := PackedStringArray()
	for t: Dictionary in _tops.values():
		var body := (t["node"] as WeakRef).get_ref() as RigidBody3D
		if body != null and not body.freeze and (t["frames"] as Dictionary).size() >= FRAMES / 2:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.freeze = true
			frozen.append(str(body.name))
			_frozen.append(body)
	print("[ShadowDirty] froze %d bodies that never stopped: %s" % [frozen.size(), ", ".join(frozen)])
	await get_tree().create_timer(2.0).timeout
	_last = {}
	_hits = {}
	_tops = {}
	for lid: int in _light_dirty:
		_light_dirty[lid] = 0
	if OS.has_environment("XENU_SHADOW_DIRTY_BISECT"):
		await _bisect()
		return
	await _time("those bodies frozen")
	await _watch()
	# What is left with nothing moving: the robot's idle (a skeleton posed every frame), and the directional light,
	# which Godot redraws every frame whatever moves, once per split.
	for n: Node in get_tree().root.find_children("*", "Skeleton3D", true, false):
		for mi: Node in n.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().create_timer(1.0).timeout
	await _time("and skinned meshes cast no shadow")
	# A caster whose material Godot calls animated (fragment TIME with discard/scissor, or vertex TIME) keeps every
	# light it is in redrawing every frame: _light_instance_update_shadow returns animated_material_found.
	var animated := _animated_casters()
	var shaders := {}
	for g: GeometryInstance3D in animated:
		shaders[_animated_shader(g)] = int(shaders.get(_animated_shader(g), 0)) + 1
	print("[ShadowDirty] %d casters with a TIME shader: %s" % [animated.size(), JSON.stringify(shaders)])
	for g: GeometryInstance3D in animated.slice(0, 12):
		var reach := {}
		_hit(g.get_instance_id(), "animated", reach)
		print("[ShadowDirty]   %2d lights  %s  %s" % [reach.size(), _animated_shader(g), g.get_path()])
	for g: GeometryInstance3D in animated:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().create_timer(1.0).timeout
	await _time("and TIME-shader casters cast no shadow")
	var ropes := get_tree().root.find_children("*", "VerletRope", true, false)
	var awake := 0
	for r: Node in ropes:
		if r.has_method("is_sleeping") and not r.call("is_sleeping"):
			awake += 1
		(r as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("[ShadowDirty] %d ropes, %d of them awake" % [ropes.size(), awake])
	await get_tree().create_timer(1.0).timeout
	await _time("and ropes cast no shadow")
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var d := n as DirectionalLight3D
		if not d.shadow_enabled or not d.is_visible_in_tree():
			continue
		print("[ShadowDirty] directional %s: mode %d, max distance %.1f m, splits %.2f/%.2f/%.2f, blend %s, cull mask %x" % [
			d.get_path(), d.directional_shadow_mode, d.directional_shadow_max_distance, d.directional_shadow_split_1,
			d.directional_shadow_split_2, d.directional_shadow_split_3, d.directional_shadow_blend_splits, d.light_cull_mask])
		d.shadow_enabled = false
	await get_tree().create_timer(1.0).timeout
	await _time("and the directional light casts no shadow")
	for l in _lights:
		if is_instance_valid(l):
			l.shadow_enabled = false
	await get_tree().create_timer(1.0).timeout
	await _time("and no light casts a shadow (the floor)")


## Frame time, draws and the viewport's measured render-thread CPU and GPU time over TIME_FRAMES, with no
## snapshot taken (the watch's own cost is not in it).
func _time(label: String) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	var draws := 0.0
	var shadow := 0.0
	var cpu := 0.0
	var gpu := 0.0
	for i in TIME_FRAMES:
		await get_tree().process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		shadow += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / TIME_FRAMES
	print("[ShadowDirty] TIME %s: frame %.2f ms (%.0f fps), render CPU %.2f ms, GPU %.2f ms, %.0f draws (%.0f of them shadow)" % [
		label, ms, 1000.0 / ms, cpu / TIME_FRAMES, gpu / TIME_FRAMES, draws / TIME_FRAMES, shadow / TIME_FRAMES])


func _watch() -> void:
	print("[ShadowDirty] watching %d frames, %d shadowed spot/omni lights" % [FRAMES, _lights.size()])
	_draws = 0.0
	_fps = 0.0
	for f in FRAMES + 1:
		_frame = f
		var now := _snapshot()
		if f > 0:
			_diff(now)
		_last = now
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_fps += Performance.get_monitor(Performance.TIME_FPS)
		await get_tree().process_frame
	_report()


## Why a dynamic body that never stopped moving never sleeps: over WAKE_TICKS physics ticks, its sleeping flag and
## speeds, and every body it touches (Jolt sleeps an island only when all of it is still) with that body's state.
func _wake_check() -> void:
	var bodies: Array[RigidBody3D] = []
	for t: Dictionary in _tops.values():
		var body := (t["node"] as WeakRef).get_ref() as RigidBody3D
		if body != null and not body.freeze and (t["frames"] as Dictionary).size() >= FRAMES / 2:
			bodies.append(body)
			body.contact_monitor = true
			body.max_contacts_reported = 32
	var seen := {}
	var asleep := {}
	var lin := {}
	var ang := {}
	# The body's own shapes (Jolt rebuilds and wakes a body whose shape moves, changes or toggles), and what joins or
	# leaves under it.
	var pattern := {}
	var shape_last := {}
	var shape_changes := {}
	var tree_events := {}
	var on_added := func(n: Node) -> void:
		for b in bodies:
			if b.is_ancestor_of(n):
				var k := "%s +%s %s" % [b.name, n.get_class(), String(b.get_path_to(n)).get_slice("/", 0)]
				tree_events[k] = int(tree_events.get(k, 0)) + 1
	var on_removed := func(n: Node) -> void:
		for b in bodies:
			if b.is_ancestor_of(n):
				var k := "%s -%s %s" % [b.name, n.get_class(), String(b.get_path_to(n)).get_slice("/", 0)]
				tree_events[k] = int(tree_events.get(k, 0)) + 1
	get_tree().node_added.connect(on_added)
	get_tree().node_removed.connect(on_removed)
	for i in WAKE_TICKS:
		await get_tree().physics_frame
		for b in bodies:
			var id := b.get_instance_id()
			pattern[id] = str(pattern.get(id, "")) + ("." if b.sleeping else "W")
			for s: Node in b.find_children("*", "CollisionShape3D", true, false):
				var cs := s as CollisionShape3D
				var owner_body := cs.get_parent()
				while owner_body != null and not (owner_body is CollisionObject3D):
					owner_body = owner_body.get_parent()
				if owner_body != b:
					continue
				var state := [b.global_transform.affine_inverse() * cs.global_transform, cs.disabled,
					cs.shape.get_instance_id() if cs.shape != null else 0]
				var sid := cs.get_instance_id()
				if shape_last.has(sid) and shape_last[sid] != state:
					var what := "moved" if shape_last[sid][0] != state[0] else ("toggled" if shape_last[sid][1] != state[1] else "reshaped")
					var k := "%s %s %s" % [b.name, what, b.get_path_to(cs)]
					shape_changes[k] = int(shape_changes.get(k, 0)) + 1
				shape_last[sid] = state
			asleep[id] = int(asleep.get(id, 0)) + (1 if b.sleeping else 0)
			lin[id] = maxf(lin.get(id, 0.0), b.linear_velocity.length())
			ang[id] = maxf(ang.get(id, 0.0), b.angular_velocity.length())
			for o: Node3D in b.get_colliding_bodies():
				var key := "%d>%d" % [id, o.get_instance_id()]
				var rec: Array = seen.get(key, [b, o, 0, 0])
				rec[2] += 1
				if o is RigidBody3D and not (o as RigidBody3D).sleeping and not (o as RigidBody3D).freeze:
					rec[3] += 1
				seen[key] = rec
	get_tree().node_added.disconnect(on_added)
	get_tree().node_removed.disconnect(on_removed)
	# One that never slept: silence the scripts on it and under it (callbacks only; the body stays in the simulation),
	# and if it then sleeps, bisect its direct children to the one whose script wakes it.
	for b in bodies:
		if int(asleep.get(b.get_instance_id(), 0)) > 0:
			continue
		var nodes: Array[Node] = [b]
		nodes.append_array(b.find_children("*", "", true, false))
		var sleeps := await _sleeps_without(b, nodes)
		print("[ShadowDirty] WAKE %s with every script on and under it silenced: %s" % [b.name, "sleeps" if sleeps else "STILL AWAKE"])
		if not sleeps:
			continue
		if await _sleeps_without(b, [b] as Array[Node]):
			print("[ShadowDirty] WAKE   ... its own script (%s) alone silenced: sleeps" % (b.get_script() as Script).resource_path.get_file())
		# Down the tree: at each node, its own script alone; else bisect its children (each with all under it).
		var at: Node = b
		for depth in 12:
			var cand: Array = at.get_children()
			if cand.is_empty():
				break
			while cand.size() > 1:
				var half := cand.slice(0, cand.size() / 2)
				if await _sleeps_without(b, _subtree(half)):
					cand = half
				else:
					cand = cand.slice(cand.size() / 2)
			var c: Node = cand[0]
			if not await _sleeps_without(b, _subtree([c])):
				print("[ShadowDirty] WAKE   under %s no single child does it (more than one, or none)" % b.get_path_to(at))
				break
			at = c
			var own := await _sleeps_without(b, [c] as Array[Node])
			print("[ShadowDirty] WAKE   -> %s (%s)%s" % [b.get_path_to(c),
				(c.get_script() as Script).resource_path.get_file() if c.get_script() != null else c.get_class(),
				"  ITS OWN SCRIPT does it" if own else ""])
			if own:
				print("[ShadowDirty] WAKE      its _process alone silenced: %s; its _physics_process alone: %s" % [
					await _sleeps_without(b, [c] as Array[Node], true, false),
					await _sleeps_without(b, [c] as Array[Node], false, true)])
				break
	for k: String in shape_changes:
		print("[ShadowDirty] WAKE shape %3d ticks  %s" % [shape_changes[k], k])
	for k: String in tree_events:
		print("[ShadowDirty] WAKE tree  %3d  %s" % [tree_events[k], k])
	for b in bodies:
		print("[ShadowDirty] WAKE pattern %s %s" % [b.name, pattern[b.get_instance_id()]])
	for b in bodies:
		var id := b.get_instance_id()
		print("[ShadowDirty] WAKE %s (%s): asleep %d/%d ticks, max speed %.4f m/s %.4f rad/s, mass %.1f kg, can_sleep %s" % [
			b.get_path(), _describe(b), asleep[id], WAKE_TICKS, lin[id], ang[id], b.mass, b.can_sleep])
		for rec: Array in seen.values():
			if rec[0] != b:
				continue
			var o: Node3D = rec[1]
			var state := ""
			if o is RigidBody3D:
				var r := o as RigidBody3D
				state = "freeze=%s(mode %d) sleeping=%s" % [r.freeze, r.freeze_mode, r.sleeping]
			print("[ShadowDirty] WAKE   touching %3d ticks, awake+dynamic %3d  %s %s %s" % [rec[2], rec[3], o.get_class(),
				state, o.get_path()])


## Every dynamic body that kept moving, twice a second for TRACK_SECONDS: tilt, heading, where, speeds, sleep, and
## the standing controller's state if it has one.
func _track() -> void:
	var bodies: Array[RigidBody3D] = []
	for t: Dictionary in _tops.values():
		var body := (t["node"] as WeakRef).get_ref() as RigidBody3D
		if body != null and not body.freeze and (t["frames"] as Dictionary).size() >= FRAMES / 2:
			bodies.append(body)
	for i in TRACK_SECONDS * 2:
		for b in bodies:
			var model: Node = null
			for c in b.get_children():
				if c.has_method("is_resting"):
					model = c
			var bz := b.global_transform.basis.z
			print("[ShadowDirty] TRACK %5.1fs %s tilt %.3f deg yaw %.3f deg at %s lin %s ang %s sleeping=%s resting=%s" % [
				i * 0.5, b.name, rad_to_deg(b.global_transform.basis.y.angle_to(Vector3.UP)), rad_to_deg(atan2(bz.x, bz.z)),
				b.global_position.snappedf(0.0001), b.linear_velocity.snappedf(0.0001), b.angular_velocity.snappedf(0.0001),
				b.sleeping, model.call("is_resting") if model != null else "-"])
		await get_tree().create_timer(0.5).timeout


func _subtree(roots: Array) -> Array[Node]:
	var out: Array[Node] = []
	for r: Node in roots:
		out.append(r)
		out.append_array(r.find_children("*", "", true, false))
	return out


## Whether `body` falls asleep within 90 physics ticks with process and physics_process off on `nodes`; put back after.
func _sleeps_without(body: RigidBody3D, nodes: Array[Node], process := true, physics := true) -> bool:
	var was := {}
	for n in nodes:
		was[n.get_instance_id()] = [n.is_processing(), n.is_physics_processing()]
		if process:
			n.set_process(false)
		if physics:
			n.set_physics_process(false)
	var slept := false
	for i in 90:
		await get_tree().physics_frame
		if body.sleeping:
			slept = true
			break
	for n in nodes:
		if is_instance_valid(n):
			n.set_process(was[n.get_instance_id()][0])
			n.set_physics_process(was[n.get_instance_id()][1])
	# Let it wake (or not) under its own scripts again before the next question.
	for i in 30:
		await get_tree().physics_frame
	return slept


## Shadow draws a frame, averaged over `n` frames after `settle` (a toggle dirties a light for two frames).
func _shadow_draws(settle := 4, n := 6) -> float:
	var vp := get_viewport().get_viewport_rid()
	for i in settle:
		await get_tree().process_frame
	var sum := 0.0
	for i in n:
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return sum / n


## With what is known silenced (the robot) and the directional light off, each spot/omni light alone: a cached one
## draws no shadow at all after it settles; one that keeps drawing has a caster keeping it dirty. For the first few
## such lights, bisect the casters (shadows switched off in halves) down to the ones that do it.
func _bisect() -> void:
	for n: Node in get_tree().root.find_children("*", "Skeleton3D", true, false):
		for mi: Node in n.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).shadow_enabled = false
	var casters: Array = []
	var modes := {}
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.is_visible_in_tree():
			casters.append(g)
			modes[g.get_instance_id()] = g.cast_shadow
	print("[ShadowDirty] BISECT %d casters, %d lights; all lights together: %.0f shadow draws" % [casters.size(),
		_lights.size(), await _shadow_draws()])
	if OS.has_environment("XENU_SHADOW_DIRTY_ATLAS"):
		await _atlas_check()
		return
	var redrawing: Array = []
	for l in _lights:
		for o in _lights:
			o.shadow_enabled = o == l
		var d := await _shadow_draws(6, 8)
		print("[ShadowDirty] BISECT alone %6.0f shadow draws  %s" % [d, l.get_path()])
		if d > 0.5:
			redrawing.append(l)
	var found := {}
	for l: Light3D in redrawing.slice(0, 4):
		for o in _lights:
			o.shadow_enabled = o == l
		var pool: Array = []
		for g: GeometryInstance3D in casters:
			if is_instance_valid(g) and not found.has(g.get_instance_id()):
				pool.append(g)
		for round in 4:
			var cand := pool.duplicate()
			while cand.size() > 1:
				var half := cand.slice(0, cand.size() / 2)
				var rest := cand.slice(cand.size() / 2)
				_set_casting(pool, false)
				_set_casting(half, true, modes)
				if await _shadow_draws(6, 6) > 0.5:
					cand = half
				else:
					cand = rest
			_set_casting(pool, false)
			_set_casting(cand, true, modes)
			var alone := await _shadow_draws(6, 6)
			if cand.is_empty() or alone <= 0.5:
				break
			var g: GeometryInstance3D = cand[0]
			found[g.get_instance_id()] = true
			print("[ShadowDirty] BISECT culprit for %s: %s (%s, top_level=%s, script %s)" % [l.name, g.get_path(),
				g.get_class(), g.top_level, (g.get_script() as Script).resource_path.get_file() if g.get_script() != null else "-"])
			pool.erase(g)
			_set_casting(pool, true, modes)
			if await _shadow_draws(6, 6) <= 0.5:
				print("[ShadowDirty] BISECT %s settles without it" % l.name)
				break
		_set_casting(casters, true, modes)
	print("[ShadowDirty] BISECT done")


## Each light alone settles while all of them together keep redrawing (2026-11-17): what they share is the
## positional shadow atlas. Prints the per-frame shadow draws, then on the atlas as set and on a uniform layout:
## rebuild it, settle, dirty every light by nudging the frozen bodies 1 mm, and measure again.
func _atlas_check() -> void:
	var root := get_tree().root
	var vp := root.get_viewport_rid()
	var series := PackedStringArray()
	for i in 40:
		await get_tree().process_frame
		series.append(str(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
	print("[ShadowDirty] ATLAS size %d, quadrants %d/%d/%d/%d (enum), 40 frames of shadow draws: %s" % [
		root.positional_shadow_atlas_size, root.get_positional_shadow_atlas_quadrant_subdiv(0),
		root.get_positional_shadow_atlas_quadrant_subdiv(1), root.get_positional_shadow_atlas_quadrant_subdiv(2),
		root.get_positional_shadow_atlas_quadrant_subdiv(3), " ".join(series)])
	var original: Array[int] = []
	for q in 4:
		original.append(root.get_positional_shadow_atlas_quadrant_subdiv(q))
	# Godot 4.7.2 LightStorage::shadow_atlas_update_light: a light that wants a slot of another size
	# (should_realloc) and finds none returns should_redraw WITHOUT storing its version in its slot, so after one
	# dirtying it redraws every frame for as long as it stays stuck. Reproduce it on each layout: rebuild the atlas,
	# settle, dirty every light once, wait out the 500 ms realloc tolerance, measure. Godot's default layout
	# (4/4/16/64) is the one that shows it, whatever the game set; on an engine with
	# godot-4.7.2-shadow-atlas-stuck-redraw.patch it settles on that one too. The dirtying is a hair of shadow bias
	# on every light and back (a new shadow version, nothing moved): nudging bodies wakes coins and plugs, which then
	# keep the lights dirty for real and hide the difference.
	var default_layout := [2, 2, 3, 4]
	for layout: Array in [default_layout, [3, 3, 3, 3], default_layout, [3, 3, 3, 3]]:
		for q in 4:
			root.set_positional_shadow_atlas_quadrant_subdiv(q, 1 if layout[q] != 1 else 2)
		await get_tree().process_frame
		for q in 4:
			root.set_positional_shadow_atlas_quadrant_subdiv(q, layout[q])
		await get_tree().create_timer(1.5).timeout
		var fresh := await _shadow_draws(4, 20)
		for l in _lights:
			if is_instance_valid(l):
				l.shadow_bias += 0.001
		await get_tree().process_frame
		await get_tree().process_frame
		for l in _lights:
			if is_instance_valid(l):
				l.shadow_bias -= 0.001
		await get_tree().create_timer(1.5).timeout
		print("[ShadowDirty] ATLAS quadrants %s (enum: 2=4, 3=16, 4=64 shadows each): rebuilt %.0f shadow draws, after a nudge %.0f" % [
			str(layout), fresh, await _shadow_draws(4, 30)])
	for q in 4:
		root.set_positional_shadow_atlas_quadrant_subdiv(q, original[q])


func _set_casting(list: Array, on: bool, modes := {}) -> void:
	for g: GeometryInstance3D in list:
		if is_instance_valid(g):
			g.cast_shadow = modes.get(g.get_instance_id(), GeometryInstance3D.SHADOW_CASTING_SETTING_ON) if on \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Visible shadow casters with a ShaderMaterial (override, overlay or a surface's) whose code reads TIME.
func _animated_casters() -> Array:
	var out := []
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not g.is_visible_in_tree():
			continue
		if not _animated_shader(g).is_empty():
			out.append(g)
	return out


func _animated_shader(g: GeometryInstance3D) -> String:
	var mats: Array = [g.material_override, g.material_overlay]
	var mi := g as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			mats.append(mi.get_active_material(s))
	for m: Variant in mats:
		var sm := m as ShaderMaterial
		while sm != null:
			if sm.shader != null and sm.shader.code.contains("TIME"):
				var path := sm.shader.resource_path
				return path.get_file() if not path.is_empty() else "(inline shader)"
			sm = sm.next_pass as ShaderMaterial
	return ""


func _collect_lights() -> void:
	for n: Node in get_tree().root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l is DirectionalLight3D or not l.shadow_enabled or not l.is_visible_in_tree():
			continue
		_lights.append(l)
		_light_dirty[l.get_instance_id()] = 0


func _snapshot() -> Dictionary:
	var out := {}
	for n: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not g.is_visible_in_tree():
			continue
		var mesh_id := 0
		var pose := 0
		var mi := g as MeshInstance3D
		if mi != null:
			mesh_id = mi.mesh.get_instance_id() if mi.mesh != null else 0
			var skel: Skeleton3D = null
			if mi.skin != null and not mi.skeleton.is_empty():
				skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if skel != null and skel.get_bone_count() > 0:
				var poses := []
				for b in skel.get_bone_count():
					poses.append(skel.get_bone_pose(b))
				pose = hash(var_to_str(poses))
		out[g.get_instance_id()] = [g.get_global_transform_interpolated(), g.layers, mesh_id, pose, g.custom_aabb]
	return out


func _diff(now: Dictionary) -> void:
	var dirtied := {}
	for id: int in now:
		var how := ""
		if not _last.has(id):
			how = "appeared"
		else:
			var a: Array = _last[id]
			var b: Array = now[id]
			if a[0] != b[0]:
				how = "moved"
				_motion(id, a[0], b[0])
			elif a[3] != b[3]:
				how = "posed"
			elif a[2] != b[2]:
				how = "mesh"
			elif a[1] != b[1]:
				how = "layers"
			elif a[4] != b[4]:
				# A VerletRope re-bounds itself each frame it draws (set_custom_aabb): a new box is an instance update.
				how = "rebounded"
		if not how.is_empty():
			_hit(id, how, dirtied)
	for id: int in _last:
		if not now.has(id):
			_hit(id, "vanished", dirtied, _last[id][0])
	for lid: int in dirtied:
		_light_dirty[lid] += 1


## Per top-level object (a child of the room): the frames any of its casters moved, the largest step and the
## farthest it got from where the watch started, so a jitter of a micron tells itself from a real motion.
func _motion(id: int, was: Transform3D, now: Transform3D) -> void:
	var g := instance_from_id(id) as Node
	if g == null or not g.is_inside_tree():
		return
	var top := g
	var scene := get_tree().current_scene
	while top.get_parent() != null and top.get_parent() != scene and top.get_parent() != get_tree().root:
		top = top.get_parent()
	var tid := top.get_instance_id()
	var rec: Dictionary = _tops.get(tid, {})
	if rec.is_empty():
		rec = {"node": weakref(top), "frames": {}, "step": 0.0, "turn": 0.0, "start": {}}
		_tops[tid] = rec
	rec["frames"][_frame] = true
	rec["step"] = maxf(rec["step"], was.origin.distance_to(now.origin))
	rec["turn"] = maxf(rec["turn"], (was.basis.inverse() * now.basis).get_rotation_quaternion().get_angle())
	if not rec["start"].has(id):
		rec["start"][id] = was.origin
	rec["drift"] = maxf(rec.get("drift", 0.0), (rec["start"][id] as Vector3).distance_to(now.origin))


func _describe(top: Node) -> String:
	var parts := PackedStringArray([str(top.name)])
	for c in top.get_children():
		if not (c is CollisionShape3D) and not (c is MeshInstance3D):
			parts.append(str(c.name))
			break
	var body := top as RigidBody3D
	if body != null:
		parts.append("freeze=%s sleeping=%s mode=%d lin=%.6f ang=%.6f" % [body.freeze, body.sleeping,
			body.freeze_mode, body.linear_velocity.length(), body.angular_velocity.length()])
	elif top is PhysicsBody3D:
		parts.append(top.get_class())
	var script := top.get_script() as Script
	if script != null:
		parts.append(script.resource_path.get_file())
	return " ".join(parts)


func _hit(id: int, how: String, dirtied: Dictionary, at: Variant = null) -> void:
	var g := instance_from_id(id) as GeometryInstance3D
	var rec: Dictionary = _hits.get(id, {})
	if rec.is_empty():
		rec = {"path": str(g.get_path()) if g != null and g.is_inside_tree() else "(freed)", "frames": 0, "how": {}, "lights": {}}
		_hits[id] = rec
	rec["frames"] += 1
	rec["how"][how] = int(rec["how"].get(how, 0)) + 1
	var box: AABB
	if g != null and g.is_inside_tree():
		box = g.global_transform * g.get_aabb()
	elif at is Transform3D:
		box = AABB((at as Transform3D).origin, Vector3.ZERO)
	else:
		return
	var layers := g.layers if g != null else 0xFFFFF
	for l in _lights:
		if not is_instance_valid(l) or not (l.light_cull_mask & layers):
			continue
		var r := (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
		var c := l.global_position
		var nearest := c.clamp(box.position, box.end)
		if nearest.distance_to(c) <= r:
			dirtied[l.get_instance_id()] = true
			rec["lights"][l.get_instance_id()] = true


func _report() -> void:
	var frames := FRAMES
	print("[ShadowDirty] %d frames: %.0f fps, %.0f draws a frame" % [frames, _fps / (frames + 1), _draws / (frames + 1)])
	var ls := _lights.duplicate()
	ls.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		return _light_dirty[a.get_instance_id()] > _light_dirty[b.get_instance_id()])
	for l: Light3D in ls:
		var n: int = _light_dirty[l.get_instance_id()]
		print("[ShadowDirty] light %5.1f%% of frames dirty  %s (%s, range %.1f m)" % [100.0 * n / frames,
			l.get_path(), l.get_class(), (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range])
	var tops := _tops.values()
	tops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["frames"] as Dictionary).size() > (b["frames"] as Dictionary).size())
	print("[ShadowDirty] %d objects moved; frames moved, largest step, largest turn, farthest drift (micrometres, microradians):" % tops.size())
	for t: Dictionary in tops:
		var node := (t["node"] as WeakRef).get_ref() as Node
		print("[ShadowDirty]   %4d frames  step %10.3f  turn %10.3f  drift %10.3f  %s" % [(t["frames"] as Dictionary).size(),
			float(t["step"]) * 1e6, float(t["turn"]) * 1e6, float(t.get("drift", 0.0)) * 1e6,
			_describe(node) if node != null else "(freed)"])
	var recs := _hits.values()
	recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["frames"]) * maxi(1, (a["lights"] as Dictionary).size()) \
			> int(b["frames"]) * maxi(1, (b["lights"] as Dictionary).size()))
	print("[ShadowDirty] %d casters changed at least once; the top %d by frames x lights:" % [recs.size(), mini(TOP, recs.size())])
	for i in mini(TOP, recs.size()):
		var r: Dictionary = recs[i]
		print("[ShadowDirty]   %4d frames  %2d lights  %s  %s" % [r["frames"], (r["lights"] as Dictionary).size(),
			JSON.stringify(r["how"]), r["path"]])
