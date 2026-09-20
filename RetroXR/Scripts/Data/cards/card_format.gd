## CardFormat — one console family's memory card, as an object.
##
## Everything about cards used to key on systemid, which held only while the
## PlayStation was the one console with them. It is the wrong key: a card family
## is a folder under save/memcards/, a file extension, a byte layout and a
## vocabulary, and the GameCube's is shared by TWO systemids — a Wii playing a
## GameCube disc writes to a GameCube card.
##
## The format half of this forwards to an all-static class (PS1Card, GCCard).
## Those stay static and untouched: they are measured, they are the thing most
## worth being able to test without a scene, and GDScript has no virtual statics
## to dispatch through anyway. This is the adapter that gives them one.
##
## Subclasses override everything. The stubs here return empty values rather than
## pushing an error, so a half-built format shows an empty card instead of
## spraying the log from _process.
class_name CardFormat
extends RefCounted

## restore_group() answers, in the order the restore list shows them.
const RESTORE_ONE_SAVE := 0
const RESTORE_MAY_HOLD := 1
const RESTORE_UNLIKELY := 2


# --- Identity -----------------------------------------------------------------

## The folder under save/memcards/, and the value a MemoryCard carries as its
## `family`.
func id() -> String:
	return ""


## Console family name for menus and refusal messages ("PlayStation").
func label() -> String:
	return ""


## Card image extension, no dot ("mcr").
func extension() -> String:
	return ""


## Extension of ONE save lifted off a card ("mcs"). Uploaded to RomM under it,
## and one of the extensions the card listing accepts from the server.
func save_extension() -> String:
	return ""


## The systemid whose RomM platform holds this family's saves. The family id
## serves when it names a console; a family named for a device has to name one.
## A family kept the name it had before the systemids were renamed (it names a
## folder of the player's cards), so "playstation" is read as "psx" here.
func romm_systemid() -> String:
	return SystemIds.canonical(id())


## The systemid whose ROM LIBRARY holds the games that save here: where a save's
## `serial` is looked up to find the game it belongs to, and whose default core
## an upload is filed under. The family id serves everywhere it always has; a
## family named for a DEVICE (the Xbox's Memory Unit) has no library of its own
## and names its console's.
func library_systemid() -> String:
	return id()


## Every extension a RomM save for this family may arrive under: its own
## single-save file, plus any file that carries saves inside it.
func romm_save_extensions() -> PackedStringArray:
	return PackedStringArray([save_extension()])


## How likely one of RomM's save rows is to hold a save for this family, for
## ordering the restore list:
##   RESTORE_ONE_SAVE  one save in this family's own format
##   RESTORE_MAY_HOLD  a file that may carry saves inside it
##   RESTORE_UNLIKELY  such a file from a game not known to save here; listed
##                     only when asked for
## Decided from the listing alone. Opening every file to find out is not an
## option on a library of any size.
func restore_group(row: Dictionary) -> int:
	var ext := str(row.get("file_name", "")).get_extension().to_lower()
	return RESTORE_ONE_SAVE if ext.is_empty() or ext == save_extension() else RESTORE_MAY_HOLD


## The size line of a restore row that is not one save: its size in units is
## unknown until it is downloaded.
func container_row_label(_row: Dictionary) -> String:
	return "whole save file"


## Where the device is plugged in, for telling a player to fit one: "console" or
## "controller".
func device_home() -> String:
	return "console"


## What a game's Saves menu says when the game saves here instead of to itself.
## `medium` is "disc" or "cartridge".
func save_device_note(game: String, medium: String) -> String:
	var noun := device_noun()
	var home := "the console" if device_home() == "console" else "a controller"
	return "%s saves to a %s, not the %s.\n\nPut a %s in %s before you play. Its saves are managed from the %s itself." \
		% [game, noun, medium, noun, home, noun]


# --- Vocabulary ---------------------------------------------------------------

## What one unit of card space is called, singular ("block").
func unit_noun() -> String:
	return "block"


## The same unit in the plural. Almost always the singular plus an s, which is
## why the usage line used to just append one — but the PlayStation 2 counts in
## KB, and "7999 KBs" is not a thing anyone has written.
func unit_plural() -> String:
	return unit_noun() + "s"


## What the OBJECT is called, for the heading over its save list. Distinct from
## label(), which names the console family — a panel headed "PlayStation" would
## be naming the machine rather than the thing in your hand. Only the N64's
## Controller Pak is not a memory card, so the default suits everything else.
func device_noun() -> String:
	return "Memory Card"


## How many units this card holds in total. Read from the IMAGE, because a
## GameCube card's size is a property of the card and not of the family — a 59
## and a 251 are both ordinary. Falls back to the family's usual size when the
## image is missing or unreadable, which is what a card that has never been
## seated has to show.
func total_blocks(_data: PackedByteArray) -> int:
	return 0


## How many units a save of this byte size occupies, given the file is one save
## as extract_save() produces it.
func blocks_for_size(_byte_size: int) -> int:
	return 1


## Frames per second to animate a save's icon at, when the format does not carry
## a per-frame duration of its own.
func icon_fps() -> float:
	return 6.0


# --- Format -------------------------------------------------------------------

## A freshly formatted, empty card. RetroXR never boots a console's own BIOS, so
## the player has no way to format one and a new card must arrive usable.
func blank_image() -> PackedByteArray:
	return PackedByteArray()


func is_card_image(_data: PackedByteArray) -> bool:
	return false


## Every save on the card, one entry each:
##   name    String   the save's own filename on the card
##   serial  String   the game's product code, for matching it to a library entry
##   title   String   the save's own title
##   blocks  int      how many units it occupies
##   block   int      an opaque handle to this save, which every other call
##                     here takes. The PlayStation numbers saves by their first
##                     block and the GameCube by directory entry; nothing outside
##                     a format may read anything into the number.
##   icons   Array    Image, one per animation frame
##
## `with_icons` off skips decoding the images, which is the expensive part by
## far. Only the save list draws them.
func list_saves(_data: PackedByteArray, _with_icons := true) -> Array[Dictionary]:
	return []


## The first block of the save with this filename, or -1.
func block_of(_data: PackedByteArray, _name: String) -> int:
	return -1


## One save lifted out of a card as a standalone file, in the format every tool
## for this console reads.
func extract_save(_data: PackedByteArray, _first_block: int) -> PackedByteArray:
	return PackedByteArray()


## Does this look like a save of THIS family, rather than some other console's?
## Worth asking of anything that came off a server: a save is just bytes with a
## name, and splicing a foreign one into a card corrupts the card.
func is_save_file(_bytes: PackedByteArray) -> bool:
	return false


## Every single save a downloaded file holds, each ready for insert_save(). A
## file that is itself one save of this family comes back as itself; anything
## this family does not recognise yields nothing.
func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if is_save_file(bytes):
		out.append(bytes)
	return out


## A single save file's own name on the card, or "" when the format cannot say.
func save_name(_save: PackedByteArray) -> String:
	return ""


## Splice a save into a card, returning a NEW image. Empty when it will not fit,
## is malformed, or a save of that name is already there.
func insert_save(_data: PackedByteArray, _save: PackedByteArray) -> PackedByteArray:
	return PackedByteArray()


## Free the space one save occupies, returning a NEW image.
func delete_save(_data: PackedByteArray, _first_block: int) -> PackedByteArray:
	return PackedByteArray()


func free_blocks(_data: PackedByteArray) -> int:
	return 0
