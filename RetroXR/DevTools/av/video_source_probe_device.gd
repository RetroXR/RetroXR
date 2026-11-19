## The smallest video source a mod can make: a box with a phono VIDEO OUT that
## hands a television a texture of its own. No game class, no core -- only what
## docs/modding.md's "A picture on a television" section asks for.
##
## Used by video_source_probe.gd, which builds it the way a mod's scene would.
extends Node3D

var texture: Texture2D = null
## The set this device's picture lead reaches, or null.
var connected_tv: RetroTV = null
## False only in the probe, to see what the set does with a source that vanishes
## without saying so.
var polite := true


func _init() -> void:
	texture = bars(Vector2i(320, 240))


## SMPTE-ish bars, so a frame on the glass is recognizably this device's.
static func bars(size: Vector2i) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var cols := [Color.WHITE, Color.YELLOW, Color.CYAN, Color.GREEN,
		Color.MAGENTA, Color.RED, Color.BLUE]
	for x in size.x:
		var c: Color = cols[x * cols.size() / size.x]
		for y in size.y:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## The picture. Read every frame by the set, so a new object (a resolution
## change) is picked up without telling anyone.
func get_video_texture() -> Texture2D:
	return texture


## REQUIRED of every source (AvSourceContract): the set's volume and mono switch.
## This box makes no sound, so both are no-ops; a device with audio applies them.
func set_audio_volume(_volume: float) -> void:
	pass


func set_audio_channel_mode(_mode: int) -> void:
	pass


func display_name() -> String:
	return "Test Pattern Box"


## A plug moved somewhere on one of this device's sockets. Required: it is also
## how a socket finds the device it belongs to (Port.get_device).
func on_av_topology_changed(_links: Array) -> void:
	var feed := AvSource.resolve(self, false)
	var tv: RetroTV = feed.video_sinks[0] if not feed.video_sinks.is_empty() else null
	if tv == connected_tv:
		return
	if is_instance_valid(connected_tv):
		connected_tv.on_av_source_lost(self)
	connected_tv = tv
	if tv != null:
		tv.on_av_source_found(self)


## Leaving the room (despawned, or the mod's object deleted): let go of the set,
## so it is not left holding a freed source.
func _exit_tree() -> void:
	if not polite:
		return          # the probe's careless case: freed without a word
	if is_instance_valid(connected_tv):
		connected_tv.on_av_source_lost(self)
	connected_tv = null
