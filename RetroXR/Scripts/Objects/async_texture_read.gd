## AsyncTextureRead — a rendered texture's pixels back on the main thread
## WITHOUT stopping it to wait for them.
##
## `texture.get_image()` on a viewport texture is a synchronous round trip: with
## Godot's separate render thread (project.godot sets it on Windows) it makes the
## main thread wait for the render thread to catch up, and the Starlight Arcade's
## 17 screen-cast lights did that every few frames (2026-11-07, performance.md).
## The read is queued on the render thread instead
## (RenderingServer.call_on_render_thread + RenderingDevice.texture_get_data_async),
## and the pixels reach the owner on the main thread a frame or two later. With
## no RenderingDevice (headless, the Compatibility renderer) or a texture format
## not mapped below, it reads synchronously as before and the owner is called at
## once.
##
## The owner's method takes `(data: PackedByteArray, width: int, height: int,
## format: int)` and turns it into an Image with `image_from()` (null when the read
## failed). It is not handed an Image because of WHO holds the callback: the
## RenderingDevice keeps a pending download's callable until the frame lands, and
## on quit that is AFTER GDScript has shut down (Main::cleanup finishes the script
## languages before finalize_display flushes and frees the RD). A GDScript lambda
## held there was called or freed with no GDScript left: a segfault on quit, every
## time a read was in flight (3 of 3, 0 of 3 with blocking reads). So the RD holds
## only native callables -- the owner's method by object id, bound to the sizes,
## deferred through Callable.call_deferred -- and the last MessageQueue flush skips
## a call to an owner that is gone, without a word.
class_name AsyncTextureRead
extends RefCounted

## Read the old blocking way (`get_image()`) every time: the A/B switch for a
## probe measuring what the async read saves.
static var synchronous := false
static var _logged_async := false
static var _logged_fallback := false
static var _logged_mismatch := false


## Ask for `texture`'s pixels; `owner.method(data, width, height, format)` is
## called with them on the main thread.
static func request(texture: Texture2D, owner: Object, method: StringName) -> void:
	if texture == null or owner == null:
		return
	var target := Callable(owner, method)
	if synchronous or RenderingServer.get_rendering_device() == null:
		_deliver_image(target, texture.get_image())
		return
	var tex_rid := texture.get_rid()
	RenderingServer.call_on_render_thread(func() -> void:
		_read_on_render_thread(tex_rid, target, texture))


## The pixels as an Image, or null when the read failed or the bytes do not
## match the size.
static func image_from(data: PackedByteArray, width: int, height: int, format: int) -> Image:
	if format < 0 or width <= 0 or height <= 0:
		return null
	var bytes_per_pixel := 8 if format == Image.FORMAT_RGBAH else 4
	if data.size() != width * height * bytes_per_pixel:
		if not _logged_mismatch:
			_logged_mismatch = true
			push_warning("[AsyncTextureRead] got %d bytes for %dx%d (format %d): dropped" % [data.size(), width, height, format])
		return null
	return Image.create_from_data(width, height, false, format, data)


static func _read_on_render_thread(tex_rid: RID, target: Callable, texture: Texture2D) -> void:
	var rd := RenderingServer.get_rendering_device()
	var rd_tex := RenderingServer.texture_get_rd_texture(tex_rid)
	if rd == null or not rd_tex.is_valid():
		_deliver_sync.call_deferred(target, texture, "no RD texture")
		return
	var fmt := rd.texture_get_format(rd_tex)
	var image_format := _image_format(fmt.format)
	if image_format < 0:
		_deliver_sync.call_deferred(target, texture, "texture format %d is not mapped" % fmt.format)
		return
	var w := int(fmt.width)
	var h := int(fmt.height)
	# Native all the way down (see the header): the bound owner method, deferred.
	var done := Callable.create(target.bind(w, h, image_format), &"call_deferred")
	var err := rd.texture_get_data_async(rd_tex, 0, done)
	if err != OK:
		_deliver_sync.call_deferred(target, texture, "texture_get_data_async: error %d" % err)
		return
	if not _logged_async:
		_logged_async = true
		print("[AsyncTextureRead] reading %dx%d textures without waiting (format %d)" % [w, h, fmt.format])


static func _image_format(data_format: int) -> int:
	match data_format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			return Image.FORMAT_RGBA8
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			return Image.FORMAT_RGBAH
	return -1


## The async path could not take this texture: read it the old way, on the main
## thread, the first failure logged.
static func _deliver_sync(target: Callable, texture: Texture2D, why: String) -> void:
	if not _logged_fallback:
		_logged_fallback = true
		push_warning("[AsyncTextureRead] %s: reading synchronously" % why)
	if not target.is_valid() or texture == null:
		return
	_deliver_image(target, texture.get_image())


static func _deliver_image(target: Callable, image: Image) -> void:
	if image == null or image.is_empty():
		target.call(PackedByteArray(), 0, 0, -1)
		return
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGBAH:
		image.convert(Image.FORMAT_RGBA8)
	target.call(image.get_data(), image.get_width(), image.get_height(), image.get_format())
