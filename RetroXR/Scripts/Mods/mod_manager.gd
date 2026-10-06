## Mods — the autoload that finds, vets and mounts mod packs.
##
## Runs before AppPrefs and SceneManager, because every registration a mod makes
## has to be in place before a room is built or a menu is populated.
##
## The shape of a boot:
##
##   1. list <mods root>/*.zip and *.pck
##   2. open each WITHOUT mounting it and read its file list
##   3. read mod.json (and thumbnail.png) out of it
##   4. check the inventory against the manifest's namespace and claims
##   5. skip anything not explicitly enabled in user://mods.json
##   6. mount what is left, in priority order, and run its entry script
##
## Steps 1-5 touch nothing and are reversible, which is what makes it safe to
## inspect every mod on disk at every boot while mounting only the enabled ones.
## Step 6 is not: ProjectSettings.load_resource_pack cannot be undone, so
## enabling or disabling a mod takes effect on the NEXT launch and the Mods page
## says so rather than pretending otherwise.
##
## One bad mod never blocks a boot. Every failure is recorded against that mod
## and the run continues, because a mod that silently vanishes is the worst
## failure this system has -- the page exists mostly to explain these.
extends Node

const STATE_PATH := "user://mods.json"
const STATE_OWNER := "ModManager"

## What happened to one mod this boot. Defined on ModRecord, which carries it;
## aliased here because the Mods page reads it as Mods.Status.
const Status := ModRecord.Status

## Emitted once discovery and loading have finished, so the Mods page can build.
signal mods_ready()
## A mod was installed, updated or removed since boot, so a list of them is stale.
signal mods_changed()

## Where a download waits, inside the mods root: on the same volume, so the move
## into place is a rename, and one level down, which scan_mods never reads -- a
## half-fetched or unvetted pack is never mistaken for an installed one.
const INCOMING_DIR := ".incoming"

## id -> ModRecord.
var _mods: Dictionary = {}
## Containers whose id could not be read at all, keyed by file path.
var _unreadable: Array[Dictionary] = []
## ids seen more than once across containers.
var _duplicates: Dictionary = {}

var _enabled: Dictionary = {}
## id -> where an installed mod came from, as the installer described it (the mod
## browser records the mod.io mod and file ids, which is how it knows a tile is
## already installed and whether a newer file is out).
var _sources: Dictionary = {}
## File moves a mounted pack would not allow, carried to the next launch and run
## before discovery. See _apply_pending.
var _pending: Array[Dictionary] = []
## Seams for mod_browser_tests, which must not touch the player's mods folder or
## their enable state. Empty means the real ones.
var mods_root_override := ""
var state_path_override := ""
var _hooks: ModHooks = null
var _ready_done := false


func _ready() -> void:
	_hooks = ModHooks.new(get_tree())
	_load_state()
	_apply_pending()
	_discover()
	_load_enabled()
	_ready_done = true
	mods_ready.emit()


# ── discovery ─────────────────────────────────────────────────────────────────

func _discover() -> void:
	if mods_root_override.is_empty():
		RomLibrary.ensure_mods_root()
	var found: Dictionary = {}          # id -> Array of file paths
	for entry: Dictionary in _scan():
		var path := str(entry["path"])
		var reader := ModPackReader.open(path)
		if not reader.error.is_empty():
			_unreadable.append({"path": path, "reason": reader.error})
			continue
		var files := reader.files()
		var manifest := _manifest_from(reader, files)
		if manifest == null:
			_unreadable.append({"path": path, "reason": "no mod.json under res://mods/<id>/"})
			reader.close()
			continue
		if not manifest.error.is_empty():
			_unreadable.append({"path": path, "reason": manifest.error})
			reader.close()
			continue
		if not found.has(manifest.id):
			found[manifest.id] = []
		(found[manifest.id] as Array).append(path)
		var rec := _record_for(manifest, path, files)
		# The thumbnail is read here, with the container open and nothing
		# mounted. That is the whole point: the page shows art for a mod that is
		# disabled and has never been loaded, which is exactly when the player is
		# deciding whether to trust it.
		rec.thumbnail = _read_thumbnail(reader, manifest)
		_mods[manifest.id] = rec
		reader.close()

	# Two copies of one mod is refused outright rather than resolved by a rule
	# the player cannot see. An ambiguous install should be visible.
	for id: String in found:
		if (found[id] as Array).size() > 1:
			_duplicates[id] = found[id]
			(_mods[id] as ModRecord).refuse("installed twice: %s" % ", ".join(
				(found[id] as Array).map(func(p): return str(p).get_file())))


