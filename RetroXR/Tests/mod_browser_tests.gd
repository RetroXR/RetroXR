## mod_browser_tests — installing, updating and removing a mod from inside the
## app, headless, with no network and without touching the player's mods folder.
##
##   godot --headless --path RetroXR res://Tests/mod_browser_tests.tscn
##   godot --headless --path RetroXR res://Tests/mod_browser_tests.tscn -- --only=install
##
## Groups:
##   install/   a vetted file lands in the mods root, disabled; a bad one never does
##   update/    one container per id, whatever the old one was called
##   mounted/   A MOUNTED PACK IS NOT TOUCHED UNTIL THE NEXT LAUNCH
##   remove/    removal, and the state it leaves behind
##   pending/   the moves carried over a restart, and what the list may not reach
##   catalogue/ what a mod.io reply becomes, and the request that asks for it
##   scan/      a file mod.io has not scanned clean is not offered
##   policy/    a download may not carry a game or a program
##   collection/ packs: what installing and removing one comes to
##   consent/   NOTHING BUT THE TERMS IS ASKED OF MOD.IO BEFORE THE PLAYER AGREES
##   bundle/    one upload holding a build per platform, or a wrapped .pck
##   review/    a download waits for the player's answer, and for nothing else
##   space/     a file that will not fit is refused before it is fetched
##   thumbnail/ the preview image the packer insists on
##   download/  a fetch from a local server: redirect, checksum, install, refusal
##
## Every case runs against its OWN ModManager, built here and never added to the
## tree, pointed at a scratch root and a scratch state file through the two
## override seams. The `Mods` autoload and <data root>/mods are never touched,
## and nothing is mounted: `mounted` is set by hand, which is the only thing the
## code under test reads.
##
## Exits 0 when everything passes, 1 otherwise.
extends Node

const MANAGER := preload("res://Scripts/Mods/mod_manager.gd")

