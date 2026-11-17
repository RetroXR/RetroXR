## Can something that is not a console put a picture on a television?
##
## The set asks whatever is on its selected input for get_video_texture() and
## paints its own glass, so a mod's device -- a capture box, a camera, a PC --
## should only need to answer that and tell the set it is cabled to it. This
## builds such a device the way a mod would (video_source_probe_device.gd: no game
## class, a stock phono socket), cables it to a real set with a real composite
## cord and checks every step the docs promise: on the glass, a new texture
## followed, a null one dark, unplugged dark, despawned dark -- also when it never
## says goodbye.
##
##   godot --headless --path RetroXR res://Tools/av/video_source_probe.tscn
extends Node3D

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const PORT_SCENE := preload("res://Scenes/Objects/cables/rca_port.tscn")
const DEVICE_SCRIPT := preload("res://Tools/av/video_source_probe_device.gd")

var _fail := false


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[vsrc] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail = true
	print("[vsrc] %s  %s" % ["PASS" if ok else "FAIL", msg])


func _wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


## What the glass is sampling (see rca_channel_probe._shown).
func _shown(tv: RetroTV) -> Texture2D:
	var mat: Material = tv.get_screen_mesh().get_surface_override_material(0)
	if mat == tv._display._crt_material:
		return tv._display._crt_source_tex
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).get_shader_parameter("source_tex") as Texture2D
	return null


func _filed_on(tv: RetroTV, dev: Node) -> int:
	var systems: Array = tv._panel._connected_systems
	for i in systems.size():
		if is_instance_valid(systems[i]) and systems[i] == dev:
			return i
	return -1


## A device as a mod's scene would make it: its script, and one VIDEO OUT socket.
func _make_device(at: Vector3) -> Node3D:
	var dev := Node3D.new()
	dev.set_script(DEVICE_SCRIPT)
	dev.name = "TestPatternBox"
	dev.position = at
	var port := PORT_SCENE.instantiate() as RcaPort
	port.name = "VideoOut"
	port.channel = RcaPort.Channel.VIDEO
	port.direction = RcaPort.Direction.OUT
	dev.add_child(port)
	add_child(dev)
	return dev


## A fresh composite cord from the device's VIDEO OUT to the set's yellow input.
func _cable(dev: Node3D, tv: RetroTV) -> Node3D:
	var cable := CABLE_SCENE.instantiate() as Node3D
	cable.position = dev.position + Vector3(-0.5, 0, 0.6)
	add_child(cable)
	await _wait(25)
	(dev.get_node("VideoOut") as RcaPort).pick_up_object(cable.get_node("PlugA0") as RcaPlug)
	(tv.get_node("CompositePort") as RcaPort).pick_up_object(cable.get_node("PlugB0") as RcaPlug)
	await _wait(45)
	return cable


func _run() -> void:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.freeze = true
	add_child(tv)
	tv.add_to_group("spawned")
	await _wait(60)
	var blue: Texture2D = tv._display._blue_texture

	# ── A: cabled and selected, the picture is on the glass ───────────────────
	var dev = _make_device(Vector3(1.5, 1, 0))
	await _wait(10)
	var cable := await _cable(dev, tv)
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	await _wait(45)
	var tex: Texture2D = dev.get_video_texture()
	print("[vsrc] filed on input %d, device sees tv=%s, glass=%s"
		% [_filed_on(tv, dev), dev.connected_tv, _shown(tv)])
	_check(dev.connected_tv == tv, "AvSource.resolve finds the set from the device's own socket")
	_check(_filed_on(tv, dev) == RetroTV.Source.COMPOSITE_1, "the set files the device on Composite 1")
	_check(tv._panel.selected_system() == dev, "and it is the selected source")
	_check(_shown(tv) == tex, "the device's texture is on the glass")
	# Fullscreen reads the glass, which with phosphor persistence on is the CRT's
	# own ping-pong buffer rather than the source texture: lit, not no-signal.
	var full := tv.display().screen_texture()
	_check(full != null and full != blue,
		"desktop fullscreen of the set has a picture (TvDisplay.screen_texture)")
	_check(TvFullscreen.panels_for(tv).size() == 1, "the set offers one fullscreen panel")
	_check(RetroTV._device_name(dev) == "Test Pattern Box", "the source toast uses display_name()")

	# ── B: a new texture object (resolution change) is followed ───────────────
	var tex2 := DEVICE_SCRIPT.bars(Vector2i(640, 480))
	dev.texture = tex2
	await _wait(10)
	_check(_shown(tv) == tex2, "a new texture object is followed without telling the set")

	# ── C: null means no signal ───────────────────────────────────────────────
	dev.texture = null
	await _wait(10)
	print("[vsrc] null texture: glass=%s" % _shown(tv))
	_check(_shown(tv) != tex2, "a null texture takes the picture off the glass")
	dev.texture = tex
	await _wait(10)
	_check(_shown(tv) == tex, "and a texture again puts it back")

	# ── D: another input selected, then back ─────────────────────────────────
	tv.set_source(RetroTV.Source.COMPOSITE_2)
	await _wait(20)
	_check(_shown(tv) != tex, "on another input the device's picture is not shown")
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	await _wait(20)
	_check(_shown(tv) == tex, "back on its input it is")

	# ── E: unplugged at the set ───────────────────────────────────────────────
	(tv.get_node("CompositePort") as RcaPort).drop_object()
	await _wait(45)
	print("[vsrc] unplugged: filed=%d device tv=%s glass=%s"
		% [_filed_on(tv, dev), dev.connected_tv, _shown(tv)])
	_check(dev.connected_tv == null, "pulling the cord from the set tells the device")
	_check(_filed_on(tv, dev) < 0, "the set forgets the device")
	_check(_shown(tv) != tex, "and its picture leaves the glass")
	_check(_shown(tv) == blue, "the set shows its no-signal screen")
	cable.queue_free()
	await _wait(10)

	# ── F: despawned while cabled, saying goodbye (_exit_tree) ────────────────
	cable = await _cable(dev, tv)
	_check(_shown(tv) == tex, "re-cabled, the picture is back")
	dev.queue_free()
	await _wait(45)
	print("[vsrc] despawned: glass=%s selected=%s" % [_shown(tv), tv._panel.selected_system()])
	_check(tv._panel.selected_system() == null, "a despawned device is no longer the source")
	_check(_shown(tv) != tex, "its picture leaves the glass")
	cable.queue_free()
	await _wait(10)

	# ── G: despawned while cabled, WITHOUT saying goodbye ─────────────────────
	var rude = _make_device(Vector3(1.5, 1, 0))
	rude.polite = false
	await _wait(10)
	cable = await _cable(rude, tv)
	var rude_tex: Texture2D = rude.get_video_texture()
	_check(_shown(tv) == rude_tex, "a second device on the same input shows")
	rude.queue_free()
	await _wait(45)
	print("[vsrc] despawned rudely: glass=%s selected=%s"
		% [_shown(tv), tv._panel.selected_system()])
	_check(tv._panel.selected_system() == null, "a device freed without a word is not the source")
	_check(_shown(tv) != rude_tex, "and the set does not keep sampling its texture")
	cable.queue_free()
	await _wait(10)

	print("[vsrc] %s" % ("FAIL" if _fail else "ALL PASS"))
	tv.queue_free()
	await _wait(5)
	get_tree().quit(1 if _fail else 0)
