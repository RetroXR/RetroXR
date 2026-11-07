## The base game's audio cassette held up close, and the headphones in the RETRO XR CD player's and cassette deck's
## PHONES jacks, and a cassette and an LP turned over (side B), windowed:
##   godot --path RetroXR res://Tools/av/bring_in_probe.tscn --resolution 320x240 --position 20,20 -- --no-mods --out=<dir>
## --no-mods: the stock cassette (a mod dressing it, xenu.cassette, would hide it). Renders into its own SubViewport.
extends Node

const CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const CD := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const DECK := preload("res://Scenes/Objects/appliances/cassette_player.tscn")
const HEADPHONES := preload("res://Scenes/Objects/appliances/headphones.tscn")
const TURNTABLE := preload("res://Scenes/Objects/appliances/record_player.tscn")
const LP := preload("res://Scenes/Objects/media/vinyl_record.tscn")
## A scratch album with a `#SIDE B`, its lengths given (no file here is real audio); removed at the end.
const SIDES_ALBUM := "user://bring_in_probe_sides/Two Sides"

var _out := ""
var _view: SubViewport
var _cam: Camera3D


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	await _cassette()
	await _phones()
	await _deck_phones()
	await _sides()
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_view.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	floor_mesh.add_child(body)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 35
	_view.add_child(_cam)
	_cam.current = true


func _shot(file: String, frames: int = 8) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out.path_join(file))
	print("[probe] wrote ", file)


## Held up as a hand holds one to read it: side A toward the eye, tilted back, a third of the way through the tape.
func _cassette() -> void:
	var t := CASSETTE.instantiate() as AudioCassette
	t.freeze = true
	t.album_label = "Summer Mix '91"
	t.tape_progress = 0.33
	_view.add_child(t)
	t.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-25), deg_to_rad(18), deg_to_rad(-6))),
		Vector3(0, 1.2, 0))
	for i in 30:
		await get_tree().process_frame
	print("[probe] cassette: shell %s, progress %.2f" % [t.get_node_or_null("Shell") is CompactCassette,
		(t.get_node("Shell") as CompactCassette).progress if t.get_node_or_null("Shell") is CompactCassette else -1.0])
	_cam.look_at_from_position(Vector3(0.02, 1.27, 0.22), Vector3(0, 1.2, 0))
	await _shot("cassette_base_in_hand.png")
	t.queue_free()


## The headphones' plug in the CD player's PHONES jack, the LEVEL knob beside it.
func _phones() -> void:
	var cd := CD.instantiate() as CDPlayer
	cd.freeze = true
	_view.add_child(cd)
	cd.global_position = Vector3(0, 0.0475, 0)
	var hp := HEADPHONES.instantiate() as Node3D
	_view.add_child(hp)
	hp.global_position = Vector3(0.12, 0.03, 0.45)
	for i in 20:
		await get_tree().process_frame
	var jack := cd.get_node("PhonesOut") as XRToolsSnapZone
	jack.pick_up_object(hp.get_node("PlugB0") as Node3D)
	for i in 90:
		await get_tree().physics_frame
	print("[probe] CD sound -> %s" % (cd.sound_sink().name if cd.sound_sink() != null else "itself"))
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_cam.look_at_from_position(Vector3(0.36, 0.17, 0.55), Vector3(0.12, 0.03, 0.2))
	await _shot("headphones_in_cd_phones.png")
	_cam.look_at_from_position(Vector3(0.23, 0.07, 0.33), Vector3(0.175, 0.03, 0.15))
	await _shot("cd_phones_close.png")


## The headphones' plug in the cassette deck's PHONES jack under EJECT, the VOLUME knob turned to a third.
func _deck_phones() -> void:
	for n in _view.get_children():
		if n is CDPlayer or n is Headphones:
			n.queue_free()
	await get_tree().process_frame
	var deck := DECK.instantiate() as CassettePlayer
	deck.freeze = true
	_view.add_child(deck)
	deck.global_position = Vector3(0, 0.06, 0)
	var hp := HEADPHONES.instantiate() as Node3D
	_view.add_child(hp)
	hp.global_position = Vector3(-0.1, 0.03, 0.45)
	for i in 20:
		await get_tree().process_frame
	var jack := deck.get_node("PhonesOut") as XRToolsSnapZone
	jack.pick_up_object(hp.get_node("PlugB0") as Node3D)
	(deck.get_node("LevelKnob") as VRKnob).set_value(0.3)
	for i in 90:
		await get_tree().physics_frame
	print("[probe] deck sound -> %s, VOLUME %.2f" % [deck.sound_sink().name if deck.sound_sink() != null else "nothing",
		deck.output_level])
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_cam.look_at_from_position(Vector3(0.05, 0.2, 0.62), Vector3(-0.03, 0.05, 0.15))
	await _shot("headphones_in_deck_phones.png")
	_cam.look_at_from_position(Vector3(0.0, 0.09, 0.3), Vector3(-0.051, 0.04, 0.15))
	await _shot("deck_phones_close.png")
	_cam.look_at_from_position(Vector3(0.24, 0.1, 0.32), Vector3(0.186, 0.04, 0.15))
	await _shot("deck_volume_close.png")


