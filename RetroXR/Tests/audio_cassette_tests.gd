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
##   art/    the album's pictures go on the labels a shell draws: the game's, and a mod's (xenu.cassette wears the
##           same model, LabelA / LabelB), filling the label with its window cut out; only a cassette with no shell
##           labels at all gets the old stand-in quads, which on the model shrank the picture and hid the window
##   name/   RetroXR's own label fits the album's name as approved: one line, brackets dropped to stay on one, two
##           even lines (three on an LP), then cut with "..." at the smallest size; every line inside its box
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
	for c: Array in [["shell", _t_shell], ["tape", _t_tape], ["mod", _t_mod], ["art", _t_art], ["name", _t_name]]:
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
	# With no picture but a name, RetroXR's own label (MediaLabelPainter: a plain card of the label's shape headless).
	await _wait_until(func() -> bool:
		var m := label.get_surface_override_material(0) as StandardMaterial3D
		return m != null and m.albedo_texture != null and m.albedo_texture.get_width() == MediaLabelPainter.CASSETTE_PX, 3.0)
	mat = label.get_surface_override_material(0) as StandardMaterial3D
	_ok(mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() == MediaLabelPainter.CASSETTE_PX,
		"shell/with no picture but a name, the labels wear RetroXR's own label")
	# With no name either there is nothing to print: the stand-in's cream.
	var blank := _cassette()
	blank.album_label = ""
	blank._request_label_art()
	await _wait(3)
	var blank_shell := blank.get_node_or_null("Shell") as CompactCassette
	var blank_label := blank_shell.levels[0].find_child("LabelA", true, false) as MeshInstance3D if blank_shell else null
	var blank_mat := blank_label.get_surface_override_material(0) as StandardMaterial3D if blank_label else null
	_ok(blank_mat != null and blank_mat.albedo_color.is_equal_approx(paper),
		"shell/with no name at all, the labels stay the stand-in's paper")
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


# ── art/ ──────────────────────────────────────────────────────────────────────

## A picture as a label loader hands one over.
func _picture() -> Texture2D:
	var img := Image.create(64, 29, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.3, 0.2))
	return ImageTexture.create_from_image(img)


## The material a label mesh wears now (its override, else its own).
func _label_texture(mi: MeshInstance3D) -> Texture2D:
	var m := mi.get_surface_override_material(0) as StandardMaterial3D
	if m == null:
		m = mi.mesh.surface_get_material(0) as StandardMaterial3D
	return m.albedo_texture if m != null else null


## A stand-in for a mod's shell, as xenu.cassette hangs one: a Shell holding the model's LabelA / LabelB (with
## `labels`), each a thin box the label's size wearing a material of its own.
func _hang_mod_shell(n: Node, labels: bool) -> void:
	if n.has_node("Shell"):
		return
	var shell := Node3D.new()
	shell.name = "Shell"
	if labels:
		for side: String in ["LabelA", "LabelB"]:
			var mi := MeshInstance3D.new()
			mi.name = side
			var box := BoxMesh.new()
			box.size = Vector3(0.0896, 0.0404, 0.00025)
			box.material = StandardMaterial3D.new()
			mi.mesh = box
			shell.add_child(mi)
	n.add_child(shell)


