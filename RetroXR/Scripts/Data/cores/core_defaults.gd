## CoreDefaults — persists the user-chosen default core per systemid.
##
## Schema of core_defaults.json:
##   { "defaults": { "nes": "fceumm", "snes": "snes9x", ... } }
##
## Usage:
##   var cd := CoreDefaults.new()
##   cd.setup(CoreDownloadManager.default_core_root().path_join("core_defaults.json"))
##   cd.set_default_core("nes", "fceumm")
##   cd.save()
class_name CoreDefaults
extends RefCounted

var _path:     String     = ""
var _defaults: Dictionary = {}   # systemid -> core_name


static func default_path() -> String:
	return CoreDownloadManager.default_core_root().path_join("core_defaults.json")


func setup(path: String) -> void:
	_path = path
	load_defaults()


## Returns the default core_name for a systemid, or "" if none set.
func get_default_core(systemid: String) -> String:
	return _defaults.get(systemid, "")


## Set which core is the default for a systemid. Call save() to persist.
func set_default_core(systemid: String, core_name: String) -> void:
	_defaults[systemid] = core_name


## Give every platform an installed core serves -- its own systemid and its
## secondaries -- a default core when it has none, the recommended one first.
## Returns the systemids that were given one. Does not save.
##
## The Cores panel does the same when its Manager grid is built, but that only
## runs when the panel is opened. A platform that appears later on cores that
## are already installed -- a new secondary_systemids entry, like gbc on the
## Game Boy cores -- had no default until then, so its tile was purple and a
## console spawned for it had nothing to boot.
func adopt_missing(core_db: CoreInfoDatabase, installed: PackedStringArray) -> Array[String]:
	var by_sid: Dictionary = {}
	for cn: String in installed:
		var info: Dictionary = core_db.get_by_core_name(cn)
		if info.is_empty():
			continue
		for sid: String in CoreInfoDatabase.systemids_of(info):
			if sid.is_empty():
				continue
			if not by_sid.has(sid):
				by_sid[sid] = []
			(by_sid[sid] as Array).append({"core_name": cn})
	var adopted: Array[String] = []
	for sid: String in by_sid:
		if not get_default_core(sid).is_empty():
			continue
		var ranked: Array = CoreRecommendations.first(sid, by_sid[sid] as Array)
		set_default_core(sid, str((ranked[0] as Dictionary)["core_name"]))
		adopted.append(sid)
	return adopted


## Returns a copy of the full defaults dict (systemid -> core_name).
func all_defaults() -> Dictionary:
	return _defaults.duplicate()


## False when the write did not land, like every other store here. A default
## core that did not reach disk is a machine that boots the wrong emulator on
## the next launch, so the caller is told rather than left to assume.
func save() -> bool:
	if _path.is_empty():
		push_error("CoreDefaults: no path set, call setup() first")
		return false
	return JsonStore.write_dict(_path, {"defaults": _defaults}, "CoreDefaults")


func load_defaults() -> void:
	if _path.is_empty():
		return
	var d: Variant = JsonStore.read_dict(_path, "CoreDefaults").get("defaults")
	if d is Dictionary:
		_defaults = SystemIds.rekeyed(d as Dictionary)
		# Ensure a roms/ folder exists for every configured system
		for sid: String in _defaults:
			RomLibrary.ensure_rom_dir(sid)
