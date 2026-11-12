## NaomiDimm — the NAOMI's DIMM board (840-0001F): the GD-ROM system's board, in the cartridge's place.
##
## It goes in a NAOMI's cartridge seat as a cartridge does (the "cartridge" group, systemid "naomi"), and is the
## NAOMI's media: its game (get_rom_path) is the one NaomiGdRom resolves from the key chip in its socket and the
## disc in the drive its GD-ROM cable runs to, or nothing. When that changes while it is seated it seats itself
## again, so the cabinet loads the new game, as a NAOMI reads the disc again at power-on.
##
## Frame: a NAOMI cartridge's (its long side X, its label side +Z up), the origin where a cartridge's middle is
## when seated (the models repo's cart frame, 10 mm up). A mod's model (ArcadeBayShells kind "naomi_dimm_board")
## replaces the stand-in drawn here and moves `KeyAnchor` and `DataAnchor`.
class_name NaomiDimm
extends XRToolsPickable

const KIND := "naomi_dimm_board"
const POLL := 0.25

@export var type_id: String = KIND
## The system it serves, as a cartridge says (ArcadeBayUnit.accepts_board reads it).
@export var systemid: String = "naomi"

var _key_zone: XRToolsSnapZone = null
var _wait := 0.0
var _rom := ""
var _missing: Array = []


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group("cartridge")
	_build_stand_in()
	ArcadeBayShells.dress(self, KIND, Vector3(0.2546, 0.1258, 0.0415))
	_build_key_zone()
	_build_data_port()
	_rom = str(NaomiGdRom.resolve(self)["rom"])


func get_rom_path() -> String:
	return _rom


## What its game is waiting for, in words ([] when it loads).
func missing() -> Array:
	return _missing


func seated_key() -> Node:
	var k := _key_zone.picked_up_object if _key_zone != null else null
	return k if is_instance_valid(k) else null


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = POLL
	var r := NaomiGdRom.resolve(self)
	_missing = r["missing"]
	if str(r["rom"]) == _rom:
		return
	_rom = str(r["rom"])
	print("[NAOMI] DIMM board: %s" % ("the game is " + _rom.get_file() if not _rom.is_empty() else "no game: missing " + ", ".join(PackedStringArray(_missing))))
	# Seated: seated again, so the cabinet takes the new game.
	var zone := get_picked_up_by() as XRToolsSnapZone
	if zone != null:
		zone.drop_object()
		zone.pick_up_object.call_deferred(self)


func _build_stand_in() -> void:
	var gray := Color(0.20, 0.27, 0.41)
	NaomiGdRom.box(self, "DimmFoot", Vector3(0.2546, 0.1258, 0.005), Vector3(0, 0, -0.0075), gray)
	NaomiGdRom.box(self, "DimmCase", Vector3(0.2456, 0.1175, 0.020), Vector3(0, 0, 0.005), gray)
	NaomiGdRom.box(self, "DimmHump", Vector3(0.185, 0.050, 0.012), Vector3(0.030, 0.033, 0.021), gray)
	NaomiGdRom.box(self, "DimmPlate", Vector3(0.182, 0.064, 0.001), Vector3(0.029, -0.026, 0.0155), Color(0.8, 0.8, 0.82), 0.9)
	NaomiGdRom.box(self, "DimmSocket", Vector3(0.038, 0.004, 0.009), Vector3(0.069, -0.0605, 0.0075), Color(0.75, 0.75, 0.78), 0.8)
	NaomiGdRom.marker(self, "KeyAnchor", Vector3(-0.028, -0.019, 0.0134))
	NaomiGdRom.marker(self, "DataAnchor", Vector3(0.069, -0.0612, 0.0075))


## The key chip's socket under the window: a key goes straight down into it, legs first.
func _build_key_zone() -> void:
	var at := find_child("KeyAnchor", true, false) as Node3D
	_key_zone = (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate() as XRToolsSnapZone
	_key_zone.name = "KeySocket"
	_key_zone.grab_distance = 0.05
	_key_zone.snap_require = NaomiGdRom.KEY_GROUP
	at.add_child(_key_zone)
	# The key's +Y (up) along this board's +Z, its length across the case (a quarter turn about +Z).
	_key_zone.basis = Basis(Vector3(0, 0, 1), PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)


## The 50-pin socket for the GD-ROM cable, on the front lip; the plug goes in along +Y (from the front, -Y).
func _build_data_port() -> void:
	var at := find_child("DataAnchor", true, false) as Node3D
	if at.has_node(NaomiGdRom.DIMM_DATA):
		return
	var port := NaomiHookup.make_port(NaomiGdRom.DIMM_DATA, "res://Scripts/Objects/cables/port.gd", NaomiGdRom.GD_PLUG)
	at.add_child(port)
	port.basis = Basis(Vector3.RIGHT, PI * 0.5)


func on_av_topology_changed(_links: Array = []) -> void:
	pass
