## NaomiGdDrive — the NAOMI's GD-ROM drive (610-0617): the disc goes on its spindle under the lid, and a GD-ROM
## cable joins its 50-pin socket to the DIMM board's (NaomiGdRom).
##
## The lid is a hinge taken by its edge: open, the disc seat takes a NAOMI disc; shut, the disc stays and the drive
## reads it. Frame: +Y up, origin on the floor at the body's middle (the models repo's gd-rom-drive in its GLB's
## frame). A mod's model (ArcadeBayShells kind "naomi_gd_drive") replaces the stand-in; its `LidPivot` (the lid)
## is carried by the hinge, and its DiscAnchor and DataAnchor move the seat and the socket.
class_name NaomiGdDrive
extends XRToolsPickable

const KIND := "naomi_gd_drive"
const LID_OPEN := 100.0

@export var type_id: String = KIND

var _disc_zone: XRToolsSnapZone = null
var _hinge_axis: Node3D = null
var _lid: Node3D = null
var _grab: VRHinge = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	_build_stand_in()
	var shell := ArcadeBayShells.dress(self, KIND, Vector3(0.1635, 0.0585, 0.1535))
	_build_lid(shell)
	_build_disc_zone()
	_build_data_port()


func seated_disc() -> Node:
	var d := _disc_zone.picked_up_object if _disc_zone != null else null
	return d if is_instance_valid(d) else null


func lid_shut() -> bool:
	return _lid == null or _lid.rotation.x < deg_to_rad(5.0)


func set_lid_open(open: bool) -> void:
	if _lid != null:
		_lid.rotation.x = deg_to_rad(LID_OPEN if open else 0.0)


func _build_stand_in() -> void:
	var blue := Color(0.24, 0.27, 0.32)
	NaomiGdRom.box(self, "DriveBody", Vector3(0.135, 0.051, 0.135), Vector3(0, 0.0255, 0), blue)
	NaomiGdRom.box(self, "DriveDrum", Vector3(0.140, 0.016, 0.140), Vector3(0.024, 0.043, 0.016), blue)
	NaomiGdRom.box(self, "DriveSocket", Vector3(0.002, 0.007, 0.034), Vector3(-0.0685, 0.0073, -0.020), Color(0.75, 0.75, 0.78), 0.8)
	NaomiGdRom.marker(self, "DiscAnchor", Vector3(0.024, 0.026, 0.016))
	NaomiGdRom.marker(self, "DataAnchor", Vector3(-0.0695, 0.0073, -0.020))
	NaomiGdRom.marker(self, "PowerAnchor", Vector3(-0.0675, 0.009, 0.015))
	NaomiGdRom.marker(self, "LidPivotAnchor", Vector3(0.024, 0.051, 0.016 - 0.070))


## The lid: a pivot at its back edge turned about +X by a hinge taken by the lid's front edge. The stand-in's lid,
## or the model's (its LidPivot, moved onto the pivot keeping where it is).
func _build_lid(shell: Node3D) -> void:
	var at := find_child("LidPivotAnchor", true, false) as Node3D
	_hinge_axis = Node3D.new()
	_hinge_axis.name = "LidHinge"
	add_child(_hinge_axis)
	_hinge_axis.position = at.position
	_lid = Node3D.new()
	_lid.name = "LidTurn"
	_hinge_axis.add_child(_lid)
	var model_lid := shell.find_child("LidPivot", true, false) as Node3D if shell != null else null
	if model_lid != null:
		# The model's lid, and each of its lower levels' (ShellLOD1, ...), keeping where they are.
		for level in get_children():
			if level is Node3D and str(level.name).begins_with("Shell"):
				var lid := level.find_child("LidPivot", true, false) as Node3D
				if lid != null:
					lid.reparent(_lid, true)
	else:
		NaomiGdRom.box(_lid, "LidMesh", Vector3(0.140, 0.006, 0.140), Vector3(0, 0.003, 0.070), Color(0.24, 0.27, 0.32))
	_grab = (load("res://Scripts/Objects/widgets/vr_hinge.gd") as GDScript).new() as VRHinge
	_grab.name = "LidGrab"
	_grab.collision_layer = 0
	_grab.collision_mask = 0
	_grab.target = _lid
	_grab.min_deg = 0.0
	_grab.max_deg = LID_OPEN
	_grab.set("engage_radius", 0.08)
	_lid.add_child(_grab)
	_grab.position = Vector3(0, 0.006, 0.135)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.10, 0.02, 0.03)
	col.shape = shape
	_grab.add_child(col)


## The spindle: a NAOMI disc lies flat on it, label up, while the lid is open.
func _build_disc_zone() -> void:
	var at := find_child("DiscAnchor", true, false) as Node3D
	_disc_zone = (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate() as XRToolsSnapZone
	_disc_zone.name = "DiscSeat"
	_disc_zone.grab_distance = 0.08
	_disc_zone.snap_require = "cartridge"
	_disc_zone.snap_filter = _accepts_disc
	at.add_child(_disc_zone)
	# A disc is flat in its own frame (thin along its Y, label up): the seat is not turned.
	_disc_zone.basis = Basis.IDENTITY


func _accepts_disc(obj: Node3D) -> bool:
	return obj is RetroDisc and NaomiGdRom.NAOMI_SYSTEMS.has(SystemIds.canonical(str(obj.get("systemid")))) and not lid_shut()


func _build_data_port() -> void:
	# The power header (its plug in from the -X face, as the data cable's).
	var pat := find_child("PowerAnchor", true, false) as Node3D
	if pat != null and not pat.has_node(NaomiGdRom.DRIVE_POWER):
		var pport := NaomiHookup.make_port(NaomiGdRom.DRIVE_POWER, "res://Scripts/Objects/cables/port.gd", NaomiHookup.NAOMI_POWER)
		pat.add_child(pport)
		pport.basis = Basis(Vector3.UP, -PI * 0.5)
	var at := find_child("DataAnchor", true, false) as Node3D
	if at.has_node(NaomiGdRom.DRIVE_DATA):
		return
	var port := NaomiHookup.make_port(NaomiGdRom.DRIVE_DATA, "res://Scripts/Objects/cables/port.gd", NaomiGdRom.GD_PLUG)
	at.add_child(port)
	port.basis = Basis(Vector3.UP, -PI * 0.5)


func on_av_topology_changed(_links: Array = []) -> void:
	pass
