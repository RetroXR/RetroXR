## The audio cassette's own Compact Cassette (CompactCassette on AudioCassette), and stepping aside for a mod's.
##
##   godot --headless --path RetroXR res://Tests/audio_cassette_tests.tscn
##   godot --headless --path RetroXR res://Tests/audio_cassette_tests.tscn -- --only=mod
##
## Groups:
##   shell/  with no mod, a cassette wears the RetroXR-models Compact Cassette (three levels) as Shell: the stand-in box
##           and its label block hidden, the collision box the deck's slot was cut for unchanged, the album's name on
##           side A's paper, both labels the stand-in's cream
##   tape/   the hubs and packs follow the tape's own place (tape_progress), eased; the deck reads those hubs
##   mod/    a mod that holds the AudioCassette/shell dressing keeps the game's shell off; one whose hook has already
##           hung its Shell (it runs as the cassette enters the tree, before _ready) is never dressed twice
extends "res://Tests/test_suite.gd"

const CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const FAKE_MOD := "test.cassette_shell"

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "cassette"
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[cassette] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.split("=")[1]
	for c: Array in [["shell", _t_shell], ["tape", _t_tape], ["mod", _t_mod]]:
		if not _only.is_empty() and not String(c[0]).begins_with(_only):
			continue
		await (c[1] as Callable).call()
		for n in _spawned:
			if is_instance_valid(n):
				n.queue_free()
		_spawned.clear()
		await get_tree().process_frame
	_finish()


func _cassette(progress: float = 0.0) -> AudioCassette:
	var t := CASSETTE.instantiate() as AudioCassette
	t.freeze = true
	t.album_label = "Test Album"
	t.tape_progress = progress
	add_child(t)
	_spawned.append(t)
	t.global_position = Vector3(_spawned.size() * 0.3, 1, 0)
	return t


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _hub_angle(shell: CompactCassette, side: String) -> float:
	return (shell.levels[0].find_child("Hub" + side, true, false) as Node3D).rotation.z


# ── shell/ ────────────────────────────────────────────────────────────────────

