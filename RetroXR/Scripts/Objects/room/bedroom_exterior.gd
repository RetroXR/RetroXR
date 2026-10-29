## The street outside the bedroom window: Cycles renders of a late-summer Midwest street, projected back onto
## proxies of its own shape (built in RetroXR-models, rooms/bedroom).
##
## Each of TimeOfDay's six keys was rendered once from the window opening's center, as three layers: the
## backdrop (houses, lawns, road, far trees), the foreground (what stands near enough to shift against the
## backdrop as the head moves: the van, the hoop, the poles, the near trees and shrubs) and the sky. Each layer
## is one mesh with one unshaded material, so the whole street is three draws whatever is in it: the grass and
## the leaves cost the headset nothing, they are pixels.
##
## Two keys are bound at a time, the pair the lever sits between, mixed by its position. Keys load on a thread
## when the lever crosses into a new pair; until they arrive the street holds the nearest key it has. Only
## the pair in use stays in memory.
##
## The TV in the ranch across the street flickers after dusk: a mask of its window and a light this script
## varies, so it costs a uniform write per frame and only while it is on.
extends Node3D

## Layer the street draws on, so nothing that lights or bakes the room ever touches it.
const EXTERIOR_LAYER := 2
const DIR := "res://imported-assets/bedroom/street/"

@export var time_of_day_path: NodePath = NodePath("../TimeOfDay")
## Scales the renders' light. The keys' exposures are already folded into the textures; this is a trim.
@export var exposure: float = 1.0
@export var tv_color: Color = Color(0.45, 0.62, 1.0)
## A pane of the window's glass; its material (shared by both panes) mirrors the room more as the street darkens.
@export var glass_path: NodePath = NodePath("../Window/PaneLower")

var _tod: Node = null
var _meta: Dictionary = {}
var _keys: Array = []                   # [{name, t}]
var _mats: Dictionary = {}              # layer -> ShaderMaterial
var _tex: Dictionary = {}               # "<key>_<layer>" -> Texture2D, only the bound pair
var _pending: Dictionary = {}           # path -> true while a threaded load is out
var _time := -1.0
var _pair := Vector2i(-1, -1)
var _tv_gain := 0.0


