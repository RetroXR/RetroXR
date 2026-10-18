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
##   6. mount what is left, in priority order with each mod's dependencies ahead
##      of it, and run its entry script; a mod whose dependency cannot run is
##      not mounted at all (dependency_problem)
##
## Steps 1-5 touch nothing and are reversible, which is what makes it safe to
## inspect every mod on disk at every boot while mounting only the enabled ones.
## Step 6 is not: ProjectSettings.load_resource_pack cannot be undone. A mod that
## was never mounted can still be mounted later in the session (apply_live), but
## disabling, updating or removing one that IS mounted waits for the next launch,
## and the Mods page says which is which rather than pretending otherwise.
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
## apply_live mounted mods after boot. What reads a registry once and keeps the
## answer (the spawn menu's TVs tab, its grids) has to read it again.
signal mods_applied()

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
	# A test suite boots with no mods. What the player has installed is not what a
	# suite checks: a modded PS2 has no stand-in shelf, and its shell's ILinkPort
	# marker hid the socket, so two suites failed on one machine and passed on CI.
	# Nor may a suite make the player's pending installs. The state is still read,
	# so anything that saves it writes the player's choices back unchanged.
	# BootScene completes a pending folder move before any pack is mounted.
	if not _is_test_run():
		if not DataPaths.migration_mode():
			load_data_root()
		return
	_ready_done = true
	mods_ready.emit()


## Also called by BootScene after a data-folder move, before choosing a room.
func load_data_root() -> void:
	_apply_pending()
	_discover()
	_load_enabled()
	_ready_done = true
	mods_ready.emit()


## Whether this run is one of the suites in res://Tests/ (the scene on the command
## line, as Tools/run_tests.py and a hand-run suite both give it). Probes under
## Tools/ are not: one that looks at the room wants the room the player has.
static func _is_test_run() -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("res://Tests/"):
			return true
	return false


# ── discovery ─────────────────────────────────────────────────────────────────

func _discover() -> void:
	if mods_root_override.is_empty():
		RomLibrary.ensure_mods_root()
	var found: Dictionary = {}          # id -> Array of file paths
	for entry: Dictionary in _scan():
		var path := str(entry["path"])
		var read := _read_container(path)
		if not read.has("rec"):
			_unreadable.append({"path": path, "reason": str(read["reason"])})
			continue
		var rec: ModRecord = read["rec"]
		if not found.has(rec.id):
			found[rec.id] = []
		(found[rec.id] as Array).append(path)
		_mods[rec.id] = rec

	# Two copies of one mod is refused outright rather than resolved by a rule
	# the player cannot see. An ambiguous install should be visible.
	for id: String in found:
		if (found[id] as Array).size() > 1:
			_duplicates[id] = found[id]
			(_mods[id] as ModRecord).refuse("installed twice: %s" % ", ".join(
				(found[id] as Array).map(func(p): return str(p).get_file())))


## Open one container WITHOUT mounting it: {"rec": its ModRecord}, or
## {"reason": why it could not be identified at all}.
func _read_container(path: String) -> Dictionary:
	var reader := ModPackReader.open(path)
	if not reader.error.is_empty():
		return {"reason": reader.error}
	var files := reader.files()
	var manifest := _manifest_from(reader, files)
	var reason := ""
	if manifest == null:
		reason = "no mod.json under res://mods/<id>/"
	elif not manifest.error.is_empty():
		reason = manifest.error
	if not reason.is_empty():
		reader.close()
		return {"reason": reason}
	var rec := _record_for(manifest, path, files)
	# The thumbnail is read here, with the container open and nothing mounted.
	# That is the whole point: the page shows art for a mod that is disabled and
	# has never been loaded, which is exactly when the player is deciding whether
	# to trust it.
	rec.thumbnail = _read_thumbnail(reader, manifest)
	reader.close()
	return {"rec": rec}


