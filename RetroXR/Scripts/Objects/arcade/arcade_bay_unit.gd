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
class_name ArcadeBayUnit
extends XRToolsPickable

## The group a cabinet's mount takes.
const GROUP := "arcade_bay"

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

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
