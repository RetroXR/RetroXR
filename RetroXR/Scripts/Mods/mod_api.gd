## ModApi — what a mod is handed, and the only supported way for it to register.
##
## Every call RECORDS what it did, so the Mods page can report what a mod
## actually contributed rather than what its manifest claimed. For a system whose
## whole security story is informed consent, observed beats declared.
##
## Ids a mod introduces must be namespaced "<mod_id>:<name>". That is not
## tidiness: the shipped model ids, the room ids and the persistence type strings
## are flat global namespaces that end up in save files, so an unprefixed mod id
## could collide with a shipped one or with another mod — and the collision would
## surface as a save that restores the wrong object.
class_name ModApi
extends RefCounted

## Contribution kinds, in the order the Mods page lists them.
const KINDS := ["console", "platform", "room", "object", "tv_shell", "controller",
	"media", "scraper", "hook"]

var id: String = ""
var manifest: ModManifest = null

var _hooks: ModHooks = null
## kind -> Array[String] of human-readable labels.
var _record: Dictionary = {}
## Problems raised during this mod's own registration, shown on the Mods page.
var _problems: PackedStringArray = []
## The subset of those that were REFUSALS rather than warnings.
##
## Kept apart because the two mean opposite things for whether the mod loads: a
## platform registered without pad art is incomplete and still works, while a
## row the registry rejected is a contribution the mod believes it made and did
## not. Only the second is grounds for withdrawing the mod.
var _errors: PackedStringArray = []


## The callbacks this mod hung on SceneManager.scene_content_ready.
var _room_callbacks: Array[Callable] = []
## The wrappers this mod hung on AppPrefs.mains_region_changed.
var _mains_callbacks: Array[Callable] = []
## region id -> the entry this mod put in MainsRegions.extra (the very
## dictionary, so withdraw() takes back only an entry that is still its own).
var _mains_regions: Dictionary = {}


func _init(a_manifest: ModManifest, hooks: ModHooks) -> void:
	manifest = a_manifest
	id = a_manifest.id
	_hooks = hooks


# ── consoles ──────────────────────────────────────────────────────────────────

## Add a console model. `row` is a SystemModelRegistry row: platform, label, and
## exactly one of scene/script, plus optional handheld and requires.
##
## `sockets` lists the cable sockets on its back panel by connector -- the
## `connector` each socket node has in its scene: "composite_plug" for phono
## jacks, "ps2_av_multi" for a PlayStation 2's AV MULTI OUT, a link socket's.
## The card reads it, since it cannot build the console to look: a console with
## no phono jacks is not offered the Composite Cable, and every lead installed
## that fits one of its sockets is offered instead. A row with no `sockets` is
## taken to wear phono jacks. The first time the console is built, its page says
## if the list and the console disagree. Its controller port is its platform's
## (Connectors.CONTROLLER_PORTS) and is not listed.
func register_model(row: Dictionary) -> bool:
	var model_id := str(row.get("id", ""))
	if not _namespaced(model_id, "model id"):
		return false
	if not _sockets_ok(row, "model %s" % model_id):
		return false
	row = _current_platform(row)
	var err := SystemModelRegistry.register_mod_row(model_id, row, id)
	if not err.is_empty():
		return _fail("model %s: %s" % [model_id, err])
	_note("console", "%s (%s)" % [row.get("label", model_id), row.get("platform", "?")])
	return true


## Replace a shipped console model in place. The recommended way to override
## hardware: no file replacement, no claim, and the row keeps its original id so
## existing saves still resolve to it.
func override_model(model_id: String, row: Dictionary) -> bool:
	if not _sockets_ok(row, "override %s" % model_id):
		return false
	row = _current_platform(row)
	var err := SystemModelRegistry.override_mod_row(model_id, row, id)
	if not err.is_empty():
		return _fail("override %s: %s" % [model_id, err])
	_note("console", "%s (replaces shipped)" % model_id)
	return true


