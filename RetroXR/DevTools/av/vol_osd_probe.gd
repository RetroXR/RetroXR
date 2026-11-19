extends Node
## Draws TvOsd's volume bar at 6 of 10 into a 512x366 viewport (the set's OSDViewport size) and saves it.
func _ready() -> void:
	get_tree().create_timer(10.0).timeout.connect(func(): get_tree().quit(1))
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 366)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var bar := TvOsd._VolumeBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.segments = TvOsd.VOL_OSD_SEGMENTS
	bar.filled = 11
	vp.add_child(bar)
	for i in 6:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://vol_osd_probe.png"))
	print("[probe] saved ", img.get_size())
	get_tree().quit(0)
