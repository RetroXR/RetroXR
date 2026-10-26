## SystemAvPorts — a console's phono sockets and where what goes in them ends up.
##
## Lifted out of system.gd (its "Cable management" A/V half). Hardware with real
## A/V sockets (the NES, the Wii's multi-out) wears them instead of a captive
## lead, and nothing plays until a lead is run to a set. This builds the sockets,
## and every time a plug is seated or pulled anywhere on a lead it is asked again
## where the picture and the sound now go (AvSource.resolve) and tells the sets.
##
## The state stays readable on the machine under its old names (_av_ports, _av_tv,
## _av_stereo, _av_speaker_l/_r): tests, probes and the mods' probes read and
## stand those in, so RetroSystem forwards them here as properties.
class_name SystemAvPorts
extends Node

var _host: RetroSystem = null
var _audio: SystemAudio = null

## The sockets built, in channel order. Empty on a machine with a captive lead.
var ports: Array = []
## The sink carrying this console's SOUND. Node3D, not RetroTV: a pair of powered
## speakers is a sink with no screen, and the picture can be going somewhere else
## entirely.
var audio_sink: Node3D = null
## The set showing the PICTURE: the first video sink.
var video_tv: RetroTV = null
## Every sink this machine currently reaches — each has been told it is here, and
## each decides for itself which of its inputs that means.
var sinks: Array[Node3D] = []
## True once an AUDIO_R socket exists — stereo hardware. Mono hardware has one
## audio socket, and its single cord drives BOTH voices to the same speaker.
var stereo: bool = false
## Which of the set's speakers each audio channel reaches — 0 left, 1 right, -1
## nowhere. The picture, the sound and the set's controls each follow a different
## cord, because a lead can carry any of them alone.
var speaker_l: int = -1
var speaker_r: int = -1
## Each cord as "OUT->IN", with (!) where its two ends sit on different channels.
## Built by on_topology_changed, printed by apply_feed.
var cord_summary: String = "none"
## Last routing reported to the log, so re-resolving the same wiring is quiet and
## only real changes are announced.
var _last_routing: String = ""


## `audio` is the machine's own SystemAudio: a cord moving between sockets has to
## invalidate its gain cache (apply_feed), and nothing else outside the machine
## may reach it.
func setup(host: RetroSystem, audio: SystemAudio) -> void:
	_host = host
	_audio = audio


## Build the sockets a `uses_av_ports` console wears, and let the model seat them
## on its own moulded jacks.
##
## Video and ONE audio channel on mono hardware, where the second socket is the
## whole of its sound. Where that cord lands decides which single speaker plays —
## see on_topology_changed.
func build() -> void:
	var model := _host.get_model()
	# Named for the channel, matching the decks, so a save file reads the same on
	# either kind of hardware.
	const PORT_NAMES := {
		RcaPort.Channel.VIDEO: "VideoOut",
		RcaPort.Channel.AUDIO_L: "AudioLOut",
		RcaPort.Channel.AUDIO_R: "AudioROut",
	}
	var channels: Array = model.av_port_channels()
	# Read off the CHANNEL LIST rather than off the sockets built, because those two
	# stopped being the same thing: a multi-way machine is as stereo as any other and
	# has one hole. Without this the Wii's left cord also fed the right speaker.
	for ch: int in channels:
		if ch == RcaPort.Channel.AUDIO_R:
			stereo = true
	var built: Array = []
	if model.av_ports_are_multi_way():
		# One socket for the lot — an AV Multi Out. Which cord carries which signal is
		# MultiAvPort.channel_for's business from here on; WHICH socket is the model's,
		# because the shell is shared across the Nintendo consoles and the pinout is
		# not. The Wii's is the fallback for a model that claims multi-way and names
		# nothing, so that mistake costs a wrong-shaped hole rather than no picture.
		var path: String = model.av_multi_port_scene()
		if path.is_empty():
			path = "res://Scenes/Objects/system_models/wii/wii_av_port.tscn"
		var multi: PackedScene = load(path)
		if multi != null:
			var port := multi.instantiate() as RcaPort
			port.name = "AvMultiOut"
			_host.add_child(port)
			built.append(port)
		else:
			push_warning("[RetroSystem] A/V multi-out scene %s did not load" % path)
	else:
		var scene: PackedScene = load("res://Scenes/Objects/cables/rca_port.tscn")
		if scene == null:
			push_warning("[RetroSystem] rca_port.tscn did not load; no A/V sockets built")
			return
		for ch: int in channels:
			var port := scene.instantiate() as RcaPort
			port.name = str(PORT_NAMES.get(ch, "AvOut"))
			port.channel = ch as RcaPort.Channel
			port.direction = RcaPort.Direction.OUT
			_host.add_child(port)
			built.append(port)
	ports = built
	# After add_child: the model places these in world space off its own meshes.
	model.configure_av_ports(built)
	_print_legend(built)
	# Hide the captive lead's own connector. CableAttachPoint carries a PortVisual —
	# the yellow RCA plug that reads as the lead permanently seated in the console —
	# and on a shell like the NES the model parks it right in the VIDEO jack. With
	# sockets there is no captive lead, so leaving it there blocks the very jack the
	# player has to plug into.
	for chan: RetroSystem.VideoChannel in _host.video_channels():
		var visual := chan.attach.get_node_or_null("PortVisual") as Node3D
		if visual != null:
			visual.hide()


