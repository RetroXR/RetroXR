class_name RuntimePropVolume
extends Node
## The props' light, BAKED AT RUN TIME, for a room that ships no volume of its own (a mod room).
##
## On a headset PropLighting puts every StandardMaterial3D prop on `pbr_prop_unshaded`, which reads its light from an
## irradiance volume instead of running Godot's light loop -- but only where ShellLighting has a baked volume to
## lend it, and a mod room has none. The Starlight Arcade lights its 242 props with 18 real lights and a reflection
## probe instead, and on a Quest 3 that lit path was the frame: lights and probe off took the eye pass from 53 to
## 27.6 ms (2026-11-13), the number of lights barely mattering.
##
## This builds the volume the props need from the room's OWN lights, as they stand: a grid over the room, each
## texel the sum of every light's diffuse reach (Godot's own omni curve and spot cone, as `bake_shell_gi.gd` uses)
## plus the environment's ambient, and the dominant direction. No occlusion -- the headset casts no shadows either.
## The work runs on the worker pool; the room's lights stay on for whatever is not a prop (cords, plugs, screens).
## A wall switch is followed: the lights' state is fingerprinted twice a second and a change rebuilds the volume.

const TEXEL := 0.3
const PAD := 0.6
const MAX_TEXELS := 80_000
const POLL_SEC := 0.5
const INTERIOR_LAYER := 1

var room: Node3D
var _prop: PropLighting
var _signature := ""
var _busy := false
var _pending := false
var _poll := 0.0
var _bounds := AABB()


## Whether a room needs one: on a headset, and only where no ShellLighting is there to lend a baked volume.
static func wanted(p_room: Node3D) -> bool:
	return ShellLighting.active() and p_room.find_children("*", "ShellLighting", true, false).is_empty()


func _ready() -> void:
	# The room's set builds its lights in its own _ready, and the restore adds the props over several frames.
	for i in 30:
		await get_tree().process_frame
	if not is_instance_valid(room):
		return
	_rebuild()


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_SEC or room == null:
		return
	_poll = 0.0
	if _fingerprint() != _signature:
		_rebuild()


## Every Light3D in the room, kept up to date from the tree's own signals: searching the room for them twice a
## second was 3.4% of a Quest 3's main thread (2026-11-13).
var _all_lights: Array[Light3D] = []
var _lights_dirty := true


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_tree_changed)
	get_tree().node_removed.disconnect(_on_tree_changed)


func _on_tree_changed(node: Node) -> void:
	if node is Light3D:
		_lights_dirty = true


func _lights() -> Array[Light3D]:
	if _lights_dirty:
		_lights_dirty = false
		_all_lights.clear()
		for n in room.find_children("*", "Light3D", true, false):
			_all_lights.append(n as Light3D)
	var out: Array[Light3D] = []
	for l in _all_lights:
		if is_instance_valid(l) and l.is_visible_in_tree() and l.light_energy > 0.0 and not l.light_negative \
				and (l.light_cull_mask & INTERIOR_LAYER) != 0:
			out.append(l)
	return out


func _fingerprint() -> String:
	var parts := PackedStringArray()
	for l in _lights():
		parts.append("%d:%.3f:%s" % [l.get_instance_id(), l.light_energy, l.light_color.to_html()])
	return ",".join(parts)


func _rebuild() -> void:
	if _busy:
		_pending = true
		return
	_signature = _fingerprint()
	var lights := _lights()
	var snap: Array = []
	for l in lights:
		var col := l.light_color.srgb_to_linear()
		var row := {"col": Vector3(col.r, col.g, col.b) * l.light_energy}
		if l is DirectionalLight3D:
			row["kind"] = 2
			row["dir"] = l.global_transform.basis.z.normalized()
		else:
			row["pos"] = l.global_position
			var spot := l as SpotLight3D
			if spot != null:
				row["kind"] = 1
				row["range"] = spot.spot_range
				row["decay"] = spot.spot_attenuation
				row["axis"] = -spot.global_transform.basis.z.normalized()
				row["cone"] = cos(deg_to_rad(spot.spot_angle))
				row["cone_att"] = spot.spot_angle_attenuation
			else:
				var omni := l as OmniLight3D
				row["kind"] = 0
				row["range"] = omni.omni_range
				row["decay"] = omni.omni_attenuation
		snap.append(row)
	if _bounds.size == Vector3.ZERO:
		_bounds = _room_bounds(lights)
	var dims := Vector3i((_bounds.size / TEXEL).ceil())
	dims = dims.max(Vector3i(2, 2, 2))
	if dims.x * dims.y * dims.z > MAX_TEXELS:
		var f := pow(float(MAX_TEXELS) / float(dims.x * dims.y * dims.z), 1.0 / 3.0)
		dims = Vector3i((Vector3(dims) * f).floor()).max(Vector3i(2, 2, 2))
	var ambient := _ambient()
	var bounds := _bounds
	_busy = true
	var t0 := Time.get_ticks_msec()
	BackgroundTask.start(func() -> void:
		var out := RuntimePropVolume.compute(snap, bounds, dims, ambient)
		_apply.call_deferred(out, bounds, dims, snap.size(), t0), false, "RuntimePropVolume")


