## Bakes a room's shell lighting into a pair of irradiance volumes — one with the
## ceiling light on, one with it off.
##
## WHY A VOLUME AND NOT A LIGHTMAP. Every shell surface in these rooms is a
## BoxMesh or a PlaneMesh, and a primitive carries no UV2 (measured: `BoxMesh
## UV=true UV2=false`). A LightmapGI bake would therefore mean converting all
## thirty-odd of them to ArrayMesh and unwrapping each one, which throws away the
## readable `size = Vector3(...)` the room is authored with. A volume is indexed
## by world position, which `pbr_surface_unshaded` already carries as a varying,
## so nothing about the geometry has to change.
##
## WHY IT IS WORTH BAKING AT ALL. Measured on a Quest 3, bedroom, VrApi App time
## at eye buffer 1.00x: Godot's lighting 20.04 ms, the four-light analytic loop
## 14.72 ms, and a lightmap-shaped profile — one extra texture fetch, no loop —
## 12.34 ms, which is 72 fps and the refresh cap. The loop's arithmetic costs
## more than a fetch, which is the opposite of what the capture's saturated
## texture pipe suggested.
##
## It also buys something the analytic loop could never have: OCCLUSION. Each
## grid point raycasts to each light, so the room's own architecture blocks a
## lamp.
##
## WHAT IS BAKED. The room as authored, and nothing a player put in it. The
## scene carries a PlayerRig, and its spawn menu restores the room's last save
## slot on startup, so the first bedroom bake was taken with that slot's tables,
## TVs and consoles standing in it. Their shadows were baked into the walls and
## floor as blocky blue shapes, and stayed there after the objects moved. The rig
## is now stripped before the room enters the tree, only the room's own static
## bodies occlude, and TimeOfDay bakes its authored time rather than whatever
## the lever was last saved at.
##
## WHY THE EDGES ARE FILLED. A wall's face sits between two rows of texels, one
## inside the room and one inside or behind the wall, and trilinear sampling
## blends them. The outer row can see no lamp, so every wall read darker at its
## edges and a corner, where three walls meet, took seven dark texels out of
## eight. Texels are now flood-filled from inside the room, and the ones the fill
## cannot reach take the average of their reachable neighbours instead.
##
## Run it windowed or headless — it is physics and arithmetic, no rendering:
##   godot --headless --path RetroXR res://Tools/room/bake_shell_gi.tscn
## `-- --time=0..1` bakes the bedroom at another time of day; see _bake.
extends Node

const OUT_DIR := "res://Scenes/baked"

## Metres per texel. The smallest thing the field has to describe is a lamp's
## falloff across a wall, not a hard edge, so this is about resolution of a
## gradient rather than of a shadow. 0.16 puts the bedroom, closet and pad
## included, at 39x23x38.
const TEXEL := 0.16

## Pad the grid past the room's bounds so a wall ON the boundary samples inside
## the volume rather than off its clamped edge, where the value belongs to the
## texel centre half a texel away.
const PAD := 0.4

## Lights whose state the two bakes differ by. Everything else is baked as it
## stands at bake time.
const SWITCHED_GROUP := "ceiling_light"

## Only the room's INTERIOR is baked. The ground, road, kerbs and soil outside
## the window wear shell materials too, and including them put the volume's
## bounds at 140 x 3.6 x 140 m — a grid of 17.8 million texels describing a
## street at 16 cm, to light a bedroom. They are on render layer 2 (set by
## bedroom_exterior.gd) and stay on the analytic loop, which is the right place
## for a surface lit by two directional lights and no local lamps.
const INTERIOR_LAYER := 1

## Refuse to bake a grid past this. A wrong bounds is otherwise an overnight run
## that ends in a texture nothing can sample.
const MAX_TEXELS := 4_000_000

## The rig the room scenes instance. Stripped before the bake: its spawn menu
## restores a save slot into the room, and its body is a capsule standing in it.
const PLAYER_RIG := "res://Scenes/player_rig.tscn"

## Height above the rig's feet the reachability fill starts from. The rig stands
## on the floor inside the room, so this point is in open air in any room.
const SEED_HEIGHT := 1.2

const FACE_STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := "res://Scenes/BedroomScene.tscn"
	var name := "bedroom"
	var time := -1.0
	for a in args:
		if a.begins_with("--scene="):
			scene = a.substr(8)
		elif a.begins_with("--name="):
			name = a.substr(7)
		elif a.begins_with("--time="):
			time = clampf(float(a.substr(7)), 0.0, 1.0)
	await _bake(scene, name, time)
	get_tree().quit(0)


