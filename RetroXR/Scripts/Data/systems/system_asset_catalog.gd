## SystemAssetCatalog — the support archives libretro publishes for cores that
## need more than a BIOS to run.
##
## buildbot.libretro.com/assets/system/ hosts one zip per core, each extracting
## to a top-level folder that matches the prefix that core's .info firmware
## paths use ("PPSSPP/", "scummvm/", "dolphin-emu/"). Unpacked into the core's
## system dir, an archive therefore satisfies its declared rows directly — no
## per-file mapping needed.
##
## Verified against the live listing 2026-07-30: the archives carry everything
## redistributable and stop exactly at console BIOSes. Dolphin.zip supplies the
## required codehandler.bin but none of the three GameCube IPL dumps; LRPS2.zip
## supplies GameIndex.yaml but not the PS2 bios folder. Those stay the user's
## to provide, which is the correct split.
class_name SystemAssetCatalog


const BASE_URL := "https://buildbot.libretro.com"
const BASE_PATH := "/assets/system/"

## core_name -> { zip, label, marker }.
##
## No size is recorded. buildbot rebuilds these archives in place, so any byte
## count written here is wrong the moment it lands; the server states the size
## on every request and that is the only figure anything uses.
##
## `marker` is a shallow file the archive always carries, relative to the system
## dir. Its presence is what tells us the archive has been unpacked — that is
## not derivable from the firmware rows, because several archives can never
## satisfy all of them (Dolphin.zip has one of dolphin's four declared files and
## never the three GameCube IPL dumps). Reading it off disk also recognises an
## archive unpacked by hand, or before this tab existed.
## Read from each archive's listing 2026-07-30.
const ARCHIVES := {
	"ppsspp":          {"zip": "PPSSPP.zip",                     "label": "PPSSPP assets",           "marker": "PPSSPP/compat.ini"},
	"scummvm":         {"zip": "ScummVM.zip",                    "label": "ScummVM themes + extras", "marker": "scummvm/extra/mm.dat"},
	"dolphin":         {"zip": "Dolphin.zip",                    "label": "Dolphin Sys folder",      "marker": "dolphin-emu/license.txt"},
	"dolphin_launcher":{"zip": "Dolphin.zip",                    "label": "Dolphin Sys folder",      "marker": "dolphin-emu/license.txt"},
	"pcsx2":           {"zip": "LRPS2.zip",                      "label": "PCSX2 resources",         "marker": "pcsx2/resources/GameIndex.yaml"},
	"bluemsx":         {"zip": "blueMSX.zip",                    "label": "blueMSX machines",        "marker": "Databases/svidb.xml"},
	"mame2003":        {"zip": "MAME 2003.zip",                  "label": "MAME 2003 support",       "marker": "mame2003/cheat.dat"},
	"mame2003_plus":   {"zip": "MAME 2003-Plus.zip",             "label": "MAME 2003-Plus support",  "marker": "mame2003-plus/cheat.dat"},
	"fbneo":           {"zip": "FinalBurn Neo (hiscore).zip",    "label": "FinalBurn Neo hiscore",   "marker": "fbneo/hiscore.dat"},
	"prboom":          {"zip": "PrBoom.zip",                     "label": "PrBoom data",             "marker": "prboom.wad"},
	"nxengine":        {"zip": "NXEngine (Cave Story).zip",      "label": "Cave Story data",         "marker": "nxengine/Readme.txt"},
	"ecwolf":          {"zip": "ECWolf.zip",                     "label": "ECWolf data",             "marker": "ecwolf.pk3"},
	"dinothawr":       {"zip": "Dinothawr.zip",                  "label": "Dinothawr game data",     "marker": "dinothawr/LICENSE"},
	"qemu":            {"zip": "QEMU.zip",                       "label": "QEMU firmware",           "marker": "qemu/README"},
	"dirksimple":      {"zip": "DirkSimple.zip",                 "label": "DirkSimple data",         "marker": "DirkSimple/LICENSE.txt"},
	"cannonball":      {"zip": "Cannonball (ROMs Required).zip", "label": "Cannonball data",         "marker": "cannonball/roms.txt"},
	"xrick":           {"zip": "XRick (Rick Dangerous).zip",     "label": "XRick data",              "marker": "xrick/data.zip"},
}


