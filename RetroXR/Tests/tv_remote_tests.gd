## TV remote self-tests — the RETRO XR handset's own keys, headless, with no core, ROM or headset.
##
##     "$godot" --headless --path RetroXR res://Tests/tv_remote_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/tv_remote_tests.tscn -- --only=ray/
##
## The remote is RetroXR-models' generic/tv-remote: 26 keys, each one of the grid's cells.
##
##   dress/   every model key is a VRButton wearing the key, the tip is on the model's IrTip;
##   shapes/  every shape is what is drawn, no margin: each key's is its own triangles, the
##            laser's the shell's, the body's the shell's hull;
##   ray/     the desktop ray at every key's face takes THAT key, from above and tilted; aimed
##            into the 2 mm gap between two keys, or at the shell, it takes no key (the control:
##            the 3 mm-padded box adopt_button used to give would have taken the gap);
##   touch/   a fingertip on a key is that key's and no other's (the ring's arcs overlap as boxes);
##   keys/    each key does its cell on a set, a VCR, a DVD player and a record player, nothing
##            where the grid would grey the cell or leave it out; PREV/NEXT are a DVD's chapters;
##   aim/     with no grid up, a key acts on what the window points at, and on nothing turned away;
##   press/   a clicked key (the laser and the desktop click are one path) sinks 1.5 mm into the remote along
##            its own -Z and comes back, every one of the 26 and no other with it, and does its cell;
##   poke/    a tracked fingertip (a real XRController3D on a registered tracker: VRButton's own touch path)
##            pushed into a key sinks it 1.5 mm, fires it once and no other key, and lets it back up, with the
##            remote lying on a table and held tilted in the other hand, whose thumb on a key presses nothing;
##   grid/    a cell pressed on the floating grid sinks the matching key on the remote for a moment;
##   bay/     the battery cover is a CoverSlots cover that is the model's own cover, taken by the desktop ray
##            from below; a remote fresh from the spawn menu has two AAA cells in BatteryAAA1/2, shut in
##            while the cover is on; off, the ray from below takes each cell (the shell's laser shape has no
##            cover in it); back on, they are shut in again; a restored remote seeds none.
extends "res://Tests/test_suite.gd"

const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const DVD_SCENE := preload("res://Scenes/Objects/appliances/dvd_player.tscn")
const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")

## Written out again here, not read from TVRemote.KEY_CELLS: a key wired to the wrong
## cell must fail against something it was not copied from.
const PRINTED := {
	"KeyPower": "power", "KeySource": "source", "KeyVolDown": "vol_down", "KeyMute": "mute",
	"KeyVolUp": "vol_up", "KeyChDown": "ch_down", "KeyChUp": "ch_up", "KeyAudioMode": "audio_mode",
	"KeyStereo3d": "stereo3d", "KeyAspect": "aspect", "KeyAudioOut": "audio_out", "KeyEject": "eject",
	"KeyPrev": "prev", "KeyPlayPause": "playpause", "KeyNext": "next", "KeyRew": "rew", "KeyStop": "stop",
	"KeyFf": "ff", "KeyUp": "up", "KeyDown": "down", "KeyLeft": "left", "KeyRight": "right", "KeyOk": "ok",
	"KeyMenu": "menu", "KeyAudio": "audio", "KeySubtitle": "subtitle",
}
## A tenth of a millimetre.
const TOLERANCE := 0.0001
## The keys' travel, written out (not TVRemote.KEY_TRAVEL): real rubber keys go 0.8-1.5 mm, these the long end.
const TRAVEL := 0.0015
const FINGER := &"tv_remote_test_finger"
const HOLDER := &"tv_remote_test_holder"

var _spawned: Array[Node] = []
var _hand: Node3D = null


func _ready() -> void:
	suite_tag = "remote"
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[remote] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	for c: Array in [["dress/", _test_dress], ["shapes/", _test_shapes], ["ray/", _test_ray],
			["touch/", _test_touch], ["keys/", _test_keys], ["aim/", _test_aim], ["press/", _test_press],
			["bay/", _test_bay], ["poke/", _test_poke], ["grid/", _test_grid]]:
		if _wanted(str(c[0])):
			await (c[1] as Callable).call()
			await _cleanup()
	_finish()


