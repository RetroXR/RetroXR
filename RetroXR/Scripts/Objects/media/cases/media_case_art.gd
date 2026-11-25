## MediaCaseArt — the case a music CD or a DVD comes in, and the printed paper it wears.
##
## A CD's is the plain jewel case, a DVD's the plain keep case (the black polypropylene one), both RetroGameCase's.
## Their paper is the player's own pictures, found beside the album or the DVD by name (any of png, jpg, jpeg, webp):
##
##   a folder (an album of tracks, a DVD's folder)   inside it:  cover / folder / front / album,   back,   spine
##   a file (one track, a playlist, an .iso)         beside it:  Name.png,   Name back.png,   Name spine.png
##
## The front is the picture the disc's own face already uses (MediaLabelArt.album_side). A front wider than tall
## is the whole sleeve in one picture, back | spine | front, as a DVD's cover is scanned. A CD's back wider than
## 5:4 is its whole tray card: the spine is cut from its left edge. Whatever is missing is RetroXR's own paper
## (MediaLabelPainter.case_sheet), so a case with no pictures at all still reads as that album's.
##
## Read when the case appears (a spawn, a restore): a picture added afterwards shows on the next case.
class_name MediaCaseArt
extends RefCounted

## kind -> [family, variant] of GameCaseModel.
const CASES := {"cd": ["jewel", "single"], "dvd": ["keep", "single"]}
const SPINE_STEMS: Array[String] = ["spine"]
## A front at least this much wider than tall is the whole sleeve (a DVD's: 273 x 183 mm).
const SLEEVE_ASPECT := 1.2
## A CD's back at least this much wider than tall is the whole tray card (150.5 x 118 mm), spines and all ...
const TRAY_CARD_ASPECT := 1.24
## ... each spine this share of its width (6.5 mm).
const TRAY_SPINE := 6.5 / 150.5
## The sheet's height in px: a picture taller is drawn down to it. (A game's scan is 680; a sheet this tall is
## 1716 px wide on a jewel case, 7 MB of texture with its mipmaps.)
const SHEET_H := 768


static func is_kind(kind: String) -> bool:
	return CASES.has(kind)


static func family_of(kind: String) -> String:
	return str((CASES.get(kind, ["jewel", "single"]) as Array)[0])


static func variant_of(kind: String) -> String:
	return str((CASES.get(kind, ["jewel", "single"]) as Array)[1])


## The pictures there are for `media_path`: {"front", "back", "spine"} -> a file, or "". The main thread's (folders
## are listed).
static func paths(media_path: String) -> Dictionary:
	var out := {"front": "", "back": "", "spine": ""}
	if media_path.is_empty():
		return out
	var is_folder := DirAccess.dir_exists_absolute(media_path)
	var stem := media_path if is_folder else media_path.get_basename()
	out["front"] = MediaLabelArt.album_side(media_path, "a")
	out["back"] = MediaLabelArt.album_side(media_path, "b")
	if str(out["back"]).is_empty():
		out["back"] = MediaLabelArt._find(stem + " back")
	if is_folder:
		out["spine"] = MediaLabelArt._in_folder(media_path, SPINE_STEMS)
	if str(out["spine"]).is_empty():
		out["spine"] = MediaLabelArt._find(stem + " spine")
	return out


## Coroutine. The whole sheet for a `kind` case of `media_path` named `title`, with its mipmaps: the pictures
## decoded and joined on a pool thread, RetroXR's own paper drawn for what they lack. `host` is any node in the
## tree. Null when the host has gone.
static func decode(host: Node, kind: String, media_path: String, title: String, family: String,
		variant: String) -> Image:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var tree := host.get_tree()
	var job := {"paths": paths(media_path), "kind": kind, "family": family, "variant": variant}
	await _on_pool(tree, _load_into.bind(job))
	if job.has("sleeve"):
		return job["sleeve"]
	if not (job.has("front") and job.has("back") and job.has("spine")):
		# The paper's own panels, at the widths the joined sheet will have them.
		var front_px := Vector2i(SHEET_H, SHEET_H)
		if job.has("front"):
			front_px = (job["front"] as Image).get_size()
		elif family == "jewel":
			front_px = Vector2i(roundi(SHEET_H * float(GameCaseModel.jewel_layout(variant)["booklet_per_h"])), SHEET_H)
		var widths := GameCaseModel.panel_widths(SHEET_H, front_px, variant, family)
		if not is_instance_valid(host) or not host.is_inside_tree():
			return null
		job["paper"] = await MediaLabelPainter.case_sheet(host, kind, title, widths, SHEET_H)
		job["widths"] = widths
	if not is_instance_valid(host) or not host.is_inside_tree():
		return null
	await _on_pool(tree, _join_into.bind(job))
	return job.get("sheet")


static func _on_pool(tree: SceneTree, work: Callable) -> void:
	var task := WorkerThreadPool.add_task(work)
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)


## The pictures there are, decoded into `job` ("front", "back", "spine": an Image each; or "sleeve", the whole
## sheet ready to wear). A pool thread's.
static func _load_into(job: Dictionary) -> void:
	var found: Dictionary = job["paths"]
	for part: String in ["front", "back", "spine"]:
		var path := str(found.get(part, ""))
		if path.is_empty():
			continue
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			continue
		if img.is_compressed() and img.decompress() != OK:
			continue
		if img.get_height() > SHEET_H:
			img.resize(maxi(1, roundi(float(img.get_width()) * SHEET_H / img.get_height())), SHEET_H, Image.INTERPOLATE_LANCZOS)
		job[part] = img
	var front := job.get("front") as Image
	if front != null and float(front.get_width()) / front.get_height() >= SLEEVE_ASPECT:
		# The whole sleeve in one picture. A jewel case's is laid out as a game's is.
		if str(job["family"]) == "jewel":
			GameCaseModel.fit_jewel_scan(front)
		front.generate_mipmaps()
		job["sleeve"] = front
		return
	var back := job.get("back") as Image
	if str(job["kind"]) == "cd" and back != null and float(back.get_width()) / back.get_height() >= TRAY_CARD_ASPECT:
		# A whole tray card: its left spine strip is the spine (when there is no picture of one), the rest between
		# the two strips the back.
		var strip := maxi(1, roundi(back.get_width() * TRAY_SPINE))
		if not job.has("spine"):
			job["spine"] = back.get_region(Rect2i(0, 0, strip, back.get_height()))
		job["back"] = back.get_region(Rect2i(strip, 0, back.get_width() - strip * 2, back.get_height()))


## The three panels joined into "sheet": each the picture, else its part of RetroXR's paper. A pool thread's.
static func _join_into(job: Dictionary) -> void:
	var paper := job.get("paper") as Image
	var widths: Vector3i = job.get("widths", Vector3i.ZERO)
	var parts: Array[Image] = []
	var x := 0
	for i in 3:
		var part := job.get(["back", "spine", "front"][i]) as Image
		if part == null and paper != null and widths[i] > 0:
			part = paper.get_region(Rect2i(x, 0, mini(widths[i], paper.get_width() - x), paper.get_height()))
		if part == null or part.is_empty():
			return
		parts.append(part)
		x += widths[i]
	var sheet := GameCaseModel.join_panels(parts[0], parts[1], parts[2], str(job["variant"]), str(job["family"]))
	if sheet != null:
		sheet.generate_mipmaps()
		job["sheet"] = sheet
