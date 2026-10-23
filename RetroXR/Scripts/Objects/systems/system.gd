## RetroSystem — pickable retro console that loads a libretro core and renders to a connected TV.
class_name RetroSystem
extends XRToolsPickable


## True when this hardware has a bespoke model — an authored scene or a model
## script — rather than the procedural placeholder every other system shows.
## The spawn menu uses it to decide whether a system's hardware row is the real
## thing (named after it) or already the stand-in.
static func has_bespoke_model(sysid: String) -> bool:
	return SystemModelRegistry.has_any_model(sysid)


## True when this hardware has an authored stand-in model scene, i.e. spawning it
## with variant "primitive" gives plain geometry shaped like the device rather
## than the generic console box.
static func has_primitive_model(sysid: String) -> bool:
	return SystemModelRegistry.has_plain_alternative(sysid)


## Every Libretro method this script calls that the extension grew after the
## scripts first called it. The in-tree libretro-godot binds all of them, so
## each is called directly; what this list is for is a STALE binary.
##
## build.py is per platform and the binaries are gitignored, so a windows
## rebuild leaves android on whatever was last built for it -- and a stale
## build says nothing until the renamed method is CALLED, which is how "PDF
## manuals do not open on Quest" shipped for 18 days. So the first machine to
## be built asks ClassDB once and says, loudly and by name, which are missing.
const LIBRETRO_API: PackedStringArray = [
	"SetRtcPath", "SetSramRegionPath", "SetTransferPak", "SetTransferPakClock",
	"SetControllerPortDevice", "HasControllerScreens", "GetControllerAudioVoiceId",
	"GetCoreDebugInfo",
]
static var _stale_libretro: PackedStringArray = PackedStringArray()
static var _libretro_api_checked := false


## The LIBRETRO_API methods this process's extension lacks: empty on a build
## that matches the scripts. Checked and logged once per process.
static func stale_libretro_methods() -> PackedStringArray:
	if _libretro_api_checked:
		return _stale_libretro
	_libretro_api_checked = true
	if not ClassDB.class_exists("Libretro"):
		push_error("[RetroSystem] the libretro-godot extension is not loaded: no machine can run")
		_stale_libretro = LIBRETRO_API.duplicate()
		return _stale_libretro
	for method in LIBRETRO_API:
		if not ClassDB.class_has_method("Libretro", method):
			_stale_libretro.append(method)
	if not _stale_libretro.is_empty():
		push_error(("[RetroSystem] STALE libretro-godot extension for this platform: Libretro "
			+ "lacks %s. Rebuild it (python Tools/build.py <platform>, both targets).")
			% ", ".join(_stale_libretro))
	return _stale_libretro


## The libretro core filename (without extension), e.g. "fceumm".
## If empty at power_on(), looked up from CoreDefaults using systemid.
@export var core_name: String = ""

## Root directory passed to the C++ core loader (NOT the cores/ subdir — C++ appends that).
## If empty at power_on(), defaults to CoreDownloadManager.default_core_root().
@export_dir var core_directory: String = ""

## Human-readable label shown in UI
@export var system_label: String = ""

## libretro systemid (e.g. "nes", "snes"). Used for dynamic core lookup.
@export var systemid: String = ""

## Which model in SystemModelRegistry this system wears. Empty means "this
## platform's default". Saves written before models had ids are translated on the
## way in by ScenePersistence, so nothing here needs to know about variants.
@export var model_id: String = ""
## Which of that model's colors this console is, by the id its row lists it
## under (SystemModelRegistry `variants`); empty for the model as it comes. Set
## before the console enters the tree, as model_id is, and saved with it.
@export var model_variant: String = ""

## The id of the memory built into this console, set by a restore before the
## machine enters the tree. Empty mints a new one -- see ConsoleMemory.
var console_memory_id := ""

## Spatial audio settings for the AudioStreamPlayer3D created at runtime.
@export_group("Spatial Audio")
@export var audio_unit_size: float = 3.0        ## Reference distance (m) for full volume
@export var audio_max_distance: float = 15.0    ## Distance (m) at which sound is fully silent
@export var audio_panning_strength: float = 1.0 ## Left/right stereo separation (1.0 = default)
@export_group("")


# Runtime state
var rom_path: String = ""
var connected_tv: RetroTV = null
var is_powered_on: bool = false

## Which physical gamepad drives this machine, for HANDHELDS only. Everything
## with a controller port takes a PadReceiver plugged into it instead; a handheld
## has none (port_count is 0 below), so the same choice is made from its own
## Controllers panel and remembered here. GUID rather than device index, because
## the index is a connection order that changes every session. Empty = none.
var pad_guid: String = ""
var pad_ordinal: int = 0
## Exact mounted path registered with RomM's process-wide cache guard.
var _protected_cache_path: String = ""

## Video-out cables shown/usable. Handhelds default OFF (they have their own
## screen — the cables are clutter until wanted); consoles default ON (a TV is
## their only display). Toggled from the options panel's System tab.
var video_out_enabled: bool = true
# Saved value restored by persistence (set before _ready; -1 = no override).
var _video_out_from_save: int = -1
# Clamshell (DS/3DS) lid open angle restored by persistence (deg, 0 shut … 180
# flat; set before _ready; -1 = keep the model default).
var _lid_angle_from_save: float = -1.0
# Set before _ready by the deserializer, and only there — a menu-spawned
# console never sets this, so it defaults false. Read once, by
# _build_expansion_hardware, to decide whether a default-occupant accessory
# (the N64's Jumper Pak) should seed itself: a restored console's own
# "expansions" list (restore_expansion, driven by the save) is always the
# whole truth about what is bolted on, whether that is the default occupant,
# a real upgrade, or nothing at all, and seeding on top of that would double it.
var _restoring_from_save: bool = false


## Hand a console the state a save carries about it, before it enters the tree.
##
## The three fields above are one decision — "this console is being restored, not
## spawned" — and they are all read once from _ready. They must therefore be set
## BEFORE the caller adds the node to the tree, which is the invariant this
## method exists to keep in one place: ScenePersistence and TestSceneBuilder both
## used to set them by hand, so a fourth latch would have had to be remembered at
## two more call sites.
##
## `video_out` is -1 to keep the platform default, 0 or 1 to force it.
## `lid_angle` is degrees for a clamshell, or -1 to keep the model default.
func begin_restore(video_out: int = -1, lid_angle: float = -1.0) -> void:
	_video_out_from_save = video_out
	_lid_angle_from_save = lid_angle
	_restoring_from_save = true


## Force the video-out cables on or off, before the console enters the tree.
##
## Deliberately NOT begin_restore: a console built into a scene rather than
## loaded from a save is not being restored, and marking it so would stop its
## bays seeding their default occupants. Handhelds are the ones that need this —
## they default video-out off, and a generated scene wants them wired to a set.
func force_video_out(on: bool) -> void:
	_video_out_from_save = 1 if on else 0


## Ignore gravity: the system freezes exactly where it's dropped and floats
## there. Toggled from the options panel's System tab; default off.
var ignore_gravity: bool = false

## A cabinet's scraped art (marquee, sides) while a game is in its bay. On by default; the System tab's
## "Cabinet Art" toggle turns it off for whoever wants it naked. Saved in the room only when off.
var cabinet_art_enabled: bool = true

## A cabinet that is on but unused shows its game instead of running it (ArcadeAttract). `attract_override`
## is this cabinet's say over the global pref (ArcadeAttract.OVERRIDE_*): follow it, force on, force off.
## Saved in the room only when it is not "follow".
var attract_override: int = ArcadeAttract.OVERRIDE_FOLLOW
## True while it is on and only SHOWING its game: no core is running, `is_powered_on` stays false.
var attracting: bool = false
## True while the core running is one an attract started: nobody at the cabinet for ArcadeAttract.IDLE_SECONDS
## puts it away again.
var attract_session: bool = false
var _attract: ArcadeAttract = null
## Set for the one power_on that a use of the cabinet asked for, so it loads the core instead of attracting.
var _attract_released: bool = false

# Cached core options (populated when options_ready fires)
var _options_definitions: Dictionary = {}
var _options_values: Dictionary = {}
# Why the options list is empty, when it is empty for a reason worth showing
# (a core that publishes nothing until content is loaded, or none installed).
var _options_unavailable: String = ""

# The card that floats over this machine's picture — achievement unlocks, and
# the notice raised when a game cannot run. Made on demand rather than at
# power-on: most sessions raise neither, and it costs a SubViewport.
var _screen_toast_card: AchievementToast = null
# The card that floats over the hardware itself, for what the machine is waiting
# on rather than showing. Same on-demand cost as _screen_toast_card.
var _machine_toast_card: AchievementToast = null
## Upper bound on half the gap between the emitters when no TV is connected, in
## metres. A connected set reports its own speaker positions instead. The gap
## actually used is a fifth of the hardware's own width, so this only binds for
## something console-sized; see SystemAudio._refresh_hardware_geometry.
@export var audio_speaker_separation: float = 0.09

## How directional the speaker the sound comes out of is, 0 (omnidirectional)
## to 1.
##
## Applied wherever there is a facing worth tracking: a handheld radiates from
## its face, and a connected set radiates the way its picture points. Measured
## difference between facing the listener and facing away:
##
##     0.0  0.00 dB      0.3  -3.7 dB      0.6  -8.6 dB      1.0  -17.5 dB
##
## 1.0 is far more than a small speaker behind a plastic grille manages; the
## default is set where a real handheld sits, a few dB down when turned away
## rather than gone.
@export var audio_directivity: float = 0.45

# Top of the body in local space, for panels that float above the hardware.
# Cached and model-keyed for the same reason as the audio geometry above.
var _body_top_model_id: int = 0
var _body_top_local: float = 0.0

# Active system model — always set (falls back to RetroSystemModelDefault)
var _model: RetroSystemModel = null

# Held-input component (handhelds only — the device itself is the controller)
var _handheld_input: HandheldInput = null
## Wireless-pad pairing, on the consoles that have it (the Wii). Null elsewhere,
## and every call site is guarded on that — see _setup_wireless_pads.
var _wii_link: WiiLink = null

# Window material for TVs on multi-output hardware (dual-screen handhelds).
const SCREEN_WINDOW_SHADER := preload("res://Shaders/screen_window.gdshader")

## One video-out channel: what the model says it is, the lead built for it, and
## the set it currently reaches.
##
## One object rather than the eleven arrays this replaced — all grown in a single
## loop, all indexed by the same number, and all read apart. Three call sites had
## started defensively bounds-checking three DIFFERENT arrays against the same
## length, which is the shape of a bug waiting for the twelfth array.
##
## The node references are typed. A channel can outlive what it points at, but
## that is safe: a field is only ever ASSIGNED a live node or null, and reading a
## freed one is not an error -- passing it to a typed local is, so every read
## that may meet a freed node still goes through _live(). A probe that wants a
## display without a real set (saturn_session_probe) stands in a RetroTV
## subclass, not a bare Node, so `tv` is typed like the rest.
class VideoChannel:
	## From the model: what this output is called, which part of the core's
	## framebuffer it shows, whether it takes touch, and its stereo eye offset.
	var label: String = ""
	var rect: Rect2 = Rect2(0, 0, 1, 1)
	var touch: bool = false
	var eye_shift: float = 0.0
	var wires: PackedColorArray = PackedColorArray()
	## The lead: where it leaves the machine, the cable, its picture plug, its
	## audio pair ([left, right], empty on a channel the model gives one wire),
	## the rope and how far it reaches.
	var attach: Node3D = null
	var cable: Node3D = null
	var plug: CablePlug = null
	var audio_plugs: Array = []
	var rope: VerletRope = null
	var max_reach: float = 0.0
	## The set this channel is plugged into, and its touch surface on that set.
	var tv: RetroTV = null
	var touch_surface: TVTouchSurface = null
	## A set to reconnect to once the cables exist, and which of its inputs for
	## (save/load restore, which runs before the lead is built).
	var pending_tv: RetroTV = null
	var pending_input: int = 0

	static func from_model(row: Dictionary) -> VideoChannel:
		var channel := VideoChannel.new()
		channel.label = str(row.get("label", ""))
		channel.rect = row.get("rect", Rect2(0, 0, 1, 1))
		channel.touch = bool(row.get("touch", false))
		channel.eye_shift = float(row.get("eye_shift", 0.0))
		channel.wires = row.get("wires", PackedColorArray())
		return channel


# Video-out channels from the model (single unlabelled entry on classic
# hardware; TOP/BOTTOM on dual-screen handhelds). One cable per channel.
# connected_tv stays the channel-0 TV for external readers (persistence,
# netplay OSD).
var _channels: Array[VideoChannel] = []

## The captive lead built for each channel -- spawning, parking, clamping and
## freeing it -- lifted out into SystemVideoLead. The channels stay HERE: they are
## the one record the picture and sound routing both read.
var _video_lead: SystemVideoLead = null


## The video-out channels, for SystemVideoLead. The same array, not a copy.
func video_channels() -> Array[VideoChannel]:
	return _channels

## A/V sockets, for hardware that wears them instead of a captive lead (the NES),
## and where the picture and sound in them go -- lifted out into SystemAvPorts.
var _av: SystemAvPorts = null

# Its state under the names it had here, forwarded: tests, probes and the mods'
# probes read these and stand them in. See SystemAvPorts for what each means.
var _av_ports: Array:
	get: return _av.ports
	set(value): _av.ports = value
var _av_tv: Node3D:
	# Through is_instance_valid: a getter hands back what it reads, and handing
	# back a freed set (one deleted while cabled) is an error a field read is not.
	get: return _av.audio_sink if is_instance_valid(_av.audio_sink) else null
	set(value): _av.audio_sink = value
var _av_stereo: bool:
	get: return _av.stereo
	set(value): _av.stereo = value
var _av_speaker_l: int:
	get: return _av.speaker_l
	set(value): _av.speaker_l = value
var _av_speaker_r: int:
	get: return _av.speaker_r
	set(value): _av.speaker_r = value
var _snapped_cartridge: Node3D = null
## The console's SECOND native slot and what is in it -- the DS's Slot-2, which
## takes a Game Boy Advance cartridge. Null on every console with one slot; see
## Slot2Catalog for which have two.
var _slot2: XRToolsSnapZone = null
var _slot2_cartridge: Node3D = null

## The disc drive -- the loader, the lid, the spinning disc and the core's
## disk-control mirror -- lifted out into SystemTray. Made in _init.
var _disc_tray: SystemTray = null

# Its state under the names it had here, forwarded: the model packs' probes read
# these by name (`sys.get("_tray_open")`). See SystemTray for what each means.
var _tray_open: bool:
	get: return _disc_tray.open
var _tray: MediaTray:
	get: return _disc_tray.media_tray
var _slot: MediaSlot:
	get: return _disc_tray.media_slot

## Cached answer for roof_above_cartridge_slot(); NAN until the model is
## measurable. The shell does not change after it loads, and the query runs on
## every preview frame, so it is worked out once.
var _roof_over_slot: float = NAN


@onready var _system_body: MeshInstance3D = $SystemBody
@onready var _cartridge_slot: XRToolsSnapZone = $CartridgeSlot
## The cart lying in a push-tray bay, which the machine cannot read until the tray
## is pushed home. Distinct from _snapped_cartridge, which means "the machine has
## this cart" — on such a bay the two are apart for as long as the tray is up.
var _tray_cartridge: Node3D = null


## The cart lying in a push-tray bay (see _tray_cartridge), or null.
func get_tray_cartridge() -> Node3D:
	return _tray_cartridge
## The card snap zones, in slot order. Named here rather than looked up through a
## method because NetObjectSync resolves a slot by node name — its test double is
## a bare node with named children and no methods of its own.
##
## Slot A keeps the original node name so a PlayStation, and every saved room and
## replicated event that already refers to it, is untouched.
const MEMCARD_SLOT_NODES := ["MemoryCardSlot", "MemoryCardSlot2"]

## Where the four N64 Controller Paks sit inside the one SAVE_RAM block both N64
## cores publish. Measured from libretro_memory.h's save_memory_data, which the
## two cores lay out identically for these fields: eeprom (0x800), then four
## 32 KiB paks, then sram and flashram. parallel_n64 appends a 64DD region after
## those, which changes the block's total SIZE but not where a pak begins.
##
## Needed because neither core gives a pak a memory id or a file of its own: they
## back all four with a storage backend whose save is a no-op and stub their own
## mempak path helper to "". Offsets are the only handle there is.
const MEMPAK_PORTS := N64Card.SRM_PORTS
const MEMPAK_BASE_OFFSET := N64Card.SRM_BASE_OFFSET
const MEMPAK_SIZE := N64Card.CARD_SIZE

@onready var _memcard_slots: Array[XRToolsSnapZone] = [
	$MemoryCardSlot, $MemoryCardSlot2,
]
@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _libretro: Libretro = $Libretro
@onready var _power_button: VRButton = $PowerButton
@onready var _reset_button: VRButton = $ResetButton
@onready var _eject_button: VRButton = $EjectButton
@onready var _sync_button: VRButton = $SyncButton
@onready var _options_panel: CoreOptionsPanel = $CoreOptionsPanel
@onready var _system_name_label: Label3D = $SystemNameLabel
## Pads this console is wired to and the wells they lie in -- see
## SystemCaptivePads. Made in _init; the pads themselves come with the model.
var _captive_pads: SystemCaptivePads = null

## What is plugged into each controller port and USB socket, and what the core
## is told about it -- lifted out into SystemPorts. Made in _init; the cabinet's
## socket zones are handed to it in _ready.
var _ports: SystemPorts = null

# Its tables under the names they had here, forwarded: the model packs' probes
# read and stand these in by name (`sys.set("_controller_info", ...)`).
var _controller_info: Array:
	get: return _ports.controller_info
	set(value): _ports.controller_info = value
var _usb_zones: Array:
	get: return _ports.usb_zones
var _usb_plugs: Array:
	get: return _ports.usb_plugs

## A USB socket's number where a socket is saved or sent over the network: past
## the controller ports and every port a multitap could number, so the two
## kinds can never be mistaken for each other. USB socket k is USB_SLOT_BASE + k.
const USB_SLOT_BASE := 16


## Real-world cross-compatibility: media of these systemids also fits.
## (The GBA plays original Game Boy and Game Boy Color carts — and mgba runs
## them; each Color handheld plays its predecessor's.)
##
## The Game Boy takes a Color cartridge as well: they are the same shape, the
## black dual-mode ones play, and a Color-only one puts up its own "Game Boy
## Color only" screen (ForcedCoreOptions.game_boy_model runs the core as a DMG).
##
## The Wii row is not just cosmetic: with a GameCube disc in the tray the core's
## IsWii() goes false, and that changes how the whole cabinet is wired — see
## _wii_mode().
const _MEDIA_COMPAT: Dictionary = {
	"gba": ["gb", "gbc"],
	"gb": ["gbc"],
	"gbc": ["gb"],
	"ngpc": ["ngp"],
	"wonderswancolor": ["wonderswan"],
	"wii": ["gc"],
}

# RETRO_DEVICE_* types relevant to port routing (libretro.h).
const RETRO_DEVICE_NONE := 0
const RETRO_DEVICE_JOYPAD := 1
const RETRO_DEVICE_MOUSE := 2
const RETRO_DEVICE_KEYBOARD := 3
const RETRO_DEVICE_LIGHTGUN := 4
## A device id is a base type in the low byte and a core-specific subclass above it.
const RETRO_DEVICE_MASK := 0xFF

## The two controllers are built HERE and not in _ready, because a RetroSystem
## is not always a scene: system_tests builds bare RetroSystem.new() instances
## that never enter the tree, and every forwarder below would find a null.
func _init() -> void:
	_save_state = SaveStateController.new()
	_save_state.name = "SaveStateController"
	add_child(_save_state)
	_save_state.setup(self)
	_memcards = MemoryCardController.new()
	_memcards.name = "MemoryCardController"
	add_child(_memcards)
	_memcards.setup(self)
	# The per-console storages, in the order every lifecycle walk takes them --
	# see ConsoleStorage. All five on every machine: another machine asks this
	# one's whether a shared folder is free.
	_vmu = _add_storage(VmuStorage.new(), "VmuStorage") as VmuStorage
	_sega_cd = _add_storage(SegaCdStorage.new(), "SegaCdStorage") as SegaCdStorage
	_saturn = _add_storage(SaturnStorage.new(), "SaturnStorage") as SaturnStorage
	_three_do = _add_storage(ThreeDoStorage.new(), "ThreeDoStorage") as ThreeDoStorage
	_xbox = _add_storage(XboxStorage.new(), "XboxStorage") as XboxStorage
	_audio = SystemAudio.new()
	_audio.name = "SystemAudio"
	add_child(_audio)
	_audio.setup(self)
	_av = SystemAvPorts.new()
	_av.name = "SystemAvPorts"
	add_child(_av)
	_av.setup(self, _audio)
	_expansion_launch = ExpansionLaunch.new()
	_expansion_launch.name = "ExpansionLaunch"
	add_child(_expansion_launch)
	_expansion_launch.setup(self)
	_ports = SystemPorts.new()
	_ports.name = "SystemPorts"
	add_child(_ports)
	_ports.setup(self)
	_disc_tray = SystemTray.new()
	_disc_tray.name = "SystemTray"
	add_child(_disc_tray)
	_disc_tray.setup(self)
	_captive_pads = SystemCaptivePads.new()
	_captive_pads.name = "SystemCaptivePads"
	add_child(_captive_pads)
	_captive_pads.setup(self)
	_video_lead = SystemVideoLead.new()
	_video_lead.name = "SystemVideoLead"
	add_child(_video_lead)
	_video_lead.setup(self)
	_expansions = SystemExpansions.new()
	_expansions.name = "SystemExpansions"
	add_child(_expansions)
	_expansions.setup(self)


func _add_storage(storage: ConsoleStorage, node_name: String) -> ConsoleStorage:
	storage.name = node_name
	add_child(storage)
	storage.setup(self)
	_storages.append(storage)
	return storage


