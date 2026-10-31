## ArcadePrompts — what a cabinet tells a player who takes its controls in hand.
##
## A panel's controls were silent: take the bicycle's bars and nothing said that a squeeze takes them, how to turn them or that the crank is a pedal; a stick, a wheel or a dial the same; and which
## buttons a GAME has (not every game uses every button) was found by trying. The rows here are the panel's own hint (HeldHint, a child of the ArcadeControlModule): a control taken in a headset says what it
## is for, the panel says which buttons the GAME has (the caps it shows, in the words the core gave them), and attaching to a panel says how its player is played, from the controller or the keyboard.
##
## Rows are [id, platform, glyphs, caption], HeldHint's. There are two kinds. A VERB row (`ap_stick_vr`, `ap_attach_vr`...) says something that is the same on every cabinet, and HeldHint stops showing it after
## LEARNED_AFTER uses (`note_used`): nobody is told the same thing for ever. A GAME row (`is_game_row`: the buttons, the pedals) says what THIS game has, which nobody can have learned from another game, so it is
## never counted. The words are plain English and short: nothing here has been read in a headset, and the glyph art is the headset's own (Textures/InputPrompts).
class_name ArcadePrompts
extends RefCounted

## What taking a control is, a row at a time: [the row's id suffix, the button that takes it (`trigger`, `grip`, or "" for no glyph), the sentence]. A bicycle's bars are turned by a hand on each grip
## and tipped by the lift of the grips; a motorbike's, a board's rail, only leaned.
const CONTROLS := {
	&"stick": [["", "trigger", "Take the stick, then lean it"]],
	&"wheel": [["", "trigger", "Take hold of the wheel, then turn it"]],
	&"dial": [["", "trigger", "Take the dial, then turn it"]],
	&"ball": [["", "trigger", "Take the ball, then roll it"]],
	&"lever": [["", "trigger", "Take the lever, then throw it forward or back"]],
	&"bars": [["", "grip", "Take a grip, then turn the bars"], ["_two", "", "A hand on each grip: one forward, one back"], ["_tip", "", "Lift or push the grips to tip the bike"]],
	&"lean": [["", "grip", "Take a grip, then push the bars sideways to lean"]],
	&"crank": [["", "trigger", "Take a pedal, then turn it forward to pedal"]],
	&"slide": [["", "trigger", "Take the lever, then slide it along its slot"]],
	&"throttle": [["", "trigger", "Take the throttle, then push or pull it"], ["_stay", "", "It stays where you leave it"]],
}

## Ids that begin like this say what THIS game has (its buttons, its pedals), and are never counted as learned.
const GAME_ROW_PREFIXES: Array[String] = ["ap_buttons", "ap_pedals"]

## More buttons than this are named in a caption by their number alone, and a row of controller or key names holds this many.
const NAMED_MAX := 4
const PER_ROW := 3


## Does this row say what THIS game has, rather than something to learn?
static func is_game_row(id: StringName) -> bool:
	var text := String(id)
	for prefix in GAME_ROW_PREFIXES:
		if text.begins_with(prefix):
			return true
	return false


## The VR rows a control of `kind` teaches the hand that takes it: the glyph of the button that takes it (THAT hand's trigger or squeeze) on the first row and what to do. [] for a kind that is not a control.
static func control_rows(kind: StringName) -> Array:
	var rows: Array = []
	if not CONTROLS.has(kind):
		return rows
	for part: Array in CONTROLS[kind]:
		var glyphs: Array = []
		if str(part[1]) != "":
			glyphs.append("quest_%s_{side}_outline" % str(part[1]))
		rows.append([StringName("ap_%s%s_vr" % [kind, part[0]]), HeldHint.PLATFORM_VR, glyphs, str(part[2])])
	return rows


## The row for the buttons a panel shows: a fingertip presses a cap. `buttons` are `{n: MAME's button 1 to 10, label: the core's word for it or ""}`; none gives no row.
static func button_rows(buttons: Array) -> Array:
	if buttons.is_empty():
		return []
	return [[&"ap_buttons_vr", HeldHint.PLATFORM_VR, [], "Press the buttons with a fingertip: %s" % _named(buttons)]]


## The row for pedals under a finger (a racer's gas and brake).
static func pedal_rows() -> Array:
	return [[&"ap_pedals_vr", HeldHint.PLATFORM_VR, [], "Press the gas and brake pedals with a fingertip"]]


## One line of rows' own words, for telling whether the same game is being described again.
static func signature(rows: Array) -> String:
	var parts: Array[String] = []
	for row: Array in rows:
		parts.append("%s=%s" % [row[0], row[3]])
	return "|".join(parts)


