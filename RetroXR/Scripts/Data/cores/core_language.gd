## CoreLanguage — the language a libretro core is told the player speaks
## (RETRO_ENVIRONMENT_GET_LANGUAGE), and how a system locale picks one.
##
## A core uses it for an "automatic" system language (a GameCube or Wii's,
## a PSP's, a DS's firmware, a Dreamcast's BIOS) and to translate its core
## options. Ids are locale-style strings so a saved pref reads plainly; each maps
## to a retro_language enum value (libretro.h).
class_name CoreLanguage
extends RefCounted

## [id, menu label, retro_language]. Menu order; the enum values are libretro.h's.
const LANGUAGES: Array = [
	["en", "English", 0],
	["en_GB", "English (UK)", 30],
	["ja", "Japanese", 1],
	["fr", "French", 2],
	["es", "Spanish", 3],
	["de", "German", 4],
	["it", "Italian", 5],
	["nl", "Dutch", 6],
	["pt_BR", "Portuguese (Brazil)", 7],
	["pt_PT", "Portuguese (Portugal)", 8],
	["ru", "Russian", 9],
	["ko", "Korean", 10],
	["zh_Hant", "Chinese (Traditional)", 11],
	["zh_Hans", "Chinese (Simplified)", 12],
	["eo", "Esperanto", 13],
	["pl", "Polish", 14],
	["vi", "Vietnamese", 15],
	["ar", "Arabic", 16],
	["el", "Greek", 17],
	["tr", "Turkish", 18],
	["sk", "Slovak", 19],
	["fa", "Persian", 20],
	["he", "Hebrew", 21],
	["ast", "Asturian", 22],
	["fi", "Finnish", 23],
	["id", "Indonesian", 24],
	["sv", "Swedish", 25],
	["uk", "Ukrainian", 26],
	["cs", "Czech", 27],
	["ca_valencia", "Valencian", 28],
	["ca", "Catalan", 29],
	["hu", "Hungarian", 31],
	["be", "Belarusian", 32],
	["gl", "Galician", 33],
	["no", "Norwegian", 34],
	["ga", "Irish", 35],
	["th", "Thai", 36],
]

const DEFAULT := "en"


static func is_language(id: String) -> bool:
	return _row(id).size() > 0


## The retro_language for an id; English for one this table does not know.
static func retro_language(id: String) -> int:
	var row := _row(id)
	return int(row[2]) if row.size() > 0 else 0


## The menu label for an id, or "" for one this table does not know.
static func label(id: String) -> String:
	var row := _row(id)
	return str(row[1]) if row.size() > 0 else ""


## The id for a system locale as Godot reports it (OS.get_locale(): "ja_JP",
## "pt_BR", "zh_Hant_TW", "ca_ES@valencia"; "-" separators are accepted too).
## Anything unknown is English.
##
## English always maps to plain English, even en_GB: British English is
## libretro's newest entry, and the few cores that translate options seldom carry
## it, so asking for it buys nothing and risks a core that mishandles it. A
## player who wants it picks it.
static func for_locale(locale: String) -> String:
	var valencia := locale.to_lower().contains("@valencia")
	var clean := locale.get_slice("@", 0).get_slice(".", 0).replace("-", "_")
	var parts := clean.split("_", false)
	if parts.is_empty():
		return DEFAULT
	var lang := parts[0].to_lower()
	var rest: Array[String] = []
	for i in range(1, parts.size()):
		rest.append(parts[i].to_upper())

	match lang:
		"zh":
			if "HANT" in rest or "TW" in rest or "HK" in rest or "MO" in rest:
				return "zh_Hant"
			return "zh_Hans"
		"pt":
			return "pt_BR" if "BR" in rest else "pt_PT"
		"ca":
			return "ca_valencia" if valencia else "ca"
		"nb", "nn", "no":
			return "no"
		# Java's old codes, which Android can still report.
		"iw":
			return "he"
		"in":
			return "id"
		"en":
			return "en"
	return lang if is_language(lang) else DEFAULT


static func _row(id: String) -> Array:
	for row: Array in LANGUAGES:
		if str(row[0]) == id:
			return row
	return []