## A cassette turned over in the deck (side B out: the display says B, the album's name is on the hidden side A), and
## an LP put down upside down on the turntable (side B up).
func _sides() -> void:
	for n in _view.get_children():
		if n is CassettePlayer or n is Headphones:
			n.queue_free()
	await get_tree().process_frame
	MusicLengths.test_mode = true
	DirAccess.make_dir_recursive_absolute(SIDES_ALBUM)
	var lines := PackedStringArray(["#EXTM3U"])
	for row: Array in [["a1.ogg", 600.0], ["a2.ogg", 500.0], ["SIDE"], ["b1.ogg", 700.0]]:
		if row[0] == "SIDE":
			lines.append("#SIDE B")
			continue
		var path: String = SIDES_ALBUM.path_join(row[0])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("not audio")
		f.close()
		MusicLengths.remember(path, row[1])
		lines.append(row[0])
	var m := FileAccess.open(SIDES_ALBUM.path_join("order.m3u8"), FileAccess.WRITE)
	m.store_string("\n".join(lines) + "\n")
	m.close()
	var deck := DECK.instantiate() as CassettePlayer
	deck.freeze = true
	_view.add_child(deck)
	deck.global_position = Vector3(0, 0.06, 0)
	var tape := CASSETTE.instantiate() as AudioCassette
	tape.album_path = SIDES_ALBUM
	tape.album_label = "Two Sides"
	tape.freeze = true
	_view.add_child(tape)
	tape.global_position = Vector3(0.3, 0.2, 0.3)
	for i in 20:
		await get_tree().process_frame
	# Let go of turned over (side B toward the deck's front), as a hand does.
	var holder: Node3D = deck._slot.get("_holder")
	tape.set("_release_basis", holder.global_basis.orthonormalized() * Basis(Vector3.UP, PI))
	deck._slot._accept(tape, false)
	for i in 120:
		await get_tree().process_frame
	print("[probe] deck: side %s, %d track(s) on it, a C%d (side %.0f s)" % [TapeSides.side_name(deck.side_playing()),
		deck._tracks.size(), roundi(tape.tape_minutes), deck._side_len])
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_cam.look_at_from_position(Vector3(-0.08, 0.16, 0.5), Vector3(-0.05, 0.05, 0.15))
	await _shot("deck_side_b.png")
	deck.queue_free()
	tape.queue_free()
	await get_tree().process_frame
	var tt := TURNTABLE.instantiate() as RecordPlayer
	tt.freeze = true
	_view.add_child(tt)
	tt.global_position = Vector3(0, 0.03, 0)
	var lp := LP.instantiate() as VinylRecord
	lp.album_path = SIDES_ALBUM
	lp.album_label = "Two Sides"
	lp.freeze = true
	_view.add_child(lp)
	lp.global_position = Vector3(0.5, 0.2, 0)
	for i in 20:
		await get_tree().process_frame
	tt.restore_media(lp, 0.0, 1)
	for i in 30:
		await get_tree().process_frame
	print("[probe] turntable: side %s up, its +Y %s, band %.0f s, track at mid-band %d" % [
		TapeSides.side_name(tt.side_playing()), lp.transform.basis.y.snapped(Vector3.ONE * 0.01), tt._side_len,
		tt._track_at((tt.arm_lead_in + tt.arm_lead_out) * 0.5)])
	_cam.look_at_from_position(Vector3(0.0, 0.55, 0.35), Vector3(0.0, 0.05, 0.0))
	await _shot("turntable_side_b.png")
	OS.move_to_trash(ProjectSettings.globalize_path(SIDES_ALBUM.get_base_dir()))
