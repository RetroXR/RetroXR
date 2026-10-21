## DesktopReticle — centered crosshair overlay for desktop (non-VR) mode.
##
## Draws a small crosshair at the screen centre to indicate where the
## XRToolsDesktopFunctionPointer ray is aimed.  Automatically hides itself
## when the viewport is running in XR mode (headset connected).
extends Control

func _ready() -> void:
	# Anchor to screen centre, 32×32 px hotspot
	anchor_left   = 0.5
	anchor_top    = 0.5
	anchor_right  = 0.5
	anchor_bottom = 0.5
	offset_left   = -16.0
	offset_top    = -16.0
	offset_right  = 16.0
	offset_bottom = 16.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	# Hide when VR is active (use_xr is set true by xr_init.gd)
	visible = not get_viewport().use_xr


func _process(_delta: float) -> void:
	# Also while a held device has the keyboard (F3 / Scroll Lock, "controller mode"): the
	# player is playing it, and the crosshair would sit in front of its screen.
	var want := not get_viewport().use_xr and not ScrollLockCapture.any_active()
	if want != visible:
		visible = want


func _draw() -> void:
	var c  := size * 0.5
	var col := Color(1.0, 1.0, 1.0, 0.85)
	var gap := 4.0
	var arm := 7.0
	var t   := 1.5

	# Four arms with a centre gap
	draw_line(c + Vector2(-arm - gap, 0), c + Vector2(-gap, 0), col, t)
	draw_line(c + Vector2( gap,       0), c + Vector2( arm + gap, 0), col, t)
	draw_line(c + Vector2(0, -arm - gap), c + Vector2(0, -gap),       col, t)
	draw_line(c + Vector2(0,  gap),       c + Vector2(0,  arm + gap), col, t)

	# Centre dot
	draw_circle(c, 1.5, col)
