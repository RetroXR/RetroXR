## ArcadeBayUnit — the box a board stands in, no longer part of the cabinet.
##
## A cabinet used to carry its bay: the slot, the harness socket and the board's seat were baked
## into its scene, so the cabinet and what it played were one thing. This is the bay as an object
## of its own. It holds the cartridge slot (`slot`, the same kind of snap zone a console has) and
## stands in the room like the 32X's spacer: clipped into the cabinet's `BayMount` it rides with the
## cabinet, rigid, and is taken out by hand; or it stands anywhere and a JAMMA cable
## (JammaCable) joins its harness socket to the cabinet's.
##
## It is NOT a machine. The cabinet is still the RetroSystem: it runs the core, takes the panels'
## and the guns' input and shows the picture. A bay only says WHICH system the cabinet is playing
## (`primary_system`, from its kind) and holds the board. Linking it to a cabinet hands the cabinet
## this bay's slot (RetroSystem.link_bay); unlinking takes it back and the board stays in the bay.
##
## One scene per kind (`bay_kind`, ArcadeProfiles.BAY_*): JAMMA, Neo Geo MVS, laserdisc, discrete.
## They differ in what is drawn round the seat, nothing else; Tools/gen/gen_arcade_bay.gd bakes them.
##
## The JAMMA bay is built as one block with a CD-ROM bay under it (a scene with a `DiscSeat`): a
## slot-loading drive, the same MediaSlot a console's slot is, for the disc a few arcade games need
## beside their board (ArcadeDiscs). The block is one object; the drive is not a part you can take off.
## The EJECT button pushes the disc half out of the slot for a hand to take.
class_name ArcadeBayUnit
extends XRToolsPickable

## The group a cabinet's mount takes.
const GROUP := "arcade_bay"

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## How far past the slot's mouth the disc's centre rides when it is in: a 120 mm disc lies wholly inside
## a 300 mm drive (60 mm radius plus 25 mm).
const DISC_INSERT_DEPTH := 0.085

## Emitted when the drive gains a disc or loses one (an eject counts as losing it).
signal disc_changed

## How a bay is joined to its cabinet.
const DOCK := "dock"
const CABLE := "cable"

## The scene each kind spawns from. Loaded when asked rather than preloaded, so this script
## compiles whether or not the bays have been baked yet.
const SCENES := {
	"jamma": "res://Scenes/Objects/peripherals/arcade_bay_jamma.tscn",
	"mvs": "res://Scenes/Objects/peripherals/arcade_bay_mvs.tscn",
	"laserdisc": "res://Scenes/Objects/peripherals/arcade_bay_laserdisc.tscn",
	"discrete": "res://Scenes/Objects/peripherals/arcade_bay_discrete.tscn",
}

## What the player is told it is, by kind.
const LABELS := {
	"jamma": "JAMMA Arcade Bay",
	"mvs": "Neo Geo MVS Arcade Bay",
	"laserdisc": "Laserdisc Arcade Bay",
	"discrete": "DICE Arcade Bay",
}

## Which ArcadeProfiles bay kind this is (it names what boards fit).
@export var bay_kind: String = ArcadeProfiles.BAY_JAMMA
## The ScenePersistence PLAIN_SCENES key this scene is saved and spawned under.
@export var type_id: String = ""

## The snap zone the board stands in. Built here, as a console's is built by its scene: 70 mm of
## reach and the `cartridge` group, which every board and cassette is in.
var slot: XRToolsSnapZone = null
## The snap zone at the CD-ROM bay's slot, null on a bay with no drive.
var disc_slot: XRToolsSnapZone = null

var _drive: MediaSlot = null
var _host: Node3D = null
var _how := ""
var _hint: HeldHint = null


