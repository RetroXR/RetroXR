## speaker_tests — the surround loudspeakers: their geometry, their socket, and
## what a lead into a television's speaker output resolves to.
##
##   godot --headless --path RetroXR res://Tests/speaker_tests.tscn
##   godot --headless --path RetroXR res://Tests/speaker_tests.tscn -- --only=faces
##
## Headless, no core, no headset, no GPU. Exits non-zero on failure.
##
## The faces/ group is the one that needs explaining. It reads the meshes' STORED
## normals, because Godot's front face is the clockwise one and so
## generate_normals() returns the negative of the textbook (b-a) x (c-a) — a check
## that recomputes a normal from vertex order reports an inside-out mesh as
## outward, which is how both cabinets shipped inside out twice during authoring.
## An inside-out solid does not look inverted; it stops OCCLUDING, so it reads as
## missing geometry.
extends Node3D

const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SUBWOOFER := preload("res://Scenes/Objects/appliances/subwoofer.tscn")
const SPEAKER_CABLE := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const RCA_PORT := preload("res://Scenes/Objects/cables/rca_port.tscn")

const MESHES := {
	"satellite": "res://Scenes/Objects/appliances/speaker_satellite.res",
	"subwoofer": "res://Scenes/Objects/appliances/speaker_sub.res",
}

## Two faces sharing a plane and a facing interleave and flicker; nearly sharing
## one z-fights. Overlap in the other two axes is part of the test, because faces
## at different positions cannot do either however parallel they are.
const MIN_PLANE_GAP := 0.0005

var _case := ""
var _checks := 0
var _case_checks := 0
var _failed: Array[String] = []
var _spawned: Array[Node] = []


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(
		func() -> void:
			push_error("[speaker] watchdog")
			get_tree().quit(2))
	get_tree().current_scene = self
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.split("=")[1]

	var cases: Array = [
		["faces/no cabinet is baked inside out", _f_outward],
		["faces/no two faces share a plane and a facing", _f_planes],
		["jack/the input is a generic speaker socket", _j_channel],
		["jack/the socket faces out of the back panel", _j_facing],
		["jack/the cone faces out of the baffle", _j_cone],
		["routing/a cabinet on each output takes that channel", _r_each_output],
		["routing/two cabinets on one output do not merge", _r_two_on_one],
		["routing/pulling the lead takes the channel away", _r_pull],
		["save/both cabinets and the lead are registered", _s_registered],
		["save/a cabinet round-trips through a save entry", _s_round_trip],
	]

	for entry in cases:
		var name: String = entry[0]
		if only != "" and not name.contains(only):
			continue
		_case = name
		_case_checks = 0
		await (entry[1] as Callable).call()
		# A case that asserted nothing aborted part way through.
		if _case_checks == 0:
			_failed.append(name)
			print("[speaker] FAIL %s  (no assertions ran)" % name)
		await _teardown()

	print("[speaker] %d checks, %d case(s) failed" % [_checks, _failed.size()])
	for f in _failed:
		print("[speaker]   failed: %s" % f)
	print("[speaker] RESULT=%s" % ("PASS" if _failed.is_empty() else "FAIL"))
	get_tree().quit(1 if not _failed.is_empty() else 0)


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	_case_checks += 1
	if cond:
		print("[speaker] PASS %s/%s" % [_case, what])
		return
	if not _failed.has(_case):
		_failed.append(_case)
	print("[speaker] FAIL %s/%s" % [_case, what])


func _check_eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [what, got, want])


func _teardown() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			if n.has_method("drop_and_free"):
				n.call("drop_and_free")
			else:
				n.queue_free()
	_spawned.clear()
	await _wait(4)


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _hold(n: Node) -> Node:
	_spawned.append(n)
	return n


# ── faces ─────────────────────────────────────────────────────────────────────

## Only surface 0 is judged. The cone and the bores are open funnels, and an open
## surface reads -1 on an axis it is edge-on to whichever way it is wound.
func _f_outward() -> void:
	var axes := {"+X": Vector3.RIGHT, "-X": Vector3.LEFT, "+Y": Vector3.UP,
		"-Y": Vector3.DOWN, "+Z": Vector3.BACK, "-Z": Vector3.FORWARD}
	for label: String in MESHES:
		var mesh: ArrayMesh = load(MESHES[label])
		var arrays := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for axis_label: String in axes:
			var axis: Vector3 = axes[axis_label]
			var best := 0
			for i in v.size():
				if v[i].dot(axis) > v[best].dot(axis):
					best = i
			_ok(n[best].dot(axis) > -0.0001,
				"%s shell faces out on %s" % [label, axis_label])


func _f_planes() -> void:
	for label: String in MESHES:
		var mesh: ArrayMesh = load(MESHES[label])
		var clashes := 0
		for axis in [Vector3.BACK, Vector3.FORWARD]:
			clashes += _plane_clashes(mesh, axis)
		_ok(clashes == 0, "%s has no overlapping coplanar faces" % label)


