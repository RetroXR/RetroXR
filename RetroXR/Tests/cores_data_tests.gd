## cores_data_tests — the pure-logic half of the core layer.
##
## Four classes that decide what a core IS and what it must be told, none of
## which had a test: CoreInfoParser (reading a libretro .info), CoreSources (the
## cores this project builds itself rather than taking from the buildbot),
## ForcedCoreOptions (the options that make hardware that hardware) and
## DownloadManifest (what is installed and how old it is).
##
## None of it needs a core, a ROM or the network. The parser is given files this
## suite writes; the rest are tables and rules.
##
## `packaging/` is the odd one out: it reads `export_presets.cfg` rather than
## game code, because the .info files are the input every other class here reads
## and NOTHING at runtime can report that a build shipped without them. A
## desktop preset that lost `include_filter="**/*.info"` produces an empty
## `CoreInfoDatabase`, and the app that reads it looks healthy.
##
## ForcedCoreOptions is the part worth having covered. Every answer in it was
## MEASURED against a real core and the reasons are written out beside each one
## — a 64DD with its drive switched off has nothing to load a disk into, an N64
## whose core defaults to "Expansion Pak installed" has 8 MB whether or not a
## player placed the pack. A wrong answer here is a machine that boots to a
## black screen, which is exactly the failure that reads as "the emulator is
## broken" rather than as a setting.
##
##   "$godot" --headless --path RetroXR res://Tests/cores_data_tests.tscn
extends Node

## Cases in this file, NOT counting the guard below -- it is checked before
## it has recorded itself.
const EXPECTED_CASES := 80

var _passed := 0
var _failed := 0

