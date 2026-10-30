## Saves the wall switch's two meshes from the Blender model to the .res files the rooms use:
## imported-assets/room/light_switch.glb -> Scenes/Objects/room/switch_plate_2gang.res and switch_toggle.res.
##
##   godot --headless --path RetroXR --import
##   godot --headless --path RetroXR --script res://Tools/gen/import_light_switch.gd
##
## The model is RetroXR-models rooms/light_switch/light_switch.py: a US two-gang toggle plate in ivory thermoset
## at its real size, the edge rolled, the screws domed and slotted, the apertures chamfered into dark wells, and a
## tapered toggle bat. It keeps gen_light_switch.gd's frame exactly (x along the wall, y up, z out; the plate's back
## at z = 0; the toggle's origin its pivot, the bat along +Z), so the bedroom and the Starlight Arcade mount it
## unchanged. The meshes are saved as standalone ArrayMeshes, materials embedded, because both rooms' scenes (and
## the arcade mod's) name these two paths.
extends SceneTree

const MODEL := "res://imported-assets/room/light_switch.glb"
const PLATE_PATH := "res://Scenes/Objects/room/switch_plate_2gang.res"
const TOGGLE_PATH := "res://Scenes/Objects/room/switch_toggle.res"


func _init() -> void:
	var scene := load(MODEL) as PackedScene
	if scene == null:
		push_error("[import_light_switch] cannot load %s (import it first)" % MODEL)
		quit(1)
		return
	var root := scene.instantiate()
	var saved := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var path := PLATE_PATH if mi.name == "plate" else TOGGLE_PATH if mi.name == "toggle" else ""
		if path.is_empty():
			continue
		var mesh := mi.mesh.duplicate(true) as ArrayMesh
		mesh.resource_name = String(mi.name)
		var err := ResourceSaver.save(mesh, path)
		print("[import_light_switch] %s -> %s (%s, %d surfaces)" % [mi.name, path, error_string(err), mesh.get_surface_count()])
		if err == OK:
			saved += 1
	root.free()
	quit(0 if saved == 2 else 1)