var _pass := 0
var _fail := 0
var _only := ""
var _dir := ""
var _root := ""
var _state := ""


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[test] TIMEOUT"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_dir = OS.get_user_data_dir().replace("\\", "/") + "/mod_browser_tests"
	_root = _dir.path_join("mods")
	_state = _dir.path_join("mods.json")

	if _want("install"):   _group_install()
	if _want("batch"):     _group_batch()
	if _want("update"):    _group_update()
	if _want("mounted"):   _group_mounted()
	if _want("remove"):    _group_remove()
	if _want("pending"):   _group_pending()
	if _want("catalogue"): _group_catalogue()
	if _want("scan"):      _group_scan()
	if _want("policy"):    _group_policy()
	if _want("collection"): _group_collection()
	if _want("consent"):   await _group_consent()
	if _want("bundle"):    _group_bundle()
	if _want("review"):    _group_review()
	if _want("space"):     await _group_space()
	if _want("thumbnail"): _group_thumbnail()
	if _want("download"):  await _group_download()

	_remove_tree(_dir)
	print("[test] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


# ── install/ ──────────────────────────────────────────────────────────────────

func _group_install() -> void:
	var m := _fresh()
	var changed := [0]
	m.mods_changed.connect(func() -> void: changed[0] += 1)

	var staged := _stage(m, "dl-1.zip", _pack("t.one", "1.0.0"))
	var out: Dictionary = m.install(staged, {"modio_id": 7, "file_id": 70})
	_ok(bool(out["ok"]), "install/a good pack is accepted", str(out["error"]))
	_eq(str(out["id"]), "t.one", "install/reports the id it read")
	_ok(FileAccess.file_exists(_root.path_join("t.one.zip")), "install/lands as <id>.zip")
	_ok(not FileAccess.file_exists(staged), "install/staging file is gone")
	_eq(changed[0], 1, "install/announces the change once")

	var rec: ModRecord = m.mod("t.one")
	_ok(rec != null, "install/has a record without a restart")
	if rec != null:
		_eq(rec.status, ModRecord.Status.DISABLED, "install/lands disabled")
		_eq(rec.path, _root.path_join("t.one.zip"), "install/record names the installed file")
	_ok(not m.is_enabled("t.one"), "install/is not enabled for the player")
	_ok(not bool(out["restart"]), "install/a disabled mod needs no restart")
	_ok(not m.restart_pending(), "install/nothing is pending")
	_eq(int(m.source("t.one").get("modio_id", 0)), 7, "install/keeps where it came from")
	_ok(m.find_by_source("modio_id", 7) == rec, "install/found again by its source")
	_ok(m.find_by_source("modio_id", 8) == null, "install/another source finds nothing")

	# The state has to survive the process, or a tile forgets it is installed.
	var again := _fresh(false)
	again._load_state()
	again._discover()
	_ok(again.mod("t.one") != null, "install/discovered at the next launch")
	_eq(int(again.source("t.one").get("file_id", 0)), 70, "install/source survives a restart")

	# Refusals. Each must leave the mods root exactly as it was.
	var before := _listing(_root)
	var escaped := _pack("t.two", "1.0.0")
	escaped["Scripts/evil.gd"] = "extends Node"
	out = m.install(_stage(m, "dl-2.zip", escaped))
	_ok(not bool(out["ok"]), "install/a namespace escape is refused")
	_ok(not str(out["error"]).is_empty(), "install/says why", str(out["error"]))
	_ok(not FileAccess.file_exists(m.incoming_dir().path_join("dl-2.zip")),
		"install/a refused download is deleted")

	out = m.install(_stage(m, "dl-3.zip", {"readme.txt": "not a mod"}))
	_ok(not bool(out["ok"]), "install/no manifest is refused")

	var elsewhere := _pack("t.three", "1.0.0", ["Nintendo64"])
	out = m.install(_stage(m, "dl-4.zip", elsewhere))
	_ok(not bool(out["ok"]), "install/another platform's mod is refused")
	_ok(str(out["error"]).contains(OS.get_name()), "install/names this platform", str(out["error"]))

	var junk: String = m.incoming_dir().path_join("dl-5.zip")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("this is not a zip archive")
	f.close()
	out = m.install(junk)
	_ok(not bool(out["ok"]), "install/a corrupt archive is refused")

	_eq(_listing(_root), before, "install/refusals leave the mods root untouched")
	_ok(m.mod("t.two") == null and m.mod("t.three") == null,
		"install/a refused mod gets no record")
	m.free()
	again.free()


# ── update/ ───────────────────────────────────────────────────────────────────

func _group_update() -> void:
	# A hand-installed pack under a name of the author's choosing, then the same
	# mod from the browser. Two files with one id refuse BOTH at the next boot,
	# so the old one has to go whatever it is called.
	var m := _fresh()
	_write_zip(_root.path_join("My Cool Mod v1.zip"), _pack("t.one", "1.0.0"))
	m._discover()
	_eq(m.mod("t.one").manifest.version, "1.0.0", "update/starts on the old version")
	m.set_enabled("t.one", true)

	var out: Dictionary = m.install(_stage(m, "dl-1.zip", _pack("t.one", "2.0.0")),
		{"modio_id": 7})
	_ok(bool(out["ok"]), "update/accepted", str(out["error"]))
	_eq(_listing(_root), PackedStringArray(["t.one.zip"]), "update/one container remains")
	_eq(m.mod("t.one").manifest.version, "2.0.0", "update/record is the new version")
	_ok(m.is_enabled("t.one"), "update/the player's switch is kept")
	_eq(m.mod("t.one").status, ModRecord.Status.PENDING, "update/an enabled mod waits for a restart")
	_ok(bool(out["restart"]), "update/says a restart is needed")

	var boot := _fresh(false)
	boot._load_state()
	boot._discover()
	_eq(boot.mod("t.one").status, ModRecord.Status.DISABLED,
		"update/no duplicate refusal at the next launch")
	_ok(boot.unreadable().is_empty(), "update/nothing unreadable left behind")
	boot.free()

	# The same when the player really had two copies. Both go.
	var d := _fresh()
	_write_zip(_root.path_join("a.zip"), _pack("t.dup", "1.0.0"))
	_write_zip(_root.path_join("b.zip"), _pack("t.dup", "1.0.0"))
	d._discover()
	_eq(d.mod("t.dup").status, ModRecord.Status.REFUSED, "update/a double install is refused")
	out = d.install(_stage(d, "dl-9.zip", _pack("t.dup", "1.1.0")))
	_ok(bool(out["ok"]), "update/installing over a double install works", str(out["error"]))
	_eq(_listing(_root), PackedStringArray(["t.dup.zip"]), "update/both old copies are gone")
	_eq(d.mod("t.dup").status, ModRecord.Status.DISABLED, "update/and it is no longer refused")
	m.free()
	d.free()


# ── mounted/ ──────────────────────────────────────────────────────────────────

func _group_mounted() -> void:
	var m := _fresh()
	_write_zip(_root.path_join("t.one.zip"), _pack("t.one", "1.0.0"))
	m._discover()
	m.set_enabled("t.one", true)
	var rec: ModRecord = m.mod("t.one")
	rec.status = ModRecord.Status.LOADED
	rec.mounted = true
	var old_bytes := FileAccess.get_file_as_bytes(_root.path_join("t.one.zip"))

	var out: Dictionary = m.install(_stage(m, "dl-1.zip", _pack("t.one", "2.0.0")))
	_ok(bool(out["ok"]) and bool(out["restart"]), "mounted/an update is accepted for later")
	_eq(FileAccess.get_file_as_bytes(_root.path_join("t.one.zip")), old_bytes,
		"mounted/the mounted file is byte-for-byte untouched")
	_ok(m.mod("t.one") == rec, "mounted/the record still describes what is mounted")
	_eq(rec.manifest.version, "1.0.0", "mounted/version shown is the one running")
	_eq(rec.update_staged, "2.0.0", "mounted/the waiting version is recorded")
	_eq(rec.update_size, ByteSize.on_disk(m.incoming_dir().path_join("t.one.zip")),
		"mounted/with the waiting pack's own size")
	_eq(rec.update_files, 2, "mounted/and its file count")
	_ok(rec.size != rec.update_size or rec.files == rec.update_files,
		"mounted/while size and files go on describing the running pack")
	_eq(SpawnMenuModsView.installed_status_text(rec), "Updates to 2.0.0 at next restart",
		"mounted/the page says which version is coming")
	_eq(m.fingerprint(), PackedStringArray(["t.one@1.0.0"]),
		"mounted/the netplay fingerprint is still this session's")
	_ok(m.restart_pending(), "mounted/a restart is pending")
	_ok(FileAccess.file_exists(m.incoming_dir().path_join("t.one.zip")),
		"mounted/the update waits in incoming")

	# A second update before the restart replaces the first; it does not queue behind it.
	out = m.install(_stage(m, "dl-2.zip", _pack("t.one", "3.0.0")))
	_eq(rec.update_staged, "3.0.0", "mounted/a newer update supersedes the waiting one")
	# The picture: the waiting pack's when it has one, else the running pack's.
	var here := ImageTexture.create_from_image(Image.create(16, 9, false, Image.FORMAT_RGB8))
	var coming := ImageTexture.create_from_image(Image.create(16, 9, false, Image.FORMAT_RGB8))
	rec.thumbnail = here
	_ok(SpawnMenuModsView.picture_of(rec) == here, "mounted/a waiting pack with no picture leaves the running one's")
	rec.update_thumbnail = coming
	_ok(SpawnMenuModsView.picture_of(rec) == coming, "mounted/a waiting pack's own picture is the one shown")
	# The same number again is a new copy, and is not called an update to itself.
	m.install(_stage(m, "dl-3.zip", _pack("t.one", "1.0.0")))
	_eq(SpawnMenuModsView.installed_status_text(rec), "A new copy of 1.0.0 installs at next restart",
		"mounted/a re-download of the running version is not called an update")
	_ok(rec.update_thumbnail == null, "mounted/and a newer download replaces the waiting picture with its own")
	# Back to the update the cases below expect to find after the restart.
	m.install(_stage(m, "dl-4.zip", _pack("t.one", "3.0.0")))
	_eq(m._pending.size(), 1, "mounted/one pending move per mod")

	var boot := _fresh(false)
	boot._load_state()
	boot._apply_pending()
	boot._discover()
	_eq(boot.mod("t.one").manifest.version, "3.0.0", "mounted/the update is in place after a restart")
	_ok(boot.is_enabled("t.one"), "mounted/still enabled after the update")
	_eq(boot._pending.size(), 0, "mounted/the pending list is cleared")
	_eq(_listing(boot.incoming_dir()), PackedStringArray(), "mounted/incoming is empty again")
	boot.free()

	# Removing a mounted mod: same rule.
	var r := _fresh()
	_write_zip(_root.path_join("t.gone.zip"), _pack("t.gone", "1.0.0"))
	r._discover()
	r.set_enabled("t.gone", true)
	var grec: ModRecord = r.mod("t.gone")
	grec.status = ModRecord.Status.LOADED
	grec.mounted = true
	out = r.remove("t.gone")
	_ok(bool(out["ok"]) and bool(out["restart"]), "mounted/removal is accepted for later")
	_ok(FileAccess.file_exists(_root.path_join("t.gone.zip")), "mounted/the file is still there")
	_ok(grec.removal_staged, "mounted/the record says it is going")
	_ok(not r.is_enabled("t.gone"), "mounted/it will not load again")
	_eq(r.fingerprint(), PackedStringArray(["t.gone@1.0.0"]),
		"mounted/a mod being removed is still in this session's fingerprint")
	r.set_enabled("t.gone", true)
	_ok(not r.is_enabled("t.gone"), "mounted/a mod on its way out cannot be re-enabled")

	var boot2 := _fresh(false)
	boot2._load_state()
	boot2._apply_pending()
	boot2._discover()
	_ok(boot2.mod("t.gone") == null, "mounted/the mod is gone after a restart")
	_ok(not FileAccess.file_exists(_root.path_join("t.gone.zip")), "mounted/and so is its file")
	boot2.free()
	m.free()
	r.free()


# ── batch/ ─────────────────────────────────────────────

## Several changes to the loader as one, and an install that does not vet twice.
func _group_batch() -> void:
	var m := _fresh()
	var changed := [0]
	m.mods_changed.connect(func() -> void: changed[0] += 1)
	var out: Dictionary = {}

	# A pack of several is ONE change: held, the loader installs, enables and
	# tags each but writes its state and says so once, when it is let go. Each
	# used to rebuild every list in the menu, in the frame Install was pressed.
	changed[0] = 0
	var state_file: String = m.state_path_override
	var stamp_before := FileAccess.get_file_as_string(state_file)
	m.hold_changes()
	m.hold_changes()
	for i in 3:
		var held: Dictionary = m.install(_stage(m, "held-%d.zip" % i, _pack("t.held%d" % i, "1.0.0")), {"modio_id": 20 + i})
		_ok(bool(held["ok"]), "batch/held, member %d still installs" % i, str(held["error"]))
		m.set_enabled("t.held%d" % i, true)
		m.set_source("t.held%d" % i, {"modio_id": 20 + i, "file_id": 5})
	_eq(changed[0], 0, "batch/held, nothing is announced while the batch runs")
	_eq(FileAccess.get_file_as_string(state_file), stamp_before, "batch/and the state file is not rewritten")
	m.release_changes()
	_eq(changed[0], 0, "batch/an inner release says nothing either")
	m.release_changes()
	_eq(changed[0], 1, "batch/let go, the whole batch is announced once")
	_ok(FileAccess.get_file_as_string(state_file).contains("t.held2"), "batch/and written once, with all of it")
	_ok(m.is_enabled("t.held0") and int(m.source("t.held2").get("file_id", 0)) == 5, "batch/nothing done while held was lost")
	m.release_changes()
	m.set_enabled("t.held0", false)
	_ok(FileAccess.get_file_as_string(state_file).contains("\"t.held0\": false"), "batch/a release too many leaves it working")

	# An install handed the vetting its caller already did does not repeat it;
	# one handed vetting for some other file, or a failed one, vets for itself.
	var good := _stage(m, "pre-1.zip", _pack("t.pre", "1.0.0"))
	var info: Dictionary = m.vet(good)
	var lie := info.duplicate()
	lie["manifest"] = ModManifest.parse({"id": "t.lie", "api_version": 1, "entry": "res://mods/t.lie/m.gd",
		"name": "Lie", "version": "9.9.9"})
	out = m.install(good, {}, lie)
	_eq(str(out.get("id", "")), "t.lie", "batch/vetting handed in for this file is used as given")
	var other := _stage(m, "pre-2.zip", _pack("t.other", "1.0.0"))
	out = m.install(other, {}, info)
	_eq(str(out.get("id", "")), "t.other", "batch/vetting for another file is not believed")
	var broken := _stage(m, "pre-3.zip", {"readme.txt": "not a mod"})
	var bad_info := {"manifest": lie["manifest"], "path": broken, "error": "", "files": PackedStringArray(), "thumbnail": null}
	DirAccess.remove_absolute(broken)
	out = m.install(broken, {}, bad_info)
	_ok(not bool(out["ok"]), "batch/nor is vetting for a file that is no longer there")


# ── remove/ ───────────────────────────────────────────────────────────────────

func _group_remove() -> void:
	var m := _fresh()
	m.install(_stage(m, "dl-1.zip", _pack("t.one", "1.0.0")), {"modio_id": 7})
	m.set_enabled("t.one", true)
	var out: Dictionary = m.remove("t.one")
	_ok(bool(out["ok"]) and not bool(out["restart"]), "remove/an unmounted mod goes at once")
	_eq(_listing(_root), PackedStringArray(), "remove/its file is deleted")
	_ok(m.mod("t.one") == null, "remove/its record is dropped")
	_ok(not m.is_enabled("t.one"), "remove/its switch is cleared")
	_ok(m.source("t.one").is_empty(), "remove/its source is forgotten")
	_ok(not m.restart_pending(), "remove/nothing waits on a restart")
	_ok(not bool(m.remove("t.one")["ok"]), "remove/twice is an error, not a crash")

	# Reinstalling must not come back enabled on the strength of the old switch.
	m.install(_stage(m, "dl-2.zip", _pack("t.one", "1.0.0")))
	_eq(m.mod("t.one").status, ModRecord.Status.DISABLED, "remove/a reinstall lands disabled")

	var junk := _root.path_join("broken.zip")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("nope")
	f.close()
	var u := _fresh(false)
	u._discover()
	_eq(u.unreadable().size(), 1, "remove/a corrupt pack is listed")
	_ok(not u.remove_unreadable(_root.path_join("t.one.zip")),
		"remove/remove_unreadable will not delete a readable mod")
	_ok(FileAccess.file_exists(_root.path_join("t.one.zip")), "remove/and the mod is still there")
	_ok(u.remove_unreadable(junk), "remove/a corrupt pack can be deleted")
	_ok(not FileAccess.file_exists(junk), "remove/and its file goes")
	m.free()
	u.free()


# ── pending/ ──────────────────────────────────────────────────────────────────

func _group_pending() -> void:
	# The pending list is a JSON file on disk. Nothing in it may reach a file
	# outside the mods root, or one that is not a mod container.
	var m := _fresh()
	var outside := _dir.path_join("precious.zip")
	_write_zip(outside, {"a.txt": "keep me"})
	var note := _root.path_join("notes.txt")
	var f := FileAccess.open(note, FileAccess.WRITE)
	f.store_string("keep me too")
	f.close()
	_write_zip(_root.path_join("victim.zip"), _pack("t.v", "1.0.0"))

	JsonStore.write_dict(_state, {"enabled": {}, "pending": [
		{"op": "remove", "id": "x", "files": ["../precious.zip", "notes.txt", outside]},
		{"op": "install", "id": "y", "from": "../precious.zip", "to": "y.zip", "replaces": []},
		{"op": "install", "id": "z", "from": "missing.zip", "to": "z.zip",
			"replaces": ["victim.zip"]},
		{"op": "format-the-disk"},
		"not even a dictionary",
	]}, "")
	var boot := _fresh(false)
	boot._load_state()
	boot._apply_pending()
	_ok(FileAccess.file_exists(outside), "pending/a path cannot climb out of the mods root")
	_ok(FileAccess.file_exists(note), "pending/a non-container is never deleted")
	_ok(not FileAccess.file_exists(_root.path_join("y.zip")),
		"pending/an install cannot pull a file in from outside incoming")
	_ok(FileAccess.file_exists(_root.path_join("victim.zip")),
		"pending/an install whose file is missing replaces nothing")
	_eq(boot._pending.size(), 0, "pending/the list is cleared even when ops were skipped")
	_ok(not boot.restart_pending(), "pending/and no restart is asked for again")
	DirAccess.remove_absolute(outside)
	m.free()
	boot.free()


# ── catalogue/ ────────────────────────────────────────────────────────────────

## One Mod object in the shape mod.io documents, trimmed to what is read.
func _modio_mod(id: int, name: String, file_id: int) -> Dictionary:
	var d := {
		"id": id, "name": name, "summary": "A console for the room.",
		"profile_url": "https://mod.io/g/retroxr/m/%d" % id,
		"date_updated": 1790000000,
		"submitted_by": {"username": "xenu"},
		"logo": {"thumb_320x180": "https://thumb.modcdn.io/a/%d_320.png" % id,
			"thumb_640x360": "https://thumb.modcdn.io/a/%d_640.png" % id},
		"tags": [{"name": "Console"}, {"name": ""}, "junk"],
		"stats": {"downloads_total": 42, "ratings_display_text": "Very Positive"},
	}
	if file_id > 0:
		d["modfile"] = {"id": file_id, "filename": "pack.zip", "filesize": 1234,
			"version": "1.2.0", "filehash": {"md5": "ABCDEF0123456789ABCDEF0123456789"},
			"virus_status": 1, "virus_positive": 0,
			"download": {"binary_url": "https://g-14432.modapi.io/v1/dl/%d" % file_id}}
	return d


func _group_catalogue() -> void:
	var mod := ModioClient.parse_mod(_modio_mod(7, "PlayStation 2", 70))
	_eq(int(mod["id"]), 7, "catalogue/id")
	_eq(str(mod["name"]), "PlayStation 2", "catalogue/name")
	_eq(str(mod["author"]), "xenu", "catalogue/author is the uploader")
	_eq(str(mod["logo_small"]), "https://thumb.modcdn.io/a/7_320.png", "catalogue/tile image is the 320 thumb")
	_eq(str(mod["logo_large"]), "https://thumb.modcdn.io/a/7_640.png", "catalogue/detail image is the 640 thumb")
	_eq(mod["tags"], PackedStringArray(["Console"]), "catalogue/tags keep only named ones")
	_eq(int(mod["file_id"]), 70, "catalogue/file id")
	_eq(int(mod["file_size"]), 1234, "catalogue/file size")
	_eq(str(mod["file_md5"]), "abcdef0123456789abcdef0123456789", "catalogue/md5 is lowered for comparing")
	_eq(str(mod["download_url"]), "https://g-14432.modapi.io/v1/dl/70", "catalogue/download address")
	_eq(int(mod["downloads"]), 42, "catalogue/download count")

	# A page somebody made and has not uploaded to. Must not look downloadable.
	var empty := ModioClient.parse_mod(_modio_mod(8, "Coming soon", 0))
	_eq(int(empty["file_id"]), 0, "catalogue/no file is file id 0")
	_eq(str(empty["download_url"]), "", "catalogue/no file has no address")
	# And a reply with nothing in it at all: every key present, nothing thrown.
	var blank := ModioClient.parse_mod({})
	_eq(int(blank["id"]), 0, "catalogue/an empty object parses to id 0")
	_eq(blank.size(), mod.size(), "catalogue/every field is present whatever was sent")
	var hostile := ModioClient.parse_mod({"id": 9, "logo": "nope", "modfile": [], "tags": 5,
		"stats": null, "submitted_by": 3})
	_eq(int(hostile["id"]), 9, "catalogue/wrong-typed fields do not break the rest")

	var path := ModioClient.list_path("mario & luigi", "-downloads_total", 48, 24, "KEY")
	_ok(path.begins_with("/games/14432/mods?api_key=KEY"), "catalogue/asks this game with the key", path)
	_ok(path.contains("_offset=48") and path.contains("_limit=24"), "catalogue/pages by offset", path)
	_ok(path.contains("_sort=-downloads_total"), "catalogue/sort is passed through", path)
	_ok(path.contains("_q=mario%20%26%20luigi"), "catalogue/the search is escaped", path)
	_ok(not ModioClient.list_path("   ", "", 0, 24).contains("_q="), "catalogue/a blank search sends none")
	_ok(not ModioClient.list_path("", "", 0, 24).contains("_sort="), "catalogue/no sort sends none")
	_ok(ModioClient.list_path("", "", -5, 24).contains("_offset=0"), "catalogue/offset never goes negative")

	_ok(ModioClient.describe(HTTPRequest.RESULT_SUCCESS, 429, "17").contains("17 s"),
		"catalogue/a rate limit says how long")
	_ok(ModioClient.describe(HTTPRequest.RESULT_SUCCESS, 429, "0").contains("60 s"),
		"catalogue/a rolling limit means the minute")
	_ok(ModioClient.describe(HTTPRequest.RESULT_CANT_CONNECT, 0).contains("reach"),
		"catalogue/no connection is said as that")
	_eq(ModioClient.report_url(7), "https://mod.io/report/mods/7/widget", "catalogue/report address")

	_eq(SpawnMenuModsView.state_text(""), "", "catalogue/a mod not here has no badge")
	_ok(not SpawnMenuModsView.state_text("update").is_empty(), "catalogue/an update has a badge")
	_ok(not SpawnMenuModsView.state_text("nofile").is_empty(), "catalogue/no file has a badge")


# ── scan/ ─────────────────────────────────────────────────────────────────────

func _group_scan() -> void:
	var clean := ModioClient.parse_mod(_modio_mod(7, "A", 70))
	_eq(int(clean["virus_status"]), 1, "scan/the scan state is read")
	_eq(ModioClient.scan_problem(clean), "", "scan/a finished clean scan is fine")
	var raw := _modio_mod(7, "A", 70)
	(raw["modfile"] as Dictionary)["virus_status"] = 0
	_ok(not ModioClient.scan_problem(ModioClient.parse_mod(raw)).is_empty(),
		"scan/a file not scanned yet is refused")
	(raw["modfile"] as Dictionary)["virus_status"] = 2
	_ok(not ModioClient.scan_problem(ModioClient.parse_mod(raw)).is_empty(),
		"scan/a scan still running is refused")
	(raw["modfile"] as Dictionary)["virus_status"] = 1
	(raw["modfile"] as Dictionary)["virus_positive"] = 1
	_ok(ModioClient.scan_problem(ModioClient.parse_mod(raw)).contains("flagged"),
		"scan/a flagged file is refused, and said to be flagged")
	_ok(not ModioClient.scan_problem({}).is_empty(), "scan/no scan fields at all is refused")

	# The tile and the page offer no download for one. 9001 is installed nowhere.
	var unscanned := ModioClient.parse_mod(_modio_mod(9001, "A", 70))
	unscanned["virus_status"] = 0
	_eq(SpawnMenuModsView.browse_state(unscanned), "unscanned", "scan/the tile says it is being scanned")
	_eq(SpawnMenuModsView.browse_state(ModioClient.parse_mod(_modio_mod(9001, "A", 70))), "",
		"scan/a clean one is offered")
	_eq(SpawnMenuModsView.browse_state(unscanned, false, true), "review",
		"scan/a download waiting for an answer says so")
	_ok(not SpawnMenuModsView.state_text("unscanned").is_empty()
		and not SpawnMenuModsView.state_text("review").is_empty(), "scan/both have a badge")

	_eq(ModioClient.platform_header("Android"), "oculus", "scan/a Quest names its platform")
	_eq(ModioClient.platform_header("Windows"), "windows", "scan/so does a desktop")
	_eq(ModioClient.platform_header("Haiku"), "", "scan/an unknown one sends none")


# ── policy/ ───────────────────────────────────────────────────────────────────

func _group_policy() -> void:
	var denied := {"sfc": true, "iso": true, "dll": true}
	_eq(ModContentPolicy.violation(PackedStringArray(["res://mods/a/mod.json",
		"res://mods/a/m.gd", "res://mods/a/shell.png", "res://mods/a/x.glb.import",
		"res://mods/a/_imported/x.glb-1f.scn", "res://mods/a/_imported/t.png-2a.s3tc.ctex"]), denied),
		"", "policy/scripts, pictures and imported files pass")
	_ok(ModContentPolicy.violation(PackedStringArray(["res://mods/a/mod.json",
		"res://mods/a/Game (USA).SFC"]), denied).contains("Game (USA).SFC"),
		"policy/a game is refused by name, whatever its case")
	_ok(ModContentPolicy.violation(PackedStringArray(["res://mods/a/lib.dll"]), denied).contains("program"),
		"policy/a program is refused as one")
	_eq(ModContentPolicy.violation(PackedStringArray(["res://mods/a/README"]), denied), "",
		"policy/a file with no extension is not guessed at")

	# The real list, from the core database.
	var real := ModContentPolicy.denied_extensions()
	for ext: String in ["iso", "nes", "sfc", "gba", "chd", "cue", "bin", "zip", "md", "exe", "so", "dll"]:
		_ok(real.has(ext), "policy/.%s is on the list" % ext)
	for ext: String in ["png", "txt", "ogg", "wav", "gd", "tscn", "json", "ctex", "scn", "import", "glb"]:
		_ok(not real.has(ext), "policy/.%s is not" % ext)

	# Wired in: a DOWNLOAD carrying a game is refused and deleted...
	var m := _fresh()
	var loaded := _pack("t.rom", "1.0.0")
	loaded["mods/t.rom/Super Game.sfc"] = "not really"
	var out: Dictionary = m.install(_stage(m, "dl-1.zip", loaded), {"modio_id": 7})
	_ok(not bool(out["ok"]) and str(out["error"]).contains("Super Game.sfc"),
		"policy/a download carrying a game is not installed", str(out["error"]))
	_eq(_listing(_root), PackedStringArray(), "policy/and nothing reaches the mods root")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "policy/and the file is deleted")
	# ...while the same pack copied in by hand is the player's own business.
	_write_zip(_root.path_join("mine.zip"), loaded)
	m._discover()
	_ok(m.mod("t.rom") != null and m.mod("t.rom").status != ModRecord.Status.REFUSED,
		"policy/a pack the player copied in themselves is not held to it")
	m.free()

	# A download nobody answered for does not outlive the session; a partial does.
	m = _fresh()
	_stage(m, "modio-7.zip", _pack("t.left", "1.0.0"))
	var part := FileAccess.open(m.incoming_dir().path_join("modio-8.zip.part"), FileAccess.WRITE)
	part.store_string("half")
	part.close()
	m._apply_pending()
	_eq(_listing(m.incoming_dir()), PackedStringArray(["modio-8.zip.part"]),
		"policy/an unanswered download is swept at the next launch, a partial kept")
	m.free()


