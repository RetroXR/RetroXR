## WiiSystemMenu — the Wii's "BIOS": the System Menu installed in dolphin's NAND.
##
## The NAND is not a file the .info can declare. It lives in the core's SAVE dir
## (the fork's User dir is `<save>/User`), and a Wii with an empty drive boots
## its System Menu from there (BiosBoot `dolphin/wii`, core option
## `dolphin_console`); with a disc in, it boots the menu with the disc in the
## drive, and the game starts from the Disc Channel.
##
## Installed by the CORE, never by RetroXR: installing a title means decrypting
## it with the Wii common key, a circumvention key RetroXR must not carry. The
## fork exports `retroxr_wii_system_update`, which is Dolphin's own
## Tools > Perform Online System Update, and Libretro.RunWiiSystemUpdate calls
## it. The title list comes from Dolphin's server (fakenus.dolphin-emu.org) and
## the files from Nintendo's Wii U CDN, so the download depends on both.
##
## Blocking for minutes and writes the whole NAND: never while a Wii or
## GameCube is running on the same NAND (FirmwareInstaller refuses).
class_name WiiSystemMenu
extends RefCounted


const CORE := "dolphin"

## Relative to the core's save dir. The fork's own test for "the menu is
## installed" (Boot.cpp, Common::GetTMDFileName of title 00000001-00000002) --
## necessary, not sufficient: see is_installed().
const TMD_PATH := "User/Wii/title/00000001/00000002/content/title.tmd"

## NUS region names, in the order the region button cycles through them.
const REGIONS: Array[String] = ["USA", "EUR", "JPN", "KOR"]

## WiiUtils::UpdateResult, plus RunWiiSystemUpdate's own two.
const RESULT_INSTALLED := 0
const RESULT_UP_TO_DATE := 1
const RESULT_CANCELLED := 8
const _RESULT_TEXT := {
	-2: "The Dolphin core is too old — update it on the Download tab",
	-1: "The Dolphin core is not installed",
	2: "Region does not match the installed menu",
	5: "Nintendo's update server could not be reached",
	6: "A download failed",
	7: "Installing into the NAND failed",
	8: "Cancelled",
}

## The menu's region is its title version's low four bits, as Dolphin reads it
## (DiscIO::GetSysMenuRegion). NOT the TMD's region field at 0x19C, which is 0
## on the System Menu whatever its region -- reading it called every menu JPN,
## and the region button then offered to replace a USA menu with a Japanese one.
const _VERSION_REGIONS := {0: "JPN", 1: "USA", 2: "EUR", 6: "KOR"}

## System Menu title versions (u16 at 0x1DC) to what a player calls them.
const _MENU_VERSIONS := {
	513: "4.3U", 514: "4.3E", 512: "4.3J", 518: "4.3K",
	481: "4.2U", 482: "4.2E", 480: "4.2J", 486: "4.2K",
}


## The fork's export that installs the menu. A Dolphin core built before it
## (every release up to v12) cannot, and the row says so up front.
const EXPORT := "retroxr_wii_system_update"

enum CoreState { MISSING, TOO_OLD, READY }


## Whether the installed dolphin core can install the menu. Opens the core
## (Libretro.CoreHasExport), so ask once per page build, not per frame.
static func core_state() -> CoreState:
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		return CoreState.MISSING
	if not bool(ClassDB.class_call_static("Libretro", "CoreHasExport",
			CoreDownloadManager.default_core_root(), CORE, EXPORT)):
		return CoreState.TOO_OLD
	return CoreState.READY


## What the row and the tile say when the core cannot install it, or "".
static func core_problem(state: CoreState) -> String:
	match state:
		CoreState.MISSING:
			return "Install the Dolphin core first (Cores > Download)"
		CoreState.TOO_OLD:
			return "Update the Dolphin core: this one cannot download the Wii Menu"
	return ""


static func save_dir() -> String:
	return CoreDownloadManager.default_core_root().path_join("save").path_join(CORE)


## The directory holding Wii/, as the fork derives it from the save dir.
static func user_dir() -> String:
	return save_dir().path_join("User")


## Dolphin's Sys folder, as the fork derives it from the system dir.
static func sys_dir() -> String:
	return CoreDownloadManager.default_system_dir(CORE).path_join("dolphin-emu").path_join("Sys")


static func tmd_path() -> String:
	return save_dir().path_join(TMD_PATH)


## The menu AND the IOS it runs on. The menu's TMD alone is not enough: Dolphin
## installs the menu second of 58 titles, so an update cancelled or failed early
## leaves a title.tmd with no IOS under it, which boots to a black screen.
## Measured with Tools/cores/wii_menu_update_probe --cancel-after=3.
static func is_installed() -> bool:
	return is_installed_at(save_dir())


## is_installed() against any dolphin save dir, so a suite can build one.
static func is_installed_at(dolphin_save_dir: String) -> bool:
	var tmd := FileAccess.get_file_as_bytes(dolphin_save_dir.path_join(TMD_PATH))
	if tmd.size() < 0x1DE:
		return false
	var ios := "%08x/%08x" % [_be32(tmd, 0x184), _be32(tmd, 0x188)]
	return FileAccess.file_exists(
		dolphin_save_dir.path_join("User/Wii/title/%s/content/title.tmd" % ios))


## The installed menu's region ("USA"…), or "" when none is installed.
static func installed_region() -> String:
	return installed_region_at(save_dir())


static func installed_region_at(dolphin_save_dir: String) -> String:
	var tmd := FileAccess.get_file_as_bytes(dolphin_save_dir.path_join(TMD_PATH))
	if tmd.size() < 0x1DE:
		return ""
	return str(_VERSION_REGIONS.get(_be16(tmd, 0x1DC) & 0xF, ""))


## "4.3U", or the raw version number for one not in the table, or "".
static func installed_version() -> String:
	var tmd := FileAccess.get_file_as_bytes(tmd_path())
	if tmd.size() < 0x1DE:
		return ""
	var v := _be16(tmd, 0x1DC)
	return str(_MENU_VERSIONS.get(v, "v%d" % v))


## The region a player most likely owns discs for, from the OS locale. Only a
## starting point: the row's region button changes it.
static func default_region() -> String:
	var locale := OS.get_locale()
	var lang := locale.get_slice("_", 0).to_lower()
	var country := locale.get_slice("_", 1).to_upper() if locale.contains("_") else ""
	if lang == "ja":
		return "JPN"
	if lang == "ko":
		return "KOR"
	if country in ["US", "CA", "MX", "BR"] or locale == "en":
		return "USA"
	return "EUR"


static func next_region(region: String) -> String:
	var i := REGIONS.find(region)
	return REGIONS[(i + 1) % REGIONS.size()]


static func succeeded(result: int) -> bool:
	return result == RESULT_INSTALLED or result == RESULT_UP_TO_DATE


static func result_text(result: int) -> String:
	if succeeded(result):
		return ""
	return str(_RESULT_TEXT.get(result, "The system update failed (%d)" % result))


## Run the core's online system update. BLOCKING for minutes — worker thread
## only. `progress(processed, total, title_hex) -> bool` runs on that thread;
## returning false cancels once the current title is in.
static func run(region: String, progress: Callable) -> int:
	DirAccess.make_dir_recursive_absolute(user_dir())
	return int(ClassDB.class_call_static("Libretro", "RunWiiSystemUpdate",
		CoreDownloadManager.default_core_root(), CORE, user_dir(), sys_dir(),
		region, progress))


static func _be16(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 8) | bytes[at + 1]


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (_be16(bytes, at) << 16) | _be16(bytes, at + 2)
