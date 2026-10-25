## ArcadeServiceModule — the service switches in the cabinet's compartment: TEST and SERVICE.
##
## Every JAMMA cabinet had them, inside the coin door or on a bracket in the cabinet: TEST toggles the game's own
## operator menu (inputs, sound, settings: a Silent Scope cabinet wants it to set the scope up) and SERVICE puts a
## credit in without a coin. Here they stand on the compartment's floor at the side OPPOSITE the power switch
## (`TestButton`, `ServiceButton`, VRButtons that stand up out of the shelf as the power switch does), so a hand or
## a laser reaches them from above once the door is open.
##
## They are there when MAME says the game reads one (`<input service="yes">`, the table's `v`: ArcadeGameProfile.has_service)
## and taken away, out of the pointer's reach, when it does not (`set_enabled`). Pressing one says `pressed(which)`; the
## cabinet model hands it to the machine (RetroSystem.press_core_service), which presses whatever the core calls it.
class_name ArcadeServiceModule
extends ArcadeModule

signal pressed(which: StringName)

var _buttons: Dictionary = {}


func _init() -> void:
	kind = ArcadeProfiles.KIND_SERVICE


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_buttons.clear()
	for which: StringName in [ArcadeServiceKeys.TEST, ArcadeServiceKeys.SERVICE]:
		var button := find_child("TestButton" if which == ArcadeServiceKeys.TEST else "ServiceButton", true, false) as VRButton
		if button == null:
			continue
		_buttons[which] = button
		button.button_pressed.connect(func() -> void: pressed.emit(which))


## The switches are on show and can be pressed, or are gone (a game that reads none).
func set_enabled(on: bool) -> void:
	visible = on
	for which: StringName in _buttons:
		(_buttons[which] as VRButton).set_interactive(on)


func is_enabled() -> bool:
	return visible


## The button for `which` (the tests, the probe).
func button(which: StringName) -> VRButton:
	return _buttons.get(which) as VRButton


## Press one as a hand would (the tests, the probe).
func press(which: StringName) -> void:
	pressed.emit(which)
