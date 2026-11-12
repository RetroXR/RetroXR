## AppPrefs — Autoload singleton holding the switches on the menu's OPTIONS tab,
## plus the player's hidden-systems list, persisted to user://app_prefs.json.
##
## Switches that back a global static (ControllerModel.draw_hands,
## SystemFilter.enabled) own it: their setters write it, so every writer -- the
## load, the OPTIONS tab, a mod, a test -- keeps the two alike. The rest need the rig
## or the scene tree, so SpawnMenuController applies those once the menu is
## connected and the camera has been found.
##
## Defaults below are the values a fresh install starts with; a key missing from
## the JSON keeps its default rather than reading as false.
extends Node

## The mains region moved (set_mains_region). The room's plates and strips follow
## it through SpawnMenuController; a mod listens with ModApi.on_mains_region_changed.
signal mains_region_changed(region: String)
## The console-name region moved (set_region_names): tiles and titles rename.
signal region_names_changed(region: String)
## "Enable Power Simulation" moved (set_power_simulation): every PowerInput in the
## room asks again whether its device has power (MainsPower.changed).
signal power_simulation_changed(on: bool)
## The welcome page at start was switched (set_show_welcome): from its own "Don't
## Show Again" or from OPTIONS > General, and each follows the other.
signal show_welcome_changed(on: bool)

const PREFS_PATH := "user://app_prefs.json"

var auto_save_scene:  bool = true
## Whether the room is also written back on a timer, not just when it is left.
## On by default: until this existed, quitting the app — or losing it to the
## Quest's own lifecycle — dropped everything placed since the last room change,
## and there is still no save-on-quit hook to fall back on.
var autosave_periodic: bool = true
## Seconds between periodic saves. Clamped to the slider's range on load so a
## hand-edited 0 cannot spin the timer every frame.
var autosave_interval: float = 60.0
const AUTOSAVE_INTERVAL_MIN := 15.0
const AUTOSAVE_INTERVAL_MAX := 300.0
var aim_crosshair:    bool = false
## Desktop mouse-look speed, a multiplier on the turn provider's own scale
## (1.0 is how it always turned). Clamped to the slider's range on load.
var mouse_sensitivity: float = 1.0
const MOUSE_SENSITIVITY_MIN := 0.1
const MOUSE_SENSITIVITY_MAX := 3.0
## The comfort rows at the top of OPTIONS > General. SpawnMenuController applies them
## to the rig once it has found it; each is clamped to its control's range on load.
## Turn Style (headset): smooth rather than snap turning.
var turn_smooth: bool = false
## Snap Angle (headset), one of SNAP_TURN_ANGLES. 45 is what the menu always showed;
## until it was saved nothing applied it, and the rig turned by xr-tools' own 20.
var snap_turn_angle: float = 45.0
const SNAP_TURN_ANGLES: Array[float] = [30.0, 45.0, 60.0]
## Field of View (desktop), before Zoom (QualityManager.zoom) brings it in.
var desktop_fov: float = 75.0
const DESKTOP_FOV_MIN := 60.0
const DESKTOP_FOV_MAX := 110.0
## Height Offset (both), metres added to the player's eye height.
var height_offset: float = 0.0
const HEIGHT_OFFSET_MIN := -1.0
const HEIGHT_OFFSET_MAX := 1.0
## World Scale (headset); passthrough still pins 1.0 while it is up.
var world_scale: float = 0.85
const WORLD_SCALE_MIN := 0.4
const WORLD_SCALE_MAX := 1.5
enum XRDisplayMode {
	CONTROLLERS,
	HANDS,
	BOTH,
}
## What the physical XR input devices look like. BOTH is deliberately the
## missing-key default too, so an existing install receives Capsense hands on
## its first run after the feature arrives rather than silently keeping the old
## controller-only presentation.
var xr_display_mode: XRDisplayMode = XRDisplayMode.BOTH
## Mirrored into ControllerModel.draw_hands by the setter (see the header).
var controller_hands: bool = false:
	set(v):
		controller_hands = v
		ControllerModel.draw_hands = v
