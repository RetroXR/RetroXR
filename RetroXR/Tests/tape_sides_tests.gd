## Side A and side B of a cassette or an LP: where an album's playlist puts side B (`#SIDE B`), how the sides are laid
## out (TapeSides), which side goes in (MediaSide), and the two decks playing it.
##
##   godot --headless --path RetroXR res://Tests/tape_sides_tests.tscn
##   godot --headless --path RetroXR res://Tests/tape_sides_tests.tscn -- --only=deck
##
## Groups:
##   marker/  `#SIDE B` cuts a playlist into its sides (any case, `#SIDE: B` too, `#SIDE A` read as nothing); a missing
##            file does not move the cut; no playlist or no marker: every track on side A, side B blank; a loose
##            playlist album and a folder one alike
##   model/   TapeSides: the shortest C46 / C60 / C90 / C120 that holds the longer side, locate / time_of round trips,
##            the blank past the last track, and one place for the tape: 60 % into side A is 40 % into side B
##   seat/    a cassette let go side B out is seated turned half round about its upright, an LP put down upside down
##            turned over about X; a restore seats the side it is told
##   deck/    the cassette deck plays the side facing out: its tracks, its tape length, the tape's place across a
##            flip, the blank run after the side's last track and its end, FF / REW through the blank, an empty side
##            all blank, the spindles on the hubs that stand on them, the counter and the display per side
##   record/  the record player plays the side up; the arm's band is the longer side's music by length, and a shorter
##            side's run-out plays nothing
##   save/    a deck saves the side in play and a cassette the side its place is on; an old save loads as side A
##   net/     the insert event carries the side, and a peer's assembled album writes `#SIDE B` back into its playlist
extends "res://Tests/test_suite.gd"

const CASSETTE_PLAYER := preload("res://Scenes/Objects/appliances/cassette_player.tscn")
const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")
const AUDIO_CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const VINYL_RECORD := preload("res://Scenes/Objects/media/vinyl_record.tscn")

const SCRATCH := "user://tape_sides_tests"

var _only := ""
var _spawned: Array[Node] = []


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


func _ready() -> void:
	suite_tag = "sides"
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[sides] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.split("=")[1]
	MusicLengths.test_mode = true
	_clear_scratch()
	for c: Array in [["marker", _t_marker], ["model", _t_model], ["seat", _t_seat], ["deck", _t_deck],
			["record", _t_record], ["save", _t_save], ["net", _t_net]]:
		if not _only.is_empty() and not String(c[0]).begins_with(_only):
			continue
		await (c[1] as Callable).call()
		for n in _spawned:
			if is_instance_valid(n):
				n.queue_free()
		_spawned.clear()
		await get_tree().process_frame
	_clear_scratch()
	_finish()


func _clear_scratch() -> void:
	if DirAccess.dir_exists_absolute(SCRATCH):
		OS.move_to_trash(ProjectSettings.globalize_path(SCRATCH))


func _file(rel: String, text := "x") -> String:
	var path := SCRATCH.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


## An album folder `name` holding `tracks` ({file: seconds}, in play order) and, with `side_b_at` >= 0, a playlist
## whose `#SIDE B` line stands before that track. The lengths are given to MusicLengths as measured.
func _album(name: String, tracks: Array, side_b_at: int) -> String:
	var lines := PackedStringArray(["#EXTM3U"])
	for i in tracks.size():
		var row: Array = tracks[i]
		var path := _file(name.path_join(str(row[0])), "audio %d" % i)
		MusicLengths.remember(path, float(row[1]))
		if i == side_b_at:
			lines.append("#SIDE B")
		lines.append(str(row[0]))
	if side_b_at >= 0:
		_file(name.path_join("order.m3u8"), "\n".join(lines) + "\n")
	return SCRATCH.path_join(name)


func _names(paths: PackedStringArray) -> Array:
	var out: Array = []
	for p in paths:
		out.append(p.get_file())
	return out


# ── marker/ ───────────────────────────────────────────────────────────────────

