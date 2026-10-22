## CoreOptionsPanel — floating 3D panel that displays libretro core options for a RetroSystem.
##
## Parented to a RetroSystem node but uses top_level=true so it inherits no transform.
## Each frame it repositions itself above the owning system and faces the camera.
## Opened/closed via show_for()/hide_panel(); also has an in-UI ✕ close button.
class_name CoreOptionsPanel
extends FloatingObjectPanel3D

## Gap between the top of the hardware and the BOTTOM edge of the panel.
##
## This replaced a fixed 0.42 m from the system's origin to the panel's centre.
## That figure was tuned against a flat console, where it clears the machine
## easily; the PC tower is 0.42 m tall, so the panel's centre landed exactly on
## its crown and the lower half of the page was drawn inside the case.
const CLEARANCE := 0.12

## Built on first open, not with the panel. A SubViewport and the whole control
## tree inside it is the most expensive part of a system, and a room pays it once
## per system while it is being built — main-thread time spent on a UI nobody has
## asked for yet, at the one moment the headset has nothing new to draw.
const UI_SCENE := preload("res://Scenes/UI/core_options_2d.tscn")

var _system: RetroSystem = null
## The slotted cartridge's panel while it is driving our Cartridge tab.
var _cart_panel: CartridgeOptionsPanel = null
## The attached unit's panel while it is driving our Saves tab.
var _saves_panel: MemoryCardPanel = null
## Which of the machine's memories the Saves tab is showing.
var _saves_index := 0
## The handheld volume the System tab's slider last showed (-1: none).
var _shown_volume := -1.0
## How often the Controls tab re-reads the machine while the menu is open.
const CONTROLS_POLL_S := 0.25
var _controls_poll := 0.0
## RetroSystem.controls_state() as the Controls tab last showed it.
var _controls_state: Dictionary = {}
## How often the Debug tab re-reads the core, while it is the tab showing.
const DEBUG_POLL_S := 1.0
var _debug_poll := 0.0
## The core's frame count at the last Debug read, -1 when there was none.
var _debug_frames := -1

@onready var _viewport_node: XRToolsViewport2DIn3D = $CoreOptionsViewport


## Centred over the machine, its bottom edge CLEARANCE above the hardware's top.
## Half the panel is added because global_position is its centre — placing the
## centre at the clearance height is what put the lower half inside the tower.
func _anchor() -> Vector3:
	# A tall machine (an arcade cabinet) hangs its panel beside itself, where it can be read.
	var beside: Variant = _system.options_panel_anchor(_viewport_node.screen_size)
	if beside != null:
		return beside as Vector3
	var origin := _system.global_position
	var half_height := _viewport_node.screen_size.y * 0.5
	return Vector3(origin.x,
		_system.body_top_y() + CLEARANCE + half_height,
		origin.z)


# ── Public API ─────────────────────────────────────────────────────────────────

## Show the panel for the given system, looking toward the given camera.
func show_for(system: RetroSystem, camera: Node3D) -> void:
	_system = system
	_camera = camera
	# Pre-position before making visible to avoid a one-frame flash at the wrong spot
	if _system:
		global_position = _anchor()
	visible = true
	print("[CoreOptionsPanel] showing for system '%s'" % system.name)
	if _viewport_node.scene == null:
		_viewport_node.scene = UI_SCENE
	_ensure_ui_connected()
	_populate()


## Called by the system when fresh options data arrives and the panel is already open.
func refresh() -> void:
	print("[CoreOptionsPanel] refreshing options display")
	_populate()


# ── Internal helpers ───────────────────────────────────────────────────────────