## Replace the shell an expansion unit wears -- an e-Reader, a 32X, a disk drive.
##
## `unit_id` is the unit's catalog id ("ereader_usa"), one call per unit, so a
## mod can dress one revision or all of them. `fields` is {shell, size} and,
## only for a model that is NOT in the same frame as the game's, the placements
## the game measured off its own: {connector, swipe_slit, seat_yaw}. `shell_lods`
## is [[model, metres], ...]; without it the shell has one level. `shell_offset`
## moves the shell off the middle of its bounds, for one whose locating part --
## the body that goes in a pocket -- is not the middle of the whole.
##
## `variants` is {variant id: fields}, for a unit sold as other moldings in other
## markets (the Super Game Boy's Super Famicom shell): a unit of that variant --
## its row held for it, as offer_variants offers -- wears that shell, each field
## laid over these. ExpansionCatalog.shell_key says which a unit reads.
##
## What the unit is does not change: its host, its media and the dump it runs
## stay the game's. One mod holds a unit; a second is told who has it.
func override_expansion_shell(unit_id: String, fields: Dictionary) -> bool:
	var holder := ExpansionCatalog.shell_owner_of(unit_id)
	if not holder.is_empty() and holder != id:
		_warn("%s's shell already comes from mod '%s'; this mod's is not used" % [unit_id, holder])
		return false
	var err := ExpansionCatalog.register_mod_shell(unit_id, fields, id)
	if not err.is_empty():
		return _fail("expansion shell %s: %s" % [unit_id, err])
	_note("console", "%s (shell)" % ExpansionCatalog.label_of(unit_id))
	return true


## Add or replace a console's hardware descriptor.
func register_system_info(info: SystemInfo) -> bool:
	if info == null or info.systemid.is_empty():
		return _fail("register_system_info needs a SystemInfo carrying a systemid")
	info.systemid = SystemIds.canonical(info.systemid)
	var err := SystemInfo.register_mod_info(info, id)
	if not err.is_empty():
		return _fail("descriptor %s: %s" % [info.systemid, err])
	_note("platform", "%s descriptor" % info.systemid)
	return true


# ── whole platforms ───────────────────────────────────────────────────────────

## Everything a genuinely new platform needs, in one call.
##
## The separate calls all exist, but a platform registered with four of the six
## pieces fails much later and far from the cause — no remap diagram, or carts
## that never get art — so this reports what is missing at registration time.
##
## Keys: systemid, system_info, models, pad_art, media, scraper_id.
func register_platform(spec: Dictionary) -> bool:
	var systemid := SystemIds.canonical(str(spec.get("systemid", "")))
	if systemid.is_empty():
		return _fail("register_platform needs a systemid")
	var missing := PackedStringArray()
	# A piece that is PRESENT and refused is a different failure from one that
	# was never supplied, and this used to discard every sub-call's answer — so
	# a platform whose pad art was rejected outright still reported success and
	# was noted as registered.
	var ok := true
	if spec.has("system_info"):
		ok = register_system_info(spec["system_info"] as SystemInfo) and ok
	else:
		missing.append("system_info")
	if spec.has("models"):
		for row: Variant in (spec["models"] as Array):
			ok = register_model(row as Dictionary) and ok
	else:
		missing.append("models")
	if spec.has("pad_art"):
		ok = register_pad_art(systemid, spec["pad_art"] as Dictionary) and ok
	else:
		missing.append("pad_art (no Controls remap diagram)")
	if spec.has("media"):
		ok = register_media(systemid, spec["media"] as Dictionary) and ok
	else:
		missing.append("media (carts come out the wrong size)")
	if spec.has("scraper_id"):
		ok = register_scraper_system(systemid, int(spec["scraper_id"])) and ok
	else:
		missing.append("scraper_id (carts never get art)")
	if not missing.is_empty():
		_warn("platform %s is incomplete: %s" % [systemid, ", ".join(missing)])
	if not ok:
		return false
	_note("platform", systemid)
	return true


## The pad drawing behind this platform's Controls remap page.
func register_pad_art(systemid: String, row: Dictionary) -> bool:
	systemid = SystemIds.canonical(systemid)
	var err := ConsolePadArt.register_mod_row(systemid, row, id)
	if not err.is_empty():
		return _fail("pad art %s: %s" % [systemid, err])
	_note("platform", "%s pad art" % systemid)
	return true


