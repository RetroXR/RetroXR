## ModioConsent — whether the player has agreed to mod.io's terms on this device.
##
## mod.io's game terms ask a game to show its Terms of Use and Privacy Policy and
## collect the player's agreement "before using any mod.io functionality, such as
## on startup, or before launching any UGC browsers" (docs.mod.io/terms). That
## covers looking at the catalogue with the game's key, not only signing in, so
## ModioClient refuses every request but the terms themselves until this says yes.
##
## The agreement is to a TEXT. Its checksum is kept, so when mod.io changes the
## wording the player is asked again rather than held to words they never saw.
class_name ModioConsent
extends RefCounted

const STATE_PATH := "user://modio_consent.json"
const STATE_OWNER := "ModioConsent"

## Overridden by mod_browser_tests, which must not touch the player's own answer.
var state_path := STATE_PATH

var _loaded := false
var _agreed := false
var _terms_md5 := ""


func granted() -> bool:
	_load()
	return _agreed


## The player pressed the agree button under `terms_text`.
func grant(terms_text: String) -> void:
	_load()
	_agreed = true
	_terms_md5 = terms_text.md5_text()
	JsonStore.write_dict(state_path, {"agreed": true, "terms_md5": _terms_md5,
		"agreed_at": int(Time.get_unix_time_from_system())}, STATE_OWNER)


func withdraw() -> void:
	_loaded = true
	_agreed = false
	_terms_md5 = ""
	if FileAccess.file_exists(state_path):
		DirAccess.remove_absolute(state_path)


## True when `terms_text` is not what the player agreed to. An empty text is no
## evidence of a change: a failed fetch must not sign anybody out.
func terms_changed(terms_text: String) -> bool:
	_load()
	return _agreed and not terms_text.is_empty() and terms_text.md5_text() != _terms_md5


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(state_path):
		return
	var d := JsonStore.read_dict(state_path, STATE_OWNER)
	_agreed = d.get("agreed") is bool and bool(d["agreed"])
	_terms_md5 = str(d.get("terms_md5", ""))
