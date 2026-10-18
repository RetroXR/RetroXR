## AudioCassette — a physical audio tape that snaps into a CassettePlayer's slot
## and carries the path to a music album (a folder of audio tracks, or a single
## audio file). Group "audio_cassette" is what lets the player's slot accept it.
## Mirrors VCRTape, but for audio.
class_name AudioCassette
extends XRToolsPickable

## Path to the album: a folder of audio files, or a single audio file.
@export var album_path: String = "":
	set(v):
		album_path = v
		if is_node_ready():
			_request_label_art()

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

## Where the pictures sit. The paper is the LabelMesh slab, whose face is at
## z = 0.0075 (the text is 0.5 mm over it); a picture lies 0.2 mm over the paper
## and is fitted inside it. Side B is the same on the back, turned half a turn
## about the upright axis, so turning the cassette over keeps it the right way up.
const _ART_Z := 0.0077
const _ART_Y := 0.012
const _PAPER_Z := 0.0065
const _ART_BOX := Vector2(0.08, 0.03)

## Finds and decodes the album's pictures (MediaLabelArt): side A on the front
## (LabelArt), side B on the back (LabelArtB). With none a cassette shows the
## album's name as text. Derived from album_path, never saved.
var _labels: MediaLabelLoader = null
var _tex_a: Texture2D = null
var _tex_b: Texture2D = null
var _download_status := ""


func _ready() -> void:
	super._ready()
	add_to_group("audio_cassette")
	_labels = MediaLabelLoader.new()
	_labels.name = "LabelLoader"
	_labels.art_ready.connect(_on_label_art)
	add_child(_labels)
	_update_label()
	_request_label_art()


func _update_label() -> void:
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.text = album_label


func _request_label_art() -> void:
	_labels.request({
		&"a": MediaLabelArt.album_side(album_path, "a"),
		&"b": MediaLabelArt.album_side(album_path, "b"),
	})


func _on_label_art(slot: StringName, tex: Texture2D) -> void:
	if slot == &"a":
		_tex_a = tex
	else:
		_tex_b = tex
	_lay_art()


## Side A on the front and side B on the back, which is side A again when the
## album has no second picture. The back gets a paper label of its own, since
## the bare cassette has one on the front only.
func _lay_art() -> void:
	var back := _tex_b if _tex_b != null else _tex_a
	MediaLabelArt.show_quad(self, "LabelArt", _tex_a, _ART_BOX,
		Transform3D(Basis.IDENTITY, Vector3(0.0, _ART_Y, _ART_Z)))
	_lay_back_paper(back != null)
	MediaLabelArt.show_quad(self, "LabelArtB", back, _ART_BOX,
		Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, _ART_Y, -_ART_Z)))
	_apply_label_text_visibility()


func _lay_back_paper(wanted: bool) -> void:
	var paper := get_node_or_null("LabelPaperB") as MeshInstance3D
	if not wanted:
		if paper != null:
			remove_child(paper)
			paper.queue_free()
		return
	var front := get_node_or_null("LabelMesh") as MeshInstance3D
	if paper != null or front == null:
		return
	paper = MeshInstance3D.new()
	paper.name = "LabelPaperB"
	paper.mesh = front.mesh
	paper.set_surface_override_material(0, front.get_surface_override_material(0))
	paper.position = Vector3(0.0, _ART_Y, -_PAPER_Z)
	add_child(paper)


## The picture carries the album's name itself, so the text steps aside for it:
## except while a transfer reports progress, which only the text can show.
func _apply_label_text_visibility() -> void:
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.visible = _tex_a == null or not _download_status.is_empty()


## Netplay: show transfer progress on the cassette label (empty string restores
## the album label). Called by NetObjectSync while fetching the album.
func net_set_download_status(status: String) -> void:
	_download_status = status
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.text = album_label if status.is_empty() else status
	_apply_label_text_visibility()


func get_album_path() -> String:
	return album_path


## What the generic object menu lists under its title (ObjectOptionsPanel):
## where the tape stands, as a track and a time into it, and the album it
## carries. The share of the tape is left off until a deck has measured it.
func options_info() -> Array:
	var s := roundi(tape_time)
	@warning_ignore("integer_division")
	var at := "Track %d, %d:%02d" % [tape_track + 1, s / 60, s % 60]
	if tape_progress > 0.0:
		at += "  (%d%% of the tape)" % roundi(tape_progress * 100.0)
	return [["Position", at], ["Path", album_path if album_path != "" else "None"]]