func _wanted(what: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return what.begins_with(arg.substr(7)) or arg.substr(7).begins_with(what)
	return true


func _remote(at := Vector3(0, 1, 0)) -> TVRemote:
	var r := REMOTE.instantiate() as TVRemote
	r.freeze = true
	r.position = at
	add_child(r)
	_spawned.append(r)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return r


func _spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var n := scene.instantiate() as Node3D
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	n.position = at
	add_child(n)
	_spawned.append(n)
	await get_tree().process_frame
	return n


func _cap(b: VRButton) -> MeshInstance3D:
	return b.get_node("ButtonMesh") as MeshInstance3D


## The middle of a key's face in world space (a key's origin is its face's middle).
func _face(b: VRButton) -> Vector3:
	return _cap(b).global_transform.origin


func _faces_box(shape: Shape3D) -> AABB:
	var faces := (shape as ConcavePolygonShape3D).get_faces()
	var box := AABB(faces[0], Vector3.ZERO)
	for p in faces:
		box = box.expand(p)
	return box


func _same(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < TOLERANCE and a.end.distance_to(b.end) < TOLERANCE


# ── dress/ ────────────────────────────────────────────────────────────────────

func _test_dress() -> void:
	var r := await _remote()
	_eq(r.get_node("Keys").get_child_count(), 26, "dress/26 keys, one VRButton each")
	var missing: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		var model_key := r.get_node("Model").call("part", key) as MeshInstance3D
		if b == null or model_key == null or _cap(b).mesh != model_key.mesh or not _cap(b).visible \
				or model_key.visible:
			missing.append(key)
	_ok(missing.is_empty(), "dress/every key wears the model's key, the model's own one hidden", str(missing))
	var tip := r.get_node("Tip") as Marker3D
	var want: Transform3D = r.get_node("Model").call("part_transform", "IrTip", r)
	_ok(tip.transform.is_equal_approx(want) and tip.position.distance_to(Vector3(0, 0.003, -0.1)) < TOLERANCE
		and tip.transform.basis.z.is_equal_approx(Vector3.BACK),
		"dress/the tip is on the model's IrTip, aiming along -Z", str(tip.transform))


# ── shapes/ ───────────────────────────────────────────────────────────────────

func _test_shapes() -> void:
	var r := await _remote()
	var model := r.get_node("Model") as ApplianceModel
	var except: Array[String] = ["BodyPrint"]
	except.append_array(PRINTED.keys())
	var drawn := ApplianceModel.node_bounds(model.levels[0], r, except)
	var body := (r.get_node("CollisionShape3D") as CollisionShape3D)
	var hull := body.shape as ConvexPolygonShape3D
	_ok(hull != null, "shapes/the body is a convex hull")
	if hull != null:
		var hb := AABB(hull.points[0], Vector3.ZERO)
		for p in hull.points:
			hb = hb.expand(p)
		_ok(_same(body.transform * hb, drawn), "shapes/the body's hull is the shell's bounds, no margin",
			"%s vs %s" % [body.transform * hb, drawn])
	var laser := r.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	_ok(laser.shape is ConcavePolygonShape3D and _same(laser.transform * _faces_box(laser.shape), drawn),
		"shapes/the laser's shape is the shell's own triangles")
	var padded: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		var shape := b.get_node("CollisionShape3D") as CollisionShape3D
		if not shape.shape is ConcavePolygonShape3D \
				or not _same(shape.transform * _faces_box(shape.shape), _cap(b).transform * _cap(b).mesh.get_aabb()):
			padded.append(key)
	_ok(padded.is_empty(), "shapes/every key's shape is its own triangles, no margin", str(padded))


# ── ray/ ──────────────────────────────────────────────────────────────────────

func _resolve(from: Vector3, to: Vector3) -> InteractionTarget:
	return InteractionResolver.resolve_desktop(get_viewport().world_3d.direct_space_state, from, to, _hand)


## Desktop rays from 0.6 m at `at`: straight down onto the face, and tilted 30 degrees
## toward the window, the grip end and either side.
func _rays_at(r: TVRemote, at: Vector3) -> Array[InteractionTarget]:
	var out: Array[InteractionTarget] = []
	for d: Vector3 in [Vector3(0, 1, 0), Vector3(0, 0.866, -0.5), Vector3(0, 0.866, 0.5),
			Vector3(0.5, 0.866, 0), Vector3(-0.5, 0.866, 0)]:
		var dir := r.global_transform.basis * d
		out.append(_resolve(at + dir * 0.6, at - dir * 0.01))
	return out


func _test_ray() -> void:
	var r := await _remote()
	var blocked: Array[String] = []
	for key: String in PRINTED:
		var b := r.key_button(key)
		for t in _rays_at(r, _face(b) - r.global_transform.basis.y * 0.0002):
			if t.kind != InteractionTarget.KIND_BUTTON or t.action_node != b:
				blocked.append("%s (%s %s)" % [key, t.kind, t.action_node.name if t.action_node else "-"])
	_ok(blocked.is_empty(), "ray/every key's face takes that key, from above and tilted", ", ".join(blocked))
	# The control: the middle of the 2 mm gap between VOL - and MUTE takes no key. Each key's
	# box used to be 3 mm larger than the key, and that box reached 0.25 mm past this point.
	var mute := _face(r.key_button("KeyMute"))
	var gap := mute - r.global_transform.basis.x * 0.00725
	var t := _resolve(gap + Vector3.UP * 0.6, gap - Vector3.UP * 0.02)
	_ok(t.kind != InteractionTarget.KIND_BUTTON, "ray/the gap between two keys takes no key",
		"%s %s" % [t.kind, t.action_node.name if t.action_node else "-"])
	# …and the shell itself (RETRO XR, over the battery end) is the remote's, to pick up.
	var shell := r.global_transform * Vector3(0, 0.0112, 0.07)
	var s := _resolve(shell + Vector3.UP * 0.6, shell - Vector3.UP * 0.02)
	_ok(s.kind != InteractionTarget.KIND_BUTTON and s.action_node == r,
		"ray/the shell between the keys is the remote's", "%s %s" % [s.kind, s.action_node])


# ── touch/ ────────────────────────────────────────────────────────────────────

## A fingertip resting on one key's face (1 mm over it) is that key's, and every
## other key's gate refuses it — the ring's arcs and OK most of all, whose boxes overlap.
func _test_touch() -> void:
	var r := await _remote()
	var wrong: Array[String] = []
	for key: String in PRINTED:
		var tip := _face(r.key_button(key)) + r.global_transform.basis.y * 0.001
		for other: String in PRINTED:
			var takes: bool = r.key_button(other).press_gate.call(tip)
			if takes != (other == key):
				wrong.append("%s's face %s %s" % [key, "taken by" if takes else "refused by", other])
	_ok(wrong.is_empty(), "touch/a fingertip on a key is that key's alone", ", ".join(wrong))
	# Over the key and not on it: 5 mm up is a hover, not a press.
	var high := _face(r.key_button("KeyOk")) + r.global_transform.basis.y * 0.005
	_ok(not r.key_button("KeyOk").press_gate.call(high), "touch/5 mm over a key does not press it")


# ── keys/ ─────────────────────────────────────────────────────────────────────

func _test_keys() -> void:
	var r := await _remote()
	var tv := await _spawn(TV_SCENE, Vector3(3, 1, 0)) as RetroTV
	r._target = tv
	# A set: each of its keys acts on it; the transport keys are no keys of a set's.
	var on := tv.is_on()
	_eq(r.press_key("KeyPower"), "power", "keys/tv POWER is the set's power cell")
	_ok(tv.is_on() != on, "keys/tv POWER switched the set")
	var muted := tv.is_muted()
	_eq(r.press_key("KeyMute"), "mute", "keys/tv MUTE is the set's mute cell")
	_ok(tv.is_muted() != muted, "keys/tv MUTE muted the set")
	var wide := tv.widescreen
	_eq(r.press_key("KeyAspect"), "aspect", "keys/tv ASPECT is the set's aspect cell")
	_ok(tv.widescreen != wide, "keys/tv ASPECT changed the picture's shape")
	for key: String in ["KeyVolUp", "KeyVolDown", "KeySource", "KeyAudioMode", "KeyAudioOut"]:
		_eq(r.press_key(key), PRINTED[key], "keys/tv %s is its cell" % key)
	for key: String in ["KeyStop", "KeyPlayPause", "KeyEject", "KeyOk", "KeyMenu", "KeyPrev"]:
		_eq(r.press_key(key), "", "keys/tv %s does nothing to a set" % key)
	var vcr := await _spawn(VCR_SCENE, Vector3(5, 1, 0))
	r._target = vcr
	_eq(r.press_key("KeyStop"), "stop", "keys/vcr STOP")
	_eq(r.press_key("KeyFf"), "ff", "keys/vcr FF")
	_eq(r.press_key("KeyPrev"), "", "keys/vcr PREV is greyed on a tape")
	_eq(r.press_key("KeyEject"), "", "keys/vcr EJECT is greyed with no tape")
	_eq(r.press_key("KeyPower"), "", "keys/vcr POWER is no deck key")
	var dvd := await _spawn(DVD_SCENE, Vector3(7, 1, 0))
	r._target = dvd
	_eq(r.cell_for_key("KeyPrev"), "prev_ch", "keys/dvd PREV is the chapter key")
	_eq(r.cell_for_key("KeyNext"), "next_ch", "keys/dvd NEXT is the chapter key")
	_eq(r.press_key("KeyNext"), "next_ch", "keys/dvd NEXT skips a chapter")
	_eq(r.press_key("KeyUp"), "", "keys/dvd the ring is greyed outside a disc menu")
	_eq(r.press_key("KeyMenu"), "menu", "keys/dvd MENU is always live")
	var rp := await _spawn(RECORD_PLAYER, Vector3(9, 1, 0))
	r._target = rp
	_eq(r.cell_for_key("KeyPrev"), "prev", "keys/record PREV is plain prev off a DVD")
	_eq(r.press_key("KeyStop"), "stop", "keys/record STOP")
	_eq(r.press_key("KeyFf"), "", "keys/record FF is greyed (a turntable has no scan)")
	var wrong: Array[String] = []
	for key: String in PRINTED:
		if r.cell_for_key(key) != PRINTED[key]:
			wrong.append(key)
	_ok(wrong.is_empty(), "keys/every key is the cell printed on it", str(wrong))
	r._target = null


# ── aim/ ──────────────────────────────────────────────────────────────────────

func _test_aim() -> void:
	# The remote at the origin points along -Z; the set stands 1.5 m off that way.
	var tv := await _spawn(TV_SCENE, Vector3(0, 1, -1.5)) as RetroTV
	var r := await _remote(Vector3(0, 1.1, 0))
	var on := tv.is_on()
	_eq(r.press_key("KeyPower"), "power", "aim/a key on a remote lying pointed at a set acts on it")
	_ok(tv.is_on() != on, "aim/…and the set switched")
	r.rotate_y(PI)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_eq(r.press_key("KeyPower"), "", "aim/turned away from it, the same key acts on nothing")


# ── press/ ────────────────────────────────────────────────────────────────────

func _test_press() -> void:
	var tv := await _spawn(TV_SCENE, Vector3(0, 1, -1.5)) as RetroTV
	var r := await _remote(Vector3(0, 1.1, 0))
	var b := r.key_button("KeyMute")
	var rest := _cap(b).global_position
	var muted := tv.is_muted()
	var at := _face(b)
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, b, at, at))
	var sunk := rest - _cap(b).global_position
	_ok(absf(sunk.length() - TRAVEL) < 0.00005 and sunk.normalized().dot(r.global_transform.basis.y) > 0.999,
		"press/a clicked key sinks 1.5 mm into the remote", str(sunk))
	_ok(tv.is_muted() != muted, "press/…and does its cell on the set it points at")
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, null, b, at, at))
	_ok(_cap(b).global_position.distance_to(rest) < 0.00001, "press/let go, it comes back up")
	# Every key, each ring arc and OK on its own: down along its own -Z by the travel, no other cap moving.
	var wrong: Array[String] = []
	var rests := _cap_rests(r)
	for key: String in PRINTED:
		var k := r.key_button(key)
		var f := _face(k)
		k.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, k, f, f))
		var bad := _sunk_wrong(r, rests, key)
		k.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, null, k, f, f))
		if not bad.is_empty() or _cap(k).global_position.distance_to(rests[key]) > 0.00001:
			wrong.append("%s %s" % [key, bad])
	_ok(wrong.is_empty(), "press/every key sinks alone, along its own -Z, and comes back", ", ".join(wrong))