# ── collection/ ───────────────────────────────────────────────────────────────

func _group_collection() -> void:
	var pack := ModioClient.parse_collection({"id": 3, "name": "Sony shelf",
		"summary": "Every PlayStation.", "submitted_by": {"username": "xenu"},
		"profile_url": "https://mod.io/g/retroxr/c/sony-shelf", "filesize": 5000,
		"logo": {"thumb_320x180": "https://t/3_320.png", "thumb_640x360": "https://t/3_640.png"},
		"stats": {"downloads_total": 9}, "incomplete": 1})
	_eq(int(pack["id"]), 3, "collection/id")
	_eq(str(pack["author"]), "xenu", "collection/curator")
	_eq(str(pack["logo_small"]), "https://t/3_320.png", "collection/tile image")
	_eq(int(pack["file_size"]), 5000, "collection/total size")
	_ok(bool(pack["incomplete"]), "collection/mod.io's incomplete flag is kept")
	_eq(ModioClient.parse_collection({}).size(), pack.size(), "collection/every field is present whatever was sent")
	var cpath := ModioClient.collections_path("sony & co", "-date_live", 24, 24, "KEY")
	_ok(cpath.begins_with("/games/14432/collections?api_key=KEY") and cpath.contains("_offset=24")
		and cpath.contains("_q=sony%20%26%20co"), "collection/the list request", cpath)
	_eq(ModioClient.members_path(3, 100, 100, "KEY"),
		"/games/14432/collections/3/mods?api_key=KEY&_limit=100&_offset=100", "collection/the members request")
	_ok(ModioClient.list_path("", "", 0, 24, "KEY", "Knick Knack").ends_with("&tags=Knick%20Knack"),
		"collection/a tag filter is escaped onto a mod list")
	_ok(not ModioClient.list_path("", "", 0, 24, "KEY").contains("tags="), "collection/and absent when none is chosen")
	_eq(ModioClient.parse_tags([{"tags": ["Console", "Controller"]}, {"tags": ["Console", ""], "hidden": false},
		{"tags": ["Secret"], "hidden": true}, "junk"]), PackedStringArray(["Console", "Controller"]),
		"collection/tags are flattened, once each, hidden groups left out")

	# What installing a pack comes to.
	var a := ModioClient.parse_mod(_modio_mod(1, "A", 10))
	var b := ModioClient.parse_mod(_modio_mod(2, "B", 20))
	var c := ModioClient.parse_mod(_modio_mod(3, "C", 0))
	var d := ModioClient.parse_mod(_modio_mod(4, "D", 40))
	d["virus_status"] = 0
	var e := ModioClient.parse_mod(_modio_mod(5, "E", 50))
	var members: Array = [a, b, c, d, e, a]
	var plan := ModCollectionPlan.plan_install(members, {2: 20, 5: 49})
	_eq(_names(plan["fetch"]), ["A", "E"], "collection/fetches what is missing and what is out of date")
	_eq(_names(plan["have"]), ["B"], "collection/leaves alone what is already at mod.io's file")
	_eq(_names(plan["skip"]), ["C", "D"], "collection/skips a member with no file and one not scanned")
	_ok(str((plan["skip"] as Array)[1]["why"]).contains("scan"), "collection/and says why")
	_eq((plan["fetch"] as Array).size() + (plan["have"] as Array).size() + (plan["skip"] as Array).size(), 5,
		"collection/a member listed twice is counted once")

	_eq(ModCollectionPlan.pack_state(members, {}), "", "collection/none here is no state")
	_eq(ModCollectionPlan.pack_state(members, {2: 20}), "partial", "collection/some here is partial")
	_eq(ModCollectionPlan.pack_state(members, {1: 10, 2: 20, 5: 49}), "update",
		"collection/all here with one out of date is an update")
	_eq(ModCollectionPlan.pack_state(members, {1: 10, 2: 20, 5: 50}), "installed",
		"collection/all that can be installed are: installed, despite the two that cannot")

	# Two members after one file, and a member after a file an installed mod has.
	var clash := ModCollectionPlan.conflicts({
		"A": ["res://Textures/logo.png", "res://Shaders/x.gdshader"],
		"B": ["res://Textures/logo.png"], "Old": ["res://Shaders/x.gdshader"], "Quiet": []})
	_eq(clash, PackedStringArray(["Old and A both replace res://Shaders/x.gdshader".replace("Old and A", "A and Old"),
		"A and B both replace res://Textures/logo.png"]), "collection/each contested file is named once")
	_eq(ModCollectionPlan.conflicts({"A": ["res://a"], "B": ["res://b"]}), PackedStringArray(),
		"collection/no shared file is no conflict")

	# Bookkeeping: which packs want a mod, and whether the player does.
	var fresh_src := ModCollectionPlan.source_after_install({}, 1, 10, "u", 3)
	_eq(ModCollectionPlan.collections_of(fresh_src), [3], "collection/a new member belongs to its pack")
	_ok(not ModCollectionPlan.is_individual(fresh_src), "collection/and was not asked for on its own")
	var owned := ModCollectionPlan.source_after_install({"modio_id": 2, "file_id": 20}, 2, 21, "u", 3)
	_ok(ModCollectionPlan.is_individual(owned), "collection/a mod that was here first stays the player's own")
	_eq(int(owned["file_id"]), 21, "collection/and takes the new file")
	var twice := ModCollectionPlan.source_after_install(fresh_src, 1, 10, "u", 4)
	_eq(ModCollectionPlan.collections_of(twice), [3, 4], "collection/a second pack is added, not swapped in")
	_eq(ModCollectionPlan.collections_of(ModCollectionPlan.source_after_install(twice, 1, 10, "u", 4)), [3, 4],
		"collection/the same pack twice is recorded once")
	_ok(ModCollectionPlan.is_individual(ModCollectionPlan.source_after_single(fresh_src, 1, 10, "u"))
		and ModCollectionPlan.collections_of(ModCollectionPlan.source_after_single(fresh_src, 1, 10, "u")) == [3],
		"collection/installing a member on its own keeps its pack too")
	_eq(ModCollectionPlan.collections_of({"collections": [3.0, 4.0, "x", 3.0]}), [3, 4],
		"collection/ids read back from JSON as floats are the same ids")

	# Removing a pack takes only what it alone brought.
	var removal := ModCollectionPlan.plan_remove(3, {
		"t.only": fresh_src, "t.owned": owned, "t.shared": twice,
		"t.other": ModCollectionPlan.source_after_install({}, 9, 90, "u", 4),
		"t.hand": {"modio_id": 8, "file_id": 80}})
	_eq(removal["remove"], ["t.only"] as Array[String], "collection/removes the member only this pack wanted")
	var kept: Dictionary = removal["keep"]
	_eq(kept.keys(), ["t.owned", "t.shared"], "collection/keeps the player's own and another pack's")
	_eq(ModCollectionPlan.collections_of(kept["t.shared"]), [4], "collection/and forgets this pack on them")
	_eq(ModCollectionPlan.collections_of(kept["t.owned"]), [], "collection/leaving the player's own with none")
	_eq((ModCollectionPlan.plan_remove(4, {"t.owned": kept["t.owned"]})["remove"] as Array).size(), 0,
		"collection/a pack that never held a mod removes nothing")

	# And the loader keeps the record it is handed.
	var m := _fresh()
	m.install(_stage(m, "dl-1.zip", _pack("t.one", "1.0.0")), fresh_src)
	m.set_source("t.one", twice)
	var again := _fresh(false)
	again._load_state()
	again._discover()
	_eq(ModCollectionPlan.collections_of(again.source("t.one")), [3, 4],
		"collection/a mod's packs survive a restart")
	m.set_source("ghost", twice)
	_ok(m.source("ghost").is_empty(), "collection/nothing is recorded for a mod that is not installed")
	m.free()
	again.free()