## Which region's wall outlets the room has (a MainsRegions id). Empty until the
## first load, which picks one from the system locale; an id no shipped table or
## installed mod knows is kept as is, so a region a mod brings survives a launch
## without that mod, and MainsRegions.resolve falls back to the default meanwhile.
var mains_region: String = ""
## Which region's console names tiles wear, and the cartridge a ROM of no known
## region gets (RegionalNames): "" not picked yet (the outlet region's, followed
## if it moves), "us" / "eu" / "jp", or "original" for the cores' own names
## (cartridges then still follow the outlet region).
var region_names: String = ""
## The player's name as cores are told it (GET_USERNAME): a PSP's nickname, a DS's
## firmware name, a netplay handle. "" = automatic (auto_player_name).
var player_name: String = ""
## The language cores are told (GET_LANGUAGE), a CoreLanguage id. "" = automatic,
## from the system locale.
var core_language: String = ""
## Whether a fingertip presses the buttons on pads, handhelds and the like
## (ControlPoke). On by default; read every frame, so a change takes at once.
var poke_controls:    bool = true
## "Enable Power Simulation" (MainsPower, PowerInput): on, a console, a set or a deck
## switches on only when a live supply reaches it -- a mains cord into a wall outlet,
## a strip in the wall, an AC adapter, cells in every bay. Off by default, which is how
## the room behaved before anything consumed power: everything powers whatever its
## cords do. A room with no wall outlet at all powers everything either way.
var power_simulation: bool = false
## Whether a held TV remote floats its button grid (TVRemote). Off, the thumbstick lights the
## handset's own keys and a stick click presses the lit one. Until the player picks on the
## remote's own menu it is automatic: ON at a desk (the mouse hand has no stick to light keys
## with) and off in a headset. Read every frame, so a change takes at once; only a choice is saved.
var remote_button_menu: bool:
	get:
		if _remote_button_menu < 0:
			return not MenuStyle.is_vr_mode()
		return _remote_button_menu == 1
	set(v):
		_remote_button_menu = 1 if v else 0
## -1 = automatic (never chosen), 0 off, 1 on.
var _remote_button_menu: int = -1
## Mirrored into SystemFilter.enabled by the setter (see the header).
var system_filter:    bool = true:
	set(v):
		system_filter = v
		SystemFilter.enabled = v
## Whether the player may move the core options that make a machine show its own
## boot screen. Off means BiosBoot's measured values are pinned every launch and
## shown locked; on hands them back, seeded once so a machine still boots right
## until the player changes one. A missing key reads as off, so an existing
## install gets the pinned behaviour.
var bios_boot_override: bool = false

