## Mod UID self-tests — what a mounted pack's scenes name by UID is found by it,
## headless, with no core, no ROM and no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/mod_uids_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/mod_uids_tests.tscn -- --only=mount
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## A pack cannot carry the UID cache, so until ModUids read them from its .import
## and .uid files every UID a mod's scene used was unknown: each texture it loaded
## logged "invalid UID ... using text path instead" and was found by its path. The
## cases:
##
##   dir/   ModUids.register_dir over a folder of fixtures: an import's UID names
##          the file it imports, a .uid file the file beside it, subfolders are
##          walked, a hidden one is not, a broken entry is passed over, a UID the
##          game already has keeps its path, and a second pass adds nothing;
##   mount/ a pack the mod manager mounts after boot: its UIDs are known once it
##          is, a scene of it finds its texture and its script by UID with no
##          warning, and finds them by UID even where its text path is wrong.
##          The control: a scene whose UID nothing registered does warn, so the
##          warnings are watched where they would be heard.
##
## The pack mounted under mount/ stays mounted to the end of the run, as a pack
## does (it cannot be taken off). Nothing after it is the worse for that.
extends Node

## How many cases this file contains, NOT counting the guard below — it is
## checked before it has recorded itself. A case that never ran is not one that
## passed: bump this when adding cases.
const EXPECTED_CASES := 25

const MANAGER := preload("res://Scripts/Mods/mod_manager.gd")
const MOD := "t.uids"
## A script of the game's own whose UID is committed beside it.
const GAME_SCRIPT := "res://Tests/pointer_fit_tests.gd"

## Every warning and error the engine logs while it is attached.
class Heard extends Logger:
	var _lock := Mutex.new()
	var _lines: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String,
			rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		_lines.append(code if rationale.is_empty() else "%s (%s)" % [code, rationale])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## What was logged since the last take that contains `part`; all of it for ""
	## (which no string "contains").
	func take(part: String) -> Array[String]:
		_lock.lock()
		var out: Array[String] = []
		for line in _lines:
			if part.is_empty() or line.contains(part):
				out.append(line)
		_lines.clear()
		_lock.unlock()
		return out

