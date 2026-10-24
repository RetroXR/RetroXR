## One RCA socket on a device: a snap zone that wears an RcaJack and knows what
## signal it carries and which way that signal flows.
##
## Every port accepts every plug — group "composite_plug", no colour filter —
## because that is what the real connector does. Putting the yellow cord into
## both L sockets carries the left channel down a yellow wire and works; putting
## it into the L socket at one end and the R at the other swaps the channels.
## Nothing here enforces a "correct" cable; the routing falls out of which ports a
## cord's two ends happen to sit in. See CompositeCable.
class_name RcaPort
extends Port


## What this socket carries. The order matches RcaJack's colour code and is used
## as an index into per-channel arrays, so do not reorder it.
##
## Everything after AUDIO_R is APPENDED for that reason, and the int is written
## into save files and onto the netplay wire, so this list only ever grows at the
## end.
##
## AUDIO_STEREO is what a 3.5 mm TRS socket carries — both channels down one
## connector — which no phono socket can express, since a phono lead needs a cord
## per channel.
##
## AUDIO_C through AUDIO_SR are a television's surround speaker outputs.
## AUDIO_SPEAKER is a loudspeaker cabinet's own input: a phono jack is generic, so
## what a cabinet carries is decided by the socket at the far end of its lead.
##
## Turning a channel into a speaker number goes through CHANNEL_SPEAKER, never
## through arithmetic on the enum value.
enum Channel {
	VIDEO,
	AUDIO_L,
	AUDIO_R,
	AUDIO_STEREO,
	AUDIO_C,
	AUDIO_LFE,
	AUDIO_SL,
	AUDIO_SR,
	AUDIO_SPEAKER,
}

## Which way the signal flows through this socket. A deck's sockets are OUT, a
## television's are IN. A cord between two OUTs (or two INs) carries nothing,
## which is also true of the real thing.
enum Direction { OUT, IN }

@export var channel: Channel = Channel.VIDEO:
	set(value):
		channel = value
		_tint_jack()

@export var direction: Direction = Direction.IN

## Draw this port's own jack, or leave it to the model underneath.
##
## The NES moulds its own AV jacks into the shell (JackYellow / JackRed), so its
## ports sit ON those and turn this off — two jacks in the same place z-fight, and
## the moulded pair is the one that matches the console.
@export var show_jack: bool = true:
	set(value):
		show_jack = value
		var jack := get_node_or_null("RcaJack") as Node3D
		if jack != null:
			jack.visible = show_jack

## True for a modulator output rather than a baseband one: the coax on the back of
## an NES or a Famicom, which carries the PICTURE AND THE SOUND down a single
## cord. That is the whole difference between it and a composite video jack, and
## the only place it shows is AvSource.resolve — a composite VIDEO cord has
## nothing an amplifier can use, and this one does.
##
## It matters far more on some machines than others. An NES also wears a phono
## pair, so a player who never touches the RF socket loses nothing; an HVC-001
## has no audio socket at all, and without this a Famicom is silent however it is
## wired.
@export var rf_feed: bool = false

## Short label for the OSD and for debugging — "VIDEO", "L", "R".
const CHANNEL_NAMES := ["VIDEO", "L", "R", "STEREO", "CENTER", "SUB", "SL", "SR", "SPEAKER"]

## Which of a sink's speakers a channel lands on, indexed by Channel. The order
## matches the decoder's output — FL, FR, C, LFE, SL, SR — so a surround rig's
## channel IS its index into RetroTV.get_surround_positions().
##
## -1 for the three that name no single speaker: VIDEO carries nothing an
## amplifier can use, AUDIO_STEREO is both channels at once, and AUDIO_SPEAKER is
## a cabinet's generic input, whose channel is whatever the far socket says.
const CHANNEL_SPEAKER := [-1, 0, 1, -1, 2, 3, 4, 5, -1]

## The television outputs a loudspeaker can be cabled to, in decoder order.
const SPEAKER_OUT_CHANNELS := [
	Channel.AUDIO_L, Channel.AUDIO_R, Channel.AUDIO_C,
	Channel.AUDIO_LFE, Channel.AUDIO_SL, Channel.AUDIO_SR,
]

## Every A/V socket in the room, for the sweeps that want signal routes
## (AvGraph) rather than any socket at all, which is Port.ANY_GROUP.
const GROUP := "rca_port"


## A phono jack's own family. A subclass (TRS, VGA, coax, Multi Out) sets its
## own in _init and answers its own here; see Port._own_connector.
func _init() -> void:
	connector = Connectors.PHONO


func _own_connector() -> String:
	return Connectors.PHONO


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	_tint_jack()
	var jack := get_node_or_null("RcaJack") as Node3D
	if jack != null:
		jack.visible = show_jack


func _tint_jack() -> void:
	var jack := get_node_or_null("RcaJack") as RcaJack
	if jack == null:
		return
	match channel:
		Channel.VIDEO: jack.jack_color = RcaJack.COMPOSITE_YELLOW
		Channel.AUDIO_L: jack.jack_color = RcaJack.AUDIO_WHITE
		Channel.AUDIO_R: jack.jack_color = RcaJack.AUDIO_RED
		Channel.AUDIO_C: jack.jack_color = RcaJack.AUDIO_GREEN
		Channel.AUDIO_LFE: jack.jack_color = RcaJack.AUDIO_PURPLE
		Channel.AUDIO_SL: jack.jack_color = RcaJack.AUDIO_BLUE
		Channel.AUDIO_SR: jack.jack_color = RcaJack.AUDIO_GREY
		Channel.AUDIO_SPEAKER: jack.jack_color = RcaJack.AUDIO_BLACK


func channel_name() -> String:
	return CHANNEL_NAMES[channel]


## In the seating log a jack says what it carries -- "VIDEO", "L" -- not its plug.
func port_label() -> String:
	return channel_name()


## What this socket carries on a given CORD of the lead seated in it.
##
## A phono socket is one signal down one wire, so the cord is nothing to it and this
## is just `channel`. The exception is a MULTI-WAY connector — the Wii's AV Multi Out
## is one shell carrying picture and both audio channels — where a single socket is
## the source for three cords at once and each has to answer differently. See
## MultiAvPort.
##
## A reader of a CompositeCable link whose device could be on either side of a
## multi-way connector must come through here rather than through `channel` directly:
## the link already carries its cord, and a socket that reported one channel for all
## three made a Multi Out lead put the picture down all of them. system.gd does.
##
## dvd_player.gd and vcr_player.gd still read `channel`, which is currently the same
## answer — a deck wears a phono row and its sink is a set with phono sockets, so
## neither side of one of their links can ever be multi-way. Give either of them a
## multi-way socket and both need this.
func channel_for(_cord: int) -> Channel:
	return channel


func channel_name_for(cord: int) -> String:
	return CHANNEL_NAMES[channel_for(cord)]

