extends Control
## Throwaway: photograph the NET view's refused-join panel with a staged refusal.


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void: get_tree().quit(1))
	var layer := CanvasLayer.new()
	layer.layer = 127
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var view := SpawnMenuNetView.create(null)
	view.position = Vector2(16, 8)
	view.size = Vector2(1000, 900)
	layer.add_child(view)
	# What a host running these would send: a pad on mod.io at its version, a
	# Saturn mod.io has newer, and a crate installed by hand.
	NetworkManager.mod_refusal.assign([
		{"id": "xenu.snespad", "version": "0.4.1", "name": "Super NES Controller", "modio_id": 77},
		{"id": "xenu.saturn", "version": "1.0.0", "name": "Sega Saturn", "modio_id": 88},
		{"id": "me.crate", "version": "0.1.0", "name": "Wooden Crate", "modio_id": 0},
		{"id": "probe.arcadestick", "version": "1.1.0", "name": "Arcade Stick", "modio_id": 99},
	])
	view._mod_versions = {77: "0.4.1", 88: "1.2.0", 99: "1.1.0"}
	view._mod_asked = true
	view._last_join = "code"
	view._refill_mods_box()
	for row: Dictionary in view._mod_plan():
		print("[probe] row %s %s" % [row["kind"], row["id"]])
	for i in 8:
		await get_tree().process_frame
	LoadingOverlay.suspend()
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("user://mods_refused_probe.png")
	img.save_png(out)
	print("[probe] saved %s" % out)
	NetworkManager.mod_refusal.clear()
	get_tree().quit(0)