## A switched-on arcade cabinet shows its game's video instead of running it, until somebody uses it
## (ArcadeAttract). On by default (2026-11-01: it was off while it was thought heavy and unstable, and it proved
## neither). Each cabinet can override it (RetroSystem.attract_override).
var arcade_attract_mode: bool = true
## How a gun game's foot pedal is worked, in a headset that reads no feet (ArcadeInput._takes_cover). You are out
## of cover, the pedal down, while you hold the gun, and something takes cover: the gun hand's A or X and the pedal
## key in every mode, the free hand's trigger as well in PEDAL_FREE_HAND, ducking as well in PEDAL_DUCK.
const PEDAL_BUTTON := "button"
const PEDAL_FREE_HAND := "free_hand"
const PEDAL_DUCK := "duck"
var arcade_pedal_mode: String = PEDAL_BUTTON
## Whether a sit-down cabinet on a moving base (After Burner's deluxe, Out Run's) moves: its seat and cabin tilt a few degrees with the stick and the
## wheel, and the player in the seat is carried with them. Automatic is on at a desk and off in a headset: a seat that moves under a headset is the
## surest way to make somebody ill, and nobody has worn this one yet.
const MOTION_AUTO := "auto"
const MOTION_ON := "on"
const MOTION_OFF := "off"
var arcade_motion: String = MOTION_AUTO
## Whether the spawn menu wraps onto a cylinder. Unlike the rest, this one is not
## an OPTIONS switch — it is the toggle on the menu's own lower-right corner.
var menu_curved:      bool = true
## Whether HeldHint pops its tooltip over a picked-up device.
var show_hints:       bool = true
## HeldHint row id -> times the player has used that verb. A row stops appearing
## past HeldHint.LEARNED_AFTER. A dictionary rather than a key per row so a new
## hint needs no change here.
var hint_uses:        Dictionary = {}
## Whether the welcome page (WelcomePanel) stands in front of the player at the
## start of every launch. On by default, the missing key too; off from the page's
## own "Don't Show Again", back on from OPTIONS > General. Change it through
## set_show_welcome, which says so to whichever of the two is not the one pressed.
var show_welcome:     bool = true
## Whether sound is spatialised by Meta XR Audio rather than Godot's own panning.
## Desktop only, and only offered there: on the Quest the SDK is the entire point,
## and its binaural rendering is right for a headset. On a desk it is not always —
## over speakers the HRTF is working against the room, and a surround rig gets no
## centre channel out of it, because the SDK renders two channels by design.
var spatial_audio_sdk: bool = true
## Whether a running core's microphone hears the real one. The device opens only
## while some core has its microphone switched on.
var microphone_enabled: bool = true
## Which input the microphone is read from, by the name AudioServer knows it by,
## or "" to follow whatever the system calls default.
##
## The NAME is stored rather than an index, because an index means a different
## device the moment one is unplugged. A name that is not currently present is
## KEPT rather than cleared: a USB microphone that is plugged back in should be
## used again, and a player who unplugged one for an afternoon has not changed
## their mind about which microphone is theirs.
var microphone_device: String = ""
## How the player gets around. Both verbs are on the LEFT stick and exactly one
## is live at a time — pushing the stick forward cannot mean "walk" and "aim a
## teleport" at once. False (smooth walking) is the default because it is the
## one that needs no explaining; teleport is the comfort option.
var locomotion_teleport: bool = false
## Whether the sticks still drive the player while passthrough is on. Sliding the
## world past you while you can see your actual room puts the two out of register,
## which is why the default is OFF (2026-11-05; it was on). The room you are standing
## in is rarely the size of the one you are furnishing, so walking alone may not reach
## everything: Options > "Move in Passthrough" turns the sticks back on.
var passthrough_locomotion: bool = false
## Whether, in passthrough, the real room hides what is behind it: a hand in front
## of a console covers it (RealRoom, from Meta's depth). On by default; edges are
## ragged and it costs the GPU something, so it can be switched off.
var passthrough_occlusion: bool = true
## Whether passthrough uses what the Quest knows of the player's room: furniture
## to rest things on, Meta's depth for the Game Boy Camera and for occlusion
## (RealRoom, EnvironmentDepth). On by default; off, passthrough is plain: it asks
## for no spatial-data consent and reads nothing.
var passthrough_spatial: bool = true
## What things rest on in the real room (RealRoom): off, the flat boxes and planes
## drawn in Space Setup -- level, and cheap; on, a Quest 3's scanned mesh of
## every surface, thousands of triangles, lumpy where the scan is.
var passthrough_room_mesh: bool = false
## How a libretro camera's subviewport (the Game Boy Camera's lens, GbCameraEye)
## finds the real room behind its picture in passthrough: "sphere", the default,
## the room taken to be 1.5 m from the headset camera everywhere, with no depth
## asked for; "depth", Meta's depth of what is really there.
var libretro_camera_backdrop: String = "sphere"
## Whether VR focus mode shows the real room through passthrough around its screen
## instead of black. Falls back to black where passthrough is unavailable.
var focus_passthrough: bool = false
## Systemids the player has hidden from the Systems and Cartridges grids. One
## list for both: hiding a machine means "I don't care about this", not "not in
## this tab". Distinct from SystemFilter, which is our own opinion about which
## systemids are not consoles — this is the player's, and it survives a core
## being installed or removed.
var hidden_systems: PackedStringArray = []
## Show the hidden ones anyway, dimmed, so they can be unhidden. Not persisted
## as "off forever": a player who turns it on to unhide something and walks away
## should find the grid the way they left it.
var show_hidden_systems: bool = false
## Draw the Systems and Cartridges grids as squares of bare art — no name, no
## core count, no source badge. One pref for both, like the hidden list: it is a
## statement about how you want to read a grid, not about one tab.
var compact_tiles: bool = false
## Whether a mod downloaded from the mod.io browser installs and switches on as
## soon as it lands. Off, each one waits for its review (what it replaces, what
## it needs) and lands switched off, as every download used to. The switch is on
## the browser's own pages.
var mods_auto_install: bool = true

