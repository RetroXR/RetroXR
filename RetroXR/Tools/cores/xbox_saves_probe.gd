## xbox_saves_probe — what XboxDisc and XboxHddSaves read off a REAL disc image
## and a REAL xemu hard disk. A probe and not a suite: it needs both files.
##
##   "$godot" --headless --path RetroXR res://Tools/cores/xbox_saves_probe.tscn -- \
##     --iso="<an Xbox disc image>" --hdd="<xbox_hdd.qcow2>" [--zip=<where to write the archive>]
##
## --hdd defaults to the disk the core writes (XboxHddSaves.hdd_path()). Point it
## at a COPY when the question is about the reader rather than about sharing the
## file with a running core. Reads only; --zip is the one thing it writes.
##
## The archive is written so something that is not this code can open it: the
## oracle for pack() is `python -m zipfile -l`, not ZIPReader reading back what
## its own engine's conventions produced.
extends Node


func _ready() -> void:
	var args := _args()
	var iso := str(args.get("iso", ""))
	var hdd := str(args.get("hdd", XboxHddSaves.hdd_path()))

	# CRC-32's standard check value: what "123456789" must hash to.
	print("[probe] crc32('123456789') = %08x (want cbf43926)"
		% XboxHddSaves._crc32("123456789".to_ascii_buffer()))

	var title := XboxDisc.title_of(iso)
	print("[probe] disc: %s -> %s" % [iso.get_file(), title])
	if title.is_empty():
		print("[probe] FAIL not an Xbox disc")
		get_tree().quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var lifted := XboxHddSaves.lift(hdd, str(title["title_id"]))
	print("[probe] hdd: %s ok=%s error='%s' in %d ms" % [hdd, lifted["ok"],
		lifted["error"], Time.get_ticks_msec() - t0])
	var files: Dictionary = lifted["files"]
	var paths: Array = files.keys()
	paths.sort()
	for path: String in paths:
		var bytes: PackedByteArray = files[path]
		print("[probe]   %-48s %8d  md5 %s" % [path, bytes.size(),
			RommSaveSync.md5_of(bytes)])
	print("[probe] %d files, %d bytes" % [files.size(), XboxHddSaves.byte_count(files)])

	var zip := XboxHddSaves.pack(files)
	var again := XboxHddSaves.pack(files)
	print("[probe] archive: %d bytes, md5 %s, packed twice the same: %s"
		% [zip.size(), RommSaveSync.md5_of(zip), zip == again])
	var out := str(args.get("zip", ""))
	if not out.is_empty():
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_buffer(zip)
		f.close()
		print("[probe] wrote %s" % out)
	get_tree().quit(0 if bool(lifted["ok"]) else 1)


func _args() -> Dictionary:
	var out := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			out[arg.substr(2).get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	return out
