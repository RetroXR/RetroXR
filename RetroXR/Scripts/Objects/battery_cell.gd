## BatteryCell — an AA or AAA cell: a thing of its own, put in a battery bay's
## slot of its size (CellSlots) with the bay's cover off.
##
## Its middle at its origin, its + end toward +Z and the label's front toward +Y,
## as a BatteryAA<n> / BatteryAAA<n> seat is (RetroXR-models generic/battery).
## Round about its long axis, so it goes in at the roll the hand holds it at
## (CellSlot); the ghost over the bay shows the same, as a disc shows its spin,
## so nothing turns when it is let go.
class_name BatteryCell
extends XRToolsPickable

## "AA" or "AAA". Set by the scene; the cell joins CellSlots.group_for(size)
## there too, which is what a slot of that size takes.
@export var size := "AA"

## The labels a cell comes in, as the spawn menu's hold picker lists them
## ({id, label, color}: SystemModelRegistry's variant rows). The first is the cell
## as it comes, the model's own label; the rest are textures for the same label,
## laid out the same (RetroXR-models generic/battery/artwork/variants). The ids
## are saved (model_variant): never rename one.
const VARIANTS: Array = [
	{"id": "classic", "label": "Classic", "color": Color(0.0, 0.85, 0.91)},
	{"id": "black_gold", "label": "Black & Gold", "color": Color(0.79, 0.64, 0.31)},
]
## Each label but the first, by size and id. Preloaded, so an export carries them.
const LABELS := {
	"AA": {"black_gold": preload("res://imported-assets/batteries/labels/battery_aa_black_gold.png")},
	"AAA": {"black_gold": preload("res://imported-assets/batteries/labels/battery_aaa_black_gold.png")},
}
## The model's label material, by its name in the GLB.
const LABEL_MATERIAL := "Label"


func _ready() -> void:
	super()
	# Given before the cell entered the room, by the spawn menu or a save.
	wear_label(SystemModelRegistry.variant_of(self))


## Wear the label `variant` (an id of VARIANTS); "" or one this build does not
## have is the model's own.
func wear_label(variant: String) -> void:
	var texture := (LABELS.get(size, {}) as Dictionary).get(variant) as Texture2D
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var own := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if own == null or own.resource_name != LABEL_MATERIAL:
				continue
			if texture == null:
				mi.set_surface_override_material(s, null)
				continue
			var worn := own.duplicate() as BaseMaterial3D
			worn.albedo_texture = texture
			mi.set_surface_override_material(s, worn)


## The type a save names it by: "battery_aa", "battery_aaa".
func save_type() -> String:
	return "battery_" + size.to_lower()


## The ghost's pose in a slot: `seat` turned by the roll `held` has about it.
## Called by XRToolsSnapZone.preview_pose_for.
func preview_basis_for(seat: Basis, held: Basis) -> Basis:
	return CellSlot.roll_basis(seat, held)