## The spawn scene for a bay kind, or null for one this build has none of.
static func scene_for(kind: String) -> PackedScene:
	var path := str(SCENES.get(kind, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


## The kind whose spawn token (type_id) is `type`, "" if none.
static func kind_of_type(type: String) -> String:
	for kind: String in SCENES:
		if "arcade_bay_" + kind == type:
			return kind
	return ""


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	_build_slot()
	_build_drive()
	ArcadeShadowBudget.trim(self)
	_hint = HeldHint.attach(self, true, 0.20)
	tree_exiting.connect(_on_leaving)


func _build_slot() -> void:
	slot = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	slot.name = "CartridgeSlot"
	slot.grab_distance = 0.07
	slot.snap_require = "cartridge"
	# A free bay takes only what its own kind takes; the cabinet that links it swaps this for its own.
	slot.snap_filter = accepts_board
	add_child(slot)
	var seat := find_child("CartSeat", true, false) as Node3D
	if seat != null:
		slot.transform = global_transform.affine_inverse() * seat.global_transform


## The CD-ROM bay's slot, where a scene has a `DiscSeat`: a snap zone at its mouth, handed to a
## MediaSlot that rides the disc in and out and keeps it a frozen child of this bay in between.
func _build_drive() -> void:
	var seat := find_child("DiscSeat", true, false) as Node3D
	if seat == null:
		return
	disc_slot = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	disc_slot.name = "DiscSnapZone"
	disc_slot.grab_distance = 0.07
	disc_slot.snap_require = "cartridge"
	disc_slot.snap_filter = accepts_disc
	add_child(disc_slot)
	disc_slot.transform = global_transform.affine_inverse() * seat.global_transform
	# The zone's ghost is a board's box; a disc is a flat platter.
	var ghost := disc_slot.get_node_or_null("SnapHighlight/HighlightMesh") as MeshInstance3D
	if ghost != null:
		var ghost_mesh := CylinderMesh.new()
		ghost_mesh.top_radius = MediaDimensions.disc_diameter(ArcadeDiscs.SYSTEMID) / 2.0
		ghost_mesh.bottom_radius = ghost_mesh.top_radius
		ghost_mesh.height = 0.004
		ghost.mesh = ghost_mesh
	_drive = MediaSlot.new()
	_drive.host = self
	_drive.slot = disc_slot
	_drive.insert_depth = DISC_INSERT_DEPTH
	add_child(_drive)
	_drive.inserted.connect(_on_disc_inserted)
	_drive.removed.connect(_on_disc_removed)
	var eject := find_child("EjectButton", true, false) as VRButton
	if eject != null:
		eject.button_pressed.connect(eject_disc)


## Does this bay have a CD-ROM bay under it?
func has_drive() -> bool:
	return _drive != null


## The disc in the drive, read and ready: null with none, and null while it is pushed half out (an
## ejected disc is not being read).
func get_disc() -> Node3D:
	if _drive == null or not _drive.has_media() or _drive.is_parked():
		return null
	var d := _drive.get_media()
	return d if is_instance_valid(d) else null


## EJECT: the disc rides out to the mouth and waits there to be taken; pressed again before it is, it
## is drawn back in.
func eject_disc() -> void:
	if _drive != null:
		_drive.toggle_eject()


## A saved disc back in the drive, seated at once (the room's restore).
func restore_disc(disc: Node3D) -> void:
	if _drive != null and disc != null and not _drive.has_media():
		_drive.restore(disc)


## Does the drive take `obj`? Only a disc made for the arcade (a CHD).
func accepts_disc(obj: Node3D) -> bool:
	return ArcadeDiscs.is_disc_object(obj)


func _on_disc_inserted(_disc: Node3D) -> void:
	_light_drive(true)
	disc_changed.emit()
	_tell_host()


func _on_disc_removed() -> void:
	_light_drive(false)
	disc_changed.emit()
	_tell_host()


## The cabinet checks that a game with a disc has both halves, whichever arrived last.
func _tell_host() -> void:
	var host := get_host()
	if host != null and host.has_method("arcade_disc_changed"):
		host.call("arcade_disc_changed")


func _light_drive(on: bool) -> void:
	var led := find_child("DriveLed", true, false) as MeshInstance3D
	if led == null:
		return
	if not (led.mesh is BoxMesh):
		return
	# The baked scene's mesh and material are shared by every bay in the room: take our own copy once.
	if not led.has_meta(&"own_light"):
		var own := (led.mesh as BoxMesh).duplicate() as BoxMesh
		if own.material != null:
			own.material = own.material.duplicate()
		led.mesh = own
		led.set_meta(&"own_light", true)
	var mat := (led.mesh as BoxMesh).material as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = on
	mat.emission_energy_multiplier = 1.2 if on else 0.0


## The systems whose boards stand in this bay, by its kind.
func systems() -> Array:
	return (ArcadeProfiles.bay_kinds().get(bay_kind, {}).get("systems", []) as Array).duplicate()


## The system a cabinet plays while this bay is in it: the kind's first.
func primary_system() -> String:
	var all := systems()
	return str(all[0]) if not all.is_empty() else ""


## Does this bay take `obj` (a board or a cassette)? An unlabelled one does, as in a console.
func accepts_board(obj: Node3D) -> bool:
	if obj == null or not ("systemid" in obj):
		return false
	# A game's disc goes in the CD-ROM bay, never where its board stands.
	if ArcadeDiscs.is_disc_object(obj):
		return false
	var sid := str(obj.get("systemid"))
	return sid.is_empty() or ArcadeProfiles.bay_accepts(bay_kind, sid)


## The board standing in the slot, or null.
func get_board() -> Node3D:
	if slot == null:
		return null
	var b := slot.picked_up_object as Node3D
	return b if is_instance_valid(b) else null


## The cabinet this bay is joined to, or null.
func get_host() -> Node3D:
	return _host if is_instance_valid(_host) else null


## How it is joined: DOCK, CABLE, or "" when it is free.
func link_kind() -> String:
	return _how if get_host() != null else ""


func is_docked() -> bool:
	return link_kind() == DOCK


## Told by the cabinet that took it. The cabinet owns the rest (the slot swap, the system).
func attach_host(host: Node3D, how: String) -> void:
	_host = host
	_how = how


## Told by the cabinet that let it go: the slot goes back to taking this kind's boards.
func detach_host() -> void:
	_host = null
	_how = ""
	if slot != null:
		slot.snap_filter = accepts_board
		slot.enabled = true


## A JAMMA socket's owner answers the A/V graph's question by being a device that does nothing with it:
## this box carries neither picture nor sound.
func on_av_topology_changed(_links: Array) -> void:
	pass


## Leaving the room (a scene change, a delete): let the cabinet have its own slot back before this
## one is freed, or it would be left holding a freed zone.
func _on_leaving() -> void:
	var host := get_host()
	if host != null and host.has_method("unlink_bay"):
		host.call("unlink_bay", self)
