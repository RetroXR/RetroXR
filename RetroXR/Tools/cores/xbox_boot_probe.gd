## xbox_boot_probe — does xemu boot an Xbox disc inside RetroXR, can the hard
## disk be read while the core holds it, and do the game's saves lift off it once
## the machine stops?
##
## Needs the real core, a BIOS set and a disc, so it is a probe. Windowed, never
## --headless (frames come back blank), and ONE run per process: xemu builds its
## machine once per process. Point --root at a THROWAWAY root holding
## cores/xemu_libretro.dll and system/xemu/{mcpx_1.0.bin, a flash BIOS,
## xbox_hdd.qcow2}: the probe writes that root's save/ and core_options/, and the
## core copies the disk into save/xemu/xemu/ on its first run.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/cores/xbox_boot_probe.tscn -- --root=C:/tmp/xroot \
##     --rom="<disc>.iso" --at=10,25,40 --press=28:start,32:a --shot=C:/tmp/xbox.png
##
## --unit=1A,1B seats a BLANK Memory Unit in each named slot, the way XboxStorage
## does for one in a pad: the image staged into the core's own file for that
## slot, and the slot's option switched on. After the stop each unit is read back
## and its saves listed — so a save the GAME put on a unit, from a unit that
## started empty, is the console writing and RetroXR reading. --unit-save puts
## one RetroXR-written save on each unit first (the other direction: RetroXR
## writing, the console reading — look for it in a game's or a dashboard's list).
## A slot the core build has no option for is reported, not assumed to work.
##
## --pull=1A:70 switches a slot's option OFF at that second, as pulling a unit out
## of a pad does, and reads the file back two seconds later (the core closes it
## within the retro_run that sees the change). --seat=1A:80 stages a FRESH unit
## into the slot and switches it on again, as pushing one in does — never into a
## slot that is still on: a file is not overwritten while its option is enabled.
##
## The console's own view comes from the core, which says at WARN when the guest
## first DETECTS a unit (USB SET_CONFIGURATION), first READS it (a mount reads the
## FATX superblock) and first WRITES to it. Those lines are printed as they come;
## grep the run for "memory unit". Halo only ever detects; Conker reads, at its
## profile screen.
##
## No --rom starts the machine with NO CONTENT, the way RetroSystem does for a
## row whose `no_content` is set: the core is handed a NULL game info rather than
## a zeroed struct, which is libretro's own convention and the one xemu wants —
## a zeroed one carries no path, and this core reads that as a medium named ""
## on any start after the first. --restart=<seconds> stops and starts again at
## that mark, which is the second power-on of a session and the case that tells
## the two conventions apart.
##
## No --rom boots the BIOS alone: the stock disk's dashboard placeholder, which
## says "Please insert an Xbox disc". That is the control leg for "the picture is
## the GAME's" — run it in a process of its own.
##
## Each sample prints how much of the frame is not black and how many distinct
## colours it has, so "it booted" is a number and not only a PNG to squint at: a
## core that started and drew nothing reads lit=0.000 colours=1.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const PRESS_MS := 250
const CORE := "xemu"

var root_dir := ""
var rom := ""
var sample_at: Array[float] = [10.0, 25.0, 40.0]
var presses: Array = []
var shot := ""
var settle := XboxStorage.SETTLE_AFTER_OFF_SEC
## [port, slot] of every Memory Unit to seat.
var units: Array = []
var unit_save := false
## When to stop the machine and start it again, or 0.
var restart_at := 0.0
## A hard disk image whose saves for --rom's game go onto each unit first.
var unit_from := ""
## [seconds, port, slot] of every mid-run pull and seat.
var pulls: Array = []
var seats: Array = []

