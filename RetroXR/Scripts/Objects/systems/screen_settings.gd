## ScreenSettings — a machine screen's look settings, as the player set them: the
## machine menu's screen tab (LCD on a Game Boy, Monitor on an arcade cabinet), the
## way a TV has its CRT tab.
##
## Only the keys `defaults` names are taken. Kept on the MODEL rather than on the
## material, so a screen whose material is rebuilt (a handheld's lit/self-lit pair, a
## cabinet's monitor after a morph) is handed the same values again. Per object,
## saved with the room (ScenePersistence "screen_params"), never sent in netplay.
class_name ScreenSettings
extends RefCounted

var defaults: Dictionary = {}
## key -> value, only what the player set.
var _values: Dictionary = {}
## Who the settings belong to, for the log.
var _owner_name := ""


func _init(p_defaults: Dictionary = {}, owner_name := "") -> void:
	defaults = p_defaults
	_owner_name = owner_name


## Every setting as it stands: the defaults with the player's changes over them.
func values() -> Dictionary:
	var out := defaults.duplicate()
	out.merge(_values, true)
	return out


## Only what differs from the default, for the room's save.
func overrides() -> Dictionary:
	var out := {}
	for key: String in _values:
		if not is_equal_approx(float(_values[key]), float(defaults.get(key, 0.0))):
			out[key] = _values[key]
	return out


## One setting, from the menu. False (and a warning) for a key that is not one.
func set_value(key: String, value: Variant) -> bool:
	if not defaults.has(key):
		push_warning("[Screen] %s: no screen setting %s; ignoring %s" % [_owner_name, key, value])
		return false
	_values[key] = value
	return true


## Several at once (a room restore). An unknown key is dropped and logged: a save
## written while the screen's look had a setting it has since lost.
func set_values(values_in: Dictionary) -> void:
	for key: Variant in values_in:
		if defaults.has(key):
			_values[key] = values_in[key]
		else:
			print("[Screen] %s: saved screen setting %s is not this screen's; dropped" % [_owner_name, key])
	print("[Screen] %s: screen settings restored %s" % [_owner_name, _values])
