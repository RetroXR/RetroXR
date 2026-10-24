## Audio-deck self-tests — the CD player, the cassette deck and the turntable, and
## the shared RetroAudioPlayer base under all three. Headless, no album, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/deck_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/deck_tests.tscn -- --only=gate
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## This is the first coverage the decks have ever had. Every case below is either a
## bug that shipped or a rule the turntable now depends on, and each one was watched
## going red before it was believed.
##
## ONE CONSTRAINT SHAPES EVERY CASE: VlcPlayer is a GDExtension that does not exist
## in a headless run, so `_vlc` is null and RetroAudioPlayer.play() returns early —
## `is_playing` NEVER becomes true here. So nothing asserts on audio. What is
## asserted is the state around it: which track is selected, whether the platter
## well is gated open or shut, what type a deck saves as, and which commands the net
## layer will accept. Asserting on is_playing would give a green that means nothing.
##
## Groups:
##   base/     the shared base with hardware a deck does not have
##   save/     each deck's save type, and the fallthrough that used to mislabel one
##   media/    the vinyl record through the guards that decide it exists
##   gate/     MediaTray's access matrix, which the tonearm now drives
##   arm/      the tonearm: parking, track mapping, and the restore that must NOT play
##   net/      the audio command shape, including the index-carrying one
##   remote/   which remote cells each deck offers
##   tape/     a tape keeps its place, and its menu says where that is
##   label/    a tape, cassette or record wears the pictures found beside its file
##   playlist/ an .m3u sets what plays and in what order, for albums and tapes
extends Node

const GROUPS := ["base", "save", "media", "gate", "arm", "scrub", "net", "remote", "tape", "label", "playlist"]

const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")
const CD_PLAYER := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const CASSETTE_PLAYER := preload("res://Scenes/Objects/appliances/cassette_player.tscn")
const VINYL_RECORD := preload("res://Scenes/Objects/media/vinyl_record.tscn")
const AUDIO_DISC := preload("res://Scenes/Objects/media/audio_disc.tscn")
const AUDIO_CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const VCR_PLAYER := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const VCR_TAPE := preload("res://Scenes/Objects/media/vcr_tape.tscn")

var _fail := 0
var _ran := 0
var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[test] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=")

	if _want("base"):
		await _test_base()
	if _want("save"):
		await _test_save_types()
	if _want("media"):
		await _test_media_guards()
	if _want("gate"):
		await _test_gate_matrix()
	if _want("arm"):
		await _test_arm()
	if _want("scrub"):
		await _test_scrub()
	if _want("net"):
		await _test_net()
	if _want("remote"):
		await _test_remote()
	if _want("tape"):
		await _test_tape()
	if _want("label"):
		await _test_label()
		await _test_label_albums()
		await _test_label_media()
	if _want("playlist"):
		await _test_playlist()

	await _cleanup()
	print("[test] %d cases, %s" % [_ran,
		"PASS" if _fail == 0 else "%d FAILURE(S)" % _fail])
	get_tree().quit(0 if _fail == 0 else 1)



# ── tape/ ─────────────────────────────────────────────────────────────────────

