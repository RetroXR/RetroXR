## NaomiGdDrive — the NAOMI's GD-ROM drive (610-0617): the disc goes on its spindle under the lid, and a GD-ROM
## cable joins its 50-pin socket to the DIMM board's (NaomiGdRom).
##
## The lid is not hinged: on the real drive it turns a little clockwise (seen from above) and lifts straight off the
## drum, one truss screw through its lug holding it in a cabinet. So it is a CoverSlots cover: taken off, put down,
## put back, saved like a battery cover. Off, the disc seat takes a NAOMI disc; on, the disc stays and the drive reads
## it. Frame: +Y up, origin on the floor at the body's middle (the models repo's gd-rom-drive in its GLB's frame). A
## mod's model (ArcadeBayShells kind "naomi_gd_drive") replaces the stand-in; the cover wears its `LidPivot`'s lid
## mesh, and its DiscAnchor and DataAnchor move the seat and the socket.
class_name NaomiGdDrive
extends XRToolsPickable

const KIND := "naomi_gd_drive"
## The group a cabinet's drive mount (ArcadeCabinetFromModel, at a model's GdDriveAnchor) takes.
const GROUP := "naomi_gd_drive"
## The lid's cover slot (CoverSlots), and the way its outer face looks.
const LID_SOCKET := "naomi_gd_lid"
const LID_OUT := Vector3.UP
## The stand-in's lid: a slab on the drum.
const LID_SIZE := Vector3(0.140, 0.006, 0.140)
const SHELL_BLUE := Color(0.24, 0.27, 0.32)
## Where the drive's own shapes stop: under the lid, which is a thing of its own with its own shape (a pointer aimed
## at the lid met the drive's box first and picked the whole drive up).
const UNDER_LID := 0.050

@export var type_id: String = KIND

var _disc_zone: XRToolsSnapZone = null
var _lid_zone: XRToolsSnapZone = null
## The model's lid mesh (LOD0's), which every cover seated here wears; null on the stand-in.
var _lid_part: MeshInstance3D = null
## The last cover seen in the slot, for set_lid_open(false).
var _lid: Node3D = null
## A seated disc held in place while the lid is on.
var _held_disc: XRToolsPickable = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	_build_stand_in()
	var shell := ArcadeBayShells.dress(self, KIND, Vector3(0.1635, 0.0585, 0.1535))
	_build_lid(shell)
	_shapes_under_lid()
	_build_disc_zone()
	_build_data_port()


func seated_disc() -> Node:
	var d := _disc_zone.picked_up_object if _disc_zone != null else null
	return d if is_instance_valid(d) else null


## True while the lid is on the drum.
func lid_shut() -> bool:
	var covers := CoverSlots.of(self)
	return covers == null or covers.is_on(LID_SOCKET)


## Take the lid off (put down beside the drive) or put it back on: for tests and scripted scenes; a hand does it
## by taking the cover.
func set_lid_open(open: bool) -> void:
	if _lid_zone == null:
		return
	if open and _lid_zone.has_snapped_object():
		_lid = _lid_zone.picked_up_object
		_lid_zone.drop_object()
		_lid.global_position = global_transform * Vector3(0.0, 0.07, 0.18)
	elif not open and is_instance_valid(_lid) and not _lid_zone.has_snapped_object():
		_lid_zone.pick_up_object(_lid)


func _build_stand_in() -> void:
	var blue := Color(0.24, 0.27, 0.32)
	NaomiGdRom.box(self, "DriveBody", Vector3(0.135, 0.051, 0.135), Vector3(0, 0.0255, 0), blue)
	NaomiGdRom.box(self, "DriveDrum", Vector3(0.140, 0.016, 0.140), Vector3(0.024, 0.043, 0.016), blue)
	NaomiGdRom.box(self, "DriveSocket", Vector3(0.002, 0.007, 0.034), Vector3(-0.0685, 0.0073, -0.020), Color(0.75, 0.75, 0.78), 0.8)
	NaomiGdRom.marker(self, "DiscAnchor", Vector3(0.024, 0.026, 0.016))
	NaomiGdRom.marker(self, "DataAnchor", Vector3(-0.0695, 0.0073, -0.020))
	NaomiGdRom.marker(self, "PowerAnchor", Vector3(-0.0675, 0.009, 0.015))


