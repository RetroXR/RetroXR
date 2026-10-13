## AudioCassette — a physical audio tape that snaps into a CassettePlayer's slot
## and carries the path to a music album (a folder of audio tracks, or a single
## audio file). Group "audio_cassette" is what lets the player's slot accept it.
## Mirrors VCRTape, but for audio.
class_name AudioCassette
extends XRToolsPickable

## Path to the album: a folder of audio files, or a single audio file.
@export var album_path: String = ""

## Display label (album name, shown on the cassette face).
@export var album_label: String = "":
	set(v):
		album_label = v
		_update_label()


## Where the tape stands: which track of the album, and how far into it, in
## seconds. A tape keeps its place. The deck it is in writes these as it plays,
## winds and stops (RetroAudioPlayer._note_tape) and reads them when the cassette
## goes in, so one taken out half way through and put back, into this deck or
## another, carries on from where it was. A save keeps them too.
var tape_track: int = 0
var tape_time: float = 0.0
## How far through the whole album the tape is, 0 to 1, for anything that shows
## the tape itself (a mod's reels). Measured by the deck from the tracks' sizes
## on disk, which follow their lengths closely enough to wind a reel by.
var tape_progress: float = 0.0
## How the tape is moving right now: 0 still (out of a deck, stopped or paused),
## 1 playing, more winding on, less than 0 winding back.
var tape_speed: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("audio_cassette")
	_update_label()


func _update_label() -> void:
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.text = album_label


## Netplay: show transfer progress on the cassette label (empty string restores
## the album label). Called by NetObjectSync while fetching the album.
func net_set_download_status(status: String) -> void:
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.text = album_label if status.is_empty() else status


func get_album_path() -> String:
	return album_path