func _ready() -> void:
	super._ready()
	stale_libretro_methods()
	add_to_group(ExpansionPort.GROUP_SYSTEM)
	# Unconditional, unlike HandheldInput and WiiLink: every machine can be asked
	# for a state, and capture_gate answers for the ones that cannot give
	# one. Built here so the forwarders below never see a null.
	_cartridge_slot.has_picked_up.connect(_on_cartridge_inserted)
	_cartridge_slot.has_dropped.connect(_on_cartridge_removed)
	# Only this system's own media fits its slot (a GB cart won't go into a
	# SNES, a PS1 disc only fits a PlayStation). Unlabelled legacy media keeps
	# working everywhere; save/netplay restores bypass the filter.
	_cartridge_slot.snap_filter = accepts_media
	# Ignore-gravity: re-freeze wherever the player lets go.
	dropped.connect(_on_system_dropped)
	if ignore_gravity:   # restored from a save — float at the saved pose
		_freeze_in_place.call_deferred()
	for i in _memcard_slots.size():
		_memcard_slots[i].snap_filter = accepts_card
		_memcard_slots[i].has_picked_up.connect(_memcards.on_memcard_inserted.bind(i))
		# has_dropped carries no argument, so the slot has to be closed over.
		_memcard_slots[i].has_dropped.connect(
			func() -> void: _memcards.on_memcard_removed(i))
	_power_button.button_pressed.connect(toggle_power)
	_reset_button.button_pressed.connect(reset)
	_eject_button.button_pressed.connect(_disc_tray.on_eject_pressed)
	_libretro.options_ready.connect(_on_options_ready)
	_libretro.rumble_state_changed.connect(_ports.on_rumble)
	_libretro.disk_control_ready.connect(_disc_tray.on_disk_control_ready)
	_libretro.sram_flushed.connect(_memcards.on_sram_flushed)
	_libretro.content_load_failed.connect(_on_content_load_failed)
	# Controller port snap signals, and the gate on what each socket takes.
	_ports.wire_zones([$ControllerPort1, $ControllerPort2, $ControllerPort3, $ControllerPort4])
	# Load system-specific model (falls back to default placeholder model)
	_load_system_model()
	_build_console_memory()
	# Hardware with real sockets (the NES) gets those instead of a captive lead —
	# nothing plays until a lead is run to the set, as it did on the real thing.
	if _model.uses_av_ports():
		_av.build()
	else:
		_video_lead.spawn()
		# Deferred for the reason the name label is: the jack is seated off the
		# shell's meshes.
		_av.build_phones.call_deferred()
		_av.build_ext2.call_deferred()
	# Last of the sockets: its A/V ones are only built above.
	_check_listed_sockets()
	_update_name_label()
	# Lay the name flat on the model's front face once meshes + text are built.
	_place_name_label.call_deferred()
	# Deferred for the same reason the label is: the socket sits on the model's
	# top face and the foot under its bottom one, and neither is known until the
	# meshes exist.
	_build_expansion_hardware.call_deferred()
	# A machine spawns switched off, and its leads are clamped only once they
	# exist. Both ticks are armed by the things that make them worth running:
	# power_on/net_start_core and SystemVideoLead.apply_video_out.
	set_process(false)
	set_physics_process(false)


## The colours of a cabinet's power SWITCH (power_is_switch): lit green when on, a dark red when off.
const POWER_SWITCH_ON := Color(0.15, 1.0, 0.35)
const POWER_SWITCH_OFF := Color(0.45, 0.04, 0.04)


## The power button always reflects run state: green START when off, red STOP
## while running. Owned here (not per-model) so bespoke models that override
## on_power_on/off for their own visuals — the Virtual Boy's eyepiece shader —
## can't lose the label toggle. Harmless no-op for handhelds (button hidden).
func _update_power_button_visual() -> void:
	if _power_button == null:
		return
	# Only the generic placeholder cap gets the green/red START/STOP tint; a
	# modelled button (set_button_mesh) keeps its own material.
	var lit := is_powered_on or attracting
	# A cabinet that shows its game when it is switched on (attract) has a SWITCH, not a start button: it
	# stays down while on, reads ON / OFF and is lit green when on, so a row of cabinets says at a glance
	# which are on. Everything else keeps the green START / red STOP.
	var as_switch := power_is_switch()
	_power_button.set_latched_pressed(as_switch and lit)
	if _power_button.state_tint:
		if as_switch:
			_power_button.set_color(POWER_SWITCH_ON if lit else POWER_SWITCH_OFF)
		else:
			_power_button.set_color(Color(1.0, 0.0, 0.0) if lit else Color(0.0, 1.0, 0.0))
	var lbl := _power_button.get_node_or_null("ButtonLabel") as Label3D
	if lbl:
		if as_switch:
			lbl.text = "ON" if lit else "OFF"
		else:
			lbl.text = "STOP" if lit else "START"


## What this machine calls itself — the scene's own label, else the systemname
## its cores agree on, else the bare systemid.
##
## The shared database rather than a fresh one: this used to reparse all 314
## .info files to answer a single lookup, and the answer cannot change at runtime.
func _display_name() -> String:
	var name_text := system_label
	if name_text.is_empty() and not systemid.is_empty():
		name_text = CoreInfoDatabase.shared().get_systemname_for_id(systemid)
	if name_text.is_empty():
		name_text = systemid
	# What the player has actually built -- "Mega Drive + Mega-CD + 32X" -- so
	# the nameplate says which machine this is while anything is bolted to it.
	var ids := expansion_ids()
	if not ids.is_empty():
		name_text = ExpansionCatalog.stack_label(name_text, ids)
	return name_text


func _update_name_label() -> void:
	_system_name_label.text = _display_name().to_upper()


## Lay the system name flat on the front face of the model, sized to fit, facing
## one fixed direction (no billboard) — consoles use their +Z face (upright,
## toward the player), handhelds their +Y top face (readable from above). Runs
## deferred so the model meshes + the label's own text mesh have been built.
func _place_name_label() -> void:
	# The nameplate is a printed legend like any other: a detailed shell has the
	# real thing moulded or printed on it, so ours only ever sat on top of it — and
	# so does a primitive that authors its own (see prints_own_name).
	if _model != null and (_model.has_baked_shell() or _model.prints_own_name()):
		_system_name_label.visible = false
		return
	var body := body_aabb()
	if body.size.x <= 0.0 or body.size.y <= 0.0 or body.size.z <= 0.0:
		return
	var lbl := _system_name_label
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.scale = Vector3.ONE
	lbl.rotation = Vector3.ZERO
	var la := lbl.get_aabb()
	if la.size.x <= 0.0 or la.size.y <= 0.0:
		return
	var cx := body.position.x + body.size.x * 0.5
	const EPS := 0.003
	# Placement config, overridable per-model via name_label_placement():
	#   upright  — true = upright on the vertical +Z front face (consoles, and
	#              clamshells whose front is the START-button face); false = flat
	#              on the +Y top face (simple flat handhelds like the Game Boy).
	#   v_center — vertical centre as a fraction of the face height.
	#   h_frac   — label height as a fraction of the face height.
	var cfg := {}
	if _model != null and _model.has_method("name_label_placement"):
		cfg = _model.name_label_placement()
	var upright: bool = cfg.get("upright", not (_model != null and _model.is_handheld()))
	if upright:
		# Vertical front (+Z) face, upright toward the player. Default sits low
		# as a nameplate strip so it clears the controller ports that occupy the
		# centre of a default console's front face; thin faces (a clamshell base)
		# override to centre + fill.
		var v_center: float = cfg.get("v_center", 0.18)
		var h_frac: float = cfg.get("h_frac", 0.26)
		var s: float = min(body.size.x * 0.85 / la.size.x, body.size.y * h_frac / la.size.y)
		lbl.scale = Vector3(s, s, s)
		var cy := body.position.y + body.size.y * v_center
		var front_z := body.position.z + body.size.z
		lbl.position = Vector3(cx, cy, front_z + EPS)
	else:
		# Top (+Y) face, lying flat; sit on the front (+Z) strip below the screen.
		lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		var s: float = min(body.size.x * 0.8 / la.size.x, body.size.z * 0.28 / la.size.y)
		lbl.scale = Vector3(s, s, s)
		var top_y := body.position.y + body.size.y
		var front_z := body.position.z + body.size.z
		lbl.position = Vector3(cx, top_y + EPS, front_z - la.size.y * s * 0.6)


## World-space Y of the top of the hardware body.
##
## Floating panels sit above this rather than at a fixed height off the origin.
## The bodies differ by an order of magnitude — a PC tower is 0.42 m tall and a
## flat console around 0.07 — so no single constant clears both, and one tuned
## for a console lands inside the tower.
##
## Cached in local space and keyed on the model instance, the same way
## SystemAudio._centre_local is: body_aabb walks every mesh in the model and a
## floating panel wants this every frame.
func body_top_y() -> float:
	var inst_id := _model.get_instance_id() if _model != null else 0
	if inst_id != _body_top_model_id:
		_body_top_model_id = inst_id
		var aabb := body_aabb()
		_body_top_local = aabb.end.y if aabb.size.y > 0.0 else 0.0
	# Through the transform, not added to it: the system may be scaled, and the
	# cached figure is in local space.
	return (global_transform * Vector3(0.0, _body_top_local, 0.0)).y


## AABB of the console/handheld body meshes in this system's local space
## (default box or the bespoke model's meshes). Excludes buttons/ports/cables/
## label, which are siblings of the body root. A model may narrow the measured
## body via name_label_body() — e.g. a clamshell returns just its base so the
## name lands on the base's front, not over the raised lid.
## The bounding box of the machine's body, excluding parts a model excludes from
## it (a clamshell's raised lid). Read by SystemAudio to place its emitter.
func body_aabb() -> AABB:
	var meshes: Array[MeshInstance3D] = []
	var src: Node = null
	if _model != null and _model.has_method("name_label_body"):
		src = _model.name_label_body()
	if src != null:
		_collect_meshes(src, meshes)
	else:
		if _system_body.visible:
			meshes.append(_system_body)
		if _model != null:
			_collect_meshes(_model, meshes)
	var inv := global_transform.affine_inverse()
	var out := AABB()
	var have := false
	for mi in meshes:
		if not mi.visible or mi.mesh == null:
			continue
		var a := (inv * mi.global_transform) * mi.get_aabb()
		if not have:
			out = a
			have = true
		else:
			out = out.merge(a)
	return out if have else AABB()


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


func _load_system_model() -> void:
	# One lookup. `model_id` names a row in SystemModelRegistry; empty means "this
	# platform's default", which resolve() handles.
	var row := SystemModelRegistry.resolve(model_id, systemid)
	_model = SystemModelRegistry.instantiate(row)
	# Never leave _model null. Every configure_*/on_*/play_* call below assumes it
	# is valid once _ready() returns, and a null here does not fail at the point of
	# failure — it crashes some unrelated caller much later (e.g. a cartridge insert
	# during a save restore).
	if _model == null:
		push_warning("[RetroSystem] model '%s' failed for systemid='%s' — using the placeholder"
			% [row.get("id", ""), systemid])
		row = SystemModelRegistry.placeholder_row()
		_model = SystemModelRegistry.instantiate(row)
	# Asked of the MODEL, not of its registry id: a row can exist for reasons that
	# have nothing to do with geometry (the Wii's carries core options), and such a
	# model still wears the procedural box. See RetroSystemModel.brings_own_body.
	add_child(_model)
	# Its color, for a console that was asked for in one. After add_child: the
	# model has built its shell by now, and before anything below reads it.
	if not model_variant.is_empty():
		_model.apply_variant(model_variant)
	var is_bespoke := _model.brings_own_body()
	_model.hide_printed_labels()
	if is_bespoke:
		_system_body.hide()
	_model.configure_buttons(_power_button, _reset_button, _eject_button)
	if _model.has_method("set_art_enabled"):
		_model.call("set_art_enabled", cabinet_art_enabled)
	_model.configure_controller_ports(_ports.zones)
	_build_video_channels()
	_model.configure_cartridge_slot(_cartridge_slot)
	# So a unit that mounts AS a cartridge can carry a grab point naming this
	# slot, and seat by its connector instead of by its centre. See
	# RetroExpansion._build_connector.
	_cartridge_slot.add_to_group(ExpansionPort.GROUP_CART_SLOT)
	_wire_push_tray()
	# The serial socket, for the consoles that have one. Placed by the model for
	# the same reason the A/V sockets are: it goes on the back panel, and only
	# the thing that draws the back panel knows where that is.
	_model.build_serial_port(self, systemid)
	_build_builtin_ethernet_port()
	_model.configure_collision(self)
	_model.attach_to_host(self)
	_ports.build_zones()
	_ports.build_usb()
	_captive_pads.spawn(_ports.zones)
	_build_memcard_slots()
	# Consoles with wireless pads grow a SYNC button and the component behind it.
	# Set up here rather than in _ready because `systemid` is an export the spawner
	# may still be filling in when _ready runs; by the time a model is resolved it
	# is definitely set.
	_setup_wireless_pads()
	_disc_tray.build(is_bespoke, _eject_button, _cartridge_slot, _system_body,
		_on_cartridge_inserted, _on_cartridge_removed)
	_build_handheld()
	_build_slot2()
	# Restore a saved lid pose — a clamshell's hinge (DS/3DS/GBA SP) or a console's
	# cartridge-bay flap (the NES). Last, and for every model rather than only the
	# handhelds, because a disc loader and configure_cartridge_slot both re-gate the
	# bay above and either would win over the restored pose.
	if _lid_angle_from_save >= 0.0:
		_model.set_lid_angle_deg(_lid_angle_from_save)
		_disc_tray.restore_open()




## A mod console's row lists its cable sockets for the spawn card, which cannot
## build it to look (ModApi.register_model). Built, it can be looked at: say on
## its mod's page where the two disagree -- a socket the row leaves out is a lead
## the card never offers, and one the console lacks is a lead offered for nothing.
func _check_listed_sockets() -> void:
	var row := SystemModelRegistry.resolve(model_id, systemid)
	var id := str(row.get("id", ""))
	if not row.has("sockets") or SystemModelRegistry.owner_of(id).is_empty():
		return
	var built: Array = []
	# Every lead's socket, A/V and link alike; not the mains inlet, which no row
	# lists because the power cord is the game's own.
	for node: Node in find_children("*", "Port", true, false):
		if node is PowerPort:
			continue
		var c := (node as Port).connector
		if not built.has(c):
			built.append(c)
	SpawnCatalog.note_built_sockets(SystemModelRegistry.owner_of(id), id,
		(row.get("sockets", []) as Array), built)


## One attach point and cable per video channel.
##
## Channel 0 is the scene's own CableAttachPoint; a second screen (the DS,
## the 3DS) gets a Node3D of its own. A machine that describes no channels
## is classic hardware with one unlabelled full-frame output.
func _build_video_channels() -> void:
	# Video-out channels: one attach point + cable per channel. Channel 0 is
	# the scene's CableAttachPoint; extra channels get their own Node3D.
	var described: Array = _model.get_video_channels()
	if described.is_empty():
		described = [{}]        # classic hardware: one unlabelled full-frame output
	_channels.clear()
	for d: Dictionary in described:
		_channels.append(VideoChannel.from_model(d))
	# Channel 0 is the scene's own CableAttachPoint; extra channels get their own.
	_channels[0].attach = _cable_attach_point
	for i in _channels.size():
		if i > 0:
			var pt := Node3D.new()
			pt.name = "CableAttachPoint%d" % (i + 1)
			add_child(pt)
			_channels[i].attach = pt
		_model.configure_cable_attach_for(_channels[i].attach, i)
	# A machine with no display of its own ALWAYS has video out — a TV is the only
	# place its picture can go, so there is no toggle. One that carries its own
	# screen defaults OFF and remembers the saved choice.
	if supports_video_out_toggle():
		video_out_enabled = _video_out_from_save == 1
	else:
		video_out_enabled = true


## The pads this console is wired to (a Famicom's two), built with the machine.
## Handed out so a teardown or a test can ask what came with the machine rather
## than searching the room for it. See SystemCaptivePads.
func captive_controllers() -> Array:
	return _captive_pads.pads()


## Show the memory-card slots this console takes, and let the model place
## the ones that exist.
##
## Cartridge systems keep their battery save on the cartridge and show
## none. The model is configured LAST and only for live slots, because a
## shell may gate its slots behind a door -- the Wii's are under the memory
## flap -- and that gate has to win over this blanket enable.
func _build_memcard_slots() -> void:
	# Memory-card slots only on hardware that takes them; cartridge systems keep
	# their battery save on the cartridge itself. A PlayStation shows one, a
	# GameCube or Wii two.
	#
	# The model is configured LAST and only for the slots that exist, because a
	# shell may gate its slots behind a door — the Wii's are under the memory
	# flap — and that gate has to win over this blanket enable.
	var card_slots := card_slot_count()
	for i in _memcard_slots.size():
		var active := i < card_slots
		_memcard_slots[i].visible = active
		_memcard_slots[i].enabled = active
		var mouth := _system_body.get_node_or_null(
			"MemCardMouth" if i == 0 else "MemCardMouth%d" % (i + 1)) as MeshInstance3D
		if mouth != null:
			mouth.visible = active
		if active:
			_model.configure_memory_card_slot(_memcard_slots[i], i)


## A handheld is its own controller.
##
## Built-in screen, on-device controls, and the HandheldInput component that
## turns the device into port 0. Dual-screen clamshells keep the cabinet's
## START/STOP button, repositioned by their own configure_buttons -- the
## back-edge power knob does not fit them.
func _build_handheld() -> void:
	# Handhelds: built-in screen, on-device controls, and the held-input
	# component that turns the device itself into the port-0 controller.
	# Dual-screen clamshells keep the cabinet START/STOP button (repositioned
	# by their configure_buttons) — the back-edge power knob doesn't fit them.
	if _model.is_handheld():
		var keep_power_btn := _model.has_start_stop_button()
		_power_button.set_active(keep_power_btn)
		_update_power_button_visual()
		_reset_button.set_active(false)
		if _model.has_method("configure_handheld_body"):
			_model.configure_handheld_body(self)
		_model.configure_handheld_controls(self)
		# Two-handed hold, like a game controller: HandheldInput already merges
		# buttons/sticks from both hands (retro_controller pipeline) — the
		# pickable just has to allow the second grab.
		second_hand_grab = SecondHandGrab.SECOND
		_handheld_input = HandheldInput.new()
		_handheld_input.name = "HandheldInput"
		add_child(_handheld_input)
		_handheld_input.setup(self)
		# Route port-0 rumble to the holding hands via the existing path.
		_ports.controllers[0] = _handheld_input
## A handheld routes the trigger and thumbstick into the emulated pad, leaving
## the push-out gesture nothing to bind to. Consoles keep it. Catching either
## back off the laser works regardless. Queried by
## function_pickup._handoff_eligible.
func wants_ray_handoff() -> bool:
	return _handheld_input == null


## Where a hand grips this system, in local space, or null when it has no
## authored grip and should stay where it was grabbed. Only handhelds define
## one — a console keeps the precise grab. Read by GripAnchor via HandheldInput.
func grip_anchor(is_left: bool) -> Variant:
	if _model != null and _model.has_method("get_grip_anchor"):
		return _model.get_grip_anchor(is_left)
	return null


## Where the options panel goes, in world space, when the hardware wants it somewhere other
## than over its top (see RetroSystemModel.options_panel_anchor); null for the default.
func options_panel_anchor(panel_size: Vector2) -> Variant:
	if _model == null:
		return null
	var local: Variant = _model.options_panel_anchor(panel_size)
	return null if local == null else global_transform * (local as Vector3)


## Where notices about this machine go, in world space, when its hardware wants them somewhere
## other than the default (RetroSystemModel.toast_anchor); null for the default.
func toast_anchor_world() -> Variant:
	if _model == null:
		return null
	var local: Variant = _model.toast_anchor()
	if local is Transform3D:
		return global_transform * (local as Transform3D)
	return null if local == null else global_transform * (local as Vector3)


## The cores installed that can run this machine's system, recommended first, as
## [{core_name, label}]. What the System tab's core picker offers.
func core_choices() -> Array:
	var out: Array = []
	var db := CoreInfoDatabase.shared()
	for cn: String in CoreDownloadManager.installed_core_names():
		var sids := CoreInfoDatabase.systemids_of(db.get_by_core_name(cn))
		if core_serves_machine(sids, systemid):
			out.append({"core_name": cn, "label": RomCompat.core_label(cn)})
	return CoreRecommendations.first(systemid, out)


## Whether a core that declares `core_systemids` can run a machine of system `machine_systemid`.
## Usually the machine's own system; but an ARCADE cabinet runs a romset, and MAME and FBNeo
## both run those: the cabinet of one tile can take the other's core (and the older MAME and
## FBAlpha cores some .info files file under the plain `arcade` id).
static func core_serves_machine(core_systemids: Array, machine_systemid: String) -> bool:
	# Both sides through canonical(): a saved cabinet may still say `mame`, the cores say `arcade`,
	# and comparing the raw strings left every arcade core out of the cabinet's list.
	var machine := SystemIds.canonical(machine_systemid)
	for sid: Variant in core_systemids:
		if SystemIds.canonical(str(sid)) == machine:
			return true
	if ArcadeProfiles.is_arcade_system(machine):
		for sid: Variant in core_systemids:
			if ArcadeProfiles.is_arcade_system(str(sid)) or ArcadeProfiles.ARCADE_ALIASES.has(str(sid)):
				return true
	return false


## The core this machine runs when nothing is picked on it: the CORES panel's default.
func default_core_name() -> String:
	var defaults := CoreDefaults.new()
	defaults.setup(CoreDefaults.default_path())
	return defaults.get_default_core(systemid)


## Pick the core THIS machine runs ("" = the default for its system). A running machine
## is switched off first: a core cannot be swapped under a game. The options the panel shows
## are the new core's, and the choice is saved with the room.
func set_core_choice(core: String) -> void:
	if core == core_name:
		return
	print("[RetroSystem] core for '%s': '%s' -> '%s'" % [name, core_name, core])
	if is_powered_on:
		power_off()
	core_name = core
	_options_definitions = {}
	_options_values = {}
	_load_prelaunch_options()
	if _options_panel != null and _options_panel.visible:
		_options_panel.refresh()


## How long the grab has to be held on this machine before it is picked up (HoldToGrab):
## 0 for an ordinary console, a couple of seconds for something that must not be carried
## off by accident.
func grab_hold_seconds() -> float:
	return _model.grab_hold_seconds() if _model != null else 0.0


## Whether this hardware is too big to hold, so the spawn menu stands it on the floor
## rather than putting it in a hand.
func spawns_on_floor() -> bool:
	return _model != null and _model.spawns_on_floor()


## Interior open angle of a clamshell handheld's lid (0 shut … 180 flat), or
## -1 for systems without a lid. Used by ScenePersistence.
func get_lid_angle_deg() -> float:
	return _model.get_lid_angle_deg() if _model != null else -1.0


## The screen light's switch (GBA SP): -1 for a machine with none, else 0 / 1.
func get_screen_light() -> int:
	if _model == null or not _model.has_screen_light():
		return -1
	return 1 if _model.get("screen_light_on") else 0


func set_screen_light(on: bool) -> void:
	if _model != null and _model.has_screen_light():
		_model.set_screen_light(on)


## The machine menu's "Self-Lit Screen" (a handheld whose real LCD had no light):
## -1 for a machine without the switch, else 0 / 1.
func get_screen_glow() -> int:
	if _model == null or not _model.has_screen_glow_switch():
		return -1
	return 1 if _model.get("self_lit") else 0