## Every key's cap position at rest.
func _cap_rests(r: TVRemote) -> Dictionary:
	var out := {}
	for key: String in PRINTED:
		out[key] = _cap(r.key_button(key)).global_position
	return out


## "" when `down` is sunk by the travel into the remote along its own -Z and every other cap is at rest; else what
## is wrong.
func _sunk_wrong(r: TVRemote, rests: Dictionary, down: String) -> String:
	var b := r.key_button(down)
	var sunk: Vector3 = rests[down] - _cap(b).global_position
	var out := b.global_transform.basis.z.normalized()
	if absf(sunk.length() - TRAVEL) > 0.00005 or sunk.normalized().dot(out) < 0.999 \
			or sunk.normalized().dot(r.global_transform.basis.y) < 0.999:
		return "sank %s" % sunk
	for key: String in PRINTED:
		if key != down and _cap(r.key_button(key)).global_position.distance_to(rests[key]) > 0.00001:
			return "%s moved too" % key
	return ""


# ── bay/ ──────────────────────────────────────────────────────────────────────

## The desktop ray from 0.6 m below the remote straight up at `at`.
func _from_below(r: TVRemote, at: Vector3) -> InteractionTarget:
	var up := r.global_transform.basis.y
	return _resolve(at - up * 0.6, at + up * 0.005)