## The bedroom's time-of-day lever, 0 = morning .. 1 = night. 0.75 is the dusk the
## room was authored at, so an unset pref opens the room exactly as it always was.
##
## Here rather than in a save slot even though the bedroom now keeps slots:
## scene_persistence only tracks the "spawned" group, and the lever is an authored
## wall fixture that is not in it. A slot carries what the player put in the room;
## where they left the lever is a setting that outlives any one slot.
var bedroom_time_of_day: float = 0.75
## What GET_PREFERRED_HW_RENDER advertises to a core with no opinion of its own,
## matching the default the extension itself carries. A constant rather than a
## setting: there is no global switch for this, because the question is only
## ever interesting per core, and pushing this back is what stops the core that
## follows an overridden one from inheriting its API.
const DEFAULT_HW_RENDER := "vulkan"
## core_name -> a value from hw_render_choices(), for a core that needs a
## different answer from the rest. Set from CORES > Manager > (core) > FRONTEND;
## absent means the default above.
var hw_render_overrides: Dictionary = {}


## Spawn-menu row -> the color a plain press of it spawns, set from the row's
## held panel. Keyed "<systemid>|<the row's own token>" (SpawnMenuSpawnView._default_key);
## a row not listed spawns as it comes. An id the row no longer lists (its mod
## gone or changed) is ignored where it is read, not pruned here.
var spawn_defaults: Dictionary = {}


## The color a plain press of the row `token` spawns, or "" for as it comes.
func spawn_default(token: String) -> String:
	return str(spawn_defaults.get(token, ""))


## Make `variant` what a plain press of the row `token` spawns ("": as it
## comes again), and persist.
func set_spawn_default(token: String, variant: String) -> void:
	if token.is_empty() or spawn_default(token) == variant:
		return
	if variant.is_empty():
		spawn_defaults.erase(token)
	else:
		spawn_defaults[token] = variant
	save_prefs()


## True when this systemid should be kept out of the grids.
func is_system_hidden(systemid: String) -> bool:
	return systemid in hidden_systems


## Hide or unhide a systemid and persist. No-op if already in that state.
func set_system_hidden(systemid: String, hidden: bool) -> void:
	if systemid.is_empty() or is_system_hidden(systemid) == hidden:
		return
	if hidden:
		hidden_systems.append(systemid)
	else:
		hidden_systems.remove_at(hidden_systems.find(systemid))
	save_prefs()


## Switch the welcome page at start on or off, save it, and say so. False when the
## save did not land: the switch holds for this launch and is back as it was at the
## next.
func set_show_welcome(on: bool) -> bool:
	if on == show_welcome:
		return true
	show_welcome = on
	var saved := save_prefs()
	print("[Prefs] welcome page at start -> %s%s" % [on, "" if saved else " (NOT saved)"])
	show_welcome_changed.emit(on)
	return saved


## Change the console-name region, save it, and say so.
func set_region_names(region: String) -> void:
	if region == region_names or not RegionalNames.is_region(region):
		return
	region_names = region
	save_prefs()
	print("[Prefs] console names -> '%s'" % region)
	region_names_changed.emit(region)


## Set the player's name for cores ("" = automatic), save it and push it. A core
## already running keeps the name it started with.
func set_player_name(name_text: String) -> void:
	var clean := _clean_player_name(name_text)
	if clean == player_name:
		return
	player_name = clean
	save_prefs()
	print("[Prefs] player name -> '%s'" % clean)
	apply_core_identity()


