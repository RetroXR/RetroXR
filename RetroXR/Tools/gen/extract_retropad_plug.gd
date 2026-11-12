## Bakes the RETRO XR generic controller plug out of plug_mobile.glb into a standalone Mesh for
## controller_cable.tscn's PlugTip (the plug every pad shows until its console names a connector of its own).
##
## Run headless to (re)generate the asset after re-exporting the model:
##   godot --headless --path RetroXR --script res://Tools/gen/extract_retropad_plug.gd
##
## The model is RetroXR's own (RetroXR-models generic/retropad, build_plug.py). Its export is already in
## ControllerPlug's frame -- connector on +Z, the cord leaving at z -0.040 along -Z, where the scene's CordExit
## marker already is -- so this is only a format change, checked on the way.
extends SceneTree

const SRC := "res://imported-assets/controllers/retropad/plug_mobile.glb"
const DST := "res://imported-assets/controllers/retropad/retropad_plug_mesh.res"


func _init() -> void:
	var ps := load(SRC) as PackedScene
	if ps == null:
		print("[extract] cannot load %s" % SRC)
		quit(1)
		return
	var root: Node = ps.instantiate()
	var mi := root.find_child("PlugTip", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		print("[extract] no PlugTip mesh in %s" % SRC)
		root.free()
		quit(1)
		return
	var mesh: Mesh = mi.mesh.duplicate(true)
	root.free()
	var ab: AABB = mesh.get_aabb()
	print("[extract] aabb %s .. %s, %d surfaces" % [ab.position, ab.end, mesh.get_surface_count()])
	if ab.end.z <= 0.0 or ab.position.z >= 0.0:
		print("[extract] REFUSING: connector must sit on +Z and the cable on -Z")
		quit(1)
		return
	# The scene's collision box is 20 x 20 x 60 mm over z -0.040 .. +0.020; the model must fit it.
	if absf(ab.position.x) > 0.0105 or absf(ab.position.y) > 0.0105 or ab.position.z < -0.0405 or ab.end.z > 0.0205:
		print("[extract] REFUSING: the model no longer fits ControllerPlug's 20 x 20 x 60 mm box")
		quit(1)
		return
	var err := ResourceSaver.save(mesh, DST)
	if err != OK:
		print("[extract] save failed: %d" % err)
		quit(1)
		return
	print("[extract] wrote %s" % DST)
	quit(0)
