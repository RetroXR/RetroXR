## SystemVideoLead — the captive video-out lead a machine without A/V sockets
## comes with: one cable per video channel, built, parked, clamped to its reach,
## switched off with Enable Video Out, and freed with the machine.
##
## A child of the RetroSystem it serves, created in _init beside the other
## components. The CHANNELS stay on RetroSystem (VideoChannel, video_channels()):
## they are the one record both routes read -- a captive lead sets a channel's
## set through on_tv_connected, a composite cable through SystemAvPorts.apply_feed -- and
## a second owner would be a second answer to "which set shows this machine".
## What lives here is the lead itself, the rope and plugs at the end of it.
##
## Lifted out of system.gd whole. Hardware that wears real sockets (the NES, the
## Wii) never builds one: RetroSystem._ready calls spawn() only when the model
## does not use A/V ports. _physics_process stays on the machine, which is the
## body the tick belongs to, and calls clamp_leads() from it.
class_name SystemVideoLead
extends Node

# Cable scene to instantiate
const CABLE_SCENE := preload("res://Scenes/Objects/cables/cable.tscn")

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null


func setup(host: RetroSystem) -> void:
	_host = host


## Put the lead's audio pair into the L and R sockets of the input the picture
## cord just went into, and take them out again when it leaves.
##
## The pair travels with the picture because on a CAPTIVE lead the sound already
## does: a machine with no A/V sockets of its own has one connection to a set, and
## on_tv_connected is the whole of it. Leaving the two connectors dangling in front
## of the television while the yellow one was seated would have said the opposite —
## that they route something, and that this lead was half plugged in.
##
## Hardware that wears real sockets (the NES, the Wii) never comes through here:
## it has no captive lead at all, and a spawned CompositeCable resolves every cord
## on its own. See CompositeCable._resolve.
func seat_audio_pair(ch: int, tv: RetroTV) -> void:
	var channels := _host.video_channels()
	if tv == null or ch < 0 or ch >= channels.size():
		return
	var pair: Array = channels[ch].audio_plugs
	if pair.is_empty():
		return
	var plug := RetroSystem._live(channels[ch].plug) as CablePlug
	if plug == null:
		return
	var sockets: Array = tv.audio_ports(tv.input_holding(plug))
	for c in mini(pair.size(), sockets.size()):
		var p := RetroSystem._live(pair[c]) as CablePlug
		var port := sockets[c] as RcaPort
		if p != null and port != null and port.enabled and port.seated_plug() == null:
			port.pick_up_object(p)


func release_audio_pair(ch: int, tv: RetroTV) -> void:
	var channels := _host.video_channels()
	if tv == null or not is_instance_valid(tv) or ch < 0 or ch >= channels.size():
		return
	for extra: Variant in channels[ch].audio_plugs:
		var p := RetroSystem._live(extra) as CablePlug
		if p != null:
			_release_plug(tv.socket_holding(p), p)


## The video-out lead hangs off the room, not the machine — a rope between two
## bodies cannot be parented to either — so a deleted machine left its lead lying
## where it was, still seated in the television if it had been plugged in. Each
## end is dropped out of whatever socket holds it first, so the set hears the
## unplug, as ScenePersistence.clear_scene does. A lead not yet hung on the room
## (its add is deferred) is freed all the same.
func free_cables() -> void:
	var channels := _host.video_channels()
	for i in channels.size():
		var inst := RetroSystem._live(channels[i].cable) as Node
		if inst == null:
			continue
		var ends: Array = [channels[i].plug]
		ends.append_array(channels[i].audio_plugs)
		for e: Variant in ends:
			var p := RetroSystem._live(e) as CablePlug
			if p != null:
				p.drop()
		inst.queue_free()
		channels[i].cable = null


## Build the lead for every channel, hung on the room one deferred call later.
func spawn() -> void:
	var channels := _host.video_channels()
	for i in channels.size():
		channels[i].cable = CABLE_SCENE.instantiate()
	# Add cables to scene root so they're not affected by system's RigidBody transform weirdness
	_add_cables_to_scene.call_deferred()