func _room_bounds(lights: Array[Light3D]) -> AABB:
	var box := AABB(room.global_position, Vector3.ZERO)
	for l in lights:
		box = box.expand(l.global_position)
	for n in room.get_children():
		if n is Node3D and n.is_in_group("spawned"):
			box = box.expand((n as Node3D).global_position)
	box.position.y = minf(box.position.y, room.global_position.y)
	return box.grow(PAD)


func _ambient() -> Vector3:
	var found := room.find_children("*", "WorldEnvironment", true, false)
	if found.is_empty() or (found[0] as WorldEnvironment).environment == null:
		return Vector3(0.05, 0.05, 0.05)
	var env: Environment = (found[0] as WorldEnvironment).environment
	var amb := env.ambient_light_color.srgb_to_linear() * env.ambient_light_energy
	return Vector3(amb.r, amb.g, amb.b)


## Pure arithmetic, run on a worker: [irr bytes RGBAH, dir bytes RGBA8], z-major slices of y rows of x.
static func compute(snap: Array, bounds: AABB, dims: Vector3i, ambient: Vector3) -> Array:
	var step := bounds.size / Vector3(dims)
	var irr := PackedByteArray()
	irr.resize(dims.x * dims.y * dims.z * 8)
	var dir := PackedByteArray()
	dir.resize(dims.x * dims.y * dims.z * 4)
	var i := 0
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var p := bounds.position + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * step
				var sum := ambient
				var axis := Vector3.ZERO
				for row: Dictionary in snap:
					var kind: int = row["kind"]
					var to_light: Vector3
					var atten := 1.0
					if kind == 2:
						to_light = row["dir"]
					else:
						var d: Vector3 = (row["pos"] as Vector3) - p
						var dist := d.length()
						var range_m: float = row["range"]
						if dist >= range_m:
							continue
						to_light = d / maxf(dist, 0.0001)
						var nd := dist / range_m
						nd = nd * nd
						nd = nd * nd
						nd = maxf(1.0 - nd, 0.0)
						atten = nd * nd * pow(maxf(dist, 0.0001), -maxf(float(row["decay"]), 0.0001))
						if kind == 1:
							var cone: float = row["cone"]
							var scos := maxf((-to_light).dot(row["axis"]), cone)
							var rim := (1.0 - scos) / maxf(1.0 - cone, 0.0001)
							atten *= 1.0 - pow(rim, maxf(float(row["cone_att"]), 0.0001))
					if atten <= 0.0:
						continue
					var e: Vector3 = (row["col"] as Vector3) * atten
					sum += e
					axis += to_light * (e.x * 0.2126 + e.y * 0.7152 + e.z * 0.0722)
				var lum := sum.x * 0.2126 + sum.y * 0.7152 + sum.z * 0.0722
				var frac := clampf(axis.length() / maxf(lum, 0.0001), 0.0, 1.0)
				var n := axis.normalized() if axis.length() > 0.0001 else Vector3.UP
				irr.encode_half(i * 8, sum.x)
				irr.encode_half(i * 8 + 2, sum.y)
				irr.encode_half(i * 8 + 4, sum.z)
				irr.encode_half(i * 8 + 6, 1.0)
				dir[i * 4] = int(clampf(n.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				dir[i * 4 + 1] = int(clampf(n.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				dir[i * 4 + 2] = int(clampf(n.z * 0.5 + 0.5, 0.0, 1.0) * 255.0)
				dir[i * 4 + 3] = int(frac * 255.0)
				i += 1
	return [irr, dir]


func _apply(out: Array, bounds: AABB, dims: Vector3i, lights: int, t0: int) -> void:
	_busy = false
	if not is_instance_valid(room) or not is_inside_tree():
		return
	var volume := {
		"irr": _texture(out[0], Image.FORMAT_RGBAH, dims),
		"dir": _texture(out[1], Image.FORMAT_RGBA8, dims),
		"min": bounds.position, "size": bounds.size, "tint": Vector3.ONE,
	}
	print("[RuntimePropVolume] %s: %d light(s) into %dx%dx%d texels over %s m in %d ms" % [
		room.name, lights, dims.x, dims.y, dims.z, str(bounds.size.snapped(Vector3.ONE * 0.1)), Time.get_ticks_msec() - t0])
	if _prop == null:
		_prop = PropLighting.new()
		_prop.name = "RuntimePropLighting"
		add_child(_prop)
		var shader: Shader = load(PropLighting.PROP_SHADER)
		_prop.call("_start", room, shader, volume)
	else:
		_prop.call("_on_volume_changed", volume)
	if _pending:
		_pending = false
		_rebuild()


static func _texture(bytes: PackedByteArray, format: Image.Format, dims: Vector3i) -> ImageTexture3D:
	var px := 8 if format == Image.FORMAT_RGBAH else 4
	var slices: Array[Image] = []
	var slice_bytes := dims.x * dims.y * px
	for z in dims.z:
		slices.append(Image.create_from_data(dims.x, dims.y, false, format, bytes.slice(z * slice_bytes, (z + 1) * slice_bytes)))
	var tex := ImageTexture3D.new()
	tex.create(format, dims.x, dims.y, dims.z, false, slices)
	return tex
