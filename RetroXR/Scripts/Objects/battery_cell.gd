## BatteryCell — an AA, AAA or C cell: a thing of its own, put in a battery bay's
## slot of its size (CellSlots) with the bay's cover off.
##
## Its middle at its origin, its + end toward +Z and the label's front toward +Y,
## as a BatteryAA<n> / BatteryAAA<n> seat is (RetroXR-models generic/battery).
## Round about its long axis, so it goes in at the roll the hand holds it at
## (CellSlot); the ghost over the bay shows the same, as a disc shows its spin,
## so nothing turns when it is let go.
class_name BatteryCell
extends XRToolsPickable

## "AA", "AAA" or "C". Set by the scene; the cell joins CellSlots.group_for(size)
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
	"C": {"black_gold": preload("res://imported-assets/batteries/labels/battery_c_black_gold.png")},
}
## The model's label material, by its name in the GLB.
const LABEL_MATERIAL := "Label"

## Labels mods add (ModApi.register_cell_label): id -> {label, color, textures:
## {size -> texture path}, owner}. A texture is the label laid out as that size's
## own (RetroXR-models generic/battery: artwork/label_<size>_template.png, scaled to
## the game's 1024 px across), worn on the model's Label surface as the shipped
## Black & Gold is. Its id is saved (model_variant): a cell whose label's mod is gone
## wears the model's own.
static var _mod_labels := {}


func _ready() -> void:
	super()
	# Given before the cell entered the room, by the spawn menu or a save.
	wear_label(SystemModelRegistry.variant_of(self))


## Wear the label `variant` (an id of VARIANTS); "" or one this build does not
## have is the model's own.
func wear_label(variant: String) -> void:
	var texture := label_texture(size, variant)
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


## The texture label `variant` puts on a cell of `size`, or null for the model's
## own (the first label, or one no texture is painted for at that size).
static func label_texture(cell_size: String, variant: String) -> Texture2D:
	var shipped := (LABELS.get(cell_size, {}) as Dictionary).get(variant) as Texture2D
	if shipped != null:
		return shipped
	var row: Dictionary = _mod_labels.get(variant, {})
	var path := str((row.get("textures", {}) as Dictionary).get(cell_size, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The labels a cell of `size` comes in, as the spawn menu's hold picker lists them
## ({id, label, color}): the model's own first, then every other with a texture for
## this size, the shipped ones before the mods'.
static func variants_for(cell_size: String) -> Array:
	var out: Array = [VARIANTS[0]]
	for v: Dictionary in VARIANTS.slice(1):
		if (LABELS.get(cell_size, {}) as Dictionary).has(v["id"]):
			out.append(v)
	for id: String in _mod_labels:
		var row: Dictionary = _mod_labels[id]
		if (row["textures"] as Dictionary).has(cell_size):
			out.append({"id": id, "label": row["label"], "color": row["color"]})
	return out


## Add a mod's label (ModApi.register_cell_label). `spec`: {label, color?,
## textures: {"AA"|"AAA"|"C" -> texture path}}. "" when it took, else why not.
static func register_mod_label(id: String, spec: Dictionary, owner_id: String) -> String:
	for v: Dictionary in VARIANTS:
		if v["id"] == id:
			return "'%s' is one of the game's own labels" % id
	if _mod_labels.has(id):
		return "'%s' is already added by mod '%s'" % [id, (_mod_labels[id] as Dictionary)["owner"]]
	var label := str(spec.get("label", "")).strip_edges()
	if label.is_empty():
		return "no label (the name the hold menu shows)"
	if spec.has("color") and not spec["color"] is Color:
		return "color is not a Color"
	var textures: Variant = spec.get("textures", {})
	if not textures is Dictionary or (textures as Dictionary).is_empty():
		return "no textures (one per cell size it is painted for: %s)" % ", ".join(CellSlots.SIZES)
	for cell_size: Variant in (textures as Dictionary):
		if not CellSlots.SIZES.has(str(cell_size)):
			return "'%s' is not a cell size (%s)" % [cell_size, ", ".join(CellSlots.SIZES)]
		var path := str((textures as Dictionary)[cell_size])
		if not ResourceLoader.exists(path) or not load(path) is Texture2D:
			return "%s: no such texture %s" % [cell_size, path]
	_mod_labels[id] = {"label": label, "color": spec.get("color", Color(0.6, 0.6, 0.6)),
		"textures": (textures as Dictionary).duplicate(), "owner": owner_id}
	print("[Cells] label %s (%s) added by mod %s for %s" % [id, label, owner_id,
		", ".join((textures as Dictionary).keys())])
	return ""


## Take back what mod `owner_id` gave (ModApi.withdraw).
static func drop_mod(owner_id: String) -> void:
	for id: String in _mod_labels.keys():
		if (_mod_labels[id] as Dictionary)["owner"] == owner_id:
			_mod_labels.erase(id)


## The type a save names it by: "battery_aa", "battery_aaa".
func save_type() -> String:
	return "battery_" + size.to_lower()


## The ghost's pose in a slot: `seat` turned by the roll `held` has about it.
## Called by XRToolsSnapZone.preview_pose_for.
func preview_basis_for(seat: Basis, held: Basis) -> Basis:
	return CellSlot.roll_basis(seat, held)
