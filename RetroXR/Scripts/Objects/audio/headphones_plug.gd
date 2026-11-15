## The 3.5 mm plug on the headphones' cord: the black edition of RetroXR-models generic/trs-plug
## (imported-assets/connectors/trs_plug/trs_plug_black.glb; it was generic/headphones-portable's own headphones_plug.glb
## until 2026-11-15).
##
## An RcaPlug in every way that matters (connector trs_plug, seats in any headphone jack); two additions. Its mesh is
## the model's Plug, put on the PlugTip BEFORE RcaPlug reads it for the cord's anchor, with the model's CordExit as a
## marker beside it, which RcaPlug takes first; its box is what that mesh draws. And it
## carries the headphones' menu: on desktop, with the headset worn, the camera is inside the band and the pointer cannot
## reach the headset, so the plug is where "On your head: Off" is.
class_name HeadphonesPlug
extends RcaPlug

const PLUG_GLB := "res://imported-assets/connectors/trs_plug/trs_plug_black.glb"

var display_name := "Headphones"


func _ready() -> void:
	var tip := get_node_or_null("PlugTip") as MeshInstance3D
	var scene := load(PLUG_GLB) as PackedScene
	if tip != null and scene != null:
		var model := scene.instantiate()
		var src := model.find_child("Plug", true, false) as MeshInstance3D
		var exit := model.find_child(PlugExit.MARKER, true, false) as Node3D
		if exit != null and get_node_or_null(PlugExit.MARKER) == null:
			var marker := Marker3D.new()
			marker.name = PlugExit.MARKER
			marker.transform = exit.transform
			add_child(marker)
		if src == null:
			push_warning("[Headphones] %s: %s has no Plug mesh" % [name, PLUG_GLB])
		else:
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
