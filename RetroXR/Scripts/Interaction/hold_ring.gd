## HoldRing — the filling ring HoldToGrab shows in VR: a camera-facing quad with
## shaders/hold_ring.gdshader, placed where the hand is holding on.
class_name HoldRing
extends Node3D

const SHADER := preload("res://Shaders/hold_ring.gdshader")
const DIAMETER := 0.09

var _mat: ShaderMaterial = null


func _init() -> void:
	name = "HoldRing"
	visible = false
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(DIAMETER, DIAMETER)
	mi.mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Show the ring `p` full (0..1) at `world_pos`, turned to face the viewer.
func show_at(world_pos: Vector3, p: float) -> void:
	global_position = world_pos
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		look_at(cam.global_position, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)   # a QuadMesh faces +Z, look_at points -Z
	_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
	visible = true


func hide_ring() -> void:
	visible = false
