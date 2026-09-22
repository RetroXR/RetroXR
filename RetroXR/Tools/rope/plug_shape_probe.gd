## Measures each loose plug's connector mesh in its own body's frame, beside the
## collider it has — the numbers the fitted plug boxes were cut from.
##
##   "$godot" --headless --path RetroXR res://Tools/rope/plug_shape_probe.tscn
##
## Lists every plug body whose physics collider is still a SPHERE, with the mesh
## AABB, the sphere, its offset and the cord anchor. A plug resting on a sphere
## two to five times its thickness rolls under any push and sits centimetres off
## the floor; size its box to `mesh_aabb`, centred on the AABB (or, as the Multi
## Out does, on the part a hand grabs). No output means none are left.

extends Node

const SCENES := [
	"res://Scenes/Objects/system_models/wii/wii_av_cable.tscn",
	"res://Scenes/Objects/system_models/nintendo_64/n64_av_cable.tscn",
	"res://Scenes/Objects/system_models/wii/sensor_bar_cable.tscn",
	"res://Scenes/Objects/controllers/wii/nunchuk_cable.tscn",
	"res://Scenes/Objects/cables/speaker_cable.tscn",
	"res://Scenes/Objects/cables/mono_composite_cable.tscn",
	"res://Scenes/Objects/cables/controller_cable.tscn",
	"res://Scenes/Objects/cables/composite_cable.tscn",
	"res://Scenes/Objects/cables/cable.tscn",
	"res://Scenes/Objects/appliances/rf_switch.tscn",
	"res://Scenes/Objects/appliances/antenna.tscn",
]


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void: get_tree().quit(1))
	for path: String in SCENES:
		var root: Node = (load(path) as PackedScene).instantiate()
		add_child(root)
		for body: Node in root.find_children("*", "RigidBody3D", true, false):
			var rb := body as RigidBody3D
			var shape_node: CollisionShape3D = null
			for c: Node in rb.get_children():
				if c is CollisionShape3D:
					shape_node = c
					break
			if shape_node == null or not (shape_node.shape is SphereShape3D):
				continue
			var inv := rb.global_transform.affine_inverse()
			var box := AABB()
			var first := true
			for mi: Node in rb.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null or not m.visible:
					continue
				var local := inv * m.global_transform * m.get_aabb()
				box = local if first else box.merge(local)
				first = false
			var anchor: Variant = rb.get("cable_anchor")
			print("[probe] %s %s mesh_aabb=%s sphere_r=%.4f shape_xf=%s anchor=%s mass=%.3f" % [
				path.get_file(), rb.name, box, (shape_node.shape as SphereShape3D).radius,
				shape_node.transform, anchor, rb.mass])
		root.queue_free()
	get_tree().quit(0)