func set_screen_glow(on: bool) -> void:
	if _model == null or not _model.has_screen_glow_switch():
		print("[RetroSystem] %s: no Self-Lit Screen switch; ignoring %s" % [name, on])
		return
	print("[RetroSystem] %s: Self-Lit Screen %s" % [name, "on" if on else "off"])
	_model.set_screen_glow(on)


## Pose a lid at a saved angle. Public because ScenePersistence has to re-apply it
## after seating a cartridge: an insert swings the bay open on its own.
func set_lid_angle_deg(open_deg: float) -> void:
	if _model != null:
		_model.set_lid_angle_deg(open_deg)
		_disc_tray.restore_open()


## Enable or disable libretro input polling for this system.
## Only the actively-controlled instance should have input enabled.
func set_input_enabled(on: bool) -> void:
	_libretro.SetInputEnabled(on)


## Spatial audio for this machine, lifted out into SystemAudio. Created in
## _init beside the other components, because every machine makes sound.
var _audio: SystemAudio = null


## Hold this machine's sound at a fixed pair of points in the listener's frame.
##
## Part of the same duck-typed contract as set_audio_volume, so the desktop
## fullscreen overlay can say this to a machine and to a deck without knowing
## which it has.
func set_audio_head_lock(left: Vector3, right: Vector3) -> void:
	if _audio != null:
		_audio.set_head_lock(left, right)
		_audio.update_position()


func clear_audio_head_lock() -> void:
	if _audio != null:
		_audio.clear_head_lock()
		_audio.update_position()


## Set the audio volume for the running libretro instance (0.0 = silent, 1.0 = 100%).
##
## Stays on RetroSystem rather than moving to the component with its body: it is
## part of the contract a set calls on whatever is plugged into it, by NAME, and
## a VCR and a DVD player answer the same names. AvSourceContract is that list.
func set_audio_volume(volume: float) -> void:
	_audio.set_volume(volume)


## Part of the TV contract (AvSourceContract): the set's mono switch.
func set_audio_channel_mode(mode: SpatialAudioEmitter.ChannelMode) -> void:
	_audio.set_channel_mode(mode)


## Part of the TV contract: where the set is sending its sound, which decides
## whether this machine's stereo pair is decoded into six placed channels.
## Returns whether this machine is really decoding.
func set_audio_out_mode(mode: int) -> bool:
	return _audio.set_audio_out_mode(mode)


## Part of the sink contract: which matrix decoder the amplifier carrying this
## machine's sound is switched to — SurroundAmp.DecodeMode. Duck-typed like the
## two above, so it stays here.
func set_surround_mode(mode: int) -> void:
	_audio.set_surround_mode(mode)


## The TV this system's sound should come out of: whichever channel is plugged
## in, channel 0 first (a dual-screen handheld can be wired up by its BOTTOM
## cable alone). Null when nothing is connected.
func _audio_tv() -> Node3D:
	# A ports console's sound goes wherever its audio cord went, which is not
	# necessarily where its picture went — or anywhere at all.
	# So does a handheld's, while its headphone jack is cabled to something.
	if not _av_ports.is_empty() or _av.phones_carry_sound():
		var live: bool = _av_speaker_l >= 0 or _av_speaker_r >= 0
		return _av_tv if live and is_instance_valid(_av_tv) else null
	for chan: VideoChannel in _channels:
		if is_instance_valid(chan.tv):
			return chan.tv
	return null


## Everything SystemAudio needs to know about the cabling, in one answer.
##
## The component is deliberately given this rather than _av_ports and
## _av_speaker_l/_r themselves. Which set the sound reaches, and which of that
## set's speakers each channel lands on, is decided in SystemAvPorts.apply_feed as cords
## are seated and pulled; a second reader of those three fields would be a
## second owner of the routing, and the gains cached against them would go stale
## in a way nothing here could see.
##
## "socketed" is the hardware-has-phono-sockets test, not a
## something-is-plugged-in test: it is what separates a console that is silent
## until a cord reaches a set from a handheld whose captive lead always carries
## its own speaker.
## Where this machine's sound goes: its speakers plus the set it reaches, if
## any. Read by SystemAudio, which this node owns and drives.
func audio_route() -> Dictionary:
	var route := audio_speakers()
	route["tv"] = _audio_tv()
	return route


## The speaker half of audio_route, without resolving the sink. Separate on
## purpose: resolving the set is the expensive half, and two of SystemAudio's
## three callers do not need it.
## The speaker half of audio_route, without resolving the sink.
##
## Split out because the gain path wants it every frame and does not care which
## set the sound is going to — and because SystemAvPorts.apply_feed has to invalidate the
## gain cache one line BEFORE it assigns _av_tv, where _audio_tv() would still
## answer with the old sink.
func audio_speakers() -> Dictionary:
	return {
		"socketed": not _av_ports.is_empty() or _av.phones_carry_sound(),
		"left": _av_speaker_l,
		"right": _av_speaker_r,
	}


## The core's picture. The ONE way anything gets at it — the television that shows
## this machine reads it here rather than being painted into, and so does the
## model's own panel.
##
## Null before the first frame and while nothing is running, and a different object
## after a resolution change, so callers read it per frame instead of caching it.
func get_video_texture() -> Texture2D:
	return _libretro.GetVideoTexture() if _libretro != null else null


## The mesh the core paints, which is now only ever this machine's OWN screen: a
## handheld's built-in LCD, or the hidden proxy a dual-screen or stereo model
## samples. Null for a console, which has no panel of its own.
##
## A television is never named here any more. It reads get_video_texture() and
## paints its own glass, so the picture no longer depends on which set was
## connected first, and a machine feeding two sets is not a special case.
func _screen_target() -> MeshInstance3D:
	return _model.get_builtin_screen() if _model else null


## Is a VIDEO cord from this machine actually reaching `tv`?
##
## Asked by a set before it paints, because being wired to a machine is not the
## same as being sent its picture. A phono plug fits any phono socket, so an
## AUDIO cord in the yellow input is ordinary hardware — and the set still files
## the machine on that input, deliberately, so the sound routes. What it must not
## do is take that as a picture.
##
## Read off the video channels rather than recomputed, because that is the one
## record both routes keep: a captive lead sets it through on_tv_connected, a
## composite cable through SystemAvPorts.apply_feed, and a walk of the cable graph would
## see only the second — captive leads carry no CompositeCable and are not in it.
##
## Per set, not per machine. A tower with its picture on a monitor and its sound
## on a second television is wired to both, and only one of them has the picture.
func sends_video_to(tv: Node3D) -> bool:
	if not is_instance_valid(tv):
		return false
	for chan: VideoChannel in _channels:
		if chan.tv == tv:
			return true
	return false


## True while a video-out cable has taken the picture to a television. The model
## asks, and darkens its own panel: a handheld's picture MOVES to the set rather
## than being mirrored (Super Game Boy), and that is the model's own glass to
## decide about.
func picture_on_tv() -> bool:
	return _channels.size() == 1 and is_instance_valid(connected_tv)


## Somewhere for the picture to go: this machine's own panel, or a television
## cabled to it. Powering on with neither is the "no display" fault.
func _has_display() -> bool:
	if _screen_target() != null:
		return true
	for chan: VideoChannel in _channels:
		if is_instance_valid(chan.tv):
			return true
	return false


## A machine wired to nothing is silent. Used to fall out of SetScreenMesh(null) —
## no mesh, no sound — which only worked while a picture reached a set by being
## painted onto it.
func _apply_audio_playing() -> void:
	if _libretro != null:
		_libretro.SetAudioPlaying(_has_display())


## True when the running core outputs a side-by-side stereo frame (Virtual Boy);
## a connected TV uses this to split the picture per-eye. Read by RetroTV.
func is_stereo_output() -> bool:
	return _model != null and _model.is_stereo_side_by_side()


# set_screen_enabled, _last_screen_enabled and _bound_screen_target are gone with
# the push. Which input a set is showing decided where the CORE rendered, so it had
# to be latched for a machine that was off, stated in both directions, and applied
# in an order that did not clobber the incoming picture. None of that is a question
# any more: the core renders to its own texture, and the set samples it or does not.


## Which channel this console's own RF switch puts it on, or -1 if it has none.
##
## Asked by a television showing its aerial input: an RF-fed console only appears
## when the set is tuned to the channel the console is modulating on. The switch is
## the MODEL's — an NES wears one, a Wii does not — so this only forwards.
func get_rf_channel() -> int:
	return _model.get_rf_channel() if _model != null else -1


## The model's channel switch moved. Tell whichever set is showing us on its aerial
## input, because that switch is half of what decides whether there is a picture and
## nothing else would prompt the set to re-read it.
func on_rf_channel_changed() -> void:
	for chan: VideoChannel in _channels:
		var tv := _live(chan.tv) as RetroTV
		if tv != null:
			tv.on_rf_channel_changed()
	if is_instance_valid(_av.video_tv):
		_av.video_tv.on_rf_channel_changed()


## Called by the TV when one of this system's plugs connects. `plug` tells us
## which video-out channel landed (null = classic single-cable path).
func on_tv_connected(tv: RetroTV, plug: CablePlug = null) -> void:
	var ch := plug.channel if plug != null else 0
	if ch < 0 or ch >= _channels.size():
		ch = 0
	_channels[ch].tv = tv
	if ch == 0:
		connected_tv = tv
	_video_lead.seat_audio_pair(ch, tv)
	_apply_audio_playing()
	if _channels.size() > 1:
		# The set samples our picture through get_video_stage; a touch channel
		# additionally turns the TV's glass into the touch screen.
		if _channels[ch].touch:
			_remove_touch_surface(ch)
			var surf := TVTouchSurface.new()
			surf.setup(self, _channels[ch].rect, tv.get_screen_mesh())
			tv.get_screen_mesh().add_child(surf)
			_channels[ch].touch_surface = surf
		return


## Called by the TV when a plug disconnects. Handhelds take the picture back
## onto their built-in LCD; consoles go dark.
func on_tv_disconnected(plug: CablePlug = null) -> void:
	var ch := plug.channel if plug != null else 0
	if ch < 0 or ch >= _channels.size():
		ch = 0
	var tv := _live(_channels[ch].tv) as RetroTV
	_channels[ch].tv = null
	if ch == 0:
		connected_tv = null
	_video_lead.release_audio_pair(ch, tv)
	_apply_audio_playing()
	if _channels.size() > 1:
		_remove_touch_surface(ch)
		return


## The TV connected to a given video-out channel, or null (persistence).
func get_channel_tv(ch: int) -> RetroTV:
	if ch < 0 or ch >= _channels.size():
		return null
	return _live(_channels[ch].tv) as RetroTV


## Which of that TV's four composite inputs channel `ch`'s lead is sitting in
## (persistence). Asked of the television rather than tracked here: the socket is
## its property, and a player can move the plug from one input to another without
## this system hearing anything about it.
func get_channel_tv_input(ch: int) -> int:
	if ch < 0 or ch >= _channels.size() or ch >= _channels.size():
		return 0
	var tv := _live(_channels[ch].tv) as RetroTV
	var plug := _live(_channels[ch].plug) as CablePlug
	if tv == null or plug == null:
		return 0
	return tv.input_holding(plug)


## How many video-out cables this system has (persistence).
func get_channel_count() -> int:
	return _channels.size()


func _remove_touch_surface(ch: int) -> void:
	var surf: TVTouchSurface = _channels[ch].touch_surface
	if is_instance_valid(surf):
		surf.queue_free()
	_channels[ch].touch_surface = null


## Which window of this machine's picture a given television should show, and the
## shader that cuts it out — dual-screen hardware only, where one composite frame
## carries the top panel above the bottom and each set is cabled to one of them.
##
## Replaces _update_tv_mirrors, which pushed a material onto every connected set
## every frame and had to be told when to stop. The set asks, so a set showing
## another input simply does not ask.
func get_video_stage(tv: Node) -> Dictionary:
	if _channels.size() <= 1:
		return {}
	var ch := -1
	for i in _channels.size():
		if _channels[i].tv == tv:
			ch = i
			break
	if ch < 0:
		return {}
	var r := _channels[ch].rect
	return {
		"shader": SCREEN_WINDOW_SHADER,
		"params": {
			"source_rect": Vector4(r.position.x, r.position.y, r.size.x, r.size.y),
			"eye_shift": _channels[ch].eye_shift,
		},
	}


## Read a slot that may be holding a freed instance.
##
## The Variant argument and return are the point: assigning a previously freed
## instance to ANY Object-typed variable — a local, or a function parameter —
## throws before is_instance_valid() gets a chance to guard it. Cables and TVs
## are freed out from under these arrays whenever a room is torn down or a slot
## restore rebuilds the set across frames.
static func _live(v: Variant) -> Object:
	return v if is_instance_valid(v) else null


## A freed system must not leave its touch surfaces on TVs. Its picture needs no
## cleaning up any more: a set that asks a freed machine for one stops getting it.
##
## It must also let its core go. Only ScenePersistence.clear_scene used to power
## machines off, so every other way one leaves — the trash can, a bare queue_free,
## a room torn down around it — skipped _stop_core() entirely: the achievements
## session was never released, so no other cabinet could claim it, and a controller
## rumbling at that moment kept rumbling. The C++ Libretro::_exit_tree still stops
## the emulation thread, which is why this was invisible; none of the GDScript-side
## release is its job. Safe here because a system is never reparented — a grab is
## driven, not a re-hang — so leaving the tree always means going away.
func _exit_tree() -> void:
	if is_powered_on:
		power_off()
	_captive_pads.free_pads()
	_release_cache_protection()
	for i in _channels.size():
		_remove_touch_surface(i)
	_video_lead.free_cables()
	super._exit_tree()


# --- Cable management ---

## Called by a CompositeCable whenever a plug is seated or pulled anywhere on it:
## re-resolve where the picture and the sound go (SystemAvPorts).
func on_av_topology_changed(_reported: Array) -> void:
	_av.on_topology_changed()
	# A cabinet's composite INPUT sockets (ArcadeAvInModule) answer to this machine: tell its model a cord moved.
	if _model != null and _model.has_method("on_av_in_changed"):
		_model.call("on_av_in_changed")
		# A console cabled to the cabinet owns its screen: the game on show gives way and the cabinet goes dark.
		if attracting and bool(_model.call("external_picture_active")):
			power_off()


## True when this system offers the Enable Video Out toggle: the machine has a
## display of its own, so running a lead to a television is a choice.
##
## Asked of the SCREEN rather than of is_handheld(), because the two are not the
## same question. The Virtual Boy is a tabletop console by every other measure —
## it takes a controller and it has no battery — but the picture is already in
## front of your eyes, and a lead permanently hanging off the back of it is the
## one thing on that machine nobody would want.
func supports_video_out_toggle() -> bool:
	if _model == null:
		return false
	return _model.is_handheld() or _model.get_builtin_screen() != null


## Only a cabinet has art to take off (the System tab shows the row for it alone).
func supports_cabinet_art_toggle() -> bool:
	return _model != null and _model.has_method("set_art_enabled")


func set_cabinet_art_enabled(on: bool) -> void:
	cabinet_art_enabled = on
	if supports_cabinet_art_toggle():
		_model.call("set_art_enabled", on)


## The System tab's Attract Mode row: follow the global option, or force it on or off for this cabinet.
## What is already showing changes at once: a cabinet that is on gives the game up (or starts showing it).
func set_attract_override(mode: int) -> void:
	attract_override = clampi(mode, ArcadeAttract.OVERRIDE_FOLLOW, ArcadeAttract.OVERRIDE_OFF)
	if attracting and not attract_applies():
		power_off()
		power_on()
	request_attract_media()
	_update_power_button_visual()


## Toggle floating: on = freeze right where it is (or where it's next dropped);
## off = normal physics resumes (unless currently held or being restored).
func set_ignore_gravity(on: bool) -> void:
	if on == ignore_gravity:
		return
	ignore_gravity = on
	if on:
		_freeze_in_place()
	elif not is_picked_up():
		freeze = false
		sleeping = false
	NetworkManager.report_event(NetEvents.Event.EV_SYS_GRAVITY, {"sys": self, "on": on})


func _on_system_dropped(_pickable: Node3D) -> void:
	if ignore_gravity:
		# Deferred: let the release finish (velocities applied) before parking.
		_freeze_in_place.call_deferred()


func _freeze_in_place() -> void:
	if ignore_gravity and not is_picked_up():
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true


## Show/hide+park the video-out cables per the video_out_enabled toggle.
## Disabling first unplugs any connected TV (so no picture lingers), then
## hides the whole cable and freezes it out of the simulation.
func set_video_out_enabled(on: bool) -> void:
	if not supports_video_out_toggle():
		on = true   # consoles are always on, whatever a save/peer says
	if on == video_out_enabled:
		return
	video_out_enabled = on
	_video_lead.apply_video_out()
	NetworkManager.report_event(NetEvents.Event.EV_SYS_VIDEO_OUT, {"sys": self, "on": on})


func _process(_delta: float) -> void:
	# Tilt-sensor feed (handhelds): the device's physical orientation IS the
	# accelerometer for tilt carts (WarioWare Twisted, Kirby Tilt 'n' Tumble).
	# libretro frame: X = screen-right, Y = screen-top, Z = out of the screen;
	# at rest flat (screen up) = (0,0,1) g. Our shell: screen normal = +Y,
	# screen-top = -Z, screen-right = +X. During netplay the tilt rides the
	# deterministic frame schedule (aux block, supplied by the port-0 owner)
	# instead of feeding the core directly.
	if is_powered_on and _model != null and _model.is_handheld():
		var a := global_transform.basis.orthonormalized().transposed() * Vector3.UP
		if not NetworkManager.netplay_set_aux_sensor(self, 0, 0,
				int(a.x * 1000.0), int(-a.z * 1000.0), int(a.y * 1000.0)):
			_libretro.SetSensorAccel(0, a.x, -a.z, a.y)
	_disc_tray.update_spin(_delta)
	_audio.ensure_bound()
	if _ports.ensure_devices_bound():
		# And the storages that wait for a frame: the Dreamcast's VMU slots, which
		# flycast reads only once `first_startup` is false (cleared at the end of
		# its first retro_run -- nudged earlier, the card never appears), and the
		# cards written back while the game runs rather than only at power-off, so
		# a hard kill does not lose what a game put on one. See VmuStorage,
		# XboxStorage.
		for storage: ConsoleStorage in _storages:
			storage.after_first_frame()
	# Every fourth frame, staggered across machines: the route is a dictionary
	# and two dynamic lookups per call, and a room holds eight of these. A
	# carried set's sound trails it by 55 ms at most, under what the ear places.
	if (Engine.get_process_frames() + get_instance_id()) % 4 == 0:
		_audio.update_position()
	# Nothing left to do until something switches on again. Tested here rather
	# than per frame from outside: a room holds a lot of these, most of them off.
	if not is_powered_on and _disc_tray.spin <= 0.0:
		set_process(false)


## Touch-screen feed (dual-screen handhelds): uv is a point in the COMPOSITE
## core framebuffer (both screens), 0..1 — the model converts a poke on its
## bottom screen through its UV window. RETRO_DEVICE_POINTER is how melonDS/
## citra take touch input. During netplay the touch rides the deterministic
## frame schedule (aux block, supplied by the port-0 owner).
func feed_touch(uv: Vector2, pressed: bool) -> void:
	if _libretro == null or not is_powered_on:
		return
	var px := int(clampf(uv.x, 0.0, 1.0) * 65534.0) - 32767
	var py := int(clampf(uv.y, 0.0, 1.0) * 65534.0) - 32767
	if not NetworkManager.netplay_set_aux_pointer(self, 0, 0, px, py, pressed):
		_libretro.SetPointerState(0, px, py, pressed)


func _physics_process(_delta: float) -> void:
	if not video_out_enabled:
		return   # cables hidden and frozen — nothing to clamp
	_video_lead.clamp_leads()


# ── attract: a cabinet that is on shows its game instead of running it ─────────

## Does switching this machine on show its game rather than start it? Only an arcade cabinet, with the
## option on (its own override, else the global pref), a game in its bay, no console cabled to its A/V
## input and no netplay session (ArcadeAttract.wanted).
func attract_applies() -> bool:
	if not _is_cabinet_model():
		return false
	var has_game := _snapped_cartridge != null and not rom_path.is_empty()
	return ArcadeAttract.wanted(AppPrefs.arcade_attract_mode, attract_override, has_game,
		bool(_model.call("external_picture_active")), NetworkManager.is_active())


## An arcade cabinet's model (by what it answers: the class itself would make this script and its model
## need each other to compile).
func _is_cabinet_model() -> bool:
	return _model != null and _model.has_method("attract_picture_active")


## Is the power button a SWITCH? An arcade cabinet that would show its game when switched on (attract_applies):
## the button is a latched ON / OFF and its state is saved in the room (`attract_on`).
func power_is_switch() -> bool:
	return attract_applies()


## What a room should remember of this cabinet's switch: it is on, whether it is only showing its game or a
## player has started it. Only for a cabinet whose button is a switch.
func attract_switched_on() -> bool:
	return power_is_switch() and (attracting or is_powered_on)


## A saved room had this cabinet switched on: it comes on again as soon as its board is in (the board can
## arrive after this cabinet's own entry, from its bay's). begin_ marks it, the board's arrival tries it,
## and finish_ (the end of the restore) gives up on a cabinet that never got one.
var _attract_restore := false


func begin_attract_restore() -> void:
	_attract_restore = true


func finish_attract_restore() -> void:
	_try_attract_restore()
	_attract_restore = false


func _try_attract_restore() -> void:
	if not _attract_restore or attracting or is_powered_on or not attract_applies():
		return
	_attract_restore = false
	power_on()


## The option, the cabinet's own override or a board coming or going decides whether the button is a
## switch: redraw it (the Options toggle reaches every machine through the `spawned` group).
func refresh_power_switch() -> void:
	_update_power_button_visual()


func _enter_attract() -> void:
	print("[RetroSystem] Attract: showing %s" % rom_path.get_file())
	if _attract == null:
		_attract = ArcadeAttract.new()
		_attract.name = "ArcadeAttract"
		add_child(_attract)
	attracting = true
	_attract.start(self)
	_update_power_button_visual()
	_model.on_power_on()
	request_attract_media()


## Stop showing the game (power button, board out, a console cabled in) and go dark. No core to stop.
func _leave_attract() -> void:
	attracting = false
	if _attract != null:
		_attract.stop()
	_update_power_button_visual()
	_model.on_power_off()


## Somebody used the cabinet while it only showed its game: a coin, a panel pressed, a gun or pad in hand
## (ArcadeInput.first_use). The game starts for real, and the coin that asked for it counts in it.
func attract_first_use(kind: StringName) -> void:
	if not attracting:
		return
	print("[RetroSystem] Attract: %s -- starting %s" % [kind, rom_path.get_file()])
	_leave_attract()
	_attract_released = true
	power_on()
	_attract_released = false