func _t_marker() -> void:
	var album := _album("Marked", [["a.ogg", 60], ["b.ogg", 60], ["c.ogg", 60], ["d.ogg", 60]], 2)
	var sides := RomLibrary.music_sides(album)
	_ok(_names(sides["a"]) == ["a.ogg", "b.ogg"] and _names(sides["b"]) == ["c.ogg", "d.ogg"] and bool(sides["marked"]),
		"marker/#SIDE B cuts the playlist: A a b, B c d (%s | %s)" % [_names(sides["a"]), _names(sides["b"])])
	_ok(RomLibrary.music_tracks(album).size() == 4, "marker/the album's track list (the CD's) is the whole album")
	var spellings := ["#SIDE B", "#side b", "  #Side B  ", "#SIDE: B", "#SIDE:B"]
	var read := spellings.map(func(l: String) -> String: return RomLibrary.playlist_side_marker(l))
	_ok(read == ["B", "B", "B", "B", "B"], "marker/any case and `#SIDE: B` read as the marker (%s)" % [read])
	_ok(RomLibrary.playlist_side_marker("#SIDE A") == "A" and RomLibrary.playlist_side_marker("#EXTINF:12,x") == ""
		and RomLibrary.playlist_side_marker("#SIDEBAR") == "", "marker/#SIDE A is side A's, other comments nothing")
	# A missing file before the marker is dropped from the list; the cut still falls before c.
	var gap := _album("Gap", [["a.ogg", 60], ["c.ogg", 60]], -1)
	_file("Gap/order.m3u8", "#EXTM3U\na.ogg\ngone.ogg\n#SIDE B\nc.ogg\n")
	var gs := RomLibrary.music_sides(gap)
	_ok(_names(gs["a"]) == ["a.ogg"] and _names(gs["b"]) == ["c.ogg"],
		"marker/a missing file does not move the cut (%s | %s)" % [_names(gs["a"]), _names(gs["b"])])
	# No playlist: every track on side A.
	var plain := _album("Plain", [["a.ogg", 60], ["b.ogg", 60]], -1)
	var ps := RomLibrary.music_sides(plain)
	_ok((ps["a"] as PackedStringArray).size() == 2 and (ps["b"] as PackedStringArray).is_empty() and not bool(ps["marked"]),
		"marker/with no playlist every track is side A's and side B is blank")
	# A playlist with no marker: the same.
	var unmarked := _album("Unmarked", [["a.ogg", 60], ["b.ogg", 60]], -1)
	_file("Unmarked/order.m3u8", "#EXTM3U\nb.ogg\na.ogg\n")
	var us := RomLibrary.music_sides(unmarked)
	_ok(_names(us["a"]) == ["b.ogg", "a.ogg"] and (us["b"] as PackedStringArray).is_empty(),
		"marker/a playlist with no #SIDE B: its order, all on side A")
	# A loose playlist is an album of its own, and may mark its side B too.
	var loose := _file("Loose.m3u8", "Marked/a.ogg\n#SIDE B\nMarked/d.ogg\n")
	var ls := RomLibrary.music_sides(loose)
	_ok(_names(ls["a"]) == ["a.ogg"] and _names(ls["b"]) == ["d.ogg"], "marker/a loose playlist album marks its side B too")
	# A marker after the last track: side B blank, but marked.
	_file("Unmarked/order.m3u8", "#EXTM3U\nb.ogg\na.ogg\n#SIDE B\n")
	var tail := RomLibrary.music_sides(unmarked)
	_ok((tail["b"] as PackedStringArray).is_empty() and (tail["a"] as PackedStringArray).size() == 2,
		"marker/#SIDE B after the last track leaves side B blank")


# ── model/ ────────────────────────────────────────────────────────────────────