## Cartridge and disc sizing. Without it a platform's carts come out the wrong
## size, and its discs do not exist at all.
func register_media(systemid: String, dims: Dictionary) -> bool:
	systemid = SystemIds.canonical(systemid)
	var err := MediaDimensions.register_mod_media(systemid, dims, id)
	if not err.is_empty():
		return _fail("media %s: %s" % [systemid, err])
	_note("media", systemid)
	return true


## The cartridge shells for a system, and which one a ROM wears.
##
## `row` is {bodies, choose, palette, uv_label}:
##
##   bodies    [{id, label, model, size}]: each shape a cartridge can be. `id` is
##             namespaced and is saved with a cartridge the player forced it on;
##             `size` is the model's true bounds in metres (the fit is per axis,
##             so never round it). The first is what a ROM gets when nothing
##             chooses.
##   choose    func(info) -> {body, preset}: this ROM's body id and shell colour.
##             `info` is {systemid, rom_path, file, region, market}. Optional,
##             and either key may be left out. It must be a STATIC function: the
##             mod's entry object is not kept after register().
##   tint      the names of the bodies' materials that are shell plastic. Those
##             are what a colour is painted on; with none the models keep their
##             own materials and the spawn menu offers no colours for them.
##   palette   a CartridgeShellPalette resource of shell colours, the swatches
##             beside the colour mixer. Needs `tint`.
##   uv_label  the bodies' label mesh is UV-mapped as the sticker itself.
##
## It replaces the game's own shells for that system, all of them, and one mod
## holds a system: a second is told who has it and is not used.
func register_cart_shell(systemid: String, row: Dictionary) -> bool:
	systemid = SystemIds.canonical(systemid)
	var holder := ModCartShells.owner_of(systemid)
	if not holder.is_empty() and holder != id:
		_warn("%s cartridge shells already come from mod '%s'; this mod's are not used"
			% [systemid, holder])
		return false
	var err := ModCartShells.register(systemid, row, id)
	if not err.is_empty():
		return _fail("cartridge shell %s: %s" % [systemid, err])
	_note("media", "%s cartridge shells (%d)" % [systemid, ModCartShells.bodies(systemid).size()])
	return true


## Map this platform to a screenscraper.fr system id so its ROMs can be scraped
## at all. A platform absent from that table gets no art, ever.
func register_scraper_system(systemid: String, systemeid: int) -> bool:
	systemid = SystemIds.canonical(systemid)
	var err := ScreenscraperSystems.register_mod_system(systemid, systemeid, id)
	if not err.is_empty():
		return _fail("scraper %s: %s" % [systemid, err])
	_note("scraper", "%s to %d" % [systemid, systemeid])
	return true


# ── rooms, props, cabinets ────────────────────────────────────────────────────

## Add a room reachable from the SCENE tab.
## Keys: id, path, title, menu_title, has_slots, thumbnail (a 16:9 picture for
## its card, shown until the player saves a slot of their own there).
func register_room(spec: Dictionary) -> bool:
	var room_id := str(spec.get("id", ""))
	if not _namespaced(room_id, "room id"):
		return false
	var err := RoomCatalog.register_mod_room(room_id, spec, id)
	if not err.is_empty():
		return _fail("room %s: %s" % [room_id, err])
	_note("room", str(spec.get("menu_title", room_id)))
	return true


## Add a spawnable prop. `type` is the persistence key written into save slots,
## so it must be namespaced and must never change once players have used it.
func register_object(type: String, scene_path: String, menu: Dictionary = {}) -> bool:
	if not _namespaced(type, "object type"):
		return false
	var err := ScenePersistence.register_mod_object(type, scene_path, id)
	if not err.is_empty():
		return _fail("object %s: %s" % [type, err])
	if not menu.is_empty():
		var menu_err := SpawnCatalog.register_mod_spawnable(type, menu, id)
		if not menu_err.is_empty():
			return _fail("object %s: %s" % [type, menu_err])
	_note("object", str(menu.get("label", type)))
	return true


## Add a television cabinet, spawned by the existing "tv:<shell>" token.
func register_tv_shell(shell_id: String, scene_path: String, label: String) -> bool:
	if not _namespaced(shell_id, "tv shell id"):
		return false
	var err := RetroTV.register_mod_shell(shell_id, scene_path, label, id)
	if not err.is_empty():
		return _fail("tv shell %s: %s" % [shell_id, err])
	_note("tv_shell", label)
	return true


