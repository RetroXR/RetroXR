## DataRootMigration — moves the player's data folder from one place to another.
##
## It holds their ROM library, so it is written to lose nothing: a file is moved
## by rename when both ends share a volume, else copied, size-checked, and only
## then deleted from the source. A file already present at the destination is left
## alone and its source kept, never overwritten. The work is a list of single-file
## steps so a caller can show progress between them, and it can be run again after
## an interruption: finished files are gone from the source, the rest still move.
class_name DataRootMigration
extends RefCounted

const MOVED := "moved"
const SKIPPED := "skipped"
const FAILED := "failed"


## Existence check for the confirmation dialog; don't enumerate a whole library
## just to decide whether to offer to move it.
static func has_files(root: String) -> bool:
	var dir := DirAccess.open(root)
	if dir == null:
		return false
	dir.include_hidden = true
	if not dir.get_files().is_empty():
		return true
	for d: String in dir.get_directories():
		if has_files(root.path_join(d)):
			return true
	return false


## Whether moving `from` to `to` is sane. Returns "" when ok, else the reason.
static func check(from: String, to: String) -> String:
	var a := DataPaths.normalize(from)
	var b := DataPaths.normalize(to)
	if a.is_empty() or b.is_empty():
		return "Missing folder."
	if a == b:
		return "That is the folder already in use."
	if b.begins_with(a + "/"):
		return "The new folder cannot be inside the old one."
	if a.begins_with(b + "/"):
		return "The old folder cannot be inside the new one."
	return ""


## Every file under `root`, as paths relative to it, in a stable order.
static func list_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	_collect(DataPaths.normalize(root), "", out)
	out.sort()
	return out


static func _collect(root: String, rel: String, out: PackedStringArray) -> void:
	var dir_path := root if rel.is_empty() else root + "/" + rel
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = true
	for f: String in dir.get_files():
		out.append(f if rel.is_empty() else rel + "/" + f)
	for d: String in dir.get_directories():
		_collect(root, d if rel.is_empty() else rel + "/" + d, out)


## Move one file. Returns MOVED, SKIPPED (destination exists) or FAILED.
static func move_one(from: String, to: String, rel: String) -> String:
	var src := DataPaths.normalize(from) + "/" + rel
	var dst := DataPaths.normalize(to) + "/" + rel
	if FileAccess.file_exists(dst):
		return SKIPPED
	if DirAccess.make_dir_recursive_absolute(dst.get_base_dir()) != OK \
			and not DirAccess.dir_exists_absolute(dst.get_base_dir()):
		return FAILED
	if DirAccess.rename_absolute(src, dst) == OK:
		return MOVED
	if DirAccess.copy_absolute(src, dst) != OK:
		DirAccess.remove_absolute(dst)
		return FAILED
	# A copy only counts once the far end is the same size.
	var want := _size(src)
	if want < 0 or _size(dst) != want:
		DirAccess.remove_absolute(dst)
		return FAILED
	DirAccess.remove_absolute(src)
	return MOVED


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	return f.get_length()


## Remove directories under `root` that are now empty, deepest first, then `root`
## itself if it too is empty. Returns whether `root` is gone.
static func prune_empty(root: String) -> bool:
	var r := DataPaths.normalize(root)
	var dir := DirAccess.open(r)
	if dir == null:
		return true
	dir.include_hidden = true
	for d: String in dir.get_directories():
		prune_empty(r + "/" + d)
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		return DirAccess.remove_absolute(r) == OK
	return false


## Run the whole move without progress reporting: {moved, skipped, failed}.
static func run(from: String, to: String) -> Dictionary:
	var counts := {MOVED: 0, SKIPPED: 0, FAILED: 0}
	for rel: String in list_files(from):
		counts[move_one(from, to, rel)] += 1
	prune_empty(from)
	return counts
