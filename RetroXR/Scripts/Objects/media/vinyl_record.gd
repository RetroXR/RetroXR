## VinylRecord — a 12" LP that drops onto a RecordPlayer's platter and carries the
## path to a music album (a folder of audio tracks, or a single audio file). Group
## "vinyl_record" is what lets the deck's platter well accept it. The third member
## of the family beside AudioDisc and AudioCassette, and identical to them in every
## respect the rest of the app can see — same album exports, same label hook, same
## verify-by-name netplay treatment.
class_name VinylRecord
extends XRToolsPickable

## Path to the album: a folder of audio files, or a single audio file.
@export var album_path: String = "":
	set(value):
		album_path = value
		if is_node_ready():
			_request_label_art()

## Human-readable label printed on the record's paper centre.
@export var album_label: String = "":
	set(value):
		album_label = value
		_update_label()

@onready var _label: Label3D = get_node_or_null("DiscLabel")

## Finds and decodes the album's pictures (MediaLabelArt): side A on the top
## label and side B on the underside, which is side A again when the album has
## no second picture. A square is cut from each, since the label is round, and
## they are handed to the shader. With none the label is the text. Derived from
## album_path, never saved.
var _labels: MediaLabelLoader = null
var _art_a: Texture2D = null
var _art_b: Texture2D = null
var _download_status := ""
var _own_material := false


func _ready() -> void:
	super._ready()
	add_to_group("vinyl_record")
	_labels = MediaLabelLoader.new()
	_labels.name = "LabelLoader"
	_labels.square = true
	_labels.art_ready.connect(_on_label_art)
	add_child(_labels)
	_update_label()
	_request_label_art()


func get_album_path() -> String:
	return album_path


## Netplay: show transfer progress on the label (empty string restores the album
## label). Called by NetObjectSync while resolving the album on this peer.
func net_set_download_status(status: String) -> void:
	_download_status = status
	if _label:
		_label.text = album_label if status.is_empty() else status
	_apply_label_text_visibility()


func _update_label() -> void:
	if _label:
		_label.text = album_label


func _request_label_art() -> void:
	_labels.request({
		&"a": MediaLabelArt.album_side(album_path, "a"),
		&"b": MediaLabelArt.album_side(album_path, "b"),
	})


func _on_label_art(slot: StringName, tex: Texture2D) -> void:
	if slot == &"a":
		_art_a = tex
	else:
		_art_b = tex
	var body := get_node_or_null("RecordMesh") as MeshInstance3D
	var mat := body.get_surface_override_material(0) as ShaderMaterial if body else null
	if mat != null:
		if not _own_material:
			# The scene's material is one resource every record shares.
			mat = mat.duplicate() as ShaderMaterial
			body.set_surface_override_material(0, mat)
			_own_material = true
		mat.set_shader_parameter("label_tex", _art_a)
		mat.set_shader_parameter("label_tex_b", _art_b if _art_b != null else _art_a)
	_apply_label_text_visibility()


## The picture carries the album's name itself, so the text steps aside for it:
## except while a transfer reports progress, which only the text can show.
func _apply_label_text_visibility() -> void:
	if _label:
		_label.visible = _art_a == null or not _download_status.is_empty()
