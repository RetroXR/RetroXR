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
## One mod per system. A second is turned away at registration (ModApi), because
## two answers to "which shell does this ROM wear" cannot both be used.
class_name ModCartShells
extends RefCounted

## systemid -> {owner, bodies: Array[Dictionary], palette, choose: Callable,
## uv_label: bool, tint: Array[StringName]}. A body is {id, label, model, size}.
static var _shells: Dictionary = {}
## "systemid|rom_path" -> what the mod's function answered. It may open the ROM
## to read its header, and a cartridge asks for its body on every drop.
static var _choices: Dictionary = {}

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
	var listed: Variant = row.get("bodies", [])
	if not (listed is Array) or (listed as Array).is_empty():
		return "no bodies given"
	var accepted: Array = []
	var seen := {}
	for entry: Variant in (listed as Array):
		if not (entry is Dictionary):
			return "a body must be a dictionary"
		var body := (entry as Dictionary).duplicate(true)
		var body_id := str(body.get("id", ""))
		# Written into save files as the cartridge's forced body.
		if not body_id.begins_with(owner_id + ":") or body_id.length() <= owner_id.length() + 1:
			return "body id '%s' must be namespaced '%s:<name>'" % [body_id, owner_id]
		if seen.has(body_id):
			return "body id '%s' is listed twice" % body_id
		seen[body_id] = true
		var model := str(body.get("model", ""))
		if model.is_empty() or not ResourceLoader.exists(model):
			return "body '%s': model does not exist: %s" % [body_id, model]
		if not (body.get("size") is Vector3):
			return "body '%s': size must be a Vector3, in metres" % body_id
		var size: Vector3 = body["size"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return "body '%s': size must be positive on every axis" % body_id
		body["label"] = str(body.get("label", body_id.get_slice(":", 1)))
		accepted.append(body)

	var palette: CartridgeShellPalette = null
	var palette_path := str(row.get("palette", ""))
	if not palette_path.is_empty():
		if not ResourceLoader.exists(palette_path):
			return "palette does not exist: %s" % palette_path
		palette = load(palette_path) as CartridgeShellPalette
		if palette == null:
			return "palette is not a CartridgeShellPalette: %s" % palette_path

	var choose: Variant = row.get("choose", Callable())
	if not (choose is Callable):
		return "choose must be a function"

	var named: Variant = row.get("tint", [])
	if not (named is Array):
		return "tint must be a list of material names"
	var tint: Array[StringName] = []
	for material_name: Variant in (named as Array):
		if str(material_name).is_empty():
			return "tint has an empty material name"
		tint.append(StringName(str(material_name)))
	# Colours with nothing to put them on would be swatches that do nothing.
	if palette != null and tint.is_empty():
		return "a palette needs tint: the names of the materials it colours"

	_shells[systemid] = {"owner": owner_id, "bodies": accepted, "palette": palette,
		"choose": choose, "uv_label": bool(row.get("uv_label", false)), "tint": tint}
	_choices.clear()
	return ""


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
## this system's mod bodies.
static func size_of(systemid: String, model: String) -> Vector3:
	for body: Dictionary in ((_shells.get(systemid, {}) as Dictionary).get("bodies", []) as Array):
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
	var answer := {}
	var choose: Callable = _shells[systemid]["choose"]
	if choose.is_valid():
		var region := N64CartShell.scraped_region(systemid, rom_path)
		var market := N64CartShell.market(systemid, rom_path) if systemid == "n64" \
			else N64CartShell.market_of_region(region)
		var said: Variant = choose.call({"systemid": systemid, "rom_path": rom_path,
			"file": rom_path.get_file(), "region": region, "market": market})
		if said is Dictionary:
			answer = said
	_choices[key] = answer
	return answer


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
	if has(systemid):
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
	return _builtin


static func drop_mod(owner_id: String) -> void:
	for systemid: String in _shells.keys():
		if _shells[systemid]["owner"] == owner_id:
			_shells.erase(systemid)
	_choices.clear()


static func _body(systemid: String, body_id: String) -> Dictionary:
	if body_id.is_empty():
		return {}
	for body: Dictionary in (_shells[systemid]["bodies"] as Array):
		if str(body["id"]) == body_id:
			return body
	return {}