## A tape keeps its place. The cassette carries which track it is on and how far
## into it; the deck takes that up as the cassette goes in, keeps it written
## while it plays, leaves it alone while it does not, and a save carries it.
## Before this a cassette taken out half way through an album started from the
## top when it went back in, and a room saved with a tape playing came back at
## track one.
##
## Nothing here plays (see the top of this file), so each case drives the
## bookkeeping either side of the sound directly.
func _test_tape() -> void:
	# How far through an album a point is, weighed by the tracks' sizes.
	var sizes := PackedInt64Array([100, 300, 600])
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(sizes, 1, 0.5), 0.25),
		"tape/half way through the second of three tracks is a quarter of this album")
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(sizes, 0, 0.0), 0.0), "tape/the start is 0")
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(sizes, 2, 1.0), 1.0), "tape/the end is 1")
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(sizes, 9, 7.0), 1.0),
		"tape/a point past the end is the end, not past it")
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(PackedInt64Array([0, 0, 0, 0]), 2, 0.5), 0.625),
		"tape/with no sizes to go by every track counts the same")
	_ok(is_equal_approx(RetroAudioPlayer.album_progress(PackedInt64Array(), 0, 0.5), 0.0),
		"tape/an empty album has no progress")

	var deck := await _deck(CASSETTE_PLAYER) as RetroAudioPlayer
	var tape := AUDIO_CASSETTE.instantiate() as AudioCassette
	add_child(tape)
	_spawned.append(tape)
	_ok(tape.tape_track == 0 and tape.tape_time == 0.0 and tape.tape_progress == 0.0
		and tape.tape_speed == 0.0, "tape/a new cassette is at its start, and still")

	# Going in: the deck takes up the tape's place.
	deck._tracks = PackedStringArray(["a.ogg", "b.ogg", "c.ogg"])
	tape.tape_track = 2
	tape.tape_time = 31.5
	deck._take_tape_place(tape)
	_eq(deck._track_idx, 2, "tape/the deck selects the track the tape was on")
	_ok(is_equal_approx(deck._resume_at, 31.5), "tape/and holds how far into it to carry on from")
	tape.tape_track = 9
	deck._take_tape_place(tape)
	_eq(deck._track_idx, 2, "tape/a track the album no longer has is its last")
	var disc := AUDIO_DISC.instantiate()
	add_child(disc)
	_spawned.append(disc)
	deck._track_idx = 1
	deck._take_tape_place(disc)
	_ok(deck._track_idx == 1 and deck._resume_at == 0.0,
		"tape/a disc keeps no place: its track is left alone and it starts at the start")

	# Choosing a track is not carrying on: it starts that track at its start.
	deck._resume_at = 12.0
	deck._goto_track(1)
	_ok(deck._track_idx == 1 and deck._resume_at == 0.0, "tape/choosing a track drops the place held")

	# In a deck that is not playing, the tape's place is left exactly as it was.
	tape.tape_track = 1
	tape.tape_time = 12.0
	tape.tape_progress = 0.4
	tape.tape_speed = 1.0
	deck._snapped_media = tape
	deck.is_playing = false
	deck._note_tape()
	_ok(tape.tape_track == 1 and is_equal_approx(tape.tape_time, 12.0)
		and is_equal_approx(tape.tape_progress, 0.4), "tape/a stopped deck does not move the tape")
	_eq(tape.tape_speed, 0.0, "tape/and says it is still")

	# Coming out: still, and where it was.
	tape.tape_speed = 1.0
	deck._media_unloaded()
	_ok(tape.tape_speed == 0.0 and tape.tape_track == 1 and is_equal_approx(tape.tape_time, 12.0),
		"tape/taken out, the tape is still and keeps its place")
	_ok(deck._resume_at == 0.0 and deck._tape() == null, "tape/and the deck holds nothing of it")

	# A save carries the place, and a load puts it back.
	var store := ScenePersistence.new()
	var entry := store._serialize_node(tape, 1, {tape: 1})
	_ok(int(entry.get("tape_track", -1)) == 1 and is_equal_approx(float(entry.get("tape_time", -1.0)), 12.0)
		and is_equal_approx(float(entry.get("tape_progress", -1.0)), 0.4),
		"tape/a save records the track, the time into it and the progress")
	var back := store._deserialize_object(entry) as AudioCassette
	_ok(back != null and back.tape_track == 1 and is_equal_approx(back.tape_time, 12.0)
		and is_equal_approx(back.tape_progress, 0.4), "tape/and a load brings back a cassette at that place")
	if back != null:
		back.free()
	var old := store._deserialize_object({"type": "audio_cassette", "album_path": "", "album_label": "x"}) as AudioCassette
	_ok(old != null and old.tape_track == 0 and old.tape_time == 0.0,
		"tape/a save from before tapes kept their place loads at the start")
	if old != null:
		old.free()

	# The video tape keeps its place the same way, in the VCR.
	var vcr := await _deck(VCR_PLAYER) as VCRPlayer
	var video := VCR_TAPE.instantiate() as VCRTape
	add_child(video)
	_spawned.append(video)
	_ok(video.tape_time == 0.0 and video.tape_progress == 0.0 and video.tape_speed == 0.0,
		"tape/a new video tape is at its start, and still")
	# Offered at the mouth the way the bay will seat it: lying flat, label up,
	# not stood on its end by the tape's own snap grab point as well.
	var mouth := vcr.get_node("TapeSlot") as XRToolsSnapZone
	var ghost := mouth.preview_pose_for(video)
	var seat := mouth.global_transform * Transform3D(vcr._slot.media_local_basis, Vector3.ZERO)
	_ok(ghost.basis.is_equal_approx(seat.basis) and ghost.origin.is_equal_approx(seat.origin),
		"tape/the slot's preview lies the way the tape is seated")
	video.tape_time = 754.0
	video.tape_progress = 0.21
	vcr._take_tape_place(video)
	_ok(is_equal_approx(vcr._resume_at, 754.0) and vcr._tape == video and is_equal_approx(vcr._tape_time(), 754.0),
		"tape/a VCR takes up a video tape's place as it goes in")
	video.tape_speed = 1.0
	vcr._note_tape()
	_ok(is_equal_approx(video.tape_time, 754.0) and is_equal_approx(video.tape_progress, 0.21) and video.tape_speed == 0.0,
		"tape/a VCR that is not playing does not move the tape, and says it is still")
	video.tape_speed = 1.0
	vcr._on_media_removed()
	_ok(video.tape_speed == 0.0 and is_equal_approx(video.tape_time, 754.0) and vcr._tape == null and vcr._resume_at == 0.0,
		"tape/taken out, the video tape is still and keeps its place")
	vcr._take_tape_place(video)
	vcr._on_video_finished()
	_ok(video.tape_progress == 1.0 and video.tape_speed == 0.0 and vcr._resume_at == 0.0 and vcr._tape_at_end(),
		"tape/played to its end, a video tape stays at its end")
	vcr._on_play_pressed()
	_ok(not vcr.is_playing and video.tape_progress == 1.0,
		"tape/and Play does not play it until it is rewound")
	vcr._on_media_removed()
	video.tape_time = 754.0
	video.tape_progress = 0.21
	var v_entry := store._serialize_node(video, 2, {video: 2})
	_ok(is_equal_approx(float(v_entry.get("tape_time", -1.0)), 754.0)
		and is_equal_approx(float(v_entry.get("tape_progress", -1.0)), 0.21), "tape/a save records a video tape's place")
	var v_back := store._deserialize_object(v_entry) as VCRTape
	_ok(v_back != null and is_equal_approx(v_back.tape_time, 754.0) and is_equal_approx(v_back.tape_progress, 0.21),
		"tape/and a load brings back a video tape at that place")
	if v_back != null:
		v_back.free()

	# A recording goes on the shortest real cassette that holds it, and plays out
	# into the blank tape after it to that cassette's end.
	_eq([VCRTape.cassette_for(10.0), VCRTape.cassette_for(301.0), VCRTape.cassette_for(7200.0),
		VCRTape.cassette_for(7201.0), VCRTape.cassette_for(99999.0)], [5, 10, 120, 160, 210],
		"cassette/a recording goes on the shortest cassette that holds it, or the longest")
	var clip := ProjectSettings.globalize_path("user://deck_tests_clip.mp4")
	var mp4 := FileAccess.open(clip, FileAccess.WRITE)
	mp4.big_endian = true
	mp4.store_32(16)
	mp4.store_buffer("ftypisom".to_ascii_buffer())
	mp4.store_32(0)
	mp4.store_32(116)
	mp4.store_buffer("moov".to_ascii_buffer())
	mp4.store_32(108)
	mp4.store_buffer("mvhd".to_ascii_buffer())
	for v: int in [0, 0, 0, 600, 6000]:
		mp4.store_32(v)
	var pad := PackedByteArray()
	pad.resize(80)
	mp4.store_buffer(pad)
	mp4.close()
	_ok(is_equal_approx(VCRTape.file_length(clip), 10.0), "cassette/an MP4's length is read off its movie header")
	var short := VCR_TAPE.instantiate() as VCRTape
	_spawned.append(short)
	short.video_path = clip
	_ok(is_equal_approx(short.recording_seconds, 10.0) and short.cassette == 5
		and is_equal_approx(short.blank_seconds(), 290.0),
		"cassette/a ten-second clip is a T-5 as it is spawned, with 4 min 50 s of blank tape after it")
	add_child(short)
	vcr._take_tape_place(short)
	vcr.is_playing = true
	vcr._on_video_finished()
	_ok(vcr.is_playing and vcr._blank and short.tape_progress == 1.0 and short.tape_blank == 0.0
		and not short.at_tape_end() and vcr.get_video_texture() == null,
		"cassette/at the end of the recording the deck plays on into the blank tape, with no picture")
	vcr._run_blank(2.0)
	_ok(is_equal_approx(short.tape_blank, 2.0) and short.tape_speed == 1.0
		and is_equal_approx(short.tape_seconds(), 12.0), "cassette/and the tape runs on through it at play speed")
	vcr._paused = true
	vcr._run_blank(2.0)
	_ok(is_equal_approx(short.tape_blank, 2.0) and short.tape_speed == 0.0, "cassette/paused, it stands still")
	vcr._paused = false
	var blank_state := vcr.net_get_state()
	_ok(is_equal_approx(float(blank_state.get("blank", -1.0)), 2.0), "cassette/a session hears where in the blank the deck is")
	vcr._run_blank(1000.0)
	_ok(not vcr.is_playing and not vcr._blank and is_equal_approx(short.tape_blank, 290.0) and short.at_tape_end()
		and is_equal_approx(short.tape_seconds(), 300.0),
		"cassette/at the end of the cassette the deck stops, with all five minutes across")
	vcr._on_play_pressed()
	_ok(not vcr.is_playing, "cassette/and Play does nothing until it is rewound")
	var s_entry := store._serialize_node(short, 3, {short: 3})
	var s_back := store._deserialize_object(s_entry) as VCRTape
	_ok(s_back != null and s_back.cassette == 5 and is_equal_approx(s_back.recording_seconds, 10.0)
		and is_equal_approx(s_back.tape_blank, 290.0) and s_back.at_tape_end(),
		"cassette/a save keeps the cassette, its recording's length and the blank tape wound")
	if s_back != null:
		s_back.free()
	vcr._on_media_removed()
	DirAccess.remove_absolute(clip)

	# The menu a tape opens (the generic one, ObjectOptionsPanel) says where it
	# stands and what it carries. Before this it said only "Lock in place", and a
	# video tape's was titled with its node name, not the video.
	var shown := VCR_TAPE.instantiate() as VCRTape
	_spawned.append(shown)
	shown.video_path = "C:/retroxr/videos/Home Movies.mp4"
	shown.video_label = "Home Movies"
	_eq(shown.options_info(), [["Cassette", "Not known until played"], ["Position", "00:00:00"],
		["Path", "C:/retroxr/videos/Home Movies.mp4"]],
		"tape/a new video tape's menu: at the start, and no share or cassette of a length no deck has measured")
	shown.tape_time = 3754.4
	shown.tape_progress = 0.372
	_eq(shown.options_info()[1], ["Position", "01:02:34  (37%)"],
		"tape/a played one: the deck's own counter, and how far through the tape")
	shown.note_recording_seconds(4000.0)
	_eq(shown.options_info()[0], ["Cassette", "T-90"], "tape/and which cassette it is on, once its length is known")
	shown.video_path = ""
	_eq(shown.options_info()[2], ["Path", "None"], "tape/a tape with no file says so")
	var menu := ObjectOptionsPanel.new()
	menu._object = shown
	_eq(menu._display_name(), "Home Movies", "tape/a video tape's menu is titled with its video")
	menu.free()

	var shown_c := AUDIO_CASSETTE.instantiate() as AudioCassette
	_spawned.append(shown_c)
	shown_c.album_path = "C:/retroxr/music/Mixtape"
	_eq(shown_c.options_info(), [["Position", "Track 1, 0:00"], ["Path", "C:/retroxr/music/Mixtape"]],
		"tape/a new cassette's menu: track one at the start")
	shown_c.tape_track = 1
	shown_c.tape_time = 134.4
	shown_c.tape_progress = 0.45
	_eq(shown_c.options_info()[0], ["Position", "Track 2, 2:14  (45% of the tape)"],
		"tape/a played one: the track counted from one, the time into it, the share of the tape")

	# The UI draws the rows under the title, above the lock row, and rewrites them
	# in place as the place moves rather than stacking new ones.
	var ui := ObjectOptions2D.new()
	add_child(ui)
	_spawned.append(ui)
	ui.set_info(shown_c.options_info())
	var texts := func() -> Array:
		var out := []
		for row in ui._info.get_children():
			out.append([(row.get_child(0) as Label).text, (row.get_child(1) as Label).text])
		return out
	_eq(texts.call(), shown_c.options_info(), "tape/the menu shows each row's caption and text")
	_ok(ui._info.visible and ui._info.get_index() == 1, "tape/under the title, so the lock row lands below it")
	shown_c.tape_time = 135.0
	ui.set_info(shown_c.options_info())
	_ok(ui._info.get_child_count() == 2 and texts.call() == shown_c.options_info(),
		"tape/a moved place is rewritten in the same two rows")
	ui.set_info([])
	_ok(not ui._info.visible, "tape/and an object with nothing to tell shows no info at all")