var _lib: Node = null
var _load_failed := ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--unit="):
			for piece: String in arg.trim_prefix("--unit=").split(",", false):
				if piece.length() == 2 and "1234".contains(piece[0]) and "AB".contains(piece[1].to_upper()):
					units.append([int(piece[0]) - 1, 0 if piece[1].to_upper() == "A" else 1])
		elif arg.begins_with("--pull=") or arg.begins_with("--seat="):
			var into: Array = pulls if arg.begins_with("--pull=") else seats
			for piece: String in arg.get_slice("=", 1).split(",", false):
				var bits := piece.split(":")
				if bits.size() == 2 and bits[0].length() == 2:
					into.append([float(bits[1]), int(bits[0][0]) - 1, 0 if bits[0][1].to_upper() == "A" else 1])
		elif arg.begins_with("--unit-from="):
			unit_from = arg.trim_prefix("--unit-from=")
		elif arg.begins_with("--restart="):
			restart_at = float(arg.trim_prefix("--restart="))
		elif arg == "--unit-save":
			unit_save = true
		elif arg.begins_with("--settle="):
			settle = float(arg.trim_prefix("--settle="))
		elif arg.begins_with("--at="):
			sample_at.clear()
			for piece: String in arg.trim_prefix("--at=").split(",", false):
				sample_at.append(float(piece))
		elif arg.begins_with("--press="):
			for piece: String in arg.trim_prefix("--press=").split(",", false):
				var bits := piece.split(":")
				if bits.size() == 2 and BUTTONS.has(bits[1]):
					presses.append([float(bits[0]), int(BUTTONS[bits[1]])])
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[xboxprobe] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not DirAccess.dir_exists_absolute(root_dir.path_join("system").path_join(CORE)):
		print("[xboxprobe] SKIP: pass --root=<throwaway root with system/xemu and cores/>")
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	var hdd := root_dir.path_join("save").path_join(CORE).path_join(CORE) \
		.path_join(XboxHddSaves.HDD_FILE)
	print("[xboxprobe] root=%s rom=%s" % [root_dir, rom if not rom.is_empty() else "(none: BIOS only)"])
	if not rom.is_empty():
		print("[xboxprobe] disc says: %s" % XboxDisc.title_of(rom))

	_stage_units()

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _load_failed = reason)
	_lib.connect("options_ready", _on_options_ready)
	_start()

	var end_at := 0.0
	for t: float in sample_at:
		end_at = maxf(end_at, t)
	for p: Array in presses:
		end_at = maxf(end_at, float(p[0]) + 0.5)
	for e: Array in pulls + seats:
		end_at = maxf(end_at, float(e[0]) + 3.0)
	var pending: Array = []
	for e: Array in pulls:
		pending.append([float(e[0]), "pull", int(e[1]), int(e[2])])
		pending.append([float(e[0]) + 2.0, "read", int(e[1]), int(e[2])])
	for e: Array in seats:
		pending.append([float(e[0]), "seat", int(e[1]), int(e[2])])
	pending.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var sorted := sample_at.duplicate()
	sorted.sort()
	var next_sample := 0
	var shared_checked := false
	var restarted := restart_at <= 0.0
	var t0 := Time.get_ticks_msec()
	while _load_failed.is_empty():
		var now := Time.get_ticks_msec() - t0
		var mask := 0
		for p: Array in presses:
			var at := int(float(p[0]) * 1000.0)
			if now >= at and now < at + PRESS_MS:
				mask |= 1 << int(p[1])
		_lib.SetJoypadState(0, mask, 0, 0, 0, 0)
		while not pending.is_empty() and now >= int(float(pending[0][0]) * 1000.0):
			var ev: Array = pending.pop_front()
			_unit_event(str(ev[1]), int(ev[2]), int(ev[3]))
		if next_sample < sorted.size() and now >= int(float(sorted[next_sample]) * 1000.0):
			_sample(float(sorted[next_sample]))
			next_sample += 1
			# Once, mid-run: QEMU has the disk open for WRITING, sharing reads
			# only. Whether a second handle may read it is the engine's open mode's
			# business, and the backup depends on the answer.
			if not shared_checked:
				shared_checked = true
				_read_while_held(hdd)
				_units_held()
		if not restarted and now >= int(restart_at * 1000.0):
			restarted = true
			print("[xboxprobe] restart: stopping")
			_lib.StopContent()
			await get_tree().create_timer(3.0).timeout
			print("[xboxprobe] restart: starting again")
			_start()
		if now >= int(end_at * 1000.0):
			break
		await get_tree().process_frame
	if not _load_failed.is_empty():
		print("[xboxprobe] REFUSED: %s" % _load_failed)

	_lib.StopContent()
	print("[xboxprobe] stopped; waiting %.0f s for the core to unload and flush" % settle)
	await get_tree().create_timer(settle).timeout

	_report_units("after stop")
	if not rom.is_empty():
		var t1 := Time.get_ticks_msec()
		var archive := XboxStorage.archive_for(rom, hdd)
		print("[xboxprobe] after stop: ok=%s title=%s archive=%d bytes error='%s' (%d ms)" % [
			archive["ok"], archive["title_id"], (archive["bytes"] as PackedByteArray).size(),
			archive["error"], Time.get_ticks_msec() - t1])
		if bool(archive["ok"]):
			var lifted := XboxHddSaves.lift(hdd, str(archive["title_id"]))
			var paths: Array = (lifted["files"] as Dictionary).keys()
			paths.sort()
			for path: String in paths:
				print("[xboxprobe]   %-44s %8d" % [path, (lifted["files"][path] as PackedByteArray).size()])
	get_tree().quit(0 if _load_failed.is_empty() else 1)