func _t_art() -> void:
	var tex := _picture()
	# 1. The game's own shell: the picture on its labels (the path that was always right).
	var own := _cassette()
	await _wait(3)
	own._on_label_art(&"a", tex)
	var own_shell := own.get_node_or_null("Shell") as CompactCassette
	var own_a := own_shell.levels[0].find_child("LabelA", true, false) as MeshInstance3D if own_shell else null
	_ok(own_a != null and _label_texture(own_a) != null and own.get_node_or_null("LabelArt") == null,
		"art/the game's shell wears the picture on its own LabelA, no quad")
	# 2. A mod's shell with the model's labels: the same, on ITS labels.
	var hooks := _hooks()
	hooks.claim_dress(FAKE_MOD, &"AudioCassette", "shell")
	hooks.watch_nodes(FAKE_MOD, &"AudioCassette", func(n: Node) -> void: _hang_mod_shell(n, true))
	var t := _cassette()
	await _wait(3)
	t._on_label_art(&"a", tex)
	var shell := t.get_node_or_null("Shell") as Node3D
	var a := shell.get_node_or_null("LabelA") as MeshInstance3D if shell else null
	var b := shell.get_node_or_null("LabelB") as MeshInstance3D if shell else null
	var on_a := _label_texture(a) if a else null
	_ok(on_a != null and t.get_node_or_null("LabelArt") == null and t.get_node_or_null("LabelArtB") == null,
		"art/a mod's shell wears the picture on its own LabelA, and no stand-in quad covers it")
	_ok(on_a != null and absf(float(on_a.get_width()) / float(on_a.get_height()) - 0.0896 / 0.0404) < 0.01,
		"art/fitted to the label's own proportions, so it fills it (%s)" % [on_a.get_size() if on_a else "none"])
	_ok(b != null and _label_texture(b) != null, "art/side B with no picture of its own wears side A's")
	_ok(not (t.get_node("CassetteLabel") as Label3D).visible, "art/the picture carries the name: the text steps aside")
	# 3. A shell with no labels at all (the plain stand-in box's case): the quads, as before.
	hooks.drop_owner(FAKE_MOD)
	hooks.claim_dress(FAKE_MOD, &"AudioCassette", "shell")
	hooks.watch_nodes(FAKE_MOD, &"AudioCassette", func(n: Node) -> void: _hang_mod_shell(n, false))
	var bare := _cassette()
	await _wait(3)
	bare._on_label_art(&"a", tex)
	var quad := bare.get_node_or_null("LabelArt") as Node3D
	_ok(quad != null and quad.visible, "art/a shell with no labels gets the stand-in quad, as the box always did")
	hooks.drop_owner(FAKE_MOD)


# ── name/ ─────────────────────────────────────────────────────────────────────

func _t_name() -> void:
	var f := MediaLabelPainter.font()
	var mm := MediaLabelPainter.CASSETTE_PX / MediaLabelPainter.CASSETTE_MM.x
	var box := MediaLabelPainter.CASSETTE_PX - 8.0 * mm
	var widest := func(fit: Dictionary) -> float:
		var w := 0.0
		for l: String in fit["lines"]:
			w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fit["size"])).x)
		return w
	var short := MediaLabelPainter.cassette_name_fit("Thriller")
	_ok((short["lines"] as PackedStringArray).size() == 1 and int(short["size"]) == int(5.2 * mm),
		"name/a short name is one line at full size (%s)" % [short])
	var two := MediaLabelPainter.cassette_name_fit("Songs from the Big Chair and Other Stories")
	var two_lines := two["lines"] as PackedStringArray
	_ok(two_lines.size() == 2 and widest.call(two) <= box, "name/a long one is two lines inside the strip (%s)" % [two_lines])
	_ok(absi(two_lines[0].length() - two_lines[1].length()) < 12, "name/split evenly by words (%s)" % [two_lines])
	var brackets := MediaLabelPainter.cassette_name_fit("Electric Ladyland (Remastered 2011) [Deluxe Edition]")
	_ok(brackets["lines"] == PackedStringArray(["ELECTRIC LADYLAND"]),
		"name/trailing brackets are dropped to keep it on one line (%s)" % [brackets["lines"]])
	var long_name := "The Very Best of the Electric Light Orchestra Live at Wembley Arena in the Summer of 1978"
	var cut := MediaLabelPainter.cassette_name_fit(long_name)
	var cut_lines := cut["lines"] as PackedStringArray
	_ok(cut_lines.size() == 2 and cut_lines[1].ends_with("...") and int(cut["size"]) == int(2.6 * mm)
		and widest.call(cut) <= box, "name/too long even then: two lines at the smallest size, cut with ... (%s)" % [cut_lines])
	var kept := cut_lines[1].trim_suffix("...").split(" ", false)
	_ok(not kept.is_empty() and long_name.to_upper().split(" ").has(kept[kept.size() - 1]),
		"name/and cut at a whole word (%s)" % cut_lines[1])
	var lp := MediaLabelPainter.lp_name_fit("Songs from the Big Chair and Other Stories")
	_ok((lp["lines"] as PackedStringArray).size() == 3, "name/an LP gives it three lines (%s)" % [lp["lines"]])
	_eq(MediaLabelPainter.strip_brackets("Album (Live) [2011]"), "Album", "name/both trailing groups go")
	_eq(MediaLabelPainter.strip_brackets("(What's the Story) Morning Glory?"), "(What's the Story) Morning Glory?",
		"name/a group that is not trailing stays")
	_eq(MediaLabelPainter.strip_brackets("(Untitled)"), "(Untitled)", "name/a name that is all brackets is kept")
