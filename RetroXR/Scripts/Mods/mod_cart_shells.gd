## ModCartShells — the cartridge shells a mod brings for a system.
##
## The game picks a cartridge's body and colour from its game and region for the
## systems it models (N64CartShell, SnesCartShell, GbcCartShell ...), and every one
## of those answers here too, in the table of the game's own shells below
## (`_builtin`). This is the same decision handed to a mod: it lists the bodies it
## has, optionally a palette of shell colours, and a function that says which a
## given ROM came in. RetroCartridge asks body_model() / shell_finish() /
## dress_body(), and a mod's row for a system answers before the game's own.
##
## Everything the game does for its own shells then happens to the mod's: the body
## is fitted to its true size, warmed before it is spawned, wears the scraped
## label, is offered on the spawn menu's hold options, and a body or colour the
## player forces is saved with the cartridge.
##
## Only one mod can hold a system with register(). ModApi turns a second mod
## away, because the game cannot use two answers to the question of which shell a
## ROM wears.
##
## Other mods can still add bodies to a system with add_bodies(). The Game Boy
## already works this way. Its Color and Camera bodies sit next to its own. An
## added row's function claims the ROMs that came in its bodies and returns
## nothing for the others. Those ROMs keep the body they would have had without
## the mod. The row's palette and tint apply only to its own bodies.
class_name ModCartShells
extends RefCounted

## systemid -> {owner, bodies: Array[Dictionary], palette, choose: Callable,
## uv_label: bool, tint: Array[StringName]}. A body is {id, label, model, size}.
static var _shells: Dictionary = {}
## "systemid|rom_path" -> what the mod's function answered. It may open the ROM
## to read its header, and a cartridge asks for its body on every drop.
static var _choices: Dictionary = {}
## This holds the rows that mods have added. Its keys are systemids, and each list
## keeps its rows in the order they arrived. Each mod has at most one row per
## system. A row has the same keys as a _shells entry.
static var _added: Dictionary = {}
## This caches the answers from added rows' functions. Its keys are
## "owner|systemid|rom_path".
static var _added_choices: Dictionary = {}

## The Body row offers this id as its Standard button on a system that has only
## one body of its own. When the player forces it, added_model asks no added row.
## RetroCartridge.body_model_for then treats it as Auto.
const STANDARD_BODY := "standard"
## This character joins a row's owner and systemid into its palette key. No
## systemid contains it.
const _KEY_JOIN := "@"

## The game's own shells, by systemid, filled on first use. Each entry holds the
## class's answers as Callables, any of them absent:
##   body(systemid, rom_path, body_region, shell_preset, pinned) -> String
##   finish(systemid, rom_path, model_path, pinned) -> {palette, preset}
##   dress(body, systemid, rom_path, model_path, pinned)
##   rom_market(systemid, rom_path) -> String   (the shell picks by market)
## A system with no body answer wears RetroCartridge's one model for it.
static var _builtin: Dictionary = {}
## Entry key -> the static function a built-in shell class answers it with.
const _BUILTIN_METHODS := {"body": &"cart_body", "finish": &"cart_finish",
	"dress": &"cart_dress", "rom_market": &"rom_market"}


## "" on success, else why the row was refused.
static func register(systemid: String, row: Dictionary, owner_id: String) -> String:
	if systemid.is_empty():
		return "no systemid"
	var parsed := _parse(row, owner_id)
	if parsed.has("error"):
		return str(parsed["error"])
	_shells[systemid] = parsed["entry"]
	_choices.clear()
	return ""


## This adds a mod's bodies to a system next to the system's own shells. If the
## mod already added a row for this system, the new row replaces it. It returns ""
## on success and the reason otherwise.
static func add_bodies(systemid: String, row: Dictionary, owner_id: String) -> String:
	if systemid.is_empty():
		return "no systemid"
	var parsed := _parse(row, owner_id)
	if parsed.has("error"):
		return str(parsed["error"])
	var rows: Array = _added.get(systemid, [])
	var kept: Array = rows.filter(func(r: Dictionary) -> bool: return r["owner"] != owner_id)
	kept.append(parsed["entry"])
	_added[systemid] = kept
	_added_choices.clear()
	return ""


