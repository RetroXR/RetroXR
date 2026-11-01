## PowerMenuRows — the Power section of a device's own menu (docs/dev/power.md): what
## it runs on, whether that has power right now, and for a device with a cord of its
## own the Show Power Cord switch.
##
## One builder for every panel (a machine's System tab, the TV's, a deck's), so each
## says the same thing in the same words: the supply line is PowerInput.describe(),
## the very words the "No power" card says. Refreshed whenever the supply moves
## (PowerInput.power_changed) and whenever the cord is shown or hidden; a panel calls
## refresh() as it opens, for anything that moved while it was shut.
class_name PowerMenuRows
extends VBoxContainer

var _input: PowerInput = null
var _cord: CaptiveMainsCord = null
var _status: Label = null
var _supply: Label = null
var _cord_switch: VRToggle = null


## The section for `input` in `ui`'s System tab, made the first time and refreshed
## after: the console's own System tab, or one made beside a panel's other tabs (a
## set's, a deck's), or the panel's own rows for a panel with no tabs. The cord is the
## device's own (PowerInput.captive). Returns the section, or null for no input.
static func ensure_in(ui: Control, input: PowerInput) -> PowerMenuRows:
	if ui == null or input == null or not is_instance_valid(input):
		return null
	var existing := ui.find_child("PowerRows", true, false) as PowerMenuRows
	if existing != null:
		if existing._input == input:
			existing.refresh()
			return existing
		existing.get_parent().remove_child(existing)
		existing.queue_free()
	var cord: CaptiveMainsCord = input.captive as CaptiveMainsCord
	return build(_system_rows_of(ui), input, cord)


## Where the section goes in `ui`: its System tab's rows, made if the panel has none.
static func _system_rows_of(ui: Control) -> Container:
	var all_tabs := ui.find_children("*", "TabContainer", true, false)
	if all_tabs.is_empty():
		var scroll: ScrollContainer = null
		for node in ui.find_children("*", "ScrollContainer", true, false):
			scroll = node as ScrollContainer
			break
		if scroll != null and scroll.get_child_count() > 0 and scroll.get_child(0) is Container:
			return scroll.get_child(0) as Container
		for node in ui.find_children("*", "VBoxContainer", true, false):
			return node as Container
		return ui as Container
	var tabs := all_tabs[0] as TabContainer
	var sys := tabs.get_node_or_null("System") as Control
	if sys == null:
		sys = VBoxContainer.new()
		sys.name = "System"
		tabs.add_child(sys)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		MenuStyle.fat_vscroll_bar(scroll)
		sys.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 4)
		scroll.add_child(rows)
		return rows
	for node in sys.find_children("*", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll.get_child_count() > 0 and scroll.get_child(0) is Container:
			return scroll.get_child(0) as Container
	return sys as Container


## The section for `input`, added to `parent`. `cord` is the device's own cord, for
## its Show Power Cord switch; null for a device with none (a console's lead is a
## thing of its own, so it has no switch here).
static func build(parent: Container, input: PowerInput, cord: CaptiveMainsCord = null) -> PowerMenuRows:
	var rows := PowerMenuRows.new()
	rows.name = "PowerRows"
	rows.add_theme_constant_override("separation", 4)
	rows._input = input
	rows._cord = cord
	parent.add_child(rows)
	rows._build()
	return rows


func _build() -> void:
	add_child(MenuStyle.header("Power"))
	_status = MenuStyle.label("", 20, MenuStyle.COLOR_TITLE)
	_status.name = "PowerStatus"
	add_child(_status)
	_supply = MenuStyle.label("", 17, MenuStyle.COLOR_DESC)
	_supply.name = "PowerSupply"
	_supply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_supply)
	if _cord != null:
		_cord_switch = MenuStyle.switch_row(self, "Show Power Cord", not _cord.hidden, 18, 56,
			"Off: the cord is put away and the device counts as plugged in out of sight.")
		_cord_switch.name = "ShowPowerCord"
		_cord_switch.toggled.connect(_on_cord_toggled)
		_cord.hidden_changed.connect(func(_on: bool) -> void: refresh())
	if _input != null:
		_input.power_changed.connect(func(_live: bool) -> void: refresh())
	refresh()


## Read the supply again and redraw the lines (and the switch, if a save or a peer
## moved the cord).
func refresh() -> void:
	if _status == null:
		return
	if _input == null or not is_instance_valid(_input):
		_status.text = "Power: always on"
		_supply.text = ""
		return
	var answer := _input.evaluate()
	var live := bool(answer["live"])
	_status.text = "Power: %s" % ("has power" if live else "NO POWER")
	_status.add_theme_color_override("font_color",
		MenuStyle.COLOR_RECOMMENDED if live else Color(0.95, 0.55, 0.45))
	_supply.text = "Supply: %s" % str(answer["supply"])
	if _cord_switch != null and is_instance_valid(_cord) \
			and _cord_switch.button_pressed == _cord.hidden:
		# Moved by a save or a peer: the knob follows, and nothing is sent back.
		_cord_switch.set_pressed_no_signal(not _cord.hidden)
		_cord_switch._refresh(not _cord.hidden)


func _on_cord_toggled(on: bool) -> void:
	if not is_instance_valid(_cord):
		return
	# Through the device, so the change is told to the other players as well.
	var host := _cord.host
	if is_instance_valid(host) and host.has_method("set_mains_cord_hidden"):
		host.call("set_mains_cord_hidden", not on)
	else:
		_cord.set_hidden(not on)
	refresh()