## Nobody has been at the cabinet for ArcadeAttract.IDLE_SECONDS: the core goes away and the game is shown
## again (libretro tells us nothing of game over, so idleness is what there is).
func attract_return() -> void:
	if not is_powered_on or not attract_session:
		return
	print("[RetroSystem] Attract: nobody at the cabinet -- back to the attract")
	power_off()
	if attract_applies():
		_enter_attract()


## Somebody coined up or pressed something: the idle clock starts over.
func attract_touch() -> void:
	if _attract != null:
		_attract.touch()


## What the glass shows while attracting, or null.
func attract_picture() -> Texture2D:
	return _attract.picture() if attracting and _attract != null else null


func attract_picture_aspect() -> float:
	return _attract.picture_aspect() if attracting and _attract != null else 0.0


## The attract's video and title come from the scraper, and only when this cabinet would use them and
## the game has no video yet: one scrape per game, once, not a library's worth (arcade.md "Attract").
func request_attract_media() -> void:
	if not _is_cabinet_model() or _snapped_cartridge == null or rom_path.is_empty():
		return
	if not ArcadeAttract.effective_pref(AppPrefs.arcade_attract_mode, attract_override):
		return
	var board_sys := str(_snapped_cartridge.get("systemid")) if "systemid" in _snapped_cartridge else ""
	if board_sys.is_empty():
		board_sys = systemid
	if not ArcadeProfiles.is_cabinet_system(board_sys):
		return
	if ArcadeAttract.has_video(board_sys, rom_path):
		return
	# Left where the menu will find it if it is not up yet; the menu takes it off the list when it asks.
	ArcadeAttract.pending_media[rom_path] = board_sys
	if get_tree().get_nodes_in_group(&"attract_media_listener").is_empty():
		print("[Attract] %s has no video yet; the scraper is not up, so it waits" % rom_path.get_file())
		return
	get_tree().call_group(&"attract_media_listener", &"request_attract_media", rom_path, board_sys)


## Power on: start this system's libretro core, HERE and nowhere else.
##
## Which power method to call:
##   toggle_power()   the power BUTTON. Netplay-aware: in a session it starts or
##                    stops lockstep on every peer, or sends a client's intent to
##                    the host. Everything a player's hand or a menu does goes
##                    through this (or set_power, which lands here).
##   set_power(on)    the menu's switch: moves a handheld's slide, else toggles.
##   power_on()       LOCAL primitive: boots this machine's core with no session
##   power_off()      bookkeeping at all. For code that is already the authority
##                    on this one machine -- a save-state load switching it on
##                    first, a room being cleared, the trash taking it, a disc
##                    restart -- never for a player's intent, which would bypass
##                    the session and leave peers on a different machine.
##   net_start_core / net_stop_core   what NetplaySession drives on every peer.
func power_on() -> void:
	if is_powered_on or attracting:
		return
	# A use of the cabinet (a coin, a pressed panel, a gun in hand) asked for the real game this time.
	var released := _attract_released
	_attract_released = false
	if not released and attract_applies():
		_enter_attract()
		return
	attract_session = released
	# A console with no TV connected still powers on and runs — the core renders to
	# its own texture regardless, and a set plugged in later simply starts sampling
	# it. Handhelds always have a panel, so they never take this branch.
	if not _has_display():
		# Name the actual state. "No display" covers two very different faults and
		# the loud one — audio cords in, video cord out — looks identical to a
		# console that is simply broken, because you can hear it running.
		if is_instance_valid(_av_tv):
			print("[RetroSystem] Powering on with SOUND but no PICTURE: audio reaches %s, "
				% _av_tv.name + "no video cord is linked. Check the yellow lead at BOTH ends.")
		else:
			print("[RetroSystem] Powering on with no display connected (connect a TV to see output)")
	# Through the same resolvers as every other path — the options panel, netplay,
	# the SRAM paths and achievements all ask these two, and the power button
	# answering them itself is how it would end up running a different core.
	# Resolved BEFORE the empty-slot check, which cannot be answered without
	# knowing the core: whether a machine shows its BIOS is a fact about the core
	# and the files in its system directory, not about the systemid.
	# Before the core is resolved and before the verdict is taken: an assembled
	# machine boots from the stack, not from the console's own slot, and both of
	# those read rom_path.
	rom_path = _disc_tray.boot_disc_path()
	_disc_tray.left_running = false
	var stack_spec := _expansion_launch.apply_expansion_launch()
	var resolved_core := _resolve_core()
	var resolved_dir := _resolve_dir()

	# Nothing in the slot, and this core will start anyway. Named because it is
	# asked four times across this function and the answer CHANGES half way
	# through: the verdict below may substitute blank media into rom_path, after
	# which rom_path.is_empty() is false for a machine that is still, as far as
	# the player is concerned, empty. See `still_empty` past that point.
	var slot_empty := rom_path.is_empty() \
		and BiosBoot.can_boot_empty(resolved_core, systemid)

	# Only when the slot is empty: empty_media_for CREATES the blank image, and
	# a machine with a game in it must not leave one behind.
	var blank := ""
	if slot_empty:
		blank = BiosBoot.empty_media_for(resolved_core, systemid)

	var missing := BiosBoot.missing_required(resolved_core)
	# And what the game needs that the core's .info calls optional: a Sega CD disc
	# cannot start without a Sega CD BIOS, though the same core runs cartridges.
	missing.append_array(BiosBoot.missing_for_media(resolved_core, _media_systemid()))
	# And what a unit in the stack runs: the spawn menu offers every unit with or
	# without its file, so this is where a missing one is said.
	missing.append_array(_expansion_launch.missing_firmware(stack_spec))
	var verdict := power_on_verdict(resolved_core, systemid, rom_path,
		missing, blank,
		slot_empty and BiosBoot.boots_with_no_content(resolved_core, systemid),
		resolved_core.is_empty()
			or not CoreDownloadManager.installed_core_lib(resolved_core).is_empty(),
		_disc_tray.open_over_disc())
	if not bool(verdict["start"]):
		push_error("[RetroSystem] Cannot power on - %s" % verdict["log"])
		# Over the hardware rather than the picture: every one of these is a
		# state of the console, and half the machines they fire on have no set
		# connected to show anything on.
		var refusal_toast := _machine_toast()
		if refusal_toast != null:
			refusal_toast.show_notice(_display_name(), str(verdict["title"]),
				str(verdict["description"]), Color(verdict["accent"]))
		return

	# One machine at a time on a shared save folder or file: a Sega CD, a Saturn
	# with a Backup RAM Cartridge, a 3DO (Opera's one NVRAM file), an Xbox (xemu
	# is one machine per process, writing one hard disk image).
	if _refused_by_busy_storage(resolved_core):
		return

	# May be empty media: a machine with nothing in it whose BIOS is installed is
	# handed a blank disc, which is what a console with a closed empty tray is.
	rom_path = str(verdict["rom"])

	# The same question as slot_empty, asked again on the OTHER side of that
	# substitution, which is why it cannot reuse it: a machine handed blank media
	# now has a non-empty rom_path while still being a console with nothing in
	# its tray. Both readers below want this one, not the one above.
	var still_empty := rom_path.is_empty() \
		and BiosBoot.can_boot_empty(resolved_core, systemid)

	print("[RetroSystem] Powering on: core=%s dir=%s rom=%s" % [resolved_core, resolved_dir, rom_path])

	# The core is handed rom_path verbatim: nothing downstream unpacks an archive
	# the core cannot read, so without this the machine sits powered on and black.
	if not _resolve_content(resolved_core):
		return

	# With the override on the BIOS options are the player's, so they are written
	# once as a default and then left alone -- a machine still boots to its BIOS
	# the first time, and a change made afterwards stands. With it off they are
	# pinned instead, by _apply_forced_core_options below, which rewrites them
	# every launch. Never both: seed_values records the key as seeded for ever,
	# and doing that behind a pin would silently disarm the override.
	if AppPrefs.bios_boot_override:
		CoreOptionsStore.seed_values(resolved_dir, resolved_core,
			BiosBoot.pinned_options(resolved_core, systemid, still_empty))
	# Before the forced options: the cartridge size they pin is read off an image
	# that staging may only now have created.
	for storage: ConsoleStorage in _storages:
		storage.stage_for_run(resolved_dir, resolved_core)
	_apply_forced_core_options(resolved_dir, resolved_core)
	# Leftovers from an earlier run that would crash the boot just pinned (a DS
	# core's built-in-firmware Wi-Fi profile, merged into the real firmware).
	BiosBoot.retire_stale_files(resolved_core, systemid)
	_ports.persist_pak_options(resolved_dir, resolved_core)
	for storage: ConsoleStorage in _storages:
		storage.stage_late(resolved_dir, resolved_core)
	AppPrefs.apply_hw_render_for(resolved_core)
	_libretro.SetSramPath(_memcards.sram_path_for_run(resolved_core))
	_libretro.SetRtcPath(_memcards.rtc_path_for_run(resolved_core))
	# Before StartContent: identification happens as the core comes up, so the
	# claim has to be in place by then. Returns false when another cabinet already
	# holds the session, nobody is signed in, or the system has no RA console —
	# all of which just mean this machine runs without achievements.
	_claim_achievements_session()
	protect_active_rom()
	# A machine starting with NOTHING in it needs the core handed a null game
	# info rather than an empty path, and most cores do not survive that -- six of
	# sixteen surveyed took the process down. It is switched on only for the
	# machines measured to want it, and off again straight after so the next
	# machine to start is not handed a setting it never asked for.
	var no_content := still_empty \
		and BiosBoot.boots_with_no_content(resolved_core, systemid)
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", true)
	_ports.bind_all_pak_storage()
	# An assembled machine goes over as one piece if the core will take it that
	# way; only if it will not do we fall back to a single path and say what the
	# drive is about to lose.
	if not _expansion_launch.start_subsystem_content(resolved_dir, resolved_core, stack_spec):
		_expansion_launch.warn_missing_sidecar(stack_spec)
		_libretro.StartContent(resolved_dir, resolved_core, rom_path)
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", false)
	_disc_tray.started_without_content = no_content
	_disc_tray.bios_run = no_content or BiosBoot.is_empty_media(rom_path)
	_after_core_started()
	# Started with the lid up: the core's drive is opened to match, so shutting
	# the lid is a whole tray cycle rather than a swap under a closed tray.
	if _disc_tray.open:
		_disc_tray.sync_core()


## Refuse the power-on when a storage says another machine holds what this run
## needs, on a card over the hardware. True when refused. The first storage to
## object wins, in ConsoleStorage order, so the card names one reason.
func _refused_by_busy_storage(core: String) -> bool:
	for storage: ConsoleStorage in _storages:
		var busy := storage.busy_elsewhere(core)
		if busy.is_empty():
			continue
		push_error("[RetroSystem] Cannot power on - %s" % busy)
		var busy_toast := _machine_toast()
		if busy_toast != null:
			busy_toast.show_notice(_display_name(), storage.busy_title(), busy,
				Color(1.0, 0.72, 0.2))
		return true
	return false


## Everything a machine does once its core is up, whichever way it was started.
##
## Written once because the netplay start used to be an abridged copy, and what
## the abridgement dropped was invisible until you looked for it: the power
## button kept saying START on a machine that was running, and the core was never
## asked whether it has disk control, so a netplay disc swap had nothing to go on.
func _after_core_started() -> void:
	# A machine with nowhere to send its picture is not heard either.
	_apply_audio_playing()
	# A fresh run re-asks which backend came up — that is decided per core start,
	# and this first attempt is expected to find neither.
	_ports.devices_settled = false
	_audio.rebind()
	is_powered_on = true
	set_process(true)
	_memcards.start_card_polling()
	_update_power_button_visual()
	_model.on_power_on()
	# Learn whether this core exposes the disk-control interface (multi-disc
	# swap). The emulation thread is only starting here, so this queues and is
	# answered once the core is up.
	_libretro.RequestDiskInfo()
	# And re-make whatever link cable this machine is on.
	#
	# Stopping a core takes its endpoints out of LinkCoordinator, and that cuts
	# the whole bus rather than idling one seat -- so after a machine is
	# switched off the lead still in its socket is joined to nothing, and the
	# console at the other end is left loose. Nothing puts it back by itself: a
	# cable re-resolves when a PLUG MOVES, and powering a machine on moves no
	# plug. Measured on a Quest, a GameCube and a Game Boy Advance on a link
	# lead: the first power-on joined (bus 0 [P1 on, P2 on]), switching the
	# handheld off left "nothing cabled, loose: m1:0 on", and every power-on
	# after that re-attached under fresh endpoint ids and stayed loose. Four
	# Swords never saw the handheld again until the lead was pulled and
	# re-seated by hand.
	net_refresh_link_cables()


## Should the power button do anything, and with what in the slot?
##
## Static and pure so the decision can be asserted without a core, a model or a
## scene — power_on() itself dereferences all three, which is why the rules used
## to be untestable. The two facts that need the disk are looked up by the
## caller and passed in: `missing` is BiosBoot.missing_required(), and `blank` is
## the path to an empty image when this machine can show its BIOS with an empty
## slot, "" otherwise. Returns
##   {start: bool, rom: String, log: String, title, description, accent}
## with the card fields filled in whenever `start` is false.
##
## Three refusals and one substitution, in the order they can be answered:
##   * no core resolved — used to be a bare push_error with nothing shown at all
##   * a required BIOS is missing — used to be a black screen and no explanation
##   * an empty slot the machine cannot boot from — the long-standing card, or,
##     when `open_over_disc` names a "lid" or "tray" standing open over a disc,
##     a card saying to close it
##   * an empty slot it CAN boot from — hand it a blank disc and start
static func power_on_verdict(core_id: String, sysid: String, rom: String,
		missing: Array[Dictionary], blank: String, empty_ok := false,
		core_installed := true, open_over_disc := "") -> Dictionary:
	var waiting := AchievementToast.ACCENT_WAITING
	var fault := AchievementToast.ACCENT_NOTICE

	if core_id.is_empty():
		return {
			"start": false, "rom": "",
			"log": "no core set and no default for systemid '%s'" % sysid,
			"title": "No core installed",
			"description": "Pick one in OPTIONS > Cores, then switch it on.",
			"accent": waiting,
		}

	# Named but not on disk, which is a different failure from having no core at
	# all and used to be indistinguishable from a broken one: the machine went
	# through every check, printed that it was powering on, and then sat black.
	#
	# An assembled machine is how a player meets this without ever having chosen a
	# core. A stack pins the core its COMBINATION needs, which is often not the
	# console's own -- a Super Famicom runs on snes9x until a Super Game Boy goes
	# into it, and then it needs bsnes, because snes9x cannot do that at any
	# price. So the core named here can be one the player has never been asked
	# about, and saying which one is missing is the whole of the help.
	#
	# Defaulted true so the check stays out of the pure verdict logic: this
	# function is a table of decisions and reads no disk, and its cases are tested
	# by calling it directly.
	if not core_installed:
		return {
			"start": false, "rom": rom,
			"log": "core '%s' is not installed" % core_id,
			"title": "Core not installed",
			"description": "This machine needs the %s core.\nGet it in OPTIONS > Cores."
				% core_id,
			"accent": fault,
		}

	# Asked even when a game IS inserted: a PS2 with no bios folder cannot run
	# anything, and the failure looks identical to a broken core.
	if not missing.is_empty():
		var first: Dictionary = missing[0]
		var path := str(first.get("path", ""))
		# The second line: where the file goes. A row may say otherwise (an
		# e-Reader's program is a library dump, not a BIOS).
		var where := str(first.get("where", "Add it in OPTIONS > Cores > BIOS / Extras."))
		# Any one of a regional set would do, so it is not counted up as several
		# missing files.
		var any_of: Array = first.get("any_of", [])
		if not any_of.is_empty():
			return {
				"start": false, "rom": rom,
				"log": "core '%s' needs one of %s and has none" % [core_id, ", ".join(any_of)],
				"title": "BIOS required",
				"description": "No %s is installed (%s).\n%s"
					% [str(first.get("desc", "BIOS")), path, where],
				"accent": fault,
			}
		var more := "" if missing.size() == 1 else " (+%d more)" % (missing.size() - 1)
		return {
			"start": false, "rom": rom,
			"log": "core '%s' is missing required firmware: %s" % [core_id, path],
			"title": "BIOS required",
			# Two lines, and no absolute path. The card is 520x132 at 1400 px/m —
			# about a playing card held at arm's length — and a Windows system path
			# overflowed it top AND bottom, clipping the one line that says what to
			# do about it. The BIOS / Extras tab prints the folder itself ("Files go
			# in: …"), so repeating it here bought nothing and cost the instruction.
			"description": "%s%s is missing.\n%s"
				% [path, more, where],
			"accent": fault,
		}

	if not rom.is_empty():
		return {"start": true, "rom": rom, "log": "", "title": "", "description": "", "accent": waiting}

	# Nothing in the slot. A machine whose BIOS is installed and whose core will
	# take a blank disc starts anyway, silently, the way the hardware does.
	if not blank.is_empty():
		return {"start": true, "rom": blank, "log": "", "title": "", "description": "", "accent": waiting}

	# Or whose core will start with nothing handed to it at all, which is a
	# different mechanism and a rarer one: a Game Boy Advance with no cartridge
	# draws its BIOS screen and then listens on the link port, which is how it
	# ends up on the end of a GameCube lead or receiving a game from another
	# handheld. An empty file would not do -- there is no drive to look at.
	if empty_ok:
		return {"start": true, "rom": "", "log": "", "title": "", "description": "", "accent": waiting}

	# Orange rather than the red of a fault: nothing is broken, the machine is
	# just waiting for something the player can put in from where they stand.
	if not open_over_disc.is_empty():
		return {
			"start": false, "rom": "",
			"log": "%s open over a disc" % open_over_disc,
			"title": "%s open" % open_over_disc.capitalize(),
			"description": "Close the %s, then switch it on." % open_over_disc,
			"accent": waiting,
		}
	var medium := "disc" if MediaDimensions.is_disc_system(sysid) else "cartridge"
	return {
		"start": false, "rom": "",
		"log": "no cartridge inserted",
		"title": "No game inserted",
		"description": "Put a %s in, then switch it on." % medium,
		"accent": waiting,
	}


## Settle rom_path against what this core actually declares it can load.
##
## Unpacks (and deletes) an archive the core cannot read, and refuses the
## power-on outright for a format no amount of unpacking will fix. Returns false
## when the machine must stay off.
##
## A core that declares the archive extension is left alone — for fbneo, MAME and
## daphne the .zip is the romset, not a wrapper around one.
func _resolve_content(core: String) -> bool:
	var verdict := RomCompat.resolve(rom_path, core, systemid)
	if int(verdict["verdict"]) == RomCompat.Verdict.UNSUPPORTED:
		push_error("[RetroSystem] %s" % verdict["message"])
		# On the card rather than the TV's OSD: half the machines this fires on
		# are handhelds with no set connected, and the card anchors to whatever
		# screen the machine actually has. A console with no TV at all gets the
		# log alone, which is all it could show anyway.
		var toast := _screen_toast()
		if toast != null:
			toast.show_notice(rom_path.get_file(),
				"Cannot run this game", str(verdict["message"]))
		return false

	var resolved := str(verdict["path"])
	if resolved != rom_path and not resolved.is_empty():
		rom_path = resolved
		# The cartridge outlives the run — an eject re-reads rom_path from it, and
		# so does a scene reload — so leaving it holding the .zip we just deleted
		# would fail the same way on the next insert.
		if is_instance_valid(_snapped_cartridge) \
				and "rom_path" in _snapped_cartridge:
			_snapped_cartridge.set("rom_path", resolved)
	return true


## Keep rom_path out of the RomM cache's eviction while the core reads it, and
## let the image it replaces go. Public because the disc drive (SystemTray) calls
## it when a lid or a hot swap hands the core a new image.
func protect_active_rom() -> void:
	if rom_path == _protected_cache_path:
		return
	_release_cache_protection()
	if systemid.is_empty() or rom_path.is_empty():
		return
	RommCacheManifest.protect_file(systemid, rom_path)
	_protected_cache_path = rom_path


func _release_cache_protection() -> void:
	if _protected_cache_path.is_empty():
		return
	RommCacheManifest.unprotect_file(systemid, _protected_cache_path)
	_protected_cache_path = ""


## Power off: stop the running core, locally. See power_on for which power
## method to call; a player's intent goes through toggle_power.
func power_off() -> void:
	_core_menu_open = false
	if attracting:
		_leave_attract()
		return
	if not is_powered_on:
		return
	print("[RetroSystem] Powering off")
	_stop_core()
	_restore_displaced_options()


## Hand back what this machine's workaround pins took from the shared file, so a
## 64DD run does not decide how every other Nintendo 64 renders.
func _restore_displaced_options() -> void:
	if _displaced_options.is_empty() or _displaced_core.is_empty():
		return
	if CoreOptionsStore.merge_values(_resolve_dir(), _displaced_core, _displaced_options):
		print("[RetroSystem] restored displaced core options: %s" % str(_displaced_options))
	_displaced_options.clear()
	_displaced_core = ""


## Everything a machine does when its core goes away, whichever way it was
## stopped. The netplay stop used to be an abridged copy of this, and what the
## abridgement dropped stayed behind: the achievements session was never
## released, so no other cabinet could claim it, and the disc state survived to
## describe a core that had gone.
func _stop_core() -> void:
	# Zero any active rumble on all plugged-in controllers so vibration
	# doesn't leak past core unload if the core was rumbling at shutdown.
	_ports.stop_all_rumble()
	RA.release_session(self)
	_libretro.StopContent()
	_release_cache_protection()
	_audio.on_core_stopped()
	is_powered_on = false
	attract_session = false
	# StopContent returned but the core has not finished: a card the core owns is
	# written during the teardown that follows. Keep watching for a while.
	_memcards.stop_card_polling_soon()
	# Every storage drains what its core writes as it unloads (ConsoleStorage).
	var stop_dir := _resolve_dir()
	var stop_core := _resolve_core()
	for storage: ConsoleStorage in _storages:
		storage.after_stop(stop_dir, stop_core)
	_disc_tray.on_core_stopped()
	_options_panel.hide_panel()
	_update_power_button_visual()
	_model.on_power_off()
	# Both directions, because the machine still running is the one left wrong.
	#
	# StopContent has just cut the bus from under a lead that is still in its
	# socket, so the console at the other end holds a join to endpoints that no
	# longer exist. Re-resolving here puts it back to a lead seated in a
	# powered machine waiting for an unpowered one -- which is a state the
	# coordinator handles, and the state it was in before this machine was ever
	# switched on.
	net_refresh_link_cables()