func _test_bay() -> void:
	var r := await _remote()
	for i in 4:
		await get_tree().process_frame
	var covers := CoverSlots.of(r)
	var zone := covers.slot(TVRemote.BATTERY_COVER) if covers else null
	_ok(zone != null and r.battery_cover_on(), "bay/the battery cover is on, in its CoverSlots slot")
	if zone == null:
		return
	var cover := zone.picked_up_object as PortCover
	var model := r.get_node("Model") as ApplianceModel
	var part := model.part("BatteryCover") as MeshInstance3D
	var drawn := part.global_transform * part.get_aabb()
	var worn := cover.get_node_or_null("Shell/" + String(part.name)) as MeshInstance3D if cover else null
	if worn == null and cover != null and cover.has_node("Shell"):
		worn = cover.get_node("Shell").get_child(0) as MeshInstance3D
	_ok(worn != null and _same(worn.global_transform * worn.get_aabb(), drawn) and not part.visible,
		"bay/the cover wears the model's cover, where the model has it, and the model's own is hidden",
		"%s vs %s" % [worn.global_transform * worn.get_aabb() if worn else AABB(), drawn])
	var hidden := true
	for p in model.parts("BatteryCover"):
		hidden = hidden and not p.visible
	_ok(hidden, "bay/no level draws a cover of its own (the slot's cover is drawn at every distance)")
	var t := _from_below(r, drawn.get_center())
	_ok(t.kind == InteractionTarget.KIND_SNAP_PICKABLE and t.highlight_node == cover,
		"bay/the desktop ray from below takes the cover", "%s %s" % [t.kind, t.highlight_node])
	var slots := CellSlots.of(r)
	var cells := slots.cells() if slots else {}
	var seated: Array[String] = []
	for seat: String in ["BatteryAAA1", "BatteryAAA2"]:
		var rec: Variant = cells.get(seat)
		var cell := (rec as Array)[0] as BatteryCell if rec is Array else null
		var marker := model.part(seat)
		if cell != null and cell.size == "AAA" and marker != null 				and cell.global_position.distance_to(marker.global_position) < 0.0005 and not cell.enabled:
			seated.append(seat)
	_eq(seated.size(), 2, "bay/two AAA cells are in BatteryAAA1 and 2, on their markers, shut in by the cover")
	# Off: the bay opens.
	zone.drop_object()
	cover.global_position += Vector3(0.3, 0, 0)
	for i in 4:
		await get_tree().physics_frame
	_ok(not r.battery_cover_on(), "bay/the cover comes off")
	var taken: Array[String] = []
	for seat: String in cells:
		var cell := (cells[seat] as Array)[0] as BatteryCell
		var c := _from_below(r, cell.global_position)
		if cell.enabled and c.kind == InteractionTarget.KIND_SNAP_PICKABLE and c.highlight_node == cell:
			taken.append(seat)
	_eq(taken.size(), 2, "bay/with the cover off, the ray from below takes each cell")
	# The remote's own laser shape is open over the bay: from below, between the cells, it is first met at the
	# divider's foot 6 mm in, not at the plane the cover closed (the shell's triangles with the cover in them).
	var laser := r.get_node("PointerArea") as CollisionObject3D
	var up := r.global_transform.basis.y
	var mid := drawn.get_center()
	var q := PhysicsRayQueryParameters3D.create(mid - up * 0.6, mid + up * 0.03, laser.collision_layer)
	q.collide_with_areas = false
	var ex: Array[RID] = []
	var depth := -1.0
	for k in 6:
		q.exclude = ex
		var h := get_viewport().world_3d.direct_space_state.intersect_ray(q)
		if h.is_empty():
			break
		if h.collider == laser:
			depth = (h.position - mid).dot(up)
			break
		ex.append(h.rid)
	_ok(depth > 0.004, "bay/with the cover off, the remote's laser shape is open over the bay",
		"met %.1f mm in" % (depth * 1000.0))
	# Back on: shut in again.
	zone.pick_up_object(cover)
	for i in 4:
		await get_tree().physics_frame
	var shut := 0
	for seat: String in cells:
		if not ((cells[seat] as Array)[0] as BatteryCell).enabled:
			shut += 1
	_ok(r.battery_cover_on() and shut == 2, "bay/the cover goes back on and the cells are shut in again")
	# A restored remote's cells are its save's: it seeds none.
	var restored := REMOTE.instantiate() as TVRemote
	restored.freeze = true
	restored.position = Vector3(0.5, 1, 0)
	restored.set_meta(CoverSlots.RESTORING, true)
	add_child(restored)
	_spawned.append(restored)
	for i in 4:
		await get_tree().process_frame
	var none := CellSlots.of(restored)
	_ok(none != null and none.seats().size() == 2 and none.cells().is_empty(),
		"bay/a restored remote has its two seats and seeds no cells")


