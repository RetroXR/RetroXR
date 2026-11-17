## AudioDisc — a physical audio CD that snaps into a CDPlayer's slot and carries
## the path to a music album (a folder of audio tracks, or a single audio file).
## Group "audio_disc" is what lets the player's slot accept it. Mirrors DVDDisc.
##
## Its printed face is the album's own picture (MediaLabelArt.album_side's side A:
## `cover` / `folder` / `front` / `album`, or `Name.png`), cut to its middle square
## and printed edge to edge; with none, RetroXR's own face (MediaLabelPainter.cd:
## the name and one stripe band in ink on the bare silver). Either goes to the disc
## shader's label_tex, printed from the mirror band out (label_r_in), so the hub
## stays clear. A CD has one printed side: a `back` picture is not used.
class_name AudioDisc
extends XRToolsPickable

## Path to the album: a folder of audio files, or a single audio file.
@export var album_path: String = "":
	set(value):
		album_path = value
		if is_node_ready():
			_request_label_art()

## Human-readable label printed on the disc face.
@export var album_label: String = "":
	set(value):
		album_label = value
		_update_label()
		# RetroXR's own face prints the name: a renamed disc draws it again.
		if is_node_ready() and _pic == null:
			_paint_missing()

## Printing starts at the mirror band's outer edge (the disc's r_data_start), metres.
const PRINT_FROM := 0.023

@onready var _label: Label3D = get_node_or_null("DiscLabel")

## Finds and decodes the album's picture; derived from album_path, never saved.
var _labels: MediaLabelLoader = null
var _pic: Texture2D = null
var _gen: Texture2D = null
## This disc's own copy of the disc material: the scene's is shared by every audio CD.
var _mat: ShaderMaterial = null
## Bumped by every paint: a paint that finishes after a newer one has started is dropped.
var _paint_token := 0
## The album whose track lengths were asked to be measured, so a failed measure is not asked again and again.
var _lengths_asked := ""
var _download_status := ""


func _ready() -> void:
	super._ready()
	add_to_group("audio_disc")
	var body := get_node_or_null("DiscMesh") as MeshInstance3D
	var shared := body.get_surface_override_material(0) as ShaderMaterial if body != null else null
	if shared != null:
		_mat = shared.duplicate() as ShaderMaterial
		body.set_surface_override_material(0, _mat)
	_labels = MediaLabelLoader.new()
	_labels.name = "LabelLoader"
	_labels.square = true
	_labels.art_ready.connect(_on_label_art)
	add_child(_labels)
	_update_label()
	_request_label_art()


func get_album_path() -> String:
	return album_path


## Netplay: show transfer progress on the disc face (empty string restores the
## album label). Called by NetObjectSync while fetching the album over the wire.
func net_set_download_status(status: String) -> void:
	_download_status = status
	if _label:
		_label.text = album_label if status.is_empty() else status
	_apply_label_text_visibility()


func _update_label() -> void:
	if _label:
		_label.text = album_label


func _request_label_art() -> void:
	var cover := MediaLabelArt.album_side(album_path, "a")
	_labels.request({&"a": cover})
	# No picture: RetroXR's face (the loader says nothing for a path that stays "").
	if cover.is_empty():
		_pic = null
		_paint_missing()


func _on_label_art(_slot: StringName, tex: Texture2D) -> void:
	_pic = tex
	if tex == null:
		_paint_missing()
	_lay_art()


## The album's name as the face prints it.
func _label_title() -> String:
	if not album_label.is_empty():
		return album_label
	return album_path.get_file() if DirAccess.dir_exists_absolute(album_path) else album_path.get_file().get_basename()


## "12 TRACKS  ·  46:20" for the album, "" when it has no tracks. Lengths not yet
## measured are estimated from the files' sizes; they are measured once, off the
## main thread, and the face drawn again with them.
func _album_details() -> String:
	var tracks := RomLibrary.music_tracks(album_path)
	if tracks.is_empty():
		return ""
	var seconds := 0.0
	for s: float in MusicLengths.lengths_now(tracks):
		seconds += s
	if _lengths_asked != album_path and not MusicLengths.all_known(tracks):
		_lengths_asked = album_path
		MusicLengths.request(tracks, func() -> void:
			if is_instance_valid(self) and _pic == null:
				_paint_missing())
	return MediaLabelPainter.cd_details(tracks.size(), seconds)


## Draw RetroXR's face for an album with no picture, then lay it on. Nothing to
## name it by: none, and the floating title shows.
func _paint_missing() -> void:
	if _labels == null:
		return
	_paint_token += 1
	var token := _paint_token
	var title := _label_title()
	if title.is_empty():
		_gen = null
		_lay_art()
		return
	var face := await MediaLabelPainter.cd(self, title, _album_details())
	if not is_instance_valid(self) or token != _paint_token:
		return
	_gen = face
	_lay_art()


## The album's picture, else RetroXR's face, printed on the label side.
func _lay_art() -> void:
	var tex := _pic if _pic != null else _gen
	if _mat != null:
		_mat.set_shader_parameter("label_tex", tex)
		_mat.set_shader_parameter("label_r_in", PRINT_FROM)
	_apply_label_text_visibility()


## The print carries the name itself, so the floating title steps aside for it:
## except while a transfer reports progress, which only the text can show.
func _apply_label_text_visibility() -> void:
	if _label:
		var printed := _mat != null and _mat.get_shader_parameter("label_tex") != null
		_label.visible = not printed or not _download_status.is_empty()
