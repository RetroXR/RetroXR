## CartridgeColor — recolours a cartridge's moulded shell at runtime, one half at a
## time, without touching the imported model, its labels, board, contacts, screws
## or anything inside it.
##
## Every surface painted gets a material of its own on its MeshInstance3D, so one
## cartridge never repaints another, the source GLB, or its own other half. What a
## surface wore before its first paint is kept on the node, and reset_to_default()
## puts exactly that back.
##
##     CartridgeColor.apply_preset(cart, &"gold_silver")
##     CartridgeColor.apply_color(cart, Color("#24479a"))
##     CartridgeColor.apply_two_tone(cart, &"gold", Color.BLACK)
##     CartridgeColor.reset_to_default(cart)
##     CartridgeColor.apply_preset(gb_cart, &"red", "gb")
##
## `cart` is the GLB instance or any node above it. Plain presets and colours stay
## on StandardMaterial3D duplicates; METAL_FLAKE presets switch that surface to
## cartridge_flake_plastic.gdshader, carrying the normal map across. Preset names
## are looked up in the palette of the system given, N64 when none is.
class_name CartridgeColor
extends RefCounted

enum Half { FRONT, BACK }

const PALETTE_PATH := "res://Resources/n64_cartridge_shells.tres"
const PALETTE_PATHS := {
	"n64": PALETTE_PATH,
	"gb": "res://Resources/gb_cartridge_shells.tres",
}
const FLAKE_SHADER := preload("res://Shaders/cartridge_flake_plastic.gdshader")

## Materials of the exterior moulding, by the name the model gives them: the N64
## bodies' three, then the Game Boy cart's front, rear, smooth rails and the rim
## round its sticker recess.
const EXTERIOR_PLASTIC: Array[StringName] = [&"Shell_Plastic", &"Molded_Smooth_Plastic", &"Nintendo_Molded_SVG",
	&"Gray_ABS_Textured", &"Rear_ABS_Rough", &"Gray_ABS_Smooth", &"Shell_Seam_Shadow"]

## A moulding authored lighter or darker than the rest of its shell, as a factor
## on the colour painted: the Game Boy cart's ratios to its front shell. Every
## other material takes the colour as given.
const SHADE := {
	&"Gray_ABS_Smooth": 1.03,
	&"Shell_Seam_Shadow": 0.65,
}

## Mouldings whose own roughness a paint keeps, because the texture of the mould
## (the Game Boy cart's rough rear, smooth rails and matte rim) sets it rather
## than the plastic's colour.
const OWN_ROUGHNESS: Array[StringName] = [&"Gray_ABS_Textured", &"Rear_ABS_Rough", &"Gray_ABS_Smooth",
	&"Shell_Seam_Shadow"]

## The half each moulded part belongs to, by node-name prefix. The Nintendo logo
## patch and the bottom latch tabs are part of the rear moulding. A part not
## listed is placed by which side of the cartridge's XY plane it sits on.
const HALF_BY_NODE := {
	"Front_Shell": Half.FRONT,
	"Rear_Shell": Half.BACK,
	"Nintendo_SVG_Relief": Half.BACK,
	"Bottom_Latch_Tongue": Half.BACK,
}

const _META := &"cartridge_shell"

## Replace to use another N64 palette.
static var palette: CartridgeShellPalette = null
static var _palettes := {}


## The palette for a system, or null when it has none.
static func get_palette(systemid := "n64") -> CartridgeShellPalette:
	if systemid == "n64":
		if palette == null:
			palette = load(PALETTE_PATH) as CartridgeShellPalette
		return palette
	if not _palettes.has(systemid) and PALETTE_PATHS.has(systemid):
		_palettes[systemid] = load(PALETTE_PATHS[systemid]) as CartridgeShellPalette
	return _palettes.get(systemid)


static func apply_preset(cartridge: Node, preset_name: StringName, systemid := "n64") -> Error:
	var preset := _find_preset(preset_name, systemid)
	if preset == null:
		return ERR_DOES_NOT_EXIST
	if preset.is_two_tone():
		return apply_two_tone(cartridge, preset.front, preset.back, systemid)
	return _paint(cartridge, preset, preset)


static func apply_color(cartridge: Node, color: Color) -> Error:
	return _paint(cartridge, color, color)


## Each half is a Color or the id of a single-colour preset.
static func apply_two_tone(cartridge: Node, front_color: Variant, back_color: Variant,
		systemid := "n64") -> Error:
	var front: Variant = _finish_of(front_color, systemid)
	var back: Variant = _finish_of(back_color, systemid)
	if front == null or back == null:
		return ERR_INVALID_PARAMETER
	return _paint(cartridge, front, back)


static func reset_to_default(cartridge: Node) -> Error:
	if cartridge == null:
		return ERR_INVALID_PARAMETER
	var found := false
	for mi in _meshes(cartridge):
		if not mi.has_meta(_META):
			continue
		found = true
		var state: Dictionary = mi.get_meta(_META)
		for i: int in state:
			mi.set_surface_override_material(i, state[i]["original"])
		mi.remove_meta(_META)
	return OK if found or not shell_surfaces(cartridge).is_empty() else ERR_DOES_NOT_EXIST


