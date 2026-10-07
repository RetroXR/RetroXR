## ModReviews — downloads that are fetched and vetted and wait for the player.
##
## A finished download is not installed. It is parked here until the player has
## seen what it replaces and said yes (the MODS tab's review), or no.
##
## Its `stage` is the downloader's install hook. It lives in the Modio autoload
## rather than in the menu because the hook must outlive the menu: a download
## that finishes with the menu gone still has to stop HERE. A hook that had died
## with the menu would fall back to installing the file unasked.
##
## Keyed by job key, "modio-<mod id>", the same key the downloader uses.
class_name ModReviews
extends RefCounted

## A download was parked, answered or thrown away.
signal changed()

## The loader that vets and installs. Null means the Mods autoload; set by
## mod_browser_tests to a scratch one.
var manager: Node = null

## job key -> {staged, source, manifest, thumbnail}.
var _parked: Dictionary = {}


static func job_key(mod_id: int) -> String:
	return "modio-%d" % mod_id


func _loader() -> Node:
	if manager != null:
		return manager
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Mods") if loop != null else null


## The downloader's install hook: func(staged, source) -> {ok, id, error, restart,
## review}. Vets the file as an install would, and parks it instead. A file that
## fails is deleted, with the loader's own sentence as the error. Main thread.
func stage(staged: String, source: Dictionary) -> Dictionary:
	var loader := _loader()
	if loader == null:
		DirAccess.remove_absolute(staged)
		return {"ok": false, "id": "", "error": "The mod loader is unavailable", "restart": false}
	var info: Dictionary = loader.vet(staged)
	if not str(info["error"]).is_empty():
		DirAccess.remove_absolute(str(info.get("path", staged)))
		DirAccess.remove_absolute(staged)
		return {"ok": false, "id": "", "error": str(info["error"]), "restart": false}
	var manifest: ModManifest = info["manifest"]
	var key := job_key(int(source.get("modio_id", 0)))
	# A second download of the same mod replaces the first's file, never joins it.
	discard(key)
	# `path` is the pack itself: the download, or the build picked out of a bundle.
	# `vetted` is the whole answer, kept so the install that follows a yes does
	# not have to ask it of the same file again.
	_parked[key] = {"staged": str(info["path"]), "source": source, "manifest": manifest,
		"thumbnail": info["thumbnail"], "vetted": info}
	changed.emit()
	return {"ok": true, "id": manifest.id, "error": "", "restart": false, "review": true}


func has(key: String) -> bool:
	return _parked.has(key)


## {staged, source, manifest, thumbnail}, or {} for nothing waiting.
func parked(key: String) -> Dictionary:
	return _parked.get(key, {})


func keys() -> Array:
	return _parked.keys()


## The player said yes. Installs the parked file under `source`, enabled for the
## next launch when asked. Returns what ModManager.install returned.
func finish(key: String, source: Dictionary, enable: bool) -> Dictionary:
	var loader := _loader()
	if not _parked.has(key) or loader == null:
		return {"ok": false, "id": "", "error": "Nothing to install", "restart": false}
	var entry: Dictionary = _parked[key]
	_parked.erase(key)
	# One write and one notice for the install and the switch together.
	loader.hold_changes()
	var out: Dictionary = loader.install(str(entry["staged"]), source, entry.get("vetted", {}))
	if bool(out.get("ok", false)) and enable:
		loader.set_enabled(str(out["id"]), true)
		out["restart"] = true
	loader.release_changes()
	changed.emit()
	return out


## The player said no. The file was fetched for this and is good for nothing else.
func discard(key: String) -> void:
	if not _parked.has(key):
		return
	DirAccess.remove_absolute(str((_parked[key] as Dictionary)["staged"]))
	_parked.erase(key)
	changed.emit()


func discard_all() -> void:
	for key: String in _parked.keys():
		discard(key)