## Silkscreen the A/V row: the outlined box, the words under the jacks and the AV OUT
## heading. Console hardware is a source, so every one of these reads OUT.
##
## Stand-ins only, the same rule _place_name_label follows: a detailed shell carries
## its own printing in its texture, and ours would sit on top of it.
##
## Parented to the cabinet rather than to the model, which keeps it out of
## body_aabb() — that walks the body and the model, and a plate merged into it would
## drag the nameplate off the front face.
func _print_legend(built: Array) -> void:
	var model := _host.get_model()
	if model == null or model.has_baked_shell():
		return
	# A multi-way socket gets no phono legend. AvLegend draws a bracket over an audio
	# PAIR and a word under each jack, and a machine with one hole has neither — the
	# Wii prints "AV MULTI OUT" beside its socket instead, from its own model.
	if model.av_ports_are_multi_way():
		return
	var legend := AvLegend.attach(_host, built)
	if legend != null:
		model.configure_av_legend(legend)


## Called (through RetroSystem.on_av_topology_changed) by a CompositeCable whenever
## a plug is seated or pulled anywhere on it.
##
## Mono, so there is one audio answer rather than two: the single cord either
## reaches one of the set's speakers or it reaches nothing. Both of this console's
## voices are then played AT that one speaker, which is what a mono feed into one
## input sounds like — two coincident sources sum, no downmix needed.
func on_topology_changed() -> void:
	var feed := AvSource.resolve(_host, stereo)
	cord_summary = feed.summary()
	apply_feed(feed.video_sinks, feed.audio_sink, feed.left, feed.right)


func apply_feed(video_devs: Array[RetroTV], audio_dev: Node3D, l: int, r: int) -> void:
	# The set every single-display consumer means: the wiimote's pointer, the RF
	# channel check, "has the picture moved to a television". The FIRST video sink,
	# and the only one that was ever resolved before.
	var video_dev: RetroTV = video_devs[0] if not video_devs.is_empty() else null
	# The conclusion, not the wiring — RcaPort logs each cord as it lands, this
	# says what they added up to. Picture and sound resolve independently below, so
	# "video=<none> audio=TV" is a real and easily-missed state: the console is
	# heard but never seen, which reads from the room as a dead console.
	#
	# Only on CHANGE. Seating one lead re-resolves the routing once per cord per
	# end, so a plain three-cord hookup would otherwise print this eighteen times
	# and bury the transition that matters.
	var names := PackedStringArray()
	for dev in video_devs:
		names.append(String(dev.name))
	var routing := "video=%s audio=%s  cords: %s" % [
		"<none>" if names.is_empty() else ", ".join(names),
		String(audio_dev.name) if audio_dev != null else "<none>",
		cord_summary]
	if routing != _last_routing:
		_last_routing = routing
		print("[RetroSystem] A/V feed: %s" % routing)
		# A cord bridging two different channels conducts nothing either side can
		# use — video out into an audio in is the classic one, and it leaves a set
		# that plays sound perfectly while showing blue.
		if cord_summary.contains("(!)"):
			push_warning("[RetroSystem] a cord has its ends on DIFFERENT channels "
				+ "(marked !) — it carries nothing. Check the colours match end to end.")
	speaker_l = l
	speaker_r = r
	# The cached pair is keyed on the gains last sent, not on the routing, so a
	# cord moving between sockets has to invalidate it or the new silence (or the
	# new sound) never reaches the mixer. Told rather than inferred: SystemAudio
	# reads the routing through audio_speakers() and cannot see it change.
	#
	# Safe to call here, one line BEFORE audio_sink is assigned, because everything
	# route_changed touches is keyed on the speakers rather than on the set. It
	# must not grow a dependency on _audio_tv(), which is still the old sink at
	# this point; the position follows on the next frame's update_position().
	_audio.route_changed()
	var prev_audio := audio_sink
	audio_sink = audio_dev
	# The PICTURE follows the video cord alone: a lead with only its audio end in
	# leaves the set on its blue no-signal screen, as it would.
	var showing: RetroTV = video_dev
	if showing != video_tv:
		if is_instance_valid(video_tv):
			_host.on_tv_disconnected(null)
		video_tv = showing
		if showing != null:
			_host.on_tv_connected(showing, null)
	# EVERY sink is told, picture and sound alike, because being told is what lets a
	# set work out which of its own inputs this machine is on — and a set that has
	# not been told shows its blue screen no matter what is cabled to it.
	#
	# One sink used to be told, and it was the AUDIO one when there was any: wire
	# the tower's sound to a speaker pair and its picture to a monitor, and the
	# thing that got the announcement was the speakers, which have no screen. The
	# monitor was never told about the machine plugged into it.
	var now: Array[Node3D] = []
	for dev in video_devs:
		now.append(dev)
	if audio_dev != null and not now.has(audio_dev):
		now.append(audio_dev)
	for old_sink in sinks:
		if is_instance_valid(old_sink) and not now.has(old_sink):
			old_sink.on_av_source_lost(_host)
	for sink in now:
		if not sinks.has(sink):
			sink.on_av_source_found(_host)
	sinks = now
	# A sink only pushes its level and its decode at machines whose SOUND lands on
	# it, so the one now carrying the sound has to hear about it even when it was
	# already a sink — a set showing this machine's picture that the white and red
	# cords have just come back to from an amplifier. It was never "found" a second
	# time. An amplifier needs nothing here: it is never a picture sink, so found and
	# lost already cover every move of its own. Optional on the sink side: only a
	# set has it.
	if audio_dev != prev_audio and is_instance_valid(audio_dev) \
			and audio_dev.has_method("on_audio_source_routed"):
		audio_dev.on_audio_source_routed(_host)
