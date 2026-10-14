## Photographs a set's tube from the side, where a screen drawn with its back
## faces shows the far half of the picture THROUGH the near half.
##
##   godot --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/av/tv_side_view_probe.tscn -- \
##     [--shell=<id>] [--stage=crt|window|vcr|static] [--fast] \
##     [--picture=bars|quarters] [--yaws=78,82,86] [--out=<dir>]
##
## Windowed: the dummy headless renderer returns a blank image.
##
## `--picture=bars` (the default) is for looking at: eight colour bars, read near
## bar first and each one once. `--picture=quarters` is the leg that checks
## itself: four bands, red green blue yellow, so along any row of the photograph
## they are met IN ORDER and none is skipped, from whichever end. The back of the
## tube is its far quarter lying over the middle of the picture — the last band
## met before the third — and the probe exits 1. Two bands are not enough: the far half lands
## beside what can be seen of itself and reads as one run. It shows from one side
## only — whichever has the far triangles later in the index buffer — and only
## past the angle at which the tube's far edge turns away, so the default angles
## are steep and on both sides.
##
## `--shell` defaults to the stock cabinet, whose 9 mm tube barely shows it; the
## deep tubes are the ones that do (a mod's, e.g. xenu.panasonic:ct20d10b, which
## has to be installed and enabled). `--stage` puts one of the other three screen
## shaders on the tube directly, and `--fast` takes the mobile tier of whichever.
extends Node3D

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
## Past about 76 degrees the far edge of a 25 mm tube has turned its back to the
## camera; 0 and 60 are the picture read normally.
const LOOK_YAWS: Array[float] = [-86.0, -82.0, -60.0, 0.0, 60.0, 82.0, 86.0]
## Head on too: a tube whose faces wind the other way is not there at all.
const CHECK_YAWS: Array[float] = [-88.0, -86.0, -84.0, -82.0, 0.0, 82.0, 84.0, 86.0, 88.0]
const QUARTERS: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
const BARS: Array[Color] = [
	Color(1, 1, 1), Color(1, 1, 0), Color(0, 1, 1), Color(0, 1, 0),
	Color(1, 0, 1), Color(1, 0, 0), Color(0, 0, 1), Color(0.35, 0.35, 0.35),
]
const STAGES := {
	"window": RetroTV.WINDOW_SHADER,
	"vcr": RetroTV.VCR_SHADER,
	"static": RetroTV.STATIC_SHADER,
}

var _viewport: SubViewport
var _tv: RetroTV
var _out := "res://../build_out/tv_probe"
var _shell := ""
var _stage := "crt"
var _picture := "bars"
var _fast := false
var _yaws: Array[float] = []


