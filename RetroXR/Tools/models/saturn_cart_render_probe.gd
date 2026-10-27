## Renders every cartridge the slot behind a Saturn's lid takes, seated, one at a
## time, and prints what the machine pins with each one in.
##
## Not a test -- expansion_tests' saturncart/ group proves the seat and the pins.
## This is the picture of it, which a headless run cannot take.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/models/saturn_cart_render_probe.tscn -- --out=C:/path/to/shots
##
## Windowed, never --headless: the dummy renderer returns a correctly sized blank.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE := preload("res://Scenes/Objects/expansion.tscn")

## Clear of the origin, where the boot splash stands and would fill the frame.
const STAGE := Vector3(4.0, 1.0, 4.0)
const CARTS := ["sega_saturn_ram_cart", "sega_saturn_extram_1m", "sega_saturn_extram_4m",
	"sega_saturn_kof95_rom", "sega_saturn_ultraman_rom"]
## Over the front corner, looking down past the lid into the slot; and from behind,
## where the cartridge's back stands out of the roof.
const VIEWS := {
	"front": [Vector3(0.12, 0.42, 0.30), Vector3(0.0, 0.06, -0.10)],
	"rear": [Vector3(-0.22, 0.24, -0.40), Vector3(0.0, 0.05, -0.10)],
}

var out_dir := ""
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if out_dir.is_empty():
		push_error("need --out=<dir>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	# The loading curtain is a 44 m backdrop 10 m down -Z, black: behind anything
	# filmed from the front it swallows a dark shell whole.
	var curtain := get_node_or_null("/root/LoadingOverlay/LoadingPanel") as Node3D
	if curtain != null:
		curtain.visible = false
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(1))
	_light()
	await _shoot()
	get_tree().quit(0)


func _light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.5
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_energy = 0.5
	add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])


func _shoot() -> void:
	var saturn := SYSTEM_SCENE.instantiate() as RetroSystem
	saturn.systemid = "saturn"
	saturn.freeze = true
	add_child(saturn)
	saturn.global_position = STAGE
	await _wait(40)

	for id: String in CARTS:
		var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
		unit.expansion_id = id
		unit.freeze = true
		add_child(unit)
		unit.global_position = STAGE + Vector3(0.5, 0.0, 0.0)
		await _wait(10)
		saturn.restore_expansion(unit)
		await _wait(20)
		print("[probe] %s seated=%s beetle=%s yaba=%s core=%s" % [id,
			str(saturn.expansion_ids()),
			str(saturn.all_forced_options("mednafen_saturn").get("beetle_saturn_cart", "?")),
			str(saturn.all_forced_options("yabasanshiro").get("yabasanshiro_addon_cart", "?")),
			saturn.resolve_core_name()])
		for view: String in VIEWS:
			var v: Array = VIEWS[view]
			_cam.position = STAGE + (v[0] as Vector3)
			_cam.look_at(STAGE + (v[1] as Vector3), Vector3.UP)
			await _wait(2)
			await _grab("%s_%s" % [id, view])
		var socket := saturn.get_node_or_null("ExpansionSocket") as XRToolsSnapZone
		socket.forget_object(unit)
		socket.drop_object()
		unit.queue_free()
		await _wait(10)

	# The Video CD Card in its slot in the back, with a cartridge in behind the lid.
	for id: String in ["sega_saturn_vcd_card", "sega_saturn_extram_4m"]:
		var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
		unit.expansion_id = id
		unit.freeze = true
		add_child(unit)
		unit.global_position = STAGE + Vector3(0.5, 0.0, 0.0)
		await _wait(10)
		saturn.restore_expansion(unit)
		await _wait(20)
	print("[probe] vcd seated=%s mpeg=%s cart=%s core=%s" % [str(saturn.expansion_ids()),
		str(saturn.all_forced_options("mednafen_saturn").get("beetle_saturn_mpeg_card", "?")),
		str(saturn.all_forced_options("mednafen_saturn").get("beetle_saturn_cart", "?")),
		saturn.resolve_core_name()])
	for shot: Array in [["vcd_card_rear", Vector3(0.05, 0.22, -0.42)],
			["vcd_card_rear_low", Vector3(-0.30, 0.06, -0.30)]]:
		_cam.position = STAGE + (shot[1] as Vector3)
		_cam.look_at(STAGE + Vector3(-0.04, 0.0, -0.10), Vector3.UP)
		await _wait(2)
		await _grab(str(shot[0]))
	print("[probe] wrote %d shots to %s" % [CARTS.size() * VIEWS.size() + 2, out_dir])
