## KavitaCache: the books downloaded from Kavita, kept under a size budget.
##
## Each server and key has its own folder (user://kavita_cache/<md5>/), and in it
## a `used.json` of when each book was last downloaded or opened. Over the budget,
## the least recently used go first. A book open in the room is never removed,
## nor the one just fetched, and only files in that folder are ever touched.
class_name KavitaCache
extends RefCounted


const ROOT := "user://kavita_cache"
const USED_FILE := "used.json"


static func dir_for(config: KavitaConfig) -> String:
	return ROOT.path_join((config.base_url + "\n" + config.auth_key).md5_text())


## Mark a book as just used, so it is the last to go.
static func touch(path: String) -> void:
	var dir := path.get_base_dir()
	var used := _read_used(dir)
	used[path.get_file()] = Time.get_unix_time_from_system()
	JsonStore.write_dict(dir.path_join(USED_FILE), used, "KavitaCache")


## Bytes the downloaded books take, over every server's folder.
static func usage_bytes() -> int:
	var total := 0
	for sub: String in DirAccess.get_directories_at(ROOT):
		for f: String in _books_in(ROOT.path_join(sub)):
			total += _size_of(ROOT.path_join(sub).path_join(f))
	return total


## Remove the least recently used books in `dir` until it fits `budget_bytes`.
## `keep` are file paths never removed (open books, the one just fetched).
## Returns how many went.
static func evict(dir: String, budget_bytes: int, keep: PackedStringArray) -> int:
	var books := _books_in(dir)
	var used := _read_used(dir)
	var total := 0
	for f: String in books:
		total += _size_of(dir.path_join(f))
	if total <= budget_bytes:
		return 0
	# Oldest first; a book with no record (from before the record) counts as oldest.
	books.sort_custom(func(a: String, b: String) -> bool:
		return float(used.get(a, 0.0)) < float(used.get(b, 0.0)))
	var removed := 0
	for f: String in books:
		if total <= budget_bytes:
			break
		var path := dir.path_join(f)
		if keep.has(path) or keep.has(ProjectSettings.globalize_path(path)):
			continue
		var size := _size_of(path)
		if DirAccess.remove_absolute(path) == OK:
			total -= size
			removed += 1
			used.erase(f)
			print("[KavitaCache] removed %s (%s), least recently used" % [f, ByteSize.human(size)])
	JsonStore.write_dict(dir.path_join(USED_FILE), used, "KavitaCache")
	if total > budget_bytes:
		print("[KavitaCache] still %s over the budget: the rest are open in the room" % ByteSize.human(total - budget_bytes))
	return removed


## Every book file in the folder: not the record, not a partial download.
static func _books_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f == USED_FILE or f.ends_with(".part") or f.ends_with(".page") or f.ends_with(".tmp"):
			continue
		out.append(f)
	return out


static func _read_used(dir: String) -> Dictionary:
	return JsonStore.read_dict(dir.path_join(USED_FILE), "KavitaCache")


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0