class StubSource extends Node3D:
	var texture: Texture2D

	func get_video_texture() -> Texture2D:
		return texture

	func set_audio_volume(_value: float) -> void:
		pass


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--shell="):
			_shell = arg.trim_prefix("--shell=")
		elif arg.begins_with("--stage="):
			_stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--picture="):
			_picture = arg.trim_prefix("--picture=")
		elif arg == "--fast":
			_fast = true
		elif arg.begins_with("--yaws="):
			for yaw: String in arg.trim_prefix("--yaws=").split(","):
				_yaws.append(yaw.to_float())
	if _stage != "crt" and not STAGES.has(_stage):
		printerr("[side-view] no stage '%s'" % _stage)
		get_tree().quit(1)
		return
	if _yaws.is_empty():
		_yaws = CHECK_YAWS if _picture == "quarters" else LOOK_YAWS
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		printerr("[side-view] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	# Before the set is built: it picks its shaders' tier as it comes up.
	if _fast:
		QualityManager.crt_fast = true

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_energy = 0.6
	world_env.environment = env
	_viewport.add_child(world_env)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -18.0, 0.0)
	fill.light_energy = 0.7
	fill.shadow_enabled = false
	_viewport.add_child(fill)

	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.tv_model = _shell
	_tv.position = Vector3(0.0, 1.0, 0.0)
	_tv.freeze = true
	_viewport.add_child(_tv)
	await _wait(40)
	if _shell != "" and _tv.shell() == null:
		printerr("[side-view] shell '%s' did not load" % _shell)
		get_tree().quit(1)
		return

	# The stock cabinet's bezel caps are green, blue and yellow as well, and from
	# the side the row of them stands in front of the bottom of the tube.
	if _picture == "quarters":
		for cap: Node in _tv.find_children("*", "VRButton", true, false):
			(cap as Node3D).hide()

	var screen := _tv.screen_mesh()
	var centre := screen.global_transform * screen.mesh.get_aabb().get_center()
	var camera := Camera3D.new()
	camera.position = centre + Vector3(0.0, 0.05, 1.1)
	camera.fov = 32.0
	_viewport.add_child(camera)
	camera.look_at(centre, Vector3.UP)
	camera.current = true

	var source := StubSource.new()
	source.texture = _quarters() if _picture == "quarters" else _bars()
	_viewport.add_child(source)
	# A cabinet with no phono sockets (the computer monitor) takes it over VGA.
	var input := RetroTV.Source.COMPOSITE_1
	if _tv.shell() != null and _tv.shell().av_inputs == 0:
		input = RetroTV.Source.VGA
	_tv._panel._connected_systems[input] = source
	_tv.set_source(input)
	await _wait(20)

	var staged: ShaderMaterial = null
	if _stage != "crt":
		staged = ShaderMaterial.new()
		staged.shader = RetroTV.stage_shader(STAGES[_stage])
		staged.set_shader_parameter("source_tex", source.texture)
		staged.set_shader_parameter("crt_enabled", true)
		_tv._display.apply_crt_params(staged)
		# The tape's tracking line and roll drag one row of the picture sideways,
		# a different row each frame, and the check would read that as disorder.
		if _stage == "vcr" and _picture == "quarters":
			staged.set_shader_parameter("effect_amount", 0.0)
		# material_override, which outranks the surface override the set keeps
		# putting back every frame.
		screen.material_override = staged
		await _wait(10)

	var material := screen.get_active_material(0) as ShaderMaterial
	if staged != null:
		material = staged
	var bounds := screen.mesh.get_aabb()
	var cabinet := _shell.get_slice(":", 0).replace(".", "_") if _shell != "" else "stock"
	print("[side-view] shell=%s shader=%s tube=%s deep=%.1f mm" % [cabinet,
		material.shader.resource_path if material != null else "none",
		bounds.size * screen.scale, bounds.size.z * screen.scale.z * 1000.0])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var failures := 0
	var most_rows := 0
	# Turn the set about the tube, not about its own origin, so the glass stays
	# in the middle of the frame at every angle.
	var home := _tv.global_transform
	for yaw: float in _yaws:
		var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3.ZERO)
		_tv.global_transform = Transform3D(Basis.IDENTITY, centre) * turn \
			* Transform3D(Basis.IDENTITY, -centre) * home
		_tv.hide_osd()
		await _wait(10)
		await RenderingServer.frame_post_draw
		if staged != null and screen.material_override != staged:
			printerr("[side-view] the set took its own material back; '%s' was not photographed"
				% _stage)
			get_tree().quit(1)
			return
		var image := _viewport.get_texture().get_image()
		var label := "m%02d" % int(absf(yaw)) if yaw < 0.0 else "p%02d" % int(yaw)
		var path := "%s/tv_side_%s_%s%s_%s_%s.png" % [_out, cabinet, _stage,
			"_fast" if _fast else "", _picture, label]
		var error := image.save_png(path)
		if error != OK:
			printerr("[side-view] could not save %s: %s" % [path, error])
			get_tree().quit(1)
			return
		if _picture == "quarters" and _stage != "static":
			var read := _read_quarters(image, _tube_rect(camera, screen))
			var ok: bool = read["disordered"] == 0
			if not ok:
				failures += 1
			most_rows = maxi(most_rows, read["rows"])
			print("[side-view] %s yaw %+.0f: %d rows carry the picture, %d out of order%s" % [
				"ok" if ok else "FAIL", yaw, read["rows"], read["disordered"],
				"" if read["disordered"] == 0 else " (row %d reads %s)" % [read["first"], read["reads"]]])
		print("[side-view] %s" % path)
	if failures > 0:
		printerr("[side-view] FAILED: the back of the tube shows at %d angle(s)" % failures)
	# A deep bezel hides the tube altogether at the steepest angles, which is no
	# fault. Not being there from ANY of them is.
	if _picture == "quarters" and _stage != "static" and most_rows < 50:
		printerr("[side-view] FAILED: the picture is on the tube from no angle")
		failures += 1
	get_tree().quit(1 if failures > 0 else 0)