## Toggle power -- the power button, and the netplay-aware way in. See power_on.
func toggle_power() -> void:
	if NetworkManager.is_active() and not NetworkManager.is_event_applying():
		# A running lockstep game: power stops it on every peer.
		if NetworkManager.netplay_running() and NetworkManager.netplay_system() == self:
			NetworkManager.netplay_stop("powered off")
			return
		# Host powering on a determinism-verified core → start lockstep netplay:
		# every peer runs the core locally instead of the host-only placeholder.
		if NetworkManager.is_host() and not is_powered_on:
			if _netplay_eligible():
				if NetworkManager.netplay_start_host(self, _resolve_core(), net_rom_md5()):
					return   # cold start drives net_start_core on every peer
			else:
				# This used to fall straight through to a local boot: no signal,
				# no error, remote players stranded on the host-only placeholder
				# and nothing anywhere saying why. It still boots locally -- that
				# is the right fallback -- but it now says so.
				_report_netplay_blocked()
		if NetworkManager.is_client():
			# Non-netplay core: emulation runs on the host only — send the intent.
			NetworkManager.report_event(NetEvents.Event.EV_SYS_POWER, {"sys": self})
			return
	if is_powered_on or attracting:
		power_off()
	else:
		power_on()
	# Host in a session: tell clients the new state (placeholder screens).
	if NetworkManager.is_active() and NetworkManager.is_host() \
			and not NetworkManager.is_event_applying():
		NetworkManager.report_event(NetEvents.Event.EV_SYS_POWER_STATE,
			{"sys": self, "on": is_powered_on})


## True if this system can run lockstep netplay right now: a determinism-verified
## core is resolvable and its present boot (game, empty media, or BIOS-only) can
## be reproduced by every peer.
func _netplay_eligible() -> bool:
	var resolved_core := _resolve_core()
	return NetworkManager.netplay_capable(resolved_core) \
		and not net_boot_spec(resolved_core).is_empty()


## Say why this machine is booting local-only, and what would fix it.
##
## Two different failures reach here and they want different words: a core that
## has never been vetted (offer a substitute) and a boot this peer cannot
## reproduce at all -- a BIOS-less machine, an unhashable ROM -- which no core
## swap helps.
func _report_netplay_blocked() -> void:
	# Its own words: the core is vetted and the ROM hashes, so neither of the two
	# reasons below is the true one, and a core swap would not help.
	if GbCameraShell.is_camera_rom(rom_path):
		NetworkManager.netplay_blocked.emit(
			"a Game Boy Camera films its own player's room, so it runs for the host only",
			self, {})
		return
	var resolved_core := _resolve_core()
	var why := NetplayCores.why_not_capable(resolved_core)
	if why.is_empty():
		NetworkManager.netplay_blocked.emit(
			"this machine's boot media cannot be shared with other players",
			self, {})
		return
	var remedy: Dictionary = {}
	var substitute := NetplayCores.suggest_substitute(resolved_core, systemid)
	if not substitute.is_empty():
		remedy = {"kind": "swap_core", "core": substitute, "machine": self,
			"strategy": NetplayCores.listed_strategy(substitute)}
	NetworkManager.netplay_blocked.emit(why, self, remedy)


## Which core this machine would actually load. Public because the core manager
## has to ask before letting one be uninstalled, and `core_name` alone is not the
## answer: a machine left on its default has it empty and resolves it here.
func resolve_core_name() -> String:
	return _resolve_core()


func _resolve_core() -> String:
	# A console with something bolted to it is a different machine, and the
	# combination names its own core: a Mega Drive on a Mega-CD is not the core
	# either box would pick alone. Ahead of core_name, because the machine the
	# player has physically built beats a default chosen for the bare console --
	# and behind nothing, since a bare console never reaches this at all.
	var spec := expansion_boot()
	if not spec.is_empty() and not str(spec.get("core", "")).is_empty():
		return str(spec["core"])
	return _bare_core_default()


## What this console alone would resolve to, ignoring anything bolted to it:
## the player's own per-instance pick if set, else the manager's per-systemid
## default (CoreDefaults, set from the CORES panel). This is also what a stack
## whose console slot is empty falls back to, since expansion_boot() names no
## core for that case.
func _bare_core_default() -> String:
	var c := core_name
	if c.is_empty() and not systemid.is_empty():
		var defaults := CoreDefaults.new()
		defaults.setup(CoreDefaults.default_path())
		c = defaults.get_default_core(systemid)
	return c


func _resolve_dir() -> String:
	var dir := core_directory
	if dir.is_empty():
		dir = CoreDownloadManager.default_core_root()
	return dir


## MD5 of the inserted ROM (for netplay peer verification). Empty if none.
## Cached (mtime-keyed) so only the first hash of a given file touches disk.
func net_rom_md5() -> String:
	if rom_path.is_empty():
		return ""
	return NetFileTransfer.hash_of(rom_path)


## Why net_prepare_boot last refused, in words a player can act on. Read by the
## session so the specific cause survives instead of being flattened into one
## generic string on its way to the menu.
var net_boot_failure: String = ""


## Reproducible launch description for netplay. A BIOS-only core still has a
## full deterministic machine state; it simply has no copyrighted content to
## hash or transfer. Empty media is regenerated locally from its extension.
func net_boot_spec(core: String) -> Dictionary:
	# A Game Boy Camera photographs the room as ONE peer's machine draws it, and
	# no two draw it alike. Lockstep would need every core shown the same thing,
	# which is the blank (CameraHandler hands exactly that to a machine in a
	# session), so the camera boots for the host alone and keeps its picture.
	if GbCameraShell.is_camera_rom(rom_path):
		return {}
	var empty_extension := BiosBoot.empty_media_extension(core, systemid)
	var generated_empty := BiosBoot.empty_media_file(empty_extension,
		BiosBoot.empty_media_track(core, systemid))
	var has_real_media := not rom_path.is_empty() and rom_path != generated_empty
	if has_real_media:
		var md5 := net_rom_md5()
		if md5.is_empty():
			return {}
		var game_boot := {"mode": "rom", "rom_md5": md5}
		# sha1 and size are carried so a peer who does NOT have this ROM can ask
		# their own RomM for it -- /api/roms/by-hash prefers md5 but falls back to
		# sha1. Both come from the same cached pass, so this costs nothing after
		# the first time. The label is metadata for the "you are missing this"
		# row; the file itself is never sent.
		var sums := NetFileTransfer.checksums_of(rom_path)
		if not sums.is_empty():
			game_boot["rom_sha1"] = str(sums.get("sha1", ""))
			game_boot["rom_size"] = int(sums.get("size", 0))
		game_boot["rom_label"] = rom_path.get_file().get_basename()
		game_boot["systemid"] = systemid
		var splash := BiosBoot.splash_options(core, systemid)
		if not splash.is_empty():
			game_boot["boot_options"] = splash
		FirmwareDigest.stamp(game_boot, core)
		return game_boot
	if not BiosBoot.can_boot_empty(core, systemid):
		return {}
	var empty_boot := {
		"boot_options": BiosBoot.empty_boot_options(core, systemid),
	}
	FirmwareDigest.stamp(empty_boot, core)
	if BiosBoot.boots_with_no_content(core, systemid):
		empty_boot["mode"] = "no_content"
	else:
		empty_boot["mode"] = "empty_media"
		empty_boot["extension"] = empty_extension
	return empty_boot


## Recreate a host machine's launch mode locally before net_start_core. ROMs
## are only resolved by hash; BIOS files are never sent and must already be
## installed on this peer.
func net_prepare_boot(spec: Dictionary) -> bool:
	var core := str(spec.get("core", ""))
	net_boot_failure = ""
	if spec.has("firmware") \
			and str(spec.get("firmware", "")) != FirmwareDigest.signature(core):
		# Name the files. The caller used to collapse every media failure into
		# "cannot reproduce one machine's boot media", which does not even say
		# the word firmware, let alone which file to go and fix.
		var diff := NetplayReadiness.firmware_diff(
			spec.get("firmware_rows", {}) as Dictionary, FirmwareDigest.rows(core))
		net_boot_failure = FirmwareDigest.failure_text(core, diff)
		push_warning("[RetroSystem] netplay: %s" % net_boot_failure)
		return false
	match str(spec.get("mode", "rom")):
		"rom":
			_net_no_content_override = false
			return net_resolve_rom(str(spec.get("rom_md5", "")),
				int(spec.get("rom_size", 0)))
		"no_content":
			if not BiosBoot.can_boot_empty(core, systemid) \
					or not BiosBoot.boots_with_no_content(core, systemid):
				return false
			rom_path = ""
			_net_no_content_override = true
			return true
		"empty_media":
			var extension := str(spec.get("extension", ""))
			if not BiosBoot.can_boot_empty(core, systemid) \
					or BiosBoot.boots_with_no_content(core, systemid) \
					or extension != BiosBoot.empty_media_extension(core, systemid):
				return false
			rom_path = BiosBoot.empty_media_for(core, systemid)
			_net_no_content_override = false
			return not rom_path.is_empty()
	return false


## Netplay cold start (client): make sure we own a byte-identical copy of the
## host's ROM. Checks the current rom_path first, then searches the local rom
## library by hash. ROMs are VERIFY-ONLY — never transferred (copyright; see
## file_transfer.gd). Returns false when no matching copy exists locally.
func net_resolve_rom(md5: String, size := 0) -> bool:
	if md5.is_empty():
		return false
	# Refresh from the seated cartridge — object_sync may have remapped it.
	if _snapped_cartridge and _snapped_cartridge.has_method("get_rom_path"):
		var cart_path: String = _snapped_cartridge.get_rom_path()
		if not cart_path.is_empty():
			rom_path = cart_path
	if not rom_path.is_empty() and FileAccess.file_exists(rom_path) \
			and NetFileTransfer.hash_of(rom_path) == md5:
		return true
	# Search THIS system's folder, not the whole library, and only files of the
	# right length. resolve_by_md5 hashes every candidate it cannot rule out, so
	# an unbounded search means reading every ROM the player owns to find one --
	# minutes of disk on a large library, at the moment someone pressed Join.
	# systemid narrows it to one console, `size` to the handful that could match.
	var dirs: Array = [RomLibrary.rom_dir_for_system(systemid)] if not systemid.is_empty() \
		else [RomLibrary.default_roms_root()]
	var found := NetFileTransfer.resolve_by_md5(md5, "rom", size, rom_path, dirs)
	if found.is_empty():
		net_boot_failure = "you do not have the game this machine is running"
		push_warning("[RetroSystem] netplay: no local ROM matches md5 %s… — not transferable" % md5.left(8))
		return false
	rom_path = found
	if _snapped_cartridge and "rom_path" in _snapped_cartridge:
		_snapped_cartridge.set("rom_path", found)
	print("[RetroSystem] netplay: rom matched by hash → %s" % found)
	return true


## The local e-Reader strip whose md5 matches, or "" if this player has none.
## Only the card folder is searched, and the machine's own rom_path is never
## touched: this is the card, not the cartridge.
func net_resolve_card(md5: String) -> String:
	if md5.is_empty():
		return ""
	return NetFileTransfer.resolve_by_md5(md5, "ereader", 0, "card.raw",
		[RomLibrary.rom_dir_for_system(EReaderCards.SYSTEMID)])


# ── Netplay core seam (driven by NetplaySession on every peer) ────────────────

## Start the local core under the netplay gate. The gate (SetNetplayMode) is set
## BEFORE StartContent so the core holds at `start_frame` until inputs post.
## Returns the Libretro node (the session connects its signals). null on failure.
func net_start_core(core: String, port_mask: int, start_frame: int, options: Dictionary) -> Libretro:
	var requested_no_content := _net_no_content_override
	_net_no_content_override = false
	if not _has_display():
		push_error("[RetroSystem] netplay start — no display (connect a TV)")
		return null
	# The host names the core, and every peer runs THAT one. _resolve_core() is
	# this machine's own preference, which is a per-player, per-platform answer:
	# taking it here is how two peers end up on different emulators with no way
	# to tell from the symptom. Falling back to it only covers a caller with
	# nothing to say (an offline-style start).
	var resolved_core := core if not core.is_empty() else _resolve_core()
	if resolved_core.is_empty():
		push_error("[RetroSystem] netplay start — no core for systemid '%s'" % systemid)
		return null
	var no_content := requested_no_content and rom_path.is_empty() \
		and BiosBoot.boots_with_no_content(resolved_core, systemid)
	if rom_path.is_empty() and not no_content:
		push_error("[RetroSystem] netplay start — boot media was not prepared")
		return null
	if is_powered_on:
		_libretro.StopContent()
		_release_cache_protection()
		is_powered_on = false
	# SetCoreOption is a live-core command and is intentionally ignored before
	# StartContent. Netplay options must therefore go through the same persisted
	# store the core reads during startup, or every "forced" option here is a
	# no-op and peers can boot with different saved settings.
	#
	# merge_values answers "was the file rewritten", which is false when the pins
	# are already there -- the second machine of a cabled pair on the same core
	# finds exactly that, the first having just written them. What matters is
	# that they are in effect, so that is what is checked.
	if not options.is_empty():
		CoreOptionsStore.merge_values(_resolve_dir(), resolved_core, options)
		var saved := CoreOptionsStore.load_values(_resolve_dir(), resolved_core)
		for key: Variant in options:
			if str(saved.get(str(key), "")) != str(options[key]):
				push_error("[RetroSystem] netplay start — could not pin deterministic core options")
				return null
	# SRAM: netplay override (session-injected identical bytes) or the normal
	# local composition when the session didn't set one (offline-like start).
	if not _memcards.apply_netplay_sram():
		_libretro.SetSramPath(_memcards.sram_path_for_run(resolved_core))
	# A clock read from each peer's own file is a different time on every peer.
	_libretro.SetRtcPath("")
	# Only the storages that stage in a session: today the Sega CD's and the
	# Saturn cartridge's, which the core reads from files at load. Not a 3DO's
	# NVRAM (Opera carries it in its savestate, so the host's would be drained
	# over this console's), nor the Xbox's or the VMUs -- see each storage's
	# stages_in_session().
	for storage: ConsoleStorage in _storages:
		if storage.stages_in_session():
			storage.stage_for_run(_resolve_dir(), resolved_core)
	_apply_forced_core_options(_resolve_dir(), resolved_core)
	# The session's determinism pins outrank what the machine pins for its own
	# hardware, so they go back over it: a Saturn's Video CD Card is off in a
	# session (NetplayCores) even seated. The one key both pin today.
	var session_pins := NetplayCores.forced_options(resolved_core)
	if not session_pins.is_empty():
		CoreOptionsStore.merge_values(_resolve_dir(), resolved_core, session_pins)
	_ports.persist_pak_options(_resolve_dir(), resolved_core)
	AppPrefs.apply_hw_render_for(resolved_core)
	_libretro.SetNetplayMode(true, port_mask, start_frame)
	protect_active_rom()
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", true)
	_ports.bind_all_pak_storage()
	_libretro.StartContent(_resolve_dir(), resolved_core, rom_path)
	if no_content:
		ClassDB.class_call_static("Libretro", "SetNoContentPassesNull", false)
	_after_core_started()
	net_remote_powered = false
	if connected_tv:
		connected_tv.hide_osd()   # real local output now, not the placeholder
	return _libretro


## Every machine on this one's link bus, ITSELF FIRST, or just itself when
## nothing is cabled to it. NetMachine protocol; LinkBusSweep.group_of explains.
func net_link_group() -> Array:
	return LinkBusSweep.group_of(self)


## Every distinct physical cable bus containing this machine. This is also the
## list netplay re-resolves after restarting cores, because StopContent drops
## LinkCoordinator ownership while the plugs themselves never moved.
func net_link_buses() -> Array:
	return LinkBusSweep.buses_of(self)


## Re-make every link cable this machine is on (LinkCable.rejoin), after a core
## start or stop cut the bus under leads that never moved.
func net_refresh_link_cables() -> void:
	LinkBusSweep.refresh(self)


## Flatten every cable bus reachable from `anchor`. Kept here by name for the
## suites; the rule is LinkBusSweep.merge's.
static func merge_link_buses(anchor: Object, buses: Array) -> Array:
	return LinkBusSweep.merge(anchor, buses)


## The bus this machine is on, as [{machine, port}], or [] when it is on none.
func net_link_bus() -> Array:
	return LinkBusSweep.bus_of(self)


## Stop the local netplay core and clear the gate.
func net_stop_core() -> void:
	_libretro.SetNetplayMode(false, 1, 0)
	_net_no_content_override = false
	_memcards.clear_netplay_sram()
	if is_powered_on:
		_stop_core()
	else:
		# Nothing was running, but a session may still have pinned the ROM in the
		# cache on its way to a start that never happened.
		_release_cache_protection()


## True on clients while the host runs this system's emulation.
var net_remote_powered := false

## Client-side mirror of the host's power state (pre-netplay placeholder).
func net_set_remote_power(on: bool) -> void:
	net_remote_powered = on
	if connected_tv:
		if on:
			connected_tv.show_osd("LIVE ON HOST")
		else:
			connected_tv.hide_osd()


## Front-panel reset: the machine restarts, the core stays loaded. Does not
## change button state, labels, or fire power model hooks.
##
## retro_reset, not a stop/start of the core: a restart has to join the
## emulation thread, and a core that owns internal threads of its own (Dolphin)
## does not unwind on demand, so the join never returns and the app hangs with
## every thread parked. Nothing is torn down here, so the screen, the audio
## voices and the port bindings all survive and there is nothing to rebind.
func reset() -> void:
	if NetworkManager.is_active() and not NetworkManager.is_event_applying():
		if NetworkManager.netplay_running() and NetworkManager.netplay_covers(self):
			if NetworkManager.is_client():
				NetworkManager.report_event(NetEvents.Event.EV_SYS_RESET, {"sys": self})
			elif not NetworkManager.netplay_pending_joins().is_empty():
				# Somebody is stood there holding a pad this session cannot give
				# them. A scheduled retro_reset would not admit them: it keeps the
				# session, and with it the ownership decided when it started. So
				# RESET means something stronger while a claim is waiting -- start
				# the game again with everybody in it, which is the only way in
				# for a core that cannot hand over a savestate.
				NetworkManager.netplay_rejoin_restart(self)
			else:
				NetworkManager.netplay_schedule_reset(self)
			return
		# Before lockstep starts, clients hold only a visual replica; reset the
		# host's running core instead of returning because this copy is powered off.
		if NetworkManager.is_client():
			NetworkManager.report_event(NetEvents.Event.EV_SYS_RESET, {"sys": self})
			return
	if not is_powered_on:
		return
	_model.play_reset()
	# Re-assert the drive first. A machine coming back up should boot whatever is
	# physically in its bay, and the core's tray is a mirror that can be left
	# behind — a lid cycle the core did not hear about leaves it believing the
	# tray is open, and then every reset lands in the BIOS menu until the machine
	# is switched off and on again.
	_disc_tray.sync_core()
	print("[RetroSystem] Resetting: rom=%s" % rom_path)
	_libretro.RequestReset()


## Visual half of a frame-scheduled netplay reset. The core half is armed on
## every peer by NetplaySession and executes at the agreed emulated frame.
func net_play_reset() -> void:
	if is_powered_on and _model != null:
		_model.play_reset()


# ── The machine's own controls, as menu rows ─────────────────────────────────

## Everything the Controls tab of this machine's menu shows. A row exists exactly
## when the machine has the control — RESET where the shell has a reset button,
## OPEN/EJECT where it has a drive, the channel slide where it has an RF out — so
## the menu never offers what the hardware does not. Values only, never nodes: the
## panel compares it whole to notice a change made by hand.
func controls_state() -> Dictionary:
	var state := {
		"on": is_powered_on,
		"game": rom_path.get_file().get_basename() if not rom_path.is_empty() else "",
		"has_reset": _reset_button != null and _reset_button.visible,
		"eject": _disc_tray.eject_label(),
		"rf_channel": get_rf_channel(),
		"rf_options": _model.rf_channel_options() if _model != null else [],
		"display": "",
		"wiring": [],
	}
	var tv := connected_tv
	var picture := is_instance_valid(tv)
	# No picture on any set is exactly when a wrong cord matters most — the yellow
	# plug in an audio jack leaves connected_tv empty — so find the set through the
	# cords themselves, and say there is no picture rather than nothing at all.
	if not picture:
		tv = null
		for link: Dictionary in AvGraph.links_for(self):
			var dev := (link["in"] as RcaPort).get_device()
			if dev is RetroTV and (link["out"] as RcaPort).get_device() == self:
				tv = dev as RetroTV
				break
	if tv != null:
		var input := tv.input_for_device(self)
		state["display"] = "TV, %s%s" % [tv.source_name(input) if input >= 0
			else "not on an input", "" if picture else " (no picture)"]
		if input >= 0:
			state["wiring"] = Array(tv.panel().miswired(input))
	return state


## Whether this machine sends left and right separately — the same answer
## AvSource.resolve is given. A mono machine's one audio cord is not "crossed" in
## whichever jack it lands (TvPanel.miswired).
func av_is_stereo() -> bool:
	return _av_stereo


## POWER to a position, for the menu's switch. A handheld's power is a slide, and
## the slide is moved rather than the machine toggled behind it, so the switch
## never stands at OFF on a machine that is running; the slide's own handler then
## takes the one path a hand does (and the event netplay knows).
func set_power(on: bool) -> void:
	var slide := _model.power_slider() if _model != null else null
	if slide != null:
		slide.set_value(1.0 if on else 0.0)
	elif on != is_powered_on:
		toggle_power()


## What the running core reports about itself, for the menu's Debug tab, as
## sections of [label, value] rows. Built by SystemDebugReport, which reads only
## this machine's public surface; the menu reaches it here by name.
func debug_state() -> Array:
	return SystemDebugReport.rows(self)


## The option values the core (or the pre-launch peek) last reported. Read-only
## window for the Debug tab; set_core_option is the way to change one.
func core_option_values() -> Dictionary:
	return _options_values


## Everything the options menu shows about the core, in one read, so the panel
## needs none of the fields behind it: what the core declared, its current
## values, its controller ports, why the options are unavailable ("" when they
## are not) and which core this machine would load.
func core_options_snapshot() -> Dictionary:
	return {
		"definitions": _options_definitions,
		"values": _options_values,
		"controller_info": _ports.controller_info,
		"unavailable": _options_unavailable,
		"core": _resolve_core(),
	}


## The RF channel slide, set from the menu. The model moves its own switch.
func set_rf_channel(channel: int) -> void:
	if _model != null:
		_model.set_rf_channel(channel)


## What this machine's memory cards pin, asked of the machine rather than of
## ForcedCoreOptions directly — the card state is the machine's to report, and
## system_tests checks it that way.
func removable_media_options(core: String) -> Dictionary:
	return ForcedCoreOptions.removable_media(core, card_family(), _seated_cards())


