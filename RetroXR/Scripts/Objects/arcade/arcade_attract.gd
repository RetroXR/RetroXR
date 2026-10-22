## ArcadeAttract -- a switched-on cabinet that shows its game instead of running it.
##
## A cabinet that is on but unused would load a core and a ROM just to sit in the game's own attract
## screen. With the option on, switching it on starts THIS instead: the game's scraped video snap
## (else its title screen, else its wheel, else its cover) looped on the glass, with the sound in
## the room. The core and ROM start only when somebody uses the cabinet (a coin, a panel pressed, a
## gun or pad taken in hand) and go away again after IDLE_SECONDS of nobody (libretro has no
## game-over signal, MAME and FinalBurn expose none, so idleness is what we can know).
##
## The option is a global pref with a per-cabinet override (`wanted`). It is off by default: a video
## decode per cabinet is real work, most of all on a Quest, so the cost is bounded three ways:
##   - a video only decodes for the nearest `video_budget()` cabinets; the rest hold the still;
##   - a screen out of view uploads no frames (the sound goes on);
##   - a cabinet past hearing range pauses its player, and a far one pulls its sound less often.
## The sound is one mono voice per cabinet (a real arcade cabinet's speaker is), which also spares
## the room's shared Meta XR Audio voices.
##
## RetroSystem owns the state (`attracting`) and the entry points; this node owns the picture.
class_name ArcadeAttract
extends Node

const GROUP := &"arcade_attract"

## Seconds with nobody at the cabinet before its core is put away and the attract returns.
const IDLE_SECONDS := 120.0
## How often the room is re-ranked (nearest first), and how often a far cabinet pulls its sound.
const ARBITRATE_INTERVAL := 0.25
const FAR_PULL_INTERVAL := 0.1
## Where sound stops being worth a full-rate pull, and where it stops being heard at all.
const NEAR_AUDIO := 6.0
const MAX_AUDIO := 15.0
## Simultaneous video decodes: the Quest's CPU cannot afford more than one.
const VIDEO_BUDGET_DESKTOP := 4
const VIDEO_BUDGET_ANDROID := 1
## How far past the picture's edge, as a fraction of the picture, the glass may be and still count as in view.
const VIEW_MARGIN := 0.15
## The glass is tilted and framed; its box is taken a little larger than its size.
const GLASS_GROW := 1.3
## The visible glass of a cabinet's monitor, metres (ArcadeScreenModule.glass_size).
const GLASS_SIZE := Vector2(0.38, 0.285)

## Override values on RetroSystem.attract_override.
const OVERRIDE_FOLLOW := 0
const OVERRIDE_ON := 1
const OVERRIDE_OFF := 2

## Seconds after the core starts before a coin that STARTED it is delivered: a coin at boot is lost.
const COIN_BOOT_DELAY := 2.0

const VIDEO_EXTS := [".mp4", ".mkv", ".webm", ".avi", ".mov"]
## The scraper's folders (rom_media.gd SCRAPED_DIRS).
const VIDEO := "video"
const TITLE := "title"
const WHEEL := "wheel"
const BOX := "box"

## Audio tiers (audio_tier).
enum Tier { SILENT, FAR, NEAR }

## A suite hands a ROM its picture without writing the player's data root. Empty in the app.
static var test_still: Dictionary = {}

static var _rank_msec: int = -100000

## Games whose video the cabinets want and nobody has asked the scraper for yet (rom path -> the board's
## system). The scraper lives in the spawn menu, which a room restore can be well ahead of: a cabinet that
## comes back already switched on asks before there is anyone to ask. The menu takes these as soon as it
## is up (SpawnMenu2D._init_scraper), and takes each one the moment it is asked for.
static var pending_media: Dictionary = {}

var active: bool = false
var _host: Node3D = null
var _vlc: RefCounted = null
var _emitter: SpatialAudioEmitter = null
var _still: Texture2D = null
var _has_video: bool = false
var _video_path: String = ""
var _media_key: String = ""
var _opened_msec: int = 0
var _video_ok: bool = true
var _tier: int = Tier.NEAR
var _in_view: bool = true
var _playing: bool = false
var _pull_clock: float = 0.0
var _idle: float = 0.0