func _t_model() -> void:
	_eq(TapeSides.tape_minutes(20 * 60, 18 * 60), 46.0, "model/20 and 18 minutes of music go on a C46")
	_eq(TapeSides.tape_minutes(23 * 60 + 10, 0), 60.0, "model/a side just over 23 minutes needs a C60")
	_eq(TapeSides.tape_minutes(44 * 60, 40 * 60), 90.0, "model/44 minutes a side: a C90")
	_eq(TapeSides.tape_minutes(59 * 60, 0), 120.0, "model/59 minutes: a C120")
	_eq(TapeSides.tape_minutes(70 * 60, 0), 141.0, "model/past a C120, the side's own length rounded up")
	_eq(TapeSides.side_s(60.0), 1800.0, "model/a C60's side is 30 minutes")
	var lens := PackedFloat64Array([100.0, 50.0, 30.0])
	var at: Dictionary = TapeSides.locate(lens, 120.0)
	_ok(int(at["track"]) == 1 and is_equal_approx(float(at["into"]), 20.0) and float(at["blank"]) < 0.0,
		"model/120 s in is 20 s into track 2 (%s)" % [at])
	var blank: Dictionary = TapeSides.locate(lens, 200.0)
	_ok(int(blank["track"]) == 3 and is_equal_approx(float(blank["blank"]), 20.0), "model/past the last track is blank (%s)" % [blank])
	_eq(TapeSides.time_of(lens, 1, 20.0), 120.0, "model/and back")
	_eq(TapeSides.time_of(lens, 3, 20.0), 200.0, "model/and from the blank")
	var empty: Dictionary = TapeSides.locate(PackedFloat64Array(), 30.0)
	_ok(int(empty["track"]) == 0 and is_equal_approx(float(empty["blank"]), 30.0), "model/a side with no tracks is all blank")
	var pos := TapeSides.pos_of(0, 0.6 * 1800.0, 1800.0)
	_ok(is_equal_approx(TapeSides.side_time(pos, 1, 1800.0), 0.4 * 1800.0),
		"model/one place for the tape: 60 %% into side A is 40 %% into side B")
	_ok(is_equal_approx(TapeSides.pos_of(1, 0.0, 1800.0), 1.0) and is_equal_approx(TapeSides.pos_of(1, 1800.0, 1800.0), 0.0),
		"model/side B starts where side A ends")


# ── seat/ ─────────────────────────────────────────────────────────────────────

## A cassette let go side B out, by hand: its basis relative to the slot's holder turned half round about Y.
func _let_go_flipped(media: Node3D, holder: Node3D, axis: Vector3) -> void:
	media.set("_release_basis", holder.global_basis.orthonormalized() * Basis(axis, PI))


func _t_seat() -> void:
	var deck := CASSETTE_PLAYER.instantiate() as CassettePlayer
	add_child(deck)
	_spawned.append(deck)
	await get_tree().process_frame
	deck.set_process(false)
	deck._vlc = FakeVlc.new()
	var slot: MediaSlot = deck._slot
	var holder: Node3D = slot.get("_holder")
	var tape := AUDIO_CASSETTE.instantiate() as AudioCassette
	tape.album_path = _album("Seat", [["s.ogg", 60]], 1)
	add_child(tape)
	_spawned.append(tape)
	await get_tree().process_frame
	_let_go_flipped(tape, holder, Vector3.UP)
	slot._accept(tape, false)
	_ok(slot.seated_side == 1 and slot.seat_basis().z.z < -0.99 and slot.seat_basis().y.y > 0.99,
		"seat/a cassette let go side B out is seated turned about its upright (z %s)" % slot.seat_basis().z)
	_eq(deck.side_playing(), 1, "seat/and the deck plays side B")
	var side_a: Array = await _cassette_in(_album("Seat", [["s.ogg", 60]], -1), 0)
	var slot_a: MediaSlot = (side_a[0] as CassettePlayer)._slot
	_ok(slot_a.seated_side == 0 and slot_a.seat_basis().z.z > 0.99, "seat/let go side A out, it goes in as authored")
	var lp := VINYL_RECORD.instantiate() as VinylRecord
	var rp := RECORD_PLAYER.instantiate() as RecordPlayer
	add_child(rp)
	_spawned.append(rp)
	add_child(lp)
	_spawned.append(lp)
	await get_tree().process_frame
	rp.set_process(false)
	var tray: MediaTray = rp._tray
	_let_go_flipped(lp, tray.get("_holder"), Vector3.RIGHT)
	tray._accept(lp, true)
	_ok(tray.seated_side == 1 and lp.transform.basis.y.y < -0.99,
		"seat/an LP put down upside down lies side B up (its +Y %s)" % lp.transform.basis.y)
	_eq(rp.side_playing(), 1, "seat/and the turntable plays side B")
	var lp2 := VINYL_RECORD.instantiate() as VinylRecord
	var rp2 := RECORD_PLAYER.instantiate() as RecordPlayer
	add_child(rp2)
	_spawned.append(rp2)
	add_child(lp2)
	_spawned.append(lp2)
	await get_tree().process_frame
	rp2.restore_media(lp2, 0.0, 1)
	_ok(rp2._tray.seated_side == 1 and lp2.transform.basis.y.y < -0.99, "seat/a restore seats the side it is told")


