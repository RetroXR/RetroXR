## bake_panel_slabs — writes res://imported-assets/media/case_panel_slabs.json: every game case's inner panels
## (a jewel case's flip trays, a keep case's flippers), each one's two faces along the case's z read off its mesh.
## A case in play reads the table instead of its mesh (GameCaseModel.PANEL_SLABS says why). Run after a case
## model changes; game_case_tests fails until it is.
##   "$godot" --headless --path RetroXR res://DevTools/cases/bake_panel_slabs.tscn
extends Node

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")


func _ready() -> void:
	var table := {}
	var rows := 0
	for family: String in ["jewel", "keep"]:
		var variants: Array = GameCaseModel.variants_of(family)
		variants.sort()
		for variant: String in variants:
			var c := CASE_SCENE.instantiate() as RetroGameCase
			c.case_family = family
			c.case_variant = variant
			c.freeze = true
			add_child(c)
			var panels := {}
			for panel: Array in c.inner_panels():
				var slab := c._panel_mesh_slab(str(panel[0]), float(panel[1]))
				if slab.x <= slab.y:
					panels[str(panel[0])] = [snappedf(slab.x, 0.000001), snappedf(slab.y, 0.000001), snappedf(float(panel[1]), 0.000001)]
					rows += 1
			if not panels.is_empty():
				table["%s/%s" % [family, variant]] = panels
			c.free()
	var file := FileAccess.open(GameCaseModel.PANEL_SLABS, FileAccess.WRITE)
	file.store_string(JSON.stringify(table, "\t", true) + "\n")
	file.close()
	print("[bake] %d panels of %d cases written to %s" % [rows, table.size(), GameCaseModel.PANEL_SLABS])
	get_tree().quit(0)
