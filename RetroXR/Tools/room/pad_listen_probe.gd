## What a real pad does here: listens for a while and prints, per second, every joypad axis and
## button that moved, the walk actions' strengths, and any mouse or key events (with their device).
##   "$godot" --headless --path RetroXR res://Tools/room/pad_listen_probe.tscn -- --secs=25
extends Node

var _secs := 25.0
var _axes: Dictionary = {}
var _buttons: Dictionary = {}
var _mouse := 0
var _keys: Dictionary = {}
var _walk := 0.0
var _t := 0.0
var _devs := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.trim_prefix("--secs="))
	await get_tree().create_timer(1.0).timeout
	var pad: DesktopPadService = DesktopPad
	print("[listen] pads %s, main_device %d" % [Input.get_connected_joypads(), pad.main_device])
	for d in Input.get_connected_joypads():
		print("[listen]   %d '%s' guid %s" % [d, Input.get_joy_name(d), Input.get_joy_guid(d)])
	for action in ["desktop_move_forward", "desktop_move_left", "action_crouch"]:
		var evs: Array = []
		for e in InputMap.action_get_events(action):
			evs.append("%s dev=%d" % [e.get_class(), e.device])
		print("[listen] %s: %s" % [action, evs])


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var key := "dev%d axis%d" % [m.device, m.axis]
		_axes[key] = maxf(absf(m.axis_value), float(_axes.get(key, 0.0)))
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if b.pressed:
			_buttons["dev%d btn%d" % [b.device, b.button_index]] = true
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device != DesktopPadService.SYNTH_DEVICE:
			_mouse += 1
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_keys[OS.get_keycode_string((event as InputEventKey).keycode) + " dev%d" % event.device] = true


func _process(delta: float) -> void:
	_t += delta
	_walk = maxf(_walk, Input.get_vector("desktop_move_left", "desktop_move_right",
		"desktop_move_backward", "desktop_move_forward").length())
	if _t >= 1.0:
		_t = 0.0
		_secs -= 1.0
		if not _axes.is_empty() or not _buttons.is_empty() or _mouse > 0 or not _keys.is_empty() or _walk > 0.0:
			print("[listen] axes %s buttons %s | os mouse events %d keys %s | walk action max %.2f" % [
				_axes, _buttons.keys(), _mouse, _keys.keys(), _walk])
		_axes.clear()
		_buttons.clear()
		_mouse = 0
		_keys.clear()
		_walk = 0.0
		if _secs <= 0.0:
			get_tree().quit(0)