# ── poke/ ─────────────────────────────────────────────────────────────────────

## A tracked hand: an XRController3D on a tracker of our own, its PokeTip at the controller's origin. Made before
## a remote, so its keys find it as they gather their controllers. `holding` gives it a pickup holding that object.
func _tracked_hand(tracker_name: StringName, holding: Node3D = null) -> XRPositionalTracker:
	var tr := XRPositionalTracker.new()
	tr.name = tracker_name
	tr.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tr)
	var origin := get_node_or_null("TestOrigin") as XROrigin3D
	if origin == null:
		origin = XROrigin3D.new()
		origin.name = "TestOrigin"
		add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.name = String(tracker_name)
	ctrl.tracker = tracker_name
	origin.add_child(ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	ctrl.add_child(tip)
	if holding != null:
		var pickup := Node.new()
		pickup.set_script(_holding_script())
		pickup.name = "FunctionPickup"
		pickup.set("picked_up_object", holding)
		ctrl.add_child(pickup)
	_place(tr, Vector3(0, 3, 0))
	return tr


## A stand-in for XRToolsFunctionPickup: all PokeTip asks of one is what it holds.
func _holding_script() -> GDScript:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar picked_up_object: Node3D = null\n"
	gs.reload()
	return gs


func _place(tr: XRPositionalTracker, at: Vector3) -> void:
	tr.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _drop_hands() -> void:
	for t: StringName in [FINGER, HOLDER]:
		var tr := XRServer.get_tracker(t)
		if tr != null:
			XRServer.remove_tracker(tr)
	var origin := get_node_or_null("TestOrigin")
	if origin:
		remove_child(origin)
		origin.free()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Push the fingertip into each of `keys` along the face's normal and out again, a few frames each step, and check
## each sank by the travel, fired once and nothing else fired, and came back up.
func _poke_keys(r: TVRemote, finger: XRPositionalTracker, keys: Array, label: String) -> void:
	var fired := {}
	for key: String in PRINTED:
		fired[key] = 0
		r.key_button(key).button_pressed.connect(func() -> void: fired[key] += 1)
	var rests := _cap_rests(r)
	var wrong: Array[String] = []
	var out := r.global_transform.basis.y.normalized()
	for key: String in keys:
		var b := r.key_button(key)
		var face: Vector3 = rests[key]
		for k in fired:
			fired[k] = 0
		for d: float in [0.03, 0.012, 0.004, 0.001, -TRAVEL, -TRAVEL, -TRAVEL]:
			_place(finger, face + out * d)
			await _ticks(2)
		var bad := _sunk_wrong(r, rests, key)
		var others := 0
		for k in fired:
			if k != key:
				others += int(fired[k])
		var once := int(fired[key])
		for d: float in [0.002, 0.012, 0.03]:
			_place(finger, face + out * d)
			await _ticks(2)
		if not bad.is_empty() or once != 1 or others != 0 \
				or _cap(b).global_position.distance_to(rests[key]) > 0.00001:
			wrong.append("%s (%s, fired %d, others %d)" % [key, bad, once, others])
	_ok(wrong.is_empty(), "poke/%s: each key sinks 1.5 mm under the fingertip, fires once, alone, and comes back up"
		% label, ", ".join(wrong))


func _test_poke() -> void:
	var finger := _tracked_hand(FINGER)
	# Lying on a table, keys up: every key.
	var r := await _remote(Vector3(0, 1, 0))
	await _ticks(2)
	await _poke_keys(r, finger, PRINTED.keys(), "lying on a table")
	# Held in the other hand, tilted the way a hand holds one, its thumb resting on STOP.
	var held := REMOTE.instantiate() as TVRemote
	var holder := _tracked_hand(HOLDER, held)
	held.freeze = true
	held.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(28), deg_to_rad(-15), deg_to_rad(12))),
		Vector3(0.6, 1.2, 0.2))
	add_child(held)
	_spawned.append(held)
	await _ticks(4)
	var holder_ctrl := get_node("TestOrigin/" + String(HOLDER)) as XRController3D
	held._holding_ctrl = holder_ctrl
	var stop := held.key_button("KeyStop")
	var stop_fired := [0]
	stop.button_pressed.connect(func() -> void: stop_fired[0] += 1)
	_place(holder, _face(stop) - held.global_transform.basis.y * 0.001)
	await _ticks(3)
	_ok(holder_ctrl.get_is_active() and stop_fired[0] == 0 and not stop.is_held(),
		"poke/the hand holding the remote presses nothing, its thumb on STOP")
	_place(holder, Vector3(0.6, 3, 0.2))
	await _ticks(2)
	await _poke_keys(held, finger, ["KeyPower", "KeyMute", "KeyUp", "KeyOk", "KeyLeft", "KeyMenu", "KeySubtitle"],
		"held tilted in the other hand")
	held._holding_ctrl = null
	_drop_hands()