## `time` below zero bakes TimeOfDay at the time the scene authors. A headset
## wall is the volume and nothing else, so the lever never reaches it: whatever
## time is baked is the time the walls show at every position of the lever.
func _bake(scene_path: String, out_name: String, time: float = -1.0) -> void:
	var room: Node3D = load(scene_path).instantiate() as Node3D
	var seed := _strip_player(room)
	for node in room.find_children("*", "", true, false):
		if node is TimeOfDay:
			var tod := node as TimeOfDay
			tod.persist = false
			if time >= 0.0:
				tod.time = time
			print("[bake] time of day %.2f" % tod.time)
	add_child(room)
	# Physics needs a tick before a raycast reports anything, and the room's own
	# _ready work (blinds duplicating the environment, time of day writing every
	# light) has to land before the lights are read.
	for i in 20:
		await get_tree().process_frame
	await get_tree().physics_frame

	# The energies a HEADSET applies, not the ones the scene authors.
	# QualityManager is an autoload, so its own boot call ran before this room
	# existed and reached none of its lights; and this bake runs on a desktop but
	# is only ever read on a headset. Skipping it bakes the arcade 33% bright and
	# its neon three times over, into a file nothing downstream can correct.
	QualityManager.adjust_lights(false)
	await get_tree().physics_frame

	# Counted, so a bake that would include a player's objects says so. Nothing
	# should have spawned with the rig gone; anything that did is still kept out
	# of the occluders below.
	var spawned := get_tree().get_nodes_in_group("spawned").size()
	print("[bake] spawned objects in the room: %d" % spawned)
	var exclude := _non_room_bodies(room)

	var bounds := _shell_bounds(room)
	if bounds.size == Vector3.ZERO:
		push_error("[bake] no shell meshes found in %s" % scene_path)
		return
	if seed == Vector3.INF:
		seed = bounds.get_center()
	bounds = bounds.grow(PAD)
	var dims := Vector3i(
		maxi(2, int(ceil(bounds.size.x / TEXEL))),
		maxi(2, int(ceil(bounds.size.y / TEXEL))),
		maxi(2, int(ceil(bounds.size.z / TEXEL))))
	var texels := dims.x * dims.y * dims.z
	print("[bake] %s  bounds %s  size %s  grid %s (%d texels)" % [
		out_name, bounds.position, bounds.size, dims, texels])
	if texels > MAX_TEXELS:
		push_error("[bake] %d texels exceeds the %d cap - check the bounds" % [
			texels, MAX_TEXELS])
		return

	var switched: Array[Light3D] = []
	for node in room.find_children("*", "Light3D", true, false):
		if node.is_in_group(SWITCHED_GROUP):
			switched.append(node as Light3D)
	print("[bake] switched lights: %d" % switched.size())

	var was := []
	for l in switched:
		was.append(l.visible)

	var space := (room.get_viewport() as Viewport).world_3d.direct_space_state
	var inside := _reachable(bounds, dims, seed, space, exclude)
	var reached := inside.count(1)
	print("[bake] texels inside the room: %d of %d, filled from neighbours: %d" % [
		reached, texels, texels - reached])
	if reached == 0:
		push_error("[bake] the fill from %s reached nothing - is the seed inside a wall?" % seed)
		return

	for state in ["on", "off"]:
		for l in switched:
			l.visible = state == "on"
		await get_tree().physics_frame
		var pair := _bake_state(room, bounds, dims, space, exclude, inside)
		_save(pair[0], pair[1], bounds, dims, "%s_gi_%s" % [out_name, state])

	for i in switched.size():
		switched[i].visible = was[i]


## Take the PlayerRig out of a room that has not entered the tree yet, and return
## a point in open air above where it stood (INF when the room has none).
##
## Before `add_child`, because the rig's spawn menu starts restoring the save
## slot from its own deferred setup, and a slot half-loaded when the bake starts
## is worse than one fully loaded.
func _strip_player(room: Node3D) -> Vector3:
	for node in room.find_children("*", "Node3D", true, false):
		if node.scene_file_path != PLAYER_RIG:
			continue
		var at := Vector3.ZERO
		var n: Node = node
		while n != room and n is Node3D:
			at = (n as Node3D).transform * at
			n = n.get_parent()
		node.get_parent().remove_child(node)
		node.free()
		print("[bake] stripped the player rig at %s" % at)
		return at + Vector3.UP * SEED_HEIGHT
	return Vector3.INF