func _add_cables_to_scene() -> void:
	var channels := _host.video_channels()
	# Deferred from spawn(), so a room change can land in between: during
	# a transition there is no current scene to hang the cables on, and this
	# system is on its way out with it.
	if not _host.is_inside_tree() or _host.get_tree().current_scene == null:
		return
	for i in channels.size():
		var inst: Node3D = channels[i].cable
		_host.get_tree().current_scene.add_child(inst)
		# Track cable in the "spawned" group so clear_scene() includes it.
		inst.add_to_group("spawned")
		var plug := inst.get_node("CablePlug") as CablePlug
		var rope := inst.get_node("VerletRope") as VerletRope
		channels[i].plug = plug
		channels[i].rope = rope

		# Tell the plug who owns it and which channel it carries
		plug.set_system(_host)
		plug.channel = i
		plug.channel_label = channels[i].label
		_decorate_channel_plug(plug, i)

		# Exclude the plug from colliding with this system so it doesn't jitter on spawn
		plug.add_collision_exception_with(_host)

		# Stand the plug off the rope's start anchor along the way the port faces,
		# so the lead lays itself out of the machine rather than across it.
		plug.global_position = _plug_park_pos(i, 0)

		# Per-channel wiring, when the model asks for something other than the
		# cable scene's own composite pigtail. A channel carrying one signal wants
		# one wire, in its own colour — the DS's bottom screen is a lone blue cord
		# beside the top's yellow/white/red three.
		var wires := channels[i].wires
		if not wires.is_empty():
			rope.ribbon_count = wires.size()
			rope.ribbon_colors = wires

		# The audio pair, and whether this channel has one at all.
		var pair: Array = _adopt_audio_pair(inst, i, rope)

		# Wire rope anchors: start = system's attach point, end = plug
		rope.start_node = channels[i].attach
		# Same correction at THIS end. The attach point sits at the console's jack,
		# and the plug seated in it is modelled from its collar too — so without
		# this the cord started inside the barrel and appeared to sprout from the
		# middle of the connector rather than the strain relief behind it.
		rope.start_anchor_offset = _port_cable_anchor(channels[i].attach)
		if pair.is_empty():
			rope.end_node = plug
			# End the cord AT the RCA plug's cable boss. The plug's origin is its
			# SEATING reference, up at the collar, so a zero offset runs the tube out
			# through the barrel.
			rope.end_anchor_offset = plug.cable_anchor
		else:
			# One tail per cord, each ending at its own connector's boss. The trunk's
			# terminal particle is left unanchored on purpose — the plugs carry the
			# breakout, the way an unsupported junction behaves on the real lead.
			var groups := PackedInt32Array()
			for c in rope.ribbon_count:
				groups.append(c)
			rope.fray_end_groups = groups
			rope.end_node = null
			var ends: Array = [plug, pair[0], pair[1]]
			for c in ends.size():
				var p: CablePlug = ends[c]
				rope.set_fray_end_node(c, p)
				rope.set_fray_end_anchor_offset(c, p.cable_anchor)
		rope._init_points()
		channels[i].max_reach = _rope_reach(rope)

		# Restore a pending TV connection requested before the cable was ready
		if channels[i].pending_tv != null:
			print("[RetroSystem] _add_cables_to_scene: restoring pending TV connection (ch %d)" % i)
			_snap_cable_to_tv(channels[i].pending_tv, i, int(channels[i].pending_input))
			channels[i].pending_tv = null
			channels[i].pending_input = 0
	apply_video_out()


## Take charge of one lead's audio pair, or retire it.
##
## The cable scene ships a composite pigtail — a picture cord with the audio pair
## beside it — because that is what all but one of this room's leads is. A channel
## whose model asks for a single wire has no pair to break out, so the two spare
## connectors are freed and the rope goes back to the plain unfrayed cord it was:
## the fray count comes off, and the trunk grows by the tail it is no longer
## spending, which keeps every channel's reach the 1.80 m the lead is.
##
## Returns [left, right], or [] on a one-wire channel.
func _adopt_audio_pair(inst: Node3D, channel: int, rope: VerletRope) -> Array:
	var channels := _host.video_channels()
	var pair: Array = []
	for nm in ["CablePlugL", "CablePlugR"]:
		var p := inst.get_node_or_null(nm) as CablePlug
		if p != null:
			pair.append(p)
	if rope.ribbon_count < 3 or pair.size() < 2:
		for p: CablePlug in pair:
			p.queue_free()
		rope.segment_count += rope.fray_segments_end
		rope.fray_segments_end = 0
		channels[channel].audio_plugs = []
		return []
	for c in pair.size():
		var p: CablePlug = pair[c]
		# NO set_system: on this lead the sound travels with the picture, so these
		# two are the picture cord's companions rather than routes of their own (see
		# seat_audio_pair). A plug that named a host would have the television take
		# it for a second video connection from this machine.
		p.channel = channel
		p.add_collision_exception_with(_host)
		p.global_position = _plug_park_pos(channel, c + 1)
	channels[channel].audio_plugs = pair
	return pair


## Sideways step per connector across the face the port is on, so three plugs on
## one lead do not spawn inside each other. Indexed picture, left, right.
const _PLUG_PARK_SPREAD := [0.0, -0.02, 0.02]