## The lid: a cover slot on the drum. With the mod's model, round its LOD0 lid mesh (the far levels' lids hidden:
## the seated cover wears LOD0's at every distance); on the stand-in, a slab on the drum's top.
func _build_lid(shell: Node3D) -> void:
	var pivot := shell.find_child("LidPivot", true, false) as Node3D if shell != null else null
	if pivot != null:
		_lid_part = _first_mesh(pivot)
	if _lid_part != null:
		for level in get_children():
			if level is Node3D and level != shell and str(level.name).begins_with("Shell"):
				var far := level.find_child("LidPivot", true, false) as Node3D
				if far != null:
					far.visible = false
		_lid_zone = CoverSlots.shell_cover(_lid_part, LID_SOCKET, LID_OUT)
	else:
		var seat := Transform3D(Basis.IDENTITY, Vector3(0.024, 0.051 + LID_SIZE.y * 0.5, 0.016))
		_lid_zone = CoverSlots.on(self).build(LID_SOCKET, self, seat, LID_SIZE)
	if _lid_zone == null:
		push_warning("[NaomiGdDrive] %s: no slot for the lid" % name)
		return
	_lid_zone.has_picked_up.connect(_on_lid_seated)
	_lid_zone.has_dropped.connect(_refresh_disc.call_deferred)
	if _lid_zone.picked_up_object != null:
		_on_lid_seated(_lid_zone.picked_up_object)


func _shapes_under_lid() -> void:
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := get_node_or_null(path) as CollisionShape3D
		if col == null or not col.shape is BoxShape3D:
			continue
		var box := (col.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size.y = UNDER_LID
		col.shape = box
		col.global_position = global_transform * Vector3(col.position.x if path == "CollisionShape3D" else 0.0, UNDER_LID * 0.5, 0.0)


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


## The lid went on: one nothing has dressed yet (a fresh one, one from a save) wears the model's lid, or the
## stand-in's color.
func _on_lid_seated(what: Node3D) -> void:
	_lid = what
	_refresh_disc.call_deferred()
	var cover := what as PortCover
	if cover == null or cover.has_node("Shell"):
		return
	if _lid_part != null:
		var copy := _lid_part.duplicate() as MeshInstance3D
		_lid_part.get_parent().add_child(copy)
		copy.transform = _lid_part.transform
		# The levels' distance ranges are the shell's; the cover is drawn at every distance.
		copy.visibility_range_begin = 0.0
		copy.visibility_range_end = 0.0
		CoverSlots.wear(cover, copy, LID_OUT)
	else:
		var mesh := cover.get_node_or_null("Mesh") as MeshInstance3D
		if mesh != null and mesh.material_override == null:
			var m := StandardMaterial3D.new()
			m.albedo_color = SHELL_BLUE
			m.roughness = 0.5
			mesh.material_override = m


## While the lid is on, the disc on the spindle stays there: neither the seat nor the disc can be taken from.
func _refresh_disc() -> void:
	if _disc_zone == null or not is_inside_tree():
		return
	var shut := lid_shut()
	_disc_zone.enabled = not shut
	var disc := _disc_zone.picked_up_object as XRToolsPickable
	if is_instance_valid(_held_disc) and _held_disc != disc:
		_held_disc.enabled = true
		_held_disc = null
	if is_instance_valid(disc):
		disc.enabled = not shut
		_held_disc = disc if shut else null


func _exit_tree() -> void:
	if is_instance_valid(_held_disc):
		_held_disc.enabled = true
	_held_disc = null
	super()


## The spindle: a NAOMI disc lies flat on it, label up, while the lid is off.
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
	_disc_zone.has_picked_up.connect(func(_d: Node3D) -> void: _refresh_disc.call_deferred())
	_disc_zone.has_dropped.connect(_refresh_disc.call_deferred)
	_refresh_disc.call_deferred()


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
