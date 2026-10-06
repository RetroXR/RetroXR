## ModContentPolicy — what a pack fetched from mod.io may not carry.
##
## A mod is models, scenes and scripts. It is never a game: RetroXR does not
## distribute ROMs, disc images or BIOS files, and a mod page is not a way round
## that. Nor is it native code, which mounting a pack would not load anyway and
## which has no business being in one.
##
## mod.io can be given the same list for uploads, and should be. This is the
## copy the game holds, because a rule enforced only on somebody else's server
## is a rule this game cannot vouch for.
##
## Applied to DOWNLOADS (ModManager.install). A file the player copied into the
## mods folder themselves is theirs, and is vetted as it always was.
class_name ModContentPolicy
extends RefCounted

## Never content for a core, never a Godot resource: programs and installers.
const NATIVE := ["so", "dll", "dylib", "exe", "apk", "msi", "bat", "cmd", "sh", "ps1",
	"jar", "dex", "elf", "com"]

## Extensions some core loads as content that a mod also has every reason to
## ship: text, pictures and sound. Everything else a core would load is refused.
##
## `md` is NOT here. It is Markdown, and it is also a Mega Drive ROM; a mod's
## notes can be a .txt.
const SHARED_WITH_GODOT := ["txt", "png", "ogg", "mp3", "wav", "cfg"]

static var _denied: Dictionary = {}


## extension -> true, lower case: every extension a core loads as content, less
## the ones above, plus NATIVE. Built once, from the core database.
static func denied_extensions() -> Dictionary:
	if not _denied.is_empty():
		return _denied
	var out := {}
	var db := CoreInfoDatabase.shared()
	if db != null:
		for systemid: String in db.get_unique_systemids():
			for ext: String in CoreInfoDatabase.extensions_for_systemid(systemid):
				var e := ext.to_lower()
				# The core list carries a few tokens that are not extensions.
				if e.is_valid_identifier() or e.is_valid_int() or _alnum(e):
					out[e] = true
	for ext: String in SHARED_WITH_GODOT:
		out.erase(ext)
	for ext: String in NATIVE:
		out[ext] = true
	_denied = out
	return _denied


## "" when every file in the pack is allowed, else a sentence naming the first
## that is not. `denied` is a parameter so the suite can test the rule without
## the core database.
static func violation(files: PackedStringArray, denied: Dictionary = denied_extensions()) -> String:
	for path: String in files:
		var ext := path.get_extension().to_lower()
		if ext.is_empty() or not denied.has(ext):
			continue
		if NATIVE.has(ext):
			return "carries a program (%s)" % path.get_file()
		return "carries a file that looks like a game (%s)" % path.get_file()
	return ""


static func _alnum(s: String) -> bool:
	if s.is_empty():
		return false
	for c: String in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true
