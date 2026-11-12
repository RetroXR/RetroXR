## NaomiKey — a NAOMI GD-ROM game's key chip (the per-game PIC in its shell, 317-xxxx). It comes with its disc
## (the spawn menu makes both) and goes in the DIMM board's socket; the DIMM board checks it is this game's.
##
## Frame: +Y up, the origin at the tips of its legs (the models repo's pic-key LegsAnchor), its length along X. A
## mod's model (ArcadeBayShells kind "naomi_key") replaces the stand-in.
class_name NaomiKey
extends XRToolsPickable

const KIND := "naomi_key"

@export var type_id: String = KIND
## The game it unlocks: its romset's zip (the disc's rom_path).
@export var rom_path: String = ""


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(NaomiGdRom.KEY_GROUP)
	NaomiGdRom.box(self, "KeyShell", Vector3(0.032, 0.020, 0.015), Vector3(0, 0.014, 0), Color(0.22, 0.23, 0.25))
	NaomiGdRom.box(self, "KeyLegs", Vector3(0.023, 0.004, 0.008), Vector3(0, 0.002, 0), Color(0.78, 0.78, 0.8), 0.8)
	ArcadeBayShells.dress(self, KIND, Vector3(0.033, 0.024, 0.015))
