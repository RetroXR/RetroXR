## ModUids — the resource UIDs a mounted mod pack carries, made known.
##
## A scene a mod ships names its textures, and anything else it loads, by UID
## first and by path second. The game learns UIDs from res://.godot/uid_cache.bin,
## which a pack may never carry (it would replace the game's own: see
## ModManifest.FORBIDDEN), so every one of a mod's UIDs was unknown and each load
## logged "invalid UID ... using text path instead" before falling back to the
## path. Harmless, but one warning per texture per load, and noise that buried
## real ones.
##
## The pack does carry what the cache would have said: each imported file's
## .import names its UID ([remap] uid), and each script or shader beside its .uid
## file. Read after the pack is mounted and handed to ResourceUID, the UIDs
## resolve and the warnings stop. A UID the game already knows is left alone.
class_name ModUids
extends RefCounted


## Register the UIDs under a mounted mod's own folder, res://mods/<mod_id>/.
## Returns how many were added.
static func register(mod_id: String) -> int:
	return register_dir("res://mods/%s" % mod_id)


## Register the UIDs recorded under `root`: every *.import's [remap] uid for the
## file it imports, and every *.uid for the file it sits beside. Returns how many
## were added.
static func register_dir(root: String) -> int:
	var added := 0
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := root.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				added += register_dir(path)
		elif entry.ends_with(".import"):
			var cfg := ConfigFile.new()
			if cfg.load(path) == OK:
				added += _add(str(cfg.get_value("remap", "uid", "")), path.trim_suffix(".import"))
		elif entry.ends_with(".uid"):
			added += _add(FileAccess.get_file_as_string(path).strip_edges(), path.trim_suffix(".uid"))
		entry = dir.get_next()
	dir.list_dir_end()
	return added


static func _add(text: String, resource_path: String) -> int:
	if not text.begins_with("uid://"):
		return 0
	var id := ResourceUID.text_to_id(text)
	if id == ResourceUID.INVALID_ID or ResourceUID.has_id(id):
		return 0
	ResourceUID.add_id(id, resource_path)
	return 1