# ── the rules: pure, so a suite can ask them ────────────────────────────────

## The option as this cabinet sees it: its own override, else the global pref.
static func effective_pref(pref: bool, override_mode: int) -> bool:
	match override_mode:
		OVERRIDE_ON:
			return true
		OVERRIDE_OFF:
			return false
	return pref


## Whether a switched-on cabinet shows its game instead of running it. A cabinet with no game (or bay)
## behaves as it always did, a console cabled to its A/V input owns the screen, and a netplay session
## runs the real core on every peer.
static func wanted(pref: bool, override_mode: int, has_game: bool, external: bool, netplay: bool) -> bool:
	return effective_pref(pref, override_mode) and has_game and not external and not netplay


## Is the glass inside what a view SEES? `views` is what the player looks through: one { "xf": the eye's
## world transform, "proj": its projection } for a desktop camera, TWO for a headset, whose eyes are each
## far wider than a flat screen's field of view and not symmetric (Quest 3: about 110 deg across, less
## up and down, each eye turned a little outward). `screen_xf` is the glass (its +Z the way it faces),
## `size` its width and height in metres.
##
## The glass is a RECTANGLE: its four corners go through each view's projection and the box they cover on
## the picture is tested against the picture, so a screen close enough to fill the view, or standing half
## out of it at the edge, counts as seen, and a point test on its centre would say it was not. Grown by
## VIEW_MARGIN (a fraction of the picture) because a head turns faster than a decode can be woken.
## From behind it is the cabinet's back, never the glass.
static func screen_in_view(views: Array, screen_xf: Transform3D, size: Vector2) -> bool:
	var half := Vector2(size.x, size.y) * 0.5 * GLASS_GROW
	var corners: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			corners.append(screen_xf.origin + screen_xf.basis.x.normalized() * (sx * half.x) \
				+ screen_xf.basis.y.normalized() * (sy * half.y))
	var normal := screen_xf.basis.z.normalized()
	for view: Dictionary in views:
		var xf: Transform3D = view["xf"]
		if normal.dot(xf.origin - screen_xf.origin) <= 0.0:
			continue
		if _rect_in_picture(xf.affine_inverse(), view["proj"] as Projection, corners):
			return true
	return false


## The corners (world) against one view: do their box on the picture and the picture overlap?
static func _rect_in_picture(world_to_eye: Transform3D, proj: Projection, corners: Array[Vector3]) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := 0
	for c in corners:
		var e: Vector3 = world_to_eye * c
		var clip: Vector4 = proj * Vector4(e.x, e.y, e.z, 1.0)
		if clip.w <= 0.0001:
			behind += 1
			continue
		lo = Vector2(minf(lo.x, clip.x / clip.w), minf(lo.y, clip.y / clip.w))
		hi = Vector2(maxf(hi.x, clip.x / clip.w), maxf(hi.y, clip.y / clip.w))
	if behind == corners.size():
		return false
	# A corner behind the eye stretches the box without limit: with the others in front, the glass crosses
	# the view's plane and is as good as seen.
	if behind > 0:
		return true
	var edge := 1.0 + VIEW_MARGIN
	return hi.x >= -edge and lo.x <= edge and hi.y >= -edge and lo.y <= edge


## The `max_videos` nearest of `dists` (metres), as indices. Ties go to the lower index so the choice
## does not flicker between two cabinets at the same distance.
static func pick_budget(dists: PackedFloat32Array, max_videos: int) -> PackedInt32Array:
	var order: Array[int] = []
	for i in dists.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(dists[a], dists[b]):
			return a < b
		return dists[a] < dists[b])
	var out := PackedInt32Array()
	for k in mini(maxi(max_videos, 0), order.size()):
		out.append(order[k])
	return out


## How the sound is served at `distance`: not at all past hearing, a lighter pull beyond NEAR_AUDIO,
## the full rate nearer.
static func audio_tier(distance: float) -> int:
	if distance >= MAX_AUDIO:
		return Tier.SILENT
	if distance > NEAR_AUDIO:
		return Tier.FAR
	return Tier.NEAR


static func video_budget() -> int:
	return VIDEO_BUDGET_ANDROID if OS.has_feature("android") else VIDEO_BUDGET_DESKTOP