func _ready() -> void:
	var f := FileAccess.open(DIR + "street.json", FileAccess.READ)
	if f == null:
		push_warning("[BedroomExterior] no street.json; the window shows nothing")
		set_process(false)
		return
	_meta = JSON.parse_string(f.get_as_text())
	_keys = _meta["keys"]
	var p: Array = _meta["proj_p"]
	var az: Array = _meta["az"]
	var el: Array = _meta["el"]
	var ranges := Vector4(deg_to_rad(az[0]), deg_to_rad(az[1]), deg_to_rad(el[0]), deg_to_rad(el[1]))
	for layer in ["sky", "bg", "fg"]:
		var shader: Shader = load("res://Shaders/street_sky.gdshader" if layer == "sky" else "res://Shaders/street_layer.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("proj_p", Vector3(p[0], p[1], p[2]))
		mat.set_shader_parameter("ranges", ranges)
		mat.set_shader_parameter("exposure", exposure)
		if layer == "fg":
			var r: Array = _meta["fg_rect"]
			mat.set_shader_parameter("crop", Vector4(r[0], r[1], r[2], r[3]))
		if layer == "bg" and ResourceLoader.exists(DIR + "street_tv.png"):
			var tr: Array = _meta["tv_rect"]
			mat.set_shader_parameter("tv_mask", load(DIR + "street_tv.png"))
			mat.set_shader_parameter("tv_rect", Vector4(tr[0], tr[1], tr[2], tr[3]))
		_mats[layer] = mat
		var scene: PackedScene = load(DIR + "street_%s.glb" % layer)
		var root := scene.instantiate()
		add_child(root)
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.layers = EXTERIOR_LAYER
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.material_override = mat
	_tod = get_node_or_null(time_of_day_path)
	if _tod != null and _tod.has_signal("time_changed"):
		_tod.time_changed.connect(_on_time)
	# TimeOfDay restores the saved time in its own _ready, after ours, and does not signal it: read it after.
	_read_time.call_deferred()


func _read_time() -> void:
	_on_time(_tod.time if _tod != null else 0.75)


func _on_time(t: float) -> void:
	_time = clampf(t, 0.0, 1.0)
	_apply()


## Which two keys bracket `t`, and how far between them.
func _bracket(t: float) -> Array:
	for i in _keys.size() - 1:
		var t0: float = _keys[i]["t"]
		var t1: float = _keys[i + 1]["t"]
		if t <= t1 or i == _keys.size() - 2:
			return [i, i + 1, clampf((t - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0)]
	return [0, 0, 0.0]


func _path(key: int, layer: String) -> String:
	return DIR + "street_%s_%s.%s" % [_keys[key]["name"], layer, "png" if layer == "sky" else "webp"]


func _has(key: int) -> bool:
	for layer in _mats:
		if not _tex.has("%d_%s" % [key, layer]):
			return false
	return true


func _request(key: int) -> void:
	for layer in _mats:
		var id := "%d_%s" % [key, layer]
		var path := _path(key, layer)
		if _tex.has(id) or _pending.has(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = [key, layer]
	set_process(true)


func _apply() -> void:
	if _keys.is_empty() or _time < 0.0:
		return
	var b := _bracket(_time)
	var a: int = b[0]
	var c: int = b[1]
	var f: float = b[2]
	_pair = Vector2i(a, c)
	# the first time, nothing is bound: load the pair now rather than show an empty window
	if _tex.is_empty():
		for k in [a, c]:
			for layer in _mats:
				_tex["%d_%s" % [k, layer]] = load(_path(k, layer))
	if not (_has(a) and _has(c)):
		_request(a)
		_request(c)
		# until they arrive, hold whatever bound key is nearest
		var have := -1
		for k in [a, c]:
			if _has(k):
				have = k
		if have < 0:
			return
		a = have
		c = have
	for layer in _mats:
		var mat: ShaderMaterial = _mats[layer]
		mat.set_shader_parameter("key_a", _tex["%d_%s" % [a, layer]])
		mat.set_shader_parameter("key_b", _tex["%d_%s" % [c, layer]])
		mat.set_shader_parameter("blend", f if a != c else 0.0)
	_evict(a, c)
	# the glass: a faint reflection by day, the room plain in it at night
	var pane := get_node_or_null(glass_path) as MeshInstance3D
	if pane != null and pane.get_surface_override_material(0) is ShaderMaterial:
		(pane.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter(
			"reflection", lerpf(0.06, 0.3, smoothstep(0.7, 1.0, _time)))
	# the TV is on from dusk, brightest at night
	_tv_gain = smoothstep(0.7, 0.95, _time) * 3.0
	set_process(_tv_gain > 0.0 or not _pending.is_empty())
	if _tv_gain <= 0.0:
		(_mats["bg"] as ShaderMaterial).set_shader_parameter("tv_light", Vector3.ZERO)


## Let go of every key but the bound pair, so their textures leave memory.
func _evict(a: int, c: int) -> void:
	for id in _tex.keys():
		var k := int(String(id).get_slice("_", 0))
		if k != a and k != c and k != _pair.x and k != _pair.y:
			_tex.erase(id)


func _process(_delta: float) -> void:
	if not _pending.is_empty():
		var landed := false
		for path in _pending.keys():
			var st := ResourceLoader.load_threaded_get_status(path)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var kl: Array = _pending[path]
				_tex["%d_%s" % [kl[0], kl[1]]] = ResourceLoader.load_threaded_get(path)
				_pending.erase(path)
				landed = true
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(path)
		if landed:
			_apply()
	if _tv_gain > 0.0:
		# a TV's light: a scene-cut step a few times a second over a fast shimmer
		var s := Time.get_ticks_msec() * 0.001
		var cut := fposmod(sin(floorf(s * 2.3) * 12.9898) * 43758.5453, 1.0)
		var shimmer := 0.85 + 0.15 * sin(s * 31.0) * sin(s * 17.0)
		var c := tv_color
		var k := _tv_gain * (0.35 + 0.65 * cut) * shimmer
		(_mats["bg"] as ShaderMaterial).set_shader_parameter("tv_light", Vector3(c.r, c.g, c.b) * k)
	elif _pending.is_empty():
		set_process(false)
