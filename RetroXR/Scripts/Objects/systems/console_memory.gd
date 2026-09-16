## ConsoleMemory — backup memory built into the console itself: the Sega
## Saturn's System Memory.
##
## A Sega CD's memory is in a unit that comes off, so it rides on the
## RetroExpansion; a Saturn's is on the board, so it rides on the machine. It
## carries what MemoryCardPanel reads off a card (card_id, family, card_label,
## minted), which is what lets the console's Saves tab manage it with the card
## panel's own code, and what CardSaveOps.holder_of matches. The image is
## save/memcards/<family>/<card_id>.<ext>, as a card's is.
class_name ConsoleMemory
extends Node3D

## The one core that hands this memory over through SAVE_RAM. Every other Saturn
## core keeps the per-disc file it always had.
const SAVE_RAM_CORE := "mednafen_saturn"
const SAVES_PANEL_SCENE_PATH := "res://Scenes/UI/memory_card_panel.tscn"

var family := ""
var card_id := ""
var card_label := ""
## True while there is no image on disk -- see MemoryCard.minted. A console's
## memory has nowhere else to be, so a restored console whose image is missing is
## in the same state as a new one.
var minted := false

var _saves_panel: MemoryCardPanel = null


static func hands_over(core: String) -> bool:
	return core.begins_with(SAVE_RAM_CORE)


## `restored_id` is the id a room save recorded, or "" for a new console, which is
## given one unique against the images on disk and every console in the room.
## Called once the machine is in the tree.
func setup(host: RetroSystem, memory_family: String, restored_id: String) -> void:
	family = memory_family
	card_id = restored_id if not restored_id.is_empty() else _unique_id(host)
	card_label = card_id
	minted = SramPaths.find_card(card_id, family).is_empty()


func _unique_id(host: RetroSystem) -> String:
	var taken := {}
	for sys: Node in host.get_tree().get_nodes_in_group("retro_system"):
		if sys == host or not sys.has_method("console_memory"):
			continue
		var other: Variant = sys.call("console_memory")
		if other is ConsoleMemory:
			taken[(other as ConsoleMemory).card_id] = true
	var info := SystemInfo.for_system(host.systemid)
	var base := "%s MEMORY" % (info.display_name if info != null else host.systemid).to_upper()
	var id := SramPaths.unique_card_id(base)
	var n := 1
	while taken.has(id):
		n += 1
		id = SramPaths.unique_card_id("%s %d" % [base, n])
	return id


## The image the core is handed, made first when it is missing: that is memory
## whose battery ran out, not a card left somewhere else, so the console runs with
## a formatted one rather than with none. The first image of the family ever made
## also takes the saves games kept per disc before the console kept them.
func ensure_image(core: String, systemid: String) -> String:
	var path := SramPaths.card_save_path(family, card_id)
	if path.is_empty() or FileAccess.file_exists(path):
		return path
	var image := CardFormats.for_family(family).blank_image()
	if SramPaths.list_cards(family).is_empty():
		var system_dir := SramPaths.system_save_dir(systemid, core)
		image = adopt_disc_saves(system_dir, image)
		if system_dir != SramPaths.core_save_dir(core):
			image = adopt_disc_saves(SramPaths.core_save_dir(core), image)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[ConsoleMemory] cannot create %s" % path)
		return ""
	f.store_buffer(image)
	f.close()
	return path


## `image` with the saves from every per-disc System Memory file under
## <save_dir>/<game>/, newest first, as far as they fit. The files stay where they
## are: they are also the games' own saves to anything else that reads them.
static func adopt_disc_saves(save_dir: String, image: PackedByteArray) -> PackedByteArray:
	if not DirAccess.dir_exists_absolute(save_dir):
		return image
	var found: Array[Dictionary] = []
	for game: String in DirAccess.get_directories_at(save_dir):
		for name: String in DirAccess.get_files_at(save_dir.path_join(game)):
			if name.get_extension().to_lower() == "srm":
				var path := save_dir.path_join(game).path_join(name)
				found.append({"path": path, "time": FileAccess.get_modified_time(path)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["time"]) > int(b["time"]))
	var out := image
	for e: Dictionary in found:
		var data := FileAccess.get_file_as_bytes(str(e["path"]))
		if data.size() != image.size() or SaturnBram.list_files(data).is_empty():
			continue
		out = SaturnBram.merge(out, data)
		print("[ConsoleMemory] new memory takes the saves in %s" % str(e["path"]))
	return out


## The panel that manages this memory, driven by the console menu's Saves tab.
func ensure_saves_panel() -> MemoryCardPanel:
	if _saves_panel == null:
		_saves_panel = (load(SAVES_PANEL_SCENE_PATH) as PackedScene).instantiate()
		add_child(_saves_panel)
	return _saves_panel
