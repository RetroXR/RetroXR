## The 3.5 mm plug on the headphones' cord (RetroXR-models generic/headphones-portable, headphones_plug.glb).
##
## An RcaPlug in every way that matters (connector trs_plug, seats in any headphone jack); two additions. Its mesh is
## the model's PlugTip, put on BEFORE RcaPlug reads it for the cord's anchor; its box is what that mesh draws. And it
## carries the headphones' menu: on desktop, with the headset worn, the camera is inside the band and the pointer cannot
## reach the headset, so the plug is where "On your head: Off" is.
class_name HeadphonesPlug
extends RcaPlug

const PLUG_GLB := "res://imported-assets/appliances/headphones/headphones_plug.glb"

var display_name := "Headphones"


func _ready() -> void:
	var tip := get_node_or_null("PlugTip") as MeshInstance3D
	var scene := load(PLUG_GLB) as PackedScene
	if tip != null and scene != null:
		var model := scene.instantiate()
		var src := model.find_child("PlugTip", true, false) as MeshInstance3D
		if src != null:
			tip.mesh = src.mesh
			var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
			if shape:
				var ab := src.mesh.get_aabb()
				var box := BoxShape3D.new()
				box.size = ab.size
				shape.shape = box
				shape.position = ab.get_center()
		model.free()
	else:
		push_warning("[Headphones] %s: the plug model did not load (%s)" % [name, PLUG_GLB])
	super._ready()


func options_choices() -> Array:
	return cable.call("options_choices") if is_instance_valid(cable) and cable.has_method("options_choices") else []


func options_choose(row: int, item: int) -> void:
	if is_instance_valid(cable) and cable.has_method("options_choose"):
		cable.call("options_choose", row, item)