# ── label/ ────────────────────────────────────────────────────────────────────

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_for(cond: Callable, frames := 180) -> bool:
	for i in frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _solid_png(path: String, w: int, h: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.1, 0.1))
	img.save_png(path)


## A video tape wears the picture found beside its video (`Name.mp4` is labelled
## by `Name.png`), so a label made in a generator such as vhs.texs.org drops in
## as it was downloaded. The text title is what a tape without one shows, and
## what steps aside for the picture, which carries the title itself.
##
## The picture is decoded on a pool thread, so each case waits for it. It is only
## derived from video_path, so nothing here is saved.
func _test_label() -> void:
	_scratch = ProjectSettings.globalize_path("user://deck_tests_label")
	RomLibrary._remove_tree(_scratch)   # what a killed run left
	DirAccess.make_dir_recursive_absolute(_scratch)
	var video := _scratch.path_join("Home Movies.mp4")

	_eq(MediaLabelArt.sidecar(video), "", "label/a video with no picture beside it has none")
	_eq(MediaLabelArt.sidecar(""), "", "label/an empty path has none")
	_eq(MediaLabelArt.sidecar(_scratch), "", "label/a folder, which is an album, has no sidecar (album_side finds its pictures)")

	var bare := VCR_TAPE.instantiate() as VCRTape
	bare.video_path = video
	bare.video_label = "Home Movies"
	add_child(bare)
	_spawned.append(bare)
	await _frames(3)
	_ok(bare.get_node_or_null("LabelArt") == null and (bare.get_node("VideoLabel") as Label3D).visible,
		"label/a tape with no picture shows its title as text")

	var png := _scratch.path_join("Home Movies.png")
	_solid_png(png, 400, 100)
	_eq(MediaLabelArt.sidecar(video), png, "label/a .png of the same name beside the video is its picture")
	DirAccess.remove_absolute(png)
	var jpg := _scratch.path_join("Home Movies.jpg")
	var jimg := Image.create(64, 64, false, Image.FORMAT_RGB8)
	jimg.save_jpg(jpg)
	_eq(MediaLabelArt.sidecar(video), jpg, "label/and a .jpg as well")
	DirAccess.remove_absolute(jpg)

	# A label made for printing is far bigger than a tape can show.
	var big := _scratch.path_join("big.png")
	_solid_png(big, 3000, 1000)
	var job := {"path": big}
	MediaLabelArt.decode_into(job)
	var decoded := job["image"] as Image
	_ok(decoded != null and decoded.get_width() == MediaLabelArt.MAX_SIDE and decoded.get_height() == 341
		and decoded.has_mipmaps(), "label/a big picture is cut to the size limit, in proportion, with mipmaps")
	var junk := _scratch_file("junk.png", "not a picture")
	var bad := {"path": junk}
	MediaLabelArt.decode_into(bad)
	_ok(bad["image"] == null, "label/a file that will not decode is no picture, rather than a blank one")

	_ok(MediaLabelArt.fit(4.0, Vector2(0.11, 0.045)).is_equal_approx(Vector2(0.11, 0.0275)),
		"label/a wide picture fills the paper's width")
	_ok(MediaLabelArt.fit(0.5, Vector2(0.11, 0.045)).is_equal_approx(Vector2(0.0225, 0.045)),
		"label/and a tall one its height, neither stretched")

	# On a tape: set before it enters the tree, as the spawn menu and a restore do.
	_solid_png(png, 400, 100)
	var tape := VCR_TAPE.instantiate() as VCRTape
	tape.video_path = video
	tape.video_label = "Home Movies"
	add_child(tape)
	_spawned.append(tape)
	var text := tape.get_node("VideoLabel") as Label3D
	var got: bool = await _wait_for(func() -> bool: return tape.get_node_or_null("LabelArt") != null)
	_ok(got, "label/a tape whose video has a picture beside it wears it")
	if not got:
		return
	var art := tape.get_node("LabelArt") as MeshInstance3D
	var mat := art.material_override as StandardMaterial3D
	_ok(mat.albedo_texture != null and mat.albedo_texture.get_width() == 400,
		"label/the picture is on the sticker, whole")
	_ok((art.mesh as QuadMesh).size.is_equal_approx(Vector2(0.11, 0.0275)),
		"label/and fitted inside the paper, not stretched over it")
	_ok(not text.visible, "label/the title text steps aside for it")
	tape.net_set_download_status("40%")
	_ok(text.visible and text.text == "40%", "label/a transfer's progress still shows, which only text can")
	tape.net_set_download_status("")
	_ok(not text.visible and text.text == "Home Movies", "label/and when it ends the picture is back and the title restored")

	# The path can change under a tape (a netplay peer remaps it to its own file).
	var other := _scratch.path_join("Other.mp4")
	tape.video_path = other
	_ok(await _wait_for(func() -> bool: return tape.get_node_or_null("LabelArt") == null),
		"label/a tape moved to a video with no picture drops it")
	_ok(text.visible, "label/and shows its title again")

	# Moved twice before the first decode lands: the last one wins.
	var tall := _scratch.path_join("Tall.png")
	_solid_png(tall, 100, 200)
	tape.video_path = video
	tape.video_path = _scratch.path_join("Tall.mp4")
	got = await _wait_for(func() -> bool:
		var a := tape.get_node_or_null("LabelArt") as MeshInstance3D
		return a != null and (a.mesh as QuadMesh).size.is_equal_approx(Vector2(0.0225, 0.045)))
	_ok(got, "label/two moves in a row end on the picture of the last")

	# Freed while a decode is in flight: the pool thread writes into the tape's
	# own job, so the tape must wait for it. A crash here is the failure.
	var doomed := VCR_TAPE.instantiate() as VCRTape
	doomed.video_path = video
	add_child(doomed)
	doomed.free()
	await _frames(3)
	_ok(true, "label/a tape freed while its picture decodes does not crash")

	RomLibrary._remove_tree(_scratch)


## Which picture is which side of an album. Pure file lookups, so nothing waits.
func _test_label_albums() -> void:
	_scratch = ProjectSettings.globalize_path("user://deck_tests_label_albums")
	RomLibrary._remove_tree(_scratch)
	DirAccess.make_dir_recursive_absolute(_scratch)
	var song := _scratch.path_join("Mix.mp3")

	_eq(MediaLabelArt.album_side(song, "a"), "", "label/an album with no picture has no side A")
	_eq(MediaLabelArt.album_side(song, "b"), "", "label/and no side B")
	_eq(MediaLabelArt.album_side("", "a"), "", "label/an empty path has neither")

	var side_a := _scratch.path_join("Mix A.png")
	_solid_png(side_a, 64, 64)
	_eq(MediaLabelArt.album_side(song, "a"), side_a, "label/`Name A.png` is side A of a single file")
	var plain := _scratch.path_join("Mix.png")
	_solid_png(plain, 64, 64)
	_eq(MediaLabelArt.album_side(song, "a"), plain, "label/but a plain `Name.png` is taken before it")
	_eq(MediaLabelArt.album_side(song, "b"), "", "label/neither of those is side B")
	var side_b := _scratch.path_join("Mix B.jpg")
	var jimg := Image.create(32, 32, false, Image.FORMAT_RGB8)
	jimg.save_jpg(side_b)
	_eq(MediaLabelArt.album_side(song, "b"), side_b, "label/`Name B.jpg` is side B")

	# A folder's own name is not a file name: "Vol. 2" has no extension to strip.
	var folder := _scratch.path_join("Vol. 2")
	DirAccess.make_dir_recursive_absolute(folder)
	_eq(MediaLabelArt.album_side(folder, "a"), "", "label/an album folder with no pictures has none")
	var beside := _scratch.path_join("Vol. 2.png")
	_solid_png(beside, 64, 64)
	_eq(MediaLabelArt.album_side(folder, "a"), beside, "label/`Folder.png` beside an album folder is its side A, dots and all")
	var beside_b := _scratch.path_join("Vol. 2 B.png")
	_solid_png(beside_b, 64, 64)
	_eq(MediaLabelArt.album_side(folder, "b"), beside_b, "label/and `Folder B.png` its side B")

	var inside := folder.path_join("Cover.JPG")
	jimg.save_jpg(inside)
	_eq(MediaLabelArt.album_side(folder, "a"), inside, "label/a picture inside the folder beats one beside it, whatever its case")
	_solid_png(folder.path_join("front.png"), 64, 64)
	_eq(MediaLabelArt.album_side(folder, "a"), inside, "label/`cover` is taken before `front`, whichever sorts first")
	_scratch_file("Vol. 2/cover.txt")
	_scratch_file("Vol. 2/back.txt")
	_eq(MediaLabelArt.album_side(folder, "b"), beside_b, "label/a file that is not a picture is not one")
	var back := folder.path_join("back.png")
	_solid_png(back, 64, 64)
	_eq(MediaLabelArt.album_side(folder, "b"), back, "label/`back` inside the folder is side B")

	RomLibrary._remove_tree(_scratch)