## Pick up packs that arrived after boot -- dropped in by hand, pushed over adb,
## uploaded through the LAN file server -- so they can be switched on without a
## restart. Returns how many mods it added.
##
## Only a NEW id gets a record. A second container for an id already here is left
## for the next boot to judge (two copies refuse both): re-recording a mod
## mid-session could rewrite one that is running, and the netplay fingerprint is
## read off the records. An unreadable container is read again, since an adb push
## or a copy may have been half-written the last time.
func rescan() -> int:
	var known: Dictionary = {}
	for rec: ModRecord in _mods.values():
		known[rec.path] = true
	for paths: Variant in _duplicates.values():
		for p: Variant in (paths as Array):
			known[str(p)] = true
	var was_unreadable: Dictionary = {}
	for u: Dictionary in _unreadable:
		was_unreadable[str(u["path"])] = true
	var unreadable: Array[Dictionary] = []
	var added := 0
	for entry: Dictionary in _scan():
		var path := str(entry["path"])
		if known.has(path):
			continue
		var read := _read_container(path)
		if not read.has("rec"):
			unreadable.append({"path": path, "reason": str(read["reason"])})
			continue
		var rec: ModRecord = read["rec"]
		if _mods.has(rec.id):
			continue
		rec.status = _status_for(rec, is_enabled(rec.id))
		_mods[rec.id] = rec
		added += 1
	if added > 0:
		_refresh_dependencies()
	var listing_changed := unreadable.size() != was_unreadable.size()
	for u: Dictionary in unreadable:
		listing_changed = listing_changed or not was_unreadable.has(str(u["path"]))
	_unreadable = unreadable
	if added > 0 or listing_changed:
		_notify_changed()
	return added


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
	for rec: ModRecord in _in_load_order(_mods.values().filter(func(r): return _should_load(r))):
		# Asked of each in turn, after everything ahead of it has been mounted: a
		# dependency that failed to register stops what needs it here.
		if not _block_if_needed(rec):
			_mount_and_register(rec)


## Priority, then id, so a boot is deterministic and a mod that must layer over
## another can say so without depending on filenames. apply_live mounts in the
## same order, among the mods it mounts.
static func _load_order(a: ModRecord, b: ModRecord) -> bool:
	if a.manifest.priority != b.manifest.priority:
		return a.manifest.priority < b.manifest.priority
	return a.id < b.id


## `recs` in load order (_load_order) with every mod's dependencies among them
## moved ahead of it, whatever their priority: a mod is mounted only after what
## it needs. A cycle is placed in some order and refused by dependency_problem.
func _in_load_order(recs: Array) -> Array[ModRecord]:
	var sorted := recs.duplicate()
	sorted.sort_custom(_load_order)
	var wanted := {}
	for rec: ModRecord in sorted:
		wanted[rec.id] = rec
	var out: Array[ModRecord] = []
	var placed := {}
	for rec: ModRecord in sorted:
		_place_after_needs(rec, wanted, placed, out)
	return out


func _place_after_needs(rec: ModRecord, wanted: Dictionary, placed: Dictionary,
		out: Array[ModRecord]) -> void:
	if placed.has(rec.id):
		return
	# Marked before its dependencies are placed, so a cycle stops here.
	placed[rec.id] = true
	for dep: Dictionary in rec.manifest.dependencies:
		var other: ModRecord = wanted.get(str(dep["id"]))
		if other != null:
			_place_after_needs(other, wanted, placed, out)
	out.append(rec)


# ── dependencies ──────────────────────────────────────────────────────────────

## Why `rec` cannot run with what is installed and switched on, "" when it can:
## every mod it needs is installed, not refused, switched on, new enough, and
## able to run itself. Asked before a mod is mounted, at boot and by apply_live,
## and after every change to what is installed or switched on, so a mod is never
## mounted without what it needs and its page always says what is missing.
func dependency_problem(rec: ModRecord) -> String:
	return _dependency_problem(rec, {})


