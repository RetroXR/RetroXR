## FirmwareRequirements — what each core needs in its system directory.
##
## Reads the firmware block every libretro .info file may carry:
##
##     firmware_count = 4
##     firmware0_desc = "scph5500.bin (PS1 JP BIOS)"
##     firmware0_path = "scph5500.bin"
##     firmware0_opt  = "true"
##     notes = "(!) scph5500.bin (md5): 8dd7d5296a650fac7319bce665a6a53c|..."
##
## `firmware*_path` is relative to the core's system dir, and often nested
## ("dolphin-emu/Sys/GC/USA/IPL.bin"). Joined onto CoreDownloadManager's
## per-core system dir it gives the absolute destination.
class_name FirmwareRequirements


## Optional files a core can run without. 143 of the 149 entries declared by a
## typical install are optional, so this is the common case, not the exception.
const OPTIONAL := "optional"
const REQUIRED := "required"


## Every firmware entry one core declares.
## Returns [{path, desc, optional: bool, md5: String, is_dir: bool}], in the
## order the .info lists them. Empty when the core declares none.
static func for_core(core_name: String) -> Array[Dictionary]:
	return from_info(CoreInfoDatabase.shared().get_by_core_name(core_name))


## Same, from an already-loaded .info entry.
static func from_info(info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if info.is_empty():
		return out

	var count := int(str(info.get("firmware_count", "0")))
	if count <= 0:
		return out

	var hashes := parse_notes_md5(str(info.get("notes", "")))

	for i in range(count):
		var path := str(info.get("firmware%d_path" % i, "")).strip_edges()
		if path.is_empty():
			continue
		out.append({
			"path": path,
			"desc": str(info.get("firmware%d_desc" % i, path)).strip_edges(),
			# Anything not explicitly "true" is required. A handful of .info
			# files omit _opt entirely, and those are all mandatory BIOSes.
			"optional": str(info.get("firmware%d_opt" % i, "false")) == "true",
			"md5": str(hashes.get(path, hashes.get(path.get_file(), ""))),
			# pcsx2 declares "pcsx2/bios", a folder it only checks for existence.
			"is_dir": path.get_extension().is_empty(),
		})
	return out


## Pull the checksum table out of a `notes` value.
##
## 85 of the 306 .info files publish md5s, always as
##   (!) <name> (md5): <32 hex>
## with "|" separating lines.
##
## <name> is NOT consistently the firmware path: 182 entries key on the full
## path ("bk/B11M_BOS.ROM") but 53 key on the basename alone (ppsspp publishes
## "ppge_atlas.zim" for the path "PPSSPP/ppge_atlas.zim"). Callers must try the
## path first, then its basename.
##
## Returns { name: lowercase md5 }.
static func parse_notes_md5(notes: String) -> Dictionary:
	var out: Dictionary = {}
	if notes.is_empty() or not notes.contains("(md5)"):
		return out

	for chunk: String in notes.split("|"):
		var marker := chunk.find("(md5)")
		if marker < 0:
			continue

		# Name sits between the "(!)" bullet and the "(md5)" marker. Paths
		# contain spaces ("Machines/Shared Roms/MSX.rom"), so take the whole
		# span rather than tokenising on whitespace.
		var name := chunk.substr(0, marker)
		var bullet := name.rfind("(!)")
		if bullet >= 0:
			name = name.substr(bullet + 3)
		name = name.strip_edges()

		var digest := chunk.substr(marker + 5).strip_edges()
		# Skips the ":" and any spaces the .info happens to use.
		while not digest.is_empty() and not _is_hex(digest[0]):
			digest = digest.substr(1)
		digest = digest.substr(0, 32).to_lower()

		if not name.is_empty() and digest.length() == 32 and _is_hex_string(digest):
			out[name] = digest
	return out


static func _is_hex(c: String) -> bool:
	return (c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")


static func _is_hex_string(s: String) -> bool:
	for i in range(s.length()):
		if not _is_hex(s[i]):
			return false
	return true


## Absolute path a firmware entry must end up at for `core_name` to find it.
static func destination(core_name: String, path: String) -> String:
	return CoreDownloadManager.default_system_dir(core_name).path_join(path)


# ── Installed cores ───────────────────────────────────────────────────────────

## Scan the cores dir: { systemid: [ {core_name, display_name}, ... ] }.
## A core can sit there under two naming conventions (bare and _android), so
## names are de-duplicated. Cores with no .info entry are grouped under
## "unknown" — the same convention the Manager tab uses.
##
## `cores_dir`, `suffixes` and `ext` default to this platform's own; a probe passes
## others to look at a folder, or to read the naming of a platform it is not on (a
## Quest's `mamearcade_libretro_android.so`).
static func installed_cores_by_system(cores_dir := "", suffixes := PackedStringArray(), ext := "") -> Dictionary:
	var by_system: Dictionary = {}
	var dir := DirAccess.open(CoreDownloadManager.default_cores_dir() if cores_dir.is_empty() else cores_dir)
	if dir == null:
		return by_system

	var db := CoreInfoDatabase.shared()
	var seen: Dictionary = {}
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var cn := "" if dir.current_is_dir() else CoreDownloadManager.core_name_from_lib_filename(fname, suffixes, ext)
		if not cn.is_empty() and not seen.has(cn):
			seen[cn] = true
			var info: Dictionary = db.get_by_core_name(cn)
			var sid: String = str(info.get("systemid", "")) if not info.is_empty() else ""
			if sid.is_empty():
				sid = "unknown"
			if not by_system.has(sid):
				by_system[sid] = []
			(by_system[sid] as Array).append({
				"core_name": cn,
				"display_name": str(info.get("corename", cn)) if not info.is_empty() else cn,
			})
		fname = dir.get_next()
	dir.list_dir_end()

	for sid: String in by_system:
		(by_system[sid] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["display_name"]).naturalnocasecmp_to(str(b["display_name"])) < 0
		)
	return by_system