## Wire signals from the 2D UI scene exactly once.
## The SubViewport may not have finished loading on the first call, so we defer
## and retry if the child scene isn't ready yet.
func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		# SubViewport hasn't instantiated its scene yet — retry next frame
		call_deferred("_ensure_ui_connected")
		return
	var ui := vp.get_child(0) as CoreOptions2D
	if not ui:
		push_warning("[CoreOptionsPanel] SubViewport child is not CoreOptions2D")
		return
	ui.option_changed.connect(_on_option_changed)
	ui.options_reset_requested.connect(_on_options_reset_requested)
	ui.port_device_changed.connect(_on_port_device_changed)
	ui.pad_device_changed.connect(_on_pad_device_changed)
	ui.video_out_toggled.connect(_on_video_out_toggled)
	ui.ignore_gravity_toggled.connect(_on_ignore_gravity_toggled)
	ui.screen_glow_toggled.connect(_on_screen_glow_toggled)
	ui.cabinet_art_toggled.connect(_on_cabinet_art_toggled)
	ui.attract_override_changed.connect(_on_attract_override_changed)
	ui.dip_menu_requested.connect(_on_dip_menu_requested)
	ui.volume_changed.connect(_on_volume_changed)
	ui.core_selected.connect(_on_core_selected)
	ui.close_requested.connect(hide_panel)
	ui.saves_source_picked.connect(_on_saves_source_picked)
	ui.control_requested.connect(_on_control_requested)
	_ui_connected = true
	print("[CoreOptionsPanel] 2D UI signals connected")


## Push the system's cached option data into the 2D UI.
## Defers if the SubViewport scene isn't ready yet.
func _populate() -> void:
	if not _system:
		return
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		call_deferred("_populate")
		return
	var ui := vp.get_child(0) as CoreOptions2D
	if not ui:
		return
	var snap := _system.core_options_snapshot()
	ui.populate(snap["definitions"], snap["values"], snap["controller_info"],
		_system.forced_core_options(), str(snap["unavailable"]), str(snap["core"]))
	_shown_volume = _device_volume()
	ui.populate_system(_system.video_out_enabled, _system.supports_video_out_toggle(),
		_system.ignore_gravity, _system.pad_guid, _system.pad_ordinal, _shown_volume,
		_system.supports_cabinet_art_toggle(), _system.cabinet_art_enabled,
		_system.attract_override if _system.supports_cabinet_art_toggle() else -1)
	ui.populate_screen_glow(_system.get_screen_glow())
	_controls_state = _system.controls_state()
	ui.populate_controls(_controls_state)
	ui.populate_debug(_system.debug_state())
	_populate_dip_tab(ui)
	ui.populate_cores(_system.core_choices(), _system.core_name, _system.default_core_name())
	# Re-evaluated on every open so a file dropped into the system dir by hand
	# shows up next time; the digest is cached by size and mtime.
	var core := str(snap["core"])
	ui.populate_firmware(core,
		FirmwareState.shared().evaluate(core, FirmwareRequirements.for_core(core)))
	_populate_cartridge_tab(ui)
	_populate_saves_tab(ui)


## Hand the Saves tab to the memory this machine keeps -- a Saturn's own, a Sega
## CD's -- so its saves are managed on the machine they belong to, by the memory
## card panel's own code. Hidden when it keeps none.
func _populate_saves_tab(ui: CoreOptions2D) -> void:
	var units := _memory_units()
	ui.set_saves_tab_visible(not units.is_empty())
	_saves_index = clampi(_saves_index, 0, maxi(units.size() - 1, 0))
	var labels := PackedStringArray()
	for unit: Node3D in units:
		labels.append(CardFormats.for_family(str(unit.get("family"))).device_noun())
	ui.set_saves_sources(labels, _saves_index)
	var shown: Node3D = units[_saves_index] if not units.is_empty() else null
	var panel: MemoryCardPanel = shown.call("ensure_saves_panel") if shown != null else null
	if is_instance_valid(_saves_panel) and _saves_panel != panel:
		_saves_panel.release_external_ui()
	_saves_panel = panel
	if panel != null:
		panel.adopt_external_ui(ui.saves_ui(), shown)


func _on_saves_source_picked(index: int) -> void:
	_saves_index = index
	_populate()


## Every memory the machine keeps: what is built into it first (a Saturn's), then
## a unit's that has a drive of its own (a Sega CD's), then any unit that is only
## memory, so the switch reads the same way whichever was attached first.
func _memory_units() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _system == null:
		return out
	if _system.console_memory() != null:
		out.append(_system.console_memory())
	var units: Array[RetroExpansion] = []
	for unit: RetroExpansion in _system.get_expansions():
		if is_instance_valid(unit) and not unit.family.is_empty():
			units.append(unit)
	units.sort_custom(func(a: RetroExpansion, b: RetroExpansion) -> bool:
		return not ExpansionCatalog.media_of(a.expansion_id).is_empty() \
			and ExpansionCatalog.media_of(b.expansion_id).is_empty())
	for unit: RetroExpansion in units:
		out.append(unit)
	return out