var _pass := 0
var _fail := 0
var _only := ""
var _dir := "user://mod_uids_tests"
var _heard := Heard.new()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--only="):
			_only = str(a).substr("--only=".length())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[uids] TIMEOUT")
		get_tree().quit(1))
	OS.add_logger(_heard)

	_remove_tree(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	if _want("dir"):
		_test_dir()
	if _want("mount"):
		_test_mount()

	OS.remove_logger(_heard)
	if _only.is_empty():
		_ok(_pass + _fail == EXPECTED_CASES, "suite/every case ran",
			"%d ran, %d expected" % [_pass + _fail, EXPECTED_CASES])
	print("[uids] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _want(group: String) -> bool:
	return _only.is_empty() or group.begins_with(_only) or _only.begins_with(group)


# ── dir ───────────────────────────────────────────────────────────────────────

func _test_dir() -> void:
	var root := _dir.path_join("fixture")
	var imported := ResourceUID.create_id()
	var beside := ResourceUID.create_id()
	var nested := ResourceUID.create_id()
	var hidden := ResourceUID.create_id()
	var game := ResourceLoader.get_resource_uid(GAME_SCRIPT)
	_ok(game != ResourceUID.INVALID_ID and ResourceUID.get_id_path(game) == GAME_SCRIPT,
		"dir/the game's own script has its UID (the case below needs one)")
	_ok(not ResourceUID.has_id(imported) and not ResourceUID.has_id(beside)
		and not ResourceUID.has_id(nested) and not ResourceUID.has_id(hidden),
		"dir/the fixtures' UIDs are new")

	_write(root.path_join("tex.png.import"), _import_text(imported, "res://nowhere/tex.ctex"))
	_write(root.path_join("s.gd.uid"), _uid(beside) + "\n")
	_write(root.path_join("sub/deeper/t.gd.uid"), _uid(nested))
	_write(root.path_join(".godot/u.gd.uid"), _uid(hidden))
	_write(root.path_join("plain.png.import"), "[remap]\n\nimporter=\"texture\"\n")
	_write(root.path_join("junk.gd.uid"), "not a uid\n")
	_write(root.path_join("broken.png.import"), "this is [not a config file\n")
	_write(root.path_join("claims.gd.uid"), ResourceUID.id_to_text(game))

	_eq(ModUids.register_dir(root), 3, "dir/three UIDs are added")
	_eq(ResourceUID.get_id_path(imported), root.path_join("tex.png"),
		"dir/an import's UID names the file it imports, not what it was imported to")
	_eq(ResourceUID.get_id_path(beside), root.path_join("s.gd"),
		"dir/a .uid file's names the file beside it")
	_eq(ResourceUID.get_id_path(nested), root.path_join("sub/deeper/t.gd"),
		"dir/subfolders are walked")
	_ok(not ResourceUID.has_id(hidden), "dir/a hidden folder is not")
	_eq(ResourceUID.get_id_path(game), GAME_SCRIPT,
		"dir/a UID the game already has keeps the game's path")
	_eq(ModUids.register_dir(root), 0, "dir/a second pass adds nothing")
	_eq(ModUids.register_dir(_dir.path_join("absent")), 0, "dir/a folder that is not there adds nothing")
	_eq(ModUids.register("t.notmounted"), 0, "dir/nor does a mod that is not mounted")


# ── mount ─────────────────────────────────────────────────────────────────────

func _test_mount() -> void:
	# The control: the loader warns about a UID it does not know, and it is heard.
	var stray := ResourceUID.create_id()
	_write(_dir.path_join("ctl.gd"), "extends Node3D\n")
	_write(_dir.path_join("ctl.tscn"), _scene_text(stray, "Script", _dir.path_join("ctl.gd"), "script"))
	_heard.take("")
	var ctl := load(_dir.path_join("ctl.tscn")) as PackedScene
	var warned := _heard.take("invalid UID")
	_ok(ctl != null and warned.size() == 1 and warned[0].contains(ResourceUID.id_to_text(stray)),
		"mount/the control: a scene naming a UID nothing registered warns, and is heard", str(warned))

	# The pack, mounted after boot as Apply does it, from a folder of its own: a
	# mounted container stays open to the end, and on Windows cannot be deleted
	# until then (the next run clears it).
	var live_dir := _dir + "_live"
	_remove_tree(live_dir)
	var mods := live_dir.path_join("mods")
	DirAccess.make_dir_recursive_absolute(mods)
	var tex_id := ResourceUID.create_id()
	var script_id := ResourceUID.create_id()
	var ns := "res://mods/%s/" % MOD
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.1))
	var made := _dir.path_join("dot.res")
	_ok(ResourceSaver.save(ImageTexture.create_from_image(img), made) == OK,
		"mount/the fixture's imported texture is written")
	var entries := {
		"mods/%s/mod.json" % MOD: JSON.stringify({"id": MOD, "api_version": 1,
			"version": "1.0.0", "name": MOD, "entry": ns + "m.gd"}),
		"mods/%s/m.gd" % MOD: "extends RetroMod\n",
		"mods/%s/look.gd" % MOD: "extends Node3D\n\nconst TAG := \"%s look\"\n" % MOD,
		"mods/%s/look.gd.uid" % MOD: _uid(script_id) + "\n",
		"mods/%s/dot.png.import" % MOD: _import_text(tex_id, ns + "_imported/dot.png-0.res"),
		"mods/%s/_imported/dot.png-0.res" % MOD: FileAccess.get_file_as_bytes(made),
		# What a mod's scene says: each resource by UID, then by path.
		"mods/%s/look.tscn" % MOD: _look_scene(tex_id, ns + "dot.png", script_id, ns + "look.gd"),
		# The same with the paths wrong: it can only be found by UID.
		"mods/%s/moved.tscn" % MOD: _look_scene(tex_id, ns + "gone.png", script_id, ns + "gone.gd"),
	}
	_write_zip(mods.path_join(MOD + ".zip"), entries)

	var m: Node = MANAGER.new()
	m.mods_root_override = mods
	m.state_path_override = live_dir.path_join("mods.json")
	m._hooks = ModHooks.new(get_tree())
	m._discover()
	m.set_enabled(MOD, true)
	_ok(not ResourceUID.has_id(tex_id) and not ResourceUID.has_id(script_id),
		"mount/before it is mounted its UIDs are unknown")
	_heard.take("")
	var mounted: Array = m.apply_live()
	var rec: ModRecord = m.mod(MOD)
	_ok(mounted.size() == 1 and rec.status == ModRecord.Status.LOADED,
		"mount/the pack mounts and loads", rec.reason)
	_eq(ResourceUID.get_id_path(tex_id), ns + "dot.png", "mount/its texture's UID is known once it is")
	_eq(ResourceUID.get_id_path(script_id), ns + "look.gd", "mount/and its script's")

	_heard.take("")
	var look := load(ns + "look.tscn") as PackedScene
	var said := _heard.take("")
	_ok(look != null, "mount/its scene loads")
	_eq(", ".join(said), "", "mount/with nothing said: no UID is invalid, nothing is found by path")
	_shows(look, "mount/")

	var moved := load(ns + "moved.tscn") as PackedScene
	said = _heard.take("")
	_ok(moved != null, "mount/a scene whose paths are wrong still loads", ", ".join(said))
	_shows(moved, "mount/moved: ")
	_eq(ModUids.register(MOD), 0, "mount/the mod's UIDs are registered once")
	m.free()


