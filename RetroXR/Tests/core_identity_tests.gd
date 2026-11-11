extends "res://Tests/test_suite.gd"

## The player's name and language as libretro cores are told them
## (GET_USERNAME, GET_LANGUAGE): CoreLanguage's locale mapping, the two prefs on
## OPTIONS > Systems, and the extension's setters. Until 2026-11-11 every core
## was told "DefaultUser" and English.

func _ready() -> void:
	suite_tag = "core_identity"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[core_identity] TIMEOUT")
		get_tree().quit(1))

	_test_locales()
	_test_table()
	_test_prefs()
	_test_player_name()
	_test_extension()
	_finish()


## System locales as Godot reports them, on desktop and on Android.
func _test_locales() -> void:
	var cases := {
		"en_US": "en", "en_GB": "en", "en": "en",
		"ja_JP": "ja", "ja": "ja",
		"fr_CA": "fr", "de_DE": "de", "es_MX": "es", "it_IT": "it", "nl_NL": "nl",
		"pt_BR": "pt_BR", "pt_PT": "pt_PT", "pt": "pt_PT", "pt-BR": "pt_BR",
		"zh_CN": "zh_Hans", "zh_SG": "zh_Hans", "zh": "zh_Hans",
		"zh_TW": "zh_Hant", "zh_HK": "zh_Hant", "zh_Hant_TW": "zh_Hant", "zh_Hans_CN": "zh_Hans",
		"ko_KR": "ko", "ru_RU": "ru", "pl_PL": "pl", "sv_SE": "sv",
		"nb_NO": "no", "nn_NO": "no",
		"iw_IL": "he", "in_ID": "id",
		"ca_ES": "ca", "ca_ES@valencia": "ca_valencia",
		"de_DE.UTF-8": "de",
		"xx_YY": "en", "": "en",
	}
	for locale: String in cases:
		_eq(CoreLanguage.for_locale(locale), cases[locale], "locale/'%s'" % locale)


## Every row's enum value is libretro.h's, and each appears once.
func _test_table() -> void:
	var seen := {}
	for row: Array in CoreLanguage.LANGUAGES:
		var value := int(row[2])
		_ok(not seen.has(value), "table/%s's value %d is used once" % [row[0], value])
		seen[value] = true
		_ok(value >= 0 and value <= 36, "table/%s within libretro.h's range" % row[0])
	_eq(seen.size(), 37, "table/every retro_language below RETRO_LANGUAGE_LAST is offered")
	_eq(CoreLanguage.retro_language("ja"), 1, "table/Japanese is 1")
	_eq(CoreLanguage.retro_language("zh_Hant"), 11, "table/Chinese (Traditional) is 11")
	_eq(CoreLanguage.retro_language("nonsense"), 0, "table/unknown reads as English")


## Both prefs start automatic and survive a save and a load; a bad language is dropped.
func _test_prefs() -> void:
	_eq(_app_prefs_default("player_name"), "", "prefs/name starts automatic")
	_eq(_app_prefs_default("core_language"), "", "prefs/language starts automatic")
	var back := _app_prefs_round_trip({"player_name": "Ada", "core_language": "pt_BR"})
	_eq(back.get("player_name"), "Ada", "prefs/name survives a save and a load")
	_eq(back.get("core_language"), "pt_BR", "prefs/language survives a save and a load")
	back = _app_prefs_round_trip({"core_language": "klingon"})
	_eq(back.get("core_language"), "", "prefs/an unknown language reads as automatic")


## The name is cleaned, and the automatic one is never empty.
func _test_player_name() -> void:
	var prefs := get_node("/root/AppPrefs")
	var script := prefs.get_script() as GDScript
	_eq(script.call("_clean_player_name", "  Ada\n\tLovelace  "), "AdaLovelace",
		"name/control characters are dropped and the ends trimmed")
	_eq(str(script.call("_clean_player_name", "x".repeat(50))).length(), 32,
		"name/cut to 32 characters")
	_ok(not str(prefs.auto_player_name()).is_empty(), "name/the automatic name is never empty")
	if OS.get_name() == "Windows":
		_eq(script.call("os_login_name"), OS.get_environment("USERNAME"),
			"name/the Windows login name comes from USERNAME")


## The extension takes both. Skipped where it did not load (no build for this
## platform), which other suites already report.
func _test_extension() -> void:
	if not ClassDB.class_exists("Libretro"):
		print("[core_identity] Libretro not loaded; extension checks skipped")
		return
	_ok(ClassDB.class_has_method("Libretro", "SetUsername"), "extension/SetUsername is bound")
	_ok(ClassDB.class_has_method("Libretro", "SetLanguage"), "extension/SetLanguage is bound")
	# Out of range must not crash; it reads as English.
	ClassDB.class_call_static("Libretro", "SetLanguage", 999)
	ClassDB.class_call_static("Libretro", "SetLanguage", -1)
	ClassDB.class_call_static("Libretro", "SetUsername", "")
	get_node("/root/AppPrefs").apply_core_identity()
	_ok(true, "extension/setters take odd values")