# ── deck/ ─────────────────────────────────────────────────────────────────────

## A cassette deck with a stand-in libVLC and `album` going in with `side` out. Returns [deck, tape, fake].
func _cassette_in(album: String, side: int, tape: AudioCassette = null) -> Array:
	var deck := CASSETTE_PLAYER.instantiate() as CassettePlayer
	add_child(deck)
	_spawned.append(deck)
	await get_tree().process_frame
	deck.set_process(false)
	var fake := FakeVlc.new()
	deck._vlc = fake
	if tape == null:
		tape = AUDIO_CASSETTE.instantiate() as AudioCassette
		tape.album_path = album
		add_child(tape)
		_spawned.append(tape)
		await get_tree().process_frame
	var holder: Node3D = deck._slot.get("_holder")
	tape.set("_release_basis", holder.global_basis.orthonormalized() * (Basis(Vector3.UP, PI) if side == 1 else Basis.IDENTITY))
	deck._slot._accept(tape, false)
	return [deck, tape, fake]


func _t_deck() -> void:
	# Side A 600 + 500 s, side B 1200 s: a C46 (23 minutes a side, 1380 s).
	var album := _album("Deck", [["a1.ogg", 600], ["a2.ogg", 500], ["b1.ogg", 1200]], 2)
	var got: Array = await _cassette_in(album, 0)
	var deck: CassettePlayer = got[0]
	var tape: AudioCassette = got[1]
	var fake: FakeVlc = got[2]
	_ok(deck.side_playing() == 0 and _names(deck._tracks) == ["a1.ogg", "a2.ogg"], "deck/side A out: side A's tracks")
	_ok(is_equal_approx(tape.tape_minutes, 46.0) and is_equal_approx(deck._side_len, 1380.0),
		"deck/the album's longer side (1200 s) goes on a C46 (%.0f, side %.0f s)" % [tape.tape_minutes, deck._side_len])
	_ok(deck.is_playing and str(fake.opened.back()).ends_with("a1.ogg"), "deck/offline it plays side A's first track")
	fake.length_ms = 600000
	deck._track_idx = 1
	fake.time_ms = 280000
	deck._note_tape()
	var want := (600.0 + 280.0) / 1380.0
	_ok(is_equal_approx(tape.tape_progress, want) and tape.tape_side == 0 and tape.tape_track == 1,
		"deck/280 s into a2 the tape is %.3f along (%.3f)" % [want, tape.tape_progress])
	_eq(deck.counter(), int(want * 999.0), "deck/the counter counts side A's share")
	deck.stop()
	deck._slot.eject()
	deck._media_unloaded()
	# Turned over: side B from the same place, 1380 - 880 = 500 s into b1.
	var again: Array = await _cassette_in(album, 1, tape)
	var deck_b: CassettePlayer = again[0]
	var fake_b: FakeVlc = again[2]
	_ok(deck_b.side_playing() == 1 and _names(deck_b._tracks) == ["b1.ogg"], "deck/turned over: side B's tracks")
	_ok(deck_b._track_idx == 0 and is_equal_approx(deck_b._resume_at, 500.0),
		"deck/it takes up 500 s into b1, where side A left the tape (%d, %.1f)" % [deck_b._track_idx, deck_b._resume_at])
	_eq(deck_b.counter(), int((500.0 / 1380.0) * 999.0), "deck/the counter counts side B's share")
	deck_b._update_vfd()
	_eq(str(deck_b._vfd_state.get("side", "")), "B", "deck/the display shows side B")
	# The spindles: turned over, the take-up hub stands on the left spindle and turns the other way seen from here.
	var hub := tape.find_child("HubTakeup", true, false) as Node3D
	if hub != null:
		hub.rotation.z = 0.7
		deck_b._turn_spindles(0.0)
		var left := deck_b._model.part("ReelL")
		_ok(left != null and is_equal_approx(left.rotation.z, -0.7), "deck/turned over, ReelL follows HubTakeup, reversed")
	# The side's last track ends: the blank tape runs on.
	fake_b.length_ms = 1200000
	deck_b._track_idx = 0
	deck_b._on_track_finished()
	_ok(deck_b.is_playing and is_equal_approx(deck_b._blank, 0.0) and deck_b._track_idx == 1,
		"deck/after side B's last track the blank tape runs on (blank %.1f)" % deck_b._blank)
	deck_b._run_blank(100.0)
	deck_b._note_tape()
	_ok(is_equal_approx(deck_b._blank, 100.0) and is_equal_approx(tape.tape_progress, 1.0 - 1300.0 / 1380.0),
		"deck/100 s into the blank: the tape at %.3f (%.3f)" % [1.0 - 1300.0 / 1380.0, tape.tape_progress])
	deck_b._run_blank(100.0)
	_ok(not deck_b.is_playing and deck_b.tape_at_end() and is_equal_approx(tape.tape_progress, 0.0),
		"deck/at the side's end it stops, the tape wound to side A's start (%.3f)" % tape.tape_progress)
	deck_b._on_play_pressed()
	_ok(not deck_b.is_playing, "deck/and PLAY does nothing until it is rewound or turned over")
	# REW from the end winds back through the blank into the last track.
	deck_b._on_rewind_pressed()
	_ok(deck_b.is_playing and deck_b._scan_dir == -1 and deck_b._blank >= 0.0, "deck/REW from the end winds back through the blank")
	deck_b._run_blank(30.0)
	_ok(deck_b._blank < 0.0 and deck_b._track_idx == 0 and str(fake_b.opened.back()).ends_with("b1.ogg")
		and deck_b._scan_dir == -1, "deck/and on into b1, still winding back")
	# FF off the last track goes into the blank, winding.
	deck_b._scan_dir = 1
	fake_b.time_ms = 1199900
	deck_b._scan_accum = RetroAudioPlayer.SCAN_SEEK_INTERVAL
	deck_b._resume_at = 0.0
	deck_b._update_scan(0.0)
	_ok(deck_b._blank >= 0.0 and deck_b._scan_dir == 1, "deck/FF off the last track winds on into the blank")
	# A side with no tracks: an album with no marker turned over is blank tape.
	var plain := _album("DeckPlain", [["p1.ogg", 300]], -1)
	var p: Array = await _cassette_in(plain, 1)
	var deck_p: CassettePlayer = p[0]
	# A new tape is wound to side A's start, which is side B's END: turned over, it is to be rewound first.
	_ok(deck_p.side_playing() == 1 and deck_p._tracks.is_empty() and not deck_p.is_playing and deck_p.tape_at_end(),
		"deck/a new tape turned over stands at side B's end (side A's start), not played")
	_ok(is_equal_approx(deck_p._side_len, 1380.0), "deck/on a C46: its one side of music fits one")
	deck_p._on_rewind_pressed()
	deck_p._run_blank(200.0)
	deck_p._on_play_pressed()
	_ok(deck_p.is_playing and deck_p._blank >= 0.0 and deck_p._scan_dir == 0,
		"deck/rewound, an album with no #SIDE B plays side B as blank tape")


