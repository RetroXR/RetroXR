## VCRTape — pickable VHS-style cassette carrying a video file path.
## Must be in the "vcr_tape" group to snap into a VCRPlayer's TapeSlot.
class_name VCRTape
extends XRToolsPickable


## The full path to the video file this tape represents
## — or a playlist (.m3u/.m3u8) of several, played one after another.
@export_global_file("*.mp4", "*.mkv", "*.avi", "*.webm", "*.mov", "*.m3u", "*.m3u8") var video_path: String = ""

## Display label (video name, shown on the tape face and in spawn menu)
@export var video_label: String = "":
	set(v):
		video_label = v
		_update_label()


## Which recording the tape stands in, counted from 0, for a tape that is a
## playlist of several (RomLibrary.video_recordings). Always 0 for one file.
var tape_track: int = 0
## Where the tape stands, in seconds from the start of that recording. A tape
## keeps its place. The deck it is in writes this as it plays, winds and stops
## (VCRPlayer._note_tape) and reads it when the tape goes in, so one taken out
## half way through and put back, into this deck or another, carries on from
## where it was. A save keeps it too. The audio cassette has the same.
var tape_time: float = 0.0
## How far through the recording the tape is, 0 to 1, for anything that shows
## the tape itself (a mod's reels).
var tape_progress: float = 0.0
## How the tape is moving right now: 0 still (out of a deck, stopped or paused),
## 1 playing, more winding on, less than 0 winding back.
var tape_speed: float = 0.0


func _ready() -> void:
	super()   # XRToolsPickable._ready collects grab points (SnapGrabPoint)
	_update_label()


func _update_label() -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.text = video_label


## Returns the video path — called by VCRPlayer when the tape snaps in
func get_video_path() -> String:
	return video_path


## Netplay: show transfer progress on the tape label (empty string restores the
## video label). Called by NetObjectSync while fetching a tape's recordings.
func net_set_download_status(status: String) -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.text = video_label if status.is_empty() else status


## What the generic object menu lists under its title (ObjectOptionsPanel):
## where the tape stands, on the deck's own counter (and in which recording, for
## a playlist), and the file it carries. The share of the tape is left off until
## a deck has measured its length.
func options_info() -> Array:
	var at := VCRClock.counter(tape_time)
	if RomLibrary.is_playlist(video_path):
		at = "Recording %d, %s" % [tape_track + 1, at]
	if tape_progress > 0.0:
		at += "  (%d%%)" % roundi(tape_progress * 100.0)
	return [["Position", at], ["Path", video_path if video_path != "" else "None"]]