## Find and parse the manifest, which is at res://mods/<id>/mod.json for exactly
## one <id>. The id is taken from the FILE LIST rather than trusted from the
## manifest, so a mod cannot file itself under a namespace it does not occupy.
func _manifest_from(reader: ModPackReader, files: PackedStringArray) -> ModManifest:
	var prefix := ModManifest.NAMESPACE_ROOT
	for path: String in files:
		if not path.begins_with(prefix) or not path.ends_with("/mod.json"):
			continue
		var rest := path.substr(prefix.length())
		var slash := rest.find("/")
		if slash < 0:
			continue
		var dir_id := rest.substr(0, slash)
		if rest != dir_id + "/mod.json":
			continue                      # nested, not the manifest
		var m := ModManifest.parse(reader.read_json(path))
		if m.error.is_empty() and m.id != dir_id:
			m.error = "manifest says id '%s' but it lives under mods/%s/" % [m.id, dir_id]
		return m
	return null


func _read_thumbnail(reader: ModPackReader, manifest: ModManifest) -> Texture2D:
	var path := manifest.own_root() + ModManifest.THUMBNAIL_NAME
	if not reader.has(path):
		return null
	var data := reader.read(path)
	if data.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(data) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _record_for(manifest: ModManifest, path: String,
		files: PackedStringArray) -> ModRecord:
	var rec := ModRecord.new()
	rec.id = manifest.id
	rec.manifest = manifest
	rec.path = path
	rec.size = ByteSize.on_disk(path)
	rec.files = files.size()
	var inventory_err := manifest.inventory_error(files)
	if not inventory_err.is_empty():
		rec.refuse(inventory_err)
	elif not manifest.runs_here():
		rec.refuse("not built for %s" % OS.get_name())
	return rec


# ── loading ───────────────────────────────────────────────────────────────────

func _load_enabled() -> void:
	var order := _mods.values().filter(func(r): return _should_load(r))
	# Priority, then id, so a boot is deterministic and a mod that must layer
	# over another can say so without depending on filenames.
	order.sort_custom(func(a, b):
		var pa: int = (a as ModRecord).manifest.priority
		var pb: int = (b as ModRecord).manifest.priority
		if pa != pb:
			return pa < pb
		return (a as ModRecord).id < (b as ModRecord).id)
	for rec: ModRecord in order:
		_mount_and_register(rec)


func _should_load(rec: ModRecord) -> bool:
	if rec.status == ModRecord.Status.REFUSED:
		return false
	return bool(_enabled.get(rec.id, false))


