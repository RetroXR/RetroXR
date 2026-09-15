## MemoryCard — pickable memory card for the consoles that take one.
## Must be in the "memory_card" group to snap into a RetroSystem's card slots
## (shown on consoles whose descriptor declares card_slots).
##
## A card IS one image, at save/memcards/<family>/<card_id>.<ext> — the same file
## every game played with this card seated writes into, which is what lets a game
## read the saves other games left behind. No card in the slot means nothing
## persists at all.
class_name MemoryCard
extends XRToolsPickable

const OPTIONS_PANEL_SCENE := preload("res://Scenes/UI/memory_card_panel.tscn")

var _options_panel: MemoryCardPanel = null
# The authored pointer box, restored whenever the card leaves a slot.
var _loose_pointer_box := Vector3.ZERO


## Which console family's card this is: the folder its image lives in and the
## byte format that image is in. A console only accepts a card of the family it
## takes, so a GameCube card will not go into a PlayStation.
##
## Defaults to the PlayStation, which is what every card authored or saved before
## there was a second family is — so nothing needs migrating.
@export var family: String = "playstation"

## Persistent identity, and literally the file name this card's saves live in
## (`<card_id>.<ext>`). Derived from card_label, so renaming a card moves its
## image — see MemoryCardPanel, which is the only thing that should change it.
@export var card_id: String = ""

## Display label shown on the card face. Also the card's filename on disk — see
## card_id — so the folder reads as a shelf of named cards.
@export var card_label: String = "MEMORY CARD":
	set(v):
		card_label = v
		_update_label()


func _ready() -> void:
	# Cards are otherwise identical grey bricks, yet each holds a different set
	# of saves. Number them in the order they appear so two can be told apart on
	# sight. A restored card arrives with its name already set and keeps it.
	if card_label == "MEMORY CARD":
		# The group also holds GameCube Microphone plugs, which are not numbered.
		var cards := get_tree().get_nodes_in_group("memory_card").filter(
			func(n: Node) -> bool: return n is MemoryCard)
		card_label = "MEMORY CARD %d" % cards.size()
	# Name before id: the id is the name, made unique against what is on disk so
	# two cards can never end up sharing one image.
	if card_id.is_empty():
		card_id = SramPaths.unique_card_id(card_label)
		card_label = card_id
		minted = true
	_update_label()
	_loose_pointer_box = _pointer_box_size()
	picked_up.connect(_on_picked_up)
	dropped.connect(_on_dropped)


## True only for a card this session invented — the id was not handed in.
##
## Which is the difference between a brand-new card, whose image is written the
## first time it is used, and one restored from a saved room or spawned from the
## shelf, whose image is supposed to exist already. Only the first may create an
## image: making one for the second would answer a card whose saves have gone
## missing with a silent blank, which reads exactly like the saves were wiped.
var minted := false


func _update_label() -> void:
	var lbl := get_node_or_null("CardLabel") as Label3D
	if lbl:
		lbl.text = card_label


## Open/close the card's save list. Reached by pointing at the card and pressing
## the options button, like every other object that has a panel.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		_options_panel = OPTIONS_PANEL_SCENE.instantiate()
		add_child(_options_panel)
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


## Whoever has it decides how big a target it should be.
##
## Loose, a card wants generous padding — it is a 42 x 8 x 63.5 mm card and the
## authored box is 62 x 28 x 83.5. Seated in a console it does not: that box stands
## 13 mm above a PlayStation's lid across 90 x 110 mm of it, so pointing at a good
## part of the machine handed you the card instead of the machine. Same treatment
## the cartridge gets, for the same reason.
func _on_picked_up(_p: Variant) -> void:
	if _snap_zone_holder() != null:
		_set_pointer_box(_card_box_size() + Vector3.ONE * 0.004)


func _on_dropped(_p: Variant) -> void:
	if _loose_pointer_box != Vector3.ZERO:
		_set_pointer_box(_loose_pointer_box)


func _snap_zone_holder() -> XRToolsSnapZone:
	if not is_picked_up():
		return null
	return get_picked_up_by() as XRToolsSnapZone


func _card_box_size() -> Vector3:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		return (col.shape as BoxShape3D).size
	return Vector3(0.042, 0.008, 0.0635)


func _pointer_box_size() -> Vector3:
	var col := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		return (col.shape as BoxShape3D).size
	return Vector3.ZERO


## A FRESH shape every time. The scene declares one BoxShape3D sub-resource with
## no resource_local_to_scene, so writing to it in place would resize every card
## in the room.
func _set_pointer_box(size: Vector3) -> void:
	var col := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