## Add a console stand: a thing a console is mounted in, which decides how it
## stands (StandCatalog's row format: `fits`, `face`, `seat`, `parts`, and an
## optional `scene` for its look). Spawned as "console_stand:<stand_id>" and
## offered on the card of every console it fits.
func register_console_stand(stand_id: String, row: Dictionary) -> bool:
	if not _namespaced(stand_id, "console stand id"):
		return false
	var err := StandCatalog.register_mod_stand(stand_id, row, id)
	if not err.is_empty():
		return _fail("console stand %s: %s" % [stand_id, err])
	_note("object", str(row.get("label", stand_id)))
	return true


## Change one of the game's own console stands in place -- give a primitive
## stand-in its real model. `changes` is merged over the shipped row (any of
## `scene`, `seat`, `seat_rotation_deg`, `parts`, `label`, `fits`, `face`, ...),
## and the stand keeps its id, so every save that names it gets the new one.
func override_console_stand(stand_id: String, changes: Dictionary) -> bool:
	var err := StandCatalog.override_stand(stand_id, changes, id)
	if not err.is_empty():
		return _fail("console stand %s: %s" % [stand_id, err])
	_note("object", StandCatalog.label_of(stand_id))
	return true


## Add rows to a console's spawn card — its pads, leads and accessories.
##
## A mod controller is simply a scene rooted at RetroController; persistence
## already records and restores its scene path, and falls back to the generic pad
## when the mod is gone, with no help needed from here.
func add_peripherals(systemid: String, items: Array) -> bool:
	systemid = SystemIds.canonical(systemid)
	var err := SpawnCatalog.register_mod_peripherals(systemid, items, id)
	if not err.is_empty():
		return _fail("peripherals %s: %s" % [systemid, err])
	for item: Variant in items:
		_note("controller", str((item as Dictionary).get("label", "?")))
	return true


## Offer colors for a row this mod does not own: something of the game's that
## the mod only dresses (the N64 controller, the Wii Remote), named by the spawn
## token its row has on the card. The row can then be held to pick one, as a
## console's row with `variants` can, and what it spawns is given the id picked
## before it enters the room: SystemModelRegistry.variant_of(node) reads it, in
## the hook that dresses the thing and after a load alike.
##
## `variants` is [{id, label, color}], the first the thing as it comes. A row
## this mod ADDS lists them on its own item instead (add_peripherals).
func offer_variants(spawn: String, variants: Array) -> bool:
	var err := SpawnCatalog.register_mod_row_variants(spawn, variants, id)
	if not err.is_empty():
		return _fail("variants %s: %s" % [spawn, err])
	_note("variants", "%s (%d)" % [spawn, variants.size()])
	return true


## offer_variants for one card's row alone, when its token is shared by rows that
## spawn different things: every console's "Memory Card" row spawns
## "memory_card", the card of that console's own family, so a PlayStation 2
## card's colors are offered with `systemid` "ps2" and appear on that page only.
func offer_variants_on(systemid: String, spawn: String, variants: Array) -> bool:
	var err := SpawnCatalog.register_mod_row_variants(spawn, variants, id, systemid)
	if not err.is_empty():
		return _fail("variants %s on %s: %s" % [spawn, systemid, err])
	_note("variants", "%s on %s (%d)" % [spawn, systemid, variants.size()])
	return true


# ── services ──────────────────────────────────────────────────────────────────

## A built-in display shader by name — "crt", "vcr", "static", "window",
## "gameboy_lcd", "vb_stereo", "phosphor_decay", "screen_pixel_aa".
##
## Only needed by a mod that wants one DELIBERATELY. A TV shell that returns null
## from screen_shader() already gets the stock CRT material.
func shader(shader_name: String) -> Shader:
	return ModShaders.get_shader(shader_name)


## Call `cb(node)` for every node of class `cls` added from now on — the way to
## decorate a RetroSystem, a RetroTV or any pickable without editing it.
func on_node_added(cls: StringName, cb: Callable) -> void:
	_hooks.watch_nodes(id, cls, cb)
	_note("hook", "watches %s" % cls)