## The tube's bounding box as the camera sees it, in viewport pixels. The check
## reads inside it only, so nothing else on the cabinet can be taken for a band.
func _tube_rect(camera: Camera3D, screen: MeshInstance3D) -> Rect2i:
	var bounds := screen.mesh.get_aabb()
	var rect := Rect2()
	for i in 8:
		var point := camera.unproject_position(screen.global_transform * bounds.get_endpoint(i))
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, _viewport.size))


## Eight vertical bars, white on the picture's left through to grey on its right,
## with a black notch cut out of the TOP of each so an upside-down or mirrored
## read is plain too.
func _bars() -> Texture2D:
	var image := Image.create(512, 384, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var bar := x * BARS.size() / image.get_width()
			var in_bar := x % (image.get_width() / BARS.size())
			var notch := y < 48 and in_bar < 20
			image.set_pixel(x, y, Color.BLACK if notch else BARS[bar])
	return ImageTexture.create_from_image(image)


## Four bands, red on the picture's left through to yellow on its right. Colours
## nothing else in the frame is, so a pixel is one of the four or not the picture.
func _quarters() -> Texture2D:
	var image := Image.create(512, 384, false, Image.FORMAT_RGBA8)
	for band in QUARTERS.size():
		image.fill_rect(Rect2i(band * 128, 0, 128, 384), QUARTERS[band])
	return ImageTexture.create_from_image(image)


## Which band a photographed pixel is, or -1 for none of them.
func _quarter_of(c: Color) -> int:
	var r := c.r > 0.6
	var g := c.g > 0.6
	var b := c.b > 0.6
	if c.b < 0.35 and r and g:
		return 3
	if r and c.g < 0.35 and c.b < 0.35:
		return 0
	if g and c.r < 0.35 and c.b < 0.35:
		return 1
	if b and c.r < 0.35 and c.g < 0.35:
		return 2
	return -1


## Walks every row of the tube in a photograph of the quarters picture and counts
## the rows whose bands are not met in order, one after the next. None may be skipped:
## a farther band is never the wider one, so yellow straight after green is the
## far quarter over a blue too thin to count. A run of one pixel is the blended
## seam between two bands and counts as neither.
func _read_quarters(image: Image, within: Rect2i) -> Dictionary:
	var rows := 0
	var disordered := 0
	var first := -1
	var reads := ""
	for y in range(within.position.y, within.end.y):
		var met: Array[int] = []
		var current := -1
		var length := 0
		for x in range(within.position.x, within.end.x + 1):
			var band := _quarter_of(image.get_pixel(x, y)) if x < within.end.x else -1
			if band == current:
				length += 1
				continue
			if current >= 0 and length >= 2 and (met.is_empty() or met[-1] != current):
				met.append(current)
			current = band
			length = 1
		if met.is_empty():
			continue
		rows += 1
		var rising := true
		var falling := true
		for i in range(1, met.size()):
			rising = rising and met[i] == met[i - 1] + 1
			falling = falling and met[i] == met[i - 1] - 1
		if not (rising or falling):
			disordered += 1
			if first < 0:
				first = y
				reads = "".join(met.map(func(band: int) -> String: return "RGBY"[band]))
	return {"rows": rows, "disordered": disordered, "first": first, "reads": reads}


func _wait(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
