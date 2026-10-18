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

## Where the label picture sits, 1 mm over the paper and 0.5 mm under the text.
const _ART_Z := 0.0145
## The paper it is printed on (LabelMesh), which the picture is fitted inside.
const _ART_BOX := Vector2(0.11, 0.045)

## The sticker image beside the video file (MediaLabelArt), else null and the
## tape shows its title as text. Derived from video_path, never saved.
var _label_art: MeshInstance3D = null
## The sidecar the tape is meant to show, and the pool task decoding one.
var _label_path := ""
var _label_task := -1
var _label_job: Dictionary = {}
var _download_status := ""


func _ready() -> void:
	super()   # XRToolsPickable._ready collects grab points (SnapGrabPoint)
	set_process(false)
	_update_label()
	_request_label_art()


func _update_label() -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.text = video_label


func _notification(what: int) -> void:
	# The pool thread writes into _label_job, which dies with this node.
	if what == NOTIFICATION_PREDELETE and _label_task != -1:
		WorkerThreadPool.wait_for_task_completion(_label_task)


## Look for a picture beside the video and decode it off the main thread. A
## second call while one decodes only changes what is wanted; _process starts
## the next decode when the running one lands.
func _request_label_art() -> void:
	var path := MediaLabelArt.sidecar(video_path)
	if path == _label_path:
		return
	_label_path = path
	if _label_task == -1:
		_next_label_step()


func _next_label_step() -> void:
	if _label_path.is_empty():
		_show_label_art(null)
		return
	_label_job = {"path": _label_path}
	_label_task = WorkerThreadPool.add_task(MediaLabelArt.decode_into.bind(_label_job))
	set_process(true)


func _process(_delta: float) -> void:
	if _label_task == -1 or not WorkerThreadPool.is_task_completed(_label_task):
		return
	WorkerThreadPool.wait_for_task_completion(_label_task)
	_label_task = -1
	set_process(false)
	if str(_label_job.get("path", "")) != _label_path:
		_next_label_step()
		return
	_show_label_art(MediaLabelArt.texture_from(_label_job.get("image") as Image))


## Put `tex` on the label, or take the picture away and show the title again.
func _show_label_art(tex: Texture2D) -> void:
	if tex == null:
		if _label_art != null:
			# Out of the tree now, so a picture arriving in the same frame does
			# not meet a half-gone "LabelArt" of the same name.
			remove_child(_label_art)
			_label_art.queue_free()
			_label_art = null
	else:
		if _label_art == null:
			_label_art = MeshInstance3D.new()
			_label_art.name = "LabelArt"
			_label_art.mesh = QuadMesh.new()
			var mat := StandardMaterial3D.new()
			mat.roughness = 0.7
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_label_art.material_override = mat
			_label_art.position = Vector3(0.0, 0.018, _ART_Z)
			add_child(_label_art)
		(_label_art.material_override as StandardMaterial3D).albedo_texture = tex
		(_label_art.mesh as QuadMesh).size = MediaLabelArt.fit(
			float(tex.get_width()) / float(tex.get_height()), _ART_BOX)
	_apply_label_text_visibility()


## The picture carries the title itself, so the text steps aside for it: except
## while a transfer reports progress, which only the text can show.
func _apply_label_text_visibility() -> void:
	var lbl := get_node_or_null("VideoLabel") as Label3D
	if lbl:
		lbl.visible = _label_art == null or not _download_status.is_empty()


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
