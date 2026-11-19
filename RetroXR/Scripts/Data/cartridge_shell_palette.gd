## The shell presets CartridgeColor applies by name.
## Mod packs load this script BY PATH (their .tres/.tscn name res://Scripts/Data/cartridge_shell_palette.gd):
## moving or renaming it breaks every installed pack that uses it. Keep it here.
class_name CartridgeShellPalette
extends Resource

@export_multiline var source := ""
@export var presets: Array[CartridgeShellPreset] = []


func find(id: StringName) -> CartridgeShellPreset:
	for p in presets:
		if p != null and p.id == id:
			return p
	return null


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in presets:
		if p != null:
			out.append(String(p.id))
	return out


func with_availability(availability: CartridgeShellPreset.Availability) -> Array[CartridgeShellPreset]:
	var out: Array[CartridgeShellPreset] = []
	for p in presets:
		if p != null and p.availability == availability:
			out.append(p)
	return out