## Where connector `index` of channel `ch`'s lead stands when the lead is built or
## parked, in world space.
##
## Through the attach point's TRANSFORM, not its position: the model's spawn offset
## is read in that frame (see RetroSystemModel.get_cable_spawn_offset), so the cord
## trails out of the face its port is on whichever way the machine happens to be
## turned. Added in the world, it always pointed at world -Z — which is the back of
## a console standing square to the room and nothing at all on one that has been
## picked up, turned round, or built with its port on the flank.
func _plug_park_pos(ch: int, index: int) -> Vector3:
	var channels := _host.video_channels()
	var attach := RetroSystem._live(channels[ch].attach) as Node3D
	if attach == null:
		return _host.global_position
	var spread: float = _PLUG_PARK_SPREAD[mini(index, _PLUG_PARK_SPREAD.size() - 1)]
	return attach.global_transform * (_host.get_model().get_cable_spawn_offset(ch)
		+ Vector3(spread, 0, 0))


## How far one lead reaches from its attach point: the trunk, plus the tail a
## frayed end hangs off it. Read off the rope rather than tabled, so a scene that
## re-lengths the cord cannot leave the tether behind.
func _rope_reach(rope: VerletRope) -> float:
	var fray_seg: float = rope.fray_segment_length
	if fray_seg <= 0.0:
		fray_seg = rope.segment_length
	return rope.segment_count * rope.segment_length \
		+ float(rope.fray_segments_end) * fray_seg


## Where the cord meets the plug seated in the console's own jack, in the attach
## point's local space — the mirror of CablePlug.cable_anchor at the far end of
## the same lead, and derived the same way so reshaping the connector cannot
## desync either end.
##
## Zero when the model hides PortVisual: with no plug modelled at this end the
## cord should leave the jack itself, which is what the attach point already is.
func _port_cable_anchor(attach: Node3D) -> Vector3:
	var pv := attach.get_node_or_null("PortVisual") as MeshInstance3D
	if pv == null or pv.mesh == null or not pv.visible:
		return Vector3.ZERO
	var ab: AABB = pv.mesh.get_aabb()
	# Cable trails -Z (VerletRope.plug_exit_axis), so the boss is at min Z.
	return pv.transform * Vector3(ab.get_center().x, ab.get_center().y, ab.position.z)


## Show/hide and park the leads per the machine's video_out_enabled. Disabling
## first unplugs any connected TV (so no picture lingers), then hides the whole
## cable and freezes it out of the simulation.
func apply_video_out() -> void:
	var channels := _host.video_channels()
	# The only thing clamp_leads does is keep the video-out leads inside
	# their reach. With the leads hidden and frozen there is nothing to clamp, so
	# the tick goes off entirely rather than opening with a flag test 90 times a
	# second — and a handheld, which has no video out, never ticks at all.
	_host.set_physics_process(_host.video_out_enabled)
	for i in channels.size():
		var inst := RetroSystem._live(channels[i].cable) as Node3D
		var plug := RetroSystem._live(channels[i].plug) as CablePlug
		if inst == null or plug == null:
			continue
		var tv := RetroSystem._live(channels[i].tv) as RetroTV
		# The whole lead goes with the picture cord: the audio pair beside it is on
		# the same cable, and a set fed by a machine with its video out switched off
		# is not fed at all.
		var ends: Array = [plug]
		for extra: Variant in channels[i].audio_plugs:
			var p := RetroSystem._live(extra) as CablePlug
			if p != null:
				ends.append(p)
		if not _host.video_out_enabled and tv != null:
			# Ask the set which socket is holding each rather than assuming the first:
			# a television has four composite inputs and this lead may be in any of
			# them, and naming CompositePort left a lead in Composite 2 seated while
			# its video-out was switched off.
			for e: CablePlug in ends:
				_release_plug(tv.socket_holding(e), e)
		for c in ends.size():
			var p: CablePlug = ends[c]
			p.enabled = _host.video_out_enabled
			if _host.video_out_enabled:
				# A plug already socketed into a TV (e.g. restored from a save, where
				# apply_video_out runs right after the snap) is held frozen at the port by
				# the snap zone. Unfreezing/parking it here drops it off the socket, and it
				# then drifts under gravity + rope tension. Only park a free-dangling plug.
				if not p.is_picked_up():
					p.freeze = false
					p.global_position = _plug_park_pos(i, c)
					p.linear_velocity = Vector3.ZERO
			else:
				p.freeze = true
		if _host.video_out_enabled:
			inst.visible = true
			inst.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			inst.visible = false
			inst.process_mode = Node.PROCESS_MODE_DISABLED


## How far a released connector is drawn out of its socket, in metres. Clear of the
## 60 mm grab distance every RcaPort uses, so it cannot be snapped straight back up.
const PULLED_CLEAR := 0.12


