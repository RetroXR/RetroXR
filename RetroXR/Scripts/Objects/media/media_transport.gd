## MediaTransport — what a VHS deck and a DVD player do identically.
##
## Both are libVLC-backed decks that hang off the A/V cable graph, and both grew
## the same wiring independently: a spatial emitter aimed at whatever set they
## are plugged into, an A/V feed resolved through AvSource, a FloatLock, and a
## VlcPlayer to shut down on the way out.
##
## Only what is byte-identical in both lives here. That is a smaller set than it
## looks from the outside -- the two files share 42 method NAMES, but 36 of those
## differ in body, several substantially (stop, play, net_get_state, _process,
## _update_scan). A VCR scans a tape in seconds through its own helpers while a
## DVD works in milliseconds off VlcPlayer and has to stop at a menu boundary;
## forcing those together would take more parameters than the code it replaced.
## So the shape is a narrow base, not a merge, and the subclasses stay large.
##
## The reason this exists at all is coverage as much as duplication:
## on_av_topology_changed and _apply_av_feed are the routing rules that
## av_tests tests through the VCR, and the DVD player had its own copy that no
## case ever reached. Sharing them puts both decks behind the same 23 cases.
##
## Sibling of RetroAudioPlayer rather than a parent or child of it: that class is
## audio-only by contract -- no connected_tv, no video feed, no screen texture --
## and bolting a TV onto it to reach these four methods would be the bigger
## change, in the file with the fewer bugs.
class_name MediaTransport
extends XRToolsPickable


## The set this deck's picture currently reaches, or null. Written only by
## _apply_av_feed, which is the one place the cable graph is turned into routing.
var connected_tv: RetroTV = null

## The set this deck is built into, or null for a deck standing on its own. Set
## once, by TvDecks, before anything is played. A built-in deck is the same deck
## with no body and no lead — see build_into.
var built_into: RetroTV = null

## The tape or disc bay, built by each deck's own _ready. Declared here because
## build_into hands it the set's body to be collision-excepted against.
var _slot: MediaSlot = null

## VlcPlayer (GDExtension). Object rather than a typed reference so a build
## without the extension still loads the scene.
var _vlc: Object = null

var _emitter: SpatialAudioEmitter = null

## Set while the desktop fullscreen overlay holds this deck's picture.
var _head_lock := false
var _head_l := Vector3.ZERO
var _head_r := Vector3.ZERO
var _volume_linear: float = 1.0
var _paused: bool = false

## Which speaker each channel reaches, as an index into the set's own positions,
## or -1 for a channel whose cord goes nowhere. Not a stereo flag: a crossed pair
## is a real thing to do with two phono leads, and it has to sound like it.
var _feed_video: bool = false
var _feed_left: int = -1
var _feed_right: int = -1

## Saved/restored by ScenePersistence, and read once by FloatLock at _ready.
## Declared here rather than per deck because set_ignore_gravity below writes
## it -- a base that assigns a member only its subclasses declare does not
## parse, which is exactly how this refactor first failed.
var ignore_gravity: bool = false

var _float_lock: FloatLock = null


func _setup_audio() -> void:
	_emitter = SpatialAudioEmitter.new()
	_emitter.name = "SpatialAudioEmitter"
	_emitter.unit_size = 3.0
	_emitter.max_distance = 15.0
	# The picture and the sound both come from the TV, so the emitter is given the
	# set's own speaker positions once one is connected (_emit_through). Non-zero
	# here for the second voice that needs, and as the spread for a set too old to
	# report them.
	_emitter.speaker_separation = 0.25
	# Aimed at whatever set it is plugged into; see _process.
	_emitter.directivity = SpatialAudioEmitter.SPEAKER_DIRECTIVITY
	add_child(_emitter)


## The same contract RetroSystem answers: hold this deck's two channels at a
## fixed pair of points in the listener's frame while its picture is filling the
## window. Re-applied on the next _process tick, which is already where the
## routing below is written, so clearing it restores the set's speakers by itself.
func set_audio_head_lock(left: Vector3, right: Vector3) -> void:
	_head_lock = true
	_head_l = left
	_head_r = right
	if _emitter:
		_emitter.set_speaker_positions(left, right)
		_emitter.clear_emit_direction()


func clear_audio_head_lock() -> void:
	_head_lock = false


func _emit_through(tv: Node3D) -> void:
	if _head_lock:
		_emitter.set_speaker_positions(_head_l, _head_r)
		# Omnidirectional: a deck aimed along a screen normal the player is no
		# longer facing would be quietened for facing the wrong way.
		_emitter.clear_emit_direction()
		return
	if tv.has_method("get_speaker_positions"):
		var sp: PackedVector3Array = tv.get_speaker_positions()
		# The two voices carry the deck's own left and right, so a crossed pair is
		# handled by writing each voice to the speaker its cord actually reaches --
		# no per-sample work, just a position each. A channel routed nowhere keeps
		# whichever position; it is silent (set_channel_gains) and cannot be heard.
		_emitter.set_speaker_positions(
			sp[_feed_left] if _feed_left >= 0 else sp[0],
			sp[_feed_right] if _feed_right >= 0 else sp[1])
	else:
		_emitter.set_emit_position(tv.global_position)
	# Omnidirectional once the set has sent its sound to external speakers: they
	# point wherever a hand put them, not the way the picture faces.
	if tv.has_method("is_sound_external") and tv.is_sound_external():
		_emitter.clear_emit_direction()
	elif tv.has_method("get_screen_normal"):
		_emitter.set_emit_direction(tv.get_screen_normal(), tv.get_screen_up())


