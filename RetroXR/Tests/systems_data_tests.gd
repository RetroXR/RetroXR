## systems_data_tests — two small tables with outsized consequences.
##
## SystemFilter decides which of the core-info database's 139 systemids a player
## can browse at all: too eager and a real console vanishes from the Download
## grid with nothing to say why, too shy and the grid fills with media players
## and libretro's own test core.
##
## BindingStore is the merge underneath every control override. binding_tests
## already covers what ControllerBindings and GamepadBindings do with it; this
## covers the store itself, which is the part both of them share and neither
## owns — three rules, and each one is a way a player's remap can be silently
## lost or silently applied to the wrong console.
##
## ByteSize and PadInputShared are here for the same reason: both were extracted
## from a pair of byte-identical copies, so what they own is a rule two callers
## must agree on, and a disagreement between them is silent. The rounding a
## player reads on a download row, and which bit a stick pushed.
##
## SystemIds is the table behind the 2026-09-18 rename of every systemid to
## ES-DE's folder name. ids/ pins the things that go wrong SILENTLY: a refreshed
## .info bringing an old id back, a descriptor or icon left under its old name
## (a missing icon falls back to the default with no error), and -- the other
## direction -- one of the three look-alike namespaces getting renamed too.
##
## No disk beyond a scratch file this suite writes and removes.
##
##   "$godot" --headless --path RetroXR res://Tests/systems_data_tests.tscn
extends Node

## Cases in this file, NOT counting the guard below -- it is checked before it
## has recorded itself. See card_tests on why this exists.
const EXPECTED_CASES := 84

var _passed := 0
var _failed := 0

