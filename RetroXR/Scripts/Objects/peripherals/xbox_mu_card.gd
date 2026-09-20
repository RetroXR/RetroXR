## XboxMuCard — the Xbox's 8 MB Memory Unit, as a thing you pick up.
##
## It goes in the top of a CONTROLLER, not the console, and a pad has two places
## for one: the console calls them 1A and 1B for the pad in port 1. They are the
## same two sockets a Dreamcast's devices use (VmuPort), because the pad is the
## same primitive box on both machines and the top edge is where both carry
## them; what is seated decides which console makes anything of it.
##
## An Xbox's games do not save here. They save to the hard disk in the console,
## and a Memory Unit is where a player COPIES a save to carry it to another
## console — or, here, where a save backed up to RomM goes on its way home,
## since nothing in RetroXR writes the hard disk image (XboxMemoryUnit says how).
##
## The image is save/memcards/xbox_mu/<card_id>.xmu, the unit's 8 MB byte for
## byte. xemu does not take a path for it: it reads a fixed file per pad and
## slot, so XboxStorage copies this one in when the unit is seated and back out
## as the game writes to it.
##
## Carries card_id, family, card_label and minted, which is everything
## MemoryCardPanel reads off a card — the panel that lists a memory card's saves
## lists this one's.
class_name XboxMuCard
extends XRToolsPickable

const FAMILY := XboxMuCardFormat.FAMILY
const OPTIONS_PANEL_SCENE := preload("res://Scenes/UI/memory_card_panel.tscn")
const DEFAULT_LABEL := "Memory Unit"
const HINT_HEIGHT := 0.08

## What a Dreamcast is told about a slot holding one of these: nothing it can
## use. VmuPort asks whatever is seated what flycast's slot option should say.
const FLYCAST_VALUE := "None"

var family: String = FAMILY

## The image's name on disk, and what persistence carries. Set BEFORE the node
## enters the tree when restoring one: _ready mints a fresh blank otherwise, and
## that reads exactly like a wiped card.
@export var card_id: String = ""

@export var card_label: String = DEFAULT_LABEL:
	set(value):
		card_label = value
		_update_label()

## True while this session invented the unit and no image exists yet — see
## MemoryCard.minted. Only a minted unit is ever handed a blank image.
var minted := false

var _options_panel: MemoryCardPanel = null
var _hint: HeldHint = null
var _slot := -1
var _pad: Node = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The slot requires this group, the same one every cable plug joins; the
	# group below is what narrows the socket to things that belong in it.
	add_to_group("controller_plug")
	add_to_group(VmuPort.XBOX_SLOT_GROUP)
	add_to_group("xbox_mu")
	# Numbering and the in-use check both sweep this group, and a unit held by a
	# controller is exactly as much "in use" as a card in a console.
	add_to_group("memory_card")

	if card_label == DEFAULT_LABEL:
		card_label = "%s %d" % [DEFAULT_LABEL, get_tree().get_nodes_in_group("xbox_mu").size()]
	if card_id.is_empty():
		card_id = SramPaths.unique_card_id(card_label)
		card_label = card_id
		minted = true
	_update_label()
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)


func slot_option_value() -> String:
	return FLYCAST_VALUE


func accessory_label() -> String:
	return "Memory Unit"


## Told by VmuPort which slot took this unit, and on which pad.
func seated_in(pad: Node, slot: int) -> void:
	_pad = pad
	_slot = slot


func unseated() -> void:
	_pad = null
	_slot = -1


## Which slot this is in — 0 is the console's "A", 1 its "B" — or -1 loose.
func seated_slot() -> int:
	return _slot


func host_system() -> Node:
	if is_instance_valid(_pad) and _pad.has_method("get_connected_system"):
		return _pad.call("get_connected_system")
	return null


func image_path() -> String:
	return SramPaths.card_save_path(FAMILY, card_id)


func display_name() -> String:
	return card_label


func _update_label() -> void:
	var lbl := get_node_or_null("CardLabel") as Label3D
	if lbl:
		lbl.text = card_label


## Open/close the save list, the same panel a memory card uses.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		_options_panel = OPTIONS_PANEL_SCENE.instantiate()
		add_child(_options_panel)
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)