## What the three media do with those pictures: a tape's spine, a cassette's two
## faces and a record's two labels. Each is built the way the spawn menu builds
## it, with its path set before it enters the tree.
func _test_label_media() -> void:
	_scratch = ProjectSettings.globalize_path("user://deck_tests_label_media")
	RomLibrary._remove_tree(_scratch)
	DirAccess.make_dir_recursive_absolute(_scratch)

	# ── a tape's spine ──
	var video := _scratch.path_join("Home Movies.mp4")
	_solid_png(_scratch.path_join("Home Movies spine.png"), 800, 100)
	var tape := VCR_TAPE.instantiate() as VCRTape
	tape.video_path = video
	tape.video_label = "Home Movies"
	add_child(tape)
	_spawned.append(tape)
	var got: bool = await _wait_for(func() -> bool: return tape.get_node_or_null("SpineArt") != null)
	_ok(got, "label/a tape with `Name spine.png` beside its video wears it on the spine")
	if not got:
		return
	var spine := tape.get_node("SpineArt") as MeshInstance3D
	_ok(tape.get_node_or_null("LabelArt") == null and (tape.get_node("VideoLabel") as Label3D).visible,
		"label/and a spine alone leaves the face as text")
	_ok(spine.transform.basis.z.is_equal_approx(Vector3.UP) and spine.transform.basis.y.is_equal_approx(Vector3(0, 0, -1)),
		"label/the strip lies on the top edge, its top toward the back")
	_ok(is_equal_approx(spine.position.y, 0.0402)
		and (spine.mesh as QuadMesh).size.is_equal_approx(Vector2(0.136, 0.017)),
		"label/over the edge and fitted inside it, not stretched")
	DirAccess.remove_absolute(_scratch.path_join("Home Movies spine.png"))
	tape.video_path = _scratch.path_join("Elsewhere.mp4")
	_ok(await _wait_for(func() -> bool: return tape.get_node_or_null("SpineArt") == null),
		"label/a tape moved to a video with no spine drops it")

	# ── a cassette's two faces ──
	var song := _scratch.path_join("Mix.mp3")
	_solid_png(_scratch.path_join("Mix.png"), 400, 100)
	var cas := AUDIO_CASSETTE.instantiate() as AudioCassette
	cas.album_path = song
	cas.album_label = "Mix"
	add_child(cas)
	_spawned.append(cas)
	var cas_text := cas.get_node("CassetteLabel") as Label3D
	got = await _wait_for(func() -> bool: return cas.get_node_or_null("LabelArtB") != null)
	_ok(got, "label/a cassette with one picture wears it on both faces")
	if not got:
		return
	var front := cas.get_node("LabelArt") as MeshInstance3D
	var rear := cas.get_node("LabelArtB") as MeshInstance3D
	_ok(front.position.z > 0.0 and rear.position.z < 0.0
		and rear.transform.basis.z.is_equal_approx(Vector3(0, 0, -1)),
		"label/side A faces front and side B faces back")
	_ok(cas.get_node_or_null("LabelPaperB") != null and (cas.get_node("LabelPaperB") as Node3D).position.z < 0.0,
		"label/and the back has paper to be printed on")
	_ok((front.mesh as QuadMesh).size.is_equal_approx(Vector2(0.08, 0.02))
		and (rear.mesh as QuadMesh).size.is_equal_approx(Vector2(0.08, 0.02)),
		"label/each fitted inside the 80 x 30 mm label, not stretched")
	_ok(not cas_text.visible, "label/the album's name text steps aside")
	cas.net_set_download_status("55%")
	_ok(cas_text.visible and cas_text.text == "55%", "label/a transfer's progress still shows on a cassette")
	cas.net_set_download_status("")
	_ok(not cas_text.visible and cas_text.text == "Mix", "label/and when it ends the picture is back")

	_solid_png(_scratch.path_join("Mix B.png"), 100, 200)
	cas.album_path = ""
	cas.album_path = song
	got = await _wait_for(func() -> bool:
		var b := cas.get_node_or_null("LabelArtB") as MeshInstance3D
		return b != null and (b.mesh as QuadMesh).size.is_equal_approx(Vector2(0.015, 0.03)))
	_ok(got, "label/a `Name B.png` is side B, and side A is left as it was")
	_ok((cas.get_node("LabelArt") as MeshInstance3D).mesh is QuadMesh
		and ((cas.get_node("LabelArt") as MeshInstance3D).mesh as QuadMesh).size.is_equal_approx(Vector2(0.08, 0.02)),
		"label/the two faces are two pictures")

	cas.album_path = _scratch.path_join("None.mp3")
	got = await _wait_for(func() -> bool:
		return cas.get_node_or_null("LabelArt") == null and cas.get_node_or_null("LabelArtB") == null)
	_ok(got and cas.get_node_or_null("LabelPaperB") == null and cas_text.visible,
		"label/a cassette moved to an album with none drops both faces and shows its name again")

	# Moved twice before the first decode lands: the last one wins.
	_solid_png(_scratch.path_join("Mix2.png"), 100, 200)
	cas.album_path = song
	cas.album_path = _scratch.path_join("Mix2.mp3")
	got = await _wait_for(func() -> bool:
		var a := cas.get_node_or_null("LabelArt") as MeshInstance3D
		return a != null and (a.mesh as QuadMesh).size.is_equal_approx(Vector2(0.015, 0.03)))
	_ok(got, "label/two moves in a row end on the pictures of the last")

	var doomed_cas := AUDIO_CASSETTE.instantiate() as AudioCassette
	doomed_cas.album_path = song
	add_child(doomed_cas)
	doomed_cas.free()
	await _frames(3)
	_ok(true, "label/a cassette freed while its pictures decode does not crash")

	# ── a record's two labels ──
	_solid_png(_scratch.path_join("Wide.png"), 400, 100)
	var lp := VINYL_RECORD.instantiate() as VinylRecord
	lp.album_path = _scratch.path_join("Wide.flac")
	lp.album_label = "Wide"
	add_child(lp)
	_spawned.append(lp)
	var lp_text := lp.get_node("DiscLabel") as Label3D
	# The record gives itself its own material when art arrives, so every read
	# looks the material up afresh.
	got = await _wait_for(func() -> bool: return _record_art(lp, "label_tex") != null)
	_ok(got, "label/a record with a picture beside its album wears it on its label")
	if not got:
		return
	var tex_a := _record_art(lp, "label_tex")
	_ok(tex_a.get_width() == 100 and tex_a.get_height() == 100,
		"label/cut square, since the label is round and a wide picture would be stretched over it")
	_ok(_record_art(lp, "label_tex_b") == tex_a, "label/a record with one picture has it on both sides")
	_ok(not lp_text.visible, "label/and the album's name text steps aside")
	lp.net_set_download_status("12%")
	_ok(lp_text.visible and lp_text.text == "12%", "label/a transfer's progress still shows on a record")
	lp.net_set_download_status("")
	_ok(not lp_text.visible and lp_text.text == "Wide", "label/and when it ends the picture is back")

	var plain := VINYL_RECORD.instantiate() as VinylRecord
	add_child(plain)
	_spawned.append(plain)
	await _frames(3)
	_ok(_record_mat(plain) != _record_mat(lp) and _record_art(plain, "label_tex") == null,
		"label/one record's picture is not on every record that shares the scene's material")

	_solid_png(_scratch.path_join("Wide B.png"), 200, 200)
	lp.album_path = ""
	lp.album_path = _scratch.path_join("Wide.flac")
	got = await _wait_for(func() -> bool:
		var b := _record_art(lp, "label_tex_b")
		return b != null and b.get_width() == 200)
	_ok(got, "label/a `Name B.png` is the label of the underside")
	_ok(_record_art(lp, "label_tex").get_width() == 100, "label/and side A is not it")

	lp.album_path = _scratch.path_join("None.flac")
	got = await _wait_for(func() -> bool: return _record_art(lp, "label_tex") == null)
	_ok(got and _record_art(lp, "label_tex_b") == null and lp_text.visible,
		"label/a record moved to an album with none drops both and shows its name again")

	var doomed_lp := VINYL_RECORD.instantiate() as VinylRecord
	doomed_lp.album_path = _scratch.path_join("Wide.flac")
	add_child(doomed_lp)
	doomed_lp.free()
	await _frames(3)
	_ok(true, "label/a record freed while its pictures decode does not crash")

	RomLibrary._remove_tree(_scratch)


