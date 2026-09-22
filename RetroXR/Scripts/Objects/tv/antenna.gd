## The antenna, a set-top aerial: rabbit ears on a weighted base, and a coax lead.
##
## Plug the lead into a set's aerial socket — or into the ANT socket of an RF switch
## whose own pigtail is in one — and that set's RF input gains every channel this
## aerial receives, on the same dial as the switch's CH3 and CH4. Pull it and they
## are gone. What it "receives" is an HDHomeRun on the network plus any streams in
## channels.json (see TVLineup), which is why the tuner's settings live on THIS
## object's menu and not on the television's.
##
## ── Why it IS a CompositeCable ───────────────────────────────────────────────
## For every reason RfSwitch gives, and they are not repeated here: binning a plug
## bins the lead (StorageBox._free_lead casts plug.cable), ScenePersistence saves
## and restores on `is CompositeCable`, and the netplay seat/release events are
## inherited. A slim sibling would have to grow all three.
##
## ── What is different ────────────────────────────────────────────────────────
## The lead has ONE connector. End A is CAPTIVE — the cord is moulded into the base,
## so the scene ships a PlugB0 and no PlugA0 — which CompositeCable allows for
## through _plug_at. A lead with one connector joins nothing to anything, so links()
## is always empty and no source ever resolves THROUGH an aerial: it is not an A/V
## device, and AvSource needs no arm for it.
##
## What it feeds instead is found by asking where the connector sits, and the set is
## told directly (RetroTV.on_aerial_changed) rather than through
## on_av_topology_changed, which only ever reports cords with two seated ends.
class_name Antenna
extends CompositeCable

@onready var _body: RigidBody3D = $Body
@onready var _attach: Node3D = $Body/LeadAttach

## Test seam: what builds this aerial's lineup. Runtime always builds a TVLineup,
## which reads the player's channels.json and broadcasts for a tuner the moment it
## is asked for — neither of which a suite that restores an aerial from a save may
## do. Same idea as CompositeCable.netplay_manager_override.
static var lineup_override: Callable = Callable()

var _reach := 0.0
var _lineup: TVLineup = null
# The set this aerial was feeding at the last resolve, so one that has just lost
# it still hears so.
var _last_set: RetroTV = null


## Black boot, like the pigtail on the RF switch — see RfSwitch._init.
func _init() -> void:
	cord_colors = PackedColorArray([Color(0.07, 0.07, 0.08)])


func _ready() -> void:
	super._ready()
	# A dangling connector must not shove its own base across the top of the set.
	for plug: RcaPlug in _end_plugs(End.B):
		plug.add_collision_exception_with(_body)


# ── what it receives ──────────────────────────────────────────────────────────

## The channel list, built — and the network asked — on first use.
##
## Not at spawn: an aerial taken out of the menu and left on a shelf should cost
## nothing. The two things that legitimately want the list are a set it has just
## been plugged into and a player opening its menu, and both come through here.
func lineup() -> TVLineup:
	if _lineup == null:
		_lineup = (lineup_override.call() as TVLineup) if lineup_override.is_valid() \
			else TVLineup.new()
		_lineup.name = "TVLineup"
		add_child(_lineup)
	if not _lineup.is_loaded():
		_lineup.reload_channels()
	return _lineup


## The list if it has already been built, else null — for a caller that must not be
## the reason discovery starts.
func lineup_if_built() -> TVLineup:
	return _lineup


# ── where the lead goes ───────────────────────────────────────────────────────

func _connector() -> RcaPlug:
	return _plug_at(End.B, 0)


## The television this aerial is feeding, directly or through an RF switch.
func reached_set() -> RetroTV:
	var plug := _connector()
	var port: RcaPort = plug.seated_port() if plug != null else null
	if port == null:
		return null
	var dev := port.get_device()
	if dev is RetroTV:
		return dev as RetroTV
	if dev is RfSwitch:
		return (dev as RfSwitch).reached_set()
	return null