## What a game shows, best first: { "kind": "video" | "image" | "", "path": String, "folder": String }.
## A video snap, else the title screen, else the wheel, else the cover (the box front, else the label).
static func resolve_media(systemid: String, rom_path: String) -> Dictionary:
	var video := MediaDimensions.media_file_path(systemid, rom_path, VIDEO, PackedStringArray(VIDEO_EXTS))
	if not video.is_empty():
		return {"kind": "video", "path": video, "folder": VIDEO}
	for folder in [TITLE, WHEEL, BOX, "label"]:
		var img := MediaDimensions.media_file_path(systemid, rom_path, folder,
			PackedStringArray([".png", ".jpg", ".jpeg", ".webp"]))
		if not img.is_empty():
			return {"kind": "image", "path": img, "folder": folder}
	return {"kind": "", "path": "", "folder": ""}


## Is there a video snap for this game yet? (The cabinet asks before it spends a scrape request.)
static func has_video(systemid: String, rom_path: String) -> bool:
	return not MediaDimensions.media_file_path(systemid, rom_path, VIDEO, PackedStringArray(VIDEO_EXTS)).is_empty()


## The still that stands in for the video: title, wheel, then the cover.
static func load_still(systemid: String, rom_path: String) -> Texture2D:
	if test_still.has(rom_path):
		return test_still[rom_path] as Texture2D
	var tex := MediaDimensions.load_media_texture(systemid, rom_path, TITLE)
	if tex != null:
		return tex
	var art := ArcadeCabinetArt.for_rom(systemid, rom_path)
	if art["wheel"] != null:
		return art["wheel"] as Texture2D
	return art["cover"] as Texture2D


# ── lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	_stop_playback()
	_release_player()


## Begin showing `host`'s game. `host` is the RetroSystem.
func start(host: Node3D) -> void:
	_host = host
	active = true
	_idle = 0.0
	add_to_group(GROUP)
	load_media()


## The scraper landed a video or a title for `rom_path`: if that is the game on show, read the media
## again so the still gives way to the video.
func on_media_arrived(rom_path: String) -> void:
	if active and _host != null and str(_host.get("rom_path")) == rom_path:
		load_media()


## Stop showing anything and give the player back.
func stop() -> void:
	active = false
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	_stop_playback()
	_still = null
	_media_key = ""


## Read the game's media again: a download that landed while the attract was up turns a still into
## the video.
func load_media() -> void:
	if _host == null:
		return
	var systemid := _game_systemid()
	var rom: String = str(_host.get("rom_path"))
	var found := resolve_media(systemid, rom)
	var key := "%s|%s" % [found["kind"], found["path"]]
	if key == _media_key and active:
		return
	_media_key = key
	_stop_playback()
	_still = load_still(systemid, rom)
	if found["kind"] == "video":
		_open_video(str(found["path"]))
	elif found["kind"] == "image" and _still == null:
		var img := Image.load_from_file(str(found["path"]))
		if img != null and not img.is_empty():
			_still = ImageTexture.create_from_image(img)


## The system the BOARD belongs to (the folder its media lives under), which is not always the
## cabinet's: an MVS bay in a generic cabinet plays Neo Geo.
func _game_systemid() -> String:
	if _host != null and _host.has_method("get_snapped_cartridge"):
		var cart: Variant = _host.call("get_snapped_cartridge")
		if cart != null and "systemid" in cart and not str(cart.get("systemid")).is_empty():
			return str(cart.get("systemid"))
	return str(_host.get("systemid")) if _host != null else ""


func _open_video(path: String) -> void:
	if not ClassDB.class_exists("VlcPlayer"):
		return
	# One player for the life of the cabinet: libvlc_new per attract would be paid on every switch-on.
	if _vlc == null:
		_vlc = ClassDB.instantiate("VlcPlayer")
		_vlc.finished.connect(_on_finished)
	_make_emitter()
	_opened_msec = Time.get_ticks_msec()
	# A path under user:// is no URL scheme libVLC knows.
	if not _vlc.open(ProjectSettings.globalize_path(path), false):
		push_warning("ArcadeAttract: VlcPlayer.open failed for %s" % path)
		_stop_playback()
		return
	_vlc.set_volume(100)
	_vlc.play()
	_has_video = true
	_video_path = path
	_playing = true


