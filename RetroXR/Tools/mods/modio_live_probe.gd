## modio_live_probe — the mod browser's own code against the REAL mod.io.
##
##   godot --headless --path RetroXR res://Tools/mods/modio_live_probe.tscn
##   godot --headless --path RetroXR res://Tools/mods/modio_live_probe.tscn -- --name="PlayStation 2"
##
## A probe, not a suite: it needs the network and something published on RetroXR's
## mod.io page. It asks for the terms, the catalogue, the tags and the packs with
## the real ModioClient, then fetches the first mod (or the one --name matches)
## with the real ModDownloader, through the redirect to mod.io's CDN, and takes
## it through the review into a loader.
##
## Nothing of the player's is touched. The loader is a scratch ModManager rooted
## in user://modio_live_probe/, the agreement to mod.io's terms is kept there too,
## and the folder is removed at the end. Running this agrees to nothing on the
## player's behalf: their own answer is the Modio autoload's and is not used.
extends Node

const MANAGER := preload("res://Scripts/Mods/mod_manager.gd")
const OUT := "user://modio_live_probe"

var _failures: Array[String] = []


func _ok(cond: bool, msg: String) -> void:
	print("[live] %s  %s" % ["PASS" if cond else "FAIL", msg])
	if not cond:
		_failures.append(msg)


