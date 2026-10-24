## ArcadeModule — one part of an arcade cabinet, found by TYPE.
##
## The cabinet model never asks for a node by name: it collects every ArcadeModule
## under it and each says what it is (`kind`) and which player it serves. That is
## what lets a four-player or two-screen cabinet be only another scene, and a mod's
## cabinet honour the contract without copying ours. The contract is versioned
## (ArcadeProfiles.CONTRACT_VERSION) and additive only.
##
## A module finds ITS OWN parts by name inside its own subtree (the player's
## `Btn1`..`Btn6`, the coin door's `CoinSpawn`), never by a path from the cabinet
## root, so a module can be moved or duplicated as a unit.
class_name ArcadeModule
extends Node3D

## What this module is (ArcadeProfiles.KIND_*). Subclasses set it in _init.
var kind: StringName = &""

## The player (0-based) this module serves, or -1 for none (a screen, a bay).
@export var player: int = -1

## The cabinet model this module belongs to, set by attach().
var cabinet: RetroSystemModel = null


## Called once by the cabinet model after its scene is built and every module is in
## the tree. Find the parts here, not in _ready, so a module reads the finished
## scene.
func attach(p_cabinet: RetroSystemModel) -> void:
	cabinet = p_cabinet


## The RetroSystem this cabinet is the hardware of, or null before it is parented.
func host() -> Node:
	return cabinet.get_parent() if cabinet != null else null


## Per-frame work, called by the cabinet model's _process. Most modules need none.
func tick(_delta: float) -> void:
	pass


## Take a pointable box out of the pointer's reach (or put it back) without freeing it: the
## layer it had is remembered the first time, so a part the game does not use cannot be aimed at.
static func set_pointable(box: CollisionObject3D, on: bool) -> void:
	if box == null:
		return
	if not box.has_meta(&"arcade_layer"):
		box.set_meta(&"arcade_layer", box.collision_layer)
	box.collision_layer = int(box.get_meta(&"arcade_layer")) if on else 0