## This checks a row. It returns {entry} when the row is good and {error} when it
## is not.
static func _parse(row: Dictionary, owner_id: String) -> Dictionary:
	var listed: Variant = row.get("bodies", [])
	if not (listed is Array) or (listed as Array).is_empty():
		return {"error": "no bodies given"}
	var accepted: Array = []
	var seen := {}
	for entry: Variant in (listed as Array):
		if not (entry is Dictionary):
			return {"error": "a body must be a dictionary"}
		var body := (entry as Dictionary).duplicate(true)
		var body_id := str(body.get("id", ""))
		# Written into save files as the cartridge's forced body.
		if not body_id.begins_with(owner_id + ":") or body_id.length() <= owner_id.length() + 1:
			return {"error": "body id '%s' must be namespaced '%s:<name>'" % [body_id, owner_id]}
		if seen.has(body_id):
			return {"error": "body id '%s' is listed twice" % body_id}
		seen[body_id] = true
		var model := str(body.get("model", ""))
		if model.is_empty() or not ResourceLoader.exists(model):
			return {"error": "body '%s': model does not exist: %s" % [body_id, model]}
		if not (body.get("size") is Vector3):
			return {"error": "body '%s': size must be a Vector3, in metres" % body_id}
		var size: Vector3 = body["size"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return {"error": "body '%s': size must be positive on every axis" % body_id}
		body["label"] = str(body.get("label", body_id.get_slice(":", 1)))
		accepted.append(body)

	var palette: CartridgeShellPalette = null
	var palette_path := str(row.get("palette", ""))
	if not palette_path.is_empty():
		if not ResourceLoader.exists(palette_path):
			return {"error": "palette does not exist: %s" % palette_path}
		palette = load(palette_path) as CartridgeShellPalette
		if palette == null:
			return {"error": "palette is not a CartridgeShellPalette: %s" % palette_path}

	var choose: Variant = row.get("choose", Callable())
	if not (choose is Callable):
		return {"error": "choose must be a function"}

	var named: Variant = row.get("tint", [])
	if not (named is Array):
		return {"error": "tint must be a list of material names"}
	var tint: Array[StringName] = []
	for material_name: Variant in (named as Array):
		if str(material_name).is_empty():
			return {"error": "tint has an empty material name"}
		tint.append(StringName(str(material_name)))
	# Colours with nothing to put them on would be swatches that do nothing.
	if palette != null and tint.is_empty():
		return {"error": "a palette needs tint: the names of the materials it colours"}

	return {"entry": {"owner": owner_id, "bodies": accepted, "palette": palette,
		"choose": choose, "uv_label": bool(row.get("uv_label", false)), "tint": tint}}


static func has(systemid: String) -> bool:
	return _shells.has(systemid)


## The mod that brings this system's shells, or "".
static func owner_of(systemid: String) -> String:
	return str((_shells.get(systemid, {}) as Dictionary).get("owner", ""))


## [{id, label, model, size}], the first being the one a ROM gets when nothing
## chooses.
static func bodies(systemid: String) -> Array:
	return ((_shells.get(systemid, {}) as Dictionary).get("bodies", []) as Array).duplicate(true)


## The mod's shell colours, or null when it brought none and its models wear
## their own materials.
static func palette_for(systemid: String) -> CartridgeShellPalette:
	return (_shells.get(systemid, {}) as Dictionary).get("palette") as CartridgeShellPalette


## Whether this system's mod shells can be coloured at all: the mod named the
## materials that are shell plastic. Without that nothing is painted and the
## spawn menu offers no colours for them.
static func tintable(systemid: String) -> bool:
	return not ((_shells.get(systemid, {}) as Dictionary).get("tint", []) as Array).is_empty()


## Whether some mod's shells name `material_name` as shell plastic. Asked by
## CartridgeColor for every surface it considers, beside the game's own names.
static func is_tint(material_name: StringName) -> bool:
	for systemid: String in _shells:
		if (_shells[systemid]["tint"] as Array).has(material_name):
			return true
	for systemid: String in _added:
		for row: Dictionary in (_added[systemid] as Array):
			if (row["tint"] as Array).has(material_name):
				return true
	return false


## Whether the bodies' label mesh is UV-mapped as the sticker itself.
static func uv_label(systemid: String) -> bool:
	return bool((_shells.get(systemid, {}) as Dictionary).get("uv_label", false))


## The model a cartridge wears: the body the player forced, else the one the
## mod's function picked for this ROM, else the first. "" with no mod shell.
static func model_for(systemid: String, rom_path: String, forced_body: String) -> String:
	if not _shells.has(systemid):
		return ""
	var forced := _body(systemid, forced_body)
	if not forced.is_empty():
		return str(forced["model"])
	var picked := _body(systemid, str(choice(systemid, rom_path).get("body", "")))
	if picked.is_empty():
		picked = (_shells[systemid]["bodies"] as Array)[0]
	return str(picked["model"])


## The shell colour this ROM came in, a preset id from the mod's palette, or &"".
static func preset_for(systemid: String, rom_path: String) -> StringName:
	return StringName(str(choice(systemid, rom_path).get("preset", "")))


## True size of the body that is `model`, or Vector3.ZERO when it is not one of
## this system's mod bodies. Added bodies count too.
static func size_of(systemid: String, model: String) -> Vector3:
	for body: Dictionary in ((_shells.get(systemid, {}) as Dictionary).get("bodies", []) as Array):
		if str(body["model"]) == model:
			return body["size"]
	var row := _added_row_of(systemid, model)
	if not row.is_empty():
		for body: Dictionary in (row["bodies"] as Array):
			if str(body["model"]) == model:
				return body["size"]
	return Vector3.ZERO


## The first body's size: what the system's cartridges are when nothing else
## says, for a system the game has no size for. Vector3.ZERO with no mod shell.
static func default_size(systemid: String) -> Vector3:
	var listed: Array = (_shells.get(systemid, {}) as Dictionary).get("bodies", [])
	return listed[0]["size"] if not listed.is_empty() else Vector3.ZERO


## What the mod's function says about this ROM: {body, preset}, either absent.
##
## It is handed what the game already knows -- the system, the ROM's path and
## file name, the region the scraper wrote, and the market that region (or, for
## an N64 ROM, its header) puts it in: "us", "eu", "au", "jp" or "". Anything
## else, a header title say, it reads from the ROM itself.
static func choice(systemid: String, rom_path: String) -> Dictionary:
	if not _shells.has(systemid):
		return {}
	var key := "%s|%s" % [systemid, rom_path]
	if _choices.has(key):
		return _choices[key]
	var answer := _ask(_shells[systemid]["choose"], systemid, rom_path)
	_choices[key] = answer
	return answer


## This asks a row's function about a ROM. It returns {} when the row has no
## function or the function says nothing.
static func _ask(choose: Callable, systemid: String, rom_path: String) -> Dictionary:
	if not choose.is_valid():
		return {}
	var region := N64CartShell.scraped_region(systemid, rom_path)
	var market := N64CartShell.market(systemid, rom_path) if systemid == "n64" \
		else N64CartShell.market_of_region(region)
	var said: Variant = choose.call({"systemid": systemid, "rom_path": rom_path,
		"file": rom_path.get_file(), "region": region, "market": market})
	return (said as Dictionary) if said is Dictionary else {}


# --- Bodies that mods add next to a system's own (add_bodies) ---

static func has_added(systemid: String) -> bool:
	return not (_added.get(systemid, []) as Array).is_empty()


## This returns every added body of the system in the order the mods added them.
## Each body is a dictionary with id, label, model and size.
static func added_bodies(systemid: String) -> Array:
	var out: Array = []
	for row: Dictionary in (_added.get(systemid, []) as Array):
		out.append_array((row["bodies"] as Array).duplicate(true))
	return out


## This returns true when at least one added row for the system names materials
## to colour.
static func added_tintable(systemid: String) -> bool:
	for row: Dictionary in (_added.get(systemid, []) as Array):
		if not (row["tint"] as Array).is_empty():
			return true
	return false


## This returns the model of the added body a cartridge wears. It returns "" when
## the cartridge wears none. An added body that the player forced comes first.
## When the body is left on Auto, the first added row whose function claims the
## ROM decides. When the player forced any other body, no added row is asked.
## STANDARD_BODY counts as one of those other bodies.
static func added_model(systemid: String, rom_path: String, forced_body: String) -> String:
	if not has_added(systemid):
		return ""
	if not forced_body.is_empty():
		for row: Dictionary in (_added[systemid] as Array):
			var forced := _row_body(row, forced_body)
			if not forced.is_empty():
				return str(forced["model"])
		return ""
	for row: Dictionary in (_added[systemid] as Array):
		var claimed := _row_body(row, str(_added_choice(row, systemid, rom_path).get("body", "")))
		if not claimed.is_empty():
			return str(claimed["model"])
	return ""


## This returns true when `model` is one of the system's added bodies.
static func is_added_body(systemid: String, model: String) -> bool:
	return not _added_row_of(systemid, model).is_empty()


## This returns the key that CartridgeColor.get_palette uses for a body's colours.
## An added body's key is made from its mod and its system. Every other body uses
## the systemid.
static func palette_key(systemid: String, model: String) -> String:
	var row := _added_row_of(systemid, model)
	return systemid if row.is_empty() else "%s%s%s" % [row["owner"], _KEY_JOIN, systemid]


## This returns true when `key` came from palette_key for an added body.
static func is_palette_key(key: String) -> bool:
	return key.contains(_KEY_JOIN)


## This returns the palette for an added body's key. It returns null when no added
## row has that key or the row brought no palette.
static func palette_by_key(key: String) -> CartridgeShellPalette:
	var owner := key.get_slice(_KEY_JOIN, 0)
	var systemid := key.get_slice(_KEY_JOIN, 1)
	for row: Dictionary in (_added.get(systemid, []) as Array):
		if row["owner"] == owner:
			return row["palette"] as CartridgeShellPalette
	return null


## This returns true when the label mesh of the body at `model` is UV-mapped as
## the sticker. An added body's row decides for its own bodies. For any other body
## the mod that holds the system decides. With no such mod the answer is
## `game_default`.
static func label_is_uv(systemid: String, model: String, game_default: bool) -> bool:
	var row := _added_row_of(systemid, model)
	if not row.is_empty():
		return bool(row["uv_label"])
	return uv_label(systemid) if has(systemid) else game_default


static func _added_row_of(systemid: String, model: String) -> Dictionary:
	if model.is_empty():
		return {}
	for row: Dictionary in (_added.get(systemid, []) as Array):
		for body: Dictionary in (row["bodies"] as Array):
			if str(body["model"]) == model:
				return row
	return {}


static func _added_choice(row: Dictionary, systemid: String, rom_path: String) -> Dictionary:
	var key := "%s|%s|%s" % [row["owner"], systemid, rom_path]
	if not _added_choices.has(key):
		_added_choices[key] = _ask(row["choose"], systemid, rom_path)
	return _added_choices[key]


static func _row_body(row: Dictionary, body_id: String) -> Dictionary:
	if body_id.is_empty():
		return {}
	for body: Dictionary in (row["bodies"] as Array):
		if str(body["id"]) == body_id:
			return body
	return {}


# --- One lookup, the mod's row first, then the game's own shell ---

## Whether a cartridge of this system has its body picked per ROM: a mod's shells,
## or one of the game's own that chooses (the N64's, the Super NES's, the Game Boy's).
static func picks_body(systemid: String) -> bool:
	return has(systemid) or (_builtins().get(systemid, {}) as Dictionary).has("body")


## The body a ROM's cartridge wears, when picks_body(): the mod's (model_for), else
## the game's own shell's. "" keeps the procedural box.
static func body_model(systemid: String, rom_path: String, body_region: String,
		shell_preset: StringName, pinned: String) -> String:
	if has(systemid):
		return model_for(systemid, rom_path, body_region)
	var entry: Dictionary = _builtins().get(systemid, {})
	if not entry.has("body"):
		return ""
	return str((entry["body"] as Callable).call(systemid, rom_path, body_region, shell_preset, pinned))


## {palette, preset}: which palette the body at `model_path` is painted from and the
## colour this ROM came in, or {} to leave the body its own materials -- a mod's
## shell that named no tint, or a system with no shell colours.
static func shell_finish(systemid: String, rom_path: String, model_path: String,
		pinned: String) -> Dictionary:
	# An added body uses its own row's palette and the colour its function gave the ROM.
	var row := _added_row_of(systemid, model_path)
	if not row.is_empty():
		if (row["tint"] as Array).is_empty():
			return {}
		return {"palette": palette_key(systemid, model_path),
			"preset": StringName(str(_added_choice(row, systemid, rom_path).get("preset", "")))}
	if has(systemid):
		if not tintable(systemid):
			return {}
		return {"palette": systemid, "preset": preset_for(systemid, rom_path)}
	var entry: Dictionary = _builtins().get(systemid, {})
	if not entry.has("finish"):
		return {}
	var said: Variant = (entry["finish"] as Callable).call(systemid, rom_path, model_path, pinned)
	return (said as Dictionary) if said is Dictionary else {}


## Whatever else the game's own shell puts on a fitted body (a PAL Super Famicom
## cartridge's rear sticker). A mod's body is left as its author made it.
static func dress_body(body: Node3D, systemid: String, rom_path: String, model_path: String,
		pinned: String) -> void:
	if has(systemid) or is_added_body(systemid, model_path):
		return
	var entry: Dictionary = _builtins().get(systemid, {})
	if entry.has("dress"):
		(entry["dress"] as Callable).call(body, systemid, rom_path, model_path, pinned)


## Whether the game's own shell for this system picks by market and this ROM names
## none, so the cartridge takes the player's (RetroCartridge.uses_fallback_market).
static func names_no_market(systemid: String, rom_path: String) -> bool:
	var entry: Dictionary = _builtins().get(systemid, {})
	if not entry.has("rom_market"):
		return false
	return str((entry["rom_market"] as Callable).call(systemid, rom_path)).is_empty()


## Enter one of the game's own shell classes for `systemids`, by the answers it
## gives (keys of _BUILTIN_METHODS). The class names them as static functions.
static func register_builtin(systemids: Array, shell: Script, answers: Array) -> void:
	var entry := {}
	for answer: Variant in answers:
		var key := str(answer)
		if not _BUILTIN_METHODS.has(key):
			push_error("[ModCartShells] unknown built-in shell answer '%s'" % key)
			continue
		entry[key] = Callable(shell, _BUILTIN_METHODS[key])
	for systemid: Variant in systemids:
		_builtin[str(systemid)] = entry


static func _builtins() -> Dictionary:
	if _builtin.is_empty():
		register_builtin([N64CartShell.SYSTEMID], N64CartShell, ["body", "finish", "rom_market"])
		register_builtin([SnesCartShell.SYSTEMID], SnesCartShell,
			["body", "finish", "dress", "rom_market"])
		register_builtin([NesCartShell.SYSTEMID], NesCartShell, ["finish", "rom_market"])
		register_builtin(GbCartShell.SYSTEMIDS, GbcCartShell, ["body", "finish"])
		register_builtin([GbaCartShell.SYSTEMID], GbaCartShell, ["finish"])
		register_builtin(FloppyShell.systemids(), FloppyShell, ["body"])
	return _builtin


static func drop_mod(owner_id: String) -> void:
	for systemid: String in _shells.keys():
		if _shells[systemid]["owner"] == owner_id:
			_shells.erase(systemid)
	for systemid: String in _added.keys():
		var kept: Array = (_added[systemid] as Array).filter(
			func(r: Dictionary) -> bool: return r["owner"] != owner_id)
		if kept.is_empty():
			_added.erase(systemid)
		else:
			_added[systemid] = kept
	_choices.clear()
	_added_choices.clear()


static func _body(systemid: String, body_id: String) -> Dictionary:
	if body_id.is_empty():
		return {}
	for body: Dictionary in (_shells[systemid]["bodies"] as Array):
		if str(body["id"]) == body_id:
			return body
	return {}
