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
	# The pointer target is the card, loose or seated, and nothing more: a box of
	# what it draws, a mod's shell once it wears one. Loose it used to be padded
	# 10 mm on every face (60 x 30 x 78 mm round a 38.2 x 7.4 x 56 mm card) so a
	# small flat thing could be found on a shelf, and what that bought was a laser
	# that stopped in the air beside the card and took the one next to it. Seated it
	# was swapped for the card's own box plus 2 mm, because the padded one stood
	# 13 mm above a PlayStation's lid across most of it; the card's own box needs
	# no swap.
	PointerFit.watch(self)


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
