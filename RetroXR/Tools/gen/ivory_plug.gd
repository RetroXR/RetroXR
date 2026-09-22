extends SceneTree

## Bake nema_5_15_plug_ivory.res: the grounded US plug with its matte body (class
## 0.7, see connector.gdshader) in the power strip's case colour, pins untouched.
## A body in its OWN colour ignores the instance tint, so the colour has to be baked.
##
##   godot --headless --path RetroXR -s res://Tools/gen/ivory_plug.gd

## The strip's Mat_body, (0.80, 0.79, 0.74) linear in Blender, as sRGB.
const CASE := Color(0.906, 0.901, 0.876)


func _init() -> void:
	var src: ArrayMesh = load("res://Scenes/Objects/cables/nema_5_15_plug.res")
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for v in colors.size():
			if absf(colors[v].a - 0.7) < 0.01:
				colors[v] = Color(CASE, colors[v].a)
		arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(src.surface_get_primitive_type(i), arrays)
		out.surface_set_material(i, src.surface_get_material(i))
		out.surface_set_name(i, src.surface_get_name(i))
	var err := ResourceSaver.save(out, "res://Scenes/Objects/cables/nema_5_15_plug_ivory.res")
	print("[ivory_plug] saved: ", error_string(err))
	quit()