## Set the cores' language (a CoreLanguage id, "" = automatic), save it and push it.
func set_core_language(id: String) -> void:
	if id == core_language or (not id.is_empty() and not CoreLanguage.is_language(id)):
		return
	core_language = id
	save_prefs()
	print("[Prefs] core language -> '%s'" % id)
	apply_core_identity()


## The name used while player_name is empty: the RetroAchievements username if
## one is saved, else the desktop login name, else "Player". The headset has no
## login name worth giving (Android's account names need a permission), so it
## goes straight from RetroAchievements to "Player".
func auto_player_name() -> String:
	var ra := get_node_or_null("/root/RA")
	if ra != null and ra.get("config") != null:
		var ra_name := _clean_player_name(str(ra.config.username))
		if not ra_name.is_empty():
			return ra_name
	var login := _clean_player_name(os_login_name())
	return login if not login.is_empty() else "Player"


## The desktop login name, or "" where there is none (Android, a web build).
static func os_login_name() -> String:
	match OS.get_name():
		"Windows":
			return OS.get_environment("USERNAME")
		"Linux", "macOS", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var user := OS.get_environment("USER")
			return user if not user.is_empty() else OS.get_environment("LOGNAME")
	return ""


func effective_player_name() -> String:
	return player_name if not player_name.is_empty() else auto_player_name()


## The CoreLanguage id cores are told: the player's pick, else the system's.
func effective_core_language() -> String:
	if not core_language.is_empty():
		return core_language
	return CoreLanguage.for_locale(OS.get_locale())


## Push the name and the language to the extension. Both are globals it copies
## when a core starts (the name) or asks (the language), so this runs at boot,
## when either pref changes, and when the RetroAchievements name does (RA calls it).
func apply_core_identity() -> void:
	if not ClassDB.class_exists("Libretro"):
		return
	ClassDB.class_call_static("Libretro", "SetUsername", effective_player_name())
	ClassDB.class_call_static("Libretro", "SetLanguage",
		CoreLanguage.retro_language(effective_core_language()))


## One line, no control characters, at most 32 characters: what a console's own
## name fields can hold is far less, and a core trims to its own limit.
static func _clean_player_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.unicode_at(0) >= 32 and c.unicode_at(0) != 127:
			out += c
	return out.substr(0, 32).strip_edges()


## Change "Enable Power Simulation", save it, and say so: every powered device in
## the room re-asks for its supply (MainsPower listens).
func set_power_simulation(on: bool) -> void:
	if on == power_simulation:
		return
	power_simulation = on
	save_prefs()
	print("[Prefs] power simulation -> %s" % on)
	power_simulation_changed.emit(on)
	if is_inside_tree():
		MainsPower.changed(get_tree())


## Change the mains region, save it, and say so.
func set_mains_region(id: String) -> void:
	if id == mains_region:
		return
	mains_region = id
	save_prefs()
	mains_region_changed.emit(id)


func _ready() -> void:
	load_prefs()
	if mains_region.is_empty() or Connectors.problem(mains_region) != "":
		mains_region = MainsRegions.for_locale(OS.get_locale())
	# A member's initializer does not run its setter, so a fresh install (no
	# prefs file, nothing loaded) has the statics set here once; every later
	# write goes through the setters.
	ControllerModel.draw_hands = controller_hands
	SystemFilter.enabled = system_filter
	# RA is a later autoload, so the name here is the login name until RA has read
	# its config and calls this again.
	apply_core_identity()
	# Spatial audio is deliberately NOT applied here: SpatialAudioListener is a
	# later autoload and reads this pref in its own _ready. See
	# _apply_spatial_audio, which serves the player changing it afterwards.