## on_node_added for a mod that DRESSES a shipped object -- hides its stand-in
## mesh and hangs a real shell on it -- which only one mod can do to one thing.
##
## `key` says which of that class's objects: a memory card's family
## ("playstation2"), a pad's systemid. The first mod to ask gets it (mods
## register in priority order) and `cb` is called for every node of `cls`, as
## with on_node_added; a later mod is told who has it, on its page in the Mods
## tab, and its callback is never connected. Returns whether this mod got it.
func dress(cls: StringName, key: String, cb: Callable) -> bool:
	var holder := _hooks.claim_dress(id, cls, key)
	if not holder.is_empty():
		_warn("%s (%s) is already dressed by mod '%s'; this mod's is not used"
			% [cls, key, holder])
		return false
	_hooks.watch_nodes(id, cls, cb)
	_note("hook", "dresses %s (%s)" % [cls, key])
	return true


## Call `cb(scene_id)` once a room has finished restoring its saved contents —
## the right moment to add something to a finished room.
func on_scene_content_ready(cb: Callable) -> void:
	var sm := _scene_manager()
	if sm == null:
		_warn("on_scene_content_ready: SceneManager is not available")
		return
	sm.scene_content_ready.connect(cb)
	# Kept, so withdraw() can take it back: a mod unloaded live (switched off,
	# removed, or updated) would otherwise go on being told about every room.
	_room_callbacks.append(cb)
	_note("hook", "waits for a room")


func _scene_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("SceneManager") if loop != null else null


## The player's mains region (a MainsRegions id, such as "na", "uk" or "jp"):
## which wall outlets the room has, so an AC adapter can wear the plug that fits.
func mains_region() -> String:
	return MainsRegions.resolve(AppPrefs.mains_region)


## Call `cb(region: String)` whenever the player changes the mains region.
func on_mains_region_changed(cb: Callable) -> void:
	var wrapper := func(region: String) -> void:
		cb.call(MainsRegions.resolve(region))
	AppPrefs.mains_region_changed.connect(wrapper)
	# Kept for withdraw(), as the room callbacks are.
	_mains_callbacks.append(wrapper)


## Offer a mains region of this mod's own on the OPTIONS dropdown, keyed and shaped
## like a MainsRegions.REGIONS entry. A shipped region of the same id is replaced.
func register_mains_region(region_id: String, spec: Dictionary) -> bool:
	var problem := Connectors.problem(region_id)
	if not problem.is_empty():
		return _fail("register_mains_region: " + problem)
	var entry := spec.duplicate(true)
	MainsRegions.extra[region_id] = entry
	_mains_regions[region_id] = entry
	_note("mains_regions", region_id)
	return true


## A writable folder of this mod's own, for settings. Use it with JsonStore.
func store() -> String:
	var dir := "user://mods/%s" % id
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func log_line(msg: String) -> void:
	print("[mod:%s] %s" % [id, msg])


# ── what this mod did ─────────────────────────────────────────────────────────

## kind -> Array[String], for the Mods page. Observed, not declared.
func contributions() -> Dictionary:
	return _record.duplicate(true)


func problems() -> PackedStringArray:
	# Socket lines are asked for, not stored: the lead that fits may come from a
	# mod that registers later, or be switched on later.
	var out := _problems.duplicate()
	out.append_array(SpawnCatalog.socket_problems_for(id))
	return out


## True when some contribution this mod tried to make was refused.
func failed() -> bool:
	return not _errors.is_empty()


func errors_text() -> String:
	return "; ".join(_errors)