## Where everything on a unit IS, in 512-byte sectors — the unit the core's SCSI
## trace counts in (XEMU_LIBRETRO_TRACE=scsi_disk_dma_command_READ, which fires
## for Memory Units only; XEMU_LIBRETRO_LOG=<file> collects it). The superblock
## is sector 0 and the FAT sector 8 on every unit. A directory below the root is
## only FOUND by following the first-cluster field of an entry in its parent, so
## a guest read at one of those sectors is the console parsing what was written.
func _print_sector_map(image: PackedByteArray) -> void:
	var volume := FatxVolume.open(XboxRawImage.of(image), 0, image.size())
	if volume == null:
		return
	print("[xboxprobe]   sector %5d  superblock    sector %5d  FAT    sector %5d  / (root directory)" % [
		0, volume.fat_offset() >> 9, volume.data_offset() >> 9])
	_map_dir(volume, FatxVolume.ROOT_CLUSTER, "/")


func _map_dir(volume: FatxVolume, cluster: int, prefix: String) -> void:
	for e: Dictionary in volume.list_dir(cluster):
		if int(e["cluster"]) < FatxVolume.ROOT_CLUSTER:
			continue
		var sector := (volume.data_offset() + (int(e["cluster"]) - 1) * volume.cluster_size()) >> 9
		print("[xboxprobe]   sector %5d  %s%s%s" % [sector, prefix, e["name"], "/" if bool(e["dir"]) else ""])
		if bool(e["dir"]):
			_map_dir(volume, int(e["cluster"]), prefix + str(e["name"]) + "/")


## A unit pulled out of, or pushed into, a pad while the console runs.
func _unit_event(what: String, port: int, slot: int) -> void:
	var name := XboxStorage.unit_name(port, slot)
	var key := XboxStorage.unit_key(port, slot)
	var path := XboxStorage.unit_path(root_dir, port, slot)
	match what:
		"pull":
			_lib.SetCoreOption(key, XboxStorage.UNIT_OFF)
			print("[xboxprobe] PULL %s: option off" % name)
		"read":
			var f := FileAccess.open(path, FileAccess.READ_WRITE)
			var data := FileAccess.get_file_as_bytes(path)
			print("[xboxprobe] after pull %s: file %s, consistent=%s, %d save(s), md5 %s" % [name,
				"CLOSED by the core (a write handle opens)" if f != null else "still HELD",
				XboxMemoryUnit.is_consistent(data), XboxMemoryUnit.list_saves(data).size(),
				RommSaveSync.md5_of(data)])
			if f != null:
				f.close()
		"seat":
			var image := XboxMemoryUnit.blank_image()
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				print("[xboxprobe] SEAT %s: REFUSED, the file is still held (err %d)" % [name, FileAccess.get_open_error()])
				return
			f.store_buffer(image)
			f.close()
			_lib.SetCoreOption(key, XboxStorage.UNIT_ON)
			print("[xboxprobe] SEAT %s: a fresh unit staged (md5 %s), option on" % [name, RommSaveSync.md5_of(image)])


## Start the machine the way RetroSystem starts one. With no content that means
## the NULL convention, switched on around the call and off again after, exactly
## as system.gd does it — a probe that passed a zeroed struct instead would be
## measuring a path the app never takes.
func _start() -> void:
	var no_content := rom.is_empty()
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", true)
	_lib.StartContent(root_dir, CORE, rom)
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", false)


