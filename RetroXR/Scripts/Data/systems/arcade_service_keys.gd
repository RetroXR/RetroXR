## ArcadeServiceKeys — which input a cabinet's TEST and SERVICE buttons press in the running core.
##
## MAME reads a game's service switch as `IPT_SERVICE` ("Service Mode", a toggle that opens the operator menu:
## F2) and the service credit as `IPT_SERVICE1` ("Service 1": 9). Those are keyboard keys in the core, and are what a
## button falls back to. A core that NAMES the input (Libretro.GetInputDescriptors: {port, device, index, id,
## description}) is believed over the fallback: FinalBurn Neo says "Service" / "Diagnostic" in its own words, on a pad id
## or a key, and it does not use F2 (measured on dino: F2 does nothing visible). So `lookup` finds the descriptor whose
## words say test or service, and the system presses what that is; no match, the MAME keys.
##
## NEVER RUN AGAINST A CORE here (no core and no ROM in the sandbox): the lookup and the keys are tested, what a real
## game does with them is OWED (docs/dev/arcade.md "Service switches").
class_name ArcadeServiceKeys
extends RefCounted

const TEST := &"test"
const SERVICE := &"service"
## The operator's selector beside them (a JVS I/O board's "Up Select", "Down Select" and "Enter", and what the first player's stick and
## button 1 are in a game that has no such board): the test menus of most games are worked with those, and a cabinet with a wheel, a
## gun or a stage has neither a stick nor a button 1 to work one with. A tap each, on player 1's port.
const UP := &"up"
const DOWN := &"down"
const LEFT := &"left"
const RIGHT := &"right"
const ENTER := &"enter"
const SELECTOR: Array[StringName] = [UP, DOWN, LEFT, RIGHT, ENTER]

## libretro.h's keys and devices.
const RETROK_9 := 57
const RETROK_F2 := 283
const DEVICE_JOYPAD := 1
const DEVICE_KEYBOARD := 3

## The words that mark the test / service-mode input, and the service-credit one (which is not the test's).
const TEST_WORDS := "(?i)\\b(test|diag\\w*|service mode)\\b"
const SERVICE_WORDS := "(?i)\\bservice\\b"


## Is `which` one of the selector's five?
static func is_selector(which: StringName) -> bool:
	return SELECTOR.has(which)


## The pad id the selector's `which` is held on: the directions are the pad's, ENTER is button 1 (the pad's B, ArcadeProfiles.button_bit(1)).
static func selector_bit(which: StringName) -> int:
	match which:
		UP:
			return ControllerBindings.JOYPAD_UP
		DOWN:
			return ControllerBindings.JOYPAD_DOWN
		LEFT:
			return ControllerBindings.JOYPAD_LEFT
		RIGHT:
			return ControllerBindings.JOYPAD_RIGHT
		ENTER:
			return ArcadeProfiles.button_bit(1)
	return -1


## The key a button falls back to when the core names nothing: MAME's.
static func default_key(which: StringName) -> int:
	return RETROK_F2 if which == TEST else RETROK_9


## What the core calls the input behind `which`: {"device": DEVICE_JOYPAD or DEVICE_KEYBOARD, "id": the pad id or
## the RETROK_ code, "port": its port, "description": its words}, or {} when it names none. Player 1's port is
## believed first. Only joypad and keyboard descriptors count (a light gun's or a mouse's ids are other things).
static func lookup(descriptors: Array, which: StringName) -> Dictionary:
	var test := RegEx.create_from_string(TEST_WORDS)
	var service := RegEx.create_from_string(SERVICE_WORDS)
	var best := {}
	for d: Variant in descriptors:
		var row := d as Dictionary
		if row == null:
			continue
		var device := int(row.get("device", -1))
		if device != DEVICE_JOYPAD and device != DEVICE_KEYBOARD:
			continue
		var words := str(row.get("description", ""))
		var is_test := test.search(words) != null
		var is_service := service.search(words) != null
		var wanted := is_test if which == TEST else (is_service and not is_test)
		if not wanted:
			continue
		var found := {"device": device, "id": int(row.get("id", -1)), "port": int(row.get("port", 0)), "description": words}
		if best.is_empty() or int(found["port"]) < int(best["port"]):
			best = found
	return best