## Which APIs this platform can hand a core, as [label, pref value,
## retro_hw_context_type]. Mirrors the switch in VideoHandler::SetHwRender:
## OpenGL is GLES3 on Android and the desktop core profile everywhere else, and
## the two D3D contexts exist only on Windows. Offering one the extension would
## reject is offering a black screen.
func hw_render_choices() -> Array:
	var out: Array = [["Vulkan", "vulkan", 6]]
	if OS.get_name() == "macOS":
		return out
	if OS.get_name() == "Android":
		out.append(["OpenGL ES 3", "opengl", 4])
	else:
		out.append(["OpenGL", "opengl", 3])
	if OS.get_name() == "Windows":
		out.append(["Direct3D 11", "d3d11", 7])
		out.append(["Direct3D 12", "d3d12", 9])
	return out


## Whether a cabinet on a moving base moves (arcade_motion): the player's choice, else on at a desk and off in a headset.
func arcade_motion_enabled(in_headset: bool) -> bool:
	match arcade_motion:
		MOTION_ON:
			return true
		MOTION_OFF:
			return false
	return not in_headset


## The API this core will be offered: its own override, or the default.
func hw_render_for(core_name: String) -> String:
	var over := str(hw_render_overrides.get(core_name, ""))
	return over if not over.is_empty() else DEFAULT_HW_RENDER


## "" when this core has no override of its own.
func hw_render_override(core_name: String) -> String:
	return str(hw_render_overrides.get(core_name, ""))


## Set or, with an empty api, clear one core's override.
func set_hw_render_override(core_name: String, api: String) -> void:
	if core_name.is_empty():
		return
	if api.is_empty():
		hw_render_overrides.erase(core_name)
	else:
		hw_render_overrides[core_name] = api
	save_prefs()


## Push the answer for the core that is about to start. MUST run before
## StartContent: the static is read on the emulation thread while the core
## initialises, so a machine already switched on keeps the API it booted with.
func apply_hw_render_for(core_name: String) -> void:
	_push_hw_render(hw_render_for(core_name))


## A value naming an API this platform does not offer (a prefs file carried over
## from another one) pushes nothing, leaving whatever was set last standing —
## the extension's own default at boot.
func _push_hw_render(api: String) -> void:
	if not ClassDB.class_exists("Libretro"):
		return
	for choice: Array in hw_render_choices():
		if str(choice[1]) == api:
			ClassDB.class_call_static("Libretro", "SetPreferredHwRender", int(choice[2]))
			return


## Push the audio backend choice when the player CHANGES it. At boot the listener
## reads this pref itself — it is declared after this autoload, so it can, and a
## push from here could not: /root/SpatialAudioListener does not exist yet.
##
## Ignored on Android, where the option is not offered and the pref could only be
## stale.
func _apply_spatial_audio() -> void:
	if OS.get_name() == "Android":
		return
	var listener := get_node_or_null("/root/SpatialAudioListener")
	if listener != null:
		listener.set_sdk_enabled(spatial_audio_sdk)
	elif Engine.has_singleton("MetaXRAudio"):
		Engine.get_singleton("MetaXRAudio").call("set_enabled", spatial_audio_sdk)


# ── Persistence ───────────────────────────────────────────────────────────────

