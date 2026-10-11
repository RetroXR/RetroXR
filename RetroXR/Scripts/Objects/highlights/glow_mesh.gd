## Makes named meshes inside an instanced GLB read as lit.
##
## Downloaded fixtures usually ship ONE material shared by every part — the
## ceiling fan uses `Ceiling_Fan_Mat` for its blades, housing, downrod and glass
## alike — so emission cannot simply be switched on at the material or the whole
## fixture glows. This duplicates the material on the named meshes only, the same
## way bedroom_exterior.gd duplicates before retinting.
##
## Registers in the "light_glow" group so a switch can darken the glass at the
## same time it kills the light; otherwise flipping the switch leaves a glowing
## shade over an unlit room.
class_name GlowMesh
extends Node3D


## Mesh node names to make emissive, matched exactly against MeshInstance3D.name.
## The ceiling fan's glass globe exports as "defaultMaterial4" — the GLB names
## every part after the material it uses, so these are positional, not
## descriptive. Re-check them if the model is ever replaced.
@export var glow_meshes: PackedStringArray = []

@export var glow_color: Color = Color(1, 0.85, 0.6)
@export var glow_energy: float = 1.6

## Transmissive fixture parts that must not block their own light's shadow map.
## Includes the bulb itself when the light sits inside its modelled envelope.
@export var shadowless_meshes: PackedStringArray = []

## Meshes to turn into LIT GLASS — a shade you can see the bulb through.
##
## Without this the only way to show a fixture was on was to make the shade itself
## emissive, which lights up the glass and leaves the bulb inside it dark. The
## fan's globe is opaque in the GLB (one material for the whole fixture), so the
## spiral CFL modelled inside it was invisible and could not be the thing that
## glowed. Making the globe translucent puts the bulb back on show.
@export var glass_meshes: PackedStringArray = []
## Alpha carries in .a. Frosted rather than clear: the bulb should read as a warm
## shape through the glass, not as a crisp spiral.
@export var glass_color: Color = Color(0.95, 0.93, 0.86, 0.38)
@export var glass_roughness: float = 0.35
## The shade picks up a little of its own glow when lit — real frosted glass does —
## but far less than the bulb, or it goes back to being the light source.
@export var glass_glow_energy: float = 0.25

## Starting state, matched to whatever the room's lights are authored at.
@export var lit: bool = true

var _mats: Array[BaseMaterial3D] = []
var _glass: Array[BaseMaterial3D] = []


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if shadowless_meshes.has(mi.name):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null:
			continue
		var is_glow := glow_meshes.has(mi.name)
		var is_glass := glass_meshes.has(mi.name)
		if not is_glow and not is_glass:
			continue
		for si in mi.mesh.get_surface_count():
			var dup := _dup_material(mi, si)
			dup.emission_enabled = true
			dup.emission = glow_color
			if is_glass:
				dup.albedo_color = glass_color
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				dup.roughness = glass_roughness
				# Both faces: a single-sided sphere shell shows nothing of its far
				# wall once you can see through the near one.
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
				_glass.append(dup)
			else:
				_mats.append(dup)
			mi.set_surface_override_material(si, dup)
	add_to_group("light_glow")
	_apply()


func _dup_material(mi: MeshInstance3D, si: int) -> BaseMaterial3D:
	var src: Material = mi.get_active_material(si)
	if src is BaseMaterial3D:
		return (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	return StandardMaterial3D.new()


func set_lit(on: bool) -> void:
	lit = on
	_apply()


func _apply() -> void:
	for mat in _mats:
		mat.emission_energy_multiplier = glow_energy if lit else 0.0
	for mat in _glass:
		mat.emission_energy_multiplier = glass_glow_energy if lit else 0.0
