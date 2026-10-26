## VCRTape — pickable VHS-style cassette carrying a video file path.
## Must be in the "vcr_tape" group to snap into a VCRPlayer's TapeSlot.
class_name VCRTape
extends XRToolsPickable


## The full path to the video file this tape represents
## — or a playlist (.m3u/.m3u8) of several, played one after another.
@export_global_file("*.mp4", "*.mkv", "*.avi", "*.webm", "*.mov", "*.m3u", "*.m3u8") var video_path: String = "":
	set(v):
		video_path = v
		# How long it is decides which cassette it is on, and is read as it is
		# given its recording: before the tape is in the room, so a shell drawn
		# as it appears is drawn at its size.
		if recording_seconds <= 0.0:
			note_recording_seconds(recording_length(v))
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

## The cassettes a recording is put on, by their NTSC names: T-5 runs five
## minutes. A recording goes on the shortest that holds it, and plays out into
## blank tape to that cassette's end, as a short clip dubbed onto a real tape
## does: it has to be rewound before it plays again. One longer than the
## longest is spread over that.
const CASSETTES: Array[int] = [5, 10, 15, 20, 30, 60, 90, 120, 160, 180, 210]
## How long the tape's recordings are, in seconds, all of them for a playlist; 0
## until known. Read from the file's own header as the tape is given it (an MP4
## or QuickTime movie header, a WAV header), or measured by the first deck to
## play it. Saved.
var recording_seconds: float = 0.0
## Which cassette it is, T-<this>, in minutes; 0 until the recording's length is
## known. Chosen once and kept: a cassette does not change size. Saved.
var cassette: int = 0
## Seconds into the blank tape after the last recording; 0 while the tape stands
## in its recordings. Written by the deck playing or winding it. Saved.
var tape_blank: float = 0.0

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
	if tape_blank > 0.0:
		at = "Blank tape, %s past the recording" % VCRClock.counter(tape_blank)
	elif tape_progress > 0.0:
		at += "  (%d%%)" % roundi(tape_progress * 100.0)
	if at_tape_end():
		at += ", at the end"
	var size := "T-%d" % cassette if cassette > 0 else "Not known until played"
	return [["Cassette", size], ["Position", at],
		["Path", video_path if video_path != "" else "None"]]


# --- The cassette ---

## The cassette a recording `seconds` long goes on, in minutes: the shortest
## that holds it, or the longest.
static func cassette_for(seconds: float) -> int:
	for minutes: int in CASSETTES:
		if minutes * 60.0 >= seconds:
			return minutes
	return CASSETTES[-1]


## Take the recordings' length, once it is known; the first length known also
## chooses the cassette.
func note_recording_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return
	recording_seconds = seconds
	if cassette <= 0:
		cassette = cassette_for(seconds)


## How long the whole cassette plays, in seconds; 0 while it is not known.
func cassette_seconds() -> float:
	return cassette * 60.0


## How much blank tape follows the recordings, in seconds.
func blank_seconds() -> float:
	if cassette <= 0 or recording_seconds <= 0.0:
		return 0.0
	return maxf(cassette_seconds() - recording_seconds, 0.0)


## Where the tape stands along the whole cassette, in seconds from its start;
## how far through its recordings it is, then the blank tape after them. A
## recording longer than the cassette is spread over it.
func tape_seconds() -> float:
	var into := clampf(tape_progress, 0.0, 1.0) * minf(recording_seconds, cassette_seconds())
	return minf(into + tape_blank, cassette_seconds())


## True when the tape has been played or wound to the very end of the cassette,
## and has to be rewound before it plays again.
func at_tape_end() -> bool:
	return tape_progress >= 1.0 and tape_blank >= blank_seconds()


## How long a tape's recordings are, in seconds, all of a playlist's added up,
## from the files' own headers; 0 when one of them cannot be read that way (a
## deck measures it when it plays it).
static func recording_length(path: String) -> float:
	if path.is_empty():
		return 0.0
	var total := 0.0
	for file: String in RomLibrary.video_recordings(path):
		var seconds := file_length(file)
		if seconds <= 0.0:
			return 0.0
		total += seconds
	return total


## One file's length in seconds from its header, or 0.
static func file_length(path: String) -> float:
	match path.get_extension().to_lower():
		"mp4", "m4v", "mov":
			return _movie_length(path)
		"wav":
			return _wave_length(path)
	return 0.0


## An MP4 or QuickTime file's length: the movie header (mvhd) in its movie box
## (moov), its duration over its timescale. The boxes are walked by their sizes,
## so a file with its movie box after its picture costs a few seeks, not a read.
static func _movie_length(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0.0
	f.big_endian = true
	var end := f.get_length()
	var at := 0
	var inside := -1
	while at + 8 <= end:
		f.seek(at)
		var size := int(f.get_32())
		var kind := f.get_buffer(4).get_string_from_ascii()
		var head := 8
		if size == 1:
			size = int(f.get_64())
			head = 16
		elif size == 0:
			size = end - at
		if size < head:
			break
		if kind == "moov" and inside < 0:
			# Into the movie box: its children follow its own header.
			inside = at + size
			at += head
			continue
		if kind == "mvhd" and inside > 0:
			var version := f.get_8()
			f.get_buffer(3)
			var timescale := 0
			var duration := 0
			if version == 1:
				f.get_buffer(16)
				timescale = int(f.get_32())
				duration = int(f.get_64())
			else:
				f.get_buffer(8)
				timescale = int(f.get_32())
				duration = int(f.get_32())
			return float(duration) / float(timescale) if timescale > 0 and duration > 0 else 0.0
		at += size
		if inside > 0 and at >= inside:
			break
	return 0.0


## A WAV file's length: its data over the bytes a second its format plays.
static func _wave_length(path: String) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 12 or f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return 0.0
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return 0.0
	var per_second := 0
	while f.get_position() + 8 <= f.get_length():
		var kind := f.get_buffer(4).get_string_from_ascii()
		var size := int(f.get_32())
		var next := f.get_position() + size + (size & 1)
		if kind == "fmt ":
			f.get_buffer(8)
			per_second = int(f.get_32())
		elif kind == "data":
			return float(size) / float(per_second) if per_second > 0 else 0.0
		f.seek(next)
	return 0.0