func _names(rows: Variant) -> Array:
	var out: Array = []
	for row: Variant in (rows as Array):
		out.append(str((row as Dictionary)["name"]))
	return out


# ── consent/ ──────────────────────────────────────────────────────────────────

## A client whose player has agreed, with the answer kept in the scratch folder.
func _agree(client: ModioClient) -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	client.consent.state_path = _dir.path_join("consent.json")
	client.consent.grant("the terms")


func _group_consent() -> void:
	_remove_tree(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	var terms_reply := {"plaintext": " This game uses mod.io. ",
		"buttons": {"agree": {"text": "I Agree"}, "disagree": {"text": "No, Thanks"}},
		"links": {"website": {"text": "mod.io", "url": "https://mod.io", "required": false},
			"terms": {"text": "Terms of Use", "url": "https://mod.io/terms", "required": true},
			"privacy": {"text": "Privacy Policy", "url": "https://mod.io/privacy", "required": true},
			"odd": {"text": "Script", "url": "javascript:alert(1)", "required": true}}}
	var terms := ModioClient.parse_terms(terms_reply)
	_eq(str(terms["text"]), "This game uses mod.io.", "consent/the text is mod.io's, trimmed")
	_eq(str(terms["agree"]), "I Agree", "consent/the agree button is mod.io's wording")
	_eq(_link_texts(terms["links"]), ["Terms of Use", "Privacy Policy", "mod.io"],
		"consent/the required links come first, and only https ones are kept")
	_eq(str(ModioClient.parse_terms({})["agree"]), "I Agree", "consent/a reply with no buttons still has two")

	var web := ModServer.new()
	var empty := JSON.stringify({"data": [], "result_total": 0}).to_utf8_buffer()
	web.routes = {
		"/authenticate/terms": {"code": 200, "body": JSON.stringify(terms_reply).to_utf8_buffer()},
		"/games/14432/mods": {"code": 200, "body": JSON.stringify({"data": [_modio_mod(7, "A", 70)],
			"result_total": 1}).to_utf8_buffer()},
		"/games/14432/mods/7": {"code": 200, "body": JSON.stringify(_modio_mod(7, "A", 70)).to_utf8_buffer()},
		"/games/14432/tags": {"code": 200, "body": JSON.stringify({"data": [{"tags": ["Console"]}]}).to_utf8_buffer()},
		"/games/14432/collections": {"code": 200, "body": JSON.stringify({"data": [{"id": 3, "name": "Shelf"}],
			"result_total": 1}).to_utf8_buffer()},
		"/games/14432/collections/3/mods": {"code": 200, "body": JSON.stringify({"data": [
			_modio_mod(7, "A", 70), _modio_mod(8, "B", 80)], "result_total": 2}).to_utf8_buffer()},
		"/games/14432/collections/4/mods": {"code": 200, "body": empty},
	}
	if not web.start():
		_ok(false, "consent/a local server can listen")
		return
	var client := ModioClient.new()
	client.base_url = "http://127.0.0.1:%d" % web.port
	client.consent.state_path = _dir.path_join("consent.json")
	add_child(client)
	_ok(not client.consent.granted(), "consent/nobody has agreed on a fresh device")

	# Every request a page can make, before the player has agreed.
	var refused := {}
	var note := func(what: String, error: String) -> void: refused[what] = error
	client.list_mods("", "", 0, func(_ok_: bool, _m: Array[Dictionary], _t: int, error: String) -> void:
		note.call("mods", error))
	client.get_mod(7, func(_ok_: bool, _m: Dictionary, error: String) -> void: note.call("mod", error))
	client.list_tags(func(_ok_: bool, _t: PackedStringArray, error: String) -> void: note.call("tags", error))
	client.list_collections("", "", 0, func(_ok_: bool, _p: Array[Dictionary], _t: int, error: String) -> void:
		note.call("packs", error))
	client.list_collection_mods(3, func(_ok_: bool, _m: Array[Dictionary], _t: int, error: String) -> void:
		note.call("members", error))
	for what: String in ["mods", "mod", "tags", "packs", "members"]:
		_eq(str(refused.get(what, "never answered")), ModioClient.NEEDS_CONSENT,
			"consent/%s is refused before agreement" % what)
	for i in 10:
		await get_tree().process_frame
	_eq(web.log_text(), "", "consent/and none of them reached mod.io")

	# The terms are the one thing that may be asked.
	var got := {}
	client.get_terms(func(ok: bool, t: Dictionary, error: String) -> void:
		got.merge({"ok": ok, "terms": t, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)), "consent/the terms are fetched without agreement", str(got.get("error", "")))
	_eq(str((got.get("terms", {}) as Dictionary).get("text", "")), "This game uses mod.io.",
		"consent/and arrive as mod.io wrote them")
	_ok(web.log_text().contains("GET /authenticate/terms") and not web.log_text().contains("/games/"),
		"consent/the terms request is the only one sent", web.log_text())

	# Agreement opens the catalogue, and is to THAT text.
	client.consent.grant("This game uses mod.io.")
	got.clear()
	client.list_mods("", "", 0, func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "mods": mods, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)) and (got.get("mods", []) as Array).size() == 1,
		"consent/after agreeing the catalogue is read", str(got.get("error", "")))
	got.clear()
	client.list_collections("", "", 0, func(ok: bool, packs: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "packs": packs, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_eq(_names(got.get("packs", [])), ["Shelf"], "consent/and the packs")
	got.clear()
	client.list_collection_mods(3, func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "mods": mods, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_eq(_names(got.get("mods", [])), ["A", "B"], "consent/and a pack's members, in order")
	_eq(int(got.get("total", 0)), 2, "consent/with mod.io's count of them")
	got.clear()
	client.list_collection_mods(4, func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "mods": mods, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)) and (got.get("mods", [1]) as Array).is_empty(), "consent/an empty pack is an empty list")
	got.clear()
	client.list_tags(func(ok: bool, tags: PackedStringArray, error: String) -> void:
		got.merge({"ok": ok, "tags": tags, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_eq(got.get("tags"), PackedStringArray(["Console"]), "consent/and the tags")

	var remembered := ModioConsent.new()
	remembered.state_path = client.consent.state_path
	_ok(remembered.granted(), "consent/the answer survives a restart")
	_ok(not remembered.terms_changed("This game uses mod.io."), "consent/the same text is not a change")
	_ok(remembered.terms_changed("This game uses mod.io, and more."), "consent/new wording is")
	_ok(not remembered.terms_changed(""), "consent/a failed fetch is not")

	# Withdrawn, it is as if they had never agreed.
	client.consent.withdraw()
	_ok(not FileAccess.file_exists(client.consent.state_path), "consent/withdrawing deletes the answer")
	got.clear()
	client.list_mods("", "", 0, func(ok: bool, _m: Array[Dictionary], _t: int, error: String) -> void:
		got.merge({"ok": ok, "error": error}))
	_eq(str(got.get("error", "")), ModioClient.NEEDS_CONSENT, "consent/and the catalogue is refused again")
	var after := ModioConsent.new()
	after.state_path = client.consent.state_path
	_ok(not after.granted(), "consent/for the next launch too")
	client.queue_free()
	web.stop()


func _link_texts(links: Variant) -> Array:
	var out: Array = []
	for link: Variant in (links as Array):
		out.append(str((link as Dictionary)["text"]))
	return out


# ── bundle/ ───────────────────────────────────────────────────────────────────

## A .pck of `entries`, as bytes.
func _pck_bytes(entries: Dictionary) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(_dir)
	var tmp := _dir.path_join("fixture.pck")
	var sources := PackedStringArray()
	var pck := PCKPacker.new()
	pck.pck_start(tmp)
	var n := 0
	for member: String in entries:
		var src := _dir.path_join("pck_src_%d" % n)
		n += 1
		var f := FileAccess.open(src, FileAccess.WRITE)
		f.store_string(str(entries[member]))
		f.close()
		sources.append(src)
		pck.add_file("res://" + member, src)
	pck.flush()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	for src: String in sources:
		DirAccess.remove_absolute(src)
	return bytes


func _group_bundle() -> void:
	var here := OS.get_name()
	var ours := _zip_bytes(_pack("t.multi", "2.0.0", [here]))
	var theirs := _zip_bytes(_pack("t.multi", "2.0.0", ["Nowhere"]))

	# A plain pack is not a bundle, and is not rewritten on its way in.
	var m := _fresh()
	var plain := _stage(m, "dl-0.zip", _pack("t.plain", "1.0.0"))
	var info: Dictionary = m.vet(plain)
	_eq(str(info["path"]), plain, "bundle/a pack that is the download is left as it is")
	_eq(str(info["error"]), "", "bundle/and is accepted")
	DirAccess.remove_absolute(plain)

	# One upload, a build per platform: the one for this device is installed.
	var out: Dictionary = m.install(_stage(m, "dl-1.zip",
		{"quest.zip": theirs, "desktop.zip": ours, "README.txt": "pick one"}), {"modio_id": 7})
	_ok(bool(out["ok"]), "bundle/a build for this platform is installed out of a bundle", str(out["error"]))
	_eq(str(out["id"]), "t.multi", "bundle/under the id its own manifest gives")
	_ok(FileAccess.file_exists(_root.path_join("t.multi.zip")), "bundle/as <id>.zip")
	_eq(_md5(FileAccess.get_file_as_bytes(_root.path_join("t.multi.zip"))), _md5(ours),
		"bundle/and it is the inner pack byte for byte, not the bundle")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "bundle/the bundle and the other build are gone")
	_eq(int(m.source("t.multi").get("modio_id", 0)), 7, "bundle/its source is kept")

	# A .pck cannot be uploaded bare, so it travels inside a zip.
	out = m.install(_stage(m, "dl-2.zip", {"wrapped.pck": _pck_bytes(_pack("t.pck", "1.0.0"))}))
	_ok(bool(out["ok"]), "bundle/a wrapped .pck is installed", str(out["error"]))
	_ok(FileAccess.file_exists(_root.path_join("t.pck.pck")), "bundle/as a .pck")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "bundle/with nothing left behind")
	m.free()

	# Nothing in it runs here: refused, with each build's reason.
	m = _fresh()
	out = m.install(_stage(m, "dl-3.zip", {"quest.zip": theirs}))
	_ok(not bool(out["ok"]) and str(out["error"]).contains("quest.zip")
		and str(out["error"]).contains("no pack that runs here"),
		"bundle/a bundle with no build for this platform is refused, and says which it held", str(out["error"]))
	_eq(_listing(_root), PackedStringArray(), "bundle/nothing reaches the mods root")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "bundle/and nothing is left in incoming")

	# Two that both run here: no rule the author could see would pick one.
	out = m.install(_stage(m, "dl-4.zip", {"a.zip": ours,
		"b.zip": _zip_bytes(_pack("t.other", "1.0.0"))}))
	_ok(not bool(out["ok"]) and str(out["error"]).contains("2 packs"),
		"bundle/two builds for one platform is refused rather than guessed", str(out["error"]))
	_eq(_listing(_root) + _listing(m.incoming_dir()), PackedStringArray(), "bundle/leaving nothing anywhere")

	# The pack inside is held to everything a bare one is.
	var loaded := _pack("t.rom", "1.0.0")
	loaded["mods/t.rom/Game.sfc"] = "not really"
	out = m.install(_stage(m, "dl-5.zip", {"desktop.zip": _zip_bytes(loaded)}))
	_ok(not bool(out["ok"]) and str(out["error"]).contains("Game.sfc"),
		"bundle/a game inside a bundled pack is still refused", str(out["error"]))
	_eq(_listing(_root) + _listing(m.incoming_dir()), PackedStringArray(), "bundle/and the build is deleted too")
	var escaped := _pack("t.esc", "1.0.0")
	escaped["Scripts/evil.gd"] = "extends Node"
	out = m.install(_stage(m, "dl-6.zip", {"desktop.zip": _zip_bytes(escaped)}))
	_ok(not bool(out["ok"]), "bundle/so is a namespace escape inside one")

	# A zip with neither a manifest nor a pack is just a bad pack.
	out = m.install(_stage(m, "dl-7.zip", {"notes.txt": "hello", "sub/inner.zip": ours}))
	_ok(not bool(out["ok"]) and str(out["error"]).contains("mod.json"),
		"bundle/a pack deeper than the top level is not gone looking for", str(out["error"]))
	m.free()


# ── review/ ───────────────────────────────────────────────────────────────────

func _group_review() -> void:
	var m := _fresh()
	var reviews := ModReviews.new()
	reviews.manager = m
	var changes := [0]
	reviews.changed.connect(func() -> void: changes[0] += 1)
	var key := ModReviews.job_key(7)
	_eq(key, "modio-7", "review/the key is the downloader's")

	# Fetched and vetted is NOT installed.
	var staged := _stage(m, "modio-7.zip", _pack("t.rev", "1.0.0"))
	var out: Dictionary = reviews.stage(staged, {"modio_id": 7, "file_id": 70})
	_ok(bool(out["ok"]) and bool(out.get("review", false)), "review/a good download is parked", str(out["error"]))
	_eq(str(out["id"]), "t.rev", "review/and says which mod it is")
	_ok(reviews.has(key), "review/it is waiting under its key")
	_eq(_listing(_root), PackedStringArray(), "review/nothing is in the mods root yet")
	_ok(m.mod("t.rev") == null, "review/and the loader knows nothing of it")
	_eq((reviews.parked(key)["manifest"] as ModManifest).version, "1.0.0", "review/its manifest is there to show")
	_eq(changes[0], 1, "review/parking is announced")

	# Yes: installed, and still disabled.
	out = reviews.finish(key, {"modio_id": 7, "file_id": 70, "individual": true}, false)
	_ok(bool(out["ok"]), "review/yes installs it", str(out["error"]))
	_ok(FileAccess.file_exists(_root.path_join("t.rev.zip")), "review/into the mods root")
	_eq(m.mod("t.rev").status, ModRecord.Status.DISABLED, "review/disabled")
	_ok(not m.is_enabled("t.rev"), "review/because the switch was left off")
	_ok(not bool(out["restart"]), "review/so no restart is asked for")
	_ok(not reviews.has(key), "review/and it is no longer waiting")
	_ok(not bool(reviews.finish(key, {}, false)["ok"]), "review/a second yes has nothing to install")

	# Yes, with the switch on.
	reviews.stage(_stage(m, "modio-8.zip", _pack("t.on", "1.0.0")), {"modio_id": 8})
	out = reviews.finish(ModReviews.job_key(8), {"modio_id": 8}, true)
	_ok(bool(out["ok"]) and m.is_enabled("t.on"), "review/the switch enables it for the next launch")
	_ok(bool(out["restart"]), "review/and that needs a restart")

	# No: the file goes.
	staged = _stage(m, "modio-9.zip", _pack("t.no", "1.0.0"))
	reviews.stage(staged, {"modio_id": 9})
	reviews.discard(ModReviews.job_key(9))
	_ok(not FileAccess.file_exists(staged) and not reviews.has(ModReviews.job_key(9)),
		"review/no deletes the download")
	_ok(m.mod("t.no") == null, "review/and installs nothing")

	# A file the loader refuses never waits.
	var bad := _pack("t.bad", "1.0.0")
	bad["Scripts/evil.gd"] = "extends Node"
	staged = _stage(m, "modio-10.zip", bad)
	out = reviews.stage(staged, {"modio_id": 10})
	_ok(not bool(out["ok"]) and not str(out["error"]).is_empty(), "review/a refused pack is not parked", str(out["error"]))
	_ok(not reviews.has(ModReviews.job_key(10)) and not FileAccess.file_exists(staged),
		"review/and is deleted")

	# A bundle is parked as the build that was picked out of it.
	staged = _stage(m, "modio-11.zip", {"desktop.zip": _zip_bytes(_pack("t.bun", "3.0.0", [OS.get_name()])),
		"quest.zip": _zip_bytes(_pack("t.bun", "3.0.0", ["Nowhere"]))})
	out = reviews.stage(staged, {"modio_id": 11})
	_ok(bool(out["ok"]), "review/a bundle is parked", str(out["error"]))
	var inner := str(reviews.parked(ModReviews.job_key(11)).get("staged", ""))
	_ok(inner != staged and FileAccess.file_exists(inner) and not FileAccess.file_exists(staged),
		"review/as its inner build, with the bundle gone")
	_ok(bool(reviews.finish(ModReviews.job_key(11), {"modio_id": 11}, false)["ok"])
		and FileAccess.file_exists(_root.path_join("t.bun.zip")), "review/which is what yes installs")

	# The same mod fetched twice waits once.
	var first := _stage(m, "first.zip", _pack("t.twice", "1.0.0"))
	reviews.stage(first, {"modio_id": 12})
	reviews.stage(_stage(m, "second.zip", _pack("t.twice", "1.1.0")), {"modio_id": 12})
	_ok(not FileAccess.file_exists(first), "review/a second download of a mod replaces the first's file")
	_eq((reviews.parked(ModReviews.job_key(12))["manifest"] as ModManifest).version, "1.1.0",
		"review/and it is the newer one that waits")
	reviews.discard_all()
	_eq(reviews.keys().size(), 0, "review/everything waiting can be thrown away at once")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "review/leaving incoming empty")
	m.free()

	# The game's own: an autoload, so the hook outlives the menu.
	_ok(Modio.client != null and Modio.client.get_parent() == Modio, "review/the catalogue client belongs to the Modio autoload")
	_ok(Modio.downloader != null and Modio.downloader.get_parent() == Modio, "review/so does the downloader")
	_ok(Modio.downloader.install_hook.is_valid()
		and Modio.downloader.install_hook.get_object() == Modio.reviews
		and Modio.downloader.install_hook.get_method() == &"stage",
		"review/a finished download goes to the review, not straight to the loader")