## What XboxStorage.stage_units_before_start does, without a room to find the
## units in: every slot's option written, on for the ones seated.
func _stage_units() -> void:
	var opts: Dictionary = {}
	for port: int in XboxStorage.UNIT_PORTS:
		for slot: int in XboxStorage.UNIT_SLOTS.size():
			opts[XboxStorage.unit_key(port, slot)] = XboxStorage.UNIT_OFF
	for u: Array in units:
		var image := XboxMemoryUnit.blank_image()
		if unit_save:
			image = XboxMemoryUnit.insert_save(image, XboxHddSaves.pack({
				"UDATA/4d530004/TitleMeta.xbx": _utf16("TitleName=Halo\r\n"),
				"UDATA/4d530004/52455452584D/SaveMeta.xbx": _utf16("Name=RetroXR wrote this\r\n"),
				"UDATA/4d530004/52455452584D/retroxr.bin": "written by RetroXR".to_ascii_buffer(),
			}))
		# The way home for a hard disk backup: the game's saves, lifted off ANOTHER
		# console's disk, written onto this unit by RetroXR's own FATX writer. If the
		# game then lists them, the console's FATX driver has read what ours wrote.
		if not unit_from.is_empty():
			var lifted := XboxStorage.archive_for(rom, unit_from)
			var parts := XboxMemoryUnit.saves_in_download(lifted["bytes"])
			for part: PackedByteArray in parts:
				var next := XboxMemoryUnit.insert_save(image, part)
				if not next.is_empty():
					image = next
			print("[xboxprobe] unit filled from %s: ok=%s, %d save(s) found, error '%s'" % [
				unit_from.get_file(), lifted["ok"], parts.size(), lifted["error"]])
		var path := XboxStorage.unit_path(root_dir, int(u[0]), int(u[1]))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(image)
		f.close()
		opts[XboxStorage.unit_key(int(u[0]), int(u[1]))] = XboxStorage.UNIT_ON
		_print_sector_map(image)
		print("[xboxprobe] unit %s staged: %d saves, %d blocks free, md5 %s" % [
			XboxStorage.unit_name(int(u[0]), int(u[1])), XboxMemoryUnit.list_saves(image).size(),
			XboxMemoryUnit.free_blocks(image), RommSaveSync.md5_of(image)])
	if not units.is_empty():
		CoreOptionsStore.merge_values(root_dir, CORE, opts)


func _utf16(text: String) -> PackedByteArray:
	var out := PackedByteArray([0xff, 0xfe])
	out.append_array(text.to_utf16_buffer())
	return out


func _on_options_ready(_categories: Dictionary, definitions: Dictionary, values: Dictionary) -> void:
	for u: Array in units:
		var key := XboxStorage.unit_key(int(u[0]), int(u[1]))
		print("[xboxprobe] unit %s: core %s option %s (value %s)" % [
			XboxStorage.unit_name(int(u[0]), int(u[1])),
			"DECLARES" if definitions.has(key) else "HAS NO", key, values.get(key, "-")])


func _report_units(when: String) -> void:
	for u: Array in units:
		var path := XboxStorage.unit_path(root_dir, int(u[0]), int(u[1]))
		var data := FileAccess.get_file_as_bytes(path)
		print("[xboxprobe] %s unit %s: %d bytes, card=%s consistent=%s, %d blocks free, md5 %s" % [when,
			XboxStorage.unit_name(int(u[0]), int(u[1])), data.size(), XboxMemoryUnit.is_card_image(data),
			XboxMemoryUnit.is_consistent(data), XboxMemoryUnit.free_blocks(data), RommSaveSync.md5_of(data)])
		for s: Dictionary in XboxMemoryUnit.list_saves(data):
			print("[xboxprobe]   save %s  '%s' (%s)  %d blocks" % [s["name"], s["title"], s["game"], s["blocks"]])
		# Everything on it, not only what parses as a save: a console that writes
		# somewhere RetroXR does not list is exactly what this is here to find.
		var volume := FatxVolume.open(XboxRawImage.of(data), 0, data.size())
		if volume != null:
			var files: Dictionary = {}
			volume.read_tree(FatxVolume.ROOT_CLUSTER, "", files, {"files": 4096, "bytes": data.size()})
			var paths: Array = files.keys()
			paths.sort()
			for path_in: String in paths:
				print("[xboxprobe]     %-52s %7d" % [path_in, (files[path_in] as PackedByteArray).size()])