# ── record/ ───────────────────────────────────────────────────────────────────

func _t_record() -> void:
	# Side A 300 + 300 s, side B 400 s: the band is side A's 600 s.
	var album := _album("Record", [["r1.ogg", 300], ["r2.ogg", 300], ["r3.ogg", 400]], 2)
	var rp := RECORD_PLAYER.instantiate() as RecordPlayer
	add_child(rp)
	_spawned.append(rp)
	var lp := VINYL_RECORD.instantiate() as VinylRecord
	lp.album_path = album
	add_child(lp)
	_spawned.append(lp)
	await get_tree().process_frame
	rp.set_process(false)
	rp._vlc = FakeVlc.new()
	rp.restore_media(lp, 0.0, 0)
	var span := rp.arm_lead_out - rp.arm_lead_in
	_ok(_names(rp._tracks) == ["r1.ogg", "r2.ogg"] and is_equal_approx(rp._side_len, 600.0),
		"record/side A up: its tracks, the band side A's 600 s")
	_eq(rp._track_at(rp.arm_lead_in + span * 0.4), 0, "record/40 % into the band is r1")
	_eq(rp._track_at(rp.arm_lead_in + span * 0.6), 1, "record/60 % into the band is r2")
	_ok(is_equal_approx(rp._arm_value_for(1), rp.arm_lead_in + span * 0.5), "record/r2's groove starts halfway in")
	rp._tray.release()
	var lp_b := VINYL_RECORD.instantiate() as VinylRecord
	lp_b.album_path = album
	add_child(lp_b)
	_spawned.append(lp_b)
	await get_tree().process_frame
	rp.restore_media(lp_b, 0.0, 1)
	_ok(rp.side_playing() == 1 and _names(rp._tracks) == ["r3.ogg"], "record/side B up: its track")
	_eq(rp._track_at(rp.arm_lead_in + span * 0.5), 0, "record/halfway in is still r3's music (400 of 600 s)")
	_eq(rp._track_at(rp.arm_lead_in + span * 0.8), -1, "record/past it is the run-out groove: nothing")