## Hand the Cartridge tab to the slotted cartridge's own options panel, which
## owns the save recovery, RomM sync and achievement lookup. Nothing is
## reimplemented here — this only decides whether the tab exists and who drives it.
func _populate_cartridge_tab(ui: CoreOptions2D) -> void:
	# game_media, not get_snapped_cartridge: on an assembled machine the game is
	# often in the EXPANSION's bay and the console's own slot is empty, and this
	# tab was hidden for every one of those -- a 64DD disk, a Mega-CD disc, a 32X
	# cartridge -- so their saves and achievements could not be reached at all.
	var cart := _system.game_media()
	ui.set_cartridge_tab_visible(cart != null)
	if cart == null:
		_cart_panel = null
		return
	# Same panel the cartridge shows on its own, so a save selected here and one
	# selected there are the same act on the same state.
	if not cart.has_method("ensure_options_panel"):
		ui.set_cartridge_tab_visible(false)
		return
	_cart_panel = cart.ensure_options_panel()
	if _cart_panel == null:
		ui.set_cartridge_tab_visible(false)
		return
	_cart_panel.adopt_external_ui(ui.cartridge_ui(), cart)


## Relay the user's option change from the 2D UI back to the system.
func _on_option_changed(key: String, value: String) -> void:
	if _system and is_instance_valid(_system):
		print("[CoreOptionsPanel] option changed: '%s' = '%s'" % [key, value])
		_system.set_core_option(key, value)


## Reset every non-forced option, then redraw so the new values show.
func _on_options_reset_requested() -> void:
	if _system and is_instance_valid(_system):
		print("[CoreOptionsPanel] resetting core options to defaults")
		_system.reset_core_options()
		_populate()


## System-tab toggle: show/hide the console's video-out cables.
func _on_video_out_toggled(enabled: bool) -> void:
	if _system and is_instance_valid(_system):
		_system.set_video_out_enabled(enabled)


## System-tab slider: the handheld's volume, set through its own control so the
## wheel turns with it and the system hears it as from a hand.
func _on_volume_changed(v: float) -> void:
	var model := _system.get_model() if _system and is_instance_valid(_system) else null
	if model != null and model.has_method("set_volume"):
		model.call(&"set_volume", v)
		_shown_volume = v


## The level the device's own volume control is at, or -1 for one without.
func _device_volume() -> float:
	var model := _system.get_model() if _system and is_instance_valid(_system) else null
	return float(model.call(&"get_volume")) if model != null and model.has_method("get_volume") else -1.0


## A Controls-tab row, through the call the machine's own button or slide makes, so
## the shell moves, the sound plays and netplay hears it as it would from a hand.
func _on_control_requested(id: String, value: Variant) -> void:
	if not is_instance_valid(_system):
		return
	print("[CoreOptionsPanel] %s: control %s%s" % [_system.name, id,
		"" if value == null else " = %s" % str(value)])
	match id:
		"power": _system.set_power(bool(value))
		"reset": _system.reset()
		"eject": _system.press_eject()
		"rf": _system.set_rf_channel(int(value))
		_:
			push_warning("[CoreOptionsPanel] unknown control %s" % id)
	_refresh_controls()


## The Debug tab, read only while it is the tab showing. The measured rate is the
## core's frame counter over the time since the last read, which is what tells a
## core running slow from one that only declares an odd rate.
func _refresh_debug(elapsed: float) -> void:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	var ui := vp.get_child(0) as CoreOptions2D if vp and vp.get_child_count() > 0 else null
	if ui == null or not ui.is_debug_tab_shown():
		_debug_frames = -1
		return
	var sections := _system.debug_state()
	for s: Array in sections:
		if s[0] != "Video":
			continue
		var frames := -1
		for row: Array in s[1]:
			if row[0] == "Frames run":
				frames = int(row[1])
		# Always there, "—" until there are two readings to measure between: a row
		# that APPEARED on the second refresh changed the page's shape, and DebugRows
		# rebuilt every label for it — a hitch the moment the tab had been open a
		# second.
		var measured := "—"
		if frames >= 0 and _debug_frames >= 0 and elapsed > 0.0:
			measured = "%.1f" % (float(frames - _debug_frames) / elapsed)
		(s[1] as Array).insert(0, ["Measured FPS", measured])
		_debug_frames = frames
	ui.populate_debug(sections)


