## KavitaConfig — the Kavita server the Books tab reads from.
##
## Lives beside romm_config.json in the roms root, as RomM's does, so it survives
## an app reinstall on Android and is visible through the web file manager.
##
## Kavita signs a client in with an AUTH KEY (the user's dashboard, Preferences >
## Clients), sent as the `x-api-key` header. The OPDS URL Kavita shows on the same
## page ends in that key, so pasting the whole OPDS URL fills in both the server
## and the key (`apply_opds_url`). No password is ever asked for or kept: a leaked
## key can be revoked from the server, a leaked password cannot.
class_name KavitaConfig
extends RefCounted


## Server base URL, no trailing slash — e.g. "https://kavita.example.com".
var base_url: String = ""
var auth_key: String = ""
var enabled: bool = false
## Disk the books downloaded from Kavita may take; the least recently used go
## first past it (KavitaCache). Streamed pages are not counted.
var cache_budget_gb: float = 5.0


## True when there is enough configured to attempt a request.
func is_configured() -> bool:
	return enabled and not base_url.is_empty() and not auth_key.is_empty()


## False when the server is plain http, so the panel can say the key crosses the
## network unprotected. An empty URL is not a complaint.
func is_encrypted() -> bool:
	return base_url.is_empty() or base_url.begins_with("https://")


## Headers for any /api/** request. Empty when there is no key.
func cache_budget_bytes() -> int:
	return int(cache_budget_gb * 1024.0 * 1024.0 * 1024.0)


func auth_headers() -> PackedStringArray:
	if auth_key.is_empty():
		return PackedStringArray()
	return PackedStringArray(["x-api-key: " + auth_key])


## Normalise what the player typed: RomM's rule (https for a bare host, no
## trailing slash), and a pasted OPDS URL cut back to the server it names.
static func normalize_url(raw: String) -> String:
	var parsed := parse_opds_url(raw)
	if not parsed.is_empty():
		return str(parsed["base_url"])
	return RommConfig.normalize_url(raw)


## {base_url, auth_key} from an OPDS URL (`<server>/api/opds/<key>[/...]`), or {}
## when `raw` is not one. Kavita may sit under a sub-path (`/kavita/api/opds/…`),
## so everything before `/api/opds/` is the server.
static func parse_opds_url(raw: String) -> Dictionary:
	var url := raw.strip_edges()
	var at := url.to_lower().find("/api/opds/")
	if at < 0:
		return {}
	var key := url.substr(at + "/api/opds/".length()).get_slice("/", 0).get_slice("?", 0)
	if key.is_empty():
		return {}
	var base := RommConfig.normalize_url(url.left(at))
	if base.is_empty():
		return {}
	return {"base_url": base, "auth_key": key}


## Take the server and key out of a pasted OPDS URL. False when it is not one.
func apply_opds_url(raw: String) -> bool:
	var parsed := parse_opds_url(raw)
	if parsed.is_empty():
		return false
	base_url = str(parsed["base_url"])
	auth_key = str(parsed["auth_key"])
	print("[KavitaConfig] OPDS URL read: server=%s, key of %d chars" % [base_url, auth_key.length()])
	return true


func load_config() -> void:
	# parse_dict, as RommConfig: a file that cannot be read leaves every field
	# standing, rather than quietly resetting a stored key.
	var raw: Variant = JsonStore.parse_dict(config_path(), "KavitaConfig")
	if raw == null:
		_adopt_old_browser_config()
		return
	var data: Dictionary = raw
	base_url = normalize_url(JsonStore.get_string(data, "base_url", ""))
	auth_key = JsonStore.get_string(data, "auth_key", "").strip_edges()
	enabled = JsonStore.get_bool(data, "enabled", false)
	cache_budget_gb = maxf(JsonStore.get_float(data, "cache_budget_gb", 5.0), 0.1)
	print("[KavitaConfig] Loaded config (server=%s enabled=%s key=%s)"
		% [base_url, enabled, "set" if not auth_key.is_empty() else "none"])


func save_config() -> bool:
	var path := config_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return JsonStore.write_dict(path, {
		"base_url": base_url,
		"auth_key": auth_key,
		"enabled": enabled,
		"cache_budget_gb": cache_budget_gb,
	}, "KavitaConfig")


## The Books tab's first Kavita browser kept a server URL and username in
## user://kavita.cfg. The URL carries over; the username means nothing to a key.
func _adopt_old_browser_config() -> void:
	const OLD := "user://kavita.cfg"
	if not FileAccess.file_exists(OLD):
		return
	var cfg := ConfigFile.new()
	if cfg.load(OLD) != OK:
		return
	base_url = normalize_url(str(cfg.get_value("connection", "url", "")))
	print("[KavitaConfig] adopted the server URL from %s: %s" % [OLD, base_url])


static func config_path() -> String:
	return RomLibrary.default_roms_root().path_join("kavita_config.json")
