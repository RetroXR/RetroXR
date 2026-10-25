## ArcadeBezel — the bezel the game's own cabinet had round its monitor, from MAME artwork the player has.
##
## The scraped bezels (ScreenScraper's `bezel-4-3`, `bezel-16-9`, `bezel-4-3-v`...) are community overlays drawn
## for a television: most are one 16:9 template with a 4:3 hole shared by many games, and none says who made
## it or from what, so none is taken. A cabinet in a room already HAS the frame round its tube; the one it
## wants is the print on the real cabinet's glass. MAME's artwork is that: a zip (or a folder) per romset (Mr.
## Do's scans, the progettoSNAPS "Official" pack) whose layout file (`default.lay`) names each picture, where it
## stands and where the screen is, and says in its credits whether the bezel was scanned. Put in
## `<data root>/artwork/` it is found the way MAME finds it: the romset's own, else its parent's
## (ArcadeGameProfile.parent_of). Nothing is downloaded and nothing ships (docs/dev/arcade.md "Bezels").
##
## A layout whose credits call its bezel fan work (a "realistic" or "custom" bezel, a widescreen view) is passed
## over, and so is a view whose bezel is a 16:9 canvas: that is the television filler again.
class_name ArcadeBezel
extends RefCounted

## The folder under the data root, as MAME's own `artwork/`.
const DIR := "artwork"
## The longest side a bezel is kept at, in pixels: a cabinet's bezel is about 60 cm across, 1024 pixels is
## better than a millimetre each, and a scan at 4000 x 3616 would be 58 MB of texture.
const MAX_SIDE := 1024
## Words in a layout's credits that say its bezel was drawn, not scanned.
const FAN_WORDS: Array[String] = ["realistic", "custom", "widescreen", "wide screen", "16:9", "fan art", "fanart",
	"recreat", "redrawn", "redraw", "vectorized", "vectorised"]

## A suite's artwork folder in place of the data root's. Empty in the app.
static var test_root := ""


## Where the player's artwork is.
static func root() -> String:
	return test_root if not test_root.is_empty() else DataPaths.media_root(DIR)


## The bezel for the game in `rom_path`, loaded now: {"image": Image (at most MAX_SIDE), "hole": Rect2 (the
## screen inside the image, 0..1, y down), "credit": String, "set": String (whose artwork it is)}, or {}.
static func load_for_rom(rom_path: String) -> Dictionary:
	return _load_first(candidates(rom_path), root())


## The same off the main thread: `done` is called on the main thread with the result ({} for none). A scan
## is a few megabytes of PNG, too slow to decode in the frame a board goes in. What to look for and where is
## worked out here, on the caller's thread (the profile table and the data root are the main thread's).
static func load_for_rom_async(rom_path: String, done: Callable) -> void:
	var sets := candidates(rom_path)
	var dir := root()
	if sets.is_empty() or not DirAccess.dir_exists_absolute(dir):
		done.call_deferred({})
		return
	# Every task is waited for (WorkerThreadPool keeps what a task holds until it is): once it has finished, on
	# the main thread, where its answer is handed over.
	var task := [-1]
	task[0] = WorkerThreadPool.add_task(func() -> void:
		ArcadeBezel._finish.call_deferred(task, _load_first(sets, dir), done))


static func _finish(task: Array, found: Dictionary, done: Callable) -> void:
	WorkerThreadPool.wait_for_task_completion(int(task[0]))
	done.call(found)