## Has this core's support archive already been unpacked into its system dir?
static func is_installed(core_name: String) -> bool:
	var a := archive_for(core_name)
	if a.is_empty():
		return false
	var marker := str(a.get("marker", ""))
	if marker.is_empty():
		return false
	return FileAccess.file_exists(
		CoreDownloadManager.default_system_dir(core_name).path_join(marker))


static func has_archive(core_name: String) -> bool:
	return ARCHIVES.has(core_name)


static func archive_for(core_name: String) -> Dictionary:
	return ARCHIVES.get(core_name, {})


## Path component of the download URL. Zip names carry spaces and parentheses
## ("MAME 2003-Plus.zip"), so they must be percent-encoded.
static func archive_path(core_name: String) -> String:
	var a := archive_for(core_name)
	if a.is_empty():
		return ""
	return BASE_PATH + str(a["zip"]).uri_encode()


## These run from 3.7 KB to 79 MB, and the size is worth knowing before you
## commit to one — but only the server can state it, so the download reports it
## in its toast rather than the button carrying a number that rots.
static func button_label(core_name: String) -> String:
	var a := archive_for(core_name)
	if a.is_empty():
		return ""
	return str(a["label"])


# ── Packs ─────────────────────────────────────────────────────────────────────
#
# Downloads a core needs that libretro does not host. A pack is several zips from
# wherever their authors publish them, and a zip rarely unpacks to the path the
# core reads, so each part names the folder inside its zip to take (`from`), the
# folder of the system dir it goes to (`into`) and, optionally, which of the
# files under `from` to keep (`only`).
#
# The first are the Voice Recognition Unit's: the mupen64plus_next fork opens
# libvosk and a model from <system>/vru/ at run time (vru_recognizer.c), and a
# game's word list decides the model -- English for Hey You, Pikachu! and Densha
# de GO! 64, whose Shift-JIS words the word table maps to English; Japanese for
# Pikachuu Genki de Chuu. Vosk and both models are Apache 2.0.

const _VOSK_RELEASES := "https://github.com/alphacep/vosk-api/releases/download/"
const _VOSK_MODELS := "https://alphacephei.com/vosk/models/"

## part id -> {label, url, from, into, only, marker}. `marker` is the file whose
## presence means the part is installed, relative to the system dir.
##
## 0.3.45 is the release vosk_api.h is vendored from in the fork. It published no
## macOS build; 0.3.42's universal dylib exports every function the recognizer
## calls. Layouts read from each zip 2026-09-16: Android's has no top folder, one
## per ABI, and only arm64-v8a is a Quest.
const PARTS := {
	"vosk_windows": {
		"label": "Vosk speech library",
		"url": _VOSK_RELEASES + "v0.3.45/vosk-win64-0.3.45.zip",
		"from": "vosk-win64-0.3.45/", "into": "vru/",
		# libvosk.dll is built with MinGW and loads none of these itself.
		"only": ["libvosk.dll", "libgcc_s_seh-1.dll", "libstdc++-6.dll", "libwinpthread-1.dll"],
		"marker": "vru/libvosk.dll",
	},
	"vosk_linux": {
		"label": "Vosk speech library",
		"url": _VOSK_RELEASES + "v0.3.45/vosk-linux-x86_64-0.3.45.zip",
		"from": "vosk-linux-x86_64-0.3.45/", "into": "vru/",
		"only": ["libvosk.so"],
		"marker": "vru/libvosk.so",
	},
	"vosk_macos": {
		"label": "Vosk speech library",
		"url": _VOSK_RELEASES + "v0.3.42/vosk-osx-0.3.42.zip",
		"from": "vosk-osx-0.3.42/", "into": "vru/",
		"only": ["libvosk.dylib"],
		"marker": "vru/libvosk.dylib",
	},
	"vosk_android": {
		"label": "Vosk speech library",
		"url": _VOSK_RELEASES + "v0.3.45/vosk-android-0.3.45.zip",
		"from": "arm64-v8a/", "into": "vru/",
		"only": ["libvosk.so"],
		"marker": "vru/libvosk.so",
	},
	"vosk_model_en": {
		"label": "English speech model",
		"url": _VOSK_MODELS + "vosk-model-small-en-us-0.15.zip",
		"from": "vosk-model-small-en-us-0.15/", "into": "vru/model-en-us/",
		"marker": "vru/model-en-us/am/final.mdl",
	},
	"vosk_model_ja": {
		"label": "Japanese speech model",
		"url": _VOSK_MODELS + "vosk-model-small-ja-0.22.zip",
		"from": "vosk-model-small-ja-0.22/", "into": "vru/model-ja/",
		# The lexicon, not the acoustic model: the recognizer splits a Japanese
		# word into its entries, and a model without it hears nothing.
		"marker": "vru/model-ja/graph/words.txt",
	},
}

