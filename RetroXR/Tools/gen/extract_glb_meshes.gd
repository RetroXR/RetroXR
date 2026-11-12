## Bakes every mesh of one of RetroXR's own GLBs into a standalone Mesh resource, one per node, so a scene
## that keeps its own node tree (paths that scripts, saves and netplay name) can wear the model's meshes
## without instancing the GLB: the RETRO XR pad (retro_controller.tscn), light gun and mouse.
##
##   godot --headless --path RetroXR --script res://Tools/gen/extract_glb_meshes.gd -- <src.glb> <dst dir>
##
## Writes <dst dir>/<NodeName>.res for every MeshInstance3D in the GLB, materials included, and prints
## each one's node transform: a scene adopting a mesh must take that transform too, since the mesh is
## authored about its node's origin.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[extract] usage: -- <src.glb> <dst dir>")
		quit(1)
		return
	var ps := load(args[0]) as PackedScene
	if ps == null:
		print("[extract] cannot load %s" % args[0])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(args[1]))
	var root: Node = ps.instantiate()
	var n := 0
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var dst := "%s/%s.res" % [args[1], m.name]
		var err := ResourceSaver.save(m.mesh.duplicate(true), dst)
		if err != OK:
			print("[extract] FAILED %s: %d" % [dst, err])
			root.free()
			quit(1)
			return
		print("[extract] %s  transform %s" % [dst, m.transform])
		n += 1
	root.free()
	print("[extract] wrote %d meshes" % n)
	quit(0 if n > 0 else 1)