## Take back everything this mod registered.
##
## The rollback the registries' own drop_mod docs describe — "only used when a
## mod fails part-way through register(), so a half-registered mod leaves
## nothing standing" — which until now nothing outside the tests called, so a
## mod that failed half way through kept the half that worked.
##
## Every table a mod can reach is named here rather than in mod_manager, so
## adding a register_* method and forgetting to make it withdrawable is one
## file's mistake instead of two.
func withdraw() -> void:
	var sm := _scene_manager()
	if sm != null:
		for cb: Callable in _room_callbacks:
			if sm.scene_content_ready.is_connected(cb):
				sm.scene_content_ready.disconnect(cb)
	_room_callbacks.clear()
	var unhooked := 0
	for wrapper: Callable in _mains_callbacks:
		if AppPrefs.mains_region_changed.is_connected(wrapper):
			AppPrefs.mains_region_changed.disconnect(wrapper)
			unhooked += 1
	_mains_callbacks.clear()
	var dropped := PackedStringArray()
	for region_id: String in _mains_regions:
		# A later mod that registered the same id owns it now: leave theirs.
		if MainsRegions.extra.has(region_id) 				and is_same(MainsRegions.extra[region_id], _mains_regions[region_id]):
			MainsRegions.extra.erase(region_id)
			dropped.append(region_id)
	_mains_regions.clear()
	if unhooked > 0 or not dropped.is_empty():
		print("[Mods] %s withdrew %d mains-region callback(s) and region(s) [%s]"
			% [id, unhooked, ", ".join(dropped)])
	SystemModelRegistry.drop_mod(id)
	SystemInfo.drop_mod(id)
	ConsolePadArt.drop_mod(id)
	MediaDimensions.drop_mod(id)
	ModCartShells.drop_mod(id)
	ExpansionCatalog.drop_mod(id)
	ScreenscraperSystems.drop_mod(id)
	RoomCatalog.drop_mod(id)
	SpawnCatalog.drop_mod(id)
	ScenePersistence.drop_mod_objects(id)
	RetroTV.drop_mod_shells(id)
	StandCatalog.drop_mod(id)
	_hooks.drop_owner(id)


## "2 consoles, 1 room, 4 props" — the one-line summary on a mod's list row.
func summary() -> String:
	var parts := PackedStringArray()
	for kind: String in KINDS:
		var n: int = (_record.get(kind, []) as Array).size()
		if n > 0:
			parts.append("%d %s" % [n, _plural(kind, n)])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


static func _plural(kind: String, n: int) -> String:
	var word: String = {
		"console": "console", "platform": "platform", "room": "room",
		"object": "prop", "tv_shell": "TV cabinet", "controller": "peripheral",
		"media": "media format", "scraper": "scraper mapping", "hook": "hook",
	}.get(kind, kind)
	return word if n == 1 else word + "s"


func _note(kind: String, label: String) -> void:
	if not _record.has(kind):
		_record[kind] = []
	(_record[kind] as Array).append(label)


func _fail(msg: String) -> bool:
	_problems.append(msg)
	_errors.append(msg)
	push_warning("[mod:%s] %s" % [id, msg])
	return false


func _warn(msg: String) -> void:
	_problems.append(msg)
	push_warning("[mod:%s] %s" % [id, msg])


## A model row's `sockets`, if it lists any, must each be spelled as a connector
## can be. Which names they are is the mod's business -- see Connectors.
func _sockets_ok(row: Dictionary, what: String) -> bool:
	if row.has("av_connector"):
		return _fail("%s: av_connector is gone; list the console's sockets in `sockets`" % what)
	var listed: Variant = row.get("sockets", [])
	if not (listed is Array):
		return _fail("%s: sockets must be an array of connector names" % what)
	for socket: Variant in listed:
		var err := Connectors.problem(str(socket))
		if not err.is_empty():
			return _fail("%s: %s" % [what, err])
	return true


## A mod-introduced id must carry its own mod's prefix.
## A mod written before the systemids were renamed names its platform the old
## way ("super_nes"). It is a file the player chose and nobody here can rewrite,
## so every systemid a mod hands over is read through SystemIds. A model row's
## OWN id is not one and is left alone.
func _current_platform(row: Dictionary) -> Dictionary:
	if not row.has("platform"):
		return row
	var out := row.duplicate()
	var platform: Variant = row["platform"]
	if platform is Array:
		var ids: Array = []
		for p: Variant in platform:
			ids.append(SystemIds.canonical(str(p)))
		out["platform"] = ids
	else:
		out["platform"] = SystemIds.canonical(str(platform))
	return out


func _namespaced(value: String, what: String) -> bool:
	if value.begins_with(id + ":") and value.length() > id.length() + 1:
		return true
	_fail("%s '%s' must be named '%s:something'" % [what, value, id])
	return false