## Whether an RF switch stands between this aerial and its set.
func via_switch() -> bool:
	var plug := _connector()
	var port: RcaPort = plug.seated_port() if plug != null else null
	return port != null and port.get_device() is RfSwitch


## Tell the set at the far end — and the one that was there a moment ago.
##
## super first: it carries nothing, but it is also what reports the seat to the
## other players and emits topology_changed, which this object's menu listens to.
func _resolve() -> void:
	super._resolve()
	if not is_inside_tree():
		return
	var now := reached_set()
	# Untyped on purpose: _last_set may be a set that has since been freed, and a
	# typed loop variable refuses a freed instance before is_instance_valid can ask.
	for tv: Variant in [_last_set, now]:
		if tv != null and is_instance_valid(tv):
			(tv as RetroTV).on_aerial_changed()
	_last_set = now


# ── the lead ──────────────────────────────────────────────────────────────────

## One rope, from the base to the connector.
##
## NOT super's, which runs a rope between PlugA0 and PlugB0 and has no PlugA0 to
## start from.
func _build_rope() -> void:
	if not is_inside_tree():
		return          # a netplay client's local copy is freed before we get here
	var plug := _connector()
	if _rope == null or plug == null:
		return
	_rope.fray_segments_start = 0
	_rope.fray_segments_end = 0
	_rope.start_node = _attach
	_rope.end_node = plug
	# End at the connector's cable boss, not at the plug's origin, which sits on the
	# mating face well forward of where the cord actually enters.
	_rope.end_anchor_offset = plug.cable_anchor
	_rope._init_points()
	_reach = float(_rope.segment_count) * _rope.segment_length
	# The base guards _physics_process on this, so an override that forgets it
	# silently disables the tether below.
	_rope_built = true


## Keep the lead within its reach, moving whichever end is NOT being held — the
## rule RfSwitch._tether states at length, with one lead instead of two.
func _physics_process(_delta: float) -> void:
	if not _rope_built or _body == null or not is_instance_valid(_body):
		return
	var plug := _connector()
	if plug == null or not is_instance_valid(plug):
		return
	# Boss to boss, not origin to origin: see RfSwitch._tether.
	var from: Vector3 = _attach.global_position
	var to: Vector3 = plug.global_transform * plug.cable_anchor
	if not plug.is_held():
		PlugTether.reel_in(plug, to, from, _reach)     # loose connector, reel it in
		return
	if _body.freeze:
		return                  # both ends owned; the reach is the hands' problem
	var back := CableHaul.haul(_body, from, to, _reach)
	if back != Vector3.ZERO:
		_body.global_position += back


# ── options ───────────────────────────────────────────────────────────────────

## Called by the body, which is what the pointer actually finds.
func toggle_options_ui(camera: Node3D) -> void:
	AntennaOptionsPanel.toggle_for(self, _body, camera)


# ── save / restore ────────────────────────────────────────────────────────────

## The base's pose, for ScenePersistence — see RfSwitch.carried_body_pose: the root
## never moves, the player carries the Body, and without these two it restores at
## the origin and the tether hauls the connector out of its socket to reach it.
func carried_body_pose() -> Dictionary:
	if _body == null or not is_instance_valid(_body):
		return {}
	var p := _body.global_position
	var r := _body.global_rotation_degrees
	return {"position": [p.x, p.y, p.z], "rotation": [r.x, r.y, r.z]}


func restore_carried_body(data: Dictionary) -> void:
	if _body == null or not is_instance_valid(_body) or data.is_empty():
		return
	var p: Array = data.get("position", [])
	var r: Array = data.get("rotation", [])
	if p.size() == 3:
		_body.global_position = Vector3(p[0], p[1], p[2])
	if r.size() == 3:
		_body.global_rotation_degrees = Vector3(r[0], r[1], r[2])
	# The rope was built around wherever the base stood a frame ago.
	call_deferred("_build_rope")
