## Bakes the other mains regions' cords from the game's two US ones.
##
##   godot --headless --path RetroXR --script res://Tools/gen/gen_mains_cords.gd
##
## Each is the US lead with another wall plug on it: the grounded C13 cord for a
## grounded plug, the two-wire C7 cord for a two-pin one. Only the wall end
## changes -- its connector, its mesh, the boxes it collides and is aimed at as
## (read off the mesh), and, for a plug whose cord leaves its bottom edge, the
## CordExit marker the rope starts from (PlugExit). Run gen_power_connectors.gd
## first: it bakes the plugs.
##
## Done to the template's TEXT rather than by packing an instance: a --script run
## has no autoloads, so half the scripts on a lead fail to compile here and a
## packed instance would quietly drop their properties.
extends SceneTree

const GROUNDED := "res://Scenes/Objects/cables/power_cord.tscn"
const TWO_WIRE := "res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn"
const DIR := "res://Scenes/Objects/cables/"
const Specs := preload("res://Tools/gen/mains_specs.gd")


func _init() -> void:
	var regions: Dictionary = (load("res://Scripts/Data/mains_regions.gd") as GDScript) \
		.get_script_constant_map()["CORDS"]
	for token: String in regions:
		var cord: Dictionary = regions[token]
		if not str(cord.get("plug", "")).is_empty():
			_bake(token, cord)
	quit()


func _bake(token: String, cord: Dictionary) -> void:
	var plug_id := str(cord["plug"])
	var grounded := bool(cord.get("grounded", true))
	var text := FileAccess.get_file_as_string(GROUNDED if grounded else TWO_WIRE)
	var mesh := load(DIR + plug_id + ".res") as Mesh

	# The pickup box is the moulding behind the face, the part a hand holds; the
	# pins are in the wall while it is seated.
	var ab := mesh.get_aabb()
	var body := AABB(ab.position, Vector3(ab.size.x, ab.size.y, -ab.position.z))
	var c := body.get_center()
	var at := "Transform3D(1,0,0,0,1,0,0,0,1,%s,%s,%s)" % [_n(c.x), _n(c.y), _n(c.z)]
	var pointer := body.size + Vector3(0.012, 0.012, 0.004)

	var old_plug := "nema_5_15_plug" if grounded else "nema_1_15_plug"
	var old_shape := "Shape_nema"
	text = _once(text, '[node name="%s" type="Node3D"]' % ("PowerCord" if grounded else "Nema115ToC7Cord"),
		'[node name="%s" type="Node3D"]' % str(cord.get("node", token.to_pascal_case())))
	text = _once(text, 'path="res://Scenes/Objects/cables/%s.res" id="3_nema"' % old_plug,
		'path="res://Scenes/Objects/cables/%s.res" id="3_nema"' % plug_id)
	text = _once(text, 'connector = "%s"' % old_plug, 'connector = "%s"' % plug_id)
	text = _replace_block_line(text, '[sub_resource type="BoxShape3D" id="%s"]' % old_shape,
		"size = ", "size = Vector3(%s, %s, %s)" % [_n(body.size.x), _n(body.size.y), _n(body.size.z)])
	text = _replace_block_line(text, '[sub_resource type="BoxShape3D" id="Shape_pointer"]',
		"size = ", "size = Vector3(%s, %s, %s)" % [_n(pointer.x), _n(pointer.y), _n(pointer.z)])
	text = _replace_block_line(text, '[node name="CollisionShape3D" type="CollisionShape3D" parent="WallPlug"]',
		"transform = ", "transform = " + at)
	text = _replace_block_line(text,
		'[node name="CollisionShape3D" type="CollisionShape3D" parent="WallPlug/PointerArea"]',
		"transform = ", "transform = " + at)

	if str(Specs.PLUGS[plug_id].get("cord_exit", "back")) == "bottom":
		# The boot's end, where gen_power_connectors' bottom boot stops: the rope
		# starts from there and not from the middle of the back.
		var depth := float(Specs.PLUGS[plug_id].get("exit_depth", 14.3)) * 0.001
		var marker := '\n[node name="CordExit" type="Marker3D" parent="WallPlug"]\n' \
			+ "transform = Transform3D(1,0,0,0,1,0,0,0,1,%s,%s,%s)\n" % [_n(c.x), _n(ab.position.y), _n(-depth)]
		text = _once(text, '\n[node name="AppliancePlug"', marker + '\n[node name="AppliancePlug"')

	var f := FileAccess.open(DIR + token + ".tscn", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("[gen] %s%s.tscn plug=%s box=%s" % [DIR, token, plug_id, body.size])


func _once(text: String, what: String, with: String) -> String:
	assert(text.count(what) == 1, "expected once: " + what)
	return text.replace(what, with)


## Replace the first line starting `prefix` after the line `header`.
func _replace_block_line(text: String, header: String, prefix: String, with: String) -> String:
	var at := text.find(header)
	assert(at >= 0, "missing: " + header)
	var line := text.find("\n" + prefix, at)
	var end := text.find("\n", line + 1)
	return text.substr(0, line + 1) + with + text.substr(end)


func _n(v: float) -> String:
	return "%.4f" % v