func _t_shell() -> void:
	var t := _cassette()
	await _wait(3)
	var shell := t.get_node_or_null("Shell") as CompactCassette
	_ok(shell != null and shell.levels.size() == 3, "shell/with no mod the cassette wears the Compact Cassette, 3 levels")
	if shell == null:
		return
	_ok(not (t.get_node("TapeMesh") as Node3D).visible and not (t.get_node("LabelMesh") as Node3D).visible,
		"shell/the stand-in box and its label block are hidden")
	var box := (t.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_ok(box != null and box.size.is_equal_approx(Vector3(0.1004, 0.0638, 0.012)),
		"shell/the collision box the deck's slot was cut for is unchanged")
	# The tape runs are boxes turned and stretched along the tape: their bounds overstate it, so the shell is measured.
	var drawn := ApplianceModel.node_bounds(shell.levels[0], t, ["TapeSpanSupply", "TapeSpanTakeup"])
	# 100.4 x 63.8 x 12 (IEC 60094-7), plus the side ribs standing 1 mm proud each side (ECMA-34): 102.4 across them.
	# The collision box stays the body's 100.4, inside what is drawn.
	_ok(absf(drawn.size.x - 0.1024) < 0.0005 and absf(drawn.size.y - 0.0638) < 0.0005 and absf(drawn.size.z - 0.012) < 0.0005
		and drawn.get_center().length() < 0.0005,
		"shell/the model is the cassette's size, centred on the box (%s mm)" % (drawn.size * 1000.0).snapped(Vector3.ONE * 0.1))
	var title := t.get_node("CassetteLabel") as Label3D
	_ok(title.text == "Test Album" and title.position.is_equal_approx(CompactCassette.TITLE_AT),
		"shell/the album's name is written on side A's paper")
	var label := shell.levels[0].find_child("LabelA", true, false) as MeshInstance3D
	var mat := label.get_surface_override_material(0) as StandardMaterial3D if label else null
	var paper := ((t.get_node("LabelMesh") as MeshInstance3D).get_active_material(0) as StandardMaterial3D).albedo_color
	_ok(mat != null and mat.albedo_color.is_equal_approx(paper), "shell/with no picture the labels are the stand-in's cream")
	_ok(t.find_children("*", "CompactCassette", true, false).size() == 1, "shell/dressed once")


# ── tape/ ─────────────────────────────────────────────────────────────────────

func _t_tape() -> void:
	var t := _cassette(0.0)
	await _wait(3)
	var shell := t.get_node("Shell") as CompactCassette
	var start := shell.tape_state()
	_ok(start["supply_r"] > start["takeup_r"], "tape/at the start the tape is on the supply hub")
	t.tape_progress = 0.6
	await _wait(2)
	_ok(shell.progress > 0.0 and shell.progress < 0.6, "tape/the reels ease toward a new place, not jump (%.3f)" % shell.progress)
	var deadline := Time.get_ticks_msec() + 3000
	while not is_equal_approx(shell.progress, 0.6) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var st := shell.tape_state()
	_ok(is_equal_approx(shell.progress, 0.6) and st["takeup_r"] > st["supply_r"],
		"tape/and settle there, most of the tape wound across")
	var want := fposmod(float(st["takeup_turns"]), 1.0) * TAU
	_ok(absf(_hub_angle(shell, "Takeup") - want) < 1e-4, "tape/the take-up hub stands at the turns wound onto it")
	var supply := shell.levels[0].find_child("PackSupply", true, false) as MeshInstance3D
	var takeup := shell.levels[0].find_child("PackTakeup", true, false) as MeshInstance3D
	_ok(supply.get_blend_shape_value(0) > 0.0 and takeup.get_blend_shape_value(0) > 0.0,
		"tape/both packs are driven by their blend shapes")
	# The deck turns its spindles to these hubs (CassettePlayer: HubSupply / HubTakeup found on the tape).
	_ok(t.find_child("HubSupply", true, false) != null and t.find_child("HubTakeup", true, false) != null,
		"tape/the hubs a deck follows are on the cassette")


# ── mod/ ──────────────────────────────────────────────────────────────────────

func _hooks() -> ModHooks:
	return get_node("/root/Mods").get("_hooks") as ModHooks


func _t_mod() -> void:
	var hooks := _hooks()
	_ok(hooks != null and (get_node("/root/Mods").call("dresser_of", &"AudioCassette", "shell") as String).is_empty(),
		"mod/a suite boots with no mod dressing the cassette")
	# 1. A mod holds the dressing (ModApi.dress claims AudioCassette/shell): the game's shell stays off.
	_ok(hooks.claim_dress(FAKE_MOD, &"AudioCassette", "shell").is_empty(), "mod/a test mod claims the dressing")
	var t := _cassette()
	await _wait(3)
	_ok(t.get_node_or_null("Shell") == null and (t.get_node("TapeMesh") as Node3D).visible,
		"mod/claimed, the game puts no shell on and leaves the stand-in for the mod")
	# 2. The mod's hook dresses the cassette as it enters the tree (before _ready): exactly its shell, never two.
	hooks.watch_nodes(FAKE_MOD, &"AudioCassette", func(n: Node) -> void:
		if not n.has_node("Shell"):
			var s := Node3D.new()
			s.name = "Shell"
			n.add_child(s))
	var t2 := _cassette()
	await _wait(3)
	var shells := 0
	for c in t2.get_children():
		if String(c.name).begins_with("Shell") or c is CompactCassette:
			shells += 1
	_ok(shells == 1 and not (t2.get_node("Shell") is CompactCassette), "mod/the mod's shell goes on and the game's never does")
	# 3. A hook that dresses but holds no claim (an older build's on_node_added): its Shell still keeps the game's off.
	hooks.drop_owner(FAKE_MOD)
	hooks.watch_nodes(FAKE_MOD, &"AudioCassette", func(n: Node) -> void:
		if not n.has_node("Shell"):
			var s := Node3D.new()
			s.name = "Shell"
			n.add_child(s))
	var t3 := _cassette()
	await _wait(3)
	_ok(t3.get_node_or_null("Shell") != null and not (t3.get_node("Shell") is CompactCassette)
		and t3.find_children("*", "CompactCassette", true, false).is_empty(),
		"mod/a hook's Shell with no claim also keeps the game's off")
	hooks.drop_owner(FAKE_MOD)
	var t4 := _cassette()
	await _wait(3)
	_ok(t4.get_node_or_null("Shell") is CompactCassette, "mod/the mod gone, a new cassette wears the game's shell again")
