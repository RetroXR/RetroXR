## Bakes the arcade cabinets to Scenes/Objects/system_models/.
##
## Run once per cabinet, out of band:
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_arcade_cabinet.gd [-- --variant=NAME]
##
## The default variant is `generic`, arcade_cabinet.tscn. The others are the same shells with other
## controls and a bay for another system (ArcadeCabinetSpecs.variants): `neogeo` (the MVS, four
## buttons), `daphne` (laserdisc, a stick and the sword button), `daphne_gun` (the same with guns) and
## `dice` (paddle dials). A shooting cabinet is no variant: the generic one becomes it when a gun game is in its bay. ALL of them honour the module
## contract, so none is a fork of the model script; only the scene and the registry row differ.
##
## The nodes are made by ArcadeCabinetBuilder, the same code a cabinet in the room builds its form
## with when the game in its bay wants another one; this script only picks the row and saves the scene.
## Run `--editor --quit` first when a class_name is new: `--script` mode reads the class cache.
extends SceneTree

const U := preload("res://Tools/gen/arcade_gen_util.gd")

const OUT_DIR := "res://Scenes/Objects/system_models/"


func _initialize() -> void:
	var name := "generic"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			name = a.substr(10)
	var spec := ArcadeCabinetSpecs.variant(name)
	if spec.is_empty():
		push_error("unknown variant: %s (%s)" % [name, ", ".join(ArcadeCabinetSpecs.variants().keys())])
		quit(1)
		return
	spec["variant"] = name
	var root := Node3D.new()
	root.name = "ArcadeCabinet"
	root.set_script(load(ArcadeCabinetBuilder.SCRIPTS["model"]))
	ArcadeCabinetBuilder.new(spec, root, true).bake()
	quit(U.save(root, OUT_DIR + str(spec["out"])))
