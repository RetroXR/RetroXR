## WiiUSystemMenu — the Wii U Menu a system dump puts in the Cemu core's mlc01:
## what a Wii U boots with no disc (BiosBoot `cemu/wiiu`, `wiiu_menu`).
##
## Not firmware the .info can name: it lives in the core's SAVE dir, as the Wii's
## System Menu does in Dolphin's NAND (WiiSystemMenu), and there is no installer
## here -- a player lays their console's dump (mlc01) in. "Installed" is the menu's
## executable, the same file the Cemu fork boots when it is given no content
## (libretro_wiiu_menu_path, the same three titles in the same order).
class_name WiiUSystemMenu
extends RefCounted

const CORE := "cemu"
## The menu's title ids by region, low halves (high half 00050010), in the order
## the fork tries them.
const TITLES := {"10040100": "USA", "10040200": "EUR", "10040000": "JPN"}


## The core's mlc01: <save>/cemu/Cemu/mlc01 (the fork's save dir is its own
## "Cemu" folder inside the one it is handed).
static func mlc_dir() -> String:
	return CoreDownloadManager.default_core_root().path_join("save").path_join(CORE) \
		.path_join("Cemu").path_join("mlc01")


static func is_installed() -> bool:
	return not menu_path_in(mlc_dir()).is_empty()


## The menu's men.rpx in `mlc`, or "" when no region's menu is there. Against any
## mlc01, so a suite can build one.
static func menu_path_in(mlc: String) -> String:
	for id: String in TITLES:
		var rpx := mlc.path_join("sys/title/00050010/%s/code/men.rpx" % id)
		if FileAccess.file_exists(rpx):
			return rpx
	return ""


## "USA" / "EUR" / "JPN" for the menu the fork will boot, or "".
static func installed_region_in(mlc: String) -> String:
	var rpx := menu_path_in(mlc)
	if rpx.is_empty():
		return ""
	return str(TITLES.get(rpx.get_base_dir().get_base_dir().get_file(), ""))
