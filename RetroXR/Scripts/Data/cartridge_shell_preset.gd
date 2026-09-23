## One plastic a cartridge shell can be moulded in, or a pairing of two for a
## shell whose halves differ.
class_name CartridgeShellPreset
extends Resource

enum Finish { PLASTIC, METAL_FLAKE }
## STANDARD is the grey every cartridge came in unless its publisher paid for
## another run; RELEASED was used by a commercial release; OFFERED_ONLY was on
## the manufacturer's list and never used commercially.
enum Availability { STANDARD, RELEASED, OFFERED_ONLY }

@export var id: StringName
@export var display_name := ""
@export var availability := Availability.RELEASED
@export var finish := Finish.PLASTIC
@export var color := Color(0.64, 0.65, 0.67)
@export_range(0.0, 1.0) var roughness := 0.43
## 1 is solid plastic. Lower is the dyed clear plastic of a clear cartridge,
## the board inside showing through, tinted: the value is how strongly the dye
## filters (CartridgeColor.CLEAR_DENSITY) and scatters (CLEAR_HAZE). PLASTIC
## finishes only; a metal flake shell is always solid.
@export_range(0.0, 1.0) var opacity := 1.0

@export_group("Metal flake")
@export var flake_color := Color(0.92, 0.92, 0.94)
@export_range(0.0, 1.0) var flake_density := 0.25
@export_range(0.02, 2.0, 0.01, "suffix:mm") var flake_size_mm := 0.35
@export_range(0.0, 1.0) var flake_intensity := 0.8
@export_range(0.0, 1.0) var flake_roughness := 0.22
@export_range(0.0, 0.9) var flake_tilt := 0.4

@export_group("Two-tone")
## Preset ids for each half. Set both and the preset's own colour is unused.
@export var front: StringName
@export var back: StringName


func is_two_tone() -> bool:
	return front != &"" and back != &""
