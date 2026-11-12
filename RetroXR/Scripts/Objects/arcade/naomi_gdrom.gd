## NaomiGdRom — the NAOMI's GD-ROM system: a DIMM board in place of the cartridge, the game's key chip in the
## DIMM board, a GD-ROM drive cabled to it, and the game's disc in the drive (docs/dev/naomi-jvs.md, phase 5).
##
## On the hardware the DIMM board reads the disc at power-on into its memory, checked against the key chip,
## and the NAOMI runs the game from there; the wrong key stops it (ERROR 33). Here the DIMM board is the
## NAOMI's media (NaomiDimm): what it hands the cabinet is the disc's game (its romset's zip, whose folder holds
## the GD-ROM image, as flycast reads it), and only when every link is there.
class_name NaomiGdRom
extends RefCounted

## The plug family of the GD-ROM cable's two ends (a 50-pin half-pitch D).
const GD_PLUG := "gd_50pin"
const KEY_GROUP := "naomi_key"
const DIMM_DATA := "DimmData"
const DRIVE_DATA := "DriveData"
## The drive's power socket, and the cabinet supply's lead for it (ArcadeCabinetFromModel, beside the board's).
const DRIVE_POWER := "DrivePowerIn"
const CAB_DRIVE_POWER := "DrivePowerLeadIn"
const NAOMI_SYSTEMS := ["naomi", "naomi2"]


## True when `rom_path` is a GD-ROM game (its romset has a disc image beside it).
static func is_gd_game(systemid: String, rom_path: String) -> bool:
	return NAOMI_SYSTEMS.has(SystemIds.canonical(systemid)) and not rom_path.is_empty() and ArcadeDiscs.needs_disc(rom_path)


## {rom: the game the chain loads ("" when it does not), missing: [what is not there, in words]}.
static func resolve(dimm: Node) -> Dictionary:
	var missing: Array[String] = []
	var key: Node = dimm.call("seated_key") if dimm != null and dimm.has_method("seated_key") else null
	var port := dimm.find_child(DIMM_DATA, true, false) as Port if dimm != null else null
	var other := NaomiHookup.peer(port)
	var drive: Node = null
	var n: Node = other
	while n != null:
		if n.has_method("seated_disc"):
			drive = n
			break
		n = n.get_parent()
	var disc: Node = drive.call("seated_disc") if drive != null else null
	if key == null:
		missing.append("the game's key chip")
	if drive == null:
		missing.append("the GD-ROM cable to the drive")
	elif disc == null:
		missing.append("the game's disc in the drive")
	elif drive.has_method("lid_shut") and not bool(drive.call("lid_shut")):
		missing.append("the drive's lid shut")
	# In a cabinet wired for the NAOMI, the drive runs from its supply: the drive's power lead from the cabinet's.
	var cabinet := _cabinet_of(dimm)
	if drive != null and cabinet != null and cabinet.find_child(CAB_DRIVE_POWER, true, false) != null:
		if not NaomiHookup.joined(drive.find_child(DRIVE_POWER, true, false) as Port, cabinet.find_child(CAB_DRIVE_POWER, true, false) as Port):
			missing.append("the drive's power lead")
	var rom := ""
	if disc != null:
		rom = str(disc.get("rom_path"))
		if key != null and str(key.get("rom_path")).get_file() != rom.get_file():
			missing.append("the right key chip (ERROR 33: this key is %s's)" % str(key.get("rom_path")).get_file().get_basename())
	if not missing.is_empty():
		rom = ""
	return {"rom": rom, "missing": missing, "systemid": str(disc.get("systemid")) if disc != null and rom != "" else ""}


## The cabinet the DIMM board's NAOMI is in: the seat it sits on, that seat's bay, the bay's cabinet.
static func _cabinet_of(dimm: Node) -> Node:
	var zone: Node = dimm.call("get_picked_up_by") if dimm != null and dimm.has_method("get_picked_up_by") else null
	var n: Node = zone
	while n != null and not (n is ArcadeBayUnit):
		n = n.get_parent()
	return (n as ArcadeBayUnit).get_host() if n != null else null


static func box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.5
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = at
	return mi


static func marker(parent: Node3D, marker_name: String, at: Vector3) -> Marker3D:
	var m := parent.get_node_or_null(marker_name) as Marker3D
	if m == null:
		m = Marker3D.new()
		m.name = marker_name
		parent.add_child(m)
		m.position = at
	return m