func _dependency_problem(rec: ModRecord, seen: Dictionary) -> String:
	seen[rec.id] = true
	for dep: Dictionary in rec.manifest.dependencies:
		var dep_id := str(dep["id"])
		var at_least := str(dep["min"])
		var other: ModRecord = _mods.get(dep_id)
		if other == null or other.removal_staged:
			return "needs %s, which is not installed" % (dep_id if at_least.is_empty()
				else "%s %s or newer" % [dep_id, at_least])
		var named := "%s (%s)" % [other.manifest.name, dep_id]
		if seen.has(dep_id):
			return "needs %s, which needs it in turn" % named
		if other.status == Status.REFUSED:
			return "needs %s, which was refused: %s" % [named, other.reason]
		if not ModManifest.version_at_least(other.manifest.version, at_least):
			return "needs %s %s or newer, and %s is installed" % [named, at_least,
				other.manifest.version]
		if not is_enabled(dep_id):
			return "needs %s, which is switched off" % named
		if other.mounted and not other.loaded:
			return "needs %s, which did not load" % named
		var deeper := _dependency_problem(other, seen.duplicate())
		if not deeper.is_empty():
			return "needs %s, which cannot run: it %s" % [named, deeper]
	return ""


## Mark `rec` FAILED, unmounted, when a dependency stops it. Returns whether it did.
func _block_if_needed(rec: ModRecord) -> bool:
	var why := dependency_problem(rec)
	if why.is_empty():
		return false
	rec.fail(why)
	rec.blocked_by_dependency = true
	return true


## Mark what cannot run for want of a dependency, and take the mark off what now
## can. Only mods switched on and not mounted: a running mod goes on running, and
## a mod switched off has nothing to explain.
func _refresh_dependencies() -> void:
	for rec: ModRecord in _mods.values():
		if rec.mounted or rec.status == Status.REFUSED or not is_enabled(rec.id):
			continue
		if not _block_if_needed(rec) and rec.blocked_by_dependency:
			rec.blocked_by_dependency = false
			rec.reason = ""
			rec.status = _status_for(rec, true)


## What switching `id` on switches on with it: every installed mod it needs, all
## the way down, that is switched off. The Mods page says so beside the switch.
func switched_on_with(id: String) -> Array[String]:
	var out: Array[String] = []
	_collect_needs(id, out, {id: true})
	return out


func _collect_needs(id: String, out: Array[String], seen: Dictionary) -> void:
	var rec: ModRecord = _mods.get(id)
	if rec == null:
		return
	for dep: Dictionary in rec.manifest.dependencies:
		var dep_id := str(dep["id"])
		if seen.has(dep_id):
			continue
		seen[dep_id] = true
		var other: ModRecord = _mods.get(dep_id)
		if other == null or other.status == Status.REFUSED or other.removal_staged:
			continue
		if not is_enabled(dep_id):
			out.append(dep_id)
		_collect_needs(dep_id, out, seen)


## What switching `id` off switches off with it: every mod switched on that needs
## it, directly or through another.
func switched_off_with(id: String) -> Array[String]:
	var out: Array[String] = []
	for other: String in needed_by(id, true):
		if is_enabled(other):
			out.append(other)
	return out


## The installed mods that need `id`, sorted: those that list it, or with `deep`
## also those that need one of those.
func needed_by(id: String, deep: bool = false) -> Array[String]:
	var out: Array[String] = []
	var frontier: Array[String] = [id]
	var seen := {id: true}
	while not frontier.is_empty():
		var cur: String = frontier.pop_back()
		for rec: ModRecord in _mods.values():
			if seen.has(rec.id) or not rec.manifest.dependencies.any(
					func(d: Dictionary) -> bool: return str(d["id"]) == cur):
				continue
			seen[rec.id] = true
			out.append(rec.id)
			if deep:
				frontier.append(rec.id)
	out.sort()
	return out


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
	rec.loaded = true
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
	if _hold > 0:
		_held_save = true
		return
	JsonStore.write_dict(_state_path(),
		{"enabled": _enabled, "sources": _sources, "pending": _pending}, STATE_OWNER)


# ── several changes at once ───────────────────────────────────────────────────

## How many callers are holding, and what they are owed when the last lets go.
var _hold := 0
var _held_save := false
var _held_notice := false