## Make this deck part of `tv`, a combination set: the picture and both channels
## go straight to it, with no lead, and the deck stops being a thing of its own.
##
## What it stops being, one line each:
## - a pickable: a hand cannot take the VCR out of a TV/VCR;
## - a body: the cabinet is the body, and a frozen box inside the set's collider
##   would only be something for the set to fight. STATIC rather than kinematic,
##   for the reason MediaSlot gives — kinematic drifts under its host's rotation;
## - a source on the cable graph: its A/V outputs are switched off, so no lead can
##   take the picture somewhere else, and on_av_topology_changed stops listening;
## - the grey box, unless the cabinet asks for it (RetroTVShell.deck_housing).
##
## What it keeps is everything a player touches — the slot, the buttons, the
## clock, the options panel, and the PointerArea the remote aims at.
##
## `controls` is where the button panel goes, in the set's frame, or null to leave
## it on top of the deck (RetroTVShell.VcrControls / DvdControls).
func build_into(tv: RetroTV, keep_housing: bool, controls: Variant = null) -> void:
	built_into = tv
	enabled = false
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	# The media rides inside the set's collider now, so it is the SET it must not
	# shove.
	if _slot != null:
		_slot.host = tv
	for port_name: String in ["VideoOut", "AudioLOut", "AudioROut"]:
		var port := get_node_or_null(port_name) as XRToolsSnapZone
		if port != null:
			port.visible = false
			port.enabled = false
	var legend := get_node_or_null("AvLegend") as Node3D
	if legend != null:
		legend.visible = false
	if not keep_housing:
		for node: Node3D in _housing():
			node.visible = false
	if controls is Transform3D:
		_move_controls(controls)
	_apply_av_feed(tv, true, 0, 1)


## Carry the button panel, as one rigid piece, from the deck's top face to
## `at` (the set's frame): the top face's centre lands on `at`, and its up on
## at's +Y. Every cap keeps its place in the layout, its glyph and its wiring —
## only where the panel is changes.
##
## The top face is the plane the caps stand on: their highest origin, since
## every cap on a stock deck sits at the same height.
func _move_controls(at: Transform3D) -> void:
	var buttons: Array[VRButton] = []
	var top := -INF
	for child in get_children():
		if child is VRButton:
			buttons.append(child as VRButton)
			top = maxf(top, (child as VRButton).position.y)
	if buttons.is_empty():
		return
	# deck <- set <- panel <- top face, so each cap's own transform is kept relative
	# to the top face's centre and that centre is carried to `at`.
	var carry := transform.affine_inverse() * at \
		* Transform3D(Basis.IDENTITY, Vector3(0.0, -top, 0.0))
	for button in buttons:
		button.transform = carry * button.transform


## The nodes that make up this deck's own box, hidden in a cabinet that is its
## housing. Each deck names its own.
func _housing() -> Array[Node3D]:
	return []


func on_av_topology_changed(_links: Array) -> void:
	# Built in: there is no lead, and the feed build_into set is the whole of it.
	if built_into != null:
		return
	# The reported list is this ONE cable's cords. AvSource asks every cable this
	# deck's own sockets touch: a deck with its picture on one lead and its sound
	# on another had whichever resolved last overwrite the whole of its routing,
	# so the other half went silently dead.
	#
	# Shared with RetroSystem, which is how these decks gained the rules they were
	# written without: a multi-way socket read through channel_for(), a sink with
	# no screen of its own, a stereo lead, and a picture and a sound that land in
	# two different boxes.
	var feed := AvSource.resolve(self, true)
	_apply_av_feed(feed.primary_sink() as RetroTV, not feed.video_sinks.is_empty(),
		feed.left, feed.right)


func _apply_av_feed(tv: RetroTV, video: bool, l: int, r: int) -> void:
	var previous := connected_tv
	_feed_video = video
	_feed_left = l
	_feed_right = r
	connected_tv = tv
	# No picture to move on or off anything: a set reads get_video_texture() and
	# stops getting one the moment the cord leaves the socket.
	if previous != tv:
		if is_instance_valid(previous):
			previous.hide_osd()
			previous.on_av_source_lost(self)
		if tv != null:
			tv.on_av_source_found(self)
	# A channel with nowhere to go is silenced at its voice; the one still
	# connected plays on. See SpatialAudioEmitter.set_channel_gains.
	if _emitter:
		_emitter.set_channel_gains(1.0 if l >= 0 else 0.0, 1.0 if r >= 0 else 0.0)


func is_paused() -> bool:
	return _paused


## Ignore-gravity: the device floats where it is put instead of falling. Restored
## from a save through this flag, which FloatLock reads once at _ready.
func get_ignore_gravity() -> bool:
	return _float_lock != null and _float_lock.enabled


func set_ignore_gravity(on: bool) -> void:
	ignore_gravity = on
	if _float_lock != null:
		_float_lock.set_enabled(on)


func _exit_tree() -> void:
	if _vlc:
		_vlc.shutdown()