## The platform's library, standing in a pack's part list for whichever of the
## vosk_* library parts this machine can load.
const LIBRARY := "library"

const _VRU_PACKS := [
	{
		"id": "vru_en",
		"label": "Voice Recognition Unit speech: English",
		"desc": "Hey You, Pikachu! and Densha de GO! 64",
		"parts": [LIBRARY, "vosk_model_en"],
	},
	{
		"id": "vru_ja",
		"label": "Voice Recognition Unit speech: Japanese",
		"desc": "Pikachuu Genki de Chuu",
		"parts": [LIBRARY, "vosk_model_ja"],
	},
]

## core_name -> packs. The Quest runs the gles3 build, which is a core name of
## its own and therefore a system dir of its own.
const PACKS := {
	"mupen64plus_next": _VRU_PACKS,
	"mupen64plus_next_gles3": _VRU_PACKS,
}


## Which library part a machine can load, or "" where Vosk publishes none that
## RetroXR runs on.
static func library_part_id(os_name: String, arch: String) -> String:
	match os_name:
		"Windows":
			return "vosk_windows" if arch == "x86_64" else ""
		"Linux":
			return "vosk_linux" if arch == "x86_64" else ""
		"macOS":
			return "vosk_macos"
		"Android":
			return "vosk_android" if arch == "arm64" else ""
	return ""


## The packs this machine can install for a core. A pack whose library does not
## exist for this platform is left out rather than offered and failed.
static func packs_for(core_name: String,
		os_name: String = OS.get_name(),
		arch: String = Engine.get_architecture_name()) -> Array:
	var out := []
	for pack: Dictionary in PACKS.get(core_name, []):
		if not pack_parts(pack, os_name, arch).is_empty():
			out.append(pack)
	return out


static func pack_for(core_name: String, pack_id: String) -> Dictionary:
	for pack: Dictionary in PACKS.get(core_name, []):
		if str(pack["id"]) == pack_id:
			return pack
	return {}


## A pack's parts, resolved to their definitions, each carrying its own `id`.
## Empty when any part cannot be resolved for this platform.
static func pack_parts(pack: Dictionary,
		os_name: String = OS.get_name(),
		arch: String = Engine.get_architecture_name()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in pack.get("parts", []):
		var part_id := library_part_id(os_name, arch) if id == LIBRARY else id
		if part_id.is_empty() or not PARTS.has(part_id):
			return []
		var part: Dictionary = (PARTS[part_id] as Dictionary).duplicate()
		part["id"] = part_id
		out.append(part)
	return out


static func part_installed(system_dir: String, part: Dictionary) -> bool:
	return FileAccess.file_exists(system_dir.path_join(str(part["marker"])))


## Installed when every part is, so a pack sharing its library with another
## reads as installed only once its own model is there too.
static func pack_installed(system_dir: String, pack: Dictionary) -> bool:
	var parts := pack_parts(pack)
	if parts.is_empty():
		return false
	for part: Dictionary in parts:
		if not part_installed(system_dir, part):
			return false
	return true
