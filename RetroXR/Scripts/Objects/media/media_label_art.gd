class_name MediaLabelArt
extends RefCounted
## A picture for a tape's label, found beside the file the tape carries:
## `Home Movies.mp4` is labelled by `Home Movies.png` (or .jpg/.jpeg/.webp) in
## the same folder, so a label made elsewhere drops in as it was downloaded.
## The image is only ever READ and never saved: the path is derived from the
## media path, so nothing about it goes into a save or onto the wire.
##
## Which picture goes where, by what the medium has:
##   video tape  `Name.png` the face sticker, `Name spine.png` the spine
##   album tape  `Name.png` (or `Name A.png`) side A, `Name B.png` side B
##   album LP    the same two, on the label of each side
## An album that is a FOLDER takes `cover`/`folder`/`front`/`album` for side A and
## `back` for side B from inside it, or `Folder.png` / `Folder B.png` beside it.
## A medium with no side B shows side A on both, as a pressing with one design.

const EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const ALBUM_FRONT_STEMS: Array[String] = ["cover", "folder", "front", "album"]
const ALBUM_BACK_STEMS: Array[String] = ["back"]
## Longest side kept, in pixels. A label made for printing is several times what
## a hand-held tape can show, and every pixel of it would sit in VRAM.
const MAX_SIDE := 1024


## The image beside `media_path` named `<name><suffix>.<ext>`, or "" when there
## is none. A folder is an album, which has its own lookup (album_side), and an
## empty path has no picture at all.
static func sidecar(media_path: String, suffix := "") -> String:
	if media_path.is_empty() or DirAccess.dir_exists_absolute(media_path):
		return ""
	return _find(media_path.get_basename() + suffix)


## The picture for one side ("a" or "b") of an album: a folder of tracks, a single
## audio file or a playlist. "" when there is none.
static func album_side(album_path: String, side: String) -> String:
	if album_path.is_empty():
		return ""
	var back := side == "b"
	var is_folder := DirAccess.dir_exists_absolute(album_path)
	# A folder's own name is not a file name: "Vol. 2" has no extension to strip.
	var stem := album_path if is_folder else album_path.get_basename()
	var found := ""
	if is_folder:
		found = _in_folder(album_path, ALBUM_BACK_STEMS if back else ALBUM_FRONT_STEMS)
	if found.is_empty():
		found = _find(stem + (" B" if back else ""))
	if found.is_empty() and not back:
		found = _find(stem + " A")
	return found


static func _find(stem: String) -> String:
	for ext in EXTENSIONS:
		var candidate := "%s.%s" % [stem, ext]
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## The image in `folder` whose name is the earliest of `stems`, matched without
## regard to case (a file system that tells `Cover.JPG` from `cover.jpg` would
## otherwise lose the album's picture on one machine and keep it on another).
static func _in_folder(folder: String, stems: Array[String]) -> String:
	var dir := DirAccess.open(folder)
	if dir == null:
		return ""
	var files := dir.get_files()
	files.sort()
	var best := ""
	var best_rank := stems.size()
	for file in files:
		if file.get_extension().to_lower() not in EXTENSIONS:
			continue
		var rank := stems.find(file.get_basename().to_lower())
		if rank != -1 and rank < best_rank:
			best = folder.path_join(file)
			best_rank = rank
	return best


## Decode `job.path` into `job.image` (null when it will not decode). Runs on a
## pool thread: the load and the downscale are the expensive part, which is why
## the texture is left to the main thread. `job.square` cuts the middle square
## out first, for a round label that a wide picture would be stretched over.
static func decode_into(job: Dictionary) -> void:
	var image := Image.load_from_file(str(job.get("path", "")))
	if image != null and not image.is_empty():
		if bool(job.get("square", false)) and image.get_width() != image.get_height():
			var side := mini(image.get_width(), image.get_height())
			image = image.get_region(Rect2i(roundi((image.get_width() - side) * 0.5),
				roundi((image.get_height() - side) * 0.5), side, side))
		var longest := maxi(image.get_width(), image.get_height())
		if longest > MAX_SIDE:
			var scale := float(MAX_SIDE) / float(longest)
			image.resize(maxi(1, roundi(image.get_width() * scale)),
				maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
	else:
		image = null
	job["image"] = image


static func texture_from(image: Image) -> ImageTexture:
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Lay `tex` on a quad named `node_name` under `parent` at `at`, fitted inside
## `box` without stretching; made on the first call and re-used after. A null
## `tex` takes the quad away. Returns the quad, or null when there is none.
static func show_quad(parent: Node3D, node_name: String, tex: Texture2D, box: Vector2,
		at: Transform3D) -> MeshInstance3D:
	var quad := parent.get_node_or_null(node_name) as MeshInstance3D
	if tex == null:
		if quad != null:
			# Out of the tree now, so a picture arriving in the same frame does
			# not meet a half-gone quad of the same name.
			parent.remove_child(quad)
			quad.queue_free()
		return null
	if quad == null:
		quad = MeshInstance3D.new()
		quad.name = node_name
		quad.mesh = QuadMesh.new()
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.7
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		quad.material_override = mat
		quad.transform = at
		parent.add_child(quad)
	(quad.material_override as StandardMaterial3D).albedo_texture = tex
	(quad.mesh as QuadMesh).size = fit(float(tex.get_width()) / float(tex.get_height()), box)
	return quad


## `aspect` (width over height) fitted inside `box`, never stretched.
static func fit(aspect: float, box: Vector2) -> Vector2:
	if aspect <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return box
	if box.x / box.y > aspect:
		return Vector2(box.y * aspect, box.y)
	return Vector2(box.x, box.x / aspect)
