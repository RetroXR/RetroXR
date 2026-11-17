## The installed NAOMI Universal's actual cash-box mesh, dressed and seated by
## CoverSlots, through the same physics checks as the unattended synthetic tray.
## Run windowed with -- --record [--fast | --no-box | --seated] [--pack=<path to xenu.naomiuniversal.zip>].
extends "res://Tests/arcade_cash_tests.gd"


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--no-box"):
		await _run_no_box()
	elif OS.get_cmdline_user_args().has("--fast"):
		await _run_fast()
	elif OS.get_cmdline_user_args().has("--seated"):
		await _run_seated()
	else:
		await super()


func _setup() -> void:
	for owner_id in LoadingOverlay.owners():
		LoadingOverlay.end(owner_id)
	LoadingOverlay.suspend()
	super()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.14, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _tray_part() -> MeshInstance3D:
	var pack := DataPaths.media_root().path_join("mods/xenu.naomiuniversal.zip")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			pack = arg.substr(7)
	assert(ProjectSettings.load_resource_pack(pack), "Cannot mount NAOMI Universal pack")
	var model := load("res://mods/xenu.naomiuniversal/model/naomi_universal.glb") as PackedScene
	assert(model != null, "Cannot load NAOMI Universal model")
	var root := model.instantiate() as Node3D
	add_child(root)
	var original := root.find_child("CashBoxLiftOff", true, false) as MeshInstance3D
	assert(original != null, "Model has no CashBoxLiftOff")
	var part := original.duplicate() as MeshInstance3D
	part.transform = original.global_transform
	root.free()
	return part


func _tray_out() -> Vector3:
	return Vector3.BACK


func _draw_collision_tray() -> bool:
	return false