var _dir := ""


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[cores] TIMEOUT")
		get_tree().quit(1))

	_dir = OS.get_user_data_dir().path_join("__cores_selftest")
	DirAccess.make_dir_recursive_absolute(_dir)

	_group_parser()
	_group_packaging()
	_group_sources()
	_group_forced()
	_group_manifest()
	_group_recommended()

	# A case that never RAN is not a case that passed. GDScript has no
	# try/catch, so one bad index aborts the function it is in and every case
	# after it simply never prints -- mutation-testing this suite is how that was
	# found here, exactly as card_tests records finding it. Bump when adding.
	_eq(_passed + _failed, EXPECTED_CASES, "suite/every case ran")

	_cleanup()
	print("[cores] %d checks, %d failed" % [_passed + _failed, _failed])
	print("[cores] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while not n.is_empty():
		if not d.current_is_dir():
			DirAccess.remove_absolute(_dir.path_join(n))
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(_dir)


func _ok(cond: bool, what: String, detail := "") -> void:
	if cond:
		_passed += 1
		print("[cores] ok   %s" % what)
	else:
		_failed += 1
		print("[cores] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [got, want])


func _write(name: String, text: String) -> String:
	var path := _dir.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


# ── parser/ ───────────────────────────────────────────────────────────────────

func _group_parser() -> void:
	var path := _write("fceumm_libretro.info",
		"# a comment\n"
		+ "display_name = \"Nintendo - NES\"\n"
		+ "\n"
		+ "supported_extensions = \"nes|fds|unf\"\n"
		+ "categories = Emulator\n"
		+ "  spaced_key   =   \"trimmed\"  \n"
		+ "novalue\n"
		+ "= orphan\n"
		+ "url = \"http://example.com/a=b\"\n")
	var info := CoreInfoParser.parse_info_file(path)

	# The core name is the FILENAME's, not a field: it is what matches the
	# library on disk (fceumm_libretro.dll), so it cannot come from the content.
	_eq(info.get("core_name", "<none>"), "fceumm", "parser/the core name comes off the filename")
	_eq(info.get("info_path", "<none>"), path, "parser/the path is carried through")

	_eq(info.get("display_name", "<none>"), "Nintendo - NES", "parser/a quoted value is unquoted")
	_eq(info.get("categories", "<none>"), "Emulator", "parser/an unquoted value is taken as-is")
	_eq(info.get("spaced_key", "<none>"), "trimmed", "parser/keys and values are trimmed")
	_ok(not info.has("#"), "parser/a comment line is skipped")
	_ok(not info.has("novalue"), "parser/a line with no = is skipped")
	# Split on the FIRST = only, or a URL with a query string loses its tail.
	_eq(info.get("url", "<none>"), "http://example.com/a=b", "parser/only the first = splits")
	_ok(not info.has(""), "parser/a line starting with = contributes no empty key")

	# "notes" is the one multi-line key, and its own separator is "|" — joining
	# rather than last-wins is what keeps a firmware checksum table whole.
	var notes := CoreInfoParser.parse_info_file(_write("bk_libretro.info",
		"notes = \"first\"\nnotes = \"second\"\nother = \"a\"\nother = \"b\"\n"))
	_eq(notes.get("notes", "<none>"), "first|second", "parser/notes lines are joined, not replaced")
	_eq(notes.get("other", "<none>"), "b", "parser/every other key is last-wins")

	# A file that is not there is not a crash, and still reports what it can.
	var missing := CoreInfoParser.parse_info_file(_dir.path_join("nope_libretro.info"))
	_eq(missing.get("core_name", "<none>"), "nope", "parser/a missing file still names its core")


# ── packaging/ ────────────────────────────────────────────────────────────────

## Every `.info` in the project, as paths relative to it — the shape the export
## filter is tested against.
static func _info_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "info":
			out.append("%s/%s" % [dir.trim_prefix("res://"), f])
	out.sort()
	return out


## Whether a preset's include_filter carries `rel_path` into the build. This
## mirrors the exporter's own test — the filter is a comma-separated list of
## patterns, a file is shipped when its path matches one, and the patterns are
## matched with String.match, whose `*` crosses a "/". That is why `*.info`
## reaches a directory two levels down, and why the controls at the end of the
## group are stated the way they are.
static func _filter_ships(filter_line: String, rel_path: String) -> bool:
	for raw: String in filter_line.split(","):
		if rel_path.match(raw.strip_edges()):
			return true
	return false


## The first few offenders, so a red run NAMES the presets and the files
## instead of counting them.
static func _named(items: Array[String]) -> String:
	if items.size() <= 4:
		return ", ".join(items)
	return "%s (+%d more)" % [", ".join(items.slice(0, 4)), items.size() - 4]


## How the .info files reach a build AT ALL, which is the one link in the chain
## that no runtime code can report on. A `.info` has no Godot importer, so
## `export_filter="all_resources"` does not carry it — only include_filter does,
## and until 2026-09-25 only the Android presets had one. A desktop export then
## ships an EMPTY CoreInfoDatabase, and nothing says so anywhere: the Cores panel
## still lists every installed library by filename, but with no .info behind it
## `systemids_of()` answers empty, every core is filed under the "unknown" bucket,
## `CoreDefaults.adopt_missing()` adopts nothing, and the Systems tab is left with
## a single tile named after whichever core sorted first. A fresh Linux install
## reproduced it exactly: 51 cores downloaded, and a `core_defaults.json`
## holding `{"unknown": "arduous"}`.
##
## So the group reads the FILTERS rather than the preset names, and asserts
## against the real file list: nothing inside a running build can tell one that
## lost its .info files from one that kept them.
func _group_packaging() -> void:
	var cfg := ConfigFile.new()
	_eq(cfg.load("res://export_presets.cfg"), OK, "packaging/the export presets parse")

	# Every "[preset.N]", and not the "[preset.N.options]" child of each.
	var sections: Array[String] = []
	for s: String in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options"):
			sections.append(s)
	_ok(sections.size() > 1, "packaging/there is more than one preset to check",
		"got %d" % sections.size())

	# The files the filters are asked about, so a case below cannot pass on an
	# empty directory. The vendored path is a literal because
	# load_from_project() names it inline; OVERLAY_DIR is the constant it uses.
	var vendored := _info_files("res://libretro-core-info")
	var overlay := _info_files(CoreInfoDatabase.OVERLAY_DIR)
	_ok(not vendored.is_empty(), "packaging/the vendored core-info set is in the project",
		"%d files" % vendored.size())
	_ok(not overlay.is_empty(), "packaging/so is the retroXR overlay laid over it",
		"%d files" % overlay.size())
	var all_info := vendored + overlay

	# The case the fix is for. Aggregate over presets and files on purpose: one
	# case per preset would make this suite's own total move whenever a preset is
	# added or a probe retired, and a red count reads as a broken suite.
	var unshipped: Array[String] = []
	for section: String in sections:
		var filter_line := str(cfg.get_value(section, "include_filter", ""))
		for rel: String in all_info:
			if not _filter_ships(filter_line, rel):
				unshipped.append("%s: %s" % [cfg.get_value(section, "name", section), rel])
	_ok(unshipped.is_empty(), "packaging/every preset ships every .info file",
		_named(unshipped))

	# A superset, not an equality: a new platform's preset is fine and needs no
	# edit here, but DELETING one must not be a way to make the case above green
	# by removing the thing it checks.
	var platforms: Array[String] = []
	for section: String in sections:
		platforms.append(str(cfg.get_value(section, "platform", "")))
	var absent: Array[String] = []
	for p: String in ["Android", "Windows Desktop", "Linux", "macOS"]:
		if not platforms.has(p):
			absent.append(p)
	_ok(absent.is_empty(), "packaging/all four shipping platforms still have a preset",
		_named(absent))

	# The controls. Without them the case above cannot tell a correct filter from
	# a matcher that says yes to everything: "" and a pattern naming some other
	# extension are the shapes those three presets really carried, and the bug is
	# precisely that they shipped a build with an empty core database.
	var sample: String = all_info[0] if not all_info.is_empty() \
		else "libretro-core-info/fceumm_libretro.info"
	_ok(not _filter_ships("", sample),
		"packaging/an empty include_filter ships no .info file")
	_ok(not _filter_ships("**/*.txt", sample),
		"packaging/neither does a filter naming another extension")
	_ok(_filter_ships("**/*.info", sample),
		"packaging/while the one every preset carries does")

	# What those files are FOR: the database assembled from them, and a systemid
	# out of it. Red if the vendored set ever stops being read, which is the
	# other half of the same silent failure.
	var db := CoreInfoDatabase.shared()
	_ok(db.cores.size() > 100, "packaging/the core database is built from those files",
		"%d cores" % db.cores.size())
	_ok(CoreInfoDatabase.systemids_of(db.get_by_core_name("fceumm")).has("nes"),
		"packaging/and a core in it still names its platform")


# ── sources/ ──────────────────────────────────────────────────────────────────

## The cores this project builds itself. Every accessor must answer "" for a core
## that is not in the table, because the download manager decides between our
## release and the buildbot by asking exactly that.
func _group_sources() -> void:
	_ok(not CoreSources.has("nestopia"),
		"sources/an ordinary buildbot core is not ours")
	_eq(CoreSources.base_url("nestopia"), "", "sources/and has no release URL")
	_eq(CoreSources.api_url("nestopia"), "", "sources/nor an API URL")
	_eq(CoreSources.asset_for("nestopia"), "", "sources/nor an asset")
	_eq(CoreSources.version_of("nestopia"), "", "sources/nor a known tag")

	# dolphin is one of ours on every desktop platform.
	_ok(CoreSources.base_url("dolphin").begins_with("https://github.com/"),
		"sources/one of ours hangs off a GitHub release")
	# The /releases/latest/ form, never a tagged one: a tag here would mean every
	# core build needed a new app build to point at it.
	_ok(CoreSources.base_url("dolphin").ends_with("/releases/latest/download/"),
		"sources/the download URL is the latest form, not a tag")
	_ok(CoreSources.api_url("dolphin").begins_with("https://api.github.com/repos/"),
		"sources/and the API URL asks GitHub what latest is")
	# Both URLs must name the same repository, or the app would download one
	# build and report another's version.
	var repo := CoreSources.base_url("dolphin").trim_prefix("https://github.com/") \
		.trim_suffix("/releases/latest/download/")
	_ok(CoreSources.api_url("dolphin").contains(repo),
		"sources/the two URLs name the same repository", repo)

	# active_core_names is what the version probe walks, so it must list only
	# cores we actually build for THIS platform. Asserted as one case rather than
	# one per core: the list is platform-dependent, and a per-core case would
	# make this suite's own total differ between Windows and the Linux CI runner.
	var not_built := PackedStringArray()
	for name: String in CoreSources.active_core_names():
		if not CoreSources.has(name):
			not_built.append(name)
	_ok(not_built.is_empty(), "sources/every active core is built for this platform",
		", ".join(not_built))


# ── forced/ ───────────────────────────────────────────────────────────────────

## Options that are not preferences. Each was measured against the core.
func _group_forced() -> void:
	# The 64DD reaches a machine two ways and the systemid says only one of them:
	# a disk from the library makes a nintendo_64dd machine, while bolting the
	# drive under a console leaves it a nintendo_64 with an expansion. Asking
	# only about the systemid left the assembled machine's drive switched off.
	var by_system := ForcedCoreOptions.disk_drive("parallel_n64", "n64dd", [], "")
	_eq(by_system.get("parallel-n64-64dd-hardware"), "enabled",
		"forced/a 64DD machine switches the drive on")
	var by_expansion := ForcedCoreOptions.disk_drive(
		"parallel_n64", "n64", ["nintendo_64dd"], "")
	_eq(by_expansion.get("parallel-n64-64dd-hardware"), "enabled",
		"forced/and so does a console with the drive bolted under it")
	var by_dev := ForcedCoreOptions.disk_drive(
		"parallel_n64", "n64", ["nintendo_64dd_dev"], "")
	_eq(by_dev.get("parallel-n64-64dd-hardware"), "enabled",
		"forced/the development unit is the same drive")
	_eq(ForcedCoreOptions.disk_drive("parallel_n64", "n64", [], ""), {},
		"forced/a plain N64 is left alone")

	# The Expansion Pak is pinned in BOTH directions: the core's own default is
	# "installed", so leaving it alone gives 8 MB to a machine with no pack in it.
	var with_pak := ForcedCoreOptions.expansion_pak("mupen64plus_next", ["expansion_pak"])
	var without := ForcedCoreOptions.expansion_pak("mupen64plus_next", [])
	_eq(with_pak.get("mupen64plus-ForceDisableExtraMem"), "False",
		"forced/a placed Expansion Pak is not disabled")
	_eq(without.get("mupen64plus-ForceDisableExtraMem"), "True",
		"forced/and an absent one is, rather than left at the core's default")
	# The other N64 core's key is named the opposite of what it means, which is
	# the trap: parallel-n64-disable_expmem describes itself as "Enable Expansion
	# Pak RAM", so "enabled" names the RAM and not the disabling. Measured, not
	# read off the key. Asserted here in the direction the core actually takes.
	_eq(ForcedCoreOptions.expansion_pak("parallel_n64", ["expansion_pak"])
			.get("parallel-n64-disable_expmem"), "enabled",
		"forced/the other N64 core's key is named the opposite of what it means")
	_eq(ForcedCoreOptions.expansion_pak("parallel_n64", [])
			.get("parallel-n64-disable_expmem"), "disabled",
		"forced/and a bare console is pushed off its default there too")
	_eq(ForcedCoreOptions.expansion_pak("fceumm", ["expansion_pak"]), {},
		"forced/a core with no such option gets nothing")

	# The FM Sound Unit is gated on the SYSTEM as well, unlike the Pak: the same
	# core runs the Mega Drive, Game Gear and SG-1000, and without the gate every
	# one of those would be pinned "disabled" for a chip they never had.
	_eq(ForcedCoreOptions.fm_sound_unit("genesis_plus_gx", "mastersystem",
			["fm_sound_unit"]).get("genesis_plus_gx_ym2413"), "enabled",
		"forced/a Master System with the unit enables the YM2413")
	_eq(ForcedCoreOptions.fm_sound_unit("genesis_plus_gx", "mastersystem", [])
			.get("genesis_plus_gx_ym2413"), "disabled",
		"forced/without it the chip is pinned off, not left on auto")
	_eq(ForcedCoreOptions.fm_sound_unit("genesis_plus_gx", "genesis",
			["fm_sound_unit"]), {},
		"forced/a Mega Drive on the same core is untouched")

	# Frame-rate detection is pinned on for flycast, and it is a speed fix rather
	# than a preference. With threaded rendering the core keeps emulating until a
	# frame is not a duplicate, so one retro_run covers two vblanks of a game
	# locked to 30 fps — and a frontend still calling sixty times a second runs
	# that game at double speed. The option is how the core says the rate moved.
	_eq(ForcedCoreOptions.declared_frame_rate("flycast")
			.get("reicast_detect_vsync_swap_interval"), "enabled",
		"forced/flycast is made to announce a frame-rate change")
	_eq(ForcedCoreOptions.declared_frame_rate("fceumm"), {},
		"forced/and no other core is handed a reicast key")
	# It has to survive the merge, not merely exist: all() is what RetroSystem
	# calls, and a layer left out of it is a function nothing runs.
	_eq(ForcedCoreOptions.all("flycast", "dreamcast", "", [], "", [], "")
			.get("reicast_detect_vsync_swap_interval"), "enabled",
		"forced/and it reaches the set a machine actually pins")

	# The VMU is a platform because an override gives vemulator a systemid.
	# Upstream's entry has none, and everything that lists cores groups by that
	# -- so the core sat in the database belonging to no platform: no row in the
	# menu, no roms dir, and nothing offering to install it, while the card said
	# "the vemulator core is not installed". These three are what make it exist.
	var vemu: Dictionary = CoreInfoDatabase.shared().get_by_core_name("vemulator")
	_ok(not vemu.is_empty(), "vmu/the vemulator entry is in the database")
	_ok("vmu" in CoreInfoDatabase.systemids_of(vemu),
		"vmu/and the override gives it a systemid to be grouped under")
	_eq(str(vemu.get("categories", "")), "Emulator",
		"vmu/it is an emulator rather than a game that ships its own content")
	# The extensions a VMU file actually has, so roms/vmu lists them.
	var vmu_exts: Array = CoreInfoDatabase.extensions_for_systemid("vmu")
	_ok("vms" in vmu_exts and "dci" in vmu_exts,
		"vmu/and the platform claims the extensions a VMU file has")


# ── manifest/ ─────────────────────────────────────────────────────────────────

## What is installed and how old it is. The manager offers an update by testing
## the stored stamp for INEQUALITY, so what matters is that it round-trips.
func _group_manifest() -> void:
	var m := DownloadManifest.new()
	m.setup(_dir)

	_ok(not m.is_downloaded("fceumm"), "manifest/an unknown core is not installed")
	_eq(m.get_remote_date("fceumm"), "", "manifest/and has no stamp")

	m.set_downloaded("fceumm", "2026-03-06", "fceumm_libretro.dll")
	_ok(m.is_downloaded("fceumm"), "manifest/a recorded core reads as installed")
	_eq(m.get_remote_date("fceumm"), "2026-03-06", "manifest/with its stamp")

	# A second manifest over the same directory must see it: the whole point of
	# the file is that it survives the app closing.
	var reopened := DownloadManifest.new()
	reopened.setup(_dir)
	_eq(reopened.get_remote_date("fceumm"), "2026-03-06",
		"manifest/and it survives being reopened")

	m.set_downloaded("fceumm", "2026-04-01", "fceumm_libretro.dll")
	_eq(m.get_remote_date("fceumm"), "2026-04-01", "manifest/re-recording replaces the stamp")
	m.remove("fceumm")
	_ok(not m.is_downloaded("fceumm"), "manifest/removing forgets the core")
	_eq(m.get_remote_date("fceumm"), "", "manifest/and its stamp with it")


## ── recommended/ ──────────────────────────────────────────────────────
##
## CoreRecommendations is one core per system, badged in the downloader and
## installed wholesale by "Download All Recommended". Its header states two
## invariants that nothing checked, and neither fails loudly: a second pick for a
## machine would make the download-all button fetch two cores for it, and a
## core_names() that stopped deduplicating would re-fetch Genesis Plus GX once
## for each of the five Sega machines it serves.
func _group_recommended() -> void:
	var table: Dictionary = CoreRecommendations.RECOMMENDED
	_ok(table.size() > 20, "recommended/the table is populated",
		"got %d" % table.size())

	# Every row carries a pick and a reason. The "why" is not decoration: the
	# header distinguishes entries measured on this hardware from ones inherited
	# from community consensus, and a row with no reason cannot say which it is.
	var missing_core := 0
	var missing_why := 0
	var empty_android := 0
	for sysid: String in table:
		var row: Dictionary = table[sysid]
		if str(row.get("core", "")).is_empty():
			missing_core += 1
		if str(row.get("why", "")).is_empty():
			missing_why += 1
		if row.has("android") and str(row["android"]).is_empty():
			empty_android += 1
	_eq(missing_core, 0, "recommended/every system names a core")
	_eq(missing_why, 0, "recommended/and says why it was picked")
	_eq(empty_android, 0, "recommended/an android override is never blank")

	# One core per system is what lets download-all install a full set without
	# fetching two cores for one machine. A row whose pick is an Array would
	# still read fine everywhere else.
	var non_string := 0
	for sysid: String in table:
		if not (table[sysid].get("core") is String):
			non_string += 1
	_eq(non_string, 0, "recommended/a system picks exactly one core, not a list")

	var names := CoreRecommendations.core_names()
	var seen: Array[String] = []
	var dupes := 0
	for n: String in names:
		if seen.has(n):
			dupes += 1
		seen.append(n)
	_eq(dupes, 0, "recommended/core_names deduplicates")
	_ok(names.size() < table.size(),
		"recommended/and is shorter than the table, since one core serves several machines",
		"%d names for %d systems" % [names.size(), table.size()])
	_ok(not names.has(""), "recommended/and never yields an empty name")

	# No opinion is an empty string, not a guess.
	_eq(CoreRecommendations.core_for(""), "", "recommended/no system, no pick")
	_eq(CoreRecommendations.core_for("__not_a_system"), "",
		"recommended/an unknown system has no pick")
	_ok(not CoreRecommendations.is_recommended("__not_a_system", "stella"),
		"recommended/nothing is recommended for an unknown system")

	# is_recommended must reject an empty core name even where the system HAS a
	# pick, or a row with no core_name would badge itself.
	var known := str(table.keys()[0])
	var pick := CoreRecommendations.core_for(known)
	_ok(CoreRecommendations.is_recommended(known, pick),
		"recommended/a system's own pick is recommended")
	_ok(not CoreRecommendations.is_recommended(known, ""),
		"recommended/an empty core name never is")
	_ok(not CoreRecommendations.is_recommended(known, "__other_core"),
		"recommended/and neither is a different core")

	# first() is a PARTITION, not a sort, and the header says why: sort_custom is
	# not stable, so ranking by recommended-ness alone would shuffle everything
	# else. These cases are what makes that difference visible.
	var entries: Array = [
		{"core_name": "aaa"}, {"core_name": "bbb"}, {"core_name": pick}, {"core_name": "ccc"},
	]
	var sorted_entries := CoreRecommendations.first(known, entries)
	_eq(str(sorted_entries[0]["core_name"]), pick, "recommended/first puts the pick at the front")
	_eq([str(sorted_entries[1]["core_name"]), str(sorted_entries[2]["core_name"]),
		str(sorted_entries[3]["core_name"])], ["aaa", "bbb", "ccc"],
		"recommended/and leaves every other entry in the order it arrived")
	_eq(sorted_entries.size(), entries.size(), "recommended/losing none of them")

	# A system with no opinion must hand the list back untouched rather than
	# reordering it around an empty pick.
	var untouched := CoreRecommendations.first("__not_a_system", entries)
	_eq(untouched.size(), entries.size(), "recommended/no pick, no reordering")
	_eq(str(untouched[0]["core_name"]), "aaa", "recommended/the list arrives as it was")

	# The key is configurable because callers hold different row shapes.
	var by_other: Array = [{"name": "zzz"}, {"name": pick}]
	var keyed := CoreRecommendations.first(known, by_other, "name")
	_eq(str(keyed[0]["name"]), pick, "recommended/first honours a different key")
