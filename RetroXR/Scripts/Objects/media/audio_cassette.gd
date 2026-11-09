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
## The side `tape_track` / `tape_time` were written for (0 A, 1 B). `tape_progress` is the tape's place whichever side
## plays (TapeSides); turned over, the deck reads its place from that instead.
var tape_side: int = 0
## How long the tape is, minutes for both sides (C46 / C60 / C90 / C120: TapeSides.tape_minutes, the shortest that
## holds the album's longer side). Derived by the deck from the album, never authored; 60 until a deck has read it.
var tape_minutes: float = 60.0:
	set(v):
		if is_equal_approx(v, tape_minutes):
			return
		tape_minutes = v
		# A generated label says which tape it is: a deck that measured the album differently draws it again.
		if is_node_ready() and (_missing_a or _missing_b):
			_paint_missing()


## The world basis the hand let go of it at (MediaSide): the slot reads which side faces out from it, as a bay reads
## a disc's spin (RetroDisc). A snap zone handing it on is not a hand and is not recorded.
var _release_basis := Basis.IDENTITY


func let_go(by: Node3D, p_linear_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	if not (by is XRToolsSnapZone):
		_release_basis = global_basis.orthonormalized()
	super(by, p_linear_velocity, p_angular_velocity)


## The pose it was let go at, in the frame of `bay`.
func release_basis_in(bay: Node3D) -> Basis:
	return bay.global_basis.orthonormalized().inverse() * _release_basis


## Side A's face: the label out of the deck along +Z. Turned over about the upright, the exposed tape edge stays down.
func side_a_axis() -> Vector3:
	return Vector3.BACK


func flip_axis() -> Vector3:
	return Vector3.UP

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
## RetroXR's own label for a side the album has no picture for (MediaLabelPainter), and which sides those are.
var _gen_a: Texture2D = null
var _gen_b: Texture2D = null
var _missing_a := false
var _missing_b := false
## Bumped by every paint: a paint that finishes after a newer one has started is dropped.
var _paint_token := 0
var _download_status := ""

## The cassette's own Compact Cassette (CompactCassette, named Shell), or null while a mod's shell dresses it or
## this is another scene built on the script.
var _shell: CompactCassette = null
const GAME_SCENE := "res://Scenes/Objects/media/audio_cassette.tscn"
## The stand-in's parts, hidden under the shell: the box and its label block (kept: the scene stays whole).
const STAND_IN := ["TapeMesh", "LabelMesh"]
## A mod that dresses the cassette claims this (ModApi.dress); the game's own shell steps aside for it.
const DRESS_CLASS := &"AudioCassette"
const DRESS_KEY := "shell"
static var _logged_dresser := "-"


func _ready() -> void:
	super._ready()
	add_to_group("audio_cassette")
	_labels = MediaLabelLoader.new()
	_labels.name = "LabelLoader"
	_labels.art_ready.connect(_on_label_art)
	add_child(_labels)
	_dress_shell()
	_update_label()
	_request_label_art()


## Put on the Compact Cassette in place of the stand-in box, unless a mod dresses the cassette: a mod's hook runs as
## the cassette enters the tree, before this, and hangs a node named Shell; and one that holds the claim but has not
## dressed this one yet still owns it. Either way the game's shell stays off, so a tape is never dressed twice.
func _dress_shell() -> void:
	if scene_file_path != GAME_SCENE or has_node("Shell"):
		_note_dresser("a shell already on it" if has_node("Shell") else "")
		return
	var mods := get_node_or_null("/root/Mods")
	var dresser := str(mods.call("dresser_of", DRESS_CLASS, DRESS_KEY)) if mods != null and mods.has_method("dresser_of") 		else ""
	if not dresser.is_empty():
		_note_dresser(dresser)
		return
	_note_dresser("the game")
	_shell = CompactCassette.new()
	_shell.name = "Shell"
	add_child(_shell)
	for part: String in STAND_IN:
		var mesh := get_node_or_null(part) as Node3D
		if mesh != null:
			mesh.visible = false
	var title := get_node_or_null("CassetteLabel") as Label3D
	if title != null:
		CompactCassette.write_on_label(title)
	_lay_art()      # plain paper until (unless) the album's pictures arrive


## Who dresses the cassettes, once per run and again only when it changes (a library spawns dozens of tapes).
static func _note_dresser(who: String) -> void:
	if who.is_empty() or who == _logged_dresser:
		return
	_logged_dresser = who
	print("[Cassette] audio cassettes dressed by %s" % who)


func _update_label() -> void:
	var lbl := get_node_or_null("CassetteLabel") as Label3D
	if lbl:
		lbl.text = album_label


func _request_label_art() -> void:
	var a := MediaLabelArt.album_side(album_path, "a")
	var b := MediaLabelArt.album_side(album_path, "b")
	_labels.request({&"a": a, &"b": b})
	# A side with no picture of its own wears RetroXR's label (the loader says nothing for a path that is "").
	_missing_a = a.is_empty()
	_missing_b = b.is_empty()
	if _missing_a:
		_tex_a = null
	if _missing_b:
		_tex_b = null
	_measure_tape()
	_paint_missing()


func _on_label_art(slot: StringName, tex: Texture2D) -> void:
	if slot == &"a":
		_tex_a = tex
		_missing_a = tex == null
	else:
		_tex_b = tex
		_missing_b = tex == null
	if tex == null:
		_paint_missing()
	_lay_art()


## The album's name as its labels print it.
func _label_title() -> String:
	if not album_label.is_empty():
		return album_label
	return album_path.get_file() if DirAccess.dir_exists_absolute(album_path) else album_path.get_file().get_basename()


## The tape this album would be wound on (TapeSides.tape_minutes over its two sides, MusicLengths' lengths), before
## any deck has read it, so the label and the reels are right from the start. A deck sets it again as it measures.
func _measure_tape() -> void:
	if album_path.is_empty():
		return
	var sides := RomLibrary.music_sides(album_path)
	var a_s := TapeSides.music_s(MusicLengths.lengths_now(sides["a"]))
	var b_s := TapeSides.music_s(MusicLengths.lengths_now(sides["b"]))
	if a_s <= 0.0 and b_s <= 0.0:
		return
	tape_minutes = TapeSides.tape_minutes(a_s, b_s)


## Draw RetroXR's label for each side with no picture, then lay them on. Nothing to name it by: none.
func _paint_missing() -> void:
	_paint_token += 1
	var token := _paint_token
	var title := _label_title()
	if title.is_empty() or not (_missing_a or _missing_b):
		_gen_a = null
		_gen_b = null
		_lay_art()
		return
	var tape := TapeSides.tape_name(tape_minutes)
	var a: Texture2D = null
	var b: Texture2D = null
	if _missing_a:
		a = await MediaLabelPainter.cassette(self, "A", title, tape)
	if _missing_b and is_instance_valid(self):
		b = await MediaLabelPainter.cassette(self, "B", title, tape)
	if not is_instance_valid(self) or token != _paint_token:
		return
	_gen_a = a
	_gen_b = b
	print("[AudioCassette] %s: RetroXR's own label on side %s (\"%s\", %s)" % [name,
		"A and B" if _missing_a and _missing_b else ("A" if _missing_a else "B"), title, tape])
	_lay_art()


## What each side wears: the album's picture, else RetroXR's label, else (side B) side A's picture.
func _front_art() -> Texture2D:
	return _tex_a if _tex_a != null else _gen_a


func _back_art() -> Texture2D:
	if _tex_b != null:
		return _tex_b
	if _gen_b != null:
		return _gen_b
	return _tex_a


## Side A on the front and side B on the back, which is side A again when the
## album has no second picture. The back gets a paper label of its own, since
## the bare cassette has one on the front only.
func _lay_art() -> void:
	var front := _front_art()
	var back := _back_art()
	var block := get_node_or_null("LabelMesh") as MeshInstance3D
	var paper_mat := block.get_active_material(0) as BaseMaterial3D if block != null else null
	var paper := paper_mat.albedo_color if paper_mat != null else Color(0.9, 0.88, 0.8)
	if _shell != null:
		# The shell's own paper labels take the pictures (and the stand-in's cream when there are none).
		_shell.set_label("LabelA", front, paper)
		_shell.set_label("LabelB", back, paper)
		_apply_label_text_visibility()
		return
	# A shell a mod hung (xenu.cassette wears the same RETRO XR model): its own LabelA / LabelB take the pictures as
	# the game's shell's do, filling the label with the window cut out. The stand-in quads below were the old box's,
	# 80 x 30 mm and solid, which on this model shrank the picture and covered the window.
	var mod_shell := get_node_or_null("Shell")
	var side_a: Array = mod_shell.find_children("LabelA", "MeshInstance3D", true, false) if mod_shell != null else []
	var side_b: Array = mod_shell.find_children("LabelB", "MeshInstance3D", true, false) if mod_shell != null else []
	if not side_a.is_empty() or not side_b.is_empty():
		if front != null or back != null:
			CompactCassette.paint_label(side_a, front, paper)
			CompactCassette.paint_label(side_b, back, paper)
		for quad: String in ["LabelArt", "LabelArtB", "LabelPaperB"]:
			var old := get_node_or_null(quad)
			if old != null:
				remove_child(old)
				old.queue_free()
		_note_art_path("on a mod shell's LabelA / LabelB (%d + %d meshes)" % [side_a.size(), side_b.size()])
		_apply_label_text_visibility()
		return
	_note_art_path("on the stand-in quads (no shell labels)")
	MediaLabelArt.show_quad(self, "LabelArt", front, _ART_BOX,
		Transform3D(Basis.IDENTITY, Vector3(0.0, _ART_Y, _ART_Z)))
	_lay_back_paper(back != null)
	MediaLabelArt.show_quad(self, "LabelArtB", back, _ART_BOX,
		Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, _ART_Y, -_ART_Z)))
	_apply_label_text_visibility()


## Which way this cassette's pictures went, said once (a picture arriving later takes the same way).
var _art_path_said := ""


func _note_art_path(how: String) -> void:
	if how == _art_path_said or (_front_art() == null and _back_art() == null):
		return
	_art_path_said = how
	print("[AudioCassette] %s: pictures %s" % [name, how])


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
		lbl.visible = _front_art() == null or not _download_status.is_empty()


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
	var side := TapeSides.side_name(tape_side)
	@warning_ignore("integer_division")
	var at := "Side %s, track %d, %d:%02d" % [side, tape_track + 1, s / 60, s % 60]
	# How far through the side it was written on (side B runs the tape back along side A).
	var share := TapeSides.side_time(tape_progress, tape_side, 1.0)
	if share > 0.0:
		at += "  (%d%% of side %s)" % [roundi(share * 100.0), side]
	return [["Position", at], ["Path", album_path if album_path != "" else "None"]]