## What attaching to a panel with a headset's controller says: it plays this player, which of its sticks moves and which buttons are start and the coin (`button_map` and `stick_map` are the
## player's own for this machine, ControllerBindings), then which of its buttons is each of the game's.
static func attach_rows_vr(player: int, has_stick: bool, buttons: Array, button_map: Dictionary, stick_map: Dictionary) -> Array:
	var parts: Array[String] = []
	var stick := _moving_stick(stick_map)
	if has_stick and stick != "":
		parts.append("%s moves" % stick)
	var start := _sources(ControllerBindings.JOYPAD_START, button_map)
	var coin := _sources(ControllerBindings.JOYPAD_SELECT, button_map)
	if start != "":
		parts.append("%s: start" % start)
	if coin != "":
		parts.append("%s: coin" % coin)
	var rows: Array = [[&"ap_attach_vr", HeldHint.PLATFORM_VR, [], "This controller plays player %d%s" % [player + 1, " (" + "; ".join(parts) + ")" if not parts.is_empty() else ""]]]
	var items: Array[String] = []
	for button: Dictionary in buttons:
		var source := _sources(ArcadeProfiles.button_bit(int(button["n"])), button_map)
		if source != "":
			items.append("%s: %s" % [_item(button), source])
	rows.append_array(_item_rows(&"ap_buttons_map", HeldHint.PLATFORM_VR, items))
	return rows


## What attaching with the keyboard says: the keys of the cabinet's own map as the player has them (DesktopBindings, in the scope of `systemid`, which is not put in the InputMap to say so).
static func attach_rows_desktop(player: int, has_stick: bool, buttons: Array, systemid: String) -> Array:
	var rows: Array = []
	if has_stick:
		rows.append([&"ap_move_pc", HeldHint.PLATFORM_DESKTOP, [], "%s %s %s %s: move" % [_key("RETRO_JOYPAD_UP", systemid), _key("RETRO_JOYPAD_LEFT", systemid), _key("RETRO_JOYPAD_DOWN", systemid), _key("RETRO_JOYPAD_RIGHT", systemid)]])
	var items: Array[String] = []
	for button: Dictionary in buttons:
		items.append("%s: %s" % [_key(_action_of(int(button["n"])), systemid), _item(button)])
	rows.append_array(_item_rows(&"ap_buttons_pc", HeldHint.PLATFORM_DESKTOP, items))
	rows.append([&"ap_start_pc", HeldHint.PLATFORM_DESKTOP, [], "%s: start, %s: coin (player %d)" % [_key("RETRO_JOYPAD_START", systemid), _key("RETRO_JOYPAD_SELECT", systemid), player + 1]])
	return rows


## The buttons by their words ("1 Punch, 2 Kick") when the core named them, else by number ("buttons 1 to 6").
static func _named(buttons: Array) -> String:
	var words: Array[String] = []
	var named := 0
	for button: Dictionary in buttons:
		if str(button.get("label", "")).strip_edges() != "":
			named += 1
		words.append(_item(button))
	if named == 0 or buttons.size() > NAMED_MAX:
		var first := int((buttons[0] as Dictionary)["n"])
		var last := int((buttons[buttons.size() - 1] as Dictionary)["n"])
		return "button %d" % first if first == last else "buttons %d to %d" % [first, last]
	return ", ".join(words)


## A button as a prompt names it: its number, and the word the core gave it.
static func _item(button: Dictionary) -> String:
	var label := str(button.get("label", "")).replace("\n", " ").strip_edges()
	return "%d %s" % [int(button["n"]), label] if label != "" else str(int(button["n"]))


## `items` laid out PER_ROW to a row, the first row's id `id` and the next ones' numbered.
static func _item_rows(id: StringName, platform: int, items: Array[String]) -> Array:
	var rows: Array = []
	for at in range(0, items.size(), PER_ROW):
		var row_id := id if rows.is_empty() else StringName("%s%d" % [id, rows.size() + 1])
		rows.append([row_id, platform, [], ", ".join(items.slice(at, at + PER_ROW))])
	return rows


## The controller inputs the player gave a joypad button, as the Controls page names them ("Right A"); "" for none.
static func _sources(bit: int, button_map: Dictionary) -> String:
	var names: Array[String] = []
	var sources: Array = button_map.keys()
	sources.sort()
	for source: String in sources:
		if int(button_map[source]) == bit:
			names.append(str(ControllerBindings.BUTTON_SOURCE_LABELS.get(source, source)))
	return " or ".join(names)


## The thumbstick that moves a panel's stick: the one the player's stick map points at the left stick or the D-pad.
static func _moving_stick(stick_map: Dictionary) -> String:
	var found: Array[String] = []
	for side: String in ["left", "right"]:
		var target := str(stick_map.get("stick_" + side, ""))
		if "left" in target or "dpad" in target:
			found.append("%s stick" % side.capitalize())
	return " or ".join(found)


static func _key(action: String, systemid: String) -> String:
	return DesktopBindings.display_name_for_system(action, systemid)


## The action of the key map that plays MAME's button `n` (1 to 10): the one that sets the pad bit the panel's cap n sets.
static func _action_of(n: int) -> String:
	var bit := ArcadeProfiles.button_bit(n)
	for action: String in ArcadeInput.DESKTOP_BUTTON_MAP:
		if int(ArcadeInput.DESKTOP_BUTTON_MAP[action]) == bit:
			return action
	return ""