## Everything pinned for a run of `core`: what the shell demands, plus what this
## system composes per run (ForcedCoreOptions) and what its storages pin. One
## place, so the .opt seam and the options panel can never disagree about which
## keys the player is allowed to move. forced_core_options() is the same for the
## core this machine would load.
func all_forced_options(core: String) -> Dictionary:
	var out: Dictionary = _model.get_forced_core_options() if _model != null else {}
	out.merge(ForcedCoreOptions.all(core, systemid, rom_path, _expansions.hardware_ids(),
		card_family(), _seated_cards(), _expansion_launch.host_media_path()), true)
	out.merge(ForcedCoreOptions.lightgun(core, _has_lightgun()), true)
	for storage: ConsoleStorage in _storages:
		out.merge(storage.forced_options_for(core), true)
	return out


## Whether any port holds a light gun (a cabinet's own, or one plugged in).
func _has_lightgun() -> bool:
	for c: Variant in _ports.controllers:
		if c is LightGun:
			return true
	return false


## Whether a card is in each slot this console shows.
func _seated_cards() -> Array[bool]:
	var out: Array[bool] = []
	for slot in card_slot_count():
		out.append(get_snapped_memcard(slot) != null)
	return out


# ── expansions ────────────────────────────────────────────────────────────────
#
# The sockets, covers and unit list live in SystemExpansions, a child this node
# owns. What stays here is the surface other code calls BY NAME on the console
# (RetroExpansion, ScenePersistence, system models, the mods' probes), as
# one-line forwarders, and the parts that are this console's own slot or drive.

var _expansions: SystemExpansions = null


## Option values this machine displaced in the shared <core>.opt, and the core
## the file belongs to, so power_off can put them back.
##
## The forced-options file is per CORE, not per machine, so a pin set for a 64DD
## outlives the run and reaches every other console using that core: one
## cartridge-less boot would leave every plain Nintendo 64 on a renderer its
## owner never chose. Pins that describe the HARDWARE -- a drive that is
## physically bolted on -- are re-pinned every launch and are fine to leave; this
## is for the ones that describe a WORKAROUND.
var _displaced_options: Dictionary = {}
var _displaced_core := ""


## The helper itself, for the suites that test its gates directly.
func expansion_hardware() -> SystemExpansions:
	return _expansions


## True from begin_restore() on: this console is being restored, not spawned, so
## nothing seeds a default occupant or a cover the save does not list.
func is_restoring_from_save() -> bool:
	return _restoring_from_save


## Build the sockets, covers and foot (SystemExpansions.build_hardware), and
## register the foot with this pickable: XRToolsPickable collects grab points in
## its own _ready, which ran long before the model was measured.
func _build_expansion_hardware() -> void:
	var foot := _expansions.build_hardware()
	if foot != null:
		_grab_points.push_back(foot)


## Where this machine's roof is relative to its own cartridge slot, in metres.
##
## Signed, and in practice NEGATIVE: the slot is placed a few millimetres proud
## of the shell so a cartridge stands out of it, which is measured as -5 mm on
## both the Mega Drive and the Jaguar. That is exactly why seating a unit by its
## origin half-sank it into the console instead of swallowing it whole, and it is
## why this is measured rather than assumed to be positive.
##
## A unit that mounts AS a cartridge -- a 32X, a Jaguar CD -- stands ON the
## console with only its connector inside, so it has to know where the top face
## is relative to the slot that connector goes into. Only the console can answer
## that: the slot is placed by the model and the roof is measured off the model's
## meshes, and the two differ by a different amount on every shell. Derived from
## the CARTRIDGE's height instead -- 35 mm on a Mega Drive -- both units hung in
## the air well above the consoles they were supposed to be sitting on.
##
## Cached once the model has meshes to measure. Answers 0.0 until then, which
## seats a unit ON the slot -- wrong, but only for the frames before a model
## finishes loading, and never cached.
func roof_above_cartridge_slot() -> float:
	if not is_nan(_roof_over_slot):
		return _roof_over_slot
	if _cartridge_slot == null:
		return 0.0
	var aabb := body_aabb()
	if aabb.size.x <= 0.0:
		return 0.0
	_roof_over_slot = aabb.end.y - _cartridge_slot.position.y
	return _roof_over_slot


## The lid seated on this console's expansion bay, or null when it is off.
func get_expansion_cover() -> Node3D:
	return _expansions.expansion_cover()


## Put a saved lid back on, building the bay first when a restore gets here
## before the deferred call that builds it (see restore_expansion).
func restore_expansion_cover(cover: Node3D) -> void:
	_build_expansion_hardware()
	_expansions.restore_expansion_cover(cover)


## True while the cover over `socket_id` is in its slot on this console.
func port_cover_on(socket_id: String) -> bool:
	return _expansions.port_cover_on(socket_id)


## Shut (or reopen) a floor opening's cover slot while this console stands on the
## unit that fills it. See SystemExpansions.block_port_cover.
func block_port_cover(socket_id: String, blocked: bool) -> void:
	_expansions.block_port_cover(socket_id, blocked)


## Put the covers on this console's own unit sockets, building them first. A
## room saved before covers existed gets them from its restore (ScenePersistence).
func seed_port_covers() -> void:
	_build_expansion_hardware()
	_expansions.seed_port_covers()


## Each unit socket that has a cover slot, and the cover in it or null.
func get_port_covers() -> Dictionary:
	return _expansions.port_covers()


## Put a saved cover back over `socket_id`, building the sockets first when a
## restore gets here before they are.
func restore_port_cover(socket_id: String, cover: Node3D) -> void:
	_build_expansion_hardware()
	_expansions.restore_port_cover(socket_id, cover)


## The socket a MOUNT_ABOVE unit naming `socket_id` goes into, or null. Kept
## under this name because suites and the mods' probes reach it here.
func _unit_socket(socket_id: String) -> XRToolsSnapZone:
	return _expansions.unit_socket(socket_id)


## Called from the unit's side of the join, whichever side owns the socket.
func attach_expansion(unit: RetroExpansion) -> void:
	if not _expansions.attach(unit):
		return
	if not unit.card_swiped.is_connected(_on_expansion_card_swiped):
		unit.card_swiped.connect(_on_expansion_card_swiped)
	_update_name_label()


func detach_expansion(unit: RetroExpansion) -> void:
	if unit == null or not _expansions.units().has(unit):
		return
	if unit.card_swiped.is_connected(_on_expansion_card_swiped):
		unit.card_swiped.disconnect(_on_expansion_card_swiped)
	_expansions.detach(unit)
	_update_name_label()


## A dotcode card was slid through an expansion's groove.
##
## The card reaches the core as removable media: eject, replace, insert, and the
## INSERT edge is what queues the dotcode. Always image 0 — the swipe has already
## decided which strip, so there is nothing for an index to choose between, and
## the frontend has no add_image_index bound. The core's per-strip image list is
## for a frontend driving this from a disk menu instead.
func _on_expansion_card_swiped(card: Node3D, edge: String, strip: int) -> void:
	if strip < 0:
		# Two different refusals, and one message for both left a player with no
		# way to tell them apart: a card presented on an uncoded edge needs
		# TURNING, a card presented face-down needs FLIPPING, and doing the second
		# when you needed the first reads nothing either way.
		var data: Dictionary = card.get_card_data() if card.has_method("get_card_data") else {}
		if EReaderCards.coded_edges(data).has(edge):
			print("[RetroSystem] card presented %s face-down: a dotcode is printed on one side only" % edge)
		else:
			print("[RetroSystem] card presented %s: no dotcode on that edge; this card is coded on %s"
				% [edge, ", ".join(EReaderCards.coded_edges(data))])
		return
	var path := _swiped_strip_path(card, strip)
	if path.is_empty():
		push_warning("[RetroSystem] swiped card supplied no path for strip %d" % strip)
		return
	# In a session the card lands on ONE agreed frame on every peer, as a disc
	# swap does, and each peer finds the strip by hash in its own card folder.
	# Rollback and late join are safe because the RetroXR mGBA build carries the
	# scanner and the card on it in its savestate (GBA_SUBSYSTEM_EREADER).
	if NetworkManager.netplay_running() and NetworkManager.netplay_covers(self):
		var md5 := NetFileTransfer.hash_of(path)
		print("[RetroSystem] card swiped in a session: %s strip %d -> %s (md5 %s…)"
			% [edge, strip, path.get_file(), md5.left(8)])
		if NetworkManager.is_host():
			NetworkManager.netplay_schedule_disk(self, DISK_OP_CARD, md5, 0)
		else:
			NetworkManager.report_event(NetEvents.Event.EV_DISK_OP,
				{"sys": self, "op": DISK_OP_CARD, "md5": md5, "index": 0})
		return
	if not _disc_tray.supports_disk_control():
		push_warning("[RetroSystem] core takes no removable media; card ignored")
		return
	print("[RetroSystem] card swiped: %s strip %d -> %s" % [edge, strip, path.get_file()])
	_libretro.SetDiskEjectState(true)
	_libretro.ReplaceDiskImage(0, path)
	_libretro.SetDiskEjectState(false)
	_libretro.RequestDiskInfo()


## The file behind the strip a swipe selected, off the card itself.
func _swiped_strip_path(card: Node3D, strip: int) -> String:
	if card == null or not card.has_method("get_card_data"):
		return ""
	var data: Variant = card.call("get_card_data")
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var strips: Array = (data as Dictionary).get("strips", [])
	if strip < 0 or strip >= strips.size():
		return ""
	return str((strips[strip] as Dictionary).get("path", ""))


## A disk going into or out of an expansion's own bay. The machine's boot media
## can change without anything touching the console's cartridge slot.
func on_expansion_media_changed(_unit: RetroExpansion) -> void:
	_update_name_label()


## Bolt `unit` on from the console's side. Used by the save restore and by a
## MOUNT_ABOVE join, where it is the console that owns the socket.
func restore_expansion(unit: RetroExpansion) -> void:
	if unit == null:
		return
	# The bay is built on a deferred call from _ready, and a restore can reach
	# here in the frame this console appeared: build it now. Built already, this
	# does nothing, and so does the deferred call when it comes.
	_build_expansion_hardware()
	# Whichever machine owns the socket is the one that has to do the taking: a
	# unit that stands on this console goes into OUR socket, a unit this console
	# stands on takes the console into ITS socket. Only the second half was here,
	# so bolting a 64DD or a Mega-CD bound the two logically and seated neither --
	# and an unfrozen console with nothing holding it simply fell through the join.
	var mount := ExpansionCatalog.mount_of(unit.expansion_id)

	if mount == ExpansionCatalog.MOUNT_CARTRIDGE:
		# It goes where a game would go, and fills the slot the way it does on
		# the hardware.
		if _cartridge_slot != null and accepts_media(unit):
			_cartridge_slot.pick_up_object(unit)
			return
	elif mount == ExpansionCatalog.MOUNT_ABOVE:
		var socket_id := ExpansionCatalog.socket_of(unit.expansion_id)
		var socket := _expansions.unit_socket(socket_id)
		if socket != null and _expansions.accepts_unit(unit, socket_id):
			socket.pick_up_object(unit)
			return
	else:
		var base := unit.get_socket()
		if base != null:
			base.pick_up_object(self)
			return
	# No socket on either side -- a combination the catalog does not describe, or
	# a machine whose body was never measured. Bind it logically so the stack is
	# at least reported correctly, rather than silently doing nothing.
	push_warning("[RetroSystem] %s and %s have no socket between them; bound without a physical join"
		% [systemid, unit.expansion_id])
	unit.bind_to_host(self)


## The ids bolted to this console, in catalog order.
func expansion_ids() -> Array[String]:
	return _expansions.ids()


## A shell's own RJ45 socket, for a model that says it has one (a slim PS2).
func _build_builtin_ethernet_port() -> void:
	var link_port := _model.builtin_ethernet_port()
	if link_port < 0 or get_node_or_null("EthernetPort") != null:
		return
	var scene := load("res://Scenes/Objects/cables/ethernet_port.tscn") as PackedScene
	var port := scene.instantiate() as EthernetPort
	port.name = "EthernetPort"
	port.link_port = link_port
	add_child(port)
	_model.place_builtin_ethernet_port(port)


## The units themselves, for whoever needs the objects rather than the names.
func get_expansions() -> Array[RetroExpansion]:
	return _expansions.units()


# ── Expansion launch ──────────────────────────────────────────────────────────
# The launch half of the expansion subject lives in ExpansionLaunch now. The
# hardware half — sockets, cover, seating, card swipes — stays here, because it
# parents nodes to this console and reads its transform. Only expansion_boot is
# called from outside, so only it keeps a forward.

func expansion_boot() -> Dictionary:
	return _expansion_launch.expansion_boot()


## Public because ExpansionLaunch and expansion_tests both call it; it was
## private when its only caller was in this file.
func slot_b_save_path(core: String) -> String:
	return _expansions.slot_b_save_path(core)


func _apply_forced_core_options(dir: String, core: String) -> void:
	var forced := all_forced_options(core)
	if forced.is_empty():
		return
	# Through the store, which owns this file: set_core_option already writes it
	# that way, and two writers with their own idea of the format is how the same
	# file came out in a different order depending on which one touched it last.
	# Remember what the renderer pin displaces. It is the only forced option here
	# that is a workaround rather than a description of the hardware, so it is the
	# only one that has to be handed back.
	_displaced_options.clear()
	_displaced_core = core
	if forced.has("mupen64plus-rdp-plugin"):
		var saved := CoreOptionsStore.load_values(dir, core)
		if saved.has("mupen64plus-rdp-plugin"):
			_displaced_options["mupen64plus-rdp-plugin"] = saved["mupen64plus-rdp-plugin"]

	if CoreOptionsStore.merge_values(dir, core, forced):
		print("[RetroSystem] forced core options applied: %s -> %s"
			% [str(forced), CoreOptionsStore.opt_path(dir, core)])


# --- Core options ---

## The run never started. Until this signal existed a refused load raised
## nothing at all, so the machine reported is_powered_on = true and sat dark —
## indistinguishable from a broken core, a missing BIOS or a dead TV.
##
## Powers back off rather than leaving the button saying STOP on a machine with
## no core behind it, and says why on the hardware, where the player is.
func _on_content_load_failed(reason: String) -> void:
	push_error("[RetroSystem] content load failed — %s" % reason)
	if is_powered_on:
		_stop_core()
	var absent := BiosBoot.absent_media_boot_roms(_resolve_core(), _media_systemid())
	var toast := _machine_toast()
	if toast != null:
		var detail := _load_failed_detail(reason, absent)
		# An arcade game that names a missing file needs its BIOS or device set beside it.
		# MAME says "NOT FOUND", FinalBurn Neo "is required".
		if ArcadeProfiles.is_cabinet_system(systemid) and (reason.contains("NOT FOUND") or reason.contains("is required")):
			detail += "\nMAME/FBNeo games need their BIOS or device ROM sets (neogeo.zip, qsound.zip...). Get them from the core's BIOS list, or put them in the same roms folder as the game."
		toast.show_notice(_display_name(), "Could not start", detail, AchievementToast.ACCENT_NOTICE)


## What a refused load says. A game that needs a regional BIOS some of which is
## not installed was most likely refused for that -- the core picks the file by
## the disc's region, which is not known here -- so the notice names it rather
## than the core's bare refusal.
static func _load_failed_detail(reason: String, absent_boot_roms: Array[String]) -> String:
	if absent_boot_roms.is_empty():
		return reason
	var more := "" if absent_boot_roms.size() == 1 else " (+%d)" % (absent_boot_roms.size() - 1)
	return "Its region's BIOS may be missing: %s%s\nAdd it in OPTIONS > Cores > BIOS / Extras." \
		% [absent_boot_roms[0], more]


## Fired by the Libretro node (via options_ready signal) once the emulation core
## has registered its option set. Caches the data and refreshes the panel if it
## is already open so live changes (e.g. second options_ready after reset) appear.
func _on_options_ready(_categories: Dictionary, definitions: Dictionary, current_values: Dictionary) -> void:
	print("[RetroSystem] options_ready — %d definitions received" % definitions.size())
	_options_definitions = definitions
	_options_values = current_values
	_options_unavailable = ""
	# Controller info is set during retro_load_game, so it's ready by the time
	# options_ready fires. Fetch it here so the panel can show both tabs.
	_ports.controller_info = _libretro.GetControllerInfo()
	print("[RetroSystem] controller info fetched — %d ports" % _ports.controller_info.size())
	# A controller can be plugged before the core (and its options) exist. Now that
	# there is a core: tell it what is on each port, then apply each pad's
	# preferred type. Devices first — the pad-type option is per-port and means
	# nothing until the port has a device on it.
	_ports.reannounce_all()
	_ports.reapply_pad_types()
	if _options_panel.visible:
		_options_panel.refresh()


## Keys that open a core's OWN DIP switch screen, as libretro.h's RETROK_ codes, by core. MAME: Tab opens
## its menu, whose second line is DIP Switches (measured: Input Settings, DIP Switches, Bookkeeping...),
## so Tab, Down, Return; Tab alone shuts it again. FBNeo has no such screen (Tab, F2 and F3 do nothing
## visible, measured): its DIPs are core options (`fbneo-dipswitch-<game>-...`), which the DIP tab lists.
const DIP_MENU_KEYS := {"mame": [9, 274, 13]}
const DIP_MENU_CLOSE := [9]
## What marks a DIP among a core's options (the key names carry it).
const DIP_OPTION_MARK := "dipswitch"
const _KEY_HOLD := 0.12
const _KEY_GAP := 0.25

var _core_menu_open := false
var _core_keys_busy := false
## A suite's stand-in for the core's keyboard: called with (keycode, down) instead of the libretro node.
var core_key_sink: Callable = Callable()


## The menu's DIP Switch tab is a cabinet's (a machine whose model is the arcade cabinet).
func has_dip_tab() -> bool:
	return _model is RetroSystemModelArcadeCabinet


## The running core has a DIP screen of its own that the tab can open on the game's screen.
func core_dip_menu_available() -> bool:
	return is_powered_on and DIP_MENU_KEYS.has(_resolve_core())


func core_dip_menu_open() -> bool:
	return _core_menu_open


## The tab's button: open the running core's own DIP screen, or shut it again.
func toggle_core_dip_menu() -> void:
	if not core_dip_menu_available() or _core_keys_busy:
		return
	var keys: Array = DIP_MENU_CLOSE if _core_menu_open else DIP_MENU_KEYS[_resolve_core()]
	_core_menu_open = not _core_menu_open
	_tap_core_keys(keys)


func _tap_core_keys(keys: Array) -> void:
	_core_keys_busy = true
	for code: int in keys:
		_core_key(code, true)
		await get_tree().create_timer(_KEY_HOLD).timeout
		_core_key(code, false)
		await get_tree().create_timer(_KEY_GAP).timeout
	_core_keys_busy = false


## One key to the core, the way a keyboard does it (keyboard_receiver `_send_key`): through the netplay
## schedule when a session is running, else straight to port 0.
func _core_key(code: int, down: bool) -> void:
	if core_key_sink.is_valid():
		core_key_sink.call(code, down)
		return
	if NetworkManager.netplay_queue_key(self, code, down, 0):
		return
	if _libretro != null:
		_libretro.SetKeyState(0, code, down, 0)


## Toggle the core options panel open or closed.
## Called by SpawnMenuController when the user points at this system and presses
## the left thumbstick (primary_click action).
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel.visible:
		print("[RetroSystem] closing options panel")
		_options_panel.hide_panel()
		return
	print("[RetroSystem] opening options panel")
	# Powered off there is no core to ask, so read what the system's DEFAULT core
	# declares. It writes to the same file the core loads at start, so a change
	# made now is what the next launch runs with.
	if not is_powered_on:
		_load_prelaunch_options()
	_options_panel.show_for(self, camera)


## Fill the option cache from the default core's own declarations without starting
## it. Some cores publish nothing until content is loaded; for those the cache
## stays empty and the panel explains why instead of showing an empty list.
func _load_prelaunch_options() -> void:
	var core := _resolve_core()
	var dir := _resolve_dir()
	var peeked := CoreOptionsStore.peek(dir, core)
	if peeked.is_empty():
		_options_definitions = {}
		_options_values = {}
		_options_unavailable = CoreOptionsStore.peek_failure_reason(dir, core)
		print("[RetroSystem] pre-launch options unavailable for '%s'" % core)
		return
	_options_unavailable = ""
	_options_definitions = peeked["definitions"]
	_options_values = CoreOptionsStore.effective_values(
		peeked, CoreOptionsStore.load_values(dir, core))
	print("[RetroSystem] pre-launch options for '%s' — %d definitions"
		% [core, _options_definitions.size()])


## Apply a single core option change. A running core is told directly; a powered
## off one is edited through its option file, which it reads at start.
func set_core_option(key: String, value: String) -> void:
	print("[RetroSystem] set_core_option '%s' = '%s'" % [key, value])
	_options_values[key] = value
	if is_powered_on:
		_libretro.SetCoreOption(key, value)
	else:
		CoreOptionsStore.set_value(_resolve_dir(), _resolve_core(), key, value)


## Options this system pins so the hardware works at all — the 3DS's
## side-by-side framebuffer, the Virtual Boy's stereo split, and which memory
## card slots the PlayStation has, which the physical cards decide rather than a
## menu. They are locked in the UI and skipped by a reset, which would otherwise
## break the screen (or silently detach a seated card) rather than restore it.
func forced_core_options() -> Dictionary:
	return all_forced_options(_resolve_core())


## Put every non-forced option back to the value the core itself declares as its
## default.
func reset_core_options() -> void:
	if _options_definitions.is_empty():
		return
	var forced := forced_core_options()
	var changed := 0
	for key: String in _options_definitions:
		if forced.has(key):
			continue
		var defn: Object = _options_definitions[key]
		var default_val: String = defn.GetDefaultValue()
		if default_val.is_empty() or String(_options_values.get(key, "")) == default_val:
			continue
		set_core_option(key, default_val)
		changed += 1
	print("[RetroSystem] reset %d core options (%d forced kept)" % [changed, forced.size()])


## Re-announce the VMU slots on one controller. Called when a card is pushed into
## or pulled out of a slot, which the system cannot see for itself — the slot
## belongs to the controller, two objects away.
##
## Unlike reapply_pak this cannot reach a RUNNING core: flycast does not
## re-create its maple devices for a changed slot option (measured, see
## Tools/cores/vmu_slot_probe). The seating is recorded and applied at the next
## content start.
func reapply_vmu(ctrl: Node) -> void:
	# The same sockets hold an Xbox's Memory Units, and the pad announces a
	# change in them the same way. Each storage ignores what is not its own.
	for storage: ConsoleStorage in _storages:
		storage.reapply(ctrl)


## Whether the running core has said what options it has yet, and whether `key`
## is one of them. Read by XboxStorage, to tell a core build with no lower
## Memory Unit slot from one that has it.
func core_options_known() -> bool:
	return not _options_definitions.is_empty()


func core_declares_option(key: String) -> bool:
	return _options_definitions.has(key)


