## TvDecks — the decks built into a combination set: a TV/VCR, a TV/DVD, or both.
##
## A child of the RetroTV it serves, created unconditionally in _init, in the same
## shape as TvPanel, TvFit and the rest. Builds nothing unless the fitted cabinet
## carries a VcrSeat or DvdSeat marker (RetroTVShell), so every set without one is
## exactly what it was.
##
## A built-in deck is the ordinary VCRPlayer or DVDPlayer, instanced as a child of
## the set at the marker and then made part of it (MediaTransport.build_into). That
## is deliberate: the tape slot, the transport, the scan, the clock, the options
## panel, the remote and netplay's transport sync are the deck's, already work, and
## would only drift if a second copy were written for a deck inside a cabinet.
##
## Which INPUT it is on. A deck takes the composite input after the cabinet's phono
## inputs — VCR first, then DVD — so a cabinet with one phono row and both decks is
## Composite 1, VCR, DVD. Two things follow from re-using a composite slot rather
## than adding a Source value:
## - nothing about the wire or the save file changes: RetroTV.Source is on disk and
##   on the network (EV_TV_SOURCE), and a built-in deck is an int it already carries;
## - a cabinet can have at most COMPOSITE_INPUTS of phono rows and decks together.
##   A deck that does not fit is left out, and says so.
##
## The input's own sockets stay switched off (TvPanel.disable_absent_inputs already
## does that for every input past the phono rows), so no lead can land on the input
## a deck is on and fight it for the glass.
class_name TvDecks
extends Node

## The kinds of deck a cabinet can carry, in the order they take their inputs.
## `seat` and `controls` are the RetroTVShell methods naming its markers; `label`
## is what SOURCE shows, which a real combination set prints as the deck's name,
## not a number.
const KINDS := [
	{"kind": "vcr", "seat": "vcr_seat", "controls": "vcr_controls_seat",
		"label": "VCR", "node": "BuiltInVcr",
		"scene": "res://Scenes/Objects/appliances/vcr_player.tscn"},
	{"kind": "dvd", "seat": "dvd_seat", "controls": "dvd_controls_seat",
		"label": "DVD", "node": "BuiltInDvd",
		"scene": "res://Scenes/Objects/appliances/dvd_player.tscn"},
]

## The set these decks are built into.
var _tv: RetroTV = null

## input -> {"deck": MediaTransport, "kind": String, "label": String}
var _decks: Dictionary = {}


func setup(tv: RetroTV) -> void:
	_tv = tv


## Build the decks the fitted cabinet names. Called once, after the shell is worn
## and the phono inputs it does not carry have been turned off.
##
## The node names are fixed (BuiltInVcr, BuiltInDvd) because they are an address:
## netplay names a built-in deck as the set's id plus the path to it inside the set,
## and every peer builds the same cabinet, so every peer finds the same node.
func build() -> void:
	var shell := _tv.shell()
	if shell == null:
		return
	var input := _tv.panel().panel_inputs()
	for kind: Dictionary in KINDS:
		var at: Variant = shell.call(kind["seat"])
		if not at is Transform3D:
			continue
		if input >= RetroTV.COMPOSITE_INPUTS:
			push_warning("[RetroTV] cabinet '%s' has no input left for its built-in %s"
				% [_tv.tv_model, kind["label"]]
				+ " (%d phono inputs and decks together at most)" % RetroTV.COMPOSITE_INPUTS)
			continue
		var deck := (load(kind["scene"]) as PackedScene).instantiate() as MediaTransport
		deck.name = kind["node"]
		deck.transform = at
		# Filed on the panel BEFORE it enters the tree: build_into tells the set it
		# has found a source, and the set looks the deck up there to learn its input.
		_decks[input] = {"deck": deck, "kind": kind["kind"], "label": kind["label"]}
		_tv.panel().attach_builtin(deck, input)
		_tv.add_child(deck)
		deck.build_into(_tv, shell.deck_housing, shell.call(kind["controls"]))
		print("[RetroTV] %s: built-in %s on input %d" % [_tv.name, kind["label"], input + 1])
		input += 1


## The deck built into one input, or null.
func deck_on(input: int) -> MediaTransport:
	var entry: Dictionary = _decks.get(input, {})
	var deck: MediaTransport = entry.get("deck") as MediaTransport
	return deck if is_instance_valid(deck) else null


## The deck of one kind ("vcr" or "dvd"), or null. What the save file asks for.
func deck_of_kind(kind: String) -> MediaTransport:
	for input: int in _decks:
		if _decks[input]["kind"] == kind:
			return deck_on(input)
	return null


## Every built-in deck, in input order.
func decks() -> Array[MediaTransport]:
	var out: Array[MediaTransport] = []
	var inputs := _decks.keys()
	inputs.sort()
	for input: int in inputs:
		var deck := deck_on(input)
		if deck != null:
			out.append(deck)
	return out


## What SOURCE calls a deck's input, or "" for an input with no deck on it.
func label_for(input: int) -> String:
	return str((_decks.get(input, {}) as Dictionary).get("label", ""))


## What is in each deck, for the save file: {kind: {"media": ref, "yaw": float}}.
## `ref` maps a media node to whatever the caller saves it as, because only the
## caller knows the id table.
func media_state(ref: Callable) -> Dictionary:
	var out := {}
	for input: int in _decks:
		var deck := deck_on(input)
		if deck == null:
			continue
		var media: Node3D = null
		var yaw := 0.0
		if deck is VCRPlayer:
			media = (deck as VCRPlayer).get_snapped_tape()
		elif deck is DVDPlayer:
			media = (deck as DVDPlayer).get_snapped_disc()
			yaw = (deck as DVDPlayer).disc_seat_yaw()
		if media == null:
			continue
		out[_decks[input]["kind"]] = {"media": ref.call(media), "yaw": yaw}
	return out


## Seat media back into a deck. Called from the restore's second pass, with the
## tape or disc already rebuilt.
func restore_deck_media(kind: String, media: Node3D, yaw: float) -> void:
	var deck := deck_of_kind(kind)
	if deck is VCRPlayer and media is VCRTape:
		(deck as VCRPlayer).restore_media(media)
	elif deck is DVDPlayer and media is DVDDisc:
		(deck as DVDPlayer).restore_media(media, yaw)