## Between hold_changes() and release_changes() the loader does everything it is
## asked but says so ONCE, at the end: one write of its state file and one
## mods_changed, however many mods were installed, enabled or tagged in between.
##
## A pack of four used to be four installs, four enables and four sources, each
## writing the file and each rebuilding every list the menu shows -- on the main
## thread, in the one frame the player pressed Install. Held, it is one of each.
## Calls nest; nothing is said until the outermost release.
func hold_changes() -> void:
	_hold += 1


func release_changes() -> void:
	if _hold <= 0:
		return
	_hold -= 1
	if _hold > 0:
		return
	if _held_save:
		_held_save = false
		_save_state()
	if _held_notice:
		_held_notice = false
		mods_changed.emit()


func _notify_changed() -> void:
	if _hold > 0:
		_held_notice = true
		return
	mods_changed.emit()


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


## Enable or disable a mod. Nothing is mounted or unmounted here: a mod switched
## on waits for apply_live or the next launch, and one switched off goes on
## running until the next launch, because a mounted pack cannot be unmounted.
##
## A mod switched on switches on what it needs (switched_on_with), and one
## switched off switches off what needs it (switched_off_with): a switch the
## player flips cannot leave a mod on that has no way to run.
func set_enabled(id: String, enabled: bool) -> void:
	if not _mods.has(id) or (_mods[id] as ModRecord).removal_staged:
		return
	for other: String in (switched_on_with(id) if enabled else switched_off_with(id)):
		_switch(other, enabled)
	_switch(id, enabled)
	_save_state()
	_refresh_dependencies()


func _switch(id: String, enabled: bool) -> void:
	_enabled[id] = enabled
	var rec: ModRecord = _mods[id]
	if rec.blocked_by_dependency:
		rec.blocked_by_dependency = false
		rec.reason = ""
	rec.status = _status_for(rec, enabled)


## A record's status once its switch reads `enabled`, from what is actually
## running rather than from the status it had: flipping a switch and flipping it
## back is not a change. (It used to be. Switching a new mod on and off again, or
## a running one off and on again, left it waiting for a restart that would have
## changed nothing.)
static func _status_for(rec: ModRecord, enabled: bool) -> Status:
	if rec.status == Status.REFUSED:
		return Status.REFUSED
	if rec.loaded:
		return Status.LOADED if enabled else Status.PENDING
	if rec.mounted:
		# Mounted, and its entry failed. Neither position of the switch changes
		# anything this session, and the reason is what the page should show.
		return Status.FAILED
	return Status.PENDING if enabled else Status.DISABLED


## Mount the mods apply_plan() says can be mounted now, the way a boot mounts
## them (_mount_and_register, in load order), and say so. Returns each record it
## mounted, LOADED or FAILED.
##
## Call it with NO room standing -- SceneManager.reload_room's `prepare` -- as a
## boot does: a mod's hooks see nodes as they enter the tree, before their
## _ready, and the room built next is what they have to see. Dressing nodes that
## are already ready is not the same thing (the n64pad reshell, for one, has to
## run before the controller looks for its controls).
##
## A mod mounted here registers after every mod mounted at boot, whatever its
## priority, so where two mods both claim one thing (ModApi.dress, an overridden
## row, a cartridge or expansion shell -- first come, first served) the next
## launch may settle it the other way.
func apply_live() -> Array[ModRecord]:
	var mounted: Array[ModRecord] = []
	var plan := apply_plan()
	if not str(plan["blocked"]).is_empty():
		return mounted
	for rec: ModRecord in (plan["live"] as Array):
		# Listed either way, so the caller says out loud why one did not load.
		if not _block_if_needed(rec):
			_mount_and_register(rec)
		mounted.append(rec)
	if mounted.is_empty():
		return mounted
	# It caches misses, and a new platform's art can arrive with its pack.
	SystemIcons.forget()
	mods_applied.emit()
	_notify_changed()
	return mounted


## True when some switch, install or removal has not taken effect yet.
func changes_waiting() -> bool:
	if not _pending.is_empty():
		return true
	for rec: ModRecord in _mods.values():
		if rec.status == ModRecord.Status.PENDING:
			return true
	return false


