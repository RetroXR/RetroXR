## RealRoomSurface — one thing in the player's real room, as something to rest on.
##
## OpenXRFbSceneManager instances this scene under an anchor for everything the
## player scanned in Space Setup and calls setup_scene() with it: the room's mesh
## (GLOBAL_MESH, a Quest 3's scan of every surface), a piece of furniture drawn as
## a box (a table, a couch), or a flat face of the room (the floor, a wall). Each
## becomes a static body on layer 1, the layer every room's shelves and tables are
## on, so whatever a player drops on it lands there as on any table in the game
## (HeldPhysics needs nothing new). RealRoom decides which kinds are solid: the
## furniture boxes only when there is no mesh, which already has the furniture's
## real shape.
class_name RealRoomSurface
extends StaticBody3D

enum Kind { NONE, MESH, FURNITURE, FACE }

## Room geometry is world geometry: layer 1, World.
const WORLD_LAYER := 1
const FURNITURE_LABELS: PackedStringArray = [
	"TABLE", "COUCH", "BED", "STORAGE", "SCREEN", "LAMP", "PLANT", "OTHER",
]
const FACE_LABELS: PackedStringArray = ["FLOOR", "CEILING", "WALL_FACE", "INVISIBLE_WALL_FACE"]
## Faces a poster is pressed flat against (PosterConform's group).
const WALL_LABELS: PackedStringArray = ["WALL_FACE", "INVISIBLE_WALL_FACE"]
const POSTER_GROUP := &"poster_flat"
const GROUP := &"real_room_surface"

var kind := Kind.NONE
var labels := PackedStringArray()


## What `labels` (Meta's semantic labels, any case) make of a surface.
static func kind_for(of: PackedStringArray) -> Kind:
	var upper := PackedStringArray()
	for l in of:
		upper.append(l.to_upper())
	if "GLOBAL_MESH" in upper:
		return Kind.MESH
	for l in upper:
		if l in FURNITURE_LABELS:
			return Kind.FURNITURE
	for l in upper:
		if l in FACE_LABELS:
			return Kind.FACE
	return Kind.NONE


## Called by the scene manager with the spatial entity this anchor is.
func setup_scene(entity: Object) -> void:
	labels = PackedStringArray(entity.call("get_semantic_labels"))
	kind = kind_for(labels)
	collision_mask = 0
	set_solid(kind != Kind.NONE)
	if kind == Kind.NONE:
		return
	var shape: Variant = entity.call("create_collision_shape")
	if shape is Node:
		add_child(shape as Node)
	add_to_group(GROUP)
	for l in labels:
		if l.to_upper() in WALL_LABELS:
			add_to_group(POSTER_GROUP)
			break


func set_solid(on: bool) -> void:
	collision_layer = WORLD_LAYER if on else 0
