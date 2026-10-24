## Photographs the cabinet menu's DIP Switch tab in both of its forms. WINDOWED, never --headless.
##
##   "$godot" --path RetroXR res://Tools/models/dip_tab_probe.tscn --resolution 640x520 --position 20,20 \
##       -- --out=/some/dir
##
## `menu.png`: a core with a DIP screen of its own (MAME), the button; `options.png`: a core whose DIPs are
## options (FBNeo), the rows. The definitions are stand-ins with the two values the row steps through.
extends Control


class _Val:
	var _v: String
	func _init(v: String) -> void:
		_v = v
	func GetValue() -> String:
		return _v
	func GetLabel() -> String:
		return _v


class _Def:
	var _desc: String
	var _vals: Array
	func _init(desc: String, vals: Array) -> void:
		_desc = desc
		_vals = vals
	func GetValues() -> Array:
		return _vals.map(func(v: String) -> Object: return _Val.new(v))
	func GetDescriptionCategorized() -> String:
		return _desc
	func GetDescription() -> String:
		return _desc


func _ready() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
	var ui := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	ui.size = Vector2(640, 520)
	add_child(ui)
	await get_tree().process_frame
	ui.populate({}, {}, [], {}, "", "mame")
	ui.populate_dip(true, true, true, false)
	ui._tabs.current_tab = ui._dip_tab_idx
	await _save(out + "/menu.png")
	ui.populate({
		"fbneo-dipswitch-dino-Coinage": _Def.new("Coinage", ["1 Coin/1 Credit", "2 Coins/1 Credit"]),
		"fbneo-dipswitch-dino-Lives": _Def.new("Lives", ["2", "3", "4"]),
		"fbneo-dipswitch-dino-Difficulty": _Def.new("Difficulty", ["Normal", "Hard"]),
		"fbneo-vertical-mode": _Def.new("Vertical mode", ["Off", "On"]),
	}, {"fbneo-dipswitch-dino-Lives": "3"}, [], {}, "", "fbneo")
	ui.populate_dip(true, false, true, false)
	await _save(out + "/options.png")
	get_tree().quit(0)


func _save(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))