# ── save/ ─────────────────────────────────────────────────────────────────────

func _t_save() -> void:
	var album := _album("Save", [["s1.ogg", 600], ["s2.ogg", 600]], 1)
	var got: Array = await _cassette_in(album, 1)
	var deck: CassettePlayer = got[0]
	var tape: AudioCassette = got[1]
	var store := ScenePersistence.new()
	var entry := store.serialize_node(deck, 1, {deck: 1, tape: 2})
	_eq(int(entry.get("media_side", 0)), 1, "save/a deck saves the side in play")
	var t_entry := store.serialize_node(tape, 2, {deck: 1, tape: 2})
	_eq(int(t_entry.get("tape_side", -1)), 1, "save/the cassette saves the side its place is on")
	var back := store.deserialize_object(t_entry) as AudioCassette
	_ok(back != null and back.tape_side == 1, "save/and loads it")
	if back != null:
		back.free()
	var old := store.deserialize_object({"type": "audio_cassette", "album_path": "", "album_label": "x", "tape_track": 1})
	_ok(old != null and (old as AudioCassette).tape_side == 0, "save/a save from before sides loads as side A")
	if old != null:
		old.free()
	var a_side: Array = await _cassette_in(album, 0)
	var a_entry := store.serialize_node(a_side[0] as Node, 3, {a_side[0]: 3, a_side[1]: 4})
	_ok(not a_entry.has("media_side"), "save/side A saves no side (what an old save has)")


# ── net/ ──────────────────────────────────────────────────────────────────────

func _t_net() -> void:
	var album := _album("Net", [["n1.ogg", 60], ["n2.ogg", 60], ["n3.ogg", 60]], 1)
	var events: Array = []
	var got: Array = await _cassette_in(album, 1)
	var deck: CassettePlayer = got[0]
	# The payload the insert reports (NetworkManager.report_event is a no-op offline): rebuilt as _media_loaded does.
	events.append({"player": deck, "media": got[1], "yaw": deck.media_seat_yaw(), "side": deck.side_playing()})
	_eq(int(events[0]["side"]), 1, "net/the insert event carries the side")
	var sync := NetObjectSync.new()
	var manifest: Array = sync._music_manifest_of(album, "music", true)
	var marked := manifest.map(func(r: Dictionary) -> bool: return bool(r.get("side_b", false)))
	_ok(marked == [false, true, false], "net/the album's manifest marks side B's first track (%s)" % [marked])
	sync.free()
	var dests: Array = manifest.map(func(r: Dictionary) -> Dictionary:
		return {"name": r["name"], "md5": r["md5"], "side_b": bool(r.get("side_b", false))})
	var text := NetObjectSync.assembled_playlist_text(dests)
	var written := _file("NetPeer/playlist.m3u8", text)
	for r: Dictionary in manifest:
		_file("NetPeer".path_join(str(r["name"])), "peer copy")
	var peer := RomLibrary.music_sides(written.get_base_dir())
	_ok(_names(peer["a"]) == ["n1.ogg"] and _names(peer["b"]) == ["n2.ogg", "n3.ogg"],
		"net/a peer's assembled album has the host's sides (%s | %s)" % [_names(peer["a"]), _names(peer["b"])])