func _make_emitter() -> void:
	if _emitter != null:
		return
	_emitter = SpatialAudioEmitter.new()
	_emitter.name = "AttractEmitter"
	# One speaker: one voice. directivity is a cabinet's own box in front of the glass.
	_emitter.speaker_separation = 0.0
	_emitter.unit_size = 2.0
	_emitter.max_distance = MAX_AUDIO
	_emitter.directivity = SpatialAudioEmitter.SPEAKER_DIRECTIVITY
	add_child(_emitter)


## Stop what is playing and give back the sound voice; the player itself is kept for the next switch-on.
func _stop_playback() -> void:
	_has_video = false
	_playing = false
	_video_path = ""
	if _vlc != null:
		_vlc.stop()
	if _emitter != null:
		_emitter.flush()
		_emitter.queue_free()
		_emitter = null


## The cabinet leaves the room: let libVLC go (bounded, vcr_player.gd does the same).
func _release_player() -> void:
	if _vlc != null:
		if _vlc.finished.is_connected(_on_finished):
			_vlc.finished.disconnect(_on_finished)
		_vlc.shutdown()
		_vlc = null


## The snap ended: round again. libVLC posts `finished` for the stop we just asked for too, hence
## the guard (vcr_player.gd STALE_FINISH_MSEC).
func _on_finished() -> void:
	if not _has_video or Time.get_ticks_msec() - _opened_msec < 300:
		return
	_restart.call_deferred()


func _restart() -> void:
	if _vlc == null or _video_path.is_empty():
		return
	_opened_msec = Time.get_ticks_msec()
	if _vlc.open(ProjectSettings.globalize_path(_video_path), false):
		_vlc.play()
		_vlc.set_volume(100)
		if _emitter != null:
			_emitter.flush()


# ── what the glass shows ────────────────────────────────────────────────────

## The picture for the screen, or null when the game has nothing to show (the tube stays dark).
func picture() -> Texture2D:
	if _has_video and _vlc != null and _playing and _vlc.get_frame_count() > 0:
		var tex: Texture2D = _vlc.get_texture()
		if tex != null:
			return tex
	return _still


## True while the picture is a decoding video rather than a still.
func is_video_playing() -> bool:
	return _has_video and _playing


## Width over height of the picture, or 0 when there is none.
func picture_aspect() -> float:
	var tex := picture()
	if tex == null or tex.get_height() <= 0:
		return 0.0
	return float(tex.get_width()) / float(tex.get_height())


# ── per frame ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _host == null:
		return
	if not active:
		_watch_idle(delta)
		return
	_rank_room(get_tree())
	if _vlc == null or not _has_video:
		return
	# Asked every frame, not with the ranking: a head turns faster than a quarter second, and a screen that
	# comes into view should not show the last picture it had until the next ranking.
	if _playing:
		_in_view = _screen_in_view()
		if _in_view:
			_vlc.update_frame()
	if _emitter != null and _playing:
		_follow_speaker()
		_pull_audio(delta)


## Re-rank every attract cabinet, nearest first, at most ARBITRATE_INTERVAL apart; whichever cabinet's
## _process comes first does it for all of them.
static func _rank_room(tree: SceneTree) -> void:
	var now := Time.get_ticks_msec()
	if now - _rank_msec < int(ARBITRATE_INTERVAL * 1000.0):
		return
	_rank_msec = now
	var members := tree.get_nodes_in_group(GROUP)
	if members.is_empty():
		return
	var listener := _listener_position(tree)
	var dists := PackedFloat32Array()
	for m in members:
		dists.append((m as ArcadeAttract).distance_to(listener))
	var allowed := pick_budget(dists, video_budget())
	for i in members.size():
		(members[i] as ArcadeAttract).apply_rank(allowed.has(i), dists[i])


static func _listener_position(tree: SceneTree) -> Vector3:
	var listener := tree.root.get_node_or_null("SpatialAudioListener")
	if listener != null and listener.has_method("get_listener_position"):
		return listener.call("get_listener_position")
	var cam := tree.root.get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