## What applying the waiting changes would take:
##   live     the mods that can be mounted NOW, in load order: switched on, never
##            mounted, and replacing no file the game ships (one that does is
##            mounted with replace_files, and a shipped file already in the
##            resource cache would go on being served from it)
##   restart  something only a restart can apply: a mounted pack switched off,
##            updated or removed, or a mod that is not `live`
##   blocked  why neither may happen now, "" when they may
## A mod is `live` only with everything it needs running or `live` too, and
## mounted after it.
func apply_plan() -> Dictionary:
	var live: Array[ModRecord] = []
	var restart := not _pending.is_empty()
	for rec: ModRecord in _mods.values():
		if rec.status != ModRecord.Status.PENDING:
			continue
		if _loads_live(rec):
			live.append(rec)
		else:
			restart = true
	var dropped := true
	while dropped:
		dropped = false
		for rec: ModRecord in live.duplicate():
			for dep: Dictionary in rec.manifest.dependencies:
				var other: ModRecord = _mods.get(str(dep["id"]))
				if other != null and not other.loaded and not live.has(other):
					live.erase(rec)
					restart = true
					dropped = true
					break
	live = _in_load_order(live)
	var blocked := ""
	if (restart or not live.is_empty()) and _in_netplay():
		# Peers compared fingerprints once, at the handshake, and a host's reload
		# would leave every client standing in the old room.
		blocked = "Leave the netplay session to apply your changes."
	return {"live": live, "restart": restart, "blocked": blocked}


func _loads_live(rec: ModRecord) -> bool:
	return not rec.mounted and _should_load(rec) \
		and rec.manifest.shadowing_claims().is_empty()


## Read through the tree rather than by the autoload's name, so a ModManager the
## tests build outside the tree can still ask.
func _in_netplay() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var net: Node = tree.root.get_node_or_null("NetworkManager")
	return net != null and net.is_active()


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
##
## `vetted` is what vet() returned for this same file, from a caller that has
## already asked (the review a download waits in). Vetting opens the pack, lists
## it and decodes its picture, and a file that has not left incoming since need
## not be put through that twice. It is believed only for the file it names,
## and only while that file is still there.
func install(staged: String, source: Dictionary = {}, vetted: Dictionary = {}) -> Dictionary:
	var info := vetted
	if info.get("manifest") == null or str(info.get("path", "")) != staged \
			or not str(info.get("error", "")).is_empty() or not FileAccess.file_exists(staged):
		info = vet(staged)
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
		_notify_changed()
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
	rec.status = _status_for(rec, is_enabled(id))
	_mods[id] = rec
	_duplicates.erase(id)
	if source.is_empty():
		_sources.erase(id)
	else:
		_sources[id] = source
	_refresh_dependencies()
	_save_state()
	_notify_changed()
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
		_refresh_dependencies()
		_save_state()
		_notify_changed()
		return {"ok": true, "error": "", "restart": true}
	for file_name: String in names:
		var path := mods_root().path_join(file_name)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			_save_state()
			return {"ok": false, "error": "Cannot delete %s" % file_name, "restart": false}
	_mods.erase(id)
	_duplicates.erase(id)
	_sources.erase(id)
	_refresh_dependencies()
	_save_state()
	_notify_changed()
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
		_notify_changed()
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
	_notify_changed()


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
		Status.PENDING:  return "Waiting to apply"
		Status.LOADED:   return "Loaded"
		Status.REFUSED:  return "Refused"
		Status.FAILED:   return "Failed"
	return "?"


## The mods running this session as "id@version", sorted — what peers compare.
## Running, not switched on: a mod switched off goes on running until the next
## launch, and leaving it out told a peer it was not there.
##
## Sent in the netplay handshake, never the packs themselves. A peer missing a
## mod is told so rather than sent it: the mod browser fetches from mod.io, where
## a pack has been through that site's scan and this game's moderation, and one
## player's copy handed straight to another has been through neither.
func fingerprint() -> PackedStringArray:
	var out := PackedStringArray()
	for rec: ModRecord in _mods.values():
		if not rec.loaded:
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