func _mount_and_register(rec: ModRecord) -> void:
	var manifest := rec.manifest
	var shadowing := manifest.shadowing_claims()
	# replace_files only when a claim actually lands on a shipped path. A mod
	# claiming nothing therefore provably cannot touch one.
	var replace := not shadowing.is_empty()
	if not ProjectSettings.load_resource_pack(rec.path, replace):
		rec.fail("the pack could not be mounted")
		return
	rec.mounted = true
	if not ResourceLoader.exists(manifest.entry):
		rec.fail("entry script is missing: %s" % manifest.entry)
		return
	var script := ResourceLoader.load(manifest.entry) as GDScript
	if script == null:
		rec.fail("entry script did not compile: %s" % manifest.entry)
		return
	var inst: Object = script.new()
	if not (inst is RetroMod):
		rec.fail("entry script does not extend RetroMod")
		return
	var api := ModApi.new(manifest, _hooks)
	(inst as RetroMod).register(api)
	# A mod whose contributions were REFUSED is not a loaded mod. Every registry
	# has carried a drop_mod for this since the overlay tables were shared, each
	# documented as the rollback for a registration that failed part-way — and
	# nothing outside the tests had ever called one, so a mod that failed half
	# way through kept the half that worked and was listed as fully loaded.
	#
	# Warnings do not qualify: a platform registered without pad art is
	# incomplete and still plays, which is why _warn and _fail are counted apart.
	if api.failed():
		api.withdraw()
		rec.fail("registration was refused: %s" % api.errors_text())
		return
	rec.api = api
	rec.status = ModRecord.Status.LOADED
	if not shadowing.is_empty():
		rec.reason = "replaces %d shipped file(s)" % shadowing.size()
	print("[mods] loaded %s %s — %s" % [manifest.id, manifest.version, api.summary()])


# ── enable state ──────────────────────────────────────────────────────────────
#
# Kept in its own file rather than in AppPrefs so this autoload does not depend
# on another one having run first.

func _load_state() -> void:
	var d := JsonStore.read_dict(_state_path(), STATE_OWNER)
	var raw: Variant = d.get("enabled", {})
	if raw is Dictionary:
		for id: Variant in (raw as Dictionary):
			_enabled[str(id)] = bool((raw as Dictionary)[id])
	var sources: Variant = d.get("sources", {})
	if sources is Dictionary:
		for id: Variant in (sources as Dictionary):
			if (sources as Dictionary)[id] is Dictionary:
				_sources[str(id)] = (sources as Dictionary)[id]
	var pending: Variant = d.get("pending", [])
	if pending is Array:
		for op: Variant in (pending as Array):
			if op is Dictionary:
				_pending.append(op)


func _save_state() -> void:
	JsonStore.write_dict(_state_path(),
		{"enabled": _enabled, "sources": _sources, "pending": _pending}, STATE_OWNER)


func _state_path() -> String:
	return STATE_PATH if state_path_override.is_empty() else state_path_override


func mods_root() -> String:
	if mods_root_override.is_empty():
		return RomLibrary.default_mods_root()
	return mods_root_override


func incoming_dir() -> String:
	return mods_root().path_join(INCOMING_DIR)


## RomLibrary.scan_mods, over whichever root is in force.
func _scan() -> Array[Dictionary]:
	if mods_root_override.is_empty():
		return RomLibrary.scan_mods()
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(mods_root_override)
	if dir == null:
		return out
	for fname: String in dir.get_files():
		if _is_container(fname):
			out.append({"path": mods_root_override.path_join(fname), "label": fname})
	out.sort_custom(func(a, b): return str(a["label"]).naturalnocasecmp_to(str(b["label"])) < 0)
	return out


static func _is_container(file_name: String) -> bool:
	var ext := file_name.get_extension().to_lower()
	return ext == "zip" or ext == "pck"


## Nothing is enabled by default. A mod that arrives on disk — pushed over adb,
## dropped in by hand, or uploaded through the LAN file server — is inert until
## the player says otherwise, which is the whole of the consent model.
func is_enabled(id: String) -> bool:
	return bool(_enabled.get(id, false))


## Enable or disable a mod. Takes effect on the next launch, because a mounted
## pack cannot be unmounted.
func set_enabled(id: String, enabled: bool) -> void:
	if not _mods.has(id) or (_mods[id] as ModRecord).removal_staged:
		return
	_enabled[id] = enabled
	_save_state()
	var rec: ModRecord = _mods[id]
	if rec.status == ModRecord.Status.REFUSED:
		return
	if enabled and rec.status != ModRecord.Status.LOADED:
		rec.status = ModRecord.Status.PENDING
	elif not enabled and rec.status == ModRecord.Status.LOADED:
		rec.status = ModRecord.Status.PENDING


