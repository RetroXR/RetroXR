## ArcadeDiscs — the disc image a few arcade games need beside their board.
##
## MAME keeps a game's hard-disc / CD-ROM images (`.chd`) in a folder named for the romset, next to
## the romset's zip: `roms/arcade/thisgame.zip` and `roms/arcade/thisgame/anything.chd`. RomM lists
## them as two entries (the zip, and the folder as a multi-file ROM). The room shows ONE game: the
## board is the zip, and the disc is what the folder holds. Everything that has to treat the pair as
## one -- the list, a download, a delete, the cabinet's bay -- asks this class, so there is a single
## answer to "what disc goes with this board".
##
## The pairing is by NAME and by place, never by a table of which games have a disc: a board needs a
## disc exactly when the folder is there.
class_name ArcadeDiscs
extends RefCounted

## The one system whose games pair this way.
const SYSTEMID := "arcade"
## What a disc image is. MAME's CHD is the only one; a cue/bin set is another system's.
const DISC_EXTS := ["chd"]
## The container a board comes in. A folder beside one of these is its disc folder.
const BOARD_EXTS := ["zip", "7z"]

## What the player is told a half-assembled game still needs; the words are the bay's parts.
const BOARD_NAME := "JAMMA Board"
const DISC_NAME := "Disc"


## Does this system pair boards with disc folders at all?
static func applies(systemid: String) -> bool:
	return SystemIds.canonical(systemid) == SYSTEMID


static func is_disc_path(path: String) -> bool:
	return path.get_extension().to_lower() in DISC_EXTS


static func is_board_path(path: String) -> bool:
	return path.get_extension().to_lower() in BOARD_EXTS


## The folder a board's discs live in: beside it, named for it.
static func folder_for(board_path: String) -> String:
	return board_path.get_base_dir().path_join(board_path.get_file().get_basename())


## Every disc image in `board_path`'s folder, sorted, as absolute paths. Empty when there is no
## folder, or it holds none: that board is a plain board.
static func disc_files(board_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if board_path.is_empty() or not is_board_path(board_path):
		return out
	var dir := DirAccess.open(folder_for(board_path))
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and not name.begins_with(".") and is_disc_path(name):
			out.append(folder_for(board_path).path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## The disc a board is played with: the first image in its folder, "" for a plain board.
static func disc_for(board_path: String) -> String:
	var all := disc_files(board_path)
	return all[0] if not all.is_empty() else ""


static func needs_disc(board_path: String) -> bool:
	return not disc_for(board_path).is_empty()


## Is `disc_path` one of `board_path`'s discs? Same folder, compared the way the filesystem would
## on the platforms that fold case.
static func belongs_to(disc_path: String, board_path: String) -> bool:
	if disc_path.is_empty() or board_path.is_empty():
		return false
	var a := disc_path.get_base_dir().simplify_path().to_lower()
	var b := folder_for(board_path).simplify_path().to_lower()
	return a == b


## The board a disc goes with: the zip (or 7z) named for the disc's folder, "" when there is none.
static func board_for(disc_path: String) -> String:
	var folder := disc_path.get_base_dir()
	var parent := folder.get_base_dir()
	var stem := folder.get_file()
	for ext: String in BOARD_EXTS:
		var candidate := parent.path_join("%s.%s" % [stem, ext])
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Is this object a disc made for an arcade bay? (A RetroDisc under the arcade system.)
static func is_disc_object(obj: Node) -> bool:
	return obj is RetroDisc and applies(str(obj.get("systemid")))


## Delete the disc folder a board owns, files first. Returns how many files went. Only ever the
## folder named for the board, and only when it sits beside it -- never a path the caller made up.
static func delete_for(board_path: String) -> int:
	if board_path.is_empty() or not is_board_path(board_path):
		return 0
	var folder := folder_for(board_path)
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	var removed := _delete_tree(folder)
	return removed


static func _delete_tree(dir_path: String) -> int:
	var removed := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	var files := PackedStringArray()
	var subdirs := PackedStringArray()
	while name != "":
		if name != "." and name != "..":
			if dir.current_is_dir():
				subdirs.append(name)
			else:
				files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	for f: String in files:
		if DirAccess.remove_absolute(dir_path.path_join(f)) == OK:
			removed += 1
	for d: String in subdirs:
		removed += _delete_tree(dir_path.path_join(d))
	DirAccess.remove_absolute(dir_path)
	return removed


## What the cabinet says when a disc game is started with only one half in. `missing` is the half
## that is not there: BOARD_NAME or DISC_NAME.
static func requires_notice(missing: String) -> String:
	return "This game also requires a %s, please insert %s." % [missing, missing]


## For each row of a platform's index, the row of the DISC FOLDER that goes with it, or -1.
## Rows are described by the catalog's sidecars: `fs_bases` the lowercase file stem and `exts` the
## lowercase extension. A folder has none; a board is a zip or 7z of the same stem. A folder with
## no board beside it pairs with nothing and stays a row of its own -- showing a spare row is the
## safe way to be wrong.
static func pair_folders(fs_bases: PackedStringArray, exts: PackedStringArray) -> PackedInt32Array:
	var pairs := PackedInt32Array()
	pairs.resize(exts.size())
	pairs.fill(-1)
	if fs_bases.size() != exts.size():
		return pairs
	var folder_by_stem := {}
	for i in exts.size():
		if exts[i].is_empty() and not folder_by_stem.has(fs_bases[i]):
			folder_by_stem[fs_bases[i]] = i
	if folder_by_stem.is_empty():
		return pairs
	for i in exts.size():
		if exts[i] in BOARD_EXTS and folder_by_stem.has(fs_bases[i]):
			pairs[i] = folder_by_stem[fs_bases[i]]
	return pairs
