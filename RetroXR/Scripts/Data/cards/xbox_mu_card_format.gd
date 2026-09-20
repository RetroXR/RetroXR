## XboxMuCardFormat — the Xbox's Memory Unit, as a CardFormat.
##
## Forwards to XboxMemoryUnit, which holds the layout. Nothing but the forwards
## belongs here.
##
## The family is "xbox_mu", named for the device as "vmu" is: the unit goes in a
## CONTROLLER, the console declares no card_family, and an Xbox's games do not
## save here at all — they save to the hard disk inside the console, and a
## Memory Unit is where the player copies a save to carry it somewhere else.
## That is why SystemInfo's save_device stays empty for the Xbox.
class_name XboxMuCardFormat
extends CardFormat

const FAMILY := "xbox_mu"


func id() -> String:
	return FAMILY


func label() -> String:
	return "Xbox"


func device_noun() -> String:
	return "Memory Unit"


func device_home() -> String:
	return "controller"


## The core's own file is memory_unit_port<N>.img, and ".img" is nobody's in
## particular; a card on the shelf needs an extension CardFormats.for_path can
## tell a family by.
func extension() -> String:
	return "xmu"


## One save is a FOLDER, so its file is an archive of it. See XboxMemoryUnit.
func save_extension() -> String:
	return XboxHddSaves.ARCHIVE_EXT


## Named for a device, so it has to say whose: the platform the saves are
## filed under on the server is the console's.
func romm_systemid() -> String:
	return "xbox"


## And the library its games are in. A save's `serial` is its game's title id,
## which RommSaveSync.rom_id_for_serial matches against each disc's default.xbe.
func library_systemid() -> String:
	return "xbox"


## What XboxStorage lifts off the console's hard disk is the same archive with
## every save of one game in it, and a Memory Unit takes those too.
func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	return XboxMemoryUnit.saves_in_download(bytes)


func save_name(save: PackedByteArray) -> String:
	return XboxMemoryUnit.save_name(save)


## The console's own unit, 16 KB, which is what its Memory screen counts in.
func unit_noun() -> String:
	return "block"


func total_blocks(data: PackedByteArray) -> int:
	return XboxMemoryUnit.total_blocks(data)


func blocks_for_size(byte_size: int) -> int:
	return XboxMemoryUnit.blocks_for_size(byte_size)


func blank_image() -> PackedByteArray:
	return XboxMemoryUnit.blank_image()


func is_card_image(data: PackedByteArray) -> bool:
	return XboxMemoryUnit.is_card_image(data)


func list_saves(data: PackedByteArray, _with_icons := true) -> Array[Dictionary]:
	return XboxMemoryUnit.list_saves(data)


func block_of(data: PackedByteArray, name: String) -> int:
	return XboxMemoryUnit.block_of(data, name)


func extract_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	return XboxMemoryUnit.extract_save(data, first_block)


func is_save_file(bytes: PackedByteArray) -> bool:
	return XboxMemoryUnit.is_save_file(bytes)


func insert_save(data: PackedByteArray, save: PackedByteArray) -> PackedByteArray:
	return XboxMemoryUnit.insert_save(data, save)


func delete_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	return XboxMemoryUnit.delete_save(data, first_block)


func free_blocks(data: PackedByteArray) -> int:
	return XboxMemoryUnit.free_blocks(data)