## Every exterior plastic surface under `cartridge`: {mesh, surface, half}.
static func shell_surfaces(cartridge: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cartridge == null:
		return out
	for mi in _meshes(cartridge):
		for i in mi.mesh.get_surface_count():
			if _source_of(mi, i) != null:
				out.append({"mesh": mi, "surface": i, "half": _half_of(cartridge, mi)})
	return out


static func _find_preset(id: StringName, systemid: String) -> CartridgeShellPreset:
	var p := get_palette(systemid)
	return p.find(id) if p != null else null


static func _finish_of(v: Variant, systemid: String) -> Variant:
	if v is Color:
		return v
	if v is String or v is StringName:
		var preset := _find_preset(StringName(v), systemid)
		if preset != null and not preset.is_two_tone():
			return preset
	return null


static func _paint(cartridge: Node, front: Variant, back: Variant) -> Error:
	var surfaces := shell_surfaces(cartridge)
	if surfaces.is_empty():
		return ERR_DOES_NOT_EXIST
	for s in surfaces:
		_paint_surface(s["mesh"], s["surface"], front if s["half"] == Half.FRONT else back)
	return OK


static func _paint_surface(mi: MeshInstance3D, i: int, finish: Variant) -> void:
	var slot := _slot(mi, i)
	var source := slot["source"] as BaseMaterial3D
	var material_name := StringName(source.resource_name)
	var shade: float = SHADE.get(material_name, 1.0)
	var own_roughness := OWN_ROUGHNESS.has(material_name)
	if finish is CartridgeShellPreset and finish.finish == CartridgeShellPreset.Finish.METAL_FLAKE:
		var sm := slot.get("flake") as ShaderMaterial
		if sm == null:
			sm = _flake_material(source)
			slot["flake"] = sm
		_set_flake(sm, finish)
		sm.set_shader_parameter("albedo", _shaded(finish.color, shade))
		sm.set_shader_parameter("flake_color", _shaded(finish.flake_color, shade))
		if own_roughness:
			sm.set_shader_parameter("roughness", source.roughness)
		mi.set_surface_override_material(i, sm)
		return
	var pm := slot.get("plain") as BaseMaterial3D
	if pm == null:
		pm = source.duplicate() as BaseMaterial3D
		slot["plain"] = pm
	if finish is CartridgeShellPreset:
		pm.albedo_color = _shaded(finish.color, shade)
		pm.roughness = source.roughness if own_roughness else finish.roughness
	else:
		pm.albedo_color = _shaded(finish, shade)
		pm.roughness = source.roughness
	mi.set_surface_override_material(i, pm)


static func _shaded(c: Color, shade: float) -> Color:
	if shade == 1.0:
		return c
	return Color(clampf(c.r * shade, 0.0, 1.0), clampf(c.g * shade, 0.0, 1.0), clampf(c.b * shade, 0.0, 1.0), c.a)


static func _flake_material(source: BaseMaterial3D) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = FLAKE_SHADER
	sm.resource_name = source.resource_name
	sm.set_shader_parameter("specular", source.metallic_specular)
	sm.set_shader_parameter("normal_enabled", source.normal_enabled and source.normal_texture != null)
	sm.set_shader_parameter("texture_normal", source.normal_texture)
	sm.set_shader_parameter("normal_scale", source.normal_scale)
	sm.set_shader_parameter("uv1_scale", source.uv1_scale)
	sm.set_shader_parameter("uv1_offset", source.uv1_offset)
	return sm


static func _set_flake(sm: ShaderMaterial, p: CartridgeShellPreset) -> void:
	sm.set_shader_parameter("albedo", p.color)
	sm.set_shader_parameter("roughness", p.roughness)
	sm.set_shader_parameter("flake_color", p.flake_color)
	sm.set_shader_parameter("flake_density", p.flake_density)
	sm.set_shader_parameter("flake_size_mm", p.flake_size_mm)
	sm.set_shader_parameter("flake_intensity", p.flake_intensity)
	sm.set_shader_parameter("flake_roughness", p.flake_roughness)
	sm.set_shader_parameter("flake_tilt", p.flake_tilt)


## Per-surface state: the override it had and the material it showed before the
## first paint, plus the duplicates painted since.
static func _slot(mi: MeshInstance3D, i: int) -> Dictionary:
	var state: Dictionary = mi.get_meta(_META, {})
	if not state.has(i):
		state[i] = {"original": mi.get_surface_override_material(i), "source": mi.get_active_material(i)}
		mi.set_meta(_META, state)
	return state[i]


## The material a shell surface is painted from, or null when it is not exterior plastic.
static func _source_of(mi: MeshInstance3D, i: int) -> BaseMaterial3D:
	var state: Dictionary = mi.get_meta(_META, {})
	var m: Material = state[i]["source"] if state.has(i) else mi.get_active_material(i)
	if m is BaseMaterial3D and EXTERIOR_PLASTIC.has(StringName(m.resource_name)):
		return m
	return null


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out


static func _half_of(root: Node, mi: MeshInstance3D) -> Half:
	for prefix: String in HALF_BY_NODE:
		if String(mi.name).begins_with(prefix):
			return HALF_BY_NODE[prefix]
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return Half.FRONT if (xf * mi.get_aabb().get_center()).z >= 0.0 else Half.BACK