## True when a change has been made that only a restart can apply.
func restart_pending() -> bool:
	if not _pending.is_empty():
		return true
	for rec: ModRecord in _mods.values():
		if rec.status == ModRecord.Status.PENDING:
			return true
	return false


# ── install, update, remove ───────────────────────────────────────────────────
#
# What the mod browser calls once a download is on disk. Everything here is the
# boot's own vetting run on one file: a pack that would be refused at the next
# launch is refused now, with the same sentence, and never reaches the mods root.
#
# The one thing that cannot be done at once is touching a MOUNTED pack. The
# engine keeps a mounted container open until the app exits, so its file can be
# neither replaced nor deleted (Windows refuses outright; elsewhere the mounted
# copy would simply go on being read). Those moves are written to the state file
# and made by _apply_pending at the next launch, before anything is discovered.

## Vet one container the way discovery does, without mounting it.
## Returns {error, manifest, files, thumbnail}; `error` is "" for a pack that
## would be accepted.
func inspect(path: String) -> Dictionary:
	var out := {"error": "", "manifest": null, "files": PackedStringArray(), "thumbnail": null}
	var reader := ModPackReader.open(path)
	if not reader.error.is_empty():
		out["error"] = reader.error
		return out
	var files := reader.files()
	var manifest := _manifest_from(reader, files)
	out["files"] = files
	out["manifest"] = manifest
	if manifest == null:
		out["error"] = "no mod.json under res://mods/<id>/"
	elif not manifest.error.is_empty():
		out["error"] = manifest.error
	else:
		var inventory_err := manifest.inventory_error(files)
		if not inventory_err.is_empty():
			out["error"] = inventory_err
		elif not manifest.runs_here():
			out["error"] = "not built for %s" % OS.get_name()
		else:
			out["thumbnail"] = _read_thumbnail(reader, manifest)
	reader.close()
	return out


## inspect(), plus what only a DOWNLOAD is held to: no games and no programs
## (ModContentPolicy). A pack the player copied in by hand is not asked this.
##
## The result carries `path`: the pack to install. That is `path` itself, unless
## the download was a BUNDLE (see _unwrap), when it is the build picked out of it.
func vet(path: String) -> Dictionary:
	var unwrapped := _unwrap(path)
	if not str(unwrapped["error"]).is_empty():
		return {"error": str(unwrapped["error"]), "manifest": null,
			"files": PackedStringArray(), "thumbnail": null, "path": path}
	var out := inspect(str(unwrapped["path"]))
	out["path"] = str(unwrapped["path"])
	if str(out["error"]).is_empty():
		out["error"] = ModContentPolicy.violation(out["files"])
	return out