## RIDs of every physics body the rays must pass through: anything that is not
## the room's own static architecture. Spawned objects move, and a player's body
## is wherever they stand, so neither belongs in a baked shadow.
func _non_room_bodies(room: Node3D) -> Array[RID]:
	var out: Array[RID] = []
	var kept: PackedStringArray = []
	for node in get_tree().root.find_children("*", "PhysicsBody3D", true, false):
		var body := node as PhysicsBody3D
		if body is StaticBody3D and room.is_ancestor_of(body) and not _in_spawned(body, room):
			kept.append(str(room.get_path_to(body)))
			continue
		out.append(body.get_rid())
	print("[bake] occluders: %s (%d other bodies ignored)" % [", ".join(kept), out.size()])
	return out


func _in_spawned(node: Node, room: Node3D) -> bool:
	var n := node
	while n != null and n != room:
		if n.is_in_group("spawned"):
			return true
		n = n.get_parent()
	return false


func _index(c: Vector3i, dims: Vector3i) -> int:
	return (c.z * dims.y + c.y) * dims.x + c.x


func _centre(c: Vector3i, bounds: AABB, step: Vector3) -> Vector3:
	return bounds.position + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * step


## 1 for every texel reachable from `seed` by stepping between neighbouring
## texel centres without a ray crossing an occluder, 0 for the rest: the ones
## inside a wall, behind it, or in the pad beyond the room.
##
## Steps are along one axis at a time, so a step is never longer than a texel
## and cannot slip diagonally through the seam where two wall boxes meet.
func _reachable(bounds: AABB, dims: Vector3i, seed: Vector3,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> PackedByteArray:
	var step := bounds.size / Vector3(dims)
	var inside := PackedByteArray()
	inside.resize(dims.x * dims.y * dims.z)
	inside.fill(0)
	var s := Vector3i(((seed - bounds.position) / step).floor())
	s = s.clamp(Vector3i.ZERO, dims - Vector3i.ONE)
	var queue: Array[Vector3i] = [s]
	inside[_index(s, dims)] = 1
	var head := 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		var p := _centre(c, bounds, step)
		for d in FACE_STEPS:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.z < 0 or n.x >= dims.x or n.y >= dims.y or n.z >= dims.z:
				continue
			var j := _index(n, dims)
			if inside[j] == 1:
				continue
			var query := PhysicsRayQueryParameters3D.create(p, _centre(n, bounds, step), 0xFFFFFFFF, exclude)
			query.collide_with_areas = false
			if not space.intersect_ray(query).is_empty():
				continue
			inside[j] = 1
			queue.append(n)
	return inside


## Union of the AABBs of every mesh wearing a shell material — the volume only
## has to cover the surfaces that will sample it.
func _shell_bounds(room: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in room.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if gi.layers & INTERIOR_LAYER == 0 or not _wears_shell(gi):
			continue
		var box := gi.global_transform * gi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _wears_shell(gi: GeometryInstance3D) -> bool:
	var mats: Array[ShaderMaterial] = []
	var over := gi.material_override as ShaderMaterial
	if over != null:
		mats.append(over)
	var mi := gi as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m == null:
				m = mi.mesh.surface_get_material(i) as ShaderMaterial
			if m != null:
				mats.append(m)
	for m in mats:
		if m.shader != null and m.get_shader_parameter("shell") == true:
			return true
	return false


## One state, as two images: irradiance and dominant direction.
func _bake_state(room: Node3D, bounds: AABB, dims: Vector3i,
		space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		inside: PackedByteArray) -> Array:
	var lights: Array[Light3D] = []
	for node in room.find_children("*", "Light3D", true, false):
		var l := node as Light3D
		# A light culled off the interior layer lights nothing this volume
		# covers on a desktop either — the street's sun and fill are the case.
		if l.is_visible_in_tree() and l.light_energy > 0.0 \
				and l.light_cull_mask & INTERIOR_LAYER != 0:
			lights.append(l)

	var amb := Color(0, 0, 0)
	var found := room.find_children("*", "WorldEnvironment", true, false)
	if not found.is_empty():
		var env: Environment = (found[0] as WorldEnvironment).environment
		if env != null:
			amb = env.ambient_light_color.srgb_to_linear() * env.ambient_light_energy

	var count := dims.x * dims.y * dims.z
	var sums := PackedVector3Array()
	sums.resize(count)
	# Dominant direction scaled by how directional the texel is, so a neighbour
	# average in _fill_outside weighs agreeing directions up and opposing ones down.
	var axes := PackedVector3Array()
	axes.resize(count)
	var step := bounds.size / Vector3(dims)
	var ambient := Vector3(amb.r, amb.g, amb.b)
	var lit_luma := 0.0

	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var i := _index(Vector3i(x, y, z), dims)
				if inside[i] == 0:
					continue
				var p := _centre(Vector3i(x, y, z), bounds, step)
				var sum := ambient
				var axis := Vector3.ZERO
				for l in lights:
					var contrib := _contribution(l, p, space, exclude)
					if contrib[0] == Vector3.ZERO:
						continue
					sum += contrib[0]
					axis += (contrib[1] as Vector3) * _luma(contrib[0])
				var lum := _luma(sum)
				lit_luma += lum
				var frac: float = clampf(axis.length() / maxf(lum, 0.0001), 0.0, 1.0)
				sums[i] = sum
				axes[i] = (axis.normalized() if axis.length() > 0.0001 else Vector3.UP) * frac

	_fill_outside(sums, axes, inside, dims, ambient)
	print("[bake]   %d lights, mean luma inside the room %.3f" % [
		lights.size(), lit_luma / maxf(inside.count(1), 1)])

	var irr := PackedByteArray()
	var dir := PackedByteArray()
	for i in count:
		_push_rgbah(irr, sums[i])
		var a := axes[i]
		var n: Vector3 = a.normalized() if a.length() > 0.0001 else Vector3.UP
		_push_rgba8(dir, n, clampf(a.length(), 0.0, 1.0))
	return [irr, dir]


## Give every texel outside the room the mean of its already-known neighbours,
## one ring at a time outward from the room.
##
## A wall's face is sampled between its inside texel and the one in or behind the
## wall, so that outer texel has to carry the inside's light rather than the
## wall's darkness. Twenty-six neighbours rather than six so a corner texel,
## which touches the room only diagonally, fills in the first ring and not the
## third.
func _fill_outside(sums: PackedVector3Array, axes: PackedVector3Array,
		inside: PackedByteArray, dims: Vector3i, fallback: Vector3) -> void:
	var known := inside.duplicate()
	var pending: Array[int] = []
	for i in known.size():
		if known[i] == 0:
			pending.append(i)
	while not pending.is_empty():
		var filled: Array[int] = []
		var still: Array[int] = []
		for i in pending:
			var c := Vector3i(i % dims.x, (i / dims.x) % dims.y, i / (dims.x * dims.y))
			var sum := Vector3.ZERO
			var axis := Vector3.ZERO
			var n := 0
			for dz in range(-1, 2):
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var o := c + Vector3i(dx, dy, dz)
						if o.x < 0 or o.y < 0 or o.z < 0 \
								or o.x >= dims.x or o.y >= dims.y or o.z >= dims.z:
							continue
						var j := _index(o, dims)
						if known[j] == 0:
							continue
						sum += sums[j]
						axis += axes[j]
						n += 1
			if n == 0:
				still.append(i)
				continue
			sums[i] = sum / n
			axes[i] = axis / n
			filled.append(i)
		if filled.is_empty():
			# Nothing left touches the room: a pocket the fill never reached and
			# no surface samples. Ambient keeps it from reading as a hole.
			for i in still:
				sums[i] = fallback
				axes[i] = Vector3.ZERO
			return
		# Marked after the ring, not during it, so a texel filled this pass is
		# not read as a source by its neighbour in the same pass.
		for i in filled:
			known[i] = 1
		pending = still


## What one light puts at a point, and the direction it comes from.
##
## Uses the engine's own omni curve rather than a linear ramp, so the bake and
## the shader's fallback loop agree — `light_energy` is an intensity and
## `omni_range` a cull boundary, and a ramp makes every lamp far too weak.
func _contribution(l: Light3D, p: Vector3, space: PhysicsDirectSpaceState3D,
		exclude: Array[RID]) -> Array:
	var col := l.light_color.srgb_to_linear()
	var to_light: Vector3
	var atten := 1.0
	var target: Vector3
	if l is DirectionalLight3D:
		to_light = l.global_transform.basis.z.normalized()
		target = p + to_light * 50.0
	else:
		var d := l.global_position - p
		var dist := d.length()
		to_light = d / maxf(dist, 0.0001)
		target = l.global_position
		var spot := l as SpotLight3D
		var range_m: float = spot.spot_range if spot != null else (l as OmniLight3D).omni_range
		var decay: float = spot.spot_attenuation if spot != null \
			else (l as OmniLight3D).omni_attenuation
		if dist >= range_m:
			return [Vector3.ZERO, Vector3.UP]
		var nd := dist / range_m
		nd = nd * nd
		nd = nd * nd
		nd = maxf(1.0 - nd, 0.0)
		atten = nd * nd * pow(maxf(dist, 0.0001), -maxf(decay, 0.0001))
		if spot != null:
			var cone := cos(deg_to_rad(spot.spot_angle))
			var scos: float = maxf((-to_light).dot(-spot.global_transform.basis.z.normalized()), cone)
			var rim := (1.0 - scos) / maxf(1.0 - cone, 0.0001)
			atten *= 1.0 - pow(rim, maxf(spot.spot_angle_attenuation, 0.0001))
	if atten <= 0.0:
		return [Vector3.ZERO, Vector3.UP]

	# Occlusion. The whole reason a bake beats the analytic loop on looks rather
	# than only on cost: the room's own architecture gets to block a lamp.
	var query := PhysicsRayQueryParameters3D.create(p, target, 0xFFFFFFFF, exclude)
	query.collide_with_areas = false
	if not space.intersect_ray(query).is_empty():
		return [Vector3.ZERO, Vector3.UP]

	var e := Vector3(col.r, col.g, col.b) * l.light_energy * atten
	return [e, to_light]


func _luma(v: Vector3) -> float:
	return v.x * 0.2126 + v.y * 0.7152 + v.z * 0.0722


func _push_rgbah(out: PackedByteArray, v: Vector3) -> void:
	# RGBAH: irradiance routinely exceeds 1.0 near a lamp, so an 8-bit format
	# would clip the brightest part of every wall the room has.
	for c in [v.x, v.y, v.z, 1.0]:
		out.append_array(_half(c))


func _push_rgba8(out: PackedByteArray, n: Vector3, frac: float) -> void:
	out.append(int(clampf(n.x * 0.5 + 0.5, 0.0, 1.0) * 255.0))
	out.append(int(clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 255.0))
	out.append(int(clampf(n.z * 0.5 + 0.5, 0.0, 1.0) * 255.0))
	out.append(int(clampf(frac, 0.0, 1.0) * 255.0))


func _half(f: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_half(0, f)
	return b


## Saved as two flat `Image` resources rather than as ImageTexture3D.
##
## An ImageTexture3D drops its source images once it has uploaded them — its
## get_data() fails with "raw_images.is_empty()" — so ResourceSaver writes a
## texture with no pixels in it and reports success. An Image serialises
## properly, so the volume is stored as a TALL 2D image, dims.z slices of
## dims.y rows stacked, and rebuilt into a 3D texture at load. The grid's frame
## rides along as resource metadata, because the shader cannot derive a world
## position from the texture and nothing else in the scene knows it.
func _save(irr: PackedByteArray, dir: PackedByteArray, bounds: AABB,
		dims: Vector3i, out_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tall := dims.y * dims.z
	var images := {
		"irr": Image.create_from_data(dims.x, tall, false, Image.FORMAT_RGBAH, irr),
		"dir": Image.create_from_data(dims.x, tall, false, Image.FORMAT_RGBA8, dir),
	}
	for suffix in images:
		var img: Image = images[suffix]
		img.set_meta("gi_min", bounds.position)
		img.set_meta("gi_size", bounds.size)
		img.set_meta("gi_dims", dims)
		var path := "%s/%s_%s.res" % [OUT_DIR, out_name, suffix]
		var err := ResourceSaver.save(img, path)
		if err != OK:
			push_error("[bake] could not write %s (%d)" % [path, err])
			return
	print("[bake] wrote %s  %dx%dx%d  (%d texels, %.0f KiB)" % [
		out_name, dims.x, dims.y, dims.z, dims.x * dims.y * dims.z,
		(irr.size() + dir.size()) / 1024.0])