## The artwork sets to look in for a game, in MAME's order: its own, then its parent's.
static func candidates(rom_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var name := rom_path.get_file().get_basename().to_lower()
	if name.is_empty():
		return out
	out.append(name)
	var parent := ArcadeGameProfile.parent_of(name)
	if not parent.is_empty():
		out.append(parent)
	return out


static func _load_first(sets: PackedStringArray, dir: String) -> Dictionary:
	for set_name in sets:
		var found := _load_set(dir, set_name)
		if not found.is_empty():
			found["set"] = set_name
			return found
	return {}


static func _load_set(dir: String, set_name: String) -> Dictionary:
	var zip_path := dir.path_join(set_name + ".zip")
	var folder := dir.path_join(set_name)
	if FileAccess.file_exists(zip_path):
		var zip := ZIPReader.new()
		if zip.open(zip_path) != OK:
			return {}
		var files := zip.get_files()
		var read := func(file: String) -> PackedByteArray:
			for f in files:
				if f.to_lower() == file.to_lower():
					return zip.read_file(f)
			return PackedByteArray()
		var out := _from_files(set_name, files, read)
		zip.close()
		return out
	if DirAccess.dir_exists_absolute(folder):
		var files := DirAccess.get_files_at(folder)
		var read := func(file: String) -> PackedByteArray:
			for f in files:
				if f.to_lower() == file.to_lower():
					return FileAccess.get_file_as_bytes(folder.path_join(f))
			return PackedByteArray()
		return _from_files(set_name, files, read)
	return {}


## The bezel out of one artwork set: its layout (`<set>.lay`, else `default.lay`) and the picture it names.
static func _from_files(set_name: String, files: PackedStringArray, read: Callable) -> Dictionary:
	var lay := PackedByteArray()
	for want in [set_name + ".lay", "default.lay"]:
		lay = read.call(want)
		if not lay.is_empty():
			break
	if lay.is_empty():
		return {}
	var pick := pick_bezel(parse_layout(lay.get_string_from_utf8()))
	if pick.is_empty():
		return {}
	var bytes: PackedByteArray = read.call(str(pick["file"]))
	if bytes.is_empty():
		return {}
	var img := Image.new()
	var ext := str(pick["file"]).get_extension().to_lower()
	var err := img.load_jpg_from_buffer(bytes) if ext in ["jpg", "jpeg"] else img.load_png_from_buffer(bytes)
	if err != OK or img.is_empty():
		return {}
	var longest := maxi(img.get_width(), img.get_height())
	if longest > MAX_SIDE:
		var k := float(MAX_SIDE) / float(longest)
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return {"image": img, "hole": pick["hole"], "credit": pick["credit"]}


## A MAME layout, read: {"elements": {name: image file}, "views": [{"name", "screen": Rect2 or null,
## "bezels": [{"element", "bounds": Rect2, "after_screen": bool}]}], "credit": all its comments, joined}.
## Both forms of a view's art are read: the old `<bezel element="...">` and the version-2
## `<element ref="...">`. A bounds is `x y width height`, `left top right bottom` or `xc yc width height`.
static func parse_layout(text: String) -> Dictionary:
	var out := {"elements": {}, "views": [], "credit": ""}
	var parser := XMLParser.new()
	if parser.open_buffer(text.to_utf8_buffer()) != OK:
		return out
	var comments: PackedStringArray = []
	var element := ""
	var view: Dictionary = {}
	var item: Dictionary = {}
	while parser.read() == OK:
		var node := parser.get_node_type()
		if node == XMLParser.NODE_COMMENT:
			comments.append(parser.get_node_name())
			continue
		if node == XMLParser.NODE_ELEMENT_END:
			match parser.get_node_name():
				"element":
					if not item.is_empty():
						_close_item(view, item)
						item = {}
					else:
						element = ""
				"view":
					if not view.is_empty():
						(out["views"] as Array).append(view)
					view = {}
				"bezel", "screen":
					_close_item(view, item)
					item = {}
			continue
		if node != XMLParser.NODE_ELEMENT:
			continue
		var tag := parser.get_node_name()
		var empty := parser.is_empty()
		match tag:
			"element":
				if view.is_empty():
					element = parser.get_named_attribute_value_safe("name")
				else:
					item = {"kind": "art", "element": parser.get_named_attribute_value_safe("ref"),
						"bounds": Rect2(0, 0, 1, 1)}
					if empty:
						_close_item(view, item)
						item = {}
			"image":
				if not element.is_empty() and view.is_empty() and not (out["elements"] as Dictionary).has(element):
					out["elements"][element] = parser.get_named_attribute_value_safe("file")
			"view":
				view = {"name": parser.get_named_attribute_value_safe("name"), "screen": null, "bezels": []}
				if empty:
					(out["views"] as Array).append(view)
					view = {}
			"bezel":
				if not view.is_empty():
					item = {"kind": "bezel", "element": parser.get_named_attribute_value_safe("element"),
						"bounds": Rect2(0, 0, 1, 1)}
					if empty:
						_close_item(view, item)
						item = {}
			"screen":
				if not view.is_empty():
					item = {"kind": "screen", "bounds": Rect2(0, 0, 1, 1)}
					if empty:
						_close_item(view, item)
						item = {}
			"bounds":
				if not item.is_empty():
					item["bounds"] = _bounds(parser)
	out["credit"] = "\n".join(comments).strip_edges()
	return out


static func _close_item(view: Dictionary, item: Dictionary) -> void:
	if view.is_empty() or item.is_empty():
		return
	if str(item["kind"]) == "screen":
		if view["screen"] == null:
			view["screen"] = item["bounds"]
		return
	(view["bezels"] as Array).append({"element": item["element"], "bounds": item["bounds"],
		"after_screen": view["screen"] != null, "legacy": str(item["kind"]) == "bezel"})


static func _bounds(parser: XMLParser) -> Rect2:
	var f := func(attr: String, fallback: float) -> float:
		var v := parser.get_named_attribute_value_safe(attr)
		return float(v) if v.is_valid_float() else fallback
	if parser.has_attribute("left") or parser.has_attribute("right"):
		var l: float = f.call("left", 0.0)
		var t: float = f.call("top", 0.0)
		return Rect2(l, t, f.call("right", 1.0) - l, f.call("bottom", 1.0) - t)
	var w: float = f.call("width", 1.0)
	var h: float = f.call("height", 1.0)
	if parser.has_attribute("xc") or parser.has_attribute("yc"):
		return Rect2(f.call("xc", 0.0) - w * 0.5, f.call("yc", 0.0) - h * 0.5, w, h)
	return Rect2(f.call("x", 0.0), f.call("y", 0.0), w, h)


## The bezel to hang, from a parsed layout: {"file", "hole": Rect2 (0..1 of the picture), "credit", "view"}, or
## {} when the layout has none that is the cabinet's own. Of the views with a bezel round the screen, the first
## whose name is not a widescreen or cocktail one, and whose bezel is not a 16:9 canvas; none at all when the
## credits say the bezel was drawn.
static func pick_bezel(layout: Dictionary) -> Dictionary:
	var credit := str(layout.get("credit", ""))
	if is_fan_made(credit):
		return {}
	var elements: Dictionary = layout.get("elements", {})
	var best: Dictionary = {}
	var best_score := -1
	for view: Dictionary in layout.get("views", []):
		if view["screen"] == null:
			continue
		var screen: Rect2 = view["screen"]
		var vname := str(view["name"]).to_lower()
		if vname.contains("cocktail") or is_fan_made(vname):
			continue
		for b: Dictionary in view["bezels"]:
			var file := str(elements.get(b["element"], ""))
			var bounds: Rect2 = b["bounds"]
			if file.is_empty() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				continue
			# A bezel holds the screen: its bounds round it, larger than it.
			if not bounds.grow(0.001).encloses(screen) or bounds.get_area() <= screen.get_area() * 1.05:
				continue
			# A version-2 layout names any picture an element: one drawn under the screen is a backdrop.
			if not bool(b["legacy"]) and not bool(b["after_screen"]) and not str(b["element"]).to_lower().contains("bezel"):
				continue
			var aspect := bounds.size.x / bounds.size.y
			if absf(aspect - 16.0 / 9.0) < 0.05:
				continue
			var score := 2 if str(b["element"]).to_lower().contains("bezel") else 1
			score += 1 if vname.contains("upright") or vname.contains("bezel") or vname.contains("artwork") else 0
			if score > best_score:
				best_score = score
				var hole := Rect2((screen.position - bounds.position) / bounds.size, screen.size / bounds.size)
				best = {"file": file, "hole": hole, "credit": credit, "view": view["name"]}
	return best


## Do these credits (or this view's name) say the art was drawn rather than scanned?
static func is_fan_made(text: String) -> bool:
	var t := text.to_lower()
	if t.contains("scanned") or t.contains("scan by") or t.contains("scans by"):
		return false
	for w in FAN_WORDS:
		if t.contains(w):
			return true
	return false
