class_name PathTracedDecals
extends Node
## Under the path tracer, a print laid over a shell as an ALPHA_DEPTH_PRE_PASS surface (a console's
## "SONY" and "PlayStation", a button's word) is drawn as alpha SCISSOR, and put back when it stops.
##
## Why: project.godot keeps `pathtracing/max_transparency_layers` at 0 (a TV picture and its labels
## vanished otherwise), so every BLENDED surface is rasterised over the traced image, before DLSS Ray
## Reconstruction. RR denoises against guides -- diffuse albedo, normal, roughness -- that are written
## by the trace alone, and they show the bare shell under the print. Text that is in the colour and not
## in the albedo is, to RR, noise: it was smeared to a blur at every scale, DLAA 100% included, while
## raster + DLSS kept it sharp (measured on xenu.psx's SCPH-1001, 2026-11-13). A scissor surface is
## OPAQUE to the tracer (any-hit alpha test), so the print is in the guides and comes through crisp.
##
## Only a decal-like material is touched: depth pre-pass, its alpha from a TEXTURE (albedo colour
## opaque), so a tinted see-through plastic, whose alpha is its colour's, keeps blending. Plain ALPHA
## (glass, screens) is never touched. A material is changed in place, so every user of it flips with
## it; a copy made while swapped keeps the scissor.

const THRESHOLD := 0.5

var active := false
## [WeakRef to the material, its transparency, its scissor threshold], to put back.
var _swapped: Array = []
var _queue: Array[Node] = []
var _flush_queued := false


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		get_tree().node_added.connect(_on_node_added)
		var before := _swapped.size()
		for gi in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
			_swap_in(gi as GeometryInstance3D)
		print("[QualityManager] path tracing: %d decal material(s) drawn as alpha scissor" % (_swapped.size() - before))
	else:
		get_tree().node_added.disconnect(_on_node_added)
		_queue.clear()
		var restored := 0
		for entry: Array in _swapped:
			var mat := (entry[0] as WeakRef).get_ref() as BaseMaterial3D
			if mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				mat.transparency = entry[1]
				mat.alpha_scissor_threshold = entry[2]
				restored += 1
		_swapped.clear()
		print("[QualityManager] path tracing off: %d decal material(s) blended again" % restored)


static func is_decal(mat: Material) -> bool:
	var bm := mat as BaseMaterial3D
	return bm != null and bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS \
		and bm.albedo_texture != null and bm.albedo_color.a >= 0.99


func _swap_in(gi: GeometryInstance3D) -> void:
	_swap_material(gi.material_override)
	var mi := gi as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		_swap_material(mi.get_active_material(s))


func _swap_material(mat: Material) -> void:
	if not is_decal(mat):
		return
	var bm := mat as BaseMaterial3D
	_swapped.append([weakref(bm), bm.transparency, bm.alpha_scissor_threshold])
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	bm.alpha_scissor_threshold = THRESHOLD


func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_queue.append(node)
		if not _flush_queued:
			_flush_queued = true
			_flush.call_deferred()


## Deferred to the end of the frame the nodes arrived in, so a material a script sets in its own _ready is there.
func _flush() -> void:
	_flush_queued = false
	if not active:
		_queue.clear()
		return
	var before := _swapped.size()
	for node in _queue:
		if is_instance_valid(node):
			_swap_in(node as GeometryInstance3D)
	_queue.clear()
	if _swapped.size() != before:
		print("[QualityManager] path tracing: %d more decal material(s) drawn as alpha scissor (%d in all)" \
			% [_swapped.size() - before, _swapped.size()])
