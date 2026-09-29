## Runs SnesCartShell over a folder of Super NES ROMs and reports what each would
## spawn in: market, body and shell. Fails when a region-tagged file's market
## disagrees with its tag, or when a coloured shell lands on any ROM but the
## expected ones.
##
##     "$godot" --headless --path RetroXR res://Tools/models/snes_cart_rom_check.tscn -- --roms=Z:/roms/snes
##
## Reads headers only (0x10200 bytes a file), never hashes. The scraper's region
## is used when the folder is the library's own; for any other folder the file
## name and header decide, which is what this checks.
extends Node

## File-name prefixes of the only ROMs that may come out coloured, by shell.
const COLOURED := {
	&"black": ["Killer Instinct (USA)", "Killer Instinct (Europe)"],
	&"red": ["Doom (USA)", "Spider-Man - Venom - Maximum Carnage (USA)"],
}


func _ready() -> void:
	var roms := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--roms="):
			roms = str(arg).trim_prefix("--roms=").replace("\\", "/")
	if roms.is_empty() or not DirAccess.dir_exists_absolute(roms):
		print("[snesroms] usage: -- --roms=<folder of .sfc/.smc>")
		get_tree().quit(2)
		return
	var bodies := {}
	var markets := {}
	var coloured := {}
	var disagree: Array[String] = []
	var files := 0
	for f in DirAccess.get_files_at(roms):
		var ext := f.get_extension().to_lower()
		if ext != "sfc" and ext != "smc":
			continue
		files += 1
		var path := roms.path_join(f)
		var market := SnesCartShell.market(SnesCartShell.SYSTEMID, path)
		markets[market] = int(markets.get(market, 0)) + 1
		var body := SnesCartShell.body_model_for_rom("", SnesCartShell.SYSTEMID, path).get_file()
		bodies[body] = int(bodies.get(body, 0)) + 1
		var tag := SnesCartShell.filename_market(path)
		if not tag.is_empty() and tag != market:
			disagree.append("%s: tag %s, market %s" % [f, tag, market])
		var preset := SnesCartShell.preset_for_rom(path)
		if preset != SnesCartShell.DEFAULT_PRESET:
			coloured[f] = preset
	print("[snesroms] %d ROMs; markets %s; bodies %s" % [files, markets, bodies])
	var wrong: Array[String] = []
	for f: String in coloured:
		print("[snesroms] %s -> %s" % [f, coloured[f]])
		var allowed: Array = COLOURED.get(coloured[f], [])
		if not allowed.any(func(p: String) -> bool: return f.begins_with(p)):
			wrong.append(f)
	for shell: StringName in COLOURED:
		for prefix: String in COLOURED[shell]:
			if not coloured.keys().any(func(f: String) -> bool: return f.begins_with(prefix)):
				print("[snesroms] note: no %s ROM in the folder" % prefix)
	for d in disagree:
		print("[snesroms] DISAGREE %s" % d)
	for w in wrong:
		print("[snesroms] UNEXPECTED COLOUR %s" % w)
	var ok := disagree.is_empty() and wrong.is_empty()
	print("[snesroms] RESULT=%s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