# ── space/ ────────────────────────────────────────────────────────────────────

func _group_space() -> void:
	var mb := 1024 * 1024
	_eq(ModDownloader.space_problem(40 * mb, 200 * mb), "", "space/a file that fits is fine")
	_ok(ModDownloader.space_problem(40 * mb, 50 * mb).contains("Not enough space"),
		"space/twice the file plus a margin is what is asked for")
	_eq(ModDownloader.space_problem(40 * mb, 80 * mb + ModDownloader.SPACE_MARGIN), "",
		"space/exactly enough is enough")
	_ok(not ModDownloader.space_problem(40 * mb, 80 * mb + ModDownloader.SPACE_MARGIN - 1).is_empty(),
		"space/one byte short is not")
	_eq(ModDownloader.space_problem(40 * mb, 50 * mb + ModDownloader.SPACE_MARGIN, 30 * mb), "",
		"space/what is already downloaded is not asked for again")
	_eq(ModDownloader.space_problem(0, 1), "", "space/an unstated size is not refused")
	_eq(ModDownloader.space_problem(40 * mb, 0), "", "space/a volume that reports nothing is unknown, not full")
	var said := ModDownloader.space_problem(40 * mb, 50 * mb)
	_ok(said.contains("96") and said.contains("50"), "space/the sentence gives both figures", said)

	# Wired in: refused before a single request is made.
	var m := _fresh()
	var good := _zip_bytes(_pack("t.big", "1.0.0"))
	var server := ModServer.new()
	server.routes = {"/dl": {"code": 200, "body": good}}
	if not server.start():
		_ok(false, "space/a local server can listen")
		return
	var dl := ModDownloader.new()
	dl.staging_dir_override = m.incoming_dir()
	dl.install_hook = Callable(m, "install")
	dl.free_space_override = 50 * mb
	add_child(dl)
	var seen := {}
	dl.job_finished.connect(func(_k: String, ok: bool, error: String, _r: Dictionary) -> void:
		seen.merge({"ok": ok, "error": error}))
	dl.enqueue("modio-7", "Big", "http://127.0.0.1:%d/dl" % server.port, 40 * mb, "", {"modio_id": 7})
	await _until(func() -> bool: return not seen.is_empty())
	_ok(not bool(seen.get("ok", true)) and str(seen.get("error", "")).contains("Not enough space"),
		"space/a download that will not fit fails, and says so", str(seen.get("error", "")))
	_eq(server.log_text(), "", "space/without asking the server for a byte")
	_eq(_listing(_root), PackedStringArray(), "space/and nothing is installed")

	# With room, the same download goes through.
	seen.clear()
	dl.free_space_override = 500 * mb
	dl.enqueue("modio-7", "Big", "http://127.0.0.1:%d/dl" % server.port, good.size(), _md5(good), {"modio_id": 7})
	await _until(func() -> bool: return not seen.is_empty())
	_ok(bool(seen.get("ok", false)), "space/with room it is fetched and installed", str(seen.get("error", "")))
	dl.queue_free()
	await get_tree().process_frame
	server.stop()
	m.free()