var _path := ""


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[sysdata] TIMEOUT")
		get_tree().quit(1))

	_path = OS.get_user_data_dir().path_join("__bindingstore_selftest.json")

	_group_filter()
	_group_store()
	_group_bytes()
	_group_dpad()
	_group_ids()

	_eq(_passed + _failed, EXPECTED_CASES, "suite/every case ran")

	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)
	print("[sysdata] %d checks, %d failed" % [_passed + _failed, _failed])
	print("[sysdata] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(cond: bool, what: String, detail := "") -> void:
	if cond:
		_passed += 1
		print("[sysdata] ok   %s" % what)
	else:
		_failed += 1
		print("[sysdata] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [got, want])


# ── filter/ ───────────────────────────────────────────────────────────────────

func _group_filter() -> void:
	# Real consoles must never be hidden. This is the direction that costs a
	# player a platform they own games for.
	for sid: String in ["nes", "snes", "psx", "n64", "wii",
			"gb", "genesis", "dreamcast"]:
		_ok(not SystemFilter.is_hidden(sid), "filter/%s stays browsable" % sid)

	# And the three groups that are not consoles do go.
	_ok(SystemFilter.is_hidden("wolfenstein"),
		"filter/an FPS engine is hidden")
	_ok(not SystemFilter.hidden_ids().is_empty(), "filter/something is hidden")

	# hidden_ids is the union of the three groups, sorted, with no repeats — a
	# settings screen lists it directly.
	var ids := SystemFilter.hidden_ids()
	var sorted_copy := ids.duplicate()
	sorted_copy.sort()
	_eq(ids, sorted_copy, "filter/hidden_ids comes back sorted")
	var seen: Dictionary = {}
	var dupes := 0
	for sid: String in ids:
		if seen.has(sid):
			dupes += 1
		seen[sid] = true
	_eq(dupes, 0, "filter/and carries no systemid twice")
	for sid: String in ids:
		if not SystemFilter.is_hidden(sid):
			_ok(false, "filter/every listed id really is hidden", sid)
			break
	_ok(true, "filter/every listed id really is hidden")

	# The two filters must agree with is_hidden, since the widgets use one and
	# the probes the other.
	var mixed: Array[String] = ["nes", "wolfenstein", "psx"]
	var kept := SystemFilter.filter_ids(mixed)
	_ok(kept.has("nes") and kept.has("psx"),
		"filter/filter_ids keeps the consoles")
	_ok(not kept.has("wolfenstein"), "filter/and drops the hidden one")
	var rows := SystemFilter.filter_systems([
		{"systemid": "nes"}, {"systemid": "wolfenstein"}, {"no_key": 1}])
	_eq(rows.size(), 2, "filter/filter_systems drops the hidden row")
	_ok(str((rows[1] as Dictionary).get("systemid", "")).is_empty(),
		"filter/a row with no systemid is kept rather than guessed at")

	# The switch is what a probe uses to see the unfiltered database.
	SystemFilter.enabled = false
	_ok(not SystemFilter.is_hidden("wolfenstein"),
		"filter/disabling the filter unhides everything")
	SystemFilter.enabled = true
	_ok(SystemFilter.is_hidden("wolfenstein"), "filter/and re-enabling restores it")


# ── store/ ────────────────────────────────────────────────────────────────────

## default -> global -> per-system, in that order. Three rules, each of which is
## a way a remap gets lost.
func _group_store() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)

	# A store that does not exist yet is empty, not an error: it is every
	# player's first launch.
	_eq(BindingStore.load_file(_path, "SelfTest"), {}, "store/a missing file reads empty")
	_ok(not BindingStore.has_system_override(_path, "SelfTest", "nes"),
		"store/and has no overrides")
	_eq(BindingStore.overridden_systems(_path, "SelfTest"), [] as Array[String],
		"store/nor anything to list")

	# The merge itself. Later layers win key by key, and a key only the base
	# carries survives -- that is what makes a per-system profile an override of
	# a few buttons rather than a replacement of the whole map.
	var base := {"a": 1, "b": 2, "c": 3}
	var glob := {"b": 20}
	var per := {"c": 300}
	var merged := BindingStore.merge(base, glob, per)
	_eq(merged.get("a"), 1, "store/a key only the default has survives")
	_eq(merged.get("b"), 20, "store/global beats the default")
	_eq(merged.get("c"), 300, "store/and per-system beats both")
	_eq(base.get("b"), 2, "store/merging does not write back into the default")

	# A per-system profile SHADOWS global completely for the keys it names,
	# including edits made to global afterwards -- which is why a profile is
	# always written whole.
	_eq(BindingStore.merge({"x": 1}, {"x": 2}, {"x": 3}).get("x"), 3,
		"store/the last layer wins outright")

	# Round trip, then the override lifecycle.
	# The per-platform key is "per_system"; values are strings here because JSON
	# turns an int into a float on the way back and this suite is about the
	# store's shape, not about that -- there is a case for it below.
	_ok(BindingStore.save_file(_path, "SelfTest", {"global": {"a": "one"},
		"per_system": {"nes": {"a": "nine"}}}), "store/a store writes")
	_ok(BindingStore.has_system_override(_path, "SelfTest", "nes"),
		"store/a written profile reads back as an override")
	_ok(not BindingStore.has_system_override(_path, "SelfTest", "snes"),
		"store/a platform with no profile has none")
	_ok(BindingStore.overridden_systems(_path, "SelfTest").has("nes"),
		"store/and is listed")

	# Clearing one puts that platform back on global WITHOUT touching anyone
	# else's -- the rule that stops a reset becoming a wipe.
	BindingStore.save_file(_path, "SelfTest", {"global": {"a": "one"},
		"per_system": {"nes": {"a": "nine"}, "genesis": {"a": "eight"}}})
	BindingStore.clear_system_override(_path, "SelfTest", "nes")
	_ok(not BindingStore.has_system_override(_path, "SelfTest", "nes"),
		"store/clearing removes that platform's profile")
	_ok(BindingStore.has_system_override(_path, "SelfTest", "genesis"),
		"store/and leaves every other platform alone")
	_eq(BindingStore.load_file(_path, "SelfTest").get("global"), {"a": "one"},
		"store/the global layer is untouched by clearing a platform")

	# layers() is what the two binding classes actually call, and it must report
	# an absent profile as an empty layer rather than as a missing one.
	var pair := BindingStore.layers(_path, "SelfTest", "genesis")
	_eq(pair.size(), 2, "store/layers always returns both layers")
	_eq(pair[0], {"a": "one"}, "store/the global layer first")
	_eq(pair[1], {"a": "eight"}, "store/then the platform's own")
	_eq(BindingStore.layers(_path, "SelfTest", "snes")[1], {},
		"store/a platform with no profile gets an empty second layer")
	_eq(BindingStore.layers(_path, "SelfTest", "")[1], {},
		"store/and so does the global page, which names no platform")

	# A number written to a binding store comes back a FLOAT: JSON has one
	# numeric type and Godot parses it as double. Anything comparing a read-back
	# value to an int literal fails on a value it wrote itself, which is why the
	# stores that carry counts int() them at the read.
	BindingStore.save_file(_path, "SelfTest", {"global": {"n": 7}})
	var n: Variant = (BindingStore.load_file(_path, "SelfTest")["global"] as Dictionary)["n"]
	_eq(typeof(n), TYPE_FLOAT, "store/an int comes back from JSON as a float")
	_eq(int(n), 7, "store/and is still the number that was written")


## ── bytes/ ────────────────────────────────────────────────────────────────────
##
## ByteSize exists because the rounding was written twice and the two copies
## could disagree about the same file with nothing to say so -- MenuStyle's own
## comment asked callers to "agree on the rounding", and then a byte-identical
## copy grew in RommDownloader. Pinning the rounding is therefore the whole
## point of the class, not incidental to it.
##
## Binary units with the decimal LABELS the platforms use, deliberately, and one
## decimal place only at GB.
func _group_bytes() -> void:
	_eq(ByteSize.human(0), "0 B", "bytes/nothing is nothing")
	_eq(ByteSize.human(17), "17 B", "bytes/a small count is plain bytes")
	_eq(ByteSize.human(ByteSize.KB - 1), "1023 B",
		"bytes/one below a kilobyte is still bytes")

	# Each threshold is the FIRST value of its unit. An off-by-one here is the
	# classic way "1024 B" reaches a player.
	_eq(ByteSize.human(ByteSize.KB), "1 KB", "bytes/a kilobyte exactly")
	_eq(ByteSize.human(ByteSize.MB), "1 MB", "bytes/a megabyte exactly")
	_eq(ByteSize.human(ByteSize.GB), "1.0 GB", "bytes/a gigabyte exactly")
	_eq(ByteSize.human(ByteSize.MB - 1), "1024 KB",
		"bytes/one below a megabyte is still kilobytes")

	# Whole units below GB, one decimal at and above it: the step between whole
	# gigabytes is large enough that rounding away the decimal would lose real
	# information about a download someone is deciding whether to start.
	_eq(ByteSize.human(ByteSize.MB * 3 + ByteSize.KB * 512), "4 MB",
		"bytes/megabytes round to whole units")
	_eq(ByteSize.human(ByteSize.GB * 3 + ByteSize.MB * 400), "3.4 GB",
		"bytes/gigabytes keep one decimal")

	# Reads the length rather than the file: get_file_as_bytes would pull a whole
	# core download into memory to answer a question about its size.
	var probe := OS.get_user_data_dir().path_join("__bytesize_selftest.bin")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
	f.close()
	_eq(ByteSize.on_disk(probe), 5, "bytes/a file on disk reports its length")
	DirAccess.remove_absolute(probe)
	_eq(ByteSize.on_disk(probe), 0, "bytes/a file that is gone reports 0")
	_eq(ByteSize.on_disk(""), 0, "bytes/no path, no size")


## ── dpad/ ─────────────────────────────────────────────────────────────────────
##
## PadInputShared.threshold_to_dpad, the stick-as-d-pad read shared by a held
## controller and a handheld console. It was forked between the two files before
## this class existed, so a fix here had to be made twice and was not.
##
## The bit positions are RetroPad's, and getting one wrong does not fail loudly:
## a player simply walks the wrong way. Each direction is asserted by its own
## bit rather than against a bundled constant, so a transposition cannot be
## copied from the code into the test.
func _group_dpad() -> void:
	_eq(PadInputShared.threshold_to_dpad(Vector2.ZERO), 0,
		"dpad/a centred stick presses nothing")

	# +y is UP. The sign convention is the thing most likely to be inverted, and
	# an inverted pair still passes any test that only counts bits.
	_eq(PadInputShared.threshold_to_dpad(Vector2(0, 1)), 1 << 4, "dpad/up is bit 4")
	_eq(PadInputShared.threshold_to_dpad(Vector2(0, -1)), 1 << 5, "dpad/down is bit 5")
	_eq(PadInputShared.threshold_to_dpad(Vector2(-1, 0)), 1 << 6, "dpad/left is bit 6")
	_eq(PadInputShared.threshold_to_dpad(Vector2(1, 0)), 1 << 7, "dpad/right is bit 7")

	# A diagonal is both, not the larger one: a stick held between two directions
	# on a menu grid must be able to move diagonally.
	_eq(PadInputShared.threshold_to_dpad(Vector2(1, 1)), (1 << 4) | (1 << 7),
		"dpad/a diagonal presses both")

	# The threshold is a real deadzone, and it is exclusive: a stick resting just
	# inside it must read as centred or a controller drifts on its own.
	var t := PadInputShared.DPAD_THRESHOLD
	_eq(PadInputShared.threshold_to_dpad(Vector2(t, 0)), 0,
		"dpad/exactly at the threshold is not a press")
	_eq(PadInputShared.threshold_to_dpad(Vector2(t - 0.01, 0)), 0,
		"dpad/just inside the deadzone is not a press")
	_eq(PadInputShared.threshold_to_dpad(Vector2(t + 0.01, 0)), 1 << 7,
		"dpad/just past it is")
	_eq(PadInputShared.threshold_to_dpad(Vector2(-t, -t)), 0,
		"dpad/a diagonal inside the deadzone presses nothing either")


# ── ids/ ───────────────────────────────────────────────────────────────────────

func _group_ids() -> void:
	_eq(SystemIds.canonical("super_nes"), "snes", "ids/an old id reads as the new one")
	_eq(SystemIds.canonical("snes"), "snes", "ids/a new id is left alone")
	_eq(SystemIds.canonical("ereader"), "ereader", "ids/so is one ES-DE has no folder for")
	_eq(SystemIds.canonical("mega_drive"), "genesis", "ids/Sega's primary is the US name")
	_eq(SystemIds.canonical("cdi"), "cdi", "ids/and the CD-i kept its own")

	var chained: Array[String] = []
	var seen: Dictionary = {}
	var shared: Array[String] = []
	for old: String in SystemIds.LEGACY:
		var now: String = SystemIds.LEGACY[old]
		if SystemIds.LEGACY.has(now):
			chained.append(old)
		if seen.has(now):
			shared.append(now)
		seen[now] = true
	_ok(chained.is_empty(), "ids/no new id is itself an old one", str(chained))
	_ok(shared.is_empty(), "ids/no two old ids became the same system", str(shared))

	# The one that goes red after libretro-core-info is refreshed from a fork that
	# was not renamed. Fix with Tools/rename_systemids.py, not by editing this.
	var stale: Array[String] = []
	for entry: Dictionary in CoreInfoDatabase.shared().cores:
		for sid: String in CoreInfoDatabase.systemids_of(entry):
			if SystemIds.LEGACY.has(sid):
				stale.append("%s: %s" % [entry.get("core_name", "?"), sid])
	_ok(stale.is_empty(), "ids/no .info declares an old id", str(stale))
	_ok(not CoreInfoDatabase.shared().get_by_systemid("snes").is_empty()
			and CoreInfoDatabase.shared().get_by_systemid("super_nes").is_empty(),
		"ids/and the cores are indexed under the new one")

	var misnamed: Array[String] = []
	var iconless: Array[String] = []
	for file_name: String in DirAccess.get_files_at("res://SystemInfo"):
		var stem := file_name.trim_suffix(".remap").get_basename()
		if file_name.trim_suffix(".remap").get_extension() != "tres":
			continue
		var info := load("res://SystemInfo/%s.tres" % stem) as SystemInfo
		if info == null or info.systemid != stem or SystemIds.LEGACY.has(stem):
			misnamed.append(stem)
		# Only a system that was renamed: a few (pico8) never had art, and a missing
		# icon falls back to the default without a word, which is the point of asking.
		if seen.has(stem) and not ResourceLoader.exists("res://Textures/SystemIcons/%s.svg" % stem):
			iconless.append(stem)
	for old: String in SystemIds.LEGACY:
		if ResourceLoader.exists("res://Textures/SystemIcons/%s.svg" % old):
			iconless.append("%s (still under its old name)" % old)
	_ok(misnamed.is_empty(), "ids/every descriptor is filed under the id it carries, and a new one",
		str(misnamed))
	_ok(iconless.is_empty(), "ids/and every renamed one took its icon with it", str(iconless))
	_ok(SystemInfo.for_system("nintendo_64") == SystemInfo.for_system("n64")
			and SystemInfo.for_system("n64") != null,
		"ids/a descriptor is still found by the id it used to have")

	_eq(Array(SystemIds.folder_names("snes")), ["snes", "super_nes", "sfc", "snesna"],
		"ids/a ROM folder is looked for under the id, then the old id, then ES-DE's others")
	_ok(SystemIds.systemid_for_folder("sfc") == "snes"
			and SystemIds.systemid_for_folder("super_nes") == "snes"
			and SystemIds.systemid_for_folder("famicom") == "famicom",
		"ids/and a folder names its system back, the Famicom staying its own")
	var squatters: Array[String] = []
	for owner: String in SystemIds.FOLDER_ALIASES:
		for alias: String in SystemIds.FOLDER_ALIASES[owner]:
			if SystemInfo.for_system(alias) != null or seen.has(alias):
				squatters.append(alias)
	_ok(squatters.is_empty(), "ids/no other folder name is a system of its own", str(squatters))

	_eq(SystemIds.rekeyed({"super_nes": 1, "nes": 2}), {"snes": 1, "nes": 2},
		"ids/a table off the player's disk is read under the new ids")
	_eq(SystemIds.rekeyed({"super_nes": 1, "snes": 3}), {"snes": 3},
		"ids/and under both names, what was written since the rename wins")
	_eq(SystemIds.rekeyed_paths({"game_boy/Tetris.gb": 7, "bare": 8}),
		{"gb/Tetris.gb": 7, "bare": 8}, "ids/so is one keyed by <systemid>/<file>")

	# The three look-alikes. Each is persisted under the name it has.
	var ps1 := CardFormats.for_system("psx")
	_ok(ps1 != null and ps1.id() == "playstation" and ps1.romm_systemid() == "psx",
		"ids/a card family kept its name, and says which SYSTEM it belongs to in the new one")
	_ok(ExpansionCatalog.has("sega_cd") and ExpansionCatalog.media_of("sega_cd") == "segacd"
			and not ExpansionCatalog.has("segacd"),
		"ids/an expansion unit kept its id, and its media is the new systemid")
	_eq(str(SystemModelRegistry.resolve("playstation", "psx").get("platform", "")), "psx",
		"ids/a model kept its id, and its platform is the new systemid")