## The scene's one node wears the pack's script and its texture.
func _shows(scene: PackedScene, prefix: String) -> void:
	var node := scene.instantiate() if scene != null else null
	var sprite := node as Sprite3D
	_ok(sprite != null and sprite.get_script() != null and str(sprite.get("TAG")) == MOD + " look",
		prefix + "the script it names by UID is the pack's",
		"%s" % [node.get_script().resource_path if node != null and node.get_script() != null else "none"])
	_ok(sprite != null and sprite.texture != null and sprite.texture.get_width() == 4,
		prefix + "and so is the texture")
	if node != null:
		node.free()


# ── fixtures ──────────────────────────────────────────────────────────────────

func _uid(id: int) -> String:
	return ResourceUID.id_to_text(id)


func _import_text(id: int, imported_path: String) -> String:
	return "[remap]\n\nimporter=\"texture\"\ntype=\"Texture2D\"\nuid=\"%s\"\npath=\"%s\"\n" \
		% [_uid(id), imported_path]


func _scene_text(id: int, type: String, path: String, property: String) -> String:
	return ("[gd_scene format=3]\n\n[ext_resource type=\"%s\" uid=\"%s\" path=\"%s\" id=\"1\"]\n\n"
		+ "[node name=\"N\" type=\"Node3D\"]\n%s = ExtResource(\"1\")\n") % [type, _uid(id), path, property]


func _look_scene(tex_id: int, tex_path: String, script_id: int, script_path: String) -> String:
	return ("[gd_scene format=3]\n\n"
		+ "[ext_resource type=\"Script\" uid=\"%s\" path=\"%s\" id=\"1\"]\n"
		+ "[ext_resource type=\"Texture2D\" uid=\"%s\" path=\"%s\" id=\"2\"]\n\n"
		+ "[node name=\"Look\" type=\"Sprite3D\"]\nscript = ExtResource(\"1\")\ntexture = ExtResource(\"2\")\n") \
		% [_uid(script_id), script_path, _uid(tex_id), tex_path]


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _write_zip(path: String, entries: Dictionary) -> void:
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return
	for member: String in entries:
		z.start_file(member)
		var value: Variant = entries[member]
		z.write_file(value if value is PackedByteArray else str(value).to_utf8_buffer())
		z.close_file()
	z.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ── assertions ────────────────────────────────────────────────────────────────

func _ok(cond: bool, test_name: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[uids] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[uids] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


func _eq(got: Variant, want: Variant, test_name: String) -> void:
	_ok(got == want, test_name, "got %s, want %s" % [str(got), str(want)])