## Re-read the machine; repaint the Controls tab only when something moved.
func _refresh_controls() -> void:
	if not is_instance_valid(_system):
		return
	var state := _system.controls_state()
	if state == _controls_state:
		return
	_controls_state = state
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	var ui := vp.get_child(0) as CoreOptions2D if vp and vp.get_child_count() > 0 else null
	if ui != null:
		ui.populate_controls(state)


## The Volume row follows the device's own wheel while the panel is open, and the
## Controls tab the machine's switches, a few times a second (a hand on the shell,
## a peer, a lead moving at the set).
func _while_shown(delta: float) -> void:
	if not is_instance_valid(_system):
		return
	_controls_poll += delta
	if _controls_poll >= CONTROLS_POLL_S:
		_controls_poll = 0.0
		_refresh_controls()
	_debug_poll += delta
	if _debug_poll >= DEBUG_POLL_S:
		_refresh_debug(_debug_poll)
		_debug_poll = 0.0
	var v := _device_volume()
	if is_equal_approx(v, _shown_volume):
		return
	_shown_volume = v
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	var ui := vp.get_child(0) as CoreOptions2D if vp and vp.get_child_count() > 0 else null
	if ui != null:
		ui.show_volume(v)


## System-tab toggle: float in place where dropped.
func _on_ignore_gravity_toggled(enabled: bool) -> void:
	if _system and is_instance_valid(_system):
		_system.set_ignore_gravity(enabled)


## System-tab toggle: a reflective-LCD handheld's screen lights itself.
func _on_screen_glow_toggled(enabled: bool) -> void:
	if _system and is_instance_valid(_system):
		_system.set_screen_glow(enabled)


## The cabinet's DIP Switch tab: the core's own DIP screen to open on the game's screen (MAME), or the
## core's DIP options to set here (FBNeo). Hidden on any other machine.
func _populate_dip_tab(ui: CoreOptions2D) -> void:
	ui.populate_dip(_system.has_dip_tab(), _system.core_dip_menu_available(), _system.is_powered_on,
		_system.core_dip_menu_open())


## DIP tab button: the core's DIP screen opens (or shuts) on the cabinet's own screen.
func _on_dip_menu_requested() -> void:
	if _system and is_instance_valid(_system):
		_system.toggle_core_dip_menu()
		_populate()


## System-tab row (cabinets): this cabinet's say over the arcade attract option.
func _on_attract_override_changed(mode: int) -> void:
	if _system and is_instance_valid(_system):
		_system.set_attract_override(mode)


## System-tab toggle (cabinets): the game's art on the marquee and sides.
func _on_cabinet_art_toggled(enabled: bool) -> void:
	if _system and is_instance_valid(_system):
		_system.set_cabinet_art_enabled(enabled)


func _on_port_device_changed(port: int, device_id: int) -> void:
	if _system and is_instance_valid(_system):
		print("[CoreOptionsPanel] port %d device → %d" % [port, device_id])
		_system.set_controller_port_device(port, device_id)


## System-tab picker: which core runs this machine.
func _on_core_selected(core: String) -> void:
	if _system and is_instance_valid(_system):
		_system.set_core_choice(core)
		_populate()


func _on_pad_device_changed(guid: String, ordinal: int) -> void:
	if _system and is_instance_valid(_system):
		print("[CoreOptionsPanel] physical pad → '%s' #%d" % [guid, ordinal])
		_system.pad_guid = guid
		_system.pad_ordinal = ordinal


# ── Placement, for FloatingObjectPanel3D ─────────────────────────────────────

func _target_node() -> Node3D:
	return _system