func _until(done: Callable, cap_sec: float = 30.0) -> void:
	var deadline := Time.get_ticks_msec() + int(cap_sec * 1000.0)
	while not done.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[live] TIMEOUT"); get_tree().quit(1))
	var wanted := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			wanted = a.substr(7).to_lower()
	var dir := ProjectSettings.globalize_path(OUT)
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("mods"))

	var client := ModioClient.new()
	client.consent.state_path = OUT.path_join("consent.json")
	add_child(client)
	var got := {}

	# Before agreement, only the terms.
	client.list_mods("", "", 0, func(ok: bool, _m: Array[Dictionary], _t: int, error: String) -> void:
		got.merge({"ok": ok, "error": error}))
	_ok(str(got.get("error", "")) == ModioClient.NEEDS_CONSENT, "the catalogue is refused before agreement")
	got.clear()
	client.get_terms(func(ok: bool, terms: Dictionary, error: String) -> void:
		got.merge({"ok": ok, "terms": terms, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	var terms: Dictionary = got.get("terms", {})
	_ok(bool(got.get("ok", false)), "mod.io's terms arrive %s" % str(got.get("error", "")))
	if terms.is_empty():
		_finish(dir)
		return
	print("[live] terms: %d characters, buttons '%s' / '%s', %d links" % [
		str(terms["text"]).length(), terms["agree"], terms["disagree"], (terms["links"] as Array).size()])
	client.consent.grant(str(terms["text"]))

	got.clear()
	client.list_tags(func(ok: bool, tags: PackedStringArray, error: String) -> void:
		got.merge({"ok": ok, "tags": tags, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)), "the tags arrive: %s" % str(got.get("tags", [])))

	got.clear()
	client.list_collections("", "", 0, func(ok: bool, packs: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "packs": packs, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	_ok(bool(got.get("ok", false)), "the packs arrive: %d" % int(got.get("total", -1)))
	for pack: Dictionary in got.get("packs", []):
		print("[live] pack %d '%s' by %s, %s" % [pack["id"], pack["name"], pack["author"],
			MenuStyle.human_bytes(int(pack["file_size"]))])

	got.clear()
	client.list_mods("", "-date_live", 0, func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
		got.merge({"ok": ok, "mods": mods, "total": total, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	var mods: Array = got.get("mods", [])
	_ok(bool(got.get("ok", false)), "the catalogue arrives: %d mod(s) %s" % [int(got.get("total", -1)),
		str(got.get("error", ""))])
	var pick: Dictionary = {}
	for mod: Dictionary in mods:
		print("[live] mod %d '%s' by %s, file %d %s, scan %d/%d, tags %s" % [mod["id"], mod["name"],
			mod["author"], mod["file_id"], MenuStyle.human_bytes(int(mod["file_size"])),
			mod["virus_status"], mod["virus_positive"], str(mod["tags"])])
		if pick.is_empty() and (wanted.is_empty() or str(mod["name"]).to_lower().contains(wanted)):
			pick = mod
	if pick.is_empty():
		_ok(false, "there is a mod to fetch")
		_finish(dir)
		return

	# Asked again at the press, as the page does.
	got.clear()
	client.get_mod(int(pick["id"]), func(ok: bool, mod: Dictionary, error: String) -> void:
		got.merge({"ok": ok, "mod": mod, "error": error}))
	await _until(func() -> bool: return not got.is_empty())
	var fresh: Dictionary = got.get("mod", {})
	_ok(bool(got.get("ok", false)) and int(fresh.get("file_id", 0)) > 0, "the mod is re-read by id")
	_ok(ModioClient.scan_problem(fresh).is_empty(), "mod.io's scan of its file is clean (%s)"
		% ModioClient.scan_problem(fresh))
	_ok(SpawnMenuModsView.browse_state(fresh) != "unscanned", "so the page would offer it")

	# The real transfer, into a scratch loader, through the review.
	var m: Node = MANAGER.new()
	m.mods_root_override = dir.path_join("mods")
	m.state_path_override = dir.path_join("mods.json")
	DirAccess.make_dir_recursive_absolute(m.incoming_dir())
	var reviews := ModReviews.new()
	reviews.manager = m
	var dl := ModDownloader.new()
	dl.staging_dir_override = m.incoming_dir()
	dl.install_hook = reviews.stage
	add_child(dl)
	var seen := {"done": false, "ok": false, "error": "", "retries": 0, "bytes": 0}
	dl.job_retrying.connect(func(_k: String, _a: int, _n: int, why: String) -> void:
		seen["retries"] = int(seen["retries"]) + 1
		print("[live] retry: ", why))
	dl.job_progress.connect(func(_k: String, received: int, _t: int) -> void: seen["bytes"] = received)
	dl.job_finished.connect(func(_k: String, ok: bool, error: String, result: Dictionary) -> void:
		seen.merge({"done": true, "ok": ok, "error": error, "result": result}, true))
	var key := ModReviews.job_key(int(fresh["id"]))
	var started := Time.get_ticks_msec()
	dl.enqueue(key, str(fresh["name"]), str(fresh["download_url"]), int(fresh["file_size"]),
		str(fresh["file_md5"]), {"modio_id": int(fresh["id"]), "file_id": int(fresh["file_id"]),
			"profile_url": str(fresh["profile_url"])})
	await _until(func() -> bool: return bool(seen["done"]), 120.0)
	_ok(bool(seen["ok"]), "the file downloads from mod.io's CDN and passes mod.io's MD5 and the loader (%s)"
		% str(seen["error"]))
	print("[live] %s in %.1f s, %d retries" % [MenuStyle.human_bytes(int(seen["bytes"])),
		float(Time.get_ticks_msec() - started) / 1000.0, int(seen["retries"])])
	_ok(reviews.has(key), "and waits for the review instead of being installed")
	if reviews.has(key):
		var manifest: ModManifest = reviews.parked(key)["manifest"]
		print("[live] it is %s %s by %s; replaces %s" % [manifest.id, manifest.version,
			manifest.author, str(manifest.shadowing_claims())])
		_ok(reviews.parked(key)["thumbnail"] != null, "its own thumbnail is read out of the pack")
		var out: Dictionary = reviews.finish(key, ModCollectionPlan.source_after_single({},
			int(fresh["id"]), int(fresh["file_id"]), str(fresh["profile_url"])), false)
		_ok(bool(out.get("ok", false)), "yes installs it (%s)" % str(out.get("error", "")))
		var rec: ModRecord = m.mod(manifest.id)
		_ok(rec != null and rec.status == ModRecord.Status.DISABLED, "disabled, as %s" % (
			rec.path.get_file() if rec != null else "nothing"))
		if rec != null:
			_ok(FileAccess.get_md5(rec.path) == str(fresh["file_md5"]),
				"byte for byte what mod.io holds (%s)" % MenuStyle.human_bytes(rec.size))
			_ok(SpawnMenuModsView.browse_state(fresh) in ["", "installed", "update"],
				"the scratch loader's mod is not the game's (the tile reads '%s')"
				% SpawnMenuModsView.browse_state(fresh))
	dl.queue_free()
	await get_tree().process_frame
	m.free()
	_finish(dir)


func _finish(dir: String) -> void:
	_remove_tree(dir)
	print("[live] %s (%d failed)" % ["ALL CHECKS PASSED" if _failures.is_empty() else "FAILURES",
		_failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub: String in d.get_directories():
		_remove_tree(path.path_join(sub))
	for file: String in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)
