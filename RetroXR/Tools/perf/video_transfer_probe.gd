## Real-core transfer timing. Use an isolated --root containing cores/ and system/.
## Requires a real core/content and a GPU, so this is a tool rather than a test.
extends Node3D

var _lib: Libretro
var _failed := ""


func _ready() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	var root_dir := str(args.get("root", ""))
	var core := str(args.get("core", ""))
	var rom := str(args.get("rom", ""))
	if root_dir.is_empty() or core.is_empty() or rom.is_empty():
		push_error("[transfer] need --root=<isolated core root> --core=<name> --rom=<path>")
		get_tree().quit(2)
		return
	var seconds := maxf(float(args.get("seconds", 15.0)), 1.0)
	var warmup := maxf(float(args.get("warmup", 5.0)), 0.0)
	get_tree().create_timer(seconds + warmup + 60.0).timeout.connect(func() -> void: get_tree().quit(1))
	_lib = Libretro.new()
	add_child(_lib)
	if not _lib.has_method("SetVideoTransferProfiling"):
		push_error("[transfer] rebuild libretro-godot for transfer profiling")
		get_tree().quit(1)
		return
	_lib.content_load_failed.connect(func(reason: String) -> void: _failed = reason)
	var camera := Camera3D.new()
	add_child(camera)
	var screen := MeshInstance3D.new()
	screen.mesh = QuadMesh.new()
	screen.position.z = -2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = material
	add_child(screen)
	_lib.StartContent(root_dir, core, rom)
	await get_tree().create_timer(warmup).timeout
	_lib.call("SetVideoTransferProfiling", true)
	var first_frame := _lib.GetFrameCount()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000.0 and _failed.is_empty():
		material.albedo_texture = _lib.GetVideoTexture()
		await get_tree().process_frame
	_lib.call("SetVideoTransferProfiling", false)
	var stats: Dictionary = _lib.call("GetVideoTransferStats")
	stats["core"] = core
	stats["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	stats["frames"] = _lib.GetFrameCount() - first_frame
	stats["failure"] = _failed
	print("[transfer] RESULT " + JSON.stringify(stats))
	_lib.StopContent()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0 if _failed.is_empty() and int(stats["texture_update"]["calls"]) > 0 else 1)