## Metres from `listener` to this cabinet's speaker.
func distance_to(listener: Vector3) -> float:
	return _speaker_position().distance_to(listener) if _host != null else INF


## Take the verdict of a ranking: whether this cabinet is among the nearest, and how far it is.
func apply_rank(video_ok: bool, distance: float) -> void:
	_video_ok = video_ok
	_tier = audio_tier(distance)
	if _vlc == null or not _has_video:
		return
	var play := _video_ok and _tier != Tier.SILENT
	if play != _playing:
		_playing = play
		_vlc.set_paused(not play)
		if not play and _emitter != null:
			_emitter.flush()


## Is the glass inside what the player sees right now? Through the real projection(s): both eyes of a
## headset (each with the field of view the runtime reports, not a number of ours), the camera's own on
## a desktop. With nothing to look through (a suite, a probe without a camera) it counts as seen.
func _screen_in_view() -> bool:
	if _host == null or not is_inside_tree():
		return true
	var views := _views()
	if views.is_empty():
		return true
	return screen_in_view(views, _screen_transform(), GLASS_SIZE)


## What the player looks through: { "xf", "proj" } per eye in a headset, or the current camera's.
func _views() -> Array:
	var out: Array = []
	var iface := XRServer.primary_interface
	if iface != null and iface.is_initialized() and iface.get_view_count() > 0:
		var origin := XRServer.world_origin
		for v in iface.get_view_count():
			out.append({"xf": iface.get_transform_for_view(v, origin),
				"proj": iface.get_projection_for_view(v, 1.0, 0.05, 100.0)})
		return out
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		out.append({"xf": cam.global_transform, "proj": cam.get_camera_projection()})
	return out


## The glass in world space: where the screen mesh is, facing the way the cabinet does (its +Z).
func _screen_transform() -> Transform3D:
	var xf := _host.global_transform
	var model: Node = _model()
	if model != null and model.has_method("get_builtin_screen"):
		var screen: Variant = model.call("get_builtin_screen")
		if screen is Node3D:
			xf.origin = (screen as Node3D).global_position
	return xf


func _speaker_position() -> Vector3:
	var model: Node = _model()
	if model != null and model.has_method("audio_speaker_positions"):
		var pts: PackedVector3Array = model.call("audio_speaker_positions")
		if pts.size() > 0:
			var sum := Vector3.ZERO
			for p in pts:
				sum += p
			return _host.global_transform * (sum / float(pts.size()))
	return _host.global_position


func _follow_speaker() -> void:
	_emitter.set_emit_position(_speaker_position())
	_emitter.set_emit_direction(_host.global_transform.basis.z.normalized())


func _pull_audio(delta: float) -> void:
	# A far cabinet is served in bigger, rarer gulps; the emitter's queue holds a quarter second.
	if _tier == Tier.FAR:
		_pull_clock += delta
		if _pull_clock < FAR_PULL_INTERVAL:
			return
		_pull_clock = 0.0
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var frames: PackedVector2Array = _vlc.read_audio(want)
	if frames.size() > 0:
		_emitter.push_stereo(frames)


# ── nobody home ─────────────────────────────────────────────────────────────

## While the core runs on behalf of an attract start: when nobody has been at the cabinet for
## IDLE_SECONDS, put the core away. `engaged` is ArcadeInput.engaged().
func _watch_idle(delta: float) -> void:
	if not bool(_host.get("attract_session")) or not bool(_host.get("is_powered_on")):
		_idle = 0.0
		return
	var input := _input_node()
	if input == null or input.engaged():
		_idle = 0.0
		return
	_idle += delta
	if _idle >= IDLE_SECONDS:
		_idle = 0.0
		_host.call("attract_return")


## Somebody did something at the cabinet (a coin, a press): the idle clock starts over.
func touch() -> void:
	_idle = 0.0


func idle_seconds() -> float:
	return _idle


func _model() -> Node:
	return _host.call("get_model") as Node if _host != null and _host.has_method("get_model") else null


func _input_node() -> ArcadeInput:
	var model: Node = _model()
	if model != null and model.has_method("arcade_input"):
		return model.call("arcade_input") as ArcadeInput
	return null