## Read the saved prefs over the defaults. Public so a suite can read back what
## save_prefs() wrote into a fresh instance without entering the tree, where
## _ready would also apply them to the running room.
func load_prefs() -> void:
	var data := JsonStore.read_dict(PREFS_PATH, "AppPrefs")
	if data.is_empty():
		return
	auto_save_scene  = JsonStore.get_bool(data, "auto_save_scene",  auto_save_scene)
	autosave_periodic = JsonStore.get_bool(data, "autosave_periodic", autosave_periodic)
	autosave_interval = clampf(JsonStore.get_float(data, "autosave_interval", autosave_interval),
		AUTOSAVE_INTERVAL_MIN, AUTOSAVE_INTERVAL_MAX)
	# The performance HUD is deliberately absent: like the collision-shape
	# overlay it is a look at how the app is running, not a setting, so it lives
	# on PerfHud's statics and is off again every launch. A "show_fps" left in an
	# old file is simply ignored.
	aim_crosshair    = JsonStore.get_bool(data, "aim_crosshair",    aim_crosshair)
	mouse_sensitivity = clampf(JsonStore.get_float(data, "mouse_sensitivity", mouse_sensitivity),
		MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	turn_smooth = JsonStore.get_bool(data, "turn_smooth", turn_smooth)
	var snap := JsonStore.get_float(data, "snap_turn_angle", snap_turn_angle)
	snap_turn_angle = snap if snap in SNAP_TURN_ANGLES else 45.0
	desktop_fov = clampf(JsonStore.get_float(data, "desktop_fov", desktop_fov),
		DESKTOP_FOV_MIN, DESKTOP_FOV_MAX)
	height_offset = clampf(JsonStore.get_float(data, "height_offset", height_offset),
		HEIGHT_OFFSET_MIN, HEIGHT_OFFSET_MAX)
	world_scale = clampf(JsonStore.get_float(data, "world_scale", world_scale),
		WORLD_SCALE_MIN, WORLD_SCALE_MAX)
	xr_display_mode = _prefs_xr_display_mode(data, "xr_display_mode", xr_display_mode)
	controller_hands = JsonStore.get_bool(data, "controller_hands", controller_hands)
	poke_controls    = JsonStore.get_bool(data, "poke_controls",    poke_controls)
	power_simulation = JsonStore.get_bool(data, "power_simulation", power_simulation)
	# A new key: the old "remote_button_menu" was written on every save whether chosen or not, so a
	# false in it is the old default, not the player's pick, and would keep a desk's grid off.
	if data.has("remote_button_menu_choice"):
		remote_button_menu = JsonStore.get_bool(data, "remote_button_menu_choice", false)
	system_filter    = JsonStore.get_bool(data, "system_filter",    system_filter)
	bios_boot_override = JsonStore.get_bool(data, "bios_boot_override", bios_boot_override)
	arcade_attract_mode = JsonStore.get_bool(data, "arcade_attract_mode", arcade_attract_mode)
	var pedal := JsonStore.get_string(data, "arcade_pedal_mode", arcade_pedal_mode)
	arcade_pedal_mode = pedal if pedal in [PEDAL_BUTTON, PEDAL_FREE_HAND, PEDAL_DUCK] else PEDAL_BUTTON
	var motion := JsonStore.get_string(data, "arcade_motion", arcade_motion)
	arcade_motion = motion if motion in [MOTION_AUTO, MOTION_ON, MOTION_OFF] else MOTION_AUTO
	menu_curved      = JsonStore.get_bool(data, "menu_curved",      menu_curved)
	show_hints       = JsonStore.get_bool(data, "show_hints",       show_hints)
	hint_uses        = JsonStore.get_dict(data, "hint_uses",        hint_uses)
	show_welcome     = JsonStore.get_bool(data, "show_welcome",     show_welcome)
	spatial_audio_sdk = JsonStore.get_bool(data, "spatial_audio_sdk", spatial_audio_sdk)
	microphone_enabled = JsonStore.get_bool(data, "microphone_enabled", microphone_enabled)
	microphone_device = JsonStore.get_string(data, "microphone_device", microphone_device)
	locomotion_teleport = JsonStore.get_bool(data, "locomotion_teleport", locomotion_teleport)
	passthrough_locomotion = JsonStore.get_bool(data, "passthrough_locomotion", passthrough_locomotion)
	passthrough_occlusion = JsonStore.get_bool(data, "passthrough_occlusion", passthrough_occlusion)
	passthrough_spatial = JsonStore.get_bool(data, "passthrough_spatial", passthrough_spatial)
	passthrough_room_mesh = JsonStore.get_bool(data, "passthrough_room_mesh", passthrough_room_mesh)
	libretro_camera_backdrop = JsonStore.get_string(data, "libretro_camera_backdrop", libretro_camera_backdrop)
	if libretro_camera_backdrop not in ["depth", "sphere"]:
		libretro_camera_backdrop = "sphere"
	focus_passthrough = JsonStore.get_bool(data, "focus_passthrough", focus_passthrough)
	hidden_systems      = PackedStringArray()
	for hidden: String in JsonStore.get_strings(data, "hidden_systems"):
		if SystemIds.canonical(hidden) not in hidden_systems:
			hidden_systems.append(SystemIds.canonical(hidden))
	show_hidden_systems = JsonStore.get_bool(data, "show_hidden_systems", show_hidden_systems)
	region_names        = JsonStore.get_string(data, "region_names", region_names)
	if not RegionalNames.is_region(region_names):
		region_names = ""
	player_name = _clean_player_name(JsonStore.get_string(data, "player_name", player_name))
	core_language = JsonStore.get_string(data, "core_language", core_language)
	if not CoreLanguage.is_language(core_language):
		core_language = ""
	compact_tiles       = JsonStore.get_bool(data, "compact_tiles",       compact_tiles)
	mods_auto_install   = JsonStore.get_bool(data, "mods_auto_install",   mods_auto_install)
	bedroom_time_of_day = clampf(JsonStore.get_float(data, "bedroom_time_of_day",
		bedroom_time_of_day), 0.0, 1.0)
	hw_render_overrides = JsonStore.get_dict(data, "hw_render_overrides", hw_render_overrides)
	mains_region = JsonStore.get_string(data, "mains_region", mains_region)
	spawn_defaults = JsonStore.get_dict(data, "spawn_defaults", spawn_defaults)


## Returns false when the write did not land. Callers that report a setting
## as changed should say so instead when this is false.
func save_prefs() -> bool:
	return JsonStore.write_dict(PREFS_PATH, _prefs_dict(), "AppPrefs")


## What save_prefs() writes.
func _prefs_dict() -> Dictionary:
	var data := {
		"auto_save_scene":  auto_save_scene,
		"autosave_periodic": autosave_periodic,
		"autosave_interval": autosave_interval,
		"aim_crosshair":    aim_crosshair,
		"mouse_sensitivity": mouse_sensitivity,
		"turn_smooth":      turn_smooth,
		"snap_turn_angle":  snap_turn_angle,
		"desktop_fov":      desktop_fov,
		"height_offset":    height_offset,
		"world_scale":      world_scale,
		"xr_display_mode":  xr_display_mode,
		"controller_hands": controller_hands,
		"poke_controls":    poke_controls,
		"power_simulation": power_simulation,
		"system_filter":    system_filter,
		"bios_boot_override": bios_boot_override,
		"arcade_attract_mode": arcade_attract_mode,
		"arcade_pedal_mode": arcade_pedal_mode,
		"arcade_motion": arcade_motion,
		"menu_curved":      menu_curved,
		"show_hints":       show_hints,
		"hint_uses":        hint_uses,
		"show_welcome":     show_welcome,
		"spatial_audio_sdk": spatial_audio_sdk,
		"microphone_enabled": microphone_enabled,
		"microphone_device": microphone_device,
		"locomotion_teleport": locomotion_teleport,
		"passthrough_locomotion": passthrough_locomotion,
		"passthrough_occlusion": passthrough_occlusion,
		"passthrough_spatial": passthrough_spatial,
		"passthrough_room_mesh": passthrough_room_mesh,
		"libretro_camera_backdrop": libretro_camera_backdrop,
		"focus_passthrough": focus_passthrough,
		"hidden_systems":    hidden_systems,
		"show_hidden_systems": show_hidden_systems,
		"region_names":      region_names,
		"player_name":       player_name,
		"core_language":     core_language,
		"compact_tiles":     compact_tiles,
		"mods_auto_install": mods_auto_install,
		"bedroom_time_of_day": bedroom_time_of_day,
		"hw_render_overrides": hw_render_overrides,
		"spawn_defaults": spawn_defaults,
		"mains_region": mains_region,
	}
	if _remote_button_menu >= 0:
		data["remote_button_menu_choice"] = _remote_button_menu == 1
	return data


## Accept only the three named display modes. JSON numbers may be int or float;
## a stale or hand-edited value keeps the safe BOTH default.
func _prefs_xr_display_mode(data: Dictionary, key: String,
		fallback: XRDisplayMode) -> XRDisplayMode:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var mode := int(value)
	if mode < XRDisplayMode.CONTROLLERS or mode > XRDisplayMode.BOTH:
		return fallback
	return mode as XRDisplayMode
