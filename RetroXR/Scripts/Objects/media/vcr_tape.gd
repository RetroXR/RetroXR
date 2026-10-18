## VCRTape — pickable VHS-style cassette carrying a video file path.
## Must be in the "vcr_tape" group to snap into a VCRPlayer's TapeSlot.
class_name VCRTape
extends XRToolsPickable


## The full path to the video file this tape represents
## — or a playlist (.m3u/.m3u8) of several, played one after another.
@export_global_file("*.mp4", "*.mkv", "*.avi", "*.webm", "*.mov", "*.m3u", "*.m3u8") var video_path: String = "":
	set(v):
		video_path = v
		if is_node_ready():
			_request_label_art()

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

## Where the label picture sits, 0.5 mm over the paper and 0.5 mm under the text.
const _ART_Z := 0.0145
## The paper it is printed on (LabelMesh), which the picture is fitted inside.
const _ART_BOX := Vector2(0.11, 0.045)
## The spine is the top edge, the one the label sits against: the picture lies
## 0.2 mm over the 40 mm half-height and is fitted inside the edge's width and
## depth, which is 140 x 25 mm.
const _SPINE_Y := 0.0402
const _SPINE_BOX := Vector2(0.136, 0.021)

## Finds and decodes the pictures beside the video file (MediaLabelArt): the
## sticker for the face (LabelArt) and a strip for the spine (SpineArt). A tape
## with no sticker shows its title as text. Derived from video_path, never saved.
var _labels: MediaLabelLoader = null
var _download_status := ""


func _ready() -> void:
	super()   # XRToolsPickable._ready collects grab points (SnapGrabPoint)
	_labels = MediaLabelLoader.new()
	_labels.name = "LabelLoader"
	_labels.art_ready.connect(_on_label_art)
	add_child(_labels)
	_update_label()
	_request_label_art()


func _update_label() -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.text = video_label


## Look for the pictures beside the video; they decode off the main thread.
func _request_label_art() -> void:
	_labels.request({
		&"front": MediaLabelArt.sidecar(video_path),
		&"spine": MediaLabelArt.sidecar(video_path, " spine"),
	})


## Put a picture on the tape, or take it away (a null `tex`) and show the title
## text again.
func _on_label_art(slot: StringName, tex: Texture2D) -> void:
	if slot == &"front":
		MediaLabelArt.show_quad(self, "LabelArt", tex, _ART_BOX,
			Transform3D(Basis.IDENTITY, Vector3(0.0, 0.018, _ART_Z)))
		_apply_label_text_visibility()
	else:
		# A quad faces +Z; turned -90 degrees about X it faces up, with the top
		# of the picture toward the back, which reads right from the front.
		MediaLabelArt.show_quad(self, "SpineArt", tex, _SPINE_BOX,
			Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, _SPINE_Y, 0.0)))


## The picture carries the title itself, so the text steps aside for it: except
## while a transfer reports progress, which only the text can show.
func _apply_label_text_visibility() -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.visible = get_node_or_null("LabelArt") == null or not _download_status.is_empty()


## Returns the video path — called by VCRPlayer when the tape snaps in
func get_video_path() -> String:
	return video_path


## Netplay: show transfer progress on the tape label (empty string restores the
## video label). Called by NetObjectSync while fetching a tape's recordings.
func net_set_download_status(status: String) -> void:
	_download_status = status
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.text = video_label if status.is_empty() else status
	_apply_label_text_visibility()


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
