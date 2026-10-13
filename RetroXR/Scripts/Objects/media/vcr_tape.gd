## VCRTape — pickable VHS-style cassette carrying a video file path.
## Must be in the "vcr_tape" group to snap into a VCRPlayer's TapeSlot.
class_name VCRTape
extends XRToolsPickable


## The full path to the video file this tape represents
@export_global_file("*.mp4", "*.mkv", "*.avi", "*.webm", "*.mov") var video_path: String = ""

## Display label (video name, shown on the tape face and in spawn menu)
@export var video_label: String = "":
	set(v):
		video_label = v
		_update_label()


## Where the tape stands, in seconds from its start. A tape keeps its place.
## The deck it is in writes this as it plays, winds and stops
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
