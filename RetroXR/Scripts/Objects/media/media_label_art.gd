class_name MediaLabelArt
extends RefCounted
## A picture for a tape's label, found beside the file the tape carries:
## `Home Movies.mp4` is labelled by `Home Movies.png` (or .jpg/.jpeg/.webp) in
## the same folder, so a label made elsewhere drops in as it was downloaded.
## The image is only ever READ and never saved: the path is derived from the
## media path, so nothing about it goes into a save or onto the wire.

const EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
## Longest side kept, in pixels. A label made for printing is several times what
## a hand-held tape can show, and every pixel of it would sit in VRAM.
const MAX_SIDE := 1024


## The image beside `media_path`, or "" when there is none. A folder is an
## album, which carries no label of its own here, and an empty path none at all.
static func sidecar(media_path: String) -> String:
	if media_path.is_empty() or DirAccess.dir_exists_absolute(media_path):
		return ""
	var stem := media_path.get_basename()
	for ext in EXTENSIONS:
		var candidate := "%s.%s" % [stem, ext]
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Decode `job.path` into `job.image` (null when it will not decode). Runs on a
## pool thread: the load and the downscale are the expensive part, which is why
## the texture is left to the main thread.
static func decode_into(job: Dictionary) -> void:
	var image := Image.load_from_file(str(job.get("path", "")))
	if image != null and not image.is_empty():
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


## `aspect` (width over height) fitted inside `box`, never stretched.
static func fit(aspect: float, box: Vector2) -> Vector2:
	if aspect <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return box
	if box.x / box.y > aspect:
		return Vector2(box.y * aspect, box.y)
	return Vector2(box.x, box.x / aspect)