func _record_mat(lp: VinylRecord) -> ShaderMaterial:
	return (lp.get_node("RecordMesh") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial


func _record_art(lp: VinylRecord, param: String) -> Texture2D:
	return _record_mat(lp).get_shader_parameter(param) as Texture2D


# ── playlist/ ─────────────────────────────────────────────────────────────────

## Stands in for VlcPlayer, which a headless run does not have: records what was
## opened, and answers time and length from two numbers the case sets.
class FakeVlc extends RefCounted:
	var opened: Array = []
	var time_ms := 0
	var length_ms := 0

	func open(path: String, _dvd: bool) -> bool:
		opened.append(path)
		time_ms = 0
		return true

	func get_time() -> int: return time_ms
	func get_length() -> int: return length_ms
	func set_position(f: float) -> void: time_ms = int(f * float(length_ms))
	func play() -> void: pass
	func stop() -> void: pass
	func set_volume(_v: int) -> void: pass
	func set_paused(_p: bool) -> void: pass
	func update_frame() -> void: pass
	func read_audio(_n: int) -> PackedVector2Array: return PackedVector2Array()
	func get_texture() -> Texture2D: return null
	func shutdown() -> void: pass


var _scratch := ""


func _scratch_file(rel: String, text := "x") -> String:
	var path := _scratch.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func _labels(entries: Array[Dictionary]) -> Array:
	return entries.map(func(e: Dictionary) -> String: return str(e["label"]))


## An .m3u/.m3u8 sets what plays and in what order: in an album folder it beats
## the file names, loose in music/ it is an album, loose in videos/ a tape of
## several recordings that the VCR plays, scans and keeps its place across.
## Before this a folder's playlist was ignored, and a loose one was handed to VLC
## as a track, which plays nothing.
##
## Everything lives in a scratch folder under user://, removed afterwards; the
## scans are pointed at it, never at the player's library.
func _test_playlist() -> void:
	_scratch = ProjectSettings.globalize_path("user://deck_tests_playlist")
	RomLibrary._remove_tree(_scratch)   # what a killed run left
	var a := _scratch_file("album/01 b.mp3", "1")
	var b := _scratch_file("album/02 a.mp3", "22")
	var c := _scratch_file("album/10 c.mp3", "333")
	_scratch_file("album/notes.txt")
	_eq(RomLibrary.music_tracks(_scratch.path_join("album")), PackedStringArray([a, b, c]),
		"playlist/with none, an album folder plays its files in name order")

	var o1 := _scratch_file("ordered/01 b.mp3")
	_scratch_file("ordered/02 a.mp3")
	var o10 := _scratch_file("ordered/10 c.mp3")
	_scratch_file("ordered/notes.txt")
	_scratch_file("ordered/ordered.m3u", "#EXTM3U\r\n#EXTINF:123,Ten\r\n10 c.mp3\r\n\r\n01 b.mp3\r\n"
		+ "missing.mp3\r\nhttp://example.com/live.mp3\r\nnotes.txt\r\n")
	_eq(RomLibrary.music_tracks(_scratch.path_join("ordered")), PackedStringArray([o10, o1]),
		"playlist/a playlist in the folder sets the order, leaving out what is missing, streamed or not music")

	var s1 := _scratch_file("stale/01 b.mp3")
	var s2 := _scratch_file("stale/02 a.mp3")
	_scratch_file("stale/stale.m3u", "gone.mp3\n")
	_eq(RomLibrary.music_tracks(_scratch.path_join("stale")), PackedStringArray([s1, s2]),
		"playlist/one naming nothing that is there falls back to the file names, not to silence")

	# Loose in the music root, its entries written every way a player writes them.
	var url := "file://" + ("" if a.begins_with("/") else "/") + a.replace(" ", "%20")
	var mix := _scratch_file("music/Mix.m3u8",
		String.chr(0xFEFF) + "..\\album\\10 c.mp3\n" + b + "\n" + url + "\n")
	_eq(RomLibrary.music_tracks(mix), PackedStringArray([c, b, a]),
		"playlist/a loose one is an album: relative with backslashes, absolute and file:// entries, in its order")
	_scratch_file("music/Dead.m3u", "nothing.mp3\n")
	_scratch_file("music/Solo.mp3")
	_scratch_file("music/Folder/x.mp3")
	DirAccess.make_dir_recursive_absolute(_scratch.path_join("music/Empty"))
	_scratch_file("music/Pointer/only.m3u", "../../album/02 a.mp3\n")
	_eq(_labels(RomLibrary.scan_music(_scratch.path_join("music"))), ["Folder", "Mix", "Pointer", "Solo"],
		"playlist/the music scan lists a loose playlist and a folder holding only one, not a dead one or an empty folder")
	_eq(RomLibrary.music_tracks(_scratch.path_join("music/Pointer")), PackedStringArray([b]),
		"playlist/a folder's playlist may name tracks outside it")
	var w := _scratch_file("weird/Odd.m3u/x.mp3")
	_eq(RomLibrary.music_tracks(_scratch.path_join("weird/Odd.m3u")), PackedStringArray([w]),
		"playlist/a FOLDER named like a playlist is still a folder")

	# A tape of several recordings.
	var v1 := _scratch_file("videos/a.mp4", "1")
	_scratch_file("videos/b.mkv")
	var v3 := _scratch_file("videos/sub/c.mp4", "333")
	var tape_list := _scratch_file("videos/Tape.m3u", "sub/c.mp4\na.mp4\n../album/01 b.mp3\n")
	_scratch_file("videos/NoVideo.m3u", "../album/01 b.mp3\n")
	_eq(RomLibrary.video_recordings(tape_list), PackedStringArray([v3, v1]),
		"playlist/a tape playlist is its videos in order, and only videos")
	_eq(RomLibrary.video_recordings("C:/x/one.mp4"), PackedStringArray(["C:/x/one.mp4"]),
		"playlist/a tape of one file is that file, as before")
	_eq(_labels(RomLibrary.scan_videos(_scratch.path_join("videos"))), ["a", "b", "Tape"],
		"playlist/the video scan lists a playlist naming videos as a tape, and not one naming none")

	# The VCR, on a stand-in player. Driven by hand, so its own frame does not move it.
	var vcr := await _deck(VCR_PLAYER) as VCRPlayer
	vcr.set_process(false)
	var fake := FakeVlc.new()
	vcr._vlc = fake
	var tape := VCR_TAPE.instantiate() as VCRTape
	add_child(tape)
	_spawned.append(tape)
	tape.video_path = tape_list
	tape.tape_track = 1
	tape.tape_time = 5.0
	vcr.video_path = tape_list
	vcr._take_tape_place(tape)
	_eq(vcr._rec_idx, 1, "playlist/a tape goes in at the recording it was left in")
	vcr._ensure_recordings()
	_eq(vcr._recordings, PackedStringArray([v3, v1]), "playlist/the VCR reads the tape's recordings in order")

	vcr._rec_idx = 0
	vcr._resume_at = 0.0
	vcr._open_recording()
	vcr.is_playing = true
	_eq(str(fake.opened.back()), v3, "playlist/the first recording is the one opened")
	fake.length_ms = 100000
	fake.time_ms = 50000
	vcr._note_tape()
	_ok(tape.tape_track == 0 and is_equal_approx(tape.tape_progress, 0.5 * 3.0 / 4.0),
		"playlist/half way through the first recording is that share of the tape, weighed by size")

	vcr._opened_msec = Time.get_ticks_msec()
	vcr._on_video_finished()
	_eq(vcr._rec_idx, 0, "playlist/a finish landing just after a recording opened is the last one's, and ignored")
	vcr._opened_msec = -100000
	vcr._on_video_finished()
	_ok(vcr._rec_idx == 1 and str(fake.opened.back()) == v1 and vcr.is_playing,
		"playlist/the end of a recording plays on into the next")

	vcr._scan_dir = -1
	vcr._scan_pos = 0.2
	vcr._update_scan(0.1)
	_ok(vcr._rec_idx == 0 and str(fake.opened.back()) == v3 and vcr._scan_dir == -1 and vcr._resume_end,
		"playlist/rewinding off the start of a recording winds back into the one before")
	vcr._update_scan(0.1)
	_eq(vcr._rec_idx, 0, "playlist/and waits there until it can seek")
	vcr._resume_tape()
	_ok(is_equal_approx(vcr._scan_pos, 99.0) and fake.time_ms == 99000 and not vcr._resume_pending(),
		"playlist/to just short of its end, and the rewind carries on from there")
	vcr._scan_dir = 1
	vcr._scan_pos = 99.5
	vcr._update_scan(0.1)
	_ok(vcr._rec_idx == 1 and str(fake.opened.back()) == v1 and vcr._scan_dir == 1,
		"playlist/fast-forwarding off the end of one winds on into the next, still scanning")
	vcr._scan_pos = 99.5
	vcr._update_scan(0.1)
	_ok(tape.cassette > 0 and vcr._blank and vcr._scan_dir == 1 and vcr._rec_idx == 1
		and tape.tape_track == 1 and tape.tape_progress == 1.0,
		"playlist/off the end of the last it winds on into the blank tape after it, still scanning (T-%d)" % tape.cassette)
	vcr._scan_dir = -1
	tape.tape_blank = 0.1
	vcr._run_blank(1.0)
	_ok(not vcr._blank and vcr._rec_idx == 1 and str(fake.opened.back()) == v1 and vcr._resume_end
		and tape.tape_blank == 0.0, "playlist/wound back off the blank's start, it goes back into the last recording at its end")

	vcr._scan_dir = 0
	vcr._resume_end = false
	vcr._opened_msec = -100000
	vcr.is_playing = true
	vcr._on_video_finished()
	_ok(vcr._rec_idx == 1 and tape.tape_track == 1 and is_equal_approx(tape.tape_time, 100.0)
		and tape.tape_progress == 1.0 and vcr.is_playing and vcr._blank and not vcr._tape_at_end(),
		"playlist/the end of the last recording plays on into the blank tape")
	_eq(vcr.net_get_state().get("rec", -1), 1, "playlist/a session hears which recording the deck is in")
	vcr.stop()

	tape.tape_track = 1
	tape.tape_time = 12.0
	tape.tape_progress = 0.0
	tape.tape_blank = 0.0
	_eq(tape.options_info()[1], ["Position", "Recording 2, 00:00:12"],
		"playlist/a playlist tape's menu says which recording it is in")
	var store := ScenePersistence.new()
	var back := store._deserialize_object(store._serialize_node(tape, 3, {tape: 3})) as VCRTape
	_ok(back != null and back.tape_track == 1, "playlist/a save keeps which recording a tape is in")
	if back != null:
		back.free()
	vcr._vlc = null
	RomLibrary._remove_tree(_scratch)


# ── base/ ─────────────────────────────────────────────────────────────────────

## A turntable has no FF/REW hardware at all. The base used to reach for
## $RewindButton and $FastForwardButton unconditionally, so a deck without them
## could not reach the end of _ready() — this is that regression.
func _test_base() -> void:
	var rp := await _deck(RECORD_PLAYER)
	# Asserted on the audio emitter, NOT on the node merely existing: a null access
	# in _ready aborts that FUNCTION and nothing else, so the deck is still in the
	# tree afterwards and "did it instantiate" cannot tell the two outcomes apart.
	# The emitter is built at the END of the base's _ready, past the button wiring,
	# so it is present only if _ready actually ran to completion.
	_ok(rp.get_node_or_null("SpatialAudioEmitter") != null,
		"base/a deck with no scan buttons runs _ready to completion")
	_ok(not rp.has_scan(), "base/a turntable reports no scan")
	_ok(rp.has_track_skip(), "base/...but keeps track skip, which the needle can do")

	var cd := await _deck(CD_PLAYER)
	_ok(cd.has_scan(), "base/a CD deck does have scan")
	_ok(cd.has_track_skip(), "base/a CD deck has track skip")

	var tape := await _deck(CASSETTE_PLAYER)
	_ok(tape.has_scan(), "base/a cassette has scan")
	_ok(not tape.has_track_skip(), "base/a cassette has no track skip — it is linear")

	# The scan handlers must refuse as well, or a TV remote and a stale peer's "ff"
	# would still scan a deck that physically cannot.
	rp._scan_dir = 0
	rp.remote_ff()
	rp.remote_rewind()
	_eq(rp._scan_dir, 0, "base/remote ff/rew cannot scan a deck with no scan")

	# THE LASER CAN PICK EVERY DECK UP. The turntable shipped without a PointerArea:
	# a hand could lift it and the ray went straight through, because the pointer's
	# RayCast masks the pointable layers and a deck's own body is on neither. A real
	# ray on the pointer's own mask, from the side so no button is in the way, resolved
	# the way function_pickup._resolve_pickable does — the collider or its parent.
	var lane := 0
	for spec: Array in [[rp, "the turntable"], [cd, "the CD deck"], [tape, "the cassette deck"]]:
		var deck: RigidBody3D = spec[0]
		lane += 1
		deck.global_position = Vector3(40.0, 50.0, 5.0 * lane)   # clear of each other
		deck.freeze = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		var q := PhysicsRayQueryParameters3D.create(
			deck.global_position + Vector3(2.0, 0.0, 0.0), deck.global_position,
			XRToolsFunctionPointer.DEFAULT_MASK)
		var hit := deck.get_world_3d().direct_space_state.intersect_ray(q)
		var collider := hit.get("collider") as Node3D
		var resolved: XRToolsPickable = null
		if collider != null:
			resolved = collider as XRToolsPickable
			if resolved == null:
				resolved = collider.get_parent() as XRToolsPickable
		_ok(resolved == deck, "base/the laser finds %s and resolves it to the deck" % spec[1])


# ── save/ ─────────────────────────────────────────────────────────────────────

## The serializer used to read `"cd_player" if node is CDPlayer else
## "cassette_player"`, whose else-arm swallowed every future deck: a turntable was
## saved as, and restored as, a cassette machine. Three decks must give three
## distinct strings.
func _test_save_types() -> void:
	var rp := await _deck(RECORD_PLAYER)
	var cd := await _deck(CD_PLAYER)
	var tape := await _deck(CASSETTE_PLAYER)
	_eq(cd.deck_save_type(), "cd_player", "save/CD deck saves as cd_player")
	_eq(tape.deck_save_type(), "cassette_player", "save/cassette saves as cassette_player")
	_eq(rp.deck_save_type(), "record_player", "save/turntable saves as record_player")

	# Through the REAL serializer, not just the virtual — the bug lived in
	# _serialize_node's type expression, so a case that only asked each deck for its
	# own answer would stay green with the fault fully restored.
	var persistence := ScenePersistence.new()
	var types := {}
	for d: Node in [rp, cd, tape]:
		var entry: Dictionary = persistence._serialize_node(d, 1, {})
		var t := str(entry.get("type", ""))
		types[t] = true
		_eq(t, d.deck_save_type(),
			"save/the serializer writes %s's own type" % d.deck_save_type())
		_ok(persistence.PLAIN_SCENES.has(t), "save/%s is restorable" % t)
	_eq(types.size(), 3, "save/three decks serialize to three distinct types")


# ── media/ ────────────────────────────────────────────────────────────────────

## A record has to survive three separate `is` chains to exist at all. The netplay
## one is the dangerous one: it fails SILENTLY — the record drops out of the content
## manifest, verify-by-name never runs, and clients are simply mute with no error.
func _test_media_guards() -> void:
	var lp := VINYL_RECORD.instantiate() as VinylRecord
	lp.album_path = "/nowhere/Some Album"
	lp.album_label = "Some Album"
	add_child(lp)
	_spawned.append(lp)
	await get_tree().process_frame

	_ok(lp.is_in_group("vinyl_record"), "media/a record is in the vinyl_record group")
	_eq(lp.get_album_path(), "/nowhere/Some Album", "media/a record reports its album")

	var sync := NetObjectSync.new()
	var desc: Dictionary = sync._file_desc(lp)
	_eq(str(desc.get("kind", "")), "music", "media/net treats a record as music")
	_eq(str(desc.get("prop", "")), "album_path", "media/...keyed on album_path")
	sync.free()

	# The label hook the transfer UI writes through.
	lp.net_set_download_status("42%")
	_eq((lp.get_node("DiscLabel") as Label3D).text, "42%", "media/status shows on the label")
	lp.net_set_download_status("")
	_eq((lp.get_node("DiscLabel") as Label3D).text, "Some Album", "media/...and clears back")


# ── gate/ ─────────────────────────────────────────────────────────────────────

## MediaTray's access matrix, which is what the tonearm now drives: the well accepts
## a record only while open AND empty (or it re-detects the one it is holding), and
## a seated record is liftable only while open. Four combinations, all four asserted
## — the turntable's whole "you cannot lift a record out from under a playing
## needle" behaviour is this table and nothing else.
func _test_gate_matrix() -> void:
	var rp := await _deck(RECORD_PLAYER)
	var tray: MediaTray = rp._tray
	_ok(tray != null, "gate/the turntable built a tray")

	# A freshly spawned deck must be OPEN. MediaTray starts closed, which for a
	# turntable is backwards — it would leave a locked platter no record could go on.
	_ok(tray.is_open(), "gate/a fresh turntable's platter is open")
	_ok(tray.slot.enabled, "gate/...and its well accepts a record")
	_ok(not tray.has_media(), "gate/...and is empty")

	var lp := await _seat(rp)
	_ok(tray.has_media(), "gate/open + record dropped in = seated")
	_ok(not tray.slot.enabled, "gate/open + full: the well stops accepting")
	_ok(lp.enabled, "gate/open + full: the record is liftable")
	_ok(not tray.can_spin(), "gate/open + full: needle up, so it does not spin")

	tray.set_open(false, false)
	_ok(not tray.slot.enabled, "gate/shut + full: the well accepts nothing")
	_ok(not lp.enabled, "gate/shut + full: the record is LOCKED under the needle")
	_ok(tray.can_spin(), "gate/shut + full: the needle is down")

	# And a hand-free unseat, which is what the net layer's remove event needs.
	# Reaching for the snap zone here unseats nothing: the tray took ownership and
	# reparented the record out of the zone when it accepted it.
	rp.remove_media()
	await get_tree().process_frame
	_ok(not tray.has_media(), "gate/remove_media unseats a tray deck")
	_ok(tray.is_open(), "gate/...leaving the platter open again")

	await _test_lid_travel()


## The CD deck's lid ANIMATES, which the turntable's never does, and the gates and
## the spin part company while it is moving: `_open` goes false the instant the
## button is pressed, because that is when the well seals and the disc stops being
## liftable. A spin keyed off that alone started the disc turning while the lid was
## still coming down over it. `set_open(false, false)` — the restore path the cases
## above take — creates no tween and so cannot see this.
func _test_lid_travel() -> void:
	var cd := await _deck(CD_PLAYER)
	var tray: MediaTray = cd._tray
	_ok(tray != null and tray.lid_pivot != null, "gate/the CD deck's lid animates")
	tray.lid_time = 0.2

	tray.set_open(true, false)
	var disc := AUDIO_DISC.instantiate() as AudioDisc
	disc.album_path = "/nowhere/Some Album"
	add_child(disc)
	_spawned.append(disc)
	await get_tree().process_frame
	cd.restore_media(disc)
	await get_tree().process_frame
	_ok(tray.has_media(), "gate/a disc is in the CD deck's well")
	_ok(not tray.can_spin(), "gate/lid up over a disc: no spin")

	tray.set_open(false)
	await get_tree().process_frame
	_ok(not tray.is_open(), "gate/the button seals the well at once")
	_ok(not tray.can_spin(), "gate/...but a lid still coming down does not spin")
	await get_tree().create_timer(tray.lid_time + 0.1).timeout
	_ok(tray.can_spin(), "gate/...and it does once the lid is home")


# ── arm/ ──────────────────────────────────────────────────────────────────────

func _test_arm() -> void:
	var rp := await _deck(RECORD_PLAYER)
	var arm: VRLever = rp._arm
	_ok(arm != null, "arm/the turntable has a tonearm lever")
	_ok(arm.target != null, "arm/...with a pivot to turn")

	# The mount's basis is what makes a tonearm swing about VERTICAL rather than
	# tipping over. VRHinge turns about the PIVOT's local X, so that axis has to
	# come out along the deck's up. Checked as a printed axis rather than by
	# looking at it: an empty arc is symmetric and reads correct either way round.
	var pivot := arm.target as Node3D
	var axis: Vector3 = pivot.global_transform.basis.x.normalized()
	var up: Vector3 = rp.global_transform.basis.y.normalized()
	_ok(absf(axis.dot(up)) > 0.99,
		"arm/the hinge axis is the deck's up (got %.3f)" % axis.dot(up))

	# Parked vs cued, and the gate that follows from it.
	arm.set_value_no_signal(0.0)
	_ok(rp._arm_parked(), "arm/value 0 is parked")
	arm.set_value_no_signal(1.0)
	_ok(not rp._arm_parked(), "arm/value 1 is over the record")

	# Track mapping across the playable band.
	rp._tracks = PackedStringArray(["a.mp3", "b.mp3", "c.mp3", "d.mp3"])
	_eq(rp._track_at(rp.arm_lead_in), 0, "arm/the outer edge is track 1")
	_eq(rp._track_at(rp.arm_lead_out), 3, "arm/the run-out is the last track")
	var mid: int = rp._track_at((rp.arm_lead_in + rp.arm_lead_out) * 0.5)
	_ok(mid == 1 or mid == 2, "arm/halfway lands mid-album (got %d)" % mid)
	# Landing anywhere in the parked zone must never index a track.
	_eq(rp._track_at(0.0), 0, "arm/a parked arm clamps to the first track")

	# THE DISCRIMINATOR. Restoring a room calls VRLever.set_value(), which EMITS
	# value_changed. A deck that dropped the needle on value_changed would treat
	# every save-load as someone starting the record — and broadcast it to the room.
	# released() is emitted only by a real hand letting go.
	rp._track_idx = 0
	var seen_cmd := false
	rp._tracks = PackedStringArray(["a.mp3", "b.mp3", "c.mp3", "d.mp3"])
	arm.set_value(1.0)          # what a restore does
	await get_tree().process_frame
	_eq(rp._track_idx, 0, "arm/a RESTORE moving the arm does not select a track")
	_ok(not seen_cmd, "arm/...and reports nothing to the room")
	# ...whereas a real release does.
	arm.released.emit(1.0)
	await get_tree().process_frame
	_eq(rp._track_idx, 3, "arm/a real release DOES drop the needle on that band")

	# Parking the arm shuts the well again, and that IS the restore path, so it has
	# to happen on value_changed rather than only on release.
	arm.set_value(0.0)
	await get_tree().process_frame
	_ok(rp._tray.is_open(), "arm/parking the arm opens the platter")

	# DESKTOP GRAB. In VR these widgets engage a fingertip by proximity to their own
	# origin and need no collision shape at all — which is exactly why this shipped
	# broken and neither a headless case nor a render could see it. The desktop
	# reticle is an intersect_ray against the pointable layer, and a ray cannot hit a
	# shapeless Area3D, so without a shape the arm simply cannot be grabbed on a
	# desktop. Asserted on both widgets a hand has to reach.
	for spec: Array in [[arm, "the tonearm"], [rp._speed_switch, "the 33/45 switch"]]:
		var w: Area3D = spec[0]
		var label: String = spec[1]
		_ok(w != null and (w.collision_layer & (1 << 20)) != 0,
			"arm/%s is on the pointable layer" % label)
		var shaped := false
		for child in w.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
				shaped = true
		_ok(shaped, "arm/%s has a shape a desktop ray can hit" % label)

	# A DETENT SWITCH MUST BE FLIPPABLE BOTH WAYS by a pointer, and this drives the
	# real thing rather than asserting a proxy for it. An earlier version of this
	# case checked only that the grab box was wider than the throw — which is
	# necessary, is documented in _update_knob, and was TRUE of a switch that still
	# could not be flipped back, because the box's REST POSE was also wrong. A
	# precondition that holds while the feature is broken is not a test of the
	# feature. So: press where a ray could actually land, and read the value.
	var sw: VRSlider = rp._speed_switch
	if sw != null and sw.steps >= 2:
		sw.set_value_no_signal(0.0)
		await get_tree().process_frame
		_eq(_press_at(sw, _reach(sw, 1.0)), 1.0, "arm/a pointer can throw the speed switch to 45")
		_eq(_press_at(sw, _reach(sw, -1.0)), 0.0, "arm/...and can throw it BACK to 33")
		# And back again, so a working one-way flip cannot pass either.
		_eq(_press_at(sw, _reach(sw, 1.0)), 1.0, "arm/the switch keeps flipping both ways")

		# The switch now drives playback as well as the platter. VlcPlayer does not
		# exist headless, so what is asserted is the rate the deck ASKS for — the
		# push itself is one guarded call, and the binding was measured separately
		# (ZCR 1.338 against this 1.35, i.e. the pitch really bends).
		_ok(absf(rp.playback_rate() - RecordPlayer.RATE_45) < 0.001,
			"arm/at 45 the deck asks for %.2fx" % RecordPlayer.RATE_45)
		_press_at(sw, _reach(sw, -1.0))
		_ok(absf(rp.playback_rate() - 1.0) < 0.001, "arm/at 33 it asks for 1.00x")


# ── scrub/ ────────────────────────────────────────────────────────────────────

## THE PITCH FOLLOWS THE PLATTER. Not the speed switch — the platter, which ramps
## toward it, coasts down after STOP and is dragged by a hand on the record. So one
## rule covers the start-up glide, the coast-down, the 33/45 bend and the hand
## brake, and this asserts the rule rather than each of the four.
##
## The rate the deck ASKS for is what is checked: VlcPlayer does not exist headless,
## so nothing can be heard here. That the ask is honoured, and bends pitch rather
## than preserving it, was measured separately against a real file (ZCR 0.04488 at
## 1.00x against 0.06006 at 1.35x — a ratio of 1.338 for a requested 1.35).
func _test_scrub() -> void:
	var rp := await _deck(RECORD_PLAYER)
	rp._tracks = PackedStringArray(["a.mp3", "b.mp3"])

	# The two speeds are one relationship, not two numbers: 45 rpm over 33 1/3 IS
	# the rate. A platter speed edited without the rate would be caught here.
	_ok(absf(RecordPlayer.SPEED_45 / RecordPlayer.SPEED_33 - RecordPlayer.RATE_45) < 0.001,
		"scrub/the platter speeds and the playback rate agree (%.3f)"
			% (RecordPlayer.SPEED_45 / RecordPlayer.SPEED_33))

	# At rest the deck settles at the selected speed.
	rp._speed_45 = false
	_ok(absf(rp.playback_rate() - 1.0) < 0.001, "scrub/33 settles at 1.00x")
	rp._speed_45 = true
	_ok(absf(rp.playback_rate() - RecordPlayer.RATE_45) < 0.001,
		"scrub/45 settles at %.2fx" % RecordPlayer.RATE_45)
	rp._speed_45 = false

	# ...but what is PLAYED is the platter's speed right now, which is a different
	# number while it is spinning up, braked or dragged.
	rp._platter_omega = RecordPlayer.SPEED_33
	_ok(absf(rp.current_rate() - 1.0) < 0.001, "scrub/a platter at 33 plays at 1.00x")
	rp._platter_omega = RecordPlayer.SPEED_45
	_ok(absf(rp.current_rate() - RecordPlayer.RATE_45) < 0.001,
		"scrub/a platter at 45 plays at %.2fx" % RecordPlayer.RATE_45)

	# A hand dragging it faster than the motor bends the note UP...
	rp._platter_omega = RecordPlayer.SPEED_33 * 1.5
	_ok(rp.current_rate() > 1.4, "scrub/dragged fast, the note bends up (%.2fx)"
		% rp.current_rate())
	# ...and braking it drops the rate under the floor, which is where the sound
	# stops rather than libVLC being asked for a rate of nothing.
	rp._platter_omega = RecordPlayer.SPEED_33 * 0.05
	_ok(rp.current_rate() < RecordPlayer.RATE_MIN,
		"scrub/a braked record falls below the audible floor (%.2fx)" % rp.current_rate())
	rp._platter_omega = 0.0
	_ok(rp.current_rate() < RecordPlayer.RATE_MIN, "scrub/a stopped platter is silent")

	# Spinning up from rest passes through the floor and comes out at speed, which
	# is the glide that stops the switch from clicking.
	rp._platter_omega = RecordPlayer.SPEED_33 * 0.5
	_ok(rp.current_rate() > RecordPlayer.RATE_MIN and rp.current_rate() < 1.0,
		"scrub/half speed is audible and low (%.2fx)" % rp.current_rate())


# ── net/ ──────────────────────────────────────────────────────────────────────

## The command vocabulary the host will act on. "track" is the new one and is the
## only one carrying an index; the match it lands in deliberately has no default
## arm, so an older host no-ops on it rather than misfiring as something else.
func _test_net() -> void:
	var rp := await _deck(RECORD_PLAYER)
	rp._tracks = PackedStringArray(["a.mp3", "b.mp3", "c.mp3", "d.mp3"])

	rp._track_idx = 0
	rp.remote_goto_track(2)
	_eq(rp._track_idx, 2, "net/remote_goto_track selects that track")

	# The index a peer that predates the command leaves absent, defaulted to -1.
	rp._track_idx = 2
	rp.remote_goto_track(-1)
	_eq(rp._track_idx, 2, "net/a missing index is ignored, not treated as track 0")
	rp.remote_goto_track(99)
	_eq(rp._track_idx, 2, "net/an out-of-range index is ignored")

	# Every deck must answer the whole remote_* vocabulary the event handler calls,
	# or a command from a peer is a crash rather than a no-op.
	var cd := await _deck(CD_PLAYER)
	var tape := await _deck(CASSETTE_PLAYER)
	for deck: Node in [rp, cd, tape]:
		var ok := true
		for m: String in ["remote_play", "remote_pause", "remote_stop", "remote_ff",
				"remote_rewind", "remote_next", "remote_prev", "remote_goto_track",
				"remove_media", "deck_save_type"]:
			if not deck.has_method(m):
				ok = false
				print("[test]      %s is missing %s" % [deck.get_class(), m])
		_ok(ok, "net/%s answers the whole command vocabulary" % deck.deck_save_type())


# ── remote/ ───────────────────────────────────────────────────────────────────

## The TV remote greys a cell a deck cannot honour. It already did that for
## prev/next; rew/ff had no such gate, so a turntable would have shown two live
## scan keys that do nothing.
func _test_remote() -> void:
	var remote := preload("res://Scenes/Objects/appliances/tv_remote.tscn").instantiate()
	add_child(remote)
	_spawned.append(remote)
	await get_tree().process_frame

	# Built before the loop, not inline in the array literal: awaiting inside one
	# segfaults the run on shutdown (it cost the net group an exit 139).
	var rp := await _deck(RECORD_PLAYER)
	var cd := await _deck(CD_PLAYER)
	var tape := await _deck(CASSETTE_PLAYER)
	for spec: Array in [[rp, false, true], [cd, true, true], [tape, true, false]]:
		var deck: Node = spec[0]
		remote._target = deck
		var name: String = deck.deck_save_type()
		_eq(remote._cell_enabled("ff"), spec[1], "remote/%s ff cell" % name)
		_eq(remote._cell_enabled("rew"), spec[1], "remote/%s rew cell" % name)
		_eq(remote._cell_enabled("next"), spec[2], "remote/%s next cell" % name)
		_eq(remote._cell_enabled("prev"), spec[2], "remote/%s prev cell" % name)
		_ok(remote._cell_enabled("stop"), "remote/%s stop cell is always live" % name)


# ── helpers ───────────────────────────────────────────────────────────────────

func _deck(scene: PackedScene) -> Node:
	var d := scene.instantiate()
	add_child(d)
	_spawned.append(d)
	await get_tree().process_frame
	return d


## Drop a record into a deck's well the way the snap zone does — through the tray's
## own accept path, which is what a released record reaches.
func _seat(rp: Node) -> Node:
	var lp := VINYL_RECORD.instantiate() as VinylRecord
	lp.album_path = "/nowhere/Some Album"
	add_child(lp)
	_spawned.append(lp)
	await get_tree().process_frame
	rp.restore_media(lp)
	await get_tree().process_frame
	return lp


## Every deck builds a SpatialAudioEmitter, and one of those still alive when the
## process quits segfaults the exit: Godot tears the AudioServer down AFTER it has
## unregistered the extension classes the emitter's backend belongs to. queue_free
## alone is not enough — it is deferred, so without the frames below the decks are
## still standing at quit and the run exits 139 with every case passed.
## The furthest point along the travel axis, in the slider's own frame, that a ray
## could actually hit RIGHT NOW — the grab box's leading face where it currently
## sits. `dir` is +1 for the far end of the throw, -1 for the near one. This is the
## whole point of the case: a pointer cannot aim at the slot, only at the box, so
## the reachable set moves with the knob.
func _reach(sw: VRSlider, dir: float) -> Vector3:
	var axis := sw.axis_local.normalized()
	var half := 0.0
	var centre := Vector3.ZERO
	for child in sw.get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		centre = cs.position
		var box := cs.shape as BoxShape3D
		if box != null:
			half = absf((box.size * 0.5).dot(axis))
	return centre + axis * half * dir


## Press the pointer at a point in the slider's local frame, and report the value it
## settled on. Exactly what XRToolsPointerEvent.pressed delivers on a desktop click.
func _press_at(sw: VRSlider, local_point: Vector3) -> float:
	var at := sw.to_global(local_point)
	sw.pointer_event(XRToolsPointerEvent.new(
		XRToolsPointerEvent.Type.PRESSED, null, sw, at, at))
	sw.pointer_event(XRToolsPointerEvent.new(
		XRToolsPointerEvent.Type.RELEASED, null, sw, at, at))
	return sw.value


func _cleanup() -> void:
	for n in _spawned:
		if not is_instance_valid(n):
			continue
		# remove_child THEN free, rather than queue_free: this runs the emitter's
		# _exit_tree here and now, so its voices are destroyed at a moment we
		# control. Deferred, they were still being torn down as the process quit
		# and the run exited 139 about one time in three, with every case passed.
		var parent := n.get_parent()
		if parent:
			parent.remove_child(n)
		n.free()
	_spawned.clear()
	for i in 4:
		await get_tree().process_frame
	# Let the audio backend settle before the engine starts unregistering the
	# extension classes its voices live in.
	await get_tree().create_timer(0.25).timeout


func _want(name: String) -> bool:
	return _only.is_empty() or _only == name


func _ok(cond: bool, what: String) -> void:
	_ran += 1
	if cond:
		print("[test] ok   %s" % what)
	else:
		_fail += 1
		print("[test] FAIL %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, got, want])