# ── thumbnail/ ────────────────────────────────────────────────────────────────

func _png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.3, 0.5))
	return img.save_png_to_buffer()


func _group_thumbnail() -> void:
	_eq(ModManifest.thumbnail_error(_png(1280, 720)), "", "thumbnail/1280x720 is accepted")
	_eq(ModManifest.thumbnail_error(_png(512, 288)), "", "thumbnail/mod.io's minimum is accepted")
	_ok(not ModManifest.thumbnail_error(PackedByteArray()).is_empty(), "thumbnail/none at all is refused")
	_ok(ModManifest.thumbnail_error(_png(320, 180)).contains("at least"),
		"thumbnail/too small is refused, and says the floor")
	_ok(ModManifest.thumbnail_error(_png(720, 720)).contains("16:9"),
		"thumbnail/a square is refused, and says the shape")
	_ok(ModManifest.thumbnail_error(_png(1024, 768)).contains("16:9"), "thumbnail/4:3 is refused")
	_ok(not ModManifest.thumbnail_error("not a png at all".to_utf8_buffer()).is_empty(),
		"thumbnail/junk bytes are refused")

	# The loader is NOT the packer: a pack with no picture still installs, and one
	# with a picture has it read without mounting.
	var m := _fresh()
	var bare: Dictionary = m.install(_stage(m, "dl-1.zip", _pack("t.bare", "1.0.0")))
	_ok(bool(bare["ok"]), "thumbnail/a pack without one still installs")
	_ok(m.mod("t.bare").thumbnail == null, "thumbnail/and simply has no picture")
	var path: String = m.incoming_dir().path_join("dl-2.zip")
	var z := ZIPPacker.new()
	z.open(path)
	var entries := _pack("t.pic", "1.0.0")
	for member: String in entries:
		z.start_file(member)
		# Bytes as they are, so a bundle can carry packs; anything else as text.
		var value: Variant = entries[member]
		z.write_file(value if value is PackedByteArray else str(value).to_utf8_buffer())
		z.close_file()
	z.start_file("mods/t.pic/thumbnail.png")
	z.write_file(_png(640, 360))
	z.close_file()
	z.close()
	var pic: Dictionary = m.install(path)
	_ok(bool(pic["ok"]), "thumbnail/a pack with one installs", str(pic["error"]))
	var tex: Texture2D = m.mod("t.pic").thumbnail
	_ok(tex != null and tex.get_width() == 640, "thumbnail/its picture is read at install, unmounted")
	m.free()