# ── grid/ ─────────────────────────────────────────────────────────────────────

func _test_grid() -> void:
	var tv := await _spawn(TV_SCENE, Vector3(0, 1, -1.5)) as RetroTV
	var r := await _remote(Vector3(0, 1.1, 0))
	r._target = tv
	r._rebuild_grid()
	var rests := _cap_rests(r)
	var cell := -1
	for i in r._cells.size():
		if str(r._cells[i]["id"]) == "mute":
			cell = i
	_ok(cell >= 0, "grid/the set's grid has a MUTE cell")
	if cell < 0:
		return
	var muted := tv.is_muted()
	r._selection = cell
	r._activate_selected()
	_ok(tv.is_muted() != muted and _sunk_wrong(r, rests, "KeyMute").is_empty(),
		"grid/MUTE pressed on the grid mutes the set and sinks the remote's MUTE key, alone",
		_sunk_wrong(r, rests, "KeyMute"))
	await get_tree().create_timer(0.25).timeout
	_ok(_cap(r.key_button("KeyMute")).global_position.distance_to(rests["KeyMute"]) < 0.00001,
		"grid/…and lets it back up")
	# On a DVD player the grid's PREV is the chapter cell; it is still the remote's PREV that sinks.
	var dvd := await _spawn(DVD_SCENE, Vector3(1.5, 1, -1.5))
	r._target = dvd
	r._flash_key("prev_ch")
	_ok(_sunk_wrong(r, rests, "KeyPrev").is_empty(), "grid/the DVD's chapter cell sinks the remote's PREV key",
		_sunk_wrong(r, rests, "KeyPrev"))
	await get_tree().create_timer(0.25).timeout


## remove_child then free, as deck_tests does: a set's or deck's audio emitter still
## alive at quit segfaults the exit.
func _cleanup() -> void:
	# What a remote put in the room, its battery cover and the two cells it came with, goes first and at the
	# frame's end: their slots still have deferred calls queued for them.
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is BatteryCell or n is PortCover:
			n.queue_free()
	for i in 3:
		await get_tree().process_frame
	for n in _spawned:
		if not is_instance_valid(n):
			continue
		var parent := n.get_parent()
		if parent:
			parent.remove_child(n)
		n.free()
	_spawned.clear()
	for i in 3:
		await get_tree().process_frame