## Open a bundle and return the pack inside it that runs here.
##
## mod.io stores ONE zip per mod. A zip is already a loadable pack, so most
## uploads are the pack and come straight back. Two kinds are not:
##   * a `.pck`, which mod.io will not take bare, so it travels inside a zip;
##   * a mod built once per platform -- a desktop pack and a Quest pack, each
##     with only its own texture formats -- which travels as one zip of both.
##
## A bundle is a zip with no manifest of its own and containers at its top level.
## The one whose manifest names this platform is written out beside the download
## (in incoming, so a failure leaves nothing in the mods root) and the download is
## deleted. None that runs here is refused with each one's reason; more than one
## is refused too, because picking would be a rule the author cannot see.
##
## Returns {path, error}. A file that is not a bundle is returned untouched and
## left for inspect() to judge.
func _unwrap(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "zip":
		return {"path": path, "error": ""}
	var reader := ModPackReader.open(path)
	if not reader.error.is_empty():
		return {"path": path, "error": ""}
	var files := reader.files()
	if _manifest_from(reader, files) != null:
		reader.close()
		return {"path": path, "error": ""}
	var inner := PackedStringArray()
	for file: String in files:
		var name := file.trim_prefix("res://")
		if not name.contains("/") and _is_container(name):
			inner.append(file)
	if inner.is_empty():
		reader.close()
		return {"path": path, "error": ""}

	var fits := PackedStringArray()
	var reasons := PackedStringArray()
	var stem := path.get_basename()
	for i in range(inner.size()):
		var out_path := "%s.build%d.%s" % [stem, i, inner[i].get_extension().to_lower()]
		var bytes := reader.read(inner[i])
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null or bytes.is_empty():
			reasons.append("%s: could not be read" % inner[i].get_file())
			continue
		var stored := f.store_buffer(bytes)
		f.close()
		if not stored:
			DirAccess.remove_absolute(out_path)
			reasons.append("%s: not enough space to open it" % inner[i].get_file())
			continue
		var info := inspect(out_path)
		if str(info["error"]).is_empty():
			fits.append(out_path)
		else:
			DirAccess.remove_absolute(out_path)
			reasons.append("%s: %s" % [inner[i].get_file(), str(info["error"])])
	reader.close()

	if fits.size() == 1:
		DirAccess.remove_absolute(path)
		return {"path": fits[0], "error": ""}
	for extra: String in fits:
		DirAccess.remove_absolute(extra)
	if fits.size() > 1:
		return {"path": path, "error": "holds %d packs that all run on %s" % [fits.size(), OS.get_name()]}
	return {"path": path, "error": "holds no pack that runs here (%s)" % "; ".join(reasons)}


## Install the container at `staged` (a file in incoming_dir()), replacing any
## copy of the same mod. `source` is kept against the mod's id for the caller.
##
## Returns {ok, id, error, restart}. `restart` is true when the new pack only
## takes over at the next launch. A refused file is deleted: it was fetched for
## this and is good for nothing else.
##
## The mod lands DISABLED unless the player had already enabled that id. Fetching
## a mod is not consent to run it; the switch is, and it shows what the mod claims.
func install(staged: String, source: Dictionary = {}) -> Dictionary:
	var info := vet(staged)
	if not str(info["error"]).is_empty():
		DirAccess.remove_absolute(str(info["path"]))
		DirAccess.remove_absolute(staged)
		return {"ok": false, "id": "", "error": str(info["error"]), "restart": false}
	# The pack itself: the download, or the build picked out of a bundle.
	staged = str(info["path"])
	var manifest: ModManifest = info["manifest"]
	var id := manifest.id
	var final_name := "%s.%s" % [id, staged.get_extension().to_lower()]
	var old: ModRecord = _mods.get(id)
	var old_names := _container_names(id)

	_drop_pending_for(id)
	if old != null and old.mounted:
		var parked := incoming_dir().path_join(final_name)
		if parked != staged:
			DirAccess.remove_absolute(parked)
			if DirAccess.rename_absolute(staged, parked) != OK:
				DirAccess.remove_absolute(staged)
				return {"ok": false, "id": id, "restart": false,
					"error": "Cannot write to the mods folder"}
		_pending.append({"op": "install", "id": id, "from": final_name,
			"to": final_name, "replaces": old_names})
		old.update_staged = manifest.version
		old.update_thumbnail = info["thumbnail"]
		old.update_size = ByteSize.on_disk(parked)
		old.update_files = (info["files"] as PackedStringArray).size()
		old.removal_staged = false
		if not source.is_empty():
			_sources[id] = source
		_save_state()
		mods_changed.emit()
		return {"ok": true, "id": id, "error": "", "restart": true}

	for file_name: String in old_names:
		var old_path := mods_root().path_join(file_name)
		if FileAccess.file_exists(old_path) and DirAccess.remove_absolute(old_path) != OK:
			DirAccess.remove_absolute(staged)
			return {"ok": false, "id": id, "restart": false,
				"error": "Cannot replace %s" % file_name}
	var final_path := mods_root().path_join(final_name)
	DirAccess.remove_absolute(final_path)
	if DirAccess.rename_absolute(staged, final_path) != OK:
		DirAccess.remove_absolute(staged)
		return {"ok": false, "id": id, "restart": false,
			"error": "Cannot write to the mods folder"}

	var rec := _record_for(manifest, final_path, info["files"])
	rec.thumbnail = info["thumbnail"]
	if is_enabled(id) and rec.status != ModRecord.Status.REFUSED:
		rec.status = ModRecord.Status.PENDING
	_mods[id] = rec
	_duplicates.erase(id)
	if source.is_empty():
		_sources.erase(id)
	else:
		_sources[id] = source
	_save_state()
	mods_changed.emit()
	return {"ok": true, "id": id, "error": "",
		"restart": rec.status == ModRecord.Status.PENDING}


## Remove an installed mod. Returns {ok, error, restart}.
func remove(id: String) -> Dictionary:
	var rec: ModRecord = _mods.get(id)
	if rec == null:
		return {"ok": false, "error": "Not installed", "restart": false}
	var names := _container_names(id)
	_drop_pending_for(id)
	_enabled.erase(id)
	if rec.mounted:
		_pending.append({"op": "remove", "id": id, "files": names})
		rec.removal_staged = true
		rec.update_staged = ""
		rec.update_thumbnail = null
		rec.update_size = 0
		rec.update_files = 0
		_save_state()
		mods_changed.emit()
		return {"ok": true, "error": "", "restart": true}
	for file_name: String in names:
		var path := mods_root().path_join(file_name)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			_save_state()
			return {"ok": false, "error": "Cannot delete %s" % file_name, "restart": false}
	_mods.erase(id)
	_duplicates.erase(id)
	_sources.erase(id)
	_save_state()
	mods_changed.emit()
	return {"ok": true, "error": "", "restart": false}


## Delete a container that could not be read at all, so a corrupt download is
## not something the player has to find a file manager for.
func remove_unreadable(path: String) -> bool:
	for i in range(_unreadable.size()):
		if str(_unreadable[i]["path"]) != path:
			continue
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			return false
		_unreadable.remove_at(i)
		mods_changed.emit()
		return true
	return false


## What install() was told about where a mod came from, {} for a hand install.
func source(id: String) -> Dictionary:
	var v: Variant = _sources.get(id, {})
	return v if v is Dictionary else {}


## Replace what is kept about where an installed mod came from. The mod browser
## uses it to record which packs brought a mod in, and to forget one.
func set_source(id: String, source: Dictionary) -> void:
	if not _mods.has(id):
		return
	if source.is_empty():
		_sources.erase(id)
	else:
		_sources[id] = source
	_save_state()
	mods_changed.emit()


## The installed mod whose source has `key` equal to `value`, or null.
func find_by_source(key: String, value: Variant) -> ModRecord:
	for id: String in _sources:
		if _mods.has(id) and (_sources[id] as Dictionary).get(key) == value:
			return _mods[id]
	return null


## The file name of every container on disk that carries this id.
func _container_names(id: String) -> Array:
	if _duplicates.has(id):
		return (_duplicates[id] as Array).map(func(p): return str(p).get_file())
	var rec: ModRecord = _mods.get(id)
	return [] if rec == null else [rec.path.get_file()]


## Forget whatever was waiting for the next launch for this mod, and the file a
## waiting install had parked.
func _drop_pending_for(id: String) -> void:
	var kept: Array[Dictionary] = []
	for op: Dictionary in _pending:
		if str(op.get("id", "")) != id:
			kept.append(op)
		elif str(op.get("op", "")) == "install":
			DirAccess.remove_absolute(
				incoming_dir().path_join(str(op.get("from", "")).get_file()))
	_pending = kept


## Make the moves the last session could not. Runs before discovery, when
## nothing is mounted.
##
## Every name is reduced to its last component and must be a container: the list
## is read from a JSON file, and a path in it must not be able to reach outside
## the mods root.
func _apply_pending() -> void:
	if _pending.is_empty():
		_sweep_incoming()
		return
	var root := mods_root()
	for op: Dictionary in _pending:
		match str(op.get("op", "")):
			"remove":
				for file_name: Variant in (op.get("files", []) as Array):
					_delete_container(root, str(file_name))
			"install":
				var from := str(op.get("from", "")).get_file()
				var to := str(op.get("to", "")).get_file()
				var staged := incoming_dir().path_join(from)
				if not _is_container(from) or not _is_container(to):
					continue
				if not FileAccess.file_exists(staged):
					continue
				for file_name: Variant in (op.get("replaces", []) as Array):
					_delete_container(root, str(file_name))
				DirAccess.remove_absolute(root.path_join(to))
				DirAccess.rename_absolute(staged, root.path_join(to))
	_pending.clear()
	_save_state()
	_sweep_incoming()


## Delete downloads nobody finished with: a pack fetched and never confirmed, or
## one whose install was interrupted. Whatever was parked for this launch has
## just been moved out by _apply_pending. A `.part` is kept, so an interrupted
## download can still resume.
func _sweep_incoming() -> void:
	var dir := DirAccess.open(incoming_dir())
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if _is_container(file_name):
			dir.remove(file_name)


static func _delete_container(root: String, file_name: String) -> void:
	var leaf := file_name.get_file()
	if _is_container(leaf) and FileAccess.file_exists(root.path_join(leaf)):
		DirAccess.remove_absolute(root.path_join(leaf))


# ── what the UI and netplay ask ───────────────────────────────────────────────

## Every discovered mod, ordered for display: loaded first, then pending, then
## disabled, then everything that failed — with the problems last because they
## are what the page is mostly there to explain.
func all_mods() -> Array:
	var out := _mods.values().duplicate()
	out.sort_custom(func(a, b):
		var rank := {Status.LOADED: 0, Status.PENDING: 1, Status.DISABLED: 2,
			Status.FAILED: 3, Status.REFUSED: 4}
		var ra: int = rank.get((a as ModRecord).status, 5)
		var rb: int = rank.get((b as ModRecord).status, 5)
		if ra != rb:
			return ra < rb
		return (a as ModRecord).id < (b as ModRecord).id)
	return out


func mod(id: String) -> ModRecord:
	return _mods.get(id) as ModRecord


## Containers that could not be identified at all — a corrupt pack, or one whose
## manifest is missing. Listed on the page so a file the player put there does
## not simply fail to appear.
func unreadable() -> Array[Dictionary]:
	return _unreadable


static func status_text(status: ModRecord.Status) -> String:
	match status:
		Status.DISABLED: return "Disabled"
		Status.PENDING:  return "Restart to apply"
		Status.LOADED:   return "Loaded"
		Status.REFUSED:  return "Refused"
		Status.FAILED:   return "Failed"
	return "?"


## The enabled-and-loaded mods as "id@version", sorted — what peers compare.
##
## Sent in the netplay handshake, never the packs themselves. A peer missing a
## mod is told so rather than sent it: the mod browser fetches from mod.io, where
## a pack has been through that site's scan and this game's moderation, and one
## player's copy handed straight to another has been through neither.
func fingerprint() -> PackedStringArray:
	var out := PackedStringArray()
	for rec: ModRecord in _mods.values():
		if rec.status != ModRecord.Status.LOADED:
			continue
		out.append("%s@%s" % [rec.manifest.id, rec.manifest.version])
	out.sort()
	return out


## Describe the difference between two fingerprints, for a rejection message.
static func fingerprint_mismatch(ours: PackedStringArray, theirs: PackedStringArray) -> String:
	var mine := {}
	for s: String in ours:
		mine[s] = true
	var yours := {}
	for s: String in theirs:
		yours[s] = true
	var missing := PackedStringArray()
	var extra := PackedStringArray()
	for s: String in ours:
		if not yours.has(s):
			missing.append(s)
	for s: String in theirs:
		if not mine.has(s):
			extra.append(s)
	var parts := PackedStringArray()
	if not missing.is_empty():
		parts.append("you are missing " + ", ".join(missing))
	if not extra.is_empty():
		parts.append("you have extra " + ", ".join(extra))
	return "; ".join(parts)