## Take a plug out of the socket holding it and stand it clear of the bank.
##
## Disarming the zone around the drop is not enough on its own once three cords go
## into a set at once. A composite input's sockets are 18 mm apart and each reaches
## 60 mm, so a plug released at the panel is standing inside its NEIGHBOURS' grab
## areas as well as its own — pull the lead and the set caught the red connector in
## the socket the white one had just left. So it is also drawn back along the
## socket's own axis, which is the way a hand takes it out.
##
## The transform goes through the physics server as well as the node: the body is
## live again the moment it is dropped, and a transform written only on the node is
## overwritten on the next tick, putting it back in the socket. Same recipe, and the
## same reasons, as CompositeCable.net_release_plug.
func _release_plug(port: XRToolsSnapZone, plug: CablePlug) -> void:
	if port == null or not is_instance_valid(port):
		return
	port.enabled = false
	port.drop_object()
	if is_instance_valid(plug):
		plug.global_position = port.global_position \
			+ port.global_transform.basis.z.normalized() * PULLED_CLEAR
		PhysicsServer3D.body_set_state(plug.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM, plug.global_transform)
	_reopen_port(port)


## Let the deferred drop handler and the area's body_exited both run before the
## socket is live again. Deliberately not awaited by the caller: the release has
## already happened, and this only reopens the socket behind it.
func _reopen_port(port: XRToolsSnapZone) -> void:
	await _host.get_tree().physics_frame
	await _host.get_tree().physics_frame
	if is_instance_valid(port):
		port.enabled = true


## Mark a multi-output host's second lead so the player can tell the two apart: a
## blue connector on the BOTTOM channel against the composite trio of the top.
##
## No printed tag. The word TOP floated in the air off the end of a cable, which is
## not a thing a lead does, and it was redundant twice over by the time it read:
## the top lead is a yellow/white/red pigtail and the bottom one a single blue
## cord, which is the same distinction the hardware would make.
func _decorate_channel_plug(plug: CablePlug, channel: int) -> void:
	if channel <= 0:
		return
	plug.plug_color = Color(0.2, 0.6, 1.0)


## Keep every lead inside its reach of where it leaves the machine. Called from
## the machine's own _physics_process while video out is on.
func clamp_leads() -> void:
	var channels := _host.video_channels()
	for i in channels.size():
		var max_len: float = channels[i].max_reach
		if max_len <= 0.0:
			continue   # cable not built yet
		var plug := RetroSystem._live(channels[i].plug) as CablePlug
		var attach := RetroSystem._live(channels[i].attach) as Node3D
		if plug == null or attach == null:
			continue
		# Snapped to TV or actively held by the user — don't fight whoever owns the plug
		if RetroSystem._live(channels[i].tv) == null:
			_clamp_plug(plug, attach.global_position, max_len)
		# Every connector on the lead is on the same cord and reaches the same
		# distance; the pair is guarded on its own hold rather than on the channel's
		# television, since either of them can be sitting in a socket while the
		# picture cord is not.
		for extra: Variant in channels[i].audio_plugs:
			var p := RetroSystem._live(extra) as CablePlug
			if p != null:
				_clamp_plug(p, attach.global_position, max_len)


## Hold one plug within the cord's reach of where the cord leaves the machine.
## A hard clamp rather than a spring, for the reason CompositeCable._physics_process
## gives: over-extension here runs to a metre and a spring stiff enough to haul a
## plug back at that distance launches it. PlugTether says how.
func _clamp_plug(plug: CablePlug, attach_pos: Vector3, max_len: float) -> void:
	if plug.is_picked_up():
		return          # a hand, a beam or a socket owns it
	PlugTether.reel_in(plug, plug.global_position, attach_pos, max_len)


## Restore a cable→TV connection after loading from a save file.
## Safe to call before the cables have finished spawning — the snap will be
## deferred until _add_cables_to_scene() runs if the plug isn't ready yet. Reached
## through RetroSystem.restore_cable_connection, the name persistence calls.
## `channel` picks the video-out cable (0 on classic single-cable systems);
## `tv_input` picks which of the set's four composite inputs to land in.
func restore_connection(tv: RetroTV, channel: int = 0, tv_input: int = 0) -> void:
	var channels := _host.video_channels()
	if channel < 0 or channel >= channels.size():
		channel = 0
	print("[RetroSystem] restore_cable_connection: ch=%d in=%d plug=%s tv=%s" %
		[channel, tv_input, channels[channel].plug if channel < channels.size() else null, tv])
	if channel < channels.size() and channels[channel].plug != null:
		_snap_cable_to_tv(tv, channel, tv_input)
	else:
		print("[RetroSystem] cable plug not ready yet, deferring restore")
		channels[channel].pending_tv = tv
		channels[channel].pending_input = tv_input


func _snap_cable_to_tv(tv: RetroTV, channel: int = 0, tv_input: int = 0) -> void:
	var channels := _host.video_channels()
	tv.accept_plug_restore(channels[channel].plug, tv_input)