## What the running core (or the pre-launch peek) declared, key -> its
## LibretroOptionDefinition. Read-only window for SystemPorts, which looks up a
## per-port option by its suffix; set_core_option is the way to change a value.
func core_option_definitions() -> Dictionary:
	return _options_definitions


func machine_toast() -> AchievementToast:
	return _machine_toast()


func display_name_for_toast() -> String:
	return _display_name()


## Read by another machine's SegaCdStorage, deciding whether the shared folder is
## free.
func sega_cd_storage() -> SegaCdStorage:
	return _sega_cd


## Read by another machine's SaturnStorage, deciding whether the shared folder is
## free.
func saturn_storage() -> SaturnStorage:
	return _saturn


## Read by another machine's ThreeDoStorage, deciding whether the shared file is
## free.
func three_do_storage() -> ThreeDoStorage:
	return _three_do


## The memory built into this console, or null on one with none -- see
## ConsoleMemory.
func console_memory() -> ConsoleMemory:
	return _console_memory


## Built once systemid is known, which the spawner and a restore both set before
## the machine enters the tree; a restore sets console_memory_id then too.
func _build_console_memory() -> void:
	var info := SystemInfo.for_system(systemid)
	if info == null or info.console_memory.is_empty() or _console_memory != null:
		return
	_console_memory = ConsoleMemory.new()
	_console_memory.name = "ConsoleMemory"
	add_child(_console_memory)
	_console_memory.setup(self, info.console_memory, console_memory_id)


## Whether this machine's core hands device screens over through the controller
## display interface, rather than drawing them into the picture.
func vmu_hands_screens_over() -> bool:
	if not is_instance_valid(_libretro):
		return false
	return bool(_libretro.HasControllerScreens())


## The screen of the card in `slot` of this pad, or null until the core has
## pushed one.
func vmu_screen_texture(ctrl: Node, slot: int) -> Texture2D:
	if slot < 0 or not vmu_hands_screens_over():
		return null
	var port := _ports.pad_libretro_port(ctrl)
	return _libretro.GetControllerScreenTexture(port, slot) if port >= 0 else null


## The voice the beep of the card in `slot` of this pad plays on, or -1 until
## that card has beeped.
func vmu_beep_voice(ctrl: Node, slot: int) -> int:
	if slot < 0 or not is_instance_valid(_libretro):
		return -1
	var port := _ports.pad_libretro_port(ctrl)
	return int(_libretro.GetControllerAudioVoiceId(port, slot)) if port >= 0 else -1


## Attach the wireless-pad component and reveal its button, on the consoles that
## have one. Everything the Wii does differently — pairing, the slot arithmetic
## it shares with wired pads, the GameCube-vs-Wii device ids — lives in WiiLink,
## the same way a handheld's input pipeline lives in HandheldInput. Every other
## console leaves `_wii_link` null and reads none of it.
func _setup_wireless_pads() -> void:
	var wants := WiiLink.handles(systemid)
	_sync_button.set_active(wants)
	if not wants or _wii_link != null:
		return
	# system.tscn parks this on the procedural box's top face. A model with its own
	# geometry has to say where it really lives, or it hangs in the air beside the
	# console. See RetroSystemModel.configure_sync_button.
	_model.configure_sync_button(_sync_button)
	_wii_link = WiiLink.new()
	_wii_link.name = "WiiLink"
	add_child(_wii_link)
	_wii_link.setup(self, _sync_button)


## True while a save is seating this machine's media, so hooks that make a NOISE
## on insertion can tell a restore from a player pushing a cartridge in.
func is_restoring_media() -> bool:
	return _restoring_media


## The Wii pairing component, or null on every other console. Wii Remotes look it
## up here after a save restore, when they have a system but not yet a link.
func get_wii_link() -> WiiLink:
	return _wii_link


## The active hardware model (RetroSystemModel). Lets peripherals/held-input drive
## model-side visuals (e.g. a handheld animating its own buttons from input).
func get_model() -> RetroSystemModel:
	return _model


## The Libretro node, so plugged-in peripherals can call input methods on it.
func get_libretro_node() -> Libretro:
	return _libretro


## True while anything on this machine wants the host microphone open.
##
## Not simply IsMicrophoneActive(), and the Famicom is why. fceumm opens no
## microphone at all: a Controller II's grille reaches the console as ONE BIT of
## player 2's pad, so there is no handle for the core to have open and a machine
## that asked only its core would never get the device switched on. A peripheral
## that measures the level itself counts too.
func hears_microphone() -> bool:
	var lib := get_libretro_node()
	if lib != null and lib.IsMicrophoneActive():
		return true
	return hears_microphone_level()


## True when a peripheral on one of this machine's ports wants the measured
## loudness rather than the samples.
func hears_microphone_level() -> bool:
	return not _microphone_level_listeners().is_empty()


## Hand one tick's measured level to each of them. (rms, peak), already scaled
## for this machine's distance from the player.
func push_microphone_level(level: Vector2) -> void:
	for node in _microphone_level_listeners():
		node.on_microphone_level(level)


## Silent while the machine is off or this is the netplay session's machine, for
## the same two reasons the C++ side answers silence: a stopped core has nothing
## to hear, and a microphone driving an input bit would desync a lockstep peer
## that cannot hear the same room.
func _microphone_level_listeners() -> Array:
	var out: Array = []
	if not is_powered_on:
		return out
	if NetworkManager.netplay_running() and NetworkManager.netplay_system() == self:
		return out
	for ctrl: Variant in _ports.controllers:
		var node := ctrl as Node
		if node != null and node.has_method("on_microphone_level"):
			out.append(node)
	return out


## Where this machine hears from, for the Microphone autoload's distance law: a
## seated microphone's stick, otherwise the machine.
func microphone_position() -> Vector3:
	if _memcards != null:
		for slot in _memcards.card_slot_count():
			var seated := _memcards.get_snapped_memcard(slot)
			if seated != null and seated.has_method("microphone_position"):
				return seated.microphone_position()
	# A microphone can be a controller-port device too: the N64's Voice
	# Recognition Unit goes in a socket and keeps its microphone on a cord, and
	# the Dreamcast's goes in a slot on the pad rather than into the console.
	for ctrl: Variant in _ports.controllers:
		var node := ctrl as Node
		if node == null:
			continue
		if node.has_method("microphone_position"):
			return node.microphone_position()
		if node.has_method("seated_microphone"):
			var seated: Node3D = node.seated_microphone()
			if seated != null:
				return seated.microphone_position()
	return global_position


# ── Controller ports and USB sockets ─────────────────────────────────────────
#
# Lifted out into SystemPorts, a child this node owns. What stays here is the
# surface other code calls BY NAME on the machine -- peripherals, WiiLink,
# netplay, ScenePersistence, the mods -- as one-line forwarders.

## The port component (SystemPorts): what is on each controller port and USB
## socket, and what the core is told. The suites and the machine's own helpers
## hold it rather than this node's forwarders.
func controller_ports() -> SystemPorts:
	return _ports


## Switch the input device type on a given controller port.
## device_id corresponds to RETRO_DEVICE_* constants (1 = joypad, 5 = analog, etc.).
func set_controller_port_device(port: int, device_id: int) -> void:
	_ports.set_device(port, device_id)


## The controllers on this machine's ports, one per port, null where empty.
## Read by VmuStorage, which has to walk them to find the seated VMUs. The same
## array, not a copy.
func get_port_controllers() -> Array:
	return _ports.controllers


## Re-announce the pak on one controller's port. Called when a pak is pushed into
## or pulled out of an expansion port, which the system cannot see for itself —
## the port belongs to the controller, two objects away.
func reapply_pak(ctrl: Node) -> void:
	_ports.reapply_pak(ctrl)


## Re-apply every port's pad-type option. Public because a pad can change its own
## mode while it stays plugged in: a DualShock toggled out of analogue mode is the
## same controller reporting a different pad_type_pref.
func reapply_pad_types() -> void:
	_ports.reapply_pad_types()


## Tell the core what is on cabinet port `i` again, now: a multitap's SELECT
## switch thrown with it plugged in changes what the port is.
func reannounce_port(i: int) -> void:
	_ports.reannounce_port(i)


## The id the RUNNING core understands for a peripheral -- see
## SystemPorts.core_device_id.
func core_device_id(device_type: int, lib_port: int,
		named: PackedStringArray = PackedStringArray()) -> int:
	return _ports.core_device_id(device_type, lib_port, named)


## The names a plugged peripheral goes by in a core's device list, or none -- see
## SystemPorts.device_names_of.
static func device_names_of(peripheral: Object) -> PackedStringArray:
	return SystemPorts.device_names_of(peripheral)


## Whether a core's device NAME reads as a light gun -- see
## SystemPorts.reads_as_lightgun.
static func reads_as_lightgun(device_name: String) -> bool:
	return SystemPorts.reads_as_lightgun(device_name)


## The node holding a given libretro port, or null. A read-only window onto the
## port table for components that need to see what is where — WiiLink searches it
## for a free remote slot.
func port_holder(port: int) -> Node:
	return _ports.port_holder(port)


## Every port's holder, port order, null where nothing is plugged in. A copy.
## Netplay decides which ports a frame must carry from it.
func port_holders() -> Array:
	return _ports.port_holders()


## The cabinet socket a plug went into, or null when it cannot be told yet. Asked
## to place a sound at the socket rather than at the plug -- see
## SystemPorts.port_socket.
func port_socket(plug: Node, port_index: int) -> Node3D:
	return _ports.port_socket(plug, port_index)


## The cabinet socket `plug` is seated in, or -1.
func cabinet_port_of_plug(plug: Node) -> int:
	return _ports.cabinet_port_of_plug(plug)


## Which cabinet socket holds this peripheral, or -1; a USB socket answers
## USB_SLOT_BASE + k. What a save records, never the libretro port.
func cabinet_port_of(peripheral: Node) -> int:
	return _ports.cabinet_port_of(peripheral)


## Attach a controller (by its cable plug) to an EXPANDED libretro port that has
## no cabinet snap zone — used by a multitap plugged into a native port to fan
## out to consecutive ports. `announce` false leaves the port's device as it is:
## a multitap at 5P owns its own port's device, the pad in its first socket only
## feeds it.
func attach_expanded_controller(port: int, plug: Node3D, announce := true) -> void:
	_ports.bind(port, plug, -1, announce)


## Detach a controller from an expanded port (see attach_expanded_controller;
## `announce` false leaves the port's device to the multitap that owns it).
func detach_expanded_controller(port: int, plug: Node3D, announce := true) -> void:
	_ports.unbind(port, plug, -1, announce)


## Release a controller port from replicated state -- see SystemPorts.net_release.
func net_release_controller_port(port_index: int) -> void:
	_ports.net_release(port_index)


# The names these had while they lived here, kept because the model packs'
# probes (RetroXR-models/mods/probes) call them by name.
func _accepts_plug(obj: Node3D) -> bool:
	return _ports.accepts_plug(obj)


func _accepts_usb_plug(obj: Node3D) -> bool:
	return _ports.accepts_usb_plug(obj)


func _reannounce_port_devices() -> void:
	_ports.reannounce_all()


# --- The second native slot (the DS's Slot-2) ---

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")


## Build the console's second slot, for the consoles Slot2Catalog says have one.
## A snap zone of its own rather than a second bay on the cartridge slot: the two
## take different media, face opposite edges and are gated separately.
func _build_slot2() -> void:
	if Slot2Catalog.media_of(systemid).is_empty():
		return
	_slot2 = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	_slot2.name = "Slot2"
	_slot2.snap_require = "cartridge"
	_slot2.snap_filter = _accepts_slot2_media
	_slot2.grab_distance = 0.03
	add_child(_slot2)
	_slot2.add_to_group(ExpansionPort.GROUP_CART_SLOT)
	_slot2.has_picked_up.connect(_on_slot2_inserted)
	_slot2.has_dropped.connect(_on_slot2_removed)
	_model.configure_slot2(_slot2)


## Slot-2 gate: the media the second slot takes, or an unlabelled cartridge,
## which is whatever machine it is put into. Deliberately NOT _MEDIA_COMPAT --
## the DS has no Game Boy support, so a Game Boy cartridge does not fit.
func _accepts_slot2_media(obj: Node3D) -> bool:
	if obj == null or obj is RetroExpansion or not ("systemid" in obj):
		return false
	var mid := str(obj.get("systemid"))
	return mid.is_empty() or mid == Slot2Catalog.media_of(systemid)


func _on_slot2_inserted(cartridge: Node3D) -> void:
	_slot2_cartridge = cartridge
	print("[RetroSystem] %s (%s): slot 2 game in: %s" % [name, systemid, cartridge.get("rom_path")])
	add_collision_exception_with(cartridge)
	if "systemid" in cartridge and str(cartridge.get("systemid")).is_empty():
		cartridge.set("systemid", Slot2Catalog.media_of(systemid))
	_model.play_cartridge_insert(cartridge, _slot2)
	_lend_cart_collision(cartridge, _slot2)
	NetworkManager.report_event(NetEvents.Event.EV_SLOT2_INSERT,
		{"sys": self, "cart": cartridge})


## Pulling the GBA cartridge does not switch a DS off: the game keeps running
## and simply no longer sees the pak, as it does on the hardware.
func _on_slot2_removed() -> void:
	if _slot2_cartridge != null:
		print("[RetroSystem] %s (%s): slot 2 game out: %s" % [name, systemid, _slot2_cartridge.get("rom_path")])
		_model.play_cartridge_eject(_slot2_cartridge, _slot2)
		remove_collision_exception_with(_slot2_cartridge)
		SeatedCollision.withdraw(self, _slot2_cartridge as CollisionObject3D)
		_slot2_cartridge = null
	NetworkManager.report_event(NetEvents.Event.EV_SLOT2_REMOVE, {"sys": self})


## A seated cartridge is frozen and collides with nothing, so the part of it
## standing out of the machine would go through a table: the machine carries it.
func _lend_cart_collision(cartridge: Node3D, zone: Node3D) -> void:
	if cartridge is CollisionObject3D:
		SeatedCollision.lend(self, cartridge as CollisionObject3D, zone)


func get_slot2_cartridge() -> Node3D:
	return _slot2_cartridge if is_instance_valid(_slot2_cartridge) else null


func slot2_media_path() -> String:
	var m := get_slot2_cartridge()
	if m == null or not m.has_method("get_rom_path"):
		return ""
	return str(m.call("get_rom_path"))


## Where the Slot-2 cartridge's battery is kept, or "" with nothing in it.
## Keyed off THAT cartridge's own path and save_id, as slot_b_save_path keys a
## Sufami Turbo's second cartridge: the save follows the GBA game between DS
## games rather than belonging to whichever DS card it was last read beside.
func slot2_save_path(core: String) -> String:
	var m := get_slot2_cartridge()
	if core.is_empty() or m == null or not ("save_id" in m):
		return ""
	var save_id := str(m.get("save_id"))
	var path := slot2_media_path()
	if save_id.is_empty() or path.is_empty():
		return ""
	return SramPaths.resolve_cart_save(
		SramPaths.media_systemid(m, Slot2Catalog.media_of(systemid)), core, path, save_id)


## Seat a Slot-2 cartridge after a save restore or from a remote peer.
func restore_slot2_cartridge(cartridge: Node3D) -> void:
	if _slot2 == null or cartridge == null:
		return
	_restoring_media = true
	_slot2.pick_up_object(cartridge)
	_restoring_media = false


## The counterpart, for a remote peer taking the cartridge out.
func net_release_slot2_cartridge() -> void:
	if _slot2 != null:
		_slot2.drop_object()


# --- Cartridge slot callbacks ---

## Does this object belong to this system, per one of the compatibility tables?
##
## An object that names no system is universal and always fits — RetroXR's own
## props (generic pad, keyboard, mouse, multitap, light gun) stand in for hardware
## we have no model of, so locking them to one system would strand every console
## that has no dedicated pad yet, and unlabelled legacy media keeps working.
##
## Anything that is not media or a plug at all falls through to true and is still
## filtered by the zone's own snap_require.
func _belongs_here(obj: Node3D, compat: Dictionary) -> bool:
	if not "systemid" in obj:
		return true
	var mid := str(obj.get("systemid"))
	if mid.is_empty():
		return true
	return mid == systemid or mid in compat.get(systemid, [])


## Slot gate: does this piece of media (cartridge/disc) belong in this system?
## The cartridge slot's snap filter, public for the spawner and the suites.
func accepts_media(obj: Node3D) -> bool:
	# A cartridge-shaped expansion goes in this slot and fills it, the way it does
	# on the hardware: a Mega Drive holds a 32X or a game, never both.
	var unit := obj as RetroExpansion
	if unit != null:
		return ExpansionCatalog.host_of(unit.expansion_id) == systemid \
			and ExpansionCatalog.mount_of(unit.expansion_id) == ExpansionCatalog.MOUNT_CARTRIDGE
	if _belongs_here(obj, _MEDIA_COMPAT):
		return true
	# An expansion with no bay of its own loads through THIS slot. A Satellaview
	# pack is a cartridge you push into the Super Famicom on top of it, so the
	# console has to take a systemid that is not its own -- see
	# ExpansionCatalog.host_slot_media for why it takes one whether or not the
	# base station is actually bolted on.
	if not ("systemid" in obj):
		return false
	return ExpansionCatalog.host_slot_media(systemid).has(str(obj.get("systemid")))


## What this console's controller ports take: its model's say, else its
## platform's (Connectors.controller_port_of) -- a Wii's take GameCube pads, a
## Genesis's anything with Atari's DE-9.
func controller_connector() -> String:
	var own := _model.get_controller_connector() if _model != null else ""
	return own if not own.is_empty() else Connectors.controller_port_of(systemid)


## Card gate: is this the family of card this console takes? Every card is in
## one "memory_card" group — the group is load-bearing in scene persistence, the
## netplay object sync and the card's own numbering — so the family is what
## separates them, the same way a plug's systemid separates controllers.
func accepts_card(obj: Node3D) -> bool:
	if obj == null or not ("family" in obj):
		return false
	return str(obj.get("family")) == card_family()


# The names the gates and the forced-option walk had while they were private,
# kept because the model packs' probes (RetroXR-models/mods/probes) call them.
func _accepts_media(obj: Node3D) -> bool:
	return accepts_media(obj)


func _accepts_card(obj: Node3D) -> bool:
	return accepts_card(obj)


func _all_forced_options(core: String) -> Dictionary:
	return all_forced_options(core)


## Returns the currently snapped cartridge, or null (used by save/load).
func get_snapped_cartridge() -> Node3D:
	return _snapped_cartridge


## The spin the seated disc is at, relative to the authored seat, in radians.
## Zero for a cartridge bay, an empty bay, or a disc seated as authored. Saved
## with the room and sent with the insert event so restore_cartridge can seat
## it the way it went in.
func cartridge_seat_yaw() -> float:
	return _disc_tray.seat_yaw()


## The media whose saves and achievements this machine's Game tab should show.
##
## The console's OWN slot first. With F-Zero X in the N64 and its Expansion Kit
## disk in the 64DD under it, the cartridge is the identity of the session --
## rom_path, the save file and the achievement set all key off it -- so it is the
## one to show, and the disk is a second piece of media for the same game.
##
## Otherwise whatever an attached unit is holding. A bare 64DD disk, a Mega-CD
## disc and a 32X cartridge are each the whole of the game on that machine, and
## the tab was hidden for all three: it asked only about the console's own slot,
## so a stack with its game one box further down looked like a console with
## nothing in it at all. Saves and achievements exist for those games exactly as
## they do for a cartridge, and there was no way to reach them.
##
## RetroDisc extends RetroCartridge, so one test covers a disc as well as a cart.
func game_media() -> RetroCartridge:
	if _snapped_cartridge is RetroCartridge:
		return _snapped_cartridge as RetroCartridge
	for unit in get_expansions():
		# Every bay, not the first: a Sufami Turbo with its second slot filled and
		# its first empty would otherwise report no game at all, and the machine
		# would offer neither saves nor achievements for something plainly in it.
		for s in unit.get_bay_count():
			var m := unit.get_media(s)
			if m is RetroCartridge:
				return m as RetroCartridge
	return null


## The systemid of the game this machine is about to run. A disc in a stacked
## unit's bay is a segacd game on a genesis machine, and it is the game that
## decides which BIOS is needed.
func _media_systemid() -> String:
	var media := game_media()
	var sid := str(media.get("systemid")) if media != null else ""
	if not sid.is_empty():
		return sid
	# Nothing inserted: an attached drive with an empty bay is still that drive's
	# machine, which boots its own BIOS and needs one.
	for unit in get_expansions():
		var unit_media := ExpansionCatalog.media_of(unit.expansion_id)
		if not unit_media.is_empty() and unit.get_bay_count() > 0:
			return unit_media
	return systemid


## Restore a cable→TV connection after loading from a save file. Safe to call
## before the lead has finished spawning -- see SystemVideoLead.restore_connection.
## `channel` picks the video-out cable (0 on classic single-cable systems);
## `tv_input` picks which of the set's four composite inputs to land in.
func restore_cable_connection(tv: RetroTV, channel: int = 0, tv_input: int = 0) -> void:
	_video_lead.restore_connection(tv, channel, tv_input)


## Restore a cartridge→slot insertion after loading from a save file. Slot/tray
## loaders seat the disc immediately through MediaSlot/MediaTray (no ride, filter
## bypassed); plain cartridge systems snap it through the zone as before.
## True only while a save is being reloaded into this machine. Restoring seats
## media and plugs through the SAME snap-zone calls a hand does, so anything that
## makes a NOISE on those events has to be able to tell the two apart — otherwise
## loading a room plays a cartridge insert for every console at once.
var _restoring_media: bool = false


## `yaw` is the spin a disc was seated at (cartridge_seat_yaw), from the save
## or from the peer whose hand put it in. A cartridge bay ignores it.
func restore_cartridge(cartridge: Node3D, yaw: float = 0.0) -> void:
	_restoring_media = true
	if not _disc_tray.restore_media(cartridge, yaw):
		_cartridge_slot.pick_up_object(cartridge)
		# A saved cart is one the machine could READ, so the tray it came out of was
		# pushed home. Pushed again inside the restore flag, so it lands latched with
		# neither the slide nor the sound.
		if has_push_tray_bay():
			_model.push_tray_down()
	_restoring_media = false


## The counterpart to restore_cartridge, for a remote peer taking the cart out.
##
## Releases the snap zone rather than running the local eject ride: the media is
## already gone on the peer that moved it, and object_sync positions it here.
## Which child holds the cartridge stays this machine's business.
func net_release_cartridge() -> void:
	_cartridge_slot.drop_object()