# ── download/ ─────────────────────────────────────────────────────────────────
#
# A real socket on loopback, the real downloader and the real loader vetting
# what arrives. Nothing here knows mod.io: the server is told what to answer.

func _group_download() -> void:
	var good := _zip_bytes(_pack("t.net", "1.0.0"))
	var md5 := _md5(good)

	# The catalogue over HTTP, through the client's own request path.
	var web := ModServer.new()
	var listing := JSON.stringify({"data": [_modio_mod(7, "A", 70), _modio_mod(8, "B", 0)],
		"result_total": 31})
	web.routes = {"/games/14432/mods": {"code": 200, "body": listing.to_utf8_buffer()},
		"/games/14432/mods/7": {"code": 200, "body": JSON.stringify(_modio_mod(7, "A", 71)).to_utf8_buffer()},
		"/games/14432/mods/9": {"code": 429, "body": PackedByteArray(), "headers": ["Retry-After: 12"]}}
	if not web.start():
		_ok(false, "download/a local server can listen")
		return
	var client := ModioClient.new()
	client.base_url = "http://127.0.0.1:%d" % web.port
	_agree(client)
	add_child(client)
	# A Dictionary, mutated: a lambda captures a local by value, so assigning to
	# one inside it changes nothing out here.
	var got := {}
	client.list_mods("", "-date_live", 0, func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "mods": mods, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)), "download/the catalogue is read over http", str(got.get("error", "")))
	_eq((got.get("mods", []) as Array).size(), 2, "download/every mod on the page arrives")
	_eq(int(got.get("total", 0)), 31, "download/the total is the server's, not the page's")
	got.clear()
	client.get_mod(7, func(ok: bool, mod: Dictionary, error: String) -> void:
		got.merge({"ok": ok, "mod": mod, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_eq(int((got.get("mod", {}) as Dictionary).get("file_id", 0)), 71, "download/one mod is re-read by id")
	got.clear()
	client.get_mod(9, func(ok: bool, mod: Dictionary, error: String) -> void:
		got.merge({"ok": ok, "mod": mod, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(not bool(got.get("ok", true)) and str(got.get("error", "")).contains("12 s"),
		"download/a rate limit reaches the player with its wait", str(got.get("error", "")))
	client.queue_free()
	web.stop()

	# 1. A redirect to another address, the checksum, and the loader's vetting.
	var m := _fresh()
	var out := await _run_download(m, {
		"/v1/dl/70": {"code": 302, "body": PackedByteArray(), "headers": ["Location: /cdn/signed/pack.zip?sig=abc"]},
		"/cdn/signed/pack.zip": {"code": 200, "body": good},
	}, "/v1/dl/70", good.size(), md5)
	_ok(bool(out["ok"]), "download/a redirected download installs", str(out["error"]))
	_ok(FileAccess.file_exists(_root.path_join("t.net.zip")), "download/the pack is in the mods root")
	_eq(_md5(FileAccess.get_file_as_bytes(_root.path_join("t.net.zip"))), md5,
		"download/and is byte-for-byte what was served")
	_eq(int(m.source("t.net").get("modio_id", 0)), 7, "download/its mod.io id is kept")
	_eq(m.mod("t.net").status, ModRecord.Status.DISABLED, "download/it lands disabled")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "download/nothing is left in incoming")
	_ok((out["requests"] as String).contains("GET /cdn/signed/pack.zip?sig=abc"),
		"download/the redirect's query string is kept", str(out["requests"]))
	_ok(int(out["progress"]) > 0, "download/progress was reported")
	m.free()

	# 2. A pack the loader refuses. Fetched whole, checksum right, still not installed.
	m = _fresh()
	var escaped := _pack("t.bad", "1.0.0")
	escaped["Scripts/evil.gd"] = "extends Node"
	var bad := _zip_bytes(escaped)
	out = await _run_download(m, {"/dl": {"code": 200, "body": bad}}, "/dl", bad.size(), _md5(bad))
	_ok(not bool(out["ok"]), "download/a pack the loader refuses is not installed")
	_ok(not str(out["error"]).is_empty(), "download/the loader's reason is reported", str(out["error"]))
	_eq(_listing(_root), PackedStringArray(), "download/the mods root is untouched")
	_eq(_listing(m.incoming_dir()), PackedStringArray(), "download/the refused file is deleted")
	m.free()

	# 3. The wrong bytes for the checksum mod.io stated. Three attempts, then no.
	m = _fresh()
	out = await _run_download(m, {"/dl": {"code": 200, "body": good}}, "/dl", good.size(),
		"00000000000000000000000000000000")
	_ok(not bool(out["ok"]), "download/a checksum mismatch is not installed")
	_eq(int(out["retries"]), ModDownloader.MAX_RETRIES - 1, "download/it is retried before giving up")
	_eq(_listing(_root), PackedStringArray(), "download/nothing reaches the mods root")
	m.free()

	# 4. Gone from the server: no retry, and said as that.
	m = _fresh()
	out = await _run_download(m, {}, "/missing", 0, "")
	_ok(not bool(out["ok"]), "download/a 404 fails")
	_eq(int(out["retries"]), 0, "download/a 404 is not retried")
	_ok(str(out["error"]).contains("no longer"), "download/a 404 says the file is gone", str(out["error"]))
	m.free()

	# 5. A partial file from an earlier attempt, and a server that resumes.
	m = _fresh()
	var half := good.size() / 2
	_write_bytes(m.incoming_dir().path_join("modio-7.zip.part"), good.slice(0, half))
	out = await _run_download(m, {"/dl": {"code": 200, "body": good, "ranged": true}},
		"/dl", good.size(), md5)
	_ok(bool(out["ok"]), "download/a partial download is resumed", str(out["error"]))
	_ok((out["requests"] as String).contains("Range: bytes=%d-" % half),
		"download/the resume asks only for the rest", str(out["requests"]))
	_eq(int(out["retries"]), 0, "download/a clean resume is one attempt")
	m.free()

	# 6. The same partial, and a server that ignores Range and sends it all. The
	#    whole body appended to the half is a corrupt file of a plausible length.
	m = _fresh()
	_write_bytes(m.incoming_dir().path_join("modio-7.zip.part"), good.slice(0, half))
	#    No checksum on this leg, so only the status check can catch it.
	out = await _run_download(m, {"/dl": {"code": 200, "body": good}}, "/dl", good.size(), "")
	_ok(bool(out["ok"]), "download/a server that ignores Range still ends in a good file",
		str(out["error"]))
	_eq(int(out["retries"]), 1, "download/by starting again, once")
	_eq(_md5(FileAccess.get_file_as_bytes(_root.path_join("t.net.zip"))), md5,
		"download/the installed file is the whole pack, not half plus all of it")
	m.free()


## Serve `routes`, download `path` through a real ModDownloader into manager
## `m`, and report what happened: {ok, error, retries, progress, requests}.
func _run_download(m: Node, routes: Dictionary, path: String, size: int, md5: String) -> Dictionary:
	var server := ModServer.new()
	server.routes = routes
	if not server.start():
		return {"ok": false, "error": "could not listen", "retries": 0, "progress": 0, "requests": ""}
	var dl := ModDownloader.new()
	dl.staging_dir_override = m.incoming_dir()
	dl.install_hook = Callable(m, "install")
	dl.backoff_ms = 5
	add_child(dl)
	var seen := {"done": false, "ok": false, "error": "", "retries": 0, "progress": 0}
	dl.job_retrying.connect(func(_k: String, _a: int, _n: int, _why: String) -> void:
		seen["retries"] = int(seen["retries"]) + 1)
	dl.job_progress.connect(func(_k: String, received: int, _t: int) -> void:
		seen["progress"] = received)
	dl.job_finished.connect(func(_k: String, ok: bool, error: String, _r: Dictionary) -> void:
		seen["done"] = true
		seen["ok"] = ok
		seen["error"] = error)
	dl.enqueue("modio-7", "Test", "http://127.0.0.1:%d%s" % [server.port, path], size, md5,
		{"modio_id": 7, "file_id": 70})
	await _until(func() -> bool: return bool(seen["done"]), 30.0)
	if not bool(seen["done"]):
		seen["error"] = "the download never finished"
	dl.queue_free()
	await get_tree().process_frame
	server.stop()
	seen["requests"] = server.log_text()
	return seen


## Wait, a frame at a time, for `done` to come true.
func _until(done: Callable, cap_sec: float = 15.0) -> void:
	var deadline := Time.get_ticks_msec() + int(cap_sec * 1000.0)
	while not done.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _zip_bytes(entries: Dictionary) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(_dir)
	var tmp := _dir.path_join("fixture.zip")
	_write_zip(tmp, entries)
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return bytes


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## A loopback HTTP server that answers by path, one request per connection, for
## as many connections as arrive -- a redirect is two, a retry is another.
##
## routes: path (without its query) -> {code, body, headers?, ranged?}. A route
## marked `ranged` honours `Range: bytes=N-` with a 206 of the remainder; one
## that is not sends the whole body whatever was asked, which is the server the
## downloader has to survive. Anything unrouted is a 404.
class ModServer extends RefCounted:

	var port := 0
	var routes: Dictionary = {}
	var _log := PackedStringArray()
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false
	var _mutex := Mutex.new()

	func start() -> bool:
		for p in range(49600, 49660):
			if _server.listen(p, "127.0.0.1") == OK:
				port = p
				break
		if port == 0:
			return false
		_thread.start(_serve)
		return true

	func stop() -> void:
		_stop = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_server.stop()

	## Every request line and Range header received, in order.
	func log_text() -> String:
		_mutex.lock()
		var text := "\n".join(_log)
		_mutex.unlock()
		return text

	func _serve() -> void:
		while not _stop:
			if not _server.is_connection_available():
				OS.delay_msec(2)
				continue
			_answer(_server.take_connection())

	func _answer(peer: StreamPeerTCP) -> void:
		var raw := PackedByteArray()
		var give_up := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < give_up and not _stop:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				if peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
					return
				OS.delay_msec(2)
				continue
			var n := peer.get_available_bytes()
			if n > 0:
				raw.append_array(peer.get_data(n)[1])
				if raw.get_string_from_utf8().contains("\r\n\r\n"):
					break
			else:
				OS.delay_msec(2)
		var lines := raw.get_string_from_utf8().split("\r\n")
		if lines.is_empty() or lines[0].is_empty():
			peer.disconnect_from_host()
			return
		var target := lines[0].get_slice(" ", 1)
		var start := 0
		_mutex.lock()
		_log.append(lines[0].get_slice(" HTTP", 0))
		for line: String in lines:
			if line.to_lower().begins_with("range:"):
				_log.append(line)
				start = int(line.get_slice("=", 1).get_slice("-", 0))
		_mutex.unlock()

		var route: Dictionary = routes.get(target.get_slice("?", 0), {})
		var code := int(route.get("code", 404))
		var body: PackedByteArray = route.get("body", PackedByteArray())
		if bool(route.get("ranged", false)) and start > 0:
			code = 206
			body = body.slice(start)
		var head := "HTTP/1.1 %d X\r\nContent-Length: %d\r\nConnection: close\r\n" % [code, body.size()]
		for extra: String in (route.get("headers", []) as Array):
			head += extra + "\r\n"
		peer.put_data((head + "\r\n").to_utf8_buffer())
		if body.size() > 0:
			peer.put_data(body)
		# Held a moment so the client reads the body before the socket closes.
		var linger := Time.get_ticks_msec() + 150
		while Time.get_ticks_msec() < linger and not _stop:
			peer.poll()
			OS.delay_msec(5)
		peer.disconnect_from_host()


# ── fixtures ──────────────────────────────────────────────────────────────────

## A manager over the scratch root. `wipe` starts from an empty root and no
## state; false stands in for the next launch.
func _fresh(wipe: bool = true) -> Node:
	if wipe:
		_remove_tree(_dir)
	DirAccess.make_dir_recursive_absolute(_root)
	var m: Node = MANAGER.new()
	m.mods_root_override = _root
	m.state_path_override = _state
	DirAccess.make_dir_recursive_absolute(m.incoming_dir())
	return m


func _pack(id: String, version: String, platforms: Array = []) -> Dictionary:
	var manifest := {"id": id, "api_version": 1, "version": version, "name": id,
		"entry": "res://mods/%s/m.gd" % id}
	if not platforms.is_empty():
		manifest["platforms"] = platforms
	return {
		"mods/%s/mod.json" % id: JSON.stringify(manifest),
		"mods/%s/m.gd" % id: "extends RetroMod",
	}


func _stage(m: Node, file_name: String, entries: Dictionary) -> String:
	return _write_zip(m.incoming_dir().path_join(file_name), entries)


func _write_zip(path: String, entries: Dictionary) -> String:
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return path
	for member: String in entries:
		z.start_file(member)
		# Bytes as they are, so a bundle can carry packs; anything else as text.
		var value: Variant = entries[member]
		z.write_file(value if value is PackedByteArray else str(value).to_utf8_buffer())
		z.close_file()
	z.close()
	return path


## File names directly in `path`, sorted.
func _listing(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir != null:
		out = dir.get_files()
		out.sort()
	return out


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

func _ok(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[test] PASS  %s" % name)
	else:
		_fail += 1
		print("[test] FAIL  %s%s" % [name,
			"  — " + detail if not detail.is_empty() else ""])


func _eq(got: Variant, want: Variant, name: String) -> void:
	_ok(got == want, name, "got %s, want %s" % [str(got), str(want)])
