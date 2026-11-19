## AtomicFile — replace a file whole, or leave the one that is there alone.
##
## Writing in place means a process killed between open and the last byte —
## which on a Quest is ordinary app lifecycle — leaves the target truncated. For
## a memory card, a console's NVRAM or a save state that is not a stale save but
## a destroyed one, and for JSON it reads back as "never set".
##
## So every write goes to a staging file beside the target (`<path>.part` unless
## the caller names another), checks the open, the store AND the close-time
## error, and only then swaps it in. The swap is delete-then-rename: Godot's
## rename does not replace an existing file on every platform, and this is the
## order JsonStore and StatePaths had already proven. A crash in the gap between
## the two leaves the new bytes complete in the .part rather than a torn target.
##
## There used to be four copies of this (JsonStore, StatePaths, RommSaveSync,
## RommCatalog) and they had drifted: one never checked the store landed, one
## failed without a word. Every failure here logs `[owner]` with the path and the
## error, and an empty owner stays silent for a disposable cache that wants that.
##
## Safe from any thread: nothing here touches the scene tree.
class_name AtomicFile
extends RefCounted


## Write `bytes` to `path` through a staging file. False, with the old file left
## standing, on any failure. `part` overrides the staging path, for a caller
## whose writers can race on one target (RommCatalog stages per thread).
static func write_bytes(path: String, bytes: PackedByteArray, owner: String = "",
		part: String = "") -> bool:
	var staging := part if not part.is_empty() else path + ".part"
	var f := _open_staging(path, staging, owner)
	if f == null:
		return false
	f.store_buffer(bytes)
	return _finish(f, path, staging, owner)


## Same, for text, stored as store_string stores it (UTF-8, no BOM).
static func write_text(path: String, text: String, owner: String = "",
		part: String = "") -> bool:
	var staging := part if not part.is_empty() else path + ".part"
	var f := _open_staging(path, staging, owner)
	if f == null:
		return false
	f.store_string(text)
	return _finish(f, path, staging, owner)


## Move an already complete staging file over `path`: the second half of a write
## a caller streamed itself (RommCatalog's index, the firmware installer's
## scratch tree). False on failure, with `staging` removed and the old file kept.
static func promote(staging: String, path: String, owner: String = "") -> bool:
	if FileAccess.file_exists(path):
		var rm := DirAccess.remove_absolute(path)
		if rm != OK:
			_log(owner, "cannot replace %s (error %d)" % [path, rm])
			DirAccess.remove_absolute(staging)
			return false
	var mv := DirAccess.rename_absolute(staging, path)
	if mv != OK:
		_log(owner, "cannot move %s over %s (error %d)" % [staging, path, mv])
		DirAccess.remove_absolute(staging)
		return false
	return true


## The `[Owner]` tag for a log line; an owner already bracketed is kept as is.
static func tag(owner: String) -> String:
	return owner if owner.begins_with("[") else "[%s]" % owner


static func _open_staging(path: String, staging: String, owner: String) -> FileAccess:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(staging, FileAccess.WRITE)
	if f == null:
		_log(owner, "cannot write %s (error %d)" % [staging, FileAccess.get_open_error()])
	return f


static func _finish(f: FileAccess, path: String, staging: String, owner: String) -> bool:
	var err := f.get_error()
	f.close()
	if err != OK:
		_log(owner, "write to %s failed (error %d)" % [staging, err])
		DirAccess.remove_absolute(staging)
		return false
	return promote(staging, path, owner)


static func _log(owner: String, message: String) -> void:
	if not owner.is_empty():
		push_error("%s %s" % [tag(owner), message])