# ── A detachable media bay (arcade cabinets) ──────────────────────────────────
#
# An arcade cabinet's slot can be a bay's (ArcadeBayUnit) rather than its own: clipped into the
# cabinet's mount, or joined to it by a JAMMA lead. The cabinet stays the machine -- the core, the
# input, the picture, the saves -- and only two things follow the bay: WHERE the board stands (this
# machine's `_cartridge_slot` becomes the bay's snap zone) and WHICH system it plays (`systemid`
# becomes the bay's kind's). Taking the bay away gives the slot back to the cabinet's own (shut and
# empty) and the board goes with the bay, so the cabinet stops: pulling the board is pulling the game.

## The slot this machine was built with, kept while a bay's is in use.
var _home_slot: XRToolsSnapZone = null
var _bay: ArcadeBayUnit = null
var _bay_how := ""


## The bay this machine plays from, or null.
func get_bay() -> ArcadeBayUnit:
	return _bay if is_instance_valid(_bay) else null


## How the bay is joined (ArcadeBayUnit.DOCK / CABLE), "" with none.
func bay_link_kind() -> String:
	return _bay_how if get_bay() != null else ""


## Play from `bay`. Returns false when it cannot be taken. A machine holds one bay: a second takes
## the place of a docked one and is refused while a cabled one is in.
func link_bay(bay: ArcadeBayUnit, how: String) -> bool:
	if bay == null or not is_instance_valid(bay) or bay.slot == null:
		return false
	if _bay == bay:
		return true
	if get_bay() != null:
		if how == ArcadeBayUnit.CABLE:
			return false
		unlink_bay(null)
	var sid := bay.primary_system()
	if not sid.is_empty() and sid != systemid:
		# The machine is whatever the bay in it plays. A power-on has not happened yet (the old
		# bay's leaving stopped the machine), so nothing is running under the old name.
		systemid = sid
		if _model != null and _model.has_method("on_machine_system_changed"):
			_model.call("on_machine_system_changed")
	if _home_slot == null:
		_home_slot = _cartridge_slot
	_home_slot.enabled = false
	_bay = bay
	_bay_how = how
	_swap_cartridge_slot(bay.slot)
	bay.attach_host(self, how)
	if _model != null and _model.has_method("on_bay_linked"):
		_model.call("on_bay_linked", bay, how)
	return true


## Stop playing from the bay (`bay` null means whichever it is). The board stays in the bay.
func unlink_bay(bay: ArcadeBayUnit) -> void:
	var gone := get_bay()
	if gone == null:
		_bay = null
		return
	if bay != null and bay != gone:
		return
	_bay = null
	_bay_how = ""
	if _home_slot != null:
		_swap_cartridge_slot(_home_slot)
		_home_slot.enabled = false
	gone.detach_host()
	if _model != null and _model.has_method("on_bay_unlinked"):
		_model.call("on_bay_unlinked", gone)


## A saved cabinet's bay, clipped back into its mount (a cabled one is joined by its lead's restore).
func restore_bay(bay: ArcadeBayUnit) -> void:
	if bay == null or _model == null or not _model.has_method("restore_bay_mount"):
		return
	_restoring_media = true
	_model.call("restore_bay_mount", bay)
	_restoring_media = false


## Make `zone` this machine's cartridge slot. What is in the old one leaves with it (the machine
## hears it go, as a hand pulling it would), and what is already in the new one arrives (the machine
## hears that too: a snap zone says nothing about a board that was there before it was listened to).
func _swap_cartridge_slot(zone: XRToolsSnapZone) -> void:
	if zone == null or zone == _cartridge_slot:
		return
	if _snapped_cartridge != null:
		_on_cartridge_removed()
	var old := _cartridge_slot
	if is_instance_valid(old):
		if old.has_picked_up.is_connected(_on_cartridge_inserted):
			old.has_picked_up.disconnect(_on_cartridge_inserted)
		if old.has_dropped.is_connected(_on_cartridge_removed):
			old.has_dropped.disconnect(_on_cartridge_removed)
	_cartridge_slot = zone
	zone.has_picked_up.connect(_on_cartridge_inserted)
	zone.has_dropped.connect(_on_cartridge_removed)
	zone.snap_filter = _accepts_media
	if not zone.is_in_group(ExpansionPort.GROUP_CART_SLOT):
		zone.add_to_group(ExpansionPort.GROUP_CART_SLOT)
	var held := zone.picked_up_object as Node3D
	if held != null:
		_on_cartridge_inserted(held)


## The same, for a memory card. `slot` is an index into MEMCARD_SLOT_NODES and
## is clamped by the caller, so a console with one well still answers an event
## from a peer that has two.
##
## Exists so the relay does not have to reach in by node name. It was the one
## eject that had no method, which meant object_sync walked this machine's
## children looking for a snap zone — the sort of thing that keeps working right
## up until a console arranges its slots differently.
func net_release_memory_card(slot: int) -> void:
	if slot < 0 or slot >= _memcard_slots.size():
		return
	_memcard_slots[slot].drop_object()


## Restore a controller plug into a port after loading from a save file.
## Node3D rather than ControllerPlug: a socket takes anything in the
## "controller_plug" group, and several things in it are not that class — a VMU,
## an N64 pak, the GameCube-to-GBA lead's console end.
func restore_controller_plug(port_index: int, plug: Node3D) -> void:
	if port_index >= USB_SLOT_BASE:
		var k := port_index - USB_SLOT_BASE
		var usb_zones := _ports.usb_zones
		if k < usb_zones.size() and not is_instance_valid(usb_zones[k].picked_up_object):
			_restoring_media = true
			usb_zones[k].pick_up_object(plug)
			_restoring_media = false
		else:
			print("[RetroSystem] %s: saved plug for USB socket %d not restored (%s)" % [systemid, k,
				"no such socket" if k >= usb_zones.size() else "socket taken"])
		return
	var port_zones := _ports.zones
	if port_index < 0 or port_index >= port_zones.size():
		print("[RetroSystem] %s: saved plug for port %d not restored: no such socket"
			% [systemid, port_index])
		return
	# Never evict. XRToolsSnapZone.pick_up_object drops whatever a zone is already
	# holding, so two peripherals naming the same slot would restore as one plugged
	# in and one lying on the floor — and the loser is decided by file order. That
	# is exactly what a save written before cabinet_port_of() existed says, since a
	# computer mouse recorded libretro port 0 rather than its socket, so those files
	# have to land somewhere sensible rather than unplug the keyboard.
	_restoring_media = true
	if is_instance_valid(port_zones[port_index].picked_up_object):
		for i in port_zones.size():
			if port_zones[i].enabled and not is_instance_valid(port_zones[i].picked_up_object):
				port_zones[i].pick_up_object(plug)
				_restoring_media = false
				return
		_restoring_media = false
		return
	port_zones[port_index].pick_up_object(plug)
	_restoring_media = false


## True when this cabinet's bay only connects on a push, so a cart lying in it knows
## a click means "push me home" rather than "take me out".
func has_push_tray_bay() -> bool:
	return _model != null and _model.has_push_tray()


## Is this cabinet's tray pushed home? False for every bay that has no tray.
func is_tray_down() -> bool:
	return has_push_tray_bay() and _model.is_tray_down()


## Push the cart home, or lift it back out. Both the desktop click and the VR hand
## end up here.
func toggle_cart_tray() -> void:
	if not has_push_tray_bay():
		return
	if _model.is_tray_down():
		_model.lift_tray()
	else:
		_model.push_tray_down()


## A bay whose cart only connects when it is pushed home (the NES ZIF cradle).
## The zone catching a cart means the cart is LYING in the tray, nothing more, so
## the emulation-side pair is fired by the tray instead — the same swap MediaSlot
## and MediaTray make for disc loaders.
func _wire_push_tray() -> void:
	if not _model.has_push_tray():
		return
	if _cartridge_slot.has_picked_up.is_connected(_on_cartridge_inserted):
		_cartridge_slot.has_picked_up.disconnect(_on_cartridge_inserted)
	if _cartridge_slot.has_dropped.is_connected(_on_cartridge_removed):
		_cartridge_slot.has_dropped.disconnect(_on_cartridge_removed)
	_cartridge_slot.has_picked_up.connect(_on_cart_laid_in_tray)
	_cartridge_slot.has_dropped.connect(_on_cart_taken_from_tray)
	_model.cart_tray_changed.connect(_on_cart_tray_changed)


## Cart is in the tray. It slides home visually here; the machine still cannot read
## it. A tray left down by a cart pulled out of it takes the next one straight away,
## because nothing more is going to be pushed.
func _on_cart_laid_in_tray(cartridge: Node3D) -> void:
	_tray_cartridge = cartridge
	_model.play_cartridge_insert(cartridge, _cartridge_slot)
	if _model.is_tray_down():
		_on_cartridge_inserted(cartridge)


## Cart has left the tray for good.
func _on_cart_taken_from_tray() -> void:
	_tray_cartridge = null
	if _snapped_cartridge != null:
		_on_cartridge_removed()
	else:
		_model.play_cartridge_eject(null, _cartridge_slot)


## The tray was pushed home, or sprung back up.
func _on_cart_tray_changed(down: bool) -> void:
	if down:
		if is_instance_valid(_tray_cartridge):
			_on_cartridge_inserted(_tray_cartridge)
	elif _snapped_cartridge != null:
		_on_cartridge_removed()


func _on_cartridge_inserted(cartridge: Node3D) -> void:
	# An expansion in the cartridge slot is a machine being bolted on, not media
	# being loaded: it has no ROM of its own, and what it runs goes into a slot
	# of its own further up the stack.
	var unit := cartridge as RetroExpansion
	if unit != null:
		add_collision_exception_with(unit)
		unit.bind_to_host(self)
		return

	_snapped_cartridge = cartridge
	# Prevent the frozen kinematic cartridge from physically pushing the system body.
	# Slot/tray loaders let their MediaSlot/MediaTray own the exception (held until
	# the disc is grabbed clear), so only plain cartridge decks add one here.
	if not _disc_tray.has_loader_bay():
		add_collision_exception_with(cartridge)
	if cartridge.has_method("get_rom_path"):
		rom_path = cartridge.get_rom_path()
		_disc_tray.left_running = false
	# Back-fill the cartridge's systemid (save-recovery list needs it to
	# resolve the core) — a cart inserted into an NES is an NES cart.
	if "systemid" in cartridge and str(cartridge.get("systemid")).is_empty():
		cartridge.set("systemid", systemid)
	# A cabinet dresses itself in the game's art (marquee, sides).
	if _model != null and _model.has_method("on_media_inserted"):
		_model.call("on_media_inserted", cartridge)
	request_attract_media()
	# With a game in, the button of a cabinet that attracts becomes its switch; a restored room's cabinet
	# that was left on comes on now.
	_update_power_button_visual()
	_try_attract_restore()
	# A push-tray bay already slid the cart home when it was laid in — this moment
	# is the tray latching, which moves nothing.
	if not _model.has_push_tray():
		_model.play_cartridge_insert(cartridge, _cartridge_slot)
	# After the model has had its say: a handheld cuts a seated cartridge's box
	# down to the stub that shows, and the stub is what there is to lend.
	if not _disc_tray.has_loader_bay():
		_lend_cart_collision(cartridge, _cartridge_slot)
	# (Slot/tray loaders already seated the disc and set its grabbability through
	# MediaSlot/MediaTray — the disc's enabled state follows the lid there.)
	# Hot swap: a powered disc console with its virtual tray open takes the new
	# disc without a reboot (multi-disc games — FF7 "insert disc 2").
	_disc_tray.hot_swap_in()
	print("[RetroSystem] %s (%s): game in: %s" % [name, systemid, rom_path])
	NetworkManager.report_event(NetEvents.Event.EV_CART_INSERT,
		{"sys": self, "cart": cartridge, "yaw": cartridge_seat_yaw()})


func _on_cartridge_removed() -> void:
	# The slot says it is empty, not what left it. If what left was a bolted-on
	# expansion, that is the join coming apart.
	for held in get_expansions():
		if ExpansionCatalog.mount_of(held.expansion_id) == ExpansionCatalog.MOUNT_CARTRIDGE:
			remove_collision_exception_with(held)
			held.unbind_from_host()
			return

	if _snapped_cartridge:
		print("[RetroSystem] %s (%s): game out: %s" % [name, systemid, rom_path])
		# On a push-tray bay this fires when the tray is LIFTED, with the cart still
		# lying in it — the eject belongs to the cart actually leaving, which
		# _on_cart_taken_from_tray plays.
		if not _model.has_push_tray():
			_model.play_cartridge_eject(_snapped_cartridge, _cartridge_slot)
		# Slot/tray loaders let MediaSlot/MediaTray manage (and hold) the collision
		# exception until the disc is grabbed clear — don't drop it here.
		if not _disc_tray.has_loader_bay():
			remove_collision_exception_with(_snapped_cartridge)
			SeatedCollision.withdraw(self, _snapped_cartridge as CollisionObject3D)
		_snapped_cartridge = null
		if _model != null and _model.has_method("on_media_cleared"):
			_model.call("on_media_cleared")
	_disc_tray.spin = 0.0
	# Taking the media out never interrupts the run. A console does not stop when
	# a disc leaves the drive — that is what lets Monster Rancher read whatever
	# CD you hand it, and what keeps a multi-disc game alive between discs — and a
	# floppy machine behaves the same way. Only a cartridge deck powers off, where
	# pulling the cart really does take the program away.
	if is_powered_on and _disc_tray.media_survives_removal():
		_disc_tray.media_left_running()
		NetworkManager.report_event(NetEvents.Event.EV_CART_REMOVE, {"sys": self})
		return
	if is_powered_on or attracting:
		power_off()
	rom_path = ""
	_update_power_button_visual()
	NetworkManager.report_event(NetEvents.Event.EV_CART_REMOVE, {"sys": self})


## Disc ops, as SystemTray.request_disk_op takes them. NONE is not an op — it is
## the answer SystemTray.tray_op_for gives when the core needs to hear nothing at
## all.
const DISK_OP_NONE := -1
const DISK_OP_EJECT := 0
const DISK_OP_CLOSE := 1
## An e-Reader card, scanned; see NetplaySession.DISK_OP_CARD.
const DISK_OP_CARD := 2


# ── Disc loader (tray lid / slot loading) ────────────────────────────────────
#
# Lifted out into SystemTray, a child this node owns. What stays here is what
# models, netplay and the menu call BY NAME on the machine.

## The disc drive component (SystemTray): its loader, its lid, the spinning disc
## and the core's disk-control mirror.
func disc_tray() -> SystemTray:
	return _disc_tray


## A model's own hand-driven lid (e.g. the PSone's VRHinge) reporting the state
## the player physically put it in. Idempotent, so a drag can report freely.
func request_tray_state(open: bool) -> void:
	_disc_tray.request_state(open)


## A lid mechanism reporting its own state. Public because a bespoke model owns
## its hinge and reports through here rather than growing a second copy of the
## rule (see playstation_model._on_lid_swung).
func lid_reports_open(open: bool, mechanism: Node) -> void:
	_disc_tray.lid_reports_open(open, mechanism)


## Netplay: another player toggled this console's tray.
func net_set_tray_open(open: bool) -> void:
	_disc_tray.net_set_open(open)


## The OPEN/EJECT button, pressed from the menu.
func press_eject() -> void:
	_disc_tray.press_eject()


# The name the button's handler had while it lived here, kept because the model
# packs' probes (RetroXR-models/mods/probes) press it by name.
func _on_eject_pressed() -> void:
	_disc_tray.on_eject_pressed()


# --- Achievements, toasts and content naming ---
#
# Sat inside the memory-card block by accident of position rather than of
# subject, and came back when that block moved out.

var _net_no_content_override := false


## Ask to track achievements for the game about to start. Silent on refusal —
## another cabinet holding the session, or a system RetroAchievements has no
## console for, is an ordinary outcome and not worth a message.
func _claim_achievements_session() -> void:
	if not RA.claim_session(self, resolve_systemid(), _libretro):
		return
	if not RA.achievement_unlocked.is_connected(_on_achievement_unlocked):
		RA.achievement_unlocked.connect(_on_achievement_unlocked)


func _on_achievement_unlocked(_id: int, title: String, description: String,
							  points: int, badge: Texture2D) -> void:
	# The signal is global, so a cabinet that lost the session to another machine
	# must not raise a toast for its unlocks.
	if RA.session_owner() != self:
		return
	var toast := _screen_toast()
	if toast == null:
		return
	toast.show_unlock(title, description, points, badge)


## The notification card over this machine's picture, made on demand.
##
## Rebuilt when the picture has moved — plugging a video-out cable into a TV
## changes _screen_target(), and a cached card is parented to the old one.
## Null when the machine has no screen at all: a console with no TV connected.
func _screen_toast() -> AchievementToast:
	var anchor := _screen_target()
	if anchor == null:
		return null
	if is_instance_valid(_screen_toast_card) and _screen_toast_card.anchor() != anchor:
		_screen_toast_card.queue_free()
		_screen_toast_card = null
	if not is_instance_valid(_screen_toast_card):
		_screen_toast_card = AchievementToast.attach(anchor)
	return _screen_toast_card if is_instance_valid(_screen_toast_card) else null


## The notification card over the hardware itself, made on demand.
##
## For what the machine is waiting on rather than what it is showing. An empty
## slot is a state of the console, and the player who just pressed its power
## button is standing at it; a console cabled to a set across the room puts its
## picture where they are not, and a handheld's own panel is dark until a game
## runs. Never null: unlike the picture, the machine is always there.
func _machine_toast() -> AchievementToast:
	if not is_instance_valid(_machine_toast_card):
		_machine_toast_card = AchievementToast.attach_to_machine(self)
	return _machine_toast_card if is_instance_valid(_machine_toast_card) else null


## What is loaded, for a label or a save name — the cartridge's title, else the
## ROM's. Read by the memory-card controller when naming a backup.
func content_label() -> String:
	if _snapped_cartridge and "game_label" in _snapped_cartridge:
		var lbl := str(_snapped_cartridge.get("game_label"))
		if not lbl.is_empty():
			return lbl
	return rom_path.get_file().get_basename()


## Which platform this machine is currently being: a cartridge's own systemid
## when one is seated, else the machine's. The controllers this node owns ask
## for it when naming a save.
func resolve_systemid() -> String:
	if _snapped_cartridge and "systemid" in _snapped_cartridge:
		var sid := str(_snapped_cartridge.get("systemid"))
		if not sid.is_empty():
			return sid
	return systemid


# --- Memory cards ---
#
# The work lives in MemoryCardController, a child this node owns. What stays
# here is the surface other code already talks to by name: ScenePersistence and
# CardSaveOps ask this node for its seated cards, NetplaySession asks it for its
# SRAM, and the snap zones were wired to it in _ready.

## The memory-card bays, in slot order. A read-only window for the controller
## this node owns; the zones themselves stay this node's to wire.
func memcard_slots() -> Array[XRToolsSnapZone]:
	return _memcard_slots


var _memcards: MemoryCardController = null

## The Dreamcast's VMUs. Inert on every other console -- see VmuStorage.
var _vmu: VmuStorage = null
## A Sega CD's backup memory and a Backup RAM Cartridge. Inert on every other
## machine -- see SegaCdStorage.
var _sega_cd: SegaCdStorage = null
## A Saturn's Backup RAM Cartridge, and the options Beetle Saturn keeps its
## memories by. Inert on every other machine -- see SaturnStorage.
var _saturn: SaturnStorage = null
## A 3DO's NVRAM, staged into the file Opera keeps it in. Inert on every other
## machine -- see ThreeDoStorage.
var _three_do: ThreeDoStorage = null
## One Xbox at a time, and its game's saves lifted off the shared hard disk for
## RomM once it stops. Inert on every other machine -- see XboxStorage.
var _xbox: XboxStorage = null
## The memory built into the console, on one with any -- see ConsoleMemory.
var _console_memory: ConsoleMemory = null
## All five storages, in lifecycle order -- see ConsoleStorage and _init.
var _storages: Array[ConsoleStorage] = []
## What a stacked expansion hands the core at boot - see ExpansionLaunch.
var _expansion_launch: ExpansionLaunch = null


## The expansion-launch component, for the suites and probes that ask what a
## stack would boot (expansion_roms, missing_firmware, host_media_path).
func expansion_launch() -> ExpansionLaunch:
	return _expansion_launch


## The card slots' controller, for a caller whose business is only cards
## (ScenePersistence). The forwarders below stay for the tests, probes and mods
## that call them on the machine by name.
func memcards() -> MemoryCardController:
	return _memcards


## The MemoryCard seated in `slot`, or null.
func get_snapped_memcard(slot := 0) -> Node3D:
	return _memcards.get_snapped_memcard(slot)


## How many card slots this machine actually has.
## Re-resolve one slot (or all, with -1) and re-point a running core at it.
func refresh_memcard_path(slot := -1) -> void:
	_memcards.refresh_memcard_path(slot)


## Restore a card into its slot from a save. Called by ScenePersistence.
func restore_memory_card(card: Node3D, slot: int) -> void:
	_memcards.restore_memory_card(card, slot)


## Netplay: override the SRAM source for the next net_start_core. path "" turns
## local persistence off; data is injected so every peer boots identical.
func net_set_sram(path: String, data: PackedByteArray) -> void:
	_memcards.net_set_sram(path, data)


## Host: the current .srm bytes for the seated content, for the cold-start
## payload. Empty when no file exists yet.
func net_sram_file_bytes() -> PackedByteArray:
	return _memcards.net_sram_file_bytes()


## Which card family this machine takes, and how many slots — read by the
## power-on option path and by the snap filter.
func card_family() -> String:
	return _memcards.card_family()


func card_slot_count() -> int:
	return _memcards.card_slot_count()


# ---------------------------------------------------------------------------
# Save states
#
# The work lives in SaveStateController, a child this node owns. What stays here
# is the surface other code already talks to: CartridgeOptionsPanel connects
# these signals by name on the system node and calls the three methods below on
# it, so the seam is behind them rather than in front.
# ---------------------------------------------------------------------------

## ok is false with a sentence in `reason` the panel can show as-is.
@warning_ignore("unused_signal")
signal state_captured(state_id: String, ok: bool, reason: String)
@warning_ignore("unused_signal")
signal state_loaded(state_id: String, ok: bool, reason: String)

var _save_state: SaveStateController = null


## The save-state controller, for a caller whose business is only states
## (CartridgeOptionsPanel). The signals above stay on the machine, and so do the
## three forwarders below: tests and probes call them on it by name.
func save_states() -> SaveStateController:
	return _save_state


## Can this machine take a state right now? {ok, reason} — reason is empty when
## ok, and a sentence to put on a disabled button when not.
func capture_gate() -> Dictionary:
	return _save_state.capture_gate()


## Take a state. `into_id` empty mints a new one; a real id overwrites that state
## in place. Answers exactly once through state_captured, always.
func capture_state(into_id := "") -> void:
	_save_state.capture_state(into_id)


## Restore a state. A machine that is off is switched on first, so one press does
## what was meant. Answers exactly once through state_loaded, always.
func load_state(state_id: String) -> void:
	_save_state.load_state(state_id)