## Group the faces pointing along `axis` by their offset along it, then report any
## two groups closer than MIN_PLANE_GAP whose extents overlap in the other axes.
func _plane_clashes(mesh: ArrayMesh, axis: Vector3) -> int:
	var groups: Dictionary = {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for t in range(0, v.size(), 3):
			# The stored normals again, for the reason in the header.
			var nf: Vector3 = (n[t] + n[t + 1] + n[t + 2]) / 3.0
			if nf.normalized().dot(axis) < 0.999:
				continue
			var tc: Vector3 = (v[t] + v[t + 1] + v[t + 2]) / 3.0
			var key := snappedf(tc.dot(axis), 0.00005)
			var flat := Vector2(tc.x, tc.y) if absf(axis.z) > 0.5 else Vector2(tc.x, tc.z)
			if not groups.has(key):
				groups[key] = [flat, flat]
			var span: Array = groups[key]
			span[0] = Vector2(minf(span[0].x, flat.x), minf(span[0].y, flat.y))
			span[1] = Vector2(maxf(span[1].x, flat.x), maxf(span[1].y, flat.y))
	var keys := groups.keys()
	keys.sort()
	var clashes := 0
	for i in keys.size():
		for j in range(i):
			if absf(float(keys[i]) - float(keys[j])) >= MIN_PLANE_GAP:
				continue
			var a: Array = groups[keys[i]]
			var b: Array = groups[keys[j]]
			if a[0].x <= b[1].x and b[0].x <= a[1].x \
					and a[0].y <= b[1].y and b[0].y <= a[1].y:
				clashes += 1
				print("[speaker]   planes %+.4f and %+.4f overlap" % [keys[i], keys[j]])
	return clashes


# ── jack ──────────────────────────────────────────────────────────────────────

func _j_channel() -> void:
	for scene in [SATELLITE, SUBWOOFER]:
		var cab := _hold((scene as PackedScene).instantiate()) as Loudspeaker
		add_child(cab)
		await _wait(2)
		var port := cab.get_node("SpeakerIn") as RcaPort
		# A phono jack is generic: the socket at the far end names the channel, so
		# a cabinet that carried one of the six would be wrong.
		_check_eq(port.channel, RcaPort.Channel.AUDIO_SPEAKER, "the input is AUDIO_SPEAKER")
		_check_eq(port.direction, RcaPort.Direction.IN, "and an input")
		_check_eq(RcaPort.CHANNEL_SPEAKER[port.channel], -1, "naming no one speaker")


## A recess is symmetric and reads the same either way round, so the facing is
## asserted from the basis rather than from a render.
func _j_facing() -> void:
	for scene in [SATELLITE, SUBWOOFER]:
		var cab := _hold((scene as PackedScene).instantiate()) as Loudspeaker
		add_child(cab)
		await _wait(2)
		var port := cab.get_node("SpeakerIn") as Node3D
		_ok(port.transform.basis.z.dot(Vector3.FORWARD) > 0.99,
			"the socket's +Z leaves the back panel")
		_ok(port.position.z < 0.0, "and it sits behind the cabinet's centre")


func _j_cone() -> void:
	for scene in [SATELLITE, SUBWOOFER]:
		var cab := _hold((scene as PackedScene).instantiate()) as Loudspeaker
		add_child(cab)
		await _wait(2)
		var cone := cab.get_node("ConeFront") as Node3D
		_ok(cone.transform.basis.z.dot(Vector3.BACK) > 0.99, "the cone's +Z leaves the baffle")
		_ok(cone.position.z > 0.0, "and it sits in front of the cabinet's centre")
		var pos: PackedVector3Array = cab.get_speaker_positions()
		_check_eq(pos.size(), 1, "one cone is published")
		_ok(pos[0].distance_to(cone.global_position) < 0.001, "and it is that marker")


# ── routing ───────────────────────────────────────────────────────────────────

## A stand-in television: the six speaker outputs and nothing else. The real set's
## panel is covered by av_tests; what is under test here is the cabinet end.
func _fake_set() -> Array:
	var src := Node3D.new()
	src.name = "FakeSet"
	src.set_script(load("res://Tests/speaker_tests_sink.gd"))
	add_child(_hold(src))
	var outs: Array[RcaPort] = []
	for i in RcaPort.SPEAKER_OUT_CHANNELS.size():
		var p := RCA_PORT.instantiate() as RcaPort
		p.name = "Out%d" % i
		p.channel = RcaPort.SPEAKER_OUT_CHANNELS[i]
		p.direction = RcaPort.Direction.OUT
		# 250 mm apart, not the panel's real 18 mm pitch. An RcaPort has a 60 mm
		# grab distance, so on a realistic pitch a plug displaced by a second
		# seating is caught by the socket next door — which is the trap av_tests'
		# _unplug exists for, and it belongs to the PANEL rather than the cabinet
		# end this suite is isolating.
		p.position = Vector3(float(i) * 0.25, 0.4, 0.0)
		src.add_child(p)
		outs.append(p)
	await _wait(4)
	return [src, outs]


func _cable_up(out_port: RcaPort, at: Vector3) -> Loudspeaker:
	var cab := SATELLITE.instantiate() as Loudspeaker
	cab.position = at
	cab.freeze = true
	add_child(_hold(cab))
	var lead := SPEAKER_CABLE.instantiate() as Node3D
	add_child(_hold(lead))
	await _wait(4)
	out_port.pick_up_object(lead.get_node("PlugA0") as Node3D)
	(cab.get_node("SpeakerIn") as RcaPort).pick_up_object(lead.get_node("PlugB0") as Node3D)
	await _wait(6)
	return cab


func _r_each_output() -> void:
	var made: Array = await _fake_set()
	var src: Node3D = made[0]
	var outs: Array = made[1]
	var cabs: Array[Loudspeaker] = []
	for i in outs.size():
		cabs.append(await _cable_up(outs[i], Vector3(float(i) * 0.6, 0.0, 1.2)))

	var feed := AvSource.resolve(src, true)
	_check_eq(feed.audio_dest.size(), 6, "six channels resolve")
	for i in outs.size():
		var ch: int = RcaPort.SPEAKER_OUT_CHANNELS[i]
		var rec: Dictionary = feed.audio_dest.get(ch, {})
		_ok(rec.get("sink", null) == cabs[i],
			"%s reaches its own cabinet" % RcaPort.CHANNEL_NAMES[ch])
		# One cone, so the index into the cabinet is 0 — not the channel's own
		# speaker number, which indexes a television's array instead.
		_check_eq(int(rec.get("speaker", -1)), 0,
			"%s indexes the cabinet's one cone" % RcaPort.CHANNEL_NAMES[ch])


## Two cabinets on one socket is a wiring mistake a phono lead allows, so it has
## to have a defined answer rather than merging them.
func _r_two_on_one() -> void:
	var made: Array = await _fake_set()
	var src: Node3D = made[0]
	var outs: Array = made[1]
	var first := await _cable_up(outs[2], Vector3(0.0, 0.0, 1.2))
	var second := await _cable_up(outs[2], Vector3(0.8, 0.0, 1.2))

	var feed := AvSource.resolve(src, true)
	var rec: Dictionary = feed.audio_dest.get(RcaPort.Channel.AUDIO_C, {})
	var sink: Variant = rec.get("sink", null)
	_ok(sink == first or sink == second, "the centre lands on one of the two")
	_ok(not (sink == null), "rather than on neither")
	# A socket holds one plug, so the second seating displaces the first and the
	# loser reaches nothing rather than both being heard on the centre.
	_check_eq(feed.audio_dest.size(), 1, "and only that one channel resolves")
	var loser: Node3D = second if sink == first else first
	_ok(loser != sink, "the other cabinet is not also on the centre")


func _r_pull() -> void:
	var made: Array = await _fake_set()
	var src: Node3D = made[0]
	var outs: Array = made[1]
	var cab := await _cable_up(outs[4], Vector3(0.0, 0.0, 1.2))

	var feed := AvSource.resolve(src, true)
	_ok(feed.audio_dest.has(RcaPort.Channel.AUDIO_SL), "the surround resolves while cabled")
	_ok(is_instance_valid(cab), "and the cabinet is there")

	outs[4].drop_object()
	await _wait(6)
	var after := AvSource.resolve(src, true)
	_ok(not after.audio_dest.has(RcaPort.Channel.AUDIO_SL),
		"and stops resolving once the lead is pulled")


# ── save ──────────────────────────────────────────────────────────────────────

## PLAIN_SCENES is read only when LOADING, so a token missing here is a prop that
## spawns and then saves as nothing. deck_tests asserts the same way.
func _s_registered() -> void:
	var persistence := ScenePersistence.new()
	for token in ["loudspeaker", "subwoofer"]:
		_ok(persistence.PLAIN_SCENES.has(token), "PLAIN_SCENES carries %s" % token)
	_ok(persistence.LEAD_SCENES.has("speaker_cable"), "LEAD_SCENES carries speaker_cable")
	for token in ["loudspeaker", "subwoofer", "speaker_cable"]:
		_ok(persistence.instantiate(token) != null, "and %s instantiates" % token)


func _s_round_trip() -> void:
	var cab := _hold(SATELLITE.instantiate()) as Loudspeaker
	cab.position = Vector3(1.25, 0.5, -2.0)
	cab.rotation_degrees = Vector3(0.0, 40.0, 0.0)
	add_child(cab)
	await _wait(4)

	var persistence := ScenePersistence.new()
	var entry: Dictionary = persistence._serialize_node(cab, 1, {})
	_ok(not entry.is_empty(), "a cabinet serialises to an entry")
	_check_eq(entry.get("type", ""), "loudspeaker", "under its own token")

	var sub := _hold(SUBWOOFER.instantiate()) as Loudspeaker
	add_child(sub)
	await _wait(4)
	var sub_entry: Dictionary = persistence._serialize_node(sub, 2, {})
	# Both scenes share one script, so the token cannot come from the type.
	_check_eq(sub_entry.get("type", ""), "subwoofer", "and the subwoofer under its own")