## Is each staged unit actually ATTACHED? A unit the core has bound is a file
## QEMU holds open for writing and shares for reading only, so asking for a
## second write handle is refused; one the core ignored opens like any file.
## The hard disk, which is certainly attached, is the control for what "held"
## reads as on this platform.
func _units_held() -> void:
	var paths := {"the hard disk (control)": root_dir.path_join("save").path_join(CORE) \
		.path_join(CORE).path_join(XboxHddSaves.HDD_FILE)}
	for u: Array in units:
		paths["unit " + XboxStorage.unit_name(int(u[0]), int(u[1]))] = \
			XboxStorage.unit_path(root_dir, int(u[0]), int(u[1]))
	for label: String in paths:
		var f := FileAccess.open(str(paths[label]), FileAccess.READ_WRITE)
		if f == null:
			print("[xboxprobe] while running: %s is HELD by the core (a write handle is refused, err %d)"
				% [label, FileAccess.get_open_error()])
		else:
			f.close()
			print("[xboxprobe] while running: %s is NOT held (a second write handle opened)" % label)


func _read_while_held(hdd: String) -> void:
	if not FileAccess.file_exists(hdd):
		print("[xboxprobe] while running: no disk at %s" % hdd)
		return
	var why: Array = []
	var image := Qcow2Image.open(hdd, why)
	if image == null:
		print("[xboxprobe] while running: CANNOT open the held disk: %s" % str(why))
		return
	var volume := FatxVolume.open(image, XboxHddSaves.DATA_PARTITION_OFFSET,
		XboxHddSaves.DATA_PARTITION_SIZE, why)
	var names := PackedStringArray()
	if volume != null:
		for e: Dictionary in volume.list_dir(FatxVolume.ROOT_CLUSTER):
			names.append(str(e["name"]))
	print("[xboxprobe] while running: held disk opens for reading; E: holds [%s] %s"
		% [", ".join(names), "" if volume != null else str(why)])
	image.close()


func _sample(at: float) -> void:
	var img: Image = _lib.GetVideoImage()
	if img == null or img.is_empty():
		print("[xboxprobe] t=%5.1f frames=%d (no image)" % [at, int(_lib.GetFrameCount())])
		return
	var flat := img.duplicate() as Image
	flat.convert(Image.FORMAT_RGB8)
	if not shot.is_empty():
		flat.save_png(shot.get_basename() + ("_%05.1f." % at).replace(" ", "0") + shot.get_extension())
	# EVERY pixel, and the bounding box of the lit ones.
	#
	# A grid of every 8th pixel used to stand in for this, and it reported as
	# uniform black a frame that carried the dashboard placeholder's single line
	# of text: ~300 lit pixels of 307,200, in a strip twelve rows high, which a
	# sparse grid steps straight over between the strokes. A whole day's wrong
	# conclusion came out of that reading, so nothing here samples any more. The
	# BOX is what makes the difference legible at a glance — a line of text is a
	# few rows near the top, a picture is the whole frame.
	var raw := flat.get_data()
	var w := flat.get_width()
	var lit := 0
	var colours: Dictionary = {}
	var top := w * flat.get_height()
	var bottom := -1
	var left := w
	var right := -1
	for i: int in range(0, raw.size(), 3):
		if raw[i] + raw[i + 1] + raw[i + 2] <= 16:
			continue
		lit += 1
		colours[(raw[i] >> 3) << 10 | (raw[i + 1] >> 3) << 5 | (raw[i + 2] >> 3)] = true
		@warning_ignore("integer_division")
		var px: int = (i / 3) % w
		@warning_ignore("integer_division")
		var py: int = (i / 3) / w
		top = mini(top, py)
		bottom = maxi(bottom, py)
		left = mini(left, px)
		right = maxi(right, px)
	var box := "none" if lit == 0 else "x %d..%d  y %d..%d" % [left, right, top, bottom]
	print("[xboxprobe] t=%5.1f frames=%d size=%dx%d lit=%.4f (%d px) colours=%d  box %s" % [at,
		int(_lib.GetFrameCount()), w, flat.get_height(),
		float(lit) / maxf(1.0, float(w * flat.get_height())), lit, colours.size(), box])
