## ScraperConfig — stores screenscraper.fr credentials and preferences.
## Developer credentials are hardcoded; user credentials and priorities are persisted.
class_name ScraperConfig
extends RefCounted


## Developer credentials (hardcoded).
const DEV_ID := "XenuIsWatching"
const DEV_PASSWORD := "cRF2f81Fdgi"
const SOFT_NAME := "retroxr"

## User credentials (persisted).
var ssid: String = ""
var sspassword: String = ""

## Region priority for selecting localized content (first match wins).
## "wor" = worldwide (screenscraper's code for universal assets, e.g. English wheel logos).
var region_priorities: Array[String] = ["us", "eu", "wor", "jp", "ss"]

## Language priority for selecting localized text (first match wins).
var language_priorities: Array[String] = ["en", "fr"]

## The regions the options menu offers for region_priorities: [code, name, flag].
## Codes are ScreenScraper's own (regionsListe.php, checked 2026-09-23) -- note
## Spain is "sp" and Mexico "mex", not their ISO codes. The flag column is a key
## for MenuIcons.region_flag(); "" draws none. Continents it also lists (afr,
## ame, oce, mor) and the tiny markets are left out; a code saved that is not
## here is still kept and shown by its code.
const REGIONS := [
	["us", "USA", "us"],
	["eu", "Europe", "eu"],
	["wor", "World", "wor"],
	["jp", "Japan", "jp"],
	["ss", "ScreenScraper", ""],
	["uk", "United Kingdom", "uk"],
	["fr", "France", "fr"],
	["de", "Germany", "de"],
	["sp", "Spain", "es"],
	["it", "Italy", "it"],
	["nl", "Netherlands", "nl"],
	["pt", "Portugal", "pt"],
	["se", "Sweden", "se"],
	["no", "Norway", "no"],
	["dk", "Denmark", "dk"],
	["fi", "Finland", "fi"],
	["pl", "Poland", "pl"],
	["cz", "Czech Republic", "cz"],
	["hu", "Hungary", "hu"],
	["gr", "Greece", "gr"],
	["tr", "Turkey", "tr"],
	["ru", "Russia", "ru"],
	["il", "Israel", "il"],
	["au", "Australia", "au"],
	["nz", "New Zealand", "nz"],
	["ca", "Canada", "ca"],
	["mex", "Mexico", "mx"],
	["br", "Brazil", "br"],
	["kr", "Korea", "kr"],
	["cn", "China", "cn"],
	["tw", "Taiwan", "tw"],
	["asi", "Asia", "asi"],
]

## The languages offered for language_priorities: [code, name, flag], from
## languesListe.php (checked 2026-09-23) -- Korean is "kr" and Czech "cz" there.
## The flag is the country a player would look for, not a claim about the
## language. Slovak is left out: the flag font has no Slovakia.
const LANGUAGES := [
	["en", "English", "uk"],
	["fr", "French", "fr"],
	["de", "German", "de"],
	["es", "Spanish", "es"],
	["it", "Italian", "it"],
	["pt", "Portuguese", "pt"],
	["nl", "Dutch", "nl"],
	["sv", "Swedish", "se"],
	["no", "Norwegian", "no"],
	["da", "Danish", "dk"],
	["fi", "Finnish", "fi"],
	["pl", "Polish", "pl"],
	["cz", "Czech", "cz"],
	["hu", "Hungarian", "hu"],
	["tr", "Turkish", "tr"],
	["ru", "Russian", "ru"],
	["ja", "Japanese", "jp"],
	["kr", "Korean", "kr"],
	["zh", "Chinese", "cn"],
	["tw", "Taiwanese", "tw"],
]

## Show each scrape result for approval before it is written. Off by default:
## a queued batch would otherwise stop at a popup after every game.
var approve_scrapes: bool = false

## Scrape a ROM's metadata on its own once it arrives (a RomM download, a
## netplay hash match). On by default, with or without an account: the
## anonymous allowance is small, but AutoScraper queues only games with no
## metadata, one at a time, and a failed scrape is silent.
var auto_scrape: bool = true

## Whether the web file server should auto-start on launch.
var web_server_enabled: bool = false

## 4-digit PIN required to log in to the web file server (persisted).
var web_server_pin: String = ""


## Returns the web-server PIN, generating & persisting a random 4-digit one if unset.
##
## From the crypto RNG, for the reason WebFileServer._gen_token already states
## about its own tokens: randi() is a SEEDED PRNG, so its stream is reproducible
## and a value drawn from it can be predicted rather than guessed. This PIN is
## the only thing standing between anyone on the same network and the player's
## ROM and save directories, and there are only 10000 of them — it should at
## least cost an attacker all 10000.
##
## Rejection sampling rather than a plain modulo: 2^32 is not a multiple of
## 10000, so the low 7296 values would come up fractionally more often than the
## rest. The loop discards the short tail instead, and retries with probability
## under one in half a million.
func ensure_web_server_pin() -> String:
	if web_server_pin.length() != 4 or not web_server_pin.is_valid_int():
		web_server_pin = "%04d" % _random_pin()
		save_config()
	return web_server_pin


func _random_pin() -> int:
	var crypto := Crypto.new()
	var limit := 4294967296 - (4294967296 % 10000)
	while true:
		var bytes := crypto.generate_random_bytes(4)
		var value := bytes.decode_u32(0)
		if value < limit:
			return value % 10000
	return 0


func load_config() -> void:
	# parse_dict, not read_dict: the two failures mean opposite things to a
	# config. A file that cannot be read at all -- missing, or damaged --
	# comes back null and leaves every field standing, while a file that
	# parses but is not an object comes back {} and falls through to the
	# defaults below. read_dict flattens both to {}, which would quietly
	# reset stored credentials on a corrupt file; ra_tests pins both.
	var raw: Variant = JsonStore.parse_dict(_config_path(), "ScraperConfig")
	if raw == null:
		return
	var data: Dictionary = raw
	ssid = data.get("ssid", "")
	sspassword = data.get("sspassword", "")

	if data.has("region_priorities") and data["region_priorities"] is Array:
		region_priorities.clear()
		for r in data["region_priorities"]:
			region_priorities.append(str(r))

	if data.has("language_priorities") and data["language_priorities"] is Array:
		language_priorities.clear()
		for l in data["language_priorities"]:
			language_priorities.append(str(l))

	approve_scrapes = bool(data.get("approve_scrapes", false))
	auto_scrape = bool(data.get("auto_scrape", true))
	web_server_enabled = bool(data.get("web_server_enabled", false))
	web_server_pin = str(data.get("web_server_pin", ""))

	print("[ScraperConfig] Loaded config")


func save_config() -> bool:
	var path := _config_path()
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var data := {
		"ssid": ssid,
		"sspassword": sspassword,
		"region_priorities": region_priorities,
		"language_priorities": language_priorities,
		"approve_scrapes": approve_scrapes,
		"auto_scrape": auto_scrape,
		"web_server_enabled": web_server_enabled,
		"web_server_pin": web_server_pin,
	}
	return JsonStore.write_dict(path, data, "ScraperConfig")


static func _config_path() -> String:
	return RomLibrary.default_roms_root().path_join("scraper_config.json")
